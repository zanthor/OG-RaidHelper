# OG-RaidHelper: Consume Tracking History Feature Design Document

**Version:** 1.0  
**Date:** January 7, 2026  
**Feature Code:** OGRH_ConsumesTracking (Enhancement)  
**Modified File:** OGRH_ConsumesTracking.lua

---

## CRITICAL IMPLEMENTATION CONSTRAINTS

**⚠️ ALL AI AGENTS IMPLEMENTING THIS FEATURE MUST FOLLOW THESE RULES:**

1. **Language Compatibility**: All code MUST be Lua 5.0 compatible (Turtle WoW 1.12 client)
   - Use `table.getn()` or manual counting, NOT `#table`
   - Use `string.find()`, NOT `string.match()` for simple patterns
   - Use `for i, item in ipairs(table)` for arrays
   - String patterns use Lua 5.0 syntax
   - No `continue` keyword (use nested if/else instead)

2. **UI Framework**: ALL interface components MUST use the OGST Library
   - Use `OGST.CreateStyledScrollList()` for both tracking history list and player details list
   - Use `OGST.CreateStyledListItem()` for all list entries
   - Use `OGST.AddListItemButtons()` for delete controls
   - Follow CRITICAL closure scoping rules documented in OGST.lua (lines 1191-1227)
   - Store data as frame properties, use `this` keyword in event handlers

3. **Integration Points**:
   - Use existing `OGRH.GetSelectedRaidAndEncounter()` to retrieve raid/encounter selection from main UI
   - Use existing `OGRH.GetClassColor(className)` for class-colored player names
   - Reference RABuffs_Logger addon for pull detection trigger pattern
   - Use existing `CT.CalculatePlayerScore()` function for scoring

4. **Code Style**: Follow existing OG-RaidHelper conventions
   - Use `CT.` namespace for module-internal functions (ConsumesTracking)
   - Use `OGRH.ConsumesTracking.` for public API functions
   - Include comprehensive comments explaining complex logic
   - Follow existing patterns in OGRH_ConsumesTracking.lua

---

## Feature Overview

**Purpose**: Provide historical tracking of raid consumables usage across multiple raid encounters, allowing raid leaders to review past performance and identify consumption trends.

**Location**: Settings → Track Consumes → "Tracking" panel (renamed from "Enable Tracking")

**Primary Use Cases**:
1. Automatically capture consume scores when raid encounters are pulled
2. Store up to 50 historical records with raid/encounter context
3. Review past consume performance by raid and encounter
4. Identify players with consistent low consume scores across multiple raids
5. Delete outdated or incorrect tracking records

---

## Data Structure

### SavedVariables Storage

**Variable Name**: `OGRH_SV.consumesTracking.history`  
**Scope**: SavedVariables (account-wide, shared across all characters)

```lua
OGRH_SV.consumesTracking.history = {
  -- Array of tracking records (max 50)
  -- Most recent records at the beginning (index 1)
  -- Oldest records at the end (trimmed when exceeding 50)
  {
    timestamp = 1704672345,  -- Unix timestamp (os.time())
    date = "01/07",          -- MM/DD format
    time = "14:32",          -- HH:MM format (24-hour)
    raid = "Molten Core",    -- Raid name from main UI selection
    encounter = "Ragnaros",  -- Encounter name from main UI selection
    players = {              -- Array of player records
      {
        name = "Tankadin",
        class = "PALADIN",
        role = "TANKS",      -- Role from RolesUI at time of capture
        score = 95           -- Consume score from CT.CalculatePlayerScore()
      },
      {
        name = "Holypriest",
        class = "PRIEST",
        role = "HEALERS",
        score = 87
      },
      -- ... more players
    }
  },
  -- ... more records (up to 50 total)
}
```

### Data Initialization

```lua
function CT.EnsureSavedVariables()
  -- Existing initialization code...
  
  -- Ensure history table exists
  if not OGRH_SV.consumesTracking.history then
    OGRH_SV.consumesTracking.history = {}
  end
end
```

### Record Management

