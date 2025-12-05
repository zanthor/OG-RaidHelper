# OG-RaidHelper Changelog

## Version 1.22.0 - Code Modularity Improvements
**Release Date:** December 4, 2025

### Technical
- **Encounter Setup Module Extraction**: Improved code organization and maintainability
  - Created OGRH_EncounterSetup.lua module for Encounter Setup window and role editor
  - Extracted ~2,338 lines (36%) from OGRH_EncounterMgmt.lua into dedicated file
  - Includes ShowEncounterSetup() function, all setup-related StaticPopupDialogs, and ShowEditRoleDialog() function
  - Added RefreshAll() wrapper function for external integration with Import/Load Defaults operations
  - Reduced OGRH_EncounterMgmt.lua complexity while maintaining all functionality
  - No user-facing changes - purely internal code organization improvement

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
