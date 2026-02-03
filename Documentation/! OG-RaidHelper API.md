# OG-RaidHelper API Documentation

This document provides comprehensive API documentation for all OG-RaidHelper modules. Functions are categorized as **Public** (intended for external use) or **Private** (internal implementation).

---

## MainUI Module (_UI/MainUI.lua)

The MainUI module manages the main addon interface, including the title bar, encounter navigation controls, and core UI state.

### Public Functions

#### `OGRH.NavigateToPreviousEncounter()`
**Type:** Public  
**Authorization:** Requires Raid Leader, Assistant, or designated Raid Admin  
**Returns:** `nil`

Navigates to the previous encounter in the currently selected raid using index-based arithmetic. Automatically updates all dependent UIs and syncs changes in realtime.

**Behavior:**
- Decrements `selectedEncounterIndex` by 1
- Minimum boundary: index 1 (will not go below first encounter)
- Updates MainUI encounter button display
- Refreshes Encounter Planning window if open
- Refreshes Consume Monitor if enabled
- Triggers REALTIME sync to raid members

**Example:**
```lua
-- Called when user clicks "<" button
OGRH.NavigateToPreviousEncounter()
```

**Implementation Notes:**
- Uses v2 schema numeric indices (`selectedRaidIndex`, `selectedEncounterIndex`)
- Active Raid is always at `raids[1]` in v2 schema
- Calls `OGRH.SetCurrentEncounter(raidIdx, encounterIdx - 1)` to persist change

---

#### `OGRH.NavigateToNextEncounter()`
**Type:** Public  
**Authorization:** Requires Raid Leader, Assistant, or designated Raid Admin  
**Returns:** `nil`

Navigates to the next encounter in the currently selected raid using index-based arithmetic. Automatically updates all dependent UIs and syncs changes in realtime.

**Behavior:**
- Increments `selectedEncounterIndex` by 1
- Maximum boundary: `table.getn(raid.encounters)` (will not exceed last encounter)
- Updates MainUI encounter button display
- Refreshes Encounter Planning window if open
- Refreshes Consume Monitor if enabled
- Triggers REALTIME sync to raid members

**Example:**
```lua
-- Called when user clicks ">" button
OGRH.NavigateToNextEncounter()
```

**Implementation Notes:**
- Uses v2 schema numeric indices (`selectedRaidIndex`, `selectedEncounterIndex`)
- Active Raid is always at `raids[1]` in v2 schema
- Calls `OGRH.SetCurrentEncounter(raidIdx, encounterIdx + 1)` to persist change

---

#### `OGRH.UpdateEncounterNavButton()`
**Type:** Public  
**Returns:** `nil`

Updates the encounter navigation button display and enable/disable states based on current selection. This is the primary UI refresh function for encounter navigation.

**Behavior:**
- Reads `selectedRaidIndex` and `selectedEncounterIndex` from SavedVariables
- Displays encounter name on main button (truncated to 15 chars max)
- Enables/disables "< >" buttons based on boundary conditions
- Falls back to Active Raid display name if no encounter selected
- Loads custom modules associated with selected encounter
- Auto-initializes indices to `(1, 1)` if missing

**Display Priority:**
1. Encounter name (if selected)
2. Active Raid display name (if no encounter)
3. "Select Raid" (if no Active Raid)

**Button State Logic:**
- Previous ("<"): Enabled if `encounterIdx > 1`
- Next (">"): Enabled if `encounterIdx < table.getn(raid.encounters)`

**Example:**
```lua
-- Called after changing Active Raid
OGRH.SetActiveRaid(sourceRaidIdx)
OGRH.UpdateEncounterNavButton()  -- Refresh display
```

**Implementation Notes:**
- Accesses data via indices, never by name lookup
- Supports debug mode via `OGRH.MainUI.State.debug`
- Calls `OGRH.LoadModulesForRole()` for custom module roles
- Calls `OGRH.UnloadAllModules()` when no modules needed

---

#### `OGRH.UpdateAdminButtonColor()`
**Type:** Public  
**Returns:** `nil`

Updates the Admin button color to reflect current raid admin status. Green when local player is admin, yellow otherwise.

**Behavior:**
- Calls `OGRH.GetRaidAdmin()` to determine current admin
- Sets button text to `|cff00ff00Admin|r` (green) if player is admin
- Sets button text to `|cffffff00Admin|r` (yellow) if player is not admin

**Example:**
```lua
-- Called when admin changes
OGRH.UpdateAdminButtonColor()
```

**Aliases:**
- `OGRH.UpdateSyncButtonColor()` - Backward compatibility alias

---

### Public Properties

#### `OGRH.MainUI.State`
**Type:** Table  
**Access:** Public Read/Write

State management for MainUI module.

**Fields:**
- `debug` (boolean) - When `true`, enables detailed debug output to chat. Toggle with `/ogrh debug ui`

**Example:**
```lua
-- Enable debug mode
OGRH.MainUI.State.debug = true

-- Disable debug mode
OGRH.MainUI.State.debug = false
```

---

#### `OGRH.encounterNav`
**Type:** Frame Reference  
**Access:** Public Read-Only

Reference to the encounter navigation frame container and its child buttons.

**Fields:**
- `markBtn` - Mark button ("M")
- `announceBtn` - Announce button ("A")
- `prevEncBtn` - Previous encounter button ("<")
- `nextEncBtn` - Next encounter button (">")
- `encounterBtn` - Main encounter select button (center)

**Example:**
```lua
-- Access encounter button
local btn = OGRH.encounterNav.encounterBtn
btn:SetText("Custom Text")
```

---

#### `OGRH.MainUI_RolesBtn`
**Type:** Frame Reference  
**Access:** Public Read-Only

Reference to the Roles button on the title bar. Used by menu system for positioning.

---

### Private Functions

#### `UpdateAdminButtonColor()` (local)
**Type:** Private  
**Returns:** `nil`

Local implementation of admin button color update. Exported to `OGRH.UpdateAdminButtonColor()` for public access.

---

#### `applyLocked(lock)` (local)
**Type:** Private  
**Parameters:**
- `lock` (boolean) - Whether UI should be locked

Updates lock button visual state. Called internally when lock state changes.

---

#### `restoreMain()` (local)
**Type:** Private  
**Returns:** `nil`

Restores MainUI position and state from SavedVariables on addon load. Called during `VARIABLES_LOADED` event.

**Behavior:**
- Restores frame position from saved coordinates
- Applies lock state
- Initializes raid lead system
- Updates admin UI state
- Initializes encounter navigation to `(1, 1)` if indices missing

---

### UI Elements

The MainUI creates the following interactive elements:

**Title Bar (20px height):**
- **RH Button** (28px) - Opens main menu (same as minimap right-click)
- **Rdy Button** (33px) - Left: Send ready check | Right: Ready check settings
- **Admin Button** (45px) - Left: Admin management | Right: Poll menu
- **Roles Button** (dynamic) - Opens roles assignment UI
- **Lock Button** (20px) - Toggles UI lock state

**Encounter Navigation Bar (20px height):**
- **M Button** (20px) - Left: Auto-mark from encounter | Right: Clear all marks
- **A Button** (20px) - Left: Announce encounter | Right: Announce consumes
- **< Button** (20px) - Navigate to previous encounter
- **Encounter Button** (dynamic) - Left: Open Encounter Planning | Right: Select raid/encounter
- **> Button** (20px) - Navigate to next encounter

---

### Event Handlers

MainUI registers and handles the following events:

- `VARIABLES_LOADED` - Restores UI state and initializes indices
- `OnDragStart` - Begins frame movement (if unlocked)
- `OnDragStop` - Ends frame movement and saves position

---

### Data Access Patterns

#### ✅ CORRECT - Index-Based Access (v2 Schema)
```lua
-- Get current encounter
local raidIdx, encounterIdx = OGRH.GetCurrentEncounter()  -- Returns (1, 3)

-- Access encounter object
local raids = OGRH.SVM.GetPath("encounterMgmt.raids")
local encounter = raids[raidIdx].encounters[encounterIdx]

-- Set current encounter
OGRH.SetCurrentEncounter(1, 5)  -- Set to 5th encounter
```

#### ❌ INCORRECT - Name-Based Access (Deprecated)
```lua
-- DO NOT USE - Legacy pattern from pre-v2 schema
local currentRaid = OGRH.SVM.Get("ui", "selectedRaid")  -- Returns display name
local currentEncounter = OGRH.SVM.Get("ui", "selectedEncounter")  -- Returns name

-- DO NOT USE - Name-based search
for i = 1, table.getn(raids) do
  if raids[i].name == currentRaid then  -- WRONG: name-based lookup
    -- ...
  end
end
```

---

### Dependencies

MainUI requires the following modules:

**Required:**
- `OGRH_Core.lua` - Core functions and SavedVariablesManager
- `OGRH.GetCurrentEncounter()` - Returns current raid/encounter indices
- `OGRH.GetCurrentEncounterNames()` - Returns names for backward compat
- `OGRH.SetCurrentEncounter(raidIdx, encIdx)` - Sets current encounter
- `OGRH.StyleButton(button)` - Applies addon button styling

**Optional:**
- `OGRH.OpenEncounterPlanning()` - Opens encounter planning UI
- `OGRH.ShowEncounterRaidMenu(anchor)` - Shows raid selection menu
- `OGRH.MarkPlayersFromMainUI()` - Auto-marks players from encounter
- `OGRH.CanNavigateEncounter()` - Checks authorization
- `OGRH.Announcements.SendEncounterAnnouncement()` - Sends encounter announcement
- `OGRH.ShowAnnouncementTooltip()` - Shows announcement preview tooltip
- `OGRH.LoadModulesForRole()` - Loads custom modules
- `OGRH.UnloadAllModules()` - Unloads all custom modules
- `OGRH.ShowConsumeMonitor()` - Updates consume monitor display

---

## EncounterMgmt Module (_Raid/EncounterMgmt.lua)

The EncounterMgmt module provides the Encounter Planning UI for configuring encounter roles, player assignments, raid marks, and announcements. It supports both Active Raid (live execution) and saved raids (planning).

---

### Permission Model

**EncounterMgmt implements a two-tier permission system for Active Raid:**

#### Tier 1: Structural Editing (Admin Only)
**Requires:** Raid Admin only  
**Controls:** "Edit: Locked/Unlocked" toggle button

**Structural operations include:**
- Role configuration (adding/removing/editing roles)
- Advanced settings (consume tracking, thresholds)
- Announcement editing
- Consume selection
- Class priority configuration

**Authorization Check:**
```lua
-- Uses CanEditCurrentEncounter() internally
if frame.selectedRaidIdx == 1 then  -- Active Raid
  return OGRH.CanModifyStructure(UnitName("player"))  -- Admin only
else
  return true  -- Anyone can edit non-Active raids
end
```

#### Tier 2: Assignment Editing (Raid Leaders & Assistants)
**Requires:** Raid Leader, Raid Assistant, OR Raid Admin  
**Always Active:** No toggle required (works regardless of "Edit" lock state)

**Assignment operations include:**
- Player drag & drop (from players list or between slots)
- Right-click to unassign players
- Raid mark selection (icons 1-8)
- Assignment numbers (1-9, 0)
- Auto-assign function

**Authorization Check:**
```lua
-- Uses CanEditAssignments() internally
if frame.selectedRaidIdx == 1 then  -- Active Raid
  -- Check if player is Admin, Raid Leader, or Assistant
  if OGRH.CanModifyStructure(playerName) then return true end
  if IsRaidLeader() or IsRaidOfficer() then return true end
  return false
else
  return true  -- Anyone can edit non-Active raids
end
```

---

### Permission Rationale

**Why two tiers?**

1. **Structural changes** affect the encounter template and should be managed by the Raid Admin to maintain consistency
2. **Assignment changes** are tactical decisions that Raid Leaders/Assistants need to make during live execution
3. This allows raid officers to help with player positioning without giving them access to modify the encounter structure

**Out of Raid:**
- All operations allowed (both structural and assignments)
- No permission checks applied

**Non-Active Raids:**
- All operations allowed for anyone
- These are saved templates not actively being used

---

### Public Functions

#### Player Assignment Functions

These functions allow Raid Leaders, Assistants, and Admins to modify player assignments in the Active Raid:

**Drag & Drop Assignment:**
- Drag from Players List → Drop on Slot
- Drag from Slot → Drop on another Slot (swaps if occupied)
- Right-click on assigned slot to unassign

**Auto-Assign:**
- Click "Auto Assign" button
- Respects role priorities and class preferences
- Sources from Raid or Planning Roster

---

### Internal Permission Helpers

#### `CanEditCurrentEncounter(frame)` (local)
**Type:** Private  
**Returns:** `boolean`

Checks if player can edit structural elements of the current encounter.

**Behavior:**
- Out of raid: Returns `true`
- Active Raid (index 1): Returns `OGRH.CanModifyStructure(UnitName("player"))`
- Non-Active Raid: Returns `true`

**Used by:**
- Edit mode toggle button
- Structural UI elements (role config, settings, announcements)

---

#### `CanEditAssignments(frame)` (local)
**Type:** Private  
**Returns:** `boolean`

Checks if player can edit player assignments, marks, and numbers.

**Behavior:**
- Out of raid: Returns `true`
- Active Raid (index 1): Returns `true` if player is:
  - Raid Admin (`OGRH.CanModifyStructure`)
  - Raid Leader (`IsRaidLeader()`)
  - Raid Assistant (`IsRaidOfficer()`)
- Non-Active Raid: Returns `true`

**Used by:**
- Player drag & drop handlers
- Right-click unassign
- Auto-assign button
- Raid mark selection
- Assignment number selection

---

### Error Messages

**Assignment Permission Denied:**
```
"Only the Raid Leader, Assistants, or Raid Admin can modify assignments."
```

**Structural Edit Permission Denied:**
```
"Only the Raid Admin can unlock structural editing (roles, settings, announcements)."
```

---

### Version History

**v2 Schema (Current):**
- Index-based navigation using `selectedRaidIndex` and `selectedEncounterIndex`
- Active Raid always at `raids[1]`
- Numeric indices for all encounter operations
- Legacy name fields maintained for consume logging compatibility

**Pre-v2 (Deprecated):**
- Name-based navigation using `selectedRaid` and `selectedEncounter`
- Direct raid name storage and lookup
- String-based encounter selection

---

### Debugging

Enable debug output:
```lua
-- Via chat command
/ogrh debug ui

-- Via code
OGRH.MainUI.State.debug = true
```

Debug output includes:
- Current raid/encounter indices
- Raid array size and validity
- Role data availability
- Custom module detection and loading
- Encounter object retrieval

---

## Core Module (_Core/Core.lua)

The Core module provides fundamental functions for schema management, encounter navigation, Active Raid management, and core utilities.

### Encounter Selection Functions

