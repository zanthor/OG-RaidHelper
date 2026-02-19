-- ReadynessDashboard.lua (Phase 1: Core Framework)
-- Core logic, scanning, state management for the Readyness Dashboard
-- Module: _Raid/ReadynessDashboard.lua
-- Dependencies: Core.lua, SavedVariablesManager.lua, ConsumesTracking.lua, BuffManager.lua

if not OGRH then
  DEFAULT_CHAT_FRAME:AddMessage("|cffff0000Error: ReadynessDashboard requires OGRH_Core to be loaded first!|r")
  return
end

-- ============================================
-- Module Namespace
-- ============================================
OGRH.ReadynessDashboard = OGRH.ReadynessDashboard or {}
local RD = OGRH.ReadynessDashboard

-- Module state
RD.State = {
  debug = false,       -- Toggle with /ogrh debug ready
  initialized = false,
  scanning = false,
  inCombat = false,
}

-- ============================================
-- Scan State — filled by each scan cycle
-- ============================================
RD.State.indicators = {
  buff       = { status = "gray", ready = 0, total = 0, missing = {}, byBuff = {} },
  classCon   = { status = "gray", ready = 0, total = 0, missing = {}, averageScore = 0 },
  encCon     = { status = "gray", ready = 0, total = 0, missing = {}, consumeItems = {}, hidden = true },
  roleResources = {
    TANKS   = { health = 0, mana = 0, healthPlayers = {}, manaPlayers = {} },
    HEALERS = { health = 0, mana = 0, healthPlayers = {}, manaPlayers = {} },
    MELEE   = { health = 0, mana = 0, healthPlayers = {}, manaPlayers = {} },
    RANGED  = { health = 0, mana = 0, healthPlayers = {}, manaPlayers = {} },
  },
  rebirth    = { status = "gray", ready = 0, total = 0, onCooldown = {}, available = {} },
  tranq      = { status = "gray", ready = 0, total = 0, onCooldown = {}, available = {} },
  taunt      = { status = "gray", ready = 0, total = 0, onCooldown = {}, available = {} },
}

-- ============================================
-- Cooldown Tracking State
-- ============================================
RD.CooldownTrackers = {
  rebirth = {
    cooldownDuration = 1800,  -- 30 minutes
    casts = {},               -- { [playerName] = { lastCast = timestamp } }
    reportedReady = {},       -- { [playerName] = true }
    totalDruids = 0,
  },
  tranquility = {
    cooldownDuration = 300,   -- 5 minutes
    casts = {},
    reportedReady = {},
    totalDruids = 0,
  },
  taunt = {
    cooldownDuration = 600,   -- 10 minutes
    casts = {},
    reportedReady = {},
    totalTaunters = 0,
  },
}

-- Active poll tracking
RD.activePoll = nil  -- { abilityKey = "rebirth"|"tranquility"|"taunt", startTime = N, timeout = 30 }

-- ============================================
-- Buff Classification Data
-- ============================================
RD.BUFF_CATEGORIES = {
  fortitude  = { patterns = { "Fortitude", "Prayer of Fortitude" }, provider = "Priest" },
  spirit     = { patterns = { "Divine Spirit", "Prayer of Spirit" }, provider = "Priest" },
  shadowprot = { patterns = { "Shadow Protection", "Prayer of Shadow Protection" }, provider = "Priest" },
  motw       = { patterns = { "Mark of the Wild", "Gift of the Wild" }, provider = "Druid" },
  int        = { patterns = { "Arcane Intellect", "Arcane Brilliance" }, provider = "Mage" },
  paladin    = { patterns = { "Blessing of", "Greater Blessing" }, provider = "Paladin" },
}

-- Classes that use mana
RD.MANA_CLASSES = {
  Priest  = true,
  Mage    = true,
  Warlock = true,
  Druid   = true,
  Paladin = true,
  Shaman  = true,
  Hunter  = true,
}

-- Item-to-spell mapping for encounter consume checking
-- Maps item IDs to the buff spell IDs they produce
RD.ItemToSpell = {
  [13457] = 17543,   -- Greater Fire Protection Potion
  [6049]  = 7233,    -- Fire Protection Potion
  [13456] = 17544,   -- Greater Frost Protection Potion
  [6050]  = 7239,    -- Frost Protection Potion
  [13460] = 17546,   -- Greater Holy Protection Potion
  [13458] = 17545,   -- Greater Nature Protection Potion
  [6052]  = 7254,    -- Nature Protection Potion
  [13459] = 17548,   -- Greater Shadow Protection Potion
  [6048]  = 7235,    -- Shadow Protection Potion
  [13461] = 17549,   -- Greater Arcane Protection Potion
  [3387]  = 3169,    -- Limited Invulnerability Potion
}

-- ============================================
-- Scan Timing
-- ============================================
-- Buff scan: 2s out of combat, disabled in combat
RD.BuffScanInterval = 2
RD.LastBuffScanTime = 0
RD.BuffScanFrame = nil

-- Resource scan (health/mana): 2s out of combat, 0.25s in combat
RD.ResourceScanInterval = 2
RD.ResourceScanIntervalOOC = 2
RD.ResourceScanIntervalCombat = 0.25
RD.LastResourceScanTime = 0
RD.ResourceScanFrame = nil

-- ============================================
-- SVM Schema Defaults
-- ============================================
RD.SVM_DEFAULTS = {
  enabled = true,
  isDocked = true,
  position = { point = "CENTER", x = 0, y = 0 },
  scanInterval = 5,
  manaThreshold = 80,
  healthThreshold = 80,
  thresholds = {
    buff = 80,
    classConsume = 75,
    encConsume = 80,
    mana = { green = 90, yellow = 70 },
    health = { green = 90, yellow = 70 },
    cooldown = 50,
  },
  announceChannel = "RAID",
  showInRaidOnly = true,
  buffCategories = {
    fortitude = true,
    spirit = true,
    shadowprot = true,
    motw = true,
    int = true,
    paladin = true,
  },
}

-- ============================================
-- Status Color Constants
-- ============================================
RD.STATUS_COLORS = {
  green  = { r = 0.0, g = 1.0, b = 0.0 },
  yellow = { r = 1.0, g = 1.0, b = 0.0 },
  red    = { r = 1.0, g = 0.0, b = 0.0 },
  gray   = { r = 0.5, g = 0.5, b = 0.5 },
}

-- ============================================
-- Initialization
-- ============================================
function RD.Initialize()
  if RD.State.initialized then return end

  -- Ensure SVM defaults are present
  RD.EnsureSVMDefaults()

  -- Load settings from SVM
  RD.LoadSettings()

  -- Register events
  RD.RegisterEvents()

  RD.State.initialized = true

  if RD.State.debug then
    OGRH.Msg("|cffff6666[RH-ReadyDash][DEBUG]|r Initialized")
  end

  OGRH.Msg("|cffff6666[RH-ReadyDash]|r module loaded")
end

-- ============================================
-- SVM Integration
-- ============================================
function RD.EnsureSVMDefaults()
  if not OGRH.SVM or not OGRH.SVM.GetPath then return end

  local existing = OGRH.SVM.GetPath("readynessDashboard")
  if not existing then
    -- Write defaults (local only, no sync)
    OGRH.SVM.SetPath("readynessDashboard", RD.SVM_DEFAULTS)
    if RD.State.debug then
      OGRH.Msg("|cffff6666[RH-ReadyDash][DEBUG]|r SVM defaults initialized")
    end
  else
    -- Ensure any new keys added in updates exist
    for key, val in pairs(RD.SVM_DEFAULTS) do
      if existing[key] == nil then
        OGRH.SVM.SetPath("readynessDashboard." .. key, val)
      end
    end
    -- Ensure nested threshold keys
    if existing.thresholds then
      for key, val in pairs(RD.SVM_DEFAULTS.thresholds) do
        if existing.thresholds[key] == nil then
          OGRH.SVM.SetPath("readynessDashboard.thresholds." .. key, val)
        end
      end
    end
  end
end

function RD.LoadSettings()
  if not OGRH.SVM or not OGRH.SVM.GetPath then return end

  local settings = OGRH.SVM.GetPath("readynessDashboard")
  if not settings then return end

  RD.BuffScanInterval = 2
  RD.ResourceScanIntervalOOC = 2
  RD.ResourceScanIntervalCombat = 0.25
end

function RD.GetSetting(path)
  if not OGRH.SVM or not OGRH.SVM.GetPath then return nil end
  return OGRH.SVM.GetPath("readynessDashboard." .. path)
end

function RD.SetSetting(path, value)
  if not OGRH.SVM or not OGRH.SVM.SetPath then return end
  OGRH.SVM.SetPath("readynessDashboard." .. path, value)
end

-- ============================================
-- Threshold Accessors
-- ============================================
function RD.GetConsumeThreshold()
  -- Try encounter-level readyThreshold first, then raid-level, then SVM default
  local encounterThreshold = RD.GetCurrentEncounterSetting("advancedSettings.consumeTracking.readyThreshold")
  if encounterThreshold then return encounterThreshold end

  local raidThreshold = RD.GetCurrentRaidSetting("advancedSettings.consumeTracking.readyThreshold")
  if raidThreshold then return raidThreshold end

  return RD.GetSetting("thresholds.classConsume") or RD.SVM_DEFAULTS.thresholds.classConsume
end

function RD.GetManaThreshold()
  return RD.GetSetting("manaThreshold") or RD.SVM_DEFAULTS.manaThreshold
end

function RD.GetHealthThreshold()
  return RD.GetSetting("healthThreshold") or RD.SVM_DEFAULTS.healthThreshold
end

-- ============================================
-- Encounter Access Helpers
-- ============================================
function RD.GetCurrentEncounterData()
  if not OGRH.SVM or not OGRH.SVM.GetPath then return nil end

  local raidIdx = OGRH.SVM.GetPath("selectedRaidIndex") or 1
  local encIdx = OGRH.SVM.GetPath("selectedEncounterIndex") or 1

  local path = string.format("encounterMgmt.raids.%d.encounters.%d", raidIdx, encIdx)
  return OGRH.SVM.GetPath(path), raidIdx, encIdx
end

function RD.GetCurrentRaidData()
  if not OGRH.SVM or not OGRH.SVM.GetPath then return nil end
  local raidIdx = OGRH.SVM.GetPath("selectedRaidIndex") or 1
  return OGRH.SVM.GetPath(string.format("encounterMgmt.raids.%d", raidIdx))
