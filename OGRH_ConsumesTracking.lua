-- ============================================================================
-- OGRH_ConsumesTracking.lua
-- Consumes tracking module for OG-RaidHelper
-- Integrates with RABuffs to track consumables usage during raids
-- Compatible with Lua 5.0 and Turtle WoW (1.12)
-- ============================================================================

-- Create namespace
if not OGRH then OGRH = {} end
if not OGRH.ConsumesTracking then
  OGRH.ConsumesTracking = {}
end

local CT = OGRH.ConsumesTracking

-- ============================================================================
-- Saved Variables
-- ============================================================================

-- Initialize saved variables on first load
function CT.EnsureSavedVariables()
  if not OGRH_SV.consumesTracking then
    OGRH_SV.consumesTracking = {
      enabled = true,
      trackingProfiles = {},
      logToMemory = true,
      maxEntries = 200,
      pullTriggers = {
        "pull%s+(%d+)",
        "пулл%s+(%d+)",
        "тянем%s+(%d+)",
        "пул%s+(%d+)"
      },
      conflicts = {},
      mapping = {},
      weights = {}
    }
  end
  
  -- Ensure sub-tables exist
  if not OGRH_SV.consumesTracking.conflicts then
    OGRH_SV.consumesTracking.conflicts = {}
  end
  if not OGRH_SV.consumesTracking.mapping then
    OGRH_SV.consumesTracking.mapping = {}
  end
  if not OGRH_SV.consumesTracking.weights then
    OGRH_SV.consumesTracking.weights = {}
  end
  
  -- Set default weights for common buffs (only if not already set)
  local defaultWeights = {
    ["Flask of the Titans"] = 3,
    ["Flask of Supreme Power"] = 3,
    ["Flask of Distilled Wisdom"] = 3,
    ["Flask of Chromatic Resistance"] = 3
  }
  
  for buffKey, weight in pairs(defaultWeights) do
    if not OGRH_SV.consumesTracking.weights[buffKey] then
      OGRH_SV.consumesTracking.weights[buffKey] = weight
    end
  end
end

-- ============================================================================
-- UI - Track Consumes Window
-- ============================================================================

local trackConsumesFrame = nil

-- Show the Track Consumes window
function OGRH.ShowTrackConsumes()
  if trackConsumesFrame and trackConsumesFrame:IsShown() then
    trackConsumesFrame:Hide()
    return
  end
  
  CT.EnsureSavedVariables()
  
  -- Create window if it doesn't exist
  if not trackConsumesFrame then
    trackConsumesFrame = OGST.CreateStandardWindow({
      name = "OGRH_TrackConsumesFrame",
      width = 600,
      height = 450,
      title = "Track Consumes",
      closeButton = true,
      escapeCloses = true,
      closeOnNewWindow = true
    })
    
    local contentFrame = trackConsumesFrame.contentFrame
    
    --[[
    TODO: Re-enable these features one by one:
    1. Right detail panel (CreateContentPanel)
    2. Detail panel title
    3. Default message in detail panel
    4. Action list items (Enable Tracking, Preview Tracking, Mapping, Conflicts)
    5. CT.UpdateDetailPanel() function with all action panels
    6. CT.PollConsumes() function
    7. RABuffs integration functions
    ]]--
    
    -- Create left list panel using OGST styled scroll list
    local actionsList, scrollFrame, scrollChild, scrollBar, contentWidth = OGST.CreateStyledScrollList(contentFrame, 175, 400, true)
    OGST.AnchorElement(actionsList, contentFrame, {position = "top", align = "left", fillHeight = true})
    
    trackConsumesFrame.scrollChild = scrollChild
    trackConsumesFrame.scrollFrame = scrollFrame
    trackConsumesFrame.scrollBar = scrollBar
    trackConsumesFrame.actionsList = actionsList
    
    -- Right detail panel
    local detailPanel = OGST.CreateContentPanel(contentFrame, {
      width = 0,  -- Let anchor system handle width
      height = 0  -- Let anchor system handle height
    })
    OGST.AnchorElement(detailPanel, actionsList, {position = "fillRight"})
    trackConsumesFrame.detailPanel = detailPanel
    trackConsumesFrame.detailContent = {}
    
    -- Default message
    local defaultMessage = OGST.CreateStaticText(detailPanel, {
      text = "Select an action from the list to see details.",
      font = "GameFontNormal",
      color = {r = 0.8, g = 0.8, b = 0.8}
    })
    OGST.AnchorElement(defaultMessage, detailPanel, {position = "center"})
    trackConsumesFrame.defaultMessage = defaultMessage
    
    -- Populate action list
    CT.RefreshActionList()
    
    -- Register frame for window management
    OGST.WindowRegistry["OGRH_TrackConsumesFrame"] = trackConsumesFrame
  end
  
  trackConsumesFrame:Show()
end

-- Hide the Track Consumes window
function OGRH.HideTrackConsumes()
  if trackConsumesFrame then
    trackConsumesFrame:Hide()
  end
end

-- ============================================================================
-- UI - Action List Management
-- ============================================================================

-- Refresh the action list
function CT.RefreshActionList()
  if not trackConsumesFrame then return end
  
  local actionsList = trackConsumesFrame.actionsList
  
  -- Clear existing items using the list's Clear method
  actionsList:Clear()
  
  -- Define action items
  local actions = {
    {name = "Enable Tracking"},
    {name = "Preview Tracking"},
    {name = "Weights"},
    {name = "Mapping"},
    {name = "Conflicts"}
  }
  
  for i, action in ipairs(actions) do
    local actionName = action.name  -- Capture in local scope for closure
    actionsList:AddItem({
      text = actionName,
      onClick = function()
        CT.UpdateDetailPanel(actionName)
      end
    })
  end
end