**Maximum Records**: 50  
**Trim Strategy**: When adding 51st record, remove oldest (last in array)  
**Sort Order**: Chronological, newest first (index 1)

---

## UI Layout Changes

### Current "Enable Tracking" Panel

**Current Location**: OGRH_ConsumesTracking.lua (lines 216-260)  
**Current Content**:
- "Track on Pull" checkbox
- "Seconds before pull" text input
- Description text

### New "Tracking" Panel Layout

**Panel Name**: "Tracking" (renamed from "Enable Tracking")  
**Layout**: Three sections stacked vertically

```
┌─────────────────────────────────────────────────────────────┐
│ Tracking                                                    │
├─────────────────────────────────────────────────────────────┤
│ Section 1: Track on Pull Controls (EXISTING)               │
│ ┌─────────────────────────────────────────────────────────┐ │
│ │ ☑ Track on Pull                                         │ │
│ │ Seconds before pull: [2]                                │ │
│ │ Automatically capture consume scores when encounters... │ │
│ └─────────────────────────────────────────────────────────┘ │
│                                                             │
│ Section 2: History List (NEW - Left Panel)                 │
│ ┌───────────────────────────┬───────────────────────────┐   │
│ │ Tracking History          │ Player Scores             │   │
│ ├───────────────────────────┼───────────────────────────┤   │
│ │ 01/07 14:32 MC Ragnaros   │ [T] 95  Tankadin          │   │
│ │   [Delete]                │ [T] 92  Wartank           │   │
│ │                           │ [H] 87  Holypriest        │   │
│ │ 01/07 13:15 MC Lucifron   │ [H] 85  Holypally         │   │
│ │   [Delete]                │ [M] 78  Rogue1            │   │
│ │                           │ [M] 76  Rogue2            │   │
│ │ 01/06 20:45 BWL Vael      │ [R] 82  Mage1             │   │
│ │   [Delete]                │ [R] 80  Mage2             │   │
│ │                           │                           │   │
│ │ ...                       │ ...                       │   │
│ └───────────────────────────┴───────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### Panel Dimensions

**Track on Pull Controls Section**:
- Height: Auto (based on existing content, approximately 80px)
- Position: Top of detail panel
- Spacing: 10px below section

**History Lists Section**:
- Total Width: Detail panel width (inherited from parent)
- Total Height: Remaining space to bottom of detail panel
- Left List Width: 45% of total width
- Right List Width: 55% of total width
- Gap between lists: 10px
- Both lists use `OGST.CreateStyledScrollList()`

---

## History List (Left Panel)

### List Configuration

**Component**: `OGST.CreateStyledScrollList(parent, width, height)`  
**Sort Order**: Chronological descending (newest first)  
**Selection**: Single selection, highlights selected row

### List Item Format

**Display Format**: `MM/DD HH:MM RAID ENCOUNTER`

**Examples**:
- `01/07 14:32 Molten Core Ragnaros`
- `01/07 13:15 Molten Core Lucifron`
- `01/06 20:45 Blackwing Lair Vaelastrasz`

**Text Truncation**:
- If combined raid + encounter name exceeds available width, truncate with "..."
- Prioritize showing date/time completely
- Example: `01/07 14:32 Molten Core Rag...`

### List Item Creation

**Component**: `OGST.CreateStyledListItem()`

**Pattern** (following OGST closure scoping rules):
```lua
-- CORRECT: Store data on frame, use 'this' in handlers
for i, record in ipairs(OGRH_SV.consumesTracking.history) do
  local item = OGST.CreateStyledListItem(scrollChild, width, height)
  
  -- Store record data on frame
  item.recordIndex = i
  item.timestamp = record.timestamp
  
  -- Create text display
  local label = item:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  label:SetPoint("LEFT", item, "LEFT", 5, 0)
  label:SetText(string.format("%s %s %s %s", 
    record.date, record.time, record.raid, record.encounter))
  
  -- OnClick handler uses 'this'
  item:SetScript("OnClick", function()
    CT.SelectHistoryRecord(this.recordIndex)
  end)
  
  -- Add delete button
  local deleteBtn = OGST.AddListItemButtons(item, i, totalRecords, 
    nil, nil, -- no up/down
    function() CT.DeleteHistoryRecord(this.recordIndex) end,
    true -- hide up/down buttons
  )