end

function RD.GetCurrentEncounterSetting(settingPath)
  local encData = RD.GetCurrentEncounterData()
  if not encData then return nil end

  -- Navigate the dot-separated path within encounter data
  local current = encData
  for segment in string.gfind(settingPath, "([^%.]+)") do
    if type(current) ~= "table" then return nil end
    current = current[segment]
    if current == nil then return nil end
  end
  return current
end

function RD.GetCurrentRaidSetting(settingPath)
  local raidData = RD.GetCurrentRaidData()
  if not raidData then return nil end

  local current = raidData
  for segment in string.gfind(settingPath, "([^%.]+)") do
    if type(current) ~= "table" then return nil end
    current = current[segment]
    if current == nil then return nil end
  end
  return current
end

-- ============================================
-- Status Evaluation
-- ============================================

-- Evaluates a scan result and assigns a traffic-light status
-- @param scanResult table with .ready and .total fields
-- @param greenThresh number (0-100, default 100 = all must be ready)
-- @param yellowThresh number (0-100, default 80)
-- @return scanResult (modified in-place with .status)
function RD.EvaluateStatus(scanResult, greenThresh, yellowThresh)
  if not scanResult or not scanResult.total or scanResult.total == 0 then
    scanResult = scanResult or {}
    scanResult.status = "gray"
    return scanResult
  end

  greenThresh = greenThresh or 100
  yellowThresh = yellowThresh or 80

  local pct = (scanResult.ready / scanResult.total) * 100

  if pct >= greenThresh then
    scanResult.status = "green"
  elseif pct >= yellowThresh then
    scanResult.status = "yellow"
  else
    scanResult.status = "red"
  end

  return scanResult
end

-- Evaluate a percentage-based indicator (mana/health)
-- @param percent number (0-100)
-- @param greenThresh number (default 90)
-- @param yellowThresh number (default 70)
-- @return string "green"|"yellow"|"red"|"gray"
function RD.EvaluatePercentStatus(percent, greenThresh, yellowThresh)
  if not percent then return "gray" end

  greenThresh = greenThresh or 90
  yellowThresh = yellowThresh or 70

  if percent >= greenThresh then
    return "green"
  elseif percent >= yellowThresh then
    return "yellow"
  else
    return "red"
  end
end

-- ============================================
-- Nampower-Aware Buff Scanning Utilities
-- ============================================

-- Resolve a spellId to a spell name using Nampower APIs (DoiteAuras approach)
-- Falls back to nil if Nampower is not available
function RD.GetSpellNameFromId(spellId)
  if not spellId or spellId <= 0 then return nil end
  if GetSpellNameAndRankForId then
    local name = GetSpellNameAndRankForId(spellId)
    if type(name) == "string" and name ~= "" then
      return name
    end
  end
  return nil
end

-- Hidden tooltip for fallback buff name resolution (vanilla API)
local rdTooltip = nil
function RD.GetBuffNameFromTooltip(unitId, buffIndex)
  if not rdTooltip then
    rdTooltip = CreateFrame("GameTooltip", "OGRH_RD_BuffTooltip", UIParent, "GameTooltipTemplate")
    rdTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    rdTooltip:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", 0, 0)
    rdTooltip:Hide()
  end
  rdTooltip:SetOwner(UIParent, "ANCHOR_NONE")
  rdTooltip:ClearLines()
  if rdTooltip.SetUnitBuff then
    rdTooltip:SetUnitBuff(unitId, buffIndex)
  end
  local nameRegion = getglobal("OGRH_RD_BuffTooltipTextLeft1")
  local result = nil
  if nameRegion then
    local text = nameRegion:GetText()
    if text and text ~= "" then result = text end
  end
  rdTooltip:Hide()
  return result
end

-- Scan all buffs on a unit, returning a list of { name, spellId, texture }
-- Uses Nampower-enhanced UnitBuff (3rd return = spellId) with tooltip fallback
function RD.ScanUnitBuffs(unitId)
  local buffs = {}
  local buffIndex = 1
  while true do
    -- Nampower-enhanced: UnitBuff returns texture, stacks, spellId
    local texture, stacks, spellId = UnitBuff(unitId, buffIndex)
    if not texture then break end

    local name = nil
    -- Tier 1: Resolve via Nampower spellId
    if spellId and spellId > 0 then
      name = RD.GetSpellNameFromId(spellId)
    end
    -- Tier 2: Fallback to tooltip
    if not name then
      name = RD.GetBuffNameFromTooltip(unitId, buffIndex)
    end

    if name then
      table.insert(buffs, { name = name, spellId = spellId, texture = texture })
    end
    buffIndex = buffIndex + 1
  end
  return buffs
end

-- ============================================
-- Buff Blacklist Framework
-- ============================================
-- Blacklist: keyed by role (from OGRH_GetPlayerRole), value is table of
-- { category = "paladin", blessingKey = "salvation" } entries.
-- category = buff category from ClassifyBuff
-- blessingKey = specific paladin blessing key (optional, only for paladin category)
-- spellPattern = additional string.find pattern to match against buff name (optional)
RD.BUFF_BLACKLIST = {
  TANKS = {
    { category = "paladin", blessingKey = "salvation", spellPattern = "Salvation" },
    { category = "int", classFilter = "PALADIN" },
  },
}

-- Class-based blacklist: keyed by uppercase class token
-- Buffs that should never be required/tracked for specific classes
RD.CLASS_BUFF_BLACKLIST = {
  WARRIOR = {
    { category = "int" },
    { category = "spirit" },
    { category = "paladin", blessingKey = "wisdom", spellPattern = "Wisdom" },
  },
  ROGUE = {
    { category = "int" },
    { category = "spirit" },
    { category = "paladin", blessingKey = "wisdom", spellPattern = "Wisdom" },
  },
  PALADIN = {
    { category = "spirit" },
    { category = "paladin", blessingKey = "might", spellPattern = "Might", roleFilter = { HEALERS = true } },
  },
  DRUID = {
    { category = "paladin", blessingKey = "wisdom", spellPattern = "Wisdom", roleFilter = { TANKS = true, MELEE = true } },
  },
  HUNTER = {
    { category = "spirit" },
  },
  MAGE = {
    { category = "paladin", blessingKey = "might", spellPattern = "Might" },
  },
  WARLOCK = {
    { category = "paladin", blessingKey = "might", spellPattern = "Might" },
  },
  PRIEST = {
    { category = "paladin", blessingKey = "might", spellPattern = "Might" },
  },
}

-- Check if a specific buff is blacklisted for a player's role or class
-- @param role string  e.g. "TANKS" (from OGRH_GetPlayerRole)
-- @param category string  e.g. "paladin"
-- @param buffName string  the actual buff name from scanning
-- @param playerClass string  (optional) e.g. "Paladin" — will be uppercased internally
-- @return boolean  true if this buff should NOT be on this player
function RD.IsBuffBlacklisted(role, category, buffName, playerClass)
  if not category then return false end

  -- Check role-based blacklist
  if role then
    local roleBlacklist = RD.BUFF_BLACKLIST[role]
    if roleBlacklist then
      for _, entry in ipairs(roleBlacklist) do
        if entry.category == category then
          -- If classFilter is set, only apply to that specific class
          local classMatch = true
          if entry.classFilter and playerClass then
            classMatch = string.upper(playerClass) == entry.classFilter
          elseif entry.classFilter then
            classMatch = false
          end
          if classMatch then
            if entry.spellPattern then
              if buffName and string.find(buffName, entry.spellPattern) then
                return true
              end
            else
              return true
            end
          end
        end
      end
    end
  end

  -- Check class-based blacklist
  if playerClass then
    local classToken = string.upper(playerClass)
    local classBlacklist = RD.CLASS_BUFF_BLACKLIST[classToken]
    if classBlacklist then
      for _, entry in ipairs(classBlacklist) do
        if entry.category == category then
          -- If roleFilter is set, only apply when player's role matches
          local roleMatch = true
          if entry.roleFilter then
            roleMatch = role and entry.roleFilter[role] or false
          end
          if roleMatch then
            if entry.spellPattern then
              if buffName and string.find(buffName, entry.spellPattern) then
                return true
              end
            else
              return true
            end
          end
        end
      end
    end
  end

  return false
end

-- Get the expected paladin blessing key for a player class from BuffManager assignments
-- Returns a table of blessing keys (one per paladin slot) or nil
-- @param playerClass string  Class name from GetRaidRosterInfo (localized, e.g. "Paladin")
function RD.GetExpectedBlessings(playerClass)
  if not playerClass then return nil end
  if not OGRH.BuffManager or not OGRH.BuffManager.GetRole then return nil end

  -- BuffManager stores class keys as uppercase tokens (PALADIN, WARRIOR, etc.)
  local classToken = string.upper(playerClass)

  local raidIdx = (OGRH.SVM and OGRH.SVM.GetPath) and OGRH.SVM.GetPath("selectedRaidIndex") or 1
  local role = OGRH.BuffManager.GetRole(raidIdx)
  if not role then return nil end

  -- Must call EnsureBuffRoles to guarantee canonical ordering and data migration
  if OGRH.BuffManager.EnsureBuffRoles then
    OGRH.BuffManager.EnsureBuffRoles(role)
  end

  if not role.buffRoles then return nil end

  -- Find the paladin buff role by flag, not by hardcoded index
  local paladinBR = nil
  for _, br in ipairs(role.buffRoles) do
    if br.isPaladinRole then
      paladinBR = br
      break
    end
  end
  if not paladinBR or not paladinBR.paladinAssignments then return nil end

  local blessings = {}
  for slotIdx, assignments in pairs(paladinBR.paladinAssignments) do
    if type(assignments) == "table" and assignments[classToken] then
      table.insert(blessings, assignments[classToken])
    end
  end

  if table.getn(blessings) == 0 then return nil end
  return blessings
end