-- Update the detail panel based on selected action
function CT.UpdateDetailPanel(actionName)
  if not trackConsumesFrame then return end
  
  local detailPanel = trackConsumesFrame.detailPanel
  if not detailPanel then return end
  
  -- Clear existing content properly
  if trackConsumesFrame.detailContent and type(trackConsumesFrame.detailContent) == "table" then
    for i = 1, table.getn(trackConsumesFrame.detailContent) do
      local element = trackConsumesFrame.detailContent[i]
      if element then
        pcall(function() 
          element:Hide()
          element:SetParent(nil)
        end)
      end
    end
  end
  trackConsumesFrame.detailContent = {}
  
  -- Hide default message if it exists
  if trackConsumesFrame.defaultMessage then
    trackConsumesFrame.defaultMessage:Hide()
  end
  
  if actionName == "Enable Tracking" then
    -- Enable/Disable checkbox using OGST
    local enableCheckbox, checkButton, checkLabel = OGST.CreateCheckbox(detailPanel, {
      label = "Enable Tracking",
      checked = OGRH_SV.consumesTracking.enabled,
      onChange = function(isChecked)
        OGRH_SV.consumesTracking.enabled = isChecked
      end
    })
    OGST.AnchorElement(enableCheckbox, detailPanel, {position = "top", align = "left", offsetX = 10, offsetY = -10})
    
    -- Description
    local desc = OGST.CreateStaticText(detailPanel, {
      text = "When enabled, this module will track consumables by integrating with RABuffs to monitor raid members' buffs during pulls.\n\nFeatures will be added progressively.",
      font = "GameFontNormalSmall",
      color = {r = 0.8, g = 0.8, b = 0.8},
      multiline = true
    })
    OGST.AnchorElement(desc, enableCheckbox, {position = "below", align = "left"})
    
    table.insert(trackConsumesFrame.detailContent, enableCheckbox)
    table.insert(trackConsumesFrame.detailContent, desc)
    
  elseif actionName == "Preview Tracking" then
    -- Poll Consumes button using OGST
    local pollBtn = OGST.CreateButton(detailPanel, {
      width = 120,
      height = 24,
      text = "Poll Consumes"
    })
    OGST.AnchorElement(pollBtn, detailPanel, {position = "top", align = "left", offsetY = -10, offsetX = 10})
    
    -- Announce Consumes button
    local announceBtn = OGST.CreateButton(detailPanel, {
      width = 140,
      height = 24,
      text = "Announce Consumes"
    })
    OGST.AnchorElement(announceBtn, pollBtn, {position = "right", align = "center", offsetX = 5})
    
    -- Create scrolling text box using OGST with dynamic sizing
    local textBoxBackdrop, textBoxEditBox, textBoxScrollFrame, textBoxScrollBar = OGST.CreateScrollingTextBox(
      detailPanel,
      0,  -- 0 = dynamic width
      0   -- 0 = dynamic height
    )
    -- Fill below button to bottom of panel (button is centered so use fillBelowFromParent)
    local buttonHeight = pollBtn:GetHeight()
    OGST.AnchorElement(textBoxBackdrop, detailPanel, {position = "fillBelowFromParent", offsetY = -(10 + buttonHeight + 5), padding = 10})
    
    -- Set initial text
    textBoxEditBox:SetText("|cff808080Click 'Poll Consumes' to preview current consumables status.|r")
    
    -- Store references on the button frames
    pollBtn.editBox = textBoxEditBox
    pollBtn.scrollBar = textBoxScrollBar
    pollBtn.scrollFrame = textBoxScrollFrame
    
    announceBtn.editBox = textBoxEditBox
    announceBtn.scrollBar = textBoxScrollBar
    announceBtn.scrollFrame = textBoxScrollFrame
    
    -- Button click handlers
    pollBtn:SetScript("OnClick", function()
      CT.PollConsumes(this.editBox, this.scrollBar, this.scrollFrame)
    end)
    
    announceBtn:SetScript("OnClick", function()
      CT.AnnounceConsumes()
    end)
    
    table.insert(trackConsumesFrame.detailContent, pollBtn)
    table.insert(trackConsumesFrame.detailContent, announceBtn)
    table.insert(trackConsumesFrame.detailContent, textBoxBackdrop)
    
  elseif actionName == "Weights" then
    -- Weights configuration panel
    local desc = OGST.CreateStaticText(detailPanel, {
      text = "Configure the point value for each consumable. Higher weights increase their impact on the score.",
      font = "GameFontNormalSmall",
      color = {r = 0.8, g = 0.8, b = 0.8},
      multiline = true,
      width = detailPanel:GetWidth() - 20
    })
    OGST.AnchorElement(desc, detailPanel, {position = "top", align = "left", offsetX = 10, offsetY = -10})
    
    -- Get list of buffs from RABuffs profile
    local profileKey = GetCVar("realmName") .. "." .. UnitName("player") .. ".OGRH_Consumables"
    
    if not RABui_Settings or not RABui_Settings.Layout or not RABui_Settings.Layout[profileKey] then
      local errorText = OGST.CreateStaticText(detailPanel, {
        text = "RABuffs profile 'OGRH_Consumables' not found. Please enable tracking first.",
        font = "GameFontNormalSmall",
        color = {r = 1, g = 0.3, b = 0.3}
      })
      OGST.AnchorElement(errorText, desc, {position = "below", align = "left", offsetY = -20})
      table.insert(trackConsumesFrame.detailContent, desc)
      table.insert(trackConsumesFrame.detailContent, errorText)
      return
    end
    
    local profileBars = RABui_Settings.Layout[profileKey]
    
    -- Create list of consumables (use same logic as Mapping)
    local consumables = {}
    for i, bar in ipairs(profileBars) do
      if bar.buffKey and RAB_Buffs[bar.buffKey] then
        local buffData = RAB_Buffs[bar.buffKey]
        local buffKey = bar.buffKey
        local weight = OGRH_SV.consumesTracking.weights[buffKey] or 1
        table.insert(consumables, {
          buffKey = buffKey,
          buffName = buffData.name or buffKey,
          texture = buffData.icon,
          label = bar.label or "",
          weight = weight,
          profileIndex = i
        })
      end
    end
    
    -- Sort by buff name
    table.sort(consumables, function(a, b)
      return a.buffName < b.buffName
    end)
    
    -- Create scrolling list for weights
    local listWidth = 380
    local listHeight = 355
    local weightsList = OGST.CreateStyledScrollList(detailPanel, listWidth, listHeight)
    OGST.AnchorElement(weightsList, desc, {position = "below", padding = 10})
    
    -- Add each consumable as a list item
    for i, consumable in ipairs(consumables) do
      local item = weightsList:AddItem({
        text = string.format("[%d] %s", consumable.profileIndex, consumable.buffName)
      })
      
      -- Plus button (rightmost)
      local plusBtn = OGST.CreateButton(item, {
        width = 18,
        height = 18,
        text = "+",
        onClick = function()
          local newWeight = item.currentWeight + 1
          if newWeight > 10 then newWeight = 10 end  -- Max 10
          item.currentWeight = newWeight
          item.weightText:SetText(tostring(newWeight))
          OGRH_SV.consumesTracking.weights[item.buffKey] = newWeight
        end
      })
      plusBtn:SetPoint("RIGHT", item, "RIGHT", -5, 0)
      
      -- Minus button (left of plus)
      local minusBtn = OGST.CreateButton(item, {
        width = 18,
        height = 18,
        text = "-",
        onClick = function()
          local newWeight = item.currentWeight - 1
          if newWeight < 0 then newWeight = 0 end  -- Min 0
          item.currentWeight = newWeight
          item.weightText:SetText(tostring(newWeight))
          OGRH_SV.consumesTracking.weights[item.buffKey] = newWeight
        end
      })
      minusBtn:SetPoint("RIGHT", plusBtn, "LEFT", -5, 0)
      
      -- Weight value display (left of minus button)
      local weightText = item:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      weightText:SetPoint("RIGHT", minusBtn, "LEFT", -10, 0)
      weightText:SetText(tostring(consumable.weight))
      weightText:SetTextColor(1, 1, 0.5)
      
      -- Store references
      item.buffKey = consumable.buffKey
      item.weightText = weightText
      item.currentWeight = consumable.weight
    end
    
    table.insert(trackConsumesFrame.detailContent, desc)
    table.insert(trackConsumesFrame.detailContent, weightsList)
    
  elseif actionName == "Mapping" then
    local desc = OGST.CreateStaticText(detailPanel, {
      text = "Configure which roles each consumable applies to.",
      font = "GameFontNormalSmall",
      color = {r = 0.8, g = 0.8, b = 0.8}
    })
    OGST.AnchorElement(desc, detailPanel, {position = "top", offsetX = 10, offsetY = -10})
    
    -- Get consumables from OGRH_Consumables profile
    local profileKey = GetCVar("realmName") .. "." .. UnitName("player") .. ".OGRH_Consumables"
    local profileBars = RABui_Settings and RABui_Settings.Layout and RABui_Settings.Layout[profileKey]
    
    if not profileBars or table.getn(profileBars) == 0 then
      local warning = OGST.CreateStaticText(detailPanel, {
        text = "No consumables found in OGRH_Consumables profile.\\n\\nPlease reload the UI to create the profile.",
        font = "GameFontNormal",
        color = {r = 1, g = 0.5, b = 0},
        multiline = true
      })
      OGST.AnchorElement(warning, desc, {position = "below", align = "left"})
      table.insert(trackConsumesFrame.detailContent, desc)
      table.insert(trackConsumesFrame.detailContent, warning)
      return
    end
    
    -- Create list of consumables sorted alphabetically by buff name
    local consumables = {}
    for i, bar in ipairs(profileBars) do
      if bar.buffKey and RAB_Buffs[bar.buffKey] then
        table.insert(consumables, {
          buffKey = bar.buffKey,
          buffName = RAB_Buffs[bar.buffKey].name or bar.buffKey,
          label = bar.label,
          index = i  -- Store the profile index
        })
      end
    end
    
    -- Sort alphabetically by buff name
    table.sort(consumables, function(a, b)
      return a.buffName < b.buffName
    end)
    
    -- Create scrollable list for consumables
    -- Width: 600 window - 175 left panel - borders/padding = ~380
    -- Height: Fill remaining space
    local listWidth = 380
    local listHeight = 355
    local mappingList = OGST.CreateStyledScrollList(detailPanel, listWidth, listHeight)
    OGST.AnchorElement(mappingList, desc, {position = "below", padding = 10})
    
    -- Initialize role mapping storage
    if not OGRH_SV.consumesTracking then
      OGRH_SV.consumesTracking = {}
    end
    if not OGRH_SV.consumesTracking.roleMapping then
      OGRH_SV.consumesTracking.roleMapping = {}
    end
    
    -- Add each consumable as a list item
    for i, consumable in ipairs(consumables) do
      -- Create unique mapping key using buffKey and profile index
      local mappingKey = consumable.buffKey .. "_" .. consumable.index
      
      -- Initialize role mapping for this consumable if not exists
      if not OGRH_SV.consumesTracking.roleMapping[mappingKey] then
        -- Get the label from RABuffs profile and parse it to determine initial checked state
        local profileKey = GetCVar("realmName") .. "." .. UnitName("player") .. ".OGRH_Consumables"
        local profileBars = RABui_Settings.Layout[profileKey]
        
        local initialMapping = {tanks = false, healers = false, melee = false, ranged = false}
        
        if profileBars then
          -- Find the bar at this specific index
          local bar = profileBars[consumable.index]
          if bar and bar.buffKey == consumable.buffKey and bar.label then
            initialMapping = CT.ParseLabelToRoles(bar.label)
          end
        end
        
        OGRH_SV.consumesTracking.roleMapping[mappingKey] = initialMapping
      end
      
      -- Create item with index appended to name
      local item = mappingList:AddItem({
        text = string.format("[%d] %s", consumable.index, consumable.buffName)
      })
      
      -- Add role checkboxes with icons
      local roles = {"tanks", "healers", "melee", "ranged"}
      local roleIcons = {
        tanks = "Interface\\Icons\\Ability_Defend",
        healers = "Interface\\Icons\\Spell_Holy_FlashHeal",
        melee = "Interface\\Icons\\INV_Sword_27",
        ranged = "Interface\\Icons\\Spell_Fire_FireBolt"
      }
      local roleLabels = {
        tanks = "T",
        healers = "H",
        melee = "M",
        ranged = "R"
      }
      
      local spacing = 5   -- Space between each role pair
      local iconSize = 16
      local checkboxSize = 16
      local rightMargin = 10  -- Margin from right edge
      
      local lastAnchor = item  -- Start anchoring from the item itself
      local lastAnchorPoint = "RIGHT"
      local lastOffset = -rightMargin
      
      -- Reverse the roles array to work right to left
      for i = table.getn(roles), 1, -1 do
        local role = roles[i]
        
        -- Create role icon first (rightmost element of the pair)
        local roleIcon = item:CreateTexture(nil, "OVERLAY")
        roleIcon:SetWidth(iconSize)
        roleIcon:SetHeight(iconSize)
        roleIcon:SetPoint("RIGHT", lastAnchor, lastAnchorPoint, lastOffset, 0)
        roleIcon:SetTexture(roleIcons[role])
        roleIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        
        -- Create checkbox to the left of the icon
        local checkbox = CreateFrame("CheckButton", nil, item)
        checkbox:SetWidth(checkboxSize)
        checkbox:SetHeight(checkboxSize)
        checkbox:SetPoint("RIGHT", roleIcon, "LEFT", -2, 0)
        checkbox:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
        checkbox:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
        checkbox:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight")
        checkbox:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
        
        -- Set initial checked state
        checkbox:SetChecked(OGRH_SV.consumesTracking.roleMapping[mappingKey][role])
        
        -- Store reference for closure
        checkbox.buffKey = consumable.buffKey
        checkbox.profileIndex = consumable.index
        checkbox.mappingKey = mappingKey
        checkbox.role = role
        
        -- Click handler
        checkbox:SetScript("OnClick", function()
          OGRH_SV.consumesTracking.roleMapping[this.mappingKey][this.role] = this:GetChecked()
          
          -- Update RABuffs label based on new role mapping
          local roleMapping = OGRH_SV.consumesTracking.roleMapping[this.mappingKey]
          local newLabel = CT.GenerateLabelFromRoles(roleMapping)
          CT.UpdateRABuffsLabel(this.buffKey, newLabel, this.profileIndex)
        end)
        
        -- Update anchor for next pair
        lastAnchor = checkbox
        lastAnchorPoint = "LEFT"
        lastOffset = -spacing
      end
    end
    
    table.insert(trackConsumesFrame.detailContent, desc)
    table.insert(trackConsumesFrame.detailContent, mappingList)

  elseif actionName == "Conflicts" then
    -- Description
    local desc = OGST.CreateStaticText(detailPanel, {
      text = "Configure buff conflicts and exclusions.",
      font = "GameFontNormal",
      color = {r = 0.8, g = 0.8, b = 0.8},
      multiline = false,
      width = 380
    })
    OGST.AnchorElement(desc, detailPanel, {position = "top", align = "left", offsetX = 10, offsetY = -10})
    
    -- Initialize conflict storage
    if not OGRH_SV.consumesTracking.conflicts then
      OGRH_SV.consumesTracking.conflicts = {}
    end
    
    -- Migration: Add profileIndex to old conflicts that don't have it
    local profileKey = GetCVar("realmName") .. "." .. UnitName("player") .. ".OGRH_Consumables"
    local profileBars = RABui_Settings and RABui_Settings.Layout and RABui_Settings.Layout[profileKey]
    if profileBars then
      for i = 1, table.getn(OGRH_SV.consumesTracking.conflicts) do
        local conflict = OGRH_SV.consumesTracking.conflicts[i]
        if conflict and conflict.buffKey and not conflict.profileIndex then
          -- Find the first occurrence of this buffKey in the profile
          for j, bar in ipairs(profileBars) do
            if bar.buffKey == conflict.buffKey then
              conflict.profileIndex = j
              break
            end
          end
        end
      end
    end
    
    -- Top half: Conflict list (half height of detail panel)
    local listHeight = 165  -- Approximately half of 355 remaining height
    local conflictList = OGST.CreateStyledScrollList(detailPanel, 380, listHeight)
    OGST.AnchorElement(conflictList, desc, {position = "below", padding = 10})
    
    -- Store currently selected conflict index
    local selectedConflictIndex = nil
    
    -- Store checkbox references for radio button behavior
    local typeCheckboxes = {}
    local groupNumberBox  -- Forward declaration
    
    -- Function to update controls panel based on selected conflict
    local function UpdateControlsForConflict(conflictIndex)
      if not conflictIndex or conflictIndex < 1 or conflictIndex > table.getn(OGRH_SV.consumesTracking.conflicts) then
        -- No valid conflict selected, clear all controls
        for name, checkbox in pairs(typeCheckboxes) do
          checkbox:SetChecked(false)
        end
        if groupNumberBox then
          groupNumberBox:SetText("")
          groupNumberBox:EnableKeyboard(false)
          groupNumberBox:EnableMouse(false)
          groupNumberBox:SetTextColor(0.5, 0.5, 0.5, 1)
        end
        return
      end
      
      local conflict = OGRH_SV.consumesTracking.conflicts[conflictIndex]
      if not conflict then return end
      
      -- Initialize conflictType if not present
      if not conflict.conflictType then
        conflict.conflictType = "Concoction"
      end
      
      -- Update checkboxes based on conflict type
      for name, checkbox in pairs(typeCheckboxes) do
        checkbox:SetChecked(name == conflict.conflictType)
      end
      
      -- Update group number box
      if groupNumberBox then
        if conflict.conflictType == "Group" and conflict.groupNumber then
          groupNumberBox:SetText(tostring(conflict.groupNumber))
          groupNumberBox:EnableKeyboard(true)
          groupNumberBox:EnableMouse(true)
          groupNumberBox:SetTextColor(1, 1, 1, 1)
        else
          groupNumberBox:SetText("")
          if conflict.conflictType == "Group" then
            groupNumberBox:EnableKeyboard(true)
            groupNumberBox:EnableMouse(true)
            groupNumberBox:SetTextColor(1, 1, 1, 1)
          else
            groupNumberBox:EnableKeyboard(false)
            groupNumberBox:EnableMouse(false)
            groupNumberBox:SetTextColor(0.5, 0.5, 0.5, 1)
          end
        end
      end
    end
    
    -- Function to refresh conflict list
    local function RefreshConflictList()
      conflictList:Clear()
      
      -- Build sortable list with buff names
      local conflicts = OGRH_SV.consumesTracking.conflicts
      local sortedConflicts = {}
      for i = 1, table.getn(conflicts) do
        local conflict = conflicts[i]
        local buffName = "Unknown"
        
        if RAB_Buffs and RAB_Buffs[conflict.buffKey] then
          buffName = RAB_Buffs[conflict.buffKey].name or conflict.buffKey
        end
        
        table.insert(sortedConflicts, {
          originalIndex = i,
          buffName = buffName,
          conflict = conflict
        })
      end
      
      -- Sort alphabetically by buff name
      table.sort(sortedConflicts, function(a, b)
        return a.buffName < b.buffName
      end)
      
      -- Add sorted conflicts with delete buttons
      for _, item in ipairs(sortedConflicts) do
        local conflict = item.conflict
        local buffName = item.buffName
        local originalIndex = item.originalIndex
        local buffIndex = conflict.profileIndex  -- Use stored profile index
        
        local conflictText = buffIndex and string.format("[%d] %s", buffIndex, buffName) or buffName
        if conflict.conflictsWith and table.getn(conflict.conflictsWith) > 0 then
          conflictText = conflictText .. " (conflicts: " .. table.getn(conflict.conflictsWith) .. ")"
        end
        
        local capturedIndex = originalIndex  -- Capture for closure
        conflictList:AddItem({
          text = conflictText,
          onClick = function()
            selectedConflictIndex = capturedIndex
            UpdateControlsForConflict(capturedIndex)
          end,
          onDelete = function()
            table.remove(OGRH_SV.consumesTracking.conflicts, capturedIndex)
            selectedConflictIndex = nil
            RefreshConflictList()
            UpdateControlsForConflict(nil)
          end
        })
      end
      
      -- Add "Add Conflict" button as last item
      local addConflictItem = conflictList:AddItem({
        text = "Add Conflict",
        textAlign = "CENTER",
        textColor = {r = 0, g = 1, b = 0, a = 1},
        onClick = function()
          CT.ShowAddConflictDialog()
        end
      })
    end
    
    RefreshConflictList()
    
    -- Bottom half: Controls panel
    local controlsPanel = OGST.CreateContentPanel(detailPanel, {
      width = 380,
      height = 160  -- Remaining space
    })
    OGST.AnchorElement(controlsPanel, conflictList, {position = "below", padding = 10})
    
    -- Function to handle radio button behavior
    local function OnTypeCheckboxClick(checkboxName)
      -- Save to selected conflict
      if selectedConflictIndex and OGRH_SV.consumesTracking.conflicts[selectedConflictIndex] then
        OGRH_SV.consumesTracking.conflicts[selectedConflictIndex].conflictType = checkboxName
      end
      
      for name, checkbox in pairs(typeCheckboxes) do
        if name ~= checkboxName then
          checkbox:SetChecked(false)
        end
      end
      
      -- Enable/disable group number input based on Group checkbox
      if groupNumberBox then
        if checkboxName == "Group" and typeCheckboxes.Group:GetChecked() then
          groupNumberBox:EnableKeyboard(true)
          groupNumberBox:EnableMouse(true)
          groupNumberBox:SetTextColor(1, 1, 1, 1)
        else
          groupNumberBox:EnableKeyboard(false)
          groupNumberBox:EnableMouse(false)
          groupNumberBox:SetTextColor(0.5, 0.5, 0.5, 1)
        end
      end
    end
    
    -- Concoction checkbox
    local concoctionContainer, concoctionCheckbox = OGST.CreateCheckbox(controlsPanel, {
      label = "Concoction",
      checked = false,
      onChange = function(checked)
        if checked then
          OnTypeCheckboxClick("Concoction")
        end
      end
    })
    OGST.AnchorElement(concoctionContainer, controlsPanel, {position = "top", align = "left", offsetX = 10, offsetY = -10})
    typeCheckboxes.Concoction = concoctionCheckbox
    
    -- Blasted Lands checkbox
    local blastedLandsContainer, blastedLandsCheckbox = OGST.CreateCheckbox(controlsPanel, {
      label = "Blasted Lands",
      checked = false,
      onChange = function(checked)
        if checked then
          OnTypeCheckboxClick("BlastedLands")
        end
      end
    })
    OGST.AnchorElement(blastedLandsContainer, concoctionContainer, {position = "below", padding = 5})
    typeCheckboxes.BlastedLands = blastedLandsCheckbox
    
    -- Food checkbox
    local foodContainer, foodCheckbox = OGST.CreateCheckbox(controlsPanel, {
      label = "Food",
      checked = false,
      onChange = function(checked)
        if checked then
          OnTypeCheckboxClick("Food")
        end
      end
    })
    OGST.AnchorElement(foodContainer, blastedLandsContainer, {position = "below", padding = 5})
    typeCheckboxes.Food = foodCheckbox
    
    -- Drink checkbox
    local drinkContainer, drinkCheckbox = OGST.CreateCheckbox(controlsPanel, {
      label = "Drink",
      checked = false,
      onChange = function(checked)
        if checked then
          OnTypeCheckboxClick("Drink")
        end
      end
    })
    OGST.AnchorElement(drinkContainer, foodContainer, {position = "below", padding = 5})
    typeCheckboxes.Drink = drinkCheckbox
    
    -- Group checkbox
    local groupContainer, groupCheckbox = OGST.CreateCheckbox(controlsPanel, {
      label = "Group",
      checked = false,
      onChange = function(checked)
        if checked then
          OnTypeCheckboxClick("Group")
        end
      end
    })
    OGST.AnchorElement(groupContainer, drinkContainer, {position = "below", padding = 5})
    typeCheckboxes.Group = groupCheckbox
    
    -- Group number text box (to the right of Group checkbox)
    local groupNumberContainer, groupNumberBackdrop
    groupNumberContainer, groupNumberBackdrop, groupNumberBox = OGST.CreateSingleLineTextBox(controlsPanel, 60, 24, {
      maxLetters = 2,
      numeric = true,
      align = "CENTER",
      onChange = function(text)
        -- Save group number to selected conflict
        if selectedConflictIndex and OGRH_SV.consumesTracking.conflicts[selectedConflictIndex] then
          local num = tonumber(text)
          if num then
            OGRH_SV.consumesTracking.conflicts[selectedConflictIndex].groupNumber = num
          end
        end
      end
    })
    OGST.AnchorElement(groupNumberContainer, groupContainer, {position = "right", align = "center", offsetX = 10, offsetY = 0})
    
    -- Initially disable the group number box
    groupNumberBox:EnableKeyboard(false)
    groupNumberBox:EnableMouse(false)
    groupNumberBox:SetTextColor(0.5, 0.5, 0.5, 1)
    
    table.insert(trackConsumesFrame.detailContent, desc)
    table.insert(trackConsumesFrame.detailContent, conflictList)
    table.insert(trackConsumesFrame.detailContent, controlsPanel)
    table.insert(trackConsumesFrame.detailContent, concoctionContainer)
    table.insert(trackConsumesFrame.detailContent, foodContainer)
    table.insert(trackConsumesFrame.detailContent, drinkContainer)
    table.insert(trackConsumesFrame.detailContent, groupContainer)
    table.insert(trackConsumesFrame.detailContent, groupNumberContainer)

  end -- Close if/elseif chain
