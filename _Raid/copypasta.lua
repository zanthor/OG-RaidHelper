-- copypasta.lua
-- Copy/Paste functionality for raids and encounters
-- Provides UI for duplicating raid/encounter structures

if not OGRH then
  DEFAULT_CHAT_FRAME:AddMessage("|cffff0000Error: copypasta requires OGRH_Core to be loaded first!|r")
  return
end

-- Initialize namespace
OGRH.CopyPasta = OGRH.CopyPasta or {}

-- ============================================
-- UNIFIED COPY DIALOG
-- ============================================

-- Show dialog for copying a raid or encounter
function OGRH.CopyPasta.ShowCopyDialog(copyType, sourceRaidIdx, sourceRaidName, sourceEncounterIdx, sourceEncounterName)
  -- Validate parameters based on copy type
  if copyType == "raid" then
    if not sourceRaidIdx or not sourceRaidName then
      OGRH.Msg("|cffff0000[RH-CopyPasta]|r Invalid raid copy parameters")
      return
    end
  elseif copyType == "encounter" then
    if not sourceRaidIdx or not sourceEncounterIdx or not sourceRaidName or not sourceEncounterName then
      OGRH.Msg("|cffff0000[RH-CopyPasta]|r Invalid encounter copy parameters")
      return
    end
  else
    OGRH.Msg("|cffff0000[RH-CopyPasta]|r Invalid copy type")
    return
  end
  
  -- Determine title and dimensions
  local title = (copyType == "raid") and ("Copy Raid: " .. sourceRaidName) or ("Copy Encounter: " .. sourceEncounterName)
  local height = (copyType == "raid") and 100 or 130
  
  -- Create dialog using OGST
  local dialog = OGST.CreateStandardWindow({
    name = "OGRH_CopyDialog",
    width = 450,
    height = height,
    title = title,
    closeButton = true,
    escapeCloses = true,
    resizable = false
  })
  
  dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  
  -- Store source data and type
  dialog.copyType = copyType
  dialog.sourceRaidIdx = sourceRaidIdx
  dialog.sourceRaidName = sourceRaidName
  dialog.sourceEncounterIdx = sourceEncounterIdx
  dialog.sourceEncounterName = sourceEncounterName
  dialog.destRaidIdx = (copyType == "encounter") and sourceRaidIdx or nil
  dialog.destRaidName = (copyType == "encounter") and sourceRaidName or nil
  dialog.destEncounterIdx = nil
  dialog.destEncounterName = nil
  
  -- Get raids data
  local raids = OGRH.SVM.GetPath("encounterMgmt.raids")
  if not raids then
    OGRH.Msg("|cffff0000[RH-CopyPasta]|r No raids available")
    dialog:Hide()
    return
  end
  
  local anchorTarget = dialog.contentFrame
  
  -- For encounters, create raid selection menu first
  if copyType == "encounter" then
    -- Get the display name for the source raid
    local sourceRaid = raids[sourceRaidIdx]
    local sourceRaidDisplayName = sourceRaid and (sourceRaid.displayName or sourceRaid.name) or sourceRaidName
    
    local raidMenuItems = {}
    for i = 1, table.getn(raids) do
      local raid = raids[i]
      local displayName = raid.displayName or raid.name
      local isSelected = (i == sourceRaidIdx)
      local capturedIdx = i
      local capturedName = raid.name
      local capturedDisplayName = displayName
      
      table.insert(raidMenuItems, {
        text = capturedDisplayName,
        selected = isSelected,
        onClick = function()
          dialog.destRaidIdx = capturedIdx
          dialog.destRaidName = capturedName
          dialog.raidMenuBtn:SetText(capturedDisplayName)
          OGRH.CopyPasta.RebuildEncounterMenu(dialog, capturedIdx)
        end
      })
    end
    
    local raidMenuContainer, raidMenuBtn, raidMenu, raidMenuLabel = OGST.CreateMenuButton(dialog.contentFrame, {
      label = "Raid",
      labelAnchor = "LEFT",
      labelWidth = 35,
      buttonText = sourceRaidDisplayName,
      buttonWidth = 140,
      singleSelect = true,
      menuItems = raidMenuItems
    })
    OGST.AnchorElement(raidMenuContainer, dialog.contentFrame, {position = "top", align = "left"})
    dialog.raidMenuContainer = raidMenuContainer
    dialog.raidMenuBtn = raidMenuBtn
    dialog.raidMenu = raidMenu
    anchorTarget = raidMenuContainer
  end
  
  -- Create target menu (raids for raid copy, encounters for encounter copy)
  local targetMenuItems = {}
  
  if copyType == "raid" then
    -- Build raid menu items
    table.insert(targetMenuItems, {
      text = "New Raid...",
      selected = true,
      onClick = function()
        dialog.destRaidIdx = nil
        dialog.destRaidName = dialog.placeholderText
        dialog.targetMenuBtn:SetText("New Raid...")
        if dialog.nameTextBoxContainer then
          dialog.nameTextBoxContainer:Show()
        end
        if dialog.nameTextBox then
          dialog.nameTextBox:SetText(dialog.placeholderText)
        end
      end
    })
    
    for i = 1, table.getn(raids) do
      if i ~= sourceRaidIdx then
        local raid = raids[i]
        local displayName = raid.displayName or raid.name
        local capturedIdx = i
        local capturedRaidName = raid.name
        local capturedDisplayName = displayName
        table.insert(targetMenuItems, {
          text = capturedDisplayName,
          selected = false,
          onClick = function()
            dialog.destRaidIdx = capturedIdx
            dialog.destRaidName = capturedRaidName
            dialog.targetMenuBtn:SetText(capturedDisplayName)
            if dialog.nameTextBoxContainer then
              dialog.nameTextBoxContainer:Hide()
            end
          end
        })
      end
    end
  else
    -- Build encounter menu items (will be populated by RebuildEncounterMenu)
    table.insert(targetMenuItems, {
      text = "New Encounter...",
      selected = true,
      onClick = function()
        dialog.destEncounterIdx = nil
        dialog.destEncounterName = dialog.placeholderText
        dialog.targetMenuBtn:SetText("New Encounter...")
        if dialog.nameTextBoxContainer then
          dialog.nameTextBoxContainer:Show()
        end
        if dialog.nameTextBox then
          dialog.nameTextBox:SetText(dialog.placeholderText)
        end
      end
    })
  end
  
  local targetLabel = "Target"
  local targetWidth = 35
  local buttonWidth = 140
  local buttonText = (copyType == "raid") and "New Raid..." or "New Encounter..."
  
  local targetMenuConfig = {
    label = targetLabel,
    labelAnchor = "LEFT",
    labelWidth = targetWidth,
    buttonText = buttonText,
    buttonWidth = buttonWidth,
    singleSelect = true,
    menuItems = targetMenuItems
  }
  
  local targetMenuContainer, targetMenuBtn, targetMenu, targetMenuLabel = OGST.CreateMenuButton(dialog.contentFrame, targetMenuConfig)
  
  if copyType == "raid" then
    OGST.AnchorElement(targetMenuContainer, anchorTarget, {position = "top", align = "left"})
  else
    OGST.AnchorElement(targetMenuContainer, anchorTarget, {position = "below", gap = -5})
  end
  
  dialog.targetMenuContainer = targetMenuContainer
  dialog.targetMenuBtn = targetMenuBtn
  dialog.targetMenu = targetMenu
  targetMenuContainer.config = targetMenuConfig
  
  -- Create text box for new name
  local textBoxWidth = 215
  local placeholderText = (copyType == "raid") and (sourceRaidName .. " Copy") or (sourceEncounterName .. " Copy")
  dialog.placeholderText = placeholderText
  
  local nameTextBoxContainer, nameTextBoxBackdrop, nameTextBox, nameLabel = OGST.CreateSingleLineTextBox(
    dialog.contentFrame,
    textBoxWidth,
    24,
    {
      align = "LEFT",
      maxLetters = 50,
      onChange = function(text)
        if copyType == "raid" then
          dialog.destRaidName = text
        else
          dialog.destEncounterName = text
        end
      end,
      onEnter = function(text)
        if copyType == "raid" then
          dialog.destRaidName = text
        else
          dialog.destEncounterName = text
        end
      end
    }
  )
  
  OGST.AnchorElement(nameTextBoxContainer, targetMenuContainer, {position = "right", gap = 0})
  
  dialog.nameTextBoxContainer = nameTextBoxContainer
  dialog.nameTextBox = nameTextBox
  
  -- Set initial placeholder text
  nameTextBox:SetText(placeholderText)
  if copyType == "raid" then
    dialog.destRaidName = placeholderText
  else
    dialog.destEncounterName = placeholderText
  end
  
  -- For encounters, build initial encounter menu
  if copyType == "encounter" then
    OGRH.CopyPasta.RebuildEncounterMenu(dialog, sourceRaidIdx)
  end
  
  -- Cancel button (bottom right)
  local cancelBtn = CreateFrame("Button", nil, dialog.contentFrame, "UIPanelButtonTemplate")
  cancelBtn:SetWidth(80)
  cancelBtn:SetHeight(24)
  cancelBtn:SetText("Cancel")
  OGRH.StyleButton(cancelBtn)
  OGST.AnchorElement(cancelBtn, dialog.contentFrame, {position = "alignBottom", align = "right"})
  
  cancelBtn:SetScript("OnClick", function()
    dialog:Hide()
  end)
  
  -- Save button (to the left of Cancel)
  local saveBtn = CreateFrame("Button", nil, dialog.contentFrame, "UIPanelButtonTemplate")
  saveBtn:SetWidth(80)
  saveBtn:SetHeight(24)
  saveBtn:SetText("Save")
  OGRH.StyleButton(saveBtn)
  OGST.AnchorElement(saveBtn, cancelBtn, {position = "left", gap = 5})
  
  saveBtn:SetScript("OnClick", function()
    if copyType == "raid" then
      -- Validate raid name
      if not dialog.destRaidName or dialog.destRaidName == "" then
        OGRH.Msg("|cffffaa00[RH-CopyPasta]|r Please enter a raid name")
        return
      end
      
      -- Check for overwrite
      if dialog.destRaidIdx then
        StaticPopupDialogs["OGRH_CONFIRM_OVERWRITE_RAID"] = {
          text = "Overwrite raid: " .. dialog.destRaidName .. "?\n\nThis will replace all encounters and settings.",
          button1 = "Overwrite",
          button2 = "Cancel",
          OnAccept = function()
            OGRH.CopyPasta.PerformRaidCopy(dialog.sourceRaidIdx, dialog.destRaidIdx, dialog.destRaidName)
            dialog:Hide()
          end,
          timeout = 0,
          whileDead = 1,
          hideOnEscape = 1
        }
        StaticPopup_Show("OGRH_CONFIRM_OVERWRITE_RAID")
      else
        OGRH.CopyPasta.PerformRaidCopy(dialog.sourceRaidIdx, nil, dialog.destRaidName)
        dialog:Hide()
      end
    else
      -- Validate encounter name
      if not dialog.destEncounterName or dialog.destEncounterName == "" then
        OGRH.Msg("|cffffaa00[RH-CopyPasta]|r Please enter an encounter name")
        return
      end
      
      -- Check for overwrite
      if dialog.destEncounterIdx then
        StaticPopupDialogs["OGRH_CONFIRM_OVERWRITE_ENCOUNTER"] = {
          text = "Overwrite encounter: " .. dialog.destEncounterName .. "?\n\nThis will replace all roles and settings.",
          button1 = "Overwrite",
          button2 = "Cancel",
          OnAccept = function()
            OGRH.CopyPasta.PerformEncounterCopy(
              dialog.sourceRaidIdx,
              dialog.sourceEncounterIdx,
              dialog.destRaidIdx,
              dialog.destEncounterIdx,
              dialog.destEncounterName
            )
            dialog:Hide()
          end,
          timeout = 0,
          whileDead = 1,
          hideOnEscape = 1
        }
        StaticPopup_Show("OGRH_CONFIRM_OVERWRITE_ENCOUNTER")
      else
        OGRH.CopyPasta.PerformEncounterCopy(
          dialog.sourceRaidIdx,
          dialog.sourceEncounterIdx,
          dialog.destRaidIdx,
          nil,
          dialog.destEncounterName
        )
        dialog:Hide()
      end
    end
  end)
  
  dialog:Show()
