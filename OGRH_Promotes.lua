-- OGRH_Promotes.lua
-- Auto-promote system for automatically giving assistant rank to specific players

local _G = getfenv(0)
local OGRH = _G.OGRH

-- Ensure SavedVariables structure
local function EnsurePromotesSV()
  OGRH.EnsureSV()
  if not OGRH_SV.autoPromotes then
    OGRH_SV.autoPromotes = {}
  end
  -- Migrate old string format to new table format
  for i, entry in ipairs(OGRH_SV.autoPromotes) do
    if type(entry) == "string" then
      -- Get class for this player
      local class = GetClassColor(entry)
      OGRH_SV.autoPromotes[i] = {name = entry, class = nil}  -- Class will be updated on next refresh
    end
  end
end

-- Get class color for a player name
local function GetClassColor(name)
  -- Try to get class from current raid roster
  local numRaidMembers = GetNumRaidMembers()
  if numRaidMembers > 0 then
    for i = 1, numRaidMembers do
      local raidName, _, _, _, class = GetRaidRosterInfo(i)
      if raidName == name and class then
        local color = RAID_CLASS_COLORS[class]
        if color then
          return color.r, color.g, color.b
        end
      end
    end
  end
  
  -- Try to get from saved role data (has class info)
  if OGRH.Roles and OGRH.Roles.nameClass and OGRH.Roles.nameClass[name] then
    local class = OGRH.Roles.nameClass[name]
    local color = RAID_CLASS_COLORS[class]
    if color then
      return color.r, color.g, color.b
    end
  end
  
  -- Default to white
  return 1, 1, 1
end

-- Auto-promote logic
local function CheckAndPromotePlayers()
  EnsurePromotesSV()
  
  -- Only run if we're raid leader
  local numRaidMembers = GetNumRaidMembers()
  if numRaidMembers == 0 then
    return
  end
  
  local playerName = UnitName("player")
  local isLeader = false
  
  for i = 1, numRaidMembers do
    local name, rank = GetRaidRosterInfo(i)
    if name == playerName and rank == 2 then
      isLeader = true
      break
    end
  end
  
  if not isLeader then
    return
  end
  
  -- Check each raid member
  for i = 1, numRaidMembers do
    local name, rank = GetRaidRosterInfo(i)
    if name and rank == 0 then  -- Regular member (not leader or assistant)
      -- Check if they're in the auto-promote list
      for _, promoteEntry in ipairs(OGRH_SV.autoPromotes) do
        local promoteName = type(promoteEntry) == "table" and promoteEntry.name or promoteEntry
        if name == promoteName then
          -- Promote them
          PromoteToAssistant("raid"..i)
          OGRH.Msg("Auto-promoted " .. name .. " to assistant.")
          break
        end
      end
    end
  end
end

-- Event handler for raid roster updates
local promoteFrame = CreateFrame("Frame")
promoteFrame:RegisterEvent("RAID_ROSTER_UPDATE")
promoteFrame:SetScript("OnEvent", function()
  if event == "RAID_ROSTER_UPDATE" then
    -- Delay check slightly to ensure roster is updated
    local delayFrame = CreateFrame("Frame")
    delayFrame.elapsed = 0
    delayFrame:SetScript("OnUpdate", function()
      delayFrame.elapsed = delayFrame.elapsed + arg1
      if delayFrame.elapsed >= 0.5 then
        CheckAndPromotePlayers()
        delayFrame:SetScript("OnUpdate", nil)
      end
    end)
  end
end)