end -- Close UpdateDetailPanel function

-- ============================================================================
-- Add Conflict Dialog
-- ============================================================================

-- Show dialog to select a buff for conflict configuration
function CT.ShowAddConflictDialog()
  -- Get list of available consumables from RABuffs profile
  local profileKey = GetCVar("realmName") .. "." .. UnitName("player") .. ".OGRH_Consumables"
  if not RABui_Settings or not RABui_Settings.Layout or not RABui_Settings.Layout[profileKey] then
    OGRH.Msg("RABuffs profile 'OGRH_Consumables' not found. Please enable tracking first.")
    return
  end
  
  local profileBars = RABui_Settings.Layout[profileKey]
  
  -- Create list of consumables sorted alphabetically
  local consumables = {}
  for i, bar in ipairs(profileBars) do
    if bar.buffKey and RAB_Buffs[bar.buffKey] then
      table.insert(consumables, {
        buffKey = bar.buffKey,
        buffName = RAB_Buffs[bar.buffKey].name or bar.buffKey,
        index = i
      })
    end
  end
  
  -- Sort alphabetically
  table.sort(consumables, function(a, b)
    return a.buffName < b.buffName
  end)
  
  -- Create dialog
  local dialogTable = OGST.CreateDialog({
    title = "Add Conflict",
    width = 400,
    height = 450,
    escapeCloses = true
  })
  
  -- Get content frame from dialog
  local contentFrame = dialogTable.contentFrame
  local backdrop = dialogTable.backdrop
  
  -- Description
  local desc = OGST.CreateStaticText(contentFrame, {
    text = "Select a buff to configure conflicts for:",
    font = "GameFontNormal",
    color = {r = 0.8, g = 0.8, b = 0.8},
    multiline = false,
    width = 360
  })
  OGST.AnchorElement(desc, contentFrame, {position = "top", align = "left", offsetX = 10, offsetY = -10})
  
  -- Scrollable list of consumables
  local buffList = OGST.CreateStyledScrollList(contentFrame, 360, 310)
  OGST.AnchorElement(buffList, desc, {position = "below", padding = 10})
  
  -- Add consumables to list
  for i = 1, table.getn(consumables) do
    local consumable = consumables[i]
    local capturedBuffKey = consumable.buffKey  -- Capture for closure
    local capturedBuffName = consumable.buffName
    local capturedIndex = consumable.index
    
    buffList:AddItem({
      text = string.format("[%d] %s", capturedIndex, capturedBuffName),
      onClick = function()
        -- Create new conflict entry
        if not OGRH_SV.consumesTracking.conflicts then
          OGRH_SV.consumesTracking.conflicts = {}
        end
        
        -- Check if conflict already exists for this buff at this index
        local exists = false
        for j = 1, table.getn(OGRH_SV.consumesTracking.conflicts) do
          local conflict = OGRH_SV.consumesTracking.conflicts[j]
          if conflict.buffKey == capturedBuffKey and conflict.profileIndex == capturedIndex then
            exists = true
            break
          end
        end
        
        if not exists then
          table.insert(OGRH_SV.consumesTracking.conflicts, {
            buffKey = capturedBuffKey,
            profileIndex = capturedIndex,
            conflictsWith = {}
          })
          
          -- Refresh the Conflicts panel if it's visible
          if trackConsumesFrame and trackConsumesFrame:IsVisible() then
            CT.UpdateDetailPanel("Conflicts")
          end
        end
        
        -- Close dialog
        backdrop:Hide()
      end
    })
  end
  
  -- Show the dialog
  backdrop:Show()
