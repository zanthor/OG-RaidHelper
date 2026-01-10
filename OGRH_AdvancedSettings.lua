-- OGRH_AdvancedSettings.lua
-- Advanced settings UI dialogs for raids and encounters
-- Phase 3: UI Layer Implementation

-- BigWigs Encounter Database (organized by zone/raid)
local BIGWIGS_ENCOUNTERS = {
  ["Molten Core"] = {
    {name = "Lucifron", id = "Lucifron"},
    {name = "Magmadar", id = "Magmadar"},
    {name = "Gehennas", id = "Gehennas"},
    {name = "Garr", id = "Garr"},
    {name = "Shazzrah", id = "Shazzrah"},
    {name = "Baron Geddon", id = "Baron Geddon"},
    {name = "Golemagg the Incinerator", id = "Golemagg the Incinerator"},
    {name = "Sulfuron Harbinger", id = "Sulfuron Harbinger"},
    {name = "Majordomo Executus", id = "Majordomo Executus"},
    {name = "Ragnaros", id = "Ragnaros"},
  },
  ["Blackwing Lair"] = {
    {name = "Razorgore the Untamed", id = "Razorgore the Untamed"},
    {name = "Vaelastrasz the Corrupt", id = "Vaelastrasz the Corrupt"},
    {name = "Broodlord Lashlayer", id = "Broodlord Lashlayer"},
    {name = "Firemaw", id = "Firemaw"},
    {name = "Ebonroc", id = "Ebonroc"},
    {name = "Flamegor", id = "Flamegor"},
    {name = "Chromaggus", id = "Chromaggus"},
    {name = "Nefarian", id = "Nefarian"},
  },
  ["Ruins of Ahn'Qiraj"] = {
    {name = "Kurinnaxx", id = "Kurinnaxx"},
    {name = "General Rajaxx", id = "General Rajaxx"},
    {name = "Moam", id = "Moam"},
    {name = "Buru the Gorger", id = "Buru the Gorger"},
    {name = "Ayamiss the Hunter", id = "Ayamiss the Hunter"},
    {name = "Ossirian the Unscarred", id = "Ossirian the Unscarred"},
  },
  ["Ahn'Qiraj Temple"] = {
    {name = "The Prophet Skeram", id = "The Prophet Skeram"},
    {name = "Silithid Royalty", id = "Silithid Royalty"},
    {name = "Battleguard Sartura", id = "Battleguard Sartura"},
    {name = "Fankriss the Unyielding", id = "Fankriss the Unyielding"},
    {name = "Viscidus", id = "Viscidus"},
    {name = "Princess Huhuran", id = "Princess Huhuran"},
    {name = "The Twin Emperors", id = "The Twin Emperors"},
    {name = "Ouro", id = "Ouro"},
    {name = "C'Thun", id = "C'Thun"},
  },
  ["Naxxramas"] = {
    {name = "Anub'Rekhan", id = "Anub'Rekhan"},
    {name = "Grand Widow Faerlina", id = "Grand Widow Faerlina"},
    {name = "Maexxna", id = "Maexxna"},
    {name = "Noth the Plaguebringer", id = "Noth the Plaguebringer"},
    {name = "Heigan the Unclean", id = "Heigan the Unclean"},
    {name = "Loatheb", id = "Loatheb"},
    {name = "Instructor Razuvious", id = "Instructor Razuvious"},
    {name = "Gothik the Harvester", id = "Gothik the Harvester"},
    {name = "The Four Horsemen", id = "The Four Horsemen"},
    {name = "Patchwerk", id = "Patchwerk"},
    {name = "Grobbulus", id = "Grobbulus"},
    {name = "Gluth", id = "Gluth"},
    {name = "Thaddius", id = "Thaddius"},
    {name = "Sapphiron", id = "Sapphiron"},
    {name = "Kel'Thuzad", id = "Kel'Thuzad"},
  },
  ["Zul'Gurub"] = {
    {name = "High Priestess Jeklik", id = "High Priestess Jeklik"},
    {name = "High Priest Venoxis", id = "High Priest Venoxis"},
    {name = "High Priestess Mar'li", id = "High Priestess Mar'li"},
    {name = "Bloodlord Mandokir", id = "Bloodlord Mandokir"},
    {name = "Gri'lek", id = "Gri'lek"},
    {name = "Hazza'arah", id = "Hazza'arah"},
    {name = "Renataki", id = "Renataki"},
    {name = "Wushoolay", id = "Wushoolay"},
    {name = "Gahz'ranka", id = "Gahz'ranka"},
    {name = "High Priest Thekal", id = "High Priest Thekal"},
    {name = "High Priestess Arlokk", id = "High Priestess Arlokk"},
    {name = "Jin'do the Hexxer", id = "Jin'do the Hexxer"},
    {name = "Hakkar", id = "Hakkar"},
  },
  ["Onyxia's Lair"] = {
    {name = "Onyxia", id = "Onyxia"},
  },
  ["World Bosses"] = {
    {name = "Azuregos", id = "Azuregos"},
    {name = "Lord Kazzak", id = "Lord Kazzak"},
    {name = "Emeriss", id = "Emeriss"},
    {name = "Lethon", id = "Lethon"},
    {name = "Taerar", id = "Taerar"},
    {name = "Ysondre", id = "Ysondre"},
  },
}

