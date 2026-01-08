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
      trackOnPull = false,
      trackingProfiles = {},
      logToMemory = true,
      logToCombatLog = false,
      maxEntries = 200,
      secondsBeforePull = 2,
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
  
  -- Ensure trackOnPull exists for existing saves
  if OGRH_SV.consumesTracking.trackOnPull == nil then
    OGRH_SV.consumesTracking.trackOnPull = false
  end
  
  -- Ensure secondsBeforePull exists for existing saves
  if not OGRH_SV.consumesTracking.secondsBeforePull then
    OGRH_SV.consumesTracking.secondsBeforePull = 2
  end
  
  -- Ensure logToCombatLog exists for existing saves
  if OGRH_SV.consumesTracking.logToCombatLog == nil then
    OGRH_SV.consumesTracking.logToCombatLog = false
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
  if not OGRH_SV.consumesTracking.history then
    OGRH_SV.consumesTracking.history = {}
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
local eventHandlerFrame = nil  -- Separate frame for event handling

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
    {name = "Tracking"},
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
  
  -- Track current selection
  trackConsumesFrame.currentSelection = actionName
  
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
  
  if actionName == "Tracking" then
    -- Track on Pull checkbox using OGST
    local enableCheckbox, checkButton, checkLabel = OGST.CreateCheckbox(detailPanel, {
      label = "Track on Pull",
      checked = OGRH_SV.consumesTracking.trackOnPull,
      onChange = function(isChecked)
        OGRH_SV.consumesTracking.trackOnPull = isChecked
      end
    })
    OGST.AnchorElement(enableCheckbox, detailPanel, {position = "top", align = "left", offsetX = 10, offsetY = -10})
    
    -- Numeric text input for seconds before pull with label
    local secondsContainer, secondsBackdrop, secondsEditBox, secondsLabelText = OGST.CreateSingleLineTextBox(detailPanel, 150, 20, {
      maxLetters = 2,
      numeric = true,
      align = "CENTER",
      textBoxWidth = 40,
      label = "seconds before pull.",
      labelWidth = 100,
      labelAnchor = "RIGHT",
      labelFont = "GameFontNormalSmall",
      gap = 5,
      onChange = function(text)
        local value = tonumber(text)
        if value and value >= 0 and value <= 99 then
          OGRH_SV.consumesTracking.secondsBeforePull = value
        end
      end
    })
    -- Set initial text
    secondsEditBox:SetText(tostring(OGRH_SV.consumesTracking.secondsBeforePull or 2))
    OGST.AnchorElement(secondsContainer, enableCheckbox, {position = "right", align = "center", offsetX = 5})
    
    -- Combat Log checkbox (disabled if SuperWoW not available)
    local hasSuperWoW = CT.IsSuperWoWAvailable()
    local combatLogCheckbox, combatLogCheckButton, combatLogLabel = OGST.CreateCheckbox(detailPanel, {
      label = "Combat Log",
      checked = OGRH_SV.consumesTracking.logToCombatLog and hasSuperWoW,
      onChange = function(isChecked)
        if hasSuperWoW then
          OGRH_SV.consumesTracking.logToCombatLog = isChecked
        end
      end
    })
    OGST.AnchorElement(combatLogCheckbox, secondsContainer, {position = "right", align = "center", offsetX = 5})
    
    -- Disable checkbox if SuperWoW not available
    if not hasSuperWoW then
      combatLogCheckButton:Disable()
      combatLogLabel:SetTextColor(0.5, 0.5, 0.5)
      -- Add tooltip explaining requirement
      combatLogCheckbox:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:SetText("SuperWoW Required", 1, 1, 1)
        GameTooltip:AddLine("Combat log feature requires SuperWoW addon.", 1, 0.8, 0, true)
        GameTooltip:AddLine("Get it from: github.com/balakethelock/SuperWoW", 0.5, 0.5, 1, true)
        GameTooltip:Show()
      end)
      combatLogCheckbox:SetScript("OnLeave", function()
        GameTooltip:Hide()
      end)
    end
    table.insert(trackConsumesFrame.detailContent, combatLogCheckbox)
    
    -- Create dual list panels using OGST properly (following Mapping pattern)
    -- Static sizing: 600 window - 175 left panel - borders/padding = ~380 width total
    local leftListWidth = 230
    local rightListWidth = 150
    local listHeight = 260
    
    -- Left Panel: History List
    local historyLabel = OGST.CreateStaticText(detailPanel, {
      text = "Tracking History",
      font = "GameFontNormal",
      color = {r = 1, g = 1, b = 1},
      width = leftListWidth
    })
    OGST.AnchorElement(historyLabel, enableCheckbox, {position = "below", align = "left"})
    
    local historyListFrame = OGST.CreateStyledScrollList(detailPanel, leftListWidth, listHeight)
    OGST.AnchorElement(historyListFrame, historyLabel, {position = "below"})
    
    -- Right Panel: Player Scores List (positioned relative to left panel)
    local scoresLabel = OGST.CreateStaticText(detailPanel, {
      text = "Player Scores",
      font = "GameFontNormal",
      color = {r = 1, g = 1, b = 1},
      width = rightListWidth
    })
    OGST.AnchorElement(scoresLabel, historyLabel, {position = "right"})
    
    local playerScoresListFrame = OGST.CreateStyledScrollList(detailPanel, rightListWidth, listHeight)
    OGST.AnchorElement(playerScoresListFrame, scoresLabel, {position = "below"})
    
    -- Store list frame references for refresh functions
    CT.historyListFrame = historyListFrame
    CT.playerScoresListFrame = playerScoresListFrame
    
    table.insert(trackConsumesFrame.detailContent, enableCheckbox)
    table.insert(trackConsumesFrame.detailContent, secondsContainer)
    table.insert(trackConsumesFrame.detailContent, historyLabel)
    table.insert(trackConsumesFrame.detailContent, historyListFrame)
    table.insert(trackConsumesFrame.detailContent, scoresLabel)
    table.insert(trackConsumesFrame.detailContent, playerScoresListFrame)
    
    -- Initial population of history list (after elements are added)
    CT.RefreshHistoryList()
    
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
  
  -- TESTING: Write to combat log if enabled
  if OGRH_SV.consumesTracking.logToCombatLog and CT.IsSuperWoWAvailable() then
    -- Get raid/encounter selection
    local raid, encounter = OGRH.GetSelectedRaidAndEncounter()
    if raid and encounter then
      -- Convert playerScores to the format expected by WriteConsumesToCombatLog
      local players = {}
      for _, playerScore in ipairs(playerScores) do
        table.insert(players, {
          name = playerScore.name,
          class = playerScore.class,
          role = playerScore.details.role or "UNKNOWN",
          score = playerScore.score
        })
      end
      
      -- Create a record structure
      local timestamp = time()
      local record = {
        timestamp = timestamp,
        date = date("%m/%d", timestamp),
        time = date("%H:%M", timestamp),
        raid = raid,
        encounter = encounter,
        players = players,
        groupSize = GetNumRaidMembers()
      }
      
      -- Write to combat log
      local success, err = CT.WriteConsumesToCombatLog(record)
      if success then
        OGRH.Msg("|cff00ff00Poll results written to combat log|r")
      else
        OGRH.Msg("|cffff8800Warning:|r Failed to write to combat log: " .. (err or "Unknown error"))
      end
    else
      OGRH.Msg("|cffff8800Note:|r Select a raid/encounter to write poll results to combat log")
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
-- SuperWoW / Combat Log Integration
-- ============================================================================

