-- OGRH_EncounterAdmin.lua
-- Admin Encounter Management
-- Provides automatic Admin encounter for every raid with special role types

if not OGRH then
  DEFAULT_CHAT_FRAME:AddMessage("|cffff0000Error: OGRH_EncounterAdmin requires OGRH_Core to be loaded first!|r")
  return
end

-- Initialize namespace
OGRH.EncounterAdmin = OGRH.EncounterAdmin or {}

-- ============================================
-- ADMIN ENCOUNTER TEMPLATE
-- ============================================
-- This template defines the structure of the Admin encounter
-- Modify this template to change default Admin encounter structure

local ADMIN_ENCOUNTER_TEMPLATE = {
  name = "Admin",
  displayName = "Raid Admin",
  roles = {
    -- Role 1: Master Looter
    {
      roleId = 1,
      name = "Master Looter",
      slots = 1,
      showRaidIcons = false,
      showAssignment = false,
      markPlayer = false,
      allowOtherRoles = true,
      linkRole = false,
      invertFillOrder = false,
      assignedPlayers = {},
      raidMarks = {0},
      assignmentNumbers = {0}
    },
    -- Role 2: Loot Settings
    {
      roleId = 2,
      name = "Loot Settings",
      isLootSettings = true,   -- Custom role flag
      lootMethod = "master",    -- "master" or "group"
      autoSwitch = false,       -- Auto-switch for trash/bosses
      threshold = "rare"        -- "uncommon", "rare", "epic"
    },
    -- Role 3: Disenchant
    {
      roleId = 3,
      name = "Disenchant",
      slots = 1,
      showRaidIcons = false,
      showAssignment = false,
      markPlayer = false,
      allowOtherRoles = true,
      linkRole = false,
      invertFillOrder = false,
      assignedPlayers = {},
      raidMarks = {0},
      assignmentNumbers = {0}
    },
    -- Role 4: Loot Rules
    {
      roleId = 4,
      name = "Loot Rules",
      isTextField = true,  -- Text field role flag
      textValue = ""
    },
    -- Role 5: Bagspace Buffer
    {
      roleId = 5,
      name = "Bagspace Buffer",
      slots = 1,
      showRaidIcons = false,
      showAssignment = false,
      markPlayer = false,
      allowOtherRoles = true,
      linkRole = false,
      invertFillOrder = false,
      assignedPlayers = {},
      raidMarks = {0},
      assignmentNumbers = {0}
    },
    -- Role 6: Discord
    {
      roleId = 6,
      name = "Discord",
      isTextField = true,
      textValue = ""
    },
    -- Role 7: SR Link
    {
      roleId = 7,
      name = "SR Link",
      isTextField = true,
      textValue = ""
    }
  }
}

-- ============================================
-- HELPER FUNCTIONS
-- ============================================

-- Deep copy a table (handles nested tables)
local function DeepCopy(original)
  local copy
  if type(original) == "table" then
    copy = {}
    for key, value in pairs(original) do
      copy[key] = DeepCopy(value)
    end
  else
    copy = original
  end
  return copy
end

-- ============================================
-- PUBLIC API FUNCTIONS
-- ============================================

--- Creates a fresh Admin encounter from the template
-- @return table Complete Admin encounter structure
function OGRH.CreateAdminEncounter()
  return DeepCopy(ADMIN_ENCOUNTER_TEMPLATE)
end

--- Checks if an encounter is the Admin encounter
-- @param encounter table Encounter object to check
-- @return boolean True if encounter is Admin encounter
function OGRH.IsAdminEncounter(encounter)
  return encounter and encounter.name == "Admin"
end

