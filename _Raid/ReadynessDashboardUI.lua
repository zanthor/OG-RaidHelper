-- ReadynessDashboardUI.lua (Phase 1: UI Framework)
-- OGST-based UI, docked panel, indicator widgets, dock system
-- Module: _Raid/ReadynessDashboardUI.lua
-- Dependencies: ReadynessDashboard.lua, OGST

if not OGRH then
  DEFAULT_CHAT_FRAME:AddMessage("|cffff0000Error: ReadynessDashboardUI requires OGRH_Core to be loaded first!|r")
  return
end

if not OGRH.ReadynessDashboard then
  DEFAULT_CHAT_FRAME:AddMessage("|cffff0000Error: ReadynessDashboardUI requires ReadynessDashboard.lua to be loaded first!|r")
  return
end

local RD = OGRH.ReadynessDashboard

-- ============================================
-- Panel Creation
-- ============================================
function RD.CreateDashboardPanel()
  if OGRH_ReadynessDashboard then
    return OGRH_ReadynessDashboard
  end

  local panel = CreateFrame("Frame", "OGRH_ReadynessDashboard", UIParent)
  panel:SetWidth(180)
  panel:SetHeight(47)
  panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  panel:EnableMouse(1)
  panel:SetMovable(1)
  panel:SetClampedToScreen(1)

  -- Movable when undocked
  panel:RegisterForDrag("LeftButton")
  panel:SetScript("OnDragStart", function()
    if not RD.isDocked then
      this:StartMoving()
    end
  end)
  panel:SetScript("OnDragStop", function()
    this:StopMovingOrSizing()
    -- Save position
    local point, _, _, x, y = this:GetPoint()
    RD.SetSetting("position", { point = point, x = x, y = y })
  end)

  -- ============================================
  -- Row 1: Buff, CCon, ECon (icons) + Tank/Healer resource bars
  -- ============================================
  local row1Y = -6
  local iconSize = 16
  local iconGap = 4

  -- Buff Indicator (Fortitude icon, tinted)
  panel.buffIndicator = RD.CreateIconIndicator(panel, "buff", "Interface\\Icons\\Spell_Holy_WordFortitude")
  panel.buffIndicator:SetPoint("TOPLEFT", panel, "TOPLEFT", 6, row1Y)

  -- Class Consume Indicator (Flask of the Titans icon, tinted)
  panel.classConIndicator = RD.CreateIconIndicator(panel, "classCon", "Interface\\Icons\\INV_Potion_62")
  panel.classConIndicator:SetPoint("LEFT", panel.buffIndicator, "RIGHT", iconGap, 0)

  -- Encounter Consume Indicator (Greater Fire Protection Potion icon, tinted)
  panel.encConIndicator = RD.CreateIconIndicator(panel, "encCon", "Interface\\Icons\\INV_Potion_24")
  panel.encConIndicator:SetPoint("LEFT", panel.classConIndicator, "RIGHT", iconGap, 0)

  -- ============================================
  -- Row 1 (right side): Tank + Healer role resource bars
  -- ============================================
  panel.tankResource = RD.CreateRoleResourceIndicator(panel, "TANKS", "Interface\\Icons\\Ability_Defend")
  panel.tankResource:SetPoint("LEFT", panel.encConIndicator, "RIGHT", iconGap + 2, 0)

  panel.healerResource = RD.CreateRoleResourceIndicator(panel, "HEALERS", "Interface\\Icons\\Spell_Holy_FlashHeal")
  panel.healerResource:SetPoint("LEFT", panel.tankResource, "RIGHT", iconGap + 2, 0)

  -- ============================================
  -- Row 2: Reb, Tranq, Taunt (icons) + Melee, Ranged resource bars
  -- ============================================
  local row2Y = row1Y - (iconSize + 4)

  -- Rebirth Indicator (spell icon, tinted)
  panel.rebirthIndicator = RD.CreateIconIndicator(panel, "rebirth", "Interface\\Icons\\Spell_Nature_Reincarnation")
  panel.rebirthIndicator:SetPoint("TOPLEFT", panel, "TOPLEFT", 6, row2Y)

  -- Tranquility Indicator (spell icon, tinted)
  panel.tranqIndicator = RD.CreateIconIndicator(panel, "tranq", "Interface\\Icons\\Spell_Nature_Tranquility")
  panel.tranqIndicator:SetPoint("LEFT", panel.rebirthIndicator, "RIGHT", iconGap, 0)

  -- Taunt Indicator (spell icon, tinted)
  panel.tauntIndicator = RD.CreateIconIndicator(panel, "taunt", "Interface\\Icons\\Ability_BullRush")
  panel.tauntIndicator:SetPoint("LEFT", panel.tranqIndicator, "RIGHT", iconGap, 0)

  -- Melee + Ranged role resource bars
  panel.meleeResource = RD.CreateRoleResourceIndicator(panel, "MELEE", "Interface\\Icons\\INV_Sword_27")
  panel.meleeResource:SetPoint("LEFT", panel.tauntIndicator, "RIGHT", iconGap + 2, 0)

  panel.rangedResource = RD.CreateRoleResourceIndicator(panel, "RANGED", "Interface\\Icons\\Spell_Fire_FireBolt")
  panel.rangedResource:SetPoint("LEFT", panel.meleeResource, "RIGHT", iconGap + 2, 0)

  -- Dock/Undock toggle button
  local dockBtn = CreateFrame("Button", nil, panel)
  dockBtn:SetWidth(16)
  dockBtn:SetHeight(16)
  dockBtn:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -4, 4)
  dockBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-CollapseButton-Up")
  dockBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
  dockBtn:SetScript("OnClick", function()
    RD.ToggleDock()
  end)
  dockBtn:SetScript("OnEnter", function()
    GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
    if RD.isDocked then
      GameTooltip:SetText("Undock Dashboard")
    else
      GameTooltip:SetText("Dock Dashboard")
    end
    GameTooltip:Show()
  end)
  dockBtn:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)
  panel.dockBtn = dockBtn

  -- Start hidden until explicitly shown
  panel:Hide()

  return panel
