# Readyness Dashboard — Design Document

**Version:** 1.1  
**Module:** ReadynessDashboard.lua  
**Location:** `_Raid/ReadynessDashboard.lua`  
**Target Release:** 2.1  
**Last Updated:** February 17, 2026  
**Status:** Design Phase  
**Dependencies:** EncounterMgmt.lua, ConsumesTracking.lua, BuffManager.lua, SVM, OGST, ChatThrottleLib

---

## Executive Summary

The Readyness Dashboard is a compact, always-visible status panel that aggregates readiness data from multiple OG-RaidHelper subsystems into a single glanceable interface for raid leaders, admins, and assists. Each readiness category is displayed as a color-coded indicator (red/yellow/green) with a deficit count (X/Y missing), and clicking an indicator triggers a targeted raid announcement identifying the responsible player(s).

**Core Goals:**

- **At-a-Glance Readiness** — Single panel showing buff, consume, mana, health, and cooldown readiness for the entire raid
- **Traffic-Light Indicators** — Red / Yellow / Green with X/Y deficit counts per category
- **Click-to-Announce** — Left-click any indicator to announce the responsible assignee(s) to raid chat
- **Combat-Aware Behavior** — Cooldown indicators change behavior in combat (announce cast vs. poll availability)
- **Dockable/Floatable** — Panel docks to the main OGRH frame by default, or undocks to float freely
- **Encounter-Contextual** — Consume and buff requirements change as the raid navigates encounters
- **Minimal Polling** — Efficient periodic scanning with configurable intervals, not per-frame

---

## Problem Statement

### Current State

1. **Fragmented readiness data** — Buff status, consume compliance, mana levels, and cooldown availability are scattered across multiple UIs or not tracked at all
2. **No pre-pull snapshot** — Raid leaders must mentally aggregate readiness from chat, addon windows, and manual inspection
3. **No accountability feedback** — When a buff is missing, there's no quick way to announce who is assigned to provide it
4. **Cooldown tracking is blind** — Leaders have no visibility into Rebirth, Tranquility, or AOE Taunt availability across the raid
5. **Mana readiness is manual** — Leaders visually scan raid frames to estimate healer/DPS mana before pulling
6. **Health readiness is invisible** — Tank and raid health status requires scanning individual raid frames; no aggregated view exists for pre-pull or mid-combat assessment

### Target State

A single dockable panel with 8 readiness indicators that updates automatically, surfaces deficits at a glance, and enables one-click targeted announcements. The panel is always contextual to the currently selected encounter, so consume and buff requirements adapt automatically.

---

## Architecture

### Module Hierarchy

```
_Raid/
  ReadynessDashboard.lua     -- Core logic, scanning, state management
  ReadynessDashboardUI.lua   -- OGST-based UI, docked panel, indicators
```

### Integration Points

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                          Readyness Dashboard                                 │
├──────────┬──────────┬──────────┬──────────┬──────────┬──────────┬────────────┤
│  Buff    │ Class    │ Enc.     │  Mana    │ Health   │ Rebirth  │ Tranq/     │
│  Ready   │ Consume  │ Consume  │  Ready   │  Ready   │  Ready   │ Taunt      │
├──────────┴──────────┴──────────┴──────────┴──────────┴──────────┴────────────┤
│                              Data Sources                                    │
├──────────┬──────────┬──────────┬──────────┬──────────┬──────────┬────────────┤
│ RABuffs  │ Consumes │ Encounter│ UnitMana │ UnitHP   │ Combat   │ Combat     │
│ API      │ Tracking │ Mgmt     │ API      │ API      │ Log      │ Log        │
│ BuffMgr  │ Scoring  │ Consume  │          │          │ Polling  │ Polling    │
└──────────┴──────────┴──────────┴──────────┴──────────┴──────────┴────────────┘
```

### Data Flow

```
Every N seconds (configurable, default 5s):
  1. ScanBuffReadyness()      → Checks raid buffs vs BuffManager assignments
  2. ScanClassConsumes()      → Calls CT.CalculatePlayerScore() for each player
  3. ScanEncounterConsumes()  → Checks encounter consume role items via RABuffs
  4. ScanManaReadyness()      → UnitMana/UnitManaMax for healers and DPS casters
  5. ScanHealthReadyness()    → UnitHealth/UnitHealthMax for tanks and non-tanks
  6. UpdateCooldownTrackers() → Updates timers from combat log events

Each scan produces:
  { status = "green"|"yellow"|"red", ready = N, total = N, missing = {} }

UI reads state → Updates indicator colors + text → Done
```

---

## Indicator Specifications

### 1. Buff Readyness

**Purpose:** Evaluate that all desired buffs (Fortitude, Spirit, MotW, Arcane Int, Shadow Prot, Paladin Blessings) are applied to all raid members.

**Data Source:** `UnitBuff(unitId, buffSlot)` (TurtleWoW extended API returns buff name, rank, icon, count, debuffType, duration, expirationTime). BuffManager encounter assignments provide per-player buff responsibility for targeted announcements.

**Tracked Buffs:**

| Buff Category | Spells | Provider Class |
|---------------|--------|----------------|
| Fortitude | Power Word: Fortitude, Prayer of Fortitude | Priest |
| Spirit | Divine Spirit, Prayer of Spirit | Priest |
| Shadow Protection | Shadow Protection, Prayer of Shadow Protection | Priest |
| Mark of the Wild | Mark of the Wild, Gift of the Wild | Druid |
| Arcane Intellect | Arcane Intellect, Arcane Brilliance | Mage |
| Paladin Blessings | Blessing of Might/Wisdom/Kings/Salvation/Light, Greater variants | Paladin |

**Scanning Logic:**

```lua
function RD.ScanBuffReadyness()
  local buffStatus = {
    ready = 0,
    total = 0,
    missing = {},   -- { {player = "Name", buff = "Fortitude"}, ... }
    byBuff = {}     -- { ["Fortitude"] = {ready = N, total = N, missing = {}} }
  }

  for i = 1, GetNumRaidMembers() do
    local name, rank, subgroup, level, class = GetRaidRosterInfo(i)
    local unitId = "raid" .. i
    if UnitIsConnected(unitId) and not UnitIsDeadOrGhost(unitId) then
      buffStatus.total = buffStatus.total + 1

      -- Scan all buffs on this unit
      local playerBuffs = {}
      local buffIndex = 1
      while true do
        local buffName = UnitBuff(unitId, buffIndex)
        if not buffName then break end
        local category = RD.ClassifyBuff(buffName)
        if category then
          playerBuffs[category] = true
        end
        buffIndex = buffIndex + 1
      end

      -- Check required buffs for this class
      local required = RD.GetRequiredBuffs(class)
      local playerReady = true
      for _, buffCat in ipairs(required) do
        if not playerBuffs[buffCat] then
          playerReady = false
          table.insert(buffStatus.missing, {player = name, buff = buffCat})
          -- Track per-buff stats
          if not buffStatus.byBuff[buffCat] then
            buffStatus.byBuff[buffCat] = {ready = 0, total = 0, missing = {}}
          end
          buffStatus.byBuff[buffCat].total = buffStatus.byBuff[buffCat].total + 1
          table.insert(buffStatus.byBuff[buffCat].missing, name)
        end
      end

      if playerReady then
        buffStatus.ready = buffStatus.ready + 1
      end
    end
  end

  return RD.EvaluateStatus(buffStatus)