end

-- ============================================================================
-- Consumables Polling (Preview)
-- ============================================================================
-- SCORING SYSTEM
-- ============================================================================

-- Helper: Get role letter from role name (TANKS->T, HEALERS->H, etc)
local function GetRoleLetter(roleName)
  if not roleName then return nil end
  if roleName == "TANKS" then return "T"
  elseif roleName == "HEALERS" then return "H"
  elseif roleName == "MELEE" then return "M"
  elseif roleName == "RANGED" then return "R"
  end
  return nil
end

-- Helper: Check if buff label includes a role letter
local function BuffAppliesToRole(buffLabel, roleLetter)
  if not buffLabel or not roleLetter then return false end
  return string.find(buffLabel, roleLetter) ~= nil
end

-- Helper: Get conflict data for a buff at a specific profile index
local function GetBuffConflict(buffKey, profileIndex)
  if not OGRH_SV or not OGRH_SV.consumesTracking or not OGRH_SV.consumesTracking.conflicts then
    return nil
  end
  
  for _, conflict in ipairs(OGRH_SV.consumesTracking.conflicts) do
    if conflict.buffKey == buffKey then
      -- If profileIndex is provided, check it; otherwise match any
      if profileIndex and conflict.profileIndex then
        if conflict.profileIndex == profileIndex then
          return conflict
        end
      else
        -- Legacy support: if no profileIndex stored, match by buffKey only
        return conflict
      end
    end
  end
  return nil