-- Show advanced settings dialog for raid or encounter
function OGRH.ShowAdvancedSettingsDialog()
  DEFAULT_CHAT_FRAME:AddMessage("|cffff00ff=== ShowAdvancedSettingsDialog called ===|r")
  DEFAULT_CHAT_FRAME:AddMessage("Dialog exists: " .. tostring(OGRH_AdvancedSettingsFrame ~= nil))
  
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
    windowHeight = 450  -- Taller for encounter settings (includes BigWigs section)
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
    
    -- Content panel for consume settings (positioned first)
    local consumePanel = OGST.CreateContentPanel(content, {
      height = panelHeight
    })
    OGST.AnchorElement(consumePanel, content, {position = "top", fill = "horizontal"})
    consumePanel:SetPoint("RIGHT", content, "RIGHT", 0, 0)
    dialog.consumePanel = consumePanel
    
    -- Consume Tracking Requirements header (inside panel)
    local consumeHeader = OGST.CreateStaticText(consumePanel, {
      text = "Consume Tracking Requirements",
      font = "GameFontNormalLarge",
      width = 460
    })
    OGST.AnchorElement(consumeHeader, consumePanel, {position = "top"})
    dialog.consumeHeader = consumeHeader
    
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
    
    -- BigWigs section (encounter-only, positioned below consume tracking)
    local bigwigsPanel = OGST.CreateContentPanel(content, {
      height = 120
    })
    OGST.AnchorElement(bigwigsPanel, consumePanel, {position = "below", fill = "horizontal"})
    bigwigsPanel:SetPoint("RIGHT", content, "RIGHT", 0, 0)
    dialog.bigwigsPanel = bigwigsPanel
    
    local bigwigsHeader = OGST.CreateStaticText(bigwigsPanel, {
      text = "BigWigs Encounter Detection",
      font = "GameFontNormalLarge",
      width = 460
    })
    OGST.AnchorElement(bigwigsHeader, bigwigsPanel, {position = "top"})
    dialog.bigwigsHeader = bigwigsHeader
    
    -- BigWigs enable checkbox
    local bigwigsCheckContainer, bigwigsCheck, bigwigsCheckLabel = OGST.CreateCheckbox(bigwigsPanel, {
      label = "Enable BigWigs Auto-Select",
      labelAnchor = "RIGHT",
      checked = false,
      labelWidth = 180
    })
    OGST.AnchorElement(bigwigsCheckContainer, bigwigsHeader, {position = "below"})
    dialog.bigwigsCheck = bigwigsCheck
    
    -- Build menu items for BigWigs encounters
    local menuItems = {}
    
    -- Sort raid zones alphabetically
    local zoneNames = {}
    for zoneName, _ in pairs(BIGWIGS_ENCOUNTERS) do
      table.insert(zoneNames, zoneName)
    end
    table.sort(zoneNames)
    
    -- Add "Clear Selection" at top
    table.insert(menuItems, {
      text = "<Clear Selection>",
      onClick = function()
        dialog.selectedEncounterId = nil
        dialog.encounterMenuBtn.button:SetText("<None Selected>")
      end
    })
    
    -- Build hierarchical menu with submenus
    for _, zoneName in ipairs(zoneNames) do
      local encounters = BIGWIGS_ENCOUNTERS[zoneName]
      local submenuItems = {}
      
      for i = 1, table.getn(encounters) do
        local encounter = encounters[i]
        local encName = encounter.name
        local encId = encounter.id
        
        table.insert(submenuItems, {
          text = encName,
          onClick = function()
            dialog.selectedEncounterId = encId
            dialog.encounterMenuBtn.button:SetText(encName)
          end
        })
      end
      
      table.insert(menuItems, {
        text = zoneName,
        submenu = submenuItems
      })
    end
    
    -- BigWigs Encounter menu button
    DEFAULT_CHAT_FRAME:AddMessage("|cffff00ffAbout to call CreateMenuButton with " .. table.getn(menuItems) .. " items|r")
    DEFAULT_CHAT_FRAME:AddMessage("bigwigsPanel = " .. tostring(bigwigsPanel))
    DEFAULT_CHAT_FRAME:AddMessage("bigwigsCheckContainer = " .. tostring(bigwigsCheckContainer))
    local success, result = pcall(function()
      return OGST.CreateMenuButton(bigwigsPanel, {
        label = "BigWigs Encounter:",
        labelAnchor = "LEFT",
        labelWidth = 130,
        buttonText = "<None Selected>",
        buttonWidth = 300,
        buttonHeight = 24,
        menuItems = menuItems,
        singleSelect = true
      })
    end)
    
    if not success then
      DEFAULT_CHAT_FRAME:AddMessage("|cffff0000ERROR creating menu button: " .. tostring(result) .. "|r")
      return
    end
    
    local encounterMenuBtn = result
    DEFAULT_CHAT_FRAME:AddMessage("|cffff00ffCreateMenuButton returned successfully|r")
    OGST.AnchorElement(encounterMenuBtn, bigwigsCheckContainer, {position = "below"})
    dialog.encounterMenuBtn = encounterMenuBtn
    dialog.selectedEncounterId = nil
    
    -- BigWigs info text
    local bigwigsInfo = OGST.CreateStaticText(bigwigsPanel, {
      text = "When BigWigs detects this encounter, OGRH will automatically select this raid/encounter.",
      font = "GameFontHighlightSmall",
      width = 440,
      multiline = true
    })
    OGST.AnchorElement(bigwigsInfo, encounterMenuBtn, {position = "below"})
    
    -- Save button (bottom right)
    local saveBtn = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    saveBtn:SetWidth(120)
    saveBtn:SetHeight(24)
    saveBtn:SetText("Save")
    OGST.StyleButton(saveBtn)
    saveBtn:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -10, 10)
    dialog.saveBtn = saveBtn
    
    saveBtn:SetScript("OnClick", function()
      OGRH.SaveAdvancedSettingsDialog()
      dialog:Hide()
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
  
  -- Update title and height
  dialog.titleText:SetText(title)
  if isRaid then
    dialog:SetHeight(275)
  else
    dialog:SetHeight(450)
  end
  
  -- Show/hide BigWigs section based on raid vs encounter
  if dialog.bigwigsHeader and dialog.bigwigsPanel then
    if isRaid then
      dialog.bigwigsHeader:Hide()
      dialog.bigwigsPanel:Hide()
    else
      dialog.bigwigsHeader:Show()
      dialog.bigwigsPanel:Show()
    end
  end
  
  -- Load current settings
  local settings
  if isRaid then
    settings = OGRH.GetCurrentRaidAdvancedSettings()
  else
    settings = OGRH.GetCurrentEncounterAdvancedSettings()
  end
  
  if settings then
    -- Load BigWigs settings (encounter only)
    if not isRaid and settings.bigwigs then
      dialog.bigwigsCheck:SetChecked(settings.bigwigs.enabled or false)
      dialog.selectedEncounterId = settings.bigwigs.encounterId
      
      -- Update menu button text
      if settings.bigwigs.encounterId and settings.bigwigs.encounterId ~= "" then
        dialog.encounterMenuBtn.button:SetText(settings.bigwigs.encounterId)
      else
        dialog.encounterMenuBtn.button:SetText("<None Selected>")
      end
    end
    
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
    -- For encounters, collect BigWigs settings from dialog
    newSettings.bigwigs = {
      enabled = dialog.bigwigsCheck:GetChecked() or false,
      encounterId = dialog.selectedEncounterId or ""
    }
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
