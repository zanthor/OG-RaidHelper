# OG-RaidHelper Changelog

## Version 1.25.3 - Encounter Auto-Assign Improvements  
**Release Date:** December 11, 2025

### Encounter Planning - Auto-Assign Enhancements
- **Allow Other Roles**: Players assigned to roles with `allowOtherRoles` can now be considered for subsequent role assignments
  - In 2-pass mode: Players from `allowOtherRoles` roles are immediately available for other roles in the same pass
  - In 3-pass mode: All players blocked in passes 1-2, then reusable in pass 3 regardless of `allowOtherRoles`
- **Smart assignment distribution**: System always prioritizes players with fewer existing assignments to distribute load evenly
- **Invert Fill Order**: Auto-assign now respects `invertFillOrder` flag, filling class priority slots bottom-up when enabled
- **3-Pass Mode**: When BOTH `invertFillOrder` AND `allowOtherRoles` are enabled:
  - Pass 1: Default roles top-down (no duplicates)
  - Pass 2: Class priority bottom-up (no duplicates)
  - Pass 3: Default roles top-down (allow duplicates to fill remaining empty slots, reusing players from pass 1)
- **Assignment protection**: Players from roles WITHOUT `allowOtherRoles` are never reused in other roles

### Technical Changes
- Added `GetAssignmentCount()` helper to track player assignment frequency
- Enhanced `AutoAssignRollForSlot()` with `defaultRolesOnly`, `allowDuplicates`, and `isThreePassMode` parameters
- Player candidate lists always sorted by assignment count (ascending) to ensure fair distribution
- Separate tracking: `assignedPlayers` (permanent) vs `tempAssignedPlayers` (temporary)
- Pass 3 filtering: Only considers players with existing assignments (count > 0) to consolidate reuse
- 2-pass vs 3-pass mode logic properly distinguishes when to respect `allowOtherRoles` for immediate reuse

## Version 1.25.2 - Auto-Sort Bug Fixes
**Release Date:** December 11, 2025

### Bug Fixes
- **Fixed endless loop in auto-sort timer**: Removed continuous polling timer that was causing infinite recursion
- **Redesigned auto-sort execution**: Timer now only runs during active sort operations, not continuously
- **Added combat detection**: Players in combat are now skipped and will be retried automatically
- **Added sanity check**: Maximum move attempts limited to 3x expected moves to prevent infinite loops
- **Fixed UI trigger**: "Sort Raid" button now directly calls sort function instead of toggling a flag
- **Improved messaging**: Removed debug window references, added class-colored player names in skip messages
- **Combat notifications**: Clear feedback when players are skipped due to combat status

### Technical Changes
- Added `IsPlayerInCombat()` helper function using `UnitAffectingCombat()`
- Implemented `movesAttempted` counter with `maxMoveAttempts` threshold (3x expected moves)
- Auto-sort frame lifecycle properly managed via `OGRH.activeAutoSortFrame`
- Skip messages now include class-colored player names using `OGRH.ClassColorHex()`
- Removed unused `autoSortEnabled` flag and polling timer

## Version 1.26.0 - Raid Group Organization & Auto-Sort
**Release Date:** December 8, 2025

### Features
- **Raid Group Organization (RGO)**: Complete raid composition planning system
  - 8 groups × 5 slots with class priority configuration per slot
  - Priority dialog with class selection and role checkboxes (Tanks, Healers, Melee, Ranged, DPS, Support, Any)
  - Support for multiple entries of same class with different role requirements
  - Visual slot display showing top 3 priorities with role indicators
  - Raid size selector (10/20/40 man) with dynamic group enable/disable
  - Drag-and-drop slot reordering: Left-click to swap, Right-click to copy
  - Settings persist per raid size configuration

- **Auto-Sort Algorithm**: Intelligent raid reorganization based on priorities
  - Three-phase sorting: Plan → Queue → Execute
  - Scores players based on class match + role match (110-position×10 points)
  - Handles full groups with smart swapping (prefers unassigned players)
  - Configurable sort speed via `/ogrh sortspeed [ms]` (default 100ms between moves)
  - Toggle via minimap menu: Invites → Sort Raid
  - Automatic disable after execution to prevent loops

- **Role System Integration**: 
  - Auto-assign roles by class defaults (Warriors→Tanks, Priests/Paladins/Druids→Healers, Rogues→Melee, others→Ranged)
  - Role assignments now persist to saved variables immediately
  - Fixed role sync between Roles UI and RGO auto-sort

### Commands
- `/ogrh shuffle [delay_ms]` - Shuffle raid with 20 random swaps (default 500ms intervals, for testing)
- `/ogrh sortspeed [ms]` - Set/view auto-sort speed (default 100ms)
- `/rgo` - Open Raid Group Organization window

### UI Improvements
- Class priority dialog with scrollable lists and multi-selection
- Visual feedback for enabled/disabled groups based on raid size
- Drag cursor indicator showing source slot during drag operations
- Minimap menu reorganized: Invites now has submenu with "Show Invites" and "Sort Raid"

