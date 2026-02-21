--[[
  OGRH_AdminSelection.lua
  Admin selection UI and polling system for OG-RaidHelper
  
  Manages the admin selection process, version polling, and permission wrappers.
  Note: Core permission logic lives in OGRH_Permissions.lua
]]--

-- Raid Admin state (legacy name kept for backward compatibility)
OGRH.RaidLead = {
  currentLead = nil,           -- DEPRECATED: Use OGRH.GetRaidAdmin() instead (legacy field only)
  addonUsers = {},             -- List of raid members running the addon {name, rank}
  lastPollTime = 0,            -- Timestamp of last poll
  pollResponses = {},          -- Responses to current poll
  pollInProgress = false       -- Whether a poll is active
}

--[[
    Admin Discovery System
    
    Query-based admin discovery with 5-second delays.
    Handles raid forming, joining, and late joining uniformly.
    
    Flow:
      1. Wait 5 seconds (passive listen for STATE.CHANGE_LEAD from existing admin)
      2. Broadcast ADMIN.QUERY (all OGRH clients respond with roll-call)
         - The querying player does NOT add itself — it doesn't know who admin is
      3. Wait 5 seconds to collect responses from other OGRH clients
      4. Resolve:
         - If any responder claimed isCurrentAdmin → accept them as admin
         - If responders exist but none claimed admin → do nothing (manual selection needed)
         - If NO responders (sole OGRH user) → self-assign with tier logic:
           Tier 1: Self is lastAdmin (persisted) → restore
           Tier 2: Self is Raid Leader → assign
           Tier 3: Self is Assistant → assign
           Tier 4: Self has no rank → temp admin (no lastAdmin update)
]]
OGRH.AdminDiscovery = {
    active = false,              -- Whether discovery is in progress
    responses = {},              -- Collected ADMIN.RESPONSE roll-call entries
    queryTimer = nil,            -- Timer ID for initial 5-second passive listen
    resolveTimer = nil,          -- Timer ID for post-query 5-second collection
    lastAdminRank = nil          -- Tracked rank of current admin (for demotion detection)
}

-- Start admin discovery process
function OGRH.AdminDiscovery.Start()
    -- Guard: if already running, don't restart
    if OGRH.AdminDiscovery.active then
        if OGRH.SyncIntegrity and OGRH.SyncIntegrity.State and OGRH.SyncIntegrity.State.debug then
            OGRH.Msg("|cff888888[RH-AdminDiscovery][DEBUG]|r Discovery already in progress, skipping")
        end
        return
    end
    
    -- Cancel any stale timers (defensive)
    OGRH.AdminDiscovery.Cancel()
    
    OGRH.AdminDiscovery.active = true
    OGRH.AdminDiscovery.responses = {}
    
    if OGRH.SyncIntegrity and OGRH.SyncIntegrity.State and OGRH.SyncIntegrity.State.debug then
        OGRH.Msg("|cff00ccff[RH-AdminDiscovery][DEBUG]|r Starting admin discovery (5s passive listen)")
    end
    
    -- Phase 1: Wait 5 seconds passively
    -- During this time, an existing admin may broadcast STATE.CHANGE_LEAD
    -- which SetRaidAdmin will handle, setting currentAdmin before we query.
    OGRH.AdminDiscovery.queryTimer = OGRH.ScheduleTimer(function()
        -- Abandoned? (left raid during wait)
        if GetNumRaidMembers() == 0 then
            OGRH.AdminDiscovery.Cancel()
            return
        end
        
        -- If admin was set during passive listen (received STATE.CHANGE_LEAD), done
        if OGRH.GetRaidAdmin and OGRH.GetRaidAdmin() then
            if OGRH.SyncIntegrity and OGRH.SyncIntegrity.State and OGRH.SyncIntegrity.State.debug then
                OGRH.Msg("|cff00ccff[RH-AdminDiscovery][DEBUG]|r Admin found during passive listen: " .. tostring(OGRH.GetRaidAdmin()))
            end
            OGRH.AdminDiscovery.active = false
            return
        end
        
        -- Phase 2: Broadcast ADMIN.QUERY (all OGRH clients respond)
        if OGRH.SyncIntegrity and OGRH.SyncIntegrity.State and OGRH.SyncIntegrity.State.debug then
            OGRH.Msg("|cff00ccff[RH-AdminDiscovery][DEBUG]|r Broadcasting ADMIN.QUERY for roll call")
        end
        
        -- NOTE: Do NOT add self to responses. The joining/reloading player doesn't
        -- know who admin is, so their vote should not count. Only responses from
        -- OTHER OGRH clients matter. If no one else responds, we fall back to
        -- self-assignment in Resolve().
        
        -- Broadcast query - all OGRH clients will respond via ADMIN.RESPONSE
        if OGRH.MessageRouter and OGRH.MessageTypes then
            OGRH.MessageRouter.Broadcast(OGRH.MessageTypes.ADMIN.QUERY, "", {priority = "HIGH"})
        end
        
        -- Phase 3: Wait 5 more seconds for responses, then resolve
        OGRH.AdminDiscovery.resolveTimer = OGRH.ScheduleTimer(function()
            OGRH.AdminDiscovery.Resolve()
        end, 5.0)
    end, 5.0)
