# DPSMate Pending Segment System

**Version:** 1.0  
**Created:** February 6, 2026  
**Status:** Design Phase  
**Related Systems:** Roster Management, AutoRank, Import Ranking Data

---

## Overview

The DPSMate Pending Segment System automatically captures DPS/Healing data from raid encounters when AutoRank is enabled, allowing delayed ELO updates through the Import Ranking Data interface. This eliminates the need for immediate post-encounter ranking by storing segment data for up to 2 days.

### Key Benefits
- **Delayed Processing:** Rank players after reviewing performance data
- **Automatic Capture:** No manual intervention needed during encounters
- **Prevents Duplicates:** Segments can only be imported once
- **Auto-Cleanup:** 2-day retention policy prevents data bloat
- **Flexible Workflow:** Import ranking data when convenient, not immediately after encounters

---

## System Architecture

### Data Flow

```
DPSMate Segment Creation
         ↓
   Hook Intercept
         ↓
   Check AutoRank
    (Raid/Encounter)
         ↓
   Capture Segment Data
         ↓
   Store in pendingSegments
         ↓
   Display in Import UI
         ↓
   User Selects Segment
         ↓
   Update ELO Rankings
         ↓
   Mark as Imported
         ↓
   Auto-Purge (2 days)
```

### Component Interaction

1. **Hook System:** Intercepts `DPSMate.Options:CreateSegment()`
2. **AutoRank Check:** Evaluates Active Raid/Encounter settings
3. **Data Capture:** Extracts relevant DPS/Healing data from DPSMate tables
4. **Storage:** Persists to `OGRH_SV.v2.rosterManagement.pendingSegments`
5. **UI Integration:** Adds "Pending Segments" source to Import Ranking Data
6. **Import Processing:** Updates ELO and marks segment as used
7. **Lifecycle Management:** Purges segments after 2 days

---

## DPSMate Integration

### Segment Creation Hook

**Target Function:** `DPSMate.Options:CreateSegment(name)`

**Location:** `DPSMate_Options.lua`, line ~1711

**Current Behavior:**
```lua
function DPSMate.Options:CreateSegment(name)
    -- Creates historical segment from current combat data
    -- Stores in DPSMateHistory tables
    -- Limits stored segments to configured datasegments count
    tinsert(DPSMateHistory["names"], 1, name.." - "..GameTime_GetTime())
    -- ... stores DMGDone, DMGTaken, Healing, etc.
end
```
#### When DPSMate Creates Segments

DPSMate automatically creates segments via `DPSMate.Options:NewSegment()` in these scenarios:

1. **Combat Start** (when player enters combat):
   - Triggered by `PLAYER_REGEN_DISABLED` event
   - Only if not already in combat state
   - Located in `DPSMate_DataBuilder.lua` line ~783

2. **Damage Event** (when damage is dealt):
   - Triggered by damage events during non-combat state
   - Starts a new segment and sets combat state
   - Located in `DPSMate_DataBuilder.lua` line ~1198

3. **Manual Creation** (user-initiated):
   - Via DPSMate menu option "New segment"
   - Can provide custom segment name

**Segment Naming Logic:**
DPSMate determines segment names via `NewSegment()` (line 1654):

```lua
function DPSMate.Options:NewSegment(segname)
    -- Find top damage taker (boss detection)
    local max = 0
    local topPlayer = ""
    for player, data in pairs(DPSMateEDT[2]) do  -- Enemy Damage Taken
        local totalDamage = 0
        for ability, abilityData in pairs(data) do
            if ability ~= "i" then
                totalDamage = totalDamage + abilityData["i"]
            end
        end
        if totalDamage > max then
            max = totalDamage
            topPlayer = player
        end
    end
    
    -- Determine segment name
    local name = segname or DPSMate:GetUserById(topPlayer) or "Unknown"
    local extra = segname and "" or " - CBT: " .. FormatTime(DPSMateCombatTime["current"])
    
    -- Filter segments based on settings
    if name ~= "Unknown" or max > 100 then
        if DPSMateSettings["onlybossfights"] then
            -- Only save if boss name recognized
            if DPSMate.BabbleBoss:Contains(name) then
                DPSMate.Options:CreateSegment(name .. extra)
            end
        else
            -- Save all segments
            DPSMate.Options:CreateSegment(name .. extra)
        end
    end
end
```