end

-- ============================================
-- Standard Indicator Widget (colored square, no label)
-- ============================================
function RD.CreateIndicator(parent, indicatorType)
  local frame = CreateFrame("Button", nil, parent)
  frame:SetWidth(16)
  frame:SetHeight(16)
  frame.indicatorType = indicatorType

  -- Colored square
  local dot = frame:CreateTexture(nil, "OVERLAY")
  dot:SetWidth(14)
  dot:SetHeight(14)
  dot:SetTexture("Interface\\BUTTONS\\WHITE8X8")
  dot:SetPoint("CENTER", frame, "CENTER", 0, 0)
  dot:SetVertexColor(0.0, 1.0, 0.0, 1)  -- Green default (preview)
  frame.dot = dot

  -- Click handler
  frame:SetScript("OnClick", function()
    if arg1 == "LeftButton" then
      if IsShiftKeyDown() and indicatorType == "buff" then
        RD.OpenBuffManager()
      else
        RD.OnIndicatorClick(indicatorType)
      end
    end
  end)
  frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")

  -- Tooltip on hover
  frame:SetScript("OnEnter", function()
    RD.ShowIndicatorTooltip(this, this.indicatorType)
  end)
  frame:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)

  return frame
end

-- ============================================
-- Icon Indicator Widget (spell icon, tinted by status)
-- ============================================
function RD.CreateIconIndicator(parent, indicatorType, iconPath)
  local frame = CreateFrame("Button", nil, parent)
  frame:SetWidth(16)
  frame:SetHeight(16)
  frame.indicatorType = indicatorType

  -- Spell icon texture
  local icon = frame:CreateTexture(nil, "ARTWORK")
  icon:SetWidth(16)
  icon:SetHeight(16)
  icon:SetTexture(iconPath)
  icon:SetPoint("CENTER", frame, "CENTER", 0, 0)
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)  -- Trim default icon border
  icon:SetVertexColor(0.0, 1.0, 0.0, 1)  -- Green tint default (preview)
  frame.icon = icon

  -- Click handler
  frame:SetScript("OnClick", function()
    if arg1 == "LeftButton" then
      if IsShiftKeyDown() and indicatorType == "buff" then
        RD.OpenBuffManager()
      else
        RD.OnIndicatorClick(indicatorType)
      end
    end
  end)
  frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")

  -- Tooltip on hover
  frame:SetScript("OnEnter", function()
    RD.ShowIndicatorTooltip(this, this.indicatorType)
  end)
  frame:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)

  return frame