end

-- Legacy wrapper for raid copy
function OGRH.CopyPasta.ShowRaidCopyDialog(sourceRaidIdx, sourceRaidName)
  OGRH.CopyPasta.ShowCopyDialog("raid", sourceRaidIdx, sourceRaidName, nil, nil)
end

-- Legacy wrapper for encounter copy
function OGRH.CopyPasta.ShowEncounterCopyDialog(sourceRaidIdx, sourceEncounterIdx, sourceRaidName, sourceEncounterName)
  OGRH.CopyPasta.ShowCopyDialog("encounter", sourceRaidIdx, sourceRaidName, sourceEncounterIdx, sourceEncounterName)
end

-- Helper function to rebuild encounter menu when raid changes
function OGRH.CopyPasta.RebuildEncounterMenu(dialog, raidIdx)
  if not dialog or not dialog.targetMenuContainer or not dialog.targetMenuBtn or not dialog.targetMenu then
    return
  end
  
  local raids = OGRH.SVM.GetPath("encounterMgmt.raids")
  if not raids or not raids[raidIdx] then
    return
  end
  
  local raid = raids[raidIdx]
  local menuItems = {}
  
  -- Add "New Encounter..." option
  table.insert(menuItems, {
    text = "New Encounter...",
    selected = true,
    onClick = function()
      dialog.destEncounterIdx = nil
      dialog.destEncounterName = dialog.placeholderText
      dialog.targetMenuBtn:SetText("New Encounter...")
      if dialog.nameTextBoxContainer then
        dialog.nameTextBoxContainer:Show()
      end
      if dialog.nameTextBox then
        dialog.nameTextBox:SetText(dialog.placeholderText)
      end
    end
  })
  
  -- Add existing encounters (except source if same raid)
  if raid.encounters then
    for i = 1, table.getn(raid.encounters) do
      local encounter = raid.encounters[i]
      local skipThis = (raidIdx == dialog.sourceRaidIdx and i == dialog.sourceEncounterIdx)
      
      if not skipThis then
        local capturedIdx = i
        local capturedName = encounter.name
        table.insert(menuItems, {
          text = capturedName,
          selected = false,
          onClick = function()
            dialog.destEncounterIdx = capturedIdx
            dialog.destEncounterName = capturedName
            dialog.targetMenuBtn:SetText(capturedName)
            if dialog.nameTextBoxContainer then
              dialog.nameTextBoxContainer:Hide()
            end
          end
        })
      end
    end
  end
  
  -- Update the config menuItems and rebuild using OGST
  dialog.targetMenuContainer.config.menuItems = menuItems
  dialog.targetMenuContainer.selectedItems = {}
  
  -- Mark first item (New Encounter...) as selected
  if table.getn(menuItems) > 0 then
    table.insert(dialog.targetMenuContainer.selectedItems, menuItems[1])
  end
  
  OGST.RebuildMenuButton(dialog.targetMenuContainer, dialog.targetMenuBtn, dialog.targetMenu, dialog.targetMenuContainer.config)
  
  -- Manually wire up onClick handlers for menu items
  if dialog.targetMenu and dialog.targetMenu.items then
    for i = 1, table.getn(menuItems) do
      if dialog.targetMenu.items[i] and menuItems[i].onClick then
        local item = dialog.targetMenu.items[i]
        local onClick = menuItems[i].onClick
        item:SetScript("OnClick", function()
          onClick()
          dialog.targetMenu:Hide()
        end)
      end
    end
  end
  
  -- Reset to "New Encounter..." state
  dialog.destEncounterIdx = nil
  dialog.destEncounterName = dialog.placeholderText
  dialog.targetMenuBtn:SetText("New Encounter...")
  if dialog.nameTextBoxContainer then
    dialog.nameTextBoxContainer:Show()
  end
  if dialog.nameTextBox then
    dialog.nameTextBox:SetText(dialog.placeholderText)
  end
