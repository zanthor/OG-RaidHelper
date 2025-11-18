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
  closeBtn:SetScript("OnClick", function() frame:Hide() end)
  
  -- Instructions
  local instructions = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  instructions:SetPoint("TOPLEFT", 20, -45)
  instructions:SetText("Configure consumable items:")
  
  -- List backdrop
  local listBackdrop = CreateFrame("Frame", nil, frame)
  listBackdrop:SetPoint("TOPLEFT", 17, -75)
  listBackdrop:SetPoint("BOTTOMRIGHT", -17, 10)
  listBackdrop:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 12,
    insets = {left = 3, right = 3, top = 3, bottom = 3}
  })
  listBackdrop:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
  
  -- Scroll frame
  local scrollFrame = CreateFrame("ScrollFrame", nil, listBackdrop)
  scrollFrame:SetPoint("TOPLEFT", listBackdrop, "TOPLEFT", 5, -5)
  scrollFrame:SetPoint("BOTTOMRIGHT", listBackdrop, "BOTTOMRIGHT", -22, 5)
  
  -- Scroll child
  local scrollChild = CreateFrame("Frame", nil, scrollFrame)
  scrollChild:SetWidth(435)
  scrollChild:SetHeight(1)
  scrollFrame:SetScrollChild(scrollChild)
  frame.scrollChild = scrollChild
  frame.scrollFrame = scrollFrame
  
  -- Create scrollbar
  local scrollBar = CreateFrame("Slider", nil, scrollFrame)
  scrollBar:SetPoint("TOPRIGHT", listBackdrop, "TOPRIGHT", -5, -16)
  scrollBar:SetPoint("BOTTOMRIGHT", listBackdrop, "BOTTOMRIGHT", -5, 16)
  scrollBar:SetWidth(16)
  scrollBar:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 8,
    insets = {left = 3, right = 3, top = 3, bottom = 3}
  })
  scrollBar:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
  scrollBar:SetOrientation("VERTICAL")
  scrollBar:SetMinMaxValues(0, 1)
  scrollBar:SetValue(0)
  scrollBar:SetValueStep(22)
  scrollBar:Hide()
  frame.scrollBar = scrollBar
  
  scrollBar:SetScript("OnValueChanged", function()
    scrollFrame:SetVerticalScroll(this:GetValue())
  end)
  
  scrollFrame:EnableMouseWheel(true)
  scrollFrame:SetScript("OnMouseWheel", function()
    if not scrollBar:IsShown() then
      return
    end
    
    local delta = arg1
    local current = scrollBar:GetValue()
    local minVal, maxVal = scrollBar:GetMinMaxValues()
    
    if delta > 0 then
      scrollBar:SetValue(math.max(minVal, current - 22))
    else
      scrollBar:SetValue(math.min(maxVal, current + 22))
    end
  end)
  
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
  if not OGRH_SV.consumes then
    OGRH_SV.consumes = {}
  end
  local items = OGRH_SV.consumes
  
  local yOffset = -5
  local rowHeight = 22
  local rowSpacing = 2
  
  for i, itemData in ipairs(items) do
    local row = CreateFrame("Button", nil, scrollChild)
    row:SetWidth(435)
    row:SetHeight(rowHeight)
    row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, yOffset)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    
    -- Background
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    bg:SetVertexColor(0.2, 0.2, 0.2, 0.5)
    row.bg = bg
    
    local idx = i
    
    -- Right-click to edit
    row:SetScript("OnClick", function()
      if arg1 == "RightButton" then
        OGRH.ShowEditConsumeDialog(idx)
      end
    end)
    
    -- Delete button (X mark - raid target icon 7)
    local deleteBtn = CreateFrame("Button", nil, row)
    deleteBtn:SetWidth(16)
    deleteBtn:SetHeight(16)
    deleteBtn:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    
    local deleteIcon = deleteBtn:CreateTexture(nil, "ARTWORK")
    deleteIcon:SetWidth(16)
    deleteIcon:SetHeight(16)
    deleteIcon:SetAllPoints(deleteBtn)
    deleteIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    deleteIcon:SetTexCoord(0.5, 0.75, 0.25, 0.5)  -- Cross/X icon (raid mark 7)
    
    local deleteHighlight = deleteBtn:CreateTexture(nil, "HIGHLIGHT")
    deleteHighlight:SetWidth(16)
    deleteHighlight:SetHeight(16)
    deleteHighlight:SetAllPoints(deleteBtn)
    deleteHighlight:SetTexture("Interface\\Buttons\\UI-Common-MouseHilight")
    deleteHighlight:SetBlendMode("ADD")
    
    deleteBtn:SetScript("OnClick", function()
      table.remove(OGRH_SV.consumes, idx)
      OGRH.RefreshConsumesSettings()
    end)
    
    -- Down button
    local downBtn = CreateFrame("Button", nil, row)
    downBtn:SetWidth(32)
    downBtn:SetHeight(32)
    downBtn:SetPoint("RIGHT", deleteBtn, "LEFT", 5, 0)
    downBtn:SetNormalTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up")
    downBtn:SetPushedTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Down")
    downBtn:SetHighlightTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Highlight")
    downBtn:SetScript("OnClick", function()
      if idx < table.getn(OGRH_SV.consumes) then
        local temp = OGRH_SV.consumes[idx + 1]
        OGRH_SV.consumes[idx + 1] = OGRH_SV.consumes[idx]
        OGRH_SV.consumes[idx] = temp
        OGRH.RefreshConsumesSettings()
      end
    end)
    
    -- Up button
    local upBtn = CreateFrame("Button", nil, row)
    upBtn:SetWidth(32)
    upBtn:SetHeight(32)
    upBtn:SetPoint("RIGHT", downBtn, "LEFT", 13, 0)
    upBtn:SetNormalTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Up")
    upBtn:SetPushedTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Down")
    upBtn:SetHighlightTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Highlight")
    upBtn:SetScript("OnClick", function()
      if idx > 1 then
        local temp = OGRH_SV.consumes[idx - 1]
        OGRH_SV.consumes[idx - 1] = OGRH_SV.consumes[idx]
        OGRH_SV.consumes[idx] = temp
        OGRH.RefreshConsumesSettings()
      end
    end)
    
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
  local addItemBtn = CreateFrame("Button", nil, scrollChild)
  addItemBtn:SetWidth(435)
  addItemBtn:SetHeight(rowHeight)
  addItemBtn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, yOffset)
  
  -- Background
  local bg = addItemBtn:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetTexture("Interface\\Buttons\\WHITE8X8")
  bg:SetVertexColor(0.1, 0.3, 0.1, 0.5)
  
  -- Highlight
  local highlight = addItemBtn:CreateTexture(nil, "HIGHLIGHT")
  highlight:SetAllPoints()
  highlight:SetTexture("Interface\\Buttons\\WHITE8X8")
  highlight:SetVertexColor(0.2, 0.5, 0.2, 0.5)
  
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
  scrollChild:SetHeight(contentHeight)
  
  -- Update scrollbar visibility
  local scrollFrame = OGRH_ConsumesFrame.scrollFrame
  local scrollBar = OGRH_ConsumesFrame.scrollBar
  local scrollFrameHeight = scrollFrame:GetHeight()
  
  if contentHeight > scrollFrameHeight then
    scrollBar:Show()
    scrollBar:SetMinMaxValues(0, contentHeight - scrollFrameHeight)
    scrollBar:SetValue(0)
    scrollFrame:SetVerticalScroll(0)
  else
    scrollBar:Hide()
    scrollFrame:SetVerticalScroll(0)
  end
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
    if not OGRH_SV.consumes then
      OGRH_SV.consumes = {}
    end
    local consumeData = {
      primaryId = primaryId,
      primaryName = primaryName or ("Item " .. primaryId)
    }
    if secondaryId > 0 then
      consumeData.secondaryId = secondaryId
      consumeData.secondaryName = secondaryName or ("Item " .. secondaryId)
    end
    table.insert(OGRH_SV.consumes, consumeData)
    
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
  if not OGRH_SV.consumes then
    OGRH_SV.consumes = {}
  end
  local itemData = OGRH_SV.consumes[itemIndex]
  if not itemData then return end
  
  if OGRH_EditConsumeDialog then
    OGRH_EditConsumeDialog.itemIndex = itemIndex
    OGRH_EditConsumeDialog.primaryInput:SetText(tostring(itemData.primaryId))
    OGRH_EditConsumeDialog.secondaryInput:SetText(tostring(itemData.secondaryId))
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
  secondaryInput:SetText(tostring(itemData.secondaryId))
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
    local consumeData = {
      primaryId = primaryId,
      primaryName = primaryName or ("Item " .. primaryId)
    }
    if secondaryId > 0 then
      consumeData.secondaryId = secondaryId
      consumeData.secondaryName = secondaryName or ("Item " .. secondaryId)
    end
    OGRH_SV.consumes[dialog.itemIndex] = consumeData
    
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
