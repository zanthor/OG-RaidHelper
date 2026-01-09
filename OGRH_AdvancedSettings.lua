-- OGRH_AdvancedSettings.lua
-- Advanced settings UI dialogs for raids and encounters
-- Phase 3: UI Layer Implementation

-- Show advanced settings dialog for raid or encounter
function OGRH.ShowAdvancedSettingsDialog()
  local frame = OGRH_EncounterFrame
  if not frame then
    OGRH.Msg("Encounter frame not found.")
    return
  end
  
  -- Determine if we're editing raid or encounter
  local isRaid = not frame.selectedEncounter
  local title
  local windowHeight = 275  -- Base height for raid settings
  
  if isRaid then
    if not frame.selectedRaid then
      OGRH.Msg("Please select a raid first.")
      return
    end
    title = "Raid Settings: " .. frame.selectedRaid
  else
    title = "Encounter Settings: " .. frame.selectedEncounter
  end
  
  -- Create or reuse dialog
  local dialog
  if not OGRH_AdvancedSettingsFrame then
    dialog = OGST.CreateStandardWindow({
      name = "OGRH_AdvancedSettingsFrame",
      width = 500,
      height = windowHeight,
      title = title,
      closeButton = true,
      escapeCloses = true,
      resizable = false
    })
    
    local content = dialog.contentFrame
    
    -- Calculate panel height based on content type
    local panelHeight = 200  -- Base height for raid settings (consume tracking only)
    
    -- Content panel for consume settings
    local consumePanel = OGST.CreateContentPanel(content, {
      height = panelHeight
    })
    OGST.AnchorElement(consumePanel, content, {position = "top", fill = "horizontal"})
    consumePanel:SetPoint("RIGHT", content, "RIGHT", 0, 0)
    
    -- Consume Tracking Requirements header (inside panel)
    local consumeHeader = OGST.CreateStaticText(consumePanel, {
      text = "Consume Tracking Requirements",
      font = "GameFontNormalLarge",
      width = 460
    })
    OGST.AnchorElement(consumeHeader, consumePanel, {position = "top"})
    
    -- Enable consume tracking checkbox
    local consumeCheckContainer, consumeCheck, consumeCheckLabel = OGST.CreateCheckbox(consumePanel, {
      label = "Enable Consume Tracking",
      labelAnchor = "RIGHT",
      checked = false,
      labelWidth = 160
    })
    OGST.AnchorElement(consumeCheckContainer, consumeHeader, {position = "below"})
    dialog.consumeCheck = consumeCheck
    
    -- Ready threshold textbox (to the right of checkbox)
    local thresholdContainer, thresholdBackdrop, thresholdInput, thresholdLabel = OGST.CreateSingleLineTextBox(consumePanel, 40, 24, {
      label = "Ready Threshold (%):",
      labelAnchor = "LEFT",
      maxLetters = 2,
      numeric = true,
      align = "CENTER"
    })
    OGST.AnchorElement(thresholdContainer, consumeCheckContainer, {position = "right"})
    dialog.thresholdInput = thresholdInput
    
    -- Flask Requirements label
    local flaskLabel = OGST.CreateStaticText(consumePanel, {
      text = "Flask Requirements (by Role):",
      font = "GameFontNormal",
      width = 440
    })
    OGST.AnchorElement(flaskLabel, consumeCheckContainer, {position = "below"})
    
    -- Flask role checkboxes (2x2 grid)
    local roles = {"Tanks", "Healers", "Melee", "Ranged"}
    dialog.flaskRoleCheckboxes = {}
    
    local tanksCB, tanksCheck, tanksLabel = OGST.CreateCheckbox(consumePanel, {
      label = "Tanks",
      labelAnchor = "RIGHT",
      checked = false,
      labelWidth = 60
    })
    OGST.AnchorElement(tanksCB, flaskLabel, {position = "below"})
    tanksCheck.roleName = "Tanks"
    table.insert(dialog.flaskRoleCheckboxes, tanksCheck)
    
    local healersCB, healersCheck, healersLabel = OGST.CreateCheckbox(consumePanel, {
      label = "Healers",
      labelAnchor = "RIGHT",
      checked = false,
      labelWidth = 60
    })
    OGST.AnchorElement(healersCB, tanksCB, {position = "right"})
    healersCheck.roleName = "Healers"
    table.insert(dialog.flaskRoleCheckboxes, healersCheck)
    
    local meleeCB, meleeCheck, meleeLabel = OGST.CreateCheckbox(consumePanel, {
      label = "Melee",
      labelAnchor = "RIGHT",
      checked = false,
      labelWidth = 60
    })
    OGST.AnchorElement(meleeCB, tanksCB, {position = "below"})
    meleeCheck.roleName = "Melee"
    table.insert(dialog.flaskRoleCheckboxes, meleeCheck)
    
    local rangedCB, rangedCheck, rangedLabel = OGST.CreateCheckbox(consumePanel, {
      label = "Ranged",
      labelAnchor = "RIGHT",
      checked = false,
      labelWidth = 60
    })
    OGST.AnchorElement(rangedCB, meleeCB, {position = "right"})
    rangedCheck.roleName = "Ranged"
    table.insert(dialog.flaskRoleCheckboxes, rangedCheck)
    
    -- Info text
    local consumeInfo = OGST.CreateStaticText(consumePanel, {
      text = "Only roles checked will be required to have flasks for raid readiness checks.",
      font = "GameFontHighlightSmall",
      width = 440,
      multiline = true
    })
    OGST.AnchorElement(consumeInfo, meleeCB, {position = "below"})
    
    -- Save button (bottom right)
    local saveBtn = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    saveBtn:SetWidth(120)
    saveBtn:SetHeight(24)
    saveBtn:SetText("Save Changes")
    OGST.StyleButton(saveBtn)
    saveBtn:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -10, 10)
    dialog.saveBtn = saveBtn
    
    saveBtn:SetScript("OnClick", function()
      OGRH.SaveAdvancedSettingsDialog()
    end)
    
    -- Close button also saves
    if dialog.closeBtn then
      dialog.closeBtn:SetScript("OnClick", function()
        OGRH.SaveAdvancedSettingsDialog()
        dialog:Hide()
      end)
    end
    
    OGRH_AdvancedSettingsFrame = dialog
  else
    dialog = OGRH_AdvancedSettingsFrame
  end
  
  -- Update title
  dialog.titleText:SetText(title)
  
  -- Load current settings
  local settings
  if isRaid then
    settings = OGRH.GetCurrentRaidAdvancedSettings()
  else
    settings = OGRH.GetCurrentEncounterAdvancedSettings()
  end
  
  if settings then
    -- Load consume tracking settings
    if settings.consumeTracking then
      dialog.consumeCheck:SetChecked(settings.consumeTracking.enabled or false)
      dialog.thresholdInput:SetText(tostring(settings.consumeTracking.readyThreshold or 85))
      
      -- Load flask role requirements
      if settings.consumeTracking.requiredFlaskRoles then
        for i = 1, table.getn(dialog.flaskRoleCheckboxes) do
          local checkbox = dialog.flaskRoleCheckboxes[i]
          local roleName = checkbox.roleName
          if roleName then
            checkbox:SetChecked(settings.consumeTracking.requiredFlaskRoles[roleName] or false)
          end
        end
      end
    end
  end
  
  dialog:Show()
