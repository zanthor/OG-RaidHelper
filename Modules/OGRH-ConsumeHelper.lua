-- OGRH-ConsumeHelper.lua
-- Module for managing consume tracking and configuration
-- Part of OG-RaidHelper / OG-ReadHelper

-- Namespace compatibility: Work with either OGRH or OGRH_Read
local OGRH = OGRH or OGRH_Read
if not OGRH then
  DEFAULT_CHAT_FRAME:AddMessage("|cffff0000Error: OGRH-ConsumeHelper requires OGRH_Core or OGRH_Read core to be loaded first!|r")
  return
end

-- Create namespace
OGRH.ConsumeHelper = OGRH.ConsumeHelper or {}
local ConsumeHelper = OGRH.ConsumeHelper

-- Also make it available globally for compatibility
_G.ConsumeHelper = ConsumeHelper

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
    OGRH.Msg("|cffffff66[RH-ConsumeHelper]|r Loaded " .. count .. " saved consume assignments")
  end
end

-- Register event to initialize after SavedVariables are loaded
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:SetScript("OnEvent", function()
  -- Support both OG-RaidHelper and OG-ReadHelper
  if arg1 == "OG-RaidHelper" or arg1 == "OG-ReadHelper" then
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

-- Helper function to count items in bags by itemId
local function CountItemInBags(itemId)
  -- Items with charges that should count total charges, not number of items
  local chargeBasedItems = {
    [20748] = true, -- Brilliant Mana Oil
    [20749] = true, -- Brilliant Wizard Oil
    [20750] = true, -- Wizard Oil
    [20745] = true, -- Minor Wizard Oil
    [20746] = true, -- Lesser Wizard Oil
    [20744] = true, -- Minor Mana Oil
    [20747] = true, -- Lesser Mana Oil
  }
  
  local total = 0
  
  for bag = 0, 4 do
    for slot = 1, GetContainerNumSlots(bag) do
      local link = GetContainerItemLink(bag, slot)
      if link then
        local _, _, linkItemId = string.find(link, "item:(%d+)")
        if linkItemId and tonumber(linkItemId) == itemId then
          -- For all items (including charge-based), count the displayed number
          -- For charge items this is charges, for stackable items this is stack count
          local texture, count = GetContainerItemInfo(bag, slot)
          count = tonumber(count) or 1
          -- WoW 1.12.1 returns negative numbers for items with charges
          if chargeBasedItems[itemId] and count < 0 then
            count = math.abs(count)
          end
          total = total + count
        end
      end
    end
  end
  
  return total
end

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

-- Get first assigned role for current player
local function GetCurrentPlayerRole()
  local playerName = UnitName("player")
  OGRH_ConsumeHelper_SV.playerRoles = OGRH_ConsumeHelper_SV.playerRoles or {}
  local playerData = OGRH_ConsumeHelper_SV.playerRoles[playerName]
  
  if playerData and ConsumeHelper.data and ConsumeHelper.data.roles then
    local roles = ConsumeHelper.data.roles
    for i = 1, getn(roles) do
      local roleName = roles[i]
      if playerData[roleName] then
        return roleName
      end
    end
  end
  
  return nil
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
    closeOnNewWindow = true,
    onClose = function()
      -- Re-open Manage Consumes when setup closes
      OGRH.ShowManageConsumes()
    end
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

-- Deposit all consumes from bags into bank
function ConsumeHelper.DepositConsumes()
  if not OGRH_ConsumeHelper_SV or not OGRH_ConsumeHelper_SV.setupConsumes then return end
  
  -- Build a set of all consume item IDs from setupConsumes
  local consumeItemIds = {}
  for i = 1, getn(OGRH_ConsumeHelper_SV.setupConsumes) do
    local itemId = OGRH_ConsumeHelper_SV.setupConsumes[i]
    if type(itemId) == "string" then
      itemId = string.gsub(itemId, "^%s*(.-)%s*$", "%1")
      itemId = tonumber(itemId)
    end
    if itemId then
      consumeItemIds[itemId] = true
    end
  end
  
  -- Build list of items to deposit
  local itemsToDeposit = {}
  
  for bag = 4, 0, -1 do
    local numSlots = GetContainerNumSlots(bag)
    if numSlots then
      for slot = numSlots, 1, -1 do
        local itemLink = GetContainerItemLink(bag, slot)
        if itemLink then
          local _, _, itemIdStr = string.find(itemLink, "item:(%d+)")
          local itemId = tonumber(itemIdStr)
          
          -- Check if this item is a consume
          if itemId and consumeItemIds[itemId] then
            table.insert(itemsToDeposit, {bag = bag, slot = slot})
          end
        end
      end
    end
  end
  
  if getn(itemsToDeposit) == 0 then
    DEFAULT_CHAT_FRAME:AddMessage("|cffffff00No consume items found in bags.|r")
    return
  end
  
  -- Create deposit frame if it doesn't exist
  if not ConsumeHelper.depositFrame then
    ConsumeHelper.depositFrame = CreateFrame("Frame")
  end
  
  local frame = ConsumeHelper.depositFrame
  frame.queue = itemsToDeposit
  frame.currentIndex = 1
  frame.totalDeposited = 0
  frame.delay = 0.1
  frame.timer = 0
  
  frame:SetScript("OnUpdate", function()
    frame.timer = frame.timer + arg1
    
    if frame.timer >= frame.delay then
      frame.timer = 0
      
      if frame.currentIndex > getn(frame.queue) then
        -- Done depositing, now restack
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00Deposited " .. frame.totalDeposited .. " consume items. Restacking...|r")
        frame:SetScript("OnUpdate", nil)
        
        -- Restack bags after deposit
        ConsumeHelper.RestackBags(function()
          DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00Restack complete.|r")
          
          -- Refresh the list to show updated counts
          local manageFrame = getglobal("OGRH_ManageConsumesFrame")
          if manageFrame then
            ConsumeHelper.PopulateManageConsumesList(manageFrame)
          end
        end)
        return
      end
      
      local item = frame.queue[frame.currentIndex]
      frame.currentIndex = frame.currentIndex + 1
      
      -- Pick up the item from bag
      PickupContainerItem(item.bag, item.slot)
      
      -- Deposit into bank
      if CursorHasItem() then
        local deposited = false
        
        -- Find empty slot in base bank
        for bankSlot = 1, 28 do
          local texture = GetContainerItemInfo(-1, bankSlot)
          if not texture then
            PutItemInBag(BankButtonIDToInvSlotID(bankSlot))
            deposited = true
            break
          end
        end
        
        -- If not deposited, check bank bags for empty slots
        if not deposited then
          for bankBag = 5, 11 do
            local numBankSlots = GetContainerNumSlots(bankBag)
            if numBankSlots and numBankSlots > 0 then
              for bankBagSlot = 1, numBankSlots do
                local texture = GetContainerItemInfo(bankBag, bankBagSlot)
                if not texture then
                  PickupContainerItem(bankBag, bankBagSlot)
                  deposited = true
                  break
                end
              end
              if deposited then break end
            end
          end
        end
        
        if deposited then
          frame.totalDeposited = frame.totalDeposited + 1
        else
          -- Bank full, put item back and stop
          PickupContainerItem(item.bag, item.slot)
          DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00Deposited " .. frame.totalDeposited .. " consume items.|r |cffff0000Bank is now full!|r")
          frame:SetScript("OnUpdate", nil)
        end
      end
    end
  end)
end

-- Withdraw consumes from bank to bags based on current list
function ConsumeHelper.WithdrawConsumes()
  -- Get the manage consumes frame
  local frame = getglobal("OGRH_ManageConsumesFrame")
  if not frame or not frame.withdrawBox or not frame.consumeScrollChild then return end
  
  -- Get multiplier from textbox
  local multiplierText = frame.withdrawBox:GetText()
  local multiplier = tonumber(multiplierText) or 1
  if multiplier < 1 then multiplier = 1 end
  
  -- Check if raid is selected
  if not ConsumeHelper.manageConsumesData or not ConsumeHelper.manageConsumesData.selectedRaid then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000Select a raid first.|r")
    return
  end
  
  -- Read items from the already-populated list
  local scrollChild = frame.consumeScrollChild
  local children = {scrollChild:GetChildren()}
  local itemsToWithdraw = {}
  
  for i = 1, getn(children) do
    local child = children[i]
    if child.itemData then
      table.insert(itemsToWithdraw, child.itemData)
    end
  end
  
  if getn(itemsToWithdraw) == 0 then
    DEFAULT_CHAT_FRAME:AddMessage("|cffffff00No consumes in the current list.|r")
    return
  end
  
  -- Build withdraw queue with calculated amounts
  local withdrawQueue = {}
  for i = 1, getn(itemsToWithdraw) do
    local itemData = itemsToWithdraw[i]
    local needed = (itemData.quantity or 0) * multiplier
    local have = CountItemInBags(itemData.itemId)
    local deficit = needed - have
    
    if deficit > 0 then
      table.insert(withdrawQueue, {
        itemId = itemData.itemId,
        targetAmount = needed,
        amount = deficit
      })
    end
  end
  
  if getn(withdrawQueue) == 0 then
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00You already have enough of all consumes.|r")
    return
  end
  
  -- Create withdraw frame if it doesn't exist
  if not ConsumeHelper.withdrawFrame then
    ConsumeHelper.withdrawFrame = CreateFrame("Frame")
  end
  
  local wFrame = ConsumeHelper.withdrawFrame
  wFrame.queue = withdrawQueue
  wFrame.currentIndex = 1
  wFrame.totalWithdrawn = 0
  wFrame.delay = 0.2
  wFrame.timer = 0
  wFrame.pendingSplit = nil
  
  wFrame:SetScript("OnUpdate", function()
    wFrame.timer = wFrame.timer + arg1
    
    if wFrame.timer >= wFrame.delay then
      wFrame.timer = 0
      
      -- Check if we're waiting for a return-to-bank operation
      if wFrame.pendingSplit then
        wFrame.pendingSplit.waitTime = (wFrame.pendingSplit.waitTime or 0) + wFrame.delay
        
        if wFrame.pendingSplit.waitTime >= 0.4 then
          -- Operation complete, move on
          wFrame.totalWithdrawn = wFrame.totalWithdrawn + wFrame.pendingSplit.amount
          wFrame.pendingSplit = nil
        end
        return
      end
      
      if wFrame.currentIndex > getn(wFrame.queue) then
        -- Done withdrawing, now restack
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00Withdrew " .. wFrame.totalWithdrawn .. " consume items. Restacking...|r")
        wFrame:SetScript("OnUpdate", nil)
        
        -- Restack bags after withdraw
        ConsumeHelper.RestackBags(function()
          DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00Restack complete.|r")
          
          -- Refresh the list to show updated counts
          local frame = getglobal("OGRH_ManageConsumesFrame")
          if frame then
            ConsumeHelper.PopulateManageConsumesList(frame)
          end
        end)
        return
      end
      
      local item = wFrame.queue[wFrame.currentIndex]
      
      -- Get how much we still need (recalculate each tick)
      local needed = item.targetAmount
      local have = CountItemInBags(item.itemId)
      local stillNeeded = needed - have
      
      if stillNeeded <= 0 then
        -- We have enough now, move to next item
        wFrame.currentIndex = wFrame.currentIndex + 1
        return
      end
      
      -- Find item in bank (do this fresh each tick)
      -- Scan all locations and find items with appropriate charges/counts
      local foundStacks = {}
      
      -- Charge-based items (wizard oils) where we track charges not items
      local chargeBasedItems = {
        [20748] = true, -- Brilliant Mana Oil
        [20749] = true, -- Brilliant Wizard Oil
        [20750] = true, -- Wizard Oil
        [20745] = true, -- Minor Wizard Oil
        [20746] = true, -- Lesser Wizard Oil
        [20744] = true, -- Minor Mana Oil
        [20747] = true, -- Lesser Mana Oil
      }
      
      local isChargeBased = chargeBasedItems[item.itemId]
      
      -- Check base bank slots first
      for slot = 1, 28 do
        local itemLink = GetContainerItemLink(-1, slot)
        if itemLink then
          local _, count = GetContainerItemInfo(-1, slot)
          local _, _, itemIdStr = string.find(itemLink, "item:(%d+)")
          local itemId = tonumber(itemIdStr)
          if itemId == item.itemId then
            count = tonumber(count) or 1
            -- WoW 1.12.1 returns negative numbers for items with charges
            if isChargeBased and count < 0 then
              count = math.abs(count)
            end
            -- Include all items (we'll sort and take what we need)
            table.insert(foundStacks, {bag = -1, slot = slot, count = count})
          end
        end
      end
      
      -- Check bank bags
      for bag = 5, 11 do
        local numSlots = GetContainerNumSlots(bag)
        if numSlots and numSlots > 0 then
          for slot = 1, numSlots do
            local itemLink = GetContainerItemLink(bag, slot)
            if itemLink then
              local _, count = GetContainerItemInfo(bag, slot)
              local _, _, itemIdStr = string.find(itemLink, "item:(%d+)")
              local itemId = tonumber(itemIdStr)
              if itemId == item.itemId then
                count = tonumber(count) or 1
                -- WoW 1.12.1 returns negative numbers for items with charges
                if isChargeBased and count < 0 then
                  count = math.abs(count)
                end
                -- Include all items (we'll sort and take what we need)
                table.insert(foundStacks, {bag = bag, slot = slot, count = count})
              end
            end
          end
        end
      end
      
      if getn(foundStacks) == 0 then
        -- Item not found in bank
        DEFAULT_CHAT_FRAME:AddMessage("|cffffff00Could not find enough " .. (GetItemInfo(item.itemId) or item.itemId) .. " in bank.|r")
        wFrame.currentIndex = wFrame.currentIndex + 1
        return
      end
      
      -- Sort by count ascending (smallest first)
      table.sort(foundStacks, function(a, b) return a.count < b.count end)
      
      -- Take from smallest stack
      local bankBag = foundStacks[1].bag
      local bankSlot = foundStacks[1].slot
      local bankCount = foundStacks[1].count
      
      -- Find empty or partial stack in bags
      local emptyBag, emptySlot = nil, nil
      local partialBag, partialSlot, partialCount = nil, nil, 0
      
      -- For charge-based items, skip partial stack logic (can't merge them)
      if not chargeBasedItems[item.itemId] then
        -- First look for partial stacks of this item
        for bag = 0, 4 do
          for slot = 1, GetContainerNumSlots(bag) do
            local itemLink = GetContainerItemLink(bag, slot)
            if itemLink then
              local _, count = GetContainerItemInfo(bag, slot)
              local _, _, bagItemId = string.find(itemLink, "item:(%d+)")
              bagItemId = tonumber(bagItemId)
              
              if bagItemId == item.itemId and count and count < 20 then
                -- Found partial stack
                if not partialBag or count > partialCount then
                  partialBag = bag
                  partialSlot = slot
                  partialCount = count
                end
              end
            elseif not emptyBag then
              -- Remember first empty slot
              emptyBag = bag
              emptySlot = slot
            end
          end
        end
      end
      
      -- For charge-based items or if no partial found, look for empty slots
      if chargeBasedItems[item.itemId] or not partialBag then
        for bag = 0, 4 do
          for slot = 1, GetContainerNumSlots(bag) do
            local itemLink = GetContainerItemLink(bag, slot)
            if not itemLink and not emptyBag then
              emptyBag = bag
              emptySlot = slot
              break
            end
          end
          if emptyBag then break end
        end
      end
      
      -- Use partial stack if found, otherwise empty slot
      local targetBag = partialBag or emptyBag
      local targetSlot = partialSlot or emptySlot
      
      if not targetBag then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000No bag space available.|r")
        wFrame:SetScript("OnUpdate", nil)
        return
      end
      
      -- For charge-based items, never try to split - always take whole item
      local isChargeBased = chargeBasedItems[item.itemId]
      if isChargeBased or stillNeeded >= bankCount then
        -- Take the whole item/stack
        PickupContainerItem(bankBag, bankSlot)
        if CursorHasItem() then
          PickupContainerItem(targetBag, targetSlot)
          wFrame.totalWithdrawn = wFrame.totalWithdrawn + bankCount
        end
      else
        -- Need less than full stack - split only what we need
        SplitContainerItem(bankBag, bankSlot, stillNeeded)
        PickupContainerItem(targetBag, targetSlot)
        
        -- Mark pending to wait for split to complete
        wFrame.pendingSplit = {itemId = item.itemId, amount = stillNeeded, waitTime = 0}
        return
      end
    end
  end)
end

-- Restack partial stacks in bags to consolidate items
-- Based on Bagshui's restack implementation
function ConsumeHelper.RestackBags(onComplete)
  -- Build inventory cache of all bag items
  local itemStacks = {}  -- [itemId] = { {bag, slot, count, maxStack}, ... }
  
  -- Blacklist of non-stackable items that appear stackable (items with charges)
  local nonStackableItems = {
    [20748] = true, -- Brilliant Mana Oil
    [20749] = true, -- Brilliant Wizard Oil
    [20750] = true, -- Wizard Oil
    [20745] = true, -- Minor Wizard Oil
    [20746] = true, -- Lesser Wizard Oil
    [20744] = true, -- Minor Mana Oil
    [20747] = true, -- Lesser Mana Oil
  }
  
  for bag = 0, 4 do
    local numSlots = GetContainerNumSlots(bag)
    for slot = 1, numSlots do
      local texture, count, locked = GetContainerItemInfo(bag, slot)
      if texture and not locked then
        local link = GetContainerItemLink(bag, slot)
        if link then
          local _, _, itemId = string.find(link, "item:(%d+)")
          itemId = tonumber(itemId)
          if itemId and not nonStackableItems[itemId] then
            -- Get stack size from item info
            local _, _, _, _, _, _, _, maxStack = GetItemInfo(itemId)
            count = tonumber(count) or 1
            maxStack = tonumber(maxStack) or 20
            
            -- Skip non-stackable items (maxStack = 1, like wizard oils with charges)
            -- Only track partial stacks of actually stackable items
            if maxStack > 1 and count < maxStack then
              if not itemStacks[itemId] then
                itemStacks[itemId] = {}
              end
              table.insert(itemStacks[itemId], {
                bag = bag,
                slot = slot,
                count = count,
                maxStack = maxStack
              })
            end
          end
        end
      end
    end
  end
  
  -- Build queue of moves (source, target pairs)
  local moveQueue = {}
  
  for itemId, stacks in pairs(itemStacks) do
    -- Only process if we have multiple partial stacks
    if getn(stacks) > 1 then
      -- Sort from largest to smallest
      table.sort(stacks, function(a, b) return a.count > b.count end)
      
      -- Try to fill largest stacks by pulling from smallest
      for targetIdx = 1, getn(stacks) - 1 do
        local target = stacks[targetIdx]
        
        if target.count < target.maxStack then
          -- Work backwards through sources (smallest stacks first)
          for sourceIdx = getn(stacks), 2, -1 do
            local source = stacks[sourceIdx]
            
            if source.count > 0 and target.count < target.maxStack then
              -- Queue this move
              table.insert(moveQueue, {
                sourceBag = source.bag,
                sourceSlot = source.slot,
                targetBag = target.bag,
                targetSlot = target.slot
              })
              
              -- Update counts for planning purposes
              local moved = math.min(source.count, target.maxStack - target.count)
              target.count = target.count + moved
              source.count = source.count - moved
            end
          end
        end
      end
    end
  end
  
  -- Execute the move queue
  if getn(moveQueue) > 0 then
    local frame = CreateFrame("Frame")
    frame.queue = moveQueue
    frame.currentIndex = 1
    frame.timer = 0
    frame.delay = 0.15  -- Delay between moves
    frame.onComplete = onComplete
    frame.retryCount = 0
    frame.maxRetries = 3
    
    frame:SetScript("OnUpdate", function()
      frame.timer = frame.timer + arg1
      
      if frame.timer >= frame.delay then
        frame.timer = 0
        
        if frame.currentIndex > getn(frame.queue) then
          -- Done
          frame:SetScript("OnUpdate", nil)
          if frame.onComplete then
            frame.onComplete()
          end
          return
        end
        
        local move = frame.queue[frame.currentIndex]
        
        -- Check if items are locked
        local _, _, sourceLocked = GetContainerItemInfo(move.sourceBag, move.sourceSlot)
        local _, _, targetLocked = GetContainerItemInfo(move.targetBag, move.targetSlot)
        
        if not sourceLocked and not targetLocked then
          -- Perform the move (pickup source, then pickup target to swap/merge)
          PickupContainerItem(move.sourceBag, move.sourceSlot)
          if CursorHasItem() then
            PickupContainerItem(move.targetBag, move.targetSlot)
          end
          
          -- Check if move succeeded (cursor should be empty after successful merge)
          if not CursorHasItem() then
            -- Success, move to next item
            frame.currentIndex = frame.currentIndex + 1
            frame.retryCount = 0
          else
            -- Failed - item couldn't be merged (probably non-stackable)
            -- Clear cursor and skip this item
            ClearCursor()
            frame.currentIndex = frame.currentIndex + 1
            frame.retryCount = 0
          end
        else
          -- Items locked, retry with counter
          frame.retryCount = frame.retryCount + 1
          if frame.retryCount >= frame.maxRetries then
            -- Give up on this item and move to next
            frame.currentIndex = frame.currentIndex + 1
            frame.retryCount = 0
          end
        end
      end
    end)
  else
    -- No restacking needed
    if onComplete then
      onComplete()
    end
  end
end

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
--   Manage Consumes Window --
------------------------------

-- Show Manage Consumes window
function ConsumeHelper.ShowManageConsumes()
  -- Create or show window
  local frame = getglobal("OGRH_ManageConsumesFrame")
  if frame then
    -- Check bank state when showing existing window
    local isBankOpen = false
    for i = 5, 11 do
      if GetContainerNumSlots(i) and GetContainerNumSlots(i) > 0 then
        isBankOpen = true
        break
      end
    end
    
    if isBankOpen then
      frame.bankPanel:Show()
    else
      frame.bankPanel:Hide()
    end
    OGST.RepositionDockedPanels()
    
    frame:Show()
    return
  end
  
  -- Create window using OGST
  frame = OGST.CreateStandardWindow({
    name = "OGRH_ManageConsumesFrame",
    width = 250,
    height = 400,
    title = "Consumes",
    closeButton = true,
    escapeCloses = true,
    closeOnNewWindow = true
  })
  
  -- Add Setup button to left side of title bar
  local setupBtn = CreateFrame("Button", nil, frame.headerFrame, "UIPanelButtonTemplate")
  setupBtn:SetWidth(60)
  setupBtn:SetHeight(20)
  setupBtn:SetText("Setup")
  setupBtn:SetPoint("LEFT", frame.headerFrame, "LEFT", 5, 0)
  OGST.StyleButton(setupBtn)
  setupBtn:SetScript("OnClick", function()
    OGRH.ShowConsumeHelper()
  end)
  
  local contentFrame = frame.contentFrame
  
  -- Create content panel using OGST
  local contentPanel = OGST.CreateContentPanel(contentFrame, {
    name = "OGRH_ManageConsumesContentPanel",
    fillParent = true
  })
  contentPanel:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
  
  frame.contentPanel = contentPanel
  
  -- Build menu items for raids
  local raidMenuItems = {}
  for _, raid in ipairs(ConsumeHelper.data.raids) do
    local raidName = raid.name
    table.insert(raidMenuItems, {
      text = raidName,
      onClick = function()
        if not ConsumeHelper.manageConsumesData then
          ConsumeHelper.manageConsumesData = {}
        end
        ConsumeHelper.manageConsumesData.selectedRaid = raidName
        frame.raidButton:SetText(raidName)
        ConsumeHelper.PopulateManageConsumesList(frame)
      end
    })
  end
  
  -- Create raid menu button using OGST
  local raidButtonContainer, raidButton, raidMenu = OGST.CreateMenuButton(contentPanel, {
    label = "Select",
    labelAnchor = "LEFT",
    labelWidth = 70,
    buttonText = "Raid",
    buttonHeight = 24,
    fillWidth = true,
    singleSelect = true,
    menuItems = raidMenuItems
  })
  raidButtonContainer:SetPoint("TOPLEFT", contentPanel, "TOPLEFT", 5, -5)
  
  frame.raidButton = raidButton
  frame.raidButtonContainer = raidButtonContainer
  frame.raidMenu = raidMenu
  
  -- Create consume list below the menu button, filling remaining space
  local listFrame, scrollFrame, scrollChild, scrollBar, contentWidth = OGST.CreateStyledScrollList(
    contentPanel,
    240,  -- Fixed width for list container
    1,  -- Height will be controlled by anchoring
    false
  )
  
  -- Anchor list to fill remaining space below menu button
  OGST.AnchorElement(listFrame, raidButtonContainer, {
    position = "fillBelow",
    gap = 5,
    padding = 5
  })
  
  frame.consumeListFrame = listFrame
  frame.consumeScrollFrame = scrollFrame
  frame.consumeScrollChild = scrollChild
  frame.consumeScrollBar = scrollBar
  frame.consumeContentWidth = contentWidth
  
  -- Create bank action docked panel (hidden by default)
  local bankPanel = CreateFrame("Frame", "OGRH_BankActionsPanel", UIParent)
  bankPanel:SetHeight(40)
  bankPanel:EnableMouse(true)
  bankPanel:Hide()
  
  -- Register as docked panel at bottom of consume window
  OGST.RegisterDockedPanel(bankPanel, {
    parentFrame = frame,
    axis = "vertical",
    preferredSide = "bottom",
    priority = 1,
    autoMove = true,
    hideInCombat = false,
    title = ""
  })
  
  -- Deposit button
  local depositBtn = CreateFrame("Button", nil, bankPanel, "UIPanelButtonTemplate")
  depositBtn:SetWidth(80)
  depositBtn:SetHeight(25)
  depositBtn:SetText("Deposit")
  depositBtn:SetPoint("LEFT", bankPanel, "LEFT", 10, 0)
  OGST.StyleButton(depositBtn)
  
  -- Deposit button click handler
  depositBtn:SetScript("OnClick", function()
    ConsumeHelper.DepositConsumes()
  end)
  
  -- Withdraw button (directly next to Deposit)
  local withdrawBtn = CreateFrame("Button", nil, bankPanel, "UIPanelButtonTemplate")
  withdrawBtn:SetWidth(80)
  withdrawBtn:SetHeight(25)
  withdrawBtn:SetText("Withdraw")
  withdrawBtn:SetPoint("LEFT", depositBtn, "RIGHT", 5, 0)
  OGST.StyleButton(withdrawBtn)
  
  -- Withdraw button click handler
  withdrawBtn:SetScript("OnClick", function()
    ConsumeHelper.WithdrawConsumes()
  end)
  
  -- x label
  local xLabel = bankPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  xLabel:SetText("x")
  xLabel:SetPoint("LEFT", withdrawBtn, "RIGHT", 10, 0)
  
  -- Withdraw amount textbox
  local withdrawBox = CreateFrame("EditBox", nil, bankPanel)
  withdrawBox:SetWidth(30)
  withdrawBox:SetHeight(20)
  withdrawBox:SetPoint("LEFT", xLabel, "RIGHT", 5, 0)
  withdrawBox:SetAutoFocus(false)
  withdrawBox:SetFontObject(GameFontHighlight)
  withdrawBox:SetMaxLetters(2)
  withdrawBox:SetNumeric(true)
  withdrawBox:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 16,
    insets = {left = 3, right = 3, top = 3, bottom = 3}
  })
  withdrawBox:SetBackdropColor(0, 0, 0, 1)
  withdrawBox:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
  withdrawBox:SetTextInsets(5, 5, 0, 0)
  withdrawBox:SetScript("OnEscapePressed", function() this:ClearFocus() end)
  withdrawBox:SetScript("OnEnterPressed", function() this:ClearFocus() end)
  
  frame.bankPanel = bankPanel
  frame.withdrawBox = withdrawBox
  
  -- Set default multiplier value immediately and on show
  withdrawBox:SetText("1")
  local oldOnShow = frame:GetScript("OnShow")
  frame:SetScript("OnShow", function()
    if oldOnShow then oldOnShow() end
    -- Always ensure multiplier has a default value when window shows
    if not withdrawBox:GetText() or withdrawBox:GetText() == "" then
      withdrawBox:SetText("1")
    end
    -- Check if bank is already open and show panel
    local isBankOpen = false
    for i = 5, 11 do
      if GetContainerNumSlots(i) then
        isBankOpen = true
        break
      end
    end
    if isBankOpen then
      bankPanel:Show()
      OGST.RepositionDockedPanels()
    end
  end)
  
  -- Register for bank and bag events
  frame:RegisterEvent("BANKFRAME_OPENED")
  frame:RegisterEvent("BANKFRAME_CLOSED")
  frame:RegisterEvent("BAG_UPDATE")
  frame:RegisterEvent("BAG_UPDATE_COOLDOWN")
  frame:SetScript("OnEvent", function()
    if event == "BANKFRAME_OPENED" then
      bankPanel:Show()
      OGST.RepositionDockedPanels()
      -- Set multiplier default when bank opens
      if not withdrawBox:GetText() or withdrawBox:GetText() == "" then
        withdrawBox:SetText("1")
      end
    elseif event == "BANKFRAME_CLOSED" then
      bankPanel:Hide()
      OGST.RepositionDockedPanels()
    elseif event == "BAG_UPDATE" or event == "BAG_UPDATE_COOLDOWN" then
      -- Refresh list to update counts
      ConsumeHelper.PopulateManageConsumesList(frame)
    end
  end)
  
  -- Populate the consume list
  ConsumeHelper.PopulateManageConsumesList(frame)
  
  -- Check initial bank state and update panel visibility
  local isBankOpen = false
  for i = 5, 11 do
    if GetContainerNumSlots(i) and GetContainerNumSlots(i) > 0 then
      isBankOpen = true
      break
    end
  end
  
  if isBankOpen then
    bankPanel:Show()
  else
    bankPanel:Hide()
  end
  OGST.RepositionDockedPanels()
  
  frame:Show()
end

-- Populate the consume list in the Manage Consumes window
function ConsumeHelper.PopulateManageConsumesList(frame)
  if not frame or not frame.consumeScrollChild then return end
  
  local scrollChild = frame.consumeScrollChild
  local contentWidth = frame.consumeContentWidth
  
  -- Clear existing items
  local children = {scrollChild:GetChildren()}
  for _, child in ipairs(children) do
    child:Hide()
    child:SetParent(nil)
  end
  
  -- Check if raid is selected
  if not ConsumeHelper.manageConsumesData or not ConsumeHelper.manageConsumesData.selectedRaid then
    scrollChild:SetHeight(1)
    return
  end
  
  local selectedRaidName = ConsumeHelper.manageConsumesData.selectedRaid
  
  -- Get player name and class
  local playerName = UnitName("player")
  local localizedClass, playerClass = UnitClass("player")
  playerClass = string.upper(string.sub(playerClass, 1, 1)) .. string.lower(string.sub(playerClass, 2))
  
  -- Check if player has assigned roles
  OGRH_ConsumeHelper_SV.playerRoles = OGRH_ConsumeHelper_SV.playerRoles or {}
  local playerData = OGRH_ConsumeHelper_SV.playerRoles[playerName]
  
  -- Find the first assigned role for this player
  local playerRole = nil
  if playerData and ConsumeHelper.data and ConsumeHelper.data.roles then
    local roles = ConsumeHelper.data.roles
    for i = 1, getn(roles) do
      local roleName = roles[i]
      if playerData[roleName] then
        playerRole = roleName
        break
      end
    end
  end
  
  -- If no role assigned, show empty
  if not playerRole then
    scrollChild:SetHeight(1)
    return
  end
  
  -- Get items for this raid
  OGRH_ConsumeHelper_SV.consumes = OGRH_ConsumeHelper_SV.consumes or {}
  local raidData = OGRH_ConsumeHelper_SV.consumes[selectedRaidName]
  
  -- Collect items to display
  local itemsToShow = {}
  
  -- Add selected raid items (combine all: role, class, All)
  if raidData then
    local raidItems = {}
    if raidData[playerRole] then
      for i = 1, getn(raidData[playerRole]) do
        table.insert(raidItems, raidData[playerRole][i])
      end
    end
    if raidData[playerClass] then
      for i = 1, getn(raidData[playerClass]) do
        table.insert(raidItems, raidData[playerClass][i])
      end
    end
    if raidData["All"] then
      for i = 1, getn(raidData["All"]) do
        table.insert(raidItems, raidData["All"][i])
      end
    end
    if getn(raidItems) > 0 then
      table.insert(itemsToShow, {header = selectedRaidName, items = raidItems})
    end
  end
  
  -- Add General items if we're not viewing General
  if selectedRaidName ~= "General" then
    local generalData = OGRH_ConsumeHelper_SV.consumes["General"]
    if generalData then
      local generalItems = {}
      if generalData[playerRole] then
        for i = 1, getn(generalData[playerRole]) do
          table.insert(generalItems, generalData[playerRole][i])
        end
      end
      if generalData[playerClass] then
        for i = 1, getn(generalData[playerClass]) do
          table.insert(generalItems, generalData[playerClass][i])
        end
      end
      if generalData["All"] then
        for i = 1, getn(generalData["All"]) do
          table.insert(generalItems, generalData["All"][i])
        end
      end
      if getn(generalItems) > 0 then
        table.insert(itemsToShow, {header = "General", items = generalItems})
      end
    end
  end
  
  -- If no items to show, display empty
  if getn(itemsToShow) == 0 then
    scrollChild:SetHeight(1)
    return
  end
  
  local yOffset = 0
  local rowHeight = OGST.LIST_ITEM_HEIGHT
  local rowSpacing = OGST.LIST_ITEM_SPACING
  local headerHeight = 20
  
  -- Display all sections
  for sectionIdx = 1, getn(itemsToShow) do
    local section = itemsToShow[sectionIdx]
    
    -- Create header
    local headerItem = OGST.CreateStyledListItem(scrollChild, nil, headerHeight, "Frame")
    headerItem:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yOffset)
    OGST.SetListItemColor(headerItem, 0.15, 0.15, 0.15, 1)
    
    local headerText = headerItem:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    headerText:SetPoint("LEFT", headerItem, "LEFT", 5, 0)
    headerText:SetText(section.header)
    headerText:SetTextColor(1, 0.82, 0)
    
    yOffset = yOffset + headerHeight + rowSpacing
    
    -- Sort items alphabetically by item name
    local items = section.items
    local sortedItems = {}
    for i = 1, getn(items) do
      local itemData = items[i]
      local itemName = GetItemInfo(itemData.itemId) or ""
      table.insert(sortedItems, {name = itemName, data = itemData})
    end
    table.sort(sortedItems, function(a, b) return a.name < b.name end)
    
    -- Display items in this section
    for i = 1, getn(sortedItems) do
      local itemData = sortedItems[i].data
      local itemName = sortedItems[i].name
      local item = OGST.CreateStyledListItem(scrollChild, nil, rowHeight, "Button")
      item:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yOffset)
      
      -- Store itemData on the button for later retrieval
      item.itemData = itemData
      
      -- Get item count in inventory
      local itemCount = CountItemInBags(itemData.itemId) or 0
      local neededCount = tonumber(itemData.quantity) or 0
      
      if itemName and itemName ~= "" then
        -- Item name on left
        local nameText = item:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        nameText:SetPoint("LEFT", item, "LEFT", 5, 0)
        nameText:SetText(itemName)
        nameText:SetTextColor(1, 1, 1)
        
        -- Count on right (X / Y)
        local countText = item:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        countText:SetPoint("RIGHT", item, "RIGHT", -5, 0)
        countText:SetText(itemCount .. " / " .. neededCount)
        
        -- Color based on whether player has enough
        if itemCount >= neededCount then
          countText:SetTextColor(0, 1, 0)  -- Green
        else
          countText:SetTextColor(1, 0, 0)  -- Red
        end
      end
      
      yOffset = yOffset + rowHeight + rowSpacing
    end
  end
  
  scrollChild:SetHeight(math.max(1, yOffset))
  
  -- Update scrollbar to enable scrolling
  if frame.consumeScrollFrame and frame.consumeScrollFrame.UpdateScrollBar then
    frame.consumeScrollFrame.UpdateScrollBar()
  end