-- Look up which paladin player is assigned to buff a given class with a given blessing
-- e.g. GetBlessingAssignee("WARRIOR", "might") -> "Healbot" (the paladin player name)
function RD.GetBlessingAssignee(classToken, blessingKey)
  if not classToken or not blessingKey then return nil end
  if not OGRH.BuffManager or not OGRH.BuffManager.GetRole then return nil end

  local raidIdx = (OGRH.SVM and OGRH.SVM.GetPath) and OGRH.SVM.GetPath("selectedRaidIndex") or 1
  local role = OGRH.BuffManager.GetRole(raidIdx)
  if not role then return nil end

  if OGRH.BuffManager.EnsureBuffRoles then
    OGRH.BuffManager.EnsureBuffRoles(role)
  end

  if not role.buffRoles then return nil end

  -- Find the paladin buff role
  local paladinBR = nil
  for _, br in ipairs(role.buffRoles) do
    if br.isPaladinRole then
      paladinBR = br
      break
    end
  end
  if not paladinBR or not paladinBR.paladinAssignments then return nil end

  for slotIdx, assignments in pairs(paladinBR.paladinAssignments) do
    if type(assignments) == "table" and assignments[classToken] == blessingKey then
      local paladinName = paladinBR.assignedPlayers and paladinBR.assignedPlayers[slotIdx]
      if paladinName and paladinName ~= "" then
        return paladinName
      end
    end
  end

  return nil
end

-- Check if a group number exists in a groupAssignments array.
-- BuffManager stores groups as a sorted array of group numbers: {1, 2, 3, 5}
-- NOT as a set {[1]=true, [5]=true}.  This helper searches values correctly.
function RD.GroupListContains(groups, groupNum)
  if not groups then return false end
  for _, gn in ipairs(groups) do
    if gn == groupNum then return true end
  end
  return false
end

-- Look up which player is assigned to cast a standard buff for a given subgroup
-- e.g. GetStandardBuffAssignee("fortitude", 3) -> "PriestA"
function RD.GetStandardBuffAssignee(buffType, subgroup)
  if not buffType or not subgroup then return nil end
  if not OGRH.BuffManager or not OGRH.BuffManager.GetRole then return nil end

  local raidIdx = (OGRH.SVM and OGRH.SVM.GetPath) and OGRH.SVM.GetPath("selectedRaidIndex") or 1
  local role = OGRH.BuffManager.GetRole(raidIdx)
  if not role then return nil end

  if OGRH.BuffManager.EnsureBuffRoles then
    OGRH.BuffManager.EnsureBuffRoles(role)
  end

  if not role.buffRoles then return nil end

  for _, br in ipairs(role.buffRoles) do
    if br.buffType == buffType and not br.isPaladinRole and br.assignedPlayers then
      for slotIdx, playerName in pairs(br.assignedPlayers) do
        if playerName and playerName ~= "" then
          local groups = br.groupAssignments and br.groupAssignments[slotIdx]
          if RD.GroupListContains(groups, subgroup) then
            return playerName
          end
        end
      end
    end
  end

  return nil
end

-- Spell IDs for group/raid buff versions (used for spell links in announcements)
RD.BUFF_SPELL_IDS = {
  fortitude = 21562,   -- Prayer of Fortitude
  spirit = 27681,      -- Prayer of Spirit
  int = 23028,         -- Arcane Brilliance
  motw = 21849,        -- Gift of the Wild
  shadowprot = 27683,  -- Prayer of Shadow Protection
  kings = 25898,       -- Greater Blessing of Kings
  might = 25782,       -- Greater Blessing of Might
  wisdom = 25894,      -- Greater Blessing of Wisdom
  salvation = 25895,   -- Greater Blessing of Salvation
  light = 25890,       -- Greater Blessing of Light
  sanctuary = 25899,   -- Greater Blessing of Sanctuary
}

-- Get a clickable spell link for announcements
-- Uses SpellInfo (Nampower) to resolve spell name, builds |Hspell: hyperlink
function RD.GetSpellLink(spellId, fallbackName)
  if spellId and SpellInfo then
    local ok, spellName = pcall(SpellInfo, spellId)
    if ok and spellName and spellName ~= "" then
      return "\124cffffffff\124Hspell:" .. spellId .. "\124h[" .. spellName .. "]\124h\124r"
    end
  end
  if fallbackName then return "[" .. fallbackName .. "]" end
  return nil
end

-- Get a clickable item link for consume announcements
-- Uses GetItemInfo to resolve item name and quality color
function RD.GetItemLink(itemId, fallbackName)
  if itemId and GetItemInfo then
    local itemName, itemLink, itemQuality = GetItemInfo(itemId)
    if itemLink and itemName then
      local _, _, _, color = GetItemQualityColor(itemQuality or 1)
      return color .. "\124H" .. itemLink .. "\124h[" .. itemName .. "]\124h\124r"
    end
  end
  if fallbackName then return "[" .. fallbackName .. "]" end
  return nil
end

-- Human-readable labels for blessing keys
RD.BLESSING_KEY_LABELS = {
  kings = "Kings",
  wisdom = "Wisdom",
  might = "Might",
  salvation = "Salvation",
  light = "Light",
  sanctuary = "Sanctuary",
}

-- Classify a specific paladin blessing buff name into a blessing key
-- e.g. "Blessing of Might" -> "might", "Greater Blessing of Kings" -> "kings"
function RD.ClassifyPaladinBlessing(buffName)
  if not buffName then return nil end
  -- Match "Blessing of X" or "Greater Blessing of X"
  local blessingKeys = {
    { pattern = "Kings",    key = "kings" },
    { pattern = "Wisdom",   key = "wisdom" },
    { pattern = "Might",    key = "might" },
    { pattern = "Salvation", key = "salvation" },
    { pattern = "Light",    key = "light" },
    { pattern = "Sanctuary", key = "sanctuary" },
  }
  for _, entry in ipairs(blessingKeys) do
    if string.find(buffName, entry.pattern) then
      return entry.key
    end
  end
  return nil
end

-- ============================================
-- Buff Readyness Scanner
-- ============================================
function RD.ScanBuffReadyness()
  local buffStatus = {
    ready = 0,
    total = 0,
    missing = {},    -- { {player = "Name", buff = "fortitude"}, ... }
    byBuff = {},     -- { ["fortitude"] = {ready = 0, total = 0, missing = {"Name1", "Name2"}} }
    blacklisted = {}, -- { {player = "Name", buff = "salvation", role = "TANKS"} }
  }

  local numMembers = GetNumRaidMembers()
  if numMembers == 0 then
    buffStatus.status = "gray"
    return buffStatus
  end

  -- Cache raid class composition for RaidHasClass checks
  local classesInRaid = {}
  for i = 1, numMembers do
    local _, _, _, _, class = GetRaidRosterInfo(i)
    if class then classesInRaid[class] = true end
  end

  for i = 1, numMembers do
    local name, _, subgroup, level, class = GetRaidRosterInfo(i)
    local unitId = "raid" .. i
    if name and UnitIsConnected(unitId) and not UnitIsDeadOrGhost(unitId) then
      -- Get player role for blacklist checking
      local playerRole = OGRH_GetPlayerRole and OGRH_GetPlayerRole(name)

      -- Scan all buffs on this unit using Nampower-enhanced scanning
      local unitBuffs = RD.ScanUnitBuffs(unitId)
      local playerCategories = {}       -- category -> true  (has this buff category)
      local playerBlessingKeys = {}     -- blessingKey -> true  (which paladin blessings)
      local playerBlessingNames = {}    -- blessingKey -> buffName  (for blacklist reporting)

      for _, buff in ipairs(unitBuffs) do
        local category = RD.ClassifyBuff(buff.name)
        if category then
          -- Check blacklist before marking as present
          if RD.IsBuffBlacklisted(playerRole, category, buff.name, class) then
            table.insert(buffStatus.blacklisted, {
              player = name,
              buff = buff.name,
              category = category,
              role = playerRole,
            })
          else
            playerCategories[category] = true
          end

          -- Track specific paladin blessings
          if category == "paladin" then
            local bKey = RD.ClassifyPaladinBlessing(buff.name)
            if bKey then
              playerBlessingKeys[bKey] = true
              playerBlessingNames[bKey] = buff.name
              -- Also check blacklist for specific blessings
              if RD.IsBuffBlacklisted(playerRole, category, buff.name, class) then
                -- Already tracked above in blacklisted, but don't count it as present
                playerCategories["paladin"] = nil
              end
            end
          end
        end
      end

      -- Determine required standard buffs for this player's class and subgroup
      local required = RD.GetRequiredBuffsWithComposition(class, classesInRaid, subgroup)
      local playerMissingAny = false

      for _, buffCat in ipairs(required) do
        -- Skip buff categories that are blacklisted for this player's role/class
        if RD.IsBuffBlacklisted(playerRole, buffCat, nil, class) then
          -- Don't count this buff as required for this player
        else
          -- Initialize byBuff tracking
          if not buffStatus.byBuff[buffCat] then
            buffStatus.byBuff[buffCat] = { ready = 0, total = 0, missing = {} }
          end
          buffStatus.byBuff[buffCat].total = buffStatus.byBuff[buffCat].total + 1

          if playerCategories[buffCat] then
            buffStatus.byBuff[buffCat].ready = buffStatus.byBuff[buffCat].ready + 1
          else
            playerMissingAny = true
            local upperClass = string.upper(class)
            local assignee = RD.GetStandardBuffAssignee(buffCat, subgroup) or "?"
            table.insert(buffStatus.missing, { player = name, buff = buffCat, class = upperClass, subgroup = subgroup, assignee = assignee })
            table.insert(buffStatus.byBuff[buffCat].missing, { name = name, class = upperClass, subgroup = subgroup, assignee = assignee })
          end
        end
      end

      -- Check paladin blessings: per-class specific assignments from BuffManager
      local paladinEnabled = true
      local enabledCats = RD.GetSetting("buffCategories") or RD.SVM_DEFAULTS.buffCategories
      if enabledCats and enabledCats.paladin == false then paladinEnabled = false end
      local expectedBlessings = paladinEnabled and RD.GetExpectedBlessings(class) or nil
      if expectedBlessings then
        for _, blessingKey in ipairs(expectedBlessings) do
          -- Apply blacklist: if this player's role + blessing is blacklisted, skip it
          local blessingName = "Blessing of " .. (RD.BLESSING_KEY_LABELS[blessingKey] or blessingKey)
          local skipBlacklisted = false
          if RD.IsBuffBlacklisted(playerRole, "paladin", blessingName, class) then
            skipBlacklisted = true
          end

          if not skipBlacklisted then
            local byBuffKey = "Blessing: " .. (RD.BLESSING_KEY_LABELS[blessingKey] or blessingKey)
            if not buffStatus.byBuff[byBuffKey] then
              buffStatus.byBuff[byBuffKey] = { ready = 0, total = 0, missing = {} }
            end
            buffStatus.byBuff[byBuffKey].total = buffStatus.byBuff[byBuffKey].total + 1

            if playerBlessingKeys[blessingKey] then
              buffStatus.byBuff[byBuffKey].ready = buffStatus.byBuff[byBuffKey].ready + 1
            else
              playerMissingAny = true
              local upperClass = string.upper(class)
              local assignee = RD.GetBlessingAssignee(string.upper(class), blessingKey)
              table.insert(buffStatus.missing, { player = name, buff = byBuffKey, class = upperClass, subgroup = subgroup, assignee = assignee })
              table.insert(buffStatus.byBuff[byBuffKey].missing, { name = name, class = upperClass, subgroup = subgroup, assignee = assignee })
            end
          end
        end
      end

      buffStatus.total = buffStatus.total + 1
      if not playerMissingAny then
        buffStatus.ready = buffStatus.ready + 1
      end
    end
  end

  -- Evaluate status using thresholds
  local greenThresh = 100
  local yellowThresh = RD.GetSetting("thresholds.buff") or RD.SVM_DEFAULTS.thresholds.buff
  return RD.EvaluateStatus(buffStatus, greenThresh, yellowThresh)