end
```

**Buff Classification:**

```lua
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
```

**Required Buffs by Class:**

All classes require: Fortitude, MotW. Additionally:
- Mana users (Priest, Mage, Warlock, Druid, Paladin, Shaman): +Spirit, +Arcane Int
- All: +Shadow Protection (if priests in raid)
- All: +Paladin Blessings (if paladins in raid)

**Managed vs Unmanaged Buff Classes:**

The Admin encounter's Buff Manager checkboxes (`managedBuffClasses`) control how each buff class is evaluated and announced:

| State | Readiness Evaluation | Announcements |
|-------|---------------------|---------------|
| **Managed** (checked) | Group-gated via BuffManager slot/group assignments | Included — directed at assigned caster with group/player targets |
| **Unmanaged** (unchecked) | Simple X/Y — all raid members checked if provider class is present | **Excluded** — deficits contribute to the score but are not announced |
| **Paladin** | Always via PallyPower integration regardless of checkbox state | Always included when blessings are assigned |

Unmanaged buff mapping:
- **Priest unchecked** → Fortitude and Spirit evaluated (Spirit respects mana-class + blacklist filters)
- **Druid unchecked** → MotW evaluated for all players
- **Mage unchecked** → Int evaluated (respects mana-class filter)

This is implemented via `OGRH.BuffManager.IsClassManaged(classKey)` checks in both `GetRequiredBuffsWithComposition` (for evaluation) and `BuildBuffAnnouncement` (for filtering).

**Click Behavior:**

Left-click announces the buff with the most missing players. When BuffManager assignments are configured for the current encounter, the announcement includes the assigned player responsible for that buff and which groups they're missing:

```
[RH] Fort missing on 5 players — Priestbro (Groups 1-3), Holyman (Groups 4-8)
```

If no BuffManager assignments exist for the current encounter, announces the deficit only:

```
[RH] Buffs: 5 players missing Fortitude, 3 missing Spirit
```

**Status Thresholds:**

| Color | Condition |
|-------|-----------|
| Green | All tracked players have all required buffs |
| Yellow | ≥80% of buff slots filled (some missing) |
| Red | <80% of buff slots filled |

---

### 2. Class Consume Readyness

**Purpose:** Evaluate consumable compliance across the raid using the existing ConsumesTracking scoring system and the raid/encounter `readyThreshold` setting.

**Data Source:** `CT.CalculatePlayerScore()` for each raid member, using the OGRH_Consumables RABuffs profile.

**Scanning Logic:**

```lua
function RD.ScanClassConsumes()
  local consumeStatus = {
    ready = 0,
    total = 0,
    missing = {},        -- { {player = "Name", score = 45, threshold = 80}, ... }
    averageScore = 0
  }

  if not CT.IsRABuffsAvailable() or not CT.CheckForOGRHProfile() then
    return { status = "red", ready = 0, total = 0, missing = {}, err = "RABuffs not available" }
  end

  -- Get threshold from current encounter or raid advanced settings
  local threshold = RD.GetConsumeThreshold()

  -- Build raid data via RABuffs
  local raidData = RD.BuildRaidData()
  local raidName, encounterName = OGRH.GetSelectedRaidAndEncounter()
  local totalScore = 0
  local playerCount = 0

  for playerName, playerInfo in pairs(raidData) do
    local score, err = CT.CalculatePlayerScore(
      playerName, playerInfo.class, raidData, raidName, encounterName
    )
    if score then
      playerCount = playerCount + 1
      consumeStatus.total = consumeStatus.total + 1
      totalScore = totalScore + score
      if score >= threshold then
        consumeStatus.ready = consumeStatus.ready + 1
      else
        table.insert(consumeStatus.missing, {
          player = playerName,
          score = score,
          threshold = threshold
        })
      end
    end
  end

  consumeStatus.averageScore = playerCount > 0
    and floor(totalScore / playerCount) or 0

  return RD.EvaluateStatus(consumeStatus)
end
```

**Click Behavior:**

Left-click announces the raid's consume compliance summary:

```
[RH] Consume Score: 85% avg — 4 below threshold (80%): Gnuzmas (45%), Shadyman (62%), Holyman (71%), Tankmedady (78%)
```

**Status Thresholds:**

| Color | Condition |
|-------|-----------|
| Green | All players at or above encounter `readyThreshold` |
| Yellow | ≥75% of players at or above threshold |
| Red | <75% of players at or above threshold |

---

### 3. Encounter Consume Readyness

**Purpose:** Evaluate whether players have used/possess the specific consumables configured in the current encounter's Consume Check role (e.g., Greater Fire Protection Potion on Ragnaros).

**Data Source:** The encounter's `isConsumeCheck` role → `role.consumes[slotIdx]` → `primaryId`/`secondaryId`. Checked via `RAB_CallRaidBuffCheck()` or TurtleWoW `UnitBuff()` with `itemToSpell` mapping.

**Scanning Logic:**

```lua
function RD.ScanEncounterConsumes()
  local encConsumeStatus = {
    ready = 0,
    total = 0,
    missing = {},       -- { {player = "Name", item = "Greater Fire Protection Potion"}, ... }
    consumeItems = {}   -- List of required items for display
  }

  -- Find the consume check role for the current encounter
  local raid, encounter = OGRH.GetCurrentEncounter()
  if not raid or not encounter then
    return { status = "green", ready = 0, total = 0, missing = {}, err = "No encounter" }
  end

  local consumeRole = nil
  if encounter.roles then
    for _, role in ipairs(encounter.roles) do
      if role.isConsumeCheck then
        consumeRole = role
        break
      end
    end
  end

  if not consumeRole or not consumeRole.consumes then
    -- No consume check role on this encounter — always green
    return { status = "green", ready = 0, total = 0, missing = {}, noRole = true }
  end

  -- Build required item list
  local requiredItems = {}
  for slotIdx, consumeData in pairs(consumeRole.consumes) do
    table.insert(requiredItems, consumeData)
    table.insert(encConsumeStatus.consumeItems, consumeData.primaryName)
  end

  -- Check each raid member for the required consume buffs
  for i = 1, GetNumRaidMembers() do
    local name, rank, subgroup, level, class = GetRaidRosterInfo(i)
    local unitId = "raid" .. i
    if UnitIsConnected(unitId) and not UnitIsDeadOrGhost(unitId) then
      -- Filter by consume role class restrictions
      if RD.PlayerMatchesConsumeClasses(class, consumeRole.classes) then
        encConsumeStatus.total = encConsumeStatus.total + 1

        local hasAll = true
        for _, consumeData in ipairs(requiredItems) do
          if not RD.PlayerHasConsumeBuff(unitId, consumeData) then
            hasAll = false
            table.insert(encConsumeStatus.missing, {
              player = name,
              item = consumeData.primaryName
            })
          end
        end

        if hasAll then
          encConsumeStatus.ready = encConsumeStatus.ready + 1
        end
      end
    end
  end

  return RD.EvaluateStatus(encConsumeStatus)
end
```

**Consume Buff Detection:**

```lua
-- itemToSpell mapping for encounter consume checking
-- Maps item IDs to the buff spell IDs they produce
RD.ItemToSpell = {
  [13457] = 17543,   -- Greater Fire Protection Potion
  [13456] = 17544,   -- Greater Frost Protection Potion
  [13458] = 17546,   -- Greater Nature Protection Potion
  [13459] = 17548,   -- Greater Shadow Protection Potion
  [13461] = 17549,   -- Greater Arcane Protection Potion
  [6049]  = 7233,    -- Fire Protection Potion
  [6050]  = 7239,    -- Frost Protection Potion
  [6052]  = 7245,    -- Nature Protection Potion
  [6048]  = 7235,    -- Shadow Protection Potion
  [3387]  = 3169,    -- Limited Invulnerability Potion
}

function RD.PlayerHasConsumeBuff(unitId, consumeData)
  local spellIds = {}
  if consumeData.primaryId and RD.ItemToSpell[consumeData.primaryId] then
    spellIds[RD.ItemToSpell[consumeData.primaryId]] = true
  end
  if consumeData.secondaryId and RD.ItemToSpell[consumeData.secondaryId] then
    spellIds[RD.ItemToSpell[consumeData.secondaryId]] = true
  end
  if consumeData.allowAlternate and consumeData.secondaryId then
    -- Already included above
  end

  -- TurtleWoW UnitBuff returns: texture, stacks, buffSpellId
  local buffIndex = 1
  while true do
    local texture, stacks, buffSpellId = UnitBuff(unitId, buffIndex)
    if not texture then break end
    if buffSpellId and spellIds[buffSpellId] then
      return true
    end
    buffIndex = buffIndex + 1
  end

  return false
end
```

**Click Behavior:**

Left-click announces who is missing the encounter-specific consume:

```
[RH] Missing Greater Fire Protection Potion: Gnuzmas, Shadyman, Holyman (3/40)
```

**Status Thresholds:**

| Color | Condition |
|-------|-----------|
| Green | All applicable players have the required consume buff(s) |
| Yellow | ≥80% have the consume |
| Red | <80% have the consume, OR no consume role exists and indicator is hidden |

**Note:** If the current encounter has no `isConsumeCheck` role, this indicator is hidden (not shown as green — it simply doesn't apply).

---

### 4. Mana Readyness

**Purpose:** Show mana readiness split into Healer Mana and DPS Mana pools to help the raid leader decide when it's safe to pull.

**Data Source:** `UnitMana(unitId)` and `UnitManaMax(unitId)` for each raid member. Role determined via `OGRH_GetPlayerRole(playerName)` → H for healers, M/R for DPS casters.

**Split Display:**

The Mana Readyness indicator shows two sub-indicators side by side:

```
┌───────────────────┐
│ H: 92%  D: 85%    │
│ ██████  █████░    │
└───────────────────┘
```

**Scanning Logic:**

```lua
function RD.ScanManaReadyness()
  local manaStatus = {
    healerMana = { current = 0, max = 0, players = {}, belowThreshold = {} },
    dpsMana    = { current = 0, max = 0, players = {}, belowThreshold = {} }
  }

  local manaThreshold = RD.GetManaThreshold()  -- Default: 80%

  for i = 1, GetNumRaidMembers() do
    local name, rank, subgroup, level, class = GetRaidRosterInfo(i)
    local unitId = "raid" .. i
    if UnitIsConnected(unitId) and not UnitIsDeadOrGhost(unitId) then
      local manaMax = UnitManaMax(unitId)
      if manaMax > 0 and UnitPowerType(unitId) == 0 then  -- 0 = Mana
        local manaCurrent = UnitMana(unitId)
        local manaPercent = floor((manaCurrent / manaMax) * 100)
        local role = OGRH_GetPlayerRole and OGRH_GetPlayerRole(name)

        local pool = nil
        if role == "H" then
          pool = manaStatus.healerMana
        elseif role == "R" or role == "M" then
          -- Only track mana classes for DPS
          local manaClasses = {MAGE=true, WARLOCK=true, PRIEST=true,
                                DRUID=true, PALADIN=true, SHAMAN=true, HUNTER=true}
          if manaClasses[class] then
            pool = manaStatus.dpsMana
          end
        end

        if pool then
          pool.current = pool.current + manaCurrent
          pool.max = pool.max + manaMax
          table.insert(pool.players, {name = name, percent = manaPercent})
          if manaPercent < manaThreshold then
            table.insert(pool.belowThreshold, {name = name, percent = manaPercent})
          end
        end
      end
    end
  end

  -- Calculate aggregate percentages
  manaStatus.healerMana.percent = manaStatus.healerMana.max > 0
    and floor((manaStatus.healerMana.current / manaStatus.healerMana.max) * 100) or 100
  manaStatus.dpsMana.percent = manaStatus.dpsMana.max > 0
    and floor((manaStatus.dpsMana.current / manaStatus.dpsMana.max) * 100) or 100

  return manaStatus