end

-- Cancel an in-progress discovery (e.g., on raid leave)
function OGRH.AdminDiscovery.Cancel()
    OGRH.AdminDiscovery.active = false
    OGRH.AdminDiscovery.responses = {}
    if OGRH.AdminDiscovery.queryTimer then
        OGRH.CancelTimer(OGRH.AdminDiscovery.queryTimer)
        OGRH.AdminDiscovery.queryTimer = nil
    end
    if OGRH.AdminDiscovery.resolveTimer then
        OGRH.CancelTimer(OGRH.AdminDiscovery.resolveTimer)
        OGRH.AdminDiscovery.resolveTimer = nil
    end
end

-- Add a roll-call response (called from ADMIN.RESPONSE handler)
function OGRH.AdminDiscovery.AddResponse(playerName, rank, isCurrentAdmin, knownAdmin)
    if not OGRH.AdminDiscovery.active then return end
    
    -- Deduplicate
    for i = 1, table.getn(OGRH.AdminDiscovery.responses) do
        if OGRH.AdminDiscovery.responses[i].name == playerName then
            return
        end
    end
    table.insert(OGRH.AdminDiscovery.responses, {
        name = playerName,
        rank = rank,
        isCurrentAdmin = isCurrentAdmin,
        knownAdmin = knownAdmin  -- Who this responder believes is admin
    })
    
    if OGRH.SyncIntegrity and OGRH.SyncIntegrity.State and OGRH.SyncIntegrity.State.debug then
        OGRH.Msg(string.format("|cff00ccff[RH-AdminDiscovery][DEBUG]|r Response: %s (rank=%d, isAdmin=%s, knownAdmin=%s)", 
            playerName, rank, tostring(isCurrentAdmin), tostring(knownAdmin or "nil")))
    end
end

-- Resolve admin from collected responses
-- Tier 1-4 fallback only runs when NO other OGRH users responded (sole user).
-- If other users responded but none claimed admin, admin stays unset.
function OGRH.AdminDiscovery.Resolve()
    OGRH.AdminDiscovery.active = false
    
    -- If admin was set during collection period (e.g., someone claimed admin), done
    if OGRH.GetRaidAdmin and OGRH.GetRaidAdmin() then
        return
    end
    
    -- Left raid?
    if GetNumRaidMembers() == 0 then
        return
    end
    
    local responses = OGRH.AdminDiscovery.responses
    
    if OGRH.SyncIntegrity and OGRH.SyncIntegrity.State and OGRH.SyncIntegrity.State.debug then
        OGRH.Msg(string.format("|cff00ccff[RH-AdminDiscovery][DEBUG]|r Resolving with %d responses", table.getn(responses)))
    end
    
    -- If other OGRH users responded to the query
    if table.getn(responses) > 0 then
        -- Check if any response claimed to be admin
        for i = 1, table.getn(responses) do
            if responses[i].isCurrentAdmin then
                OGRH.SetRaidAdmin(responses[i].name, true)  -- suppress broadcast
                return
            end
        end
        -- Check if any responder knows who admin is (e.g., admin reloaded,
        -- other clients still know who was admin)
        for i = 1, table.getn(responses) do
            if responses[i].knownAdmin and responses[i].knownAdmin ~= "" then
                OGRH.SetRaidAdmin(responses[i].knownAdmin, true)  -- suppress broadcast
                OGRH.Msg("|cff00ccff[RH]|r Restored admin " .. responses[i].knownAdmin .. " (reported by " .. responses[i].name .. ")")
                return
            end
        end
        -- Other OGRH users exist but nobody knows who admin is.
        -- Admin must be set manually — do not auto-assign.
        OGRH.Msg("|cff00ccff[RH]|r No admin found in raid. Use the Admin button to designate one.")
        return
    end
    
    -- ================================================================
    -- NO responses from other OGRH users — we are the sole addon user.
    -- Fall back to self-assignment using tier logic.
    -- ================================================================
    local selfName = UnitName("player")
    local selfRank = 0
    for i = 1, GetNumRaidMembers() do
        local name, rank = GetRaidRosterInfo(i)
        if name == selfName then
            selfRank = rank
            break
        end
    end
    
    -- NOTE: All self-assignments use suppressBroadcast=true.
    -- If we truly are the sole OGRH user, there's no one to broadcast to.
    -- If we're wrong (responses were just delayed by network congestion),
    -- broadcasting STATE.CHANGE_LEAD would override the real admin on other clients.
    -- Late-arriving ADMIN.RESPONSE with isCurrentAdmin=true will still correct us.
    
    -- Tier 1: Check if we are the lastAdmin (persisted)
    local lastAdmin = OGRH.GetLastAdmin and OGRH.GetLastAdmin()
    if lastAdmin and lastAdmin == selfName then
        OGRH.SetRaidAdmin(selfName, true)
        OGRH.Msg("|cff00ccff[RH]|r Restored as admin (last admin, sole OGRH user)")
        return
    end
    
    -- Tier 2: Raid Leader
    if selfRank == 2 then
        OGRH.SetRaidAdmin(selfName, true)
        OGRH.Msg("|cff00ccff[RH]|r Assigned self as admin (raid leader, sole OGRH user)")
        return
    end
    
    -- Tier 3: Assistant
    if selfRank == 1 then
        OGRH.SetRaidAdmin(selfName, true)
        OGRH.Msg("|cff00ccff[RH]|r Assigned self as admin (assistant, sole OGRH user)")
        return
    end
    
    -- Tier 4: No rank, sole OGRH user — temp admin (no lastAdmin update)
    OGRH.SetRaidAdmin(selfName, true, true)  -- suppressBroadcast + skipLastAdminUpdate
    OGRH.Msg("|cff00ccff[RH]|r Temporarily assigned self as admin (sole OGRH user, no L/A)")