end

-- Helper: Check if player has any buff from a conflict group
local function HasAnyBuffFromConflict(playerBuffs, conflictBuffKeys)
  for _, buffKey in ipairs(conflictBuffKeys) do
    if playerBuffs[buffKey] then
      return true
    end
  end
  return false
end

-- Calculate score for a single player
function CT.CalculatePlayerScore(playerName, playerClass, raidData)
  -- Get player's role from RolesUI
  local playerRole = OGRH_SV and OGRH_SV.roles and OGRH_SV.roles[playerName]
  if not playerRole then
    return nil, "No role assigned"
  end
  
  local roleLetter = GetRoleLetter(playerRole)
  if not roleLetter then
    return nil, "Invalid role"
  end
  
  -- Get player's buffs
  local playerBuffs = {} -- {buffKey = true}
  if raidData and raidData[playerName] then
    playerBuffs = raidData[playerName].buffs or {}
  end
  
  -- Load profile bars
  local profileKey = GetCVar("realmName") .. "." .. UnitName("player") .. ".OGRH_Consumables"
  local profileBars = RABui_Settings and RABui_Settings.Layout and RABui_Settings.Layout[profileKey]
  if not profileBars then
    return nil, "Profile not found"
  end
  
  -- Build list of required buffs for this player's role
  local requiredBuffs = {} -- {buffKey = {bar, profileIndex}}
  for profileIndex, bar in ipairs(profileBars) do
    if bar.buffKey and RAB_Buffs[bar.buffKey] then
      -- Check if buff applies to player's role
      if BuffAppliesToRole(bar.label, roleLetter) then
        -- Check class restrictions
        local includeForClass = true
        if bar.classes and bar.classes ~= "" and RAB_ClassShort and RAB_ClassShort[playerClass] then
          local classCode = RAB_ClassShort[playerClass]
          includeForClass = string.find(bar.classes, classCode) ~= nil
        end
        
        if includeForClass then
          -- Store as array to handle multiple entries with same buffKey
          if not requiredBuffs[bar.buffKey] then
            requiredBuffs[bar.buffKey] = {}
          end
          table.insert(requiredBuffs[bar.buffKey], {bar = bar, profileIndex = profileIndex})
        end
      end
    end
  end
  
  -- Group buffs by conflict type
  -- Simpler approach: All buffs with same conflict type are grouped together
  local conflictGroups = {} -- {conflictId = {buffKeys, hasAny}}
  local processedBuffs = {} -- Track which buffs we've handled (buffKey_profileIndex)
  
  for buffKey, entries in pairs(requiredBuffs) do
    for _, entry in ipairs(entries) do
      local profileIndex = entry.profileIndex
      local processKey = buffKey .. "_" .. profileIndex
      
      if not processedBuffs[processKey] then
        local conflict = GetBuffConflict(buffKey, profileIndex)
        
        if conflict and conflict.conflictType then
          local conflictId = conflict.conflictType
          
          -- For Group conflicts, include the group number in the ID
          if conflict.conflictType == "Group" and conflict.groupNumber then
            conflictId = "Group_" .. conflict.groupNumber
          end
          
          -- Skip concoctions from conflict grouping - they're handled specially
          local isConcoction = (buffKey == "emeraldmongoose" or buffKey == "dreamwater" or buffKey == "arcanegiants")
          if not isConcoction then
            if not conflictGroups[conflictId] then
              conflictGroups[conflictId] = {buffKeys = {}, hasAny = false}
            end
            
            table.insert(conflictGroups[conflictId].buffKeys, buffKey)
            
            if playerBuffs[buffKey] then
              conflictGroups[conflictId].hasAny = true
            end
            
            processedBuffs[processKey] = true
          else
            -- Mark concoctions as processed so they don't get counted in standalone loop
            processedBuffs[processKey] = true
          end
        end
      end
    end
  end
  
  -- Calculate score
  -- Special handling for concoctions:
  -- - Concoctions themselves don't count as possible buffs
  -- - When checking if a player has a required buff, also check if they have a concoction that replaces it
  local concoctionReplacements = {
    emeraldmongoose = {"mongoose", "dreamshard"},     -- Emerald Mongoose replaces Mongoose + Dreamshard
    dreamwater = {"firewater", "dreamtonic"},         -- Dreamwater replaces Firewater + Dreamtonic
    arcanegiants = {"giants", "greaterarcane"}        -- Arcane Giant replaces Giants + Greater Arcane
  }
  
  -- Helper function: Check if player has a buff OR a concoction that replaces it
  local function PlayerHasBuff(buffKey)
    -- Direct buff check
    if playerBuffs[buffKey] then
      return true
    end
    
    -- Check if any concoction replaces this buff
    for concKey, replacedBuffs in pairs(concoctionReplacements) do
      if playerBuffs[concKey] then
        for _, replacedKey in ipairs(replacedBuffs) do
          if replacedKey == buffKey then
            return true
          end
        end
      end
    end
    
    return false
  end
  
  -- Helper function: Get weight for a buff (default 1)
  local function GetBuffWeight(buffKey)
    local weight = OGRH_SV.consumesTracking.weights[buffKey]
    if weight and weight > 0 then
      return weight
    end
    return 1  -- Default weight
  end
  
  local possiblePoints = 0
  local actualPoints = 0
  
  -- Count conflict groups (each group uses the weight of the first buff)
  for conflictId, group in pairs(conflictGroups) do
    -- Use weight of first buff in group
    local firstBuff = group.buffKeys[1]
    local weight = GetBuffWeight(firstBuff)
    
    possiblePoints = possiblePoints + weight
    -- Check if player has any buff from this group (including concoction replacements)
    local hasGroupBuff = false
    for _, buffKey in ipairs(group.buffKeys) do
      if PlayerHasBuff(buffKey) then
        hasGroupBuff = true
        break
      end
    end
    if hasGroupBuff then
      actualPoints = actualPoints + weight
    end
  end
  
  -- Count standalone buffs (not in any conflict)
  -- Exclude ONLY the 3 concoction items from possible count
  -- Buffs they replace still count as possible, and we check for concoctions when evaluating them
  for buffKey, entries in pairs(requiredBuffs) do
    for _, entry in ipairs(entries) do
      local profileIndex = entry.profileIndex
      local processKey = buffKey .. "_" .. profileIndex
      
      if not processedBuffs[processKey] then
        -- Check if this is one of the 3 concoctions
        local isConcoction = (buffKey == "emeraldmongoose" or buffKey == "dreamwater" or buffKey == "arcanegiants")
        
        if not isConcoction then
          -- Get configurable weight for this buff
          local buffValue = GetBuffWeight(buffKey)
          
          possiblePoints = possiblePoints + buffValue
          
          -- Check if player has this buff OR a concoction that replaces it
          if PlayerHasBuff(buffKey) then
            actualPoints = actualPoints + buffValue
          end
        end
        -- If it IS a concoction, don't count it as a possible point
      end
    end
  end
  
  local score = possiblePoints > 0 and floor((actualPoints / possiblePoints) * 100) or 0
  
  return score, nil, {
    possible = possiblePoints,
    actual = actualPoints,
    role = playerRole,
    roleLetter = roleLetter,
    hasBuffs = playerBuffs,
    conflictGroups = conflictGroups,
    requiredBuffs = requiredBuffs,
    concoctionReplacements = concoctionReplacements
  }