end
```

**Click Behavior:**

Left-click announces mana status:

```
[RH] Mana: Healers 92% | DPS 85% — Low: Holyman (45%), Priestbro (62%)
```

**Status Thresholds:**

| Color | Condition (per sub-indicator) |
|-------|-------------------------------|
| Green | Aggregate mana ≥90% |
| Yellow | Aggregate mana ≥70% and <90% |
| Red | Aggregate mana <70% |

---

### 5. Health Readyness

**Purpose:** Show health readiness split into Tank Health and Raid Health (everyone else) pools to help the raid leader assess survivability before pulling and monitor raid health during combat.

**Data Source:** `UnitHealth(unitId)` and `UnitHealthMax(unitId)` for each raid member. Role determined via `OGRH_GetPlayerRole(playerName)` → T for tanks, all other roles for raid.

**Split Display:**

The Health Readyness indicator shows two sub-indicators side by side, identical in layout to the Mana indicator:

```
┌───────────────────┐
│ T: 100% R: 95%    │
│ ██████  █████░    │
└───────────────────┘
```

**Scanning Logic:**

```lua
function RD.ScanHealthReadyness()
  local healthStatus = {
    tankHealth = { current = 0, max = 0, players = {}, belowThreshold = {} },
    raidHealth = { current = 0, max = 0, players = {}, belowThreshold = {} }
  }

  local healthThreshold = RD.GetHealthThreshold()  -- Default: 80%

  for i = 1, GetNumRaidMembers() do
    local name, rank, subgroup, level, class = GetRaidRosterInfo(i)
    local unitId = "raid" .. i
    if UnitIsConnected(unitId) and not UnitIsDeadOrGhost(unitId) then
      local healthMax = UnitHealthMax(unitId)
      if healthMax > 0 then
        local healthCurrent = UnitHealth(unitId)
        local healthPercent = floor((healthCurrent / healthMax) * 100)
        local role = OGRH_GetPlayerRole and OGRH_GetPlayerRole(name)

        local pool = nil
        if role == "T" then
          pool = healthStatus.tankHealth
        else
          pool = healthStatus.raidHealth
        end

        if pool then
          pool.current = pool.current + healthCurrent
          pool.max = pool.max + healthMax
          table.insert(pool.players, {name = name, percent = healthPercent})
          if healthPercent < healthThreshold then
            table.insert(pool.belowThreshold, {name = name, percent = healthPercent})
          end
        end
      end
    end
  end

  -- Calculate aggregate percentages
  healthStatus.tankHealth.percent = healthStatus.tankHealth.max > 0
    and floor((healthStatus.tankHealth.current / healthStatus.tankHealth.max) * 100) or 100
  healthStatus.raidHealth.percent = healthStatus.raidHealth.max > 0
    and floor((healthStatus.raidHealth.current / healthStatus.raidHealth.max) * 100) or 100

  return healthStatus
end
```

**Click Behavior:**

Left-click announces health status:

```
[RH] Health: Tanks 100% | Raid 95% — Low: Gnuzmas (32%), Shadyman (55%)
```

**Status Thresholds:**

| Color | Condition (per sub-indicator) |
|-------|-------------------------------|
| Green | Aggregate health ≥90% |
| Yellow | Aggregate health ≥70% and <90% |
| Red | Aggregate health <70% |

---

### 6. Rebirth Readyness

**Purpose:** Track X/Y druids who have Rebirth available (off cooldown). Rebirth has a 30-minute cooldown.

**Data Source:** Combat log parsing. There is **no WoW 1.12 API** to check another player's spell cooldowns. Tracking must be done by:

1. **Combat Log Events** — Detect `SPELL_CAST_SUCCESS` for Rebirth (spell name pattern match) and record the caster + timestamp
2. **Polling (Out of Combat)** — Request druids to report availability via `/raid +` convention
3. **Inference** — After 30 minutes from last observed cast, assume available again

**Cooldown Tracking State:**

```lua
RD.CooldownTrackers = {
  rebirth = {
    spellName = "Rebirth",
    cooldownDuration = 1800,  -- 30 minutes in seconds
    -- Tracked per druid:
    druids = {
      -- ["Druidname"] = {
      --   lastCast = GetTime() timestamp or nil,
      --   reportedReady = true/false,  -- from polling
      --   inRaid = true/false
      -- }
    }
  }
}
```

**Combat Log Detection:**

```lua
-- Registered on CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE, CHAT_MSG_SPELL_SELF_BUFF,
-- and all combat log message events
function RD.OnCombatLogEvent()
  -- TurtleWoW combat log format for spell cast:
  -- "Druidname's Rebirth heals Playername for 0."
  -- "Druidname casts Rebirth on Playername."
  -- Pattern: "<caster>'s Rebirth" or "<caster> casts Rebirth"
  local msg = arg1
  if not msg then return end

  -- Check for Rebirth cast
  local caster = nil
  -- Pattern 1: "Name's Rebirth"
  for name in string.gfind(msg, "(.+)'s Rebirth") do
    caster = name
    break
  end
  -- Pattern 2: "Name casts Rebirth"
  if not caster then
    for name in string.gfind(msg, "(.+) casts Rebirth") do
      caster = name
      break
    end
  end

  if caster and RD.CooldownTrackers.rebirth.druids[caster] then
    RD.CooldownTrackers.rebirth.druids[caster].lastCast = GetTime()
    RD.CooldownTrackers.rebirth.druids[caster].reportedReady = false
    RD.UpdateIndicator("rebirth")
  end
end
```

**Druid Roster Building:**

```lua
function RD.BuildDruidRoster()
  local druids = {}
  for i = 1, GetNumRaidMembers() do
    local name, rank, subgroup, level, class = GetRaidRosterInfo(i)
    if class == "Druid" then
      if not RD.CooldownTrackers.rebirth.druids[name] then
        RD.CooldownTrackers.rebirth.druids[name] = {
          lastCast = nil,
          reportedReady = true,  -- Assume ready until observed
          inRaid = true
        }
      else
        RD.CooldownTrackers.rebirth.druids[name].inRaid = true
      end
      druids[name] = true
    end
  end
  -- Mark druids who left
  for name, data in pairs(RD.CooldownTrackers.rebirth.druids) do
    if not druids[name] then
      data.inRaid = false
    end
  end
end
```

**Availability Calculation:**

```lua
function RD.GetRebirthReadyness()
  local status = { ready = 0, total = 0, onCooldown = {}, available = {} }
  local now = GetTime()
  local cd = RD.CooldownTrackers.rebirth.cooldownDuration

  for name, data in pairs(RD.CooldownTrackers.rebirth.druids) do
    if data.inRaid then
      status.total = status.total + 1
      local isReady = true

      if data.lastCast then
        local elapsed = now - data.lastCast
        if elapsed < cd then
          isReady = false
          local remaining = cd - elapsed
          table.insert(status.onCooldown, {
            name = name,
            remaining = remaining,
            remainingText = RD.FormatTime(remaining)
          })
        end
      end

      if isReady then
        status.ready = status.ready + 1
        table.insert(status.available, name)
      end
    end
  end

  return RD.EvaluateStatus(status)
