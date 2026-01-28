--[[
  OGRH_Consumes.lua
  
  Consume management for OG-RaidHelper
  Manages consumable items with primary/secondary item tracking
  
  Version: 1.0.0
]]--

if not OGRH then
  DEFAULT_CHAT_FRAME:AddMessage("ERROR: OGRH_Consumes loaded before OGRH_Core!")
  return
end

-- Consumes Window
function OGRH.ShowConsumesSettings()
  OGRH.EnsureSV()
  OGRH.CloseAllWindows("OGRH_ConsumesFrame")
  
  if OGRH_ConsumesFrame then
    OGRH_ConsumesFrame:Show()
    OGRH.RefreshConsumesSettings()
    return
  end
  
  local frame = CreateFrame("Frame", "OGRH_ConsumesFrame", UIParent)
  frame:SetWidth(500)
  frame:SetHeight(450)
  frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  frame:SetFrameStrata("DIALOG")
  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function() frame:StartMoving() end)
  frame:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
  
  -- Backdrop
  frame:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 12,
    insets = {left = 4, right = 4, top = 4, bottom = 4}
  })
  frame:SetBackdropColor(0, 0, 0, 0.85)
  
  -- Register ESC key handler
  OGRH.MakeFrameCloseOnEscape(frame, "OGRH_ConsumesFrame")
  
  -- Title
  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOP", 0, -15)
  title:SetText("Consume Settings")
  
  -- Close button
  local closeBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  closeBtn:SetWidth(60)
  closeBtn:SetHeight(24)
  closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -10)
  closeBtn:SetText("Close")
  OGRH.StyleButton(closeBtn)
  closeBtn:SetScript("OnClick", function() frame:Hide() end)
  
  -- Instructions
  local instructions = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  instructions:SetPoint("TOPLEFT", 20, -45)
  instructions:SetText("Configure consumable items:")
  
  -- Create scroll list using template
  local listWidth = frame:GetWidth() - 34
  local listHeight = frame:GetHeight() - 85
  local outerFrame, scrollFrame, scrollChild, scrollBar, contentWidth = OGRH.CreateStyledScrollList(frame, listWidth, listHeight)
  outerFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 17, -75)
  
  frame.scrollChild = scrollChild
  frame.scrollFrame = scrollFrame
  frame.scrollBar = scrollBar
  
  frame:Show()
  OGRH.RefreshConsumesSettings()
end

