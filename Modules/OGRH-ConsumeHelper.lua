-- OGRH-ConsumeHelper.lua
-- Module for managing consume tracking and configuration
-- Part of OG-RaidHelper

if not OGRH then
  DEFAULT_CHAT_FRAME:AddMessage("|cffff0000Error: OGRH-ConsumeHelper requires OGRH_Core to be loaded first!|r")
  return
end

-- Create namespace
OGRH.ConsumeHelper = OGRH.ConsumeHelper or {}
local ConsumeHelper = OGRH.ConsumeHelper

-- Initialize saved variables (separate from main OGRH data to avoid sync/checksum issues)
local function InitializeSavedVariables()
  -- If no saved variables exist, load factory defaults
  if not OGRH_ConsumeHelper_SV then
    if OGRH_ConsumeHelper_FactoryDefaults then
      OGRH_ConsumeHelper_SV = OGRH_ConsumeHelper_FactoryDefaults
      OGRH.Msg("Consume Helper: Loaded factory defaults for new character")
    else
      OGRH_ConsumeHelper_SV = {}
    end
  end
  
  -- Ensure all keys exist (in case saved variables existed from older version)
  OGRH_ConsumeHelper_SV.setupConsumes = OGRH_ConsumeHelper_SV.setupConsumes or {}
  OGRH_ConsumeHelper_SV.playerRoles = OGRH_ConsumeHelper_SV.playerRoles or {}
  OGRH_ConsumeHelper_SV.consumes = OGRH_ConsumeHelper_SV.consumes or {}
  
  -- Deduplicate setupConsumes
  local seen = {}
  local deduplicated = {}
  for _, itemId in ipairs(OGRH_ConsumeHelper_SV.setupConsumes) do
    if not seen[itemId] then
      seen[itemId] = true
      table.insert(deduplicated, itemId)
    end
  end
  OGRH_ConsumeHelper_SV.setupConsumes = deduplicated
  
  -- Migration: If setupConsumes exists in main data structure, migrate it
  if ConsumeHelper.data and ConsumeHelper.data.setupConsumes then
    -- Migrate data to new saved variable
    if getn(ConsumeHelper.data.setupConsumes) > 0 then
      OGRH_ConsumeHelper_SV.setupConsumes = ConsumeHelper.data.setupConsumes
      OGRH.Msg("Migrated " .. getn(ConsumeHelper.data.setupConsumes) .. " setup consumes to separate saved variable")
    end
    -- Clean up old data
    ConsumeHelper.data.setupConsumes = nil
  end
end

-- Report loaded consumes
local function ReportLoadedConsumes()
  local count = 0
  if OGRH_ConsumeHelper_SV and OGRH_ConsumeHelper_SV.consumes then
    for raidName, raidData in pairs(OGRH_ConsumeHelper_SV.consumes) do
      for className, items in pairs(raidData) do
        count = count + getn(items)
      end
    end
  end
  
  if count > 0 then
    OGRH.Msg("ConsumeHelper: Loaded " .. count .. " saved consume assignments")
  end
end

-- Register event to initialize after SavedVariables are loaded
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:SetScript("OnEvent", function()
  if arg1 == "OG-RaidHelper" then
    InitializeSavedVariables()
    ReportLoadedConsumes()
    this:UnregisterEvent("ADDON_LOADED")
  end
end)

-- Constants
local FRAME_WIDTH = 900
local FRAME_HEIGHT = 500
local SECTION_LIST_WIDTH = 195
local CLASS_LIST_WIDTH = 155
local SELECTED_LIST_WIDTH = 245
local AVAILABLE_LIST_WIDTH = 245
local PANEL_PADDING = 5

-- Class colors
local CLASS_COLORS = {
  ["Druid"] = {r = 1, g = 0.49, b = 0.04},
  ["Hunter"] = {r = 0.67, g = 0.83, b = 0.45},
  ["Mage"] = {r = 0.41, g = 0.8, b = 0.94},
  ["Paladin"] = {r = 0.96, g = 0.55, b = 0.73},
  ["Priest"] = {r = 1, g = 1, b = 1},
  ["Rogue"] = {r = 1, g = 0.96, b = 0.41},
  ["Shaman"] = {r = 0, g = 0.44, b = 0.87},
  ["Warlock"] = {r = 0.58, g = 0.51, b = 0.79},
  ["Warrior"] = {r = 0.78, g = 0.61, b = 0.43}
}

-- Data structure
ConsumeHelper.data = ConsumeHelper.data or {
  selectedRaid = nil,
  selectedClass = nil,
  selectedPlayer = nil,
  viewMode = nil,  -- "setup", "roles", or nil (raid view)
  raids = {
    {name = "General", order = 1},
    {name = "Onyxia", order = 2},
    {name = "ES", order = 3},
    {name = "K10", order = 4},
    {name = "Zul'Garub", order = 5},
    {name = "Molten Core", order = 6},
    {name = "BWL", order = 7},
    {name = "AQ40", order = 8},
    {name = "Naxx", order = 9},
    {name = "K40", order = 10}
  },
  classes = {
    "Druid", "Hunter", "Mage", "Paladin", "Priest", "Rogue", "Shaman", "Warlock", "Warrior"
  },
  roles = {
    "Tank", "Healer", "Melee DPS", "Ranged DPS", "Caster DPS"
  },
  -- NOTE: Consumes are stored directly in OGRH_ConsumeHelper_SV.consumes
  -- Structure: OGRH_ConsumeHelper_SV.consumes[raidName][className] = { {itemId=123, quantity=1}, ... }
  -- Available items that can be added
  availableItems = {}  -- Will be populated with all available consume items
}

-- Helper functions to access playerRoles (directly from saved variables)
local function GetPlayerRoles()
  OGRH_ConsumeHelper_SV.playerRoles = OGRH_ConsumeHelper_SV.playerRoles or {}
  return OGRH_ConsumeHelper_SV.playerRoles
end

local function SavePlayerRole(playerName, roleName, value)
  OGRH_ConsumeHelper_SV.playerRoles = OGRH_ConsumeHelper_SV.playerRoles or {}
  if not OGRH_ConsumeHelper_SV.playerRoles[playerName] then
    OGRH_ConsumeHelper_SV.playerRoles[playerName] = {}
  end
  OGRH_ConsumeHelper_SV.playerRoles[playerName][roleName] = value
end

local function EnsurePlayerExists(playerName, playerClass)
  OGRH_ConsumeHelper_SV.playerRoles = OGRH_ConsumeHelper_SV.playerRoles or {}
  if not OGRH_ConsumeHelper_SV.playerRoles[playerName] then
    OGRH_ConsumeHelper_SV.playerRoles[playerName] = {class = playerClass}
  end
end

------------------------------
--   Frame Creation         --
------------------------------

