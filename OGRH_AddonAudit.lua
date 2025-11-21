--[[
  OGRH_AddonAudit.lua
  
  Addon Audit window for OG-RaidHelper
  Queries raid members for specific addon versions (e.g., BigWigs)
  
  Version: 1.0.0
]]--

if not OGRH then
  DEFAULT_CHAT_FRAME:AddMessage("ERROR: OGRH_AddonAudit loaded before OGRH_Core!")
  return
end

OGRH.AddonAudit = OGRH.AddonAudit or {}
local AddonAudit = OGRH.AddonAudit

-- UI constants
local FRAME_WIDTH = 700
local FRAME_HEIGHT = 500
local PANEL_PADDING = 10
local LEFT_PANEL_WIDTH = 180
local BUTTON_HEIGHT = 25
local ITEM_HEIGHT = 22

-- Addon registry
local addonList = {
  {
    name = "BigWigs",
    displayName = "BigWigs",
    checkFunction = function()
      return BigWigsVersionQuery ~= nil
    end,
    queryFunction = function()
      -- Manually trigger BigWigs sync without showing their UI
      if not BigWigsVersionQuery then return end
      
      -- Initialize our own response tables
      AddonAudit.bwResponseTable = {}
      AddonAudit.bwPepoResponseTable = {}
      AddonAudit.bwResponded = {} -- Track who responded
      
      -- Populate with raid members
      if GetNumRaidMembers() > 0 then
        for i = 1, GetNumRaidMembers() do
          local name, _, _, _, _, _, zone = GetRaidRosterInfo(i)
          if name then
            if zone == "Offline" then
              AddonAudit.bwResponseTable[name] = -2
              AddonAudit.bwResponded[name] = true -- offline = responded
            else
              AddonAudit.bwResponseTable[name] = nil -- no response yet
              AddonAudit.bwResponded[name] = false
            end
          end
        end
      end
      
      -- Add self
      local playerName = UnitName("player")
      
      -- Populate zone revisions if not already done
      if not BigWigsVersionQuery.zoneRevisions and BigWigsVersionQuery.PopulateRevisions then
        BigWigsVersionQuery:PopulateRevisions()
      end
      
      if BigWigsVersionQuery.zoneRevisions then
        local version = BigWigsVersionQuery.zoneRevisions["BigWigs"] or 0
        AddonAudit.bwResponseTable[playerName] = version
        AddonAudit.bwPepoResponseTable[playerName] = version
        AddonAudit.bwResponded[playerName] = true
      else
        AddonAudit.bwResponseTable[playerName] = -1
        AddonAudit.bwPepoResponseTable[playerName] = -1
        AddonAudit.bwResponded[playerName] = true
      end
      
      -- Register to receive BigWigs sync responses
      if not AddonAudit.bwSyncRegistered then
        AddonAudit.bwSyncRegistered = true
        
        -- Hook into BigWigs event system
        if BigWigs and BigWigs.RegisterEvent then
          BigWigs:RegisterEvent("BigWigs_RecvSync", function(sync, rest, nick)
            AddonAudit.OnBigWigsRecvSync(sync, rest, nick)
          end)
        end
      end
      
      -- Populate zone revisions if needed
      if BigWigsVersionQuery.PopulateRevisions and not BigWigsVersionQuery.zoneRevisions then
        BigWigsVersionQuery:PopulateRevisions()
      end
      
      -- Trigger the sync query
      if BigWigsVersionQuery.TriggerEvent then
        BigWigsVersionQuery:TriggerEvent("BigWigs_SendSync", "BWVQ BigWigs")
      end
    end,
    getResultsFunction = function()
      if not AddonAudit.bwResponseTable then return nil end
      return AddonAudit.bwResponseTable, AddonAudit.bwPepoResponseTable
    end
  },
  {
    name = "TWThreat",
    displayName = "TW Threat",
    checkFunction = function()
      -- TWThreat doesn't expose itself globally, but creates global frames and saved variables
      return getglobal("TWTMain") ~= nil or TWT_CONFIG ~= nil
    end,
    queryFunction = function()
      -- Initialize response tables
      AddonAudit.twtResponseTable = {}
      AddonAudit.twtResponded = {}
      
      -- Populate with raid members
      if GetNumRaidMembers() > 0 then
        for i = 1, GetNumRaidMembers() do
          local name, _, _, _, _, _, zone = GetRaidRosterInfo(i)
          if name then
            if zone == "Offline" then
              AddonAudit.twtResponseTable[name] = -2
              AddonAudit.twtResponded[name] = true
            else
              AddonAudit.twtResponseTable[name] = nil
              AddonAudit.twtResponded[name] = false
            end
          end
        end
      end
      
      -- Add self - get version from addon metadata since TWT is local
      local playerName = UnitName("player")
      local selfVersion = GetAddOnMetadata("TWThreat", "Version")
      if selfVersion then
        AddonAudit.twtResponseTable[playerName] = selfVersion
        AddonAudit.twtResponded[playerName] = true
      end
      
      -- Register event handler
      if not AddonAudit.twtEventFrame then
        AddonAudit.twtEventFrame = CreateFrame("Frame")
        AddonAudit.twtEventFrame:RegisterEvent("CHAT_MSG_ADDON")
        AddonAudit.twtEventFrame:SetScript("OnEvent", function()
          if event == "CHAT_MSG_ADDON" and arg1 == "TWT" then
            AddonAudit.OnTWThreatMessage(arg2, arg4)
          end
        end)
      end
      
      -- Send query directly since TWT.send is not accessible (TWT is local)
      SendAddonMessage("TWT", "TWT_WHO", "RAID")
    end,
    getResultsFunction = function()
      if not AddonAudit.twtResponseTable then return nil end
      return AddonAudit.twtResponseTable, nil
    end
  }
}

