# OG-RaidHelper: Roster Management Feature Design Document

**Version:** 1.0  
**Date:** December 23, 2025  
**Feature Code:** OGRH_RosterMgmt  
**New File:** OGRH_RGO_Roster.lua

---

## CRITICAL IMPLEMENTATION CONSTRAINTS

**⚠️ ALL AI AGENTS IMPLEMENTING THIS FEATURE MUST FOLLOW THESE RULES:**

1. **Language Compatibility**: All code MUST be Lua 5.0 compatible (Turtle WoW 1.12 client)
   - Use `table.getn()` or manual counting, NOT `#table`
   - Use `table.foreach()`, NOT `ipairs()` where order matters
   - No `continue` statement - use conditional blocks or flags
   - String patterns use Lua 5.0 syntax

2. **UI Framework**: ALL interface components MUST use the OGST Library (Libs/OGST/)
   - Use `OGST.CreateList()`, `OGST.CreateButton()`, `OGST.CreatePanel()`, etc.
   - If a required UI component doesn't exist in OGST, **ADD IT TO OGST FIRST**
   - Do NOT create custom UI code outside OGST unless absolutely necessary
   - Reference existing OGST implementations in OG-RaidHelper for patterns

3. **Code Style**: Follow existing OG-RaidHelper conventions
   - Use `OGRH.` namespace for all public functions
   - Local functions use `local function FunctionName()`
   - Follow existing naming patterns (PascalCase for functions, camelCase for variables)
   - Include comprehensive comments explaining complex logic

4. **Integration**: Must integrate seamlessly with existing systems
   - Use existing `OGRH.EnsureSV()` pattern for saved variables
   - Use existing `OGRH.StyleButton()`, `OGRH.SetListItemColor()` patterns
   - Register menu items properly in `OGRH_MainUI.lua`
   - Follow existing event registration patterns

5. **Testing**: All implementations must be tested in WoW 1.12 client
   - No modern WoW API calls
   - Verify compatibility with Turtle WoW custom features
   - Test with both DPSMate and ShaguDPS present/absent

---

## Feature Overview

**Purpose**: Provide a roster management interface to track potential raid participants, assign them to roles, and rank them within those roles for automated assignment prioritization.

**Location**: Settings → Roster Management (between "Raid Group Organization" and "Data Management")

**Primary Use Cases**:
1. Track guild members and regular raiders who participate in raids
2. Assign players to primary and secondary roles (Tank, Healer, Melee, Ranged)
3. Rank players within each role to prioritize auto-assignment
4. Sync roster data between raid leaders and assistants
5. Integrate rankings with RGO auto-sort and Encounter auto-assign systems

---

## Data Structure

### SavedVariables Storage

**Variable Name**: `OGRH_SV.rosterManagement`  
**Scope**: SavedVariables (account-wide, shared across all characters)

```lua
OGRH_SV.rosterManagement = {
  -- Player roster data
  players = {
    ["PlayerName"] = {
      class = "WARRIOR",           -- Uppercase class name
      primaryRole = "TANKS",        -- TANKS, HEALERS, MELEE, RANGED
      secondaryRoles = {            -- Array of additional roles (max 3)
        "MELEE",
        -- Can have up to 3 secondary roles
      },
      rankings = {                  -- Per-role ELO rating (starts at 1000)
        TANKS = 1000,
        HEALERS = 1000,
        MELEE = 1000,
        RANGED = 1000
      },
      notes = "",                   -- Optional notes about player
      lastUpdated = 1234567890      -- Unix timestamp
    }
  },
  
  -- Ranking history for automated ranking system
  rankingHistory = {
    ["PlayerName"] = {
      TANKS = {},                   -- Empty for tanks (manual only)
      HEALERS = {                   -- Array of recent performance values
        { value = 8500, timestamp = 1234567890, source = "DPSMate" },
        { value = 9200, timestamp = 1234567891, source = "DPSMate" },
        -- Keep last 10 entries
      },
      MELEE = {},                   -- Similar structure for DPS
      RANGED = {}
    }
  },
  
  -- Configuration
  config = {
    historySize = 10,               -- Number of historical rankings to track
    autoRankingEnabled = {          -- Per-role auto-ranking toggle
      TANKS = false,                -- Always false (manual only)
      HEALERS = true,
      MELEE = true,
      RANGED = true
    },
    rankingSource = "DPSMate",      -- "DPSMate" or "ShaguDPS"
    useEffectiveHealing = true,     -- For healers
    eloSettings = {
      startingRating = 1000,        -- Default ELO for new players
      kFactor = 32,                 -- ELO adjustment sensitivity (16-40 typical)
      manualAdjustment = 25         -- ELO change per manual up/down button
    }
  },
  
  -- Sync metadata
  syncMeta = {
    version = 1,
    lastSync = 0,
    syncChecksum = ""               -- Separate from main OGRH sync checksums
  }
}
```