end

-- Optimized version of GetRequiredBuffs that takes pre-computed class composition
-- Only requires buffs that have active assignments in BuffManager AND cover this player's group
function RD.GetRequiredBuffsWithComposition(class, classesInRaid, subgroup)
  -- Only require buff types that have active BuffManager assignments
  local assignedBuffTypes = RD.GetAssignedBuffTypes()
  if not assignedBuffTypes then assignedBuffTypes = {} end

  local candidates = {}
  local candidateSet = {}  -- track what's already added
  for buffType, groupData in pairs(assignedBuffTypes) do
    local coversThisGroup = false

    if groupData == true then
      -- Paladin blessings: not group-gated, apply to all
      coversThisGroup = true
    elseif type(groupData) == "table" and subgroup then
      -- Standard buffs: only include if this player's subgroup is in the assigned groups
      if groupData[subgroup] then
        coversThisGroup = true
      end
    end

    if coversThisGroup then
      table.insert(candidates, buffType)
      candidateSet[buffType] = true
    end
  end

  -- Add buff types from UNMANAGED classes (simple X/Y evaluation, no group gating).
  -- Only added when the provider class is present in the raid.
  local UNMANAGED_BUFF_MAP = {
    priest = { types = {"fortitude", "spirit"}, provider = "Priest" },
    druid  = { types = {"motw"},               provider = "Druid"  },
    mage   = { types = {"int"},                provider = "Mage"   },
  }
  local isClassManaged = OGRH.BuffManager and OGRH.BuffManager.IsClassManaged
  for classKey, info in pairs(UNMANAGED_BUFF_MAP) do
    if isClassManaged and not isClassManaged(classKey) then
      if classesInRaid[info.provider] then
        for _, bt in ipairs(info.types) do
          if not candidateSet[bt] then
            table.insert(candidates, bt)
            candidateSet[bt] = true
          end
        end
      end
    end
  end

  -- Filter: mana-only buffs (spirit, int) only apply to mana classes
  -- Filter by enabled categories in settings
  local enabled = RD.GetSetting("buffCategories") or RD.SVM_DEFAULTS.buffCategories
  local filtered = {}
  for _, cat in ipairs(candidates) do
    local include = true

    -- Spirit and Int only required for mana users
    if cat == "spirit" or cat == "int" then
      if not RD.MANA_CLASSES[class] then
        include = false
      end
    end

    -- Check user-toggled category setting
    if enabled[cat] == false then
      include = false
    end

    if include then
      table.insert(filtered, cat)
    end
  end

  return filtered
end

-- Query BuffManager for which buff types have active player assignments
-- Returns a table keyed by buffType:
--   Standard buffs: { [buffType] = { [groupNum] = true, ... } } (set of covered groups)
--   Paladin blessings: { paladin = true } (applies based on per-class assignments, not groups)
function RD.GetAssignedBuffTypes()
  if not OGRH.BuffManager or not OGRH.BuffManager.GetRole then return {} end

  local raidIdx = (OGRH.SVM and OGRH.SVM.GetPath) and OGRH.SVM.GetPath("selectedRaidIndex") or 1
  local role = OGRH.BuffManager.GetRole(raidIdx)
  if not role then return {} end

  if OGRH.BuffManager.EnsureBuffRoles then
    OGRH.BuffManager.EnsureBuffRoles(role)
  end

  if not role.buffRoles then return {} end

  local assigned = {}
  for _, br in ipairs(role.buffRoles) do
    if br.buffType and br.assignedPlayers then
      -- Skip paladin blessings — they are handled separately via per-class paladinAssignments
      if not br.isPaladinRole then
        -- Standard buffs: collect the UNION of all assigned groups across all slots
        for slotIdx, playerName in pairs(br.assignedPlayers) do
          if playerName and playerName ~= "" then
            local groups = br.groupAssignments and br.groupAssignments[slotIdx]
            if groups then
              -- groups is a sorted array of group numbers: {1, 2, 3, 5}
              for _, grpNum in ipairs(groups) do
                if not assigned[br.buffType] then
                  assigned[br.buffType] = {}
                end
                assigned[br.buffType][grpNum] = true
              end
            end
          end
        end
      end
    end
  end

  return assigned
end

-- ============================================
-- Buff Classification
-- ============================================
function RD.ClassifyBuff(buffName)
  if not buffName then return nil end
  if string.find(buffName, "Fortitude") then return "fortitude" end
  if string.find(buffName, "Divine Spirit") or string.find(buffName, "Prayer of Spirit") then return "spirit" end
  if string.find(buffName, "Shadow Protection") then return "shadowprot" end
  if string.find(buffName, "Mark of the Wild") or string.find(buffName, "Gift of the Wild") then return "motw" end
  if string.find(buffName, "Arcane Intellect") or string.find(buffName, "Arcane Brilliance") then return "int" end
  if string.find(buffName, "Blessing of") or string.find(buffName, "Greater Blessing") then return "paladin" end
  return nil
end

-- Get required buffs for a class, accounting for raid composition
function RD.GetRequiredBuffs(class)
  local required = { "fortitude", "motw" }

  -- Mana users also need Spirit and Intellect
  if RD.MANA_CLASSES[class] then
    table.insert(required, "spirit")
    table.insert(required, "int")
  end

  -- Shadow prot if priests in raid
  if RD.RaidHasClass("Priest") then
    table.insert(required, "shadowprot")
  end

  -- Paladin blessings if paladins in raid
  if RD.RaidHasClass("Paladin") then
    table.insert(required, "paladin")
  end

  -- Filter by enabled categories in settings
  local enabled = RD.GetSetting("buffCategories") or RD.SVM_DEFAULTS.buffCategories
  local filtered = {}
  for _, cat in ipairs(required) do
    if enabled[cat] ~= false then
      table.insert(filtered, cat)
    end
  end

  return filtered
end

-- Check if a specific class exists in the raid
function RD.RaidHasClass(className)
  local numMembers = GetNumRaidMembers()
  if numMembers == 0 then return false end

  for i = 1, numMembers do
    local _, _, _, _, class = GetRaidRosterInfo(i)
    if class == className then
      return true
    end
  end
  return false
end

-- ============================================
-- Utility: Format Time
-- ============================================
function RD.FormatTime(seconds)
  if not seconds or seconds <= 0 then return "0s" end
  local mins = math.floor(seconds / 60)
  local secs = math.floor(seconds - mins * 60)
  if mins > 0 then
    return string.format("%dm %ds", mins, secs)
  else
    return string.format("%ds", secs)
  end
end

-- ============================================
-- Encounter Consume Buff Detection
-- ============================================
function RD.PlayerHasConsumeBuff(unitId, consumeData)
  if not consumeData then return false end

  -- Build list of spell IDs to look for
  local spellIds = {}
  if consumeData.primaryId and RD.ItemToSpell[consumeData.primaryId] then
    spellIds[RD.ItemToSpell[consumeData.primaryId]] = true
  end
  if consumeData.secondaryId and RD.ItemToSpell[consumeData.secondaryId] then
    spellIds[RD.ItemToSpell[consumeData.secondaryId]] = true
  end

  -- Scan buffs on the unit
  -- TurtleWoW UnitBuff returns: texture, stacks, spellId  (3 values)
  local buffIndex = 1
  while true do
    local texture, stacks, spellId = UnitBuff(unitId, buffIndex)
    if not texture then break end

    -- Primary check: spellId match
    if spellId and spellIds[spellId] then
      return true
    end

    -- Fallback: resolve buff name via tooltip and match against consume names
    if consumeData.primaryName or consumeData.secondaryName then
      local buffName = RD.GetBuffNameFromTooltip(unitId, buffIndex)
      if buffName then
        if consumeData.primaryName and string.find(buffName, consumeData.primaryName) then
          return true
        end
        if consumeData.secondaryName and string.find(buffName, consumeData.secondaryName) then
          return true
        end
      end
    end

    buffIndex = buffIndex + 1
  end

  return false
end