end

-- ============================================================================

-- Poll current consumables status from RABuffs
function CT.PollConsumes(editBox, scrollBar, scrollFrame)
  if not editBox then
    return
  end
  
  if not CT.IsRABuffsAvailable() then
    editBox:SetText("|cffff0000Error:|r RABuffs addon not found.")
    return
  end
  
  -- Check if OGRH_Consumables profile exists
  if not CT.CheckForOGRHProfile() then
    editBox:SetText("|cffff8800Warning:|r OGRH_Consumables profile not found in RABuffs.\n\nPlease reload the UI to create the profile.")
    return
  end
  
  -- Load the OGRH_Consumables profile bars
  local profileKey = GetCVar("realmName") .. "." .. UnitName("player") .. ".OGRH_Consumables"
  local profileBars = RABui_Settings.Layout[profileKey]
  
  if not profileBars or table.getn(profileBars) == 0 then
    editBox:SetText("|cffff8800Warning:|r OGRH_Consumables profile has no bars configured.")
    return
  end
  
  -- Build raid data structure: {playerName = {class, buffs={buffKey=true}}}
  local raidData = {}
  
  -- First pass: collect all player buff data
  for i, bar in ipairs(profileBars) do
    if bar.buffKey and RAB_Buffs[bar.buffKey] then
      local buffed, fading, total, misc, mhead, hhead, mtext, htext, invert, raw = RAB_CallRaidBuffCheck(bar, true, true)
      
      if raw and type(raw) == "table" then
        for _, playerData in ipairs(raw) do
          if playerData and playerData.name then
            local playerName = playerData.name
            local playerClass = playerData.class
            
            if not raidData[playerName] then
              raidData[playerName] = {
                class = playerClass,
                buffs = {}
              }
            end
            
            if playerData.buffed then
              raidData[playerName].buffs[bar.buffKey] = true
            end
          end
        end
      end
    end
  end
  
  -- Calculate scores for all players
  local playerScores = {} -- {{name, class, score, details}}
  for playerName, data in pairs(raidData) do
    local score, err, details = CT.CalculatePlayerScore(playerName, data.class, raidData)
    if score then
      table.insert(playerScores, {
        name = playerName,
        class = data.class,
        score = score,
        details = details
      })
    end
  end
  
  -- Sort by score (highest first), then by name
  table.sort(playerScores, function(a, b)
    if a.score ~= b.score then
      return a.score > b.score
    else
      return a.name < b.name
    end
  end)
  
  -- Calculate average score
  local totalScore = 0
  local countScored = 0
  for _, playerScore in ipairs(playerScores) do
    totalScore = totalScore + playerScore.score
    countScored = countScored + 1
  end
  local avgScore = countScored > 0 and floor(totalScore / countScored) or 0
  
  -- Build output text
  local output = {}
  table.insert(output, "|cff00ff00=== Consumables Ranking ===|r")
  table.insert(output, string.format("Time: %s", date("%H:%M:%S")))
  table.insert(output, string.format("Players: %d | Avg Score: %d%%", countScored, avgScore))
  table.insert(output, "")
  
  -- Display ranked players with detailed consumable lists
  for rank, playerScore in ipairs(playerScores) do
    local details = playerScore.details
    
    -- Color based on score
    local color
    if playerScore.score >= 80 then
      color = "|cff00ff00" -- Green
    elseif playerScore.score >= 60 then
      color = "|cffffff00" -- Yellow  
    elseif playerScore.score >= 40 then
      color = "|cffffaa00" -- Orange
    else
      color = "|cffff0000" -- Red
    end
    
    table.insert(output, string.format("%s%d. %s [%s] - %d%% (%d/%d)|r",
      color,
      rank,
      OGRH.ColorName(playerScore.name),
      details.role or "?",
      playerScore.score,
      details.actual or 0,
      details.possible or 0
    ))
    
    -- Build lists of buffs/groups they have and are missing
    -- Use conflict groups from the scoring details
    local conflictGroups = details.conflictGroups or {}
    local processedBuffs = {} -- Track which buffs are in conflict groups
    local requiredBuffs = details.requiredBuffs or {}
    local concoctionReplacements = details.concoctionReplacements or {}
    local playerBuffs = details.hasBuffs or {}
    local roleLetter = details.roleLetter
    local playerClass = playerScore.class
    local hasList = {}
    local missingList = {}
    
    -- Build satisfiedByConcoction table: which buffs are satisfied by concoctions the player has
    local satisfiedByConcoction = {}
    for concKey, replacedBuffs in pairs(concoctionReplacements) do
      if playerBuffs[concKey] then
        for _, replacedKey in ipairs(replacedBuffs) do
          -- Only mark as satisfied if the replaced buff is actually required for this player
          if requiredBuffs[replacedKey] then
            satisfiedByConcoction[replacedKey] = concKey
          end
        end
      end
    end
    
    -- First, display conflict groups (but handle concoctions specially)
    for conflictId, group in pairs(conflictGroups) do
      local groupBuffNames = {}
      local seenNames = {} -- Avoid duplicates
      for _, buffKey in ipairs(group.buffKeys) do
        if RAB_Buffs[buffKey] then
          local buffName = RAB_Buffs[buffKey].name or buffKey
          if not seenNames[buffName] then
            table.insert(groupBuffNames, buffName)
            seenNames[buffName] = true
          end
        end
        processedBuffs[buffKey] = true
      end
      
      -- Determine conflict group display name
      local groupName = conflictId
      if conflictId == "Concoction" then
        -- Special handling: show individual concoctions player has
        -- Don't show as a grouped conflict, handle individually below
        for _, buffKey in ipairs(group.buffKeys) do
          processedBuffs[buffKey] = true -- Mark as processed so they don't appear in standalone
        end
      elseif conflictId == "Food" then
        groupName = "Food (any: " .. table.concat(groupBuffNames, ", ") .. ")"
        if group.hasAny then
          table.insert(hasList, groupName)
        else
          table.insert(missingList, groupName)
        end
      elseif conflictId == "Drink" then
        groupName = "Drink (any: " .. table.concat(groupBuffNames, ", ") .. ")"
        if group.hasAny then
          table.insert(hasList, groupName)
        else
          table.insert(missingList, groupName)
        end
      elseif conflictId == "BlastedLands" then
        groupName = "Blasted Lands buff (any: " .. table.concat(groupBuffNames, ", ") .. ")"
        if group.hasAny then
          table.insert(hasList, groupName)
        else
          table.insert(missingList, groupName)
        end
      elseif string.find(conflictId, "^Group_") then
        local groupNum = string.sub(conflictId, 7)
        groupName = "Group " .. groupNum .. " buff (any: " .. table.concat(groupBuffNames, ", ") .. ")"
        if group.hasAny then
          table.insert(hasList, groupName)
        else
          table.insert(missingList, groupName)
        end
      end
    end
    
    -- Then, display standalone buffs (not in any conflict)
    
    for _, bar in ipairs(profileBars) do
      if bar.buffKey and RAB_Buffs[bar.buffKey] and not processedBuffs[bar.buffKey] then
        -- Check if this buff applies to this player
        local appliesToRole = BuffAppliesToRole(bar.label, roleLetter)
        if appliesToRole then
          -- Check class restrictions
          local includeForClass = true
          if bar.classes and bar.classes ~= "" and RAB_ClassShort and RAB_ClassShort[playerClass] then
            local classCode = RAB_ClassShort[playerClass]
            includeForClass = string.find(bar.classes, classCode) ~= nil
          end
          
          if includeForClass then
            local buffName = RAB_Buffs[bar.buffKey].name or bar.buffKey
            local buffKey = bar.buffKey
            
            -- Check if it's a concoction the player has
            local isConcoction = (buffKey == "emeraldmongoose" or buffKey == "dreamwater" or buffKey == "arcanegiants")
            if isConcoction and playerBuffs[buffKey] then
              -- Calculate how many required buffs this concoction replaces
              local replacedBuffs = concoctionReplacements[buffKey] or {}
              local replacedCount = 0
              for _, replacedKey in ipairs(replacedBuffs) do
                if requiredBuffs[replacedKey] then
                  replacedCount = replacedCount + 1
                end
              end
              -- Show concoction with actual contribution
              if replacedCount > 0 then
                table.insert(hasList, buffName .. " (+" .. replacedCount .. ")")
              else
                table.insert(hasList, buffName)
              end
            elseif not isConcoction then
              -- Regular buff
              if playerBuffs[buffKey] then
                table.insert(hasList, buffName)
              elseif not satisfiedByConcoction[buffKey] then
                -- Only show as missing if it's not satisfied by a concoction
                table.insert(missingList, buffName)
              end
            end
          end
        end
      end
    end
    
    -- Display what they have
    if table.getn(hasList) > 0 then
      table.insert(output, "   |cff00ff00✓ Has:|r")
      for _, item in ipairs(hasList) do
        table.insert(output, "      " .. item)
      end
    end
    
    -- Display what they're missing
    if table.getn(missingList) > 0 then
      table.insert(output, "   |cffff8800✗ Missing:|r")
      for _, item in ipairs(missingList) do
        table.insert(output, "      " .. item)
      end
    end
    
    -- Add spacing between players
    table.insert(output, "")
  end
  
  if countScored == 0 then
    table.insert(output, "|cffff8800No players with assigned roles found.|r")
    table.insert(output, "")
    table.insert(output, "Please assign roles in the Roles UI first.")
    table.insert(output, "")
  end
  
  table.insert(output, "|cff888888Note: Scores based on role requirements and conflict configuration.|r")
  
  -- OLD CODE REMOVED: Individual buff status listings
  -- Now we show ranked player scores instead
  
  -- Commented out old buff-by-buff display
  --[[
  for i, bar in ipairs(profileBars) do
    if bar.buffKey and RAB_Buffs[bar.buffKey] then
      -- Call with needraw=true to get detailed player data
      local buffed, fading, total, misc, mhead, hhead, mtext, htext, invert, raw = RAB_CallRaidBuffCheck(bar, true, true)
      
      local buffName = RAB_Buffs[bar.buffKey].name or bar.buffKey
      local buffedCount = buffed or 0
      local totalCount = total or 0
      local percentage = totalCount > 0 and floor(buffedCount * 100 / totalCount) or 0
      
      -- Color based on percentage
      local color
      if percentage >= 80 then
        color = "|cff00ff00" -- Green
      elseif percentage >= 50 then
        color = "|cffffff00" -- Yellow
      else
        color = "|cffff0000" -- Red
      end
      
      -- OLD BUFF-BY-BUFF DISPLAY CODE REMOVED
    end
  end
  --]]
  
  -- Update output text in editBox
  local outputStr = table.concat(output, "\n")
  editBox:SetText(outputStr)
  editBox:ClearFocus()
  
  -- Force scroll update
  if scrollFrame and scrollBar then
    local scrollChild = scrollFrame:GetScrollChild()
    if scrollChild then
      local maxScroll = scrollChild:GetHeight() - scrollFrame:GetHeight()
      if maxScroll > 0 then
        scrollBar:SetMinMaxValues(0, maxScroll)
        scrollBar:Show()
      else
        scrollBar:Hide()
      end
      scrollBar:SetValue(0)  -- Scroll to top
    end
  end