### Data Initialization

```lua
function OGRH.RosterMgmt.EnsureSV()
  OGRH.EnsureSV()
  
  if not OGRH_SV.rosterManagement then
    OGRH_SV.rosterManagement = {
      players = {},
      rankingHistory = {},
      config = {
        historySize = 10,
        autoRankingEnabled = {
          TANKS = false,
          HEALERS = true,
          MELEE = true,
          RANGED = true
        },
        rankingSource = "DPSMate",
        useEffectiveHealing = true,
        eloSettings = {
          startingRating = 1000,
          kFactor = 32,
          manualAdjustment = 25
        }
      },
      syncMeta = {
        version = 1,
        lastSync = 0,
        syncChecksum = ""
      }
    }
  end
end
```

---

## Interface Design

### Main Window Layout

**Window Dimensions**: 900x600  
**Window Name**: "Roster Management"  
**Layout**: Three-panel design (Role List | Player List | Player Details)

```
┌──────────────────────────────────────────────────────────────────────────┐
│  Roster Management                                              [X] Close │
├─────────────┬───────────────────────────────┬────────────────────────────┤
│ Roles       │ Players                       │ Player Details             │
│             │                               │                            │
│ > Tanks     │ PlayerName1     [↑] [↓] 1250  │ PlayerName1                │
│   Healers   │ PlayerName2     [↑] [↓] 1180  │ [Warrior Icon] WARRIOR     │
│   Melee     │ PlayerName3     [↑] [↓] 1050  │ ────────────────────────   │
│   Ranged    │ PlayerName4     [↑] [↓] 980   │ Primary: Tank              │
│   All       │ PlayerName5     [↑] [↓] 920   │ Secondary: Melee           │
│   Players   │ ...                           │                            │
│             │                               │ Tanks:    1250             │
│             │                               │ Healers:  1000             │
│             │                               │ Melee:    1100             │
│             │                               │ Ranged:   1000             │
│             │                               │                            │
│             │                               │ Notes:                     │
│             │                               │ ┌────────────────────────┐ │
│             │                               │ │Good attendance, knows  │ │
│             │                               │ │mechanics               │ │
│             │                               │ └────────────────────────┘ │
├─────────────┴───────────────────────────────┴────────────────────────────┤
│ [Add Player] [Remove Player] [Import from DPS Meter] [Sync]              │
└──────────────────────────────────────────────────────────────────────────┘
```

### Panel 1: Role List (Left Panel)

**Width**: 150px  
**Component**: OGST.CreateList() or custom OGST list component

**Entries**:
- Tanks (with count badge)
- Healers (with count badge)
- Melee (with count badge)
- Ranged (with count badge)
- **All Players** (with total count badge)

**Behavior**:
- Single selection
- Default: "Tanks" selected on open
- Selection changes populate Player List panel
- Count badges update dynamically

### Panel 2: Player List (Center Panel)

**Width**: 400px  
**Component**: OGST scrollable list with custom row template

**Display Modes**:

#### Mode A: Role-Specific View (Tanks/Healers/Melee/Ranged selected)

**Row Format**:
```
[Class Icon] PlayerName          [↑] [↓] [Edit: 1250]
```

**Columns**:
1. Class icon (16x16)
2. Player name (class colored)
3. Up button (↑) - increases ELO by configured amount (default +25)
4. Down button (↓) - decreases ELO by configured amount (default -25)
5. ELO rating (editable, integer value)

**Sort Order**: Descending by ranking (highest first)

**Row Actions**:
- Click row: Select player (highlight, show details in right panel)
- Click ↑: Increase ELO by configured amount (default +25)
- Click ↓: Decrease ELO by configured amount (default -25)
- Click ELO value: Open edit dialog
- Right-click row: Context menu (Remove, Set Primary Role, Add/Remove from Role)