end

-- ============================================
-- COPY OPERATIONS
-- ============================================

-- Perform raid copy operation
function OGRH.CopyPasta.PerformRaidCopy(sourceRaidIdx, destRaidIdx, destRaidName)
  local raids = OGRH.SVM.GetPath("encounterMgmt.raids")
  if not raids or not raids[sourceRaidIdx] then
    OGRH.Msg("|cffff0000[RH-CopyPasta]|r Source raid not found")
    return
  end
  
  -- Deep copy source raid
  local sourceRaid = raids[sourceRaidIdx]
  local newRaid = OGRH.CopyPasta.DeepCopyTable(sourceRaid)
  newRaid.name = destRaidName
  newRaid.displayName = destRaidName
  
  if destRaidIdx then
    -- Overwrite existing raid
    OGRH.SVM.SetPath("encounterMgmt.raids." .. destRaidIdx, newRaid, {
      syncLevel = (destRaidIdx == 1) and "REALTIME" or "MANUAL",
      componentType = "structure"
    })
    OGRH.Msg("|cff00ff00[RH-CopyPasta]|r Raid copied to: " .. destRaidName)
  else
    -- Create new raid
    table.insert(raids, newRaid)
    OGRH.SVM.SetPath("encounterMgmt.raids", raids, {
      syncLevel = "MANUAL",
      componentType = "structure"
    })
    OGRH.Msg("|cff00ff00[RH-CopyPasta]|r New raid created: " .. destRaidName)
  end
  
  -- Refresh UI if encounter frame is open
  if OGRH_EncounterFrame and OGRH_EncounterFrame.RefreshRaidsList then
    OGRH_EncounterFrame.RefreshRaidsList()
  end
  if OGRH_EncounterFrame and OGRH_EncounterFrame.RefreshEncountersList then
    OGRH_EncounterFrame.RefreshEncountersList()
  end