#### `OGRH.GetCurrentEncounter()`
**Type:** Public  
**Returns:** `(number, number)` - `(raidIndex, encounterIndex)`

Returns the currently selected raid and encounter as numeric indices. This is the primary method for retrieving current selection in v2 schema.

**Behavior:**
- Returns indices from `ui.selectedRaidIndex` and `ui.selectedEncounterIndex`
- Active Raid is always at index 1
- Returns `nil, nil` if no selection exists

**Example:**
```lua
local raidIdx, encIdx = OGRH.GetCurrentEncounter()
if raidIdx and encIdx then
  local raids = OGRH.SVM.GetPath("encounterMgmt.raids")
  local encounter = raids[raidIdx].encounters[encIdx]
end
```

---

#### `OGRH.GetCurrentEncounterNames()`
**Type:** Public  
**Returns:** `(string, string)` - `(raidName, encounterName)`

Returns the currently selected raid and encounter as name strings. Backward compatibility helper for consume logging and announcements.

**Behavior:**
- Calls `GetCurrentEncounter()` to get indices
- Looks up names from raid/encounter objects
- Uses `raid.name` (not `displayName`) for lookups
- Returns `nil, nil` if selection invalid

**Example:**
```lua
local raidName, encounterName = OGRH.GetCurrentEncounterNames()
if OGRH.Announcements then
  OGRH.Announcements.SendEncounterAnnouncement(raidName, encounterName)
end
```

---

#### `OGRH.SetCurrentEncounter(raidIndex, encounterIndex)`
**Type:** Public  
**Authorization:** Admin updates immediately; L/A sends request to Admin  
**Parameters:**
- `raidIndex` (number) - Index of raid to select (1 = Active Raid)
- `encounterIndex` (number) - Index of encounter within raid

**Returns:** `nil`

Sets the currently selected raid and encounter. Centralized write interface with authorization checks and sync broadcasting.

**Behavior:**
- **Admin in raid:** Updates local state immediately, broadcasts to all raid members
- **L/A in raid:** Sends `REQUEST_ENCOUNTER` to Admin, waits for Admin broadcast
- **Solo (no raid):** Updates local state immediately
- Sets both numeric indices (v2 schema) and legacy name fields (backward compat)
- Triggers REALTIME sync when Admin broadcasts

**Example:**
```lua
-- Set to first encounter in Active Raid
OGRH.SetCurrentEncounter(1, 1)

-- Navigate to 5th encounter
OGRH.SetCurrentEncounter(1, 5)
```

**Implementation Notes:**
- Only function that should write `selectedRaidIndex`/`selectedEncounterIndex`
- Maintains `selectedRaid`/`selectedEncounter` legacy fields for consume logging
- Uses displayName for consume logging (e.g., "[AR] AQ40")

---

#### `OGRH.GetSelectedRaidAndEncounter()`
**Type:** Public  
**Returns:** `(string, string)` - `(raidDisplayName, encounterName)`

Returns the currently selected raid and encounter with display names suitable for consume logging.

**Behavior:**
- Gets indices via `GetCurrentEncounter()`
- Uses `raid.displayName` (falls back to `raid.name`)
- Strips `[AR] ` prefix from Active Raid name
- Returns `nil, nil` if selection invalid

**Example:**
```lua
-- Consume tracking usage
local raid, encounter = OGRH.GetSelectedRaidAndEncounter()
-- raid = "AQ40" (not "[AR] AQ40")
-- encounter = "Twins"
```

---

### Active Raid Management

#### `OGRH.EnsureActiveRaid()`
**Type:** Public  
**Returns:** `boolean` - Success status

Ensures the Active Raid structure exists at `raids[1]`. Creates it if missing and migrates existing raids.

**Behavior:**
- Checks if `raids[1].id == "__active__"`
- If missing, creates Active Raid with default "Planning" encounter
- Shifts existing raids up by 1 index (raids[1] → raids[2], etc.)
- Updates `ui.selectedRaid` reference if numeric index
- Always positions Active Raid at `raids[1]`

**Example:**
```lua
-- Called during addon initialization
OGRH.EnsureActiveRaid()
```

---

#### `OGRH.SetActiveRaid(sourceRaidIdx)`
**Type:** Public  
**Parameters:**
- `sourceRaidIdx` (number) - Index of source raid to copy (must be >= 2)

**Returns:** `boolean` - Success status

Copies a raid configuration to the Active Raid slot and selects it for use.

**Behavior:**
- Deep copies all encounters from source raid to `raids[1]`
- Sets `displayName` to `[AR] SourceRaidName`
- Sets `sourceRaidId` to track origin
- Auto-selects first encounter (sets indices to `1, 1`)
- Updates all dependent UIs
- Broadcasts checksum after 2 seconds
- Validates source index (must be >= 2)

**Example:**
```lua
-- Copy AQ40 (at index 3) to Active Raid
OGRH.SetActiveRaid(3)
-- Now raids[1] contains deep copy of AQ40 encounters
-- UI shows "[AR] AQ40 - First Encounter"
```

**Implementation Notes:**
- Uses deep copy to prevent reference sharing
- Triggers REALTIME sync via encounter selection
- Called when user right-clicks encounter button and selects raid

---

#### `OGRH.GetActiveRaid()`
**Type:** Public  
**Returns:** `table|nil` - Active Raid object

Returns the Active Raid data structure.

**Behavior:**
- Returns `encounterMgmt.raids[1]`
- Returns `nil` if structure doesn't exist

**Example:**
```lua
local activeRaid = OGRH.GetActiveRaid()
if activeRaid then
  local encounterCount = table.getn(activeRaid.encounters)
  OGRH.Msg("Active Raid: " .. activeRaid.displayName .. " (" .. encounterCount .. " encounters)")
end
```

---

#### `OGRH.IsActiveRaid(raidIdx)`
**Type:** Public  
**Parameters:**
- `raidIdx` (number) - Raid index to check

**Returns:** `boolean`

Checks if the given raid index is the Active Raid.

**Behavior:**
- Returns `true` if `raidIdx == 1`
- Returns `false` otherwise

**Example:**
```lua
if OGRH.IsActiveRaid(raidIdx) then
  syncLevel = "REALTIME"  -- Active Raid uses realtime sync
else
  syncLevel = "MANUAL"    -- Other raids use manual sync
end
```

---

### Utility Functions

#### `OGRH.EnsureSV()`
**Type:** Public  
**Returns:** `nil`

Ensures SavedVariables structure exists and initializes schema version.

**Behavior:**
- Creates `OGRH_SV` table if missing
- Creates `OGRH_SV.v2` table if missing
- Sets schema version markers
- Called at addon startup and before data access

---

#### `OGRH.ScheduleTimer(callback, delay, repeating)`
**Type:** Public  
**Parameters:**
- `callback` (function) - Function to execute
- `delay` (number) - Delay in seconds
- `repeating` (boolean) - If true, repeat until canceled

**Returns:** `number` - Timer ID for cancellation

Schedules a function to execute after a delay.

**Example:**
```lua
-- One-time execution after 5 seconds
local timerId = OGRH.ScheduleTimer(function()
  OGRH.Msg("5 seconds elapsed")
end, 5, false)

-- Repeating timer every 2 seconds
local repeatId = OGRH.ScheduleTimer(function()
  OGRH.Msg("Tick")
end, 2, true)
```

---

#### `OGRH.CancelTimer(id)`
**Type:** Public  
**Parameters:**
- `id` (number) - Timer ID from `ScheduleTimer`

Cancels a scheduled timer.

---

#### `OGRH.StyleButton(button)`
**Type:** Public  
**Parameters:**
- `button` (Frame) - Button frame to style

Applies OG-RaidHelper button styling.

**Behavior:**
- Sets font to GameFontNormalSmall
- Configures text insets
- Applies consistent appearance

---

### Module System Functions

#### `OGRH.RegisterModule(module)`
**Type:** Public  
**Parameters:**
- `module` (table) - Module definition with `id`, `name`, `version`, `OnLoad`, `OnUnload`

Registers a custom module for role-based loading.

---

#### `OGRH.GetAvailableModules()`
**Type:** Public  
**Returns:** `table` - Array of registered modules

Returns all registered custom modules.

---

#### `OGRH.LoadModulesForRole(moduleIds)`
**Type:** Public  
**Parameters:**
- `moduleIds` (table) - Array of module IDs to load

Loads specified custom modules for current encounter/role.

---

#### `OGRH.UnloadAllModules()`
**Type:** Public

Unloads all currently loaded custom modules.

---

### Helper Functions

#### `OGRH.Trim(s)`
**Type:** Public  
**Parameters:**
- `s` (string) - String to trim

**Returns:** `string` - Trimmed string

Removes leading and trailing whitespace.

---

#### `OGRH.CanRW()`
**Type:** Public  
**Returns:** `boolean`

Checks if player can send raid warnings (is raid leader or assistant).

---

#### `OGRH.SayRW(text)`
**Type:** Public  
**Parameters:**
- `text` (string) - Message to send

Sends message to raid warning if authorized, otherwise sends to raid chat.

---

### Integration Functions

#### `OGRH.CheckRollForVersion()`
**Type:** Public  
**Returns:** `boolean`

Checks if RollFor addon is installed with correct version.

**Behavior:**
- Sets `OGRH.ROLLFOR_AVAILABLE` flag
- Returns `true` if version matches `OGRH.ROLLFOR_REQUIRED_VERSION`

---

### Data Access Patterns

#### ✅ CORRECT - Use Core.lua Functions
```lua
-- Get current selection
local raidIdx, encIdx = OGRH.GetCurrentEncounter()

-- Set current selection (with authorization)
OGRH.SetCurrentEncounter(1, 3)

-- Get Active Raid
local activeRaid = OGRH.GetActiveRaid()

-- Copy raid to Active Raid
OGRH.SetActiveRaid(sourceRaidIdx)
```

#### ❌ INCORRECT - Direct SVM Access
```lua
-- DO NOT write indices directly
OGRH_SV.v2.ui.selectedRaidIndex = 3  -- WRONG: Bypasses authorization
OGRH.SVM.Set("ui", "selectedRaidIndex", 3)  -- WRONG: Bypasses sync

-- DO NOT copy raids manually
OGRH_SV.v2.encounterMgmt.raids[1] = sourceRaid  -- WRONG: No deep copy
```

---

### Dependencies

**Required:**
- `SavedVariablesManager (SVM)` - Data persistence and schema routing
- `MessageRouter` - Realtime sync broadcasting

**Optional:**
- `OGRH.UpdateEncounterNavButton()` - UI refresh after encounter change
- `OGRH.SyncIntegrity` - Checksum broadcasting for Active Raid changes
- `OGRH_EncounterFrame` - Encounter planning window refresh

---

### Version History

**v2 Schema (Current):**
- Index-based encounter selection
- Active Raid always at `raids[1]`
- Centralized write interface with authorization
- REALTIME sync for Active Raid, MANUAL sync for library raids

**Pre-v2 (Deprecated):**
- Name-based encounter selection
- No Active Raid concept
- Direct raid access and modification

---

## RolesUI Module (_Raid/RolesUI.lua)

The RolesUI module provides role assignment and management through an interactive drag-and-drop interface. Players are organized into four role columns (Tanks, Healers, Melee, Ranged) with automatic alphabetical sorting.

### Public Functions

#### `OGRH.ShowRolesUI()`
**Type:** Public  
**Returns:** `nil`

Opens the Roles UI window and requests role sync check from raid admin.

**Behavior:**
- Shows the roles management frame
- Automatically calls `OGRH.RequestRolesUISync()` if available
- Displays current raid members organized by role
- Enables drag-and-drop role reassignment

**Example:**
```lua
-- Open roles interface
OGRH.ShowRolesUI()
```

---

#### `OGRH.HideRolesUI()`
**Type:** Public  
**Returns:** `nil`

Closes the Roles UI window.

**Example:**
```lua
-- Close roles interface
OGRH.HideRolesUI()
```

---

#### `OGRH.GetRolePlayers(role)`
**Type:** Public  
**Parameters:**
- `role` (string) - Role bucket: `"TANKS"`, `"HEALERS"`, `"MELEE"`, or `"RANGED"`

**Returns:** `table` - Array of player names in the specified role

Returns all players currently assigned to a specific role.

**Behavior:**
- Returns live reference to role column's player list
- Returns empty table `{}` if role invalid
- Player names are alphabetically sorted

**Example:**
```lua
-- Get all tanks
local tanks = OGRH.GetRolePlayers("TANKS")
for i = 1, table.getn(tanks) do
  OGRH.Msg("Tank " .. i .. ": " .. tanks[i])
end

-- Get all healers
local healers = OGRH.GetRolePlayers("HEALERS")
```

---

#### `OGRH.GetRoleCount(role)`
**Type:** Public  
**Parameters:**
- `role` (string) - Role bucket: `"TANKS"`, `"HEALERS"`, `"MELEE"`, or `"RANGED"`

**Returns:** `number` - Count of players in the role

Returns the number of players assigned to a specific role.

**Example:**
```lua
-- Check tank count
local tankCount = OGRH.GetRoleCount("TANKS")
if tankCount < 2 then
  OGRH.Msg("Warning: Only " .. tankCount .. " tanks assigned!")
end
```

---

#### `OGRH.ForEachRolePlayer(role, callback)`
**Type:** Public  
**Parameters:**
- `role` (string) - Role bucket: `"TANKS"`, `"HEALERS"`, `"MELEE"`, or `"RANGED"`
- `callback` (function) - Function to call for each player: `callback(playerName, index)`

Iterates through all players in a role, calling the callback for each.

**Example:**
```lua
-- Mark all tanks with skull
OGRH.ForEachRolePlayer("TANKS", function(playerName, index)
  SetRaidTarget(playerName, 8)  -- Skull icon
end)

-- Send whisper to all healers
OGRH.ForEachRolePlayer("HEALERS", function(playerName, index)
  SendChatMessage("Please save mana", "WHISPER", nil, playerName)
end)
```

---

#### `OGRH.RolesUI.SetPlayerRole(playerName, roleBucket)`
**Type:** Public  
**Authorization:** No restrictions (designed for programmatic use by Invites module)  
**Parameters:**
- `playerName` (string) - Player name to assign
- `roleBucket` (string) - Role: `"TANKS"`, `"HEALERS"`, `"MELEE"`, or `"RANGED"`

**Returns:** `boolean` - Success status

Programmatically assigns a player to a role. Used by Invites module for automatic role sync when players join raid during Invite Mode.

**Behavior:**
- Validates role bucket against valid roles
- Removes player from all other role columns
- Adds player to target role column
- Saves role assignment to SavedVariables
- Refreshes UI if roles window is open
- Syncs tank/healer roles to Puppeteer and pfUI
- Returns `false` if player name empty or role invalid