**No Delete Button**: Players removed via bottom toolbar or context menu

#### Mode B: All Players View

**Row Format**:
```
[Class Icon] PlayerName          [Role Badge]
```

**Columns**:
1. Class icon (16x16)
2. Player name (class colored)
3. Primary role badge (Tank/Healer/Melee/Ranged)

**Sort Order**: 
- Primary: By class (alphabetical)
- Secondary: By name (alphabetical)

**Row Actions**:
- Click row: Show player details in right panel (highlight row)
- Right-click: Context menu (Remove, Set Primary Role, Edit Roles)

### Panel 3: Player Details (Right Panel)

**Width**: 280px  
**Visibility**: Always visible, shows details of currently selected player  
**Component**: OGST.CreatePanel() with form elements

**Layout**:
```
┌─────────────────────────┐
│ PlayerName              │
│ [Class Icon] WARRIOR    │
├─────────────────────────┤
│ Primary Role:           │
│ [Dropdown: Tanks    ▼]  │
│                         │
│ Secondary Roles:        │
│ [Dropdown: Melee    ▼]  │
│ [Dropdown: None     ▼]  │
│ [Dropdown: None     ▼]  │
│                         │
│ Notes:                  │
│ ┌─────────────────────┐ │
│ │                     │ │
│ │ (multiline text)    │ │
│ │                     │ │
│ └─────────────────────┘ │
│                         │
│ Rankings Summary:       │
│ Tanks:    [1000]        │
│ Healers:  [1000]        │
│ Melee:    [1250]        │
│ Ranged:   [1000]        │
│                         │
│ [Save] [Cancel]         │
└─────────────────────────┘
```

**Fields**:
1. **Player Name** (read-only, display with class icon)
2. **Class** (read-only, shown with icon)
3. **Primary Role** (dropdown: Tanks, Healers, Melee, Ranged)
4. **Secondary Roles** (3 dropdowns: None, Tanks, Healers, Melee, Ranged)
   - Cannot select same role as primary
   - Cannot select same role twice
5. **Notes** (multiline text, max 500 chars)
6. **Rankings Summary** (read-only display of current rankings)
7. **Save/Cancel** buttons

**Validation**:
- Primary role required
- Secondary roles optional
- Warn if removing roles that have ELO ratings different from starting value (1000)

**Panel Behavior**:
- Always visible on the right side
- Shows details for currently selected player (from any role view)
- When no player is selected, shows placeholder text: "Select a player to view details"
- Updates immediately when clicking different player rows
- Save button updates player data and refreshes all views
- Cancel button reverts to last saved state
- Edit mode enabled when clicking in any editable field

### Bottom Toolbar

**Buttons** (left to right):

1. **Add Player** - Opens add player dialog
2. **Remove Player** - Removes selected player (with confirmation)
3. **Import from DPS Meter** - Opens import wizard
4. **Update Rankings** - Manual refresh rankings from DPS meter
5. **Sync** (right side) - Opens sync options menu

---

## Ranking System

### ELO Rating System

- **System**: Modified ELO rating (chess-style competitive ranking)
- **Starting Value**: 1000 ELO for all new players
- **Range**: Theoretically unlimited, but typically 500-2000 in practice
- **Independent**: Each role has separate ELO rating
- **Display**: Always show current ELO rating as integer

**Why ELO?**
- Naturally distributes players across a skill curve
- Self-balancing: stronger players have higher ratings
- Accommodates new players joining at any time
- Historical performance automatically factored in
- More granular than 0-100 scale

### Ranking Adjustments

#### Manual Adjustment Methods

1. **Up/Down Buttons**:
   - Increment/decrement by configured amount (default: 25 ELO)
   - Re-sort list automatically
   - No hard floor or ceiling (can go below 0 or above any value)
   - Configurable step size in settings

2. **Direct Edit**:
   - Click ELO value opens dialog
   - Enter new ELO value (any integer)
   - Validates input (must be numeric)
   - Updates and re-sorts

3. **Drag and Drop** (Stretch Goal):
   - Drag player row to reorder
   - Calculate ELO swap based on position
   - Update affected players

#### Automated Ranking (On-Demand Only)

**Trigger**: Manual button click "Update Rankings"  
**Process**:

1. Check which DPS meter is available (DPSMate → ShaguDPS → None)
2. Retrieve performance data based on role:
   - **Tanks**: Skip (manual only)
   - **Healers**: Healing or effective healing data
   - **Melee**: DPS data (filter melee classes/specs)
   - **Ranged**: DPS data (filter ranged classes/specs)
3. Add to ranking history (keep last 10 entries)
4. Calculate aggregate ranking using formula
5. Update player rankings
6. Refresh UI

**ELO Calculation Algorithm**:

```lua
-- Calculate expected score between two players
local function CalculateExpectedScore(ratingA, ratingB)
  return 1 / (1 + 10 ^ ((ratingB - ratingA) / 400))
end

-- Update ELO rating based on performance
local function UpdateEloRating(currentRating, performancePercentile, kFactor)
  -- performancePercentile: 0.0-1.0 where player ranks among role peers this session
  -- kFactor: How much ratings change per update (typically 16-40)
  
  local expectedScore = 0.5  -- Assume average expected performance
  local actualScore = performancePercentile  -- 0.0 = worst, 1.0 = best
  
  local ratingChange = kFactor * (actualScore - expectedScore)
  return math.floor(currentRating + ratingChange + 0.5)  -- Round to nearest integer
end

-- Calculate aggregate ELO adjustment from performance history
local function CalculateEloAdjustment(currentElo, performanceHistory, allPlayersInRole)
  if not performanceHistory or table.getn(performanceHistory) == 0 then 
    return currentElo 
  end
  
  local kFactor = OGRH_SV.rosterManagement.config.eloSettings.kFactor or 32
  local newElo = currentElo
  
  -- Process each performance entry
  for i = 1, table.getn(performanceHistory) do
    local entry = performanceHistory[i]
    local percentile = CalculatePercentile(entry.value, allPlayersInRole, entry.role)
    newElo = UpdateEloRating(newElo, percentile, kFactor)
  end
  
  return newElo
end

-- Calculate where player ranks among peers (0.0 to 1.0)
local function CalculatePercentile(playerValue, allPlayersInRole, role)
  local betterCount = 0
  local totalCount = 0
  
  for _, otherPlayer in ipairs(allPlayersInRole) do
    if otherPlayer.performanceValue and otherPlayer.performanceValue > 0 then
      totalCount = totalCount + 1
      if playerValue > otherPlayer.performanceValue then
        betterCount = betterCount + 1
      end
    end
  end
  
  if totalCount == 0 then return 0.5 end  -- No data, assume average
  return betterCount / totalCount
end
```

**ELO Update Strategy**:

1. **After Each Raid Session**:
   - Import DPS/Healing data from meter
   - Calculate percentile rank for each player in their role
   - Apply ELO adjustment based on performance
   - Higher K-factor (32-40) = more volatile, faster adjustment
   - Lower K-factor (16-24) = more stable, slower adjustment

2. **Performance Percentile**:
   - Top performer in role = 1.0 percentile → gains ELO
   - Middle performer = 0.5 percentile → neutral
   - Bottom performer = 0.0 percentile → loses ELO

3. **Manual Adjustments**:
   - Bypass ELO formula entirely
   - Direct addition/subtraction or set value
   - Use for non-measurable factors (attendance, attitude, mechanics)

---

## Integration Points

### 1. RGO Auto-Sort Integration (OGRH_RGO.lua)

**Purpose**: Use roster rankings to prioritize player selection during auto-sort

**Access Point**: `OGRH.RGO.GetRankedPlayersForRole(role)`

```lua
function OGRH.RosterMgmt.GetRankedPlayersForRole(role)
  -- Returns sorted array of players for the given role
  -- Sorted by ranking (descending)
  -- Only includes players assigned to that role
  
  local players = {}
  
  for name, data in pairs(OGRH_SV.rosterManagement.players) do
    -- Check if player has this role (primary or secondary)
    if data.primaryRole == role then
      table.insert(players, {
        name = name,
        class = data.class,
        ranking = data.rankings[role] or 1000,
        isPrimary = true
      })
    else
      -- Check secondary roles
      for _, secRole in ipairs(data.secondaryRoles or {}) do
        if secRole == role then
          table.insert(players, {
            name = name,
            class = data.class,
            ranking = data.rankings[role] or 1000,
            isPrimary = false
          })
          break
        end
      end
    end
  end
  
  -- Sort by ELO rating (descending - highest first)
  table.sort(players, function(a, b)
    return (a.ranking or 1000) > (b.ranking or 1000)
  end)
  
  return players
end
```