end

-- Perform encounter copy operation
function OGRH.CopyPasta.PerformEncounterCopy(sourceRaidIdx, sourceEncounterIdx, destRaidIdx, destEncounterIdx, destEncounterName)
  local raids = OGRH.SVM.GetPath("encounterMgmt.raids")
  if not raids or not raids[sourceRaidIdx] or not raids[sourceRaidIdx].encounters then
    OGRH.Msg("|cffff0000[RH-CopyPasta]|r Source encounter not found")
    return
  end
  
  if not raids[destRaidIdx] then
    OGRH.Msg("|cffff0000[RH-CopyPasta]|r Destination raid not found")
    return
  end
  
  -- Deep copy source encounter
  local sourceEncounter = raids[sourceRaidIdx].encounters[sourceEncounterIdx]
  local newEncounter = OGRH.CopyPasta.DeepCopyTable(sourceEncounter)
  newEncounter.name = destEncounterName
  
  if destEncounterIdx then
    -- Overwrite existing encounter
    OGRH.SVM.SetPath("encounterMgmt.raids." .. destRaidIdx .. ".encounters." .. destEncounterIdx, newEncounter, {
      syncLevel = (destRaidIdx == 1) and "REALTIME" or "MANUAL",
      componentType = "structure"
    })
    OGRH.Msg("|cff00ff00[RH-CopyPasta]|r Encounter copied to: " .. destEncounterName)
  else
    -- Create new encounter
    if not raids[destRaidIdx].encounters then
      raids[destRaidIdx].encounters = {}
    end
    table.insert(raids[destRaidIdx].encounters, newEncounter)
    OGRH.SVM.SetPath("encounterMgmt.raids." .. destRaidIdx .. ".encounters", raids[destRaidIdx].encounters, {
      syncLevel = (destRaidIdx == 1) and "REALTIME" or "MANUAL",
      componentType = "structure"
    })
    OGRH.Msg("|cff00ff00[RH-CopyPasta]|r New encounter created: " .. destEncounterName)
  end
  
  -- Refresh UI if encounter frame is open
  if OGRH_EncounterFrame and OGRH_EncounterFrame.RefreshEncountersList then
    OGRH_EncounterFrame.RefreshEncountersList()
  end
  if OGRH_EncounterFrame and OGRH_EncounterFrame.RefreshRoleContainers then
    OGRH_EncounterFrame.RefreshRoleContainers()
  end