-- Check if SuperWoW is available (provides CombatLogAdd function)
function CT.IsSuperWoWAvailable()
  return CombatLogAdd ~= nil
end

-- Write consume tracking data to combat log via SuperWoW's CombatLogAdd
-- This writes directly to Logs/WoWCombatLog.txt
function CT.WriteConsumesToCombatLog(record)
  if not CT.IsSuperWoWAvailable() then
    return false, "SuperWoW not available"
  end
  
  if not record then
    return false, "No record provided"
  end
  
  -- Format: OGRH_CONSUME_PULL: timestamp&date&time&raid&encounter&pullNumber&requester&groupSize
  local header = string.format("OGRH_CONSUME_PULL: %s&%s&%s&%s&%s&%d&%s&%d",
    tostring(record.timestamp or time()),
    record.date or "",
    record.time or "",
    record.raid or "",
    record.encounter or "",
    CT.currentPullNumber or 0,
    CT.currentPullRequester or "Unknown",
    record.groupSize or GetNumRaidMembers()
  )
  
  CombatLogAdd(header)
  
  -- Write each player's score
  -- Format: OGRH_CONSUME_PLAYER: playerName&class&role&score&actualPoints&possiblePoints
  if record.players then
    for _, player in ipairs(record.players) do
      -- Calculate actual and possible points for this player
      local profileKey = GetCVar("realmName") .. "." .. UnitName("player") .. ".OGRH_Consumables"
      local profileBars = RABui_Settings and RABui_Settings.Layout and RABui_Settings.Layout[profileKey]
      
      local actualPoints = 0
      local possiblePoints = 0
      
      if profileBars then
        -- Recalculate detailed score for this player
        local raidData = {}
        for i, bar in ipairs(profileBars) do
          if bar.buffKey and RAB_Buffs[bar.buffKey] then
            local buffed, fading, total, misc, mhead, hhead, mtext, htext, invert, raw = RAB_CallRaidBuffCheck(bar, true, true)
            
            if raw and type(raw) == "table" then
              for _, playerData in ipairs(raw) do
                if playerData and playerData.name == player.name then
                  if not raidData[player.name] then
                    raidData[player.name] = {
                      class = playerData.class,
                      buffs = {}
                    }
                  end
                  
                  if playerData.buffed then
                    raidData[player.name].buffs[bar.buffKey] = true
                  end
                end
              end
            end
          end
        end
        
        local score, err, details = CT.CalculatePlayerScore(player.name, player.class, raidData)
        if details then
          actualPoints = details.actual or 0
          possiblePoints = details.possible or 0
        end
      end
      
      local playerLine = string.format("OGRH_CONSUME_PLAYER: %s&%s&%s&%d&%d&%d",
        player.name,
        player.class or "Unknown",
        player.role or "UNKNOWN",
        player.score or 0,
        actualPoints,
        possiblePoints
      )
      CombatLogAdd(playerLine)
    end
  end
  
  -- End marker
  CombatLogAdd(string.format("OGRH_CONSUME_END: %s", tostring(record.timestamp or time())))
  
  return true
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
  
  -- Register for BigWigs pull timer detection (Phase 3)
  if not eventHandlerFrame then
    eventHandlerFrame = CreateFrame("Frame", "OGRH_ConsumesTrackingEventFrame")
  end
  eventHandlerFrame:RegisterEvent("CHAT_MSG_ADDON")
  eventHandlerFrame:SetScript("OnEvent", CT.OnPullTimerDetected)
  
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

