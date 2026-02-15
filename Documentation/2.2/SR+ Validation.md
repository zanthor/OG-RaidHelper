# SR+ Validation System — Updated Design Document

**Version:** 2.0 (LootManager Integration)  
**Module:** SRValidation.lua  
**Location:** `_Administration/SRValidation.lua`  
**Target Release:** 2.1  
**Last Updated:** February 15, 2026  
**Status:** Design Phase  
**Dependencies:** LootMan.lua, Invites.lua, SVM, OGST, RollFor (optional/transitional)

---

## Executive Summary

The SR+ Validation system is being redesigned to serve as the pre-raid and at-loot validation engine for LootManager. The current `SRValidation.lua` validates SR+ data after import from RollFor; the updated version will:

- **Decouple from RollFor** — Accept data from LootManager's import engine (CSV + Base64) rather than reading `RollForCharDb` directly
- **Pre-Raid Validation** — Surface all SR+ conflicts, discrepancies, and warnings before the raid starts
- **At-Loot Validation** — Provide instant validation status when items drop (no manual checking required)
- **Roster Cross-Reference** — Validate SR+ entries against guild roster (Main/Alt/Spec/Rank)
- **Historical Tracking** — Maintain per-player validation history across raids
- **Integration API** — Expose clean functions for LootManager to call during loot distribution

---

## Problem Statement

### Current SRValidation.lua Limitations

1. **Hard RollFor Dependency** — Reads directly from `RollForCharDb.softres.data` and calls `RollFor.SoftRes.decode()` / `RollFor.SoftResDataTransformer.transform()`
2. **Reactive Only** — Officers must open the SR Validation window manually; no pre-raid prompt
3. **Per-Player Manual Review** — Each player must be clicked and validated individually
4. **No Roster Awareness** — Cannot detect Main/Alt conflicts or spec mismatches
5. **Weak History** — Only stores "last validation" per player; no per-item, per-raid tracking
6. **No LootManager Integration** — Standalone window with no hooks into the loot distribution pipeline
7. **Single-Source Data** — Only reads RollFor's decoded data; no CSV support

### Requirements for Updated System

| Requirement | Current | Updated |
|-------------|---------|---------|
| Data Source | RollFor only | LootManager import (CSV + Base64) |
| Validation Trigger | Manual window open | Auto on import + pre-raid prompt |
| Validation Scope | Per-player, one-at-a-time | Batch all players, surface summary |
| Roster Integration | None | Check Main/Alt, Spec, Rank |
| SR+ Rules Enforcement | +10/week only | Full BaT rules (limits, tiers, resets) |
| LootManager Integration | None | API for at-loot validation |
| History | Last validation only | Per-player, per-item, per-raid |
| Conflict Detection | None | Pre-raid conflict report |

---

## Architecture

### Module Structure

```
SR+ Validation System
│
├── SRValidation.lua (Core Validation Engine)
│   ├── Data Ingestion (accept data from LootManager or legacy RollFor)
│   ├── Validation Rules Engine
│   │   ├── SR+ Increment Rule (max +10 per week)
│   │   ├── SR+ Limit Rule (2x for 40-man, 1x for 20-man)
│   │   ├── SR+ Reset Rule (different item = reset to 0)
│   │   ├── SR+ Win Rule (won item = reset to 0)
│   │   ├── SR+ Threshold Rule (>=50 = +1 tier for ALL)
│   │   └── Custom Rules (guild-specific hooks)
│   │
│   ├── Roster Cross-Reference
│   │   ├── Main/Alt Detection
│   │   ├── Spec Validation
│   │   ├── Rank Validation
│   │   ├── Attendance Verification
│   │   └── Split Raid Detection
│   │
│   ├── Conflict Detection
│   │   ├── Duplicate SR (same player, same item, different values)
│   │   ├── Missing Players (SR'd but not in raid)
│   │   ├── Unknown Players (not in guild roster)
│   │   ├── Item Mismatch (SR'd item doesn't exist or wrong ID)
│   │   └── SR+ Anomaly (value higher than expected for weeks attended)
│   │
│   ├── Validation API (for LootManager)
│   │   ├── ValidateAll() → full report
│   │   ├── ValidatePlayer(name) → player report
│   │   ├── GetValidationStatus(name, srPlus) → instant status
│   │   ├── GetItemValidation(itemId) → item-specific report
│   │   └── GetPreRaidReport() → summary for raid leader
│   │
│   └── History Tracking
│       ├── Per-Player Records
│       ├── Per-Item Records
│       └── Per-Raid Snapshots
│
└── SRValidationUI.lua (User Interface — uses OGST)
    ├── Pre-Raid Summary Panel (docked or floating)
    ├── Player Detail Panel (validation history)
    ├── Conflict Resolution Panel
    └── SR+ Edit Dialog (manual corrections)
```