end

-- Announce top 10 consumables scores to raid chat
function CT.AnnounceConsumes()
  if not CT.IsRABuffsAvailable() then
    OGRH.Msg("Error: RABuffs addon not found.")
    return
  end
  
  if not CT.CheckForOGRHProfile() then
    OGRH.Msg("Error: OGRH_Consumables profile not found.")
    return
  end
  
  -- Load the OGRH_Consumables profile bars
  local profileKey = GetCVar("realmName") .. "." .. UnitName("player") .. ".OGRH_Consumables"
  local profileBars = RABui_Settings.Layout[profileKey]
  
  if not profileBars or table.getn(profileBars) == 0 then
    OGRH.Msg("Error: OGRH_Consumables profile has no bars configured.")
    return
  end
  
  -- Build raid data structure
  local raidData = {}
  
  for i, bar in ipairs(profileBars) do
    if bar.buffKey and RAB_Buffs[bar.buffKey] then
      local buffed, fading, total, misc, mhead, hhead, mtext, htext, invert, raw = RAB_CallRaidBuffCheck(bar, true, true)
      
      if raw and type(raw) == "table" then
        for _, playerData in ipairs(raw) do
          if playerData and playerData.name then
            local playerName = playerData.name
            local playerClass = playerData.class
            
            if not raidData[playerName] then
              raidData[playerName] = {
                class = playerClass,
                buffs = {}
              }
            end
            
            if playerData.buffed then
              raidData[playerName].buffs[bar.buffKey] = true
            end
          end
        end
      end
    end
  end
  
  -- Calculate scores for all players
  local playerScores = {}
  for playerName, data in pairs(raidData) do
    local score, err, details = CT.CalculatePlayerScore(playerName, data.class, raidData)
    if score then
      table.insert(playerScores, {
        name = playerName,
        class = data.class,
        score = score,
        details = details
      })
    end
  end
  
  -- Sort by score (highest first), then by name
  table.sort(playerScores, function(a, b)
    if a.score ~= b.score then
      return a.score > b.score
    else
      return a.name < b.name
    end
  end)
  
  -- Announce header
  SendChatMessage("=== Consumables Ranking (Top 10) ===", "RAID")
  
  -- Announce top 10 players
  local maxPlayers = math.min(10, table.getn(playerScores))
  for rank = 1, maxPlayers do
    local playerScore = playerScores[rank]
    local details = playerScore.details
    
    local message = string.format("%d. %s [%s] - %d%% (%d/%d)",
      rank,
      playerScore.name,
      details.role or "?",
      playerScore.score,
      details.actual or 0,
      details.possible or 0
    )
    
    SendChatMessage(message, "RAID")
  end
