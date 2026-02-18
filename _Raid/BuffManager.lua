-- _Raid/BuffManager.lua
-- Buff Manager module for OG-RaidHelper
-- Provides multi-class buff coordination, assignment, tracking, and announcements.
-- Lives as a role (isBuffManager = true) inside the Admin encounter (encounter index 1).

if not OGRH then
  DEFAULT_CHAT_FRAME:AddMessage("|cffff0000Error: BuffManager requires OGRH_Core to be loaded first!|r")
  return
end

-- ============================================
-- NAMESPACE
-- ============================================
OGRH.BuffManager = OGRH.BuffManager or {}

-- ============================================
-- CONSTANTS: BUFF ROLE DEFINITIONS
-- ============================================
-- Default buff roles used to seed the Admin encounter's buffRoles table.
-- Each entry defines one class of raid buff with player assignment slots.

local BUFF_ROLE_DEFAULTS = {
  {
    buffRoleId = 1,
    name = "Paladin Blessings",
    shortName = "Pally",
    buffType = "paladin",
    requiredClass = "PALADIN",
    isPaladinRole = true,
    slots = 2,
    groupAssignments = {},
    assignedPlayers = {},
    paladinAssignments = {}
  },
  {
    buffRoleId = 2,
    name = "Mark of the Wild",
    shortName = "MotW",
    buffType = "motw",
    requiredClass = "DRUID",
    slots = 2,
    groupAssignments = {},
    assignedPlayers = {},
    hasImprovedTalent = true,
    improvedTalentName = "Improved Mark of the Wild",
    improvedTalentIcon = "Interface\\Icons\\Spell_Nature_Regeneration",
    improvedTalents = {}
  },
  {
    buffRoleId = 3,
    name = "Fortitude",
    shortName = "Fort",
    buffType = "fortitude",
    requiredClass = "PRIEST",
    slots = 2,
    groupAssignments = {},
    assignedPlayers = {},
    hasImprovedTalent = true,
    improvedTalentName = "Improved Power Word: Fortitude",
    improvedTalentIcon = "Interface\\Icons\\Spell_Holy_WordFortitude",
    improvedTalents = {}
  },
  {
    buffRoleId = 4,
    name = "Spirit",
    shortName = "Spirit",
    buffType = "spirit",
    requiredClass = "PRIEST",
    slots = 2,
    groupAssignments = {},
    assignedPlayers = {}
  },
  {
    buffRoleId = 5,
    name = "Shadow Protection",
    shortName = "SP",
    buffType = "shadowprot",
    requiredClass = "PRIEST",
    slots = 2,
    groupAssignments = {},
    assignedPlayers = {}
  },
  {
    buffRoleId = 6,
    name = "Arcane Brilliance",
    shortName = "Int",
    buffType = "int",
    requiredClass = "MAGE",
    slots = 2,
    groupAssignments = {},
    assignedPlayers = {}
  }
}

--- Talent scan definitions for auto-detecting improved talents on the local player.
-- Maps buffType → { tabIndex, talentName } for GetTalentInfo() scanning.
local IMPROVED_TALENT_SCAN = {
  motw      = { tabIndex = 3, talentName = "Improved Mark of the Wild" },   -- Druid Restoration
  fortitude = { tabIndex = 1, talentName = "Improved Power Word: Fortitude" }, -- Priest Discipline
}

-- ============================================
-- HELPERS
-- ============================================

--- Deep copy a table
local function DeepCopy(original)
  if type(original) ~= "table" then return original end
  local copy = {}
  for k, v in pairs(original) do
    copy[k] = DeepCopy(v)
  end
  return copy
end

--- Get the BuffManager role from the Admin encounter for a given raid
-- @param raidIdx number Raid index
-- @return role, roleIndex, encounterIdx  or nil
function OGRH.BuffManager.GetRole(raidIdx)
  if not raidIdx then return nil end
  OGRH.EnsureSV()
  local raids = OGRH.SVM.GetPath("encounterMgmt.raids")
  if not raids or not raids[raidIdx] then return nil end

  local raid = raids[raidIdx]
  if not raid.encounters or not raid.encounters[1] then return nil end

  local adminEnc = raid.encounters[1]
  if adminEnc.name ~= "Admin" or not adminEnc.roles then return nil end

  for i = 1, table.getn(adminEnc.roles) do
    if adminEnc.roles[i].isBuffManager then
      return adminEnc.roles[i], i, 1
    end
  end
  return nil
end

--- Ensure the buffRoles sub-table is populated with defaults.
-- Also migrates existing data to match the canonical order from BUFF_ROLE_DEFAULTS.
-- @param role table The BuffManager role from SVM
function OGRH.BuffManager.EnsureBuffRoles(role)
  if not role then return end
  if not role.buffRoles or table.getn(role.buffRoles) == 0 then
    role.buffRoles = DeepCopy(BUFF_ROLE_DEFAULTS)
    return
  end

  -- Migration: reorder existing buffRoles to match BUFF_ROLE_DEFAULTS order,
  -- preserving any player assignments and group assignments.
  local byType = {}
  for _, br in ipairs(role.buffRoles) do
    byType[br.buffType] = br
  end

  local reordered = {}
  for i, def in ipairs(BUFF_ROLE_DEFAULTS) do
    local existing = byType[def.buffType]
    if existing then
      existing.buffRoleId = def.buffRoleId  -- sync id to match new position
      -- Merge any new fields from defaults that the saved data doesn't have yet
      for k, v in pairs(def) do
        if existing[k] == nil then
          existing[k] = DeepCopy(v)
        end
      end
      table.insert(reordered, existing)
    else
      table.insert(reordered, DeepCopy(def))
    end
  end
  role.buffRoles = reordered
end

--- Get the SVM base path for a buff-manager role
local function SVMBase(raidIdx, encounterIdx, roleIndex)
  return string.format("encounterMgmt.raids.%d.encounters.%d.roles.%d", raidIdx, encounterIdx, roleIndex)
end

--- Build sync metadata matching the EncounterMgmt delta-sync pattern.
-- Active raid (idx 1) → REALTIME; non-active → MANUAL (no auto-sync).
local function BuildSyncMeta(raidIdx)
  local syncLevel = (raidIdx == 1) and "REALTIME" or "MANUAL"
  local raids = OGRH.SVM.GetPath("encounterMgmt.raids")
  local raidName = (raids and raids[raidIdx] and raids[raidIdx].name) or "Unknown"
  return {
    syncLevel = syncLevel,
    componentType = "assignments",
    scope = {
      raid = raidName,
      encounter = "Admin",
      isActiveRaid = (raidIdx == 1)
    }
  }
end

--- Check if the local player can edit buff assignments.
-- Returns true if: not in a raid, editing a non-active raid, or the player is
-- Admin/Leader/Assist.
function OGRH.BuffManager.CanEdit(raidIdx)
  if not raidIdx or raidIdx ~= 1 then return true end  -- non-active raid: anyone
  local numRaid = GetNumRaidMembers()
  if numRaid == 0 then return true end  -- not in a raid: anyone
  local playerName = UnitName("player")
  if OGRH.CanModifyStructure and OGRH.CanModifyStructure(playerName) then return true end
  if OGRH.CanModifyAssignments and OGRH.CanModifyAssignments(playerName) then return true end
  return false
end

--- Calculate how many slot rows to show for a buff role.
-- Rule: always show at least 2 rows; show one empty row beyond the highest assigned slot.
function OGRH.BuffManager.CalcVisibleSlots(buffRole)
  local minSlots = 2
  local highestAssigned = 0
  if buffRole.assignedPlayers then
    for idx, name in pairs(buffRole.assignedPlayers) do
      if name and name ~= "" then
        local n = tonumber(idx) or idx
        if type(n) == "number" and n > highestAssigned then
          highestAssigned = n
        end
      end
    end
  end
  -- Show one empty row beyond the last assigned
  local needed = highestAssigned + 1
  if needed < minSlots then needed = minSlots end
  return needed
end

-- ============================================
-- BUFF DETECTION
-- ============================================

--- Classify a buff name into one of our tracked buff types
-- @param buffName string
-- @return string|nil  One of "fortitude","spirit","shadowprot","motw","int","paladin" or nil
function OGRH.BuffManager.GetBuffCategory(buffName)
  if not buffName then return nil end
  if string.find(buffName, "Fortitude") then return "fortitude" end
  if string.find(buffName, "Divine Spirit") or string.find(buffName, "Prayer of Spirit") then return "spirit" end
  if string.find(buffName, "Shadow Protection") then return "shadowprot" end
  if string.find(buffName, "Mark of the Wild") or string.find(buffName, "Gift of the Wild") then return "motw" end
  if string.find(buffName, "Arcane Intellect") or string.find(buffName, "Arcane Brilliance") then return "int" end
  if string.find(buffName, "Blessing of") or string.find(buffName, "Greater Blessing") then return "paladin" end
  return nil
end

-- ============================================
-- SCANNING
-- ============================================

--- Scan all raid members' buffs and store the result
-- @return table  {timestamp, players = {[name] = {class,group,buffs={[category]=true}}}}
function OGRH.BuffManager.ScanRaidBuffs()
  local data = { timestamp = GetTime(), players = {} }

  local numRaid = GetNumRaidMembers()
  for i = 1, numRaid do
    local name, _, subgroup, _, class = GetRaidRosterInfo(i)
    if name then
      local unitId = "raid" .. i
      local buffs = {}
      for slot = 1, 32 do
        local buffName = UnitBuff(unitId, slot)
        if not buffName then break end
        local cat = OGRH.BuffManager.GetBuffCategory(buffName)
        if cat then
          buffs[cat] = true
        end
      end
      data.players[name] = {
        class = class,
        group = subgroup,
        buffs = buffs
      }
    end
  end

  OGRH.BuffManager.lastScan = data
  return data
end

-- ============================================
-- COVERAGE
-- ============================================

--- Calculate how many raid members have a specific buff type
-- @param buffType string  e.g. "fortitude"
-- @return table {buffed=n, total=n, percent=n, missing={}}
function OGRH.BuffManager.CalculateCoverage(buffType)
  local result = {buffed = 0, total = 0, percent = 0, missing = {}}
  local scan = OGRH.BuffManager.lastScan
  if not scan or not scan.players then return result end

  for name, pdata in pairs(scan.players) do
    result.total = result.total + 1
    if pdata.buffs[buffType] then
      result.buffed = result.buffed + 1
    else
      table.insert(result.missing, {name = name, class = pdata.class, group = pdata.group})
    end
  end

  if result.total > 0 then
    result.percent = math.floor((result.buffed / result.total) * 100)
  end
  return result
end

-- ============================================
-- ADMIN ROLE RENDERING (compact summary)
-- ============================================