### Integration Architecture

```
┌────────────────┐     ┌──────────────────┐     ┌────────────────┐
│  LootManager   │────→│  SRValidation    │←────│  Roster/       │
│  (Import Data) │     │  (Validate)      │     │  Invites       │
└────────────────┘     └──────────────────┘     └────────────────┘
        │                      │                        │
        │                      ▼                        │
        │              ┌──────────────────┐             │
        │              │  SVM (History)   │             │
        │              │  srValidation.*  │             │
        │              └──────────────────┘             │
        │                      │                        │
        ▼                      ▼                        │
┌────────────────┐     ┌──────────────────┐             │
│  LootManUI     │←────│  SRValidationUI  │             │
│  (❌/✓/⚠ icons)│     │  (Detail Panel)  │             │
└────────────────┘     └──────────────────┘             │
```

---

## Data Schema (SVM)

### Updated SRValidation Schema

```lua
OGRH_SV.v2.srValidation = {
    schemaVersion = 2,  -- Upgraded from v1
    
    -- Validation Records (per-player history)
    records = {
        ["Tankadin"] = {
            [1] = {
                timestamp = 1739577600,
                instance = "Naxxramas",
                raidId = "NAXX-20260215",
                
                -- Per-item validation at this point
                items = {
                    [1] = {
                        itemId = 22349,
                        itemName = "Desecrated Breastplate",
                        srPlus = 40,
                        previousSRPlus = 30,
                        validationStatus = "VALID",  -- VALID, WARNING, ERROR
                        validationReason = "Increment +10 from last raid",
                    },
                },
                
                -- Player metadata at validation time
                playerClass = "PALADIN",
                isMain = true,
                mainSpec = "Protection",
                raidSize = 40,
                validatedBy = "RaidLeader",
                source = "raidres_csv",  -- Import source
            },
            -- ... more records (newest first, max 20 per player)
        },
    },
    
    -- Pre-Raid Report (generated on import/validate)
    preRaidReport = {
        generated = 1739577600,
        instance = "Naxxramas",
        raidSize = 40,
        
        -- Summary counts
        totalPlayers = 24,
        validPlayers = 20,
        warningPlayers = 3,
        errorPlayers = 1,
        
        -- Per-player status
        players = {
            ["Tankadin"] = {
                status = "VALID",
                srPlus = 40,
                items = { {itemId = 22349, srPlus = 40} },
                class = "PALADIN",
                isMain = true,
                rosterMatch = true,
            },
            ["UnknownPug"] = {
                status = "WARNING",
                srPlus = 10,
                items = { {itemId = 19346, srPlus = 10} },
                class = "ROGUE",
                isMain = nil,   -- Unknown
                rosterMatch = false,
                warnings = {"Player not found in guild roster"},
            },
            ["Cheater"] = {
                status = "ERROR",
                srPlus = 80,
                items = { {itemId = 17076, srPlus = 80} },
                class = "WARRIOR",
                isMain = true,
                rosterMatch = true,
                errors = {"SR+ 80 exceeds expected maximum (50 for 5 weeks)"},
            },
        },
        
        -- Conflicts detected
        conflicts = {
            [1] = {
                type = "SR_LIMIT_EXCEEDED",
                player = "GreedyPlayer",
                detail = "3 SR items in 40-man raid (max 2)",
                severity = "ERROR",
            },
            [2] = {
                type = "PLAYER_NOT_IN_RAID",
                player = "AbsentPlayer",
                detail = "SR'd but not in current raid roster",
                severity = "WARNING",
            },
            [3] = {
                type = "SPLIT_RAID_CONFLICT",
                player = "AltChar",
                detail = "Main 'MainChar' also has SR entries",
                severity = "WARNING",
            },
        },
    },
    
    -- Configuration
    config = {
        autoValidateOnImport = true,    -- Run validation after every import
        showPreRaidPrompt = true,       -- Show summary before first pull
        maxRecordsPerPlayer = 20,       -- History depth
        expectedMaxWeeks = 10,          -- Max reasonable weeks of SR+ accumulation
        warningThreshold = "WARNING",   -- Show in LootMan UI: "WARNING" or "ERROR" only
    },
}
```

### Migration from v1 Schema