end

-- ============================================================================
-- Integration with RABuffs
-- ============================================================================

-- Check if RABuffs is available
function CT.IsRABuffsAvailable()
  return RAB_CallRaidBuffCheck ~= nil and RAB_ImportProfile ~= nil
end

-- Check if the OGRH consumables profile exists in RABuffs
function CT.CheckForOGRHProfile()
  if not CT.IsRABuffsAvailable() then
    return false
  end
  
  -- Check if profile exists using RABuffs internal functions
  if not RABui_Settings or not RABui_Settings.Layout then
    return false
  end
  
  -- Build profile key: RealmName.PlayerName.ProfileName
  local profileKey = GetCVar("realmName") .. "." .. UnitName("player") .. ".OGRH_Consumables"
  return RABui_Settings.Layout[profileKey] ~= nil
end

-- Initialize integration with RABuffs
function CT.InitializeRABuffsIntegration()
  if not CT.IsRABuffsAvailable() then
    OGRH.Msg("|cffff0000Warning:|r RABuffs addon not found. Consumes tracking requires RABuffs to function.")
    return false
  end
  
  -- Check if OGRH profile exists, create it if not
  if not CT.CheckForOGRHProfile() then
    -- Ensure RABui_Settings structure exists
    if not RABui_Settings then
      return false
    end
    
    if not RABui_Settings.Layout then
      RABui_Settings.Layout = {}
    end
    
    -- Use the default profile from the external defaults file
    local profileData = OGRH.ConTrack and OGRH.ConTrack.DefaultProfile
    if not profileData then
      OGRH.Msg("|cffff0000Error:|r OGRH_ConTrack_Defaults.lua not loaded.")
      return false
    end
    
    local success = RAB_ImportProfile("OGRH_Consumables", profileData)
    if success then
      OGRH.Msg("OGRH_Consumables profile created in RABuffs.")
      
      -- Clear any existing role mapping data to force reload from new profile defaults
      if OGRH_SV.consumesTracking then
        OGRH_SV.consumesTracking.roleMapping = {}
      end
    else
      OGRH.Msg("|cffff0000Error:|r Failed to create OGRH_Consumables profile.")
      return false
    end
  end
  
  return true
end

-- Update the label for a specific buff in RABuffs profile
function CT.UpdateRABuffsLabel(buffKey, newLabel, profileIndex)
  if not CT.IsRABuffsAvailable() then
    return false
  end
  
  if not RABui_Settings or not RABui_Settings.Layout then
    return false
  end
  
  -- Build profile key
  local profileKey = GetCVar("realmName") .. "." .. UnitName("player") .. ".OGRH_Consumables"
  local profileBars = RABui_Settings.Layout[profileKey]
  
  if not profileBars then
    return false
  end
  
  -- If profileIndex is provided, update that specific bar
  if profileIndex then
    local bar = profileBars[profileIndex]
    if bar and bar.buffKey == buffKey then
      bar.label = newLabel
      return true
    end
  else
    -- Legacy: Find the first bar with matching buffKey (for backward compatibility)
    for i, bar in ipairs(profileBars) do
      if bar.buffKey == buffKey then
        bar.label = newLabel
        return true
      end
    end
  end
  
  return false
end

-- Generate label string based on role mapping
function CT.GenerateLabelFromRoles(roleMapping)
  local label = ""
  local roles = {"tanks", "healers", "melee", "ranged"}
  local roleLetters = {tanks = "T", healers = "H", melee = "M", ranged = "R"}
  
  for _, role in ipairs(roles) do
    if roleMapping[role] then
      label = label .. roleLetters[role]
    else
      label = label .. "X"
    end
  end
  
  return label
end

-- Parse label string to role mapping
function CT.ParseLabelToRoles(label)
  local roleMapping = {tanks = false, healers = false, melee = false, ranged = false}
  local roles = {"tanks", "healers", "melee", "ranged"}
  local roleLetters = {T = "tanks", H = "healers", M = "melee", R = "ranged"}
  
  if not label or label == "" then
    return roleMapping
  end
  
  -- Parse each character in the label
  for i = 1, string.len(label) do
    local char = string.sub(label, i, i)
    if roleLetters[char] then
      roleMapping[roleLetters[char]] = true
    end
  end
  
  return roleMapping
end

-- ============================================================================
-- Pull Detection (Placeholder)
-- ============================================================================

-- Detect raid pull announcements
function CT.OnChatMessage(msg, sender)
  if not OGRH_SV.consumesTracking.enabled then
    return
  end
  
  -- Pull detection logic will be implemented in future updates
end

-- ============================================================================
-- Initialization
-- ============================================================================

-- Initialize the module
function CT.Initialize()
  CT.EnsureSavedVariables()
  
  -- Delay RABuffs integration to ensure it's fully loaded
  local rabuffsInitFrame = CreateFrame("Frame")
  local attempts = 0
  local maxAttempts = 50 -- 5 seconds max
  
  rabuffsInitFrame:SetScript("OnUpdate", function()
    attempts = attempts + 1
    
    if CT.IsRABuffsAvailable() and RABui_Settings then
      -- RABuffs is ready
      if RAB_ImportProfile and RAB_GetProfileKey then
        CT.InitializeRABuffsIntegration()
      end
      this:SetScript("OnUpdate", nil)
    elseif attempts >= maxAttempts then
      -- Timeout - RABuffs not available
      this:SetScript("OnUpdate", nil)
    end
  end)
end

-- Call initialization directly
CT.Initialize()
-- Debug/Info
-- ============================================================================

OGRH.Msg("ConsumesTracking module loaded (v1.0.0)")