end
```

### Delete Functionality

**Button**: Red "X" button on right side of each list item  
**Implementation**: `OGST.AddListItemButtons()` with `hideUpDown = true`  
**Behavior**:
1. Click delete button shows confirmation dialog
2. Confirmation dialog: "Delete tracking record from MM/DD HH:MM RAID ENCOUNTER?"
3. On confirm: Remove record from `OGRH_SV.consumesTracking.history`
4. Refresh both history list and player list (clear selection)

**Confirmation Dialog**:
```lua
-- Use OGST.CreateDialog()
local dialogTable = OGST.CreateDialog({
  title = "Delete Record",
  width = 400,
  height = 150,
  content = string.format("Delete tracking record from %s %s %s %s?", 
    record.date, record.time, record.raid, record.encounter),
  buttons = {
    {text = "Delete", onClick = function() CT.ConfirmDeleteRecord(recordIndex) end},
    {text = "Cancel", onClick = function() backdrop:Hide() end}
  },
  escapeCloses = true
})
```

---

## Player Scores List (Right Panel)

### List Configuration

**Component**: `OGST.CreateStyledScrollList(parent, width, height)`  
**Visibility**: Only populates when history record selected  
**Default State**: Shows message "Select a tracking record to view player scores"

### List Item Format

**Display Format**: `[ROLE_LETTER] SCORE Playername`

**Role Letters**:
- `T` = Tanks
- `H` = Healers
- `M` = Melee
- `R` = Ranged

**Examples**:
- `[T] 95  Tankadin` (Paladin - gold color)
- `[H] 87  Holypriest` (Priest - white color)
- `[M] 78  Rogue1` (Rogue - yellow color)
- `[R] 82  Mage1` (Mage - cyan color)

**Sort Order**:
1. Primary: Role (Tanks → Healers → Melee → Ranged)
2. Secondary: Score (descending, highest first)
3. Tertiary: Name (alphabetical)

### Player Name Coloring

**Color Source**: Use existing `OGRH.GetClassColor(className)` function

**Reference Pattern** (from main addon):
```lua
-- Get class color from cached data
local classColor = OGRH.GetClassColor(player.class)
if classColor then
  playerNameText:SetTextColor(classColor.r, classColor.g, classColor.b)
else
  playerNameText:SetTextColor(1, 1, 1) -- White fallback
end
```

### List Item Creation

**Pattern** (following OGST closure scoping rules):
```lua
-- Sort players by role and score
local sortedPlayers = CT.SortPlayersByRoleAndScore(selectedRecord.players)

for i, player in ipairs(sortedPlayers) do
  local item = OGST.CreateStyledListItem(scrollChild, width, height)
  
  -- Store player data on frame
  item.playerName = player.name
  item.playerClass = player.class
  
  -- Create role/score label
  local roleLabel = item:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  roleLabel:SetPoint("LEFT", item, "LEFT", 5, 0)
  roleLabel:SetText(string.format("[%s] %d  ", 
    CT.GetRoleLetterShort(player.role), player.score))
  roleLabel:SetTextColor(1, 1, 1)
  
  -- Create player name label (class colored)
  local nameLabel = item:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  nameLabel:SetPoint("LEFT", roleLabel, "RIGHT", 0, 0)
  nameLabel:SetText(player.name)
  
  local classColor = OGRH.GetClassColor(player.class)
  if classColor then
    nameLabel:SetTextColor(classColor.r, classColor.g, classColor.b)
  else
    nameLabel:SetTextColor(1, 1, 1)
  end
  
  -- No click handler needed (informational only)
end
```

### Role Letter Helper

**Function**: `CT.GetRoleLetterShort(role)`

**Implementation**:
```lua
function CT.GetRoleLetterShort(role)
  if role == "TANKS" then return "T"
  elseif role == "HEALERS" then return "H"
  elseif role == "MELEE" then return "M"
  elseif role == "RANGED" then return "R"
  else return "?" end