end
```

**Click Behavior:**

**Out of combat — Left Click:**
Initiates a raid poll asking druids to report Rebirth availability:

```
[RH] Druids: + in /raid if your Rebirth is ready
```

The dashboard then listens for `CHAT_MSG_RAID` events matching `"+"` from known druids and updates their `reportedReady` status.

**In combat — Left Click:**
Announces which druid just cast Rebirth (most recent cast) or which druids still have it available:

```
[RH] Rebirth available: Druidguy, Feralboi (2/5)
```

**Right Click (any combat state):**
Shows detailed tooltip with per-druid cooldown timers.

**Status Thresholds:**

| Color | Condition |
|-------|-----------|
| Green | ≥50% of druids have Rebirth ready |
| Yellow | ≥1 druid has Rebirth ready but <50% |
| Red | 0 druids have Rebirth ready |

---

### 7. Tranquility Readyness

**Purpose:** Identical to Rebirth tracking except for Tranquility (5-minute cooldown, Druid only).

**Cooldown Duration:** 300 seconds (5 minutes)

**Combat Log Pattern:**

```lua
-- "Druidname's Tranquility heals ..."
-- "Druidname begins to cast Tranquility"
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
```

**Click Behavior:** Same as Rebirth — poll out of combat, announce in combat.

**Status Thresholds:** Same as Rebirth.

---

### 8. Taunt Readyness

**Purpose:** Track AOE Taunt cooldowns for Druids (Challenging Roar, 10-min CD) and Warriors (Challenging Shout, 10-min CD).

**Tracked Abilities:**

| Ability | Class | Cooldown |
|---------|-------|----------|
| Challenging Shout | Warrior | 600s (10 min) |
| Challenging Roar | Druid | 600s (10 min) |

**Data Source:** Combat log parsing, same pattern as Rebirth/Tranquility.

**Combat Log Patterns:**

```lua
-- Warriors: "Tankmedady's Challenging Shout"
-- Druids:   "Feralboi's Challenging Roar"
for name in string.gfind(msg, "(.+)'s Challenging Shout") do
  RD.RecordTauntCast(name, "warrior")
  break
end
for name in string.gfind(msg, "(.+)'s Challenging Roar") do
  RD.RecordTauntCast(name, "druid")
  break
end
```

**Roster:** Tracks all Warriors and Druids with Tank role (`OGRH_GetPlayerRole(name) == "T"`).

**Click Behavior:** Same pattern as Rebirth — poll out of combat, announce in combat.

**Status Thresholds:** Same as Rebirth.

---

## Status Evaluation

### Unified Status Function

```lua
-- Evaluates a scan result and assigns a traffic-light status
function RD.EvaluateStatus(scanResult)
  if not scanResult or not scanResult.total or scanResult.total == 0 then
    scanResult.status = "green"
    return scanResult
  end

  local percent = (scanResult.ready / scanResult.total) * 100

  if percent >= 100 then
    scanResult.status = "green"
  elseif percent >= 80 then
    scanResult.status = "yellow"
  else
    scanResult.status = "red"
  end

  return scanResult
end
```

**Per-indicator threshold overrides** can be configured in SVM settings. The 80% default matches the existing consume tracking convention. Individual indicators may define custom thresholds as documented in their respective sections above.

---

## UI Design

### Panel Layout

The Readyness Dashboard is an OGST docked panel that attaches to the main OGRH frame. It can be undocked to float independently.

**Docked Mode (Default):**

```
┌─ OGRH Main Frame ──────────────────────┐
│ [RH] [Rdy] [Admin] [Roles]      [Lock] │
│ [M] [A] [<] Encounter Name [>]         │
└─────────────────────────────────────────┘
┌─ Readyness Dashboard ──────────────────────────────────────────────┐
│ ● Buffs 2/40   ● CCon 4/40   ● ECon 3/40   H:92% D:85%          │
│ T:100% R:95%   ● Reb 3/5    ● Tranq 4/5   ● Taunt 2/4     [⇱/⇲] │
└────────────────────────────────────────────────────────────────────┘
```

**Undocked Mode:**

The panel floats freely, movable by dragging. Retains all functionality but is not anchored to the main frame.

**Indicator Layout Detail:**

Each indicator is a horizontal row element containing:

```
┌──────────────────────────────┐
│ ● IndicatorName  X/Y        │
└──────────────────────────────┘
  │          │          │
  │          │          └─ Deficit count (ready/total)
  │          └─ Label text
  └─ Color dot (8x8 texture, colored R/Y/G)
```

**Mana Indicator (special layout):**

```
┌───────────────────────────────────┐
│ H: ██████████ 92%   D: ████████░ 85% │
└───────────────────────────────────┘
```

Uses two compact `OGST.CreateProgressBar` instances side by side with bar color matching the traffic-light system.

**Health Indicator (special layout):**

```
┌───────────────────────────────────┐
│ T: ██████████ 100%  R: ████████░ 95% │
└───────────────────────────────────┘
```

Uses two compact `OGST.CreateProgressBar` instances side by side, identical in structure to the Mana indicator. Bar color uses the traffic-light system based on aggregate health percentage.

### Panel Frame Structure

```lua
function RD.CreateDashboardPanel()
  local panel = CreateFrame("Frame", "OGRH_ReadynessDashboard", UIParent)
  panel:SetWidth(340)
  panel:SetHeight(52)
  panel:SetFrameStrata("HIGH")

  -- Register as docked panel
  OGST.RegisterDockedPanel(panel, {
    parentFrame = OGRH_Main,
    axis = "vertical",
    preferredSide = "bottom",
    priority = 10,        -- High priority = close to parent
    autoMove = true,
    hideInCombat = false,  -- Dashboard should stay visible in combat
    title = "Readyness"
  })

  -- Row 1: Buffs, ClassConsume, EncConsume, Mana
  local row1 = CreateFrame("Frame", nil, panel)
  row1:SetWidth(330)
  row1:SetHeight(20)
  row1:SetPoint("TOPLEFT", panel, "TOPLEFT", 5, -5)

  panel.buffIndicator = RD.CreateIndicator(row1, "Buffs", "buff")
  panel.classConsumeIndicator = RD.CreateIndicator(row1, "CCon", "classConsume")
  panel.encConsumeIndicator = RD.CreateIndicator(row1, "ECon", "encConsume")
  panel.manaIndicator = RD.CreateManaIndicator(row1)

  -- Row 2: Health, Rebirth, Tranquility, Taunt, Dock/Undock
  local row2 = CreateFrame("Frame", nil, panel)
  row2:SetWidth(330)
  row2:SetHeight(20)
  row2:SetPoint("TOPLEFT", row1, "BOTTOMLEFT", 0, -2)

  panel.healthIndicator = RD.CreateHealthIndicator(row2)
  panel.rebirthIndicator = RD.CreateIndicator(row2, "Reb", "rebirth")
  panel.tranqIndicator = RD.CreateIndicator(row2, "Tranq", "tranquility")
  panel.tauntIndicator = RD.CreateIndicator(row2, "Taunt", "taunt")

  -- Dock/Undock toggle button
  local dockBtn = CreateFrame("Button", nil, row2)
  dockBtn:SetWidth(16)
  dockBtn:SetHeight(16)
  dockBtn:SetPoint("RIGHT", row2, "RIGHT", -2, 0)
  dockBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-CollapseButton-Up")
  dockBtn:SetScript("OnClick", function()
    RD.ToggleDock()
  end)
  panel.dockBtn = dockBtn

  panel.indicators = {
    panel.buffIndicator,
    panel.classConsumeIndicator,
    panel.encConsumeIndicator,
    panel.rebirthIndicator,
    panel.tranqIndicator,
    panel.tauntIndicator
  }

  return panel
end
```

### Indicator Widget

```lua
function RD.CreateIndicator(parent, label, indicatorType)
  local frame = CreateFrame("Button", nil, parent)
  frame:SetWidth(80)
  frame:SetHeight(16)
  frame.indicatorType = indicatorType

  -- Color dot
  local dot = frame:CreateTexture(nil, "OVERLAY")
  dot:SetWidth(8)
  dot:SetHeight(8)
  dot:SetTexture("Interface\\BUTTONS\\WHITE8X8")
  dot:SetPoint("LEFT", frame, "LEFT", 2, 0)
  frame.dot = dot

  -- Label + count text
  local text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  text:SetPoint("LEFT", dot, "RIGHT", 4, 0)
  text:SetText(label .. " 0/0")
  text:SetJustifyH("LEFT")
  frame.text = text

  -- Click handlers
  frame:SetScript("OnClick", function()
    if arg1 == "LeftButton" then
      RD.OnIndicatorClick(indicatorType)
    elseif arg1 == "RightButton" then
      RD.OnIndicatorRightClick(indicatorType)
    end
  end)
  frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")

  -- Tooltip on hover
  frame:SetScript("OnEnter", function()
    RD.ShowIndicatorTooltip(frame, indicatorType)
  end)
  frame:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)

  return frame
end
```

### Color Update

```lua
local STATUS_COLORS = {
  green  = { r = 0.0, g = 1.0, b = 0.0 },
  yellow = { r = 1.0, g = 0.9, b = 0.0 },
  red    = { r = 1.0, g = 0.0, b = 0.0 },
  gray   = { r = 0.5, g = 0.5, b = 0.5 }  -- disabled/no data
}