```lua
function OGRH.SRValidation.MigrateSchema()
    local srValidation = OGRH.SVM.GetPath("srValidation")
    if not srValidation then return end
    
    if not srValidation.schemaVersion or srValidation.schemaVersion < 2 then
        -- v1 records are flat: records[playerName][N] = { timestamp, srPlus, instance, ... }
        -- v2 records add per-item detail and roster metadata
        
        local oldRecords = srValidation.records or {}
        local newRecords = {}
        
        for playerName, records in pairs(oldRecords) do
            newRecords[playerName] = {}
            for i = 1, table.getn(records) do
                local old = records[i]
                table.insert(newRecords[playerName], {
                    timestamp = old.timestamp,
                    instance = old.instance or "Unknown",
                    raidId = old.raidId or "",
                    items = old.items or {
                        [1] = {
                            itemId = old.itemId or 0,
                            itemName = old.itemName or "Unknown",
                            srPlus = old.srPlus or 0,
                            previousSRPlus = old.previousSRPlus or 0,
                            validationStatus = old.status or "VALID",
                            validationReason = "",
                        },
                    },
                    playerClass = old.playerClass or "",
                    isMain = true,
                    mainSpec = nil,
                    raidSize = 40,
                    validatedBy = old.validatedBy or "auto",
                    source = "rollfor",
                })
            end
        end
        
        srValidation.records = newRecords
        srValidation.schemaVersion = 2
        srValidation.preRaidReport = nil
        srValidation.config = srValidation.config or {}
        srValidation.config.autoValidateOnImport = true
        srValidation.config.showPreRaidPrompt = true
        srValidation.config.maxRecordsPerPlayer = 20
        srValidation.config.expectedMaxWeeks = 10
        srValidation.config.warningThreshold = "WARNING"
        
        OGRH.SVM.SetPath("srValidation", srValidation)
        OGRH.Msg("|cffcc99ff[RH-SRValidation]|r Migrated to schema v2")
    end
end
```

---

## Validation Rules Engine

### Rule 1: SR+ Increment Validation

**Rule:** SR+ increases by exactly +10 per week for the same item.

```lua
function OGRH.SRValidation.ValidateIncrement(playerName, itemId, currentSRPlus)
    local lastRecord = OGRH.SRValidation.GetLastRecordForItem(playerName, itemId)
    
    if not lastRecord then
        -- New item, SR+ should be 0 or first-week value
        if currentSRPlus > 10 then
            -- Could be legitimate if player has historical SR+ from before tracking
            return "WARNING", "New item with SR+ " .. currentSRPlus .. " (no prior record)"
        end
        return "VALID", "New SR entry"
    end
    
    local expectedSRPlus = lastRecord.srPlus + 10
    
    if currentSRPlus == expectedSRPlus then
        return "VALID", "Expected increment +10"
    elseif currentSRPlus == lastRecord.srPlus then
        -- Same value (missed a raid, SR+ maintained)
        return "VALID", "SR+ maintained (missed raid)"
    elseif currentSRPlus == 0 then
        -- Reset (won item or switched)
        return "VALID", "SR+ reset (item won or switched)"
    elseif currentSRPlus > expectedSRPlus then
        local diff = currentSRPlus - lastRecord.srPlus
        return "ERROR", "SR+ increased by " .. diff .. " (expected max +10)"
    elseif currentSRPlus < lastRecord.srPlus and currentSRPlus ~= 0 then
        return "WARNING", "SR+ decreased from " .. lastRecord.srPlus .. " to " .. currentSRPlus
    else
        return "WARNING", "Unexpected SR+ value: " .. currentSRPlus .. " (expected " .. expectedSRPlus .. ")"
    end
end
```

### Rule 2: SR+ Limit Validation

**Rule:** Max 2 SR items in 40-man, max 1 in 20-man.

```lua
function OGRH.SRValidation.ValidateItemLimit(playerName, raidSize)
    local importedSR = OGRH.LootMan.GetImportedSR()
    if not importedSR or not importedSR.playerSummary then return "VALID", "" end
    
    local summary = importedSR.playerSummary[playerName]
    if not summary then return "VALID", "Player has no SR entries" end
    
    local itemCount = table.getn(summary.items)
    local maxItems = (raidSize >= 40) and 2 or 1
    
    if itemCount > maxItems then
        return "ERROR", itemCount .. " SR items in " .. raidSize .. "-man raid (max " .. maxItems .. ")"
    end
    
    return "VALID", itemCount .. "/" .. maxItems .. " SR slots used"
end
```

### Rule 3: SR+ Reset Detection

**Rule:** Switching items resets SR+ to 0.

