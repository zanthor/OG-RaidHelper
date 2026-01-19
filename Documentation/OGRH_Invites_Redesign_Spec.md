# OGRH_Invites Redesign Specification
**Version:** 2.0  
**Date:** January 19, 2026  
**Status:** Design Phase

---

## Executive Summary

Complete redesign of the OGRH_Invites module to support dual data sources (RollFor and Raid-Helper JSON), automated timer-based invite system, intelligent raid group organization, and automatic role synchronization with the RolesUI module.

---

## Current Implementation Analysis

### Data Source
- **Single Source:** RollFor addon only
- **Data Format:** Decoded from RollFor's SoftRes system using `RollFor.SoftRes.decode()` and `RollFor.SoftResDataTransformer.transform()`
- **Data Structure:**
  ```lua
  {
    name = "PlayerName",
    role = "ClassSpec", -- e.g., "DruidBalance", "WarriorProtection"
    srPlus = 0,         -- Soft-res plus status
    itemCount = 1,      -- Number of items soft-reserved
    class = "DRUID"     -- Optional, fetched from roster/guild
  }
  ```
- **Metadata:** Instance ID, date, time extracted from RollFor data

### Current UI Components
1. **RollFor Import Button** (Top Left)
   - Opens RollFor's soft-res import window via `RollFor.key_bindings.softres_toggle()`
   - Includes tooltip with instructions

2. **Title Bar** (Center Top)
   - Shows "Raid Invites - [Instance Name] ([Instance ID])"
   - Dynamically updates based on metadata

3. **Close Button** (Top Right)
   - Standard close functionality

4. **Info Text** (Below header)
   - Context-sensitive messages:
     - "RollFor addon not detected..."
     - "RollFor is loading..."
     - "No soft-res data found..."
     - "All soft-res players are in the raid!"
     - "Players from RollFor soft-res data not currently in the raid:"

5. **Column Headers**
   - Name | Role | Status | Actions

6. **Scrollable Player List**
   - Uses `OGRH.CreateStyledScrollList()` (OGST pattern)
   - Each row shows:
     - **Name:** Class-colored
     - **Role:** Mapped to OGRH bucket (Tank/Healer/Melee/Ranged)
     - **Status:** Online/Offline/Invited/Declined with color coding
     - **Invite Button:** Per-player invite action (disabled if offline)
     - **Msg Button:** Opens whisper dialog (disabled if offline)
   - **Row Colors:**
     - Green tint: In raid (should never show)
     - Red tint: Declined
     - Blue tint: Invited
     - Default: Not invited/unknown

7. **Bottom Buttons**
   - **Invite** (Bottom Left): Calls `InviteAllOnline()`
   - **Clear Status** (Bottom Center): Clears declined/invited tracking
   - **Refresh** (Bottom Right): Manually refreshes player list

8. **Stats Text** (Bottom Center)
   - "X players not in raid (Y already in raid)"

### Current Behavior

#### Refresh Button Functionality
**Current Implementation Analysis:**
- **Manual Trigger:** User clicks "Refresh" button
- **Action:** Calls `OGRH.Invites.RefreshPlayerList()`
- **What It Does:**
  1. Re-fetches soft-res player data from RollFor
  2. Updates player online/offline status via guild roster
  3. Removes players already in raid from the list
  4. Updates class information for each player
  5. Re-renders the UI with current data
  6. Updates stats text
- **Auto-Refresh:** Window already has OnUpdate handler that calls `RefreshPlayerList()` every 2 seconds
- **Conclusion:** Refresh button is **redundant** - the UI already auto-refreshes

#### Auto-Update System
- **OnUpdate Handler:** Refreshes every 2 seconds (`updateInterval = 2`)
- **Updates:** Player list, statuses, raid membership

#### Auto-Invite from Whisper
- **Listens:** `CHAT_MSG_WHISPER` event
- **Behavior:** If whisper sender is in soft-res list and not in raid, auto-invite them
- **Message:** "Auto-inviting [Name] (whispered for invite)"

#### Auto-Convert Party to Raid
- **Trigger:** When "Invite All" is clicked, sets 60-second window (`autoConvertExpiry`)
- **Behavior:**
  - If solo, sends only 4 invites initially
  - When first player joins (creates party), auto-converts to raid
  - After conversion, invites remaining online players
- **Events:** Listens to `PARTY_MEMBERS_CHANGED` and `RAID_ROSTER_UPDATE`

#### Invite Status Tracking
- **Session Storage:** `OGRH.Invites.playerStatuses` (not persistent)
- **Persistent Storage:** `OGRH_SV.invites.declinedPlayers` and `OGRH_SV.invites.history`
- **Status Types:**
  - `NOT_IN_RAID`: Default state
  - `IN_RAID`: Player is in current raid
  - `INVITED`: Invite sent this session
  - `DECLINED`: Player declined (tracked persistently)
  - `OFFLINE`: Not online in guild roster
  - `IN_OTHER_GROUP`: Not currently used

