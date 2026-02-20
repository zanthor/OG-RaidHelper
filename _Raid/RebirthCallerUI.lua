-- RebirthCallerUI.lua (Phase 2: UI & Announcement)
-- UI: dead player list, class-colored buttons, green backdrop, click-to-announce
-- Settings dialog, growth direction, dynamic button sizing
-- Module: _Raid/RebirthCallerUI.lua
-- Dependencies: RebirthCaller.lua, OGST

if not OGRH or not OGRH.RebirthCaller then return end

local RC = OGRH.RebirthCaller

-- ============================================
-- UI Constants
-- ============================================
local DEFAULT_BUTTON_WIDTH = 80
local BUTTON_HEIGHT   = 20
local SPACING         = 2
local TITLE_HEIGHT    = 16
local INSET           = 4

-- Growth direction constants
local GROWTH_DOWN  = "down"
local GROWTH_UP    = "up"
local GROWTH_LEFT  = "left"
local GROWTH_RIGHT = "right"

-- Green backdrop + gold border for "druid in range + LoS"
local GREEN_BACKDROP = {
  bgFile = "Interface/Tooltips/UI-Tooltip-Background",
  edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
  tile = true, tileSize = 16, edgeSize = 8,
  insets = { left = 2, right = 2, top = 2, bottom = 2 },
}

-- Default backdrop for no druid in range
local DEFAULT_BACKDROP = {
  bgFile = "Interface/Tooltips/UI-Tooltip-Background",
  edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
  tile = true, tileSize = 16, edgeSize = 8,
  insets = { left = 2, right = 2, top = 2, bottom = 2 },
}

-- Shared FontString for measuring text widths (created lazily)
local measureFs = nil
local function GetTextWidth(text)
  if not measureFs then
    local f = CreateFrame("Frame", nil, UIParent)
    f:SetWidth(1)
    f:SetHeight(1)
    f:Hide()
    measureFs = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  end
  measureFs:SetText(text)
  return measureFs:GetStringWidth()
end

-- ============================================
-- Class Colors (for FontString:SetTextColor)
-- ============================================
local CLASS_COLORS = {
  WARRIOR = { 0.78, 0.61, 0.43 },
  PALADIN = { 0.96, 0.55, 0.73 },
  HUNTER  = { 0.67, 0.83, 0.45 },
  ROGUE   = { 1.00, 0.96, 0.41 },
  PRIEST  = { 1.00, 1.00, 1.00 },
  SHAMAN  = { 0.00, 0.44, 0.87 },
  MAGE    = { 0.25, 0.78, 0.92 },
  WARLOCK = { 0.53, 0.53, 0.93 },
  DRUID   = { 1.00, 0.49, 0.04 },
}

local function GetClassColor(class)
  local c = CLASS_COLORS[class]
  if c then return c[1], c[2], c[3] end
  return 1, 1, 1
end

-- ============================================
-- Helper: Measure the widest name in the dead list
-- ============================================
local function GetMaxNameWidth()
  local maxW = 0
  if RC.deadPlayerList then
    for i = 1, table.getn(RC.deadPlayerList) do
      local w = GetTextWidth(RC.deadPlayerList[i])
      if w > maxW then maxW = w end
    end
  end
  -- Add padding for button insets
  return maxW + 10
end

-- ============================================
-- Helper: Determine effective button width
-- ============================================
local function GetEffectiveButtonWidth(columns)
  if RC.isDocked then
    -- When docked, compute width from parent to fill available space
    local panel = OGRH_RebirthCallerPanel
    if panel then
      local panelWidth = panel:GetWidth()
      if panelWidth > 0 then
        local available = panelWidth - INSET * 2 - SPACING * (columns - 1)
        local bw = math.floor(available / columns)
        if bw < 20 then bw = 20 end
        return bw
      end
    end
    return DEFAULT_BUTTON_WIDTH
  else
    -- Undocked: use the larger of configured width or longest name
    local configured = RC.GetSetting("columnWidth") or DEFAULT_BUTTON_WIDTH
    local nameWidth = GetMaxNameWidth()
    if nameWidth > configured then
      return nameWidth
    end
    return configured
  end
end

-- ============================================
-- Helper: Is horizontal growth direction?
-- ============================================
local function IsHorizontalGrowth(dir)
  return dir == GROWTH_LEFT or dir == GROWTH_RIGHT
end