```lua
function OGRH.SRValidation.ValidateNoItemSwitch(playerName, currentItems)
    local lastRecord = OGRH.SRValidation.GetLastRecord(playerName)
    if not lastRecord or not lastRecord.items then return "VALID", "" end
    
    -- Compare current items to last validated items
    for i = 1, table.getn(currentItems) do
        local currentItem = currentItems[i]
        local foundInPrevious = false
        
        for j = 1, table.getn(lastRecord.items) do
            if lastRecord.items[j].itemId == currentItem.itemId then
                foundInPrevious = true
                break
            end
        end
        
        if not foundInPrevious and currentItem.srPlus > 0 then
            return "WARNING", "New item " .. (currentItem.itemName or currentItem.itemId) .. 
                " with SR+ " .. currentItem.srPlus .. " (should be 0 if switched)"
        end
    end
    
    return "VALID", "Items consistent with previous raid"
end
```

### Rule 4: Split Raid Validation

**Rule:** In split play (Part-Time Main, Part-Time Alt), 1 SR+ per character, not exceeding raid limits.

```lua
function OGRH.SRValidation.ValidateSplitRaid(playerName)
    local roster = OGRH.LootMan.GetRosterEntry(playerName)
    if not roster then return "VALID", "" end
    
    if roster.isAlt and roster.mainName then
        -- Check if main also has SR entries in this import
        local importedSR = OGRH.LootMan.GetImportedSR()
        if importedSR and importedSR.playerSummary then
            local mainSummary = importedSR.playerSummary[roster.mainName]
            local altSummary = importedSR.playerSummary[playerName]
            
            if mainSummary and altSummary then
                local totalItems = table.getn(mainSummary.items) + table.getn(altSummary.items)
                local raidSize = OGRH.LootMan.GetConfig().raidSize or 40
                local maxItems = (raidSize >= 40) and 2 or 1
                
                if totalItems > maxItems then
                    return "WARNING", playerName .. " (alt of " .. roster.mainName .. 
                        ") combined SR count: " .. totalItems .. " (max " .. maxItems .. " per rules)"
                end
            end
        end
    end
    
    return "VALID", ""
end
```

### Rule 5: Roster Cross-Reference

```lua
function OGRH.SRValidation.ValidateRosterMatch(playerName, importedClass)
    -- Check guild roster
    local roster = OGRH.LootMan.GetRosterEntry(playerName)
    
    if not roster or not roster.rank then
        return "WARNING", "Player not found in guild roster (PUG?)"
    end
    
    -- Validate class matches
    if importedClass and roster.class then
        local normalizedImported = string.upper(importedClass)
        if normalizedImported ~= roster.class then
            return "ERROR", "Class mismatch: imported as " .. importedClass .. 
                " but roster says " .. roster.class
        end
    end
    
    return "VALID", "Roster match confirmed"
end
```

---

## Validation API

### `OGRH.SRValidation.ValidateAll()`

Run full validation on all imported SR+ data. Generates the pre-raid report.

**Returns:** `table` — Pre-raid report (stored in `srValidation.preRaidReport`)

**Example:**
```lua
local report = OGRH.SRValidation.ValidateAll()
OGRH.Msg("|cffcc99ff[RH-SRValidation]|r Pre-Raid Report:")
OGRH.Msg("  Valid: " .. report.validPlayers)
OGRH.Msg("  Warnings: " .. report.warningPlayers)
OGRH.Msg("  Errors: " .. report.errorPlayers)
```