-- ============================================
-- Class Consume Scanner
-- ============================================
-- Uses ConsumesTracking (CT) to poll RABuffs for each raid member,
-- calculate their consume score, and compare against the threshold.
function RD.ScanClassConsumes()
  local CT = OGRH.ConsumesTracking
  local status = {
    ready = 0,
    total = 0,
    missing = {},        -- { {name, class, score, details}, ... }
    averageScore = 0,
    status = "gray",
  }

  -- Require RABuffs integration
  if not CT or not CT.IsRABuffsAvailable or not CT.IsRABuffsAvailable() then
    return status
  end
  if not CT.CheckForOGRHProfile or not CT.CheckForOGRHProfile() then
    return status
  end

  -- Load OGRH_Consumables profile bars
  local profileKey = GetCVar("realmName") .. "." .. UnitName("player") .. ".OGRH_Consumables"
  local profileBars = RABui_Settings and RABui_Settings.Layout and RABui_Settings.Layout[profileKey]
  if not profileBars or table.getn(profileBars) == 0 then
    return status
  end

  -- Get raid/encounter names for flask requirement resolution
  local raidName, encounterName = nil, nil
  if OGRH.GetSelectedRaidAndEncounter then
    raidName, encounterName = OGRH.GetSelectedRaidAndEncounter()
  end

  -- Build raid data: {playerName = {class, buffs = {buffKey = true}}}
  local raidData = {}
  for _, bar in ipairs(profileBars) do
    if bar.buffKey and RAB_Buffs and RAB_Buffs[bar.buffKey] then
      local buffed, fading, total, misc, mhead, hhead, mtext, htext, invert, raw = RAB_CallRaidBuffCheck(bar, true, true)
      if raw and type(raw) == "table" then
        for _, playerData in ipairs(raw) do
          if playerData and playerData.name then
            if not raidData[playerData.name] then
              raidData[playerData.name] = {
                class = playerData.class,
                buffs = {}
              }
            end
            if playerData.buffed then
              raidData[playerData.name].buffs[bar.buffKey] = true
            end
          end
        end
      end
    end
  end

  -- Calculate scores for all players
  local threshold = RD.GetConsumeThreshold()
  local totalScore = 0
  local countScored = 0

  for playerName, data in pairs(raidData) do
    local score, err, details = CT.CalculatePlayerScore(playerName, data.class, raidData, raidName, encounterName)
    if score then
      countScored = countScored + 1
      totalScore = totalScore + score
      status.total = status.total + 1

      if score >= threshold then
        status.ready = status.ready + 1
      else
        table.insert(status.missing, {
          name = playerName,
          class = string.upper(data.class or "UNKNOWN"),
          score = score,
          details = details,
        })
      end
    end
  end

  status.averageScore = countScored > 0 and math.floor(totalScore / countScored) or 0

  -- Sort missing by score ascending (worst first)
  table.sort(status.missing, function(a, b) return a.score < b.score end)

  -- Evaluate status: green if all at/above threshold, else use percentage
  local greenThresh = 100
  local yellowThresh = RD.GetSetting("thresholds.classConsume") or RD.SVM_DEFAULTS.thresholds.classConsume or 75
  return RD.EvaluateStatus(status, greenThresh, yellowThresh)
end

-- ============================================
-- Encounter Consume Scanner
-- ============================================
-- Looks at the selected encounter's isConsumeCheck role,
-- iterates each player in the raid, checks if they have
-- each required consume buff, and builds per-consume stats.
function RD.ScanEncounterConsumes()
  local status = {
    ready = 0,
    total = 0,
    missing = {},
    byConsume = {},      -- { [consumeLabel] = { ready = 0, total = 0, missing = { {name, class, subgroup}, ... } } }
    consumeItems = {},   -- { { primaryName, primaryId, secondaryName, secondaryId }, ... }
    encounterName = nil,
    hidden = true,
  }

  -- Get current encounter
  if not OGRH.GetCurrentEncounter then return status end
  local raidIdx, encIdx = OGRH.GetCurrentEncounter()
  if not raidIdx or not encIdx then return status end

  OGRH.EnsureSV()
  local raids = OGRH.SVM.GetPath("encounterMgmt.raids")
  if not raids or not raids[raidIdx] then return status end
  local raid = raids[raidIdx]
  if not raid.encounters or not raid.encounters[encIdx] then return status end

  local encounter = raid.encounters[encIdx]
  status.encounterName = encounter.name

  -- Find the isConsumeCheck role
  local consumeRole = nil
  if encounter.roles then
    for _, role in ipairs(encounter.roles) do
      if role.isConsumeCheck then
        consumeRole = role
        break
      end
    end
  end

  if not consumeRole or not consumeRole.consumes then return status end

  -- Collect valid consume slots
  local consumeSlots = {}
  local numSlots = consumeRole.slots or 1
  for slotIdx = 1, numSlots do
    local consumeData = consumeRole.consumes[slotIdx]
    if consumeData and consumeData.primaryId then
      table.insert(consumeSlots, consumeData)
      table.insert(status.consumeItems, consumeData)
    end
  end

  if table.getn(consumeSlots) == 0 then return status end

  -- No longer hidden since we have valid consume data
  status.hidden = false

  -- Iterate every raid member, check each consume
  local numMembers = GetNumRaidMembers()
  if numMembers == 0 then
    status.status = "gray"
    return status
  end

  for i = 1, numMembers do
    local name, _, subgroup, level, class = GetRaidRosterInfo(i)
    local unitId = "raid" .. i
    if name and UnitIsConnected(unitId) and not UnitIsDeadOrGhost(unitId) then
      local upperClass = string.upper(class or "UNKNOWN")
      local allPresent = true

      for _, consumeData in ipairs(consumeSlots) do
        local label = consumeData.primaryName or "Unknown Consume"
        if not status.byConsume[label] then
          status.byConsume[label] = { ready = 0, total = 0, missing = {}, consumeData = consumeData }
        end
        status.byConsume[label].total = status.byConsume[label].total + 1

        if RD.PlayerHasConsumeBuff(unitId, consumeData) then
          status.byConsume[label].ready = status.byConsume[label].ready + 1
        else
          allPresent = false
          table.insert(status.byConsume[label].missing, { name = name, class = upperClass, subgroup = subgroup })
        end
      end

      status.total = status.total + 1
      if allPresent then
        status.ready = status.ready + 1
      end
    end
  end

  -- Evaluate status using threshold
  local greenThresh = 100
  local yellowThresh = RD.GetSetting("thresholds.encConsume") or RD.SVM_DEFAULTS.thresholds.encConsume
                       or RD.GetSetting("thresholds.buff") or RD.SVM_DEFAULTS.thresholds.buff or 80
  return RD.EvaluateStatus(status, greenThresh, yellowThresh)
end

-- ============================================
-- Raid Data Builder (for ConsumesTracking integration)
-- ============================================
function RD.BuildRaidData()
  local data = {}
  local numMembers = GetNumRaidMembers()
  for i = 1, numMembers do
    local name, _, subgroup, level, class = GetRaidRosterInfo(i)
    if name then
      data[name] = {
        name = name,
        class = class,
        subgroup = subgroup,
        level = level,
        unitId = "raid" .. i,
      }
    end
  end
  return data
end

-- ============================================
-- Role Resources Scanner (Health + Mana per role)
-- ============================================
function RD.ScanRoleResources()
  local roles = { "TANKS", "HEALERS", "MELEE", "RANGED" }
  local result = {}
  for _, r in ipairs(roles) do
    result[r] = {
      healthCurrent = 0, healthMax = 0, health = 0,
      manaCurrent = 0, manaMax = 0, mana = 0,
      healthPlayers = {}, manaPlayers = {},
    }
  end

  local numMembers = GetNumRaidMembers()
  for i = 1, numMembers do
    local name, rank, subgroup, level, class = GetRaidRosterInfo(i)
    local unitId = "raid" .. i
    if name and UnitIsConnected(unitId) and not UnitIsDeadOrGhost(unitId) then
      local role = OGRH_GetPlayerRole and OGRH_GetPlayerRole(name)
      if not role then role = "RANGED" end  -- default unassigned to RANGED
      local pool = result[role]
      if not pool then pool = result["RANGED"] end

      -- Health
      local healthMax = UnitHealthMax(unitId)
      if healthMax > 0 then
        local healthCurrent = UnitHealth(unitId)
        local healthPct = math.floor((healthCurrent / healthMax) * 100)
        pool.healthCurrent = pool.healthCurrent + healthCurrent
        pool.healthMax = pool.healthMax + healthMax
        table.insert(pool.healthPlayers, { name = name, percent = healthPct })
      end

      -- Mana (only for mana power type)
      if UnitPowerType(unitId) == 0 then
        local manaMax = UnitManaMax(unitId)
        if manaMax > 0 then
          local manaCurrent = UnitMana(unitId)
          local manaPct = math.floor((manaCurrent / manaMax) * 100)
          pool.manaCurrent = pool.manaCurrent + manaCurrent
          pool.manaMax = pool.manaMax + manaMax
          table.insert(pool.manaPlayers, { name = name, percent = manaPct })
        end
      end
    end
  end

  -- Calculate aggregate percentages
  for _, r in ipairs(roles) do
    local pool = result[r]
    pool.health = pool.healthMax > 0
      and math.floor((pool.healthCurrent / pool.healthMax) * 100) or 100
    pool.mana = pool.manaMax > 0
      and math.floor((pool.manaCurrent / pool.manaMax) * 100) or 100
  end

  return result
end

-- ============================================
-- Scanning Engine
-- ============================================
function RD.StartScanning()
  -- Buff scan frame (2s OOC, disabled in combat)
  if not RD.BuffScanFrame then
    RD.BuffScanFrame = CreateFrame("Frame")
    RD.BuffScanFrame:SetScript("OnUpdate", function()
      if RD.State.inCombat then return end  -- Skip buff scanning in combat
      local now = GetTime()
      if now - RD.LastBuffScanTime >= RD.BuffScanInterval then
        RD.LastBuffScanTime = now
        RD.RunBuffScan()
      end
    end)
  end

  -- Resource scan frame (2s OOC, 0.25s in combat)
  if not RD.ResourceScanFrame then
    RD.ResourceScanFrame = CreateFrame("Frame")
    RD.ResourceScanFrame:SetScript("OnUpdate", function()
      local now = GetTime()
      if now - RD.LastResourceScanTime >= RD.ResourceScanInterval then
        RD.LastResourceScanTime = now
        RD.RunResourceScan()
      end
    end)
  end

  RD.State.scanning = true

  if RD.State.debug then
    OGRH.Msg("|cffff6666[RH-ReadyDash][DEBUG]|r Scanning started (buff: " .. RD.BuffScanInterval .. "s OOC, resource: " .. RD.ResourceScanIntervalOOC .. "s OOC / " .. RD.ResourceScanIntervalCombat .. "s combat)")
  end
end

function RD.StopScanning()
  if RD.BuffScanFrame then
    RD.BuffScanFrame:SetScript("OnUpdate", nil)
    RD.BuffScanFrame = nil
  end
  if RD.ResourceScanFrame then
    RD.ResourceScanFrame:SetScript("OnUpdate", nil)
    RD.ResourceScanFrame = nil
  end
  RD.State.scanning = false

  if RD.State.debug then
    OGRH.Msg("|cffff6666[RH-ReadyDash][DEBUG]|r Scanning stopped")
  end
end