### Technical Implementation
- Queue-based move execution prevents infinite loops
- Scoring system evaluates all class positions for best role match
- Saved variables: `OGRH_SV.rgo.raidSizes[size][group][slot]` for priorities
- `OGRH_SV.rgo.sortSpeed` for configurable sort delay
- `OGRH_SV.rgo.autoSortEnabled` for toggle state

## Version 1.23.0 - Guild Recruitment Module & Data Export
**Release Date:** December 8, 2025

### Features
- **OGST Library**: Extracted UI template functions into reusable library
  - New `Libs\OGST\OGST.lua` - OG Standard Templates library for cross-addon reuse
  - Comprehensive API documentation in `Libs\OGST\README.md`
  - Functions: StyleButton, CreateStandardMenu, CreateStyledScrollList, CreateStyledListItem, AddListItemButtons, CreateScrollingTextBox, MakeFrameCloseOnEscape
  - Backward compatible wrappers in OGRH_Core maintain existing addon functionality
  - Standardized constants for colors and dimensions
  - Can be used in other addons for consistent UI styling
- **Raid Data Export**: Export raid encounter assignments in multiple formats
  - Export Raid button in Encounter Planning window (top left)
  - Three export formats available via button selection:
    - **Plain Text**: Clean, readable format without color codes for text editors
    - **CSV (Spreadsheet)**: Structured data export for Google Sheets/Excel
      - Columns: Raid, Encounter, R.T (Role Title), R.M (Mark Index), R.P (Player Name), R.A (Assignment Number)
      - Perfect for creating reference tabs with formulas and pivot tables
    - **HTML (Colors)**: Preserves WoW color codes as HTML for web viewing or import to Google Docs
  - Pre-selected text for easy copying (Ctrl+A, Ctrl+C)
  - Higher frame strata (FULLSCREEN_DIALOG) ensures ESC closes export window first
  - Processes all announcement tags with player names, marks, and assignments

- **Guild Recruitment Module**: Complete advertising and contact management system
  - Automated guild recruitment message broadcasting to selected chat channels
  - Channel selection: General, Trade, World, or Raid chat
  - Configurable interval between advertisements (default 5 minutes)
  - Start/Stop Recruiting toggle with visual feedback
  - Character limit (255) with live counter for recruitment messages
  - 5 preset message templates with dropdown selector for quick switching
  - Message persistence across sessions (all 5 presets saved independently)

- **Recruiting Panel**: Active recruitment status display
  - Countdown progress bar showing time until next advertisement
  - Timer display in M:SS format
  - Quick Stop button for immediate cancellation
  - Priority-based stacking with other auxiliary panels
  - Auto-show/hide based on recruiting state
  - Persists recruiting state across /reload

- **Whisper Contact System**: Automatic tracking and chat interface
  - Intelligent whisper filtering (tracks only when recruiting or existing contact)
  - Contact list with class-colored names and timestamps (MM/DD HH:MM format)
  - Full chat history view with detailed timestamps (YYYY-MM-DD HH:MM)
  - Class color detection via pfUI database integration
  - WHO query system for unknown players with throttling protection
  - Reply interface for sending whispers directly from contact view

- **Contact Management**: Standard deletion and tracking controls
  - Delete button using standardized interface
  - Deleted contacts tracking prevents automatic re-adding
  - Contacts persist across sessions in saved variables
  - Scheduled list refresh for smooth performance (0.5s batch updates)
  - Window registry integration (closes other dialogs when opening)

### UI Improvements
- Class-colored player names throughout contact list and chat interface
- Consistent styling with existing Data Management module
- Dynamic left panel with Advertise option and contact list
- Full-width chat view with message history and reply box
- Standard list item buttons with proper spacing

### Technical Implementation
- pfUI_playerDB integration for immediate class lookup
- WHO query queue with 2-second throttling to prevent server limits
- Player cache system stores class information for performance
- Auxiliary panel system integration (priority 15)
- Saved variables: whisperHistory, playerCache, deletedContacts

## Version 1.22.8 - Menu System & Panel Positioning Improvements
**Release Date:** December 7, 2025

### Features
- **Generic Menu System**: Created reusable menu/submenu builder function
  - `OGRH.CreateStandardMenu()` provides consistent menu creation across addon
  - Supports nested submenus with automatic positioning and arrow indicators
  - Configurable title and item colors (titleColor, itemColor)
  - All menus now use standardized system (minimap button, encounter select)
  - Reduced code duplication by ~300 lines

- **Auxiliary Panel Positioning System**: Centralized panel stacking management
  - Automatic positioning of all auxiliary panels (consume monitor, ready check, push structure, etc.)
  - Panels intelligently stack below or above main UI based on available screen space
  - Priority-based ordering ensures consistent layout (consume monitor → ready check → push structure)
  - 2-pixel gap between panels prevents border overlap
  - Automatic repositioning on main UI movement or panel visibility changes
  - Future-proof system for adding new panels without positioning conflicts