function ConsumeHelper.CreateFrame()
  if getglobal("OGRH_ConsumeHelperFrame") then
    return
  end
  
  -- Create main window using OGST standards
  local frame = OGST.CreateStandardWindow({
    name = "OGRH_ConsumeHelperFrame",
    width = FRAME_WIDTH,
    height = FRAME_HEIGHT,
    title = "Consume Helper",
    closeButton = true,
    escapeCloses = true,
    closeOnNewWindow = true
  })
  
  if not frame then
    OGRH.Msg("Failed to create Consume Helper window.")
    return
  end
  
  local contentFrame = frame.contentFrame
  
  -- ===== Left Panel: Section List =====
  local leftPanel = CreateFrame("Frame", nil, contentFrame)
  leftPanel:SetWidth(SECTION_LIST_WIDTH)
  leftPanel:SetHeight(FRAME_HEIGHT - 80)
  leftPanel:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, 0)
  
  -- Create styled scroll list using OGST
  local listFrame, scrollFrame, scrollChild, scrollBar, contentWidth = OGST.CreateStyledScrollList(
    leftPanel, 
    SECTION_LIST_WIDTH, 
    FRAME_HEIGHT - 80,
    true  -- Hide scrollbar for cleaner look
  )
  listFrame:SetAllPoints(leftPanel)
  
  leftPanel.scrollFrame = scrollFrame
  leftPanel.scrollChild = scrollChild
  leftPanel.scrollBar = scrollBar
  leftPanel.contentWidth = contentWidth
  
  frame.leftPanel = leftPanel
  
  -- ===== Right Panel: Setup Detail View =====
  local rightPanel = CreateFrame("Frame", nil, contentFrame)
  rightPanel:SetWidth(FRAME_WIDTH - SECTION_LIST_WIDTH - PANEL_PADDING - 25)
  rightPanel:SetHeight(FRAME_HEIGHT - 80)
  rightPanel:SetPoint("TOPLEFT", leftPanel, "TOPRIGHT", PANEL_PADDING, 0)
  rightPanel:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 4, right = 4, top = 4, bottom = 4 }
  })
  rightPanel:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
  
  frame.rightPanel = rightPanel
  
  -- Populate the left list
  ConsumeHelper.PopulateLeftList(frame)
  
  -- Show initial instruction text
  local infoText = rightPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  infoText:SetPoint("CENTER", rightPanel, "CENTER", 0, 0)
  infoText:SetText("|cff888888Select a raid from the left to configure consumes.|r")
  frame.instructionText = infoText
  
  return frame
end

------------------------------
--   Left Panel Population  --
------------------------------

function ConsumeHelper.PopulateLeftList(frame)
  if not frame or not frame.leftPanel then return end
  
  local scrollChild = frame.leftPanel.scrollChild
  local contentWidth = frame.leftPanel.contentWidth
  
  -- Clear existing items
  local children = {scrollChild:GetChildren()}
  for _, child in ipairs(children) do
    child:Hide()
    child:SetParent(nil)
  end
  
  local yOffset = 0
  local rowHeight = OGST.LIST_ITEM_HEIGHT
  local rowSpacing = OGST.LIST_ITEM_SPACING
  
  -- Sort raids by order
  table.sort(ConsumeHelper.data.raids, function(a, b) return a.order < b.order end)
  
  -- Add raid items with up/down/delete controls
  for i, raid in ipairs(ConsumeHelper.data.raids) do
    local item = OGST.CreateStyledListItem(scrollChild, contentWidth, rowHeight, "Button")
    item:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yOffset)
    
    local isSelected = (ConsumeHelper.data.selectedRaid == raid.name and not ConsumeHelper.data.viewMode)
    OGST.SetListItemSelected(item, isSelected)
    
    -- Raid name text
    local text = item:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("LEFT", item, "LEFT", 5, 0)
    text:SetText(raid.name)
    text:SetTextColor(1, 1, 1)
    item.text = text
    
    -- Click handler
    local raidName = raid.name
    local capturedFrame = frame
    item:SetScript("OnClick", function()
      ConsumeHelper.SelectRaid(capturedFrame, raidName)
    end)
    
    -- Add up/down/delete buttons
    local idx = i
    local capturedFrame2 = frame
    OGST.AddListItemButtons(
      item, idx, getn(ConsumeHelper.data.raids),
      function() ConsumeHelper.MoveRaidUp(frame, idx) end,
      function() ConsumeHelper.MoveRaidDown(frame, idx) end,
      function() ConsumeHelper.DeleteRaid(frame, idx) end,
      false
    )
    
    yOffset = yOffset + rowHeight + rowSpacing
  end
  
  -- Add "Add Raid" as a list item
  local addRaidItem = OGST.CreateStyledListItem(scrollChild, contentWidth, rowHeight, "Button")
  addRaidItem:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yOffset)
  
  local addText = addRaidItem:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  addText:SetPoint("LEFT", addRaidItem, "LEFT", 8, 0)
  addText:SetText("Add Raid")
  addText:SetTextColor(0.7, 0.7, 0.7)
  
  local capturedFrame = frame
  addRaidItem:SetScript("OnClick", function()
    StaticPopupDialogs["OGRH_CH_ADD_RAID"] = {
      text = "Enter raid name:",
      button1 = "Add",
      button2 = "Cancel",
      hasEditBox = 1,
      maxLetters = 32,
      OnAccept = function()
        local raidName = getglobal(this:GetParent():GetName().."EditBox"):GetText()
        if raidName and raidName ~= "" then
          -- Check if raid already exists
          local exists = false
          for _, raid in ipairs(ConsumeHelper.data.raids) do
            if raid.name == raidName then
              exists = true
              break
            end
          end
          
          if not exists then
            -- Find highest order value
            local maxOrder = 0
            for _, raid in ipairs(ConsumeHelper.data.raids) do
              if raid.order > maxOrder then
                maxOrder = raid.order
              end
            end
            
            -- Add new raid
            table.insert(ConsumeHelper.data.raids, {name = raidName, order = maxOrder + 1})
            
            -- Don't pre-create empty tables - they won't be saved
            -- Tables will be created on-demand when items are added
            
            -- Refresh the list
            ConsumeHelper.PopulateLeftList(capturedFrame)
            
            OGRH.Msg("Raid '" .. raidName .. "' added")
          else
            OGRH.Msg("Raid '" .. raidName .. "' already exists")
          end
        end
      end,
      OnShow = function()
        getglobal(this:GetName().."EditBox"):SetFocus()
      end,
      OnHide = function()
        getglobal(this:GetName().."EditBox"):SetText("")
      end,
      EditBoxOnEnterPressed = function()
        local parent = this:GetParent()
        StaticPopup_OnClick(parent, 1)
      end,
      EditBoxOnEscapePressed = function()
        this:GetParent():Hide()
      end,
      timeout = 0,
      whileDead = 1,
      hideOnEscape = 1
    }
    StaticPopup_Show("OGRH_CH_ADD_RAID")
  end)
  
  yOffset = yOffset + rowHeight + rowSpacing
  
  -- Add Roles section
  local rolesItem = OGST.CreateStyledListItem(scrollChild, contentWidth, rowHeight, "Button")
  rolesItem:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yOffset)
  
  local isRolesSelected = (ConsumeHelper.data.viewMode == "roles")
  OGST.SetListItemSelected(rolesItem, isRolesSelected)
  
  local rolesText = rolesItem:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  rolesText:SetPoint("LEFT", rolesItem, "LEFT", 8, 0)
  rolesText:SetText("Roles")
  rolesText:SetTextColor(1, 1, 1)
  
  local capturedFrame3 = frame
  rolesItem:SetScript("OnClick", function()
    ConsumeHelper.SelectRoles(capturedFrame3)
  end)
  
  yOffset = yOffset + rowHeight + rowSpacing
  
  -- Add Setup section (same styling as raids for consistency)
  local setupItem = OGST.CreateStyledListItem(scrollChild, contentWidth, rowHeight, "Button")
  setupItem:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yOffset)
  
  local isSetupSelected = (ConsumeHelper.data.viewMode == "setup")
  OGST.SetListItemSelected(setupItem, isSetupSelected)
  
  local setupText = setupItem:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  setupText:SetPoint("LEFT", setupItem, "LEFT", 8, 0)
  setupText:SetText("Setup")
  setupText:SetTextColor(1, 1, 1)
  
  local setupFrame = frame
  setupItem:SetScript("OnClick", function()
    ConsumeHelper.SelectSetup(setupFrame)
  end)
  
  yOffset = yOffset + rowHeight + rowSpacing
  
  -- Update scroll child height
  scrollChild:SetHeight(math.max(1, yOffset))
end

------------------------------
--   Selection Handlers     --
------------------------------

function ConsumeHelper.SelectRaid(frame, raidName)
  ConsumeHelper.data.selectedRaid = raidName
  ConsumeHelper.data.selectedClass = nil
  ConsumeHelper.data.viewMode = nil
  ConsumeHelper.PopulateLeftList(frame)
  ConsumeHelper.ShowRaidPanel(frame)
