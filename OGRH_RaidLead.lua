--[[
  OGRH_RaidLead.lua
  Raid Lead management system for coordinated encounter planning
]]--

-- Raid Lead state
OGRH.RaidLead = {
  currentLead = nil,           -- Current designated raid lead (player name)
  addonUsers = {},             -- List of raid members running the addon {name, rank}
  lastPollTime = 0,            -- Timestamp of last poll
  pollResponses = {},          -- Responses to current poll
  pollInProgress = false       -- Whether a poll is active
}

-- Check if local player is the raid admin
function OGRH.IsRaidAdmin()
  local playerName = UnitName("player")
  return OGRH.RaidLead.currentLead == playerName
end

-- Backward compatibility wrapper
function OGRH.IsRaidLead()
  return OGRH.IsRaidAdmin()
end

-- Check if local player can edit (is raid lead, or not in raid)
function OGRH.CanEdit()
  -- If not in a raid, allow editing
  if GetNumRaidMembers() == 0 then
    return true
  end
  
  -- If in a raid, must be the designated raid lead
  return OGRH.IsRaidLead()
end

-- Check if local player can navigate encounters (change Main UI selection)
-- Check if local player can manage roles (is raid lead, L, or A)
function OGRH.CanManageRoles()
  -- If not in a raid, allow role management
  if GetNumRaidMembers() == 0 then
    return true
  end
  
  -- Check if player is the designated raid admin
  if OGRH.IsRaidLead() then
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

function OGRH.CanNavigateEncounter()
  -- If not in a raid, allow navigation
  if GetNumRaidMembers() == 0 then
    return true
  end
  
  -- Check if player is the designated raid admin
  if OGRH.IsRaidLead() then
    return true
  end
  
  -- Check if player is raid leader or assistant
  local playerName = UnitName("player")
  
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

-- Set the raid lead
function OGRH.SetRaidLead(playerName)
  OGRH.RaidLead.currentLead = playerName
  
  -- Save to saved variables
  OGRH.EnsureSV()
  OGRH_SV.raidLead = playerName
  
  -- Broadcast the change
  if GetNumRaidMembers() > 0 then
    local message = "RAID_LEAD_SET;" .. playerName
    SendAddonMessage(OGRH.ADDON_PREFIX, message, "RAID")
  end
  
  -- Update UI state
  OGRH.UpdateRaidLeadUI()
  
  local selfName = UnitName("player")
  if playerName ~= selfName then
    OGRH.Msg("Raid Lead set to: " .. playerName)
  end
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
    OGRH.Msg("Only raid leaders or assistants can select a raid lead.")
    return
  end
  
  -- Reset poll state
  OGRH.RaidLead.pollResponses = {}
  OGRH.RaidLead.readHelperResponses = {}
  OGRH.RaidLead.pollInProgress = true
  OGRH.RaidLead.lastPollTime = GetTime()
  
  -- Send poll request
  SendAddonMessage(OGRH.ADDON_PREFIX, "ADDON_POLL", "RAID")
  
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
    checksum = checksum
  })
  
  -- Show UI immediately
  OGRH.ShowRaidLeadSelectionUI()
  
  -- Keep poll open for 5 seconds to accept responses
  OGRH.ScheduleFunc(function()
    OGRH.RaidLead.pollInProgress = false
  end, 5)
end

-- Handle poll response
function OGRH.HandleAddonPollResponse(sender, version, checksum)
  version = version or "Unknown"
  checksum = checksum or "0"
  
  -- Route to raid lead selection poll if active
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