-- ============================================
-- Panel Creation
-- ============================================
function RC.CreatePanel()
  if OGRH_RebirthCallerPanel then
    return OGRH_RebirthCallerPanel
  end

  local panel = CreateFrame("Frame", "OGRH_RebirthCallerPanel", UIParent)
  panel:SetWidth(DEFAULT_BUTTON_WIDTH * 2 + SPACING + INSET * 2)
  panel:SetHeight(TITLE_HEIGHT + INSET * 2 + BUTTON_HEIGHT)
  panel:SetPoint("CENTER", UIParent, "CENTER", 200, 0)
  panel:EnableMouse(1)
  panel:SetMovable(1)
  panel:SetClampedToScreen(1)

  -- Panel backdrop
  panel:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  panel:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
  panel:SetBackdropBorderColor(0.6, 0.3, 0.3, 1)

  -- Draggable (only when undocked)
  panel:RegisterForDrag("LeftButton")
  panel:SetScript("OnDragStart", function()
    if not RC.isDocked then
      this:StartMoving()
    end
  end)
  panel:SetScript("OnDragStop", function()
    this:StopMovingOrSizing()
    if not RC.isDocked then
      local point, _, _, x, y = this:GetPoint()
      RC.SetSetting("position", { point = point, x = x, y = y })
    end
  end)

  -- Title
  local titleFs = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  titleFs:SetPoint("TOPLEFT", panel, "TOPLEFT", INSET + 2, -INSET)
  titleFs:SetText("|cffff6666Rebirth Caller|r")
  panel.titleFs = titleFs

  -- Close button
  local closeBtn = CreateFrame("Button", nil, panel)
  closeBtn:SetWidth(14)
  closeBtn:SetHeight(14)
  closeBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -INSET, -INSET)
  closeBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
  closeBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
  closeBtn:SetScript("OnClick", function()
    RC.HideUI()
  end)

  -- Button pool
  panel.buttons = {}
  panel.numVisible = 0

  -- Cycle index per dead player (for right-click cycling)
  panel.cycleIndex = {}

  panel:Hide()
  return panel
end

-- ============================================
-- Button Management
-- ============================================
local function CreateDeadPlayerButton(parent, index)
  local btn = CreateFrame("Button", "OGRH_RCBtn" .. index, parent)
  btn:SetWidth(DEFAULT_BUTTON_WIDTH)
  btn:SetHeight(BUTTON_HEIGHT)

  -- Button backdrop (default: dark)
  btn:SetBackdrop(DEFAULT_BACKDROP)
  btn:SetBackdropColor(0.15, 0.15, 0.15, 0.8)
  btn:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.5)

  -- Name text (anchored left-right so it truncates)
  local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  fs:SetPoint("LEFT", btn, "LEFT", 3, 0)
  fs:SetPoint("RIGHT", btn, "RIGHT", -3, 0)
  fs:SetJustifyH("CENTER")
  btn.nameFs = fs

  -- Click handlers
  btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  btn:SetScript("OnClick", function()
    if not btn.deadName then return end
    local panel = OGRH_RebirthCallerPanel
    if arg1 == "RightButton" then
      -- Cycle to next druid
      local ci = (panel.cycleIndex[btn.deadName] or 1) + 1
      panel.cycleIndex[btn.deadName] = ci
      RC.CallRebirth(btn.deadName, ci)
    else
      -- Left-click: best druid
      panel.cycleIndex[btn.deadName] = 1
      RC.CallRebirth(btn.deadName)
    end
  end)

  -- Tooltip
  btn:SetScript("OnEnter", function()
    if not btn.deadName then return end
    GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
    GameTooltip:SetText(btn.deadName, 1, 1, 1)

    -- Show best assignment preview
    local result = RC.GetAssignment(btn.deadName)
    if result.druid then
      local distText = result.distance and string.format("%.0f yds", result.distance) or "?"
      local losText = ""
      if result.hasLoS == true then
        losText = " |cff00ff00LoS|r"
      elseif result.hasLoS == false then
        losText = " |cffff0000no LoS|r"
      end
      GameTooltip:AddLine("Best: " .. result.druid .. " (" .. distText .. losText .. ")", 0.5, 1.0, 0.5)

      -- Show fallbacks
      if result.fallbackDruids then
        for i = 1, table.getn(result.fallbackDruids) do
          local fb = result.fallbackDruids[i]
          local fbDist = fb.distance and string.format("%.0f yds", fb.distance) or "?"
          GameTooltip:AddLine("  " .. fb.name .. " (" .. fbDist .. ")", 0.6, 0.6, 0.6)
        end
      end
    else
      GameTooltip:AddLine(result.reason or "No druids available", 1.0, 0.3, 0.3)
    end

    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Left-click: Announce best druid", 0.7, 0.7, 0.7)
    GameTooltip:AddLine("Right-click: Cycle to next druid", 0.7, 0.7, 0.7)
    GameTooltip:Show()
  end)
  btn:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)

  btn:Hide()
  return btn