end

function ConsumeHelper.SelectRoles(frame)
  ConsumeHelper.data.viewMode = "roles"
  ConsumeHelper.data.selectedRaid = nil
  ConsumeHelper.data.selectedClass = nil
  ConsumeHelper.PopulateLeftList(frame)
  ConsumeHelper.ShowRolesPanel(frame)
end

function ConsumeHelper.SelectSetup(frame)
  ConsumeHelper.data.viewMode = "setup"
  ConsumeHelper.data.selectedRaid = nil
  ConsumeHelper.data.selectedClass = nil
  ConsumeHelper.PopulateLeftList(frame)
  ConsumeHelper.ShowSetupPanel(frame)
end

function ConsumeHelper.SelectClass(frame, className)
  ConsumeHelper.data.selectedClass = className
  ConsumeHelper.PopulateClassList(frame)
  ConsumeHelper.PopulateSelectedList(frame)
  ConsumeHelper.PopulateAvailableList(frame)
end

function ConsumeHelper.DeletePlayer(frame, playerName)
  -- Remove player from saved variables
  OGRH_ConsumeHelper_SV.playerRoles[playerName] = nil
  
  -- Clear selection if this was the selected player
  if ConsumeHelper.data.selectedPlayer == playerName then
    ConsumeHelper.data.selectedPlayer = nil
  end
  
  -- Refresh the panel
  ConsumeHelper.ShowRolesPanel(frame)
end

------------------------------
--   Right Panel: Raid View --
------------------------------

function ConsumeHelper.ShowRaidPanel(frame)
  if not frame or not frame.rightPanel then return end
  
  local rightPanel = frame.rightPanel
  
  -- Hide instruction text
  if frame.instructionText then frame.instructionText:Hide() end
  
  -- Hide headers from previous views
  if frame.classHeader then frame.classHeader:Hide() end
  if frame.selectedHeader then frame.selectedHeader:Hide() end
  if frame.availableHeader then frame.availableHeader:Hide() end
  
  -- Clear existing content
  local children = {rightPanel:GetChildren()}
  for _, child in ipairs(children) do
    child:Hide()
    child:SetParent(nil)
  end
  
  if not ConsumeHelper.data.selectedRaid then return end
  
  local contentTop = -5
  local headerHeight = 20
  local listHeight = FRAME_HEIGHT - 120  -- Reduced to fit better
  local columnSpacing = 5
  local leftPadding = 10
  local headerListGap = 2  -- Reduced gap between headers and lists
  
  -- ===== Column 1: Class/Role =====
  local classHeader = rightPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  classHeader:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", leftPadding, contentTop)
  classHeader:SetText("|cffffffffClass/Role|r")
  frame.classHeader = classHeader
  
  local classListFrame = CreateFrame("Frame", nil, rightPanel)
  classListFrame:SetWidth(CLASS_LIST_WIDTH)
  classListFrame:SetHeight(listHeight)
  classListFrame:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", leftPadding, contentTop - headerHeight - headerListGap)
  
  frame.classListFrame = classListFrame
  ConsumeHelper.PopulateClassList(frame)
  
  -- ===== Column 2: Selected Consumes =====
  local selectedHeader = rightPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  selectedHeader:SetPoint("TOPLEFT", classListFrame, "TOPRIGHT", columnSpacing, headerHeight + headerListGap)
  selectedHeader:SetText("|cffffffffSelected|r")
  frame.selectedHeader = selectedHeader
  
  local selectedListFrame = CreateFrame("Frame", nil, rightPanel)
  selectedListFrame:SetWidth(SELECTED_LIST_WIDTH)
  selectedListFrame:SetHeight(listHeight)
  selectedListFrame:SetPoint("TOPLEFT", classListFrame, "TOPRIGHT", columnSpacing, 0)
  
  frame.selectedListFrame = selectedListFrame
  ConsumeHelper.PopulateSelectedList(frame)
  
  -- ===== Column 3: Available Consumes =====
  local availableHeader = rightPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  availableHeader:SetPoint("TOPLEFT", selectedListFrame, "TOPRIGHT", columnSpacing, headerHeight + headerListGap)
  availableHeader:SetText("|cffffffffAvailable|r")
  frame.availableHeader = availableHeader
  
  local availableListFrame = CreateFrame("Frame", nil, rightPanel)
  availableListFrame:SetWidth(AVAILABLE_LIST_WIDTH)
  availableListFrame:SetHeight(listHeight)
  availableListFrame:SetPoint("TOPLEFT", selectedListFrame, "TOPRIGHT", columnSpacing, 0)
  
  frame.availableListFrame = availableListFrame
  ConsumeHelper.PopulateAvailableList(frame)
end

------------------------------
--   StaticPopupDialogs      --
------------------------------

StaticPopupDialogs["OGRH_CH_ADD_SETUP_CONSUME"] = {
  text = "Enter item ID to add:",
  button1 = "Add",
  button2 = "Cancel",
  hasEditBox = 1,
  OnAccept = function()
    local itemId = tonumber(getglobal(this:GetParent():GetName().."EditBox"):GetText())
    if itemId and itemId > 0 then
      -- Check if already exists
      local exists = false
      for _, id in ipairs(OGRH_ConsumeHelper_SV.setupConsumes) do
        if id == itemId then
          exists = true
          break
        end
      end
      
      if not exists then
        table.insert(OGRH_ConsumeHelper_SV.setupConsumes, itemId)
        
        -- Refresh the list if frame exists
        if ConsumeHelper.setupFrame then
          ConsumeHelper.PopulateSetupList(ConsumeHelper.setupFrame)
        end
      else
        OGRH.Msg("Item " .. itemId .. " already in setup consumes")
      end
    else
      OGRH.Msg("Invalid item ID")
    end
    this:GetParent():Hide()
  end,
  OnShow = function()
    getglobal(this:GetName().."EditBox"):SetFocus()
  end,
  OnHide = function()
    getglobal(this:GetName().."EditBox"):SetText("")
  end,
  EditBoxOnEnterPressed = function()
    local parent = this:GetParent()
    StaticPopup_OnClick(parent, 1)
  end,
  EditBoxOnEscapePressed = function()
    this:GetParent():Hide()
  end,
  timeout = 0,
  whileDead = 1,
  hideOnEscape = 1
}

------------------------------
--   Right Panel: Roles     --
------------------------------