end
```

---

## Tracking Trigger System

### Reference Implementation

**Source**: RABuffs_Logger addon (already installed in workspace)  
**Pattern**: Pull detection via combat log events

**Key Components to Duplicate**:
1. Combat log event registration (`CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE`)
2. Boss engagement detection (specific creature names)
3. Pre-pull timing window (X seconds before pull)
4. Raid roster snapshot at trigger time

### Integration with Track on Pull

**Setting**: `OGRH_SV.consumesTracking.trackOnPull` (boolean)  
**Setting**: `OGRH_SV.consumesTracking.secondsBeforePull` (number, default 2)

**Existing UI Location**: OGRH_ConsumesTracking.lua (lines 216-260)

### Trigger Flow

```
1. Combat log event fires (creature spell cast detected)
   ↓
2. Check if trackOnPull enabled
   ↓
3. Parse creature name from combat log
   ↓
4. Check if creature matches known boss list
   ↓
5. Check if currently in raid
   ↓
6. Check if raid/encounter selected in main UI
   ↓
7. Schedule capture after secondsBeforePull delay
   ↓
8. Capture consume scores for all raid members
   ↓
9. Create tracking record
   ↓
10. Store record in OGRH_SV.consumesTracking.history
   ↓
11. Trim history if > 50 records
   ↓
12. Refresh UI if tracking panel open
```

### Event Registration

**Pattern**:
```lua
function CT.Initialize()
  -- Existing initialization...
  
  -- Register for combat log events (pull detection)
  trackConsumesFrame:RegisterEvent("CHAT_MSG_SPELL_CREATURE_VS_CREATURE_DAMAGE")
  trackConsumesFrame:RegisterEvent("CHAT_MSG_SPELL_CREATURE_VS_CREATURE_BUFF")
  trackConsumesFrame:SetScript("OnEvent", CT.OnPullDetectionEvent)
end
```

### Pull Detection Handler

**Function**: `CT.OnPullDetectionEvent(event, arg1, arg2, ...)`

**Logic**:
1. Check if `OGRH_SV.consumesTracking.trackOnPull` is enabled
2. Parse combat log message to extract creature name
3. Cross-reference creature name against known boss list
4. If boss detected and not already tracking this pull:
   - Get current raid/encounter selection from main UI
   - Schedule capture timer (delay by `secondsBeforePull`)
   - Set flag to prevent duplicate captures for same pull

### Known Boss List

**Storage**: Module-level table (not saved)

**Initial List** (can be expanded later):
```lua
local KNOWN_BOSSES = {
  -- Molten Core
  ["Lucifron"] = true,
  ["Magmadar"] = true,
  ["Gehennas"] = true,
  ["Garr"] = true,
  ["Shazzrah"] = true,
  ["Baron Geddon"] = true,
  ["Sulfuron Harbinger"] = true,
  ["Golemagg the Incinerator"] = true,
  ["Majordomo Executus"] = true,
  ["Ragnaros"] = true,
  
  -- Blackwing Lair
  ["Razorgore the Untamed"] = true,
  ["Vaelastrasz the Corrupt"] = true,
  ["Broodlord Lashlayer"] = true,
  ["Firemaw"] = true,
  ["Ebonroc"] = true,
  ["Flamegor"] = true,
  ["Chromaggus"] = true,
  ["Nefarian"] = true,
  
  -- Add more as needed
}
```

### Capture Function

**Function**: `CT.CaptureConsumesSnapshot()`

**Logic**:
```lua
function CT.CaptureConsumesSnapshot()
  -- Get raid/encounter selection from main UI
  local raid, encounter = OGRH.GetSelectedRaidAndEncounter()
  if not raid or not encounter then
    return -- Can't track without raid/encounter context
  end
  
  -- Build raid data structure (reuse existing code)
  local raidData = CT.BuildRaidDataStructure()
  
  -- Calculate scores for all raid members
  local players = {}
  for playerName, data in pairs(raidData) do
    local score = CT.CalculatePlayerScore(playerName, data.class, raidData)
    local role = OGRH_SV.roles and OGRH_SV.roles[playerName] or "UNKNOWN"
    
    table.insert(players, {
      name = playerName,
      class = data.class,
      role = role,
      score = score or 0
    })
  end
  
  -- Create tracking record
  local record = {
    timestamp = os.time(),
    date = date("%m/%d"),
    time = date("%H:%M"),
    raid = raid,
    encounter = encounter,
    players = players
  }
  
  -- Insert at beginning of history (newest first)
  table.insert(OGRH_SV.consumesTracking.history, 1, record)
  
  -- Trim to 50 records
  while table.getn(OGRH_SV.consumesTracking.history) > 50 do
    table.remove(OGRH_SV.consumesTracking.history)
  end
  
  -- Refresh UI if open
  CT.RefreshTrackingHistoryLists()
  
  -- Announce to chat
  OGRH.Msg(string.format("Captured consume scores for %s - %s (%d players)", 
    raid, encounter, table.getn(players)))