end

local function GetOrCreateButton(panel, index)
  if not panel.buttons[index] then
    panel.buttons[index] = CreateDeadPlayerButton(panel, index)
  end
  return panel.buttons[index]
end

-- ============================================
-- UI Refresh
-- ============================================
function RC.RefreshUI()
  local panel = OGRH_RebirthCallerPanel
  if not panel then return end
  if not panel:IsVisible() then return end

  local deadList = RC.deadPlayerList
  local numDead = table.getn(deadList)
  local columns = RC.GetSetting("columns") or 2
  if columns < 1 then columns = 1 end
  if columns > 10 then columns = 10 end

  -- Growth direction (only used when undocked)
  local growthDir = GROWTH_DOWN
  if not RC.isDocked then
    growthDir = RC.GetSetting("growthDirection") or GROWTH_DOWN
  end

  local btnWidth = GetEffectiveButtonWidth(columns)

  -- Hide all existing buttons first
  for i = 1, panel.numVisible do
    if panel.buttons[i] then
      panel.buttons[i]:Hide()
    end
  end

  if numDead == 0 then
    -- Auto-hide if enabled
    local autoHide = RC.GetSetting("autoHide")
    if autoHide ~= false then
      panel:Hide()
    end
    panel.numVisible = 0
    -- Resize to minimum (keep docked width if docked)
    if not RC.isDocked then
      panel:SetWidth(btnWidth * columns + SPACING * (columns - 1) + INSET * 2)
    end
    panel:SetHeight(TITLE_HEIGHT + INSET * 2)
    return
  end

  -- For horizontal growth (left/right), "columns" setting is actually "rows"
  local isHoriz = IsHorizontalGrowth(growthDir)
  local gridCols, gridRows
  if isHoriz then
    gridRows = columns
    gridCols = math.ceil(numDead / gridRows)
  else
    gridCols = columns
    gridRows = math.ceil(numDead / gridCols)
  end

  for i = 1, numDead do
    local btn = GetOrCreateButton(panel, i)
    local deadName = deadList[i]
    local deadData = RC.deadPlayers[deadName]

    btn.deadName = deadName
    btn:SetWidth(btnWidth)

    -- Set class-colored name text
    if deadData then
      local r, g, b = GetClassColor(deadData.class)
      btn.nameFs:SetText(deadName)
      btn.nameFs:SetTextColor(r, g, b)
    else
      btn.nameFs:SetText(deadName)
      btn.nameFs:SetTextColor(1, 1, 1)
    end

    -- Green backdrop + gold border if a druid is in range + LoS
    if RC.HasDruidInRange(deadName) then
      btn:SetBackdrop(GREEN_BACKDROP)
      btn:SetBackdropColor(0.0, 0.6, 0.0, 0.9)
      btn:SetBackdropBorderColor(1.0, 0.82, 0.0, 1.0)  -- Gold border
    else
      btn:SetBackdrop(DEFAULT_BACKDROP)
      btn:SetBackdropColor(0.15, 0.15, 0.15, 0.8)
      btn:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.5)  -- Dim border
    end

    -- Position in grid based on growth direction
    local col, row
    if isHoriz then
      -- Fill row-first for horizontal growth
      row = math.mod(i - 1, gridRows)
      col = math.floor((i - 1) / gridRows)
    else
      -- Fill column-first for vertical growth (default)
      col = math.mod(i - 1, gridCols)
      row = math.floor((i - 1) / gridCols)
    end

    btn:ClearAllPoints()

    if growthDir == GROWTH_DOWN or growthDir == GROWTH_RIGHT then
      local x = INSET + col * (btnWidth + SPACING)
      local y = -(TITLE_HEIGHT + INSET + row * (BUTTON_HEIGHT + SPACING))
      btn:SetPoint("TOPLEFT", panel, "TOPLEFT", x, y)
    elseif growthDir == GROWTH_UP then
      local x = INSET + col * (btnWidth + SPACING)
      local y = TITLE_HEIGHT + INSET + row * (BUTTON_HEIGHT + SPACING)
      btn:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", x, y)
    elseif growthDir == GROWTH_LEFT then
      local x = INSET + col * (btnWidth + SPACING)
      local y = -(TITLE_HEIGHT + INSET + row * (BUTTON_HEIGHT + SPACING))
      btn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -x, y)
    end

    btn:Show()
  end

  panel.numVisible = numDead

  -- Resize panel to fit content
  local totalWidth = gridCols * btnWidth + (gridCols - 1) * SPACING + INSET * 2
  local totalHeight = TITLE_HEIGHT + INSET + gridRows * (BUTTON_HEIGHT + SPACING) + INSET

  panel:SetHeight(totalHeight)

  -- Width: match parent when docked, otherwise fit content
  if not RC.isDocked then
    panel:SetWidth(totalWidth)
  end

  -- Reposition title for growth direction
  if panel.titleFs then
    panel.titleFs:ClearAllPoints()
    if growthDir == GROWTH_UP and not RC.isDocked then
      panel.titleFs:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", INSET + 2, INSET)
    else
      panel.titleFs:SetPoint("TOPLEFT", panel, "TOPLEFT", INSET + 2, -INSET)
    end
  end

  -- Clean stale cycle indices
  for name, _ in pairs(panel.cycleIndex) do
    if not RC.deadPlayers[name] then
      panel.cycleIndex[name] = nil
    end
  end