-- ============================================================================
-- Phase 1: History Tracking - Data Management Functions
-- ============================================================================

-- Module-level state for tracking history UI
CT.selectedRecordIndex = nil
CT.historyListFrame = nil
CT.playerScoresListFrame = nil

-- ============================================================================
-- Phase 3: Pull Detection System - State Variables
-- ============================================================================

-- Current pull tracking state
CT.currentPullNumber = 0
CT.currentPullRequester = "Unknown"
CT.currentPullStartTime = 0
CT.captureScheduled = false
CT.captureTimerFrame = nil

-- ============================================================================
-- Phase 3: Pull Detection System - State Variables
-- ============================================================================

-- Current pull tracking state
CT.currentPullNumber = 0
CT.currentPullRequester = "Unknown"
CT.currentPullStartTime = 0
CT.captureScheduled = false
CT.captureTimerFrame = nil

-- Sort players by role and score for display
-- @param players table: Array of player records {name, class, role, score}
-- @return table: Sorted array of player records
function CT.SortPlayersByRoleAndScore(players)
  local sorted = {}
  for i, player in ipairs(players) do
    table.insert(sorted, player)
  end
  
  -- Define role order: Tanks -> Healers -> Melee -> Ranged
  local roleOrder = {TANKS = 1, HEALERS = 2, MELEE = 3, RANGED = 4}
  
  table.sort(sorted, function(a, b)
    -- Primary: Role
    local roleA = roleOrder[a.role] or 999
    local roleB = roleOrder[b.role] or 999
    if roleA ~= roleB then return roleA < roleB end
    
    -- Secondary: Score (descending - highest first)
    if a.score ~= b.score then return a.score > b.score end
    
    -- Tertiary: Name (alphabetical)
    return a.name < b.name
  end)
  
  return sorted
end

