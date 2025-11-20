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

-- Check if local player is the raid lead
function OGRH.IsRaidLead()
  local playerName = UnitName("player")
  return OGRH.RaidLead.currentLead == playerName
end

-- Check if local player can edit (is raid lead)
function OGRH.CanEdit()
  return OGRH.IsRaidLead()
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
  if playerName == selfName then
    OGRH.Msg("|cff00ff00You are now the Raid Lead for encounter planning.|r")
  else
    OGRH.Msg("Raid Lead set to: " .. playerName)
  end
end

-- Poll for addon users in raid
function OGRH.PollAddonUsers()
  if GetNumRaidMembers() == 0 then
    OGRH.Msg("You must be in a raid to poll for addon users.")
    return
  end
  
  -- Reset poll state
  OGRH.RaidLead.pollResponses = {}
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
  
  table.insert(OGRH.RaidLead.pollResponses, {
    name = selfName,
    rank = selfRank
  })
  
  -- Wait 2 seconds then show results
  OGRH.ScheduleFunc(function()
    OGRH.RaidLead.pollInProgress = false
    local count = table.getn(OGRH.RaidLead.pollResponses)
    OGRH.Msg("Poll complete: " .. count .. " player(s) with addon detected.")
    OGRH.ShowRaidLeadSelectionUI()
  end, 2)
  
  OGRH.Msg("Polling raid for addon users...")
end

-- Handle poll response
function OGRH.HandleAddonPollResponse(sender)
  if not OGRH.RaidLead.pollInProgress then
    return
  end
  
  -- Check if already in list
  for i = 1, table.getn(OGRH.RaidLead.pollResponses) do
    if OGRH.RaidLead.pollResponses[i].name == sender then
      return -- Already recorded
    end
  end
  
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
    rank = senderRank
  })
end

-- Show raid lead selection UI
function OGRH.ShowRaidLeadSelectionUI()
  if OGRH_RaidLeadSelectionFrame then
    OGRH_RaidLeadSelectionFrame:Show()
    OGRH_RaidLeadSelectionFrame.Rebuild()
    return
  end
  
  local frame = CreateFrame("Frame", "OGRH_RaidLeadSelectionFrame", UIParent)
  frame:SetWidth(195)
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
  
  -- Player list panel (matching raids panel style)
  local playerPanel = CreateFrame("Frame", nil, frame)
  playerPanel:SetWidth(175)
  playerPanel:SetHeight(210)
  playerPanel:SetPoint("TOP", frame, "TOP", 0, -38)
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
  scrollChild:SetWidth(165)
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
    
    -- Create/update buttons
    local yOffset = 0
    for i = 1, table.getn(sorted) do
      local response = sorted[i]
      
      if not frame.playerButtons[i] then
        local btn = CreateFrame("Button", nil, scrollChild)
        btn:SetWidth(165)
        btn:SetHeight(18)
        btn:SetPoint("TOPLEFT", 0, yOffset)
        
        -- No backdrop - just highlight on selection
        local text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetPoint("LEFT", 5, 0)
        text:SetJustifyH("LEFT")
        btn.text = text
        
        local rankText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        rankText:SetPoint("RIGHT", -5, 0)
        btn.rankText = rankText
        
        frame.playerButtons[i] = btn
      end
      
      local btn = frame.playerButtons[i]
      
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
      
      -- Hover effect
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
      
      -- Color code rank
      if response.rank == "Leader" then
        btn.rankText:SetText("|cffff0000L|r")
      elseif response.rank == "Assistant" then
        btn.rankText:SetText("|cffffff00A|r")
      else
        btn.rankText:SetText("")
      end
      
      -- Click handler
      btn:SetScript("OnClick", function()
        OGRH.SetRaidLead(response.name)
        frame:Hide()
      end)
      
      btn:SetPoint("TOPLEFT", 0, yOffset)
      btn:Show()
      yOffset = yOffset - 20
    end
    
    scrollChild:SetHeight(math.max(1, math.abs(yOffset)))
  end
  
  frame.Rebuild()
  frame:Show()
end

-- Update UI elements based on raid lead status
function OGRH.UpdateRaidLeadUI()
  local canEdit = OGRH.CanEdit()
  
  -- Update sync button text
  if OGRH.syncButton then
    if OGRH.IsRaidLead() then
      OGRH.syncButton:SetText("|cff00ff00Sync|r")
    else
      OGRH.syncButton:SetText("|cffffff00Sync|r")
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