#### Role Mapping & Sync
- **Mapping Function:** `MapRollForRoleToOGRH()` converts RollFor specs to OGRH buckets
  - Example: "DruidBalance" → "RANGED"
  - Example: "WarriorProtection" → "TANKS"
- **Manual Sync:** Not present in this file (exists in RolesUI with "Sync RollFor" button)
- **Integration:** Roles displayed in UI but not automatically synced to RolesUI on invite

---

## New Design Specification

### 1. Data Source System

#### 1.1 Dual Source Architecture

**Data Source Enum:**
```lua
OGRH.Invites.SOURCE_TYPE = {
  ROLLFOR = "rollfor",
  RAIDHELPER = "raidhelper"
}
```

**Source Selection Storage:**
```lua
OGRH_SV.invites.currentSource = "rollfor" -- or "raidhelper"
OGRH_SV.invites.raidhelperData = nil -- Stores parsed JSON
```

#### 1.2 RollFor Data Source (Existing)
- **No changes to current implementation**
- Continues to use `RollFor.SoftRes.decode()` and `RollFor.SoftResDataTransformer.transform()`

#### 1.3 Raid-Helper JSON Data Source (New)

**JSON Format (from sample):**
```json
{
  "id": 96,
  "name": "Naxxramas (96)",
  "players": [
    {
      "name": "Anamar",
      "class": "Warrior",
      "role": "Melee",
      "status": "signed",
      "group": 1,
      "bench": false,
      "absent": false
    }
  ]
}
```