function ConsumeHelper.ShowRolesPanel(frame)
  if not frame or not frame.rightPanel then return end
  
  local rightPanel = frame.rightPanel
  
  -- Hide instruction text
  if frame.instructionText then frame.instructionText:Hide() end
  
  -- Hide headers from previous views
  if frame.classHeader then frame.classHeader:Hide() end
  if frame.selectedHeader then frame.selectedHeader:Hide() end
  if frame.availableHeader then frame.availableHeader:Hide() end
  
  -- Clear existing content
  local children = {rightPanel:GetChildren()}
  for _, child in ipairs(children) do
    child:Hide()
    child:SetParent(nil)
  end
  
  -- Get current player name and class
  local playerName = UnitName("player")
  local _, playerClass = UnitClass("player")
  
  -- Build player list from playerRoles, add current player if not in list
  EnsurePlayerExists(playerName, playerClass)
  
  -- Collect all players
  local players = {}
  OGRH_ConsumeHelper_SV.playerRoles = OGRH_ConsumeHelper_SV.playerRoles or {}
  for name, data in pairs(OGRH_ConsumeHelper_SV.playerRoles) do
    table.insert(players, name)
  end
  
  -- Sort alphabetically
  table.sort(players)
  
  -- Select first player if none selected
  if not ConsumeHelper.data.selectedPlayer and getn(players) > 0 then
    ConsumeHelper.data.selectedPlayer = players[1]
  end
  
  local contentTop = -5
  local headerHeight = 20
  local listHeight = FRAME_HEIGHT - 120
  local columnSpacing = 5
  local leftPadding = 10
  local headerListGap = 2
  
  -- ===== Column 1: Players =====
  local playersHeader = rightPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  playersHeader:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", leftPadding, contentTop)
  playersHeader:SetText("|cffffffffPlayers|r")
  frame.classHeader = playersHeader
  
  local playerListFrame = CreateFrame("Frame", nil, rightPanel)
  playerListFrame:SetWidth(CLASS_LIST_WIDTH)
  playerListFrame:SetHeight(listHeight)
  playerListFrame:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", leftPadding, contentTop - headerHeight - headerListGap)
  
  frame.classListFrame = playerListFrame
  
  -- Create player list scroll
  local listFrame, scrollFrame, scrollChild, scrollBar, contentWidth = OGST.CreateStyledScrollList(
    playerListFrame,
    CLASS_LIST_WIDTH,
    listHeight,
    true
  )
  listFrame:SetPoint("TOPLEFT", playerListFrame, "TOPLEFT", 0, 0)
  playerListFrame.listFrame = listFrame
  playerListFrame.scrollChild = scrollChild
  
  local yOffset = 0
  local rowHeight = OGST.LIST_ITEM_HEIGHT
  local rowSpacing = OGST.LIST_ITEM_SPACING
  
  for i, name in ipairs(players) do
    local item = OGST.CreateStyledListItem(scrollChild, contentWidth, rowHeight, "Button")
    item:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yOffset)
    
    local isSelected = (ConsumeHelper.data.selectedPlayer == name)
    OGST.SetListItemSelected(item, isSelected)
    
    -- Player name with class color
    local text = item:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("LEFT", item, "LEFT", 8, 0)
    text:SetText(name)
    
    local playerData = OGRH_ConsumeHelper_SV.playerRoles and OGRH_ConsumeHelper_SV.playerRoles[name]
    local playerClass = playerData and playerData.class
    local color = playerClass and CLASS_COLORS[playerClass]
    if color then
      text:SetTextColor(color.r, color.g, color.b)
    else
      text:SetTextColor(1, 1, 1)
    end
    
    -- Click handler - capture name properly
    local capturedName = name
    item:SetScript("OnClick", function()
      ConsumeHelper.data.selectedPlayer = capturedName
      ConsumeHelper.ShowRolesPanel(frame)
    end)
    
    -- Delete button
    local capturedPlayerName = name
    OGST.AddListItemButtons(
      item, i, getn(players),
      nil, nil,
      function() ConsumeHelper.DeletePlayer(frame, capturedPlayerName) end,
      true
    )
    
    yOffset = yOffset + rowHeight + rowSpacing
  end
  
  scrollChild:SetHeight(math.max(1, yOffset))
  
  -- ===== Column 2: Selected Roles =====
  local selectedHeader = rightPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  selectedHeader:SetPoint("TOPLEFT", playerListFrame, "TOPRIGHT", columnSpacing, headerHeight + headerListGap)
  selectedHeader:SetText("|cffffffffSelected|r")
  frame.selectedHeader = selectedHeader
  
  local selectedListFrame = CreateFrame("Frame", nil, rightPanel)
  selectedListFrame:SetWidth(SELECTED_LIST_WIDTH)
  selectedListFrame:SetHeight(listHeight)
  selectedListFrame:SetPoint("TOPLEFT", playerListFrame, "TOPRIGHT", columnSpacing, 0)
  
  frame.selectedListFrame = selectedListFrame
  
  local selectedList, selectedScroll, selectedChild, selectedBar, selectedWidth = OGST.CreateStyledScrollList(
    selectedListFrame,
    SELECTED_LIST_WIDTH,
    listHeight,
    true
  )
  selectedList:SetPoint("TOPLEFT", selectedListFrame, "TOPLEFT", 0, 0)
  selectedListFrame.listFrame = selectedList
  selectedListFrame.scrollChild = selectedChild
  
  yOffset = 0
  if ConsumeHelper.data.selectedPlayer then
    local selectedPlayerName = ConsumeHelper.data.selectedPlayer
    OGRH_ConsumeHelper_SV.playerRoles = OGRH_ConsumeHelper_SV.playerRoles or {}
    local playerData = OGRH_ConsumeHelper_SV.playerRoles[selectedPlayerName] or {}
    for _, roleName in ipairs(ConsumeHelper.data.roles) do
      if playerData[roleName] then
        local item = OGST.CreateStyledListItem(selectedChild, selectedWidth, rowHeight, "Button")
        item:SetPoint("TOPLEFT", selectedChild, "TOPLEFT", 0, -yOffset)
        
        local text = item:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetPoint("LEFT", item, "LEFT", 8, 0)
        text:SetText(roleName)
        text:SetTextColor(1, 0.82, 0)
        
        -- Click to remove from selected
        local capturedPlayerName = selectedPlayerName
        local capturedRoleName = roleName
        item:SetScript("OnClick", function()
          OGRH_ConsumeHelper_SV.playerRoles = OGRH_ConsumeHelper_SV.playerRoles or {}
          if OGRH_ConsumeHelper_SV.playerRoles[capturedPlayerName] then
            OGRH_ConsumeHelper_SV.playerRoles[capturedPlayerName][capturedRoleName] = nil
          end
          ConsumeHelper.ShowRolesPanel(frame)
        end)
        
        yOffset = yOffset + rowHeight + rowSpacing
      end
    end
  end
  selectedChild:SetHeight(math.max(1, yOffset))
  
  -- ===== Column 3: Available Roles =====
  local availableHeader = rightPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  availableHeader:SetPoint("TOPLEFT", selectedListFrame, "TOPRIGHT", columnSpacing, headerHeight + headerListGap)
  availableHeader:SetText("|cffffffffAvailable|r")
  frame.availableHeader = availableHeader
  
  local availableListFrame = CreateFrame("Frame", nil, rightPanel)
  availableListFrame:SetWidth(AVAILABLE_LIST_WIDTH)
  availableListFrame:SetHeight(listHeight)
  availableListFrame:SetPoint("TOPLEFT", selectedListFrame, "TOPRIGHT", columnSpacing, 0)
  
  frame.availableListFrame = availableListFrame
  
  local availableList, availableScroll, availableChild, availableBar, availableWidth = OGST.CreateStyledScrollList(
    availableListFrame,
    AVAILABLE_LIST_WIDTH,
    listHeight,
    true
  )
  availableList:SetPoint("TOPLEFT", availableListFrame, "TOPLEFT", 0, 0)
  availableListFrame.listFrame = availableList
  availableListFrame.scrollChild = availableChild
  
  yOffset = 0
  if ConsumeHelper.data.selectedPlayer then
    local selectedPlayerName = ConsumeHelper.data.selectedPlayer
    OGRH_ConsumeHelper_SV.playerRoles = OGRH_ConsumeHelper_SV.playerRoles or {}
    local playerData = OGRH_ConsumeHelper_SV.playerRoles[selectedPlayerName] or {}
    for _, roleName in ipairs(ConsumeHelper.data.roles) do
      if not playerData[roleName] then
        local item = OGST.CreateStyledListItem(availableChild, availableWidth, rowHeight, "Button")
        item:SetPoint("TOPLEFT", availableChild, "TOPLEFT", 0, -yOffset)
        
        local text = item:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetPoint("LEFT", item, "LEFT", 8, 0)
        text:SetText(roleName)
        text:SetTextColor(0.7, 0.7, 0.7)
        
        -- Click to add to selected
        local capturedPlayerName = selectedPlayerName
        local capturedRoleName = roleName
        item:SetScript("OnClick", function()
          OGRH_ConsumeHelper_SV.playerRoles = OGRH_ConsumeHelper_SV.playerRoles or {}
          OGRH_ConsumeHelper_SV.playerRoles[capturedPlayerName] = OGRH_ConsumeHelper_SV.playerRoles[capturedPlayerName] or {}
          OGRH_ConsumeHelper_SV.playerRoles[capturedPlayerName][capturedRoleName] = true
          ConsumeHelper.ShowRolesPanel(frame)
        end)
        
        yOffset = yOffset + rowHeight + rowSpacing
      end
    end
  end
  availableChild:SetHeight(math.max(1, yOffset))