**RGO Usage**:
```lua
-- In OGRH_RGO.lua when building raid composition
local tanksNeeded = 2
local rankedTanks = OGRH.RosterMgmt.GetRankedPlayersForRole("TANKS")

-- Take top N players
for i = 1, math.min(tanksNeeded, table.getn(rankedTanks)) do
  local player = rankedTanks[i]
  -- Assign to tank slot
  OGRH.AssignPlayerToRole(player.name, "TANKS")
end
```

### 2. Encounter Auto-Assign Integration (OGRH_EncounterMgmt.lua)

**Purpose**: Use roster rankings when auto-assigning raid members to encounter roles

**Access Point**: `OGRH.RosterMgmt.GetBestPlayerForRole(role, excludeList)`

```lua
function OGRH.RosterMgmt.GetBestPlayerForRole(role, excludeList)
  -- Returns highest ranked available player for role
  -- Excludes players in excludeList
  -- Prioritizes primary role over secondary
  
  local rankedPlayers = OGRH.RosterMgmt.GetRankedPlayersForRole(role)
  excludeList = excludeList or {}
  
  for _, player in ipairs(rankedPlayers) do
    local excluded = false
    for _, name in ipairs(excludeList) do
      if player.name == name then
        excluded = true
        break
      end
    end
    
    if not excluded then
      return player
    end
  end
  
  return nil  -- No available players
end
```

### 3. RolesUI Synchronization

**Purpose**: Sync role assignments between RosterMgmt and RolesUI

**Behavior**:
- When player added to roster, check if they exist in RolesUI
- If yes, pre-populate their primary role from RolesUI
- When primary role changed in RosterMgmt, optionally update RolesUI
- Provide manual sync button

**Functions**:
```lua
function OGRH.RosterMgmt.SyncFromRolesUI()
  -- Import players from RolesUI into roster
end

function OGRH.RosterMgmt.SyncToRolesUI()
  -- Update RolesUI assignments based on roster primary roles
end
```

---

## Custom Sync System

### Sync Protocol

**Channel**: Addon message channel "OGRH_ROSTER"  
**Scope**: Raid only  
**Permissions**: Only Raid Admin (uses existing OGRH admin detection)

### Sync Flow

1. **Initiate Sync** (Raid Admin only):
   - Admin clicks "Sync" button
   - System calculates data checksum
   - Broadcasts sync offer to raid

2. **Offer Broadcast**:
   ```lua
   SendAddonMessage("OGRH_ROSTER", "SYNC_OFFER|version|checksum", "RAID")
   ```

3. **Opt-In Response**:
   - Each player receives offer
   - Shows confirmation dialog: "Raid leader wants to sync roster data. Accept?"
   - Player clicks Accept or Decline
   - If Accept, send response:
   ```lua
   SendAddonMessage("OGRH_ROSTER", "SYNC_ACCEPT|playerName", "RAID")
   ```

4. **Data Broadcast**:
   - Admin collects all accepts (wait 5 seconds)
   - Serializes roster data
   - Chunks data if needed (addon messages have size limits)
   - Broadcasts to raid:
   ```lua
   SendAddonMessage("OGRH_ROSTER", "SYNC_DATA|chunkNum|totalChunks|data", "RAID")
   ```

5. **Data Reception**:
   - Players who accepted reassemble chunks
   - Validate checksum
   - Merge data (overwrite or merge strategy TBD)
   - Show confirmation

### Sync UI

**Button Location**: Bottom toolbar, right side

**Context Menu** (right-click or shift-click):
- **Sync to Raid** (admin only)
- **View Sync Status**
- **Force Resync** (admin only)

**Sync Status Dialog**:
- Last sync time
- Current checksum
- Players who have data
- Sync version compatibility

---

## DPS Meter Integration

### Detection

**Priority Order**:
1. Check for ShaguDPS (simpler API)
2. Check for DPSMate (fallback)
3. If neither available, disable auto-ranking

```lua
function OGRH.RosterMgmt.DetectDPSMeter()
  if ShaguDPS and ShaguDPS.data then
    return "ShaguDPS"
  elseif DPSMateDamageDone and DPSMateUser then
    return "DPSMate"
  end
  return nil
end
```

### Data Extraction

#### From ShaguDPS