-- Full scan runs both buff + resource scans (used for forced scan, roster changes, etc.)
function RD.RunFullScan()
  -- If not in a raid, scan solo player
  if GetNumRaidMembers() == 0 then
    RD.RunSoloScan()
    return
  end

  RD.RunBuffScan()
  RD.RunResourceScan()

  if RD.State.debug then
    OGRH.Msg("|cffff6666[RH-ReadyDash][DEBUG]|r Full scan completed")
  end
end

-- Buff scan: buffs, consumes, cooldowns (OOC only)
function RD.RunBuffScan()
  if GetNumRaidMembers() == 0 then return end

  if RD.ScanBuffReadyness then
    RD.State.indicators.buff = RD.ScanBuffReadyness()
  end

  if RD.ScanClassConsumes then
    RD.State.indicators.classCon = RD.ScanClassConsumes()
  end

  if RD.ScanEncounterConsumes then
    RD.State.indicators.encCon = RD.ScanEncounterConsumes()
  end

  if RD.GetRebirthReadyness then
    RD.State.indicators.rebirth = RD.GetRebirthReadyness()
  end

  if RD.GetTranquilityReadyness then
    RD.State.indicators.tranq = RD.GetTranquilityReadyness()
  end

  if RD.GetTauntReadyness then
    RD.State.indicators.taunt = RD.GetTauntReadyness()
  end

  -- Refresh the UI
  if RD.RefreshDashboard then
    RD.RefreshDashboard()
  end
end

-- Resource scan: health/mana (both OOC and combat)
function RD.RunResourceScan()
  if GetNumRaidMembers() == 0 then return end

  if RD.ScanRoleResources then
    RD.State.indicators.roleResources = RD.ScanRoleResources()
  end

  -- Refresh the UI
  if RD.RefreshDashboard then
    RD.RefreshDashboard()
  end
end

function RD.ResetAllIndicators()
  RD.State.indicators.buff     = { status = "gray", ready = 0, total = 0, missing = {}, byBuff = {} }
  RD.State.indicators.classCon = { status = "gray", ready = 0, total = 0, missing = {}, averageScore = 0 }
  RD.State.indicators.encCon   = { status = "gray", ready = 0, total = 0, missing = {}, consumeItems = {}, hidden = true }
  RD.State.indicators.roleResources = {
    TANKS   = { health = 0, mana = 0, healthPlayers = {}, manaPlayers = {} },
    HEALERS = { health = 0, mana = 0, healthPlayers = {}, manaPlayers = {} },
    MELEE   = { health = 0, mana = 0, healthPlayers = {}, manaPlayers = {} },
    RANGED  = { health = 0, mana = 0, healthPlayers = {}, manaPlayers = {} },
  }
  RD.State.indicators.rebirth  = { status = "gray", ready = 0, total = 0, onCooldown = {}, available = {} }
  RD.State.indicators.tranq    = { status = "gray", ready = 0, total = 0, onCooldown = {}, available = {} }
  RD.State.indicators.taunt    = { status = "gray", ready = 0, total = 0, onCooldown = {}, available = {} }

  if RD.RefreshDashboard then
    RD.RefreshDashboard()
  end
end

-- ============================================
-- Solo Player Scan (when not in a raid)
-- ============================================
function RD.RunSoloScan()
  local pName = UnitName("player")
  local result = {
    TANKS   = { health = 0, mana = 0, healthCurrent = 0, healthMax = 0, manaCurrent = 0, manaMax = 0, healthPlayers = {}, manaPlayers = {} },
    HEALERS = { health = 0, mana = 0, healthCurrent = 0, healthMax = 0, manaCurrent = 0, manaMax = 0, healthPlayers = {}, manaPlayers = {} },
    MELEE   = { health = 0, mana = 0, healthCurrent = 0, healthMax = 0, manaCurrent = 0, manaMax = 0, healthPlayers = {}, manaPlayers = {} },
    RANGED  = { health = 0, mana = 0, healthCurrent = 0, healthMax = 0, manaCurrent = 0, manaMax = 0, healthPlayers = {}, manaPlayers = {} },
  }

  -- Put solo player in all pools for preview
  local healthMax = UnitHealthMax("player")
  local healthCurrent = UnitHealth("player")
  local healthPct = healthMax > 0 and math.floor((healthCurrent / healthMax) * 100) or 100

  local manaPct = 100
  local hasMana = UnitPowerType("player") == 0
  if hasMana then
    local manaMax = UnitManaMax("player")
    local manaCurrent = UnitMana("player")
    manaPct = manaMax > 0 and math.floor((manaCurrent / manaMax) * 100) or 100
  end

  for _, r in ipairs({ "TANKS", "HEALERS", "MELEE", "RANGED" }) do
    result[r].health = healthPct
    result[r].healthPlayers = { { name = pName, percent = healthPct } }
    if hasMana then
      result[r].mana = manaPct
      result[r].manaPlayers = { { name = pName, percent = manaPct } }
    end
  end

  RD.State.indicators.roleResources = result

  -- Refresh the UI
  if RD.RefreshDashboard then
    RD.RefreshDashboard()
  end
end

-- ============================================
-- Combat Log Parsing (Phase 4 stubs, basic framework now)
-- ============================================
function RD.OnCombatLogEvent(msg)
  if not msg then return end

  -- Rebirth detection: "X's Rebirth" or "X casts Rebirth" patterns
  local caster = nil
  for name in string.gfind(msg, "(.+)'s Rebirth") do
    caster = name
    break
  end
  if not caster then
    for name in string.gfind(msg, "(.+) casts Rebirth") do
      caster = name
      break
    end
  end
  if caster then
    RD.RecordCooldownCast(caster, "rebirth")
    return
  end

  -- Tranquility detection
  for name in string.gfind(msg, "(.+)'s Tranquility") do
    caster = name
    break
  end
  if not caster then
    for name in string.gfind(msg, "(.+) begins to cast Tranquility") do
      caster = name
      break
    end
  end
  if caster then
    RD.RecordCooldownCast(caster, "tranquility")
    return
  end

  -- Challenging Shout / Challenging Roar detection
  for name in string.gfind(msg, "(.+)'s Challenging Shout") do
    RD.RecordCooldownCast(name, "taunt")
    return
  end
  for name in string.gfind(msg, "(.+)'s Challenging Roar") do
    RD.RecordCooldownCast(name, "taunt")
    return
  end
end

function RD.RecordCooldownCast(casterName, abilityKey)
  local tracker = RD.CooldownTrackers[abilityKey]
  if not tracker then return end

  tracker.casts[casterName] = { lastCast = GetTime() }
  tracker.reportedReady[casterName] = nil  -- Clear any previous report

  if RD.State.debug then
    OGRH.Msg("|cffff6666[RH-ReadyDash][DEBUG]|r Cooldown recorded: " .. casterName .. " cast " .. abilityKey)
  end
end

-- ============================================
-- Poll System
-- ============================================
function RD.StartCooldownPoll(abilityKey)
  RD.activePoll = {
    abilityKey = abilityKey,
    startTime = GetTime(),
    timeout = 30,
    respondents = {},
  }

  -- Clear old reportedReady for this ability
  local tracker = RD.CooldownTrackers[abilityKey]
  if tracker then
    tracker.reportedReady = {}
  end
end

function RD.OnRaidChatMessage(msg, sender)
  if not RD.activePoll then return end
  if not msg or not sender then return end

  -- Check if the message is just "+" (the raid convention for readiness)
  local trimmed = OGRH.Trim and OGRH.Trim(msg) or msg
  if trimmed ~= "+" then return end

  -- Check if poll is still active (within timeout)
  if GetTime() - RD.activePoll.startTime > RD.activePoll.timeout then
    RD.activePoll = nil
    return
  end

  local abilityKey = RD.activePoll.abilityKey
  local tracker = RD.CooldownTrackers[abilityKey]
  if not tracker then return end

  -- Validate sender is a relevant class for this ability
  local isRelevant = false
  if abilityKey == "rebirth" or abilityKey == "tranquility" then
    -- Only druids
    local class = OGRH.GetPlayerClass and OGRH.GetPlayerClass(sender)
    if class == "Druid" then
      isRelevant = true
    end
  elseif abilityKey == "taunt" then
    -- Warriors and druids with tank role
    local class = OGRH.GetPlayerClass and OGRH.GetPlayerClass(sender)
    local role = OGRH_GetPlayerRole and OGRH_GetPlayerRole(sender)
    if (class == "Warrior" or class == "Druid") and role == "TANKS" then
      isRelevant = true
    end
  end

  if isRelevant then
    tracker.reportedReady[sender] = true
    RD.activePoll.respondents[sender] = true

    if RD.State.debug then
      OGRH.Msg("|cffff6666[RH-ReadyDash][DEBUG]|r Poll response: " .. sender .. " (+) for " .. abilityKey)
    end
  end
end

-- ============================================
-- Open Buff Manager (shift-click from buff indicator)
-- ============================================
function RD.OpenBuffManager()
  if not OGRH.BuffManager or not OGRH.BuffManager.ShowWindow then return end

  local raidIdx = 1  -- active raid
  local _, _, encIdx = RD.GetCurrentEncounterData()
  if not encIdx then encIdx = 1 end

  -- Find the BuffManager role index in the Admin encounter
  local role, roleIndex, encounterIdx = OGRH.BuffManager.GetRole(raidIdx)
  if not role then
    OGRH.Msg("|cffff8800[Dashboard]|r Could not find Buff Manager role data.")
    return
  end

  OGRH.BuffManager.ShowWindow(raidIdx, encounterIdx, roleIndex)
end

-- ============================================
-- Announcement System
-- ============================================
function RD.OnIndicatorClick(indicatorType)
  local state = RD.State.indicators[indicatorType]
  if not state then return end

  -- Determine which announcement to build
  local lines = {}

  if indicatorType == "buff" then
    lines = RD.BuildBuffAnnouncement(state)
  elseif indicatorType == "classCon" then
    lines = RD.BuildClassConsumeAnnouncement(state)
  elseif indicatorType == "encCon" then
    lines = RD.BuildEncConsumeAnnouncement(state)
  elseif indicatorType == "mana" then
    lines = RD.BuildManaAnnouncement(state)
  elseif indicatorType == "health" then
    lines = RD.BuildHealthAnnouncement(state)
  elseif indicatorType == "rebirth" then
    if RD.State.inCombat then
      lines = RD.BuildCooldownAnnouncement(state, "Rebirth", "druids")
    else
      RD.StartCooldownPoll("rebirth")
      lines = { "[RH] Druids: + in /raid if your Rebirth is ready" }
    end
  elseif indicatorType == "tranq" then
    if RD.State.inCombat then
      lines = RD.BuildCooldownAnnouncement(state, "Tranquility", "druids")
    else
      RD.StartCooldownPoll("tranquility")
      lines = { "[RH] Druids: + in /raid if your Tranquility is ready" }
    end
  elseif indicatorType == "taunt" then
    if RD.State.inCombat then
      lines = RD.BuildCooldownAnnouncement(state, "AOE Taunt", "tanks")
    else
      RD.StartCooldownPoll("taunt")
      lines = { "[RH] Tanks: + in /raid if your Challenging Shout/Roar is ready" }
    end
  end

  -- Send announcement
  if table.getn(lines) > 0 then
    OGRH.SendAnnouncement(lines)
  end