**Implementation:**
```lua
function OGRH.SRValidation.ValidateAll()
    local importedSR = OGRH.LootMan.GetImportedSR()
    if not importedSR then
        -- Fallback: try legacy RollFor data
        importedSR = OGRH.SRValidation.GetLegacyRollForData()
    end
    
    if not importedSR or not importedSR.playerSummary then
        return { totalPlayers = 0, validPlayers = 0, warningPlayers = 0, errorPlayers = 0, players = {}, conflicts = {} }
    end
    
    local raidSize = OGRH.LootMan.GetConfig() and OGRH.LootMan.GetConfig().raidSize or 40
    
    local report = {
        generated = GetTime(),
        instance = importedSR.instance or "Unknown",
        raidSize = raidSize,
        totalPlayers = 0,
        validPlayers = 0,
        warningPlayers = 0,
        errorPlayers = 0,
        players = {},
        conflicts = {},
    }
    
    for playerName, summary in pairs(importedSR.playerSummary) do
        report.totalPlayers = report.totalPlayers + 1
        
        local playerReport = {
            status = "VALID",
            srPlus = summary.totalSRPlus,
            items = summary.items,
            class = summary.class,
            isMain = nil,
            rosterMatch = false,
            warnings = {},
            errors = {},
        }
        
        -- Run all validation rules
        local rules = {
            { OGRH.SRValidation.ValidateRosterMatch, { playerName, summary.class } },
            { OGRH.SRValidation.ValidateItemLimit, { playerName, raidSize } },
            { OGRH.SRValidation.ValidateSplitRaid, { playerName } },
        }
        
        for _, rule in ipairs(rules) do
            local fn = rule[1]
            local args = rule[2]
            local status, reason = fn(unpack(args))
            
            if status == "ERROR" then
                playerReport.status = "ERROR"
                table.insert(playerReport.errors, reason)
            elseif status == "WARNING" and playerReport.status ~= "ERROR" then
                playerReport.status = "WARNING"
                table.insert(playerReport.warnings, reason)
            end
        end
        
        -- Per-item validation
        for _, item in ipairs(summary.items) do
            local incStatus, incReason = OGRH.SRValidation.ValidateIncrement(
                playerName, item.itemId, item.srPlus
            )
            
            if incStatus == "ERROR" then
                playerReport.status = "ERROR"
                table.insert(playerReport.errors, incReason)
            elseif incStatus == "WARNING" and playerReport.status ~= "ERROR" then
                playerReport.status = "WARNING"
                table.insert(playerReport.warnings, incReason)
            end
        end
        
        -- Switch detection
        local switchStatus, switchReason = OGRH.SRValidation.ValidateNoItemSwitch(
            playerName, summary.items
        )
        if switchStatus == "ERROR" then
            playerReport.status = "ERROR"
            table.insert(playerReport.errors, switchReason)
        elseif switchStatus == "WARNING" and playerReport.status ~= "ERROR" then
            playerReport.status = "WARNING"
            table.insert(playerReport.warnings, switchReason)
        end
        
        -- Roster enrichment
        local roster = OGRH.LootMan.GetRosterEntry(playerName)
        if roster then
            playerReport.isMain = roster.isMain
            playerReport.rosterMatch = true
        end
        
        -- Count by status
        if playerReport.status == "VALID" then
            report.validPlayers = report.validPlayers + 1
        elseif playerReport.status == "WARNING" then
            report.warningPlayers = report.warningPlayers + 1
        elseif playerReport.status == "ERROR" then
            report.errorPlayers = report.errorPlayers + 1
        end
        
        report.players[playerName] = playerReport
    end
    
    -- Store report
    OGRH.SVM.SetPath("srValidation.preRaidReport", report)
    
    return report
end
```

---

### `OGRH.SRValidation.ValidatePlayer(playerName)`

Validate a single player's SR+ data.

**Parameters:**
- `playerName` (string)

**Returns:** `table` — Player validation report

**Example:**
```lua
local result = OGRH.SRValidation.ValidatePlayer("Tankadin")
if result.status == "ERROR" then
    for _, err in ipairs(result.errors) do
        OGRH.Msg("|cffff0000[RH-SRValidation]|r " .. playerName .. ": " .. err)
    end
end
```

---

### `OGRH.SRValidation.GetValidationStatus(playerName, srPlus)`

Quick validation check for use during loot distribution. Returns a simple status without running full validation.

**Parameters:**
- `playerName` (string)
- `srPlus` (number) — Current SR+ value

**Returns:** `string, string` — Status ("VALID"/"WARNING"/"ERROR"), Reason

**Example:**
```lua
-- Called by LootManager when displaying eligible SR rollers
local status, reason = OGRH.SRValidation.GetValidationStatus("Tankadin", 40)
-- Returns: "VALID", "Validated in pre-raid check"
```

**Implementation:**
```lua
function OGRH.SRValidation.GetValidationStatus(playerName, srPlus)
    -- Check pre-raid report first (fast path)
    local report = OGRH.SVM.GetPath("srValidation.preRaidReport")
    if report and report.players and report.players[playerName] then
        local playerReport = report.players[playerName]
        return playerReport.status, 
            playerReport.status == "VALID" and "Validated in pre-raid check" or
            (playerReport.errors and playerReport.errors[1]) or
            (playerReport.warnings and playerReport.warnings[1]) or "Unknown"
    end
    
    -- No pre-raid report, do quick validation
    local lastRecord = OGRH.SRValidation.GetLastRecord(playerName)
    if not lastRecord then
        if srPlus == 0 then
            return "VALID", "New player, no prior history"
        else
            return "WARNING", "No validation history for this player"
        end
    end
    
    -- Quick increment check
    local lastSRPlus = 0
    if lastRecord.items and table.getn(lastRecord.items) > 0 then
        lastSRPlus = lastRecord.items[1].srPlus or 0
    end
    
    local diff = srPlus - lastSRPlus
    if diff == 10 or diff == 0 or srPlus == 0 then
        return "VALID", "SR+ consistent with history"
    elseif diff > 10 then
        return "ERROR", "SR+ jumped by " .. diff .. " (expected max +10)"
    else
        return "WARNING", "Unexpected SR+ change: " .. lastSRPlus .. " → " .. srPlus
    end
end
```