-- State
local selectedAddon = nil
local queryInProgress = false

------------------------------
--   TWThreat Handler        --
------------------------------

function AddonAudit.OnTWThreatMessage(message, sender)
  if not AddonAudit.twtResponseTable or not sender then return end
  
  -- Handle TWT_ME responses (format: "TWT_ME:version")
  if string.find(message, "TWT_ME:", 1, true) then
    local version = string.sub(message, 8) -- Skip "TWT_ME:"
    if version and version ~= "" then
      AddonAudit.twtResponseTable[sender] = version
      AddonAudit.twtResponded[sender] = true
    end
  end
end

------------------------------
--   BigWigs Sync Handler   --
------------------------------

function AddonAudit.OnBigWigsRecvSync(sync, rest, nick)
  if not AddonAudit.bwResponseTable or not nick then return end
  
  -- Handle version query requests (others querying us)
  if sync == "BWVQ" and nick ~= UnitName("player") and rest then
    if not BigWigsVersionQuery.zoneRevisions then
      if BigWigsVersionQuery.PopulateRevisions then
        BigWigsVersionQuery:PopulateRevisions()
      end
    end
    
    if BigWigsVersionQuery.zoneRevisions then
      if not BigWigsVersionQuery.zoneRevisions[rest] then
        BigWigsVersionQuery:TriggerEvent("BigWigs_SendSync", "PEPO_BWVR -1 " .. nick)
      else
        BigWigsVersionQuery:TriggerEvent("BigWigs_SendSync", "PEPO_BWVR " .. BigWigsVersionQuery.zoneRevisions[rest] .. " " .. nick)
      end
    end
  -- Handle version responses (responses to our query)
  elseif string.find(sync, "BWVR") and nick and rest then
    local isPepo = (sync == "PEPO_BWVR")
    
    -- Parse response format: "version playername" or just "version"
    local revision, queryNick = nil, nil
    if tonumber(rest) == nil then
      -- New format: "version playername"
      local spacePos = string.find(rest, " ")
      if spacePos then
        local versionStr = string.sub(rest, 1, spacePos - 1)
        queryNick = string.sub(rest, spacePos + 1)
        revision = tonumber(versionStr)
      end
    else
      -- Old format: just version number
      revision = tonumber(rest)
    end
    
    -- Only accept if response is for us or no target specified
    if revision and (queryNick == nil or queryNick == UnitName("player")) then
      AddonAudit.bwResponseTable[nick] = revision
      AddonAudit.bwResponded[nick] = true
      if isPepo then
        AddonAudit.bwPepoResponseTable[nick] = revision
      end
    end
  end