-- Capture current raid consume scores and create a tracking record
-- This is called when a pull timer is detected (future implementation)
-- For now, this can be called manually for testing
function CT.CaptureConsumesSnapshot()
  -- Ensure saved variables are initialized
  CT.EnsureSavedVariables()
  
  -- Get raid/encounter selection from main UI
  -- TODO: This function needs to be implemented in the main UI module
  local raid, encounter = OGRH.GetSelectedRaidAndEncounter()
  if not raid or not encounter then
    OGRH.Msg("Cannot capture consume scores: No raid/encounter selected.")
    return
  end
  
  -- Check if OGRH_Consumables profile exists
  if not CT.CheckForOGRHProfile() then
    OGRH.Msg("Cannot capture consume scores: OGRH_Consumables profile not found in RABuffs.")
    return
  end
  
  -- Load the OGRH_Consumables profile bars
  local profileKey = GetCVar("realmName") .. "." .. UnitName("player") .. ".OGRH_Consumables"
  local profileBars = RABui_Settings.Layout[profileKey]
  
  if not profileBars or table.getn(profileBars) == 0 then
    OGRH.Msg("Cannot capture consume scores: OGRH_Consumables profile has no bars configured.")
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
  
  -- Calculate scores for all raid members
  local players = {}
  for playerName, data in pairs(raidData) do
    local score, err, details = CT.CalculatePlayerScore(playerName, data.class, raidData)
    local role = OGRH_SV.roles and OGRH_SV.roles[playerName] or "UNKNOWN"
    
    table.insert(players, {
      name = playerName,
      class = data.class,
      role = role,
      score = score or 0
    })
  end
  
  -- Create tracking record with current timestamp
  local timestamp = time()
  local record = {
    timestamp = timestamp,
    date = date("%m/%d", timestamp),
    time = date("%H:%M", timestamp),
    raid = raid,
    encounter = encounter,
    players = players,
    groupSize = GetNumRaidMembers()
  }
  
  -- Write to combat log if enabled and SuperWoW available
  if OGRH_SV.consumesTracking.logToCombatLog and CT.IsSuperWoWAvailable() then
    local success, err = CT.WriteConsumesToCombatLog(record)
    if not success then
      OGRH.Msg("|cffff8800Warning:|r Failed to write to combat log: " .. (err or "Unknown error"))
    end
  end
  
  -- Insert at beginning of history (newest first)
  table.insert(OGRH_SV.consumesTracking.history, 1, record)
  
  -- Trim to 50 records max
  while table.getn(OGRH_SV.consumesTracking.history) > 50 do
    table.remove(OGRH_SV.consumesTracking.history)
  end
  
  -- Refresh UI if tracking panel is open
  CT.RefreshTrackingHistoryLists()
  
  -- Announce to chat
  OGRH.Msg(string.format("Captured consume scores for %s - %s (%d players)", 
    raid, encounter, table.getn(players)))
end

-- ============================================================================
-- Phase 3: Pull Detection System
-- ============================================================================

-- Schedule a capture timer based on pull duration
-- @param pullDuration number: Total pull timer duration in seconds
function CT.ScheduleCaptureTimer(pullDuration)
  local secondsBeforePull = OGRH_SV.consumesTracking.secondsBeforePull or 2
  local captureDelay = pullDuration - secondsBeforePull
  
  -- If pull is too short, capture immediately
  if captureDelay <= 0 then
    CT.CaptureConsumesSnapshot()
    return
  end
  
  -- Create timer frame if it doesn't exist
  if not CT.captureTimerFrame then
    CT.captureTimerFrame = CreateFrame("Frame")
  end
  
  -- Set up timer
  local startTime = GetTime()
  local targetTime = startTime + captureDelay
  CT.captureScheduled = true
  
  CT.captureTimerFrame:SetScript("OnUpdate", function()
    local now = GetTime()
    if now >= targetTime then
      -- Time to capture!
      this:SetScript("OnUpdate", nil)
      CT.captureScheduled = false
      CT.CaptureConsumesSnapshot()
    end
  end)
end

-- Event handler for BigWigs pull timer detection
-- This function is called on CHAT_MSG_ADDON events
function CT.OnPullTimerDetected()
  if event ~= "CHAT_MSG_ADDON" then return end
  
  -- Ensure saved variables exist
  if not OGRH_SV or not OGRH_SV.consumesTracking then return end
  
  -- Check if track on pull is enabled
  if not OGRH_SV.consumesTracking.trackOnPull then return end
  
  -- Prevent duplicate captures for the same pull
  if CT.captureScheduled then return end
  
  -- arg1 = prefix ("BigWigs")
  -- arg2 = message ("PulltimerSync 10" or "PulltimerBroadcastSync 10")
  -- arg3 = channel ("RAID" or "PARTY")
  -- arg4 = sender (player name)
  
  if arg1 == "BigWigs" and arg2 and arg4 then
    local message = arg2
    local sender = arg4
    
    -- Parse pull timer duration from message
    local _, _, duration = string.find(message, "PulltimerSync%s+(%d+)")
    if not duration then
      _, _, duration = string.find(message, "PulltimerBroadcastSync%s+(%d+)")
    end
    
    if duration then
      local pullDuration = tonumber(duration)
      if pullDuration and pullDuration > 0 then
        -- Store pull info
        CT.currentPullNumber = pullDuration
        CT.currentPullRequester = sender
        CT.currentPullStartTime = GetTime()
        
        -- Schedule the capture
        CT.ScheduleCaptureTimer(pullDuration)
      end
    end
  end