end

-- ============================================
-- Dock / Undock System
-- ============================================
RC.isDocked = true  -- Default state

function RC.ToggleDock()
  if RC.isDocked then
    RC.Undock()
  else
    RC.Dock()
  end
  RC.SetSetting("isDocked", RC.isDocked)
end

function RC.Dock()
  local panel = OGRH_RebirthCallerPanel
  if not panel then return end

  local RD = OGRH.ReadynessDashboard
  local rdDocked = RD and RD.isDocked

  if rdDocked then
    -- RD is docked to main → RC also docks to main (below RD via priority)
    local parentFrame = OGRH_Main
    if not parentFrame then
      if RC.State.debug then
        OGRH.Msg("|cffff6666[RH-RebirthCaller][DEBUG]|r Cannot dock — OGRH_Main not found")
      end
      return
    end
    panel:SetWidth(parentFrame:GetWidth())
    if OGRH.RegisterAuxiliaryPanel then
      OGRH.RegisterAuxiliaryPanel(panel, 10)
    else
      panel:ClearAllPoints()
      panel:SetPoint("TOPLEFT", parentFrame, "BOTTOMLEFT", 0, -2)
    end
  else
    -- RD is undocked (floating) → RC docks below RD's panel
    local rdPanel = OGRH_ReadynessDashboard
    if rdPanel then
      -- Unregister from main stacking first
      if OGRH.UnregisterAuxiliaryPanel then
        OGRH.UnregisterAuxiliaryPanel(panel)
      end
      panel:SetWidth(rdPanel:GetWidth())
      panel:ClearAllPoints()
      panel:SetPoint("TOPLEFT", rdPanel, "BOTTOMLEFT", 0, -2)
    else
      -- RD panel doesn't exist — fall back to main
      local parentFrame = OGRH_Main
      if parentFrame then
        panel:SetWidth(parentFrame:GetWidth())
        if OGRH.RegisterAuxiliaryPanel then
          OGRH.RegisterAuxiliaryPanel(panel, 10)
        else
          panel:ClearAllPoints()
          panel:SetPoint("TOPLEFT", parentFrame, "BOTTOMLEFT", 0, -2)
        end
      end
    end
  end

  RC.isDocked = true

  if RC.State.debug then
    OGRH.Msg("|cffff6666[RH-RebirthCaller][DEBUG]|r Panel docked")
  end
end