**Example:**
```lua
-- Called by Invites module when player joins during Invite Mode
local success = OGRH.RolesUI.SetPlayerRole("Tankadin", "TANKS")
if success then
  OGRH.Msg("Tankadin assigned to Tanks")
end

-- Called by Poll module when player responds to role poll
OGRH.RolesUI.SetPlayerRole("Holypally", "HEALERS")
```

**Implementation Notes:**
- No authorization check (designed for internal module use)
- Triggers Puppeteer/pfUI integration for tanks and healers
- Calls `OGRH.RenderRoles()` if UI is visible
- Updates `OGRH_SV.v2.roles` table
- Used by Invites module via `OGRH.Invites.SyncPlayerRole()`
- Used by Poll module when processing role poll responses

---

### Global Helper Functions (External Addon Integration)

These functions provide external addons (like RABuffs) access to the role system without requiring OGRH namespace access.

#### `OGRH_GetPlayerRole(playerName)`
**Type:** Global Public  
**Parameters:**
- `playerName` (string) - Player name to query

**Returns:** `string|nil` - Role bucket (`"TANKS"`, `"HEALERS"`, `"MELEE"`, `"RANGED"`) or `nil` if no role assigned

Returns a player's current role assignment.

**Example:**
```lua
-- Check if player is a tank
local role = OGRH_GetPlayerRole("Tankadin")
if role == "TANKS" then
  -- Apply tank-specific buff
end
```

---

#### `OGRH_IsRoleSystemAvailable()`
**Type:** Global Public  
**Returns:** `boolean`

Checks if OG-RaidHelper role system is loaded and available.

**Example:**
```lua
-- Check before using role functions
if OGRH_IsRoleSystemAvailable() then
  local tanks = OGRH_GetPlayersInRole("TANKS")
  -- Process tanks
end
```

---

#### `OGRH_GetPlayersInRole(role)`
**Type:** Global Public  
**Parameters:**
- `role` (string) - Role bucket: `"TANKS"`, `"HEALERS"`, `"MELEE"`, or `"RANGED"`

**Returns:** `table` - Array of player names (or empty table if role system unavailable)

Returns all players in a specific role. Wrapper for `OGRH.GetRolePlayers()`.

**Example:**
```lua
-- Get all healers for external addon
local healers = OGRH_GetPlayersInRole("HEALERS")
for i = 1, table.getn(healers) do
  -- Apply healer-specific logic
end
```

---

### Frame References

#### `OGRH.rolesFrame`
**Type:** Frame Reference  
**Access:** Public Read-Only

Reference to the main roles management frame.

**Properties:**
- `tanksList` (table) - Backward compat reference to `ROLE_COLUMNS[1].players`
- `getHealers()` (function) - Backward compat function, returns `ROLE_COLUMNS[2].players`
- `RefreshColumnDisplays()` (function) - Refreshes visual display of all role columns
- `UpdatePlayerLists(forceSyncRollFor)` (function) - Updates player lists from raid roster
- `ROLE_COLUMNS` (table) - Array of 4 role column definitions

**Example:**
```lua
-- Access tanks list (backward compat)
local tanks = OGRH.rolesFrame.tanksList

-- Refresh display after manual change
OGRH.rolesFrame.RefreshColumnDisplays()

-- Force sync from RollFor/Invites
OGRH.rolesFrame.UpdatePlayerLists(true)
```

---

### UI Features

**Drag-and-Drop Role Assignment:**
- Click and drag player names between role columns
- Requires OFFICER or ADMIN permission
- Automatically saves to SavedVariables
- Updates Puppeteer/pfUI integration in realtime
- Shows permission error if unauthorized

**Polling System:**
- **Poll Button** (top-left): Left-click to start/cancel full role poll sequence
- **Column Headers** (clickable): Click any role header to poll that specific role
- Requires Raid Leader, Assistant, or designated Raid Admin

**Display Features:**
- Players alphabetically sorted within each column
- Class-colored player names
- 4 columns: Tanks, Healers, Melee, Ranged
- Auto-updates on `RAID_ROSTER_UPDATE` event

**Integration Features:**
- **Puppeteer Sync**: Tank and Healer roles auto-sync to Puppeteer role system
- **pfUI Sync**: Tank roles auto-sync to pfUI tankrole system
- **RollFor Integration**: Imports role data from RollFor/Invites when players join during Invite Mode

---

### Role Assignment Priority

RolesUI uses a **dual-path** approach to role assignment:

#### Path 1: Invites Module Push (Event-Driven)
When Invite Mode is active, the Invites module actively pushes role data to RolesUI:

1. **Trigger**: Player joins raid (`RAID_ROSTER_UPDATE` event)
2. **Check**: Invites module detects new member via `previousRaidMembers` tracking
3. **Push**: Calls `OGRH.Invites.SyncPlayerRole(playerName)`
   - Looks up player in roster data (`GetRosterPlayers()`)
   - Calls `OGRH.RolesUI.SetPlayerRole(playerName, player.role)`
   - Saves role assignment immediately
4. **Result**: Player assigned to role from RollFor/Invites/Groups data

**Implementation (Invites.lua):**
```lua
-- RAID_ROSTER_UPDATE handler
if not previousRaidMembers[name] then
  OGRH.Invites.SyncPlayerRole(name)  -- Push to RolesUI
end
```

#### Path 2: RolesUI Pull (Fallback)
When Invite Mode is active but Invites module hasn't synced yet, RolesUI can pull role data:

1. **Trigger**: `UpdatePlayerLists()` called (e.g., RAID_ROSTER_UPDATE, manual refresh)
2. **Check**: Player is new (`not knownPlayers[name]`) AND no manual assignment exists
3. **Pull**: Queries `OGRH.Invites.GetRosterPlayers()` directly
4. **Result**: Role applied and saved if found in roster data

**Priority Order (Per Player):**

1. **Manual Assignment** (Highest Priority)
   - Saved role from previous drag-and-drop assignment
   - Persists across sessions via SavedVariables
   - **Blocks both push and pull** - manual assignments are never overwritten

2. **Invites Push** (Second Priority - Active During Invite Mode)
   - Role data pushed by `OGRH.Invites.SyncPlayerRole()`
   - Only applied on first join (tracked via `previousRaidMembers`)
   - Sources: RollFor, Raid Helper (Invites), Raid Helper (Groups)

3. **RolesUI Pull** (Third Priority - Fallback)
   - Only if no manual assignment exists
   - Only if player is new (`isNewPlayer = true`)
   - Only if Invite Mode is active
   - Queries `OGRH.Invites.GetRosterPlayers()` directly

4. **Class Defaults** (Lowest Priority)
   - Warrior → Tanks
   - Priest/Paladin/Druid → Healers
   - Rogue → Melee
   - All others → Ranged

**Force Sync:**
```lua
-- Override manual assignments with RollFor/Invites data (uses Pull path)
OGRH.rolesFrame.UpdatePlayerLists(true)
```

**Key Difference:**
- **Push (Invites)**: Active during Invite Mode - Invites module detects joins and pushes roles
- **Pull (RolesUI)**: Passive fallback - RolesUI queries Invites data when needed
- Both paths respect manual assignments (never overwritten unless force sync)

---

### Authorization

**Role Modification (Drag-and-Drop):**
- Requires: OFFICER or ADMIN permission
- Checked via `OGRH.CanModifyAssignments(playerName)`
- Shows chat error: "You don't have permission to modify role assignments"

**Polling:**
- Requires: Raid Leader, Assistant, or designated Raid Admin
- Checked via `OGRH.CanManageRoles()`
- Shows chat error: "Only raid leader, assistants, or raid admin can start polls"

---

### Data Storage

**Role Assignments:**
```lua
-- SavedVariables structure
OGRH_SV.v2.roles = {
  ["PlayerName"] = "TANKS",
  ["AnotherPlayer"] = "HEALERS",
  -- ...
}
```

**Role Buckets:**
- `"TANKS"` - Tank role
- `"HEALERS"` - Healer role
- `"MELEE"` - Melee DPS role
- `"RANGED"` - Ranged DPS role

---

### Integration with Other Modules

**Invites Module (Push-Based Role Sync):**
- **Event**: `RAID_ROSTER_UPDATE` in Invites module
- **Mechanism**: Invites module actively detects new raid members
- **Tracking**: Uses `previousRaidMembers` table to identify first-time joins
- **Action**: Calls `OGRH.Invites.SyncPlayerRole(playerName)` for new members
- **Result**: `SetPlayerRole()` called with role from RollFor/Invites/Groups roster data
- **Condition**: Only during Invite Mode (`inviteMode.enabled == true`)
- **Auto-Organize**: Raid-Helper source also triggers `AutoOrganizeNewMembers()`

**Example Flow:**
```lua
-- Player "Tankadin" joins raid
-- 1. RAID_ROSTER_UPDATE fires in Invites module
-- 2. Invites detects "Tankadin" not in previousRaidMembers
-- 3. Calls OGRH.Invites.SyncPlayerRole("Tankadin")
-- 4. Looks up "Tankadin" in GetRosterPlayers() → finds role "TANKS"
-- 5. Calls OGRH.RolesUI.SetPlayerRole("Tankadin", "TANKS")
-- 6. Role saved and Puppeteer/pfUI synced
```

**Poll Module:**
- Uses `OGRH.RolesUI.SetPlayerRole()` when processing role poll responses
- Assigns player to role they selected in poll
- No authorization check needed (poll responses are voluntary)

**Puppeteer Integration:**
- Tank and Healer roles sync to `Puppeteer.SetAssignedRole()`
- Calls `Puppeteer.UpdateUnitFrameGroups()` after batch changes
- Other roles set to "No Role" in Puppeteer

**pfUI Integration:**
- Tank roles sync to `pfUI.uf.raid.tankrole[playerName]`
- Updates unit frames via `pfUI.uf.raid:Show()`
- Only tank role supported (no healer sync)

**Consume Module:**
- Uses role assignments for consume tracking
- Filters consumes by role (tanks need flasks, healers need mana pots, etc.)

---

### Event Handlers

RolesUI registers and handles:

- `VARIABLES_LOADED` - Initializes RolesUI frame on addon load
- `RAID_ROSTER_UPDATE` - Updates player lists when raid composition changes

---

### Known Players Tracking

RolesUI tracks which players have joined the raid to apply first-join logic:

**Behavior:**
- `knownPlayers` table stores all players who have joined current raid session
- RollFor/Invites data only applied on first join
- Prevents overwriting manual assignments when player re-joins
- Cleared when player leaves raid

**Force Override:**
```lua
-- Force apply RollFor/Invites data even for known players
OGRH.rolesFrame.UpdatePlayerLists(true)
```

---

### Removed Features

The following features have been removed in favor of integration with other systems:

- **Encounter Button** - Use `OGRH.ShowEncounterManagementWindow()` directly
- **Marks Button** - Mark management integrated into Encounter system
- **Assignments Button** - Assignment system integrated into Encounter system
- **Test Button** - Test mode removed
- **Raid Target Icons** - Marking handled by Encounter system
- **Tank Assignment Icons** - Assignment handled by Encounter system
- **Up/Down Arrows** - Manual ordering replaced with alphabetical sort
- **Sync RollFor Button** - Role sync now automatic (v1.17.0)

---

### Dependencies

**Required:**
- `OGRH_Core.lua` - Core functions and SavedVariablesManager
- `OGRH.SVM` - SavedVariables access for role persistence
- `OGRH.Roles.nameClass` - Class lookup table for color coding

**Optional:**
- `OGRH.Poll` - Polling system for role requests
- `OGRH.CanModifyAssignments(playerName)` - Authorization check
- `OGRH.CanManageRoles()` - Polling authorization check
- `OGRH.RequestRolesUISync()` - Sync request on window open
- `OGRH.Invites.GetRosterPlayers()` - RollFor/Invites data source
- `OGRH.Invites.IsInviteModeActive()` - Invite mode check
- `Puppeteer.SetAssignedRole()` - Puppeteer integration
- `Puppeteer.UpdateUnitFrameGroups()` - Puppeteer UI update
- `pfUI.uf.raid.tankrole` - pfUI tank role table
- `pfUI.uf.raid:Show()` - pfUI UI update

---

### Version History

**v1.17.0 (Current):**
- Removed "Sync RollFor" button - role sync now automatic
- Added `SetPlayerRole()` API for programmatic role assignment
- Role sync happens automatically via Invites module when players join during Invite Mode
- Role data sourced from all invite systems: RollFor, Raid Helper (Invites), Raid Helper (Groups)
- Unified role sync using `OGRH.Invites.GetRosterPlayers()`

**v1.16.0:**
- Added Puppeteer integration (tank/healer roles)
- Added pfUI integration (tank roles)
- Fixed role priority: Manual assignments now take precedence over RollFor data
- Tank role changes trigger immediate UI updates in Puppeteer and pfUI

---

### Debugging

**Common Issues:**

**"You don't have permission to modify role assignments"**
- Requires OFFICER or ADMIN permission
- Check `OGRH.CanModifyAssignments(UnitName("player"))`

**"Only raid leader, assistants, or raid admin can start polls"**
- Requires RL/A or designated admin
- Check `OGRH.CanManageRoles()`

**Roles not syncing from RollFor/Invites:**
- Verify Invite Mode is active: `OGRH.Invites.IsInviteModeActive()`
- Check if player is known: May need force sync via `UpdatePlayerLists(true)`
- Verify RollFor version: `OGRH.CheckRollForVersion()`

**Manual Inspections:**
```lua
-- View all saved roles
local roles = OGRH.SVM.Get("roles")
for name, role in pairs(roles) do
  print(name .. " = " .. role)
end

-- Check if player is known (first join vs re-join)
-- (knownPlayers is local, no direct access)

-- Force full resync
OGRH.rolesFrame.UpdatePlayerLists(true)
```

---

## Invites Module (_Configuration/Invites.lua)

The Invites module manages raid invites with support for multiple data sources (RollFor, Raid-Helper Invites, Raid-Helper Groups). It provides automated invite mode, role sync, group organization, and player status tracking.

### Data Sources

The module supports three data sources via two import types:

**Source Type Constants:**
- `OGRH.Invites.SOURCE_TYPE.ROLLFOR` - RollFor addon integration
- `OGRH.Invites.SOURCE_TYPE.RAIDHELPER` - Raid-Helper JSON imports

**Data Sources:**
1. **RollFor** - Real-time integration with RollFor addon
   - Soft reserve list with class and spec/role
   - Auto-updates when RollFor data changes
   - No manual import required

2. **Raid-Helper (Invites)** - JSON import for sign-ups
   - Import via "Import Raid-Helper (Invites)" button
   - Includes: name, class, role, bench/absence status
   - Supports roster metadata (raid title, instance, date)