--- Ensures the Admin encounter exists at index 1 of the specified raid
-- Automatically adds Admin encounter if it doesn't exist
-- @param raidIdx number Raid index in SVM
function OGRH.EnsureAdminEncounter(raidIdx)
  if not raidIdx then
    return
  end
  
  OGRH.EnsureSV()
  local raids = OGRH.SVM.GetPath("encounterMgmt.raids")
  if not raids or not raids[raidIdx] then
    return
  end
  
  local raid = raids[raidIdx]
  if not raid.encounters then
    raid.encounters = {}
  end
  
  -- Check if first encounter is Admin
  if table.getn(raid.encounters) > 0 and raid.encounters[1].name == "Admin" then
    return -- Admin encounter already exists
  end
  
  -- Create and insert Admin encounter at index 1
  local adminEncounter = OGRH.CreateAdminEncounter()
  table.insert(raid.encounters, 1, adminEncounter)
  
  -- Write back to SVM
  OGRH.SVM.SetPath("encounterMgmt.raids[" .. raidIdx .. "]", raid)
  OGRH.SVM.Save()
  
  if OGRH.EncounterAdmin.debug then
    OGRH.Msg("|cff00ff00[RH-Admin]|r Admin encounter added to raid: " .. tostring(raid.name))
  end
end

--- Prevents sorting encounters above Admin encounter (index 1)
-- @param encounterIdx number Current encounter index
-- @param newIndex number Target index for move
-- @param encounter table Encounter to move
-- @return boolean True if move is allowed, false if blocked
function OGRH.CanMoveEncounterToIndex(encounterIdx, newIndex, encounter)
  -- Allow Admin to stay at or move to index 1
  if OGRH.IsAdminEncounter(encounter) and newIndex == 1 then
    return true
  end
  
  -- Block non-Admin encounters from moving to index 1
  if newIndex == 1 and not OGRH.IsAdminEncounter(encounter) then
    return false
  end
  
  return true
end

--- Applies loot settings from a Loot Settings role to the raid
-- Only works if player is Raid Leader or Assistant
-- @param lootSettingsRole table Role object with loot configuration
-- @return boolean Success status
function OGRH.ApplyLootSettings(lootSettingsRole)
  if not lootSettingsRole or not lootSettingsRole.isLootSettings then
    return false
  end
  
  -- Check if player can modify loot settings
  if GetNumRaidMembers() == 0 then
    OGRH.Msg("|cffff6666[RH-Admin]|r Not in a raid")
    return false
  end
  
  if not IsRaidLeader() and not IsRaidOfficer() then
    OGRH.Msg("|cffff6666[RH-Admin]|r Only Raid Leader or Assistants can change loot settings")
    return false
  end
  
  -- Apply loot method
  local method = lootSettingsRole.lootMethod or "master"
  if method == "master" then
    SetLootMethod("master")
  else
    SetLootMethod("group")
  end
  
  -- Apply loot threshold
  local threshold = lootSettingsRole.threshold or "rare"
  local thresholdValue = 2 -- Default to Uncommon
  if threshold == "uncommon" then
    thresholdValue = 2
  elseif threshold == "rare" then
    thresholdValue = 3
  elseif threshold == "epic" then
    thresholdValue = 4
  end
  SetLootThreshold(thresholdValue)
  
  -- Note: Auto-switch is handled by encounter events, not here
  
  OGRH.Msg("|cff00ff00[RH-Admin]|r Loot settings applied")
  return true
end

--- Gets formatted text for Loot Settings role (for announcements)
-- @param lootSettingsRole table Role object with loot configuration
-- @return string Formatted loot settings text
function OGRH.GetLootSettingsText(lootSettingsRole)
  if not lootSettingsRole or not lootSettingsRole.isLootSettings then
    return ""
  end
  
  local methodText = (lootSettingsRole.lootMethod == "master") and "Master Looter" or "Group Loot"
  local autoText = lootSettingsRole.autoSwitch and " (Auto-Switch: ON)" or ""
  local thresholdText = lootSettingsRole.threshold or "rare"
  thresholdText = string.upper(string.sub(thresholdText, 1, 1)) .. string.sub(thresholdText, 2)
  
  return methodText .. autoText .. " | Threshold: " .. thresholdText
end

-- ============================================
-- INTEGRATION HOOKS
-- ============================================

--- Hook into raid creation to ensure Admin encounter
-- Called when a new raid is created or when Active Raid changes
local function OnRaidCreated(raidIdx)
  OGRH.EnsureAdminEncounter(raidIdx)