```lua
function OGRH.RosterMgmt.GetPerformanceFromShaguDPS(playerName, role)
  if not ShaguDPS or not ShaguDPS.data then return nil end
  
  local segment = 0  -- Overall data
  local performance = 0
  
  if role == "HEALERS" then
    -- Get healing data
    local healData = ShaguDPS.data.heal[segment][playerName]
    if healData then
      if OGRH_SV.rosterManagement.config.useEffectiveHealing then
        performance = healData["_esum"] or 0
      else
        performance = healData["_sum"] or 0
      end
    end
  else
    -- Get DPS data
    local damageData = ShaguDPS.data.damage[segment][playerName]
    if damageData then
      performance = damageData["_sum"] or 0
    end
  end
  
  return performance
end
```

#### From DPSMate

```lua
function OGRH.RosterMgmt.GetPerformanceFromDPSMate(playerName, role)
  if not DPSMateDamageDone or not DPSMateUser then return nil end
  
  local userId = nil
  for name, data in pairs(DPSMateUser) do
    if name == playerName then
      userId = data[1]
      break
    end
  end
  
  if not userId then return nil end
  
  local mode = 1  -- Total session
  local performance = 0
  
  if role == "HEALERS" then
    -- Get healing data
    local healData = OGRH_SV.rosterManagement.config.useEffectiveHealing 
      and DPSMateEHealing or DPSMateTHealing
    if healData[mode][userId] then
      performance = healData[mode][userId]["i"] or 0
    end
  else
    -- Get DPS data
    if DPSMateDamageDone[mode][userId] then
      performance = DPSMateDamageDone[mode][userId]["i"] or 0
    end
  end
  
  return performance
end
```

### Import Wizard

**Purpose**: Bulk import players from DPS meter data

**Flow**:
1. Open wizard dialog
2. Select data source (ShaguDPS/DPSMate)
3. Select segment (Overall, Current, specific segment)
4. Select roles to import (Healers, Melee, Ranged - not Tanks)
5. Set minimum threshold (e.g., only import players with >1000 DPS)
6. Preview list of players to import
7. Confirm import
8. Add players to roster, assign roles, initial rankings

---

## Menu Integration

### Settings Menu Location

**Path**: Main Menu → Settings → Roster Management

**Insert After**: "Raid Group Organization"  
**Insert Before**: "Data Management"

**Menu Item**:
```lua
-- In OGRH_MainUI.lua settings menu construction
{
  text = "Roster Management",
  func = function()
    OGRH.RosterMgmt.ShowWindow()
  end,
  tooltipTitle = "Roster Management",
  tooltipText = "Manage raid roster, assign roles, and set player rankings for auto-assign priority."
}
```

---

## Implementation Phases

### Phase 1: Core Data & UI (Week 1)

**Tasks**:
1. Create OGRH_RGO_Roster.lua file structure
2. Implement data structures and EnsureSV
3. Create main window with three panels using OGST
4. Implement role list (left panel)
5. Implement player list with basic display (center panel)
6. Add/remove player functionality
7. Manual ranking adjustment (up/down, direct edit)
8. Basic integration with menu system

**Deliverables**:
- Players can be added/removed manually
- Players can be assigned to roles
- ELO ratings can be adjusted manually (up/down buttons and direct edit)
- Configurable ELO adjustment amount
- Data persists across sessions

### Phase 2: Player Details & Role Management (Week 2)

**Tasks**:
1. Implement "All Players" view
2. Create Player Details panel
3. Primary/secondary role assignment UI
4. Notes field
5. Class detection and display
6. Role validation logic
7. Player list filtering and sorting

**Deliverables**:
- Complete role assignment interface
- Player details editing
- Class-colored player names
- Proper sorting in all views

### Phase 3: DPS Meter Integration (Week 3)

**Tasks**:
1. Implement DPS meter detection
2. ShaguDPS data extraction
3. DPSMate data extraction
4. Ranking history system
5. Aggregate ranking calculation
6. "Update Rankings" button
7. Import wizard UI and logic
8. Configuration panel for ranking settings

**Deliverables**:
- Automatic ELO rating updates from DPS meters
- Percentile-based ELO adjustment calculation
- Import wizard for bulk player addition
- Performance history tracking
- Configurable ELO settings (K-factor, manual adjustment amount)

### Phase 4: Sync System (Week 4)