end
```

---

## Helper Functions

### Get Selected Raid and Encounter

**Function**: `OGRH.GetSelectedRaidAndEncounter()`

**Expected Return**: `raid, encounter` (strings)

**Integration Point**: This function should already exist in main UI module. If not, it needs to be created to expose the current dropdown selections.

### Sort Players by Role and Score

**Function**: `CT.SortPlayersByRoleAndScore(players)`

**Implementation**:
```lua
function CT.SortPlayersByRoleAndScore(players)
  local sorted = {}
  for i, player in ipairs(players) do
    table.insert(sorted, player)
  end
  
  -- Define role order
  local roleOrder = {TANKS = 1, HEALERS = 2, MELEE = 3, RANGED = 4}
  
  table.sort(sorted, function(a, b)
    -- Primary: Role
    local roleA = roleOrder[a.role] or 999
    local roleB = roleOrder[b.role] or 999
    if roleA ~= roleB then return roleA < roleB end
    
    -- Secondary: Score (descending)
    if a.score ~= b.score then return a.score > b.score end
    
    -- Tertiary: Name (alphabetical)
    return a.name < b.name
  end)
  
  return sorted
end
```

### Select History Record

**Function**: `CT.SelectHistoryRecord(recordIndex)`

**Implementation**:
```lua
function CT.SelectHistoryRecord(recordIndex)
  -- Update selected index
  CT.selectedRecordIndex = recordIndex
  
  -- Highlight selected item in history list
  CT.RefreshHistoryListSelection()
  
  -- Populate player scores list
  CT.RefreshPlayerScoresList(recordIndex)
end
```

### Delete History Record

**Function**: `CT.DeleteHistoryRecord(recordIndex)`

**Implementation**:
```lua
function CT.DeleteHistoryRecord(recordIndex)
  -- Remove record from history
  table.remove(OGRH_SV.consumesTracking.history, recordIndex)
  
  -- Clear selection
  CT.selectedRecordIndex = nil
  
  -- Refresh both lists
  CT.RefreshTrackingHistoryLists()
end
```

---

## UI Refresh Functions

### Refresh History List

**Function**: `CT.RefreshHistoryList()`

**Purpose**: Rebuild left panel list with current history records

**Called When**:
- Tracking panel opened
- New record captured
- Record deleted
- Manual refresh

### Refresh Player Scores List

**Function**: `CT.RefreshPlayerScoresList(recordIndex)`

**Purpose**: Populate right panel with players from selected record

**Called When**:
- History record selected
- Record deleted (clear list)

### Refresh Tracking History Lists (Combined)

**Function**: `CT.RefreshTrackingHistoryLists()`

**Purpose**: Refresh both lists together

**Implementation**:
```lua
function CT.RefreshTrackingHistoryLists()
  CT.RefreshHistoryList()
  
  if CT.selectedRecordIndex then
    CT.RefreshPlayerScoresList(CT.selectedRecordIndex)
  else
    CT.ClearPlayerScoresList()
  end