end

--- Hook into encounter sorting to prevent moving above Admin
-- Called before an encounter is moved
local function OnEncounterMoveAttempt(raidIdx, encounterIdx, newIndex)
  local raids = OGRH.SVM.GetPath("encounterMgmt.raids")
  if not raids or not raids[raidIdx] or not raids[raidIdx].encounters then
    return true
  end
  
  local encounter = raids[raidIdx].encounters[encounterIdx]
  if not encounter then
    return true
  end
  
  if not OGRH.CanMoveEncounterToIndex(encounterIdx, newIndex, encounter) then
    OGRH.Msg("|cffff6666[RH-Admin]|r Cannot move encounters above Admin encounter")
    return false
  end
  
  return true
end

-- Register hooks (these will be called by EncounterMgmt when appropriate)
if not OGRH.AdminHooks then
  OGRH.AdminHooks = {
    OnRaidCreated = OnRaidCreated,
    OnEncounterMoveAttempt = OnEncounterMoveAttempt
  }
end

-- ============================================
-- UI RENDERING EXTENSIONS
-- ============================================

--- Renders a Text Field role UI component
-- @param container frame Parent frame for the text field
-- @param role table Role data with isTextField flag
-- @param roleIndex number Index of this role
-- @param raidIdx number Raid index
-- @param encounterIdx number Encounter index
-- @param containerWidth number Width of container
-- @return frame The created text field frame
function OGRH.RenderTextFieldRole(container, role, roleIndex, raidIdx, encounterIdx, containerWidth)
  if not role.isTextField then
    return nil
  end
  
  -- Create text input container
  local textContainer = CreateFrame("Frame", nil, container)
  textContainer:SetWidth(containerWidth - 10)
  textContainer:SetHeight(30)
  textContainer:SetPoint("TOPLEFT", container, "TOPLEFT", 5, -25)
  
  -- Create label
  local label = textContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  label:SetPoint("TOPLEFT", textContainer, "TOPLEFT", 0, 0)
  label:SetText(role.name .. ":")
  label:SetTextColor(0.7, 0.7, 0.7)
  
  -- Create text input box
  local textBox = CreateFrame("EditBox", nil, textContainer)
  textBox:SetWidth(containerWidth - 20)
  textBox:SetHeight(20)
  textBox:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 2, -2)
  textBox:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 8,
    insets = {left = 2, right = 2, top = 2, bottom = 2}
  })
  textBox:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
  textBox:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
  textBox:SetFontObject("GameFontHighlight")
  textBox:SetAutoFocus(false)
  textBox:SetMaxLetters(200)
  textBox:SetText(role.textValue or "")
  
  -- Add padding for text
  textBox:SetTextInsets(5, 5, 0, 0)
  
  -- Clear focus on escape
  textBox:SetScript("OnEscapePressed", function()
    this:ClearFocus()
  end)
  
  -- Save on text change
  textBox:SetScript("OnTextChanged", function()
    if not this:HasFocus() then
      return -- Ignore programmatic changes
    end
    
    local newText = this:GetText()
    role.textValue = newText
    
    -- Save to SVM
    local path = "encounterMgmt.raids[" .. raidIdx .. "].encounters[" .. encounterIdx .. "].roles[" .. roleIndex .. "].textValue"
    OGRH.SVM.SetPath(path, newText)
    OGRH.SVM.Save()
  end)
  
  -- Enable mouse wheel for scrolling long text
  textBox:SetScript("OnMouseWheel", function()
    local cursorPos = this:GetCursorPosition()
    if arg1 > 0 then
      -- Scroll up
      this:SetCursorPosition(math.max(0, cursorPos - 10))
    else
      -- Scroll down
      this:SetCursorPosition(math.min(string.len(this:GetText()), cursorPos + 10))
    end
  end)
  textBox:EnableMouseWheel()
  
  return textContainer
end