**Tasks**:
1. Implement custom sync protocol
2. Data serialization/deserialization
3. Chunk handling for large datasets
4. Opt-in confirmation dialogs
5. Sync status tracking
6. Admin permission checks
7. Conflict resolution strategy

**Deliverables**:
- Working sync system
- Raid-wide roster sharing
- Admin controls
- Sync status visibility

### Phase 5: Integration & Polish (Week 5)

**Tasks**:
1. RGO integration (GetRankedPlayersForRole)
2. EncounterMgmt integration (GetBestPlayerForRole)
3. RolesUI sync functions
4. Error handling and validation
5. Tooltips and help text
6. Performance optimization
7. Bug fixes and testing

**Deliverables**:
- Complete RGO/Auto-Assign integration
- All error cases handled gracefully
- Polished UI with helpful tooltips
- Production-ready feature

---

## Open Questions & Future Considerations

### Questions to Resolve During Implementation

1. **ELO Edit Dialog**: Use inline EditBox vs modal dialog?
2. **Drag-and-Drop**: Worth implementing for easier reordering?
3. **Role Badges**: Use icons, text, or color coding?
4. **Conflict Resolution**: When syncing, how to handle local ELO changes vs incoming data?
5. **Performance**: How to handle large rosters (100+ players)?
6. **Validation**: Should we prevent duplicate names (server-realm)?
7. **K-Factor Tuning**: Should K-factor be adjustable per-role or global?
8. **ELO Floor/Ceiling**: Should there be min/max ELO limits to prevent extreme values?
9. **ELO Decay**: Should inactive players lose ELO over time?
10. **Initial Seeding**: Should imported players start at 1000 or be seeded based on first performance?

### Stretch Goals (Future Enhancements)

1. **Off-Spec Suggestions**: Suggest players with secondary roles when primary pool is exhausted
2. **Attendance Tracking**: Track raid participation history
3. **Performance Trends**: Graph player performance over time
4. **Batch Operations**: Multi-select for bulk operations
5. **Import from Guild**: Auto-import guild members with class detection
6. **Export/Import**: CSV or text-based backup/restore
7. **Mobile Companion**: Web interface for roster management
8. **Class Filters**: Filter player list by class
9. **Search Function**: Quick search for players by name
10. **Ranking Presets**: Save/load different ranking configurations

### Known Limitations

1. **Tanks**: No automated ranking (manual only by design)
2. **Cross-Realm**: May need special handling for name collisions
3. **Offline Data**: No performance data for offline players
4. **Historical Data**: Only tracks last N performances (configurable)
5. **Sync Size**: Large rosters may hit addon message size limits

---

## Testing Checklist

### Unit Testing

- [ ] Data structure initialization
- [ ] Player add/remove operations
- [ ] Ranking calculations
- [ ] Data serialization/deserialization
- [ ] Role assignment validation
- [ ] DPS meter data extraction

### Integration Testing

- [ ] Menu navigation
- [ ] Window open/close behavior
- [ ] RGO integration
- [ ] EncounterMgmt integration
- [ ] RolesUI sync
- [ ] Sync protocol

### UI Testing

- [ ] All panels render correctly
- [ ] Scrolling works properly
- [ ] Buttons respond appropriately
- [ ] Dialogs display correctly
- [ ] Tooltips show accurate information
- [ ] Class colors display correctly

### Compatibility Testing

- [ ] Works without DPSMate
- [ ] Works without ShaguDPS
- [ ] Works with DPSMate only
- [ ] Works with ShaguDPS only
- [ ] Works with both meters installed
- [ ] Lua 5.0 compatibility verified
- [ ] WoW 1.12 API compatibility

### Edge Cases

- [ ] Empty roster
- [ ] Single player
- [ ] 100+ players (performance)
- [ ] All players same ranking
- [ ] Player with no roles assigned
- [ ] Sync with no raid members
- [ ] Sync with incomplete data
- [ ] Import with invalid data

---

## Code Structure Template