end

-- ============================================
-- Role Resource Indicator (icon + health bar / mana bar stacked)
-- ============================================
function RD.CreateRoleResourceIndicator(parent, roleKey, iconPath)
  local barWidth = 30
  local barHeight = 8
  local iconSize = 16
  local frame = CreateFrame("Button", nil, parent)
  frame:SetWidth(iconSize + 2 + barWidth)
  frame:SetHeight(iconSize)
  frame.roleKey = roleKey

  -- Role icon
  local icon = frame:CreateTexture(nil, "OVERLAY")
  icon:SetWidth(iconSize)
  icon:SetHeight(iconSize)
  icon:SetTexture(iconPath)
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  icon:SetPoint("LEFT", frame, "LEFT", 0, 0)
  frame.roleIcon = icon

  -- Health bar (top half)
  if OGST and OGST.CreateProgressBar then
    frame.healthBar = OGST.CreateProgressBar(frame, {
      width = barWidth,
      height = barHeight,
      barColor = { r = 0.0, g = 1.0, b = 0.0 },
      showText = false,
    })
    frame.healthBar:SetPoint("TOPLEFT", icon, "TOPRIGHT", 2, 0)
    frame.healthBar:SetMinMaxValues(0, 100)
    frame.healthBar:SetValue(100)
  end

  -- Mana bar (bottom half)
  if OGST and OGST.CreateProgressBar then
    frame.manaBar = OGST.CreateProgressBar(frame, {
      width = barWidth,
      height = barHeight,
      barColor = { r = 0.0, g = 0.4, b = 1.0 },
      showText = false,
    })
    frame.manaBar:SetPoint("TOPLEFT", frame.healthBar, "BOTTOMLEFT", 0, 0)
    frame.manaBar:SetMinMaxValues(0, 100)
    frame.manaBar:SetValue(100)
  end

  -- Tooltip
  frame:SetScript("OnEnter", function()
    RD.ShowRoleResourceTooltip(this, this.roleKey)
  end)
  frame:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)

  return frame
end

-- ============================================
-- Display Update Functions
-- ============================================

function RD.UpdateIndicatorDisplay(indicator, scanResult)
  if not indicator then return end

  local color = RD.STATUS_COLORS[scanResult.status] or RD.STATUS_COLORS.gray

  -- Icon indicators (Reb, Tranq, Taunt)
  if indicator.icon then
    indicator.icon:SetVertexColor(color.r, color.g, color.b, 1)
    return
  end

  -- Standard square indicators
  if indicator.dot then
    indicator.dot:SetVertexColor(color.r, color.g, color.b, 1)
  end
end

function RD.UpdateRoleResourceDisplay(indicator, poolData)
  if not indicator or not poolData then return end

  -- Health bar
  local healthPct = poolData.health or 0
  local hColor = RD.GetHealthColor(healthPct)
  if indicator.healthBar then
    indicator.healthBar:SetValue(healthPct)
    indicator.healthBar:SetBarColor(hColor.r, hColor.g, hColor.b)
  end

  -- Mana bar
  local manaPct = poolData.mana or 0
  local mColor = RD.GetManaColor(manaPct)
  if indicator.manaBar then
    indicator.manaBar:SetValue(manaPct)
    indicator.manaBar:SetBarColor(mColor.r, mColor.g, mColor.b)
  end