function RC.Undock()
  local panel = OGRH_RebirthCallerPanel
  if not panel then return end

  -- Unregister from auxiliary panel stacking
  if OGRH.UnregisterAuxiliaryPanel then
    OGRH.UnregisterAuxiliaryPanel(panel)
  end

  -- Position from saved settings or offset from center
  local pos = RC.GetSetting("position")
  panel:ClearAllPoints()
  if pos and pos.point then
    panel:SetPoint(pos.point, UIParent, pos.point, pos.x or 0, pos.y or 0)
  else
    panel:SetPoint("CENTER", UIParent, "CENTER", 200, 0)
  end

  -- Restore content-based width
  local columns = RC.GetSetting("columns") or 2
  local btnWidth = RC.GetSetting("columnWidth") or DEFAULT_BUTTON_WIDTH
  panel:SetWidth(btnWidth * columns + SPACING * (columns - 1) + INSET * 2)

  RC.isDocked = false

  if RC.State.debug then
    OGRH.Msg("|cffff6666[RH-RebirthCaller][DEBUG]|r Panel undocked")
  end
end

-- ============================================
-- Show / Hide / Toggle
-- ============================================
function RC.ShowUI()
  if not RC.IsEnabled() then return end

  local panel = OGRH_RebirthCallerPanel
  if not panel then
    panel = RC.CreatePanel()
  end

  panel:Show()

  -- Apply dock state
  local savedDocked = RC.GetSetting("isDocked")
  if savedDocked ~= nil then
    RC.isDocked = savedDocked
  end

  if RC.isDocked then
    RC.Dock()
  else
    RC.Undock()
  end

  RC.RefreshUI()
end

function RC.HideUI()
  local panel = OGRH_RebirthCallerPanel
  if panel then
    -- Unregister from stacking so other panels reposition
    if RC.isDocked and OGRH.UnregisterAuxiliaryPanel then
      OGRH.UnregisterAuxiliaryPanel(panel)
    end
    panel:Hide()
  end
end

function RC.ToggleUI()
  local panel = OGRH_RebirthCallerPanel
  if panel and panel:IsVisible() then
    RC.HideUI()
  else
    RC.ShowUI()
  end
end