end

------------------------------
--   Right Panel: Setup     --
------------------------------

function ConsumeHelper.ShowSetupPanel(frame)
  if not frame or not frame.rightPanel then return end
  
  local rightPanel = frame.rightPanel
  
  -- Hide instruction text
  if frame.instructionText then frame.instructionText:Hide() end
  
  -- Hide headers if they exist
  if frame.classHeader then frame.classHeader:Hide() end
  if frame.selectedHeader then frame.selectedHeader:Hide() end
  if frame.availableHeader then frame.availableHeader:Hide() end
  
  -- Clear existing content
  local children = {rightPanel:GetChildren()}
  for _, child in ipairs(children) do
    child:Hide()
    child:SetParent(nil)
  end
  
  -- Load Defaults button at top left
  local btnLoadDefaults = CreateFrame("Button", nil, rightPanel, "UIPanelButtonTemplate")
  btnLoadDefaults:SetWidth(120)
  btnLoadDefaults:SetHeight(24)
  btnLoadDefaults:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", 10, -10)
  btnLoadDefaults:SetText("Load Defaults")
  OGST.StyleButton(btnLoadDefaults)
  btnLoadDefaults:SetScript("OnClick", function()
    StaticPopupDialogs["OGRH_CH_LOAD_DEFAULTS"] = {
      text = "This will OVERWRITE all Consume Helper data!\n\nAre you sure?",
      button1 = "Yes",
      button2 = "No",
      OnAccept = function()
        ConsumeHelper.LoadDefaults()
      end,
      timeout = 0,
      whileDead = 1,
      hideOnEscape = 1
    }
    StaticPopup_Show("OGRH_CH_LOAD_DEFAULTS")
  end)
  
  -- Import button
  local btnImport = CreateFrame("Button", nil, rightPanel, "UIPanelButtonTemplate")
  btnImport:SetWidth(80)
  btnImport:SetHeight(24)
  btnImport:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", SELECTED_LIST_WIDTH + 20, -10)
  btnImport:SetText("Import")
  OGST.StyleButton(btnImport)
  btnImport:SetScript("OnClick", function()
    StaticPopupDialogs["OGRH_CH_IMPORT_WARNING"] = {
      text = "This will OVERWRITE all Consume Helper data!\n\nAre you sure?",
      button1 = "Yes",
      button2 = "No",
      OnAccept = function()
        ConsumeHelper.ImportData(frame)
      end,
      timeout = 0,
      whileDead = 1,
      hideOnEscape = 1
    }
    StaticPopup_Show("OGRH_CH_IMPORT_WARNING")
  end)
  
  -- Export button
  local btnExport = CreateFrame("Button", nil, rightPanel, "UIPanelButtonTemplate")
  btnExport:SetWidth(80)
  btnExport:SetHeight(24)
  btnExport:SetPoint("LEFT", btnImport, "RIGHT", 5, 0)
  btnExport:SetText("Export")
  OGST.StyleButton(btnExport)
  btnExport:SetScript("OnClick", function()
    ConsumeHelper.ExportData(frame)
  end)
  
  -- Create setup list below Load Defaults button
  local listTop = -10  -- Space below button
  local panelHeight = rightPanel:GetHeight()
  local listHeight = panelHeight - 54  -- 10 (top to button) + 24 (button) + 10 (spacing) + 10 (bottom padding)
  
  local setupListFrame = CreateFrame("Frame", nil, rightPanel)
  setupListFrame:SetWidth(SELECTED_LIST_WIDTH)
  setupListFrame:SetHeight(listHeight)
  setupListFrame:SetPoint("TOPLEFT", btnLoadDefaults, "BOTTOMLEFT", 0, listTop)
  
  -- Import/Export text box to the right of setup list
  local textBoxWidth = 400  -- Width for text box area
  local textBoxHeight = listHeight  -- Same height as setup list
  
  local textBoxBackdrop, textBoxEditBox, textBoxScrollFrame, textBoxScrollBar = OGST.CreateScrollingTextBox(
    rightPanel,
    textBoxWidth,
    textBoxHeight
  )
  textBoxBackdrop:SetPoint("TOPLEFT", btnImport, "BOTTOMLEFT", 0, listTop)
  
  -- Store references
  frame.setupListFrame = setupListFrame
  frame.importExportBackdrop = textBoxBackdrop
  frame.importExportEditBox = textBoxEditBox
  frame.importExportScrollFrame = textBoxScrollFrame
  frame.importExportScrollBar = textBoxScrollBar
  
  ConsumeHelper.setupFrame = frame
  
  ConsumeHelper.PopulateSetupList(frame)
end

function ConsumeHelper.PopulateSetupList(frame)
  if not frame or not frame.setupListFrame then return end
  
  local setupListFrame = frame.setupListFrame
  
  -- Clear existing content
  if setupListFrame.listFrame then
    local children = {setupListFrame.scrollChild:GetChildren()}
    for _, child in ipairs(children) do
      child:Hide()
      child:SetParent(nil)
    end
  else
    -- Create scroll list
    local listHeight = setupListFrame:GetHeight()
    local listFrame, scrollFrame, scrollChild, scrollBar, contentWidth = OGST.CreateStyledScrollList(
      setupListFrame,
      SELECTED_LIST_WIDTH,
      listHeight,
      true
    )
    listFrame:SetPoint("TOPLEFT", setupListFrame, "TOPLEFT", 0, 0)
    setupListFrame.listFrame = listFrame
    setupListFrame.scrollFrame = scrollFrame
    setupListFrame.scrollChild = scrollChild
    setupListFrame.scrollBar = scrollBar
    setupListFrame.contentWidth = contentWidth
  end
  
  local scrollChild = setupListFrame.scrollChild
  local contentWidth = setupListFrame.contentWidth
  local yOffset = 0
  local rowHeight = OGST.LIST_ITEM_HEIGHT
  local rowSpacing = OGST.LIST_ITEM_SPACING
  
  -- Sort items alphabetically by name
  local sortedItems = {}
  for _, itemId in ipairs(OGRH_ConsumeHelper_SV.setupConsumes) do
    if type(itemId) == "number" then
      local itemName = GetItemInfo(itemId)
      if itemName then
        table.insert(sortedItems, {id = itemId, name = itemName})
      else
        table.insert(sortedItems, {id = itemId, name = "Item " .. itemId})
      end
    end
  end
  table.sort(sortedItems, function(a, b) return a.name < b.name end)
  
  -- Add consume items with delete buttons
  for index, sortedItem in ipairs(sortedItems) do
    local itemId = sortedItem.id
    local item = OGST.CreateStyledListItem(scrollChild, contentWidth, rowHeight)
    item:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, yOffset)
    
    -- Get item info
    local itemName, _, itemQuality = GetItemInfo(itemId)
    local displayText = ""
    
    if itemName then
      local colorCode = "|cffffffff"
      if itemQuality == 0 then colorCode = "|cff9d9d9d"
      elseif itemQuality == 1 then colorCode = "|cffffffff"
      elseif itemQuality == 2 then colorCode = "|cff1eff00"
      elseif itemQuality == 3 then colorCode = "|cff0070dd"
      elseif itemQuality == 4 then colorCode = "|cffa335ee"
      elseif itemQuality == 5 then colorCode = "|cffff8000"
      end
      displayText = colorCode .. itemName .. "|r"
    else
      displayText = "Item " .. itemId
    end
    
    -- Create clickable button for tooltip (leave room for delete button on right)
    local itemBtn = CreateFrame("Button", nil, item)
    itemBtn:SetPoint("TOPLEFT", item, "TOPLEFT", 0, 0)
    itemBtn:SetPoint("BOTTOMRIGHT", item, "BOTTOMRIGHT", -40, 0)  -- Leave 40px for delete button
    itemBtn:SetHighlightTexture("Interface\\\\QuestFrame\\\\UI-QuestTitleHighlight", "ADD")
    
    local itemText = itemBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    itemText:SetPoint("LEFT", itemBtn, "LEFT", 5, 0)
    itemText:SetText(displayText)
    
    -- Capture itemId in closure
    local capturedItemId = itemId
    
    -- Tooltip on hover
    itemBtn:SetScript("OnEnter", function()
      GameTooltip:SetOwner(itemBtn, "ANCHOR_CURSOR")
      GameTooltip:SetHyperlink("item:" .. capturedItemId)
      GameTooltip:Show()
    end)
    itemBtn:SetScript("OnLeave", function()
      GameTooltip:Hide()
    end)
    
    -- Delete button (no up/down buttons for setup list)
    OGST.AddListItemButtons(
      item,
      index,
      getn(sortedItems),
      nil,  -- no onMoveUp
      nil,  -- no onMoveDown
      function()
        -- Remove from array
        for i, id in ipairs(OGRH_ConsumeHelper_SV.setupConsumes) do
          if id == capturedItemId then
            table.remove(OGRH_ConsumeHelper_SV.setupConsumes, i)
            break
          end
        end
        ConsumeHelper.PopulateSetupList(frame)
      end,
      true  -- hide up/down buttons
    )
    
    yOffset = yOffset - rowHeight - rowSpacing
  end
  
  -- Add "Add Consume" item at the bottom
  local addItem = OGST.CreateStyledListItem(scrollChild, contentWidth, rowHeight)
  addItem:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, yOffset)
  
  local addText = addItem:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  addText:SetPoint("CENTER", addItem, "CENTER", 0, 0)
  addText:SetText("|cff00ff00Add Consume|r")
  
  addItem:SetScript("OnClick", function()
    StaticPopup_Show("OGRH_CH_ADD_SETUP_CONSUME")
  end)
  
  yOffset = yOffset - rowHeight - rowSpacing
  
  -- Update scroll height
  scrollChild:SetHeight(math.abs(yOffset))