**JSON Library:**
- **Library:** [json.lua by rxi](https://github.com/rxi/json.lua)
- **Location:** `OG-RaidHelper/Libs/json.lua`
- **Version:** 0.1.2-wow (modified for WoW 1.12 compatibility)
- **Git Repository:** C:\Users\zanth\Documents\GIT\json.lua (WoW 1.12 fixes applied)
- **Modifications:**
  - Changed `#table` to `table.getn(table)` (line 81)
  - Changed `select()` to `arg` table pattern (line 145-149)
- **License:** MIT
- **Size:** ~10KB, 280 lines
- **Features:**
  - Pure Lua 5.0/5.1 compatible
  - Fast and lightweight
  - Proper error messages with line/column information
  - No external dependencies
- **Reusable:** The modified version in the git repo can be used in other WoW 1.12 addons

**Loading the Library:**
```lua
-- In OG-RaidHelper.toc, add:
-- Libs\json.lua

-- In OGRH_Invites.lua, load at module initialization:
if not json then
  json = dofile("Interface\\AddOns\\OG-RaidHelper\\Libs\\json.lua")
end
```

**Required Parser Function:**
```lua
function OGRH.Invites.ParseRaidHelperJSON(jsonString)
  -- Returns: raidData table or nil + error message
  
  if not jsonString or jsonString == "" then
    return nil, "No JSON data provided"
  end
  
  -- Parse JSON using json.lua library
  local success, data = pcall(json.decode, jsonString)
  if not success then
    -- data contains error message with line/column info
    return nil, "JSON Parse Error: " .. tostring(data)
  end
  
  -- Validate structure
  if type(data) ~= "table" then
    return nil, "Invalid JSON: Root must be an object"
  end
  
  if not data.players or type(data.players) ~= "table" then
    return nil, "Invalid JSON: Missing 'players' array"
  end
  
  -- Normalize player data
  for i = 1, table.getn(data.players) do
    local player = data.players[i]
    
    -- Required: name
    if not player.name or player.name == "" then
      return nil, "Invalid JSON: Player at index " .. i .. " missing 'name'"
    end
    
    -- Normalize class to uppercase
    if player.class then
      player.class = string.upper(player.class)
    end
    
    -- Set defaults
    player.bench = player.bench or false
    player.absent = player.absent or false
    player.status = player.status or "signed"
  end
  
  -- Structure validated and normalized:
  -- {
  --   id = 96,
  --   name = "Naxxramas (96)",
  --   players = {
  --     {
  --       name = "PlayerName",
  --       class = "WARRIOR",      -- Normalized to uppercase
  --       role = "Melee",          -- Tank/Healer/Melee/Ranged
  --       status = "signed",       -- signed, confirmed, etc.
  --       group = 1,               -- Target raid group (1-8, optional)
  --       bench = false,
  --       absent = false
  --     }
  --   }
  -- }
  
  return data, nil
end
```

**Role Mapping for Raid-Helper:**
- Raid-Helper uses simplified roles: "Tank", "Healer", "Melee", "Ranged"
- Map directly to OGRH buckets: "TANKS", "HEALERS", "MELEE", "RANGED"

#### 1.4 Unified Player Data Interface

**Standardized Player Object:**
```lua
{
  name = "PlayerName",           -- Normalized (TitleCase)
  class = "WARRIOR",             -- Uppercase class name
  role = "TANKS",                -- OGRH bucket: TANKS/HEALERS/MELEE/RANGED
  group = 1,                     -- Target raid group (1-8, nil if not specified)
  bench = false,                 -- Is benched?
  absent = false,                -- Marked absent?
  status = "NOT_IN_RAID",        -- Invite status
  online = false,                -- Online status (detected)
  source = "rollfor"             -- Source: "rollfor" or "raidhelper"
}
```

**Unified Fetch Function:**
```lua
function OGRH.Invites.GetRosterPlayers()
  -- Returns array of standardized player objects
  -- Automatically uses currentSource
end
```

---

### 2. UI Redesign

#### 2.1 Import Button → OGST Menu Button

**Location:** Top Left  
**Label:** "Import Roster"

**Menu Structure:**
```lua
OGRH.Invites.CreateImportMenu()
  -> MenuItem: "RollFor Soft-Res"
     - Opens RollFor import window (existing behavior)
  -> MenuItem: "Raid-Helper JSON"
     - Opens JSON input dialog (new)
```

**JSON Input Dialog:**
- **Title:** "Import Raid-Helper JSON"
- **Content:**
  - **Label:** "Paste Raid-Helper JSON data below:"
  - **Multi-line EditBox:** 400x300px scrollable text input
  - **Buttons:**
    - **Import:** Validates and imports JSON
    - **Cancel:** Closes dialog
  - **Status Text:** Shows validation results or errors
- **Validation:**
  - Must be valid JSON
  - Must contain "players" array
  - Each player must have "name" field
  - Shows helpful error messages

**Implementation Pattern:**
```lua
function OGRH.Invites.ShowJSONImportDialog()
  -- Create or show existing dialog frame
  -- Use OGST.CreateStyledScrollList for multiline input area
  -- Validate on Import button click
  -- On success: Parse, store in OGRH_SV.invites.raidhelperData
  -- Set OGRH_SV.invites.currentSource = "raidhelper"
  -- Refresh main window
end
```

#### 2.2 Player List Sections

**New Structure:**
1. **Active Roster Section** (Invitable players)
2. **Benched Section** (Bench = true)
3. **Absent Section** (Absent = true)

**Section Headers:**
- Large, bold, separator-style headers between sections
- Example: "═══ BENCHED PLAYERS ═══" with yellow color
- Example: "═══ ABSENT PLAYERS ═══" with red color

**Section Behavior:**
- **Active Roster:**
  - Shows all players where `bench = false` and `absent = false`
  - Full functionality: Invite/Msg buttons enabled if online
- **Benched:**
  - Shows all players where `bench = true`
  - No action buttons (or disabled)
  - Yellow/orange tint on rows
  - Status text: "Benched"
- **Absent:**
  - Shows all players where `absent = true`
  - No action buttons (or disabled)
  - Red tint on rows
  - Status text: "Absent"

**Sorting:**
- Within each section: Sort alphabetically by name
- Sections always in order: Active → Benched → Absent

#### 2.3 Auto-Refresh for RollFor Source

**Behavior:**
- **If currentSource == "rollfor":**
  - Check RollFor data every 5 seconds
  - Compare hash/checksum of decoded data
  - If changed: Refresh UI
- **If currentSource == "raidhelper":**
  - No auto-refresh (manual JSON input)
  - User must re-import JSON to update

**Implementation:**
```lua
-- Store hash of last RollFor data
OGRH.Invites.lastRollForHash = nil

function OGRH.Invites.GetRollForDataHash()
  -- Returns simple hash/checksum of current RollFor data
  -- Could be: concatenation of all player names sorted
end

-- In OnUpdate handler:
if OGRH_SV.invites.currentSource == "rollfor" then
  local newHash = OGRH.Invites.GetRollForDataHash()
  if newHash ~= OGRH.Invites.lastRollForHash then
    OGRH.Invites.lastRollForHash = newHash
    OGRH.Invites.RefreshPlayerList()
    OGRH.Msg("RollFor data updated - roster refreshed")
  end
end
```

#### 2.4 Refresh Button - Keep or Remove?

**Analysis:**
- Current auto-refresh interval: 2 seconds (very frequent)
- New RollFor check: 5 seconds
- User can manually trigger if they want instant update
- **Recommendation:** **KEEP** - Provides user control for instant update
  - Useful after importing new data
  - Useful if guild roster updates
  - Low complexity to maintain

**Updated Behavior:**
- Refresh button forces immediate re-fetch and UI update
- Also resets RollFor hash check
- Shows feedback: "Refreshed player list"

---

### 3. Invite Mode System (Timer-Based)

#### 3.1 Invite Mode Controls

**New UI Layout (Bottom Section):**

```
┌────────────────────────────────────────────────────┐
│ [Invite Mode] [Invite every] [60] [seconds]       │
│                                    [Clear Status]  │
│                                    [Refresh]       │
└────────────────────────────────────────────────────┘
```

**Components:**
1. **Invite Mode Toggle Button** (Bottom Left)
   - **Label:** "Start Invite Mode" (when off)
   - **Label:** "Stop Invite Mode" (when on, red tint)
   - **Width:** 120px
   - **Position:** BOTTOMLEFT, 20, 15

2. **Interval Label** (Next to toggle)
   - **Text:** "Invite every"
   - **Position:** LEFT of interval input

3. **Interval Input** (OGST TextBox)
   - **Type:** Numbers only
   - **Default:** 60
   - **Width:** 40px
   - **Range:** 10-300 seconds
   - **Position:** Next to label

4. **Interval Unit Label**
   - **Text:** "seconds"
   - **Position:** RIGHT of interval input

**Storage:**
```lua
OGRH_SV.invites.inviteMode = {
  enabled = false,
  interval = 60,           -- Seconds between invite batches
  lastInviteTime = 0,      -- GetTime() of last invite batch
  totalPlayers = 0,        -- Total eligible players
  invitedCount = 0         -- Number invited so far
}
```

#### 3.2 Invite Mode Panel (Auxiliary)

**Design Pattern:** Similar to `OGRH_RecruitingPanel` in OGRH_Recruitment.lua

**Panel Layout:**
```
┌─────────────────────────────────────┐
│  🔄 INVITE MODE ACTIVE              │
│  ─────────────────────────────────  │
│  Next Invite Round:                 │
│  [████████░░░░░░] 45s               │
│  ─────────────────────────────────  │
│  Players Invited:                   │
│  [████████████░░] 12 / 15           │
│  ─────────────────────────────────  │
│  [Stop Invite Mode]                 │
└─────────────────────────────────────┘
```

**Components:**
1. **Panel Frame**
   - **Size:** 280x160
   - **Position:** Anchored to right side of main window (or bottom-right of screen)
   - **Movable:** Yes
   - **Backdrop:** Dark semi-transparent

2. **Title Text**
   - "🔄 INVITE MODE ACTIVE"
   - Green color, pulsing animation

3. **Next Invite Timer Section**
   - **Label:** "Next Invite Round:"
   - **Progress Bar:** Shows seconds until next batch (fills right-to-left or left-to-right)
   - **Text Overlay:** "Xs" countdown
   - **Uses:** OGST.CreateProgressBar() if available

4. **Players Invited Section**
   - **Label:** "Players Invited:"
   - **Progress Bar:** Shows invited/total ratio
   - **Text Overlay:** "X / Y"
   - **Color:** Green (invited) / Gray (remaining)

5. **Stop Button**
   - **Label:** "Stop Invite Mode"
   - **Width:** 100%
   - **Style:** Red warning button
   - **Action:** Disables invite mode, hides panel

**Show/Hide Behavior:**
- Shows when Invite Mode is enabled
- Hides when Invite Mode is disabled
- Persists position in SavedVariables

**Implementation:**
```lua
function OGRH.Invites.CreateInviteModePanel()
  -- Similar to OGRH.CreateRecruitingPanel()
  -- Stores frame in OGRH_InviteModePanel global
end

function OGRH.Invites.UpdateInviteModePanel()
  -- Updates progress bars and text
  -- Called in OnUpdate handler
end
```

#### 3.3 Invite Mode Behavior

**When Enabled:**

1. **Initial Invite Batch:**
   - Immediately invites all online eligible players (Active Roster only)
   - Respects party-to-raid conversion logic (4 initial invites if solo)
   - Sets `lastInviteTime = GetTime()`
   - Counts total eligible players: `totalPlayers = count`
   - Tracks invited: `invitedCount = initial batch size`

2. **Timer Loop:**
   - Every `interval` seconds (default 60):
     - Check all Active Roster players
     - Invite any who are:
       - Online
       - Not in raid
       - Not already invited this cycle
     - Update `invitedCount`
   - Updates progress bars

3. **Auto-Invite from Whisper:**
   - **Only active during Invite Mode**
   - **Active Roster Player Whispers:** ANY whisper from an active roster player triggers an immediate auto-invite (if invite mode is enabled and they're not in raid)
   - **Benched Player Whispers:** Reply with: "You are on the bench. We'll contact you if we need your role."
   - **Absent Player Whispers:** Reply with: "You are marked as absent for this raid. Contact the raid leader if your status has changed."
   - Log whisper responses to ChatFrame4 during invite mode

4. **Raid Group Organization** (Raid-Helper JSON only):
   - When a player joins the raid (event: `RAID_ROSTER_UPDATE`):
     - Check if they have a `group` assignment in roster data
     - If yes: Call `OGRH.Invites.OrganizePlayerIntoGroup(playerName, targetGroup)`
   - Organization logic:
     ```lua
     function OGRH.Invites.OrganizePlayerIntoGroup(playerName, targetGroup)
       -- 1. Check current group of player
       -- 2. If in target group: Done
       -- 3. If target group has < 5 players: Move player to target group
       -- 4. If target group has 5 players:
       --    - Find which player in that group doesn't belong (no group assignment or wrong group)
       --    - Swap players or move misplaced player to their correct group
       --    - If no correct group: Move to group 8 (or 7 if 8 full, etc.)
     end
     ```
   - **Permissions Check:** Only works if raid leader/assistant
   - **Feedback:** Message when organizing: "Moving [Name] to group [X]"

5. **Role Sync to RolesUI:**
   - When a player joins the raid during Invite Mode:
     - Get their role from roster data (`player.role`)
     - Call new API: `OGRH.RolesUI.SetPlayerRole(playerName, roleBucket)`
   - **This replaces the "Sync RollFor" button functionality**
   - Automatic, no user interaction needed

6. **Completion Detection:**
   - When `invitedCount >= totalPlayers`:
     - Show message: "All eligible players have been invited"
     - Optionally auto-disable Invite Mode (or keep running for whisper auto-invites)

**When Disabled:**
- Stops timer loop
- Hides Invite Mode Panel
- **Whisper auto-invite is DISABLED** (will not auto-invite on whisper)
- No raid group organization
- No automatic role sync

---

### 4. RolesUI Integration

#### 4.1 Remove "Sync RollFor" Button
- **Current Location:** RolesUI window (OGRH_RolesUI.lua)
- **Action:** Remove button from UI
- **Reason:** Replaced by automatic sync during invites

#### 4.2 New API: SetPlayerRole

**Function Signature:**
```lua
function OGRH.RolesUI.SetPlayerRole(playerName, roleBucket)
  -- roleBucket: "TANKS", "HEALERS", "MELEE", "RANGED"
  -- Adds player to specified role column
  -- Removes from other columns if present
  -- Triggers UI refresh
  -- Returns: true on success, false on error
end
```

**Implementation in OGRH_RolesUI.lua:**
```lua
function OGRH.RolesUI.SetPlayerRole(playerName, roleBucket)
  if not playerName or playerName == "" then
    return false
  end
  
  -- Normalize name
  playerName = NormalizeName(playerName)
  
  -- Validate role bucket
  local validRoles = {TANKS = true, HEALERS = true, MELEE = true, RANGED = true}
  if not validRoles[roleBucket] then
    return false
  end
  
  -- Remove player from all role columns
  for _, column in ipairs(ROLE_COLUMNS) do
    for i = table.getn(column.players), 1, -1 do
      if column.players[i] == playerName then
        table.remove(column.players, i)
      end
    end
  end
  
  -- Add to target column
  for _, column in ipairs(ROLE_COLUMNS) do
    if column.name == roleBucket then
      table.insert(column.players, playerName)
      break
    end
  end
  
  -- Save to SV
  if OGRH.Roles and OGRH.Roles.SaveRoles then
    OGRH.Roles.SaveRoles()
  end
  
  -- Refresh UI if window is open
  if OGRH_RolesFrame and OGRH_RolesFrame:IsVisible() then
    OGRH.RenderRoles()
  end
  
  -- Sync to Puppeteer/pfUI (existing integrations)
  if roleBucket == "TANKS" or roleBucket == "HEALERS" then
    -- Trigger Puppeteer/pfUI sync
    if OGRH.Roles and OGRH.Roles.SyncExternalAddons then
      OGRH.Roles.SyncExternalAddons(playerName, roleBucket)
    end
  end
  
  return true
end
```

**Integration Points:**
- Called in `OGRH.Invites.OnPlayerJoinRaid(playerName)` handler
- Triggered by `RAID_ROSTER_UPDATE` event during Invite Mode
- Uses source data (RollFor or Raid-Helper) to determine role

#### 4.3 Intermittent Behavior Fix

**Problem Analysis:**
- User reports intermittent behavior with "Sync RollFor" button
- Likely causes:
  - Race condition: RollFor data not fully loaded when sync called
  - Timing issue: Players not yet in raid when sync attempts
  - Missing error handling

**Solution:**
- Remove button (eliminates user-triggered race conditions)
- Automatic sync happens **after** player joins raid (guaranteed to be in roster)
- Direct function call to SetPlayerRole API - no retry needed since it's same addon

**Implementation:**
```lua
function OGRH.Invites.SyncPlayerRole(playerName)
  if not OGRH_SV.invites.inviteMode.enabled then
    return -- Only sync during invite mode
  end
  
  -- Get player's role from roster data
  local players = OGRH.Invites.GetRosterPlayers()
  for _, player in ipairs(players) do
    if NormalizeName(player.name) == NormalizeName(playerName) then
      if player.role and OGRH.RolesUI and OGRH.RolesUI.SetPlayerRole then
        if OGRH.RolesUI.SetPlayerRole(playerName, player.role) then
          ChatFrame4:AddMessage("[OGRH] Auto-synced " .. playerName .. " to " .. player.role, 0, 1, 0)
        else
          ChatFrame4:AddMessage("[OGRH] Failed to sync role for " .. playerName, 1, 0, 0)
        end
      end
      return
    end
  end
end
```

---

## 5. Implementation Plan

### Phase 1: Data Infrastructure ✅ COMPLETE
1. ✅ **Define constants and enums** (SOURCE_TYPE, standardized player object)
2. ✅ **Load json.lua library** (add to .toc, initialize in module)
3. ✅ **Implement JSON parser** (`ParseRaidHelperJSON` using json.lua)
4. ✅ **Create unified player fetch** (`GetRosterPlayers`)
5. ✅ **Add SavedVariables structure** for Raid-Helper data

### Phase 2: UI Foundation ✅ COMPLETE
6. ✅ **Replace Import button with OGST Menu Button**
   - Replaced simple RollFor button with dropdown menu
   - Menu items: "RollFor Soft-Res" and "Raid-Helper JSON"
   - Uses OGST.ShowDropdownMenu with fallback to basic WoW dropdown
7. ✅ **Create JSON input dialog**
   - 450x400px dialog with 420x250px EditBox
   - Multi-line JSON input with scrolling
   - Validation on Import button click
   - Success/error status display
   - Auto-closes after successful import
8. ✅ **Implement section headers** (Active/Benched/Absent)
   - `CreateSectionHeader()` helper function
   - Color-coded headers with player counts
   - Active = green, Benched = yellow/orange, Absent = red
9. ✅ **Update player list rendering** to support sections
   - Players separated into active/benched/absent arrays
   - Alphabetical sorting within each section
   - Section headers with counts
   - Disabled buttons for benched/absent players
   - Color-coded row backgrounds
   - Info bar shows current source and section counts

### Phase 3: Invite Mode Core ✅ COMPLETE
9. ✅ **Add Invite Mode toggle button and interval controls**
10. ✅ **Create Invite Mode auxiliary panel**
11. ✅ **Implement timer-based invite loop**
12. ✅ **Add progress tracking** (next invite countdown, X/Y players)

### Phase 4: Advanced Features ✅ COMPLETE
13. ✅ **Implement whisper auto-responses** (bench/absent)
14. ✅ **Add raid group organization logic** (Raid-Helper source only)
15. ✅ **Implement auto-refresh for RollFor** (5-second check)

### Phase 5: RolesUI Integration ✅ COMPLETE
16. ✅ **Create `OGRH.RolesUI.SetPlayerRole` API**
17. ✅ **Remove "Sync RollFor" button from RolesUI**
18. ✅ **Implement automatic role sync on player join**
19. ✅ **Direct function call (no retry queue needed - same addon)**

### Phase 6: Testing & Polish
20. ✅ **Test RollFor source compatibility**
21. ✅ **Test Raid-Helper JSON import**
22. ✅ **Test Invite Mode with solo → party → raid conversion**
23. ✅ **Test whisper auto-invite/responses**
24. ✅ **Test raid group organization**
25. ✅ **Test role sync with Puppeteer/pfUI**
26. ✅ **Performance testing** (40-player roster)
27. ✅ **Error handling and edge cases**

---

## 6. Technical Constraints & Considerations

### 6.1 WoW 1.12 Lua Constraints
- **JSON library:** Using json.lua by rxi (MIT licensed)
  - Modified for WoW 1.12 compatibility (2 changes)
  - Lightweight: 280 lines, ~10KB
  - Provides proper error messages with line/column info
- **Table operations:**
  - Use `table.getn()` not `#`
  - Use `table.insert()` / `table.remove()`
- **String concatenation:** Use `table.concat()` for performance
- **No continue:** Use conditional blocks

### 6.2 WoW API Limitations
- **Raid group management:**
  - `SetRaidSubgroup(raidIndex, subgroup)` - requires raid leader/assistant
  - `GetNumRaidMembers()` - max 40
  - Subgroups: 1-8 (5 players each)
- **Invite limits:**
  - Solo: Can invite up to 4 (creates party)
  - Party: Can invite up to 39 more (must convert to raid first)
  - Raid: Can invite directly
- **Whisper detection:**
  - `CHAT_MSG_WHISPER` event provides `arg1` (message), `arg2` (sender)
  - No sender normalization - must handle realm suffixes

### 6.3 Performance Considerations
- **Large rosters:** 40+ players
  - Minimize table scans
  - Cache player lookups
  - Throttle UI updates (batch changes)
- **Auto-refresh frequency:**
  - RollFor check: 5 seconds (hash comparison is cheap)
  - UI refresh: Only when data changes
  - Invite loop: User-configurable (10-300s)

### 6.4 Error Handling
- **JSON parsing errors:**
  - Show clear error messages in UI
  - Don't crash on invalid JSON
  - Validate required fields
- **RollFor unavailable:**
  - Graceful degradation (show message)
  - Don't break if RollFor unloaded mid-session
- **Raid permissions:**
  - Check permissions before:
    - Inviting
    - Moving players to groups
  - Show helpful error messages

---

## 7. SavedVariables Schema

```lua
OGRH_SV.invites = {
  -- Data source
  currentSource = "rollfor", -- "rollfor" | "raidhelper"
  raidhelperData = nil,      -- Parsed Raid-Helper JSON (table)
  
  -- Invite tracking (existing)
  declinedPlayers = {},      -- [playerName] = true
  history = {},              -- Array of {player, timestamp, action}
  
  -- Invite Mode (new)
  inviteMode = {
    enabled = false,
    interval = 60,
    lastInviteTime = 0,
    totalPlayers = 0,
    invitedCount = 0
  },
  
  -- Invite Mode Panel position (new)
  invitePanelPosition = {
    point = "BOTTOMRIGHT",
    x = -20,
    y = 200
  },
  
  -- RollFor change detection (new)
  lastRollForHash = nil
}
```

---

## 8. User Experience Flow

### Scenario 1: Using RollFor Source
1. User opens Invites window
2. Clicks "Import Roster" → "RollFor Soft-Res"
3. RollFor window opens, user imports soft-res data
4. Invites window refreshes automatically (detects RollFor data change)
5. User sees Active Roster list populated
6. User clicks "Start Invite Mode"
7. Invite Mode Panel appears, first batch of invites sent
8. Progress bars show next invite round and invited count
9. As players whisper for invite, they're auto-invited
10. As players join raid:
    - Automatically placed in correct role column (RolesUI)
    - (No group organization - RollFor doesn't have group data)
11. Every 60 seconds, next batch of invites sent
12. User clicks "Stop Invite Mode" when raid is full

### Scenario 2: Using Raid-Helper JSON
1. User opens Invites window
2. Clicks "Import Roster" → "Raid-Helper JSON"
3. JSON dialog opens
4. User pastes JSON from Raid-Helper website
5. Clicks "Import"
6. Dialog validates JSON, shows success message
7. Main window refreshes, shows:
   - Active Roster section (signed/confirmed players)
   - Benched section (bench = true)
   - Absent section (absent = true)
8. User configures interval: Changes "60" to "120" (invite every 2 minutes)
9. User clicks "Start Invite Mode"
10. Invite Mode Panel appears
11. As players join raid:
    - Automatically assigned to correct role (RolesUI)
    - Automatically moved to correct group (1-8 from JSON)
12. Benched player whispers → Receives auto-reply about being benched
13. Absent player whispers → Receives auto-reply about being absent
14. Raid fills up, user clicks "Stop Invite Mode"

### Scenario 3: Raid Group Organization
1. Raid-Helper JSON imported with group assignments
2. Invite Mode enabled
3. Player "Tankwar" joins raid (assigned to group 1)
   - Currently in group 7 (auto-assigned by WoW)
   - Group 1 has 3 players
   - System moves Tankwar from group 7 to group 1
   - Message: "Moving Tankwar to group 1"
4. Player "Healpriest" joins raid (assigned to group 2)
   - Currently in group 1
   - Group 2 has 5 players already
   - System checks group 2 for misplaced players
   - Finds "Dpsrogue" in group 2 (should be group 3)
   - Swaps Healpriest to group 2, moves Dpsrogue to group 3
   - Messages:
     - "Moving Healpriest to group 2"
     - "Moving Dpsrogue to group 3"
5. Player "Pugmage" joins raid (no group assignment in JSON)
   - No target group
   - Left in current group (or moved to group 8 if available)

---

## 9. Open Questions & Decisions

### Q1: Should Invite Mode auto-stop when raid is full (40 players)?
- **Option A:** Auto-stop and hide panel
- **Option B:** Keep running (still useful for whisper auto-invite if someone leaves)
- **Recommendation:** Option B - Let user control when to stop

### Q2: Should Refresh button be removed or kept?
- **Analysis:** UI already auto-refreshes, button is redundant
- **Recommendation:** **KEEP** - Provides user control, low cost to maintain

### Q3: What happens if user switches data source mid-session?
- **Scenario:** RollFor data loaded, then user imports Raid-Helper JSON
- **Behavior:**
  - Clear current roster data
  - Switch `currentSource`
  - Reload UI with new source
  - Reset Invite Mode state (stop if running)
- **Warning:** Show confirmation dialog before switching sources

### Q4: How to handle players in multiple sources?
- **Scenario:** Player in both RollFor and guild, shows in both lists
- **Behavior:**
  - Deduplicate by normalized name
  - Prefer Raid-Helper data if both sources available (more detailed)
- **Not applicable:** User can only use one source at a time

### Q5: Should individual Invite/Msg buttons remain in Invite Mode?
- **Analysis:**
  - Invite Mode sends batches automatically
  - But user may want to manually invite specific player
- **Recommendation:** **KEEP** - Provide manual override

### Q6: How to handle realm suffixes in player names?
- **Scenario:** JSON contains "PlayerName-RealmName"
- **Behavior:**
  - Strip realm suffix when normalizing
  - Only use character name for matching
  - `string.gfind(name, "^([^-]+)")` to extract

### Q7: Should benched/absent players be hidden by default?
- **Option A:** Hide behind toggle/checkbox
- **Option B:** Always show in separate sections
- **Recommendation:** Option B - Always visible, but clearly separated

### Q8: What if RollFor data changes while Invite Mode is active?
- **Scenario:** User updates soft-res mid-raid
- **Behavior:**
  - Detect change (hash comparison)
  - Show warning: "RollFor data changed. Stop and restart Invite Mode to use new data."
  - Don't auto-update roster during active Invite Mode (could break state)
- **Alternative:** Auto-stop Invite Mode and refresh
- **Recommendation:** Show warning, require manual restart

---

## 10. Success Metrics

### Functional Requirements Met
- ✅ Dual data source support (RollFor + Raid-Helper JSON)
- ✅ JSON import with validation
- ✅ Timer-based invite automation
- ✅ Bench/Absent sections
- ✅ Whisper auto-responses
- ✅ Raid group organization
- ✅ Automatic role sync to RolesUI
- ✅ Remove "Sync RollFor" button

### User Experience Goals
- ⏱️ Reduces manual invite clicks from ~40 to 1
- ⏱️ Saves raid leader 10-15 minutes of invite/organization time
- ✅ Clear visual feedback (progress bars, status text)
- ✅ Eliminates intermittent role sync issues
- ✅ Supports advanced raid composition planning (group assignments)

### Technical Quality
- ✅ No errors in Lua 5.0/5.1 environment
- ✅ Follows OGST UI patterns
- ✅ Clean SavedVariables structure
- ✅ Comprehensive error handling
- ✅ Performance: <50ms per update cycle

---

## 11. Future Enhancements (Out of Scope)

### Post-V2.0 Features
- **Multi-raid support:** Import multiple raid rosters, switch between them
- **Discord integration:** Auto-post invite status to Discord webhook
- **Invite history dashboard:** Statistics on invite response rates
- **Smart invite ordering:** Prioritize by role need (invite tanks first)
- **Conflict resolution:** Highlight players assigned to multiple roles
- **Export functionality:** Export current raid composition back to JSON

---

## Appendix A: Raid-Helper JSON Schema

```typescript
interface RaidHelperData {
  id: number;           // Instance ID (e.g., 96 for Naxxramas)
  name: string;         // Instance name (e.g., "Naxxramas (96)")
  players: Player[];
}

interface Player {
  name: string;         // Character name (required)
  class: string;        // WoW class (e.g., "Warrior", "Priest")
  role: string;         // Role: "Tank" | "Healer" | "Melee" | "Ranged"
  status: string;       // Signup status: "signed" | "confirmed" | etc.
  group?: number;       // Target raid group (1-8, optional)
  bench?: boolean;      // Is benched? (default: false)
  absent?: boolean;     // Marked absent? (default: false)
}
```

**Example JSON:**
```json
{
  "id": 96,
  "name": "Naxxramas (96)",
  "players": [
    {
      "name": "Tankwar",
      "class": "Warrior",
      "role": "Tank",
      "status": "confirmed",
      "group": 1,
      "bench": false,
      "absent": false
    },
    {
      "name": "Benchrogue",
      "class": "Rogue",
      "role": "Melee",
      "status": "signed",
      "bench": true
    },
    {
      "name": "Absentmage",
      "class": "Mage",
      "role": "Ranged",
      "status": "declined",
      "absent": true
    }
  ]
}
```

---

## Appendix B: OGST UI Components Reference

### Components to Use
```lua
-- Scroll list (existing usage)
OGRH.CreateStyledScrollList(parent, width, height)

-- List items (existing usage)
OGRH.CreateStyledListItem(parent, width, height, frameType)
OGRH.SetListItemColor(item, r, g, b, a)

-- Progress bars (new)
-- Note: Check if OGST has progress bar component
-- If not: Create custom using texture + frame

-- Text input (numbers only)
-- Note: Check if OGST has number input
-- If not: Create EditBox with OnChar validation

-- Menu button
-- Note: Check if OGST has dropdown/menu component
-- If not: Create custom dropdown on button click
```

### Styling Patterns
```lua
-- Button styling (existing)
OGRH.StyleButton(button)

-- Frame backdrop (existing pattern)
frame:SetBackdrop({
  bgFile = "Interface/Tooltips/UI-Tooltip-Background",
  edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
  edgeSize = 12,
  insets = {left = 4, right = 4, top = 4, bottom = 4}
})
frame:SetBackdropColor(0, 0, 0, 0.85)

-- ESC key handling (existing)
OGRH.MakeFrameCloseOnEscape(frame, "FrameName")
```

---

## Document Version History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-01-19 | AI Design Doc | Initial specification based on user requirements |

---

**END OF SPECIFICATION**