function RD.UpdateIndicatorDisplay(indicator, scanResult)
  local color = STATUS_COLORS[scanResult.status] or STATUS_COLORS.gray
  indicator.dot:SetVertexColor(color.r, color.g, color.b)

  local deficit = scanResult.total - scanResult.ready
  local label = indicator.indicatorType
  if deficit > 0 then
    indicator.text:SetText(string.format("%s %d/%d",
      RD.GetShortLabel(label), deficit, scanResult.total))
    -- Deficit count: show as "missing/total"
  else
    indicator.text:SetText(RD.GetShortLabel(label) .. " OK")
  end
end
```

### Mana Indicator (Special)

```lua
function RD.CreateManaIndicator(parent)
  local frame = CreateFrame("Button", nil, parent)
  frame:SetWidth(120)
  frame:SetHeight(16)
  frame.indicatorType = "mana"

  -- Healer mana mini-bar
  local healerLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  healerLabel:SetPoint("LEFT", frame, "LEFT", 2, 0)
  healerLabel:SetText("H:")
  frame.healerLabel = healerLabel

  local healerBar = OGST.CreateProgressBar(frame, {
    width = 40, height = 10, barColor = {0, 0.7, 1}, showText = false
  })
  healerBar:SetPoint("LEFT", healerLabel, "RIGHT", 2, 0)
  frame.healerBar = healerBar

  local healerPct = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  healerPct:SetPoint("LEFT", healerBar, "RIGHT", 2, 0)
  healerPct:SetText("0%")
  frame.healerPct = healerPct

  -- DPS mana mini-bar
  local dpsLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  dpsLabel:SetPoint("LEFT", healerPct, "RIGHT", 6, 0)
  dpsLabel:SetText("D:")
  frame.dpsLabel = dpsLabel

  local dpsBar = OGST.CreateProgressBar(frame, {
    width = 40, height = 10, barColor = {0, 0.7, 1}, showText = false
  })
  dpsBar:SetPoint("LEFT", dpsLabel, "RIGHT", 2, 0)
  frame.dpsBar = dpsBar

  local dpsPct = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  dpsPct:SetPoint("LEFT", dpsBar, "RIGHT", 2, 0)
  dpsPct:SetText("0%")
  frame.dpsPct = dpsPct

  -- Click handler
  frame:SetScript("OnClick", function()
    RD.OnIndicatorClick("mana")
  end)
  frame:RegisterForClicks("LeftButtonUp")

  return frame
end

function RD.UpdateManaDisplay(manaIndicator, manaStatus)
  -- Healer bar
  local hPct = manaStatus.healerMana.percent
  manaIndicator.healerBar:SetValue(hPct)
  manaIndicator.healerPct:SetText(hPct .. "%")
  local hColor = RD.GetManaColor(hPct)
  manaIndicator.healerBar:SetBarColor(hColor.r, hColor.g, hColor.b)

  -- DPS bar
  local dPct = manaStatus.dpsMana.percent
  manaIndicator.dpsBar:SetValue(dPct)
  manaIndicator.dpsPct:SetText(dPct .. "%")
  local dColor = RD.GetManaColor(dPct)
  manaIndicator.dpsBar:SetBarColor(dColor.r, dColor.g, dColor.b)
end

function RD.GetManaColor(percent)
  if percent >= 90 then
    return { r = 0, g = 1, b = 0 }
  elseif percent >= 70 then
    return { r = 1, g = 0.9, b = 0 }
  else
    return { r = 1, g = 0, b = 0 }
  end
end
```

### Health Indicator (Special)

```lua
function RD.CreateHealthIndicator(parent)
  local frame = CreateFrame("Button", nil, parent)
  frame:SetWidth(120)
  frame:SetHeight(16)
  frame.indicatorType = "health"

  -- Tank health mini-bar
  local tankLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  tankLabel:SetPoint("LEFT", frame, "LEFT", 2, 0)
  tankLabel:SetText("T:")
  frame.tankLabel = tankLabel

  local tankBar = OGST.CreateProgressBar(frame, {
    width = 40, height = 10, barColor = {0, 0.8, 0}, showText = false
  })
  tankBar:SetPoint("LEFT", tankLabel, "RIGHT", 2, 0)
  frame.tankBar = tankBar

  local tankPct = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  tankPct:SetPoint("LEFT", tankBar, "RIGHT", 2, 0)
  tankPct:SetText("0%")
  frame.tankPct = tankPct

  -- Raid health mini-bar
  local raidLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  raidLabel:SetPoint("LEFT", tankPct, "RIGHT", 6, 0)
  raidLabel:SetText("R:")
  frame.raidLabel = raidLabel

  local raidBar = OGST.CreateProgressBar(frame, {
    width = 40, height = 10, barColor = {0, 0.8, 0}, showText = false
  })
  raidBar:SetPoint("LEFT", raidLabel, "RIGHT", 2, 0)
  frame.raidBar = raidBar

  local raidPct = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  raidPct:SetPoint("LEFT", raidBar, "RIGHT", 2, 0)
  raidPct:SetText("0%")
  frame.raidPct = raidPct

  -- Click handler
  frame:SetScript("OnClick", function()
    RD.OnIndicatorClick("health")
  end)
  frame:RegisterForClicks("LeftButtonUp")

  return frame
end

function RD.UpdateHealthDisplay(healthIndicator, healthStatus)
  -- Tank bar
  local tPct = healthStatus.tankHealth.percent
  healthIndicator.tankBar:SetValue(tPct)
  healthIndicator.tankPct:SetText(tPct .. "%")
  local tColor = RD.GetHealthColor(tPct)
  healthIndicator.tankBar:SetBarColor(tColor.r, tColor.g, tColor.b)

  -- Raid bar
  local rPct = healthStatus.raidHealth.percent
  healthIndicator.raidBar:SetValue(rPct)
  healthIndicator.raidPct:SetText(rPct .. "%")
  local rColor = RD.GetHealthColor(rPct)
  healthIndicator.raidBar:SetBarColor(rColor.r, rColor.g, rColor.b)
end

function RD.GetHealthColor(percent)
  if percent >= 90 then
    return { r = 0, g = 1, b = 0 }
  elseif percent >= 70 then
    return { r = 1, g = 0.9, b = 0 }
  else
    return { r = 1, g = 0, b = 0 }
  end
end
```

### Tooltip Detail

Right-click or hover on any indicator shows a GameTooltip with detailed breakdown:

```lua
function RD.ShowIndicatorTooltip(frame, indicatorType)
  GameTooltip:SetOwner(frame, "ANCHOR_RIGHT")
  GameTooltip:ClearLines()

  local state = RD.State[indicatorType]
  if not state then
    GameTooltip:AddLine("No data")
    GameTooltip:Show()
    return
  end

  if indicatorType == "buff" then
    GameTooltip:AddLine("Buff Readyness", 1, 1, 1)
    GameTooltip:AddDoubleLine("Status:", state.status, 1, 0.82, 0, 1, 1, 1)
    GameTooltip:AddDoubleLine("Ready:", state.ready .. "/" .. state.total, 1, 0.82, 0, 1, 1, 1)
    if state.byBuff then
      for buffName, buffData in pairs(state.byBuff) do
        local missingCount = table.getn(buffData.missing)
        if missingCount > 0 then
          GameTooltip:AddDoubleLine(
            buffName .. ":", missingCount .. " missing",
            1, 0.5, 0, 1, 0.5, 0
          )
        end
      end
    end

  elseif indicatorType == "rebirth" or indicatorType == "tranquility" or indicatorType == "taunt" then
    local label = indicatorType == "rebirth" and "Rebirth"
      or indicatorType == "tranquility" and "Tranquility"
      or "AOE Taunt"
    GameTooltip:AddLine(label .. " Readyness", 1, 1, 1)
    GameTooltip:AddDoubleLine("Available:", state.ready .. "/" .. state.total, 1, 0.82, 0, 1, 1, 1)
    if state.onCooldown then
      for _, entry in ipairs(state.onCooldown) do
        GameTooltip:AddDoubleLine(
          entry.name, entry.remainingText .. " remaining",
          1, 0.5, 0, 0.8, 0.8, 0.8
        )
      end
    end
    if state.available then
      for _, name in ipairs(state.available) do
        GameTooltip:AddDoubleLine(name, "Ready", 0, 1, 0, 0, 1, 0)
      end
    end

  elseif indicatorType == "mana" then
    GameTooltip:AddLine("Mana Readyness", 1, 1, 1)
    GameTooltip:AddDoubleLine("Healers:", state.healerMana.percent .. "%", 1, 0.82, 0, 1, 1, 1)
    GameTooltip:AddDoubleLine("DPS:", state.dpsMana.percent .. "%", 1, 0.82, 0, 1, 1, 1)
    -- Show players below threshold
    local below = state.healerMana.belowThreshold
    if below and table.getn(below) > 0 then
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine("Low Mana Healers:", 1, 0.5, 0)
      for _, entry in ipairs(below) do
        GameTooltip:AddDoubleLine(entry.name, entry.percent .. "%", 1, 1, 1, 1, 0.5, 0)
      end
    end

  elseif indicatorType == "health" then
    GameTooltip:AddLine("Health Readyness", 1, 1, 1)
    GameTooltip:AddDoubleLine("Tanks:", state.tankHealth.percent .. "%", 1, 0.82, 0, 1, 1, 1)
    GameTooltip:AddDoubleLine("Raid:", state.raidHealth.percent .. "%", 1, 0.82, 0, 1, 1, 1)
    -- Show players below threshold
    local belowTanks = state.tankHealth.belowThreshold
    if belowTanks and table.getn(belowTanks) > 0 then
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine("Low Health Tanks:", 1, 0.5, 0)
      for _, entry in ipairs(belowTanks) do
        GameTooltip:AddDoubleLine(entry.name, entry.percent .. "%", 1, 1, 1, 1, 0.5, 0)
      end
    end
    local belowRaid = state.raidHealth.belowThreshold
    if belowRaid and table.getn(belowRaid) > 0 then
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine("Low Health Raid:", 1, 0.5, 0)
      for _, entry in ipairs(belowRaid) do
        GameTooltip:AddDoubleLine(entry.name, entry.percent .. "%", 1, 1, 1, 1, 0.5, 0)
      end
    end
  end

  GameTooltip:AddLine(" ")
  GameTooltip:AddLine("Left-Click: Announce to raid", 0.5, 0.5, 0.5)
  GameTooltip:AddLine("Right-Click: Detailed view", 0.5, 0.5, 0.5)
  GameTooltip:Show()