end

------------------------------
--   Class List Population  --
------------------------------

function ConsumeHelper.PopulateClassList(frame)
  if not frame or not frame.classListFrame then return end
  
  local classListFrame = frame.classListFrame
  
  -- Clear existing content
  if classListFrame.listFrame then
    local children = {classListFrame.scrollChild:GetChildren()}
    for _, child in ipairs(children) do
      child:Hide()
      child:SetParent(nil)
    end
  else
    -- Create scroll list
    local listFrame, scrollFrame, scrollChild, scrollBar, contentWidth = OGST.CreateStyledScrollList(
      classListFrame,
      CLASS_LIST_WIDTH,
      classListFrame:GetHeight(),
      true
    )
    listFrame:SetPoint("TOPLEFT", classListFrame, "TOPLEFT", 0, 0)
    classListFrame.listFrame = listFrame
    classListFrame.scrollFrame = scrollFrame
    classListFrame.scrollChild = scrollChild
    classListFrame.scrollBar = scrollBar
    classListFrame.contentWidth = contentWidth
  end
  
  local scrollChild = classListFrame.scrollChild
  local contentWidth = classListFrame.contentWidth
  local yOffset = 0
  local rowHeight = OGST.LIST_ITEM_HEIGHT
  local rowSpacing = OGST.LIST_ITEM_SPACING
  
  -- Add "All" option first (when viewing a raid)
  if ConsumeHelper.data.selectedRaid and not ConsumeHelper.data.viewMode then
    local item = OGST.CreateStyledListItem(scrollChild, contentWidth, rowHeight, "Button")
    item:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yOffset)
    
    local isSelected = (ConsumeHelper.data.selectedClass == "All")
    OGST.SetListItemSelected(item, isSelected)
    
    local text = item:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("LEFT", item, "LEFT", 8, 0)
    text:SetText("All")
    text:SetTextColor(1, 1, 1) -- White color
    item.text = text
    
    item:SetScript("OnClick", function()
      ConsumeHelper.SelectClass(frame, "All")
    end)
    
    yOffset = yOffset + rowHeight + rowSpacing
  end
  
  -- Add roles (when viewing a raid)
  if ConsumeHelper.data.selectedRaid and not ConsumeHelper.data.viewMode then
    for _, roleName in ipairs(ConsumeHelper.data.roles) do
      local item = OGST.CreateStyledListItem(scrollChild, contentWidth, rowHeight, "Button")
      item:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yOffset)
      
      local isSelected = (ConsumeHelper.data.selectedClass == roleName)
      OGST.SetListItemSelected(item, isSelected)
      
      -- Role name text (gold color)
      local text = item:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      text:SetPoint("LEFT", item, "LEFT", 8, 0)
      text:SetText(roleName)
      text:SetTextColor(1, 0.82, 0) -- Gold color for roles
      item.text = text
      
      -- Click handler
      local capturedRoleName = roleName
      item:SetScript("OnClick", function()
        ConsumeHelper.SelectClass(frame, capturedRoleName)
      end)
      
      yOffset = yOffset + rowHeight + rowSpacing
    end
  end
  
  -- Create class items (already alphabetical)
  for _, className in ipairs(ConsumeHelper.data.classes) do
    local item = OGST.CreateStyledListItem(scrollChild, contentWidth, rowHeight, "Button")
    item:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yOffset)
    
    local isSelected = (ConsumeHelper.data.selectedClass == className)
    OGST.SetListItemSelected(item, isSelected)
    
    -- Class name text with color
    local text = item:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("LEFT", item, "LEFT", 8, 0)
    text:SetText(className)
    local color = CLASS_COLORS[className]
    if color then
      text:SetTextColor(color.r, color.g, color.b)
    else
      text:SetTextColor(1, 1, 1)
    end
    item.text = text
    
    -- Click handler
    local capturedClassName = className
    item:SetScript("OnClick", function()
      ConsumeHelper.SelectClass(frame, capturedClassName)
    end)
    
    yOffset = yOffset + rowHeight + rowSpacing
  end
  
  -- Update scroll child height
  scrollChild:SetHeight(math.max(1, yOffset))
end

------------------------------
--   Selected List Population --
------------------------------