end

-- Check if local player can edit (is raid admin, or not in raid)
function OGRH.CanEdit()
  -- If not in a raid, allow editing
  if GetNumRaidMembers() == 0 then
    return true
  end
  
  -- If in a raid, must be the designated raid admin
  return OGRH.IsRaidAdmin(UnitName("player"))
end

-- Check if local player can navigate encounters (change Main UI selection)
-- Check if local player can manage roles (is raid admin, L, or A)
function OGRH.CanManageRoles()
  -- If not in a raid, allow role management
  if GetNumRaidMembers() == 0 then
    return true
  end
  
  -- Check if player is the designated raid admin
  if OGRH.IsRaidAdmin(UnitName("player")) then
    return true
  end
  
  -- Check if player is raid leader or assistant
  local playerName = UnitName("player")
  for i = 1, GetNumRaidMembers() do
    local name, rank = GetRaidRosterInfo(i)
    if name == playerName then
      if rank == 2 or rank == 1 then  -- 2 = Leader, 1 = Assistant
        return true
      end
      break
    end
  end
  
  return false
 end

function OGRH.CanNavigateEncounter(playerName)
  -- Default to local player if not specified
  if not playerName then
    playerName = UnitName("player")
  end
  
  -- If not in a raid, allow navigation
  if GetNumRaidMembers() == 0 then
    return true
  end
  
  -- Check if player is the designated raid admin
  if OGRH.IsRaidAdmin(playerName) then
    return true
  end
  
  -- Hardcoded exceptions for specific players
  if playerName == "Tankmedady" or playerName == "Gnuzmas" then
    return true
  end
  
  for i = 1, GetNumRaidMembers() do
    local name, rank = GetRaidRosterInfo(i)
    if name == playerName then
      -- rank 2 = leader, rank 1 = assistant
      if rank == 2 or rank == 1 then
        return true
      end
      break
    end
  end
  
  return false
end


-- Poll for addon users in raid
function OGRH.PollAddonUsers()
  if GetNumRaidMembers() == 0 then
    OGRH.Msg("You must be in a raid to poll for addon users.")
    return
  end
  
  -- Check if local player is raid leader or assistant
  local playerName = UnitName("player")
  local hasPermission = false
  for i = 1, GetNumRaidMembers() do
    local name, rank = GetRaidRosterInfo(i)
    if name == playerName and (rank == 2 or rank == 1) then
      hasPermission = true
      break
    end
  end
  
  if not hasPermission then
    OGRH.Msg("Only raid leaders or assistants can select a raid admin.")
    return
  end
  
  -- Reset poll state
  OGRH.RaidLead.pollResponses = {}
  OGRH.RaidLead.readHelperResponses = {}
  OGRH.RaidLead.pollInProgress = true
  OGRH.RaidLead.lastPollTime = GetTime()
  
  -- Send poll request via MessageRouter (empty string, not empty table)
  OGRH.MessageRouter.Broadcast(OGRH.MessageTypes.ADMIN.POLL_VERSION, "")
  
  -- Add self to responses
  local selfName = UnitName("player")
  local selfRank = "None"
  for i = 1, GetNumRaidMembers() do
    local name, rank = GetRaidRosterInfo(i)
    if name == selfName then
      if rank == 2 then
        selfRank = "Leader"
      elseif rank == 1 then
        selfRank = "Assistant"
      end
      break
    end
  end
  
  -- Calculate checksum for ALL structure data
  local checksum = "0"
  if OGRH.Sync and OGRH.Sync.GetCurrentChecksum then
    checksum = OGRH.Sync.GetCurrentChecksum()
  end
  
  table.insert(OGRH.RaidLead.pollResponses, {
    name = selfName,
    rank = selfRank,
    version = OGRH.VERSION or "Unknown",
    tocVersion = OGRH.TOC_VERSION or OGRH.VERSION or "Unknown",
    checksum = checksum
  })
  
  -- Show UI immediately
  OGRH.ShowRaidAdminSelectionUI()
  
  -- Keep poll open for 5 seconds to accept responses
  OGRH.ScheduleFunc(function()
    OGRH.RaidLead.pollInProgress = false
  end, 5)