end
```

---

## Dock / Undock System

### Dock Toggle

```lua
RD.isDocked = true  -- Default state

function RD.ToggleDock()
  if RD.isDocked then
    RD.Undock()
  else
    RD.Dock()
  end
  -- Persist preference
  OGRH.SVM.SetPath("readynessDashboard.isDocked", RD.isDocked)
end

function RD.Dock()
  local panel = OGRH_ReadynessDashboard
  if not panel then return end

  -- Re-register as docked panel
  OGST.RegisterDockedPanel(panel, {
    parentFrame = OGRH_Main,
    axis = "vertical",
    preferredSide = "bottom",
    priority = 10,
    autoMove = true,
    hideInCombat = false
  })

  panel:EnableMouse(false)   -- Disable dragging
  panel:SetMovable(false)
  RD.isDocked = true
end

function RD.Undock()
  local panel = OGRH_ReadynessDashboard
  if not panel then return end

  -- Unregister from docked panel system
  OGST.UnregisterDockedPanel(panel)

  -- Make freely movable
  panel:SetMovable(true)
  panel:EnableMouse(true)
  panel:RegisterForDrag("LeftButton")
  panel:SetScript("OnDragStart", function() this:StartMoving() end)
  panel:SetScript("OnDragStop", function()
    this:StopMovingOrSizing()
    -- Save position
    local point, _, relPoint, x, y = this:GetPoint()
    OGRH.SVM.SetPath("readynessDashboard.position", {
      point = point, relPoint = relPoint, x = x, y = y
    })
  end)

  -- Restore saved position if available
  local pos = OGRH.SVM.GetPath("readynessDashboard.position")
  if pos then
    panel:ClearAllPoints()
    panel:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
  end

  RD.isDocked = false
end
```

---

## Announcement System

### Click-to-Announce

```lua
function RD.OnIndicatorClick(indicatorType)
  local state = RD.State[indicatorType]
  if not state then return end

  local lines = {}

  if indicatorType == "buff" then
    lines = RD.BuildBuffAnnouncement(state)
  elseif indicatorType == "classConsume" then
    lines = RD.BuildClassConsumeAnnouncement(state)
  elseif indicatorType == "encConsume" then
    lines = RD.BuildEncConsumeAnnouncement(state)
  elseif indicatorType == "mana" then
    lines = RD.BuildManaAnnouncement(state)
  elseif indicatorType == "health" then
    lines = RD.BuildHealthAnnouncement(state)
  elseif indicatorType == "rebirth" then
    lines = RD.BuildCooldownAnnouncement(state, "Rebirth", "Druids")
  elseif indicatorType == "tranquility" then
    lines = RD.BuildCooldownAnnouncement(state, "Tranquility", "Druids")
  elseif indicatorType == "taunt" then
    lines = RD.BuildCooldownAnnouncement(state, "AOE Taunt", "Tanks")
  end

  if table.getn(lines) > 0 then
    OGRH.SendAnnouncement(lines)
  end
end
```

### Buff Announcement Builder

```lua
function RD.BuildBuffAnnouncement(state)
  local lines = {}

  if state.status == "green" then
    table.insert(lines, "[RH] All buffs applied!")
    return lines
  end

  -- Sort missing buffs by count (most missing first)
  local buffCounts = {}
  for buffName, buffData in pairs(state.byBuff or {}) do
    local count = table.getn(buffData.missing)
    if count > 0 then
      table.insert(buffCounts, {name = buffName, count = count, missing = buffData.missing})
    end
  end
  table.sort(buffCounts, function(a, b) return a.count > b.count end)

  -- Build announcement (top 3 most-missing buffs)
  local parts = {}
  for i = 1, math.min(3, table.getn(buffCounts)) do
    local bc = buffCounts[i]
    -- List up to 5 player names
    local names = {}
    for j = 1, math.min(5, table.getn(bc.missing)) do
      table.insert(names, bc.missing[j])
    end
    local nameStr = table.concat(names, ", ")
    if table.getn(bc.missing) > 5 then
      nameStr = nameStr .. " (+" .. (table.getn(bc.missing) - 5) .. " more)"
    end
    table.insert(parts, bc.name .. " (" .. bc.count .. "): " .. nameStr)
  end

  table.insert(lines, "[RH] Missing Buffs:")
  for _, part in ipairs(parts) do
    table.insert(lines, "  " .. part)
  end

  return lines
end
```

### Cooldown Announcement Builder

```lua
function RD.BuildCooldownAnnouncement(state, abilityName, groupLabel)
  local lines = {}
  local inCombat = UnitAffectingCombat("player")

  if inCombat then
    -- In combat: announce who has it available
    local available = state.available or {}
    if table.getn(available) > 0 then
      table.insert(lines, "[RH] " .. abilityName .. " available: "
        .. table.concat(available, ", ")
        .. " (" .. state.ready .. "/" .. state.total .. ")")
    else
      table.insert(lines, "[RH] " .. abilityName .. ": ALL ON COOLDOWN (0/" .. state.total .. ")")
    end
  else
    -- Out of combat: poll
    table.insert(lines, "[RH] " .. groupLabel .. ": + in /raid if your " .. abilityName .. " is ready")
    RD.StartCooldownPoll(string.lower(abilityName))
  end

  return lines
end
```

### Poll Listener

```lua
function RD.StartCooldownPoll(abilityKey)
  RD.activePoll = {
    ability = abilityKey,
    startTime = GetTime(),
    duration = 15,          -- Listen for 15 seconds
    responses = {}
  }
end

function RD.OnRaidChatMessage(msg, sender)
  if not RD.activePoll then return end
  if GetTime() - RD.activePoll.startTime > RD.activePoll.duration then
    RD.activePoll = nil
    return
  end

  -- Check for "+" response
  local trimmed = string.gsub(msg, "^%s+", "")
  trimmed = string.gsub(trimmed, "%s+$", "")
  if trimmed == "+" then
    RD.activePoll.responses[sender] = true

    -- Update the corresponding tracker
    local ability = RD.activePoll.ability
    if ability == "rebirth" and RD.CooldownTrackers.rebirth.druids[sender] then
      RD.CooldownTrackers.rebirth.druids[sender].reportedReady = true
      RD.CooldownTrackers.rebirth.druids[sender].lastCast = nil
    elseif ability == "tranquility" and RD.CooldownTrackers.tranquility.druids[sender] then
      RD.CooldownTrackers.tranquility.druids[sender].reportedReady = true
      RD.CooldownTrackers.tranquility.druids[sender].lastCast = nil
    elseif ability == "aoe taunt" then
      local tracker = RD.CooldownTrackers.taunt.players[sender]
      if tracker then
        tracker.reportedReady = true
        tracker.lastCast = nil
      end
    end

    RD.RefreshDashboard()
  end
end
```

---

## Scanning Engine

### Periodic Scan

```lua
RD.ScanInterval = 5       -- seconds between full scans
RD.LastScanTime = 0
RD.ScanFrame = nil

function RD.StartScanning()
  if RD.ScanFrame then return end

  RD.ScanFrame = CreateFrame("Frame")
  RD.ScanFrame:SetScript("OnUpdate", function()
    local now = GetTime()
    if now - RD.LastScanTime >= RD.ScanInterval then
      RD.LastScanTime = now
      RD.RunFullScan()
    end
  end)
end