end

function RD.GetManaColor(percent)
  if percent >= 90 then
    return { r = 0.0, g = 0.4, b = 1.0 }
  elseif percent >= 70 then
    return { r = 1.0, g = 1.0, b = 0.0 }
  else
    return { r = 1.0, g = 0.0, b = 0.0 }
  end
end

function RD.GetHealthColor(percent)
  if percent >= 90 then
    return { r = 0.0, g = 1.0, b = 0.0 }
  elseif percent >= 70 then
    return { r = 1.0, g = 1.0, b = 0.0 }
  else
    return { r = 1.0, g = 0.0, b = 0.0 }
  end
end

-- ============================================
-- Role Resource Tooltip
-- ============================================
local ROLE_LABELS = {
  TANKS = "Tanks",
  HEALERS = "Healers",
  MELEE = "Melee",
  RANGED = "Ranged",
}

function RD.ShowRoleResourceTooltip(frame, roleKey)
  if not frame or not roleKey then return end
  GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
  GameTooltip:SetText((ROLE_LABELS[roleKey] or roleKey) .. " Resources")

  local res = RD.State.indicators.roleResources
  local pool = res and res[roleKey]
  if pool then
    GameTooltip:AddLine(string.format("Health: %d%%", pool.health or 0), 0.0, 1.0, 0.0)
    GameTooltip:AddLine(string.format("Mana: %d%%", pool.mana or 0), 0.0, 0.4, 1.0)
    if pool.healthPlayers then
      for _, p in ipairs(pool.healthPlayers) do
        GameTooltip:AddLine(string.format("  %s: %d%% hp", p.name, p.percent), 0.8, 0.8, 0.8)
      end
    end
  else
    GameTooltip:AddLine("No data", 0.5, 0.5, 0.5)
  end
  GameTooltip:Show()
end

-- ============================================
-- Refresh Dashboard (called after each scan)
-- ============================================
function RD.RefreshDashboard()
  local panel = OGRH_ReadynessDashboard
  if not panel then return end
  if not panel:IsVisible() then return end

  -- Standard indicators (default green for preview)
  RD.UpdateIndicatorDisplay(panel.buffIndicator, RD.State.indicators.buff or { status = "green" })
  RD.UpdateIndicatorDisplay(panel.classConIndicator, RD.State.indicators.classCon or { status = "green" })

  -- Encounter consume: show gray when no consumes defined for current encounter
  local encConState = RD.State.indicators.encCon or { status = "gray", ready = 0, total = 0 }
  if encConState.hidden then
    encConState.status = "gray"
    encConState.ready = 0
    encConState.total = 0
  end
  RD.UpdateIndicatorDisplay(panel.encConIndicator, encConState)

  -- Role resource indicators
  local res = RD.State.indicators.roleResources
  if res then
    RD.UpdateRoleResourceDisplay(panel.tankResource, res.TANKS)
    RD.UpdateRoleResourceDisplay(panel.healerResource, res.HEALERS)
    RD.UpdateRoleResourceDisplay(panel.meleeResource, res.MELEE)
    RD.UpdateRoleResourceDisplay(panel.rangedResource, res.RANGED)
  end

  -- Cooldown indicators (default green for preview)
  RD.UpdateIndicatorDisplay(panel.rebirthIndicator, RD.State.indicators.rebirth or { status = "green" })
  RD.UpdateIndicatorDisplay(panel.tranqIndicator, RD.State.indicators.tranq or { status = "green" })
  RD.UpdateIndicatorDisplay(panel.tauntIndicator, RD.State.indicators.taunt or { status = "green" })
end