end

-- Save settings from dialog
function OGRH.SaveAdvancedSettingsDialog()
  local dialog = OGRH_AdvancedSettingsFrame
  if not dialog then return end
  
  local frame = OGRH_EncounterFrame
  if not frame then return end
  
  local isRaid = not frame.selectedEncounter
  
  -- Collect consume tracking settings
  local newSettings = {
    consumeTracking = {
      enabled = dialog.consumeCheck:GetChecked() or false,
      readyThreshold = tonumber(dialog.thresholdInput:GetText()) or 85,
      requiredFlaskRoles = {}
    }
  }
  
  -- Validate threshold (0-100)
  if newSettings.consumeTracking.readyThreshold < 0 then
    newSettings.consumeTracking.readyThreshold = 0
  elseif newSettings.consumeTracking.readyThreshold > 100 then
    newSettings.consumeTracking.readyThreshold = 100
  end
  
  -- Collect flask role checkboxes
  for i = 1, table.getn(dialog.flaskRoleCheckboxes) do
    local checkbox = dialog.flaskRoleCheckboxes[i]
    local roleName = checkbox.roleName
    if roleName then
      newSettings.consumeTracking.requiredFlaskRoles[roleName] = checkbox:GetChecked() or false
    end
  end
  
  -- Save based on type
  local success = false
  if isRaid then
    success = OGRH.SaveCurrentRaidAdvancedSettings(newSettings)
  else
    -- For encounters, need to include bigwigs settings
    local currentSettings = OGRH.GetCurrentEncounterAdvancedSettings()
    if currentSettings and currentSettings.bigwigs then
      newSettings.bigwigs = currentSettings.bigwigs
    else
      newSettings.bigwigs = {
        enabled = false,
        encounterId = ""
      }
    end
    success = OGRH.SaveCurrentEncounterAdvancedSettings(newSettings)
  end
  
  if success then
    OGRH.Msg("Settings saved.")
  else
    OGRH.Msg("Failed to save settings.")
  end
end

-- Raid settings function calls the main one
function OGRH.ShowRaidSettingsDialog()
  OGRH.ShowAdvancedSettingsDialog()
end