function RD.StopScanning()
  if RD.ScanFrame then
    RD.ScanFrame:SetScript("OnUpdate", nil)
    RD.ScanFrame = nil
  end
end

function RD.RunFullScan()
  -- Only scan when in a raid
  if GetNumRaidMembers() == 0 then return end

  -- Update cooldown rosters
  RD.BuildDruidRoster()
  RD.BuildTauntRoster()

  -- Run all scans
  RD.State.buff = RD.ScanBuffReadyness()
  RD.State.classConsume = RD.ScanClassConsumes()
  RD.State.encConsume = RD.ScanEncounterConsumes()
  RD.State.mana = RD.ScanManaReadyness()
  RD.State.health = RD.ScanHealthReadyness()
  RD.State.rebirth = RD.GetRebirthReadyness()
  RD.State.tranquility = RD.GetTranquilityReadyness()
  RD.State.taunt = RD.GetTauntReadyness()

  -- Update UI
  RD.RefreshDashboard()
end

function RD.RefreshDashboard()
  local panel = OGRH_ReadynessDashboard
  if not panel or not panel:IsShown() then return end

  RD.UpdateIndicatorDisplay(panel.buffIndicator, RD.State.buff or {status="gray"})
  RD.UpdateIndicatorDisplay(panel.classConsumeIndicator, RD.State.classConsume or {status="gray"})

  -- Hide encounter consume indicator if no consume role
  if RD.State.encConsume and RD.State.encConsume.noRole then
    panel.encConsumeIndicator:Hide()
  else
    panel.encConsumeIndicator:Show()
    RD.UpdateIndicatorDisplay(panel.encConsumeIndicator, RD.State.encConsume or {status="gray"})
  end

  RD.UpdateManaDisplay(panel.manaIndicator, RD.State.mana or {
    healerMana = {percent = 0}, dpsMana = {percent = 0}
  })
  RD.UpdateHealthDisplay(panel.healthIndicator, RD.State.health or {
    tankHealth = {percent = 0}, raidHealth = {percent = 0}
  })
  RD.UpdateIndicatorDisplay(panel.rebirthIndicator, RD.State.rebirth or {status="gray"})
  RD.UpdateIndicatorDisplay(panel.tranqIndicator, RD.State.tranquility or {status="gray"})
  RD.UpdateIndicatorDisplay(panel.tauntIndicator, RD.State.taunt or {status="gray"})
end
```

### Encounter Change Handler

When the user navigates to a different encounter, the dashboard must re-scan immediately since consume requirements may have changed:

```lua
-- Hook into encounter navigation
local originalNav = OGRH.NavigateToNextEncounter
OGRH.NavigateToNextEncounter = function()
  originalNav()
  RD.RunFullScan()
end

local originalNavPrev = OGRH.NavigateToPreviousEncounter
OGRH.NavigateToPreviousEncounter = function()
  originalNavPrev()
  RD.RunFullScan()
end
```

---

## SVM Schema

### Data Paths

```lua
-- readynessDashboard settings stored in SVM
readynessDashboard = {
  enabled = true,                -- Master toggle
  isDocked = true,               -- Docked vs floating
  position = {                   -- Undocked position (only when floating)
    point = "CENTER",
    relPoint = "CENTER",
    x = 0,
    y = 0
  },
  scanInterval = 5,              -- Seconds between scans
  manaThreshold = 80,            -- % below which mana is "low"
  healthThreshold = 80,          -- % below which health is "low"
  thresholds = {                 -- Per-indicator threshold overrides
    buff = 80,                   -- % for yellow/red boundary
    classConsume = 75,
    encConsume = 80,
    mana = {
      green = 90,
      yellow = 70
    },
    health = {
      green = 90,
      yellow = 70
    },
    cooldown = 50                -- % for rebirth/tranq/taunt
  },
  announceChannel = "auto",      -- "auto" (RW if can, else RAID), "RAID", "RAID_WARNING"
  showInRaidOnly = true,         -- Hide when not in a raid group
  buffCategories = {             -- Which buffs to track (toggleable)
    fortitude = true,
    spirit = true,
    shadowprot = true,
    motw = true,
    int = true,
    paladin = true
  }
}
```

### SVM Path

```
readynessDashboard.enabled
readynessDashboard.isDocked
readynessDashboard.position
readynessDashboard.scanInterval
readynessDashboard.manaThreshold
readynessDashboard.healthThreshold
readynessDashboard.thresholds.buff
readynessDashboard.thresholds.classConsume
readynessDashboard.thresholds.encConsume
readynessDashboard.thresholds.mana.green
readynessDashboard.thresholds.mana.yellow
readynessDashboard.thresholds.health.green
readynessDashboard.thresholds.health.yellow
readynessDashboard.thresholds.cooldown
readynessDashboard.announceChannel
readynessDashboard.showInRaidOnly
readynessDashboard.buffCategories.*
```

---

## Event Registration

```lua
function RD.RegisterEvents()
  local eventFrame = CreateFrame("Frame")

  -- Combat log events for cooldown tracking
  eventFrame:RegisterEvent("CHAT_MSG_SPELL_SELF_BUFF")
  eventFrame:RegisterEvent("CHAT_MSG_SPELL_PARTY_BUFF")
  eventFrame:RegisterEvent("CHAT_MSG_SPELL_FRIENDLYPLAYER_BUFF")
  eventFrame:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_FRIENDLYPLAYER_BUFFS")
  eventFrame:RegisterEvent("CHAT_MSG_SPELL_HOSTILEPLAYER_BUFF")

  -- Combat state changes
  eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")  -- Entering combat
  eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")   -- Leaving combat

  -- Raid roster changes
  eventFrame:RegisterEvent("RAID_ROSTER_UPDATE")

  -- Chat messages for polling
  eventFrame:RegisterEvent("CHAT_MSG_RAID")
  eventFrame:RegisterEvent("CHAT_MSG_RAID_LEADER")

  eventFrame:SetScript("OnEvent", function()
    if event == "RAID_ROSTER_UPDATE" then
      RD.BuildDruidRoster()
      RD.BuildTauntRoster()
      RD.RunFullScan()

    elseif event == "PLAYER_REGEN_DISABLED" then
      RD.InCombat = true
      -- Increase scan frequency during combat
      RD.ScanInterval = 3

    elseif event == "PLAYER_REGEN_ENABLED" then
      RD.InCombat = false
      RD.ScanInterval = OGRH.SVM.GetPath("readynessDashboard.scanInterval") or 5

    elseif event == "CHAT_MSG_RAID" or event == "CHAT_MSG_RAID_LEADER" then
      RD.OnRaidChatMessage(arg1, arg2)

    elseif string.find(event, "CHAT_MSG_SPELL") then
      RD.OnCombatLogEvent()
    end
  end)

  RD.EventFrame = eventFrame
