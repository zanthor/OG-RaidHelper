# LootManager (LootMan) — Design Document

**Version:** 1.0  
**Module:** LootMan.lua  
**Location:** `_Administration/LootMan.lua`  
**Target Release:** 2.1  
**Last Updated:** February 15, 2026  
**Status:** Design Phase  
**Dependencies:** Admin Encounter (EncounterAdmin.lua), SR+ Validation (SRValidation.lua), SVM, OGST, ChatThrottleLib

---

## Executive Summary

LootManager (LootMan) is a comprehensive loot distribution system that replaces RollFor as the master looting interface within OG-RaidHelper. It integrates directly with the Admin Encounter's loot settings, the existing Roster/Invites system, and a redesigned SR+ Validation module to provide error-free, rules-aware loot distribution with full audit capability.

**Core Goals:**

- **Replace RollFor** — Native master looting interface with no external addon dependency
- **SR+ Import Compatibility** — Import from RaidRes.top export format (base64 JSON) and standard CSV
- **Rules-Aware Distribution** — Enforce MS > OS > Alt MS > Alt OS > TMOG roll hierarchy with SR+ priority
- **Sanity Checks** — Prevent equip-incompatible awards (sword → priest), prompt for disenchanter
- **Pre-Raid Validation** — Surface SR+ conflicts before raid starts, not when loot drops
- **Boss/Trash/Token Awareness** — Track tradability windows and non-tradable tokens
- **Roster Integration** — Leverage guild roster Main/Alt/MainSpec/OffSpec data for roll enforcement

---

## Problem Statement

### Current State

1. **RollFor Dependency** — The guild relies on RollFor for master loot distribution; RollFor has no awareness of guild roster, Main/Alt status, or custom loot rules
2. **No Equip Validation** — RollFor will happily award a sword to a priest or cloth to a warrior with no warning
3. **Manual SR+ Tracking** — Officers manually cross-reference SR+ sheets; errors surface mid-raid
4. **No Tradability Tracking** — 10-minute boss loot trade windows expire silently; non-tradable tokens (ZG/AQ20/AQ40/Naxx/K40 class tokens) get mis-assigned with no recourse
5. **No Roll Hierarchy Enforcement** — MS/OS/Alt/TMOG priority is honor-system only
6. **Disconnected Systems** — RollFor, SR+ sheets, guild roster, and OGRH admin encounter all operate independently

### Target State

A unified loot pipeline where:
- SR+ data is imported once and validated pre-raid
- The master looter sees eligible players sorted by SR+ with validation status
- Roll hierarchy (MS > OS > Alt MS > Alt OS > TMOG) is enforced by the system
- Equip-incompatible awards are blocked with configurable warnings
- Tradability timers are tracked and visible
- All loot decisions produce an audit trail

---

## RollFor Workflow Analysis (Baseline)

Understanding RollFor's current workflow is essential for building a compatible replacement.

### RollFor Loot Pipeline

```
LOOT_OPENED (WoW Event)
    │
    ├─→ LootList.on_loot_opened()
    │     Parse item slots → DroppedItem[] or Coin[]
    │     Read tooltip for bind type, class restrictions
    │
    ├─→ LootController.on_loot_opened()
    │     Build LootListEntry[] (annotate HR/SR per item)
    │     Show custom LootFrame
    │     Auto-reselect cached selections
    │
    ├─→ AutoLoot.on_loot_opened()
    │     Auto-loot items below threshold (if ML & enabled)
    │
    ├─→ MasterLoot.on_loot_opened()
    │     Clear slot cache & confirmation state
    │
    └─→ LootAutoProcess.on_loot_opened()
          Auto-preview first eligible item (if enabled)

ML clicks item in LootFrame
    │
    └─→ LootController.select_item()
          Cache selection, call RollController.preview()

RollController.preview()
    │
    ├─ HR item → Show HR badge, offer Roll/Award/Close
    ├─ SR count == item count → Declare SR winners (no roll)
    ├─ SR with contention → Show SR rollers, offer Roll
    └─ No SR → Show normal preview, offer Roll/InstaRaidRoll

ML clicks Roll
    │
    └─→ RollingLogic.start()
          Create RollingStrategy via factory
          Announce in raid chat, start timer

Players /roll
    │
    └─→ RollingLogic.on_roll()
          Route to active strategy.on_roll()
          Validate: player eligibility, roll range, remaining rolls

Timer expires / All rolled
    │
    └─→ strategy.on_rolling_finished()
          ├─ No winners → Finish (optionally auto-raid-roll)
          ├─ Winners > items → TieRollingLogic (re-roll tied)
          └─ Winners found → transform_to_winner(), finish

ML clicks Award Winner
    │
    └─→ LootAwardPopup confirmation
          └─→ MasterLoot.on_confirm()
                GiveMasterLoot(slot, index)
                └─→ LOOT_SLOT_CLEARED
                      LootAwardCallback.on_loot_awarded()
```

### RollFor Data Structures

| Type | Fields | Purpose |
|------|--------|---------|
| `DroppedItem` | id, name, link, quality, tooltip_link, quantity, bind, classes, is_boss_loot | Item in loot window |
| `RollingPlayer` | name, class, role, online, rolls, sr_plus, plus_ones | Player eligible to roll |
| `ItemCandidate` | name, class, online | ML candidate from WoW API |
| `Winner` | name, class, item, roll_type, winning_roll, is_on_ml_list | Roll winner |
| `Roll` | player, roll_type, roll (value) | Single roll record |

### RollFor Roll Types

| Roll Type | Command | Max Value | Priority |
|-----------|---------|-----------|----------|
| SoftRes | `/roll` (during SR) | 100 + sr_plus | Highest |
| MainSpec | `/roll` or `/roll 100` | 100 | High |
| OffSpec | `/roll 99` | 99 | Medium |
| Transmog | `/roll 98` | 98 | Low |

### RollFor SR+ Import Format (RaidRes.top Base64 JSON)

```json
{
  "metadata": {
    "id": "3QS858",
    "instance": 101,
    "instances": ["Karazhan"],
    "origin": "raidres"
  },
  "softreserves": [
    {
      "name": "Jogobobek",
      "role": "Daggers",
      "items": [
        {"id": 14145, "quality": 3, "sr_plus": 20},
        {"id": 14148, "quality": 3, "sr_plus": 0}
      ]
    }
  ],
  "hardreserves": [
    {"id": 19019, "quality": 4}
  ]
}
```

---

## LootManager Architecture

### Module Hierarchy

```
LootManager System
│
├── LootMan.lua (Core Orchestrator)
│   ├── Import Engine (CSV + RaidRes.top base64)
│   ├── Loot Event Handler (LOOT_OPENED pipeline)
│   ├── Roll Manager (roll tracking, hierarchy enforcement)
│   ├── Award Engine (sanity checks, ML API calls)
│   └── Tradability Tracker (boss loot 10min, token non-tradable)
│
├── LootManUI.lua (User Interface)
│   ├── Loot Distribution Window (replaces RollFor popup)
│   ├── SR+ Eligible List (sorted, validated)
│   ├── Roll Hierarchy Display (MS/OS/AltMS/AltOS/TMOG tabs)
│   ├── Sanity Check Dialogs (equip warnings, DE prompt)
│   ├── Tradability Timer Bar (per-item countdown)
│   └── Import Dialog (CSV paste / file browse)
│
├── LootManRules.lua (Rules Engine - Configurable)
│   ├── Equip Proficiency Tables (class → weapon/armor)
│   ├── Roll Hierarchy Definition (priority order)
│   ├── Hard Reserve Rules
│   ├── SR+ Threshold Rules (50+ = +1 tier for ALL)
│   └── Custom Rule Hooks (guild-specific overrides)
│
└── LootManData.lua (Data Layer)
    ├── Loot Session State (current raid's loot tracking)
    ├── Award History (per-raid loot log)
    ├── Tradability Records (item → expiry timestamp)
    └── Import Cache (parsed SR+ data)
```

### Integration Points

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│  Admin Encounter │────→│   LootManager    │←────│  SR+ Validation │
│  (Loot Settings) │     │   (LootMan.lua)  │     │ (SRValidation)  │
└─────────────────┘     └──────────────────┘     └─────────────────┘
        │                        │                        │
        │                        ▼                        │
        │               ┌──────────────────┐              │
        │               │   Roster/Invites │              │
        │               │ (Main/Alt/Spec)  │              │
        │               └──────────────────┘              │
        │                        │                        │
        ▼                        ▼                        ▼
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│  Loot Settings  │     │  WoW Master Loot │     │  Audit Trail    │
│  (Method/Thresh)│     │  API (GiveMaster │     │  (SVM Records)  │
│                 │     │  Loot)           │     │                 │
└─────────────────┘     └──────────────────┘     └─────────────────┘
```

---

## Data Import

### Import Sources

LootManager supports two import formats:

#### 1. RaidRes.top Base64 JSON (RollFor-Compatible)

The existing format used by RollFor. Base64-encoded JSON containing softreserves and hardreserves.

**Import Flow:**
```
User pastes base64 string
    → Base64 decode
    → JSON parse
    → SoftResDataTransformer.transform()
    → LootMan.ImportSRData(softresData, hardresData, metadata)
    → Store in SVM: lootManager.importedSR
    → Trigger SR+ Validation pre-check