-- Show Auto Promote settings window
function OGRH.ShowAutoPromote()
  EnsurePromotesSV()
  OGRH.CloseAllWindows("OGRH_AutoPromoteFrame")
  
  if OGRH_AutoPromoteFrame then
    OGRH_AutoPromoteFrame:Show()
    OGRH.RefreshAutoPromote()
    return
  end
  
  local frame = CreateFrame("Frame", "OGRH_AutoPromoteFrame", UIParent)
  frame:SetWidth(500)
  frame:SetHeight(450)
  frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  frame:SetFrameStrata("DIALOG")
  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function() frame:StartMoving() end)
  frame:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
  
  -- Backdrop
  frame:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 12,
    insets = {left = 4, right = 4, top = 4, bottom = 4}
  })
  frame:SetBackdropColor(0, 0, 0, 0.85)
  
  -- Title
  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOP", 0, -15)
  title:SetText("Auto Promote")
  
  -- Close button
  local closeBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  closeBtn:SetWidth(60)
  closeBtn:SetHeight(24)
  closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -10)
  closeBtn:SetText("Close")
  closeBtn:SetScript("OnClick", function() frame:Hide() end)
  OGRH.StyleButton(closeBtn)
  
  -- Instructions
  local instructions = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  instructions:SetPoint("TOPLEFT", 20, -45)
  instructions:SetText("Drag players from the raid list to auto-promote them:")
  
  -- === LEFT SIDE: Auto-Promote List ===
  local leftBackdrop = CreateFrame("Frame", nil, frame)
  leftBackdrop:SetPoint("TOPLEFT", 17, -75)
  leftBackdrop:SetPoint("BOTTOMLEFT", 17, 10)
  leftBackdrop:SetWidth(230)
  leftBackdrop:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 12,
    insets = {left = 3, right = 3, top = 3, bottom = 3}
  })
  leftBackdrop:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
  
  -- Left list title
  local leftTitle = leftBackdrop:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  leftTitle:SetPoint("TOP", leftBackdrop, "TOP", 0, -8)
  leftTitle:SetText("Auto-Promote List")
  leftTitle:SetTextColor(1, 0.82, 0)
  
  -- Create a container frame for the list that fills available space
  local leftListContainer = CreateFrame("Frame", nil, leftBackdrop)
  leftListContainer:SetPoint("TOP", leftTitle, "BOTTOM", 0, -5)
  leftListContainer:SetPoint("LEFT", leftBackdrop, "LEFT", 10, 0)
  leftListContainer:SetPoint("RIGHT", leftBackdrop, "RIGHT", -10, 0)
  leftListContainer:SetPoint("BOTTOM", leftBackdrop, "BOTTOM", 0, 10)
  
  -- Create styled scroll list using standardized function
  local leftListFrame, leftScrollFrame, leftScrollChild, leftScrollBar, leftContentWidth = OGRH.CreateStyledScrollList(leftListContainer, 210, leftListContainer:GetHeight())
  leftListFrame:SetAllPoints(leftListContainer)
  
  frame.leftScrollChild = leftScrollChild
  frame.leftScrollFrame = leftScrollFrame
  frame.leftScrollBar = leftScrollBar
  frame.leftContentWidth = leftContentWidth
  
  -- === RIGHT SIDE: Players Panel ===
  local rightBackdrop = CreateFrame("Frame", nil, frame)
  rightBackdrop:SetPoint("TOPRIGHT", -17, -75)
  rightBackdrop:SetPoint("BOTTOMRIGHT", -17, 10)
  rightBackdrop:SetWidth(230)
  rightBackdrop:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 12,
    insets = {left = 3, right = 3, top = 3, bottom = 3}
  })
  rightBackdrop:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
  
  -- Right list title
  local rightTitle = rightBackdrop:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  rightTitle:SetPoint("TOP", rightBackdrop, "TOP", 0, -8)
  rightTitle:SetText("Players")
  rightTitle:SetTextColor(1, 0.82, 0)
  
  -- Search box for player list
  local searchBox = CreateFrame("EditBox", nil, rightBackdrop)
  searchBox:SetWidth(200)
  searchBox:SetHeight(24)
  searchBox:SetPoint("TOP", rightTitle, "BOTTOM", 0, -3)
  searchBox:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 12,
    insets = {left = 3, right = 3, top = 3, bottom = 3}
  })
  searchBox:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
  searchBox:SetFontObject(GameFontNormal)
  searchBox:SetAutoFocus(false)
  searchBox:SetText("")
  searchBox:SetScript("OnEscapePressed", function() this:ClearFocus() end)
  searchBox:SetScript("OnEnterPressed", function() this:ClearFocus() end)
  searchBox:SetScript("OnTextChanged", function()
    if OGRH.RefreshAutoPromote then
      OGRH.RefreshAutoPromote()
    end
  end)
  frame.playerSearchBox = searchBox
  
  -- Search placeholder text
  local searchPlaceholder = searchBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  searchPlaceholder:SetPoint("LEFT", searchBox, "LEFT", 5, 0)
  searchPlaceholder:SetText("|cff888888Search...|r")
  searchPlaceholder:SetTextColor(0.5, 0.5, 0.5)
  
  searchBox:SetScript("OnEditFocusGained", function()
    searchPlaceholder:Hide()
  end)
  
  searchBox:SetScript("OnEditFocusLost", function()
    if searchBox:GetText() == "" then
      searchPlaceholder:Show()
    end
  end)
  
  -- Create a container frame for the right list that fills available space
  local rightListContainer = CreateFrame("Frame", nil, rightBackdrop)
  rightListContainer:SetPoint("TOP", searchBox, "BOTTOM", 0, -3)
  rightListContainer:SetPoint("LEFT", rightBackdrop, "LEFT", 10, 0)
  rightListContainer:SetPoint("RIGHT", rightBackdrop, "RIGHT", -10, 0)
  rightListContainer:SetPoint("BOTTOM", rightBackdrop, "BOTTOM", 0, 10)
  
  -- Create styled scroll list using standardized function
  local rightListFrame, rightScrollFrame, rightScrollChild, rightScrollBar, rightContentWidth = OGRH.CreateStyledScrollList(rightListContainer, 210, rightListContainer:GetHeight())
  rightListFrame:SetAllPoints(rightListContainer)
  
  frame.rightScrollChild = rightScrollChild
  frame.rightScrollFrame = rightScrollFrame
  frame.rightScrollBar = rightScrollBar
  frame.rightContentWidth = rightContentWidth
  
  frame:Show()
  OGRH.RefreshAutoPromote()