--- Render the compact buff status inside the Admin encounter's role container.
-- Called by EncounterMgmt when it hits a role with isBuffManager = true.
--
-- Layout:
--   Row 1: buff type labels
--   Row 2: colored indicator panels
--   Row 3: percentage numbers
--   Bottom: "Manage Buffs" button
--
function OGRH.RenderBuffManagerRole(container, role, roleIndex, raidIdx, encounterIdx, containerWidth)
  if not role or not role.isBuffManager then return nil end

  -- Ensure data exists
  OGRH.BuffManager.EnsureBuffRoles(role)

  local frame = CreateFrame("Frame", nil, container)
  frame:SetWidth(containerWidth - 10)
  frame:SetHeight(65)
  frame:SetPoint("TOPLEFT", container, "TOPLEFT", 5, -25)

  -- Top row: buff type short names + indicators
  local buffTypes = {}
  for i = 1, table.getn(role.buffRoles) do
    table.insert(buffTypes, {
      short = role.buffRoles[i].shortName or role.buffRoles[i].name,
      type  = role.buffRoles[i].buffType
    })
  end

  local numTypes = table.getn(buffTypes)
  local indicatorW = 30
  local spacing = 6
  local totalW = numTypes * indicatorW + (numTypes - 1) * spacing
  local startX = math.floor(((containerWidth - 10) - totalW) / 2)

  -- Store indicator references for dynamic updates
  frame.indicators = {}

  for idx, bt in ipairs(buffTypes) do
    local x = startX + (idx - 1) * (indicatorW + spacing)

    -- Label
    local lbl = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("TOPLEFT", frame, "TOPLEFT", x, 0)
    lbl:SetText(bt.short)
    lbl:SetTextColor(0.8, 0.8, 0.8)

    -- Colored indicator
    local indicator = OGST.CreateColoredPanel(frame, indicatorW, 10,
      {r = 0.3, g = 0.3, b = 0.3},
      {r = 0.2, g = 0.2, b = 0.2, a = 0.8}
    )
    indicator:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -14)
    indicator.buffType = bt.type

    -- Percentage text
    local pctText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pctText:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -28)
    pctText:SetText("--")
    pctText:SetTextColor(0.6, 0.6, 0.6)

    frame.indicators[idx] = {panel = indicator, pctText = pctText, buffType = bt.type}
  end

  -- "Manage Buffs" button (centered at bottom)
  local manageBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  manageBtn:SetWidth(105)
  manageBtn:SetHeight(20)
  manageBtn:SetPoint("BOTTOM", frame, "BOTTOM", 0, 0)
  manageBtn:SetText("Manage Buffs")
  OGRH.StyleButton(manageBtn)

  manageBtn:SetScript("OnClick", function()
    OGRH.BuffManager.ShowWindow(raidIdx, encounterIdx, roleIndex)
  end)

  -- Update indicators from last scan (if any)
  OGRH.BuffManager.RefreshIndicators(frame)

  -- Keep reference so we can refresh later
  container.buffIndicatorFrame = frame
  return frame
end

--- Refresh the small coloured indicators inside the admin role
function OGRH.BuffManager.RefreshIndicators(frame)
  if not frame or not frame.indicators then return end

  for _, ind in ipairs(frame.indicators) do
    local cov = OGRH.BuffManager.CalculateCoverage(ind.buffType)
    local pct = cov.percent

    -- Color coding
    local r, g, b
    if cov.total == 0 then
      r, g, b = 0.3, 0.3, 0.3  -- gray = no data
    elseif pct >= 100 then
      r, g, b = 0.0, 0.8, 0.0  -- green
    elseif pct >= 80 then
      r, g, b = 0.9, 0.9, 0.0  -- yellow
    else
      r, g, b = 0.9, 0.2, 0.2  -- red
    end

    if ind.panel.bg then
      ind.panel.bg:SetVertexColor(r, g, b, 1)
    end
    if cov.total > 0 then
      ind.pctText:SetText(pct .. "%")
    else
      ind.pctText:SetText("--")
    end
  end
end

-- ============================================
-- BUFF MANAGER WINDOW
-- ============================================

--- Open (or re-show) the full Buff Manager configuration window.
function OGRH.BuffManager.ShowWindow(raidIdx, encounterIdx, roleIndex)
  local canEdit = OGRH.BuffManager.CanEdit(raidIdx)

  -- Re-show existing window (destroy + recreate if permissions changed)
  if OGRH.BuffManager.window then
    if OGRH.BuffManager.window.canEdit ~= canEdit then
      OGRH.BuffManager.window:Hide()
      OGRH.BuffManager.window = nil
    else
      -- Update stored context in case raid switched
      OGRH.BuffManager.window.raidIdx = raidIdx
      OGRH.BuffManager.window.encounterIdx = encounterIdx
      OGRH.BuffManager.window.roleIndex = roleIndex
      OGRH.BuffManager.window:Show()
      OGRH.BuffManager.RefreshWindow()
      return
    end
  end

  -- Fetch the role data & seed defaults
  local role = OGRH.BuffManager.GetRole(raidIdx)
  if not role then
    OGRH.Msg("|cffff6666[BuffManager]|r Could not find Buff Manager role data.")
    return
  end
  OGRH.BuffManager.EnsureBuffRoles(role)

  -- -------------------------------------------------------
  -- Create window via OGST — size depends on edit permission
  -- -------------------------------------------------------
  local canEdit = OGRH.BuffManager.CanEdit(raidIdx)
  local rosterWidth = 210
  local gap = 5
  local windowWidth = canEdit and 710 or 490

  local window = OGST.CreateStandardWindow({
    name = "OGRHBuffManagerWindow",
    title = "Buff Manager",
    width = windowWidth,
    height = 550
  })

  window.raidIdx = raidIdx
  window.encounterIdx = encounterIdx
  window.roleIndex = roleIndex
  window.canEdit = canEdit

  -- "Auto Assign All" button in the header (editors only)
  if canEdit and window.closeButton then
    local assignAllBtn = OGST.CreateButton(window.headerFrame, {
      text = "Auto Assign All",
      width = 120,
      height = 24,
      onClick = function()
        OGRH.BuffManager.RunAutoAssignAll()
      end
    })
    assignAllBtn:SetPoint("RIGHT", window.closeButton, "LEFT", -5, 0)
    assignAllBtn:SetScript("OnEnter", function()
      this:SetBackdropColor(0.3, 0.45, 0.45, 1)
      this:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
    end)
    assignAllBtn:SetScript("OnLeave", function()
      this:SetBackdropColor(0.25, 0.35, 0.35, 1)
      this:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    end)
    window.assignAllBtn = assignAllBtn
  end

  local content = window.contentFrame

  -- -------------------------------------------------------
  -- Left side: scrollable buff sections
  -- -------------------------------------------------------
  local leftWidth = canEdit and (windowWidth - 10 - rosterWidth - gap) or (windowWidth - 10)
  local leftFrame = CreateFrame("Frame", nil, content)
  leftFrame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
  leftFrame:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 0, 0)
  leftFrame:SetWidth(leftWidth)

  local listFrame, scrollFrame, scrollChild, scrollBar, scrollContentWidth =
    OGRH.CreateStyledScrollList(leftFrame, leftWidth, 505)
  listFrame:SetPoint("TOPLEFT", leftFrame, "TOPLEFT", 0, 0)
  window.buffScrollChild = scrollChild
  window.buffScrollFrame = scrollFrame
  window.buffScrollBar = scrollBar
  window.buffContentWidth = scrollContentWidth  -- store for section sizing

  -- -------------------------------------------------------
  -- Right side: roster panel (only for editors)
  -- -------------------------------------------------------
  if canEdit then
    local rosterPanel = OGRH.CreateRosterPanel(content, {
      width = rosterWidth,
      height = 505,
      anchor = {"TOPLEFT", listFrame, "TOPRIGHT", gap, 0},
      showUnassignedFilter = false,
      showGuildMembers = true,
      defaultSource = "Raid",

      -- Permission check
      canDrag = function()
        return OGRH.BuffManager.CanEdit(raidIdx)
      end,

      -- Drag start: just mark what is being dragged
      onDragStart = function(panel, playerName, playerClass, classColor)
        -- nothing beyond what the panel already does
      end,

      -- Drag stop: hit-test against assignment slots
      onDragStop = function(panel, playerName, playerClass)
        local slots = OGRH.BuffManager.GetAllDropSlots()
        if not slots then return end

        for _, slot in ipairs(slots) do
          if slot:IsVisible() and MouseIsOver(slot) then
            -- Assign this player to the slot
            OGRH.BuffManager.AssignPlayerToSlot(slot.buffRoleId, slot.slotIndex, playerName)
            OGRH.BuffManager.RefreshWindow()
            return
          end
        end
      end
    })
    window.rosterPanel = rosterPanel
  end

  OGRH.BuffManager.window = window

  -- Initial render
  OGRH.BuffManager.RefreshWindow()
  window:Show()
end

-- ============================================
-- WINDOW REFRESH
-- ============================================

-- Hidden frame used as recycling bin — reparenting here removes frames from
-- the scroll child's hit-test tree without leaking (WoW 1.12 cannot destroy frames).
local recyclingBin = CreateFrame("Frame")
recyclingBin:Hide()

--- Recursively disable mouse interaction on a frame and all its children.
--- This ensures recycled frames don't participate in WoW's per-frame hit-testing.
local function DisableMouseRecursive(frame)
  if frame.EnableMouse then frame:EnableMouse(false) end
  local children = { frame:GetChildren() }
  for _, child in ipairs(children) do
    DisableMouseRecursive(child)
  end
end

--- Rebuild the buff sections inside the window's scroll child.
function OGRH.BuffManager.RefreshWindow()
  local window = OGRH.BuffManager.window
  if not window then return end

  local role = OGRH.BuffManager.GetRole(window.raidIdx)
  if not role then return end
  OGRH.BuffManager.EnsureBuffRoles(role)

  local sc = window.buffScrollChild
  if not sc then return end

  -- Recycle previous children into the hidden bin
  local children = {sc:GetChildren()}
  for _, child in ipairs(children) do
    child:Hide()
    DisableMouseRecursive(child)
    child:SetParent(recyclingBin)
  end

  -- Reset drop slot registry
  OGRH.BuffManager.dropSlots = {}

  local yOffset = 0
  local sectionWidth = window.buffContentWidth or 445

  for brIdx = 1, table.getn(role.buffRoles) do
    local br = role.buffRoles[brIdx]

    -- Section panel
    local section = OGRH.BuffManager.CreateBuffSection(sc, br, brIdx, sectionWidth,
      window.raidIdx, window.encounterIdx, window.roleIndex)
    section:SetPoint("TOPLEFT", sc, "TOPLEFT", 0, -yOffset)

    yOffset = yOffset + section:GetHeight() + 8
  end

  sc:SetHeight(math.max(yOffset, 1))

  -- Update scroll range, preserving current position
  if window.buffScrollFrame and window.buffScrollBar then
    local frameH = window.buffScrollFrame:GetHeight()
    local prevScroll = window.buffScrollFrame:GetVerticalScroll() or 0
    if yOffset > frameH then
      window.buffScrollBar:Show()
      window.buffScrollBar:SetMinMaxValues(0, yOffset - frameH)
      local maxScroll = yOffset - frameH
      local restored = math.min(prevScroll, maxScroll)
      window.buffScrollBar:SetValue(restored)
      window.buffScrollFrame:SetVerticalScroll(restored)
    else
      window.buffScrollBar:Hide()
      window.buffScrollFrame:SetVerticalScroll(0)
    end
  end

  -- Also refresh the roster panel
  if window.rosterPanel then
    window.rosterPanel:Refresh()
  end
end

-- ============================================
-- PALADIN BLESSING DEFINITIONS
-- ============================================

local PALADIN_CLASSES = {
  "WARRIOR", "ROGUE", "PRIEST", "DRUID", "PALADIN", "HUNTER", "MAGE", "WARLOCK", "SHAMAN"
}

local PALADIN_CLASS_DISPLAY = {
  WARRIOR = "Warrior", ROGUE = "Rogue", HUNTER = "Hunter", MAGE = "Mage",
  WARLOCK = "Warlock", PRIEST = "Priest", DRUID = "Druid", SHAMAN = "Shaman", PALADIN = "Paladin"
}

local PP_ICON_PATH = "Interface\\AddOns\\OG-RaidHelper\\textures\\PPIcons\\"