-- Refresh the consumes settings list
function OGRH.RefreshConsumesSettings()
  if not OGRH_ConsumesFrame then return end
  
  local scrollChild = OGRH_ConsumesFrame.scrollChild
  
  -- Clear existing rows
  if scrollChild.rows then
    for _, row in ipairs(scrollChild.rows) do
      row:Hide()
      row:SetParent(nil)
    end
  end
  scrollChild.rows = {}
  
  OGRH.EnsureSV()
  local items = OGRH.SVM.Get("consumes") or {}
  
  local yOffset = -5
  local rowHeight = OGRH.LIST_ITEM_HEIGHT
  local rowSpacing = OGRH.LIST_ITEM_SPACING
  
  local contentWidth = OGRH_ConsumesFrame.scrollChild:GetWidth()
  
  for i, itemData in ipairs(items) do
    local row = OGRH.CreateStyledListItem(scrollChild, contentWidth, OGRH.LIST_ITEM_HEIGHT, "Button")
    row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, yOffset)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    
    local idx = i
    
    -- Right-click to edit
    row:SetScript("OnClick", function()
      if arg1 == "RightButton" then
        OGRH.ShowEditConsumeDialog(idx)
      end
    end)
    
    -- Add up/down/delete buttons using template
    local deleteBtn, downBtn, upBtn = OGRH.AddListItemButtons(
      row,
      idx,
      table.getn(items),
      function()
        -- Move up
        local consumes = OGRH.SVM.Get("consumes") or {}
        local temp = consumes[idx - 1]
        consumes[idx - 1] = consumes[idx]
        consumes[idx] = temp
        OGRH.SVM.Set("consumes", nil, consumes, {syncLevel = "BATCH", componentType = "consumes"})
        OGRH.RefreshConsumesSettings()
      end,
      function()
        -- Move down
        local consumes = OGRH.SVM.Get("consumes") or {}
        local temp = consumes[idx + 1]
        consumes[idx + 1] = consumes[idx]
        consumes[idx] = temp
        OGRH.SVM.Set("consumes", nil, consumes, {syncLevel = "BATCH", componentType = "consumes"})
        OGRH.RefreshConsumesSettings()
      end,
      function()
        -- Delete
        local consumes = OGRH.SVM.Get("consumes") or {}
        table.remove(consumes, idx)
        OGRH.SVM.Set("consumes", nil, consumes, {syncLevel = "BATCH", componentType = "consumes"})
        OGRH.RefreshConsumesSettings()
      end
    )
    
    -- Item names display (Primary / Secondary)
    local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    nameText:SetPoint("LEFT", row, "LEFT", 5, 0)
    nameText:SetPoint("RIGHT", upBtn, "LEFT", -10, 0)
    nameText:SetJustifyH("LEFT")
    
    local primaryName = itemData.primaryName or ("Item " .. (itemData.primaryId or "?"))
    local secondaryName = ""
    if itemData.secondaryId and itemData.secondaryId > 0 then
      secondaryName = " / " .. (itemData.secondaryName or ("Item " .. itemData.secondaryId))
    end
    nameText:SetText(primaryName .. secondaryName)
    
    table.insert(scrollChild.rows, row)
    yOffset = yOffset - rowHeight - rowSpacing
  end
  
  -- Add "Add Consume" placeholder row at the bottom
  local addItemBtn = OGRH.CreateStyledListItem(scrollChild, contentWidth, OGRH.LIST_ITEM_HEIGHT, "Button")
  addItemBtn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, yOffset)
  
  -- Text
  local addText = addItemBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  addText:SetPoint("CENTER", addItemBtn, "CENTER", 0, 0)
  addText:SetText("|cff00ff00Add Consume|r")
  
  addItemBtn:SetScript("OnClick", function()
    OGRH.ShowAddConsumeDialog()
  end)
  
  table.insert(scrollChild.rows, addItemBtn)
  yOffset = yOffset - rowHeight
  
  -- Update scroll child height
  local contentHeight = math.abs(yOffset) + 5
  scrollChild:SetHeight(math.max(contentHeight, 1))
  
  -- Update scrollbar visibility
  local scrollBar = OGRH_ConsumesFrame.scrollBar
  local scrollFrame = OGRH_ConsumesFrame.scrollFrame
  local scrollFrameHeight = scrollFrame:GetHeight()
  
  if contentHeight > scrollFrameHeight then
    scrollBar:Show()
    scrollBar:SetMinMaxValues(0, contentHeight - scrollFrameHeight)
    scrollBar:SetValue(0)
  else
    scrollBar:Hide()
  end
  scrollFrame:SetVerticalScroll(0)
end