-- ============================================
-- Settings Dialog
-- ============================================
function RC.ShowSettings()
  -- Reuse existing dialog
  if OGRH_RCSettingsFrame then
    RC.RefreshSettingsDialog()
    OGRH_RCSettingsFrame:Show()
    return
  end

  local W = 260
  local H = 290
  local frame = CreateFrame("Frame", "OGRH_RCSettingsFrame", UIParent)
  frame:SetWidth(W)
  frame:SetHeight(H)
  frame:SetPoint("CENTER", UIParent, "CENTER", 0, 50)
  frame:SetFrameStrata("DIALOG")
  frame:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 12,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  frame:SetBackdropColor(0, 0, 0, 0.9)
  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function() frame:StartMoving() end)
  frame:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)

  -- Title
  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOP", frame, "TOP", 0, -10)
  title:SetText("|cffff6666Rebirth Caller Settings|r")

  -- Close button
  local closeBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  closeBtn:SetWidth(60)
  closeBtn:SetHeight(20)
  closeBtn:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 10)
  closeBtn:SetText("Close")
  if OGST and OGST.StyleButton then OGST.StyleButton(closeBtn) end
  closeBtn:SetScript("OnClick", function() frame:Hide() end)

  -- ESC closes
  if OGRH.MakeFrameCloseOnEscape then
    OGRH.MakeFrameCloseOnEscape(frame, "OGRH_RCSettingsFrame")
  end

  local yOff = -32
  local leftMargin = 14
  local rowH = 22

  -- ==========================================
  -- Docked checkbox
  -- ==========================================
  local dockedCB = CreateFrame("CheckButton", "OGRH_RCSettings_Docked", frame, "UICheckButtonTemplate")
  dockedCB:SetWidth(24)
  dockedCB:SetHeight(24)
  dockedCB:SetPoint("TOPLEFT", frame, "TOPLEFT", leftMargin, yOff)
  dockedCB:SetChecked(RC.isDocked)
  local dockedLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  dockedLabel:SetPoint("LEFT", dockedCB, "RIGHT", 2, 0)
  dockedLabel:SetText("Docked")
  dockedCB:SetScript("OnClick", function()
    RC.ToggleDock()
    RC.RefreshSettingsDialog()
    RC.RefreshUI()
  end)
  frame.dockedCB = dockedCB
  yOff = yOff - rowH - 4

  -- ==========================================
  -- Columns / Rows label + value + +/- buttons
  -- ==========================================
  local colLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  colLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", leftMargin, yOff)
  frame.colLabel = colLabel

  local colValue = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  colValue:SetPoint("LEFT", colLabel, "RIGHT", 6, 0)
  frame.colValue = colValue

  local colMinus = CreateFrame("Button", nil, frame)
  colMinus:SetWidth(18)
  colMinus:SetHeight(18)
  colMinus:SetPoint("LEFT", colValue, "RIGHT", 6, 0)
  colMinus:SetNormalTexture("Interface\\Buttons\\UI-MinusButton-Up")
  colMinus:SetPushedTexture("Interface\\Buttons\\UI-MinusButton-Down")
  colMinus:SetHighlightTexture("Interface\\Buttons\\UI-MinusButton-Highlight")
  colMinus:SetScript("OnClick", function()
    local cur = RC.GetSetting("columns") or 2
    cur = cur - 1
    if cur < 1 then cur = 1 end
    RC.SetSetting("columns", cur)
    RC.RefreshSettingsDialog()
    RC.RefreshUI()
  end)
  frame.colMinus = colMinus

  local colPlus = CreateFrame("Button", nil, frame)
  colPlus:SetWidth(18)
  colPlus:SetHeight(18)
  colPlus:SetPoint("LEFT", colMinus, "RIGHT", 2, 0)
  colPlus:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-Up")
  colPlus:SetPushedTexture("Interface\\Buttons\\UI-PlusButton-Down")
  colPlus:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Highlight")
  colPlus:SetScript("OnClick", function()
    local cur = RC.GetSetting("columns") or 2
    cur = cur + 1
    if cur > 10 then cur = 10 end
    RC.SetSetting("columns", cur)
    RC.RefreshSettingsDialog()
    RC.RefreshUI()
  end)
  frame.colPlus = colPlus
  yOff = yOff - rowH - 2

  -- ==========================================
  -- Column Width + +/- buttons
  -- ==========================================
  local cwLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  cwLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", leftMargin, yOff)
  cwLabel:SetText("Column Width:")
  frame.cwLabel = cwLabel

  local cwValue = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  cwValue:SetPoint("LEFT", cwLabel, "RIGHT", 6, 0)
  frame.cwValue = cwValue

  local cwMinus = CreateFrame("Button", nil, frame)
  cwMinus:SetWidth(18)
  cwMinus:SetHeight(18)
  cwMinus:SetPoint("LEFT", cwValue, "RIGHT", 6, 0)
  cwMinus:SetNormalTexture("Interface\\Buttons\\UI-MinusButton-Up")
  cwMinus:SetPushedTexture("Interface\\Buttons\\UI-MinusButton-Down")
  cwMinus:SetHighlightTexture("Interface\\Buttons\\UI-MinusButton-Highlight")
  cwMinus:SetScript("OnClick", function()
    local cur = RC.GetSetting("columnWidth") or DEFAULT_BUTTON_WIDTH
    cur = cur - 5
    if cur < 40 then cur = 40 end
    RC.SetSetting("columnWidth", cur)
    RC.RefreshSettingsDialog()
    RC.RefreshUI()
  end)
  frame.cwMinus = cwMinus

  local cwPlus = CreateFrame("Button", nil, frame)
  cwPlus:SetWidth(18)
  cwPlus:SetHeight(18)
  cwPlus:SetPoint("LEFT", cwMinus, "RIGHT", 2, 0)
  cwPlus:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-Up")
  cwPlus:SetPushedTexture("Interface\\Buttons\\UI-PlusButton-Down")
  cwPlus:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Highlight")
  cwPlus:SetScript("OnClick", function()
    local cur = RC.GetSetting("columnWidth") or DEFAULT_BUTTON_WIDTH
    cur = cur + 5
    if cur > 200 then cur = 200 end
    RC.SetSetting("columnWidth", cur)
    RC.RefreshSettingsDialog()
    RC.RefreshUI()
  end)
  frame.cwPlus = cwPlus

  -- Note: column width not used when docked
  local cwNote = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  cwNote:SetPoint("TOPLEFT", cwLabel, "BOTTOMLEFT", 0, -2)
  cwNote:SetText("(not used when docked)")
  cwNote:SetWidth(200)
  cwNote:SetJustifyH("LEFT")
  frame.cwNote = cwNote
  yOff = yOff - rowH - 16

  -- ==========================================
  -- Growth Direction
  -- ==========================================
  local gdLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  gdLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", leftMargin, yOff)
  gdLabel:SetText("Growth Direction:")
  frame.gdLabel = gdLabel
  yOff = yOff - 16

  local dirLabels = { Down = GROWTH_DOWN, Up = GROWTH_UP, Left = GROWTH_LEFT, Right = GROWTH_RIGHT }
  local dirOrder = { "Down", "Up", "Left", "Right" }
  frame.dirButtons = {}

  local dirX = leftMargin + 4
  for di = 1, 4 do
    local dirName = dirOrder[di]
    local dirVal = dirLabels[dirName]
    local rb = CreateFrame("CheckButton", "OGRH_RCSettings_Dir" .. dirName, frame, "UIRadioButtonTemplate")
    rb:SetWidth(16)
    rb:SetHeight(16)
    rb:SetPoint("TOPLEFT", frame, "TOPLEFT", dirX, yOff)
    rb.dirValue = dirVal

    local rl = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rl:SetPoint("LEFT", rb, "RIGHT", 1, 0)
    rl:SetText(dirName)
    rb.label = rl

    rb:SetScript("OnClick", function()
      RC.SetSetting("growthDirection", rb.dirValue)
      RC.RefreshSettingsDialog()
      RC.RefreshUI()
    end)

    frame.dirButtons[di] = rb
    dirX = dirX + 54
  end
  yOff = yOff - 20

  -- Note: growth direction only when undocked
  local gdNote = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  gdNote:SetPoint("TOPLEFT", frame, "TOPLEFT", leftMargin, yOff)
  gdNote:SetText("(only available when undocked)")
  gdNote:SetWidth(220)
  gdNote:SetJustifyH("LEFT")
  frame.gdNote = gdNote
  yOff = yOff - 18

  -- ==========================================
  -- Auto-Show checkbox
  -- ==========================================
  local autoShowCB = CreateFrame("CheckButton", "OGRH_RCSettings_AutoShow", frame, "UICheckButtonTemplate")
  autoShowCB:SetWidth(24)
  autoShowCB:SetHeight(24)
  autoShowCB:SetPoint("TOPLEFT", frame, "TOPLEFT", leftMargin, yOff)
  local autoShowLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  autoShowLabel:SetPoint("LEFT", autoShowCB, "RIGHT", 2, 0)
  autoShowLabel:SetText("Auto-Show on Death")
  autoShowCB:SetScript("OnClick", function()
    local cur = RC.GetSetting("autoShow")
    if cur == nil then cur = true end
    RC.SetSetting("autoShow", not cur)
    RC.RefreshSettingsDialog()
  end)
  frame.autoShowCB = autoShowCB
  yOff = yOff - rowH - 2

  -- ==========================================
  -- Whisper Druid checkbox
  -- ==========================================
  local whisperCB = CreateFrame("CheckButton", "OGRH_RCSettings_Whisper", frame, "UICheckButtonTemplate")
  whisperCB:SetWidth(24)
  whisperCB:SetHeight(24)
  whisperCB:SetPoint("TOPLEFT", frame, "TOPLEFT", leftMargin, yOff)
  local whisperLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  whisperLabel:SetPoint("LEFT", whisperCB, "RIGHT", 2, 0)
  whisperLabel:SetText("Whisper Druid on Assign")
  whisperCB:SetScript("OnClick", function()
    local cur = RC.GetSetting("whisperDruid")
    if cur == nil then cur = true end
    RC.SetSetting("whisperDruid", not cur)
    RC.RefreshSettingsDialog()
  end)
  frame.whisperCB = whisperCB

  -- Apply initial state
  RC.RefreshSettingsDialog()
  frame:Show()