local BLESSING_OPTIONS = {
  { key = "kings",      name = "Kings",      icon = PP_ICON_PATH .. "Spell_Magic_GreaterBlessingofKings" },
  { key = "wisdom",     name = "Wisdom",     icon = PP_ICON_PATH .. "Spell_Holy_SealOfWisdom" },
  { key = "might",      name = "Might",      icon = PP_ICON_PATH .. "Spell_Holy_FistOfJustice" },
  { key = "salvation",  name = "Salvation",   icon = PP_ICON_PATH .. "Spell_Holy_SealOfSalvation" },
  { key = "light",      name = "Light",      icon = PP_ICON_PATH .. "Spell_Holy_GreaterBlessingofLight" },
  { key = "sanctuary",  name = "Sanctuary",  icon = PP_ICON_PATH .. "Spell_Holy_GreaterBlessingofSanctuary" },
}

--- Get the blessing option table by key
local function GetBlessingByKey(key)
  if not key then return nil end
  for _, b in ipairs(BLESSING_OPTIONS) do
    if b.key == key then return b end
  end
  return nil
end

-- ============================================
-- BUFF SECTION WIDGET
-- ============================================

--- Create a shared section frame with title and backdrop.
-- @return section, numSlots
local function CreateSectionFrame(parent, buffRole, brIdx, width, extraHeight)
  -- Check if auto-assign button should be shown
  local window = OGRH.BuffManager.window
  local raidIdx = window and window.raidIdx or 1
  local showAutoAssign = OGRH.BuffManager.CanEdit(raidIdx) and GetNumRaidMembers() > 0
  local autoAssignH = showAutoAssign and 28 or 0

  local numSlots = OGRH.BuffManager.CalcVisibleSlots(buffRole)
  local sectionH = 28 + autoAssignH + numSlots * 26 + 6 + (extraHeight or 0)

  local section = CreateFrame("Frame", nil, parent)
  section:SetWidth(width)
  section:SetHeight(sectionH)
  section:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 8,
    insets = {left = 2, right = 2, top = 2, bottom = 2}
  })
  section:SetBackdropColor(0.12, 0.12, 0.12, 0.9)

  -- Title
  local classLabel = buffRole.requiredClass
                     and (" (" .. string.sub(buffRole.requiredClass, 1, 1) .. string.lower(string.sub(buffRole.requiredClass, 2)) .. ")")
                     or ""
  local title = section:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", section, "TOPLEFT", 8, -8)
  title:SetText((buffRole.name or "Buff") .. classLabel)

  -- Auto Assign button (between title and player content)
  if showAutoAssign then
    local capturedBrIdx = brIdx
    local autoBtn = OGST.CreateButton(section, {
      text = "Auto Assign",
      width = 100,
      height = 24,
      onClick = function()
        OGRH.BuffManager.RunAutoAssign(capturedBrIdx)
      end
    })
    autoBtn:SetPoint("TOPLEFT", section, "TOPLEFT", 32, -26)

    -- Re-apply hover scripts (OGST.AddDesignTooltip overwrites StyleButton's OnEnter/OnLeave)
    autoBtn:SetScript("OnEnter", function()
      this:SetBackdropColor(0.3, 0.45, 0.45, 1)
      this:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
    end)
    autoBtn:SetScript("OnLeave", function()
      this:SetBackdropColor(0.25, 0.35, 0.35, 1)
      this:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    end)

    section.autoAssignBtn = autoBtn
  end

  return section, numSlots, autoAssignH
end

--- Create the player assign button + slot label shared by both section types.
-- @return assignBtn
local function CreatePlayerSlot(section, brIdx, slotIdx, buffRole, rowY)
  -- Slot label "P1:"
  local slotLabel = section:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  slotLabel:SetPoint("TOPLEFT", section, "TOPLEFT", 8, rowY - 3)
  slotLabel:SetText("|cffaaaaaaP" .. slotIdx .. ":|r")

  -- Player assignment button (drop target)
  local assignBtn = CreateFrame("Button", nil, section)
  assignBtn:SetWidth(100)
  assignBtn:SetHeight(20)
  assignBtn:SetPoint("TOPLEFT", section, "TOPLEFT", 32, rowY)

  local assignBg = assignBtn:CreateTexture(nil, "BACKGROUND")
  assignBg:SetAllPoints()
  assignBg:SetTexture("Interface\\Buttons\\WHITE8X8")
  assignBg:SetVertexColor(0.15, 0.15, 0.15, 0.9)
  assignBtn.bg = assignBg

  local assignText = assignBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  assignText:SetPoint("LEFT", assignBtn, "LEFT", 4, 0)
  assignText:SetPoint("RIGHT", assignBtn, "RIGHT", -4, 0)
  assignText:SetJustifyH("LEFT")
  assignBtn.nameText = assignText

  -- Store metadata for drop targeting
  assignBtn.buffRoleId = brIdx
  assignBtn.slotIndex = slotIdx
  assignBtn:EnableMouse(true)
  assignBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

  -- Show current assignment
  local playerName = buffRole.assignedPlayers and buffRole.assignedPlayers[slotIdx]
  if playerName and playerName ~= "" then
    assignText:SetText(playerName)
    local pc = OGRH.GetPlayerClass(playerName)
    if pc and RAID_CLASS_COLORS[pc] then
      local cc = RAID_CLASS_COLORS[pc]
      assignText:SetTextColor(cc.r, cc.g, cc.b)
    else
      assignText:SetTextColor(1, 1, 1)
    end
  else
    assignText:SetText("|cff666666<assign>|r")
    assignText:SetTextColor(0.5, 0.5, 0.5)
  end

  -- Right-click to clear
  local capturedSlotIdx = slotIdx
  local capturedBrIdx = brIdx
  assignBtn:SetScript("OnClick", function()
    if arg1 == "RightButton" then
      OGRH.BuffManager.AssignPlayerToSlot(capturedBrIdx, capturedSlotIdx, nil)
      OGRH.BuffManager.RefreshWindow()
    end
  end)

  -- Highlight on hover
  assignBtn:SetScript("OnEnter", function()
    assignBg:SetVertexColor(0.25, 0.25, 0.3, 0.9)
    GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
    GameTooltip:SetText("Player Slot " .. capturedSlotIdx, 1, 1, 1)
    GameTooltip:AddLine("Drag a player here or right-click to clear", 0.8, 0.8, 0.8, 1)
    GameTooltip:Show()
  end)
  assignBtn:SetScript("OnLeave", function()
    assignBg:SetVertexColor(0.15, 0.15, 0.15, 0.9)
    GameTooltip:Hide()
  end)

  -- Register as drop target
  table.insert(OGRH.BuffManager.dropSlots or {}, assignBtn)

  return assignBtn
end



-- ============================================
-- PALADIN BLESSING SECTION
-- ============================================

--- Paladin talent options for the multi-select menu.
-- Each paladin player slot can toggle which talents/abilities they have.
local PALADIN_TALENT_OPTIONS = {
  {
    key = "improved",
    name = "Improved",
    icons = {
      PP_ICON_PATH .. "Spell_Holy_FistOfJustice",           -- Might
      PP_ICON_PATH .. "Spell_Holy_SealOfWisdom",            -- Wisdom
    }
  },
  {
    key = "kings",
    name = "Kings",
    icons = { PP_ICON_PATH .. "Spell_Magic_GreaterBlessingofKings" }
  },
  {
    key = "sanctuary",
    name = "Sanctuary",
    icons = { PP_ICON_PATH .. "Spell_Holy_GreaterBlessingofSanctuary" }
  },
}

--- Show a multi-select popup for paladin talents on a given slot.
local function ShowTalentMenu(anchorBtn, brIdx, slotIdx, buffRole, raidIdx, encounterIdx, roleIndex)
  local menuName = "OGRHPaladinTalentMenu"
  local menuFrame = getglobal(menuName)
  if not menuFrame then
    menuFrame = CreateFrame("Frame", menuName, UIParent)
    menuFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    menuFrame:SetWidth(160)
    menuFrame:SetBackdrop({
      bgFile = "Interface/Tooltips/UI-Tooltip-Background",
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 12,
      insets = {left = 3, right = 3, top = 3, bottom = 3}
    })
    menuFrame:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
    menuFrame:EnableMouse(true)
    menuFrame:Hide()
  end

  -- Clear old children
  local oldChildren = { menuFrame:GetChildren() }
  for _, child in ipairs(oldChildren) do child:Hide(); child:SetParent(nil) end

  -- Read current talents
  local talents = {}
  if buffRole.paladinTalents and buffRole.paladinTalents[slotIdx] then
    talents = buffRole.paladinTalents[slotIdx]
  end

  local itemH = 24
  local numItems = table.getn(PALADIN_TALENT_OPTIONS)
  local totalH = numItems * itemH + 8
  menuFrame:SetHeight(totalH)
  menuFrame:ClearAllPoints()
  menuFrame:SetPoint("TOPLEFT", anchorBtn, "BOTTOMLEFT", 0, 0)
  menuFrame:Show()

  for i, opt in ipairs(PALADIN_TALENT_OPTIONS) do
    local btn = CreateFrame("Button", nil, menuFrame)
    btn:SetWidth(154)
    btn:SetHeight(itemH)
    btn:SetPoint("TOPLEFT", menuFrame, "TOPLEFT", 3, -((i - 1) * itemH) - 4)

    -- Icons (one or two, side by side)
    local iconOffset = 2
    for _, iconPath in ipairs(opt.icons) do
      local ico = btn:CreateTexture(nil, "ARTWORK")
      ico:SetWidth(16)
      ico:SetHeight(16)
      ico:SetPoint("LEFT", btn, "LEFT", iconOffset, 0)
      ico:SetTexture(iconPath)
      iconOffset = iconOffset + 18
    end

    -- Label: green if selected, grey if not
    local isSelected = talents[opt.key] and true or false
    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", btn, "LEFT", iconOffset + 2, 0)
    if isSelected then
      label:SetText("|cff00ff00" .. opt.name .. "|r")
    else
      label:SetText("|cff888888" .. opt.name .. "|r")
    end

    -- Highlight
    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture("Interface\\Buttons\\WHITE8X8")
    hl:SetVertexColor(0.3, 0.3, 0.5, 0.4)

    local capturedKey = opt.key
    btn:SetScript("OnClick", function()
      OGRH.BuffManager.TogglePaladinTalent(brIdx, slotIdx, capturedKey, raidIdx, encounterIdx, roleIndex)
      -- Re-show with updated state
      ShowTalentMenu(anchorBtn, brIdx, slotIdx, buffRole, raidIdx, encounterIdx, roleIndex)
    end)
  end

  -- Auto-hide; refresh when menu closes so the talent icon updates
  menuFrame:SetScript("OnUpdate", function()
    if not MouseIsOver(menuFrame) and not MouseIsOver(anchorBtn) then
      menuFrame:Hide()
      OGRH.BuffManager.RefreshWindow()
    end
  end)
end

--- Show a popup menu to pick a blessing for a given paladin slot + class.
local function ShowBlessingMenu(anchorBtn, brIdx, slotIdx, className, raidIdx, encounterIdx, roleIndex)
  -- Reuse or create the shared menu frame
  local menuName = "OGRHBlessingMenu"
  local menuFrame = getglobal(menuName)
  if not menuFrame then
    menuFrame = CreateFrame("Frame", menuName, UIParent)
    menuFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    menuFrame:SetWidth(130)
    menuFrame:SetBackdrop({
      bgFile = "Interface/Tooltips/UI-Tooltip-Background",
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 12,
      insets = {left = 3, right = 3, top = 3, bottom = 3}
    })
    menuFrame:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
    menuFrame:EnableMouse(true)
    menuFrame:Hide()
  end

  -- Clear old children
  local oldChildren = { menuFrame:GetChildren() }
  for _, child in ipairs(oldChildren) do child:Hide(); child:SetParent(nil) end

  -- Read paladin talents for this slot to filter available blessings
  local window = OGRH.BuffManager.window
  local talents = {}
  if window then
    local role = OGRH.BuffManager.GetRole(window.raidIdx)
    if role then
      OGRH.BuffManager.EnsureBuffRoles(role)
      local br = role.buffRoles[brIdx]
      if br and br.paladinTalents and br.paladinTalents[slotIdx] then
        talents = br.paladinTalents[slotIdx]
      end
    end
  end

  -- "None" option + blessing options filtered by talents
  local items = { { key = nil, name = "None", icon = nil } }
  for _, b in ipairs(BLESSING_OPTIONS) do
    local show = true
    if b.key == "kings" and not talents.kings then show = false end
    if b.key == "sanctuary" and not talents.sanctuary then show = false end
    if show then
      table.insert(items, b)
    end
  end

  local itemH = 22
  local totalH = table.getn(items) * itemH + 8
  menuFrame:SetHeight(totalH)
  menuFrame:ClearAllPoints()
  menuFrame:SetPoint("TOPLEFT", anchorBtn, "BOTTOMLEFT", 0, 0)
  menuFrame:Show()

  for i, item in ipairs(items) do
    local btn = CreateFrame("Button", nil, menuFrame)
    btn:SetWidth(124)
    btn:SetHeight(itemH)
    btn:SetPoint("TOPLEFT", menuFrame, "TOPLEFT", 3, -((i - 1) * itemH) - 4)

    -- Icon (16x16)
    if item.icon then
      local ico = btn:CreateTexture(nil, "ARTWORK")
      ico:SetWidth(16)
      ico:SetHeight(16)
      ico:SetPoint("LEFT", btn, "LEFT", 2, 0)
      ico:SetTexture(item.icon)
    end

    -- Label
    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", btn, "LEFT", item.icon and 22 or 4, 0)
    label:SetText(item.name)

    -- Highlight
    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture("Interface\\Buttons\\WHITE8X8")
    hl:SetVertexColor(0.3, 0.3, 0.5, 0.4)

    local capturedKey = item.key
    btn:SetScript("OnClick", function()
      OGRH.BuffManager.SetPaladinBlessing(brIdx, slotIdx, className, capturedKey, raidIdx, encounterIdx, roleIndex)
      menuFrame:Hide()
      OGRH.BuffManager.RefreshWindow()
    end)
  end

  -- Auto-hide
  menuFrame:SetScript("OnUpdate", function()
    if not MouseIsOver(menuFrame) and not MouseIsOver(anchorBtn) then
      menuFrame:Hide()
    end
  end)
end

--- Create the Paladin Blessings section with class icon headers and spell icon buttons.
local function CreatePaladinBuffSection(parent, buffRole, brIdx, width, raidIdx, encounterIdx, roleIndex)
  local numClasses = table.getn(PALADIN_CLASSES)
  local colWidth = 26
  local headerRowH = 24  -- class icon header row height
  -- When auto-assign button is shown, class icons sit beside it (different X range)
  -- so no extra height needed.  When hidden, we need the header row space.
  local section, numSlots, autoAssignH = CreateSectionFrame(parent, buffRole, brIdx, width, 0)
  if autoAssignH == 0 then
    -- No auto-assign button — reserve space for class icon header row
    local sectionH = 28 + headerRowH + numSlots * 26 + 6
    section:SetHeight(sectionH)
  end

  local contentTop = -28 - autoAssignH  -- first player row Y (matches standard sections)
  local classStartX = 166  -- shifted right to make room for talent button

  -- Class icon headers — when auto-assign shown, sit alongside the button;
  -- when hidden, sit between title and first player row.
  local iconY = autoAssignH > 0 and -30 or -28

  for ci = 1, numClasses do
    local cls = PALADIN_CLASSES[ci]
    local iconX = classStartX + (ci - 1) * colWidth
    local iconBtn = CreateFrame("Button", nil, section)
    iconBtn:SetWidth(20)
    iconBtn:SetHeight(20)
    iconBtn:SetPoint("TOPLEFT", section, "TOPLEFT", iconX, iconY)

    local iconTex = iconBtn:CreateTexture(nil, "ARTWORK")
    iconTex:SetAllPoints()
    local classFile = PALADIN_CLASS_DISPLAY[cls]
    iconTex:SetTexture(PP_ICON_PATH .. "Class-" .. classFile)

    -- Tooltip
    local capturedCls = cls
    iconBtn:SetScript("OnEnter", function()
      GameTooltip:SetOwner(this, "ANCHOR_TOP")
      GameTooltip:SetText(PALADIN_CLASS_DISPLAY[capturedCls], 1, 1, 1)
      GameTooltip:Show()
    end)
    iconBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end

  -- Player rows with blessing icon buttons per class
  -- When no auto-assign, rows start below the icon header row
  local rowStartY = autoAssignH > 0 and contentTop or (-28 - headerRowH)
  for slotIdx = 1, numSlots do
    local rowY = rowStartY - ((slotIdx - 1) * 26)
    CreatePlayerSlot(section, brIdx, slotIdx, buffRole, rowY)

    -- Talent toggle button (between player name and class columns)
    local talentBtn = CreateFrame("Button", nil, section)
    talentBtn:SetWidth(20)
    talentBtn:SetHeight(20)
    talentBtn:SetPoint("TOPLEFT", section, "TOPLEFT", 140, rowY)

    local talentBg = talentBtn:CreateTexture(nil, "BACKGROUND")
    talentBg:SetAllPoints()
    talentBg:SetTexture("Interface\\Buttons\\WHITE8X8")
    talentBg:SetVertexColor(0.15, 0.15, 0.15, 0.6)

    -- Show a small gear/talent indicator
    local talentIcon = talentBtn:CreateTexture(nil, "ARTWORK")
    talentIcon:SetWidth(16)
    talentIcon:SetHeight(16)
    talentIcon:SetPoint("CENTER", talentBtn, "CENTER", 0, 0)
    talentIcon:SetTexture("Interface\\Icons\\Spell_Holy_SealOfWisdom")

    -- Count active talents for visual feedback
    local talents = (buffRole.paladinTalents and buffRole.paladinTalents[slotIdx]) or {}
    local talentCount = 0
    if talents.improved then talentCount = talentCount + 1 end
    if talents.kings then talentCount = talentCount + 1 end
    if talents.sanctuary then talentCount = talentCount + 1 end
    if talentCount > 0 then
      talentIcon:SetVertexColor(0.2, 1, 0.2, 1)  -- green tint when talents set
    else
      talentIcon:SetVertexColor(0.5, 0.5, 0.5, 0.6)  -- dim when no talents
    end

    local hlTex = talentBtn:CreateTexture(nil, "HIGHLIGHT")
    hlTex:SetAllPoints()
    hlTex:SetTexture("Interface\\Buttons\\WHITE8X8")
    hlTex:SetVertexColor(0.4, 0.4, 0.6, 0.3)

    local capturedSlotIdx = slotIdx
    local capturedBrIdx = brIdx
    talentBtn:SetScript("OnClick", function()
      ShowTalentMenu(talentBtn, capturedBrIdx, capturedSlotIdx, buffRole, raidIdx, encounterIdx, roleIndex)
    end)
    talentBtn:SetScript("OnEnter", function()
      GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
      GameTooltip:SetText("Paladin Talents", 1, 1, 1)
      local t = (buffRole.paladinTalents and buffRole.paladinTalents[capturedSlotIdx]) or {}
      if t.improved then GameTooltip:AddLine("Improved Might/Wisdom", 0, 1, 0) end
      if t.kings then GameTooltip:AddLine("Kings", 0, 1, 0) end
      if t.sanctuary then GameTooltip:AddLine("Sanctuary", 0, 1, 0) end
      if not (t.improved or t.kings or t.sanctuary) then
        GameTooltip:AddLine("Click to set talents", 0.6, 0.6, 0.6)
      end
      GameTooltip:Show()
    end)
    talentBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Blessing icon buttons (one per class)
    for ci = 1, numClasses do
      local cls = PALADIN_CLASSES[ci]
      local btnX = classStartX + (ci - 1) * colWidth
      local blessBtn = CreateFrame("Button", nil, section)
      blessBtn:SetWidth(20)
      blessBtn:SetHeight(20)
      blessBtn:SetPoint("TOPLEFT", section, "TOPLEFT", btnX, rowY)

      -- Background for empty state
      local bgTex = blessBtn:CreateTexture(nil, "BACKGROUND")
      bgTex:SetAllPoints()
      bgTex:SetTexture("Interface\\Buttons\\WHITE8X8")
      bgTex:SetVertexColor(0.15, 0.15, 0.15, 0.6)

      -- Spell icon overlay
      local spellTex = blessBtn:CreateTexture(nil, "ARTWORK")
      spellTex:SetAllPoints()

      -- Look up current assignment
      local currentKey = nil
      if buffRole.paladinAssignments and buffRole.paladinAssignments[slotIdx] then
        currentKey = buffRole.paladinAssignments[slotIdx][cls]
      end
      local blessing = GetBlessingByKey(currentKey)
      if blessing then
        spellTex:SetTexture(blessing.icon)
        spellTex:Show()
      else
        spellTex:Hide()
      end

      -- Highlight
      local hlTex = blessBtn:CreateTexture(nil, "HIGHLIGHT")
      hlTex:SetAllPoints()
      hlTex:SetTexture("Interface\\Buttons\\WHITE8X8")
      hlTex:SetVertexColor(0.4, 0.4, 0.6, 0.3)

      -- Click to open blessing picker
      local capturedSlotIdx = slotIdx
      local capturedBrIdx = brIdx
      local capturedCls = cls
      blessBtn:SetScript("OnClick", function()
        ShowBlessingMenu(blessBtn, capturedBrIdx, capturedSlotIdx, capturedCls, raidIdx, encounterIdx, roleIndex)
      end)

      -- Tooltip
      local capturedBlessing = blessing
      blessBtn:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        local clsName = PALADIN_CLASS_DISPLAY[capturedCls] or capturedCls
        if capturedBlessing then
          GameTooltip:SetText(clsName .. ": " .. capturedBlessing.name, 1, 1, 1)
        else
          GameTooltip:SetText(clsName .. ": (none)", 0.6, 0.6, 0.6)
        end
        GameTooltip:AddLine("Click to assign a blessing", 0.8, 0.8, 0.8, 1)
        GameTooltip:Show()
      end)
      blessBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
  end

  return section