3. **Raid-Helper (Groups)** - JSON import for group assignments
   - Import via "Import Raid-Helper (Groups)" button
   - Includes: all Invites data PLUS group assignments (1-8)
   - Enables auto-organize functionality

### Public Functions

#### `OGRH.Invites.ShowWindow()`
**Type:** Public  
**Authorization:** Requires RollFor addon  
**Returns:** `nil`

Opens the Invites management window.

**Behavior:**
- Closes other addon windows
- Creates window if first use
- Refreshes player list from current data source
- Shows error if RollFor not available

**Example:**
```lua
-- Open invites window
OGRH.Invites.ShowWindow()
```

---

#### `OGRH.Invites.GetRosterPlayers()`
**Type:** Public  
**Returns:** `table` - Array of standardized player objects

Returns unified roster data from the currently active data source (RollFor or Raid-Helper).

**Player Object Structure:**
```lua
{
  name = "PlayerName",        -- Normalized (Title case)
  class = "WARRIOR",          -- Uppercase class name or nil
  role = "TANKS",             -- OGRH format: TANKS, HEALERS, MELEE, RANGED
  group = 1,                  -- Group assignment (1-8) or nil
  bench = false,              -- On bench status
  absent = false,             -- Absent status
  status = "not_in_raid",     -- Current status (see STATUS constants)
  online = false,             -- Online status
  source = "rollfor",         -- Data source type
  rawRole = "WarriorTank"     -- Original role string (RollFor only)
}
```

**Example:**
```lua
-- Get all roster players
local players = OGRH.Invites.GetRosterPlayers()
for _, player in ipairs(players) do
  if not player.bench and not player.absent then
    print(player.name .. " - " .. player.role)
  end
end
```

**Implementation Notes:**
- Automatically switches between RollFor and Raid-Helper based on `currentSource`
- Returns empty table `{}` if no data loaded
- Used by RolesUI for automatic role sync

---

#### `OGRH.Invites.GetSoftResPlayers()`
**Type:** Public  
**Returns:** `table` - Array of RollFor player objects

Returns player list from RollFor addon (soft reserve data).

**RollFor Player Structure:**
```lua
{
  name = "PlayerName",
  class = "Warrior",
  role = "WarriorTank"  -- ClassSpec format
}
```

**Example:**
```lua
-- Get soft-res players from RollFor
local players = OGRH.Invites.GetSoftResPlayers()
```

**Implementation Notes:**
- Requires RollFor addon loaded
- Calls `RollFor.GetSoftResPlayers()`
- Returns empty table if RollFor unavailable

---

#### `OGRH.Invites.IsInviteModeActive()`
**Type:** Public  
**Returns:** `boolean`

Checks if Invite Mode is currently active.

**Example:**
```lua
-- Check invite mode status
if OGRH.Invites.IsInviteModeActive() then
  -- Auto-sync roles for joining players
end
```

---

#### `OGRH.Invites.ToggleInviteMode()`
**Type:** Public  
**Authorization:** No restrictions  
**Returns:** `nil`

Starts or stops automated invite mode.

**Behavior When Starting:**
- Announces to guild chat
- Shows Invite Mode panel
- Does immediate first invite cycle
- Sets up OnUpdate handler for periodic invites
- Auto-responds to whispers from roster players

**Behavior When Stopping:**
- Hides Invite Mode panel
- Stops automatic invites
- Disables auto-responses

**Example:**
```lua
-- Toggle invite mode on/off
OGRH.Invites.ToggleInviteMode()
```

**Implementation Notes:**
- Invite interval configurable via `inviteMode.interval` (default 60 seconds)
- Automatically converts party to raid when needed
- Tracks progress (invited count vs total players)

---

#### `OGRH.Invites.InvitePlayer(playerName)`
**Type:** Public  
**Parameters:**
- `playerName` (string) - Player name to invite

**Returns:** `boolean` - Success status

Invites a single player and tracks the invitation.

**Behavior:**
- Checks player status (online, in raid, declined, etc.)
- Sends invite via `InviteByName()`
- Updates `playerStatuses` tracking
- Returns `false` if already in raid, offline, or declined

**Example:**
```lua
-- Invite specific player
local success = OGRH.Invites.InvitePlayer("Tankadin")
```

---

#### `OGRH.Invites.InviteAllOnline()`
**Type:** Public  
**Authorization:** No restrictions  
**Returns:** `nil`

Invites all online players from roster (excluding benched/absent).

**Behavior:**
- Iterates through `GetRosterPlayers()`
- Checks online status for each
- Skips benched and absent players
- Invites all eligible online players

**Example:**
```lua
-- Mass invite button click
OGRH.Invites.InviteAllOnline()
```

---

#### `OGRH.Invites.IsPlayerInRaid(playerName)`
**Type:** Public  
**Parameters:**
- `playerName` (string) - Player name to check

**Returns:** `boolean`

Checks if player is currently in the raid.

**Example:**
```lua
-- Check if player already in raid
if not OGRH.Invites.IsPlayerInRaid("Tankadin") then
  OGRH.Invites.InvitePlayer("Tankadin")
end
```

---

#### `OGRH.Invites.GetPlayerStatus(playerName)`
**Type:** Public  
**Parameters:**
- `playerName` (string) - Player name to query

**Returns:** `(string, boolean, string|nil)` - `(status, online, groupType)`

Returns detailed status information for a player.

**Status Constants:**
- `"in_raid"` - Player is in current raid
- `"invited"` - Player has been invited this session
- `"declined"` - Player declined invite
- `"offline"` - Player is offline
- `"in_other_group"` - Player is in another group/raid
- `"not_in_raid"` - Player is online and available

**Example:**
```lua
-- Get player status
local status, online, groupType = OGRH.Invites.GetPlayerStatus("Tankadin")
if status == "offline" then
  print("Player is offline")
elseif status == "declined" then
  print("Player declined invite")
end
```

---

#### `OGRH.Invites.WhisperPlayer(playerName, message)`
**Type:** Public  
**Parameters:**
- `playerName` (string) - Player name
- `message` (string) - Message to send

**Returns:** `nil`

Sends a whisper to the specified player.

**Example:**
```lua
-- Whisper player
OGRH.Invites.WhisperPlayer("Tankadin", "Can you join now?")
```

---

#### `OGRH.Invites.ClearDeclined(playerName)`
**Type:** Public  
**Parameters:**
- `playerName` (string) - Player name

**Returns:** `nil`

Clears declined status for a player, allowing them to be invited again.

**Example:**
```lua
-- Reset declined status
OGRH.Invites.ClearDeclined("Tankadin")
```

---

#### `OGRH.Invites.ClearAllTracking()`
**Type:** Public  
**Returns:** `nil`

Clears all invite tracking (invited, declined statuses).

**Example:**
```lua
-- Reset all tracking
OGRH.Invites.ClearAllTracking()
```

---

#### `OGRH.Invites.SyncPlayerRole(playerName)`
**Type:** Public (Internal Use)  
**Parameters:**
- `playerName` (string) - Player who just joined raid

**Returns:** `nil`

Syncs a player's role from roster data to RolesUI when they join during Invite Mode.

**Behavior:**
- Only active when Invite Mode is enabled
- Looks up player in `GetRosterPlayers()`
- Calls `OGRH.RolesUI.SetPlayerRole()` if role found
- Automatically called by `RAID_ROSTER_UPDATE` handler

**Example:**
```lua
-- Called automatically when player joins
-- Manual call (rare):
OGRH.Invites.SyncPlayerRole("Tankadin")
```

**Implementation Notes:**
- Part of automatic role sync system (push path)
- Only syncs if Invite Mode active
- No effect if player not in roster data

---

#### `OGRH.Invites.GeneratePlanningRoster()`
**Type:** Public  
**Returns:** `table` - Planning roster array

Generates a planning roster from current roster data for EncounterMgmt integration. Filters out absent players while keeping benched players for planning purposes.

**Behavior:**
- Reads current roster via `GetRosterPlayers()`
- Excludes only absent players (keeps benched)
- Maps all roles to OGRH format
- Saves to `invites.planningRoster` in schema
- Returns the generated roster array

**Planning Roster Entry Structure:**
```lua
{
  name = "PlayerName",
  class = "WARRIOR",
  role = "TANKS",           -- OGRH format: TANKS, HEALERS, MELEE, RANGED
  group = 1,                -- Group assignment or nil
  online = false,           -- Online status
  source = "rollfor",       -- Data source type
  benched = false           -- Benched status (preserved for planning)
}
```

**Example:**
```lua
-- Generate planning roster after import
OGRH.Invites.GeneratePlanningRoster()

-- Access generated roster
local roster = OGRH.Invites.GetPlanningRoster()
for _, player in ipairs(roster) do
  if not player.benched then
    print("Active: " .. player.name .. " - " .. player.role)
  else
    print("Benched: " .. player.name .. " - " .. player.role)
  end
end
```