```

**Compatibility Note:** LootManager reads the same `RollForCharDb.softres.data` field if RollFor is installed, enabling a migration period where both can coexist.

#### 2. Standard CSV Format (RaidRes.top Export)

```csv
ID,Item,Boss,Attendee,Class,Specialization,Comment,Date,"Date (GMT)",SR+
19346,"Dragonfang Blade",Vaelastrasz,Thannatos,Rogue,Daggers,,"2/11/2026, 9:02:20 PM","2026-02-12 03:02:20",60
21232,"Imperial Qiraji Armaments",Fankriss,Holypriest,Paladin,Holy,,"2/11/2026, 9:02:20 PM","2026-02-12 03:02:20",30
```

**CSV Field Mapping:**

| CSV Column | Internal Field | Notes |
|-----------|---------------|-------|
| `ID` | `itemId` | WoW item ID (number) |
| `Item` | `itemName` | Display name (string) |
| `Boss` | `bossName` | Source boss (for validation) |
| `Attendee` | `playerName` | Character name |
| `Class` | `class` | Player class |
| `Specialization` | `spec` | Player spec (maps to MS/OS) |
| `Comment` | `comment` | User notes (optional) |
| `Date` | `localDate` | Local timestamp |
| `Date (GMT)` | `gmtDate` | UTC timestamp |
| `SR+` | `srPlus` | Current SR+ value (number) |

**CSV Import Flow:**
```
User pastes CSV text (or loads from SR Link text field)
    → Parse CSV headers
    → For each row: extract fields, validate types
    → Build softresData structure (same as RaidRes.top format internally)
    → LootMan.ImportCSVData(parsedRows)
    → Store in SVM: lootManager.importedSR
    → Trigger SR+ Validation pre-check
```

**CSV Parser Implementation:**
```lua
function OGRH.LootMan.ParseCSV(csvText)
    local rows = {}
    local headers = nil
    local lineNum = 0
    
    for line in string.gfind(csvText, "[^\n]+") do
        lineNum = lineNum + 1
        local fields = {}
        
        -- Handle quoted fields (CSV RFC 4180 compliant)
        local pos = 1
        while pos <= string.len(line) do
            if string.sub(line, pos, pos) == "\"" then
                -- Quoted field
                local endQuote = string.find(line, "\"", pos + 1)
                local value = string.sub(line, pos + 1, endQuote - 1)
                table.insert(fields, value)
                pos = endQuote + 2  -- Skip closing quote and comma
            else
                -- Unquoted field
                local nextComma = string.find(line, ",", pos)
                if nextComma then
                    table.insert(fields, string.sub(line, pos, nextComma - 1))
                    pos = nextComma + 1
                else
                    table.insert(fields, string.sub(line, pos))
                    pos = string.len(line) + 1
                end
            end
        end
        
        if lineNum == 1 then
            headers = fields
        else
            local row = {}
            for i = 1, table.getn(headers) do
                row[headers[i]] = fields[i] or ""
            end
            table.insert(rows, row)
        end
    end
    
    return rows, headers
end
```

### Imported Data Schema (SVM)

```lua
OGRH_SV.v2.lootManager = {
    schemaVersion = 1,
    
    -- Imported SR+ Data (unified from both sources)
    importedSR = {
        source = "raidres_csv",  -- "raidres_csv", "raidres_base64", "manual"
        importTimestamp = 1739577600,
        raidId = "3QS858",       -- From metadata (if available)
        instance = "Naxxramas",
        
        -- Soft Reserves (indexed by itemId)
        softReserves = {
            [19346] = {
                itemId = 19346,
                itemName = "Dragonfang Blade",
                quality = 4,  -- Epic
                rollers = {
                    [1] = {
                        name = "Thannatos",
                        class = "ROGUE",
                        spec = "Daggers",
                        srPlus = 60,
                        comment = "",
                    },
                    -- additional rollers for same item
                },
            },
            -- additional items
        },
        
        -- Hard Reserves
        hardReserves = {
            [18563] = {
                itemId = 18563,
                itemName = "Bindings of the Windseeker (Left)",
                quality = 5,  -- Legendary
                reservedFor = "MainTank",  -- Optional: specific player/role
                note = "Main Tank Priority",
            },
        },
        
        -- Per-Player SR+ Summary (computed from softReserves)
        playerSummary = {
            ["Thannatos"] = {
                class = "ROGUE",
                spec = "Daggers",
                items = {
                    [1] = {itemId = 19346, srPlus = 60, itemName = "Dragonfang Blade"},
                },
                totalSRPlus = 60,
                validationStatus = "PENDING",  -- PENDING, VALID, WARNING, ERROR
            },
        },
    },
    
    -- Current Loot Session
    session = {
        active = false,
        raidName = "",
        startTime = 0,
        
        -- Items awarded this session
        awarded = {
            -- [1] = { itemId, itemName, winner, method, srPlus, timestamp, tradable, tradeExpiry }
        },
        
        -- Items pending (loot window open)
        pending = {
            -- [1] = { itemId, itemName, slot, quality, bind, classes, isBossLoot }
        },
        
        -- Tradability tracking
        tradableItems = {
            -- [itemId.."-"..timestamp] = { itemId, itemName, winner, awardTime, tradeExpiry, isTradable }
        },
    },
    
    -- Configuration
    config = {
        enabled = true,
        
        -- Roll Hierarchy
        rollHierarchy = {
            -- Priority order (1 = highest)
            [1] = "MAIN_MS",     -- Main character, Main Spec
            [2] = "MAIN_OS",     -- Main character, Off Spec
            [3] = "ALT_MS",      -- Alt character, Main Spec
            [4] = "ALT_OS",      -- Alt character, Off Spec
            [5] = "TMOG",        -- Transmog (any character)
        },
        
        -- Roll Thresholds (max roll value per type)
        rollThresholds = {
            MAIN_MS = 100,
            MAIN_OS = 99,
            ALT_MS = 99,   -- Same as Main OS per rules: "Main OS = Alt MS"
            ALT_OS = 98,
            TMOG = 97,
        },
        
        -- SR+ Rules
        srPlusIncrement = 10,         -- Per week increment
        srPlusThreshold50 = true,     -- When SR+ >= 50, +1 tier for ALL
        maxSRPlus40 = 2,              -- Max SR items in 40-person raids
        maxSRPlus20 = 1,              -- Max SR items in 20-person raids
        
        -- Sanity Checks
        sanityChecks = {
            enabled = true,
            equipCheck = true,          -- Check class can equip item
            deDisenchantPrompt = true,  -- Prompt for DE assignment
            confirmNonTradable = true,  -- Extra confirm for non-tradable tokens
        },
        
        -- Tradability
        bossLootTradeWindow = 600,    -- 10 minutes (seconds)
        nonTradableTokenRaids = {     -- Raids with non-tradable class tokens
            "ZG", "AQ20", "AQ40", "Naxx", "K40",
        },
        
        -- Auto-Processing
        autoPreviewFirst = true,      -- Auto-preview first eligible item
        autoSkipBelowThreshold = true, -- Auto-loot items below quality threshold
    },
    
    -- Equip Proficiency Rules (configurable defaults)
    equipRules = {
        -- See LootManRules.lua section for full tables
    },
}
```

---

## Roll System

### Roll Hierarchy

LootManager enforces a strict roll priority system based on the guild's loot rules:

```
SR+ Rolls (when item is soft-reserved):
    Main MS > Main OS > Alt MS > Alt OS
    (when SR+ >= 50, +1 Threshold tier for ALL)

Open Rolls (when item has no SR, or SR rolls complete):
    Main MS > Main OS = Alt MS > Alt OS
```

### Roll Priority Resolution

```lua
-- Priority order for tie-breaking between roll categories
ROLL_PRIORITY = {
    SR_MAIN_MS = 1,    -- SR+ roller, Main character, Main Spec
    SR_MAIN_OS = 2,    -- SR+ roller, Main character, Off Spec
    SR_ALT_MS  = 3,    -- SR+ roller, Alt character, Main Spec  
    SR_ALT_OS  = 4,    -- SR+ roller, Alt character, Off Spec
    MAIN_MS    = 5,    -- Open roll, Main character, Main Spec
    MAIN_OS    = 6,    -- Open roll, Main character, Off Spec
    ALT_MS     = 6,    -- Open roll, Alt character, Main Spec (EQUAL to Main OS)
    ALT_OS     = 7,    -- Open roll, Alt character, Off Spec
    TMOG       = 8,    -- Transmog roll (any character)
}
```

### Roll Phase Flow

```
Item Drops
    │
    ▼
┌─────────────────────────────────────────────┐
│ Phase 0: Hard Reserve Check                  │
│ Is item HR? → Award to designated recipient  │
│ (per BaT Loot Rules: next eligible Core      │
│ Raider with Priority Class consideration)    │
└──────────────────────┬──────────────────────┘
                       │ Not HR
                       ▼