end

-- ============================================
-- STANDARD GROUP-BASED BUFF SECTION
-- ============================================

--- Create the panel for one non-paladin buff role (e.g. "Fortitude (Priest)").
-- Contains: title, player assignment slots, optional improved-talent toggle,
-- group checkboxes (1-8).
-- @return Frame
local function CreateStandardBuffSection(parent, buffRole, brIdx, width, raidIdx, encounterIdx, roleIndex)
  local section, numSlots, autoAssignH = CreateSectionFrame(parent, buffRole, brIdx, width, 0)

  -- If the buff has an Improved talent variant, reserve a column for the toggle
  local hasImp = buffRole.hasImprovedTalent
  local groupStartX = hasImp and 166 or 140  -- shift groups right when toggle present

  local headerY = -12 - autoAssignH
  local contentTop = -28 - autoAssignH

  -- "Imp" header label (only for roles with improved talent)
  if hasImp then
    local impHeader = section:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    impHeader:SetWidth(20)
    impHeader:SetJustifyH("CENTER")
    impHeader:SetPoint("TOPLEFT", section, "TOPLEFT", 140, headerY)
    impHeader:SetText("|cffaaaaaaImp|r")
  end

  -- Group number header labels (one per column, centered above each checkbox)
  for g = 1, 8 do
    local gLabel = section:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    local cbX = groupStartX + (g - 1) * 26
    gLabel:SetWidth(20)
    gLabel:SetJustifyH("CENTER")
    gLabel:SetPoint("TOPLEFT", section, "TOPLEFT", cbX, headerY)
    gLabel:SetText("|cffaaaaaa" .. g .. "|r")
  end

  -- Player assignment rows
  for slotIdx = 1, numSlots do
    local rowY = contentTop - ((slotIdx - 1) * 26)
    CreatePlayerSlot(section, brIdx, slotIdx, buffRole, rowY)

    -- Improved talent toggle button (between player name and group checkboxes)
    if hasImp then
      local impBtn = CreateFrame("Button", nil, section)
      impBtn:SetWidth(20)
      impBtn:SetHeight(20)
      impBtn:SetPoint("TOPLEFT", section, "TOPLEFT", 140, rowY)

      local impBg = impBtn:CreateTexture(nil, "BACKGROUND")
      impBg:SetAllPoints()
      impBg:SetTexture("Interface\\Buttons\\WHITE8X8")
      impBg:SetVertexColor(0.15, 0.15, 0.15, 0.6)

      local impIcon = impBtn:CreateTexture(nil, "ARTWORK")
      impIcon:SetWidth(16)
      impIcon:SetHeight(16)
      impIcon:SetPoint("CENTER", impBtn, "CENTER", 0, 0)
      impIcon:SetTexture(buffRole.improvedTalentIcon or "Interface\\Icons\\INV_Misc_QuestionMark")

      -- Visual state: green tint when improved, dim when not
      local isImproved = buffRole.improvedTalents and buffRole.improvedTalents[slotIdx]
      if isImproved then
        impIcon:SetVertexColor(0.2, 1, 0.2, 1)
      else
        impIcon:SetVertexColor(0.5, 0.5, 0.5, 0.6)
      end

      local hlTex = impBtn:CreateTexture(nil, "HIGHLIGHT")
      hlTex:SetAllPoints()
      hlTex:SetTexture("Interface\\Buttons\\WHITE8X8")
      hlTex:SetVertexColor(0.4, 0.4, 0.6, 0.3)

      -- Click to toggle
      local capturedSlotIdx = slotIdx
      local capturedBrIdx = brIdx
      impBtn:SetScript("OnClick", function()
        OGRH.BuffManager.ToggleImprovedTalent(capturedBrIdx, capturedSlotIdx, raidIdx, encounterIdx, roleIndex)
        OGRH.BuffManager.RefreshWindow()
      end)

      -- Tooltip
      local impName = buffRole.improvedTalentName or "Improved"
      impBtn:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        if isImproved then
          GameTooltip:SetText(impName .. ": |cff00ff00Yes|r", 1, 1, 1)
        else
          GameTooltip:SetText(impName .. ": |cff999999No|r", 1, 1, 1)
        end
        GameTooltip:AddLine("Click to toggle", 0.8, 0.8, 0.8, 1)
        GameTooltip:Show()
      end)
      impBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    -- Group checkboxes (1-8) — right of the player button / improved toggle
    local capturedSlotIdx = slotIdx
    local capturedBrIdx = brIdx
    for g = 1, 8 do
      local cbX = groupStartX + (g - 1) * 26
      local cbFrame = CreateFrame("CheckButton", nil, section)
      cbFrame:SetWidth(20)
      cbFrame:SetHeight(20)
      cbFrame:SetPoint("TOPLEFT", section, "TOPLEFT", cbX, rowY)
      cbFrame:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
      cbFrame:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
      cbFrame:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight")
      cbFrame:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")

      -- Check if this group is currently assigned
      local isChecked = false
      if buffRole.groupAssignments and buffRole.groupAssignments[slotIdx] then
        local groups = buffRole.groupAssignments[slotIdx]
        for _, gn in ipairs(groups) do
          if gn == g then isChecked = true; break end
        end
      end
      cbFrame:SetChecked(isChecked)

      -- Checkbox click handler
      local capturedGroup = g
      cbFrame:SetScript("OnClick", function()
        local checked = (this:GetChecked() == 1) and true or false
        OGRH.BuffManager.SetGroupAssignment(capturedBrIdx, capturedSlotIdx, capturedGroup, checked, raidIdx, encounterIdx, roleIndex)
      end)
    end
  end  -- end slot loop

  return section