end

-- Handle poll response
function OGRH.HandleAddonPollResponse(sender, version, checksum, tocVersion)
  version = version or "Unknown"
  checksum = checksum or "0"
  tocVersion = tocVersion or version
  
  -- Route to raid admin selection poll if active
  if OGRH.RaidLead.pollInProgress then
    -- Check if already in list
    local alreadyRecorded = false
    for i = 1, table.getn(OGRH.RaidLead.pollResponses) do
      if OGRH.RaidLead.pollResponses[i].name == sender then
        alreadyRecorded = true
        break
      end
    end
    
    if not alreadyRecorded then
      -- Get sender's rank
      local senderRank = "None"
      for i = 1, GetNumRaidMembers() do
        local name, rank = GetRaidRosterInfo(i)
        if name == sender then
          if rank == 2 then
            senderRank = "Leader"
          elseif rank == 1 then
            senderRank = "Assistant"
          end
          break
        end
      end
      
      table.insert(OGRH.RaidLead.pollResponses, {
        name = sender,
        rank = senderRank,
        version = version,
        tocVersion = tocVersion,
        checksum = checksum
      })
      
      -- Refresh the UI if it's visible
      if OGRH_RaidLeadSelectionFrame and OGRH_RaidLeadSelectionFrame:IsVisible() and OGRH_RaidLeadSelectionFrame.Rebuild then
        OGRH_RaidLeadSelectionFrame.Rebuild()
      end
    end
  end
  
  -- Route to push structure poll if active
  if OGRH.Sync and OGRH.Sync.HandlePushPollResponse then
    OGRH.Sync.HandlePushPollResponse(sender, version, checksum)
  end
end

-- Handle ReadHelper poll response
function OGRH.HandleReadHelperPollResponse(sender, version)
  if not OGRH.RaidLead.pollInProgress then
    return
  end
  
  version = version or "Unknown"
  
  -- Check if already in list
  for i = 1, table.getn(OGRH.RaidLead.readHelperResponses) do
    if OGRH.RaidLead.readHelperResponses[i].name == sender then
      return -- Already recorded
    end
  end
  
  table.insert(OGRH.RaidLead.readHelperResponses, {
    name = sender,
    version = version
  })
  
  -- Refresh the UI if it's visible
  if OGRH_RaidLeadSelectionFrame and OGRH_RaidLeadSelectionFrame:IsVisible() and OGRH_RaidLeadSelectionFrame.Rebuild then
    OGRH_RaidLeadSelectionFrame.Rebuild()
  end
end