-- Show raid lead selection UI
function OGRH.ShowRaidLeadSelectionUI()
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
  title:SetText("Select Raid Lead:")
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
  checksumHeader:SetText("Checksum")
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
      
      -- Highlight current raid lead with green background (like selected raid)
      local isCurrentLead = (OGRH.RaidLead.currentLead == response.name)
      if isCurrentLead then
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
          if isCurrentLead then
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
      
      -- Display checksum (color red if different from local) - only for RaidHelper users
      if btn.checksumText then
        local localChecksum = "0"
        if OGRH.Sync and OGRH.Sync.GetCurrentChecksum then
          localChecksum = OGRH.Sync.GetCurrentChecksum()
        end
        
        local displayChecksum = response.checksum or "0"
        if displayChecksum ~= localChecksum then
          btn.checksumText:SetText("|cffff0000" .. displayChecksum .. "|r")
        else
          btn.checksumText:SetText("|cff00ff00" .. displayChecksum .. "|r")
        end
        
        -- Click handler (only for Button types with checksum - RaidHelper users)
        btn:SetScript("OnClick", function()
          OGRH.SetRaidLead(response.name)
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

-- Update UI elements based on raid lead status
function OGRH.UpdateRaidLeadUI()
  local canEdit = OGRH.CanEdit()
  local isRaidLead = OGRH.IsRaidLead()
  
  -- Update sync button text
  if OGRH.syncButton then
    if isRaidLead then
      OGRH.syncButton:SetText("|cff00ff00Sync|r")
    else
      OGRH.syncButton:SetText("|cffffff00Sync|r")
    end
  end
  
  -- Enable/disable Structure Sync and Encounter Sync buttons
  if OGRH_EncounterFrame then
    if OGRH_EncounterFrame.structureSyncBtn then
      if isRaidLead then
        OGRH_EncounterFrame.structureSyncBtn:Enable()
        OGRH_EncounterFrame.structureSyncBtn:SetAlpha(1.0)
      else
        OGRH_EncounterFrame.structureSyncBtn:Disable()
        OGRH_EncounterFrame.structureSyncBtn:SetAlpha(0.5)
      end
    end
    
    if OGRH_EncounterFrame.encounterSyncBtn then
      if isRaidLead then
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

-- Request sync from raid lead
function OGRH.RequestSyncFromLead()
  if not OGRH.RaidLead.currentLead then
    OGRH.Msg("No raid lead is currently set.")
    return
  end
  
  if GetNumRaidMembers() == 0 then
    OGRH.Msg("You must be in a raid.")
    return
  end
  
  -- Send request
  SendAddonMessage(OGRH.ADDON_PREFIX, "SYNC_REQUEST", "RAID")
  OGRH.Msg("Requesting encounter sync from raid lead...")
end

-- Schedule a function to run after delay (seconds)
function OGRH.ScheduleFunc(func, delay)
  local frame = CreateFrame("Frame")
  local elapsed = 0
  frame:SetScript("OnUpdate", function()
    elapsed = elapsed + arg1
    if elapsed >= delay then
      frame:SetScript("OnUpdate", nil)
      func()
    end
  end)
end

-- Query raid for current lead
function OGRH.QueryRaidLead()
  if GetNumRaidMembers() == 0 then
    return
  end
  
  SendAddonMessage(OGRH.ADDON_PREFIX, "RAID_LEAD_QUERY", "RAID")
end

-- Initialize raid lead from saved variables
function OGRH.InitRaidLead()
  OGRH.EnsureSV()
  if OGRH_SV.raidLead then
    OGRH.RaidLead.currentLead = OGRH_SV.raidLead
  end
  
  -- Set up event handler for raid roster changes
  if not OGRH.RaidLeadEventFrame then
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("RAID_ROSTER_UPDATE")
    frame.lastRaidSize = GetNumRaidMembers()
    
    frame:SetScript("OnEvent", function()
      local currentSize = GetNumRaidMembers()
      
      -- If we just left the raid (went from > 0 to 0)
      if frame.lastRaidSize > 0 and currentSize == 0 then
        -- Clear raid lead
        OGRH.RaidLead.currentLead = nil
        OGRH_SV.raidLead = nil
        if OGRH.UpdateRaidLeadUI then
          OGRH.UpdateRaidLeadUI()
        end
      -- If we just joined a raid (went from 0 to > 0)
      elseif frame.lastRaidSize == 0 and currentSize > 0 then
        -- Query for current raid lead after a short delay
        OGRH.ScheduleFunc(function()
          if GetNumRaidMembers() > 0 then
            OGRH.QueryRaidLead()
          end
        end, 1)
      end
      
      frame.lastRaidSize = currentSize
    end)
    
    OGRH.RaidLeadEventFrame = frame
  end
  
  -- If already in raid, query for current lead
  if GetNumRaidMembers() > 0 then
    OGRH.ScheduleFunc(function()
      if GetNumRaidMembers() > 0 then
        OGRH.QueryRaidLead()
      end
    end, 1)
  end
end