end

function RD.BuildBuffAnnouncement(state)
  local lines = {}
  if not state or not state.byBuff then return lines end

  local BUFF_LABELS = {
    fortitude = "Fortitude", spirit = "Spirit", shadowprot = "Shadow Prot",
    motw = "MotW", int = "Arcane Int",
  }

  -- Helper: class-color a player name for chat
  local function colorPlayer(playerName)
    if not playerName then return "?" end
    if OGRH.ColorName then return OGRH.ColorName(playerName) end
    return playerName
  end

  -- Helper: class-color a class display name (e.g. "WARRIOR" → colored "Warrior")
  local function colorClass(classToken)
    local display = string.sub(classToken, 1, 1) .. string.lower(string.sub(classToken, 2))
    local cc = OGRH.COLOR and OGRH.COLOR.CLASS and OGRH.COLOR.CLASS[classToken]
    if cc then return cc .. display .. "|r" end
    return display
  end

  -- Helper: get spell link for a buff category or blessing key
  local function buffLink(cat, fallbackLabel)
    local spellId = RD.BUFF_SPELL_IDS[cat]
    return RD.GetSpellLink(spellId, fallbackLabel or BUFF_LABELS[cat] or cat)
  end

  -- Separate blessing categories from standard buff categories
  local blessingDeficits = {}
  local standardDeficits = {}

  for buffCat, data in pairs(state.byBuff) do
    local missingCount = table.getn(data.missing or {})
    if missingCount > 0 then
      -- Skip unmanaged class buffs from chat announcements
      -- (they still appear in the readiness indicator as X/Y)
      local BUFF_CLASS_MAP = {
        fortitude = "priest", spirit = "priest", shadowprot = "priest",
        motw = "druid", int = "mage",
      }
      local managedClassKey = BUFF_CLASS_MAP[buffCat]
      local skipUnmanaged = false
      if managedClassKey then
        local isManaged = OGRH.BuffManager and OGRH.BuffManager.IsClassManaged
          and OGRH.BuffManager.IsClassManaged(managedClassKey)
        if not isManaged then
          skipUnmanaged = true
        end
      end

      if skipUnmanaged then
        -- Not managed: skip from announcements (readiness indicator still shows X/Y)
      elseif string.find(buffCat, "^Blessing: ") then
        table.insert(blessingDeficits, { cat = buffCat, count = missingCount, missing = data.missing })
      else
        table.insert(standardDeficits, { cat = buffCat, count = missingCount, missing = data.missing })
      end
    end
  end

  -- =========================================================
  -- Standard buffs: consolidate ALL deficits per assignee
  -- into a single announcement line per caster.
  -- Format: [RH] Assignee: SpellLink → Group X, Y | SpellLink → PlayerName
  -- =========================================================
  -- Step 1: For each deficit, group missing entries by assignee
  --         and build a per-assignee → buff-parts mapping.
  local assigneeBuffParts = {}  -- assigneeName → { "SpellLink → targets", ... }
  local assigneeGlobalOrder = {} -- ordered unique assignee names
  local assigneeSeen = {}

  -- Sort standard deficits by severity first so worst buffs appear first in line
  table.sort(standardDeficits, function(a, b) return a.count > b.count end)

  for _, d in ipairs(standardDeficits) do
    local link = buffLink(d.cat)

    -- Group missing entries by assignee (pre-computed during scan)
    local byAssignee = {}
    local assigneeOrder = {}
    for _, entry in ipairs(d.missing) do
      local assignee = (type(entry) == "table" and entry.assignee) or "?"
      if not assignee or assignee == "" then assignee = "?" end
      if not byAssignee[assignee] then
        byAssignee[assignee] = {}
        table.insert(assigneeOrder, assignee)
      end
      table.insert(byAssignee[assignee], entry)
    end

    -- Build a target string per assignee for this buff
    for _, assignee in ipairs(assigneeOrder) do
      local entries = byAssignee[assignee]
      local count = table.getn(entries)
      local targetStr

      -- Mixed format: groups with 2+ missing → "Group X", groups with 1 → player name
      local groupBuckets = {}   -- subgroup → { entries }
      local groupOrder = {}     -- sorted subgroup numbers
      local groupSeen = {}
      for _, entry in ipairs(entries) do
        local sg = (type(entry) == "table" and entry.subgroup) or 0
        if not groupSeen[sg] then
          groupSeen[sg] = true
          table.insert(groupOrder, sg)
          groupBuckets[sg] = {}
        end
        table.insert(groupBuckets[sg], entry)
      end
      table.sort(groupOrder)

      -- Separate groups into "show as Group N" (2+ missing) vs "show names" (1 missing)
      local groupNums = {}   -- subgroups worth showing as "Group X"
      local soloNames = {}   -- individual player names from groups with only 1 missing
      for _, sg in ipairs(groupOrder) do
        local grpEntries = groupBuckets[sg]
        if table.getn(grpEntries) > 1 then
          table.insert(groupNums, sg)
        else
          local pName = (type(grpEntries[1]) == "table" and grpEntries[1].name) or grpEntries[1]
          table.insert(soloNames, colorPlayer(pName))
        end
      end

      -- Build target string: group ranges first, then solo names
      local targetParts = {}
      if table.getn(groupNums) > 0 then
        -- Compress consecutive group numbers into ranges: 1,2,3,5 → "1-3, 5"
        local rangeParts = {}
        local rangeStart = groupNums[1]
        local rangeEnd = groupNums[1]
        for idx = 2, table.getn(groupNums) do
          if groupNums[idx] == rangeEnd + 1 then
            rangeEnd = groupNums[idx]
          else
            if rangeStart == rangeEnd then
              table.insert(rangeParts, tostring(rangeStart))
            else
              table.insert(rangeParts, rangeStart .. "-" .. rangeEnd)
            end
            rangeStart = groupNums[idx]
            rangeEnd = groupNums[idx]
          end
        end
        if rangeStart == rangeEnd then
          table.insert(rangeParts, tostring(rangeStart))
        else
          table.insert(rangeParts, rangeStart .. "-" .. rangeEnd)
        end
        table.insert(targetParts, "Group " .. table.concat(rangeParts, ", "))
      end
      for _, n in ipairs(soloNames) do
        table.insert(targetParts, n)
      end
      targetStr = table.concat(targetParts, ", ")

      -- Track global assignee order
      if not assigneeSeen[assignee] then
        assigneeSeen[assignee] = true
        table.insert(assigneeGlobalOrder, assignee)
        assigneeBuffParts[assignee] = {}
      end
      table.insert(assigneeBuffParts[assignee], link .. " " .. targetStr)
    end
  end

  -- Step 2: Emit one line per assignee with all their buff parts
  for _, assignee in ipairs(assigneeGlobalOrder) do
    local parts = assigneeBuffParts[assignee]
    table.insert(lines, "[RH] " .. colorPlayer(assignee) .. ": " .. table.concat(parts, " - "))
  end

  -- =========================================================
  -- Paladin blessings: consolidate per paladin assignee.
  -- Format: [RH] PaladinName give blessings to Class, Class, and Class
  -- =========================================================
  local paladinClasses = {}    -- paladinName → { CLASS_TOKEN = true }
  local paladinOrder = {}
  local paladinSeen = {}
  local unassignedClasses = {} -- classes with no assignee

  for _, d in ipairs(blessingDeficits) do
    local blessingLabel = string.gsub(d.cat, "^Blessing: ", "")
    local blessingKey = nil
    for key, label in pairs(RD.BLESSING_KEY_LABELS) do
      if label == blessingLabel then
        blessingKey = key
        break
      end
    end

    if blessingKey then
      for _, entry in ipairs(d.missing) do
        local ct = (type(entry) == "table" and entry.class) or "UNKNOWN"
        local assignee = (type(entry) == "table" and entry.assignee) or nil
        if assignee then
          if not paladinSeen[assignee] then
            paladinSeen[assignee] = true
            table.insert(paladinOrder, assignee)
            paladinClasses[assignee] = {}
          end
          paladinClasses[assignee][ct] = true
        else
          unassignedClasses[ct] = true
        end
      end
    end
  end

  -- Helper: format class list with "and" before last item
  local function formatClassList(classSet)
    local tokens = {}
    for ct, _ in pairs(classSet) do
      table.insert(tokens, ct)
    end
    table.sort(tokens)
    local colored = {}
    for _, ct in ipairs(tokens) do
      table.insert(colored, colorClass(ct))
    end
    local n = table.getn(colored)
    if n == 1 then return colored[1] end
    if n == 2 then return colored[1] .. " and " .. colored[2] end
    -- 3+: "A, B, and C"
    local last = colored[n]
    local rest = {}
    for i = 1, n - 1 do table.insert(rest, colored[i]) end
    return table.concat(rest, ", ") .. ", and " .. last
  end

  -- Emit one line per paladin
  for _, pal in ipairs(paladinOrder) do
    local classList = formatClassList(paladinClasses[pal])
    table.insert(lines, "[RH] " .. colorPlayer(pal) .. " give blessings to " .. classList)
  end

  -- Emit unassigned blessings if any
  local hasUnassigned = false
  for _, _ in pairs(unassignedClasses) do hasUnassigned = true; break end
  if hasUnassigned then
    local classList = formatClassList(unassignedClasses)
    table.insert(lines, "[RH] Unassigned blessings for " .. classList)
  end

  return lines
end