end

-- ============================================
-- PUBLIC ENTRY POINT
-- ============================================

--- Create the panel for one buff role — dispatches to paladin or standard layout.
-- @return Frame
function OGRH.BuffManager.CreateBuffSection(parent, buffRole, brIdx, width, raidIdx, encounterIdx, roleIndex)
  if buffRole.isPaladinRole then
    return CreatePaladinBuffSection(parent, buffRole, brIdx, width, raidIdx, encounterIdx, roleIndex)
  else
    return CreateStandardBuffSection(parent, buffRole, brIdx, width, raidIdx, encounterIdx, roleIndex)
  end
end

-- ============================================
-- ASSIGNMENT LOGIC
-- ============================================

--- Assign a player to a buff role slot (or clear with nil)
function OGRH.BuffManager.AssignPlayerToSlot(brIdx, slotIdx, playerName)
  local window = OGRH.BuffManager.window
  if not window then return end
  if not OGRH.BuffManager.CanEdit(window.raidIdx) then return end

  local role = OGRH.BuffManager.GetRole(window.raidIdx)
  if not role then return end
  OGRH.BuffManager.EnsureBuffRoles(role)

  local br = role.buffRoles[brIdx]
  if not br then return end

  if not br.assignedPlayers then br.assignedPlayers = {} end
  local previousPlayer = br.assignedPlayers[slotIdx]
  br.assignedPlayers[slotIdx] = playerName

  -- Persist to SVM with delta sync
  local basePath = SVMBase(window.raidIdx, window.encounterIdx, window.roleIndex)
  local syncMeta = BuildSyncMeta(window.raidIdx)
  local path = basePath .. ".buffRoles." .. brIdx .. ".assignedPlayers." .. slotIdx
  OGRH.SVM.SetPath(path, playerName, syncMeta)

  -- Clear paladin talents and class assignments when player changes or is removed
  local playerChanged = (not playerName or playerName == "") or (previousPlayer and previousPlayer ~= "" and playerName ~= previousPlayer)
  if playerChanged and br.isPaladinRole then
    if br.paladinTalents then
      br.paladinTalents[slotIdx] = nil
      OGRH.SVM.SetPath(basePath .. ".buffRoles." .. brIdx .. ".paladinTalents." .. slotIdx, nil, syncMeta)
    end
    if br.paladinAssignments then
      br.paladinAssignments[slotIdx] = nil
      OGRH.SVM.SetPath(basePath .. ".buffRoles." .. brIdx .. ".paladinAssignments." .. slotIdx, nil, syncMeta)
    end
  end

  -- Clear group assignments and improved talent when player changes or is removed
  if playerChanged and not br.isPaladinRole then
    if br.groupAssignments and br.groupAssignments[slotIdx] then
      br.groupAssignments[slotIdx] = nil
      OGRH.SVM.SetPath(basePath .. ".buffRoles." .. brIdx .. ".groupAssignments." .. slotIdx, nil, syncMeta)
    end
    if br.improvedTalents and br.improvedTalents[slotIdx] then
      br.improvedTalents[slotIdx] = nil
      OGRH.SVM.SetPath(basePath .. ".buffRoles." .. brIdx .. ".improvedTalents." .. slotIdx, nil, syncMeta)
    end
  end

  -- Auto-detect improved talents when the local player is assigned
  if playerName and playerName == UnitName("player") and br.hasImprovedTalent then
    OGRH.BuffManager.AutoDetectImprovedTalents()
  end
end

--- Toggle a group assignment for a buff role slot
function OGRH.BuffManager.SetGroupAssignment(brIdx, slotIdx, groupNum, enabled, raidIdx, encounterIdx, roleIndex)
  if not OGRH.BuffManager.CanEdit(raidIdx) then return end
  local role = OGRH.BuffManager.GetRole(raidIdx)
  if not role then return end
  OGRH.BuffManager.EnsureBuffRoles(role)

  local br = role.buffRoles[brIdx]
  if not br then return end

  if not br.groupAssignments then br.groupAssignments = {} end
  if not br.groupAssignments[slotIdx] then br.groupAssignments[slotIdx] = {} end

  local groups = br.groupAssignments[slotIdx]
  if enabled then
    -- Add if not present
    local found = false
    for _, gn in ipairs(groups) do
      if gn == groupNum then found = true; break end
    end
    if not found then
      table.insert(groups, groupNum)
      -- Keep sorted
      table.sort(groups)
    end
  else
    -- Remove
    for i = table.getn(groups), 1, -1 do
      if groups[i] == groupNum then
        table.remove(groups, i)
      end
    end
  end

  -- Persist
  local basePath = SVMBase(raidIdx, encounterIdx, roleIndex)
  local path = basePath .. ".buffRoles." .. brIdx .. ".groupAssignments." .. slotIdx
  OGRH.SVM.SetPath(path, groups, BuildSyncMeta(raidIdx))
end

--- Return all registered drop-target slots (for drag-and-drop hit testing)
function OGRH.BuffManager.GetAllDropSlots()
  return OGRH.BuffManager.dropSlots
end

--- Set (or clear) a paladin blessing assignment for a specific slot + class.
-- @param brIdx number   Buff role index
-- @param slotIdx number Paladin player slot (1, 2, …)
-- @param className string  e.g. "WARRIOR"
-- @param blessingKey string|nil  e.g. "kings", "wisdom", or nil to clear
function OGRH.BuffManager.SetPaladinBlessing(brIdx, slotIdx, className, blessingKey, raidIdx, encounterIdx, roleIndex)
  if not OGRH.BuffManager.CanEdit(raidIdx) then return end
  local role = OGRH.BuffManager.GetRole(raidIdx)
  if not role then return end
  OGRH.BuffManager.EnsureBuffRoles(role)

  local br = role.buffRoles[brIdx]
  if not br then return end

  if not br.paladinAssignments then br.paladinAssignments = {} end
  if not br.paladinAssignments[slotIdx] then br.paladinAssignments[slotIdx] = {} end

  br.paladinAssignments[slotIdx][className] = blessingKey

  -- Persist
  local basePath = SVMBase(raidIdx, encounterIdx, roleIndex)
  local path = basePath .. ".buffRoles." .. brIdx .. ".paladinAssignments." .. slotIdx .. "." .. className
  OGRH.SVM.SetPath(path, blessingKey, BuildSyncMeta(raidIdx))
end

--- Toggle a paladin talent flag for a specific slot.
-- @param brIdx number   Buff role index
-- @param slotIdx number Paladin player slot
-- @param talentKey string  "improved", "kings", or "sanctuary"
function OGRH.BuffManager.TogglePaladinTalent(brIdx, slotIdx, talentKey, raidIdx, encounterIdx, roleIndex)
  if not OGRH.BuffManager.CanEdit(raidIdx) then return end
  local role = OGRH.BuffManager.GetRole(raidIdx)
  if not role then return end
  OGRH.BuffManager.EnsureBuffRoles(role)

  local br = role.buffRoles[brIdx]
  if not br then return end

  if not br.paladinTalents then br.paladinTalents = {} end
  if not br.paladinTalents[slotIdx] then br.paladinTalents[slotIdx] = {} end

  local current = br.paladinTalents[slotIdx][talentKey]
  br.paladinTalents[slotIdx][talentKey] = not current

  -- Persist
  local basePath = SVMBase(raidIdx, encounterIdx, roleIndex)
  local path = basePath .. ".buffRoles." .. brIdx .. ".paladinTalents." .. slotIdx .. "." .. talentKey
  OGRH.SVM.SetPath(path, br.paladinTalents[slotIdx][talentKey], BuildSyncMeta(raidIdx))