end

-- ============================================
-- Refresh Settings Dialog
-- ============================================
function RC.RefreshSettingsDialog()
  local frame = OGRH_RCSettingsFrame
  if not frame then return end

  local isDocked = RC.isDocked
  local growthDir = RC.GetSetting("growthDirection") or GROWTH_DOWN
  local columns = RC.GetSetting("columns") or 2
  local colWidth = RC.GetSetting("columnWidth") or DEFAULT_BUTTON_WIDTH
  local autoShow = RC.GetSetting("autoShow")
  if autoShow == nil then autoShow = true end
  local whisper = RC.GetSetting("whisperDruid")
  if whisper == nil then whisper = true end

  -- Docked
  frame.dockedCB:SetChecked(isDocked)

  -- Columns / Rows label (changes based on growth direction)
  local isHoriz = IsHorizontalGrowth(growthDir)
  if isDocked then
    frame.colLabel:SetText("Columns:")
  else
    frame.colLabel:SetText(isHoriz and "Rows:" or "Columns:")
  end
  frame.colValue:SetText(tostring(columns))

  -- Column Width
  frame.cwValue:SetText(tostring(colWidth))
  if isDocked then
    frame.cwLabel:SetTextColor(0.5, 0.5, 0.5)
    frame.cwValue:SetTextColor(0.5, 0.5, 0.5)
    frame.cwMinus:Disable()
    frame.cwPlus:Disable()
    frame.cwNote:Show()
  else
    frame.cwLabel:SetTextColor(1, 1, 1)
    frame.cwValue:SetTextColor(1, 0.82, 0)
    frame.cwMinus:Enable()
    frame.cwPlus:Enable()
    frame.cwNote:Show()
  end

  -- Growth direction radio buttons
  for di = 1, 4 do
    local rb = frame.dirButtons[di]
    rb:SetChecked(rb.dirValue == growthDir)
    if isDocked then
      rb:Disable()
      rb.label:SetTextColor(0.5, 0.5, 0.5)
    else
      rb:Enable()
      rb.label:SetTextColor(1, 1, 1)
    end
  end
  if isDocked then
    frame.gdLabel:SetTextColor(0.5, 0.5, 0.5)
    frame.gdNote:Show()
  else
    frame.gdLabel:SetTextColor(1, 1, 1)
    frame.gdNote:Hide()
  end

  -- Auto-Show
  frame.autoShowCB:SetChecked(autoShow)

  -- Whisper Druid
  frame.whisperCB:SetChecked(whisper)