function ConsumeHelper.PopulateSelectedList(frame)
  if not frame or not frame.selectedListFrame then return end
  
  local selectedListFrame = frame.selectedListFrame
  
  -- Clear existing content
  if selectedListFrame.listFrame then
    local children = {selectedListFrame.scrollChild:GetChildren()}
    for _, child in ipairs(children) do
      child:Hide()
      child:SetParent(nil)
    end
  else
    -- Create scroll list
    local listFrame, scrollFrame, scrollChild, scrollBar, contentWidth = OGST.CreateStyledScrollList(
      selectedListFrame,
      selectedListFrame:GetWidth(),
      selectedListFrame:GetHeight(),
      true
    )
    listFrame:SetPoint("TOPLEFT", selectedListFrame, "TOPLEFT", 0, 0)
    selectedListFrame.listFrame = listFrame
    selectedListFrame.scrollFrame = scrollFrame
    selectedListFrame.scrollChild = scrollChild
    selectedListFrame.scrollBar = scrollBar
    selectedListFrame.contentWidth = contentWidth
  end
  
  local scrollChild = selectedListFrame.scrollChild
  local contentWidth = selectedListFrame.contentWidth
  
  -- Only show if raid and class are selected
  if not ConsumeHelper.data.selectedRaid or not ConsumeHelper.data.selectedClass then
    scrollChild:SetHeight(1)
    return
  end
  local yOffset = 0
  local rowHeight = OGST.LIST_ITEM_HEIGHT
  local rowSpacing = OGST.LIST_ITEM_SPACING
  
  -- Get items for selected raid/class (don't create if doesn't exist)
  local items = nil
  if OGRH_ConsumeHelper_SV.consumes and 
     OGRH_ConsumeHelper_SV.consumes[ConsumeHelper.data.selectedRaid] and 
     OGRH_ConsumeHelper_SV.consumes[ConsumeHelper.data.selectedRaid][ConsumeHelper.data.selectedClass] then
    items = OGRH_ConsumeHelper_SV.consumes[ConsumeHelper.data.selectedRaid][ConsumeHelper.data.selectedClass]
  end
  
  -- If no items exist yet, just show empty list
  if not items then
    scrollChild:SetHeight(1)
    return
  end
  
  -- Sort items alphabetically by name
  table.sort(items, function(a, b)
    local nameA = GetItemInfo(a.itemId) or ("Item " .. a.itemId)
    local nameB = GetItemInfo(b.itemId) or ("Item " .. b.itemId)
    return nameA < nameB
  end)
  
  -- Create item entries
  for i, itemData in ipairs(items) do
    local item = OGST.CreateStyledListItem(scrollChild, contentWidth, rowHeight, "Button")
    item:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yOffset)
    
    -- Get item name
    local itemName, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(itemData.itemId)
    
    -- Item text (left side)
    local text = item:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("LEFT", item, "LEFT", 8, 0)
    if itemName then
      text:SetText(itemName)
    else
      text:SetText("Item " .. itemData.itemId)
    end
    text:SetTextColor(1, 1, 1)
    
    -- Tooltip on hover
    local capturedItemIdForTooltip = itemData.itemId
    item:SetScript("OnEnter", function()
      GameTooltip:SetOwner(item, "ANCHOR_CURSOR")
      GameTooltip:SetHyperlink("item:" .. capturedItemIdForTooltip)
      GameTooltip:Show()
    end)
    item:SetScript("OnLeave", function()
      GameTooltip:Hide()
    end)
    
    -- Quantity edit box (inline on right side)
    local qtyBox = CreateFrame("EditBox", nil, item)
    qtyBox:SetWidth(30)
    qtyBox:SetHeight(16)
    qtyBox:SetPoint("RIGHT", item, "RIGHT", -35, 0)
    qtyBox:SetAutoFocus(false)
    qtyBox:SetFontObject(GameFontNormalSmall)
    qtyBox:SetJustifyH("CENTER")  -- Center the text horizontally
    qtyBox:SetBackdrop({
      bgFile = "Interface/Tooltips/UI-Tooltip-Background",
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
      tile = true, tileSize = 8, edgeSize = 8,
      insets = {left = 2, right = 2, top = 2, bottom = 2}
    })
    qtyBox:SetBackdropColor(0, 0, 0, 0.8)
    qtyBox:SetText(tostring(itemData.quantity or 1))
    local capturedItemData = itemData
    
    -- Validate on blur or enter
    local function validateQuantity()
      local text = this:GetText()
      local value = tonumber(text)
      if not value or value < 1 then
        value = 1
        this:SetText("1")
      end
      capturedItemData.quantity = value
    end
    
    qtyBox:SetScript("OnEscapePressed", function() 
      validateQuantity()
      this:ClearFocus() 
    end)
    qtyBox:SetScript("OnEnterPressed", function() 
      validateQuantity()
      this:ClearFocus() 
    end)
    qtyBox:SetScript("OnEditFocusLost", function()
      validateQuantity()
    end)
    qtyBox:SetScript("OnTextChanged", function()
      local text = this:GetText()
      -- Remove any non-digit characters
      local digitsOnly = string.gsub(text, "%D", "")
      if digitsOnly ~= text then
        this:SetText(digitsOnly)
      end
      -- Update quantity if valid
      local value = tonumber(digitsOnly)
      if value and value >= 1 then
        capturedItemData.quantity = value
      end
      -- Allow empty during editing - will validate on blur
    end)
    
    local qtyLabel = item:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    qtyLabel:SetPoint("RIGHT", qtyBox, "LEFT", -3, 0)
    qtyLabel:SetText("x")
    qtyLabel:SetTextColor(0.7, 0.7, 0.7)
    
    -- Delete button
    local capturedItemId = itemData.itemId
    local deleteBtn = OGST.AddListItemButtons(
      item, i, getn(items),
      nil, nil,
      function() ConsumeHelper.DeleteItem(frame, capturedItemId) end,
      true
    )
    
    yOffset = yOffset + rowHeight + rowSpacing
  end
  
  -- Update scroll child height
  scrollChild:SetHeight(math.max(1, yOffset))
end

------------------------------
--   Available List Population --
------------------------------

function ConsumeHelper.PopulateAvailableList(frame)
  if not frame or not frame.availableListFrame then return end
  
  local availableListFrame = frame.availableListFrame
  
  -- Clear existing content
  if availableListFrame.listFrame then
    local children = {availableListFrame.scrollChild:GetChildren()}
    for _, child in ipairs(children) do
      child:Hide()
      child:SetParent(nil)
    end
  else
    -- Create scroll list
    local listFrame, scrollFrame, scrollChild, scrollBar, contentWidth = OGST.CreateStyledScrollList(
      availableListFrame,
      availableListFrame:GetWidth(),
      availableListFrame:GetHeight(),
      true
    )
    listFrame:SetPoint("TOPLEFT", availableListFrame, "TOPLEFT", 0, 0)
    availableListFrame.listFrame = listFrame
    availableListFrame.scrollFrame = scrollFrame
    availableListFrame.scrollChild = scrollChild
    availableListFrame.scrollBar = scrollBar
    availableListFrame.contentWidth = contentWidth
  end
  
  local scrollChild = availableListFrame.scrollChild
  local contentWidth = availableListFrame.contentWidth
  
  -- Only show if raid and class are selected
  if not ConsumeHelper.data.selectedRaid or not ConsumeHelper.data.selectedClass then
    scrollChild:SetHeight(1)
    return
  end
  local yOffset = 0
  local rowHeight = OGST.LIST_ITEM_HEIGHT
  local rowSpacing = OGST.LIST_ITEM_SPACING
  
  -- Get items already assigned to this class/role (don't create if doesn't exist)
  local assignedItems = nil
  if OGRH_ConsumeHelper_SV.consumes and 
     OGRH_ConsumeHelper_SV.consumes[ConsumeHelper.data.selectedRaid] and 
     OGRH_ConsumeHelper_SV.consumes[ConsumeHelper.data.selectedRaid][ConsumeHelper.data.selectedClass] then
    assignedItems = OGRH_ConsumeHelper_SV.consumes[ConsumeHelper.data.selectedRaid][ConsumeHelper.data.selectedClass]
  end
  
  -- Build lookup of already assigned items
  local assignedItemIds = {}
  if assignedItems then
    for _, item in ipairs(assignedItems) do
      assignedItemIds[item.itemId] = true
    end
  end
  
  -- Build sorted list of available items
  local availableItems = {}
  for _, itemId in ipairs(OGRH_ConsumeHelper_SV.setupConsumes) do
    if not assignedItemIds[itemId] then
      table.insert(availableItems, itemId)
    end
  end
  
  -- Sort alphabetically by item name
  table.sort(availableItems, function(a, b)
    local nameA = GetItemInfo(a) or ("Item " .. a)
    local nameB = GetItemInfo(b) or ("Item " .. b)
    return nameA < nameB
  end)
  
  -- Show all available items
  for _, itemId in ipairs(availableItems) do
    if true then
      local item = OGST.CreateStyledListItem(scrollChild, contentWidth, rowHeight, "Button")
      item:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yOffset)
      
      -- Item name
      local itemName, _, _, _, _, _, _, _, _, itemTexture = GetItemInfo(itemId)
      local text = item:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      text:SetPoint("LEFT", item, "LEFT", 8, 0)
      if itemName then
        text:SetText(itemName)
      else
        text:SetText("Item " .. itemId)
      end
      text:SetTextColor(0.7, 0.7, 0.7)
      
      -- Tooltip on hover
      local capturedItemId = itemId
      item:SetScript("OnEnter", function()
        GameTooltip:SetOwner(item, "ANCHOR_CURSOR")
        GameTooltip:SetHyperlink("item:" .. capturedItemId)
        GameTooltip:Show()
      end)
      item:SetScript("OnLeave", function()
        GameTooltip:Hide()
      end)
      
      -- Click to add
      item:SetScript("OnClick", function()
        -- Ensure consumes table exists
        OGRH_ConsumeHelper_SV.consumes = OGRH_ConsumeHelper_SV.consumes or {}
        
        -- Create table structure if it doesn't exist
        if not OGRH_ConsumeHelper_SV.consumes[ConsumeHelper.data.selectedRaid] then
          OGRH_ConsumeHelper_SV.consumes[ConsumeHelper.data.selectedRaid] = {}
        end
        if not OGRH_ConsumeHelper_SV.consumes[ConsumeHelper.data.selectedRaid][ConsumeHelper.data.selectedClass] then
          OGRH_ConsumeHelper_SV.consumes[ConsumeHelper.data.selectedRaid][ConsumeHelper.data.selectedClass] = {}
        end
        local items = OGRH_ConsumeHelper_SV.consumes[ConsumeHelper.data.selectedRaid][ConsumeHelper.data.selectedClass]
        table.insert(items, {itemId = capturedItemId, quantity = 1})
        ConsumeHelper.PopulateSelectedList(frame)
        ConsumeHelper.PopulateAvailableList(frame)
      end)
      
      yOffset = yOffset + rowHeight + rowSpacing
    end
  end
  
  -- Update scroll child height
  scrollChild:SetHeight(math.max(1, yOffset))