end

-- Deep copy a table (handles nested tables)
function OGRH.CopyPasta.DeepCopyTable(original)
  local copy
  if type(original) == "table" then
    copy = {}
    for k, v in pairs(original) do
      copy[k] = OGRH.CopyPasta.DeepCopyTable(v)
    end
  else
    copy = original
  end
  return copy
end

-- ============================================
-- BUTTON CREATION
-- ============================================

-- Create a copy button for raid list items
function OGRH.CopyPasta.CreateRaidCopyButton(parent, raidIdx, raidName)
  local copyBtn = CreateFrame("Button", nil, parent)
  copyBtn:SetWidth(12)
  copyBtn:SetHeight(12)
  copyBtn:SetNormalTexture("Interface\\AddOns\\OG-RaidHelper\\textures\\copy.tga")
  copyBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
  copyBtn:SetPushedTexture("Interface\\AddOns\\OG-RaidHelper\\textures\\copy.tga")
  
  -- Capture variables for closure
  local capturedRaidIdx = raidIdx
  local capturedRaidName = raidName
  
  copyBtn:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
    GameTooltip:SetText("Copy Raid")
    GameTooltip:AddLine("Duplicate this raid structure", 1, 1, 1, 1)
    GameTooltip:Show()
  end)
  
  copyBtn:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)
  
  copyBtn:SetScript("OnClick", function()
    OGRH.CopyPasta.ShowRaidCopyDialog(capturedRaidIdx, capturedRaidName)
  end)
  
  return copyBtn