end

-- ============================================
-- Periodic Backdrop Refresh (for green indicator)
-- ============================================
-- The green backdrop depends on druid positions which change constantly.
-- We refresh on a short interval during combat only.
RC.backdropTimer = 0
RC.BACKDROP_INTERVAL = 1.0  -- seconds

local function OnUpdateBackdrop()
  if not OGRH_RebirthCallerPanel then return end
  if not OGRH_RebirthCallerPanel:IsVisible() then return end

  RC.backdropTimer = RC.backdropTimer + arg1
  if RC.backdropTimer < RC.BACKDROP_INTERVAL then return end
  RC.backdropTimer = 0

  -- Only re-check backdrops (not full layout)
  local panel = OGRH_RebirthCallerPanel
  for i = 1, panel.numVisible do
    local btn = panel.buttons[i]
    if btn and btn:IsVisible() and btn.deadName then
      if RC.HasDruidInRange(btn.deadName) then
        btn:SetBackdrop(GREEN_BACKDROP)
        btn:SetBackdropColor(0.0, 0.6, 0.0, 0.9)
        btn:SetBackdropBorderColor(1.0, 0.82, 0.0, 1.0)  -- Gold border
      else
        btn:SetBackdrop(DEFAULT_BACKDROP)
        btn:SetBackdropColor(0.15, 0.15, 0.15, 0.8)
        btn:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.5)  -- Dim border
      end
    end
  end
end

-- ============================================
-- Callback Hooks (auto-refresh UI on death events)
-- ============================================
RC.RegisterCallback("OnPlayerDeath", function(name)
  -- Auto-show
  local autoShow = RC.GetSetting("autoShow")
  if autoShow ~= false and RC.IsEnabled() then
    if not OGRH_RebirthCallerPanel or not OGRH_RebirthCallerPanel:IsVisible() then
      RC.ShowUI()
    end
  end
  RC.RefreshUI()
end)

RC.RegisterCallback("OnPlayerResurrected", function(name)
  RC.RefreshUI()
end)

-- ============================================
-- Initialization
-- ============================================
local uiInitFrame = CreateFrame("Frame")
uiInitFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
uiInitFrame:SetScript("OnEvent", function()
  -- Wait a frame for RC to initialize
  local waitFrame = CreateFrame("Frame")
  waitFrame:SetScript("OnUpdate", function()
    if not RC.State.initialized then return end
    waitFrame:SetScript("OnUpdate", nil)

    -- Create the panel (hidden initially)
    RC.CreatePanel()

    -- Attach backdrop refresh OnUpdate to the panel
    OGRH_RebirthCallerPanel:SetScript("OnUpdate", OnUpdateBackdrop)

    -- If we're in a raid and enabled, auto-show
    if GetNumRaidMembers() > 0 and RC.IsEnabled() then
      -- Only auto-show if there are dead players (or autoShow is aggressive)
      -- For now, just create it — it will show when someone dies
    end
  end)

  uiInitFrame:UnregisterAllEvents()
end)