end

------------------------------
--   Raid Management        --
------------------------------

function ConsumeHelper.MoveRaidUp(frame, index)
  if index <= 1 then return end
  local raids = ConsumeHelper.data.raids
  local temp = raids[index - 1].order
  raids[index - 1].order = raids[index].order
  raids[index].order = temp
  ConsumeHelper.PopulateLeftList(frame)
end

function ConsumeHelper.MoveRaidDown(frame, index)
  local raids = ConsumeHelper.data.raids
  if index >= getn(raids) then return end
  local temp = raids[index + 1].order
  raids[index + 1].order = raids[index].order
  raids[index].order = temp
  ConsumeHelper.PopulateLeftList(frame)
end

function ConsumeHelper.DeleteRaid(frame, index)
  local raidName = ConsumeHelper.data.raids[index].name
  table.remove(ConsumeHelper.data.raids, index)
  
  -- Clear selection if deleted raid was selected
  if ConsumeHelper.data.selectedRaid == raidName then
    ConsumeHelper.data.selectedRaid = nil
    ConsumeHelper.data.selectedClass = nil
    ConsumeHelper.ShowSetupPanel(frame)
  end
  
  ConsumeHelper.PopulateLeftList(frame)
end

------------------------------
--   Item Management        --
------------------------------

function ConsumeHelper.DeleteItem(frame, itemId)
  if not ConsumeHelper.data.selectedRaid or not ConsumeHelper.data.selectedClass then return end
  
  local items = OGRH_ConsumeHelper_SV.consumes[ConsumeHelper.data.selectedRaid][ConsumeHelper.data.selectedClass]
  
  -- Find the item by itemId and remove it
  for i, itemData in ipairs(items) do
    if itemData.itemId == itemId then
      table.remove(items, i)
      break
    end
  end
  
  ConsumeHelper.PopulateSelectedList(frame)
  ConsumeHelper.PopulateAvailableList(frame)
end

------------------------------
--   Import/Export          --
------------------------------

function ConsumeHelper.ExportData(frame)
  if not frame or not frame.importExportEditBox then return end
  
  -- Serialize the entire saved variable data
  local exportData = OGRH_ConsumeHelper_SV or {}
  
  -- Use OGRH.Sync serialization if available, otherwise use simple serialization
  local serialized
  if OGRH and OGRH.Sync and OGRH.Sync.Serialize then
    serialized = OGRH.Sync.Serialize(exportData)
  else
    serialized = ConsumeHelper.SimpleSerialize(exportData)
  end
  
  if serialized then
    frame.importExportEditBox:SetText(serialized)
    frame.importExportEditBox:HighlightText()
    frame.importExportEditBox:SetFocus()
  else
    OGRH.Msg("Failed to export data!")
  end
end

function ConsumeHelper.ImportData(frame)
  if not frame or not frame.importExportEditBox then return end
  
  local importString = frame.importExportEditBox:GetText()
  if not importString or importString == "" then
    OGRH.Msg("No data to import!")
    return
  end
  
  -- Deserialize the data
  local importData
  if OGRH and OGRH.Sync and OGRH.Sync.Deserialize then
    importData = OGRH.Sync.Deserialize(importString)
  else
    importData = ConsumeHelper.SimpleDeserialize(importString)
  end
  
  if importData then
    -- Overwrite the saved variable
    OGRH_ConsumeHelper_SV = importData
    
    -- Refresh the UI
    if frame then
      ConsumeHelper.PopulateSetupList(frame)
    end
    
    OGRH.Msg("Data imported successfully!")
  else
    OGRH.Msg("Failed to import data! Invalid format.")
  end
end

function ConsumeHelper.LoadDefaults()
  if not OGRH_ConsumeHelper_FactoryDefaults then
    OGRH.Msg("No factory defaults available!")
    return
  end
  
  -- Overwrite with factory defaults
  OGRH_ConsumeHelper_SV = OGRH_ConsumeHelper_FactoryDefaults
  
  -- Refresh the UI
  local frame = getglobal("OGRH_ConsumeHelperFrame")
  if frame then
    ConsumeHelper.PopulateSetupList(frame)
  end
  
  OGRH.Msg("Factory defaults loaded!")
end

-- Simple serialization fallback
function ConsumeHelper.SimpleSerialize(tbl)
  if type(tbl) ~= "table" then
    return tostring(tbl)
  end
  
  local result = "{"
  local first = true
  
  for k, v in pairs(tbl) do
    if not first then
      result = result .. ","
    end
    first = false
    
    if type(k) == "number" then
      result = result .. "[" .. k .. "]="
    else
      result = result .. "[" .. string.format("%q", k) .. "]="
    end
    
    if type(v) == "table" then
      result = result .. ConsumeHelper.SimpleSerialize(v)
    elseif type(v) == "string" then
      result = result .. string.format("%q", v)
    elseif type(v) == "boolean" then
      result = result .. tostring(v)
    else
      result = result .. tostring(v)
    end
  end
  
  result = result .. "}"
  return result
end

function ConsumeHelper.SimpleDeserialize(str)
  if not str or str == "" then
    return nil
  end
  
  local func = loadstring("return " .. str)
  if not func then
    return nil
  end
  
  local success, result = pcall(func)
  if success then
    return result
  else
    return nil
  end
end

------------------------------
--   Show Window            --
------------------------------

function ConsumeHelper.ShowWindow()
  -- Create frame if it doesn't exist
  if not getglobal("OGRH_ConsumeHelperFrame") then
    ConsumeHelper.CreateFrame()
  end
  
  local frame = getglobal("OGRH_ConsumeHelperFrame")
  if frame then
    frame:Show()
  end
end

------------------------------
--   Global Access          --
------------------------------

-- Show Manage Consumes window (stub for now, will be implemented)
function ConsumeHelper.ShowManageConsumes()
  OGRH.Msg("Manage Consumes window - Coming soon!")
  -- TODO: Implement manage consumes interface
end

-- Make the show functions globally accessible
OGRH.ShowConsumeHelper = ConsumeHelper.ShowWindow
OGRH.ShowManageConsumes = ConsumeHelper.ShowManageConsumes

-- Initialize on load
OGRH.Msg("Consume Helper module loaded.")