end

-- Refresh the auto promote lists
function OGRH.RefreshAutoPromote()
  if not OGRH_AutoPromoteFrame then return end
  
  EnsurePromotesSV()
  
  local leftScrollChild = OGRH_AutoPromoteFrame.leftScrollChild
  local rightScrollChild = OGRH_AutoPromoteFrame.rightScrollChild
  
  -- Clear existing rows
  if leftScrollChild.rows then
    for _, row in ipairs(leftScrollChild.rows) do
      row:Hide()
      row:SetParent(nil)
    end
  end
  leftScrollChild.rows = {}
  
  if rightScrollChild.rows then
    for _, row in ipairs(rightScrollChild.rows) do
      row:Hide()
      row:SetParent(nil)
    end
  end
  rightScrollChild.rows = {}
  
  local rowHeight = OGRH.LIST_ITEM_HEIGHT
  local rowSpacing = OGRH.LIST_ITEM_SPACING
  
  -- Sort promote list alphabetically
  local promoteList = {}
  for _, entry in ipairs(OGRH_SV.autoPromotes) do
    local playerName = type(entry) == "table" and entry.name or entry
    local playerClass = type(entry) == "table" and entry.class or nil
    
    -- Try to get class if not stored
    if not playerClass then
      local r, g, b = GetClassColor(playerName)
      -- If GetClassColor returned something, try to find class from roster
      local numRaidMembers = GetNumRaidMembers()
      if numRaidMembers > 0 then
        for j = 1, numRaidMembers do
          local name, _, _, _, class = GetRaidRosterInfo(j)
          if name == playerName and class then
            playerClass = string.upper(class)
            break
          end
        end
      end
      -- Try guild roster
      if not playerClass then
        local numGuildMembers = GetNumGuildMembers(true)
        for j = 1, numGuildMembers do
          local name, _, _, _, class = GetGuildRosterInfo(j)
          if name == playerName and class then
            playerClass = string.upper(class)
            break
          end
        end
      end
    end
    
    table.insert(promoteList, {name = playerName, class = playerClass})
  end
  table.sort(promoteList, function(a, b) return string.upper(a.name) < string.upper(b.name) end)
  
  -- === LEFT LIST: Auto-Promote Players ===
  local yOffset = -5
  for i, playerData in ipairs(promoteList) do
    local playerName = playerData.name
    local playerClass = playerData.class
    
    -- Create styled list item
    local row = OGRH.CreateStyledListItem(leftScrollChild, OGRH_AutoPromoteFrame.leftContentWidth, rowHeight, "Button")
    row:SetPoint("TOPLEFT", leftScrollChild, "TOPLEFT", 0, yOffset)
    row:RegisterForDrag("LeftButton")
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    
    -- Player name with class color
    local classColor = playerClass and RAID_CLASS_COLORS[playerClass] or {r=1, g=1, b=1}
    local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameText:SetPoint("LEFT", row, "LEFT", 5, 0)
    nameText:SetTextColor(classColor.r, classColor.g, classColor.b)
    nameText:SetText(playerName)
    
    -- Delete button
    local deleteBtn = CreateFrame("Button", nil, row)
    deleteBtn:SetWidth(16)
    deleteBtn:SetHeight(16)
    deleteBtn:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    
    local deleteIcon = deleteBtn:CreateTexture(nil, "ARTWORK")
    deleteIcon:SetWidth(16)
    deleteIcon:SetHeight(16)
    deleteIcon:SetAllPoints(deleteBtn)
    deleteIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    deleteIcon:SetTexCoord(0.5, 0.75, 0.25, 0.5)  -- Cross/X icon
    
    local deleteHighlight = deleteBtn:CreateTexture(nil, "HIGHLIGHT")
    deleteHighlight:SetWidth(16)
    deleteHighlight:SetHeight(16)
    deleteHighlight:SetAllPoints(deleteBtn)
    deleteHighlight:SetTexture("Interface\\Buttons\\UI-Common-MouseHilight")
    deleteHighlight:SetBlendMode("ADD")
    
    local idx = i
    deleteBtn:SetScript("OnClick", function()
      table.remove(OGRH_SV.autoPromotes, idx)
      OGRH.RefreshAutoPromote()
    end)
    
    table.insert(leftScrollChild.rows, row)
    yOffset = yOffset - rowHeight - rowSpacing
  end
  
  -- Update left scroll child height
  local leftContentHeight = math.max(1, table.getn(promoteList) * (rowHeight + rowSpacing) + 10)
  leftScrollChild:SetHeight(leftContentHeight)
  
  -- Update left scrollbar
  local leftVisibleHeight = OGRH_AutoPromoteFrame.leftScrollFrame:GetHeight()
  if leftContentHeight > leftVisibleHeight then
    OGRH_AutoPromoteFrame.leftScrollBar:SetMinMaxValues(0, leftContentHeight - leftVisibleHeight)
    OGRH_AutoPromoteFrame.leftScrollBar:Show()
  else
    OGRH_AutoPromoteFrame.leftScrollBar:Hide()
  end
  
  -- === RIGHT LIST: Players (In Raid / Online / Offline) ===
  local raidPlayers = {}
  local onlinePlayers = {}
  local offlinePlayers = {}
  
  -- Get search text
  local searchText = ""
  if OGRH_AutoPromoteFrame.playerSearchBox then
    searchText = string.lower(OGRH_AutoPromoteFrame.playerSearchBox:GetText() or "")
  end
  
  -- Get raid members
  local numRaidMembers = GetNumRaidMembers()
  if numRaidMembers > 0 then
    for i = 1, numRaidMembers do
      local name, _, _, _, class = GetRaidRosterInfo(i)
      if name and class then
        -- Apply search filter
        if searchText == "" or string.find(string.lower(name), searchText, 1, true) then
          -- Don't show players already in the promote list
          local alreadyInList = false
          for _, promoteEntry in ipairs(OGRH_SV.autoPromotes) do
            local promoteName = type(promoteEntry) == "table" and promoteEntry.name or promoteEntry
            if name == promoteName then
              alreadyInList = true
              break
            end
          end
          
          if not alreadyInList then
            table.insert(raidPlayers, {name = name, class = string.upper(class), section = "raid"})
          end
        end
      end
    end
  end
  
  -- Build a set of raid member names for deduplication
  local raidNames = {}
  for _, p in ipairs(raidPlayers) do
    raidNames[p.name] = true
  end
  
  -- Get guild members (level 60 only)
  local numGuildMembers = GetNumGuildMembers(true)
  for i = 1, numGuildMembers do
    local name, _, _, level, class, _, _, _, online = GetGuildRosterInfo(i)
    if name and level == 60 and class and not raidNames[name] then
      -- Apply search filter
      if searchText == "" or string.find(string.lower(name), searchText, 1, true) then
        -- Don't show players already in the promote list
        local alreadyInList = false
        for _, promoteEntry in ipairs(OGRH_SV.autoPromotes) do
          local promoteName = type(promoteEntry) == "table" and promoteEntry.name or promoteEntry
          if name == promoteName then
            alreadyInList = true
            break
          end
        end
        
        if not alreadyInList then
          if online then
            table.insert(onlinePlayers, {name = name, class = string.upper(class), section = "online"})
          else
            table.insert(offlinePlayers, {name = name, class = string.upper(class), section = "offline"})
          end
        end
      end
    end
  end
  
  -- Sort each section alphabetically
  table.sort(raidPlayers, function(a, b) return string.upper(a.name) < string.upper(b.name) end)
  table.sort(onlinePlayers, function(a, b) return string.upper(a.name) < string.upper(b.name) end)
  table.sort(offlinePlayers, function(a, b) return string.upper(a.name) < string.upper(b.name) end)
  
  -- Combine all sections
  local allPlayers = {}
  for _, p in ipairs(raidPlayers) do
    table.insert(allPlayers, p)
  end
  for _, p in ipairs(onlinePlayers) do
    table.insert(allPlayers, p)
  end
  for _, p in ipairs(offlinePlayers) do
    table.insert(allPlayers, p)
  end
  
  yOffset = -5
  local lastSection = nil
  
  for _, memberData in ipairs(allPlayers) do
    -- Add section header if section changed
    if memberData.section ~= lastSection then
      local sectionLabel = ""
      if memberData.section == "raid" then
        sectionLabel = "In Raid"
      elseif memberData.section == "online" then
        sectionLabel = "Online"
      elseif memberData.section == "offline" then
        sectionLabel = "Offline"
      end
      
      if sectionLabel ~= "" then
        local headerFrame = CreateFrame("Frame", nil, rightScrollChild)
        headerFrame:SetWidth(OGRH_AutoPromoteFrame.rightContentWidth)
        headerFrame:SetHeight(16)
        headerFrame:SetPoint("TOPLEFT", rightScrollChild, "TOPLEFT", 0, yOffset)
        
        local headerText = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        headerText:SetPoint("LEFT", headerFrame, "LEFT", 5, 0)
        headerText:SetText("|cffaaaaaa" .. sectionLabel .. "|r")
        
        table.insert(rightScrollChild.rows, headerFrame)
        yOffset = yOffset - 18
      end
      
      lastSection = memberData.section
    end
    
    -- Create styled list item
    local row = OGRH.CreateStyledListItem(rightScrollChild, OGRH_AutoPromoteFrame.rightContentWidth, rowHeight, "Button")
    row:SetPoint("TOPLEFT", rightScrollChild, "TOPLEFT", 0, yOffset)
    row:RegisterForDrag("LeftButton")
    row:RegisterForClicks("LeftButtonUp")
    
    -- Player name with class color
    local classColor = RAID_CLASS_COLORS[memberData.class] or {r=1, g=1, b=1}
    local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameText:SetPoint("LEFT", row, "LEFT", 5, 0)
    nameText:SetTextColor(classColor.r, classColor.g, classColor.b)
    nameText:SetText(memberData.name)
    
    -- Drag to add to promote list
    local playerName = memberData.name
    local playerClass = memberData.class
    row:SetScript("OnDragStart", function()
      -- Add to promote list
      table.insert(OGRH_SV.autoPromotes, {name = playerName, class = playerClass})
      OGRH.RefreshAutoPromote()
      OGRH.Msg(playerName .. " added to auto-promote list.")
    end)
    
    -- Click to add
    row:SetScript("OnClick", function()
      table.insert(OGRH_SV.autoPromotes, {name = playerName, class = playerClass})
      OGRH.RefreshAutoPromote()
      OGRH.Msg(playerName .. " added to auto-promote list.")
    end)
    
    table.insert(rightScrollChild.rows, row)
    yOffset = yOffset - rowHeight - rowSpacing
  end
  
  -- Update right scroll child height
  -- Calculate total height including headers
  local totalRows = table.getn(allPlayers)
  local numSections = 0
  local tempSection = nil
  for _, p in ipairs(allPlayers) do
    if p.section ~= tempSection then
      numSections = numSections + 1
      tempSection = p.section
    end
  end
  local rightContentHeight = math.max(1, totalRows * (rowHeight + rowSpacing) + (numSections * 18) + 10)
  rightScrollChild:SetHeight(rightContentHeight)
  
  -- Update right scrollbar
  local rightVisibleHeight = OGRH_AutoPromoteFrame.rightScrollFrame:GetHeight()
  if rightContentHeight > rightVisibleHeight then
    OGRH_AutoPromoteFrame.rightScrollBar:SetMinMaxValues(0, rightContentHeight - rightVisibleHeight)
    OGRH_AutoPromoteFrame.rightScrollBar:Show()
  else
    OGRH_AutoPromoteFrame.rightScrollBar:Hide()
  end
end

-- Export to OGRH namespace
OGRH.Promotes = {
  CheckAndPromotePlayers = CheckAndPromotePlayers
}

OGRH.Msg("Auto Promote module loaded.")