---

### `OGRH.SRValidation.GetItemValidation(itemId)`

Get validation info for all players who SR'd a specific item.

**Parameters:**
- `itemId` (number)

**Returns:** `table[]` — Array of `{playerName, srPlus, status, reason}`

**Example:**
```lua
-- Called by LootManager when item drops
local validators = OGRH.SRValidation.GetItemValidation(22349)
for _, v in ipairs(validators) do
    -- v.playerName, v.srPlus, v.status, v.reason
end
```

---

### `OGRH.SRValidation.SaveValidation(playerName, items, instance)`

Save a validation record after officer review.

**Parameters:**
- `playerName` (string)
- `items` (table[]) — Array of `{itemId, itemName, srPlus, previousSRPlus}`
- `instance` (string) — Raid instance name

**Returns:** `boolean` — Success status

---

### `OGRH.SRValidation.GetPreRaidReport()`

Get the cached pre-raid report (or generate if stale).

**Returns:** `table` — Pre-raid report

---

### `OGRH.SRValidation.GetLastRecord(playerName)`

Get the most recent validation record for a player.

**Parameters:**
- `playerName` (string)

**Returns:** `table|nil` — Last validation record

---

### `OGRH.SRValidation.GetLastRecordForItem(playerName, itemId)`

Get the most recent validation record for a specific player+item combination.

**Parameters:**
- `playerName` (string)
- `itemId` (number)

**Returns:** `table|nil` — Last record containing this item

---

### `OGRH.SRValidation.GetPlayerHistory(playerName, maxRecords)`

Get validation history for a player.

**Parameters:**
- `playerName` (string)
- `maxRecords` (number|nil) — Max records to return (default: 10)

**Returns:** `table[]` — Array of validation records (newest first)

---

## Legacy RollFor Compatibility

During the transition period, SRValidation can still read from RollFor if LootManager hasn't imported data:

```lua
function OGRH.SRValidation.GetLegacyRollForData()
    if not OGRH.ROLLFOR_AVAILABLE then return nil end
    
    if not RollForCharDb or not RollForCharDb.softres or not RollForCharDb.softres.data then
        return nil
    end
    
    local encodedData = RollForCharDb.softres.data
    if not encodedData or encodedData == "" then return nil end
    
    local decodedData = RollFor.SoftRes.decode(encodedData)
    if not decodedData then return nil end
    
    local softresData = RollFor.SoftResDataTransformer.transform(decodedData)
    if not softresData then return nil end
    
    -- Convert to LootManager format
    local playerSummary = {}
    for itemId, itemData in pairs(softresData) do
        if itemData.rollers then
            for _, roller in ipairs(itemData.rollers) do
                if not playerSummary[roller.name] then
                    playerSummary[roller.name] = {
                        class = roller.class or "",
                        spec = roller.role or "",
                        items = {},
                        totalSRPlus = 0,
                    }
                end
                table.insert(playerSummary[roller.name].items, {
                    itemId = itemId,
                    srPlus = roller.sr_plus or 0,
                    itemName = "",  -- Not available from RollFor transform
                })
                playerSummary[roller.name].totalSRPlus = 
                    playerSummary[roller.name].totalSRPlus + (roller.sr_plus or 0)
            end
        end
    end
    
    return {
        source = "rollfor",
        importTimestamp = GetTime(),
        raidId = "",
        instance = "",
        softReserves = softresData,
        hardReserves = {},
        playerSummary = playerSummary,
    }
end
```

---

## User Interface Updates

### Pre-Raid Summary Panel

Automatically shown after import (or on demand via `/ogrhlm validate`):

```
┌──────────────────────────────────────────────────────┐
│ SR+ Pre-Raid Validation — Naxxramas            [✕]  │
├──────────────────────────────────────────────────────┤
│                                                      │
│  ✓ 20 Valid  │  ⚠ 3 Warnings  │  ❌ 1 Error        │
│                                                      │
├──────────────────────────────────────────────────────┤
│ Errors (must resolve):                               │
├──────────────────────────────────────────────────────┤
│ ❌ Cheater     Warrior  SR+ 80  "SR+ exceeded max"  │
│                                  [View] [Edit] [OK] │
│                                                      │
├──────────────────────────────────────────────────────┤
│ Warnings (review recommended):                       │
├──────────────────────────────────────────────────────┤
│ ⚠ UnknownPug  Rogue    SR+ 10  "Not in roster"     │
│ ⚠ AltChar     Paladin  SR+ 20  "Main also has SR"  │
│ ⚠ NewPlayer   Mage     SR+ 30  "No prior history"  │
│                                                      │
├──────────────────────────────────────────────────────┤
│  [Validate All Passed]  [Re-Import]  [Close]        │
└──────────────────────────────────────────────────────┘
```