-- Show add consume dialog
function OGRH.ShowAddConsumeDialog()
  if OGRH_AddConsumeDialog then
    OGRH_AddConsumeDialog:Show()
    return
  end
  
  local dialog = CreateFrame("Frame", "OGRH_AddConsumeDialog", UIParent)
  dialog:SetWidth(280)
  dialog:SetHeight(180)
  dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  dialog:SetFrameStrata("FULLSCREEN_DIALOG")
  dialog:EnableMouse(true)
  dialog:SetMovable(true)
  dialog:RegisterForDrag("LeftButton")
  dialog:SetScript("OnDragStart", function() dialog:StartMoving() end)
  dialog:SetScript("OnDragStop", function() dialog:StopMovingOrSizing() end)
  
  -- Backdrop
  dialog:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 12,
    insets = {left = 4, right = 4, top = 4, bottom = 4}
  })
  dialog:SetBackdropColor(0, 0, 0, 0.9)
  
  -- Register ESC key handler
  OGRH.MakeFrameCloseOnEscape(dialog, "OGRH_AddConsumeDialog")
  
  -- Title
  local title = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOP", 0, -15)
  title:SetText("Add Consume")
  
  -- Primary ID label
  local primaryLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  primaryLabel:SetPoint("TOPLEFT", 20, -50)
  primaryLabel:SetText("Primary ID:")
  
  -- Primary ID input
  local primaryInput = CreateFrame("EditBox", nil, dialog)
  primaryInput:SetPoint("LEFT", primaryLabel, "RIGHT", 10, 0)
  primaryInput:SetWidth(120)
  primaryInput:SetHeight(25)
  primaryInput:SetAutoFocus(false)
  primaryInput:SetFontObject(ChatFontNormal)
  primaryInput:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 12,
    insets = {left = 4, right = 4, top = 4, bottom = 4}
  })
  primaryInput:SetBackdropColor(0, 0, 0, 0.8)
  primaryInput:SetTextInsets(8, 8, 0, 0)
  primaryInput:SetScript("OnEscapePressed", function() primaryInput:ClearFocus() end)
  dialog.primaryInput = primaryInput
  
  -- Secondary ID label
  local secondaryLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  secondaryLabel:SetPoint("TOPLEFT", 20, -90)
  secondaryLabel:SetText("Secondary ID:")
  
  -- Secondary ID input
  local secondaryInput = CreateFrame("EditBox", nil, dialog)
  secondaryInput:SetPoint("LEFT", secondaryLabel, "RIGHT", 10, 0)
  secondaryInput:SetWidth(120)
  secondaryInput:SetHeight(25)
  secondaryInput:SetAutoFocus(false)
  secondaryInput:SetFontObject(ChatFontNormal)
  secondaryInput:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 12,
    insets = {left = 4, right = 4, top = 4, bottom = 4}
  })
  secondaryInput:SetBackdropColor(0, 0, 0, 0.8)
  secondaryInput:SetTextInsets(8, 8, 0, 0)
  secondaryInput:SetScript("OnEscapePressed", function() secondaryInput:ClearFocus() end)
  dialog.secondaryInput = secondaryInput
  
  -- Cancel button
  local cancelBtn = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
  cancelBtn:SetWidth(80)
  cancelBtn:SetHeight(25)
  cancelBtn:SetPoint("BOTTOMRIGHT", -20, 15)
  cancelBtn:SetText("Cancel")
  cancelBtn:SetScript("OnClick", function()
    dialog:Hide()
  end)
  
  -- Add button
  local addBtn = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
  addBtn:SetWidth(80)
  addBtn:SetHeight(25)
  addBtn:SetPoint("RIGHT", cancelBtn, "LEFT", -10, 0)
  addBtn:SetText("Add")
  addBtn:SetScript("OnClick", function()
    local primaryText = primaryInput:GetText()
    local secondaryText = secondaryInput:GetText()
    
    local primaryId = tonumber(primaryText)
    local secondaryId = tonumber(secondaryText)
    
    if not primaryId or primaryId <= 0 then
      OGRH.Msg("Invalid Primary Item ID. Please enter a valid number.")
      return
    end
    
    -- Secondary is optional - allow empty or 0
    if secondaryText == "" then
      secondaryId = 0
    elseif not secondaryId or secondaryId < 0 then
      OGRH.Msg("Invalid Secondary Item ID. Please enter a valid number or leave empty.")
      return
    end
    
    -- Get item names from game
    local primaryName, primaryLink = GetItemInfo(primaryId)
    local secondaryName = nil
    if secondaryId > 0 then
      secondaryName, _ = GetItemInfo(secondaryId)
    end
    
    -- Add to list
    OGRH.EnsureSV()
    local consumes = OGRH.SVM.Get("consumes") or {}
    local consumeData = {
      primaryId = primaryId,
      primaryName = primaryName or ("Item " .. primaryId)
    }
    if secondaryId > 0 then
      consumeData.secondaryId = secondaryId
      consumeData.secondaryName = secondaryName or ("Item " .. secondaryId)
    end
    table.insert(consumes, consumeData)
    OGRH.SVM.Set("consumes", nil, consumes, {syncLevel = "BATCH", componentType = "consumes"})
    
    -- Clear inputs
    primaryInput:SetText("")
    secondaryInput:SetText("")
    
    -- Refresh settings window
    OGRH.RefreshConsumesSettings()
    
    dialog:Hide()
    local msg = "Added consume: " .. (primaryName or ("Item " .. primaryId))
    if secondaryId > 0 then
      msg = msg .. " / " .. (secondaryName or ("Item " .. secondaryId))
    end
    OGRH.Msg(msg)
  end)
  
  dialog:Show()