end
```

---

## Panel Reconstruction Logic

### Modify UpdateDetailPanel

**Location**: OGRH_ConsumesTracking.lua (function CT.UpdateDetailPanel, lines 189-879)

**Current "Enable Tracking" Section**: Lines 216-260

**Changes Required**:

1. **Rename section**: "Enable Tracking" → "Tracking"

2. **Keep existing Track on Pull controls** at top:
   - Checkbox
   - Text input
   - Description

3. **Add dual list panel below**:
   - Create container for both lists
   - Anchor to bottom of Track on Pull controls
   - Use `OGST.CreateStyledScrollList()` for each list
   - Store list references for refresh functions

4. **Store list frame references**:
```lua
-- Store at module level for refresh access
CT.historyListFrame = nil
CT.playerScoresListFrame = nil
CT.selectedRecordIndex = nil
```

---

## Testing Checklist

### Manual Testing Requirements

1. **History Capture**:
   - Enable "Track on Pull"
   - Join raid, select raid/encounter
   - Pull boss, verify record captured after delay
   - Check record appears in history list
   - Verify timestamp, raid, encounter correct

2. **History List Display**:
   - Add multiple records (different raids/encounters)
   - Verify chronological sort (newest first)
   - Verify date/time format correct
   - Test text truncation for long names

3. **Record Selection**:
   - Click history record
   - Verify player scores list populates
   - Verify class colors display correctly
   - Verify role/score sort order

4. **Record Deletion**:
   - Click delete button
   - Verify confirmation dialog appears
   - Confirm deletion
   - Verify record removed from list
   - Verify player scores list clears

5. **Max Records Trim**:
   - Add 51+ records manually (via lua command)
   - Verify oldest record removed automatically
   - Verify count stays at 50

6. **Pull Detection**:
   - Test with known bosses from list
   - Test with unknown creatures (should not trigger)
   - Test secondsBeforePull delay accuracy
   - Test duplicate pull prevention

7. **UI Integration**:
   - Open/close tracking panel multiple times
   - Verify lists persist correctly
   - Test with no records (empty state)
   - Test with no selection (default message)

---

## Implementation Phases

### Phase 1: Data Structure and Storage
- Add `history` table to SavedVariables
- Implement record creation function
- Implement max 50 trim logic
- Implement delete function

### Phase 2: UI Layout Changes
- Rename "Enable Tracking" to "Tracking"
- Create dual list panel container
- Implement history list (left panel)
- Implement player scores list (right panel)
- Add delete buttons to history items

### Phase 3: Pull Detection System
- Register combat log events
- Implement boss detection logic
- Implement capture timer
- Integrate with track on pull settings

### Phase 4: Integration and Polish
- Connect to main UI for raid/encounter selection
- Implement class coloring
- Implement list sorting
- Add refresh functions
- Test all scenarios

---

## Dependencies and Integration Points

### Required Existing Functions

1. **Main UI**:
   - `OGRH.GetSelectedRaidAndEncounter()` - Must exist or be created

2. **Core Addon**:
   - `OGRH.GetClassColor(className)` - Should exist, verify location

3. **Roles System**:
   - `OGRH_SV.roles[playerName]` - Already exists

4. **Consumes Tracking**:
   - `CT.CalculatePlayerScore()` - Already exists (line 1047)
   - `CT.BuildRaidDataStructure()` - Already exists (used in PollConsumes)

### RABuffs_Logger Reference

**Location**: Workspace should contain RABuffs_Logger addon for reference

**Files to Study**:
- Event registration patterns
- Combat log parsing
- Boss detection logic
- Timing/delay mechanisms

**Note**: Do not copy code directly; adapt patterns to OG-RaidHelper style and OGST library usage.

---

## Success Criteria

✅ **History records captured automatically on boss pulls**  
✅ **Up to 50 records stored, oldest auto-trimmed**  
✅ **History list displays chronologically with delete controls**  
✅ **Player scores list populates on selection with correct sorting**  
✅ **Class colors display correctly for player names**  
✅ **Pull detection works reliably with configurable delay**  
✅ **UI integrates seamlessly with existing tracking panel**  
✅ **All code follows Lua 5.0 and OGST patterns**  
✅ **No errors in WoW 1.12 client**