function RD.BuildClassConsumeAnnouncement(state)
  local lines = {}
  if not state then return lines end

  local avgScore = state.averageScore or 0
  local threshold = RD.GetConsumeThreshold()
  local missingCount = state.missing and table.getn(state.missing) or 0

  -- Header line
  table.insert(lines, string.format(
    "[RH] %sConsume Readyness|r: %d%% avg - %d/%d ready (threshold %d%%)",
    OGRH.COLOR.ANNOUNCE, math.floor(avgScore), state.ready or 0, state.total or 0, threshold
  ))

  -- Player lines: class-colored names with scores, split at 255
  if missingCount > 0 then
    local MAX_LINE = 255
    local currentLine = ""
    local first = true

    for _, entry in ipairs(state.missing) do
      local colored = OGRH.ColorName and OGRH.ColorName(entry.name) or entry.name
      local segment = string.format("%s(%d%%)", colored, entry.score or 0)
      if not first then segment = ", " .. segment end

      if not first and string.len(currentLine) + string.len(segment) > MAX_LINE then
        table.insert(lines, currentLine)
        currentLine = string.format("%s(%d%%)", colored, entry.score or 0)
      else
        currentLine = currentLine .. segment
      end
      first = false
    end

    if currentLine ~= "" then
      table.insert(lines, currentLine)
    end
  end

  return lines
end

function RD.BuildEncConsumeAnnouncement(state)
  local lines = {}
  if not state or not state.byConsume then return lines end

  -- Helper: class-color a player name for chat
  local function colorPlayer(playerName)
    if not playerName then return "?" end
    if OGRH.ColorName then return OGRH.ColorName(playerName) end
    return playerName
  end

  -- Format: Line 1 = "[RH] Players missing [ItemLink] [or ItemLink]"
  --         Line 2+ = "Player1, Player2, Player3, ..."  (split at 255 if needed)
  local MAX_LINE = 255

  for label, data in pairs(state.byConsume) do
    local missingCount = data.missing and table.getn(data.missing) or 0
    if missingCount > 0 then
      -- Build item link from consumeData (show "Item1 or Item2" when allowAlternate)
      local consumeLink = label
      if data.consumeData then
        consumeLink = RD.GetItemLink(data.consumeData.primaryId, label)
        if data.consumeData.allowAlternate and data.consumeData.secondaryId then
          local altLink = RD.GetItemLink(data.consumeData.secondaryId, data.consumeData.secondaryName or "Alt")
          consumeLink = consumeLink .. " or " .. altLink
        end
      end

      -- Header line: consume name only (no players)
      table.insert(lines, "[RH] " .. OGRH.COLOR.ANNOUNCE .. "Players missing|r " .. consumeLink)

      -- Player lines: class-colored names, comma-separated, split at limit
      local currentLine = ""
      local first = true

      for _, entry in ipairs(data.missing) do
        local pName = (type(entry) == "table" and entry.name) or entry
        local colored = colorPlayer(pName)
        local segment = colored
        if not first then segment = ", " .. colored end

        if not first and string.len(currentLine) + string.len(segment) > MAX_LINE then
          table.insert(lines, currentLine)
          currentLine = colored
        else
          currentLine = currentLine .. segment
        end
        first = false
      end

      if currentLine ~= "" then
        table.insert(lines, currentLine)
      end
    end
  end

  return lines
end

function RD.BuildManaAnnouncement(state)
  local lines = {}
  if not state then return lines end

  local healerPct = state.healerMana and state.healerMana.percent or 0
  local dpsPct = state.dpsMana and state.dpsMana.percent or 0

  local msg = string.format("[RH] Mana: Healers %d%% | DPS %d%%", math.floor(healerPct), math.floor(dpsPct))

  -- List low mana players
  local lowPlayers = {}
  if state.healerMana and state.healerMana.low then
    for _, entry in ipairs(state.healerMana.low) do
      table.insert(lowPlayers, string.format("%s (%d%%)", entry.name, math.floor(entry.percent)))
    end
  end
  if state.dpsMana and state.dpsMana.low then
    for _, entry in ipairs(state.dpsMana.low) do
      table.insert(lowPlayers, string.format("%s (%d%%)", entry.name, math.floor(entry.percent)))
    end
  end

  if table.getn(lowPlayers) > 0 then
    msg = msg .. " — Low: " .. table.concat(lowPlayers, ", ")
  end

  table.insert(lines, msg)
  return lines
end

function RD.BuildHealthAnnouncement(state)
  local lines = {}
  if not state then return lines end

  local tankPct = state.tankHealth and state.tankHealth.percent or 0
  local raidPct = state.raidHealth and state.raidHealth.percent or 0

  local msg = string.format("[RH] Health: Tanks %d%% | Raid %d%%", math.floor(tankPct), math.floor(raidPct))

  -- List low health players
  local lowPlayers = {}
  if state.tankHealth and state.tankHealth.low then
    for _, entry in ipairs(state.tankHealth.low) do
      table.insert(lowPlayers, string.format("%s (%d%%)", entry.name, math.floor(entry.percent)))
    end
  end
  if state.raidHealth and state.raidHealth.low then
    for _, entry in ipairs(state.raidHealth.low) do
      table.insert(lowPlayers, string.format("%s (%d%%)", entry.name, math.floor(entry.percent)))
    end
  end

  if table.getn(lowPlayers) > 0 then
    msg = msg .. " — Low: " .. table.concat(lowPlayers, ", ")
  end

  table.insert(lines, msg)
  return lines
end

function RD.BuildCooldownAnnouncement(state, abilityName, groupLabel)
  local lines = {}
  if not state then return lines end

  local availableNames = {}
  if state.available then
    for _, name in ipairs(state.available) do
      table.insert(availableNames, name)
    end
  end

  if table.getn(availableNames) > 0 then
    table.insert(lines, string.format("[RH] %s available: %s (%d/%d)",
      abilityName,
      table.concat(availableNames, ", "),
      state.ready or 0,
      state.total or 0))
  else
    table.insert(lines, string.format("[RH] %s: None available (0/%d)",
      abilityName,
      state.total or 0))
  end

  return lines
end

-- ============================================
-- Event Registration
-- ============================================
function RD.RegisterEvents()
  local eventFrame = CreateFrame("Frame")

  eventFrame:RegisterEvent("ADDON_LOADED")
  eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
  eventFrame:RegisterEvent("RAID_ROSTER_UPDATE")
  eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
  eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
  eventFrame:RegisterEvent("CHAT_MSG_RAID")
  eventFrame:RegisterEvent("CHAT_MSG_RAID_LEADER")

  -- Combat log events for cooldown tracking
  eventFrame:RegisterEvent("CHAT_MSG_SPELL_SELF_DAMAGE")
  eventFrame:RegisterEvent("CHAT_MSG_SPELL_PARTY_DAMAGE")
  eventFrame:RegisterEvent("CHAT_MSG_SPELL_HOSTILEPLAYER_DAMAGE")
  eventFrame:RegisterEvent("CHAT_MSG_SPELL_FRIENDLYPLAYER_DAMAGE")
  eventFrame:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE")
  eventFrame:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_PARTY_DAMAGE")
  eventFrame:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_FRIENDLYPLAYER_DAMAGE")
  eventFrame:RegisterEvent("CHAT_MSG_SPELL_SELF_BUFF")
  eventFrame:RegisterEvent("CHAT_MSG_SPELL_PARTY_BUFF")
  eventFrame:RegisterEvent("CHAT_MSG_SPELL_FRIENDLYPLAYER_BUFF")
  eventFrame:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_SELF_BUFF")
  eventFrame:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_PARTY_BUFF")
  eventFrame:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_FRIENDLYPLAYER_BUFF")

  eventFrame:SetScript("OnEvent", function()
    if event == "ADDON_LOADED" and arg1 == "OG-RaidHelper" then
      -- Deferred initialization handled by Initialize()
      return
    end

    if event == "PLAYER_ENTERING_WORLD" then
      -- Check if we should start scanning
      if GetNumRaidMembers() > 0 then
        local enabled = RD.GetSetting("enabled")
        if enabled ~= false then
          RD.StartScanning()
        end
      end
      return
    end

    if event == "RAID_ROSTER_UPDATE" then
      local numMembers = GetNumRaidMembers()
      if numMembers > 0 then
        local enabled = RD.GetSetting("enabled")
        if enabled ~= false and not RD.State.scanning then
          RD.StartScanning()
        end
        -- Force an immediate scan on roster change
        if RD.State.scanning then
          RD.RunFullScan()
        end
      else
        -- Left raid
        RD.StopScanning()
        RD.ResetAllIndicators()
      end
      return
    end

    if event == "PLAYER_REGEN_DISABLED" then
      -- Entered combat: switch resource scan to fast interval
      RD.State.inCombat = true
      RD.ResourceScanInterval = RD.ResourceScanIntervalCombat
      return
    end

    if event == "PLAYER_REGEN_ENABLED" then
      -- Left combat: restore resource scan to slow interval, run one buff scan
      RD.State.inCombat = false
      RD.ResourceScanInterval = RD.ResourceScanIntervalOOC
      RD.RunBuffScan()
      return
    end

    if event == "CHAT_MSG_RAID" or event == "CHAT_MSG_RAID_LEADER" then
      -- Poll listener
      RD.OnRaidChatMessage(arg1, arg2)
      return
    end

    -- Combat log events — all spell events for cooldown tracking
    if string.find(event, "CHAT_MSG_SPELL") then
      RD.OnCombatLogEvent(arg1)
      return
    end
  end)

  RD.EventFrame = eventFrame
end

-- ============================================
-- Encounter Change Hooks
-- ============================================
function RD.HookEncounterNavigation()
  -- Hook into encounter navigation to re-scan when encounter changes
  if OGRH.NavigateToNextEncounter then
    local originalNavNext = OGRH.NavigateToNextEncounter
    OGRH.NavigateToNextEncounter = function()
      originalNavNext()
      if RD.State.scanning then
        RD.RunFullScan()
      end
    end
  end

  if OGRH.NavigateToPreviousEncounter then
    local originalNavPrev = OGRH.NavigateToPreviousEncounter
    OGRH.NavigateToPreviousEncounter = function()
      originalNavPrev()
      if RD.State.scanning then
        RD.RunFullScan()
      end
    end
  end

  if RD.State.debug then
    OGRH.Msg("|cffff6666[RH-ReadyDash][DEBUG]|r Encounter navigation hooks installed")
  end
end

-- ============================================
-- Module Load
-- ============================================
-- Initialize will be called after UI is created (from ReadynessDashboardUI.lua)
-- Hook encounter navigation now while functions are available
RD.HookEncounterNavigation()
