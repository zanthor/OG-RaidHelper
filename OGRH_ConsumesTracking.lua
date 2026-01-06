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
      }
    }
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
        if isChecked then
          OGRH.Msg("Consumes tracking |cff00ff00enabled|r.")
        else
          OGRH.Msg("Consumes tracking |cffff0000disabled|r.")
        end
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
    OGST.AnchorElement(pollBtn, detailPanel, {position = "top", align = "center", offsetY = -10})
    
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
    
    -- Store references on the button frame
    pollBtn.editBox = textBoxEditBox
    pollBtn.scrollBar = textBoxScrollBar
    pollBtn.scrollFrame = textBoxScrollFrame
    
    -- Button click handler
    pollBtn:SetScript("OnClick", function()
      CT.PollConsumes(this.editBox, this.scrollBar, this.scrollFrame)
    end)
    
    table.insert(trackConsumesFrame.detailContent, pollBtn)
    table.insert(trackConsumesFrame.detailContent, textBoxBackdrop)
    
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
          label = bar.label
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
      -- Initialize role mapping for this consumable if not exists
      if not OGRH_SV.consumesTracking.roleMapping[consumable.buffKey] then
        -- Get the label from RABuffs profile and parse it to determine initial checked state
        local profileKey = GetCVar("realmName") .. "." .. UnitName("player") .. ".OGRH_Consumables"
        local profileBars = RABui_Settings.Layout[profileKey]
        
        local initialMapping = {tanks = false, healers = false, melee = false, ranged = false}
        
        if profileBars then
          -- Find the bar with matching buffKey
          for _, bar in ipairs(profileBars) do
            if bar.buffKey == consumable.buffKey and bar.label then
              initialMapping = CT.ParseLabelToRoles(bar.label)
              break
            end
          end
        end
        
        OGRH_SV.consumesTracking.roleMapping[consumable.buffKey] = initialMapping
      end
      
      -- Create item
      local item = mappingList:AddItem({
        text = consumable.buffName
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
        checkbox:SetChecked(OGRH_SV.consumesTracking.roleMapping[consumable.buffKey][role])
        
        -- Store reference for closure
        checkbox.buffKey = consumable.buffKey
        checkbox.role = role
        
        -- Click handler
        checkbox:SetScript("OnClick", function()
          OGRH_SV.consumesTracking.roleMapping[this.buffKey][this.role] = this:GetChecked()
          
          -- Update RABuffs label based on new role mapping
          local roleMapping = OGRH_SV.consumesTracking.roleMapping[this.buffKey]
          local newLabel = CT.GenerateLabelFromRoles(roleMapping)
          CT.UpdateRABuffsLabel(this.buffKey, newLabel)
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
      
      -- Add existing conflicts with delete buttons
      local conflicts = OGRH_SV.consumesTracking.conflicts
      for i = 1, table.getn(conflicts) do
        local conflict = conflicts[i]
        local buffName = "Unknown"
        if RAB_Buffs and RAB_Buffs[conflict.buffKey] then
          buffName = RAB_Buffs[conflict.buffKey].name or conflict.buffKey
        end
        
        local conflictText = buffName
        if conflict.conflictsWith and table.getn(conflict.conflictsWith) > 0 then
          conflictText = conflictText .. " (conflicts: " .. table.getn(conflict.conflictsWith) .. ")"
        end
        
        local capturedIndex = i  -- Capture for closure
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
        buffName = RAB_Buffs[bar.buffKey].name or bar.buffKey
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
    
    buffList:AddItem({
      text = capturedBuffName,
      onClick = function()
        -- Create new conflict entry
        if not OGRH_SV.consumesTracking.conflicts then
          OGRH_SV.consumesTracking.conflicts = {}
        end
        
        -- Check if conflict already exists for this buff
        local exists = false
        for j = 1, table.getn(OGRH_SV.consumesTracking.conflicts) do
          if OGRH_SV.consumesTracking.conflicts[j].buffKey == capturedBuffKey then
            exists = true
            break
          end
        end
        
        if not exists then
          table.insert(OGRH_SV.consumesTracking.conflicts, {
            buffKey = capturedBuffKey,
            conflictsWith = {}
          })
          
          OGRH.Msg("Added conflict configuration for " .. capturedBuffName)
          
          -- Refresh the Conflicts panel if it's visible
          if trackConsumesFrame and trackConsumesFrame:IsVisible() then
            CT.UpdateDetailPanel("Conflicts")
          end
        else
          OGRH.Msg("Conflict configuration already exists for " .. capturedBuffName)
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

-- Poll current consumables status from RABuffs
function CT.PollConsumes(editBox, scrollBar, scrollFrame)
  if not editBox then
    OGRH.Msg("PollConsumes error: editBox is nil")
    return
  end
  
  OGRH.Msg("Poll Consumes clicked - updating text...")
  
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
  
  -- Build output text
  local output = {}
  table.insert(output, "|cff00ff00=== Consumables Status ===|r")
  table.insert(output, string.format("Time: %s", date("%H:%M:%S")))
  table.insert(output, string.format("Profile: OGRH_Consumables (%d buffs)", table.getn(profileBars)))
  table.insert(output, "")
  
  -- Don't modify RABui_Bars - just iterate the profile bars directly
  -- Poll each bar from the OGRH_Consumables profile
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
      
      table.insert(output, string.format("%s[%s] %s: %d/%d (%d%%)|r", 
        color, bar.label or "?", buffName, buffedCount, totalCount, percentage))
      
      -- Add detailed player info if available
      if raw and type(raw) == "table" and table.getn(raw) > 0 then
        local withBuff = {}
        local withoutBuff = {}
        
        for _, playerData in ipairs(raw) do
          if playerData and playerData.name then
            local playerName = playerData.name
            local playerClass = playerData.class or "Unknown"
            local playerGroup = playerData.group or 0
            local formattedName = string.format("%s [%s; G%d]", playerName, playerClass, playerGroup)
            
            if playerData.buffed then
              table.insert(withBuff, formattedName)
            else
              table.insert(withoutBuff, formattedName)
            end
          end
        end
        
        if table.getn(withBuff) > 0 then
          table.insert(output, "  |cff00ff00With buff:|r " .. table.concat(withBuff, ", "))
        end
        if table.getn(withoutBuff) > 0 then
          table.insert(output, "  |cffff8800Missing:|r " .. table.concat(withoutBuff, ", "))
        end
      end
      
      table.insert(output, "")
    end
  end
  
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
  
  OGRH.Msg("Poll complete - " .. table.getn(profileBars) .. " buffs checked")
end

-- ============================================================================
-- Integration with RABuffs
-- ============================================================================

-- Check if RABuffs is available
function CT.IsRABuffsAvailable()
  return RAB_CallRaidBuffCheck ~= nil and RAB_ImportProfile ~= nil
end

-- Profile data for OGRH consumables tracking
local OGRH_CONSUMABLES_PROFILE = '{[1]={["excludeNames"]={},["label"]="TXMX",["color"]={[1]=1,[2]=1,[3]=1},["extralabel"]="",["selfLimit"]=false,["classes"]="",["groups"]="",["out"]="RAID",["buffKey"]="arcanegiants",["priority"]=1,["useOnClick"]=false},[2]={["excludeNames"]={},["label"]="TXMX",["color"]={[1]=1,[2]=1,[3]=1},["extralabel"]="",["selfLimit"]=false,["classes"]=" as",["groups"]="",["out"]="RAID",["buffKey"]="dreamwater",["priority"]=1,["useOnClick"]=false},[3]={["excludeNames"]={},["label"]="TXMX",["color"]={[1]=1,[2]=1,[3]=1},["extralabel"]="",["selfLimit"]=false,["classes"]=" as",["groups"]="",["out"]="RAID",["buffKey"]="emeraldmongoose",["priority"]=1,["useOnClick"]=false},[4]={["excludeNames"]={},["label"]="THMR",["color"]={[1]=1,[2]=1,[3]=1},["extralabel"]="",["selfLimit"]=false,["classes"]="",["groups"]="",["out"]="RAID",["buffKey"]="telabimdelight",["priority"]=1,["useOnClick"]=false},[5]={["excludeNames"]={},["label"]="THMR",["color"]={[1]=1,[2]=1,[3]=1},["extralabel"]="",["selfLimit"]=false,["classes"]="",["groups"]="",["out"]="RAID",["buffKey"]="telabimsurprise",["priority"]=1,["useOnClick"]=false},[6]={["excludeNames"]={},["label"]="THMR",["color"]={[1]=1,[2]=1,[3]=1},["extralabel"]="",["selfLimit"]=false,["classes"]=" as",["groups"]="",["out"]="RAID",["buffKey"]="dreamshard",["priority"]=1,["useOnClick"]=false},[7]={["excludeNames"]={},["label"]="TXMR",["color"]={[1]=1,[2]=1,[3]=1},["extralabel"]="",["selfLimit"]=false,["classes"]=" as",["groups"]="",["out"]="RAID",["buffKey"]="dreamtonic",["priority"]=1,["useOnClick"]=false},[8]={["excludeNames"]={},["label"]="TXMR",["color"]={[1]=1,[2]=1,[3]=1},["extralabel"]="",["selfLimit"]=false,["classes"]=" wd",["groups"]="",["out"]="RAID",["buffKey"]="giants",["priority"]=1,["useOnClick"]=false},[9]={["excludeNames"]={},["label"]="TXMR",["color"]={[1]=1,[2]=1,[3]=1},["extralabel"]="",["selfLimit"]=false,["classes"]="",["groups"]="",["out"]="RAID",["buffKey"]="greaterarcanepower",["priority"]=1,["useOnClick"]=false},[10]={["excludeNames"]={},["label"]="TXMR",["color"]={[1]=1,[2]=1,[3]=1},["extralabel"]="",["selfLimit"]=false,["classes"]="",["groups"]="",["out"]="RAID",["buffKey"]="greaterfirepower",["priority"]=1,["useOnClick"]=false},[11]={["excludeNames"]={},["label"]="TXMR",["color"]={[1]=1,[2]=1,[3]=1},["extralabel"]="",["selfLimit"]=false,["classes"]="",["groups"]="",["out"]="RAID",["buffKey"]="greaterfrostpower",["priority"]=1,["useOnClick"]=false},[12]={["excludeNames"]={},["label"]="TXMR",["color"]={[1]=1,[2]=1,[3]=1},["extralabel"]="",["selfLimit"]=false,["classes"]="",["groups"]="",["out"]="RAID",["buffKey"]="greaternaturepower",["priority"]=1,["useOnClick"]=false},[13]={["excludeNames"]={},["label"]="TXMR",["color"]={[1]=1,[2]=1,[3]=1},["extralabel"]="",["selfLimit"]=false,["classes"]="",["groups"]="",["out"]="RAID",["buffKey"]="mongoose",["priority"]=1,["useOnClick"]=false},[14]={["excludeNames"]={},["label"]="TXXX",["color"]={[1]=1,[2]=1,[3]=1},["extralabel"]="",["selfLimit"]=false,["classes"]="",["groups"]="",["out"]="RAID",["buffKey"]="supdef",["priority"]=1,["useOnClick"]=false},[15]={["excludeNames"]={},["label"]="TXMR",["color"]={[1]=1,[2]=1,[3]=1},["extralabel"]="",["selfLimit"]=false,["classes"]=" lp",["groups"]="",["out"]="RAID",["buffKey"]="shadowpower",["priority"]=1,["useOnClick"]=false},[16]={["excludeNames"]={},["label"]="TXXX",["color"]={[1]=1,[2]=1,[3]=1},["extralabel"]="",["selfLimit"]=false,["classes"]="",["groups"]="",["out"]="RAID",["buffKey"]="titans",["priority"]=1,["useOnClick"]=false},[17]={["excludeNames"]={},["label"]="TXXX",["color"]={[1]=1,[2]=1,[3]=1},["extralabel"]="",["selfLimit"]=false,["classes"]="",["groups"]="",["out"]="RAID",["buffKey"]="giftarthas",["priority"]=1,["useOnClick"]=false},[18]={["excludeNames"]={},["label"]="TXMR",["color"]={[1]=1,[2]=1,[3]=1},["extralabel"]="",["selfLimit"]=false,["classes"]=" as",["groups"]="",["out"]="RAID",["buffKey"]="greaterarcane",["priority"]=1,["useOnClick"]=false},[19]={["excludeNames"]={},["label"]="TXMR",["color"]={[1]=1,[2]=1,[3]=1},["extralabel"]="",["selfLimit"]=false,["classes"]="",["groups"]="",["out"]="RAID",["buffKey"]="scorpok",["priority"]=1,["useOnClick"]=false},[20]={["excludeNames"]={},["label"]="THMR",["color"]={[1]=1,[2]=1,[3]=1},["extralabel"]="",["selfLimit"]=false,["classes"]="",["groups"]="",["out"]="RAID",["buffKey"]="mushroomstam",["priority"]=1,["useOnClick"]=false},[21]={["excludeNames"]={},["label"]="THMR",["color"]={[1]=1,[2]=1,[3]=1},["extralabel"]="",["selfLimit"]=false,["classes"]="",["groups"]="",["out"]="RAID",["buffKey"]="herbalsalad",["priority"]=1,["useOnClick"]=false},[22]={["excludeNames"]={},["label"]="TXMR",["color"]={[1]=1,[2]=1,[3]=1},["extralabel"]="",["selfLimit"]=false,["classes"]=" wsd",["groups"]="",["out"]="RAID",["buffKey"]="jujumight",["priority"]=1,["useOnClick"]=false},[23]={["excludeNames"]={},["label"]="THMR",["color"]={[1]=1,[2]=1,[3]=1},["extralabel"]="",["selfLimit"]=false,["classes"]="",["groups"]="",["out"]="RAID",["buffKey"]="merlot",["priority"]=1,["useOnClick"]=false},[24]={["excludeNames"]={},["label"]="THMR",["color"]={[1]=1,[2]=1,[3]=1},["extralabel"]="",["selfLimit"]=false,["classes"]="",["groups"]="",["out"]="RAID",["buffKey"]="nightfinsoup",["priority"]=1,["useOnClick"]=false},[25]={["excludeNames"]={},["label"]="TXMR",["color"]={[1]=1,[2]=1,[3]=1},["extralabel"]="",["selfLimit"]=false,["classes"]="",["groups"]="",["out"]="RAID",["buffKey"]="roids",["priority"]=1,["useOnClick"]=false},[26]={["excludeNames"]={},["label"]="THMR",["color"]={[1]=1,[2]=1,[3]=1},["extralabel"]="",["selfLimit"]=false,["classes"]="",["groups"]="",["out"]="RAID",["buffKey"]="rumseyrum",["priority"]=1,["useOnClick"]=false},[27]={["excludeNames"]={},["label"]="TXMR",["color"]={[1]=1,[2]=1,[3]=1},["extralabel"]="",["selfLimit"]=false,["classes"]=" wsd",["groups"]="",["out"]="RAID",["buffKey"]="firewater",["priority"]=1,["useOnClick"]=false},[28]={["excludeNames"]={},["label"]="THMR",["color"]={[1]=1,[2]=1,[3]=1},["extralabel"]="",["selfLimit"]=false,["classes"]="",["groups"]="",["out"]="RAID",["buffKey"]="spiritofzanza",["priority"]=1,["useOnClick"]=false}}'

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
    
    local success = RAB_ImportProfile("OGRH_Consumables", OGRH_CONSUMABLES_PROFILE)
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
function CT.UpdateRABuffsLabel(buffKey, newLabel)
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
  
  -- Find the bar with matching buffKey and update its label
  for i, bar in ipairs(profileBars) do
    if bar.buffKey == buffKey then
      bar.label = newLabel
      return true
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