--- Renders a Loot Settings role UI component
-- @param container frame Parent frame for the loot settings
-- @param role table Role data with isLootSettings flag
-- @param roleIndex number Index of this role
-- @param raidIdx number Raid index
-- @param encounterIdx number Encounter index
-- @param containerWidth number Width of container
-- @return frame The created loot settings frame
function OGRH.RenderLootSettingsRole(container, role, roleIndex, raidIdx, encounterIdx, containerWidth)
  if not role.isLootSettings then
    return nil
  end
  
  -- Create settings container
  local settingsContainer = CreateFrame("Frame", nil, container)
  settingsContainer:SetWidth(containerWidth - 10)
  settingsContainer:SetHeight(90)
  settingsContainer:SetPoint("TOPLEFT", container, "TOPLEFT", 5, -25)
  
  local yOffset = 0
  
  -- Loot Method dropdown
  local methodLabel = settingsContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  methodLabel:SetPoint("TOPLEFT", settingsContainer, "TOPLEFT", 0, yOffset)
  methodLabel:SetText("Method:")
  methodLabel:SetTextColor(0.7, 0.7, 0.7)
  
  local methodBtn = CreateFrame("Button", nil, settingsContainer, "UIPanelButtonTemplate")
  methodBtn:SetWidth(120)
  methodBtn:SetHeight(20)
  methodBtn:SetPoint("LEFT", methodLabel, "RIGHT", 5, 0)
  methodBtn:SetText(role.lootMethod == "master" and "Master Looter" or "Group Loot")
  OGRH.StyleButton(methodBtn)
  
  methodBtn:SetScript("OnClick", function()
    -- Toggle between master and group
    local newMethod = (role.lootMethod == "master") and "group" or "master"
    role.lootMethod = newMethod
    this:SetText(newMethod == "master" and "Master Looter" or "Group Loot")
    
    -- Save to SVM
    local path = "encounterMgmt.raids[" .. raidIdx .. "].encounters[" .. encounterIdx .. "].roles[" .. roleIndex .. "].lootMethod"
    OGRH.SVM.SetPath(path, newMethod)
    OGRH.SVM.Save()
  end)
  
  yOffset = yOffset - 25
  
  -- Auto Switch checkbox
  local autoSwitchLabel = settingsContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  autoSwitchLabel:SetPoint("TOPLEFT", settingsContainer, "TOPLEFT", 0, yOffset)
  autoSwitchLabel:SetText("Auto-Switch:")
  autoSwitchLabel:SetTextColor(0.7, 0.7, 0.7)
  
  local autoSwitchCheck = CreateFrame("CheckButton", nil, settingsContainer, "UICheckButtonTemplate")
  autoSwitchCheck:SetPoint("LEFT", autoSwitchLabel, "RIGHT", 5, 0)
  autoSwitchCheck:SetWidth(20)
  autoSwitchCheck:SetHeight(20)
  autoSwitchCheck:SetChecked(role.autoSwitch or false)
  
  autoSwitchCheck:SetScript("OnClick", function()
    local checked = this:GetChecked()
    role.autoSwitch = checked
    
    -- Save to SVM
    local path = "encounterMgmt.raids[" .. raidIdx .. "].encounters[" .. encounterIdx .. "].roles[" .. roleIndex .. "].autoSwitch"
    OGRH.SVM.SetPath(path, checked)
    OGRH.SVM.Save()
  end)
  
  -- Tooltip for Auto-Switch
  autoSwitchCheck:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
    GameTooltip:SetText("Auto-Switch", 1, 1, 1)
    GameTooltip:AddLine("Automatically switch to Master Loot for bosses and Group Loot for trash", 0.8, 0.8, 0.8, 1)
    GameTooltip:Show()
  end)
  autoSwitchCheck:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)
  
  yOffset = yOffset - 25
  
  -- Threshold dropdown
  local thresholdLabel = settingsContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  thresholdLabel:SetPoint("TOPLEFT", settingsContainer, "TOPLEFT", 0, yOffset)
  thresholdLabel:SetText("Threshold:")
  thresholdLabel:SetTextColor(0.7, 0.7, 0.7)
  
  local thresholdBtn = CreateFrame("Button", nil, settingsContainer, "UIPanelButtonTemplate")
  thresholdBtn:SetWidth(120)
  thresholdBtn:SetHeight(20)
  thresholdBtn:SetPoint("LEFT", thresholdLabel, "RIGHT", 5, 0)
  
  -- Format threshold text
  local thresholdText = role.threshold or "rare"
  thresholdText = string.upper(string.sub(thresholdText, 1, 1)) .. string.sub(thresholdText, 2)
  thresholdBtn:SetText(thresholdText)
  OGRH.StyleButton(thresholdBtn)
  
  thresholdBtn:SetScript("OnClick", function()
    -- Cycle through thresholds: uncommon -> rare -> epic -> uncommon
    local current = role.threshold or "rare"
    local newThreshold
    if current == "uncommon" then
      newThreshold = "rare"
    elseif current == "rare" then
      newThreshold = "epic"
    else
      newThreshold = "uncommon"
    end
    
    role.threshold = newThreshold
    local displayText = string.upper(string.sub(newThreshold, 1, 1)) .. string.sub(newThreshold, 2)
    this:SetText(displayText)
    
    -- Save to SVM
    local path = "encounterMgmt.raids[" .. raidIdx .. "].encounters[" .. encounterIdx .. "].roles[" .. roleIndex .. "].threshold"
    OGRH.SVM.SetPath(path, newThreshold)
    OGRH.SVM.Save()
  end)
  
  yOffset = yOffset - 25
  
  -- Apply button
  local applyBtn = CreateFrame("Button", nil, settingsContainer, "UIPanelButtonTemplate")
  applyBtn:SetWidth(100)
  applyBtn:SetHeight(20)
  applyBtn:SetPoint("TOPLEFT", settingsContainer, "TOPLEFT", 0, yOffset)
  applyBtn:SetText("Apply Settings")
  OGRH.StyleButton(applyBtn)
  
  applyBtn:SetScript("OnClick", function()
    OGRH.ApplyLootSettings(role)
  end)
  
  return settingsContainer