### UI Improvements
- **Encounter Select Menu**: Enhanced right-click menu on encounter button
  - Menu items now left-aligned for consistency
  - Raids show submenu with encounters on hover
  - Direct encounter selection from submenu
  - Visual arrow indicator (>) for items with submenus
  - White text matching minimap menu style

### Bug Fixes
- Fixed Settings menu item showing duplicate arrow ("Settings > >")
- Fixed push structure sync panel overlapping other panels
- Fixed all auxiliary panels now using consistent frame strata (MEDIUM/HIGH instead of DIALOG)
- Fixed sync panel not registering with positioning system on creation and re-show
- Fixed consume monitor not appearing on reload when encounter with consumes is selected
- Fixed inconsistent text colors between menus (both now use white for items)

## Version 1.22.1 - Invites Module Fixes
**Release Date:** December 6, 2025

### Features
- **Generic Menu System**: Created reusable menu/submenu builder function
  - `OGRH.CreateStandardMenu()` provides consistent menu creation across addon
  - Supports nested submenus with automatic positioning
  - Configurable text colors for easy identification
  - All menus now use standardized system (minimap button, encounter select)
  - Reduced code duplication by ~300 lines

### Bug Fixes
- **Invites Module**: Fixed case-sensitivity issues with player name matching
  - Added proper title case normalization (e.g., "jOhNdOe" → "Johndoe")
  - Player names from soft-res data now match guild roster and raid roster regardless of capitalization
  - Fixes class color lookups that require proper name formatting
  - Ensures case-insensitive matching while maintaining display compatibility

### UI Improvements
- **Encounter Select Menu**: Enhanced right-click menu on encounter button
  - Menu items now left-aligned for consistency
  - Raids show submenu with encounters on hover
  - Direct encounter selection from submenu
  - Visual arrow indicator (>) for items with submenus

## Version 1.22.0 - Code Modularity Improvements
**Release Date:** December 4, 2025

### Features
- **Stable Role IDs**: Roles now maintain stable identifiers that persist across reordering
  - Role announcement tags (e.g., `[R1.T]`, `[R2.P3]`) no longer break when roles are reordered
  - One-time migration automatically assigns IDs to existing roles based on current position
  - Deleted roles will still break announcements (expected behavior)
  - Users may see non-sequential role numbers (e.g., R5, R2, R1) after reordering, but announcements remain functional
  - Added `fillOrder` field to roles for future fill priority enhancements

### Technical
- **Encounter Setup Module Extraction**: Improved code organization and maintainability
  - Created OGRH_EncounterSetup.lua module for Encounter Setup window and role editor
  - Extracted ~2,338 lines (36%) from OGRH_EncounterMgmt.lua into dedicated file
  - Includes ShowEncounterSetup() function, all setup-related StaticPopupDialogs, and ShowEditRoleDialog() function
  - Added RefreshAll() wrapper function for external integration with Import/Load Defaults operations
  - Reduced OGRH_EncounterMgmt.lua complexity while maintaining all functionality
- **Role ID Migration**: Added MigrateRolesToStableIDs() migration function
  - Automatically runs on first load after update
  - Assigns stable IDs based on current column1 → column2 order
  - All role index calculations now use roleId instead of array position
- **Removed Ineffective Code**: Removed UpdateAnnouncementTagsForRoleChanges() function (~100 lines)
  - Previous attempt to auto-update announcement tags was unreliable
  - Stable role IDs provide better solution

## Version 1.21.0 - Data Management Refactoring
**Release Date:** December 4, 2025

### Features
- **Data Management Window**: New unified interface for structure and configuration management
  - Replaces old "Import / Export" window from main menu
  - Centralized location for Load Defaults, Push Structure, and Import/Export operations
  - Action-based interface with detail panel for each operation
  - All data management operations now in OGRH_Sync.lua module

- **Improved Import/Export Interface**: Complete rebuild with proper scrolling support
  - Native WoW 1.12 scrollframe implementation (no external templates)
  - Properly sized editbox that fills available space
  - Auto-focus on Import/Export action selection
  - Manual scrollbar with mouse wheel support
  - Export/Import/Clear buttons for workflow clarity

- **Push Structure Enhancements**: Visual improvements to sync interface
  - User list with class-colored names
  - Version and checksum columns for mismatch detection
  - Refresh button for manual raid polling
  - Auto-refresh after sync completion

### Technical
- Removed OGRH.ShowShareWindow() and OGRH_ShareFrame from OGRH_Core.lua
- All data management operations consolidated in OGRH_Sync.lua
- Import/Export editbox properly calculated width (312px) accounting for scrollbar
- ESC key handler fixed by removing keyboard capture conflicts
- Data Management window properly registered in UISpecialFrames for ESC closing
- Duplicate prevention in MakeFrameCloseOnEscape to avoid UISpecialFrames pollution