```lua
-- OGRH_RGO_Roster.lua
-- Roster Management Module for OG-RaidHelper
-- Manages raid roster, role assignments, and player rankings

if not OGRH then
  DEFAULT_CHAT_FRAME:AddMessage("|cffff0000Error: OGRH_RGO_Roster requires OGRH_Core to be loaded first!|r")
  return
end

-- ============================================================================
-- NAMESPACE & CONSTANTS
-- ============================================================================

OGRH.RosterMgmt = OGRH.RosterMgmt or {}

local ROLES = { "TANKS", "HEALERS", "MELEE", "RANGED" }
local ROLE_NAMES = {
  TANKS = "Tanks",
  HEALERS = "Healers",
  MELEE = "Melee DPS",
  RANGED = "Ranged DPS"
}

-- ============================================================================
-- LOCAL VARIABLES
-- ============================================================================

local selectedRole = "TANKS"
local selectedPlayer = nil
local lastUpdate = 0
local updateInterval = 1

-- ============================================================================
-- SAVED VARIABLES MANAGEMENT
-- ============================================================================

function OGRH.RosterMgmt.EnsureSV()
  -- Implementation here
end

-- ============================================================================
-- DATA ACCESS FUNCTIONS
-- ============================================================================

function OGRH.RosterMgmt.AddPlayer(name, class)
  -- Implementation here
end

function OGRH.RosterMgmt.RemovePlayer(name)
  -- Implementation here
end

function OGRH.RosterMgmt.GetPlayer(name)
  -- Implementation here
end

function OGRH.RosterMgmt.UpdatePlayerRanking(name, role, ranking)
  -- Implementation here
end

-- ============================================================================
-- RANKING SYSTEM
-- ============================================================================

function OGRH.RosterMgmt.GetRankedPlayersForRole(role)
  -- Implementation here
end

function OGRH.RosterMgmt.AdjustRanking(name, role, delta)
  -- Implementation here
end

-- ============================================================================
-- DPS METER INTEGRATION
-- ============================================================================

function OGRH.RosterMgmt.DetectDPSMeter()
  -- Implementation here
end

function OGRH.RosterMgmt.UpdateRankingsFromMeter()
  -- Implementation here
end

-- ============================================================================
-- SYNC SYSTEM
-- ============================================================================

function OGRH.RosterMgmt.InitiateSync()
  -- Implementation here
end

function OGRH.RosterMgmt.HandleSyncMessage(message, sender)
  -- Implementation here
end

-- ============================================================================
-- UI CONSTRUCTION
-- ============================================================================

function OGRH.RosterMgmt.ShowWindow()
  -- Implementation here
end

function OGRH.RosterMgmt.CreateRoleList(parent)
  -- Implementation here using OGST
end

function OGRH.RosterMgmt.CreatePlayerList(parent)
  -- Implementation here using OGST
end

function OGRH.RosterMgmt.CreatePlayerDetailsPanel(parent)
  -- Implementation here using OGST
  -- Panel is always visible, populated based on selected player
end

function OGRH.RosterMgmt.UpdatePlayerDetailsPanel(playerName)
  -- Updates right panel with player data
  -- Called when player selection changes
end

function OGRH.RosterMgmt.ClearPlayerDetailsPanel()
  -- Shows placeholder when no player selected
end

-- ============================================================================
-- INTEGRATION POINTS
-- ============================================================================

function OGRH.RosterMgmt.GetBestPlayerForRole(role, excludeList)
  -- Implementation here
  -- Used by EncounterMgmt
end

function OGRH.RosterMgmt.SyncFromRolesUI()
  -- Implementation here
end

function OGRH.RosterMgmt.SyncToRolesUI()
  -- Implementation here
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

OGRH.RosterMgmt.EnsureSV()

-- Event frame for sync messages
local syncFrame = CreateFrame("Frame")
syncFrame:RegisterEvent("CHAT_MSG_ADDON")
syncFrame:SetScript("OnEvent", function()
  if event == "CHAT_MSG_ADDON" and arg1 == "OGRH_ROSTER" then
    OGRH.RosterMgmt.HandleSyncMessage(arg2, arg4)
  end
end)
```

---

## References

- **Main Integration**: OGRH_Core.lua, OGRH_MainUI.lua
- **RGO Integration**: OGRH_RGO.lua
- **Auto-Assign Integration**: OGRH_EncounterMgmt.lua
- **RolesUI Integration**: OGRH_RolesUI.lua
- **DPS Meter Notes**: IntegrationNotes-DPSMate.md, IntegrationNotes-ShaguDPS.md
- **OGST Library**: Libs/OGST/OGST.lua
- **Existing Patterns**: OGRH_Invites.lua (for list UI), OGRH_Sync.lua (for sync protocol)

---

**END OF DESIGN DOCUMENT**