end

------------------------------
--   Utility Functions      --
------------------------------

local function GetPlayerCount()
  if GetNumRaidMembers() > 0 then
    return GetNumRaidMembers()
  elseif GetNumPartyMembers() > 0 then
    return GetNumPartyMembers() + 1 -- +1 for player
  else
    return 1 -- solo
  end
end

local function IsInGroupOrRaid()
  return GetNumRaidMembers() > 0 or GetNumPartyMembers() > 0
end

------------------------------
--   Frame Creation         --
------------------------------

function AddonAudit.CreateFrame()
  if getglobal("OGRH_AddonAuditFrame") then
    return
  end
  
  -- Main frame
  local frame = CreateFrame("Frame", "OGRH_AddonAuditFrame", UIParent)
  frame:SetWidth(FRAME_WIDTH)
  frame:SetHeight(FRAME_HEIGHT)
  frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  frame:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 4, right = 4, top = 4, bottom = 4 }
  })
  frame:SetBackdropColor(0, 0, 0, 0.9)
  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function() this:StartMoving() end)
  frame:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
  frame:SetFrameStrata("HIGH")
  frame:Hide()
  
  -- Header
  local header = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  header:SetPoint("TOP", frame, "TOP", 0, -10)
  header:SetText("|cff00ff00Addon Audit|r")
  
  -- Close button
  local closeBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  closeBtn:SetWidth(60)
  closeBtn:SetHeight(20)
  closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -8)
  closeBtn:SetText("Close")
  OGRH.StyleButton(closeBtn)
  closeBtn:SetScript("OnClick", function()
    OGRH_AddonAuditFrame:Hide()
  end)
  
  -- Left Panel (Addon List)
  local leftPanel = CreateFrame("Frame", "OGRH_AddonAuditLeftPanel", frame)
  local leftPanelWidth = LEFT_PANEL_WIDTH
  local leftPanelHeight = FRAME_HEIGHT - 80
  leftPanel:SetWidth(leftPanelWidth)
  leftPanel:SetHeight(leftPanelHeight)
  leftPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", PANEL_PADDING, -40)
  
  -- Create styled scroll list using standardized function
  local listFrame, scrollFrame, scrollChild, scrollBar, contentWidth = OGRH.CreateStyledScrollList(leftPanel, leftPanelWidth, leftPanelHeight)
  listFrame:SetAllPoints(leftPanel)
  
  leftPanel.scrollFrame = scrollFrame
  leftPanel.scrollChild = scrollChild
  leftPanel.scrollBar = scrollBar
  leftPanel.contentWidth = contentWidth
  
  local leftHeader = leftPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  leftHeader:SetPoint("TOP", leftPanel, "TOP", 0, -8)
  leftHeader:SetText("|cffffffffAddons to Audit|r")
  
  -- Create scrollable addon list
  AddonAudit.CreateAddonListItems(leftPanel)
  
  -- Right Panel (Results)
  local rightPanel = CreateFrame("Frame", "OGRH_AddonAuditRightPanel", frame)
  rightPanel:SetWidth(FRAME_WIDTH - LEFT_PANEL_WIDTH - (PANEL_PADDING * 3))
  rightPanel:SetHeight(FRAME_HEIGHT - 80)
  rightPanel:SetPoint("TOPLEFT", leftPanel, "TOPRIGHT", PANEL_PADDING, 0)
  rightPanel:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 2, right = 2, top = 2, bottom = 2 }
  })
  rightPanel:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
  
  local rightHeader = rightPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  rightHeader:SetPoint("TOP", rightPanel, "TOP", 0, -8)
  rightHeader:SetText("|cffffffffSelect an addon to audit|r")
  rightPanel.header = rightHeader
  
  -- Results scroll frame
  local scrollFrame = CreateFrame("ScrollFrame", "OGRH_AddonAuditScrollFrame", rightPanel, "UIPanelScrollFrameTemplate")
  scrollFrame:SetWidth(rightPanel:GetWidth() - 30)
  scrollFrame:SetHeight(rightPanel:GetHeight() - 80)
  scrollFrame:SetPoint("TOP", rightPanel, "TOP", -10, -35)
  
  local scrollChild = CreateFrame("Frame", "OGRH_AddonAuditScrollChild", scrollFrame)
  scrollChild:SetWidth(scrollFrame:GetWidth() - 20)
  scrollChild:SetHeight(1)
  scrollFrame:SetScrollChild(scrollChild)
  scrollFrame:Hide()
  
  rightPanel.scrollFrame = scrollFrame
  rightPanel.scrollChild = scrollChild
  
  -- Refresh button
  local refreshBtn = CreateFrame("Button", "OGRH_AddonAuditRefreshBtn", rightPanel, "UIPanelButtonTemplate")
  refreshBtn:SetWidth(100)
  refreshBtn:SetHeight(BUTTON_HEIGHT)
  refreshBtn:SetPoint("BOTTOM", rightPanel, "BOTTOM", 0, 10)
  refreshBtn:SetText("Refresh")
  OGRH.StyleButton(refreshBtn)
  refreshBtn:SetScript("OnClick", function()
    AddonAudit.RefreshResults()
  end)
  refreshBtn:Hide()
  rightPanel.refreshBtn = refreshBtn
  
  -- Status text
  local statusText = rightPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  statusText:SetPoint("CENTER", rightPanel, "CENTER", 0, 0)
  statusText:SetText("")
  rightPanel.statusText = statusText
  
  frame.leftPanel = leftPanel
  frame.rightPanel = rightPanel