end

-- Select a history record for viewing
-- @param recordIndex number: Index in the history array
function CT.SelectHistoryRecord(recordIndex)
  -- Update selected index
  CT.selectedRecordIndex = recordIndex
  
  -- Highlight selected item in history list
  CT.RefreshHistoryListSelection()
  
  -- Populate player scores list
  CT.RefreshPlayerScoresList(recordIndex)
end

-- Delete a history record (with confirmation)
-- @param recordIndex number: Index in the history array
function CT.DeleteHistoryRecord(recordIndex)
  local record = OGRH_SV.consumesTracking.history[recordIndex]
  if not record then return end
  
  -- Show confirmation dialog
  local dialog = OGST.CreateDialog({
    title = "Delete Record",
    width = 400,
    height = 150,
    content = string.format("Delete tracking record from %s %s %s %s?", 
      record.date, record.time, record.raid, record.encounter),
    buttons = {
      {
        text = "Delete", 
        onClick = function()
          CT.ConfirmDeleteRecord(recordIndex)
        end
      },
      {
        text = "Cancel", 
        onClick = function()
          -- Dialog closes automatically
        end
      }
    },
    escapeCloses = true
  })
end

-- Actually delete a record after confirmation
-- @param recordIndex number: Index in the history array
function CT.ConfirmDeleteRecord(recordIndex)
  -- Remove record from history
  table.remove(OGRH_SV.consumesTracking.history, recordIndex)
  
  -- Clear selection
  CT.selectedRecordIndex = nil
  
  -- Refresh both lists
  CT.RefreshTrackingHistoryLists()
  
  OGRH.Msg("Tracking record deleted.")
end

-- Refresh the history list (left panel)
-- Rebuilds the left panel list with current history records
function CT.RefreshHistoryList()
  if not CT.historyListFrame then return end
  
  -- Clear existing items using OGST API
  CT.historyListFrame:Clear()
  
  -- Get history records
  local history = OGRH_SV.consumesTracking.history
  if not history or table.getn(history) == 0 then
    -- Show empty message using OGST API
    local emptyItem = CT.historyListFrame:AddItem({
      text = "|cff808080No tracking records.|r"
    })
    return
  end
  
  -- Add list items for each record using OGST API
  for i, record in ipairs(history) do
    -- Create display text
    local displayText = string.format("%s %s %s %s", 
      record.date, record.time, record.raid, record.encounter)
    
    -- Add item using OGST API
    local item = CT.historyListFrame:AddItem({
      text = displayText
    })
    
    -- Store record data on frame (CRITICAL: closure scoping pattern)
    item.recordIndex = i
    item.timestamp = record.timestamp
    
    -- Highlight if selected
    if CT.selectedRecordIndex == i then
      item:SetBackdropColor(0.3, 0.3, 0.5, 0.5)
    end
    
    -- OnClick handler (uses 'this')
    item:SetScript("OnClick", function()
      CT.SelectHistoryRecord(this.recordIndex)
    end)
    
    -- Add delete button using OGST API
    OGST.AddListItemButtons(item, i, table.getn(history), 
      nil, nil,  -- no up/down callbacks
      function()  -- delete callback (uses 'this')
        CT.DeleteHistoryRecord(this:GetParent().recordIndex)
      end,
      true  -- hide up/down buttons
    )
  end
end