end

--- Toggle the "Improved" talent flag for a standard buff role slot (e.g. MotW, Fort).
-- @param brIdx number   Buff role index
-- @param slotIdx number Player slot (1, 2, …)
function OGRH.BuffManager.ToggleImprovedTalent(brIdx, slotIdx, raidIdx, encounterIdx, roleIndex)
  if not OGRH.BuffManager.CanEdit(raidIdx) then return end
  local role = OGRH.BuffManager.GetRole(raidIdx)
  if not role then return end
  OGRH.BuffManager.EnsureBuffRoles(role)

  local br = role.buffRoles[brIdx]
  if not br then return end

  if not br.improvedTalents then br.improvedTalents = {} end
  local current = br.improvedTalents[slotIdx]
  br.improvedTalents[slotIdx] = not current

  -- Persist
  local basePath = SVMBase(raidIdx, encounterIdx, roleIndex)
  local path = basePath .. ".buffRoles." .. brIdx .. ".improvedTalents." .. slotIdx
  OGRH.SVM.SetPath(path, br.improvedTalents[slotIdx], BuildSyncMeta(raidIdx))
end

--- Detect whether the local player has an improved talent for a given buff type.
-- Iterates through all talents in the relevant tree to match by name (Turtle WoW safe).
-- @param buffType string  e.g. "motw", "fortitude"
-- @return boolean
local function DetectLocalImprovedTalent(buffType)
  local scanDef = IMPROVED_TALENT_SCAN[buffType]
  if not scanDef then return false end

  local numTalents = GetNumTalents(scanDef.tabIndex)
  if not numTalents then return false end

  for i = 1, numTalents do
    local name, _, _, _, rank = GetTalentInfo(scanDef.tabIndex, i)
    if name == scanDef.talentName then
      return rank and rank > 0
    end
  end
  return false
end

--- Scan all buff roles for the local player and report improved talent status.
-- Matches by class (not slot assignment) so it works before players are assigned.
-- Writes improvedTalents keyed by player NAME (string key). AutoAssignStandard
-- reads these name-keyed entries for filtering, then converts to slot-keyed
-- entries after assignment for UI display.
-- Safe to call from any context (assignment, sync receive, etc.).
function OGRH.BuffManager.AutoDetectImprovedTalents()
  local window = OGRH.BuffManager.window
  local raidIdx = window and window.raidIdx or 1
  local encounterIdx = window and window.encounterIdx
  local roleIndex = window and window.roleIndex

  local role, ri, ei = OGRH.BuffManager.GetRole(raidIdx)
  if not role then return end
  OGRH.BuffManager.EnsureBuffRoles(role)

  if not encounterIdx then encounterIdx = ei end
  if not roleIndex then roleIndex = ri end
  if not encounterIdx or not roleIndex then return end

  local localName = UnitName("player")
  if not localName or localName == "" or localName == "Unknown" then return end
  local _, localClass = UnitClass("player")
  if not localClass then return end

  local basePath = SVMBase(raidIdx, encounterIdx, roleIndex)
  local syncMeta = BuildSyncMeta(raidIdx)
  syncMeta.componentType = "self-report"

  for brIdx, br in ipairs(role.buffRoles) do
    if br.hasImprovedTalent and br.requiredClass == localClass then
      local hasImproved = DetectLocalImprovedTalent(br.buffType)
      if not br.improvedTalents then br.improvedTalents = {} end

      -- Name-keyed entry: used by AutoAssignStandard for filtering before assignment
      local currentName = br.improvedTalents[localName] and true or false
      if hasImproved ~= currentName then
        br.improvedTalents[localName] = hasImproved or nil
        local path = basePath .. ".buffRoles." .. brIdx .. ".improvedTalents." .. localName
        OGRH.SVM.SetPath(path, br.improvedTalents[localName], syncMeta)
      end

      -- Slot-keyed entry: used by UI for green checkmark display
      if br.assignedPlayers then
        for slotIdx, pName in pairs(br.assignedPlayers) do
          if pName == localName then
            local currentSlot = br.improvedTalents[slotIdx] and true or false
            if hasImproved ~= currentSlot then
              br.improvedTalents[slotIdx] = hasImproved or nil
              local slotPath = basePath .. ".buffRoles." .. brIdx .. ".improvedTalents." .. slotIdx
              OGRH.SVM.SetPath(slotPath, br.improvedTalents[slotIdx], syncMeta)
            end
          end
        end
      end
    end
  end
end

-- ============================================
-- AUTO-ASSIGN LOGIC
-- ============================================

--- Blessing priority per role+class for paladin auto-assign.
-- Key format: "ROLE_CLASS" or just "CLASS" for classes with single role treatment.
-- Values: ordered list of blessing keys, highest priority first.
local BLESSING_PRIORITY = {
  TANKS_WARRIOR     = { "kings", "might", "light", "sanctuary" },
  MELEE_WARRIOR     = { "salvation", "kings", "might", "light", "sanctuary" },
  MELEE_ROGUE       = { "salvation", "kings", "might", "light", "sanctuary" },
  HEALERS_PRIEST    = { "wisdom", "kings", "salvation", "light", "sanctuary" },
  RANGED_PRIEST     = { "salvation", "kings", "wisdom", "light", "sanctuary" },
  TANKS_DRUID       = { "kings", "might", "light", "sanctuary" },
  MELEE_DRUID       = { "salvation", "kings", "might", "light", "sanctuary" },
  HEALERS_DRUID     = { "wisdom", "kings", "salvation", "light", "sanctuary" },
  RANGED_DRUID      = { "salvation", "kings", "wisdom", "light", "sanctuary" },
  TANKS_PALADIN     = { "sanctuary", "kings", "wisdom", "light", "might" },
  HEALERS_PALADIN   = { "wisdom", "kings", "salvation", "light", "sanctuary" },
  MELEE_PALADIN     = { "salvation", "kings", "wisdom", "might", "light", "sanctuary" },
  MELEE_HUNTER      = { "salvation", "might", "kings", "wisdom", "light", "sanctuary" },
  RANGED_HUNTER     = { "salvation", "wisdom", "kings", "might", "light", "sanctuary" },
  RANGED_MAGE       = { "salvation", "kings", "wisdom", "light", "sanctuary" },
  RANGED_WARLOCK    = { "salvation", "kings", "wisdom", "light", "sanctuary" },
  TANKS_SHAMAN      = { "kings", "might", "wisdom", "sanctuary", "light" },
  HEALERS_SHAMAN    = { "wisdom", "kings", "salvation", "light", "sanctuary" },
  MELEE_SHAMAN      = { "salvation", "kings", "might", "light", "sanctuary" },
  RANGED_SHAMAN     = { "salvation", "kings", "might", "light", "sanctuary" },
}

--- Build a set of groups that actually have players in them.
-- @return table  {[groupNum] = true}
local function GetActiveGroups()
  local active = {}
  local numRaid = GetNumRaidMembers()
  for i = 1, numRaid do
    local name, _, subgroup = GetRaidRosterInfo(i)
    if name and subgroup then
      active[subgroup] = true
    end
  end
  return active
end

--- Get all raid members of a specific class.
-- @return table  {[name] = {class=string, group=number}}
local function GetRaidMembersByClass(className)
  local result = {}
  local numRaid = GetNumRaidMembers()
  for i = 1, numRaid do
    local name, _, subgroup, _, class = GetRaidRosterInfo(i)
    if name and class then
      local upperClass = string.upper(class)
      if upperClass == className then
        result[name] = { class = upperClass, group = subgroup }
      end
    end
  end
  return result
end

--- Get all raid members with their class and group.
-- @return table  {[name] = {class=string, group=number}}
local function GetAllRaidMembers()
  local result = {}
  local numRaid = GetNumRaidMembers()
  for i = 1, numRaid do
    local name, _, subgroup, _, class = GetRaidRosterInfo(i)
    if name and class then
      result[name] = { class = string.upper(class), group = subgroup }
    end
  end
  return result
end

--- Find or create a slot for a player in a buff role.
-- @return slotIdx or nil if no room
local function FindOrCreateSlot(br, playerName)
  -- Check if already assigned
  if br.assignedPlayers then
    for idx, name in pairs(br.assignedPlayers) do
      if name == playerName then return idx end
    end
  end
  -- Find an empty slot
  if not br.assignedPlayers then br.assignedPlayers = {} end
  local maxSlot = math.max(br.slots or 2, table.getn(br.assignedPlayers))
  for idx = 1, maxSlot do
    if not br.assignedPlayers[idx] or br.assignedPlayers[idx] == "" then
      return idx
    end
  end
  -- Grow by one
  return maxSlot + 1
end

--- Which prior priest buff roles to account for when balancing group distribution.
-- Spirit balances against Fort; Shadow Prot balances against Fort + Spirit.
local BALANCE_AGAINST = {
  spirit     = { "fortitude" },
  shadowprot = { "fortitude", "spirit" },
}

--- Fallback improved-talent assumptions for players who don't have the addon.
-- Maps buffType → { requiredClass, roles that imply improved talent }.
-- If a player of the required class is in one of these roles and did NOT respond
-- to the talent poll, we assume they have the improved talent.
local TALENT_FALLBACK_ROLES = {
  motw      = { "HEALERS", "RANGED" },  -- healer/balance druids likely have improved MotW
  fortitude = { "HEALERS" },             -- healer priests likely have improved Fort
}