end

-- Show edit consume dialog
function OGRH.ShowEditConsumeDialog(itemIndex)
  OGRH.EnsureSV()
  local consumes = OGRH.SVM.Get("consumes") or {}
  local itemData = consumes[itemIndex]
  if not itemData then return end
  
  if OGRH_EditConsumeDialog then
    OGRH_EditConsumeDialog.itemIndex = itemIndex
    OGRH_EditConsumeDialog.primaryInput:SetText(tostring(itemData.primaryId))
    OGRH_EditConsumeDialog.secondaryInput:SetText((itemData.secondaryId and itemData.secondaryId > 0) and tostring(itemData.secondaryId) or "")
    OGRH_EditConsumeDialog:Show()
    return
  end
  
  local dialog = CreateFrame("Frame", "OGRH_EditConsumeDialog", UIParent)
  dialog:SetWidth(280)
  dialog:SetHeight(180)
  dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  dialog:SetFrameStrata("FULLSCREEN_DIALOG")
  dialog:EnableMouse(true)
  dialog:SetMovable(true)
  dialog:RegisterForDrag("LeftButton")
  dialog:SetScript("OnDragStart", function() dialog:StartMoving() end)
  dialog:SetScript("OnDragStop", function() dialog:StopMovingOrSizing() end)
  dialog.itemIndex = itemIndex
  
  -- Backdrop
  dialog:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 12,
    insets = {left = 4, right = 4, top = 4, bottom = 4}
  })
  dialog:SetBackdropColor(0, 0, 0, 0.9)
  
  -- Register ESC key handler
  OGRH.MakeFrameCloseOnEscape(dialog, "OGRH_EditConsumeDialog")
  
  -- Title
  local title = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOP", 0, -15)
  title:SetText("Edit Consume")
  
  -- Primary ID label
  local primaryLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  primaryLabel:SetPoint("TOPLEFT", 20, -50)
  primaryLabel:SetText("Primary ID:")
  
  -- Primary ID input
  local primaryInput = CreateFrame("EditBox", nil, dialog)
  primaryInput:SetPoint("LEFT", primaryLabel, "RIGHT", 10, 0)
  primaryInput:SetWidth(120)
  primaryInput:SetHeight(25)
  primaryInput:SetAutoFocus(false)
  primaryInput:SetFontObject(ChatFontNormal)
  primaryInput:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 12,
    insets = {left = 4, right = 4, top = 4, bottom = 4}
  })
  primaryInput:SetBackdropColor(0, 0, 0, 0.8)
  primaryInput:SetTextInsets(8, 8, 0, 0)
  primaryInput:SetText(tostring(itemData.primaryId))
  primaryInput:SetScript("OnEscapePressed", function() primaryInput:ClearFocus() end)
  dialog.primaryInput = primaryInput
  
  -- Secondary ID label
  local secondaryLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  secondaryLabel:SetPoint("TOPLEFT", 20, -90)
  secondaryLabel:SetText("Secondary ID:")
  
  -- Secondary ID input
  local secondaryInput = CreateFrame("EditBox", nil, dialog)
  secondaryInput:SetPoint("LEFT", secondaryLabel, "RIGHT", 10, 0)
  secondaryInput:SetWidth(120)
  secondaryInput:SetHeight(25)
  secondaryInput:SetAutoFocus(false)
  secondaryInput:SetFontObject(ChatFontNormal)
  secondaryInput:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 12,
    insets = {left = 4, right = 4, top = 4, bottom = 4}
  })
  secondaryInput:SetBackdropColor(0, 0, 0, 0.8)
  secondaryInput:SetTextInsets(8, 8, 0, 0)
  secondaryInput:SetText((itemData.secondaryId and itemData.secondaryId > 0) and tostring(itemData.secondaryId) or "")
  secondaryInput:SetScript("OnEscapePressed", function() secondaryInput:ClearFocus() end)
  dialog.secondaryInput = secondaryInput
  
  -- Cancel button
  local cancelBtn = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
  cancelBtn:SetWidth(80)
  cancelBtn:SetHeight(25)
  cancelBtn:SetPoint("BOTTOMRIGHT", -20, 15)
  cancelBtn:SetText("Cancel")
  cancelBtn:SetScript("OnClick", function()
    dialog:Hide()
  end)
  
  -- Save button
  local saveBtn = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
  saveBtn:SetWidth(80)
  saveBtn:SetHeight(25)
  saveBtn:SetPoint("RIGHT", cancelBtn, "LEFT", -10, 0)
  saveBtn:SetText("Save")
  saveBtn:SetScript("OnClick", function()
    local primaryText = primaryInput:GetText()
    local secondaryText = secondaryInput:GetText()
    
    local primaryId = tonumber(primaryText)
    local secondaryId = tonumber(secondaryText)
    
    if not primaryId or primaryId <= 0 then
      OGRH.Msg("Invalid Primary Item ID. Please enter a valid number.")
      return
    end
    
    -- Secondary is optional - allow empty or 0
    if secondaryText == "" then
      secondaryId = 0
    elseif not secondaryId or secondaryId < 0 then
      OGRH.Msg("Invalid Secondary Item ID. Please enter a valid number or leave empty.")
      return
    end
    
    -- Get item names from game
    local primaryName, primaryLink = GetItemInfo(primaryId)
    local secondaryName = nil
    if secondaryId > 0 then
      secondaryName, _ = GetItemInfo(secondaryId)
    end
    
    -- Update item
    local consumes = OGRH.SVM.Get("consumes") or {}
    local consumeData = {
      primaryId = primaryId,
      primaryName = primaryName or ("Item " .. primaryId)
    }
    if secondaryId > 0 then
      consumeData.secondaryId = secondaryId
      consumeData.secondaryName = secondaryName or ("Item " .. secondaryId)
    end
    consumes[dialog.itemIndex] = consumeData
    OGRH.SVM.Set("consumes", nil, consumes, {syncLevel = "BATCH", componentType = "consumes"})
    
    -- Refresh settings window
    OGRH.RefreshConsumesSettings()
    
    dialog:Hide()
    local msg = "Updated consume: " .. (primaryName or ("Item " .. primaryId))
    if secondaryId > 0 then
      msg = msg .. " / " .. (secondaryName or ("Item " .. secondaryId))
    end
    OGRH.Msg(msg)
  end)
  
  dialog:Show()