end

------------------------------
--   Addon List Items       --
------------------------------

function AddonAudit.CreateAddonListItems(parentFrame)
  local scrollChild = parentFrame.scrollChild
  local contentWidth = parentFrame.contentWidth
  local yOffset = 0
  local rowHeight = OGRH.LIST_ITEM_HEIGHT
  local rowSpacing = OGRH.LIST_ITEM_SPACING
  
  for i, addon in ipairs(addonList) do
    local btn = OGRH.CreateStyledListItem(scrollChild, contentWidth, rowHeight, "Button")
    btn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -5 - yOffset)
    
    local text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("LEFT", btn, "LEFT", 5, 0)
    text:SetText(addon.displayName)
    btn.text = text
    
    btn.addonData = addon
    btn:SetScript("OnClick", function()
      AddonAudit.SelectAddon(this.addonData)
      
      -- Update selection highlight
      for _, otherBtn in ipairs(scrollChild.buttons or {}) do
        OGRH.SetListItemSelected(otherBtn, false)
      end
      OGRH.SetListItemSelected(this, true)
    end)
    
    if not scrollChild.buttons then
      scrollChild.buttons = {}
    end
    table.insert(scrollChild.buttons, btn)
    
    yOffset = yOffset + rowHeight + rowSpacing
  end
  
  -- Update scroll child height
  local contentHeight = yOffset + 5
  scrollChild:SetHeight(contentHeight)
  
  -- Update scrollbar
  local scrollFrameHeight = parentFrame.scrollFrame:GetHeight()
  if contentHeight > scrollFrameHeight then
    parentFrame.scrollBar:SetMinMaxValues(0, contentHeight - scrollFrameHeight)
    parentFrame.scrollBar:Show()
  else
    parentFrame.scrollBar:Hide()
  end
end

------------------------------
--   Addon Selection        --
------------------------------