-- Show raid admin selection UI
function OGRH.ShowRaidAdminSelectionUI()
  OGRH.CloseAllWindows("OGRH_RaidLeadSelectionFrame")
  
  if OGRH_RaidLeadSelectionFrame then
    OGRH_RaidLeadSelectionFrame:Show()
    OGRH_RaidLeadSelectionFrame.Rebuild()
    return
  end
  
  local frame = CreateFrame("Frame", "OGRH_RaidLeadSelectionFrame", UIParent)
  frame:SetWidth(360)  -- Increased width for version and checksum columns
  frame:SetHeight(260)
  frame:SetPoint("CENTER", UIParent, "CENTER")
  frame:SetFrameStrata("DIALOG")
  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function() frame:StartMoving() end)
  frame:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
  
  frame:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 16,
    insets = {left = 4, right = 4, top = 4, bottom = 4}
  })
  frame:SetBackdropColor(0, 0, 0, 0.9)
  
  -- Refresh button
  local refreshBtn = CreateFrame("Button", nil, frame)
  refreshBtn:SetWidth(60)
  refreshBtn:SetHeight(24)
  refreshBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -75, -10)
  
  local refreshBtnText = refreshBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  refreshBtnText:SetPoint("CENTER", 0, 0)
  refreshBtnText:SetText("Refresh")
  refreshBtn.text = refreshBtnText
  
  OGRH.StyleButton(refreshBtn)
  refreshBtn:SetScript("OnClick", function()
    -- Re-poll
    OGRH.PollAddonUsers()
  end)
  
  -- Close button
  local closeBtn = CreateFrame("Button", nil, frame)
  closeBtn:SetWidth(60)
  closeBtn:SetHeight(24)
  closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -10)
  
  -- Create text for close button
  local closeBtnText = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  closeBtnText:SetPoint("CENTER", 0, 0)
  closeBtnText:SetText("Close")
  closeBtn.text = closeBtnText
  
  OGRH.StyleButton(closeBtn)
  closeBtn:SetScript("OnClick", function() frame:Hide() end)
  
  -- Title (left-aligned under close button, matching "Raids:" style)
  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -17)
  title:SetText("Select Raid Admin:")
  title:SetTextColor(1, 0.82, 0)
  
  -- Column headers
  local nameHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  nameHeader:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, -38)
  nameHeader:SetText("Name")
  nameHeader:SetTextColor(1, 0.82, 0)
  
  local versionHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  versionHeader:SetPoint("TOPLEFT", frame, "TOPLEFT", 155, -38)
  versionHeader:SetText("Version")
  versionHeader:SetTextColor(1, 0.82, 0)
  
  local checksumHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  checksumHeader:SetPoint("TOPLEFT", frame, "TOPLEFT", 235, -38)
  checksumHeader:SetText("TOC")
  checksumHeader:SetTextColor(1, 0.82, 0)
  
  -- Player list panel (matching raids panel style)
  local playerPanel = CreateFrame("Frame", nil, frame)
  playerPanel:SetWidth(340)  -- Increased width
  playerPanel:SetHeight(190)  -- Reduced height to make room for headers
  playerPanel:SetPoint("TOP", frame, "TOP", 0, -55)  -- Moved down for headers
  playerPanel:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 12,
    insets = {left = 3, right = 3, top = 3, bottom = 3}
  })
  playerPanel:SetBackdropColor(0.15, 0.15, 0.15, 0.9)
  frame.playerPanel = playerPanel
  
  -- Scroll frame for player list (directly in panel, no inner frame)
  local scrollFrame = CreateFrame("ScrollFrame", nil, playerPanel)
  scrollFrame:SetPoint("TOPLEFT", playerPanel, "TOPLEFT", 5, -5)
  scrollFrame:SetPoint("BOTTOMRIGHT", playerPanel, "BOTTOMRIGHT", -5, 5)
  scrollFrame:EnableMouseWheel(true)
  
  local scrollChild = CreateFrame("Frame", nil, scrollFrame)
  scrollChild:SetWidth(330)  -- Increased for new columns
  scrollChild:SetHeight(1)
  scrollFrame:SetScrollChild(scrollChild)
  frame.scrollChild = scrollChild
  
  -- Mouse wheel scrolling
  scrollFrame:SetScript("OnMouseWheel", function()
    local delta = arg1
    local current = scrollFrame:GetVerticalScroll()
    local maxScroll = scrollChild:GetHeight() - scrollFrame:GetHeight()
    if maxScroll < 0 then maxScroll = 0 end
    
    local newScroll = current - (delta * 20)
    if newScroll < 0 then
      newScroll = 0
    elseif newScroll > maxScroll then
      newScroll = maxScroll
    end
    scrollFrame:SetVerticalScroll(newScroll)
  end)
  
  -- Player button list
  frame.playerButtons = {}
  
  -- Rebuild function
  frame.Rebuild = function()
    -- Clear existing buttons
    for i = 1, table.getn(frame.playerButtons) do
      frame.playerButtons[i]:Hide()
    end
    
    -- Check if local player can select (must be raid leader or assistant)
    local canSelect = false
    local playerName = UnitName("player")
    for i = 1, GetNumRaidMembers() do
      local name, rank = GetRaidRosterInfo(i)
      if name == playerName and (rank == 2 or rank == 1) then
        canSelect = true
        break
      end
    end
    
    -- Create message text if it doesn't exist
    if not frame.messageText then
      frame.messageText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      frame.messageText:SetPoint("CENTER", 0, 20)
      frame.messageText:SetWidth(300)
    end
    
    if not canSelect then
      -- Show message that only leader/assistant can select
      frame.messageText:SetTextColor(1, 0.2, 0.2)
      frame.messageText:SetText("Only raid leader or assistants\ncan designate the raid lead.")
      frame.messageText:Show()
      return
    else
      frame.messageText:Hide()
    end
    
    -- Check if we have any responses
    if table.getn(OGRH.RaidLead.pollResponses) == 0 then
      frame.messageText:SetTextColor(1, 0.82, 0)
      frame.messageText:SetText("No players with the addon detected.\n\nMake sure other raid members\nhave OG-RaidHelper installed.")
      frame.messageText:Show()
      return
    else
      frame.messageText:Hide()
    end
    
    -- Sort responses by rank (Leader > Assistant > None) then by name
    local sorted = {}
    for i = 1, table.getn(OGRH.RaidLead.pollResponses) do
      table.insert(sorted, OGRH.RaidLead.pollResponses[i])
    end
    
    table.sort(sorted, function(a, b)
      if a.rank ~= b.rank then
        if a.rank == "Leader" then return true end
        if b.rank == "Leader" then return false end
        if a.rank == "Assistant" then return true end
        if b.rank == "Assistant" then return false end
      end
      return a.name < b.name
    end)
    
    -- Initialize player buttons table and labels
    if not frame.playerButtons then
      frame.playerButtons = {}
    end
    if not frame.readHelperLabels then
      frame.readHelperLabels = {}
    end
    
    -- Create/update buttons for RaidHelper users
    local yOffset = 0
    local buttonIndex = 1
    
    for i = 1, table.getn(sorted) do
      local response = sorted[i]
      
      if not frame.playerButtons[buttonIndex] then
        local btn = CreateFrame("Button", nil, scrollChild)
        btn:SetWidth(330)  -- Increased width
        btn:SetHeight(18)
        btn:SetPoint("TOPLEFT", 0, yOffset)
        
        -- No backdrop - just highlight on selection
        local text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetPoint("LEFT", 5, 0)
        text:SetJustifyH("LEFT")
        text:SetWidth(130)  -- Constrain name width
        btn.text = text
        
        local rankText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        rankText:SetPoint("LEFT", 140, 0)
        btn.rankText = rankText
        
        local versionText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        versionText:SetPoint("LEFT", 145, 0)
        versionText:SetJustifyH("LEFT")
        versionText:SetWidth(70)
        btn.versionText = versionText
        
        local checksumText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        checksumText:SetPoint("LEFT", 225, 0)
        checksumText:SetJustifyH("LEFT")
        checksumText:SetWidth(80)
        btn.checksumText = checksumText
        
        frame.playerButtons[buttonIndex] = btn
      end
      
      local btn = frame.playerButtons[buttonIndex]
      
      -- Background texture setup
      if not btn.bg then
        btn.bg = btn:CreateTexture(nil, "BACKGROUND")
        btn.bg:SetAllPoints(btn)
        btn.bg:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
      end
      
      -- Get player class for color
      local playerClass = OGRH.GetPlayerClass and OGRH.GetPlayerClass(response.name)
      local classColor = playerClass and RAID_CLASS_COLORS[playerClass] or {r=1, g=1, b=1}
      
      -- Highlight current raid admin with green background (like selected raid)
      local currentAdmin = OGRH.GetRaidAdmin and OGRH.GetRaidAdmin()
      local isCurrentAdmin = (currentAdmin == response.name)
      if isCurrentAdmin then
        btn.bg:SetVertexColor(0, 0.4, 0, 0.5)
        btn.text:SetText(response.name)
      else
        -- Light gray background like raids list
        btn.bg:SetVertexColor(0.25, 0.35, 0.35, 0.8)
        btn.text:SetText(response.name)
      end
      btn.bg:Show()
      
      -- Apply class color to text
      btn.text:SetTextColor(classColor.r, classColor.g, classColor.b)
      
      -- Hover effect and click handler (only for Button frames - RaidHelper users)
      if btn.RegisterForClicks then
        -- This is a Button, set up hover and click
        btn:SetScript("OnEnter", function()
          if not btn.hoverBg then
            btn.hoverBg = btn:CreateTexture(nil, "BACKGROUND")
            btn.hoverBg:SetAllPoints(btn)
            btn.hoverBg:SetTexture("Interface\\Tooltips\\UI-Tooltip-Background")
          end
          if isCurrentAdmin then
            btn.hoverBg:SetVertexColor(0, 0.5, 0, 0.6)
          else
            btn.hoverBg:SetVertexColor(0.35, 0.45, 0.45, 0.9)
          end
          btn.hoverBg:Show()
        end)
        
        btn:SetScript("OnLeave", function()
          if btn.hoverBg then
            btn.hoverBg:Hide()
          end
        end)
      end
      
      -- Color code rank (only if rankText exists - RaidHelper users have this)
      if btn.rankText then
        if response.rank == "Leader" then
          btn.rankText:SetText("|cffff0000L|r")
        elseif response.rank == "Assistant" then
          btn.rankText:SetText("|cffffff00A|r")
        else
          btn.rankText:SetText("")
        end
      end
      
      -- Display version (color red if different from local)
      local localVersion = OGRH.VERSION or "Unknown"
      local displayVersion = response.version or "Unknown"
      if displayVersion ~= localVersion then
        btn.versionText:SetText("|cffff0000" .. displayVersion .. "|r")
      else
        btn.versionText:SetText("|cff00ff00" .. displayVersion .. "|r")
      end
      
      -- Display TOC version (color red if different from code version = needs restart)
      if btn.checksumText then
        local localTocVersion = OGRH.TOC_VERSION or OGRH.VERSION or "Unknown"
        
        local displayTocVersion = response.tocVersion or response.version or "Unknown"
        local displayCodeVersion = response.version or "Unknown"
        
        -- Red if TOC doesn't match their code version (needs restart)
        -- Green if TOC matches code version (fully updated)
        if displayTocVersion ~= displayCodeVersion then
          btn.checksumText:SetText("|cffff0000" .. displayTocVersion .. "|r")
        else
          btn.checksumText:SetText("|cff00ff00" .. displayTocVersion .. "|r")
        end
        
        -- Click handler (only for Button types - RaidHelper users)
        btn:SetScript("OnClick", function()
          OGRH.SetRaidAdmin(response.name)
          frame:Hide()
        end)
      end
      
      btn:SetPoint("TOPLEFT", 0, yOffset)
      btn:Show()
      yOffset = yOffset - 20
      buttonIndex = buttonIndex + 1
    end
    
    -- Add ReadHelper users section if any exist
    if OGRH.RaidLead.readHelperResponses and table.getn(OGRH.RaidLead.readHelperResponses) > 0 then
      -- Add spacing and header
      yOffset = yOffset - 10
      
      -- Create header label if needed
      if not frame.readHelperLabels.header then
        frame.readHelperLabels.header = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        frame.readHelperLabels.header:SetTextColor(1, 0.82, 0)
      end
      frame.readHelperLabels.header:SetPoint("TOPLEFT", 5, yOffset)
      frame.readHelperLabels.header:SetText("OG-ReadHelper Users:")
      frame.readHelperLabels.header:Show()
      yOffset = yOffset - 20
      
      -- Sort ReadHelper responses by name
      local sortedReadHelper = {}
      for i = 1, table.getn(OGRH.RaidLead.readHelperResponses) do
        table.insert(sortedReadHelper, OGRH.RaidLead.readHelperResponses[i])
      end
      table.sort(sortedReadHelper, function(a, b) return a.name < b.name end)
      
      -- Display ReadHelper users (non-clickable, just informational)
      for i = 1, table.getn(sortedReadHelper) do
        local response = sortedReadHelper[i]
        
        if not frame.playerButtons[buttonIndex] then
          local btn = CreateFrame("Frame", nil, scrollChild)  -- Frame, not Button (non-clickable)
          btn:SetWidth(330)
          btn:SetHeight(18)
          
          local text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
          text:SetPoint("LEFT", 5, 0)
          text:SetJustifyH("LEFT")
          text:SetWidth(130)
          btn.text = text
          
          local versionText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
          versionText:SetPoint("LEFT", 145, 0)
          versionText:SetJustifyH("LEFT")
          versionText:SetWidth(70)
          btn.versionText = versionText
          
          frame.playerButtons[buttonIndex] = btn
        end
        
        local btn = frame.playerButtons[buttonIndex]
        
        -- Get player class for color
        local playerClass = OGRH.GetPlayerClass and OGRH.GetPlayerClass(response.name)
        local classColor = playerClass and RAID_CLASS_COLORS[playerClass] or {r=1, g=1, b=1}
        
        btn.text:SetText(response.name)
        btn.text:SetTextColor(classColor.r, classColor.g, classColor.b)
        
        -- Display version
        btn.versionText:SetText(response.version or "Unknown")
        btn.versionText:SetTextColor(0.7, 0.7, 0.7)
        
        -- Hide rank/checksum fields if they exist (ReadHelper users don't have these)
        if btn.rankText then btn.rankText:SetText("") end
        if btn.checksumText then btn.checksumText:SetText("") end
        if btn.bg then btn.bg:Hide() end
        
        btn:SetPoint("TOPLEFT", 0, yOffset)
        btn:Show()
        yOffset = yOffset - 20
        buttonIndex = buttonIndex + 1
      end
    else
      -- Hide header if no ReadHelper users
      if frame.readHelperLabels.header then
        frame.readHelperLabels.header:Hide()
      end
    end
    
    -- Hide unused buttons
    for i = buttonIndex, table.getn(frame.playerButtons) do
      frame.playerButtons[i]:Hide()
    end
    
    scrollChild:SetHeight(math.max(1, math.abs(yOffset)))
  end
  
  frame.Rebuild()
  frame:Show()
end

-- Update UI elements based on raid admin status
function OGRH.UpdateRaidAdminUI()
  local canEdit = OGRH.CanEdit()
  
  -- Check if player is the ACTUAL current admin (not just a session admin)
  local currentAdmin = OGRH.GetRaidAdmin()
  local isCurrentAdmin = (currentAdmin == UnitName("player"))
  
  -- Update admin button text (green only for actual current admin)
  if OGRH.adminButton then
    if isCurrentAdmin then
      OGRH.adminButton:SetText("|cff00ff00Admin|r")
    else
      OGRH.adminButton:SetText("|cffffff00Admin|r")
    end
  end
  
  -- Enable/disable Structure Sync and Encounter Sync buttons
  -- These check full permissions (hardcoded admins can sync even if not current admin)
  local canSync = OGRH.IsRaidAdmin(UnitName("player"))
  
  if OGRH_EncounterFrame then
    if OGRH_EncounterFrame.structureSyncBtn then
      if canSync then
        OGRH_EncounterFrame.structureSyncBtn:Enable()
        OGRH_EncounterFrame.structureSyncBtn:SetAlpha(1.0)
      else
        OGRH_EncounterFrame.structureSyncBtn:Disable()
        OGRH_EncounterFrame.structureSyncBtn:SetAlpha(0.5)
      end
    end
    
    if OGRH_EncounterFrame.encounterSyncBtn then
      if canSync then
        OGRH_EncounterFrame.encounterSyncBtn:Enable()
        OGRH_EncounterFrame.encounterSyncBtn:SetAlpha(1.0)
      else
        OGRH_EncounterFrame.encounterSyncBtn:Disable()
        OGRH_EncounterFrame.encounterSyncBtn:SetAlpha(0.5)
      end
    end
  end
  
  -- Disable/enable edit controls in encounter planning window
  if OGRH_EncounterFrame and OGRH_EncounterFrame:IsVisible() then
    -- This will be handled by the encounter management UI
    if OGRH.RefreshEncounterEditState then
      OGRH.RefreshEncounterEditState()
    end
  end
end

-- Request full sync from admin (using Phase 2 sync system)
function OGRH.RequestSyncFromAdmin()
  local currentAdmin = OGRH.GetRaidAdmin()
  if not currentAdmin then
    OGRH.Msg("No raid admin set - cannot request sync")
    return
  end
  
  if GetNumRaidMembers() == 0 then
    OGRH.Msg("You must be in a raid.")
    return
  end
  
  -- Use Phase 2 sync system for reliable sync request
  if OGRH.Sync and OGRH.Sync.RequestFullSync then
    OGRH.Sync.RequestFullSync(currentAdmin)
    OGRH.Msg("Requesting encounter sync from raid admin...")
  else
    OGRH.Msg("|cffff0000[OGRH]|r Phase 2 sync system not available")
  end
end

-- Legacy function for backward compatibility
function OGRH.RequestSyncFromLead()
  OGRH.RequestSyncFromAdmin()
end

-- Query raid for current admin (now delegates to AdminDiscovery)
function OGRH.QueryRaidAdmin()
  if GetNumRaidMembers() == 0 then
    return
  end
  
  -- Delegate to AdminDiscovery system for proper 3-tier resolution
  if OGRH.AdminDiscovery and OGRH.AdminDiscovery.Start then
    OGRH.AdminDiscovery.Start()
  end
end

-- Initialize raid admin system with consolidated RAID_ROSTER_UPDATE handler
function OGRH.InitRaidLead()
  -- Admin is determined by AdminDiscovery:
  --   1. lastAdmin (persisted) if in raid with OGRH
  --   2. Raid Leader with OGRH
  --   3. Alphabetically first OGRH user (temp, no lastAdmin update)
  
  -- Set up consolidated event handler for raid roster changes
  if not OGRH.RaidLeadEventFrame then
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("RAID_ROSTER_UPDATE")
    frame.lastRaidSize = GetNumRaidMembers()
    
    frame:SetScript("OnEvent", function()
      local currentSize = GetNumRaidMembers()
      
      -- If we just left the raid (went from > 0 to 0)
      if frame.lastRaidSize > 0 and currentSize == 0 then
        -- Cancel any in-progress discovery
        if OGRH.AdminDiscovery then
          OGRH.AdminDiscovery.Cancel()
        end
        
        -- Clear runtime admin (lastAdmin stays in SV for reconnection)
        if OGRH.Permissions and OGRH.Permissions.State then
          OGRH.Permissions.State.currentAdmin = nil
        end
        if OGRH.RaidLead then
          OGRH.RaidLead.currentLead = nil
        end
        if OGRH.UpdateRaidAdminUI then
          OGRH.UpdateRaidAdminUI()
        end
        
      -- If we just joined a raid (went from 0 to > 0)
      elseif frame.lastRaidSize == 0 and currentSize > 0 then
        -- Start admin discovery (5s passive listen, then query)
        if OGRH.AdminDiscovery and OGRH.AdminDiscovery.Start then
          OGRH.AdminDiscovery.Start()
        end
        
      -- Already in raid - check for admin demotion
      elseif currentSize > 0 then
        local currentAdmin = OGRH.GetRaidAdmin and OGRH.GetRaidAdmin()
        if currentAdmin and OGRH.AdminDiscovery then
          for i = 1, currentSize do
            local name, rank = GetRaidRosterInfo(i)
            if name == currentAdmin then
              local lastRank = OGRH.AdminDiscovery.lastAdminRank
              -- Detect demotion: admin had L/A (rank >= 1) and now has rank 0
              if lastRank and lastRank >= 1 and rank == 0 then
                OGRH.Msg("|cff00ccff[RH]|r Admin " .. currentAdmin .. " was demoted, starting re-discovery")
                -- Clear admin and re-discover
                if OGRH.Permissions and OGRH.Permissions.State then
                  OGRH.Permissions.State.currentAdmin = nil
                end
                if OGRH.RaidLead then
                  OGRH.RaidLead.currentLead = nil
                end
                if OGRH.UpdateRaidAdminUI then
                  OGRH.UpdateRaidAdminUI()
                end
                OGRH.AdminDiscovery.Start()
              end
              -- Always update tracked rank
              OGRH.AdminDiscovery.lastAdminRank = rank
              break
            end
          end
        end
      end
      
      frame.lastRaidSize = currentSize
    end)
    
    OGRH.RaidLeadEventFrame = frame
  end
  
  -- If already in raid on load (e.g., /reload), start discovery
  if GetNumRaidMembers() > 0 then
    if OGRH.AdminDiscovery and OGRH.AdminDiscovery.Start then
      OGRH.AdminDiscovery.Start()
    end
  end
end