-- ============================================
-- Tooltip Details
-- ============================================
function RD.ShowIndicatorTooltip(frame, indicatorType)
  if not frame or not indicatorType then return end

  GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")

  local state = RD.State.indicators[indicatorType]
  if not state then
    GameTooltip:SetText("No data")
    GameTooltip:Show()
    return
  end

  if indicatorType == "buff" then
    GameTooltip:SetText("Buff Readyness")

    -- Status summary
    local statusColors = { green = {0,1,0}, yellow = {1,1,0}, red = {1,0,0}, gray = {0.5,0.5,0.5} }
    local sc = statusColors[state.status or "gray"] or statusColors.gray
    GameTooltip:AddLine(string.format("Ready: %d / %d players fully buffed", state.ready or 0, state.total or 0), sc[1], sc[2], sc[3])

    -- Per-buff category breakdown
    if state.byBuff then
      local BUFF_LABELS = {
        fortitude = "Fortitude", spirit = "Spirit", shadowprot = "Shadow Prot",
        motw = "Mark of the Wild", int = "Arcane Intellect",
      }
      -- Alphabetical sort by display label
      local cats = {}
      for cat, _ in pairs(state.byBuff) do table.insert(cats, cat) end
      table.sort(cats, function(a, b)
        local aLabel = BUFF_LABELS[a] or a
        local bLabel = BUFF_LABELS[b] or b
        return aLabel < bLabel
      end)

      for _, cat in ipairs(cats) do
        local data = state.byBuff[cat]
        local missingCount = table.getn(data.missing or {})
        local label = BUFF_LABELS[cat] or cat
        if missingCount > 0 then
          GameTooltip:AddLine(string.format("  %s: %d/%d", label, (data.ready or 0), (data.total or 0)), 1, 0.5, 0.5)
        else
          GameTooltip:AddLine(string.format("  %s: %d/%d", label, (data.ready or 0), (data.total or 0)), 0.5, 1, 0.5)
        end
      end
    end

    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Click to announce missing buffs", 0.6, 0.6, 0.6)
    GameTooltip:AddLine("Shift-Click to open Buff Manager", 0.6, 0.6, 0.6)

  elseif indicatorType == "classCon" then
    GameTooltip:SetText("Class Consume Readyness")
    GameTooltip:AddLine(string.format("Ready: %d / %d  (threshold %d%%)",
      state.ready or 0, state.total or 0, RD.GetConsumeThreshold()), 1, 1, 1)
    GameTooltip:AddLine(string.format("Average Score: %d%%", math.floor(state.averageScore or 0)), 0.7, 0.7, 0.7)
    if state.missing and table.getn(state.missing) > 0 then
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine("Below Threshold:", 1, 0.5, 0.5)
      local thresh = RD.GetConsumeThreshold()
      local yellowCutoff = thresh * 0.80  -- 80% of threshold = yellow, below = red
      for _, entry in ipairs(state.missing) do
        local score = entry.score or 0
        local r, g, b
        if score >= thresh then
          r, g, b = 0.5, 1, 0.5  -- green (shouldn't be in missing, but safety)
        elseif score >= yellowCutoff then
          r, g, b = 1, 1, 0      -- yellow
        else
          r, g, b = 1, 0.4, 0.4  -- red
        end
        GameTooltip:AddDoubleLine("  " .. (entry.name or "?"), string.format("%d%%", score), r, g, b, r, g, b)
      end
    end

  elseif indicatorType == "encCon" then
    local encName = state.encounterName or "Encounter"
    GameTooltip:SetText(encName .. " Consumes")
    GameTooltip:AddLine(string.format("Ready: %d / %d players fully buffed", state.ready or 0, state.total or 0), 1, 1, 1)
    if state.byConsume then
      -- Alphabetical sort by consume label
      local labels = {}
      for label, _ in pairs(state.byConsume) do table.insert(labels, label) end
      table.sort(labels)
      for _, label in ipairs(labels) do
        local data = state.byConsume[label]
        local missingCount = data.missing and table.getn(data.missing) or 0
        if missingCount > 0 then
          GameTooltip:AddLine(string.format("  %s: %d/%d", label, (data.ready or 0), (data.total or 0)), 1, 0.5, 0.5)
        else
          GameTooltip:AddLine(string.format("  %s: %d/%d", label, (data.ready or 0), (data.total or 0)), 0.5, 1, 0.5)
        end
      end
    end

  elseif indicatorType == "rebirth" then
    GameTooltip:SetText("Rebirth Readyness")
    RD.AddCooldownTooltipLines(state, "Rebirth")

  elseif indicatorType == "tranq" then
    GameTooltip:SetText("Tranquility Readyness")
    RD.AddCooldownTooltipLines(state, "Tranquility")

  elseif indicatorType == "taunt" then
    GameTooltip:SetText("AOE Taunt Readyness")
    RD.AddCooldownTooltipLines(state, "AOE Taunt")
  end

  GameTooltip:AddLine(" ")
  GameTooltip:AddLine("Left-click: Announce to raid", 0.5, 0.5, 0.5)
  GameTooltip:AddLine("Right-click: Show details", 0.5, 0.5, 0.5)
  GameTooltip:Show()
end

function RD.AddCooldownTooltipLines(state, abilityName)
  GameTooltip:AddLine(string.format("Available: %d / %d", state.ready or 0, state.total or 0), 1, 1, 1)

  if state.available and table.getn(state.available) > 0 then
    GameTooltip:AddLine("Ready:", 0.0, 1.0, 0.0)
    for _, name in ipairs(state.available) do
      GameTooltip:AddLine("  " .. name, 0.5, 1.0, 0.5)
    end
  end

  if state.onCooldown and table.getn(state.onCooldown) > 0 then
    GameTooltip:AddLine("On Cooldown:", 1.0, 0.5, 0.0)
    for _, entry in ipairs(state.onCooldown) do
      local remaining = entry.remaining or 0
      GameTooltip:AddLine(string.format("  %s: %s", entry.name, RD.FormatTime(remaining)), 1.0, 0.7, 0.3)
    end
  end
end

-- ============================================
-- Dock / Undock System
-- ============================================
RD.isDocked = true  -- Default state

function RD.ToggleDock()
  if RD.isDocked then
    RD.Undock()
  else
    RD.Dock()
  end
  RD.SetSetting("isDocked", RD.isDocked)
end

function RD.Dock()
  local panel = OGRH_ReadynessDashboard
  if not panel then return end

  -- Find the main OGRH frame to dock to
  local parentFrame = OGRH_Main
  if not parentFrame then
    if RD.State.debug then
      OGRH.Msg("|cffff6666[RH-ReadyDash][DEBUG]|r Cannot dock — OGRH_Main not found")
    end
    return
  end

  -- Match parent width
  panel:SetWidth(parentFrame:GetWidth())

  -- Register with OGRH auxiliary panel stacking system (priority 5 = closest to main)
  if OGRH.RegisterAuxiliaryPanel then
    OGRH.RegisterAuxiliaryPanel(panel, 5)
  else
    -- Fallback: manual positioning below main frame
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", parentFrame, "BOTTOMLEFT", 0, -2)
  end

  RD.isDocked = true

  if RD.State.debug then
    OGRH.Msg("|cffff6666[RH-ReadyDash][DEBUG]|r Panel docked")
  end
end

function RD.Undock()
  local panel = OGRH_ReadynessDashboard
  if not panel then return end

  -- Unregister from auxiliary panel stacking
  if OGRH.UnregisterAuxiliaryPanel then
    OGRH.UnregisterAuxiliaryPanel(panel)
  end

  -- Position from saved settings or center of screen
  local pos = RD.GetSetting("position")
  panel:ClearAllPoints()
  if pos and pos.point then
    panel:SetPoint(pos.point, UIParent, pos.point, pos.x or 0, pos.y or 0)
  else
    panel:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
  end

  -- Ensure the panel has a proper width when undocked
  panel:SetWidth(180)

  RD.isDocked = false

  if RD.State.debug then
    OGRH.Msg("|cffff6666[RH-ReadyDash][DEBUG]|r Panel undocked")
  end
end

-- ============================================
-- Show / Hide / Toggle
-- ============================================
function RD.ShowDashboard()
  local panel = OGRH_ReadynessDashboard
  if not panel then
    panel = RD.CreateDashboardPanel()
  end

  panel:Show()

  -- Apply dock state
  local savedDocked = RD.GetSetting("isDocked")
  if savedDocked ~= nil then
    RD.isDocked = savedDocked
  end

  if RD.isDocked then
    RD.Dock()
  else
    RD.Undock()
  end

  -- Start scanning and run immediate scan
  RD.StartScanning()
  RD.RunFullScan()
end

function RD.HideDashboard()
  local panel = OGRH_ReadynessDashboard
  if panel then
    -- Unregister from stacking so other panels reposition
    if RD.isDocked and OGRH.UnregisterAuxiliaryPanel then
      OGRH.UnregisterAuxiliaryPanel(panel)
    end
    panel:Hide()
  end
  RD.StopScanning()
end

function RD.ToggleDashboard()
  local panel = OGRH_ReadynessDashboard
  if panel and panel:IsVisible() then
    RD.HideDashboard()
  else
    RD.ShowDashboard()
  end
end

function RD.ResetDashboard()
  local panel = OGRH_ReadynessDashboard
  if panel then
    panel:Hide()
    if OGRH.UnregisterAuxiliaryPanel then
      OGRH.UnregisterAuxiliaryPanel(panel)
    end
  end

  -- Reset SVM settings
  RD.SetSetting("isDocked", true)
  RD.SetSetting("position", { point = "CENTER", x = 0, y = 0 })

  RD.isDocked = true

  -- Re-show
  RD.ShowDashboard()

  OGRH.Msg("|cffff6666[RH-ReadyDash]|r Dashboard position reset")
end

-- ============================================
-- Slash Command Handler (called from MainUI)
-- ============================================
function RD.HandleSlashCommand(args)
  if not args or args == "" then
    RD.ToggleDashboard()
    return
  end

  local sub = string.lower(args)

  if sub == "dock" then
    RD.Dock()
    OGRH.Msg("|cffff6666[RH-ReadyDash]|r Dashboard docked")
  elseif sub == "undock" then
    RD.Undock()
    OGRH.Msg("|cffff6666[RH-ReadyDash]|r Dashboard undocked")
  elseif sub == "scan" then
    RD.RunFullScan()
    OGRH.Msg("|cffff6666[RH-ReadyDash]|r Forced scan")
  elseif sub == "reset" then
    RD.ResetDashboard()
  else
    OGRH.Msg("|cffff6666[RH-ReadyDash]|r Usage: /ogrh ready [dock|undock|scan|reset]")
  end
end

-- ============================================
-- Module Initialization (deferred)
-- ============================================
-- CreateDashboardPanel is deferred until first Show or ADDON_LOADED
-- RD.Initialize() is called once, sets up SVM + events

-- Create an init frame that handles ADDON_LOADED, PLAYER_ENTERING_WORLD, and RAID_ROSTER_UPDATE
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
initFrame:RegisterEvent("RAID_ROSTER_UPDATE")

initFrame:SetScript("OnEvent", function()
  if event == "ADDON_LOADED" and arg1 == "OG-RaidHelper" then
    -- Initialize the core module
    RD.Initialize()

    -- Create the panel (but keep it hidden initially)
    RD.CreateDashboardPanel()

    initFrame:UnregisterEvent("ADDON_LOADED")
    return
  end

  -- Auto-show/hide based on raid status (fires on login and roster changes)
  if event == "PLAYER_ENTERING_WORLD" or event == "RAID_ROSTER_UPDATE" then
    if not OGRH_ReadynessDashboard then return end
    local enabled = RD.GetSetting("enabled")
    if enabled == false then return end

    if GetNumRaidMembers() > 0 then
      if not OGRH_ReadynessDashboard:IsVisible() then
        RD.ShowDashboard()
      end
    else
      if OGRH_ReadynessDashboard:IsVisible() then
        RD.HideDashboard()
      end
    end
  end
end)