### Player Detail Panel

Enhanced from current SRValidation window with per-item and historical detail:

```
┌──────────────────────────────────────────────────────┐
│ SR+ Detail — Tankadin (Paladin)                 [✕]  │
├──────────────────────────────────────────────────────┤
│                                                      │
│  Roster: Main │ Spec: Protection │ Rank: Officer    │
│                                                      │
├──────────────────────────────────────────────────────┤
│ Current SR Entries:                                  │
├──────────────────────────────────────────────────────┤
│  [Icon] Desecrated Breastplate    SR+ 40  ✓ Valid   │
│         Last validated: Feb 8, 2026 (SR+ 30)       │
│         History: 0 → 10 → 20 → 30 → 40            │
│                                                      │
├──────────────────────────────────────────────────────┤
│ Validation History (last 5 raids):                   │
├──────────────────────────────────────────────────────┤
│  Feb 15  Naxxramas  SR+ 40  ✓ Validated            │
│  Feb 8   Naxxramas  SR+ 30  ✓ Validated            │
│  Feb 1   Naxxramas  SR+ 20  ✓ Validated            │
│  Jan 25  Naxxramas  SR+ 10  ✓ Validated            │
│  Jan 18  BWL        SR+ 0   ✓ New entry            │
│                                                      │
├──────────────────────────────────────────────────────┤
│  [Validate] [Edit SR+] [View Full History]          │
└──────────────────────────────────────────────────────┘
```

### SR+ Edit Dialog (Updated)

The existing edit dialog is retained but enhanced with better context:

```
┌──────────────────────────────────────────────┐
│ Edit SR+ Value                          [✕]  │
├──────────────────────────────────────────────┤
│                                              │
│  Player: Cheater (Warrior)                  │
│  Item: [22349] Desecrated Breastplate       │
│                                              │
│  Current SR+: ❌ 80                          │
│  Expected SR+: ✓ 50 (based on 5 weeks)     │
│  Last Validated: 40 (Feb 8, 2026)           │
│                                              │
│  New SR+ Value: [____]                      │
│                                              │
│  Reason for edit:                           │
│  [_________________________________]        │
│                                              │
│  [Save]  [Cancel]                           │
│                                              │
│  ⚠ This creates an audit record.            │
└──────────────────────────────────────────────┘
```

---

## Message Routing

**Module Prefix:** `[RH-SRValidation]`  
**Color Code:** `|cffcc99ff` (Light Purple — Administration category)

```lua
-- Validation complete
OGRH.Msg("|cffcc99ff[RH-SRValidation]|r Pre-raid validation complete: 20 valid, 3 warnings, 1 error")

-- Error found
OGRH.Msg("|cffff0000[RH-SRValidation]|r ERROR: Cheater has SR+ 80 (expected max 50)")

-- Warning
OGRH.Msg("|cffffaa00[RH-SRValidation]|r WARNING: UnknownPug not found in guild roster")

-- Validation passed
OGRH.Msg("|cff00ff00[RH-SRValidation]|r All SR+ entries validated successfully")

-- Debug
if OGRH.SRValidation.State.debug then
    OGRH.Msg("|cffcc99ff[RH-SRValidation][DEBUG]|r ValidateIncrement: Tankadin 30→40 = VALID (+10)")
end
```

---

## Integration with Existing SRValidation.lua

### Functions to Retain

The following existing functions will be kept (with updates):

| Function | Status | Changes |
|----------|--------|---------|
| `EnsureSV()` | **Update** | Add v2 schema fields, migration logic |
| `GetPlayerItems()` | **Update** | Read from LootManager import instead of RollFor |
| `GetValidationStatus()` | **Update** | Check pre-raid report first (fast path) |
| `ValidatePlayer()` | **Update** | Add per-item validation, roster checks |
| `SaveValidation()` | **Update** | Save per-item detail, audit trail |
| `GetPlayerRecords()` | **Keep** | No changes needed |
| `EditItemPlus()` | **Update** | Add audit reason field, edit LootMan data |
| `ShowWindow()` | **Major Update** | Redesign with pre-raid summary panel |
| `RefreshPlayerList()` | **Update** | Add status icons, roster info columns |
| `SelectPlayer()` | **Update** | Enhanced detail with per-item history |
| `FindNextPlayerToReview()` | **Keep** | No changes needed |
| `ValidateAllPassed()` | **Keep** | No changes needed |

### Functions to Add

