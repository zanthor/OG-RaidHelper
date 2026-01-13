-- OGRH_AdvancedSettings.lua
-- Advanced settings UI dialogs for raids and encounters
-- Phase 3: UI Layer Implementation

-- Function to get BigWigs zone and boss data dynamically
local function GetBigWigsEncounters()
  -- Check if BigWigs is loaded
  if not BigWigs then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OGRH:|r BigWigs not loaded, using fallback encounter list.")
    return {}
  end
  
  -- Build zone -> bosses map from BigWigs modules
  local encounters = {}
  
  -- Iterate through all registered BigWigs modules
  for name, module in BigWigs:IterateModules() do
    -- Only process boss modules (skip plugins and other modules)
    if module.IsBossModule and module:IsBossModule() then
      -- Get the zone name
      local zoneName = nil
      if type(module.zonename) == "string" then
        zoneName = module.zonename
      elseif type(module.zonename) == "table" and table.getn(module.zonename) > 0 then
        -- Some modules have multiple zones, use first one
        zoneName = module.zonename[1]
      end
      
      -- Get the boss name - use translatedName if available, otherwise module name
      local bossName = module.translatedName or name
      
      -- Add to encounters table if we have both zone and boss
      if zoneName and bossName and type(bossName) == "string" then
        if not encounters[zoneName] then
          encounters[zoneName] = {}
        end
        
        table.insert(encounters[zoneName], {
          name = bossName,
          id = bossName  -- Use boss name as ID for BigWigs detection
        })
      end
    end
  end
  
  -- Sort bosses within each zone alphabetically
  for zoneName, bosses in pairs(encounters) do
    table.sort(bosses, function(a, b)
      if type(a.name) == "string" and type(b.name) == "string" then
        return a.name < b.name
      end
      return false
    end)
  end
  
  return encounters
end

-- Cache BigWigs encounters (will be populated when dialog is opened)
local BIGWIGS_ENCOUNTERS = nil

-- Function to refresh BigWigs encounter cache (call this if BigWigs loads new modules)
function OGRH.RefreshBigWigsEncounters()
  BIGWIGS_ENCOUNTERS = GetBigWigsEncounters()
  DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OGRH:|r BigWigs encounter list refreshed.")
end

