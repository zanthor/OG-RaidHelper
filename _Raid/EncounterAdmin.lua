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
    -- Left Column: Loot Settings, Discord
    -- Role 1: Loot Settings (includes 3 player assignment slots)
    {
      roleId = 1,
      name = "Loot Settings",
      column = 1,
      isLootSettings = true,   -- Custom role flag
      lootMethod = "master",    -- "master" or "group"
      autoSwitch = false,       -- Auto-switch for trash/bosses
      threshold = "rare",       -- "uncommon", "rare", "epic"
      assignedPlayers = {},     -- [1]=Master Looter, [2]=Disenchant, [3]=Bagspace Buffer
      slotLabels = {"Master Looter", "Disenchant", "Bagspace Buffer"}
    },
    -- Right Column: Loot Rules
    -- Role 2: Loot Rules (4 text field slots)
    {
      roleId = 2,
      name = "Loot Rules",
      column = 2,
      isTextField = true,
      textSlots = 6,
      textValues = {}
    },
    -- Role 3: Discord (left column, below Loot Settings)
    {
      roleId = 3,
      name = "Discord",
      column = 1,
      isTextField = true,
      textSlots = 1,
      textValues = {}
    },
    -- Role 4: SR Link (left column, below Discord)
    {
      roleId = 4,
      name = "SR Link",
      column = 1,
      isTextField = true,
      textSlots = 1,
      textValues = {}
    },
    -- Role 5: Buff Manager (right column, below Loot Rules)
    {
      roleId = 5,
      name = "Buff Manager",
      column = 2,
      isBuffManager = true,
      enabled = false,
      buffRoles = {},
      settings = {
        autoScan = true,
        scanInterval = 30,
        shameThreshold = 80,
        whisperFirst = true,
        pallyPowerSync = false
      }
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
    -- Patch existing Admin encounter: replace roles with fresh template if structure changed
    local adminEnc = raid.encounters[1]
    local template = ADMIN_ENCOUNTER_TEMPLATE
    local needsRebuild = false
    
    -- Detect structure mismatch: wrong role count, missing flags, or wrong column layout
    if not adminEnc.roles or table.getn(adminEnc.roles) ~= table.getn(template.roles) then
      needsRebuild = true
    else
      for i = 1, table.getn(template.roles) do
        local existing = adminEnc.roles[i]
        local tmpl = template.roles[i]
        if not existing
          or existing.name ~= tmpl.name
          or existing.column ~= tmpl.column
          or existing.roleId ~= tmpl.roleId
          or (tmpl.textSlots and existing.textSlots ~= tmpl.textSlots) then
          needsRebuild = true
          break
        end
      end
    end
    
    if needsRebuild then
      -- Preserve user data by name before replacing
      local savedData = {}
      if adminEnc.roles then
        for i = 1, table.getn(adminEnc.roles) do
          local r = adminEnc.roles[i]
          if r.name then
            savedData[r.name] = {
              assignedPlayers = r.assignedPlayers,
              textValues = r.textValues,
              textValue = r.textValue,  -- backward compat: old single-string field
              lootMethod = r.lootMethod,
              autoSwitch = r.autoSwitch,
              threshold = r.threshold,
              -- BuffManager data
              buffRoles = r.buffRoles,
              settings = r.settings,
              enabled = r.enabled
            }
          end
        end
      end
      
      -- Deep copy fresh template roles
      local newRoles = DeepCopy(template.roles)
      
      -- Restore user data where names match
      for i = 1, table.getn(newRoles) do
        local saved = savedData[newRoles[i].name]
        if saved then
          if newRoles[i].isTextField then
            if saved.textValues then
              newRoles[i].textValues = saved.textValues
            elseif saved.textValue and saved.textValue ~= "" then
              -- Migrate old single textValue into textValues[1]
              newRoles[i].textValues = { saved.textValue }
            end
          end
          if newRoles[i].isLootSettings then
            if saved.lootMethod then newRoles[i].lootMethod = saved.lootMethod end
            if saved.autoSwitch ~= nil then newRoles[i].autoSwitch = saved.autoSwitch end
            if saved.threshold then newRoles[i].threshold = saved.threshold end
          end
          if newRoles[i].isBuffManager then
            if saved.buffRoles then newRoles[i].buffRoles = saved.buffRoles end
            if saved.settings then newRoles[i].settings = saved.settings end
            if saved.enabled ~= nil then newRoles[i].enabled = saved.enabled end
          end
          if newRoles[i].assignedPlayers and saved.assignedPlayers then
            newRoles[i].assignedPlayers = saved.assignedPlayers
          end
        end
      end
      
      adminEnc.roles = newRoles
      adminEnc.displayName = template.displayName
      OGRH.SVM.SetPath("encounterMgmt.raids[" .. raidIdx .. "]", raid)
      if OGRH.EncounterAdmin.debug then
        OGRH.Msg("|cff00ff00[RH-Admin]|r Rebuilt Admin encounter roles for raid: " .. tostring(raid.name))
      end
    else
      -- Structure matches but merge any NEW template flags/fields into existing
      -- roles so upgrades (e.g. adding isBuffManager) propagate without a rebuild.
      for i = 1, table.getn(template.roles) do
        local existing = adminEnc.roles[i]
        local tmpl = template.roles[i]
        for k, v in pairs(tmpl) do
          if existing[k] == nil then
            existing[k] = DeepCopy(v)
          end
        end
      end
    end
    return
  end
  
  -- Create and insert Admin encounter at index 1
  local adminEncounter = OGRH.CreateAdminEncounter()
  table.insert(raid.encounters, 1, adminEncounter)
  
  -- Write back to SVM
  OGRH.SVM.SetPath("encounterMgmt.raids[" .. raidIdx .. "]", raid)
  
  if OGRH.EncounterAdmin.debug then
    OGRH.Msg("|cff00ff00[RH-Admin]|r Admin encounter added to raid: " .. tostring(raid.name))
  end
end

--- Prevents sorting encounters above Admin encounter (index 1)
-- Admin must always stay at index 1; non-Admin encounters cannot move to index 1
-- @param encounterIdx number Current encounter index
-- @param newIndex number Target index for move
-- @param encounter table Encounter to move
-- @return boolean True if move is allowed, false if blocked
function OGRH.CanMoveEncounterToIndex(encounterIdx, newIndex, encounter)
  -- Admin encounter must stay at index 1 — block all moves
  if OGRH.IsAdminEncounter(encounter) then
    return newIndex == 1
  end
  
  -- Block non-Admin encounters from moving to index 1
  if newIndex == 1 then
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
  
  -- Build the loot settings data to apply
  local method = lootSettingsRole.lootMethod or "master"
  local mlName = UnitName("player")
  if method == "master" and lootSettingsRole.assignedPlayers and lootSettingsRole.assignedPlayers[1] then
    mlName = lootSettingsRole.assignedPlayers[1]
  end
  
  local threshold = lootSettingsRole.threshold or "rare"
  local thresholdValue = 2 -- Default to Uncommon
  if threshold == "uncommon" then
    thresholdValue = 2
  elseif threshold == "rare" then
    thresholdValue = 3
  elseif threshold == "epic" then
    thresholdValue = 4
  end
  
  if IsRaidLeader() == 1 then
    -- We are raid leader, apply directly
    OGRH.ExecuteLootSettings(method, mlName, thresholdValue)
    return true
  else
    -- Delegate to raid leader via addon message
    if OGRH.MessageRouter then
      OGRH.MessageRouter.Broadcast(OGRH.MessageTypes.ADMIN.LOOT_REQUEST, {
        method = method,
        mlName = mlName,
        thresholdValue = thresholdValue
      }, {
        priority = "HIGH"
      })
      OGRH.Msg("|cff00ccff[RH-Admin]|r Loot settings request sent to raid leader.")
      return true
    else
      OGRH.Msg("|cffff6666[RH-Admin]|r Cannot send loot request - MessageRouter not loaded")
      return false
    end
  end
end

--- Actually execute the loot method/threshold changes (must be called by raid leader)
-- Delays threshold by 1 second so the server processes the method change first.
function OGRH.ExecuteLootSettings(method, mlName, thresholdValue)
  if method == "master" then
    SetLootMethod("master", mlName)
  else
    SetLootMethod("group")
  end
  
  -- Delay threshold change so server processes method change first
  local thresholdFrame = CreateFrame("Frame")
  thresholdFrame.elapsed = 0
  thresholdFrame:SetScript("OnUpdate", function()
    this.elapsed = this.elapsed + arg1
    if this.elapsed >= 1.0 then
      SetLootThreshold(thresholdValue)
      OGRH.Msg("|cff00ff00[RH-Admin]|r Loot settings applied")
      this:SetScript("OnUpdate", nil)
    end
  end)
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
  
  local textSlots = role.textSlots or 1
  
  -- Ensure textValues array exists (migrate old textValue if needed)
  if not role.textValues then
    role.textValues = {}
    if role.textValue and role.textValue ~= "" then
      role.textValues[1] = role.textValue
    end
  end
  
  for slotIdx = 1, textSlots do
    -- Create text input container for this slot
    local textContainer = CreateFrame("Frame", nil, container)
    textContainer:SetWidth(containerWidth - 10)
    textContainer:SetHeight(22)
    textContainer:SetPoint("TOPLEFT", container, "TOPLEFT", 5, -25 - ((slotIdx - 1) * 22))
    
    -- Tag label (T1, T2, etc.) to the left of the text box
    local tagLabel = textContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tagLabel:SetPoint("LEFT", textContainer, "LEFT", 2, 0)
    tagLabel:SetText("|cff888888L" .. slotIdx .. "|r")
    tagLabel:SetTextColor(0.5, 0.5, 0.5)
    
    -- Create text input box
    local textBox = CreateFrame("EditBox", nil, textContainer)
    textBox:SetWidth(containerWidth - 40)
    textBox:SetHeight(20)
    textBox:SetPoint("LEFT", tagLabel, "RIGHT", 3, 0)
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
    textBox:SetText(role.textValues[slotIdx] or "")
    
    -- Add padding for text
    textBox:SetTextInsets(5, 5, 0, 0)
    
    -- Track focus state (HasFocus() is not available in 1.12)
    local hasFocus = false
    textBox:SetScript("OnEditFocusGained", function()
      hasFocus = true
    end)
    textBox:SetScript("OnEditFocusLost", function()
      hasFocus = false
    end)
    
    -- Clear focus on escape
    textBox:SetScript("OnEscapePressed", function()
      this:ClearFocus()
    end)
    
    -- Save on text change (capture slotIdx for closure)
    local capturedSlotIdx = slotIdx
    textBox:SetScript("OnTextChanged", function()
      if not hasFocus then
        return -- Ignore programmatic changes
      end
      
      local newText = this:GetText()
      if not role.textValues then role.textValues = {} end
      role.textValues[capturedSlotIdx] = newText
      
      -- Save to SVM
      local path = "encounterMgmt.raids[" .. raidIdx .. "].encounters[" .. encounterIdx .. "].roles[" .. roleIndex .. "].textValues." .. capturedSlotIdx
      OGRH.SVM.SetPath(path, newText)
    end)
  end
  
  return container
end

--- Renders a Loot Settings role UI component
-- Layout: Method button + Auto-Switch on same row, Threshold below, then 3 player slots
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
  settingsContainer:SetHeight(135)
  settingsContainer:SetPoint("TOPLEFT", container, "TOPLEFT", 5, -25)
  
  local yOffset = 0
  
  -- Row 1: Method MenuButton + Auto-Switch checkbox
  local methodBtn  -- forward declare for closure access
  
  local methodItems = {
    {text = "Master", selected = (role.lootMethod == "master"), onClick = function()
      role.lootMethod = "master"
      methodBtn:SetText("Master")
      local path = "encounterMgmt.raids[" .. raidIdx .. "].encounters[" .. encounterIdx .. "].roles[" .. roleIndex .. "].lootMethod"
      OGRH.SVM.SetPath(path, "master")
    end},
    {text = "Group", selected = (role.lootMethod ~= "master"), onClick = function()
      role.lootMethod = "group"
      methodBtn:SetText("Group")
      local path = "encounterMgmt.raids[" .. raidIdx .. "].encounters[" .. encounterIdx .. "].roles[" .. roleIndex .. "].lootMethod"
      OGRH.SVM.SetPath(path, "group")
    end}
  }
  
  local methodContainer
  methodContainer, methodBtn = OGST.CreateMenuButton(settingsContainer, {
    label = "Method:",
    labelWidth = 62,
    labelColor = {r = 0.7, g = 0.7, b = 0.7},
    buttonText = role.lootMethod == "master" and "Master" or "Group",
    buttonWidth = 80,
    buttonHeight = 20,
    padding = 0,
    gap = 4,
    menuItems = methodItems,
    singleSelect = true
  })
  methodContainer:SetPoint("TOPLEFT", settingsContainer, "TOPLEFT", 0, yOffset)
  
  -- Auto-Switch checkbox to the right of Method
  local autoSwitchCheck = CreateFrame("CheckButton", nil, settingsContainer, "UICheckButtonTemplate")
  autoSwitchCheck:SetWidth(20)
  autoSwitchCheck:SetHeight(20)
  autoSwitchCheck:SetPoint("LEFT", methodContainer, "RIGHT", 4, 0)
  autoSwitchCheck:SetChecked(role.autoSwitch or false)
  
  local autoSwitchLabel = settingsContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  autoSwitchLabel:SetPoint("LEFT", autoSwitchCheck, "RIGHT", 0, 0)
  autoSwitchLabel:SetText("Auto-Switch")
  autoSwitchLabel:SetTextColor(0.7, 0.7, 0.7)
  
  autoSwitchCheck:SetScript("OnClick", function()
    local checked = (this:GetChecked() == 1) and true or false
    role.autoSwitch = checked
    
    local path = "encounterMgmt.raids[" .. raidIdx .. "].encounters[" .. encounterIdx .. "].roles[" .. roleIndex .. "].autoSwitch"
    OGRH.SVM.SetPath(path, checked)
  end)
  
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
  
  -- Row 2: Threshold MenuButton
  local thresholdBtn  -- forward declare for closure access
  
  -- Helper: apply loot-rarity color to the threshold button text
  local function ApplyThresholdColor(btn, threshold)
    local colors = {
      uncommon = {r = 0.12, g = 1.0, b = 0.0},   -- green
      rare     = {r = 0.0,  g = 0.44, b = 0.87},  -- blue
      epic     = {r = 0.64, g = 0.21, b = 0.93}   -- purple
    }
    local c = colors[threshold] or colors.rare
    local fs = btn:GetFontString()
    if fs then fs:SetTextColor(c.r, c.g, c.b) end
  end
  
  local thresholdItems = {
    {text = "Uncommon", selected = (role.threshold == "uncommon"), onClick = function()
      role.threshold = "uncommon"
      thresholdBtn:SetText("Uncommon")
      ApplyThresholdColor(thresholdBtn, "uncommon")
      local path = "encounterMgmt.raids[" .. raidIdx .. "].encounters[" .. encounterIdx .. "].roles[" .. roleIndex .. "].threshold"
      OGRH.SVM.SetPath(path, "uncommon")
    end},
    {text = "Rare", selected = (role.threshold == "rare"), onClick = function()
      role.threshold = "rare"
      thresholdBtn:SetText("Rare")
      ApplyThresholdColor(thresholdBtn, "rare")
      local path = "encounterMgmt.raids[" .. raidIdx .. "].encounters[" .. encounterIdx .. "].roles[" .. roleIndex .. "].threshold"
      OGRH.SVM.SetPath(path, "rare")
    end},
    {text = "Epic", selected = (role.threshold == "epic"), onClick = function()
      role.threshold = "epic"
      thresholdBtn:SetText("Epic")
      ApplyThresholdColor(thresholdBtn, "epic")
      local path = "encounterMgmt.raids[" .. raidIdx .. "].encounters[" .. encounterIdx .. "].roles[" .. roleIndex .. "].threshold"
      OGRH.SVM.SetPath(path, "epic")
    end}
  }
  
  local thresholdContainer
  thresholdContainer, thresholdBtn = OGST.CreateMenuButton(settingsContainer, {
    label = "Threshold:",
    labelWidth = 62,
    labelColor = {r = 0.7, g = 0.7, b = 0.7},
    buttonText = string.upper(string.sub(role.threshold or "rare", 1, 1)) .. string.sub(role.threshold or "rare", 2),
    buttonWidth = 80,
    buttonHeight = 20,
    padding = 0,
    gap = 4,
    menuItems = thresholdItems,
    singleSelect = true
  })
  thresholdContainer:SetPoint("TOPLEFT", settingsContainer, "TOPLEFT", 0, yOffset)
  ApplyThresholdColor(thresholdBtn, role.threshold or "rare")
  
  yOffset = yOffset - 25
  
  -- Player assignment slots (3 slots: Master Looter, Disenchant, Bagspace Buffer)
  local slotLabels = role.slotLabels or {"Master Looter", "Disenchant", "Bagspace Buffer"}
  if not role.assignedPlayers then
    role.assignedPlayers = {}
  end
  
  container.slots = {}
  for i = 1, 3 do
    local slot = CreateFrame("Frame", nil, settingsContainer)
    slot:SetWidth(containerWidth - 20)
    slot:SetHeight(20)
    slot:SetPoint("TOPLEFT", settingsContainer, "TOPLEFT", 0, yOffset)
    
    -- Background
    local bg = slot:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    bg:SetVertexColor(0.1, 0.1, 0.1, 0.8)
    slot.bg = bg
    
    -- Player tag label (P1/P2/P3)
    local playerTag = slot:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    playerTag:SetPoint("LEFT", slot, "LEFT", 5, 0)
    playerTag:SetText("|cff888888P" .. i .. "|r")
    playerTag:SetTextColor(0.5, 0.5, 0.5)
    slot.playerTag = playerTag
    
    -- Player name text
    local nameText = slot:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    nameText:SetPoint("LEFT", playerTag, "RIGHT", 3, 0)
    nameText:SetPoint("RIGHT", slot, "RIGHT", -5, 0)
    nameText:SetJustifyH("LEFT")
    slot.nameText = nameText
    
    -- Store slot info for drag/drop compatibility
    slot.roleIndex = roleIndex
    slot.slotIndex = i
    
    -- Show assigned player or placeholder with class color
    local assignedPlayer = role.assignedPlayers[i]
    if assignedPlayer and assignedPlayer ~= "" then
      nameText:SetText(assignedPlayer)
      local playerClass = OGRH.GetPlayerClass and OGRH.GetPlayerClass(assignedPlayer)
      if playerClass and RAID_CLASS_COLORS[playerClass] then
        local cc = RAID_CLASS_COLORS[playerClass]
        nameText:SetTextColor(cc.r, cc.g, cc.b)
      else
        nameText:SetTextColor(1, 1, 1)
      end
    else
      nameText:SetText(slotLabels[i] or ("Slot " .. i))
      nameText:SetTextColor(0.53, 0.53, 0.53)
    end
    
    -- Click handler: clicking cycles through raid members (simplified assignment)
    local capturedSlotIndex = i
    local capturedSlotLabel = slotLabels[i] or ("Slot " .. i)
    
    -- Create clickable button overlay for drop target and click-to-assign
    local dropBtn = CreateFrame("Button", nil, slot)
    dropBtn:SetAllPoints()
    dropBtn:EnableMouse(true)
    dropBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    
    dropBtn:SetScript("OnClick", function()
      local button = arg1 or "LeftButton"
      if button == "RightButton" then
        -- Right-click clears the assignment
        role.assignedPlayers[capturedSlotIndex] = nil
        nameText:SetText(capturedSlotLabel)
        nameText:SetTextColor(0.53, 0.53, 0.53)
        
        OGRH.SVM.SetPath(
          string.format("encounterMgmt.raids.%d.encounters.%d.roles.%d.assignedPlayers.%d",
            raidIdx, encounterIdx, roleIndex, capturedSlotIndex),
          nil
        )
        return
      end
      
      -- Left-click: show player list from the players panel if available
      -- For now, use a simple menu from raid members
      if OGRH.ShowPlayerAssignmentMenu then
        OGRH.ShowPlayerAssignmentMenu(slot, raidIdx, encounterIdx, roleIndex, capturedSlotIndex, function(playerName)
          role.assignedPlayers[capturedSlotIndex] = playerName
          nameText:SetText(playerName)
          local pc = OGRH.GetPlayerClass and OGRH.GetPlayerClass(playerName)
          if pc and RAID_CLASS_COLORS[pc] then
            local cc = RAID_CLASS_COLORS[pc]
            nameText:SetTextColor(cc.r, cc.g, cc.b)
          else
            nameText:SetTextColor(1, 1, 1)
          end
        end)
      else
        -- Fallback: cycle through "target" assignment
        local targetName = UnitName("target")
        if targetName then
          role.assignedPlayers[capturedSlotIndex] = targetName
          nameText:SetText(targetName)
          local pc = OGRH.GetPlayerClass and OGRH.GetPlayerClass(targetName)
          if pc and RAID_CLASS_COLORS[pc] then
            local cc = RAID_CLASS_COLORS[pc]
            nameText:SetTextColor(cc.r, cc.g, cc.b)
          else
            nameText:SetTextColor(1, 1, 1)
          end
          
          OGRH.SVM.SetPath(
            string.format("encounterMgmt.raids.%d.encounters.%d.roles.%d.assignedPlayers.%d",
              raidIdx, encounterIdx, roleIndex, capturedSlotIndex),
            targetName
          )
        end
      end
    end)
    
    -- Tooltip showing slot purpose
    dropBtn:SetScript("OnEnter", function()
      slot.bg:SetVertexColor(0.2, 0.2, 0.3, 0.8)
      GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
      GameTooltip:SetText(capturedSlotLabel, 1, 1, 1)
      GameTooltip:AddLine("Left-click: Assign from target", 0.8, 0.8, 0.8, 1)
      GameTooltip:AddLine("Right-click: Clear assignment", 0.8, 0.8, 0.8, 1)
      GameTooltip:Show()
    end)
    dropBtn:SetScript("OnLeave", function()
      slot.bg:SetVertexColor(0.1, 0.1, 0.1, 0.8)
      GameTooltip:Hide()
    end)
    
    table.insert(container.slots, slot)
    yOffset = yOffset - 22
  end
  
  -- Apply Loot Settings button at bottom, centered
  yOffset = yOffset - 5
  local applyBtn = CreateFrame("Button", nil, settingsContainer, "UIPanelButtonTemplate")
  applyBtn:SetWidth(130)
  applyBtn:SetHeight(20)
  applyBtn:SetPoint("TOP", settingsContainer, "TOP", 0, yOffset)
  applyBtn:SetText("Apply Loot Settings")
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