end

-- Create a copy button for encounter list items
function OGRH.CopyPasta.CreateEncounterCopyButton(parent, raidIdx, encounterIdx, raidName, encounterName)
  local copyBtn = CreateFrame("Button", nil, parent)
  copyBtn:SetWidth(12)
  copyBtn:SetHeight(12)
  copyBtn:SetNormalTexture("Interface\\AddOns\\OG-RaidHelper\\textures\\copy.tga")
  copyBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
  copyBtn:SetPushedTexture("Interface\\AddOns\\OG-RaidHelper\\textures\\copy.tga")
  
  -- Capture variables for closure
  local capturedRaidIdx = raidIdx
  local capturedEncounterIdx = encounterIdx
  local capturedRaidName = raidName
  local capturedEncounterName = encounterName
  
  copyBtn:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
    GameTooltip:SetText("Copy Encounter")
    GameTooltip:AddLine("Duplicate this encounter structure", 1, 1, 1, 1)
    GameTooltip:Show()
  end)
  
  copyBtn:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)
  
  copyBtn:SetScript("OnClick", function()
    OGRH.CopyPasta.ShowEncounterCopyDialog(
      capturedRaidIdx,
      capturedEncounterIdx,
      capturedRaidName,
      capturedEncounterName
    )
  end)
  
  return copyBtn
end

-- Load message
OGRH.Msg("|cffff6666[RH-CopyPasta]|r Loaded")