function AddonAudit.SelectAddon(addon)
  selectedAddon = addon
  
  -- Update button highlights
  for i = 1, table.getn(addonList) do
    local btn = getglobal("OGRH_AddonListItem" .. i)
    if btn then
      if btn.addonData == addon then
        btn:SetBackdropColor(0.1, 0.4, 0.1, 0.9)
      else
        btn:SetBackdropColor(0.2, 0.2, 0.2, 0.8)
      end
    end
  end
  
  -- Update right panel
  local rightPanel = OGRH_AddonAuditFrame.rightPanel
  
  -- Check if addon is available
  if not addon or not addon.displayName or not addon.checkFunction then
    rightPanel.header:SetText("|cffffffffAddon Audit|r")
    rightPanel.statusText:SetText("|cffff0000Addon not found or invalid.|r")
    rightPanel.scrollFrame:Hide()
    rightPanel.refreshBtn:Hide()
    return
  end
  
  rightPanel.header:SetText("|cffffffff" .. addon.displayName .. " Audit|r")
  
  if not addon.checkFunction() then
    rightPanel.statusText:SetText("|cffff0000" .. addon.displayName .. " is not installed or not loaded.|r")
    rightPanel.scrollFrame:Hide()
    rightPanel.refreshBtn:Hide()
    return
  end
  
  -- Check if in group/raid
  if not IsInGroupOrRaid() then
    rightPanel.statusText:SetText("|cffffff00You must be in a party or raid to query addon versions.|r")
    rightPanel.scrollFrame:Hide()
    rightPanel.refreshBtn:Hide()
    return
  end
  
  -- Show results
  rightPanel.statusText:SetText("")
  rightPanel.scrollFrame:Show()
  rightPanel.refreshBtn:Show()
  
  -- Query the addon
  AddonAudit.RefreshResults()
end

------------------------------
--   Query & Display        --
------------------------------

function AddonAudit.RefreshResults()
  if not selectedAddon then return end
  if not IsInGroupOrRaid() then return end
  
  local rightPanel = OGRH_AddonAuditFrame.rightPanel
  
  -- Start query
  rightPanel.statusText:SetText("|cffffff00Querying raid members...|r")
  queryInProgress = true
  
  if selectedAddon.queryFunction then
    selectedAddon.queryFunction()
  end
  
  -- Wait a moment for responses, then display (5 seconds matches BigWigs query time)
  local waitFrame = CreateFrame("Frame")
  waitFrame.elapsed = 0
  waitFrame:SetScript("OnUpdate", function()
    waitFrame.elapsed = waitFrame.elapsed + arg1
    if waitFrame.elapsed > 5 then
      AddonAudit.DisplayResults()
      queryInProgress = false
      waitFrame:SetScript("OnUpdate", nil)
    end
  end)
end