┌─────────────────────────────────────────────┐
│ Phase 1: SR+ Roll (if SR'd)                 │
│ Players who SR'd this item roll /roll       │
│ Roll value = /roll + sr_plus bonus          │
│ Sort by: SR+ tier → Roll value              │
│ Winner gets item (SR+ resets to 0)          │
│                                              │
│ If SR+ >= 50 for ANY roller:                │
│   +1 threshold tier for ALL SR rollers      │
└──────────────────────┬──────────────────────┘
                       │ No SR winner / No SRs
                       ▼
┌─────────────────────────────────────────────┐
│ Phase 2: Main Spec Roll                      │
│ Main characters roll /roll 100              │
│ Sort by: roll value (highest wins)          │
└──────────────────────┬──────────────────────┘
                       │ No MS winner
                       ▼
┌─────────────────────────────────────────────┐
│ Phase 3: Off Spec + Alt Main Spec Roll       │
│ Main OS and Alt MS roll /roll 99            │
│ (Equal priority per BaT rules)              │
│ Sort by: roll value (highest wins)          │
└──────────────────────┬──────────────────────┘
                       │ No OS/Alt MS winner
                       ▼
┌─────────────────────────────────────────────┐
│ Phase 4: Alt Off Spec Roll                   │
│ Alt characters roll /roll 98                │
│ Sort by: roll value (highest wins)          │
└──────────────────────┬──────────────────────┘
                       │ No Alt OS winner
                       ▼
┌─────────────────────────────────────────────┐
│ Phase 5: Transmog Roll                       │
│ Any character rolls /roll 97                │
│ Sort by: roll value (highest wins)          │
└──────────────────────┬──────────────────────┘
                       │ No TMOG winner
                       ▼
┌─────────────────────────────────────────────┐
│ Phase 6: Disenchant                          │
│ Award to designated disenchanter             │
│ (from Admin Encounter Role 3)               │
└─────────────────────────────────────────────┘
```

### Roll Detection

LootManager reads `/roll` results from `CHAT_MSG_SYSTEM` just as RollFor does:

```lua
-- Pattern: "PlayerName rolls 85 (1-100)"
local ROLL_PATTERN = "(.+) rolls (%d+) %((%d+)-(%d+)%)"

function OGRH.LootMan.OnRoll(msg)
    local player, rollValue, minRoll, maxRoll = string.find(msg, ROLL_PATTERN)
    if not player then return end
    
    rollValue = tonumber(rollValue)
    maxRoll = tonumber(maxRoll)
    
    -- Determine roll type from max value
    local rollType = OGRH.LootMan.ClassifyRoll(maxRoll)
    
    -- Validate against roster (Main/Alt, MS/OS)
    local validation = OGRH.LootMan.ValidateRoll(player, rollType)
    
    if validation.valid then
        OGRH.LootMan.RecordRoll(player, rollValue, rollType, validation)
    else
        OGRH.LootMan.FlagInvalidRoll(player, rollType, validation.reason)
    end
end
```

### Roll Classification

```lua
function OGRH.LootMan.ClassifyRoll(maxRoll)
    local thresholds = OGRH.LootMan.GetConfig().rollThresholds
    
    if maxRoll == thresholds.MAIN_MS then  -- 100
        return "MAIN_MS"
    elseif maxRoll == thresholds.MAIN_OS then  -- 99
        -- Could be Main OS or Alt MS (equal priority)
        -- Disambiguate using roster data
        return "MAIN_OS_OR_ALT_MS"
    elseif maxRoll == thresholds.ALT_OS then  -- 98
        return "ALT_OS"
    elseif maxRoll == thresholds.TMOG then  -- 97
        return "TMOG"
    else
        return "UNKNOWN"
    end
end

-- Disambiguate /roll 99 using roster
function OGRH.LootMan.ResolveAmbiguousRoll(playerName, rollType)
    if rollType ~= "MAIN_OS_OR_ALT_MS" then return rollType end
    
    local rosterEntry = OGRH.LootMan.GetRosterEntry(playerName)
    if not rosterEntry then
        return "MAIN_OS"  -- Default assumption
    end
    
    if rosterEntry.isAlt then
        return "ALT_MS"
    else
        return "MAIN_OS"
    end
end
```

---

## Roster Integration

### Main/Alt Detection

LootManager queries OG-RaidHelper's Roster module (`OGRH.RosterMgmt`) and the guild roster to determine each raider's Main/Alt/Spec status:

```lua
function OGRH.LootMan.GetRosterEntry(playerName)
    -- Check OGRH Roster first
    local rosterPlayer = OGRH.RosterMgmt and OGRH.RosterMgmt.GetPlayer(playerName)
    
    if rosterPlayer then
        return {
            name = playerName,
            class = rosterPlayer.class,
            isMain = rosterPlayer.isMain or true,
            isAlt = rosterPlayer.isAlt or false,
            mainName = rosterPlayer.mainName,     -- If alt, who is their main?
            mainSpec = rosterPlayer.mainSpec,       -- Primary spec
            offSpec = rosterPlayer.offSpec,         -- Secondary spec
            rank = rosterPlayer.rank,               -- Guild rank
        }
    end
    
    -- Fallback to guild roster
    local guildInfo = OGRH.LootMan.GetGuildRosterInfo(playerName)
    if guildInfo then
        return {
            name = playerName,
            class = guildInfo.class,
            isMain = true,  -- Assume main if not in OGRH roster
            isAlt = false,
            mainSpec = nil,
            offSpec = nil,
            rank = guildInfo.rank,
        }
    end
    
    -- Unknown player (PUG)
    return {
        name = playerName,
        class = OGRH.LootMan.GetUnitClass(playerName),
        isMain = true,  -- Assume main for PUGs
        isAlt = false,
        mainSpec = nil,
        offSpec = nil,
        rank = nil,
    }
end
```

### Spec Detection for Roll Validation

When a player rolls, LootManager checks if the item is appropriate for their spec:

```lua
function OGRH.LootMan.ValidateRoll(playerName, rollType)
    local roster = OGRH.LootMan.GetRosterEntry(playerName)
    local result = { valid = true, reason = "", warnings = {} }
    
    -- Alt rolling as Main MS?
    if rollType == "MAIN_MS" and roster.isAlt then
        result.valid = false
        result.reason = playerName .. " is an alt and cannot roll Main MS"
        return result
    end
    
    -- Main rolling as Alt OS?
    if rollType == "ALT_OS" and not roster.isAlt then
        table.insert(result.warnings, playerName .. " is a main rolling Alt OS")
    end
    
    return result
end
```

---

## Equip Proficiency Sanity Checks

### Default Proficiency Tables

```lua
OGRH.LootMan.WEAPON_PROFICIENCY = {
    -- Weapon subclass → classes that can equip
    ["Swords"]       = { WARRIOR = true, PALADIN = true, ROGUE = true, HUNTER = true, MAGE = true, WARLOCK = true },
    ["Two-Handed Swords"] = { WARRIOR = true, PALADIN = true, HUNTER = true },
    ["Maces"]        = { WARRIOR = true, PALADIN = true, ROGUE = true, SHAMAN = true, PRIEST = true, DRUID = true },
    ["Two-Handed Maces"] = { WARRIOR = true, PALADIN = true, SHAMAN = true, DRUID = true },
    ["Axes"]         = { WARRIOR = true, PALADIN = true, ROGUE = true, HUNTER = true, SHAMAN = true },
    ["Two-Handed Axes"] = { WARRIOR = true, PALADIN = true, HUNTER = true, SHAMAN = true },
    ["Daggers"]      = { WARRIOR = true, ROGUE = true, HUNTER = true, MAGE = true, WARLOCK = true, PRIEST = true, SHAMAN = true, DRUID = true },
    ["Fist Weapons"] = { WARRIOR = true, ROGUE = true, HUNTER = true, SHAMAN = true, DRUID = true },
    ["Polearms"]     = { WARRIOR = true, PALADIN = true, HUNTER = true, DRUID = true, SHAMAN = true },
    ["Staves"]       = { WARRIOR = true, MAGE = true, WARLOCK = true, PRIEST = true, DRUID = true, SHAMAN = true, HUNTER = true },
    ["Bows"]         = { WARRIOR = true, ROGUE = true, HUNTER = true },
    ["Crossbows"]    = { WARRIOR = true, ROGUE = true, HUNTER = true },
    ["Guns"]         = { WARRIOR = true, ROGUE = true, HUNTER = true },
    ["Thrown"]        = { WARRIOR = true, ROGUE = true, HUNTER = true },
    ["Wands"]        = { MAGE = true, WARLOCK = true, PRIEST = true },
}

OGRH.LootMan.ARMOR_PROFICIENCY = {
    -- Armor subclass → classes that can equip
    ["Cloth"]        = { WARRIOR = true, PALADIN = true, ROGUE = true, HUNTER = true, MAGE = true, WARLOCK = true, PRIEST = true, DRUID = true, SHAMAN = true },
    ["Leather"]      = { WARRIOR = true, PALADIN = true, ROGUE = true, HUNTER = true, DRUID = true, SHAMAN = true },
    ["Mail"]         = { WARRIOR = true, PALADIN = true, HUNTER = true, SHAMAN = true },
    ["Plate"]        = { WARRIOR = true, PALADIN = true },
    ["Shields"]      = { WARRIOR = true, PALADIN = true, SHAMAN = true },
    ["Librams"]      = { PALADIN = true },
    ["Totems"]       = { SHAMAN = true },
    ["Idols"]        = { DRUID = true },
}
```

### Sanity Check Flow

```
ML clicks Award on Player
    │
    ▼
┌─────────────────────────────────────────────┐
│ Step 1: Equip Proficiency Check              │
│ Can this class equip this item type?         │
│                                              │
│ Read item tooltip → extract weapon/armor     │
│ subclass. Cross-reference against            │
│ WEAPON_PROFICIENCY / ARMOR_PROFICIENCY.      │
│                                              │
│ Also check item's own class restriction      │
│ field (from tooltip: "Classes: Warrior,      │
│ Paladin")                                    │
│                                              │
│ FAIL → Warning dialog:                       │
│ "[PlayerName] cannot equip [ItemName]        │
│  (Priests cannot use Swords).                │
│  Award anyway? [Yes] [No] [Disenchant]"     │
└──────────────────────┬──────────────────────┘
                       │ Pass / Override
                       ▼
┌─────────────────────────────────────────────┐
│ Step 2: Non-Tradable Token Check             │
│ Is this a class token from                   │
│ ZG/AQ20/AQ40/Naxx/K40?                      │
│                                              │
│ Token items are identified by a configurable │
│ list of itemIds per raid.                    │
│                                              │
│ MATCH → Extra confirmation dialog:           │
│ "⚠ [ItemName] is a non-tradable token.      │
│  Once assigned it CANNOT be traded.          │
│  Confirm award to [PlayerName]?             │
│  [Confirm] [Cancel]"                         │
└──────────────────────┬──────────────────────┘
                       │ Pass / Confirmed
                       ▼
┌─────────────────────────────────────────────┐
│ Step 3: Disenchant Prompt                    │
│ (If no one wanted the item)                  │
│                                              │
│ "No eligible rollers. Send to disenchanter?" │
│ Disenchanter: [Admin Encounter Role 3 name] │
│ [Send to DE] [Award to Other] [Leave]       │
└──────────────────────┬──────────────────────┘
                       │
                       ▼
                GiveMasterLoot(slot, index)
```

### Tooltip Parsing for Item Type

```lua
function OGRH.LootMan.GetItemEquipInfo(itemLink)
    -- Create hidden tooltip
    local tooltip = OGRH.LootMan.ScanTooltip
    if not tooltip then
        tooltip = CreateFrame("GameTooltip", "OGRH_LootManScanTooltip", nil, "GameTooltipTemplate")
        OGRH.LootMan.ScanTooltip = tooltip
    end
    
    tooltip:SetOwner(UIParent, "ANCHOR_NONE")
    tooltip:ClearLines()
    tooltip:SetHyperlink(itemLink)
    
    local itemType = nil
    local itemSubType = nil
    local classRestriction = nil
    
    -- Scan tooltip lines for equip info
    for i = 2, tooltip:NumLines() do
        local leftText = getglobal("OGRH_LootManScanTooltipTextLeft" .. i)
        if leftText then
            local text = leftText:GetText()
            if text then
                -- Check for armor/weapon type (typically line 2-3)
                -- e.g., "Two-Hand", "Sword", "Plate", "Mail", "Leather"
                -- RightText often has subclass: "Sword" on right of "Main Hand"
                
                -- Check for class restriction
                local classes = string.find(text, "^Classes:%s*(.+)")
                if classes then
                    classRestriction = classes
                end
            end
        end
        
        local rightText = getglobal("OGRH_LootManScanTooltipTextRight" .. i)
        if rightText then
            local text = rightText:GetText()
            if text then
                itemSubType = text  -- Often the weapon/armor subclass
            end
        end
    end
    
    tooltip:Hide()
    
    return {
        itemType = itemType,
        itemSubType = itemSubType,
        classRestriction = classRestriction,
    }
end

function OGRH.LootMan.CanPlayerEquip(playerName, itemLink)
    local equipInfo = OGRH.LootMan.GetItemEquipInfo(itemLink)
    local roster = OGRH.LootMan.GetRosterEntry(playerName)
    local playerClass = roster.class
    
    -- Check class restriction first (most specific)
    if equipInfo.classRestriction then
        if not string.find(equipInfo.classRestriction, playerClass) then
            return false, "Class restriction: " .. equipInfo.classRestriction
        end
    end
    
    -- Check weapon proficiency
    if equipInfo.itemSubType and OGRH.LootMan.WEAPON_PROFICIENCY[equipInfo.itemSubType] then
        local canUse = OGRH.LootMan.WEAPON_PROFICIENCY[equipInfo.itemSubType][playerClass]
        if not canUse then
            return false, playerClass .. " cannot use " .. equipInfo.itemSubType
        end
    end
    
    -- Check armor proficiency
    if equipInfo.itemSubType and OGRH.LootMan.ARMOR_PROFICIENCY[equipInfo.itemSubType] then
        local canUse = OGRH.LootMan.ARMOR_PROFICIENCY[equipInfo.itemSubType][playerClass]
        if not canUse then
            return false, playerClass .. " cannot wear " .. equipInfo.itemSubType
        end
    end
    
    return true, nil
end
```

### Custom Rule Configuration

Proficiency tables are stored in SVM and can be edited by officers:

```lua
function OGRH.LootMan.GetEquipRules()
    local customRules = OGRH.SVM.GetPath("lootManager.equipRules")
    if customRules and customRules.weaponProficiency then
        return customRules
    end
    
    -- Return defaults
    return {
        weaponProficiency = OGRH.LootMan.WEAPON_PROFICIENCY,
        armorProficiency = OGRH.LootMan.ARMOR_PROFICIENCY,
    }
end
```

---

## Tradability Tracking

### Loot Categories

| Category | Tradable? | Window | Examples |
|----------|-----------|--------|----------|
| Boss Loot | Yes | 10 minutes | All boss drops |
| Trash Loot | No | — | BOE greens/blues from trash |
| Class Tokens | No | — | ZG/AQ20/AQ40/Naxx/K40 tokens |
| Quest Items | No | — | Quest-flagged items |
| Coins | N/A | — | Gold drops |

### Non-Tradable Token List (Configurable)

```lua
-- Default non-tradable token item IDs
OGRH.LootMan.NON_TRADABLE_TOKENS = {
    -- Zul'Gurub (ZG)
    [19724] = "Primal Hakkari Aegis",
    [19716] = "Primal Hakkari Armsplint",
    [19717] = "Primal Hakkari Bindings",
    [19718] = "Primal Hakkari Stanchion",
    [19719] = "Primal Hakkari Girdle",
    [19720] = "Primal Hakkari Sash",
    [19721] = "Primal Hakkari Shawl",
    [19722] = "Primal Hakkari Tabard",
    [19723] = "Primal Hakkari Kossack",
    
    -- AQ20 (Ruins of Ahn'Qiraj)
    [20888] = "Qiraji Ceremonial Ring",
    [20884] = "Qiraji Magisterial Ring",
    [20885] = "Qiraji Martial Drape",
    [20889] = "Qiraji Regal Drape",
    [20890] = "Qiraji Ornate Hilt",
    [20886] = "Qiraji Spiked Hilt",
    
    -- AQ40 (Temple of Ahn'Qiraj)
    [20926] = "Vek'nilash's Circlet",
    [20927] = "Ouro's Intact Hide",
    [20928] = "Qiraji Bindings of Command",
    [20929] = "Qiraji Bindings of Dominance",
    [20930] = "Vek'lor's Diadem",
    [20931] = "Skin of the Great Sandworm",
    [20932] = "Imperial Qiraji Armaments",
    [20933] = "Imperial Qiraji Regalia",
    [21232] = "Imperial Qiraji Armaments",
    [21237] = "Imperial Qiraji Regalia",
    
    -- Naxxramas
    [22349] = "Desecrated Breastplate",
    [22350] = "Desecrated Tunic",
    [22351] = "Desecrated Robe",
    [22352] = "Desecrated Legplates",
    [22359] = "Desecrated Leggings",
    [22366] = "Desecrated Legguards",
    [22353] = "Desecrated Helmet",
    [22360] = "Desecrated Headpiece",
    [22367] = "Desecrated Circlet",
    [22354] = "Desecrated Pauldrons",
    [22361] = "Desecrated Shoulderpads",
    [22368] = "Desecrated Spaulders",
    [22355] = "Desecrated Bracers",
    [22362] = "Desecrated Wristguards",
    [22369] = "Desecrated Bindings",
    [22356] = "Desecrated Gauntlets",
    [22363] = "Desecrated Handguards",
    [22370] = "Desecrated Gloves",
    [22357] = "Desecrated Waistguard",
    [22364] = "Desecrated Belt",
    [22371] = "Desecrated Girdle",
    [22358] = "Desecrated Sabatons",
    [22365] = "Desecrated Boots",
    [22372] = "Desecrated Sandals",
    -- Sapphiron enchants (Might/Fortitude/Resilience/Power of the Scourge)
    [22726] = "Splinter of Atiesh",
    
    -- K40 (Karazhan 40 - Turtle WoW custom content)
    -- Add K40 class token IDs when available
}
```

### Trade Window Tracking

```lua
function OGRH.LootMan.StartTradeTimer(itemId, itemName, winner, isBossLoot)
    if not isBossLoot then
        -- Trash loot and tokens are not tradable
        OGRH.LootMan.RecordNonTradable(itemId, itemName, winner)
        return
    end
    
    local tradeExpiry = GetTime() + OGRH.LootMan.GetConfig().bossLootTradeWindow
    
    local record = {
        itemId = itemId,
        itemName = itemName,
        winner = winner,
        awardTime = GetTime(),
        tradeExpiry = tradeExpiry,
        isTradable = true,
    }
    
    local key = itemId .. "-" .. tostring(math.floor(GetTime()))
    OGRH.SVM.SetPath("lootManager.session.tradableItems." .. key, record)
    
    -- Schedule expiry warning at 2 minutes remaining
    OGRH.LootMan.ScheduleTradeWarning(key, tradeExpiry - 120)
    
    -- Schedule expiry
    OGRH.LootMan.ScheduleTradeExpiry(key, tradeExpiry)
end
```

---

## Admin Encounter Integration

### Reading Loot Settings

LootManager reads configuration from the Admin Encounter (index 1, always present):

```lua
function OGRH.LootMan.GetAdminSettings()
    local raidIdx = 1  -- Active Raid
    local raid = OGRH.SVM.GetPath("encounterMgmt.raids." .. raidIdx)
    if not raid then return nil end
    
    local adminEnc = raid.encounters and raid.encounters[1]
    if not adminEnc or not OGRH.IsAdminEncounter(adminEnc) then return nil end
    
    local roles = adminEnc.roles
    return {
        masterLooter = roles[1] and roles[1].assignedPlayers and roles[1].assignedPlayers[1],
        lootSettings = roles[2],  -- { lootMethod, autoSwitch, threshold }
        disenchanter = roles[3] and roles[3].assignedPlayers and roles[3].assignedPlayers[1],
        lootRules = roles[4] and roles[4].textValue,
        bagspaceBuffer = roles[5] and roles[5].assignedPlayers and roles[5].assignedPlayers[1],
        discordLink = roles[6] and roles[6].textValue,
        srLink = roles[7] and roles[7].textValue,
    }
end
```

### Auto-Switch Integration

When `autoSwitch` is enabled in Admin Encounter's Loot Settings:

```lua
function OGRH.LootMan.OnTargetChanged()
    local admin = OGRH.LootMan.GetAdminSettings()
    if not admin or not admin.lootSettings or not admin.lootSettings.autoSwitch then return end
    
    local targetName = UnitName("target")
    if not targetName then return end
    
    -- Is target a boss?
    local isBoss = OGRH.LootMan.IsBossTarget(targetName)
    
    if isBoss then
        -- Switch to Master Loot for bosses
        if GetLootMethod() ~= "master" then
            local ml = admin.masterLooter or UnitName("player")
            SetLootMethod("master", ml)
            OGRH.Msg("|cffcc99ff[RH-LootMan]|r Auto-switched to Master Loot for boss: " .. targetName)
        end
    else
        -- Switch to Group Loot for trash
        if GetLootMethod() ~= "group" then
            SetLootMethod("group")
            OGRH.Msg("|cffcc99ff[RH-LootMan]|r Auto-switched to Group Loot for trash")
        end
    end
end
```

---

## User Interface

### Loot Distribution Window

```
┌─────────────────────────────────────────────────────────────────┐
│ ⚔ LootManager — Naxxramas (Feb 15, 2026)              [✕]    │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  [Icon] Desecrated Breastplate                                 │
│  Quality: Epic  │  Source: Four Horsemen  │  ⚠ NON-TRADABLE   │
│  Classes: Warrior, Rogue, Paladin (Token)                      │
│                                                                 │
├─────────────────────────────────────────────────────────────────┤
│  SR+ Eligible:                                    [Validate All]│
├─────────────────────────────────────────────────────────────────┤
│  ✓ Tankadin      Paladin  SR+ 40  Main/MS  [Validate] [Award] │
│  ✓ Stabsworth    Rogue    SR+ 30  Main/MS  [Validate] [Award] │
│  ⚠ Cleavemaster  Warrior  SR+ 20  Alt/MS   [Validate] [Award] │
│    Darkstab      Rogue    SR+  0  Main/MS  [Validate] [Award] │
│                                                                 │
├─────────────────────┬───────────────────────────────────────────┤
│  Open Roll:          │  Award Controls:                         │
│  [Start MS Roll]    │  [Select Player ▼] [Manual Award]       │
│  [Start OS/Alt Roll]│  [Send to DE: Enchanter1]               │
│  [Start TMOG Roll]  │                                          │
│  [Raid Roll]        │  [Skip Item] [Close Loot]               │
├─────────────────────┴───────────────────────────────────────────┤
│  Trade Timers:                                                  │
│  🕐 Desecrated Robe → Holypriest (7:23 remaining)             │
│  🕐 Gressil → Stabsworth (3:41 remaining)                     │
│  ❌ Token of Fortitude → Tankadin (non-tradable)               │
└─────────────────────────────────────────────────────────────────┘
```

### Sanity Check Warning Dialog

```
┌─────────────────────────────────────────────┐
│ ⚠ Equip Warning                       [✕]  │
├─────────────────────────────────────────────┤
│                                             │
│  Holypriest (Priest) cannot equip:         │
│                                             │
│  [Icon] Gressil, Dawn of Ruin              │
│  Type: Sword (One-Hand)                    │
│                                             │
│  Priests cannot use Swords.                │
│                                             │
│  ┌─────────────────────────────────────┐   │
│  │ [Award Anyway] [Cancel] [Send DE]  │   │
│  └─────────────────────────────────────┘   │
│                                             │
│  □ Don't warn for this item again          │
└─────────────────────────────────────────────┘
```

### Non-Tradable Token Confirmation

```
┌─────────────────────────────────────────────┐
│ ⚠ Non-Tradable Item                   [✕]  │
├─────────────────────────────────────────────┤
│                                             │
│  [Icon] Desecrated Breastplate              │
│                                             │
│  This is a CLASS TOKEN from Naxxramas.      │
│  Once assigned, it CANNOT be traded.        │
│                                             │
│  Award to: Tankadin (Paladin)              │
│                                             │
│  ┌─────────────────────────────────────┐   │
│  │ [Confirm Award]         [Cancel]    │   │
│  └─────────────────────────────────────┘   │
└─────────────────────────────────────────────┘
```

### Import Dialog

```
┌─────────────────────────────────────────────────────┐
│ Import SR+ Data                                [✕]  │
├─────────────────────────────────────────────────────┤
│                                                     │
│  Source: (●) RaidRes.top Base64  ( ) CSV            │
│                                                     │
│  ┌───────────────────────────────────────────────┐  │
│  │ Paste data here...                            │  │
│  │                                               │  │
│  │                                               │  │
│  │                                               │  │
│  └───────────────────────────────────────────────┘  │
│                                                     │
│  [Import]  [Clear]  [Load from SR Link field]      │
│                                                     │
│  Status: ✓ 24 players, 31 SR entries imported      │
│  Warnings: 2 players not in roster (marked PUG)    │
│                                                     │
└─────────────────────────────────────────────────────┘
```

---

## API Design

### Core Functions

#### `OGRH.LootMan.Initialize()`
Initialize LootManager module. Called on ADDON_LOADED.

**Returns:** `nil`

---

#### `OGRH.LootMan.ImportBase64(encodedData)`
Import SR+ data from RaidRes.top base64 format.

**Parameters:**
- `encodedData` (string) — Base64-encoded JSON string

**Returns:** `boolean, string` — Success status and message

**Example:**
```lua
local ok, msg = OGRH.LootMan.ImportBase64("eyJtZXRhZGF0YS...")
if ok then
    OGRH.Msg("|cff00ff00[RH-LootMan]|r " .. msg)
end
```

---

#### `OGRH.LootMan.ImportCSV(csvText)`
Import SR+ data from standard CSV format.

**Parameters:**
- `csvText` (string) — CSV text with header row

**Returns:** `boolean, string` — Success status and message

**Example:**
```lua
local csvData = 'ID,Item,Boss,Attendee,Class,Specialization,Comment,Date,"Date (GMT)",SR+\n19346,...'
local ok, msg = OGRH.LootMan.ImportCSV(csvData)
```

---

#### `OGRH.LootMan.GetSRForItem(itemId)`
Get all SR+ entries for an item.

**Parameters:**
- `itemId` (number) — WoW item ID

**Returns:** `table[]` — Array of SR entries sorted by SR+ descending

**Example:**
```lua
local entries = OGRH.LootMan.GetSRForItem(19346)
-- entries[1] = { name = "Thannatos", srPlus = 60, class = "ROGUE", ... }
```

---

#### `OGRH.LootMan.IsHardReserved(itemId)`
Check if an item is hard reserved.

**Parameters:**
- `itemId` (number)

**Returns:** `boolean, table|nil` — Reserved status and HR details

---

#### `OGRH.LootMan.StartRoll(itemId, rollPhase)`
Begin a roll phase for an item.

**Parameters:**
- `itemId` (number) — Item to roll for
- `rollPhase` (string) — "SR", "MAIN_MS", "MAIN_OS_ALT_MS", "ALT_OS", "TMOG"

**Returns:** `boolean` — Success status

---

#### `OGRH.LootMan.AwardItem(itemId, playerName, method, rollValue)`
Award an item to a player with full sanity checks.

**Parameters:**
- `itemId` (number) — Item ID
- `playerName` (string) — Winner name
- `method` (string) — "SR_PLUS", "ROLL_MS", "ROLL_OS", "MANUAL", "DISENCHANT"
- `rollValue` (number|nil) — Roll value (if applicable)

**Returns:** `boolean, string` — Success status and message

---

#### `OGRH.LootMan.CanPlayerEquip(playerName, itemLink)`
Check if a player's class can equip an item.

**Parameters:**
- `playerName` (string)
- `itemLink` (string) — WoW item link

**Returns:** `boolean, string|nil` — Can equip, reason if not

---

#### `OGRH.LootMan.IsNonTradableToken(itemId)`
Check if an item is a non-tradable class token.

**Parameters:**
- `itemId` (number)

**Returns:** `boolean`

---

#### `OGRH.LootMan.GetTradableItems()`
Get all items with active trade windows.

**Returns:** `table[]` — Array of tradable item records with remaining time

---

#### `OGRH.LootMan.GetDisenchanter()`
Get the designated disenchanter from Admin Encounter.

**Returns:** `string|nil` — Player name or nil

---

#### `OGRH.LootMan.ValidatePreRaid()`
Run pre-raid SR+ validation. Surfaces conflicts before raid starts.

**Returns:** `table` — Validation report with warnings/errors per player

---

### Event Integration

```lua
-- Events LootManager registers for
local EVENTS = {
    "LOOT_OPENED",          -- Loot window opened
    "LOOT_CLOSED",          -- Loot window closed
    "LOOT_SLOT_CLEARED",    -- Item looted from slot
    "CHAT_MSG_SYSTEM",      -- Roll messages
    "CHAT_MSG_LOOT",        -- Loot received messages
    "PLAYER_TARGET_CHANGED", -- For auto-switch ML/Group
    "PARTY_LOOT_METHOD_CHANGED", -- Loot method changed
}
```

---

## Message Routing

### Chat Prefixes

**Module Prefix:** `[RH-LootMan]`  
**Color Code:** `|cffcc99ff` (Light Purple — Administration category)

```lua
-- Module load
OGRH.Msg("|cffcc99ff[RH-LootMan]|r Loaded")

-- Import success
OGRH.Msg("|cff00ff00[RH-LootMan]|r Imported 24 SR entries from RaidRes.top")

-- Roll announcement (via ChatThrottleLib to RAID)
ChatThrottleLib:SendChatMessage("NORMAL", "OGRH",
    "Roll for [Desecrated Breastplate]: SR+ by Tankadin (40), Stabsworth (30), Cleavemaster (20)",
    "RAID")

-- Sanity check warning
OGRH.Msg("|cffffaa00[RH-LootMan]|r WARNING: Holypriest cannot equip Gressil (Sword)")

-- Award announcement (via ChatThrottleLib to RAID)
ChatThrottleLib:SendChatMessage("NORMAL", "OGRH",
    "[Desecrated Breastplate] awarded to Tankadin (SR+ 40, Main/MS)",
    "RAID")

-- Trade timer warning
OGRH.Msg("|cffffaa00[RH-LootMan]|r Trade window expiring in 2 min: [Gressil] → Stabsworth")

-- Error
OGRH.Msg("|cffff0000[RH-LootMan]|r Error: Cannot award - loot window closed")

-- Debug
if OGRH.LootMan.State.debug then
    OGRH.Msg("|cffcc99ff[RH-LootMan][DEBUG]|r ParseCSV: 24 rows, 10 columns")
end
```

---

## Slash Commands

```lua
SLASH_OGRHLOOTMAN1 = "/ogrhlm"
SLASH_OGRHLOOTMAN2 = "/lootman"

SlashCmdList["OGRHLOOTMAN"] = function(msg)
    local args = {}
    for word in string.gfind(msg, "%S+") do
        table.insert(args, word)
    end
    
    local cmd = args[1] and string.lower(args[1]) or ""
    
    if cmd == "" or cmd == "show" then
        OGRH.LootMan.ShowWindow()
    elseif cmd == "import" then
        OGRH.LootMan.ShowImportDialog()
    elseif cmd == "validate" then
        OGRH.LootMan.ValidatePreRaid()
    elseif cmd == "status" then
        OGRH.LootMan.PrintStatus()
    elseif cmd == "config" then
        OGRH.LootMan.ShowConfig()
    elseif cmd == "debug" then
        OGRH.LootMan.State.debug = not OGRH.LootMan.State.debug
        OGRH.Msg("|cffcc99ff[RH-LootMan]|r Debug: " .. 
            (OGRH.LootMan.State.debug and "ON" or "OFF"))
    elseif cmd == "help" then
        OGRH.Msg("|cffcc99ff[RH-LootMan]|r Commands:")
        OGRH.Msg("  /lootman show - Open LootManager window")
        OGRH.Msg("  /lootman import - Open import dialog")
        OGRH.Msg("  /lootman validate - Run pre-raid validation")
        OGRH.Msg("  /lootman status - Show current session status")
        OGRH.Msg("  /lootman config - Open configuration")
        OGRH.Msg("  /lootman debug - Toggle debug mode")
    end
end
```

---

## File Structure

```
OG-RaidHelper/
├── _Administration/
│   ├── LootMan.lua              -- Core orchestrator (import, roll, award)
│   ├── LootManUI.lua            -- Loot distribution window UI
│   ├── LootManRules.lua         -- Equip proficiency, roll hierarchy rules
│   ├── LootManData.lua          -- Data layer (SVM integration, session state)
│   ├── SRValidation.lua         -- Updated SR+ validation (see SR+ Validation doc)
│   └── SRMasterLoot.lua         -- Future: blockchain SR+ tracking
│
├── _Raid/
│   └── EncounterAdmin.lua       -- Admin encounter (loot settings source)
│
├── _Configuration/
│   └── Invites.lua              -- Roster/planning (SR+ source)
│
└── Documentation/
    └── 2.1/
        ├── LootMan.md           -- This document
        ├── SR+ Validation.md    -- SR+ Validation updates
        └── SR+ Master Loot & Validation Design.md  -- Future blockchain design
```

### TOC Load Order

Add to Phase 5 (Administration) in `OG-RaidHelper.toc`:

```toc
## Phase 5: Administration
_Administration\AdminSelection.lua
_Administration\Roster.lua
_Administration\PendingSegments.lua
_Administration\Recruitment.lua
_Administration\SRValidation.lua
_Administration\LootManRules.lua       -- NEW: Rules engine (no dependencies)
_Administration\LootManData.lua        -- NEW: Data layer (SVM dependency)
_Administration\LootMan.lua            -- NEW: Core orchestrator
_Administration\LootManUI.lua          -- NEW: UI (OGST dependency)
_Administration\AddonAudit.lua
```

---

## Testing Strategy

### Unit Tests

| Test | Description | Expected |
|------|-------------|----------|
| CSV Import - Valid | Import well-formed CSV | 24 entries parsed |
| CSV Import - Empty Fields | CSV with missing optional fields | Graceful default |
| CSV Import - Malformed | CSV with wrong column count | Error message, no import |
| Base64 Import - Valid | Import RaidRes.top data | Matches RollFor behavior |
| Base64 Import - Corrupt | Corrupt base64 string | Error message, no import |
| Equip Check - Valid | Warrior + Sword | true |
| Equip Check - Invalid | Priest + Sword | false, "Priests cannot use Swords" |
| Equip Check - Class Token | Token with class restriction | Respect Classes: field |
| Roll Classify - MS | /roll 100 | MAIN_MS |
| Roll Classify - OS | /roll 99 + roster check | MAIN_OS or ALT_MS |
| Roll Classify - TMOG | /roll 97 | TMOG |
| Non-Tradable Check | Desecrated Breastplate | true |
| Non-Tradable Check | Random Epic | false |
| HR Check | HR item | true + HR details |
| Trade Timer | 10 min window | Counts down, warns at 2 min |
| Roster - Main | Main character | isMain = true |
| Roster - Alt | Alt character | isAlt = true, mainName set |

### Integration Tests

| Test | Description | Expected |
|------|-------------|----------|
| Full Loot Flow | Boss drop → SR roll → Award → Trade timer | Complete pipeline |
| Pre-Raid Validate | Import + Validate before raid | Report with warnings |
| Auto-Switch | Target boss → ML, target trash → Group | Loot method switches |
| DE Flow | No rollers → DE prompt → Award to DE | DE receives item |
| Sanity Block | Award sword to priest | Warning dialog shown |
| Token Confirm | Award non-tradable token | Extra confirmation shown |
| RollFor Compat | Import from RollForCharDb | Data matches |

### Edge Cases

1. Player disconnects mid-roll
2. Loot window closed before award confirmed
3. Multiple items of same ID drop simultaneously
4. SR+ ties between players at same value
5. Player not in ML candidate list (too far)
6. Inventory full on recipient
7. Admin Encounter not present (no DE/ML assignments)
8. Import data has players not in raid
9. Player changes spec between import and roll
10. Trade timer expires during another award

---

## SR+ Validation Integration

LootManager depends on the updated SR+ Validation module for pre-raid checks. See [SR+ Validation.md](SR+%20Validation.md) for the complete spec.

**Key integration points:**

1. **Pre-Raid Validation** — `OGRH.LootMan.ValidatePreRaid()` calls `OGRH.SRValidation.ValidateAll()` and displays results in the LootManager UI
2. **Import Trigger** — After importing SR+ data, LootManager triggers validation automatically
3. **Loot-Time Validation** — When an SR+ item drops, LootManager calls `OGRH.SRValidation.GetValidationStatus(playerName, srPlus)` for each eligible roller
4. **Conflict Surfacing** — Validation warnings appear in the LootManager's eligible player list (⚠ icon)

---

## Future Enhancements (Post-Initial Release)

### Phase 2 Features
- **Loot History Browser** — View all loot awarded across sessions
- **Export Loot Log** — CSV/text export for guild records
- **Loot Statistics** — Items won per player, average SR+ at win
- **Multi-Roll Automation** — Auto-advance through SR → MS → OS → TMOG phases

### Phase 3 Features (Blockchain Integration)
- **SR+ Blockchain** — Replace imported SR+ with native tracking (per SR+ Master Loot Design)
- **Officer Sync** — Multi-officer SR+ validation and audit trail
- **Cross-Raid Persistence** — SR+ accumulation tracked natively across raids

### Phase 4 Features
- **Loot Council Mode** — Hybrid SR+/Council voting system
- **Custom Rules Engine** — GUI for defining guild-specific loot rules
- **External Integration** — Discord bot, guild website export

---

## Compatibility Notes

### RollFor Coexistence

During transition, LootManager can coexist with RollFor:

1. **Read-Only Access** — LootManager reads `RollForCharDb.softres.data` but does not write to it
2. **Separate UI** — LootManager uses its own loot window; RollFor's window can be disabled
3. **Event Sharing** — Both addons register for `LOOT_OPENED`; LootManager should be loaded after RollFor
4. **Migration Path** — Once LootManager is stable, RollFor can be disabled entirely

### WoW 1.12 API Constraints

All code must comply with OG-RaidHelper Design Philosophy constraints:
- Lua 5.0/5.1 syntax (no `#`, no `%`, no `string.gmatch`, no `continue`)
- Event handlers use implicit globals (`this`, `event`, `arg1`)
- All UI via OGST library
- ChatThrottleLib for raid announcements
- SVM for all data persistence

---

## Unified Development Plan

This plan covers the ordered implementation of both LootManager and the SR+ Validation update. Phases are sequenced so that each builds on the previous — no phase requires code that hasn't been written yet.

### Prerequisites (Before Phase 1)

- [ ] **EncounterAdmin.lua in TOC** — Confirm EncounterAdmin.lua is loaded (currently missing from TOC)
- [ ] **V2 Schema Update** — Add `lootManager` and `srValidation` v2 paths to `! V2 Schema Specification.md`
- [ ] **OGST Components Audit** — Verify OGST has all components needed (scroll lists, popup dialogs, tab frames, timer bars). Add missing components to OGST first per Design Philosophy

---

### Phase 1: Data Foundation (Week 1)

**Goal:** Build the data layer with no UI — import, parse, store, and read SR+ data.

| Step | File(s) | Deliverables | Depends On |
|------|---------|-------------|------------|
| 1.1 | `LootManData.lua` | SVM schema initialization (`lootManager.*`), `EnsureSV()` | SVM |
| 1.2 | `LootManData.lua` | CSV parser (`ParseCSV()`), field mapping, type validation | 1.1 |
| 1.3 | `LootManData.lua` | Base64/JSON importer (reuse RollFor decode logic or port it) | 1.1 |
| 1.4 | `LootManData.lua` | Unified import pipeline (`ImportSRData()`) — normalize both formats to common `importedSR` structure | 1.2, 1.3 |
| 1.5 | `LootManData.lua` | `GetImportedSR()`, `GetSRForItem()`, `IsHardReserved()` read functions | 1.4 |
| 1.6 | `OG-RaidHelper.toc` | Add `LootManData.lua` to Phase 5 load order | — |

**Documentation:**
- [ ] Update `! V2 Schema Specification.md` with `lootManager` schema
- [ ] Update `! OG-RaidHelper API.md` with `OGRH.LootMan.*` data functions

**Tests:**
- CSV parse: valid, empty fields, malformed, quoted fields
- Base64 import: valid, corrupt, empty
- Unified format consistency: CSV import == Base64 import for same data
- SVM round-trip: write → reload → read

---

### Phase 2: SR+ Validation Engine (Week 1-2)

**Goal:** Implement the validation rules engine and pre-raid report generator. No UI yet.

| Step | File(s) | Deliverables | Depends On |
|------|---------|-------------|------------|
| 2.1 | `SRValidation.lua` | Schema migration (`MigrateSchema()` v1 → v2) | SVM |
| 2.2 | `SRValidation.lua` | Validation rules: `ValidateIncrement()`, `ValidateItemLimit()`, `ValidateNoItemSwitch()` | 2.1 |
| 2.3 | `SRValidation.lua` | Roster rules: `ValidateRosterMatch()`, `ValidateSplitRaid()` | 2.1, Roster.lua |
| 2.4 | `SRValidation.lua` | `ValidateAll()` — batch validation, generate `preRaidReport` | 2.2, 2.3, Phase 1 |
| 2.5 | `SRValidation.lua` | `GetValidationStatus()` — fast path for LootManager | 2.4 |
| 2.6 | `SRValidation.lua` | `GetItemValidation()`, `GetLastRecordForItem()` — per-item API | 2.4 |
| 2.7 | `SRValidation.lua` | `GetLegacyRollForData()` — backward compat bridge | 2.1 |
| 2.8 | `SRValidation.lua` | `SaveValidation()` update — per-item detail, audit reason | 2.1 |

**Documentation:**
- [ ] Update `! V2 Schema Specification.md` with `srValidation` v2 schema
- [ ] Update `! OG-RaidHelper API.md` with new/updated SRValidation functions

**Tests:**
- All validation rules (see SR+ Validation.md test matrix)
- `ValidateAll()` with mixed valid/warning/error players
- Schema migration from v1 records
- Legacy RollFor fallback

---

### Phase 3: Equip Rules Engine (Week 2)

**Goal:** Build the configurable rules engine for sanity checks. No UI yet.

| Step | File(s) | Deliverables | Depends On |
|------|---------|-------------|------------|
| 3.1 | `LootManRules.lua` | Default weapon/armor proficiency tables | — |
| 3.2 | `LootManRules.lua` | Tooltip scanner (`GetItemEquipInfo()`) | — |
| 3.3 | `LootManRules.lua` | `CanPlayerEquip(playerName, itemLink)` | 3.1, 3.2 |
| 3.4 | `LootManRules.lua` | Non-tradable token registry (`IsNonTradableToken()`) | — |
| 3.5 | `LootManRules.lua` | Roll hierarchy definition and classification (`ClassifyRoll()`) | — |
| 3.6 | `LootManRules.lua` | Custom rule loading from SVM (`GetEquipRules()`) | 3.1, SVM |
| 3.7 | `OG-RaidHelper.toc` | Add `LootManRules.lua` to Phase 5 (before LootManData) | — |

**Documentation:**
- [ ] Update `! OG-RaidHelper API.md` with `OGRH.LootMan.Rules.*` functions

**Tests:**
- All class × weapon type combinations
- All class × armor type combinations
- Token ID lookups
- Roll classification for each threshold
- Custom rule override via SVM

---

### Phase 4: Core Orchestrator (Week 2-3)

**Goal:** Build the loot distribution core — event handling, roll tracking, award pipeline.

| Step | File(s) | Deliverables | Depends On |
|------|---------|-------------|------------|
| 4.1 | `LootMan.lua` | Module initialization, event registration (`LOOT_OPENED`, `LOOT_CLOSED`, `LOOT_SLOT_CLEARED`, `CHAT_MSG_SYSTEM`) | Phase 1, 3 |
| 4.2 | `LootMan.lua` | Loot opened handler — parse items, annotate HR/SR, build pending list | 4.1 |
| 4.3 | `LootMan.lua` | Roll detection and tracking (`OnRoll()`, `RecordRoll()`, `ClassifyRoll()`) | 4.1, 3.5 |
| 4.4 | `LootMan.lua` | Roll validation against roster (`ValidateRoll()`, `ResolveAmbiguousRoll()`) | 4.3, Roster |
| 4.5 | `LootMan.lua` | Award pipeline with sanity checks (`AwardItem()`) | 4.2, 3.3, 3.4 |
| 4.6 | `LootMan.lua` | Tradability tracking (`StartTradeTimer()`, expiry scheduling) | 4.5 |
| 4.7 | `LootMan.lua` | Admin Encounter integration (`GetAdminSettings()`, auto-switch) | 4.1, EncounterAdmin |
| 4.8 | `LootMan.lua` | Pre-raid validation trigger (`ValidatePreRaid()`) | Phase 2 |
| 4.9 | `LootMan.lua` | Slash commands (`/lootman`, `/ogrhlm`) | 4.1 |
| 4.10 | `LootMan.lua` | ChatThrottleLib integration for raid announcements | 4.3, 4.5 |
| 4.11 | `OG-RaidHelper.toc` | Add `LootMan.lua` to Phase 5 (after LootManData) | — |

**Documentation:**
- [ ] Update `! OG-RaidHelper API.md` with `OGRH.LootMan.*` orchestrator functions

**Tests:**
- Full loot opened → roll → award pipeline (mock LOOT events)
- Roll detection from CHAT_MSG_SYSTEM patterns
- Sanity check blocking (sword → priest)
- Non-tradable token confirmation
- Trade timer countdown
- Auto-switch ML ↔ Group loot

---

### Phase 5: Import UI (Week 3)

**Goal:** Build the import dialog so officers can paste CSV/Base64 data.

| Step | File(s) | Deliverables | Depends On |
|------|---------|-------------|------------|
| 5.1 | `LootManUI.lua` | Import dialog frame (OGST `CreateStandardWindow`) | OGST, Phase 1 |
| 5.2 | `LootManUI.lua` | Radio buttons: RaidRes.top Base64 / CSV source selection | 5.1 |
| 5.3 | `LootManUI.lua` | Scrolling text box for paste input | 5.1 |
| 5.4 | `LootManUI.lua` | Import button → call `LootMan.ImportBase64()` or `ImportCSV()` | 5.1, Phase 1 |
| 5.5 | `LootManUI.lua` | Import status display (player count, warnings) | 5.4 |
| 5.6 | `LootManUI.lua` | "Load from SR Link field" button (reads Admin Encounter Role 7) | 5.4, EncounterAdmin |

**Documentation:**
- [ ] Add UI screenshots/mockups to this document

**Tests:**
- Paste base64 → Import → Status display
- Paste CSV → Import → Status display
- Load from SR Link field → Import
- Empty paste → Error message
- Corrupt data → Error message

---

### Phase 6: SR+ Validation UI (Week 3-4)

**Goal:** Build the pre-raid summary and player detail panels.

| Step | File(s) | Deliverables | Depends On |
|------|---------|-------------|------------|
| 6.1 | `SRValidation.lua` + UI | Pre-Raid Summary Panel (OGST window with error/warning/valid counts) | Phase 2, OGST |
| 6.2 | `SRValidation.lua` + UI | Error/Warning player list (scrollable, clickable) | 6.1 |
| 6.3 | `SRValidation.lua` + UI | Player Detail Panel (per-item SR+, history, roster info) | 6.2 |
| 6.4 | `SRValidation.lua` + UI | SR+ Edit Dialog (updated with audit reason field) | 6.3 |
| 6.5 | `SRValidation.lua` + UI | "Validate All Passed" batch action | 6.2 |
| 6.6 | `SRValidation.lua` | Auto-show pre-raid report after import (config toggle) | 6.1, Phase 5 |

**Documentation:**
- [ ] Update SR+ Validation.md with final UI screenshots

**Tests:**
- Pre-raid report display accuracy
- Click player → detail panel loads
- Edit SR+ → audit record created
- Validate All Passed → batch updates
- Auto-show on import

---

### Phase 7: Loot Distribution UI (Week 4-5)

**Goal:** Build the main loot distribution window that replaces RollFor's popup.

| Step | File(s) | Deliverables | Depends On |
|------|---------|-------------|------------|
| 7.1 | `LootManUI.lua` | Main loot distribution window frame | OGST, Phase 4 |
| 7.2 | `LootManUI.lua` | Item display header (icon, name, quality, source, tradability badge) | 7.1 |
| 7.3 | `LootManUI.lua` | SR+ eligible player list (sorted, with validation icons) | 7.1, Phase 2 |
| 7.4 | `LootManUI.lua` | Roll control buttons (Start MS/OS/TMOG/Raid Roll) | 7.1, Phase 4 |
| 7.5 | `LootManUI.lua` | Award controls (Select Player, Manual Award, Send to DE) | 7.1, Phase 4 |
| 7.6 | `LootManUI.lua` | Sanity check warning dialog (equip check popup) | 7.5, Phase 3 |
| 7.7 | `LootManUI.lua` | Non-tradable token confirmation dialog | 7.5, Phase 3 |
| 7.8 | `LootManUI.lua` | Trade timer display (per-item countdown bars) | 7.1, Phase 4 |
| 7.9 | `LootManUI.lua` | Disenchant prompt (pull DE name from Admin Encounter) | 7.5, EncounterAdmin |
| 7.10 | `OG-RaidHelper.toc` | Add `LootManUI.lua` to Phase 5 (after LootMan.lua) | — |

**Documentation:**
- [ ] Update `! OG-RaidHelper API.md` with UI functions
- [ ] Add final UI screenshots to LootMan.md

**Tests:**
- Full boss kill → loot window → SR roll → award flow
- Sanity check popup appears for incompatible items
- Non-tradable token prompt appears
- Trade timer counts down and warns at 2 min
- DE prompt when no rollers
- Multiple items in same loot window

---

### Phase 8: Integration Testing & Polish (Week 5-6)

**Goal:** End-to-end testing, edge cases, performance, and documentation finalization.

| Step | File(s) | Deliverables | Depends On |
|------|---------|-------------|------------|
| 8.1 | All | End-to-end test: Import → Validate → Raid → Loot → Award | All phases |
| 8.2 | All | Edge case testing (see test matrices in both docs) | All phases |
| 8.3 | All | RollFor coexistence testing (both loaded simultaneously) | All phases |
| 8.4 | All | Performance testing (40-player raid, 30+ items per session) | All phases |
| 8.5 | All | OGST compliance audit (all UI uses OGST components) | All phases |
| 8.6 | All | Design Philosophy compliance audit (Lua 5.0, event handlers, etc.) | All phases |
| 8.7 | Documentation | Finalize `! OG-RaidHelper API.md` with all new functions | All phases |
| 8.8 | Documentation | Finalize `! V2 Schema Specification.md` with final schema | All phases |
| 8.9 | Documentation | Update `! SVM-Quick-Reference.md` with new paths | All phases |
| 8.10 | Documentation | Create user guide for officers (quick-start, import, validation) | All phases |

---

### Phase Summary Timeline

```
Week 1:  Phase 1 (Data Foundation) + Phase 2 Start (Validation Engine)
Week 2:  Phase 2 Complete + Phase 3 (Rules Engine) + Phase 4 Start (Orchestrator)
Week 3:  Phase 4 Complete + Phase 5 (Import UI) + Phase 6 Start (Validation UI)
Week 4:  Phase 6 Complete + Phase 7 Start (Loot Distribution UI)
Week 5:  Phase 7 Complete + Phase 8 Start (Integration & Polish)
Week 6:  Phase 8 Complete → Release Candidate
```

### Dependency Graph

```
Phase 1 (Data) ──────────────────┐
       │                         │
       ├── Phase 2 (Validation) ─┤
       │         │               │
       │         ├── Phase 6 (Validation UI)
       │         │               │
       ├── Phase 3 (Rules) ──────┤
       │         │               │
       │         └── Phase 4 (Orchestrator) ──── Phase 7 (Loot UI)
       │                   │                         │
       └── Phase 5 (Import UI)                       │
                                                     │
                                     Phase 8 (Integration & Polish)
```

### Documentation Checkpoints

Each phase must update the following before moving to the next:

1. **API Documentation** (`! OG-RaidHelper API.md`) — All new public functions documented
2. **Schema Specification** (`! V2 Schema Specification.md`) — All new SVM paths documented
3. **Design Documents** (LootMan.md, SR+ Validation.md) — Update if implementation deviates from spec
4. **Inline Code Comments** — Module headers, function signatures, complex logic blocks

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | February 15, 2026 | Initial design document |

---

## References

- [SR+ Validation Design Document](SR+%20Validation.md)
- [SR+ Master Loot & Validation Design](SR+%20Master%20Loot%20%26%20Validation%20Design.md)
- [BaT Loot Rules](BaT%20Loot%20Rules.md)
- [Admin Encounter Specification](EncounterAdmin.md)
- [OG-RaidHelper Design Philosophy](../Spec%20Docs/!%20OG-RaidHelper%20Design%20Philososphy.md)
- [SVM API Documentation](../Spec%20Docs/!%20SVM-API-Documentation.md)
- [OG-RaidHelper API](../Spec%20Docs/!%20OG-RaidHelper%20API.md)
- [V2 Schema Specification](../Spec%20Docs/!%20V2%20Schema%20Specification.md)

---

**END OF DOCUMENT**