-- Show advanced settings dialog for raid or encounter
-- @param forceMode: "raid" to force raid mode, "encounter" to force encounter mode, nil to auto-detect
function OGRH.ShowAdvancedSettingsDialog(forceMode)
  local frame = OGRH_EncounterFrame
  if not frame then
    OGRH.Msg("Encounter frame not found.")
    return
  end
  
  -- Determine if we're editing raid or encounter
  local isRaid
  if forceMode == "raid" then
    isRaid = true
  elseif forceMode == "encounter" then
    isRaid = false
  else
    -- Auto-detect: raid mode if no encounter selected
    isRaid = not frame.selectedEncounter
  end
  local title
  local windowHeight = 330  -- Both raid and encounter include BigWigs section now
  
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
      closeOnClickOutside = true,
      resizable = false
    })
    
    local content = dialog.contentFrame
    
    -- Calculate panel height based on content type
    local panelHeight = 150  -- Base height for raid settings (consume tracking only)
    
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
    local thresholdContainer, thresholdBackdrop, thresholdInput, thresholdLabel = OGST.CreateSingleLineTextBox(consumePanel, 180, 24, {
      label = "Ready Threshold (%):",
      labelAnchor = "LEFT",
      labelWidth = 100,
      textBoxWidth = 40,
      maxLetters = 2,
      numeric = true,
      align = "CENTER"
    })
    OGST.AnchorElement(thresholdContainer, consumeCheckContainer, {position = "right"})
    dialog.thresholdInput = thresholdInput
    
    -- Raid threshold info label (only shown in encounter mode)
    local raidThresholdLabel = OGST.CreateStaticText(consumePanel, {
      text = "Raid set to: %",
      width = 110
    })
    OGST.AnchorElement(raidThresholdLabel, thresholdContainer, {position = "right", align = "center"})
    raidThresholdLabel:Hide()  -- Hidden by default, shown in encounter mode
    dialog.raidThresholdLabel = raidThresholdLabel
    
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
      height = 100
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
      labelWidth = 120
    })
    OGST.AnchorElement(bigwigsCheckContainer, bigwigsHeader, {position = "below"})
    dialog.bigwigsCheck = bigwigsCheck
    
    -- Warning text for encounter mode (shown when raid BigWigs is not enabled)
    local bigwigsWarning = OGST.CreateStaticText(bigwigsPanel, {
      text = "(Must enable BigWigs at raid level first)",
      font = "GameFontHighlightSmall",
      width = 240,
      multiline = false
    })
    bigwigsWarning:SetTextColor(1, 0.5, 0)  -- Orange warning color
    OGST.AnchorElement(bigwigsWarning, bigwigsCheckLabel, {position = "right", align = "center"})
    bigwigsWarning:Hide()  -- Hidden by default, shown only in encounter mode when raid BigWigs is off
    dialog.bigwigsWarning = bigwigsWarning
    
    -- Add onChange handler for BigWigs checkbox (handles both raid and encounter mode)
    bigwigsCheck:SetScript("OnClick", function()
      local isChecked = bigwigsCheck:GetChecked()
      
      -- Handle raid mode menu button
      if dialog.raidMenuBtn and dialog.raidMenuBtn.button then
        if isChecked then
          -- Enable: allow menu to open, restore previous selection or show None
          dialog.raidMenuBtn.disabled = nil
        else
          -- Disable: prevent menu from opening, show disabled text
          dialog.raidMenuBtn.disabled = true
          dialog.raidMenuBtn.button:SetText("<Enable to Set>")
          dialog.selectedEncounterId = nil
          dialog.raidMenuBtn.selectedItems = {}
          if dialog.raidMenuBtn.config then
            dialog.raidMenuBtn.config.buttonText = "<Enable to Set>"
          end
        end
      end
      
      -- Handle encounter mode menu button
      if dialog.encounterMenuBtn and dialog.encounterMenuBtn.button then
        if isChecked then
          -- Enable: allow menu to open, restore previous selection or show None
          dialog.encounterMenuBtn.disabled = nil
        else
          -- Disable: prevent menu from opening, show disabled text
          dialog.encounterMenuBtn.disabled = true
          dialog.encounterMenuBtn.button:SetText("<Enable to Set>")
          dialog.encounterMenuBtn.selectedItems = {}
          if dialog.encounterMenuBtn.config then
            dialog.encounterMenuBtn.config.buttonText = "<Enable to Set>"
          end
        end
      end
    end)
    
    -- === RAID MODE MENU BUTTON (flat zone list) ===
    
    -- Load BigWigs encounters if not already loaded
    if not BIGWIGS_ENCOUNTERS then
      BIGWIGS_ENCOUNTERS = GetBigWigsEncounters()
      
      -- If BigWigs isn't loaded or has no encounters, show a warning
      if not BigWigs then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff8800OGRH:|r BigWigs addon not found. BigWigs integration will not be available.")
      elseif not BIGWIGS_ENCOUNTERS or not next(BIGWIGS_ENCOUNTERS) then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff8800OGRH:|r No BigWigs boss modules found. Make sure BigWigs raid modules are loaded.")
      end
    end
    
    local raidMenuItems = {}
    
    -- Sort raid zones alphabetically
    local zoneNames = {}
    for zoneName, _ in pairs(BIGWIGS_ENCOUNTERS) do
      table.insert(zoneNames, zoneName)
    end
    table.sort(zoneNames)
    
    -- Helper function to update raid menu button text showing selected zone names
    local function UpdateRaidMenuButtonText(menuBtn)
      if not menuBtn or not menuBtn.button then return end
      
      local selectedCount = table.getn(menuBtn.selectedItems or {})
      if selectedCount == 0 then
        menuBtn.button:SetText("<None Selected>")
      elseif selectedCount == 1 then
        menuBtn.button:SetText(menuBtn.selectedItems[1].text)
      else
        -- Multiple selections: show comma-separated zone names
        local displayText = ""
        for i = 1, selectedCount do
          if i > 1 then displayText = displayText .. ", " end
          displayText = displayText .. menuBtn.selectedItems[i].text
        end
        menuBtn.button:SetText(displayText)
      end
    end
    
    -- Add zones to raid mode menu
    table.insert(raidMenuItems, {
      text = "<None Selected>",
      onClick = function()
        if dialog.raidMenuBtn then
          dialog.raidMenuBtn.selectedItems = {}
          UpdateRaidMenuButtonText(dialog.raidMenuBtn)
        end
      end
    })
    
    for _, zoneName in ipairs(zoneNames) do
      table.insert(raidMenuItems, {
        text = zoneName,
        onClick = function()
          -- OGST handles selection internally, just update button text
          UpdateRaidMenuButtonText(dialog.raidMenuBtn)
        end
      })
    end
    
    -- Store the update function for later use
    dialog.UpdateRaidMenuButtonText = UpdateRaidMenuButtonText
    
    -- Create raid mode menu button
    local raidMenuBtn = OGST.CreateMenuButton(bigwigsPanel, {
      label = "BigWigs Raid:",
      labelAnchor = "LEFT",
      labelWidth = 130,
      buttonText = "<None Selected>",
      buttonWidth = 300,
      buttonHeight = 24,
      menuItems = raidMenuItems,
      singleSelect = false
    })
    OGST.AnchorElement(raidMenuBtn, bigwigsCheckContainer, {position = "below"})
    dialog.raidMenuBtn = raidMenuBtn
    
    -- Intercept button click to check disabled state without changing visual appearance
    local originalOnClick = raidMenuBtn.button:GetScript("OnClick")
    raidMenuBtn.button:SetScript("OnClick", function()
      if dialog.raidMenuBtn.disabled then
        -- Don't show menu when disabled
        return
      end
      -- Call original handler when enabled
      if originalOnClick then
        originalOnClick()
      end
    end)
    
    -- === ENCOUNTER MODE MENU BUTTON (encounters for selected raid zone) ===
    -- Helper function to update encounter menu button text showing selected encounter names
    local function UpdateEncounterMenuButtonText(menuBtn)
      if not menuBtn or not menuBtn.button then return end
      
      local selectedCount = table.getn(menuBtn.selectedItems or {})
      if selectedCount == 0 then
        menuBtn.button:SetText("<None Selected>")
      elseif selectedCount == 1 then
        menuBtn.button:SetText(menuBtn.selectedItems[1].text)
      else
        -- Multiple selections: show comma-separated encounter names
        local displayText = ""
        for i = 1, selectedCount do
          if i > 1 then displayText = displayText .. ", " end
          displayText = displayText .. menuBtn.selectedItems[i].text
        end
        menuBtn.button:SetText(displayText)
      end
    end
    
    -- Build all possible encounters upfront (like raid menu)
    local encounterMenuItems = {
      {
        text = "<None Selected>",
        onClick = function()
          if dialog.encounterMenuBtn then
            dialog.encounterMenuBtn.selectedItems = {}
            UpdateEncounterMenuButtonText(dialog.encounterMenuBtn)
          end
        end
      }
    }
    
    -- Add all encounters from all zones
    for zoneName, encounters in pairs(BIGWIGS_ENCOUNTERS) do
      for i = 1, table.getn(encounters) do
        local encounter = encounters[i]
        local capturedName = encounter.name
        local capturedZone = zoneName
        
        table.insert(encounterMenuItems, {
          text = capturedName,
          zone = capturedZone,  -- Store zone for filtering
          onClick = function()
            -- OGST handles selection internally, just update button text
            UpdateEncounterMenuButtonText(dialog.encounterMenuBtn)
          end
        })
      end
    end
    
    -- Store the update function for later use
    dialog.UpdateEncounterMenuButtonText = UpdateEncounterMenuButtonText
    
    -- Create encounter mode menu button
    local encounterMenuBtn = OGST.CreateMenuButton(bigwigsPanel, {
      label = "BigWigs Encounter:",
      labelAnchor = "LEFT",
      labelWidth = 130,
      buttonText = "<None Selected>",
      buttonWidth = 300,
      buttonHeight = 24,
      menuItems = encounterMenuItems,
      singleSelect = false
    })
    OGST.AnchorElement(encounterMenuBtn, bigwigsCheckContainer, {position = "below"})
    
    -- Store all items for filtering
    encounterMenuBtn.allMenuItems = encounterMenuItems
    
    dialog.encounterMenuBtn = encounterMenuBtn
    
    -- Intercept button click to check disabled state without changing visual appearance
    local originalEncounterOnClick = encounterMenuBtn.button:GetScript("OnClick")
    encounterMenuBtn.button:SetScript("OnClick", function()
      if dialog.encounterMenuBtn.disabled then
        -- Don't show menu when disabled
        return
      end
      -- Call original handler when enabled
      if originalEncounterOnClick then
        originalEncounterOnClick()
      end
    end)
    
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
  
  -- Store the mode in the dialog for use by save function
  dialog.isRaidMode = isRaid
  
  -- Update title
  dialog.titleText:SetText(title)
  
  -- Update BigWigs section label and info text based on mode
  if dialog.bigwigsHeader and dialog.bigwigsInfo then
    if isRaid then
      dialog.bigwigsHeader:SetText("BigWigs Raid Selection")
      dialog.bigwigsInfo:SetText("Select the BigWigs raid zone. Individual encounters can then be configured in their settings.")
      if dialog.encounterMenuBtn and dialog.encounterMenuBtn.label then
        dialog.encounterMenuBtn.label:SetText("BigWigs Raid:")
      end
    else
      dialog.bigwigsHeader:SetText("BigWigs Encounter Detection")
      dialog.bigwigsInfo:SetText("When BigWigs detects this encounter, OGRH will automatically select this raid/encounter.")
      if dialog.encounterMenuBtn and dialog.encounterMenuBtn.label then
        dialog.encounterMenuBtn.label:SetText("BigWigs Encounter:")
      end
    end
  end
  
  -- Get the raid's BigWigs zones for encounter mode (needed for menu and enabling/disabling)
  local raidBigWigsZones = {}
  if not isRaid then
    local raid = OGRH.FindRaidByName(frame.selectedRaid)
    if raid and raid.advancedSettings and raid.advancedSettings.bigwigs then
      OGRH.EnsureRaidAdvancedSettings(raid)
      -- Support both new array format and legacy single zone
      if raid.advancedSettings.bigwigs.raidZones and table.getn(raid.advancedSettings.bigwigs.raidZones) > 0 then
        raidBigWigsZones = raid.advancedSettings.bigwigs.raidZones
      elseif raid.advancedSettings.bigwigs.raidZone and raid.advancedSettings.bigwigs.raidZone ~= "" then
        raidBigWigsZones = {raid.advancedSettings.bigwigs.raidZone}
      end
    end
  end
  
  -- Enable/disable BigWigs section for encounters based on raid zone selection
  if not isRaid then
    if not raidBigWigsZones or table.getn(raidBigWigsZones) == 0 then
      -- Disable BigWigs section (just state, no visual changes)
      if dialog.bigwigsCheck then dialog.bigwigsCheck:Disable() end
      if dialog.bigwigsInfo then
        dialog.bigwigsInfo:SetText("Please select a BigWigs raid zone in the raid settings first.")
        dialog.bigwigsInfo:SetTextColor(1, 0.5, 0.5)  -- Red tint
      end
    else
      -- Enable BigWigs section
      if dialog.bigwigsCheck then dialog.bigwigsCheck:Enable() end
      if dialog.bigwigsInfo then
        dialog.bigwigsInfo:SetText("When BigWigs detects this encounter, OGRH will automatically select this raid/encounter.")
        dialog.bigwigsInfo:SetTextColor(1, 1, 1)  -- White
      end
    end
  end
  
  -- Load current settings FIRST
  local settings
  if isRaid then
    settings = OGRH.GetCurrentRaidAdvancedSettings()
  else
    settings = OGRH.GetCurrentEncounterAdvancedSettings()
  end
  
  -- Reset menu button state before loading new settings
  if dialog.raidMenuBtn then
    dialog.raidMenuBtn.selectedItems = {}
    dialog.raidMenuBtn.config.buttonText = "<None Selected>"
    OGST.RebuildMenuButton(dialog.raidMenuBtn, dialog.raidMenuBtn.button, dialog.raidMenuBtn.menu, dialog.raidMenuBtn.config)
  end
  if dialog.encounterMenuBtn then
    dialog.encounterMenuBtn.selectedItems = {}
    dialog.encounterMenuBtn.config.buttonText = "<None Selected>"
    OGST.RebuildMenuButton(dialog.encounterMenuBtn, dialog.encounterMenuBtn.button, dialog.encounterMenuBtn.menu, dialog.encounterMenuBtn.config)
  end
  dialog.selectedEncounterId = nil
  
  -- Show/hide appropriate menu button based on mode
  if dialog.raidMenuBtn and dialog.encounterMenuBtn then
    if isRaid then
      -- Raid mode: show raid menu, hide encounter menu
      dialog.raidMenuBtn:Show()
      dialog.encounterMenuBtn:Hide()
    else
      -- Encounter mode: hide raid menu, show encounter menu
      dialog.raidMenuBtn:Hide()
      dialog.encounterMenuBtn:Show()
      
        -- Check if raid-level BigWigs is enabled
        local raidSettings = OGRH.GetCurrentRaidAdvancedSettings()
        local raidBigWigsEnabled = false
        if raidSettings and raidSettings.bigwigs and raidSettings.bigwigs.enabled then
          raidBigWigsEnabled = true
        end
        
        -- Show warning if raid BigWigs is not enabled
        if dialog.bigwigsWarning then
          if raidBigWigsEnabled then
            dialog.bigwigsWarning:Hide()
          else
            dialog.bigwigsWarning:Show()
          end
        end
      
        -- Filter encounter menu to only show bosses from the raid's selected BigWigs zones
        if dialog.encounterMenuBtn.allMenuItems and raidBigWigsZones and table.getn(raidBigWigsZones) > 0 then
          -- Filter items: show <None Selected> + items matching any of the raid's selected zones
          local filteredItems = {}
          for i = 1, table.getn(dialog.encounterMenuBtn.allMenuItems) do
            local item = dialog.encounterMenuBtn.allMenuItems[i]
            -- Include <None Selected> or items matching any selected raid zone
            if not item.zone then
              table.insert(filteredItems, item)
            else
              -- Check if item's zone is in any of the selected zones
              for j = 1, table.getn(raidBigWigsZones) do
                if item.zone == raidBigWigsZones[j] then
                  table.insert(filteredItems, item)
                  break
                end
              end
            end
          end
          
          -- Update config with filtered items AND preserve singleSelect
          dialog.encounterMenuBtn.config.menuItems = filteredItems
          dialog.encounterMenuBtn.config.singleSelect = false  -- Ensure multi-select is preserved
          
          -- Rebuild menu with filtered items
          OGST.RebuildMenuButton(dialog.encounterMenuBtn, dialog.encounterMenuBtn.button, dialog.encounterMenuBtn.menu, dialog.encounterMenuBtn.config)
        end
    end
  end
  
  -- Load BigWigs settings and update button text
  if settings then
    if settings.bigwigs then
      local bigwigsEnabled = settings.bigwigs.enabled or false
      dialog.bigwigsCheck:SetChecked(bigwigsEnabled)
      
      if isRaid then
        -- Set initial disabled state flag (no visual change to button)
        if dialog.raidMenuBtn then
          dialog.raidMenuBtn.disabled = not bigwigsEnabled
        end
        
        -- Raid mode: Load raid zone selection (supports array or legacy single string)
        local raidZones = settings.bigwigs.raidZones or (settings.bigwigs.raidZone and {settings.bigwigs.raidZone} or {})
        DEFAULT_CHAT_FRAME:AddMessage("[OGRH Debug] Loading raid zones: " .. table.getn(raidZones) .. " zones")
        
        if raidZones and table.getn(raidZones) > 0 then
          -- Find the matching menu items and mark them as selected
          if dialog.raidMenuBtn and dialog.raidMenuBtn.config and dialog.raidMenuBtn.config.menuItems then
            dialog.raidMenuBtn.selectedItems = {}  -- Clear existing selections
            for i = 1, table.getn(raidZones) do
              local zoneName = raidZones[i]
              for _, menuItem in ipairs(dialog.raidMenuBtn.config.menuItems) do
                if menuItem.text == zoneName then
                  table.insert(dialog.raidMenuBtn.selectedItems, menuItem)
                  break
                end
              end
            end
            
            -- Use helper function to set button text
            if dialog.UpdateRaidMenuButtonText then
              dialog.UpdateRaidMenuButtonText(dialog.raidMenuBtn)
            end
            
            -- Rebuild menu to show selection state
            OGST.RebuildMenuButton(dialog.raidMenuBtn, dialog.raidMenuBtn.button, dialog.raidMenuBtn.menu, dialog.raidMenuBtn.config)
          end
        else
          if dialog.raidMenuBtn and dialog.raidMenuBtn.config then
            dialog.raidMenuBtn.selectedItems = {}
            -- Show different text based on whether BigWigs is enabled
            local buttonText = bigwigsEnabled and "<None Selected>" or "<Enable to Set>"
            dialog.raidMenuBtn.config.buttonText = buttonText
            OGST.RebuildMenuButton(dialog.raidMenuBtn, dialog.raidMenuBtn.button, dialog.raidMenuBtn.menu, dialog.raidMenuBtn.config)
            if dialog.raidMenuBtn.button then
              dialog.raidMenuBtn.button:SetText(buttonText)
            end
          end
        end
      else
        -- Encounter mode: Load encounter IDs (supports array or legacy single string)
        -- Set initial disabled state flag (no visual change to button)
        if dialog.encounterMenuBtn then
          dialog.encounterMenuBtn.disabled = not bigwigsEnabled
        end
        
        local encounterIds = settings.bigwigs.encounterIds or (settings.bigwigs.encounterId and {settings.bigwigs.encounterId} or {})
        DEFAULT_CHAT_FRAME:AddMessage("[OGRH Debug] Loading encounter IDs: " .. table.getn(encounterIds) .. " encounters")
        
        if encounterIds and table.getn(encounterIds) > 0 then
          -- Find the matching menu items and mark them as selected
          if dialog.encounterMenuBtn and dialog.encounterMenuBtn.config and dialog.encounterMenuBtn.config.menuItems then
            dialog.encounterMenuBtn.selectedItems = {}  -- Clear existing selections
            for i = 1, table.getn(encounterIds) do
              local encounterId = encounterIds[i]
              for _, menuItem in ipairs(dialog.encounterMenuBtn.config.menuItems) do
                if menuItem.text == encounterId then
                  table.insert(dialog.encounterMenuBtn.selectedItems, menuItem)
                  break
                end
              end
            end
            
            -- Use helper function to set button text
            if dialog.UpdateEncounterMenuButtonText then
              dialog.UpdateEncounterMenuButtonText(dialog.encounterMenuBtn)
            end
            
            -- Rebuild menu to show selection state
            OGST.RebuildMenuButton(dialog.encounterMenuBtn, dialog.encounterMenuBtn.button, dialog.encounterMenuBtn.menu, dialog.encounterMenuBtn.config)
          end
        else
          if dialog.encounterMenuBtn and dialog.encounterMenuBtn.config then
            dialog.encounterMenuBtn.selectedItems = {}
            -- Show different text based on whether BigWigs is enabled
            local buttonText = bigwigsEnabled and "<None Selected>" or "<Enable to Set>"
            dialog.encounterMenuBtn.config.buttonText = buttonText
            OGST.RebuildMenuButton(dialog.encounterMenuBtn, dialog.encounterMenuBtn.button, dialog.encounterMenuBtn.menu, dialog.encounterMenuBtn.config)
            if dialog.encounterMenuBtn.button then
              dialog.encounterMenuBtn.button:SetText(buttonText)
            end
          end
        end
      end
    else
      -- No bigwigs settings - set default
      local menuBtn = isRaid and dialog.raidMenuBtn or dialog.encounterMenuBtn
      if menuBtn and menuBtn.config then
        menuBtn.selectedItems = {}
        menuBtn.config.buttonText = "<None Selected>"
        OGST.RebuildMenuButton(menuBtn, menuBtn.button, menuBtn.menu, menuBtn.config)
      end
    end
    
    -- Load consume tracking settings
    if settings.consumeTracking then
      dialog.consumeCheck:SetChecked(settings.consumeTracking.enabled or false)
      dialog.thresholdInput:SetText(tostring(settings.consumeTracking.readyThreshold or 85))
      
      -- Show raid threshold label if in encounter mode AND raid has consume tracking enabled
      if not isRaid and dialog.raidThresholdLabel then
        local raid = OGRH.FindRaidByName(frame.selectedRaid)
        if raid and raid.advancedSettings and raid.advancedSettings.consumeTracking and raid.advancedSettings.consumeTracking.enabled then
          local raidThreshold = raid.advancedSettings.consumeTracking.readyThreshold or 85
          dialog.raidThresholdLabel:SetText("|cffaaaaaa(Raid set to: " .. raidThreshold .. "%)|r")
          dialog.raidThresholdLabel:Show()
        else
          dialog.raidThresholdLabel:Hide()
        end
      elseif dialog.raidThresholdLabel then
        dialog.raidThresholdLabel:Hide()
      end
      
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
  
  -- Use the stored mode from when dialog was opened, not the current frame state
  local isRaid = dialog.isRaidMode or false
  
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
  
  -- Collect BigWigs settings
  newSettings.bigwigs = {
    enabled = dialog.bigwigsCheck:GetChecked() or false
  }
  
  if isRaid then
    -- Raid mode: Save raid zone
    -- Save selected zones as array
    local selectedZones = {}
    if dialog.raidMenuBtn and dialog.raidMenuBtn.selectedItems then
      for i = 1, table.getn(dialog.raidMenuBtn.selectedItems) do
        table.insert(selectedZones, dialog.raidMenuBtn.selectedItems[i].text)
      end
    end
    newSettings.bigwigs.raidZones = selectedZones
    -- Keep legacy single value for backward compatibility (use first selected)
    newSettings.bigwigs.raidZone = (table.getn(selectedZones) > 0) and selectedZones[1] or ""
    DEFAULT_CHAT_FRAME:AddMessage("[OGRH Debug] Saving " .. table.getn(selectedZones) .. " raid zones")
  else
    -- Encounter mode: Save encounter IDs
    local selectedEncounters = {}
    if dialog.encounterMenuBtn and dialog.encounterMenuBtn.selectedItems then
      for i = 1, table.getn(dialog.encounterMenuBtn.selectedItems) do
        table.insert(selectedEncounters, dialog.encounterMenuBtn.selectedItems[i].text)
      end
    end
    newSettings.bigwigs.encounterIds = selectedEncounters
    -- Keep legacy single value for backward compatibility (use first selected)
    newSettings.bigwigs.encounterId = (table.getn(selectedEncounters) > 0) and selectedEncounters[1] or ""
    DEFAULT_CHAT_FRAME:AddMessage("[OGRH Debug] Saving " .. table.getn(selectedEncounters) .. " encounter IDs")
  end
  
  -- Save based on type
  local success = false
  if isRaid then
    success = OGRH.SaveCurrentRaidAdvancedSettings(newSettings)
  else
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
  OGRH.ShowAdvancedSettingsDialog("raid")
end