### Fixed
- Fixed editbox not filling available width in Import/Export interface
- Fixed CTRL+V requiring double-press (now auto-focuses editbox)
- Fixed ESC key not closing Data Management window
- Fixed "UIPanelScrollFrameTemplate" error (WoW 1.12 doesn't have this template)

## Version 1.20.0 - Announcement System Refactoring
**Release Date:** December 4, 2025

### Features
- **Unified Announcement System**: Complete refactoring of announcement functionality
  - Created OGRH_Announce.lua module for all announcement-related code
  - New `OGRH.Announcements.SendEncounterAnnouncement()` unified function
  - Both Main UI "A" button and Encounter Planning "Announce" button now use identical code paths
  - New `OGRH.Announcements.BuildConsumeAnnouncement()` helper for consume announcements
  - Removed ~250 lines of duplicate announcement code from OGRH_EncounterMgmt.lua
  - ReadHelper sync functionality preserved in unified announcement system

- **Lua 5.0 Compatibility Layer**: Added OGRH_Backport.lua for WoW 1.12 compatibility
  - Implements `string.match()` as wrapper around `string.find()` (Lua 5.1 feature)
  - Implements `string.gmatch()` as alias for `string.gfind()`
  - Removes dependency on RollFor's backport library
  - Announcement system now works independently of external addons

### Technical
- OGRH_Backport.lua loads first in TOC to provide Lua 5.1 features
- Tag replacement system (`ReplaceTags`) fully self-contained in OGRH_Announce.lua
- Supports all tag types: [Rx.T], [Rx.P], [Rx.PA], [Rx.Py], [Rx.My], [Rx.Ay], [Rx.A=y], [Rx.Cy]
- Conditional block processing with AND (&) and OR logic preserved
- ShowAnnouncementTooltip cleaned up to remove duplicate variable initialization

### Fixed
- Fixed "attempt to call field 'match' (a nil value)" error when RollFor disabled
- Announcement system no longer requires RollFor addon to function

## Version 1.19.0 - Plugin Architecture
**Release Date:** December 1, 2025

### Features
- **Plugin Architecture**: New modular system for encounter-specific functionality
  - Custom Module role type added to Edit Role dialog (alongside Raider Roles and Consume Check)
  - Modules can be selected and ordered via dual list boxes (Selected/Available)
  - Modules automatically load/unload when navigating encounters on main UI
  - Module loading respects encounter sync from raid leader
  - Modules only visible on main UI, hidden from Encounter Planning window

- **C'Thun Plugin**: First official encounter plugin
  - Automatically loads BigWigs C'Thun positioning map
  - Overrides map texture with custom numbered version for zone assignments
  - Map shows/hides automatically when navigating to/from C'Thun encounter
  - Requires BigWigs addon and synced encounter structure

### Technical
- Module registration system in OGRH_Core.lua
- Modules folder structure for organization
- Standard module lifecycle: OnLoad, OnUnload, OnCleanup
- Modules stored per Custom Module role in encounter configuration

## Version 1.18.1 - RollFor Auto-Assign
**Release Date:** November 30, 2025

### Features
- **RollFor Auto-Assign**: Right-click Auto-Assign button to assign from RollFor soft-reserve data
  - Auto-assigns players who signed up via RollFor but aren't in the raid yet
  - Respects class priority configuration
  - Respects linked roles for alternating assignment
  - Updates player class cache from guild roster
  - Clears existing assignments before assigning
  - Added tooltip to Auto-Assign button showing left/right click actions

### Fixed
- **Bidirectional Role Linking**: Linked roles now properly connect all roles to each other
  - When linking R1 to R2, R3, R4: all four roles now link to each other
  - Previously only created one-way links back to the initiating role
  - Ensures proper alternating assignment across all linked roles

## Version 1.18.0 - Link Role Feature
**Release Date:** November 29, 2025

### Features
- **Link Role System**: Connect multiple roles together for alternating assignment
  - New "Link Role" checkbox in Edit Role dialog (below Invert Fill Order)
  - Link button appears in role header when Link Role is enabled
  - Link Role dialog allows selecting which roles to link together
  - Bidirectional linking: linking Role A to Role B automatically links Role B to Role A
  - Linked roles are included in checksum validation for proper sync

- **Alternating Auto-Assign**: Auto-assign now distributes players across linked roles
  - Slots filled in alternating order (Role A Slot 1, Role B Slot 1, Role A Slot 2, etc.)
  - Works with both class priority and defaultRoles fallback
  - Each slot in the alternating queue uses class priority if configured, otherwise falls back to defaultRoles
  - Ensures fair distribution of players across linked roles

- **Invert Fill Order**: New checkbox in Edit Role dialog
  - Controls fill direction for auto-assign (top-down by default, bottom-up when enabled)
  - Works independently for each role
  - Phase 2 (defaultRoles fallback) always fills top-down

### Technical
- Added OGRH_LinkRole.lua for Link Role dialog management
- Updated HashRole function to include linkedRoles and invertFillOrder in checksums
- Linked roles processed as a group in auto-assign to maintain alternating order
- Role skip tracking prevents linked roles from being processed multiple times

## Version 1.15.2 - Auto-Assign Class Priority Fixes
**Release Date:** November 29, 2025

### Fixed
- Auto-assign now correctly assigns players based on class priority system
- Fixed role matching logic for classes without role checkboxes (Warlock, Mage, Rogue)
- Classes in priority list with no role checkboxes configured now accept players from any role
- Classes with role checkboxes enabled only accept players matching those specific roles
- Classes with role checkboxes but none enabled accept players from any role

## Version 1.17.0 - Class Priority System
**Release Date:** November 29, 2025

### Features
- **Class Priority Assignment**: Left-click any role slot in Encounter Planning to set class priority
  - Define which classes should be preferred for each slot
  - Drag classes up/down to set priority order
  - Classes not in the priority list have no preference
  - Role checkboxes for hybrid classes (Tanks, Healers, Melee, Ranged)
  - Role naming matches RolesUI convention for consistency with auto-assignment
  - Future feature: Auto-assignment based on priority (not yet implemented)

- **Class Priority Dialog**:
  - Two-column interface: Priority Order (left) and Available Classes (right)
  - Priority Order list has up/down/delete buttons using standardized template
  - Available Classes list has add button to move classes to priority list
  - Class priority stored per slot, not per role (each slot can have different priorities)
  - Role-specific checkboxes for hybrid classes:
    - Druid/Shaman: Tanks, Healers, Melee, Ranged
    - Warrior: Tanks, Melee
    - Paladin: Tanks, Healers, Melee
    - Hunter: Melee, Ranged
    - Priest: Healers, Ranged
    - Mage/Rogue/Warlock: No role checkboxes (single role)

### Technical Details
- **New File**: OGRH_ClassPriority.lua - Dialog for managing class priorities
- **Data Structure**: 
  - `role.classPriority[slotIndex] = {"Warrior", "Paladin", ...}`
  - `role.classPriorityRoles[slotIndex][className] = {Tanks=true, Healers=true, ...}`
- **Structure Checksum**: Updated to include both classPriority and classPriorityRoles data
  - HashRole function moved to module level for reuse
  - CalculateAllStructureChecksum now calls HashRole for complete property coverage
- **Import/Export**: Class priority and role flags included in structure sync
- **Multipliers**: 
  - classPriority uses 3000x multiplier in checksum calculation
  - classPriorityRoles uses 4000-4004x multipliers (one per role flag)
- **Role Naming**: Uses RolesUI convention (Tanks, Healers, Melee, Ranged) for consistency

## Version 1.15.4 - UI Standardization
**Release Date:** November 28, 2025

### Code Improvements
- **List Item Button Template**: Created standardized `OGRH.AddListItemButtons()` template function
  - Consolidates duplicated up/down/delete button code across all list windows
  - Reduces ~440 lines of duplicated code to ~110 lines (75% reduction)
  - Provides consistent button behavior and positioning across addon
  - Supports optional delete-only mode for lists that don't need reordering

- **Applied Template To**:
  - Encounter Setup: Raids list, Encounters list, both Roles columns
  - Trade Settings: Item list
  - Consume Settings: Item list
  - Auto Promote: Player list (delete-only mode)

### Technical Details
- **Template Function**: `OGRH.AddListItemButtons(listItem, index, listLength, onMoveUp, onMoveDown, onDelete, hideUpDown)`
- **Button Graphics**: Standard WoW scroll arrows (up/down) and minimize button (X)
- **Auto-disable**: Up button disabled on first item, down button disabled on last item
- **Return Values**: Returns button references for positioning adjacent text elements

## Version 1.15.3 - Structure Checksum Enhancement
**Release Date:** November 28, 2025

### Bug Fixes
- **Structure Checksum Validation**: Enhanced checksum to include all role dialog settings
  - Now hashes all 20+ role properties from Edit Role dialog
  - Includes: boolean flags, defaultRoles, classes, consume primary/secondary/allowAlternate
  - Prevents false mismatches when role settings differ between raid members
  - Uses unique multipliers for each property to ensure checksum sensitivity

### Technical Details
- **New Helper Function**: `HashRole()` comprehensively hashes all role properties
- **Properties Included**: name, slots, isConsumeCheck, showRaidIcons, showAssignment, markPlayer, allowOtherRoles, defaultRoles (4 values), classes (10 values), consumes (3 values per item)
- **Multiplier System**: Column1 uses 10x, Column2 uses 20x, unique multipliers per property

## Version 1.15.2 - Consume Tag Display Fix
**Release Date:** November 28, 2025

### Bug Fixes
- **Consume Tag Formatting**: Fixed [Rx.Cy] consume tags not displaying properly in announcements
  - Item links now preserve color codes and formatting correctly
  - Removed erroneous color reset codes that were breaking item link format
  - Consume items now display as clickable, colored item links in both tooltips and raid chat
  - Cleaned up debug code from previous troubleshooting

### Technical Details
- **Item Link Preservation**: Consume tag replacements now use special `__NOCOLOR__` marker to prevent color wrapping
- **Replacement Logic**: Added special case handling for item links that must be inserted exactly as-is
- **Broadcast System**: Previously disabled announcement broadcast system remains disabled (not needed for non-staged announcements)

## Version 1.15.1 - Sync RollFor Bug Fix
**Release Date:** November 27, 2025

### Bug Fixes
- **Sync RollFor**: Fixed issue where clicking "Sync RollFor" button moved players NOT in RollFor data
  - Now only updates roles for players who are actually in RollFor data
  - Players not in RollFor keep their current/manually assigned roles
  - Fixed both sender and receiver to use consistent logic
  - Prevents unwanted role changes based on class defaults

## Version 1.15.0 - Roles UI Synchronization
**Release Date:** November 27, 2025

### Features
- **Roles UI Broadcasting**:
  - Player role changes now broadcast to entire raid in real-time
  - When raid admin/L/A drags a player to a different role, all raid members see the change
  - "Sync RollFor" button now broadcasts to entire raid
  - All raid members' Roles UI stays synchronized automatically

- **Permission System**:
  - Only Raid Leader (L), Assistants (A), or designated Raid Admin can:
    - Drag players between roles
    - Click Poll or column headers to start polls
    - Use "Sync RollFor" button
  - Non-admin players see permission error message if they attempt restricted actions
  - Prevents conflicting role assignments from multiple sources

### Technical Details
- **New Addon Messages**:
  - `ROLE_CHANGE;playerName;newRole` - broadcasts when player moved between roles
  - `ROLLFOR_SYNC` - broadcasts when "Sync RollFor" button clicked
- **New Permission Function**:
  - `OGRH.CanManageRoles()` - checks if player is L, A, or raid admin
  - Returns true if not in raid (solo editing allowed)
  - Used to gate all role management actions

### Bug Fixes
- **Role Consistency**: Fixed issue where role changes weren't visible to other raid members
- **RollFor Sync**: Fixed "Sync RollFor" only applying locally instead of raid-wide

## Version 1.14.1 - Raid Lead Poll Version & Checksum Display
**Release Date:** November 27, 2025

### Features
- **Raid Lead Selection UI Enhancement**:
  - Added "Version" column showing each player's addon version (1.14.1)
  - Added "Checksum" column showing structure data checksum for sync verification
  - Color-coded display: Green = matching version/checksum, Red = mismatch
  - Added "Refresh" button to re-poll after syncing structure data
  - Expanded frame width to 360px to accommodate new columns
  - Right-click the blue "Sync" button to open raid lead selection poll

### Technical Details
- **Checksum Calculation**:
  - New `CalculateAllStructureChecksum()` function hashes ALL structure data
  - Includes: raids list, encounters list, roles, marks, assignment numbers, announcements, trade items, consumes
  - Matches EXACTLY the data exported by Import/Export > Sync
  - Each player calculates their own checksum when responding to poll
  - Enables quick verification that all raid members have matching structure data

### Bug Fixes
- **Poll Response Parsing**: Fixed string parsing bugs in ADDON_POLL_RESPONSE handler
  - Fixed prefix length check (19 characters, not 20)
  - Fixed data extraction offset (position 21, not 22)
  - Poll now correctly displays all raid members with addon installed

## Version 1.11.11 - ESC Key Handling
**Release Date:** November 23, 2025

### Features
- **ESC Key Support**: Added ESC key handling to all windows and dialogs
  - All main windows now close when pressing ESC (Invites, SR+ Validation, Encounter Planning, etc.)
  - All dialogs now close when pressing ESC (Edit Role, Player Selection, Consume Selection, etc.)
  - Minimap menu closes on ESC key press
  - Uses standard WoW UISpecialFrames mechanism for proper integration

### Bug Fixes
- **ESC Key Behavior**: Fixed ESC key opening game menu instead of closing OGRH windows
  - Removed conflicting keyboard handler that interfered with default ESC behavior
  - Now matches behavior of other addons like pfQuest

## Version 1.11.10 - SR+ Validation UI Improvements
**Release Date:** November 22, 2025

### Features
- **SR+ Validation Window**:
  - Added selection highlighting to player list - selected player now clearly highlighted
  - Auto-select next record after clicking "Save Validation" for faster workflow
  - Smart selection order prioritizes: Error > Passed > Validated
  - Window title now updates when clicking Refresh to reflect current raid instance

### Performance Improvements
- **SR+ Validation Loading**:
  - Added caching for decoded RollFor data (5 second cache)
  - Pre-warm GetItemInfo cache before building UI to reduce lag
  - Deferred item name lookups to avoid blocking on initial load
  - Significantly improved window load time, especially on first open

### Bug Fixes
- **SR+ Validation Display**: Fixed nil concatenation errors when displaying items whose data isn't cached yet
  - Added proper fallbacks for item names in both current and historical displays
  - Now shows "Item [itemId]" when item info not available instead of crashing

## Version 1.11.9 - Assignment Sync Fixes
**Release Date:** November 22, 2025

### Bug Fixes
- **Assignment Sync System**:
  - Fixed Main UI Sync button using legacy code - now uses proper structure validation
  - Fixed Auto Assign not syncing - created `OGRH.BroadcastFullSync()` wrapper function
  - Fixed Clear encounter sync call using non-existent function
  - Removed marks and numbers from assignment syncs (structure elements should only update via Import/Export)
  - Assignment syncs now only transmit player assignments, not structure elements
  - Ensures separation of concerns: assignment syncs = player assignments only, structure syncs = roles/marks/numbers

### Technical Improvements
- **Code Cleanup**: Replaced 60+ lines of legacy sync code with unified function calls
- **Data Integrity**: Structure elements (marks, numbers) now exclusively managed through Import/Export > Sync
- **Consistency**: All sync operations now use structure checksum validation

## Version 1.11.8 - Auto-Promote Improvements
**Release Date:** November 21, 2025

### Features
- **Auto-Promote Enhancements**:
  - Session tracking: Players are only auto-promoted once per session (prevents re-promoting demoted players)
  - Assistant support: Raid assistants can now trigger auto-promotes by sending requests to the raid leader
  - Uses same message protocol as remote ready checks

### UI Improvements
- **Consume Settings**: Close button now uses standard button styling for consistency

## Version 1.11.7 - Encounter Setup List Items Standardization
**Release Date:** November 21, 2025

### UI Improvements
- **Encounter Setup Interface**: Applied standard UI template to all list items
  - Raids list items: Now use `CreateStyledListItem` with hover effects
  - Encounters list items: Now use `CreateStyledListItem` with hover effects
  - Roles list items (both columns): Now use `CreateStyledListItem` with hover effects
  - "Add Role" buttons: Standardized with custom green color using `SetListItemColor`
  - All items now respond to global hover color changes in `OGRH.LIST_COLORS`
  - Consistent spacing using `OGRH.LIST_ITEM_HEIGHT` and `OGRH.LIST_ITEM_SPACING` constants
  - Proper drag-and-drop color feedback using `SetListItemSelected` and `SetListItemColor`

## Version 1.11.6 - Encounter Setup UI Standardization
**Release Date:** November 21, 2025

### UI Improvements
- **Encounter Setup Interface**: Applied standard UI template to scroll frames
  - Raids list: Replaced custom scroll frame with standardized template
  - Encounters list: Replaced custom scroll frame with standardized template
  - Roles assignment area: Replaced custom scroll frame with standardized template
  - All lists now use consistent scrollbar management

### Bug Fixes
- **Consume Settings**: Fixed secondary item field showing "nil" instead of empty string when not set
  - Edit dialog now properly handles nil/0 secondary item values
  - Prevents validation errors when saving consume items without secondary options

## Version 1.11.5 - Consume Settings UI Standardization
**Release Date:** November 21, 2025

### UI Improvements
- **Consume Settings Interface**: Applied standard UI template to consumables list
  - Replaced custom scroll frame with standardized template
  - List items now use consistent height, spacing, and styling
  - Used `CreateStyledListItem` template for both regular items and "Add Consume" button
  - Applied custom green color to "Add Consume" button using `SetListItemColor`
  - Proper scrollbar management with standard template functions
  - Consistent with other interfaces (Auto Promote, Raid Invites, SR+ Validation, Addon Audit, Trade Settings)

## Version 1.11.4 - Trade Settings UI Standardization
**Release Date:** November 21, 2025

### UI Improvements
- **Trade Settings Interface**: Applied standard UI template to trade items list
  - Replaced custom scroll frame with standardized template
  - List items now use consistent height, spacing, and styling
  - Used `CreateStyledListItem` template for both regular items and "Add Item" button
  - Applied custom green color to "Add Item" button using `SetListItemColor`
  - Proper scrollbar management with standard template functions
  - Consistent with other interfaces (Auto Promote, Raid Invites, SR+ Validation, Addon Audit)

## Version 1.11.3 - Addon Audit UI Standardization
**Release Date:** November 21, 2025

### UI Improvements
- **Addon Audit Interface**: Applied standard UI template to addon list
  - Replaced custom scroll frame with standardized template
  - List items now use consistent height, spacing, and styling
  - Added proper scrollbar management
  - Selection highlighting now uses standard template functions
  - Consistent with other interfaces (Auto Promote, Raid Invites, SR+ Validation)

## Version 1.11.2 - SR+ Validation UI Standardization
**Release Date:** November 21, 2025

### Bug Fixes
- **SR+ Validation Logic**: Fixed validation for new players with SR+ items
  - Now correctly checks that ALL items must be at +0 for new players
  - Previously only checked total SR+ value, allowing mixed values like one item at +0 and another at +20

### UI Improvements
- **SR+ Validation Interface**: Applied standard UI template to player list
  - Replaced red/green background colors with status labels
  - Added three validation states: "Validated" (bright green), "Passed" (gray), "Error" (red)
  - "Validated": Player's current SR+ exactly matches their last validation record
  - "Passed": Player's SR+ passes auto-validation rules (increases within limits)
  - "Error": Player's SR+ has unexpected changes requiring attention
  - Right panel now matches left panel height
  - Reduced spacing between panels from ~10px to 5px
  - List items use standardized height and spacing constants

### Technical Changes
- Added `OGRH.LIST_ITEM_HEIGHT` and `OGRH.LIST_ITEM_SPACING` constants for consistent dimensions
- Updated Invites and Promotes windows to use template constants
- Added `OGRH.SRValidation.GetValidationStatus()` function for determining validation state

## Version 1.11.1 - UI Template Application
**Release Date:** November 21, 2025

### Bug Fixes
- **Raid Invites List Styling**: Applied standard UI template to Raid Invites window
  - Fixed list item backgrounds not displaying properly
  - Issue was caused by dynamic container sizing with anchor points
  - Now uses explicit width/height calculations before creating scroll list
  - List items now display with proper gray backgrounds and hover effects

### UI Improvements
- Aligned RollFor Import button to match Close button dimensions and padding

## Version 1.11.0 - Auto Promote & UI Standardization
**Release Date:** November 21, 2025

### New Features
- **Auto Promote System**: Automatically promote specific players to assistant when they join raids
  - Maintain a list of players who should always receive assistant rank
  - Drag/drop or click to add players from raid/guild roster
  - Search functionality to quickly find players
  - Players organized by In Raid / Online / Offline status
  - Class-colored player names for easy identification
  - Auto-promotion triggers on raid roster updates
  - Accessible via "Auto Promote" in main menu

### UI Improvements
- **Standardized List Formatting**: Created reusable scroll list template
  - `OGRH.CreateStyledScrollList()` function for consistent scroll lists
  - Standardized spacing, scrollbar positioning, and backdrop styling
  - Returns content width for consistent row sizing
  - Applied to Auto Promote interface (both left and right lists)
  - Includes mouse wheel support and automatic scrollbar show/hide

### Technical Changes
- Added OGRH_Promotes.lua with auto-promote logic and UI
- Auto-promote data stored in OGRH_SV.autoPromotes as table format
- CreateStyledScrollList() template added to OGRH_Core.lua
- Migrates old string format to new table format with class info

## Version 1.10.0 - Factory Defaults & UI Improvements
**Release Date:** November 21, 2025

### New Features
- **Factory Defaults System**: Configure default raid settings that load automatically on first run
  - New OGRH_Defaults.lua file for storing factory default configurations
  - "Defaults" button in Import/Export Data window to load factory defaults
  - First-run detection automatically loads defaults if configured
  - Easy configuration: Export your raid setup and paste into defaults file

### UI Improvements
- Renamed "Share Raid Data" window to "Import / Export Data" for clarity
- Redesigned button layout with 6 evenly-spaced, centered buttons
  - Export, Import, Defaults, Sync, Clear, Close
- Improved button sizing and spacing for better visual consistency
- All buttons now fit proportionally across window width

### Technical Changes
- Added OGRH_Defaults.lua to load order after OGRH_Core.lua
- Factory defaults use direct Lua table format (no string parsing needed)
- First-run check validates table structure with version field
- LoadFactoryDefaults() function copies default data to SavedVariables

## Version 1.9.0 - Raid Lead System
**Release Date:** November 20, 2025

### Major Features
- **Raid Lead System**: Coordinate encounter planning across your raid with designated raid lead
  - Right-click Sync button to poll addon users and select a raid lead
  - Only raid leaders and assistants can initiate polls and be selected as raid lead
  - Designated raid lead automatically syncs changes to all raid members
  - Permission system prevents non-leads from editing assignments while in raid
  - Automatic query for current raid lead when joining a raid
  - Raid lead cleared when leaving raid to allow solo editing

### Sync Improvements
- Drag/drop player assignments now automatically broadcast to raid (raid lead only)
- Assignment updates bypass sync lock when coming from designated raid lead
- Full encounter sync updates bypass sync lock when from designated raid lead
- Sync button tooltip shows current raid lead
- Left-click sync broadcasts current encounter (raid lead only)
- Left-click sync requests update from raid lead (non-leads)

### Permission Controls
- Auto-Assign button restricted to raid lead
- Drag/drop functionality restricted to raid lead
- Right-click clear assignment restricted to raid lead
- Edit Role button restricted to raid lead
- Edit unlock button restricted to raid lead
- Announcement edit boxes only unlockable by raid lead
- All restrictions lifted when not in raid for solo planning

### UI Enhancements
- Select Raid Lead dialog with class-colored player names
- Current raid lead highlighted with green background
- Player list shows raid rank indicators (L for Leader, A for Assistant)
- Compact dialog styling matching addon's visual standards
- Proper spacing and margins for improved readability

### Technical Improvements
- Added RAID_LEAD_QUERY message for discovering current lead
- Added RAID_LEAD_SET message for broadcasting lead changes
- RAID_ROSTER_UPDATE event handling for automatic state management
- Class color caching system for Select Raid Lead dialog
- Automatic cleanup of raid lead state when leaving raid

### Bug Fixes
- Fixed sync system to respect raid lead permissions
- Fixed edit controls to properly check permissions before allowing actions
- Fixed assignment broadcasts to only send from designated raid lead
- Fixed poll system to only include players with proper raid rank

---

## Version 1.8.5
**Release Date:** Prior Release

### Bug Fixes
- Fixed invite auto-convert to only trigger within 60s of clicking Invite All