--- Standard auto-assign: fill slots with matching class players, then split groups.
-- For MotW/Fort: only improved-talent holders get groups if any exist.
-- For Spirit/SP: groups are distributed to balance total casts per priest
-- accounting for groups already assigned in prior buff roles.
local function AutoAssignStandard(br, brIdx, raidIdx, encounterIdx, roleIndex)
  local window = OGRH.BuffManager.window
  if not window then return end
  local basePath = SVMBase(raidIdx, encounterIdx, roleIndex)
  local syncMeta = BuildSyncMeta(raidIdx)

  local role = OGRH.BuffManager.GetRole(raidIdx)

  -- Clear existing assignments for this role (always, even if no members remain)
  if br.assignedPlayers then
    for idx, _ in pairs(br.assignedPlayers) do
      br.assignedPlayers[idx] = nil
      OGRH.SVM.SetPath(basePath .. ".buffRoles." .. brIdx .. ".assignedPlayers." .. idx, nil, syncMeta)
    end
  end
  if br.groupAssignments then
    for idx, _ in pairs(br.groupAssignments) do
      br.groupAssignments[idx] = nil
      OGRH.SVM.SetPath(basePath .. ".buffRoles." .. brIdx .. ".groupAssignments." .. idx, nil, syncMeta)
    end
  end
  if br.improvedTalents then
    -- Only clear numeric (slot-keyed) entries; preserve string (name-keyed) talent reports
    for idx, _ in pairs(br.improvedTalents) do
      if type(idx) == "number" then
        br.improvedTalents[idx] = nil
        OGRH.SVM.SetPath(basePath .. ".buffRoles." .. brIdx .. ".improvedTalents." .. idx, nil, syncMeta)
      end
    end
  end

  -- Get all raid members of the required class
  local members = GetRaidMembersByClass(br.requiredClass)
  if not members or not next(members) then return end

  -- Convert all members to an ordered list
  local playerList = {}
  for name, _ in pairs(members) do
    table.insert(playerList, name)
  end
  table.sort(playerList)  -- deterministic ordering

  if table.getn(playerList) == 0 then return end

  -- Assign ALL players to slots
  if not br.assignedPlayers then br.assignedPlayers = {} end
  for slotIdx, name in ipairs(playerList) do
    br.assignedPlayers[slotIdx] = name
    OGRH.SVM.SetPath(basePath .. ".buffRoles." .. brIdx .. ".assignedPlayers." .. slotIdx, name, syncMeta)
  end

  -- Determine which groups have actual players
  local activeGroups = GetActiveGroups()
  local groupList = {}
  for g = 1, 8 do
    if activeGroups[g] then table.insert(groupList, g) end
  end

  -- Determine who gets groups: only improved players if any exist, else all
  local groupRecipients = {}
  if br.hasImprovedTalent and br.improvedTalents then
    for slotIdx, name in ipairs(playerList) do
      if br.improvedTalents[name] then
        table.insert(groupRecipients, slotIdx)
      end
    end
  end
  if table.getn(groupRecipients) == 0 then
    for slotIdx = 1, table.getn(playerList) do
      table.insert(groupRecipients, slotIdx)
    end
  end

  -- Initialize group assignments for all slots (empty for non-recipients)
  local numPlayers = table.getn(playerList)
  if not br.groupAssignments then br.groupAssignments = {} end
  for slotIdx = 1, numPlayers do
    br.groupAssignments[slotIdx] = {}
  end

  -- Build prior-load map: how many groups each player already has from earlier
  -- priest buff roles (Fort for Spirit, Fort+Spirit for Shadow Prot).
  local priorLoad = {}  -- [slotIdx] = count
  for _, si in ipairs(groupRecipients) do
    priorLoad[si] = 0
  end

  local balanceList = BALANCE_AGAINST[br.buffType]
  if balanceList and role then
    for _, priorType in ipairs(balanceList) do
      for _, otherBr in ipairs(role.buffRoles) do
        if otherBr.buffType == priorType and otherBr.groupAssignments then
          -- Map player names to their slot in THIS role's playerList
          for _, si in ipairs(groupRecipients) do
            local pName = playerList[si]
            -- Find this player in the other role and count their groups
            if otherBr.assignedPlayers then
              for otherSlot, otherName in pairs(otherBr.assignedPlayers) do
                if otherName == pName and otherBr.groupAssignments[otherSlot] then
                  priorLoad[si] = priorLoad[si] + table.getn(otherBr.groupAssignments[otherSlot])
                end
              end
            end
          end
        end
      end
    end
  end

  -- Distribute groups one at a time to the recipient with the lowest total load
  -- (prior groups + groups assigned so far in this role).
  for _, g in ipairs(groupList) do
    local bestSlot = nil
    local bestLoad = 999999
    for _, si in ipairs(groupRecipients) do
      local totalLoad = priorLoad[si] + table.getn(br.groupAssignments[si])
      if totalLoad < bestLoad then
        bestLoad = totalLoad
        bestSlot = si
      end
    end
    if bestSlot then
      table.insert(br.groupAssignments[bestSlot], g)
    end
  end

  -- Sort each slot's groups and persist
  for slotIdx = 1, numPlayers do
    table.sort(br.groupAssignments[slotIdx])
    OGRH.SVM.SetPath(basePath .. ".buffRoles." .. brIdx .. ".groupAssignments." .. slotIdx,
      br.groupAssignments[slotIdx], syncMeta)
  end

  -- Copy name-keyed improved flags to slot-keyed for UI display
  if br.hasImprovedTalent and br.improvedTalents then
    for slotIdx = 1, numPlayers do
      local pName = br.assignedPlayers[slotIdx]
      local isImp = pName and br.improvedTalents[pName]
      br.improvedTalents[slotIdx] = isImp or nil
      OGRH.SVM.SetPath(basePath .. ".buffRoles." .. brIdx .. ".improvedTalents." .. slotIdx,
        br.improvedTalents[slotIdx], syncMeta)
    end
  end
end

--- Paladin auto-assign: fill slots with paladins, then apply blessing algorithm.
local function AutoAssignPaladin(br, brIdx, raidIdx, encounterIdx, roleIndex)
  local window = OGRH.BuffManager.window
  if not window then return end
  local basePath = SVMBase(raidIdx, encounterIdx, roleIndex)
  local syncMeta = BuildSyncMeta(raidIdx)

  -- Step 1: Fill paladin slots with all paladins in raid
  local paladins = GetRaidMembersByClass("PALADIN")
  if not paladins or not next(paladins) then return end

  -- Clear existing assignments
  if br.assignedPlayers then
    for idx, _ in pairs(br.assignedPlayers) do
      br.assignedPlayers[idx] = nil
      OGRH.SVM.SetPath(basePath .. ".buffRoles." .. brIdx .. ".assignedPlayers." .. idx, nil, syncMeta)
    end
  end
  if br.paladinAssignments then
    for idx, _ in pairs(br.paladinAssignments) do
      br.paladinAssignments[idx] = nil
      OGRH.SVM.SetPath(basePath .. ".buffRoles." .. brIdx .. ".paladinAssignments." .. idx, nil, syncMeta)
    end
  end
  -- Keep paladin talents (from PP sync), don't clear those

  -- Assign paladins to slots
  local pallyList = {}
  for name, _ in pairs(paladins) do
    table.insert(pallyList, name)
  end
  table.sort(pallyList)

  if not br.assignedPlayers then br.assignedPlayers = {} end
  for slotIdx, name in ipairs(pallyList) do
    br.assignedPlayers[slotIdx] = name
    OGRH.SVM.SetPath(basePath .. ".buffRoles." .. brIdx .. ".assignedPlayers." .. slotIdx, name, syncMeta)
  end

  local numPallys = table.getn(pallyList)
  if numPallys == 0 then return end

  -- Step 2: Build raid composition data
  local allMembers = GetAllRaidMembers()

  -- Build class → {players} and determine which classes exist
  local classMembers = {}
  for name, info in pairs(allMembers) do
    if not classMembers[info.class] then classMembers[info.class] = {} end
    table.insert(classMembers[info.class], { name = name, group = info.group })
  end

  -- Get player roles from RolesUI
  local getRole = OGRH_GetPlayerRole or function() return nil end

  -- Check if any paladin healer exists in raid (for Blessing of Light rule)
  local hasPaladinHealer = false
  if classMembers["PALADIN"] then
    for _, p in ipairs(classMembers["PALADIN"]) do
      local r = getRole(p.name)
      if r == "HEALERS" then hasPaladinHealer = true; break end
    end
  end

  -- Build per-class blessing priority based on role composition
  -- For each class, determine the priority list and whether Salv should be forced
  local classPriority = {}  -- className → ordered list of blessing keys
  for _, cls in ipairs(PALADIN_CLASSES) do
    if classMembers[cls] then
      -- Gather unique roles for members of this class
      local roles = {}
      local hasDPS = false
      local hasTank = false
      for _, p in ipairs(classMembers[cls]) do
        local r = getRole(p.name) or "RANGED"
        roles[r] = true
        if r == "MELEE" or r == "RANGED" then hasDPS = true end
        if r == "TANKS" then hasTank = true end
      end

      -- Pick the best priority list for this class
      -- If mixed roles, pick the DPS variant (since Salv rule applies)
      local priorityKey
      if hasDPS and hasTank then
        -- Mixed: DPS priority (Salv) wins for the class blessing assignment
        priorityKey = "MELEE_" .. cls
      elseif hasTank then
        priorityKey = "TANKS_" .. cls
      elseif roles["HEALERS"] then
        priorityKey = "HEALERS_" .. cls
      elseif roles["MELEE"] then
        priorityKey = "MELEE_" .. cls
      else
        priorityKey = "RANGED_" .. cls
      end

      classPriority[cls] = BLESSING_PRIORITY[priorityKey]
      if not classPriority[cls] then
        -- Fallback: try just RANGED_CLASS
        classPriority[cls] = BLESSING_PRIORITY["RANGED_" .. cls]
      end

      -- Filter out Light if no paladin healer
      if not hasPaladinHealer and classPriority[cls] then
        local filtered = {}
        for _, bk in ipairs(classPriority[cls]) do
          if bk ~= "light" then
            table.insert(filtered, bk)
          end
        end
        classPriority[cls] = filtered
      end
    end
  end

  -- Step 3: Build paladin capability map (what blessings each paladin CAN give)
  -- Check talents: kings requires talent, sanctuary requires talent, improved affects might/wisdom
  local pallyCapabilities = {}
  for slotIdx, pallyName in ipairs(pallyList) do
    local talents = (br.paladinTalents and br.paladinTalents[slotIdx]) or {}
    local canGive = {
      wisdom = true,
      might = true,
      salvation = true,
      light = true,
      kings = talents.kings and true or false,
      sanctuary = talents.sanctuary and true or false,
    }
    pallyCapabilities[slotIdx] = canGive
  end

  -- Step 4: Greedy assignment algorithm
  -- For each class (by priority order: DPS classes first benefit from Salv),
  -- assign the highest-priority blessing that a paladin can provide.
  -- Each paladin can only give ONE blessing per class.

  if not br.paladinAssignments then br.paladinAssignments = {} end
  for slotIdx = 1, numPallys do
    br.paladinAssignments[slotIdx] = {}
  end

  -- Track what blessing each paladin is "known for" giving to help with distribution
  -- pallyUsed[slotIdx][blessingKey] = count of classes assigned this blessing
  local pallyBlessingCount = {}
  for slotIdx = 1, numPallys do
    pallyBlessingCount[slotIdx] = {}
  end

  -- Process classes in priority order: Salv-needing classes first
  local classOrder = {}
  for _, cls in ipairs(PALADIN_CLASSES) do
    if classPriority[cls] then
      table.insert(classOrder, cls)
    end
  end

  -- For each priority tier (iterate through blessing priorities together)
  -- Round 1: assign the #1 priority blessing for each class
  -- Round 2: assign the #2 priority, etc.
  -- This ensures highest-priority blessings are distributed first

  local maxRounds = 6  -- max blessings per class
  local assigned = {}  -- [cls] = { [slotIdx] = blessingKey }
  for _, cls in ipairs(classOrder) do
    assigned[cls] = {}
  end

  for round = 1, maxRounds do
    for _, cls in ipairs(classOrder) do
      local prioList = classPriority[cls]
      if prioList and prioList[round] then
        local desiredBlessing = prioList[round]

        -- Already have this blessing for this class from another paladin?
        local alreadyHas = false
        for _, bk in pairs(assigned[cls]) do
          if bk == desiredBlessing then alreadyHas = true; break end
        end

        if not alreadyHas then
          -- Find the best paladin to give this blessing
          -- Prefer a paladin who hasn't assigned this class yet AND can give this blessing
          -- Among eligible, prefer the one with the fewest total assignments (load balance)
          local bestSlot = nil
          local bestLoad = 9999
          for slotIdx = 1, numPallys do
            if not assigned[cls][slotIdx]
                and pallyCapabilities[slotIdx][desiredBlessing] then
              local load = 0
              for _, cnt in pairs(pallyBlessingCount[slotIdx]) do
                load = load + cnt
              end
              if load < bestLoad then
                bestLoad = load
                bestSlot = slotIdx
              end
            end
          end

          if bestSlot then
            assigned[cls][bestSlot] = desiredBlessing
            pallyBlessingCount[bestSlot][desiredBlessing] = (pallyBlessingCount[bestSlot][desiredBlessing] or 0) + 1
          end
        end
      end
    end
  end

  -- Step 5: Write assignments to data + SVM
  for _, cls in ipairs(classOrder) do
    for slotIdx, blessingKey in pairs(assigned[cls]) do
      br.paladinAssignments[slotIdx][cls] = blessingKey
      OGRH.SVM.SetPath(
        basePath .. ".buffRoles." .. brIdx .. ".paladinAssignments." .. slotIdx .. "." .. cls,
        blessingKey, syncMeta)
    end
  end