-- Refresh the player scores list (right panel)
-- @param recordIndex number: Index in the history array
function CT.RefreshPlayerScoresList(recordIndex)
  if not CT.playerScoresListFrame then return end
  
  -- Clear existing items using OGST API
  CT.playerScoresListFrame:Clear()
  
  if not recordIndex then
    CT.ClearPlayerScoresList()
    return
  end
  
  -- Get the selected record
  local record = OGRH_SV.consumesTracking.history[recordIndex]
  if not record or not record.players then
    CT.ClearPlayerScoresList()
    return
  end
  
  -- Sort players by role and score
  local sortedPlayers = CT.SortPlayersByRoleAndScore(record.players)
  
  if table.getn(sortedPlayers) == 0 then
    local emptyItem = CT.playerScoresListFrame:AddItem({
      text = "|cff808080No players in record.|r"
    })
    return
  end
  
  -- Add list items for each player using OGST API
  for i, player in ipairs(sortedPlayers) do
    -- Build display text with role and score
    local roleText = player.role or "UNKNOWN"
    local displayText = string.format("[%s] %d  %s", roleText, player.score, player.name)
    
    -- Add item using OGST API
    local item = CT.playerScoresListFrame:AddItem({
      text = displayText
    })
    
    -- Store player data on frame
    item.playerName = player.name
    item.playerClass = player.class
    
    -- Apply class color to the player name using OGRH's cached class data
    if item.text then
      local coloredText = string.format("[%s] %d  %s", 
        roleText, player.score, OGRH.ColorName(player.name))
      item.text:SetText(coloredText)
    end
  end
end

-- Refresh history list selection highlighting
function CT.RefreshHistoryListSelection()
  CT.RefreshHistoryList()
end

-- Clear the player scores list
function CT.ClearPlayerScoresList()
  if not CT.playerScoresListFrame then return end
  
  -- Clear existing items using OGST API
  CT.playerScoresListFrame:Clear()
  
  -- Show default message using OGST API
  local emptyItem = CT.playerScoresListFrame:AddItem({
    text = "|cff808080Select a tracking record\nto view player scores.|r"
  })
end

-- Refresh both tracking history lists together
function CT.RefreshTrackingHistoryLists()
  if CT.historyListFrame then
    CT.RefreshHistoryList()
    
    if CT.selectedRecordIndex then
      CT.RefreshPlayerScoresList(CT.selectedRecordIndex)
    else
      CT.ClearPlayerScoresList()
    end
  end
end

-- ============================================================================
-- Testing Functions (Phase 1)
-- ============================================================================

-- Manually capture a snapshot (for testing Phase 1)
-- Can be called via: /script OGRH.ConsumesTracking.TestCaptureSnapshot()
function OGRH.ConsumesTracking.TestCaptureSnapshot()
  CT.CaptureConsumesSnapshot()
end

-- List all history records (for testing Phase 1)
-- Can be called via: /script OGRH.ConsumesTracking.TestListHistory()
function OGRH.ConsumesTracking.TestListHistory()
  CT.EnsureSavedVariables()
  
  local history = OGRH_SV.consumesTracking.history
  local count = table.getn(history)
  
  OGRH.Msg(string.format("=== Tracking History (%d records) ===", count))
  
  if count == 0 then
    OGRH.Msg("No records found.")
    return
  end
  
  for i, record in ipairs(history) do
    OGRH.Msg(string.format("%d. %s %s - %s %s (%d players)", 
      i, record.date, record.time, record.raid, record.encounter, 
      table.getn(record.players)))
  end
end

-- Delete a history record by index (for testing Phase 1)
-- Can be called via: /script OGRH.ConsumesTracking.TestDeleteRecord(1)
function OGRH.ConsumesTracking.TestDeleteRecord(index)
  CT.EnsureSavedVariables()
  
  local history = OGRH_SV.consumesTracking.history
  if not history[index] then
    OGRH.Msg(string.format("Error: Record %d does not exist.", index))
    return
  end
  
  local record = history[index]
  OGRH.Msg(string.format("Deleting record %d: %s %s - %s %s", 
    index, record.date, record.time, record.raid, record.encounter))
  
  table.remove(history, index)
  OGRH.Msg("Record deleted.")
end

-- Clear all history records (for testing Phase 1)
-- Can be called via: /script OGRH.ConsumesTracking.TestClearHistory()
function OGRH.ConsumesTracking.TestClearHistory()
  CT.EnsureSavedVariables()
  
  local count = table.getn(OGRH_SV.consumesTracking.history)
  OGRH_SV.consumesTracking.history = {}
  
  OGRH.Msg(string.format("Cleared %d history records.", count))
end

-- ============================================================================
-- Initialization
-- ============================================================================

-- Call initialization directly
CT.Initialize()
-- Debug/Info
-- ============================================================================

OGRH.Msg("ConsumesTracking module loaded (v1.0.0)")