end
```

---

## Slash Commands

```
/ogrh ready          -- Toggle Readyness Dashboard visibility
/ogrh ready dock     -- Dock the panel to the main frame
/ogrh ready undock   -- Undock and float the panel
/ogrh ready scan     -- Force an immediate full scan
/ogrh ready reset    -- Reset position and dock state
```

---

## API Reference

### Core Functions

| Function | Description | Returns |
|----------|-------------|---------|
| `RD.Initialize()` | Set up the dashboard, register events, create UI | `nil` |
| `RD.StartScanning()` | Begin periodic scanning | `nil` |
| `RD.StopScanning()` | Stop periodic scanning | `nil` |
| `RD.RunFullScan()` | Execute all scans immediately | `nil` |
| `RD.RefreshDashboard()` | Update all indicator visuals | `nil` |
| `RD.ToggleDock()` | Toggle between docked/floating | `nil` |
| `RD.Dock()` | Dock panel to main frame | `nil` |
| `RD.Undock()` | Float panel freely | `nil` |

### Scan Functions

| Function | Description | Returns |
|----------|-------------|---------|
| `RD.ScanBuffReadyness()` | Scan raid buff coverage | `{status, ready, total, missing, byBuff}` |
| `RD.ScanClassConsumes()` | Evaluate consume scores | `{status, ready, total, missing, averageScore}` |
| `RD.ScanEncounterConsumes()` | Check encounter consume role items | `{status, ready, total, missing, consumeItems}` |
| `RD.ScanManaReadyness()` | Check healer + DPS mana levels | `{healerMana, dpsMana}` |
| `RD.ScanHealthReadyness()` | Check tank + raid health levels | `{tankHealth, raidHealth}` |
| `RD.GetRebirthReadyness()` | Check druid Rebirth cooldowns | `{status, ready, total, onCooldown, available}` |
| `RD.GetTranquilityReadyness()` | Check druid Tranquility cooldowns | `{status, ready, total, onCooldown, available}` |
| `RD.GetTauntReadyness()` | Check AOE Taunt cooldowns | `{status, ready, total, onCooldown, available}` |

### UI Functions

| Function | Description | Returns |
|----------|-------------|---------|
| `RD.CreateDashboardPanel()` | Build the OGST panel | Frame |
| `RD.CreateIndicator(parent, label, type)` | Create a single indicator widget | Frame |
| `RD.CreateManaIndicator(parent)` | Create the special mana indicator | Frame |
| `RD.CreateHealthIndicator(parent)` | Create the special health indicator | Frame |
| `RD.UpdateIndicatorDisplay(indicator, result)` | Update indicator color and text | `nil` |
| `RD.UpdateManaDisplay(indicator, manaStatus)` | Update mana bars | `nil` |
| `RD.UpdateHealthDisplay(indicator, healthStatus)` | Update health bars | `nil` |
| `RD.ShowIndicatorTooltip(frame, type)` | Show detailed tooltip | `nil` |

### Announcement Functions

| Function | Description | Returns |
|----------|-------------|---------|
| `RD.OnIndicatorClick(type)` | Handle left-click announcement | `nil` |
| `RD.BuildBuffAnnouncement(state)` | Build buff deficit message | `lines` table |
| `RD.BuildClassConsumeAnnouncement(state)` | Build consume score message | `lines` table |
| `RD.BuildEncConsumeAnnouncement(state)` | Build encounter consume message | `lines` table |
| `RD.BuildManaAnnouncement(state)` | Build mana status message | `lines` table |
| `RD.BuildHealthAnnouncement(state)` | Build health status message | `lines` table |
| `RD.BuildCooldownAnnouncement(state, name, group)` | Build cooldown poll/report | `lines` table |

### Utility Functions

| Function | Description | Returns |
|----------|-------------|---------|
| `RD.ClassifyBuff(buffName)` | Categorize a buff name | category string or `nil` |
| `RD.EvaluateStatus(scanResult)` | Assign traffic-light status | modified scanResult |
| `RD.FormatTime(seconds)` | Format seconds to "Xm Ys" | string |
| `RD.GetConsumeThreshold()` | Get encounter/raid ready threshold | number |
| `RD.GetManaThreshold()` | Get mana low threshold | number |
| `RD.GetHealthThreshold()` | Get health low threshold | number |
| `RD.PlayerHasConsumeBuff(unitId, data)` | Check if unit has consume buff | boolean |
| `RD.BuildRaidData()` | Build RABuffs raid data table | table |

---

## Interaction with Existing Systems

### Encounter Navigation

The dashboard listens for encounter changes (via hooks on `NavigateToNextEncounter` / `NavigateToPreviousEncounter`) and re-scans immediately. The Encounter Consume indicator dynamically shows/hides based on whether the current encounter has an `isConsumeCheck` role.

### ConsumesTracking Module

The dashboard reuses `CT.CalculatePlayerScore()` directly — it does not duplicate scoring logic. It also reuses `CT.IsRABuffsAvailable()` and `CT.CheckForOGRHProfile()` for availability checks.

### BuffManager

The Buff Readyness indicator reads assignments from BuffManager encounters to determine which player is responsible for which buff on which groups. This enables targeted announcements that include the assignee (e.g., "Priestbro should be casting Fortitude on Groups 1-3"). When no BuffManager assignments exist for the current encounter, the dashboard falls back to reporting deficits without assignee attribution.

### Announce System

Uses `OGRH.SendAnnouncement(lines)` for raid-wide messages. Respects `OGRH.CanRW()` for RAID_WARNING vs RAID channel selection. Does not use ChatThrottleLib (consistent with existing announce pattern).

### MainUI Integration

The dashboard panel docks below the OGRH main frame via `OGST.RegisterDockedPanel`. The dock/undock toggle is a small button in the bottom-right corner of the panel.

---

## Lua 5.0 Compatibility Notes

- Use `table.getn()` instead of `#` operator
- Use `string.gfind()` instead of `string.gmatch()`
- Use `floor()` (global) instead of `math.floor()`
- No `continue` statement — use nested `if` blocks
- Event handlers use implicit `this`, `event`, `arg1`–`arg9` globals
- `table.concat()` is available in Lua 5.0
- `pairs()` and `ipairs()` available
- No string interpolation — use `string.format()` or concatenation

---

## Testing Strategy

### Unit Tests

| Test | Description |
|------|-------------|
| ClassifyBuff | Verify all buff name patterns map to correct categories |
| EvaluateStatus | Green/Yellow/Red thresholds at boundary values |
| PlayerHasConsumeBuff | Mock `UnitBuff` with known spellIds, verify detection |
| FormatTime | Edge cases: 0s, 60s, 600s, 1800s |
| GetConsumeThreshold | Falls back from encounter → raid → default (80) |
| GetHealthThreshold | Falls back from encounter → raid → default (80) |

### Integration Tests

| Test | Description |
|------|-------------|
| Full Scan Cycle | Mock 40-player raid, run `RunFullScan()`, verify all states populated |
| Encounter Change | Navigate encounter, verify encConsume indicator updates |
| Cooldown Tracking | Simulate combat log messages, verify cooldown timers start |
| Poll System | Simulate "+" chat messages, verify tracker updates |
| Dock/Undock | Toggle dock state, verify OGST registration/unregistration |

### Manual Testing

1. **Join a raid** — Dashboard should auto-show (if enabled) and begin scanning
2. **Check buff indicators** — Verify green when fully buffed, yellow/red with missing buffs
3. **Navigate encounters** — ECon indicator should appear/disappear based on consume roles
4. **Click indicators** — Verify announcements appear correctly in raid chat
5. **Undock dashboard** — Verify it floats and saves position on `/reload`
6. **Enter combat** — Verify scan interval increases, cooldown click behavior changes
7. **Check health indicators** — Verify tank vs. raid health bars update correctly, color thresholds match
8. **Druid casts Rebirth** — Verify Rebirth indicator changes from green to yellow/red

---

## Implementation Phases

### Phase 1: Core Framework
- [x] Create `ReadynessDashboard.lua` — module skeleton, state management, scan engine
- [x] Create `ReadynessDashboardUI.lua` — OGST panel, indicator widgets, dock system
- [x] SVM schema initialization and defaults
- [x] Event registration, periodic scanning
- [x] Slash command integration

### Phase 2: Mana, Health & Buff Indicators
- [x] Mana scanning (healer + DPS split)
- [x] Mana dual progress bar indicator
- [x] Health scanning (tank + raid split)
- [x] Health dual progress bar indicator
- [x] Buff scanning via `UnitBuff()` TurtleWoW API
- [x] Buff classification and required-buff-per-class logic
- [x] Buff deficit announcement builder

### Phase 3: Consume Indicators
- [ ] Class Consume scanning via `CT.CalculatePlayerScore()` integration
- [ ] Encounter Consume scanning via `isConsumeCheck` role
- [ ] `itemToSpell` mapping for encounter consume buff detection
- [ ] Consume announcement builders
- [ ] Dynamic hide/show of ECon indicator per encounter

### Phase 4: Cooldown Tracking
- [ ] Combat log event parsing for Rebirth, Tranquility, Taunt abilities
- [ ] Cooldown timer state management
- [ ] Druid/Warrior roster building
- [ ] Cooldown poll system (`+` in raid)
- [ ] Combat-aware click behavior (poll vs. announce)

### Phase 5: Polish & Integration
- [ ] Tooltip detail views for all indicators
- [ ] BuffManager integration for targeted buff announcements
- [ ] Settings UI for thresholds, buff categories, scan interval
- [ ] Right-click context menus for indicator configuration
- [ ] Performance profiling and optimization

---

## Future Enhancements

- **BigWigs/DBM Pull Timer Integration** — Auto-snapshot readiness when pull timer begins
- **Historical Tracking** — Record readiness state per pull for post-raid review
- **Custom Indicators** — Allow raid leaders to define custom indicators (e.g., Soulstone tracking)
- **Mini-Map Button** — Quick toggle via mini-map icon
- **Sound Alerts** — Play a sound when readiness drops below threshold
- **Sync to Raid** — Broadcast readiness summary to other addon users via AddonMsg

---

## Related Modules

| Module | Relationship |
|--------|-------------|
| `EncounterMgmt.lua` | Provides encounter data, consume roles, advanced settings |
| `ConsumesTracking.lua` | Provides `CalculatePlayerScore()` and RABuffs integration |
| `BuffManager.lua` | Provides buff assignments for targeted announcements |
| `MainUI.lua` | Provides OGRH_Main frame for docking |
| `Announce.lua` | Provides `OGRH.SendAnnouncement()` for raid messages |
| `Core.lua` | Provides `OGRH.CanRW()`, `OGRH.COLOR`, `OGRH.Msg()` |
| `OGST.lua` | Provides docked panel system, progress bars, layout engine |

---

## Change Log

| Version | Date | Changes |
|---------|------|---------|
| 1.1 | Feb 2026 | Added Health Readyness indicator (Tanks/Raid split); Updated BuffManager from future to implemented across all references |
| 1.0 | Feb 2026 | Initial Readyness Dashboard specification |