**Implementation Notes:**
- Called automatically after roster import (RollFor, Raid-Helper)
- Benched players included for assignment planning
- Absent players excluded (won't be in raid)
- Stored with MANUAL sync level (no auto-sync)

---

#### `OGRH.Invites.GetPlanningRoster()`
**Type:** Public  
**Returns:** `table` - Cached planning roster array

Returns the cached planning roster for EncounterMgmt integration.

**Behavior:**
- Reads `invites.planningRoster` from schema
- Returns empty table `{}` if no roster generated
- No filtering or processing (returns cached data as-is)

**Example:**
```lua
-- Get planning roster for encounter assignment
local roster = OGRH.Invites.GetPlanningRoster()
print("Planning roster has " .. table.getn(roster) .. " players")

-- Use in EncounterMgmt for auto-assignment
for _, player in ipairs(roster) do
  if player.role == "TANKS" and not player.benched then
    -- Auto-assign to tank role
  end
end
```

**Implementation Notes:**
- Accessor function for EncounterMgmt module
- Returns cached data (no regeneration)
- Use `GeneratePlanningRoster()` to refresh roster
- Cleared on new roster import

---

#### `OGRH.Invites.ApplyGroupAssignments()`
**Type:** Public  
**Authorization:** Requires Raid Leader or Assistant  
**Returns:** `nil`

Organizes raid members into groups based on Raid-Helper Groups assignments.

**Behavior:**
- Only available when using Raid-Helper (Groups) source
- Requires group assignments in imported data
- Moves players to assigned groups (1-8)
- Handles group swaps when target group full
- Skips players in combat
- Shows feedback messages

**Example:**
```lua
-- Organize raid groups (manual)
OGRH.Invites.OrganizeRaidGroups()
```

**Alias:**
- `OGRH.Invites.OrganizeRaidGroups()` - Manual version with chat feedback

**Implementation Notes:**
- Auto-organize version (`AutoOrganizeNewMembers()`) runs silently when players join
- Only active for Raid-Helper source
- Requires RL/A permissions

---

#### `OGRH.Invites.ParseRaidHelperJSON(jsonString)`
**Type:** Public  
**Parameters:**
- `jsonString` (string) - Raid-Helper Invites JSON export

**Returns:** `(table|nil, string|nil)` - `(parsedData, errorMessage)`

Parses Raid-Helper Invites JSON into standardized format.

**Parsed Data Structure:**
```lua
{
  id = "raid-123",
  name = "MC Raid",
  players = {
    {
      name = "PlayerName",
      class = "WARRIOR",
      role = "TANKS",
      bench = false,
      absent = false,
      status = "signed",
      group = nil  -- Not in Invites format
    },
    -- ...
  }
}
```

**Example:**
```lua
-- Parse JSON
local data, err = OGRH.Invites.ParseRaidHelperJSON(jsonString)
if err then
  print("Parse error: " .. err)
else
  print("Loaded " .. table.getn(data.players) .. " players")
end
```

---

#### `OGRH.Invites.ParseRaidHelperGroupsJSON(jsonString)`
**Type:** Public  
**Parameters:**
- `jsonString` (string) - Raid-Helper Groups JSON export

**Returns:** `(table|nil, string|nil)` - `(parsedData, errorMessage)`

Parses Raid-Helper Groups JSON (includes group assignments).

**Behavior:**
- Same as `ParseRaidHelperJSON()` but includes `group` field
- Enables auto-organize functionality

**Example:**
```lua
-- Parse Groups JSON
local data, err = OGRH.Invites.ParseRaidHelperGroupsJSON(jsonString)
if data then
  -- Can now use ApplyGroupAssignments()
end
```

---

#### `OGRH.Invites.ShowJSONImportDialog(importType)`
**Type:** Public  
**Parameters:**
- `importType` (string) - `"invites"` or `"groups"`

**Returns:** `nil`

Shows JSON import dialog for Raid-Helper data.

**Example:**
```lua
-- Show invites import dialog
OGRH.Invites.ShowJSONImportDialog("invites")

-- Show groups import dialog
OGRH.Invites.ShowJSONImportDialog("groups")
```

---

#### `OGRH.Invites.MapRoleToOGRH(roleString, source)`
**Type:** Public  
**Parameters:**
- `roleString` (string) - Role from data source
- `source` (string) - Source type (`ROLLFOR` or `RAIDHELPER`)

**Returns:** `string|nil` - OGRH role bucket (`TANKS`, `HEALERS`, `MELEE`, `RANGED`)

Converts role strings from different sources to standardized OGRH format.

**Example:**
```lua
-- Map RollFor role
local role = OGRH.Invites.MapRoleToOGRH("WarriorTank", "rollfor")
-- Returns: "TANKS"

-- Map Raid-Helper role
local role = OGRH.Invites.MapRoleToOGRH("Healer", "raidhelper")
-- Returns: "HEALERS"
```

---

#### `OGRH.Invites.MapRollForRoleToOGRH(rollForRole)`
**Type:** Public  
**Parameters:**
- `rollForRole` (string) - ClassSpec format from RollFor

**Returns:** `string|nil` - OGRH role bucket

Maps RollFor ClassSpec roles to OGRH role buckets.

**RollFor Role Mapping:**
- Tank specs → `TANKS` (WarriorTank, PaladinTank, DruidTank)
- Healer specs → `HEALERS` (PriestHealer, PaladinHealer, DruidHealer, ShamanHealer)
- Melee specs → `MELEE` (RogueDD, WarriorDD, DruidDD, ShamanDD, PaladinDD, HunterDD)
- Ranged specs → `RANGED` (MageDD, WarlockDD, HunterDD)

**Example:**
```lua
-- Map RollFor role
local role = OGRH.Invites.MapRollForRoleToOGRH("PriestHealer")
-- Returns: "HEALERS"
```

---

#### `OGRH.Invites.GetMetadata()`
**Type:** Public  
**Returns:** `table` - Roster metadata

Returns raid metadata from current data source.

**Metadata Structure:**
```lua
{
  source = "rollfor",      -- Data source type
  instance = "MC",         -- Instance/raid name
  date = "2026-02-02",     -- Raid date
  title = "MC Raid"        -- Full title
}
```

**Example:**
```lua
-- Get raid info
local meta = OGRH.Invites.GetMetadata()
print("Raid: " .. meta.title)
```

---

#### `OGRH.Invites.GetInstanceName(instanceId)`
**Type:** Public  
**Parameters:**
- `instanceId` (string) - Instance abbreviation

**Returns:** `string` - Full instance name

Converts instance abbreviations to full names.

**Supported Instances:**
- `MC` → Molten Core
- `BWL` → Blackwing Lair
- `AQ20` → Ruins of Ahn'Qiraj
- `AQ40` → Temple of Ahn'Qiraj
- `ZG` → Zul'Gurub
- `NAXX` → Naxxramas
- `ONY` → Onyxia's Lair

**Example:**
```lua
local name = OGRH.Invites.GetInstanceName("MC")
-- Returns: "Molten Core"
```

---

### UI Components

**Main Invites Window:**
- **Data Source Selector** - Toggle between RollFor and Raid-Helper
- **Import Buttons** - Import Raid-Helper JSON (Invites or Groups)
- **Player List** - Scrollable list organized by status
  - Active roster (online/offline)
  - Benched players
  - Absent players
- **Action Buttons** - Invite, Whisper, Clear Declined
- **Invite Mode Toggle** - Start/stop automated invites
- **Organize Groups** - Apply Raid-Helper group assignments

**Invite Mode Panel:**
- **Progress Bars** - Visual countdown and player count
- **Stop Button** - Cancel invite mode
- **Draggable** - Position saved to SavedVariables

**Player List Sections:**
- Players grouped by status
- Class-colored names
- Online/offline indicators
- In-raid status badges
- Benched/absent visual indicators

---

### Invite Mode Features

**Automatic Invites:**
- **Interval-based** - Configurable delay between cycles (default 60s)
- **Smart inviting** - Only invites online, non-benched, non-absent players
- **Party conversion** - Auto-converts to raid when needed
- **Progress tracking** - Shows invited count vs total players

**Auto-Response System:**
- **Benched players** - "You are currently on the bench..."
- **Absent players** - "You are marked as absent..."
- **Active players** - Auto-invites if not already in raid

**Auto-Organize (Groups Source Only):**
- **Silent mode** - Auto-organizes when players join during Invite Mode
- **Manual mode** - "Organize Groups" button with feedback
- **Smart swapping** - Handles full groups intelligently

---

### Role Sync Integration

**Automatic Role Push (Primary):**
```lua
-- RAID_ROSTER_UPDATE handler in Invites.lua
if not previousRaidMembers[name] then
  OGRH.Invites.SyncPlayerRole(name)  -- Push to RolesUI
end
```

**Role Sync Flow:**
1. Player joins raid
2. `RAID_ROSTER_UPDATE` event fires
3. Invites module detects new member
4. Calls `SyncPlayerRole(playerName)`
5. Looks up role in `GetRosterPlayers()`
6. Calls `OGRH.RolesUI.SetPlayerRole(name, role)`
7. Role saved and Puppeteer/pfUI synced

**Conditions:**
- Only during Invite Mode (`inviteMode.enabled == true`)
- Only for players in roster data
- Only on first join (tracked via `previousRaidMembers`)

---

### Data Storage

**SavedVariables Structure:**
```lua
OGRH_SV.v2.invites = {
  -- Source selection
  currentSource = "rollfor",  -- or "raidhelper"
  
  -- Raid-Helper data
  raidhelperData = {
    id = "raid-123",
    name = "MC Raid",
    players = {...}
  },
  raidhelperGroupsData = {...},
  
  -- Invite Mode state
  inviteMode = {
    enabled = false,
    interval = 60,
    lastInviteTime = 0,
    totalPlayers = 0,
    invitedCount = 0
  },
  
  -- Invite tracking (session only)
  declinedPlayers = {...},
  history = {...},
  
  -- v2 Invites Update additions
  autoSort = false,          -- Auto-organize new members during Invite Mode
  planningRoster = {         -- Cached roster for EncounterMgmt integration
    -- Array of standardized player objects (benched included, absent excluded)
  },
  
  -- UI state
  invitePanelPosition = {
    point = "BOTTOMRIGHT",
    x = -20,
    y = 200
  }
}
```

---

### Event Handlers

Invites module registers and handles:

- `RAID_ROSTER_UPDATE` - Detects new members, syncs roles, auto-organizes
- `CHAT_MSG_WHISPER` - Auto-response for roster players during Invite Mode
- `OnUpdate` (Invite Mode Panel) - Countdown timer, periodic invites

---

### Integration with Other Modules

**RolesUI Integration:**
- **Push-based sync** - Calls `SetPlayerRole()` when players join
- **Data source** - Provides `GetRosterPlayers()` for pull-based sync
- **IsInviteModeActive()** - RolesUI checks before pulling data

**RollFor Integration:**
- **Real-time data** - Queries `RollFor.GetSoftResPlayers()`
- **Change detection** - Hash-based detection of RollFor updates
- **Auto-refresh** - Updates UI when RollFor data changes

**Raid Organization:**
- **Group assignments** - Applies Raid-Helper group data
- **Auto-organize** - Organizes new members silently
- **Manual organize** - "Organize Groups" button with feedback

---

### Authorization

**No Permission Checks:**
- Anyone can use Invites window
- Anyone can toggle Invite Mode
- Anyone can import JSON data

**RL/A Required:**
- `ApplyGroupAssignments()` - Requires raid leader or assistant
- `OrganizeRaidGroups()` - Requires raid leader or assistant

---

### Dependencies

**Required:**
- `OGRH_Core.lua` - Core functions and SavedVariablesManager
- `RollFor` addon - For RollFor data source
- `json.lua` library - For Raid-Helper JSON parsing

**Optional:**
- `OGRH.RolesUI.SetPlayerRole()` - Role sync integration
- `OGRH.CloseAllWindows()` - Window management
- `OGRH.StyleButton()` - Button styling

---

### Debugging

**Common Issues:**

**"Invites requires RollFor version X"**
- RollFor addon not loaded or wrong version
- Check `OGRH.ROLLFOR_AVAILABLE` flag

**Roles not syncing:**
- Verify Invite Mode is active
- Check if player is in roster data: `GetRosterPlayers()`
- Manually sync: `OGRH.Invites.SyncPlayerRole("PlayerName")`

**JSON parse errors:**
- Verify JSON format (copy exactly from Raid-Helper export)
- Check for trailing commas or formatting issues
- Error message shows line/column of parse error

**Group organize not working:**
- Must use Raid-Helper (Groups) source (not Invites)
- Requires RL/A permissions
- Players in combat cannot be moved

**Manual Inspections:**
```lua
-- Check current source
local source = OGRH.SVM.GetPath("invites.currentSource")

-- Get all roster players
local players = OGRH.Invites.GetRosterPlayers()
for _, p in ipairs(players) do
  print(p.name, p.role, p.group or "no group")
end

-- Check invite mode status
local inviteMode = OGRH.SVM.GetPath("invites.inviteMode")
print("Enabled:", inviteMode.enabled)
print("Interval:", inviteMode.interval)

-- View Raid-Helper data
local data = OGRH.SVM.GetPath("invites.raidhelperData")
if data then
  print("Raid:", data.name)
  print("Players:", table.getn(data.players))
end
```

---

## Invites Module (_Configuration/Invites.lua) - v2 Update

The Invites module manages raid roster imports from RollFor soft-reserve data and Raid-Helper JSON exports, with automated invite cycles and planning roster integration.

### Public Functions

#### `OGRH.Invites.GeneratePlanningRoster()`
**Type:** Public  
**Returns:** `table` - Planning roster array

Generates planning roster from current import source, filtering out absent players and mapping roles to OGRH format (TANKS/HEALERS/MELEE/RANGED).

**Behavior:**
- Reads roster from current source (RollFor or Raid-Helper)
- Filters out players with status "absent"
- Includes players with status "benched" (available for planning)
- Maps roles to OGRH buckets using `MapRoleToOGRH()`
- Writes result to `OGRH_SV.v2.invites.planningRoster`
- Returns generated roster array

**Planning Roster Structure:**
```lua
{
  {name = "PlayerName", class = "WARRIOR", role = "TANKS"},
  {name = "PlayerName", class = "PRIEST", role = "HEALERS"},
  {name = "PlayerName", class = "ROGUE", role = "MELEE"},
  {name = "PlayerName", class = "MAGE", role = "RANGED"},
  -- ... etc
}
```

**Role Mapping:**
- **TANKS** - Tank, Feral Tank
- **HEALERS** - Healer, Resto Druid, Holy Priest, etc.
- **MELEE** - Melee DPS, Feral DPS, Rogue, Warrior DPS
- **RANGED** - Ranged DPS, Caster, Mage, Warlock, Hunter

**Example:**
```lua
-- Generate planning roster after import
local roster = OGRH.Invites.GeneratePlanningRoster()
print("Generated roster with " .. table.getn(roster) .. " players")
```

**Implementation Notes:**
- Called automatically after all import operations
- Clears existing planning roster before regenerating
- Uses SVM with MANUAL sync level (no auto-sync)
- Accessed by EncounterMgmt for assignment planning

---

#### `OGRH.Invites.GetPlanningRoster()`
**Type:** Public  
**Returns:** `table` - Cached planning roster array

Accessor for EncounterMgmt integration to retrieve current planning roster.

**Behavior:**
- Reads from `OGRH_SV.v2.invites.planningRoster`
- Returns cached roster (no regeneration)
- Returns empty table if no roster exists

**Example:**
```lua
-- Access planning roster for assignment
local roster = OGRH.Invites.GetPlanningRoster()
for _, player in ipairs(roster) do
    print(player.name .. " (" .. player.role .. ")")
end
```

**Use Cases:**
- EncounterMgmt auto-assignment
- Roster validation
- Planning UI display

---

#### `OGRH.Invites.ShowWindow()`
**Type:** Public  
**Returns:** `nil`

Opens the Raid Invites window with player roster and import controls.

**UI Elements:**
- **Import Roster** - Dropdown menu (RollFor, Raid-Helper Invites, Raid-Helper Groups)
- **Sort** - Toggle auto-organization (green=on, yellow=off, grey=no data)
- **Start Invite Mode** - Automated invite cycles
- **Clear Status** - Clears history, declined players, invite tracking
- **Player List** - Shows all roster players with status indicators

**Example:**
```lua
-- Open invites window
OGRH.Invites.ShowWindow()
```

---

#### `OGRH.Invites.AutoOrganizeNewMembers()`
**Type:** Public  
**Authorization:** Requires Raid Leader or Assistant  
**Returns:** `nil`

Automatically organizes new raid members into assigned groups based on Raid-Helper group data. Only runs when `autoSort` flag is enabled AND group data is available.

**Behavior:**
- Checks `autoSort` flag from schema
- Verifies group assignments data exists
- Skips if player in combat
- Moves player to assigned group
- Provides feedback on organization status

**Conditions:**
- ✅ Auto-sort enabled via Sort button
- ✅ Raid-Helper (Groups) data imported
- ✅ Player has group assignment
- ✅ Player not in combat
- ✅ User has RL/A permissions

**Example:**
```lua
-- Called when player joins raid during Invite Mode
OGRH.Invites.AutoOrganizeNewMembers()
```

**Implementation Notes:**
- Called from RAID_ROSTER_UPDATE event handler
- Silent operation (no chat spam)
- Skips gracefully if conditions not met

---

#### `OGRH.Invites.GetRosterPlayers()`
**Type:** Public  
**Returns:** `table` - Unified player roster array

Returns unified roster from current data source (RollFor or Raid-Helper).

**Player Object Structure:**
```lua
{
  name = "PlayerName",
  class = "WARRIOR",
  role = "Tank",           -- Source-specific role string
  status = "active",       -- "active", "benched", "absent"
  group = 1,              -- Group number (if assigned)
  realm = "Turtle WoW"    -- (optional)
}
```

**Example:**
```lua
local players = OGRH.Invites.GetRosterPlayers()
for _, player in ipairs(players) do
    print(player.name, player.role, player.status)
end
```

---

#### `OGRH.Invites.ToggleInviteMode()`
**Type:** Public  
**Authorization:** Requires Raid Leader or Assistant  
**Returns:** `nil`

Toggles automated invite cycle mode with guild announcements and auto-whisper responses.

**Behavior:**
- Starts/stops timer-based invite cycles
- Announces to guild on start (includes raid name)
- Announces each invite cycle to guild
- Auto-responds to whispers from roster players
- Auto-organizes new members (if Sort enabled)

**Guild Announcements:**
```
[Start] Now inviting for <Raid Name>! Whisper me for invite.
[Cycle] Inviting players for <Raid Name>...
```

**Auto-Whisper Responses:**
- **Active players** - Auto-invited
- **Benched players** - "You are on bench. Whisper again if available."
- **Absent players** - "You are marked absent."
- **Not on roster** - Source-specific message (RollFor: "Not on soft-res list", Raid-Helper: "Not on signup list")

**Example:**
```lua
-- Toggle invite mode
OGRH.Invites.ToggleInviteMode()
```

**Implementation Notes:**
- Interval configurable in Invite Mode panel
- Deduplicates auto-responses via history tracking
- Tracks "already in group" messages from CHAT_MSG_SYSTEM

---

### Public Properties

#### `OGRH.Invites.SOURCE_TYPE`
**Type:** Table (Constants)  
**Access:** Public Read-Only

Data source type constants.

**Values:**
- `ROLLFOR` - "rollfor" (RollFor soft-reserve import)
- `RAIDHELPER` - "raidhelper" (Raid-Helper JSON import)

**Example:**
```lua
-- Check current source
local source = OGRH.SVM.GetPath("invites.currentSource")
if source == OGRH.Invites.SOURCE_TYPE.ROLLFOR then
    print("Using RollFor data")
end
```

---

### Schema Structure (OGRH_SV.v2.invites)

```lua
OGRH_SV.v2.invites = {
    -- Data Source
    currentSource = "rollfor",  -- "rollfor" | "raidhelper"
    
    -- RollFor Data (Option A: Read-only from RollForCharDb)
    -- No local storage - reads directly from RollFor
    
    -- Raid-Helper Data
    raidhelperData = {
        id = "hash123",
        name = "Raid Title",
        players = {...}
    },
    
    raidhelperGroupsData = {
        groups = {...},
        groupAssignments = {...}
    },
    
    -- Invite Mode
    inviteMode = {
        enabled = false,
        interval = 60,
        lastInviteTime = 0,
        totalPlayers = 0,
        invitedCount = 0
    },
    
    -- Tracking
    declinedPlayers = {},
    history = {},  -- Cleared on new import
    
    -- v2 Invites Update (NEW)
    autoSort = false,        -- Enable/disable auto-group sorting
    planningRoster = {},     -- Array for EncounterMgmt integration
    
    -- UI
    invitePanelPosition = {...}
}
```

---

### Import Flow (v2 Update)

All three import sources follow the same pattern:

1. **Clear session data:**
   ```lua
   OGRH.SVM.SetPath("invites.history", {}, {syncLevel = "MANUAL"})
   OGRH.SVM.SetPath("invites.declinedPlayers", {}, {syncLevel = "MANUAL"})
   OGRH.SVM.SetPath("invites.planningRoster", {}, {syncLevel = "MANUAL"})
   ```

2. **Import data from source:**
   - **RollFor** - Read from `RollForCharDb.softres.data` (user imports to RollFor first via `/sr`)
   - **Raid-Helper (Invites)** - Parse JSON from signup export
   - **Raid-Helper (Groups)** - Parse JSON from Composition Tool export

3. **Set current source:**
   ```lua
   OGRH.SVM.SetPath("invites.currentSource", sourceType, {syncLevel = "MANUAL"})
   ```

4. **Generate planning roster:**
   ```lua
   OGRH.Invites.GeneratePlanningRoster()
   ```

5. **Refresh UI and update Sort button state**

---

### RollFor Integration (Option A: Read-Only)

**Workflow:**
1. User imports soft-res data into RollFor (via `/sr` command)
2. User clicks Import Roster → RollFor Soft-Res in OGRH
3. OGRH reads from `RollForCharDb.softres.data`
4. Data decoded using RollFor's public `SoftRes.decode()` function
5. Planning roster generated

**Why Read-Only?**
- RollFor v4.8.1 does not expose `import_encoded_softres_data` as a public API
- Direct write to `RollForCharDb` would bypass RollFor's validation
- Read-only approach is safest and most stable

**Data Access:**
```lua
-- OGRH reads from RollFor's SavedVariables
local encodedData = RollForCharDb.softres.data
local decodedData = RollFor.SoftRes.decode(encodedData)
local softresData = RollFor.SoftResDataTransformer.transform(decodedData)
```

---

### Common Issues

**Import not working:**
- Check current source: `/script print(OGRH.SVM.GetPath("invites.currentSource"))`
- RollFor: Ensure data imported to RollFor first (via `/sr`)
- Raid-Helper: Verify JSON format (paste full export)

**Sort button greyed out:**
- Requires Raid-Helper (Groups) import
- Group assignments must exist in imported data
- Check: `/script print(OGRH.SVM.GetPath("invites.raidhelperGroupsData.groupAssignments"))`

**Auto-sort not working:**
- Verify Sort button is green (enabled)
- Must use Raid-Helper (Groups) source
- Requires RL/A permissions
- Players in combat cannot be moved

**Planning roster empty:**
- Import data first (clears roster before regenerating)
- Check roster: `/script local r = OGRH.Invites.GetPlanningRoster(); print(table.getn(r))`
- Verify players not all marked "absent"

---

## MessageRouter Module (_Infrastructure/MessageRouter.lua)

The MessageRouter module provides centralized message routing and handling for all OGAddonMsg addon communication. It manages message registration, sending, receiving, deduplication, and permission checking.

### Public Functions

#### `OGRH.MessageRouter.RegisterHandler(messageType, handler)`
**Type:** Public  
**Returns:** `boolean` - True if registration succeeded

Registers a handler function for a specific message type. The handler will be called when messages of this type are received.

**Parameters:**
- `messageType` (string) - Full message type string (e.g., "OGRH_STRUCT_SET_ENCOUNTER")
- `handler` (function) - Function(sender, data, channel) to handle the message

**Behavior:**
- Validates message type against known types (warns if unknown)
- Stores handler in internal registry
- Replaces existing handler if messageType already registered

**Example:**
```lua
-- Register handler for structure updates
OGRH.MessageRouter.RegisterHandler("OGRH_STRUCT_SET_ENCOUNTER", function(sender, data, channel)
    -- Handle encounter structure update
    OGRH.ApplyEncounterUpdate(data)
end)
```

**Implementation Notes:**
- Handlers are stored in `OGRH.MessageRouter.State.handlers` table
- Message type validation uses `OGRH.IsValidMessageType()`

---

#### `OGRH.MessageRouter.UnregisterHandler(messageType)`
**Type:** Public  
**Returns:** `boolean` - True if unregistration succeeded

Removes a previously registered handler for a message type.

**Parameters:**
- `messageType` (string) - Message type to unregister

**Example:**
```lua
OGRH.MessageRouter.UnregisterHandler("OGRH_STRUCT_SET_ENCOUNTER")
```

---

#### `OGRH.MessageRouter.Send(messageType, data, options)`
**Type:** Public  
**Authorization:** Automatically checks permissions based on message category  
**Returns:** `messageId` (string) or `nil` - Message ID from OGAddonMsg, or nil on error

Sends a message via OGAddonMsg with automatic permission checking and serialization.

**Parameters:**
- `messageType` (string) - Message type from OGRH.MessageTypes
- `data` (table or string) - Data to send (tables auto-serialized by OGAddonMsg)
- `options` (table, optional) - Configuration options:
  - `priority` (string) - "ALERT", "NORMAL", or "BULK" (default: "NORMAL")
  - `target` (string) - Target player name for targeted messages
  - `channel` (string) - Specific channel ("RAID", "PARTY", "GUILD", etc.)
  - `onSuccess` (function) - Callback on successful send
  - `onFailure` (function) - Callback on send failure
  - `onComplete` (function) - Callback when send completes (regardless of success)

**Behavior:**
- Validates message type (warns if unknown)
- Checks permissions based on message category:
  - **STRUCT** messages: Requires admin permissions
  - **ASSIGN** messages: Requires admin permissions
  - **SYNC/ADMIN/STATE** messages: No restrictions (anyone can query)
- Auto-detects best channel if not specified
- Sends via OGAddonMsg with specified priority

**Permission Categories:**
- `STRUCT` - Structure changes (create/delete raids/encounters)
- `ASSIGN` - Assignment changes (roles, marks, icons)
- `SYNC` - Sync requests and responses
- `ADMIN` - Admin state queries
- `STATE` - General state queries

**Example:**
```lua
-- Send role assignment (REALTIME)
OGRH.MessageRouter.Send("OGRH_ASSIGN_ROLE", {
    raid = 1,
    encounter = 2,
    role = "tank1",
    player = "Tankadin"
}, {
    priority = "ALERT",
    onSuccess = function()
        OGRH.Msg("Role assignment synced")
    end
})

-- Send settings update (BATCH)
OGRH.MessageRouter.Send("OGRH_STRUCT_SET_ENCOUNTER", {
    raid = 1,
    encounter = 2,
    settings = {...}
}, {
    priority = "NORMAL"
})
```

**Implementation Notes:**
- Uses `OGAddonMsg.Send()` for actual transmission
- Prepends target to message type for targeted messages (e.g., "OGRH_SYNC_REQUEST@PlayerName")
- Returns nil if OGAddonMsg is unavailable

---

#### `OGRH.MessageRouter.SendTo(targetPlayer, messageType, data, options)`
**Type:** Public  
**Authorization:** Same as `Send()`  
**Returns:** `messageId` or `nil`

Sends a targeted message to a specific player. In WoW 1.12, this broadcasts to RAID with target prefix since WHISPER is not supported for addon messages in raids.

**Parameters:**
- `targetPlayer` (string) - Target player name
- `messageType` (string) - Message type
- `data` (table or string) - Message data
- `options` (table, optional) - Same as `Send()` (target and channel are auto-set)

**Behavior:**
- Prepends target to message type: `messageType@targetPlayer`
- Broadcasts to RAID channel
- Receiver filters messages by target suffix

**Example:**
```lua
-- Request sync data from specific player
OGRH.MessageRouter.SendTo("AdminPlayer", "OGRH_SYNC_REQUEST_COMPONENT", {
    raid = "MC",
    encounter = "Rag",
    component = "roles"
})
```

---

#### `OGRH.MessageRouter.Broadcast(messageType, data, options)`
**Type:** Public  
**Authorization:** Same as `Send()`  
**Returns:** `messageId` or `nil`

Broadcasts a message to all raid/party members using auto-detected best channel.

**Parameters:**
- `messageType` (string) - Message type
- `data` (table or string) - Message data
- `options` (table, optional) - Same as `Send()` (channel is auto-detected)

**Example:**
```lua
-- Broadcast checksum to all raid members
OGRH.MessageRouter.Broadcast("OGRH_SYNC_CHECKSUM_BROADCAST", {
    activeRaid = "abc123",
    assignments = "def456",
    roles = "ghi789"
})
```

---

### Public Properties

#### `OGRH.MessageRouter.State`
**Type:** Table  
**Access:** Public Read-Only (Internal Write)

State management for MessageRouter module.

**Fields:**
- `handlers` (table) - Registered message handlers (messageType -> function)
- `messageQueue` (table) - Outgoing message queue
- `receivedMessages` (table) - Recently received message IDs (for deduplication)
- `isInitialized` (boolean) - Module initialization status

---

### Private Functions

#### `OnMessageReceived(sender, messageType, data, channel)` (local)
**Type:** Private

Internal handler called by OGAddonMsg when messages are received.

**Behavior:**
- Filters targeted messages (only processes if local player is target)
- Deduplicates messages using message ID tracking
- Routes to registered handler for message type
- Logs errors if handler fails

---

#### `InitializeOGAddonMsg()` (local)
**Type:** Private

Registers OGAddonMsg listener and initializes message routing.

**Behavior:**
- Validates OGAddonMsg availability
- Registers `OnMessageReceived` callback
- Returns true on success

---

### Handler Architecture

**MessageRouter owns ALL handler registration** - modules provide handler functions but do not register them directly.

#### Design Pattern

```lua
-- ❌ INCORRECT: Module self-registers handlers
function OGRH.SVM.Initialize()
    OGRH.MessageRouter.RegisterHandler("OGRH_SYNC_DELTA", OGRH.SVM.OnDeltaReceived)
end

-- ✅ CORRECT: MessageRouter registers all handlers
function OGRH.MessageRouter.RegisterDefaultHandlers()
    -- SYNC.DELTA delegates to SVM
    self.RegisterHandler("OGRH_SYNC_DELTA", function(sender, data, channel)
        OGRH.SVM.OnDeltaReceived(sender, data, channel)
    end)
end
```

**Rationale:**
- Single source of truth for all handler registrations
- No duplicate/conflicting registrations
- No timing/load order dependencies
- Clear separation: MessageRouter = infrastructure, modules = business logic

---

### Message Type Categories

The MessageRouter recognizes the following message categories (prefix-based):

| Category | Prefix | Permission | Purpose |
|----------|--------|------------|---------|
| **STRUCT** | `OGRH_STRUCT_` | Admin only | Structure changes (CRUD operations) |
| **ASSIGN** | `OGRH_ASSIGN_` | Admin only | Player assignments (roles, marks) |
| **SYNC** | `OGRH_SYNC_` | Anyone | Sync requests and data transfers |
| **ADMIN** | `OGRH_ADMIN_` | Anyone | Admin state queries |
| **STATE** | `OGRH_STATE_` | Anyone | General state queries |

---

## SyncRouter Module (_Infrastructure/SyncRouter.lua)

The SyncRouter module provides context-aware sync level routing based on Active Raid status and UI context. It determines the appropriate sync level (REALTIME, BATCH, MANUAL) for data changes.

### Public Functions

#### `OGRH.SyncRouter.DetectContext(raidIdx)`
**Type:** Public  
**Returns:** `string` - Context identifier: "active_mgmt", "active_setup", or "nonactive_setup"

Determines the current operational context based on raid index and open UI windows.

**Parameters:**
- `raidIdx` (number) - Raid index (1 = Active Raid)

**Behavior:**
- Checks if raid is Active Raid (index 1)
- Detects open UI: EncounterSetup vs EncounterMgmt
- Returns context string based on state

**Context Types:**
- `active_mgmt` - Active Raid + EncounterMgmt open → REALTIME sync
- `active_setup` - Active Raid + EncounterSetup open → BATCH sync
- `nonactive_setup` - Non-Active Raid → BATCH sync

**Example:**
```lua
local context = OGRH.SyncRouter.DetectContext(1)
if context == "active_mgmt" then
    -- Live execution mode, use REALTIME sync
end
```

---

#### `OGRH.SyncRouter.DetermineSyncLevel(raidIdx, componentType, changeType)`
**Type:** Public  
**Returns:** `string` - Sync level: "REALTIME", "BATCH", or "MANUAL"

Determines the appropriate sync level for a change based on context and component type.

**Parameters:**
- `raidIdx` (number) - Raid index
- `componentType` (string) - Component being changed ("roles", "assignments", "settings", "structure", etc.)
- `changeType` (string, optional) - Type of change

**Behavior:**
- Structure changes (CRUD) → Always "MANUAL"
- Active Raid + EncounterMgmt + assignments → "REALTIME"
- Active Raid + EncounterMgmt + settings → "BATCH"
- All other contexts → "BATCH"

**Sync Level Decision Matrix:**

| Context | Component Type | Sync Level |
|---------|---------------|------------|
| Any | `structure` | MANUAL |
| `active_mgmt` | `roles`, `assignments`, `marks`, `numbers` | REALTIME |
| `active_mgmt` | `settings`, `metadata` | BATCH |
| `active_setup` | Any | BATCH |
| `nonactive_setup` | Any | BATCH |

**Example:**
```lua
-- Determine sync level for role assignment
local syncLevel = OGRH.SyncRouter.DetermineSyncLevel(1, "roles", "update")
-- Returns "REALTIME" if in active_mgmt context
```

---

#### `OGRH.SyncRouter.ExtractScope(raidIdx, encounterIdx, componentType)`
**Type:** Public  
**Returns:** `table` - Scope information: `{type, raid, raidIdx, encounter, encounterIdx, component}`

Extracts scope metadata from raid/encounter indices.

**Parameters:**
- `raidIdx` (number) - Raid index
- `encounterIdx` (number, optional) - Encounter index
- `componentType` (string) - Component type

**Example:**
```lua
local scope = OGRH.SyncRouter.ExtractScope(1, 2, "roles")
-- Returns: {type = "encounter", raid = "MC", raidIdx = 1, encounter = "Rag", encounterIdx = 2, component = "roles"}
```

---

#### `OGRH.SyncRouter.Route(path, value, changeType)`
**Type:** Public  
**Returns:** `table` - Sync metadata: `{syncLevel, componentType, scope, changeType}`

Main routing function that determines sync metadata for a data change. Called by SavedVariablesManager on writes.

**Parameters:**
- `path` (string) - Dot-separated path to data (e.g., "encounterMgmt.raids.1.encounters.2.roles")
- `value` (any) - New value being written
- `changeType` (string, optional) - Type of change

**Behavior:**
- Parses path to extract raid/encounter indices and component type
- Calls `DetermineSyncLevel()` to get sync level
- Calls `ExtractScope()` to get scope metadata
- Returns complete sync metadata table

**Example:**
```lua
local syncMetadata = OGRH.SyncRouter.Route("encounterMgmt.raids.1.encounters.2.roles", {...}, "update")
-- Returns: {syncLevel = "REALTIME", componentType = "roles", scope = {...}, changeType = "update"}
```

**Implementation Notes:**
- Integrates with SavedVariablesManager automatic sync triggering
- Path parsing handles both v1 and v2 schema formats

---

#### `OGRH.SyncRouter.ParsePath(path)`
**Type:** Public  
**Returns:** `raidIdx, encounterIdx, componentType` - Parsed path components

Parses a dot-separated path to extract numeric indices and component type.

**Parameters:**
- `path` (string) - Path to parse

**Example:**
```lua
local raidIdx, encounterIdx, componentType = OGRH.SyncRouter.ParsePath("encounterMgmt.raids.1.encounters.2.roles")
-- Returns: 1, 2, "roles"
```

---

#### `OGRH.SyncRouter.IsActiveRaid(raidIdx)`
**Type:** Public  
**Returns:** `boolean` - True if raid index is the Active Raid

Checks if given raid index is the Active Raid (always index 1 in v2 schema).

**Parameters:**
- `raidIdx` (number) - Raid index to check

**Example:**
```lua
if OGRH.SyncRouter.IsActiveRaid(raidIdx) then
    -- This is the Active Raid
end
```

---

### Public Properties

#### `OGRH.SyncRouter.State`
**Type:** Table  
**Access:** Public Read/Write

State management for SyncRouter module.

**Fields:**
- `currentContext` (string) - Current context: "unknown", "active_mgmt", "active_setup", "nonactive_setup"
- `activeRaidIdx` (number) - Active Raid index (always 1)

---

## SyncIntegrity Module (_Infrastructure/SyncIntegrity.lua)

The SyncIntegrity module provides checksum verification and automatic repair for Active Raid data. It implements a polling system where the admin broadcasts checksums every 30 seconds, and clients auto-repair on mismatches.

### Public Functions

#### `OGRH.SyncIntegrity.BroadcastChecksums()`
**Type:** Public  
**Authorization:** Admin only (auto-checked)  
**Returns:** `nil`

Broadcasts Active Raid checksums to all raid members. Called automatically every 30 seconds by polling timer.

**Behavior:**
- Only runs if player is raid admin
- Skips if in combat, offline, or made recent changes
- Skips if network queue is busy (prevents traffic storms)
- Computes checksums for:
  - Active Raid structure (all encounters, excluding assignments)
  - Active Encounter assignments (current encounter only)
  - RolesUI (global role buckets)
- Broadcasts via MessageRouter with LOW priority

**Checksum Types:**
- `activeRaidStructure` - Structure checksum (roles, columns, but NO assignments)
- `activeAssignments` - Current encounter assignments only
- `rolesUI` - Global TANKS/HEALERS/MELEE/RANGED buckets

**Note:** Global components (consumes, tradeItems) are NOT part of automated sync. Use SyncGranular for manual sync of these components.

**Example:**
```lua
-- Called automatically by polling timer
OGRH.SyncIntegrity.BroadcastChecksums()
```

**Implementation Notes:**
- Respects modification cooldown (2 seconds after admin's last change)
- Uses `OGRH.SyncChecksum.ComputeRaidChecksum()` for structure
- Uses `OGRH.SyncChecksum.ComputeActiveAssignmentsChecksum()` for assignments

---

#### `OGRH.SyncIntegrity.OnChecksumBroadcast(sender, checksums)`
**Type:** Public (called by MessageRouter)  
**Returns:** `nil`

Client handler for checksum broadcasts from admin. Compares local checksums to admin's and triggers repair if mismatched.

**Parameters:**
- `sender` (string) - Player name of sender (must be current admin)
- `checksums` (table) - Checksum values: `{activeRaidStructure, activeAssignments, rolesUI}`

**Behavior:**
- Verifies sender is current raid admin
- Computes local checksums for comparison
- Detects mismatches and queues repair requests
- Broadcasts repair request to admin (buffered for 1 second)

**Mismatch Types:**
- `ACTIVE_RAID_STRUCTURE` - Structure mismatch (roles, columns)
- `ACTIVE_ASSIGNMENTS` - Assignment mismatch (current encounter)
- `ROLES_UI` - Global role bucket mismatch

**Example:**
```lua
-- Called automatically when OGRH_SYNC_CHECKSUM_BROADCAST received
OGRH.SyncIntegrity.OnChecksumBroadcast("AdminPlayer", {
    activeRaidStructure = "abc123",
    activeAssignments = "def456",
    rolesUI = "ghi789"
})
```

---

#### `OGRH.SyncIntegrity.RecordAdminModification()`
**Type:** Public (called by SVM)  
**Returns:** `nil`

Records timestamp of admin's last modification to delay checksum broadcasts. Prevents broadcasting while admin is actively editing.

**Called automatically by SVM when:**
1. Change is to Active Raid (`scope.isActiveRaid == true`)
2. Local player is Raid Admin (`OGRH.IsRaidAdmin()`)

**Behavior:**
- Updates `lastAdminModification` timestamp
- Prevents broadcasts until cooldown expires (2 seconds default)
- Only fires for Active Raid changes made by local admin

**Example:**
```lua
-- SVM calls this automatically for Active Raid admin edits
-- You typically don't call this directly
OGRH.SyncIntegrity.RecordAdminModification()
```

**Implementation Notes:**
- Called by `SVM.SyncRealtime()` for Active Raid REALTIME syncs
- Called by `SVM.InvalidateChecksum()` for Active Raid checksum invalidations
- Only fires if both conditions met (Active Raid AND local admin)
- Cooldown duration: 2 seconds (configurable via `modificationCooldown`)
- Prevents "flapping" during rapid UI changes

**Rationale:**
- **Active Raid only**: Non-Active Raids don't have checksum polling
- **Admin only**: Non-admins don't broadcast checksums (they send SYNC.DELTA)
- Prevents unnecessary delays for irrelevant changes

---

#### `OGRH.SyncIntegrity.StartIntegrityChecks()`
**Type:** Public  
**Returns:** `nil`

Starts the integrity check polling timer (admin only). Broadcasts checksums every 30 seconds.

**Behavior:**
- Creates repeating timer (30-second interval)
- Only runs if player is raid admin
- Automatically stops when admin status lost

**Example:**
```lua
-- Called automatically when player becomes raid admin
OGRH.SyncIntegrity.StartIntegrityChecks()
```

---

### Public Properties

#### `OGRH.SyncIntegrity.State`
**Type:** Table  
**Access:** Public Read/Write

State management for SyncIntegrity module.

**Fields:**
- `lastChecksumBroadcast` (number) - Timestamp of last broadcast
- `verificationInterval` (number) - Seconds between broadcasts (default: 30)
- `checksumCache` (table) - Cached checksum values
- `pollingTimer` (timer) - Active polling timer reference
- `enabled` (boolean) - Module enabled state
- `lastAdminModification` (number) - Timestamp of last admin change
- `modificationCooldown` (number) - Seconds to wait after change (default: 2)
- `debug` (boolean) - Debug mode (toggle with `/ogrh debug sync`)

---

### Private Functions

#### `OnRepairRequest(sender, data)` (local)
**Type:** Private

Admin handler for client repair requests. Buffers requests for 1 second to prevent broadcast storms.

**Behavior:**
- Validates sender is in raid
- Adds request to repair buffer
- Schedules flush after 1 second (or uses existing timer)
- Broadcasts repair data once per component

---

#### `FlushRepairBuffer()` (local)
**Type:** Private

Flushes repair buffer and broadcasts repair data to requesting clients.

**Behavior:**
- Deduplicates requests (one repair per component)
- Calls appropriate repair broadcast function
- Clears buffer after flush

---

#### `BroadcastActiveRaidRepair()` (local)
**Type:** Private

Admin broadcasts Active Raid structure data for repair.

---

#### `BroadcastAssignmentsRepair(encounterIdx)` (local)
**Type:** Private

Admin broadcasts Active Encounter assignments for repair.

---

#### `BroadcastRolesRepair()` (local)
**Type:** Private

Admin broadcasts RolesUI data for repair.

---

#### `BroadcastGlobalRepair()` (local)
**Type:** Private

Admin broadcasts global components for repair.

---

#### `OnActiveRaidRepair(sender, data)` (local)
**Type:** Private

Client receives and applies Active Raid structure repair.

---

#### `OnAssignmentsRepair(sender, data)` (local)
**Type:** Private

Client receives and applies assignments repair.

---

#### `OnRolesRepair(sender, data)` (local)
**Type:** Private

Client receives and applies RolesUI repair.

---

#### `OnGlobalRepair(sender, data)` (local)
**Type:** Private

Client receives and applies global components repair.

---

## SyncGranular Module (_Infrastructure/SyncGranular.lua)

The SyncGranular module provides surgical data repair at component, encounter, and raid levels. It implements priority-based sync queuing and manual repair requests.

### Public Functions

#### `OGRH.SyncGranular.SetContext(raidName, encounterName)`
**Type:** Public  
**Returns:** `nil`

Sets the current UI context for priority calculation. Called automatically when user changes raid/encounter selection.

**Parameters:**
- `raidName` (string) - Currently selected raid name
- `encounterName` (string) - Currently selected encounter name

**Behavior:**
- Updates `currentRaid` and `currentEncounter` state
- Affects priority of subsequent sync operations
- Higher priority for current raid/encounter

**Example:**
```lua
-- Called when user selects encounter
OGRH.SyncGranular.SetContext("MC", "Rag")
```

---

#### `OGRH.SyncGranular.RequestComponentSync(raidName, encounterName, componentName, encounterPosition)`
**Type:** Public  
**Returns:** `nil`

Requests sync of a specific component (e.g., "roles", "assignments") from admin/officer.

**Parameters:**
- `raidName` (string) - Raid name
- `encounterName` (string) - Encounter name
- `componentName` (string) - Component to sync ("roles", "assignments", "marks", "numbers", "consumes", "bigwigs")
- `encounterPosition` (number, optional) - Encounter position in raid

**Behavior:**
- Broadcasts sync request to raid
- Queues with automatic priority (based on current context)
- Admin/officer responds with component data
- Client applies data when received

**Example:**
```lua
-- Request roles for specific encounter
OGRH.SyncGranular.RequestComponentSync("MC", "Rag", "roles", 5)
```

---

#### `OGRH.SyncGranular.RequestEncounterSync(raidName, encounterName)`
**Type:** Public  
**Returns:** `nil`

Requests sync of all components for a specific encounter.

**Parameters:**
- `raidName` (string) - Raid name
- `encounterName` (string) - Encounter name

**Behavior:**
- Syncs all 6 components: roles, assignments, marks, numbers, consumes, bigwigs
- Queues with priority based on context
- More efficient than requesting each component individually

**Example:**
```lua
-- Request full encounter sync
OGRH.SyncGranular.RequestEncounterSync("MC", "Rag")
```

---

#### `OGRH.SyncGranular.RequestRaidSync(raidName)`
**Type:** Public  
**Returns:** `nil`

Requests sync of entire raid (metadata + all encounters).

**Parameters:**
- `raidName` (string) - Raid name

**Behavior:**
- Syncs raid metadata (advancedSettings, displayName, etc.)
- Syncs all encounters in raid
- Highest-impact sync operation

**Example:**
```lua
-- Request full raid sync
OGRH.SyncGranular.RequestRaidSync("MC")
```

---

#### `OGRH.SyncGranular.RequestGlobalComponentSync(componentName)`
**Type:** Public  
**Returns:** `nil`

Requests sync of global components (consumes, tradeItems, etc.).

**Parameters:**
- `componentName` (string) - Component to sync ("consumes", "tradeItems")

**Example:**
```lua
-- Request consumes sync
OGRH.SyncGranular.RequestGlobalComponentSync("consumes")
```

---

#### `OGRH.SyncGranular.RequestRaidMetadataSync(raidName, targetPlayer)`
**Type:** Public  
**Returns:** `nil`

Requests sync of raid metadata only (advancedSettings, no encounters).

**Parameters:**
- `raidName` (string) - Raid name
- `targetPlayer` (string, optional) - Specific player to request from

**Example:**
```lua
-- Request metadata sync
OGRH.SyncGranular.RequestRaidMetadataSync("MC")
```

---

#### `OGRH.SyncGranular.QueueRepair(validationResult, targetPlayer)`
**Type:** Public (called by validation system)  
**Returns:** `nil`

Queues a repair operation based on validation failure. Automatically determines sync scope and priority.

**Parameters:**
- `validationResult` (table) - Validation result from integrity check
- `targetPlayer` (string, optional) - Player to request repair from

**Behavior:**
- Determines repair scope (component, encounter, or raid)
- Calculates priority based on current UI context
- Queues repair operation
- Processes queue automatically

---

### Public Properties

#### `OGRH.SyncGranular.State`
**Type:** Table  
**Access:** Public Read/Write

State management for SyncGranular module.

**Fields:**
- `syncQueue` (table) - Queued sync operations (prioritized)
- `activeSyncs` (table) - Currently executing syncs
- `currentRaid` (string) - Currently selected raid in UI
- `currentEncounter` (string) - Currently selected encounter in UI
- `maxConcurrentSyncs` (number) - Max parallel syncs (default: 1)
- `enabled` (boolean) - Module enabled state

---

### Priority Levels

Sync operations are prioritized based on user's current UI context:

| Priority | Use For | Value |
|----------|---------|-------|
| **CRITICAL** | Current raid/encounter (user actively working on it) | 1 |
| **HIGH** | Other encounters in same raid (likely relevant) | 2 |
| **NORMAL** | Other raids (fix when convenient) | 3 |
| **LOW** | Background/deferred syncs | 4 |

**Priority Calculation:**
- If syncing current raid + encounter → CRITICAL
- If syncing current raid (different encounter) → HIGH
- If syncing different raid → NORMAL
- Manual low-priority requests → LOW

---

## SyncChecksum Module (_Infrastructure/SyncChecksum.lua)

The SyncChecksum module provides centralized checksum computation, serialization, and deep copy utilities. All checksum operations are consolidated here to prevent code duplication.

### Public Functions

#### `OGRH.SyncChecksum.HashString(str)`
**Type:** Public  
**Returns:** `string` - Numeric hash as string

Computes a numeric hash for a string using simple additive algorithm.

**Parameters:**
- `str` (string) - String to hash

**Example:**
```lua
local hash = OGRH.SyncChecksum.HashString("Molten Core")
-- Returns: "12345" (numeric hash as string)
```

**Implementation Notes:**
- Uses sum of character codes with simple multiplier
- Not cryptographic, designed for change detection
- Consistent results for same input

---

#### `OGRH.SyncChecksum.HashRole(role, columnMultiplier, roleIndex)`
**Type:** Public  
**Returns:** `number` - Computed hash value

Computes hash for a role structure including all slots and assignments.

**Parameters:**
- `role` (table) - Role data structure
- `columnMultiplier` (number) - Column multiplier for hash calculation
- `roleIndex` (number) - Index of role in encounter

**Behavior:**
- Hashes role metadata (name, color, column)
- Hashes all slot assignments
- Includes position information in hash

**Example:**
```lua
local hash = OGRH.SyncChecksum.HashRole(roleData, 1000, 1)
```

---

#### `OGRH.SyncChecksum.Serialize(tbl)`
**Type:** Public  
**Returns:** `string` - Serialized representation

Serializes a Lua table to string using OGAddonMsg serialization.

**Parameters:**
- `tbl` (table) - Table to serialize

**Behavior:**
- Uses OGAddonMsg.TableToString() for compression
- Falls back to simple serialization if OGAddonMsg unavailable
- Handles nested tables, circular references

**Example:**
```lua
local serialized = OGRH.SyncChecksum.Serialize({name = "MC", encounters = {...}})
```

**Implementation Notes:**
- Requires OGAddonMsg for optimal compression
- Throws error if OGAddonMsg missing (critical dependency)

---

#### `OGRH.SyncChecksum.Deserialize(str)`
**Type:** Public  
**Returns:** `table` or `nil` - Deserialized table, or nil on error

Deserializes a string back to Lua table.

**Parameters:**
- `str` (string) - Serialized string

**Example:**
```lua
local tbl = OGRH.SyncChecksum.Deserialize(serializedData)
```

---

#### `OGRH.SyncChecksum.DeepCopy(original, seen)`
**Type:** Public  
**Returns:** `table` - Deep copy of original

Creates a deep copy of a table, handling nested tables and circular references.

**Parameters:**
- `original` (table) - Table to copy
- `seen` (table, optional) - Internal tracking for circular references

**Example:**
```lua
local copy = OGRH.SyncChecksum.DeepCopy(originalData)
-- Modifying copy won't affect original
```

---

#### `OGRH.SyncChecksum.CalculateStructureChecksum(raid, encounter)`
**Type:** Public  
**Returns:** `string` - Checksum value

Calculates checksum for encounter structure (excludes assignments).

**Parameters:**
- `raid` (string) - Raid name
- `encounter` (string) - Encounter name

**Behavior:**
- Hashes role definitions (names, colors, columns)
- Excludes slot assignments (assignments handled separately)
- Consistent hash for same structure

**Example:**
```lua
local checksum = OGRH.SyncChecksum.CalculateStructureChecksum("MC", "Rag")
```

---

#### `OGRH.SyncChecksum.CalculateAllStructureChecksum()`
**Type:** Public  
**Returns:** `string` - Global structure checksum

Calculates checksum for all raids and encounters in SavedVariables.

**Behavior:**
- Iterates all raids and encounters
- Combines individual checksums
- Used for full-database integrity checks

**Example:**
```lua
local globalChecksum = OGRH.SyncChecksum.CalculateAllStructureChecksum()
```

---

#### `OGRH.SyncChecksum.ComputeRaidChecksum(raidName)`
**Type:** Public  
**Returns:** `string` - Structure checksum (excludes assignments)

Computes checksum for Active Raid structure (v2 schema).

**Parameters:**
- `raidName` (string) - Raid name (unused in v2, uses index 1)

**Behavior:**
- Extracts Active Raid structure (roles, columns)
- Excludes all slot assignments
- Serializes and hashes structure

**Example:**
```lua
local checksum = OGRH.SyncChecksum.ComputeRaidChecksum("MC")
```

---

#### `OGRH.SyncChecksum.ComputeActiveAssignmentsChecksum(encounterIdx)`
**Type:** Public  
**Returns:** `string` - Assignments-only checksum

Computes checksum for Active Encounter assignments only.

**Parameters:**
- `encounterIdx` (number) - Encounter index

**Behavior:**
- Extracts slot assignments for specified encounter
- Excludes structure (roles, columns)
- Serializes and hashes assignments

**Example:**
```lua
local checksum = OGRH.SyncChecksum.ComputeActiveAssignmentsChecksum(2)
```

---

#### `OGRH.SyncChecksum.CalculateRolesUIChecksum()`
**Type:** Public  
**Returns:** `string` - RolesUI checksum

Calculates checksum for global role buckets (TANKS, HEALERS, MELEE, RANGED).

**Behavior:**
- Hashes global role assignments
- Used for RolesUI integrity checks

**Example:**
```lua
local checksum = OGRH.SyncChecksum.CalculateRolesUIChecksum()
```

---

#### `OGRH.SyncChecksum.GetGlobalComponentChecksums()`
**Type:** Public  
**Returns:** `table` - Table of component checksums `{consumes="...", tradeItems="..."}`

Calculates checksums for all global components.

**Example:**
```lua
local checksums = OGRH.SyncChecksum.GetGlobalComponentChecksums()
-- Returns: {consumes = "abc123", tradeItems = "def456"}
```

---

#### `OGRH.SyncChecksum.MarkEncounterDirty(raidIdx, encounterIdx)`
**Type:** Public  
**Returns:** `nil`

Marks encounter as dirty (checksum invalidated). Currently a no-op, reserved for future dirty tracking.

**Parameters:**
- `raidIdx` (number) - Raid index
- `encounterIdx` (number) - Encounter index

---

#### `OGRH.SyncChecksum.MarkRaidDirty(raidIdx)`
**Type:** Public  
**Returns:** `nil`

Marks raid as dirty (checksum invalidated). Currently a no-op, reserved for future dirty tracking.

**Parameters:**
- `raidIdx` (number) - Raid index

---

#### `OGRH.SyncChecksum.MarkComponentDirty(componentType)`
**Type:** Public  
**Returns:** `nil`

Marks component as dirty (checksum invalidated). Currently a no-op, reserved for future dirty tracking.

**Parameters:**
- `componentType` (string) - Component type

---

### Backward Compatibility Wrappers

The following functions are backward compatibility wrappers for legacy code. They delegate to `OGRH.SyncChecksum.*` functions:

- `OGRH.HashString()` → `OGRH.SyncChecksum.HashString()`
- `OGRH.HashRole()` → `OGRH.SyncChecksum.HashRole()`
- `OGRH.CalculateStructureChecksum()` → `OGRH.SyncChecksum.CalculateStructureChecksum()`
- `OGRH.CalculateAllStructureChecksum()` → `OGRH.SyncChecksum.CalculateAllStructureChecksum()`
- `OGRH.CalculateRolesUIChecksum()` → `OGRH.SyncChecksum.CalculateRolesUIChecksum()`
- `OGRH.ComputeRaidChecksum()` → `OGRH.SyncChecksum.ComputeRaidChecksum()`
- `OGRH.ComputeActiveAssignmentsChecksum()` → `OGRH.SyncChecksum.ComputeActiveAssignmentsChecksum()`
- `OGRH.GetGlobalComponentChecksums()` → `OGRH.SyncChecksum.GetGlobalComponentChecksums()`
- `OGRH.Serialize()` → `OGRH.SyncChecksum.Serialize()`
- `OGRH.Deserialize()` → `OGRH.SyncChecksum.Deserialize()`
- `OGRH.DeepCopy()` → `OGRH.SyncChecksum.DeepCopy()`

**Debug Mode:**
Set `OGRH_CHECKSUM_DEBUG = true` to log all wrapper calls (useful for tracking migration from legacy calls to new namespace).

---

## Permissions Module (_Infrastructure/Permissions.lua)

The Permissions module provides a three-tier permission system for controlling access to raid management functions.

### Permission Levels

| Level | Name | WoW Rank | Access |
|-------|------|----------|--------|
| **ADMIN** | Raid Admin | Designated admin | Full control (structure + assignments) |
| **OFFICER** | Raid Leader/Assistant | Rank >= 1 | Assignment control only |
| **MEMBER** | Member | Rank 0 | Read-only |

### Public Functions

#### `OGRH.GetPermissionLevel(playerName)`
**Type:** Public  
**Returns:** `string` - "ADMIN", "OFFICER", or "MEMBER"

Determines the permission level for a player.

**Parameters:**
- `playerName` (string, optional) - Player name to check. Defaults to local player if nil.

**Logic:**
1. Check if player is designated Raid Admin → "ADMIN"
2. Check if player is Raid Leader or Assistant → "OFFICER"
3. Otherwise → "MEMBER"

**Example:**
```lua
local level = OGRH.GetPermissionLevel("PlayerName")
if level == "ADMIN" then
    -- Full access
elseif level == "OFFICER" then
    -- Assignment access
else
    -- Read-only
end
```

---

#### `OGRH.CanModifyStructure(playerName)`
**Type:** Public  
**Returns:** `boolean` - True if player can modify raid/encounter structure

Checks if a player can create/delete raids or encounters, modify metadata, etc.

**Parameters:**
- `playerName` (string, optional) - Player name to check. Defaults to local player if nil.

**Authorization:**
- **ADMIN only** - Only designated Raid Admin can modify structure

**Example:**
```lua
if OGRH.CanModifyStructure(UnitName("player")) then
    -- Allow creating/deleting raids
    OGRH.CreateNewRaid(raidName)
else
    OGRH.Msg("|cffff0000[OGRH]|r You don't have permission to modify raid structure")
end
```

---

#### `OGRH.CanModifyAssignments(playerName)`
**Type:** Public  
**Returns:** `boolean` - True if player can modify player assignments

Checks if a player can assign players to roles, set marks/numbers, etc.

**Parameters:**
- `playerName` (string, optional) - Player name to check. Defaults to local player if nil.

**Authorization:**
- **ADMIN or OFFICER** - Raid Admin OR Raid Leader/Assistant can modify assignments

**Example:**
```lua
if OGRH.CanModifyAssignments(sender) then
    -- Allow assignment change
    OGRH.SVM.SetPath(path, playerName, {syncLevel = "NONE"})
else
    OGRH.Msg("|cffff0000[OGRH]|r Unauthorized assignment change from " .. sender)
end
```

---

#### `OGRH.IsRaidOfficer(playerName)`
**Type:** Public  
**Returns:** `boolean` - True if player is Raid Leader or Assistant

Checks if a player has Raid Leader or Raid Assistant status.

**Parameters:**
- `playerName` (string, optional) - Player name to check. Defaults to local player if nil.

**Implementation:**
- Scans raid roster for player
- Checks if `rank >= 1` (1 = Assistant, 2 = Leader)

**Example:**
```lua
if OGRH.IsRaidOfficer(UnitName("player")) then
    -- Player is RL or RA
end
```

---

#### `OGRH.IsRaidAdmin(playerName)`
**Type:** Public  
**Returns:** `boolean` - True if player is designated Raid Admin

Checks if a player is the designated Raid Admin (controls sync, structure, all permissions).

**Parameters:**
- `playerName` (string, optional) - Player name to check. Defaults to local player if nil.

**Implementation:**
- Reads `OGRH_SV.v2.permissions.currentAdmin`
- Compares to provided player name

**Example:**
```lua
if OGRH.IsRaidAdmin(UnitName("player")) then
    -- Start checksum broadcasting
    OGRH.SyncIntegrity.StartIntegrityChecks()
end
```

---

### Permission Enforcement

Permissions are enforced at **two layers**:

**Layer 1: UI (User Feedback)**
- Located in UI modules (EncounterMgmt, RolesUI, etc.)
- Disables buttons, shows error messages
- Provides immediate feedback to user
- Example: `EncounterMgmt.CanEditAssignments()`

**Layer 2: SVM (Security)**
- Located in SavedVariablesManager
- Validates permission before broadcasting changes
- Validates permission before applying received changes
- Prevents circumvention of UI restrictions
- Example: `SVM.SyncRealtime()` checks permissions before broadcast
- Example: `SVM.OnDeltaReceived()` checks sender permissions before applying

### Active Raid vs Non-Active Raids

**Active Raid (index 1):**
- Permission checks enforced
- Structure: Admin only
- Assignments: Admin/Leader/Assistant
- Requires `isActiveRaid = true` in sync metadata

**Non-Active Raids (index != 1):**
- No permission checks
- Anyone can edit (planning mode)
- Used for preparing future raids
- Set `isActiveRaid = false` or omit

---

## Sync System Overview

The sync system consists of four integrated modules that work together to maintain data consistency across raid members:

### Architecture Flow

```
1. User makes change → SavedVariablesManager
2. SVM calls SyncRouter.Route() → Determines sync level
3. SVM applies change and triggers sync based on level:
   - REALTIME → Immediate broadcast via MessageRouter
   - BATCH → Queue for 2-second batch send
   - MANUAL → No auto-sync (admin must push manually)
4. Admin broadcasts checksums every 30s → SyncIntegrity
5. Clients compare checksums → Auto-repair on mismatch
6. Manual repairs → SyncGranular (component/encounter/raid level)
```

### Sync Levels

| Level | Use Case | Timing | Priority |
|-------|----------|--------|----------|
| **REALTIME** | Combat-critical assignments | Instant | ALERT |
| **BATCH** | Bulk edits, settings | 2-second delay | NORMAL |
| **MANUAL** | Structure changes (CRUD) | Admin push only | N/A |
| **GRANULAR** | Surgical repairs | On-demand | Varies |

### Data Integrity System

**Active Polling (SyncIntegrity):**
- Admin broadcasts checksums every 30 seconds
- Covers: Active Raid structure, current encounter assignments, global roles, global components
- Clients auto-repair on mismatch (1-second buffer prevents storms)

**Manual Repair (SyncGranular):**
- Component-level: Single component (roles, assignments, etc.)
- Encounter-level: All 6 components for one encounter
- Raid-level: Full raid metadata + all encounters
- Global-level: Consumes, tradeItems, etc.

### Checksum Types (SyncChecksum)

| Type | Covers | Excludes | Use Case |
|------|--------|----------|----------|
| **Structure** | Roles, columns, metadata | Assignments | Detect structure changes |
| **Assignments** | Slot assignments | Structure | Detect assignment changes |
| **RolesUI** | Global role buckets | Everything else | Detect global role changes |
| **Global** | Consumes, tradeItems | Raid data | Detect global component changes |

---

## Future Additions

This document will be expanded to include:
- **Core Module** - SavedVariablesManager, schema routing, data persistence
- **EncounterMgmt Module** - Encounter planning, role management, raid configuration
- **Consume Module** - Consume checking, monitoring, logging
- **Admin Module** - Raid admin management, permissions, polling
- **Poll Module** - Role polling system, ready checks, response tracking

---

*Last Updated: February 3, 2026*