end

--- Main auto-assign entry point, called from the section button.
-- For standard buffs: assigns class players to slots, waits 2s for talent responses, then splits groups.
-- For paladins: fills slots and runs blessing algorithm immediately.
function OGRH.BuffManager.RunAutoAssign(brIdx)
  local window = OGRH.BuffManager.window
  if not window then return end
  if not OGRH.BuffManager.CanEdit(window.raidIdx) then return end
  if GetNumRaidMembers() == 0 then
    OGRH.Msg("|cffff8800[BuffManager]|r Must be in a raid to auto-assign.")
    return
  end

  local role = OGRH.BuffManager.GetRole(window.raidIdx)
  if not role then return end
  OGRH.BuffManager.EnsureBuffRoles(role)

  local br = role.buffRoles[brIdx]
  if not br then return end

  if br.isPaladinRole then
    AutoAssignPaladin(br, brIdx, window.raidIdx, window.encounterIdx, window.roleIndex)
    OGRH.BuffManager.RefreshWindow()
  else
    -- Standard buff: wait for talent responses first, then assign once.
    if br.hasImprovedTalent then
      -- If no members of the required class exist, clear immediately and skip the poll
      local preCheckMembers = GetRaidMembersByClass(br.requiredClass)
      if not preCheckMembers or not next(preCheckMembers) then
        AutoAssignStandard(br, brIdx, window.raidIdx, window.encounterIdx, window.roleIndex)
        OGRH.BuffManager.RefreshWindow()
        OGRH.Msg("|cff00ff00[BuffManager]|r Auto-assign complete (no " .. (br.requiredClass or "players") .. " in raid).")
        return
      end

      local scanningBrIdx = brIdx
      local capturedRaidIdx = window.raidIdx
      local capturedEncIdx = window.encounterIdx
      local capturedRoleIdx = window.roleIndex
      OGRH.Msg("|cff00aaff[BuffManager]|r Scanning for improved talents... (2s)")

      -- Ask: bump talentScanSeq to trigger all clients to report their talent.
      -- Only matching-class players (priests/druids) will respond.
      local basePath = SVMBase(capturedRaidIdx, capturedEncIdx, capturedRoleIdx)
      br.talentScanSeq = (br.talentScanSeq or 0) + 1
      OGRH.SVM.SetPath(basePath .. ".buffRoles." .. scanningBrIdx .. ".talentScanSeq",
        br.talentScanSeq, BuildSyncMeta(capturedRaidIdx))

      -- Also run local detection (in case admin IS the matching class)
      OGRH.BuffManager.AutoDetectImprovedTalents()

      -- Wait 2s for remote talent responses, then do a single assignment pass
      local timerFrame = CreateFrame("Frame")
      timerFrame.elapsed = 0
      timerFrame:SetScript("OnUpdate", function()
        timerFrame.elapsed = timerFrame.elapsed + arg1
        if timerFrame.elapsed >= 2 then
          timerFrame:SetScript("OnUpdate", nil)

          -- Re-read role data (talent flags may have arrived during the wait)
          local r2 = OGRH.BuffManager.GetRole(capturedRaidIdx)
          if r2 then
            OGRH.BuffManager.EnsureBuffRoles(r2)
            local br2 = r2.buffRoles[scanningBrIdx]
            if br2 then
              -- Apply fallback talent assumptions for players who didn't respond
              local fallbackRoles = TALENT_FALLBACK_ROLES[br2.buffType]
              if fallbackRoles and br2.hasImprovedTalent then
                if not br2.improvedTalents then br2.improvedTalents = {} end
                local classMembers = GetRaidMembersByClass(br2.requiredClass)
                for name, _ in pairs(classMembers) do
                  if not br2.improvedTalents[name] then
                    -- No response from this player — check their role for a default
                    local playerRole = OGRH_GetPlayerRole(name)
                    if playerRole then
                      for _, fbRole in ipairs(fallbackRoles) do
                        if playerRole == fbRole then
                          br2.improvedTalents[name] = true
                          OGRH.Msg("|cff00aaff[BuffManager]|r Assuming improved talent for " .. name .. " (role: " .. playerRole .. ")")
                          break
                        end
                      end
                    end
                  end
                end
              end

              AutoAssignStandard(br2, scanningBrIdx, capturedRaidIdx, capturedEncIdx, capturedRoleIdx)
            end
          end

          OGRH.BuffManager.RefreshWindow()
          OGRH.Msg("|cff00ff00[BuffManager]|r Auto-assign complete.")
        end
      end)
    else
      -- No improved talent to scan — assign immediately
      AutoAssignStandard(br, brIdx, window.raidIdx, window.encounterIdx, window.roleIndex)
      OGRH.BuffManager.RefreshWindow()
      OGRH.Msg("|cff00ff00[BuffManager]|r Auto-assign complete.")
    end
  end
end

-- ============================================
-- AUTO ASSIGN ALL
-- ============================================

--- Desired assignment order for "Auto Assign All".
-- Fort must precede Spirit, and Spirit must precede Shadow Prot
-- so that load-balancing (BALANCE_AGAINST) works correctly.
local AUTO_ASSIGN_ALL_ORDER = { 1, 2, 3, 4, 5, 6 }  -- pally, motw, fort, spirit, shadowprot, int

--- Auto-assign every buff role in a single operation.
-- Fires talent-scan requests for all improved-talent roles up front,
-- assigns immediate roles right away, then after 2 s assigns the
-- talent-scan roles in the order defined by AUTO_ASSIGN_ALL_ORDER.
function OGRH.BuffManager.RunAutoAssignAll()
  local window = OGRH.BuffManager.window
  if not window then return end
  if not OGRH.BuffManager.CanEdit(window.raidIdx) then return end
  if GetNumRaidMembers() == 0 then
    OGRH.Msg("|cffff8800[BuffManager]|r Must be in a raid to auto-assign.")
    return
  end

  local role = OGRH.BuffManager.GetRole(window.raidIdx)
  if not role then return end
  OGRH.BuffManager.EnsureBuffRoles(role)

  local capturedRaidIdx = window.raidIdx
  local capturedEncIdx  = window.encounterIdx
  local capturedRoleIdx = window.roleIndex
  local basePath = SVMBase(capturedRaidIdx, capturedEncIdx, capturedRoleIdx)
  local syncMeta = BuildSyncMeta(capturedRaidIdx)

  -- Classify roles into immediate (no talent wait) and deferred (need 2 s poll)
  local immediateRoles = {}   -- { brIdx, ... }
  local deferredRoles  = {}   -- { brIdx, ... } — preserves AUTO_ASSIGN_ALL_ORDER
  local needTalentScan = false

  for _, brIdx in ipairs(AUTO_ASSIGN_ALL_ORDER) do
    local br = role.buffRoles[brIdx]
    if br then
      if br.isPaladinRole then
        table.insert(immediateRoles, brIdx)
      elseif br.hasImprovedTalent then
        -- Only defer if there are actually members of the required class
        local members = GetRaidMembersByClass(br.requiredClass)
        if members and next(members) then
          table.insert(deferredRoles, brIdx)
          -- Bump talentScanSeq now so all clients start reporting in parallel
          br.talentScanSeq = (br.talentScanSeq or 0) + 1
          OGRH.SVM.SetPath(basePath .. ".buffRoles." .. brIdx .. ".talentScanSeq",
            br.talentScanSeq, syncMeta)
          needTalentScan = true
        else
          -- No members of required class — assign (clear) immediately
          table.insert(immediateRoles, brIdx)
        end
      else
        -- Non-talent standard roles are deferred too so they run after
        -- their prerequisite (e.g. Spirit after Fort).
        table.insert(deferredRoles, brIdx)
      end
    end
  end

  -- Fire local talent detection once (covers every class the admin might be)
  if needTalentScan then
    OGRH.BuffManager.AutoDetectImprovedTalents()
  end

  -- Assign immediate roles now (paladins and empty-class talent roles)
  for _, brIdx in ipairs(immediateRoles) do
    local br = role.buffRoles[brIdx]
    if br then
      if br.isPaladinRole then
        AutoAssignPaladin(br, brIdx, capturedRaidIdx, capturedEncIdx, capturedRoleIdx)
      else
        AutoAssignStandard(br, brIdx, capturedRaidIdx, capturedEncIdx, capturedRoleIdx)
      end
    end
  end

  -- If nothing needs the 2 s talent window, finish now
  if not needTalentScan then
    -- Still need to process deferred (non-talent) roles in order
    for _, brIdx in ipairs(deferredRoles) do
      local br = role.buffRoles[brIdx]
      if br then
        AutoAssignStandard(br, brIdx, capturedRaidIdx, capturedEncIdx, capturedRoleIdx)
      end
    end
    OGRH.BuffManager.RefreshWindow()
    OGRH.Msg("|cff00ff00[BuffManager]|r Auto-assign all complete.")
    return
  end

  OGRH.Msg("|cff00aaff[BuffManager]|r Scanning for improved talents... (2s)")

  -- Wait 2 s for talent responses, then assign deferred roles in order
  local timerFrame = CreateFrame("Frame")
  timerFrame.elapsed = 0
  timerFrame:SetScript("OnUpdate", function()
    timerFrame.elapsed = timerFrame.elapsed + arg1
    if timerFrame.elapsed >= 2 then
      timerFrame:SetScript("OnUpdate", nil)

      -- Re-read role data (talent flags may have arrived during the wait)
      local r2 = OGRH.BuffManager.GetRole(capturedRaidIdx)
      if r2 then
        OGRH.BuffManager.EnsureBuffRoles(r2)

        -- Apply fallback talent assumptions for all deferred roles that need them
        for _, brIdx in ipairs(deferredRoles) do
          local br2 = r2.buffRoles[brIdx]
          if br2 and br2.hasImprovedTalent then
            local fallbackRoles = TALENT_FALLBACK_ROLES[br2.buffType]
            if fallbackRoles then
              if not br2.improvedTalents then br2.improvedTalents = {} end
              local classMembers = GetRaidMembersByClass(br2.requiredClass)
              for name, _ in pairs(classMembers) do
                if not br2.improvedTalents[name] then
                  local playerRole = OGRH_GetPlayerRole(name)
                  if playerRole then
                    for _, fbRole in ipairs(fallbackRoles) do
                      if playerRole == fbRole then
                        br2.improvedTalents[name] = true
                        OGRH.Msg("|cff00aaff[BuffManager]|r Assuming improved talent for " .. name .. " (role: " .. playerRole .. ")")
                        break
                      end
                    end
                  end
                end
              end
            end
          end
        end

        -- Now assign all deferred roles in the correct order
        for _, brIdx in ipairs(deferredRoles) do
          local br2 = r2.buffRoles[brIdx]
          if br2 then
            AutoAssignStandard(br2, brIdx, capturedRaidIdx, capturedEncIdx, capturedRoleIdx)
          end
        end
      end

      OGRH.BuffManager.RefreshWindow()
      OGRH.Msg("|cff00ff00[BuffManager]|r Auto-assign all complete.")
    end
  end)
end

-- ============================================
-- PUBLIC API SHORTCUTS
-- ============================================

--- Convenience wrapper used by the "Manage Buffs" button
function OGRH.ShowBuffManagerWindow(raidIdx, encounterIdx, roleIndex)
  OGRH.BuffManager.ShowWindow(raidIdx, encounterIdx, roleIndex)
end