end

--[[
  Consume Monitor Window
  Tracks consume buffs on raid members
]]--

-- Buff cache for consume checking
OGRH.ConsumeBuffCache = {}
OGRH.ConsumeBuffLastUpdated = {}

-- Check if unit has a consume buff by spell ID
local function HasConsumeBuff(unit, spellId)
  if not unit or not UnitExists(unit) or not spellId then
    return false
  end
  
  -- Check cache
  local cTime = GetTime()
  if OGRH.ConsumeBuffCache[unit] and OGRH.ConsumeBuffLastUpdated[unit] and 
     OGRH.ConsumeBuffLastUpdated[unit] > cTime - 3 then
    -- Use cache
    if OGRH.ConsumeBuffCache[unit][spellId] then
      return true
    end
  else
    -- Update cache
    OGRH.ConsumeBuffCache[unit] = {}
    OGRH.ConsumeBuffLastUpdated[unit] = cTime
    
    local i = 1
    while true do
      local texture, stacks, buffSpellId = UnitBuff(unit, i)
      if not texture then break end
      
      if buffSpellId then
        OGRH.ConsumeBuffCache[unit][buffSpellId] = true
      end
      
      i = i + 1
    end
    
    if OGRH.ConsumeBuffCache[unit][spellId] then
      return true
    end
  end
  
  return false