end

-- ============================================
-- INITIALIZATION
-- ============================================

-- Ensure Admin encounter exists for existing raids
local function InitializeAdminEncounters()
  OGRH.EnsureSV()
  local raids = OGRH.SVM.GetPath("encounterMgmt.raids")
  if not raids then
    return
  end
  
  -- Add Admin encounter to all existing raids
  for i = 1, table.getn(raids) do
    OGRH.EnsureAdminEncounter(i)
  end
end

-- Register initialization on addon loaded
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:SetScript("OnEvent", function()
  if event == "ADDON_LOADED" and arg1 == "OG-RaidHelper" then
    -- Delay initialization slightly to ensure SVM is ready
    this:UnregisterEvent("ADDON_LOADED")
    
    -- Initialize after 0.5 seconds
    local delayFrame = CreateFrame("Frame")
    local elapsed = 0
    delayFrame:SetScript("OnUpdate", function()
      elapsed = elapsed + arg1
      if elapsed >= 0.5 then
        InitializeAdminEncounters()
        this:SetScript("OnUpdate", nil)
      end
    end)
  end
end)

-- Debug toggle
OGRH.EncounterAdmin.debug = false

-- Export functions for external use
OGRH.CreateAdminEncounter = OGRH.CreateAdminEncounter
OGRH.IsAdminEncounter = OGRH.IsAdminEncounter
OGRH.EnsureAdminEncounter = OGRH.EnsureAdminEncounter
OGRH.CanMoveEncounterToIndex = OGRH.CanMoveEncounterToIndex
OGRH.ApplyLootSettings = OGRH.ApplyLootSettings
OGRH.GetLootSettingsText = OGRH.GetLootSettingsText
OGRH.RenderTextFieldRole = OGRH.RenderTextFieldRole
OGRH.RenderLootSettingsRole = OGRH.RenderLootSettingsRole

if OGRH.EncounterAdmin.debug then
  OGRH.Msg("|cff00ff00[RH-Admin]|r EncounterAdmin module loaded")
end