**Key Filters:**
- If `DPSMateSettings["onlybossfights"] = true`: Only saves segments where top damage taker matches known boss name
- If top damage taker is "Unknown" AND total damage < 100: Segment is not saved (filters out trivial combat)
- Segment name format: `"[Boss/Player Name] - CBT: [Combat Time]"` or custom name if provided

**Implications for OGRH:**
- ✅ DPSMate already filters trash fights if user enables "onlybossfights"
- ✅ Trivial combat (< 100 damage) automatically excluded
- ✅ OGRH should capture ALL segments DPSMate creates (trust DPSMate's filtering)
- ⚠️ Users with `onlybossfights = false` may get trash segments - consider adding OGRH filter option
**Hook Implementation:**
```lua
-- Hook CreateSegment to capture data when AutoRank is enabled
local originalCreateSegment = DPSMate.Options.CreateSegment
DPSMate.Options.CreateSegment = function(self, name)
    -- Call original function first
    originalCreateSegment(self, name)
    
    -- Check if AutoRank is enabled for Active Raid or Active Encounter
    if OGRH.ShouldCaptureSegment() then
        OGRH.CaptureSegmentData(name)
    end
end
```

### Required DPSMate Data

From DPSMate's segment creation, we need:

**Core Metadata:**
- `name` - Segment name (boss name + timestamp)
- `timestamp` - Unix timestamp of creation
- `combatTime` - Total combat duration
- `effectiveCombatTime` - Per-player effective combat time

**Performance Data:**

1. **Damage Done** (`DPSMateDamageDone[2]`)
   - Player damage output
   - Used for MELEE, RANGED DPS rankings

2. **Total Healing** (`DPSMateTHealing[2]`)
   - Total healing (including overhealing)
   - Used for HEALERS rankings

3. **Effective Healing** (`DPSMateEHealing[2]`)
   - Healing minus overhealing
   - Preferred metric for HEALERS if `useEffectiveHealing = true`

4. **Threat** (`DPSMateThreat[2]`) [OPTIONAL]
   - Threat generation
   - Potential future use for TANKS rankings

**Data Structure Example:**
```lua
-- DPSMateDamageDone[2] structure
{
    ["PlayerName"] = {
        i = 50000,  -- Total damage done
        -- ability breakdown...
    }
}

-- DPSMateTHealing[2] structure
{
    ["PlayerName"] = {
        i = 30000,  -- Total healing done
        -- spell breakdown...
    }
}

-- DPSMateEHealing[2] structure
{
    ["PlayerName"] = {
        i = 25000,  -- Effective healing (no overheal)
        -- spell breakdown...
    }
}

-- DPSMateCombatTime structure
{
    current = 120.5,  -- Total combat duration
    effective = {
        [2] = {
            ["PlayerName"] = 118.2,  -- Player's effective combat time
        }
    }
}
```

---

## Schema Design

### Location
`OGRH_SV.v2.rosterManagement.pendingSegments`

### Structure

```lua
OGRH_SV.v2.rosterManagement = {
    config = { ... },
    syncMeta = { ... },
    rankingHistory = { ... },
    
    -- NEW: Pending Segments
    pendingSegments = {
        [1] = {
            -- Metadata
            segmentId = "seg_1234567890_mc_ragnaros",  -- Unique identifier
            name = "Ragnaros - 19:30:45",               -- Display name (from DPSMate)
            timestamp = 1234567890,                     -- Unix timestamp
            createdAt = "2026-02-06 19:30:45",         -- Human-readable datetime
            
            -- Source Context
            raidName = "Molten Core",                   -- Active Raid name
            raidIndex = 1,                              -- Active Raid index
            encounterName = "Ragnaros",                 -- Active Encounter name (if applicable)
            encounterIndex = 9,                         -- Active Encounter index (if applicable)
            
            -- Combat Metrics
            combatTime = 120.5,                         -- Total combat duration (seconds)
            effectiveCombatTime = {                     -- Per-player effective time
                ["PlayerName"] = 118.2,
                ["PlayerName2"] = 115.8,
            },
            
            -- Performance Data
            damageData = {                              -- From DPSMateDamageDone[2]
                ["PlayerName"] = {
                    total = 50000,                      -- Total damage
                    dps = 423.7,                        -- Calculated DPS
                },
            },
            
            totalHealingData = {                        -- From DPSMateTHealing[2]
                ["PlayerName"] = {
                    total = 30000,                      -- Total healing
                    hps = 254.2,                        -- Calculated HPS
                },
            },
            
            effectiveHealingData = {                    -- From DPSMateEHealing[2]
                ["PlayerName"] = {
                    total = 25000,                      -- Effective healing
                    hps = 211.8,                        -- Calculated HPS (effective)
                },
            },
            
            -- State Management
            imported = false,                           -- Has been imported for ELO update
            importedAt = nil,                           -- Timestamp when imported (nil if not imported)
            importedBy = nil,                           -- Player who imported (nil if not imported)
            
            -- Expiration
            expiresAt = 1234740690,                     -- timestamp + (2 days * 86400)
            
            -- Optional: Preview Data
            playerCount = 25,                           -- Number of players in segment
            topDPS = "PlayerName",                      -- Top DPS player
            topHealer = "HealerName",                   -- Top healer
        },
        [2] = { ... },
        -- Array of pending segments (newest first)
    }
}
```

### Field Definitions

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `segmentId` | string | Yes | Unique identifier (timestamp + encounter name) |
| `name` | string | Yes | Display name from DPSMate segment |
| `timestamp` | number | Yes | Unix timestamp of segment creation |
| `createdAt` | string | Yes | ISO 8601 datetime for display |
| `raidName` | string | Yes | Active Raid name at time of capture |
| `raidIndex` | number | Yes | Active Raid numeric index |
| `encounterName` | string | No | Active Encounter name (if selected) |
| `encounterIndex` | number | No | Active Encounter index (if selected) |
| `combatTime` | number | Yes | Total combat duration in seconds |
| `effectiveCombatTime` | table | Yes | Per-player effective combat time |
| `damageData` | table | Yes | Player damage totals and DPS |
| `totalHealingData` | table | Yes | Player healing totals and HPS |
| `effectiveHealingData` | table | Yes | Player effective healing and HPS |
| `imported` | boolean | Yes | Import status flag |
| `importedAt` | number | No | Unix timestamp of import |
| `importedBy` | string | No | Player name who imported |
| `expiresAt` | number | Yes | Unix timestamp for auto-purge |
| `playerCount` | number | No | Number of players (for preview) |
| `topDPS` | string | No | Top DPS player name (for preview) |
| `topHealer` | string | No | Top healer name (for preview) |

---

## Implementation Details

### 1. Hook Installation

**File:** `_Configuration/Roster.lua` or new `_Configuration/PendingSegments.lua`

**Timing:** `ADDON_LOADED` event after DPSMate is confirmed loaded

```lua
-- Check if DPSMate is available
if DPSMate and DPSMate.Options and DPSMate.Options.CreateSegment then
    OGRH.HookDPSMateSegments()
else
    -- Delay hook until DPSMate loads
    OGRH.RegisterEvent("ADDON_LOADED", function(addon)
        if addon == "DPSMate" then
            OGRH.HookDPSMateSegments()
        end
    end)
end
```

### 2. AutoRank Check Function

```lua
function OGRH.ShouldCaptureSegment()
    -- Check raid permissions using existing Permissions API
    if not OGRH.CanModifyAssignments(UnitName("player")) then
        return false
    end
    
    -- Get Active Raid index
    local raidIdx = OGRH.SVM.Get("ui", "selectedRaidIndex")
    if not raidIdx then return false end
    
    -- Get Active Raid
    local raid = OGRH.SVM.GetPath("encounterMgmt.raids." .. raidIdx)
    if not raid then return false end
    
    -- Check if Raid-level AutoRank is enabled
    if raid.autoRank then
        return true, raid, nil
    end
    
    -- Get Active Encounter index
    local encounterIdx = OGRH.SVM.Get("ui", "selectedEncounterIndex")
    if not encounterIdx then return false end
    
    -- Get Active Encounter
    local encounter = OGRH.SVM.GetPath("encounterMgmt.raids." .. raidIdx .. ".encounters." .. encounterIdx)
    if not encounter then return false end
    
    -- Check if Encounter-level AutoRank is enabled
    if encounter.autoRank then
        return true, raid, encounter
    end
    
    return false
end
```

**Note:** Uses existing `OGRH.CanModifyAssignments()` API from `_Infrastructure/Permissions.lua`
- Returns `true` for ADMIN level (Raid Admin, Session Admin via `/ogrh sa`)
- Returns `true` for OFFICER level (Blizzard Raid Leader, Blizzard Raid Assistant)
- Returns `false` for MEMBER level or when not in raid

### 3. Data Capture Function

```lua
function OGRH.CaptureSegmentData(segmentName)
    local shouldCapture, raid, encounter = OGRH.ShouldCaptureSegment()
    if not shouldCapture then return end
    
    -- Generate unique segment ID
    local timestamp = time()
    local segmentId = "seg_" .. timestamp .. "_" .. (segmentName:gsub("%s", "_"):lower())
    
    -- Extract data from DPSMate tables
    local segment = {
        segmentId = segmentId,
        name = segmentName,
        timestamp = timestamp,
        createdAt = date("%Y-%m-%d %H:%M:%S", timestamp),
        
        raidName = raid.name or raid.displayName,
        raidIndex = OGRH.SVM.Get("ui", "selectedRaidIndex"),
        encounterName = encounter and (encounter.name or encounter.displayName),
        encounterIndex = encounter and OGRH.SVM.Get("ui", "selectedEncounterIndex"),
        
        combatTime = DPSMateCombatTime.current or 0,
        effectiveCombatTime = DPSMate:CopyTable(DPSMateCombatTime.effective[2] or {}),
        
        damageData = OGRH.ExtractDamageData(),
        totalHealingData = OGRH.ExtractHealingData(false),
        effectiveHealingData = OGRH.ExtractHealingData(true),
        
        imported = false,
        importedAt = nil,
        importedBy = nil,
        
        expiresAt = timestamp + (2 * 86400),  -- 2 days
        
        playerCount = OGRH.CountPlayers(DPSMateDamageDone[2], DPSMateTHealing[2]),
        topDPS = OGRH.GetTopPlayer(DPSMateDamageDone[2]),
        topHealer = OGRH.GetTopPlayer(DPSMateTHealing[2]),
    }
    
    -- Store segment
    local pendingSegments = OGRH.SVM.GetPath("rosterManagement.pendingSegments") or {}
    table.insert(pendingSegments, 1, segment)  -- Insert at front (newest first)
    
    OGRH.SVM.SetPath("rosterManagement.pendingSegments", pendingSegments, {
        source = "PendingSegments",
        action = "capture",
        sync = false,  -- Don't sync pending segments
    })
    
    OGRH.Msg("|cff00ff00[AutoRank]|r Captured segment: " .. segmentName)
end
```

### 4. Helper Functions

```lua
-- Extract damage data with calculated DPS
function OGRH.ExtractDamageData()
    local data = {}
    local damageTable = DPSMateDamageDone[2] or {}
    local effectiveTime = DPSMateCombatTime.effective[2] or {}
    
    for playerName, playerData in pairs(damageTable) do
        local total = playerData.i or 0
        local time = effectiveTime[playerName] or 1
        data[playerName] = {
            total = total,
            dps = total / time,
        }
    end
    
    return data
end

-- Extract healing data with calculated HPS
function OGRH.ExtractHealingData(effective)
    local data = {}
    local healingTable = effective and DPSMateEHealing[2] or DPSMateTHealing[2]
    healingTable = healingTable or {}
    local effectiveTime = DPSMateCombatTime.effective[2] or {}
    
    for playerName, playerData in pairs(healingTable) do
        local total = playerData.i or 0
        local time = effectiveTime[playerName] or 1
        data[playerName] = {
            total = total,
            hps = total / time,
        }
    end
    
    return data
end

-- Count unique players across damage and healing tables
function OGRH.CountPlayers(damageTable, healingTable)
    local players = {}
    for name, _ in pairs(damageTable or {}) do
        players[name] = true
    end
    for name, _ in pairs(healingTable or {}) do
        players[name] = true
    end
    
    local count = 0
    for _ in pairs(players) do
        count = count + 1
    end
    return count
end

-- Get top player by total value
function OGRH.GetTopPlayer(dataTable)
    local topPlayer = nil
    local topValue = 0
    
    for playerName, playerData in pairs(dataTable or {}) do
        local value = playerData.i or 0
        if value > topValue then
            topValue = value
            topPlayer = playerName
        end
    end
    
    return topPlayer
end
```

### 5. Purge Function

```lua
-- Auto-purge expired or imported segments
function OGRH.PurgeExpiredSegments()
    local pendingSegments = OGRH.SVM.GetPath("rosterManagement.pendingSegments") or {}
    local currentTime = time()
    local purgedCount = 0
    
    -- Iterate backwards to safely remove items
    for i = table.getn(pendingSegments), 1, -1 do
        local segment = pendingSegments[i]
        
        -- Remove if expired OR if imported more than 2 days ago
        local shouldPurge = false
        if segment.expiresAt and currentTime > segment.expiresAt then
            shouldPurge = true
        elseif segment.imported and segment.importedAt and (currentTime - segment.importedAt) > (2 * 86400) then
            shouldPurge = true
        end
        
        if shouldPurge then
            table.remove(pendingSegments, i)
            purgedCount = purgedCount + 1
        end
    end
    
    if purgedCount > 0 then
        OGRH.SVM.SetPath("rosterManagement.pendingSegments", pendingSegments, {
            source = "PendingSegments",
            action = "purge",
            sync = false,
        })
        OGRH.Msg("|cffaaaaaa[AutoRank]|r Purged " .. purgedCount .. " expired segment(s)")
    end
end

-- Schedule purge check every hour
OGRH.ScheduleRepeatingTimer("PurgeExpiredSegments", 3600)
```

---

## UI Integration

### Import Ranking Data Interface Structure

**Current Interface Layout:**
- **Top Section:** Source dropdown selector
- **Main Section:** Four role columns (Tanks, Healers, Melee, Ranged)
- **Bottom Section:** Include checkboxes + "Update ELO" button

**Current Sources:**
1. Current (current segment data)
2. Total (total/aggregate data)
3. DPSMate (DPSMate segment selector)
4. ShaguDPS (if installed)
5. CSV (manual import)

### Adding Pending Segments Source

**New Source Option:**
- **Name:** "Pending Segments"
- **Badge:** Shows count of ready-to-import segments
- **Behavior:** When selected, shows segment selector dropdown

**Source Selection UI:**
```
Source: [Pending Segments (3) ▼]
        └─ Dropdown shows: Current, Total, DPSMate, Pending Segments (3), CSV

When "Pending Segments (3)" selected:
  └─ Second dropdown appears: [Select Segment ▼]
                             └─ Ragnaros - 19:30:45 (2h ago)
                             └─ Onyxia - 18:15:20 (4h ago)  
                             └─ Lucifron - 17:45:10 (Yesterday) [IMPORTED]
```

**Integration Code:**
```lua
-- In Roster.lua, add to source menu
if OGRH.HasPendingSegments() then
    local count = OGRH.GetPendingSegmentCount(false)  -- false = exclude imported
    table.insert(sourceMenuItems, {
        text = "Pending Segments (" .. count .. ")",
        value = "pending",
        onClick = function()
            OGRH.ShowPendingSegmentSelector()
        end
    })
end
```

### Segment Selector Dropdown

**Layout:** Dropdown below Source selector (similar to DPSMate segment selector)

**Entry Format:**
```
[Segment Name] - [Time Ago]
Ragnaros - 19:30:45 (2h ago)
```

**Entry Details (on hover/expand):**
- Raid/Encounter context
- Player count
- Top DPS / Top Healer
- Import status

**Filtering:**
- Default: Show only ready-to-import segments (not imported)
- Option: "Show All" (includes already imported segments with grayed out text)

**Code Structure:**
```lua
function OGRH.ShowPendingSegmentSelector()
    -- Create dropdown menu below source selector
    local pendingSegments = OGRH.SVM.GetPath("rosterManagement.pendingSegments") or {}
    local menuItems = {}
    
    for i, segment in ipairs(pendingSegments) do
        -- Skip imported segments unless "Show All" enabled
        if not segment.imported or OGRH.GetSetting("showAllSegments") then
            local timeAgo = OGRH.FormatTimeAgo(segment.timestamp)
            local status = segment.imported and " [IMPORTED]" or ""
            
            table.insert(menuItems, {
                text = segment.name .. " (" .. timeAgo .. ")" .. status,
                value = i,
                disabled = segment.imported,  -- Gray out imported segments
                onClick = function()
                    OGRH.LoadPendingSegment(i)
                end
            })
        end
    end
    
    -- Show dropdown with segments
    OGRH.ShowDropdownMenu(menuItems)
end
```

### Loading Segment Data

**When segment selected:**
1. Validate segment hasn't been imported (or show warning)
2. Extract player rankings from segment data
3. Populate four role columns (Tanks, Healers, Melee, Ranged)
4. Enable "Update ELO" button

**Column Population:**
```lua
function OGRH.LoadPendingSegment(segmentIndex)
    local segment = OGRH.GetPendingSegment(segmentIndex)
    
    if segment.imported then
        OGRH.Msg("|cffff8800Warning:|r This segment was already imported on " .. 
                 date("%Y-%m-%d %H:%M", segment.importedAt) .. " by " .. segment.importedBy)
        -- Optionally allow re-import or block
    end
    
    -- Build role rankings from segment data
    local roleRankings = {
        TANKS = OGRH.ExtractTankRankings(segment),
        HEALERS = OGRH.ExtractHealerRankings(segment),
        MELEE = OGRH.ExtractMeleeRankings(segment),
        RANGED = OGRH.ExtractRangedRankings(segment),
    }
    
    -- Populate UI columns
    OGRH.PopulateRankingColumns(roleRankings)
    
    -- Store selected segment for import
    OGRH.selectedPendingSegment = segmentIndex
end
```

### Import Process

**Flow:**
1. User selects "Pending Segments" source
2. User selects specific segment from dropdown
3. System loads segment data into four role columns
4. User reviews rankings (can remove players with X buttons)
5. User clicks "Update ELO" button
6. System validates segment hasn't been imported
7. Update ELO for all included players
8. Mark segment as imported with metadata
9. Show success message
10. Refresh segment selector (remove from ready count)

**Import Code:**
```lua
function OGRH.ImportSelectedPendingSegment()
    if not OGRH.selectedPendingSegment then
        OGRH.Msg("|cffff0000Error:|r No segment selected")
        return
    end
    
    local pendingSegments = OGRH.SVM.GetPath("rosterManagement.pendingSegments")
    local segment = pendingSegments[OGRH.selectedPendingSegment]
    
    -- Validate
    if segment.imported then
        OGRH.Msg("|cffff0000Error:|r This segment has already been imported")
        return
    end
    
    -- Get current rankings from UI columns (respects user removals)
    local rankings = OGRH.GetCurrentRankingsFromUI()
    
    -- Update ELO using existing system
    OGRH.UpdateELOFromRankings(rankings)
    
    -- Mark as imported
    segment.imported = true
    segment.importedAt = time()
    segment.importedBy = UnitName("player")
    
    -- Save
    OGRH.SVM.SetPath("rosterManagement.pendingSegments", pendingSegments, {
        source = "PendingSegments",
        action = "import",
        sync = false,
    })
    
    OGRH.Msg("|cff00ff00[AutoRank]|r Imported segment: " .. segment.name)
    
    -- Clear selection
    OGRH.selectedPendingSegment = nil
end
```

---

## Data Lifecycle

### Capture Conditions
- DPSMate creates a new segment
- Active Raid OR Active Encounter has AutoRank enabled
- Combat data exists in DPSMate tables
- Player is in a raid group (not party/solo)
- Player has raid permissions (OG-RaidHelper Raid Admin, Blizzard Raid Leader, or Blizzard Raid Assistant)

### Storage Duration
- **Ready to Import:** 2 days from creation
- **After Import:** 2 days from import date
- **Total Max:** 4 days (2 days waiting + 2 days after import)

### Purge Conditions
1. `expiresAt` < current time (segment created > 2 days ago)
2. `imported = true` AND `importedAt + 2 days` < current time

### Purge Schedule
- Runs every 1 hour
- Triggered on player login
- Triggered when viewing Pending Segments UI

---

## Error Handling

### Missing DPSMate Data
```lua
-- Validate DPSMate tables exist before capture
if not DPSMateDamageDone or not DPSMateTHealing then
    OGRH.Msg("|cffff0000[AutoRank]|r Cannot capture segment: DPSMate data unavailable")
    return
end
```

### Duplicate Prevention
```lua
-- Check for existing segment with same ID
local pendingSegments = OGRH.SVM.GetPath("rosterManagement.pendingSegments") or {}
for i, seg in ipairs(pendingSegments) do
    if seg.segmentId == segmentId then
        OGRH.Msg("|cffaaaaaa[AutoRank]|r Segment already captured: " .. segmentName)
        return
    end
end
```

### Import Validation
```lua
-- Prevent re-importing
if segment.imported then
    OGRH.Msg("|cffff0000Error:|r Segment already imported")
    return false
end

-- Validate segment data integrity
if not segment.damageData and not segment.totalHealingData then
    OGRH.Msg("|cffff0000Error:|r Segment has no ranking data")
    return false
end
```

---

## Implementation Phases

### Phase 1: Core Capture System
**Estimated Time:** 30-45 minutes

**Scope:**
- Create new file: `_Configuration/PendingSegments.lua`
- Hook `DPSMate.Options:CreateSegment()`
- Implement permission checks (`ShouldCaptureSegment()`)
- Implement data capture (`CaptureSegmentData()`)
- Add helper functions:
  - `ExtractDamageData()`
  - `ExtractHealingData()`
  - `CountPlayers()`
  - `GetTopPlayer()`
- Initialize `pendingSegments` schema in `rosterManagement`
- Update `! V2 Schema Specification.md` with `pendingSegments` structure

**Testing:**
- [x] Hook installs without errors on addon load
- [x] DPSMate segment creation still works normally (no interference)
- [x] Enable AutoRank on test raid/encounter
- [x] Kill a boss (or create DPSMate segment manually)
- [x] Verify segment captured in `OGRH_SV.v2.rosterManagement.pendingSegments`
- [x] Check all required fields populated (damage, healing, metadata)
- [x] Verify permission check blocks capture when not Raid Admin/Lead/Assist
- [x] Test with AutoRank disabled - should NOT capture

**Success Criteria:**
- Segments automatically captured when AutoRank enabled
- No errors in chat or Lua errors
- Data persists between reloads
- Capture only happens with proper permissions

**Rollback Plan:**
- Comment out hook installation if issues arise
- System can be disabled without affecting other OGRH features

---

### Phase 2: Purge System
**Estimated Time:** 15 minutes

**Scope:**
- Implement `PurgeExpiredSegments()`
- Schedule repeating timer (hourly)
- Trigger purge on login
- Add manual purge command (optional)

**Testing:**
- [x] Manually set `expiresAt` to past timestamp
- [x] Run purge manually or wait for timer
- [x] Verify expired segments removed
- [x] Test imported segment purge (2 days after import)
- [x] Verify active segments NOT purged
- [x] Check purge runs on login

**Success Criteria:**
- Old segments automatically removed
- No errors during purge
- Active segments preserved
- Purge count displayed in chat

**Dependencies:**
- Phase 1 must be complete and working

---

### Phase 3: UI Integration + Import
**Estimated Time:** 45-60 minutes

**Scope:**
- Read existing `_Configuration/Roster.lua` Import Ranking Data code
- Add "Pending Segments" source to source dropdown menu
- Create segment selector dropdown (shows when source selected)
- Implement segment loading:
  - `LoadPendingSegment(segmentIndex)`
  - `ExtractTankRankings(segment)`
  - `ExtractHealerRankings(segment)`
  - `ExtractMeleeRankings(segment)`
  - `ExtractRangedRankings(segment)`
- Populate existing four role columns with segment data
- Implement import logic:
  - `ImportSelectedPendingSegment()`
  - Mark segment as imported
  - Update `importedAt` and `importedBy`
- Add time formatting helper (`FormatTimeAgo()`)
- Handle already-imported segments (show warning or gray out)

**Testing:**
- [ ] "Pending Segments" source appears in dropdown
- [ ] Source shows correct count badge
- [ ] Segment selector displays all segments
- [ ] Already-imported segments marked/grayed
- [ ] Selected segment populates role columns correctly
- [ ] DPS/HPS values match segment data
- [ ] Player names mapped to correct roles
- [ ] Remove player with X button still works
- [ ] "Update ELO" button triggers import
- [ ] Segment marked as imported after successful import
- [ ] Re-import prevented or shows warning
- [ ] ELO updates applied correctly
- [ ] Count badge decrements after import

**Success Criteria:**
- Seamless integration with existing Import UI
- Segment data displays accurately
- Import process matches existing DPSMate/CSV flow
- No regressions in existing import sources
- User-friendly error messages

**Dependencies:**
- Phase 1 must be complete (data must exist)
- Phase 2 recommended but not required

**UI Research Required:**
- Understand existing source dropdown implementation
- Identify how DPSMate segment selector works
- Map role ranking data structure (TANKS, HEALERS, MELEE, RANGED)
- Understand ELO update mechanism from existing imports

---

## Testing Checklist

**Full Integration Testing (After All Phases):**

### Capture Testing
- [ ] Hook installs correctly when DPSMate loads
- [ ] Segment captured when Raid AutoRank enabled
- [ ] Segment captured when Encounter AutoRank enabled
- [ ] No capture when AutoRank disabled
- [ ] No capture when no combat data
- [ ] Duplicate segments prevented

### Data Integrity
- [ ] All required fields populated
- [ ] DPS/HPS calculated correctly
- [ ] Effective combat time extracted
- [ ] Player count accurate
- [ ] Top player detection works

### UI Testing
- [ ] Pending Segments source appears in menu
- [ ] Segment count badge accurate
- [ ] Segment list displays correctly
- [ ] Filters work properly
- [ ] Sort options function
- [ ] Import button enabled/disabled correctly

### Import Testing
- [ ] ELO updates applied correctly
- [ ] Segment marked as imported
- [ ] Import metadata saved
- [ ] Re-import prevented
- [ ] UI refreshes after import

### Lifecycle Testing
- [ ] Purge runs on schedule
- [ ] Expired segments removed
- [ ] Imported segments purged after 2 days
- [ ] Manual purge works
- [ ] No data loss on purge

---

## Future Enhancements

**Note:** These are post-launch features, not part of the initial 3-phase implementation.

### Future Feature Ideas
1. **Segment Comparison:** Compare multiple segments side-by-side
2. **Batch Import:** Import multiple segments at once
3. **Segment Notes:** Add custom notes to segments
4. **Performance Trends:** Track player performance over time
5. **Export Segments:** Save segments to external file
6. **Import Segments:** Load segments from external file

### Integration Opportunities
1. **Consume Tracking:** Correlate segment data with consume usage
2. **Boss Mods:** Auto-capture on BigWigs boss kill detection
3. **Guild Sync:** Share pending segments with guild members
4. **Web Dashboard:** View segments on external website

---

## Migration Notes

### Existing Installations
- No migration needed for new feature
- Schema changes automatically applied
- No impact on existing ranking data

### Rollback Plan
- Hook can be disabled via setting
- Pending segments can be cleared manually
- No data loss if feature disabled

---

## Performance Considerations

### Memory Usage
- Estimated 5-10 KB per segment
- 20 segments = ~100-200 KB
- Negligible impact on addon memory

### Hook Overhead
- Hook fires once per segment creation
- ~1-2ms processing time per capture
- No impact on combat performance

### Purge Performance
- Runs on timer (not combat)
- O(n) complexity where n = segment count
- Typically < 20 segments to check

---

## Configuration Options

### User Settings
```lua
OGRH_SV.v2.rosterManagement.config.pendingSegments = {
    enabled = true,                      -- Enable/disable capture
    retentionDays = 2,                   -- Days before purge (default: 2)
    maxSegments = 50,                    -- Max segments to store (default: 50)
    autoImport = false,                  -- Auto-import on capture (default: false)
    showNotifications = true,            -- Show capture notifications (default: true)
}
```

### Admin Controls
- Enable/disable pending segment capture
- Adjust retention period (1-7 days)
- Set maximum segment limit
- Clear all pending segments
- Export pending segments

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-02-06 | Initial design specification |

---

## Related Documentation
- [! V2 Schema Specification.md](! V2 Schema Specification.md)
- [! OG-RaidHelper API.md](! OG-RaidHelper API.md)
- [Auto-Rank Integration Guide](TBD)
- [Roster Management System](TBD)