function AddonAudit.DisplayResults()
  if not selectedAddon then return end
  
  local rightPanel = OGRH_AddonAuditFrame.rightPanel
  local scrollChild = rightPanel.scrollChild
  
  -- Clear previous results - properly destroy all font strings
  if scrollChild.resultItems then
    for _, item in ipairs(scrollChild.resultItems) do
      item:SetText("")
      item:Hide()
    end
  end
  scrollChild.resultItems = {}
  
  rightPanel.statusText:SetText("")
  
  -- Get results
  local responseTable, pepoResponseTable = selectedAddon.getResultsFunction()
  if not responseTable then
    rightPanel.statusText:SetText("|cffff0000Unable to retrieve results.|r")
    return
  end
  
  -- Get all raid members to check who didn't respond
  local allRaidMembers = {}
  if GetNumRaidMembers() > 0 then
    for i = 1, GetNumRaidMembers() do
      local name = GetRaidRosterInfo(i)
      if name then
        allRaidMembers[name] = true
      end
    end
  end
  
  -- Categorize players
  local noAddon = {}
  local withAddon = {}
  local offline = {}
  
  -- Check everyone in the raid
  for name in pairs(allRaidMembers) do
    local version = responseTable[name]
    -- Use appropriate responded table based on addon
    local hasResponded = false
    if AddonAudit.bwResponded and AddonAudit.bwResponded[name] ~= nil then
      hasResponded = AddonAudit.bwResponded[name]
    elseif AddonAudit.twtResponded and AddonAudit.twtResponded[name] ~= nil then
      hasResponded = AddonAudit.twtResponded[name]
    end
    
    if version == -2 then
      -- Offline
      table.insert(offline, name)
    elseif not hasResponded or version == -1 or version == nil then
      -- No response = no addon, or -1 = N/A/no zone module
      table.insert(noAddon, name)
    elseif hasResponded and version ~= nil then
      -- Has addon (they responded with a version, even if 0)
      local isPepo = pepoResponseTable and pepoResponseTable[name]
      table.insert(withAddon, {
        name = name,
        version = version,
        isPepo = isPepo
      })
    else
      -- Unknown/other state, treat as no addon
      table.insert(noAddon, name)
    end
  end
  
  -- Sort
  table.sort(noAddon)
  table.sort(offline)
  table.sort(withAddon, function(a, b)
    if a.version ~= b.version then
      return a.version > b.version
    end
    return a.name < b.name
  end)
  
  -- Display
  local yOffset = -10
  
  -- Without addon section
  if table.getn(noAddon) > 0 then
    yOffset = AddonAudit.CreateSectionHeader(scrollChild, yOffset, "Players WITHOUT " .. selectedAddon.displayName .. " (" .. table.getn(noAddon) .. ")")
    for _, name in ipairs(noAddon) do
      yOffset = AddonAudit.CreatePlayerItem(scrollChild, yOffset, name, nil, false)
    end
    yOffset = yOffset - 10
  end
  
  -- With addon section
  if table.getn(withAddon) > 0 then
    yOffset = AddonAudit.CreateSectionHeader(scrollChild, yOffset, "Players WITH " .. selectedAddon.displayName .. " (" .. table.getn(withAddon) .. ")")
    for _, player in ipairs(withAddon) do
      yOffset = AddonAudit.CreatePlayerItem(scrollChild, yOffset, player.name, player.version, player.isPepo)
    end
    yOffset = yOffset - 10
  end
  
  -- Offline section
  if table.getn(offline) > 0 then
    yOffset = AddonAudit.CreateSectionHeader(scrollChild, yOffset, "Offline Players (" .. table.getn(offline) .. ")")
    for _, name in ipairs(offline) do
      yOffset = AddonAudit.CreatePlayerItem(scrollChild, yOffset, name, "Offline", false)
    end
  end
  
  -- Update scroll child height
  scrollChild:SetHeight(math.abs(yOffset) + 20)
end

function AddonAudit.CreateSectionHeader(parent, yOffset, text)
  local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  header:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, yOffset)
  header:SetText("|cff00ff00" .. text .. "|r")
  
  -- Store for cleanup
  if not parent.resultItems then
    parent.resultItems = {}
  end
  table.insert(parent.resultItems, header)
  
  return yOffset - 25
end

function AddonAudit.CreatePlayerItem(parent, yOffset, name, version, isPepo)
  local item = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  item:SetPoint("TOPLEFT", parent, "TOPLEFT", 20, yOffset)
  
  local text = name
  if version then
    if version == "Offline" then
      text = text .. " - |cff808080Offline|r"
    elseif isPepo then
      text = text .. " - |cff00ff00Pepo " .. version .. "|r"
    else
      text = text .. " - |cffffffff" .. version .. "|r"
    end
  else
    text = text .. " - |cffff0000Not Installed|r"
  end
  
  item:SetText(text)
  
  -- Store for cleanup
  if not parent.resultItems then
    parent.resultItems = {}
  end
  table.insert(parent.resultItems, item)
  
  return yOffset - 18
end

------------------------------
--   Public API             --
------------------------------

function OGRH.ShowAddonAudit()
  OGRH.CloseAllWindows("OGRH_AddonAuditFrame")
  
  -- Create frame if needed
  if not getglobal("OGRH_AddonAuditFrame") then
    AddonAudit.CreateFrame()
  end
  
  -- Show frame
  OGRH_AddonAuditFrame:Show()
end
