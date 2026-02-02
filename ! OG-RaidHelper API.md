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

## Future Additions

This document will be expanded to include:
- **Core Module** - SavedVariablesManager, schema routing, data persistence
- **EncounterMgmt Module** - Encounter planning, role management, raid configuration
- **Sync Module** - Realtime synchronization, version control, conflict resolution
- **Consume Module** - Consume checking, monitoring, logging
- **Admin Module** - Raid admin management, permissions, polling
- **Poll Module** - Role polling system, ready checks, response tracking

---

*Last Updated: February 2, 2026*