end

-- Show raid selection menu
function ConsumeHelper.ShowRaidSelectionMenu()
  local frame = getglobal("OGRH_ManageConsumesFrame")
  if not frame or not frame.raidMenu then return end
  
  local menu = frame.raidMenu
  
  -- Position menu below button
  menu:ClearAllPoints()
  menu:SetPoint("TOP", frame.raidButtonContainer, "BOTTOM", 0, -2)
  menu:Show()
end

-- Refresh the consume list
function ConsumeHelper.RefreshManageConsumes()
  local frame = getglobal("OGRH_ManageConsumesFrame")
  if not frame then return end
  
  local scrollChild = frame.scrollChild
  local contentWidth = frame.contentWidth
  
  -- Clear existing items
  local children = {scrollChild:GetChildren()}
  for _, child in ipairs(children) do
    child:Hide()
    child:SetParent(nil)
  end
  
  -- Check if raid is selected
  if not ConsumeHelper.manageConsumesData or not ConsumeHelper.manageConsumesData.selectedRaid then
    -- Show instruction text
    local infoText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    infoText:SetPoint("TOP", scrollChild, "TOP", 0, -20)
    infoText:SetText("|cff888888Select a raid|r")
    infoText:SetWidth(contentWidth - 10)
    infoText:SetJustifyH("CENTER")
    scrollChild:SetHeight(1)
    return
  end
  
  local raidName = ConsumeHelper.manageConsumesData.selectedRaid
  
  -- Get player's class
  local _, playerClass = UnitClass("player")
  
  -- Get player's configured role from playerRoles
  local playerName = UnitName("player")
  local playerRole = nil
  
  if OGRH_ConsumeHelper_SV.playerRoles and OGRH_ConsumeHelper_SV.playerRoles[playerName] then
    -- Find any role that is set to true (ignoring "class" key)
    for roleName, isAssigned in pairs(OGRH_ConsumeHelper_SV.playerRoles[playerName]) do
      if roleName ~= "class" and isAssigned then
        playerRole = roleName
        break
      end
    end
  end
  
  -- Try to find consumes - first by role, then by class name variations
  local consumes = {}
  local lookupKey = nil
  
  if OGRH_ConsumeHelper_SV.consumes and OGRH_ConsumeHelper_SV.consumes[raidName] then
    local raidData = OGRH_ConsumeHelper_SV.consumes[raidName]
    
    -- Try role first (e.g., "Tank")
    if playerRole and raidData[playerRole] then
      consumes = raidData[playerRole]
      lookupKey = playerRole
    -- Try all caps class (e.g., "PALADIN")
    elseif raidData[playerClass] then
      consumes = raidData[playerClass]
      lookupKey = playerClass
    -- Try proper case (e.g., "Paladin")
    else
      local properClass = string.sub(playerClass, 1, 1) .. string.lower(string.sub(playerClass, 2))
      if raidData[properClass] then
        consumes = raidData[properClass]
        lookupKey = properClass
      end
    end
  end
  
  -- If no consumes configured
  if getn(consumes) == 0 then
    local infoText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    infoText:SetPoint("TOP", scrollChild, "TOP", 0, -20)
    local displayName = playerRole or playerClass
    infoText:SetText("|cff888888No consumes\nconfigured for\n" .. displayName .. "|r")
    infoText:SetWidth(contentWidth - 10)
    infoText:SetJustifyH("CENTER")
    scrollChild:SetHeight(1)
    return
  end
  
  -- Populate consume list
  local yOffset = 0
  local rowHeight = 40
  local rowSpacing = OGST.LIST_ITEM_SPACING
  
  for i, consumeData in ipairs(consumes) do
    local item = OGST.CreateStyledListItem(scrollChild, contentWidth, rowHeight)
    item:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yOffset)
    
    -- Get item info
    local itemName, itemLink, itemQuality, _, _, _, _, _, _, itemTexture = GetItemInfo(consumeData.itemId)
    
    -- Item icon
    local icon = item:CreateTexture(nil, "ARTWORK")
    icon:SetWidth(32)
    icon:SetHeight(32)
    icon:SetPoint("LEFT", item, "LEFT", 5, 0)
    if itemTexture then
      icon:SetTexture(itemTexture)
    else
      icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    end
    
    -- Item name and quantity
    local nameText = item:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameText:SetPoint("TOPLEFT", icon, "TOPRIGHT", 5, -2)
    nameText:SetPoint("RIGHT", item, "RIGHT", -5, 0)
    nameText:SetJustifyH("LEFT")
    nameText:SetTextColor(1, 1, 1)
    
    if itemName then
      -- Color by quality
      if itemQuality then
        local r, g, b = GetItemQualityColor(itemQuality)
        nameText:SetTextColor(r, g, b)
      end
      nameText:SetText(itemName)
    else
      nameText:SetText("Item " .. consumeData.itemId)
    end
    
    -- Quantity
    local qtyText = item:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    qtyText:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 5, 0)
    qtyText:SetText("Quantity: " .. (consumeData.quantity or 1))
    qtyText:SetTextColor(0.8, 0.8, 0.8)
    
    yOffset = yOffset + rowHeight + rowSpacing
  end
  
  scrollChild:SetHeight(math.max(1, yOffset))
end

------------------------------
--   Global Access          --
------------------------------

-- Make the show functions globally accessible
OGRH.ShowConsumeHelper = ConsumeHelper.ShowWindow
OGRH.ShowManageConsumes = ConsumeHelper.ShowManageConsumes

-- Initialize on load
OGRH.Msg("|cffffff66[RH-ConsumeHelper]|r module loaded.")