| Function | Purpose |
|----------|---------|
| `MigrateSchema()` | v1 → v2 schema migration |
| `ValidateAll()` | Full batch validation, generate pre-raid report |
| `GetItemValidation(itemId)` | Per-item validation for LootManager |
| `GetPreRaidReport()` | Return cached pre-raid report |
| `GetLastRecordForItem(player, itemId)` | Item-specific history lookup |
| `ValidateIncrement()` | SR+ +10/week rule check |
| `ValidateItemLimit()` | SR item count per raid size |
| `ValidateNoItemSwitch()` | Detect item switches without reset |
| `ValidateSplitRaid()` | Main/Alt combined SR check |
| `ValidateRosterMatch()` | Roster cross-reference |
| `GetLegacyRollForData()` | Backward-compatible RollFor data read |
| `ShowPreRaidReport()` | Display pre-raid summary UI |

### Functions to Deprecate

| Function | Reason | Replacement |
|----------|--------|-------------|
| `GetSRPlusData()` | RollFor-specific | `GetLegacyRollForData()` (transitional) |
| `GetCachedSoftresData()` | RollFor caching | LootManager handles caching |
| `DebugSRPlus()` | RollFor debug commands | General `/ogrhlm debug` |

---

## File Structure

```
OG-RaidHelper/
├── _Administration/
│   ├── SRValidation.lua         -- Updated v2 validation engine
│   └── LootMan.lua              -- Import engine (provides data to SRValidation)
│
└── Documentation/
    └── 2.1/
        ├── SR+ Validation.md    -- This document
        └── LootMan.md           -- LootManager design
```

---

## Testing Strategy

### Unit Tests

| Test | Input | Expected |
|------|-------|----------|
| Increment +10 | last=30, current=40 | VALID |
| Increment +20 | last=30, current=50 | ERROR, "increased by 20" |
| Increment same | last=30, current=30 | VALID, "maintained" |
| Increment reset | last=30, current=0 | VALID, "reset" |
| Limit 40-man 2 items | 2 items, raidSize=40 | VALID |
| Limit 40-man 3 items | 3 items, raidSize=40 | ERROR, "3 SR items" |
| Limit 20-man 1 item | 1 item, raidSize=20 | VALID |
| Limit 20-man 2 items | 2 items, raidSize=20 | ERROR, "2 SR items" |
| Roster match | player in guild | VALID |
| Roster mismatch | player not in guild | WARNING, "PUG?" |
| Class mismatch | imported MAGE, roster WARRIOR | ERROR |
| Split raid ok | alt + main = 2 items (40-man) | VALID |
| Split raid exceed | alt + main = 3 items (40-man) | WARNING |
| New player high SR+ | no history, srPlus=30 | WARNING |
| Item switch no reset | different item, srPlus>0 | WARNING |
| Schema migration | v1 records | Converted to v2 format |

### Integration Tests

| Test | Description | Expected |
|------|-------------|----------|
| Import → Validate | CSV import triggers auto-validation | Pre-raid report generated |
| LootMan API | `GetValidationStatus()` during loot | Correct status returned |
| Pre-Raid UI | Show pre-raid report after import | Summary with errors/warnings |
| Edit + Audit | Edit SR+ value with reason | Audit record created |
| Legacy Compat | RollFor data with no LootManager import | Falls back to RollFor |
| History Depth | 20+ validations for one player | Oldest pruned, newest kept |

---

## Migration Path

### Phase 1: Dual-Source (Current → LootManager)

During transition:
1. SRValidation checks LootManager import first
2. Falls back to RollFor data if no LootManager import
3. Both sources use same validation rules
4. Pre-raid report works with either source

### Phase 2: LootManager Primary

After LootManager is stable:
1. SRValidation reads exclusively from LootManager
2. RollFor fallback code deprecated (logged warning if used)
3. Import dialog is the only entry point for SR+ data

### Phase 3: Blockchain Integration (Future)

When SR+ blockchain is implemented:
1. SRValidation computes SR+ from transaction chain
2. No external import needed
3. Validation is continuous (not just pre-raid)
4. Full audit trail via blockchain

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | January 2026 | Initial SRValidation module |
| 2.0 | February 15, 2026 | LootManager integration redesign (this document) |

---

## References

- [LootManager Design Document](LootMan.md)
- [SR+ Master Loot & Validation Design](SR+%20Master%20Loot%20%26%20Validation%20Design.md)
- [BaT Loot Rules](BaT%20Loot%20Rules.md)
- [OG-RaidHelper Design Philosophy](../Spec%20Docs/!%20OG-RaidHelper%20Design%20Philososphy.md)
- [SVM API Documentation](../Spec%20Docs/!%20SVM-API-Documentation.md)
- [V2 Schema Specification](../Spec%20Docs/!%20V2%20Schema%20Specification.md)

---

**END OF DOCUMENT**