end

-- Get spell ID from item ID
local function GetSpellIdFromItem(itemId)
  -- Spell IDs for common consumables - extend as needed
  local itemToSpell = {
    -- Greater Protection Potions
    [13457] = 17543, -- Greater Fire Protection Potion
    [13456] = 17544, -- Greater Frost Protection Potion  
    [13458] = 17546, -- Greater Nature Protection Potion
    [13459] = 17548, -- Greater Shadow Protection Potion
    [13461] = 17549, -- Greater Arcane Protection Potion
    
    -- Lesser Protection Potions
    [6049] = 7233,   -- Fire Protection Potion
    [6050] = 7239,   -- Frost Protection Potion
    [6052] = 7254,   -- Nature Protection Potion
    [6048] = 10278,  -- Shadow Protection Potion
  }
  
  return itemToSpell[itemId]
end

function OGRH.ShowConsumeMonitor()
  OGRH.EnsureSV()
  
  if not OGRH_SV.monitorConsumes then
    return
  end
  
  if OGRH_ConsumeMonitorFrame then
    -- Force immediate update when frame already exists
    if OGRH_ConsumeMonitorFrame.Update then
      OGRH_ConsumeMonitorFrame.Update()
    end
    -- Manually register and reposition in case OnShow doesn't fire
    if OGRH.RegisterAuxiliaryPanel then
      OGRH.RegisterAuxiliaryPanel(OGRH_ConsumeMonitorFrame, 10)
    end
    if OGRH.RepositionAuxiliaryPanels then
      OGRH.RepositionAuxiliaryPanels()
    end
    return
  end
  
  local frame = CreateFrame("Frame", "OGRH_ConsumeMonitorFrame", UIParent)
  frame:SetWidth(180)
  frame:SetHeight(100)
  frame:SetFrameStrata("MEDIUM")
  frame:EnableMouse(true)
  
  frame:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 12,
    insets = {left = 2, right = 2, top = 2, bottom = 2}
  })
  frame:SetBackdropColor(0, 0, 0, 0.85)
  
  -- Register with auxiliary panel system (priority 10 = consume monitor goes first)
  frame:SetScript("OnShow", function()
    if OGRH.RegisterAuxiliaryPanel then
      OGRH.RegisterAuxiliaryPanel(this, 10)
    end
  end)
  
  frame:SetScript("OnHide", function()
    if OGRH.UnregisterAuxiliaryPanel then
      OGRH.UnregisterAuxiliaryPanel(this)
    end
  end)
  
  -- Consume rows container
  frame.consumeRows = {}
  
  -- Update function
  frame.Update = function()
    if not OGRH_SV.monitorConsumes then
      frame:Hide()
      return
    end
    
    -- Hide if in combat
    if UnitAffectingCombat("player") then
      frame:Hide()
      return
    end
    
    -- Get current encounter
    if not OGRH.GetCurrentEncounter then
      frame:Hide()
      return
    end
    
    local currentRaid, currentEncounter = OGRH.GetCurrentEncounter()
    if not currentRaid or not currentEncounter then
      frame:Hide()
      return
    end
    
    -- Get encounter roles
    local roles = OGRH_SV.encounterMgmt and OGRH_SV.encounterMgmt.roles
    if not roles or not roles[currentRaid] or not roles[currentRaid][currentEncounter] then
      frame:Hide()
      return
    end
    
    local encounterRoles = roles[currentRaid][currentEncounter]
    local column1 = encounterRoles.column1 or {}
    local column2 = encounterRoles.column2 or {}
    
    -- Find consume check role
    local consumeRole = nil
    for i = 1, table.getn(column1) do
      if column1[i].isConsumeCheck then
        consumeRole = column1[i]
        break
      end
    end
    if not consumeRole then
      for i = 1, table.getn(column2) do
        if column2[i].isConsumeCheck then
          consumeRole = column2[i]
          break
        end
      end
    end
    
    if not consumeRole or not consumeRole.consumes then
      frame:Hide()
      return
    end
    
    -- Clear existing rows
    for _, row in ipairs(frame.consumeRows) do
      row:Hide()
    end
    
    -- Get raid size
    local numRaid = GetNumRaidMembers()
    if numRaid == 0 then
      frame:Hide()
      return
    end
    
    -- Build consume rows
    local yOffset = -6
    local rowIndex = 1
    
    for i = 1, (consumeRole.slots or 1) do
      if consumeRole.consumes[i] then
        local consumeData = consumeRole.consumes[i]
        local primarySpellId = GetSpellIdFromItem(consumeData.primaryId)
        local secondarySpellId = consumeData.allowAlternate and consumeData.secondaryId and GetSpellIdFromItem(consumeData.secondaryId)
        
        if primarySpellId then
          -- Count buffed players
          local buffedCount = 0
          local unbuffedPlayers = {}
          
          for j = 1, numRaid do
            local name = GetRaidRosterInfo(j)
            if name then
              local hasBuff = HasConsumeBuff("raid"..j, primarySpellId)
              if not hasBuff and secondarySpellId then
                hasBuff = HasConsumeBuff("raid"..j, secondarySpellId)
              end
              
              if hasBuff then
                buffedCount = buffedCount + 1
              else
                table.insert(unbuffedPlayers, name)
              end
            end
          end
          
          -- Create or reuse row
          if not frame.consumeRows[rowIndex] then
            local row = CreateFrame("Button", nil, frame)
            row:SetWidth(172)
            row:SetHeight(20)
            row:SetPoint("TOP", 0, yOffset)
            
            row:SetBackdrop({
              bgFile = "Interface/Tooltips/UI-Tooltip-Background",
              tile = true, tileSize = 16
            })
            row:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
            
            local text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            text:SetPoint("LEFT", 5, 0)
            row.text = text
            
            local count = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            count:SetPoint("RIGHT", -5, 0)
            row.count = count
            
            row:SetScript("OnEnter", function()
              row:SetBackdropColor(0.2, 0.2, 0.3, 0.8)
            end)
            
            row:SetScript("OnLeave", function()
              row:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
            end)
            
            row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            
            frame.consumeRows[rowIndex] = row
          end
          
          local row = frame.consumeRows[rowIndex]
          local itemName, _ = GetItemInfo(consumeData.primaryId)
          local displayName = itemName or consumeData.primaryName or "Unknown"
          
          -- Shorten consume name: "Greater" -> "G.", remove "Potion"
          displayName = string.gsub(displayName, "Greater ", "G. ")
          displayName = string.gsub(displayName, " Potion", "")
          
          row.text:SetText(displayName)
          
          -- Color code the count
          local color = "|cff00ff00"
          if buffedCount < numRaid then
            color = "|cffff0000"
          end
          row.count:SetText(color .. buffedCount .. "/" .. numRaid .. "|r")
          
          -- Store unbuffed players for reporting
          row.unbuffedPlayers = unbuffedPlayers
          row.consumeName = itemName or consumeData.primaryName
          row.primaryItemId = consumeData.primaryId
          row.secondaryItemId = consumeData.allowAlternate and consumeData.secondaryId or nil
          row.primarySpellId = primarySpellId
          row.secondarySpellId = secondarySpellId
          
          -- Click handler
          row:SetScript("OnClick", function()
            local button = arg1 or "LeftButton"
            
            if button == "RightButton" then
              -- Right-click: Use consume from inventory
              -- Check if player already has the buff
              local hasPrimaryBuff = HasConsumeBuff("player", row.primarySpellId)
              local hasSecondaryBuff = row.secondarySpellId and HasConsumeBuff("player", row.secondarySpellId)
              
              if hasPrimaryBuff or hasSecondaryBuff then
                OGRH.Msg("You already have " .. row.consumeName .. " buff")
                return
              end
              
              -- Try to use secondary first if allowed, then primary
              local itemToUse = nil
              local itemName = nil
              
              if row.secondaryItemId then
                -- Search for secondary item in bags
                for bag = 0, 4 do
                  for slot = 1, GetContainerNumSlots(bag) do
                    local link = GetContainerItemLink(bag, slot)
                    if link then
                      local _, _, itemId = string.find(link, "item:(%d+)")
                      if itemId and tonumber(itemId) == row.secondaryItemId then
                        itemToUse = {bag = bag, slot = slot}
                        itemName, _ = GetItemInfo(row.secondaryItemId)
                        break
                      end
                    end
                  end
                  if itemToUse then break end
                end
              end
              
              -- If secondary not found, try primary
              if not itemToUse and row.primaryItemId then
                for bag = 0, 4 do
                  for slot = 1, GetContainerNumSlots(bag) do
                    local link = GetContainerItemLink(bag, slot)
                    if link then
                      local _, _, itemId = string.find(link, "item:(%d+)")
                      if itemId and tonumber(itemId) == row.primaryItemId then
                        itemToUse = {bag = bag, slot = slot}
                        itemName, _ = GetItemInfo(row.primaryItemId)
                        break
                      end
                    end
                  end
                  if itemToUse then break end
                end
              end
              
              if itemToUse then
                UseContainerItem(itemToUse.bag, itemToUse.slot)
                OGRH.Msg("Using " .. (itemName or row.consumeName))
              else
                OGRH.Msg("You don't have " .. row.consumeName .. " in your bags")
              end
            else
              -- Left-click: Report missing players
              if table.getn(row.unbuffedPlayers) > 0 then
                -- Build colored player list
                local coloredPlayers = {}
                for _, playerName in ipairs(row.unbuffedPlayers) do
                  local playerClass = OGRH.GetPlayerClass and OGRH.GetPlayerClass(playerName)
                  local colorHex = OGRH.ClassColorHex and OGRH.ClassColorHex(playerClass) or "|cffffffff"
                  table.insert(coloredPlayers, colorHex .. playerName .. "|r")
                end
                
                -- Send compact announcement
                local canRW = OGRH.CanRW and OGRH.CanRW()
                local channel = canRW and "RAID_WARNING" or "RAID"
                
                local headerColor = OGRH.COLOR and OGRH.COLOR.HEADER or "|cff00ff00"
                SendChatMessage(headerColor .. "Missing " .. row.consumeName .. "|r", channel)
                SendChatMessage(table.concat(coloredPlayers, ", "), channel)
                
                OGRH.Msg("Reported " .. table.getn(row.unbuffedPlayers) .. " players missing " .. row.consumeName)
              end
            end
          end)
          
          row:Show()
          yOffset = yOffset - 22
          rowIndex = rowIndex + 1
        end
      end
    end
    
    -- Resize frame
    local newHeight = 6 + (rowIndex - 1) * 22 + 6
    frame:SetHeight(newHeight)
    
    frame:Show()
  end
  
  -- Update timer
  frame.timeSinceUpdate = 0
  frame:SetScript("OnUpdate", function()
    frame.timeSinceUpdate = frame.timeSinceUpdate + arg1
    if frame.timeSinceUpdate >= 3 then
      frame.timeSinceUpdate = 0
      frame.Update()
    end
  end)
  
  -- Combat detection - hide in combat, show after combat
  frame:RegisterEvent("PLAYER_REGEN_DISABLED")
  frame:RegisterEvent("PLAYER_REGEN_ENABLED")
  frame:SetScript("OnEvent", function()
    if event == "PLAYER_REGEN_DISABLED" then
      -- Entering combat - hide window
      if frame:IsVisible() then
        frame.wasVisibleBeforeCombat = true
        frame:Hide()
      end
    elseif event == "PLAYER_REGEN_ENABLED" then
      -- Leaving combat - show window if it was visible before
      if frame.wasVisibleBeforeCombat then
        frame.wasVisibleBeforeCombat = false
        frame.Update()
      end
    end
  end)
  
  -- Initial update
  frame.Update()
end

function OGRH.HideConsumeMonitor()
  if OGRH_ConsumeMonitorFrame then
    OGRH_ConsumeMonitorFrame:Hide()
  end
end
