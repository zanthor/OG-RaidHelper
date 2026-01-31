# Core.lua Function Review & Call Site Analysis
**Date:** January 30, 2026  
**Purpose:** Document all functions in Core.lua and identify their call sites to help identify dead code and reduce complexity

---

## Table of Contents
1. [RollFor Integration](#rollfor-integration)
2. [SavedVariables Management](#savedvariables-management)
3. [Active Raid Management](#active-raid-management)
4. [Sync Priority Helpers](#sync-priority-helpers)
5. [RGO Settings Migration](#rgo-settings-migration)
6. [SavedVariables V2 Migration](#savedvariables-v2-migration)
7. [Timer System](#timer-system)
8. [Module System](#module-system)
9. [Utility Functions](#utility-functions)
10. [UI Component Wrappers (OGST Library)](#ui-component-wrappers-ogst-library)
11. [Auxiliary Panel System](#auxiliary-panel-system)
12. [Ready Check System](#ready-check-system)
13. [Announcement System](#announcement-system)
14. [Checksum & Sync Functions](#checksum--sync-functions)
15. [Serialization Functions](#serialization-functions)
16. [Raid Management Functions](#raid-management-functions)
17. [Player Management Functions](#player-management-functions)
18. [Import/Export Functions](#importexport-functions)
19. [Minimap Button](#minimap-button)
20. [Global Helper Functions](#global-helper-functions)

---

## 1. RollFor Integration

### `OGRH.CheckRollForVersion()`
**Purpose:** Check if RollFor addon is installed and has the required version  
**Called From:**
- `_Core/Core.lua:27` - Auto-called during initialization
- **Status:** ✅ ACTIVE - Used for RollFor compatibility checks

---

## 2. SavedVariables Management

### `OGRH.EnsureSV()`
**Purpose:** Initialize SavedVariables structure, handle schema versioning, auto-migration, and auto-purge of old v1 data  
**Called From:**
- `_Core/Core.lua:174` - During VARIABLES_LOADED event
- `_Core/Core.lua:330` - Before various operations
- `_Core/Core.lua:2214, 2291, 2537, 2585` - Multiple locations in Core.lua
- `_Infrastructure/Sync_v2.lua` - 6 calls
- `_Infrastructure/DataManagement.lua` - 3 calls
- `_Administration/SRValidation.lua` - Has own `OGRH.SRValidation.EnsureSV()`
- `_Administration/Recruitment.lua:16`
- **Status:** ✅ ACTIVE - Critical initialization function used everywhere

---

## 3. Active Raid Management

### `OGRH.EnsureActiveRaid()`
**Purpose:** Ensure Active Raid exists at raids[1], automatically shifts existing raids if needed  
**Called From:**
- `_Core/Core.lua:245` - During VARIABLES_LOADED event (Phase 1)
- `_Core/Core.lua:493` - Within SetActiveRaid when creating structure
- **Status:** ✅ ACTIVE - Core Phase 1 infrastructure

### `OGRH.SetActiveRaid(sourceRaidIdx)`
**Purpose:** Copy a raid structure to the Active Raid slot  
**Called From:**
- `_Tests/test_phase1.lua:117` - Test suite
- **Status:** ⚠️ LIMITED USE - Only used in tests currently, but designed for future UI integration

### `OGRH.GetActiveRaid()`
**Purpose:** Get Active Raid data from raids[1]  
**Called From:**
- `_Infrastructure/SyncIntegrity.lua` - 3 calls (lines 227, 284, 343)
- `_Tests/test_phase1.lua` - 4 calls in tests
- **Status:** ✅ ACTIVE - Used by SyncIntegrity system

---

## 4. Sync Priority Helpers

### `OGRH.IsActiveRaid(raidIdx)`
**Purpose:** Determine if a raid index is the Active Raid (index 1)  
**Called From:**
- `_Core/Core.lua:575` - Within GetSyncLevel
- **Status:** ✅ ACTIVE - Helper for sync level determination

### `OGRH.GetSyncLevel(raidIdx, context)`
**Purpose:** Get appropriate sync level based on whether raid is active and the context (EncounterMgmt vs EncounterSetup)  
**Called From:**
- `_Raid/EncounterMgmt.lua` - 8 calls (lines 348, 1880, 2273, 2753, 2862, 3004, 3235)
- **Status:** ✅ ACTIVE - Critical for Phase 3 sync priority system

---

## 5. RGO Settings Migration

### `OGRH.MigrateRGOSettings()`
**Purpose:** Migrate deprecated RGO settings to new locations and clean up  
**Called From:**
- `_Core/Core.lua:175` - During VARIABLES_LOADED event
- **Status:** ✅ ACTIVE - Migration function, runs once per session

---

## 6. SavedVariables V2 Migration

### `OGRH.Migration.MigrateToV2(force)`
**Purpose:** Main migration function to create v2 schema (NOTE: Overwritten by Infrastructure/Migration.lua)  
**Called From:**
- Auto-migration system in VARIABLES_LOADED event handler
- **Status:** ⚠️ DEPRECATED - Function in Core.lua is commented out, actual implementation in Infrastructure/Migration.lua

### `OGRH.Migration.ValidateV2()`
**Purpose:** Compare v1 vs v2 schemas for validation  
**Called From:**
- Manual validation commands
- **Status:** ✅ ACTIVE - Used for migration validation

### `OGRH.Migration.CutoverToV2()`
**Purpose:** Switch to v2 schema  
**Called From:**
- Auto-cutover in VARIABLES_LOADED event handler
- Manual cutover commands
- **Status:** ✅ ACTIVE - Used during migration process

### `OGRH.Migration.RollbackFromV2()`
**Purpose:** Revert to v1 schema  
**Called From:**
- Manual rollback commands
- **Status:** ✅ ACTIVE - Safety mechanism for migration issues

---

## 7. Timer System

### `OGRH.ScheduleTimer(callback, delay, repeating)`
**Purpose:** Schedule a delayed or repeating function call  
**Called From:**
- `_Core/Core.lua:544` - Within SetActiveRaid
- `_Infrastructure/SyncIntegrity.lua` - 5 calls (lines 469, 763, 833, 863)
- `_Core/SavedVariablesManager.lua` - 2 calls (lines 447, 752)
- `_Configuration/Invites_Test.lua` - 3 calls (lines 203, 214, 218)
- `_Configuration/Invites.lua:1464`
- `_Core/ChatWindow.lua:174`
- **Status:** ✅ ACTIVE - Heavily used timer utility

### `OGRH.CancelTimer(id)`
**Purpose:** Cancel a scheduled timer  
**Called From:**
- `_Infrastructure/SyncIntegrity.lua` - 2 calls (lines 466, 851)
- **Status:** ✅ ACTIVE - Used with ScheduleTimer

---

## 8. Module System

### `OGRH.RegisterModule(module)`
**Purpose:** Register a module for dynamic loading  
**Called From:**
- **Status:** ⚠️ NO CALLS FOUND - May be dead code or used by external modules not in search

### `OGRH.GetAvailableModules()`
**Purpose:** Get list of all available modules  
**Called From:**
- **Status:** ⚠️ NO CALLS FOUND - May be dead code

### `OGRH.LoadModulesForRole(moduleIds)`
**Purpose:** Load modules for a specific role  
**Called From:**
- `_UI/MainUI.lua:549, 603` - When loading encounter modules
- **Status:** ✅ ACTIVE - Used by MainUI

### `OGRH.UnloadAllModules()`
**Purpose:** Unload all currently loaded modules  
**Called From:**
- `_Core/Core.lua:936` - Within LoadModulesForRole
- `_Core/Core.lua:964` - Within CleanupModules
- `_UI/MainUI.lua:549, 606, 609, 612` - Multiple calls in MainUI
- **Status:** ✅ ACTIVE - Used for module lifecycle management

### `OGRH.CleanupModules()`
**Purpose:** Clean up all modules on addon unload  
**Called From:**
- `_Core/Core.lua:2976` - During PLAYER_LOGOUT event
- **Status:** ✅ ACTIVE - Cleanup function

---

## 9. Utility Functions

### `OGRH.Trim(s)`
**Purpose:** Trim whitespace from string  
**Called From:**
- **Status:** ⚠️ NO CALLS FOUND - May be dead code

### `OGRH.Mod1(n,t)`
**Purpose:** Modulo function (1-indexed)  
**Called From:**
- **Status:** ⚠️ NO CALLS FOUND - May be dead code

### `OGRH.CanRW()`
**Purpose:** Check if player can send raid warnings  
**Called From:**
- Multiple locations for raid warning checks
- **Status:** ✅ ACTIVE - Used for permission checks

### `OGRH.SayRW(text)`
**Purpose:** Send text as raid warning if able, else raid chat  
**Called From:**
- Multiple locations for raid announcements
- **Status:** ✅ ACTIVE - Used for announcements

### `OGRH.FormatConsumeItemLinks(consumeData, escapeForProcessing)`
**Purpose:** Create formatted item links for chat messages  
**Called From:**
- **Status:** ⚠️ NO DIRECT CALLS FOUND - May be used indirectly or dead code

### `DeepCopy(obj, seen)` (local function)
**Purpose:** Deep copy utility for tables  
**Called From:**
- Multiple calls within Core.lua for v1 data copying
- **Status:** ✅ ACTIVE - Used in migration system

### `DeepCopyForActiveRaid(obj, seen)` (local function)
**Purpose:** Deep copy specifically for Active Raid operations  
**Called From:**
- `_Core/Core.lua:498` - Within SetActiveRaid
- **Status:** ✅ ACTIVE - Used by Active Raid system

---

## 10. UI Component Wrappers (OGST Library)

### `OGRH.CloseAllWindows(exceptFrame)`
**Purpose:** Close all dialog windows except specified one  
**Called From:**
- `_UI/MainUI.lua:415` - When opening Encounter Frame
- `_Core/Core.lua:5138, 5177, 5196` - Multiple window opens in minimap menu
- **Status:** ✅ ACTIVE - Used for window management

### `OGRH.ShowStructureSyncPanel(isSender, encounterName)`
**Purpose:** Show/update Structure Sync progress panel  
**Called From:**
- `_Core/Core.lua:1143` - Within ShowStructureSyncProgress
- `_Core/Core.lua:4513, 4586` - During structure sync broadcasts
- **Status:** ✅ ACTIVE - Used for sync UI feedback

### `OGRH.UpdateStructureSyncPanel(isSender, encounterName)`
**Purpose:** Update Structure Sync panel content  
**Called From:**
- Internal to ShowStructureSyncPanel
- **Status:** ✅ ACTIVE - Helper function

### `OGRH.ShowStructureSyncProgress(isSender, progress, complete, encounterName)`
**Purpose:** Show sync progress with percentage  
**Called From:**
- Internal sync operations
- **Status:** ✅ ACTIVE - Used during sync operations

### `OGRH.StyleButton(button)` 
**Purpose:** Apply custom button styling (wrapper for OGST.StyleButton)  
**Called From:**
- `_Infrastructure/DataManagement.lua` - 7 calls for various buttons
- `_UI/MainUI.lua` - 10 calls for UI buttons (lines 36, 65, 68, 71, 79, 196, 231, 372, 386, 400, 719)
- **Status:** ✅ ACTIVE - Heavily used for UI consistency

### `OGRH.CreateStandardWindow(config)`, `OGRH.CreateStandardMenu(config)`, etc.
**Purpose:** Wrappers for OGST library functions  
**Called From:**
- Various UI components
- **Status:** ✅ ACTIVE - All OGST wrappers are actively used

### `OGRH.CreateStyledScrollList(parent, width, height, hideScrollBar)`
**Purpose:** Create standardized scrolling list with frame  
**Called From:**
- `_Infrastructure/DataManagement.lua` - 2 calls
- `_Raid/EncounterMgmt.lua` - 3 calls (lines 884, 895, 1447)
- `_Modules/OGRH-ConsumeHelper.lua` - 2 calls
- **Status:** ✅ ACTIVE - Used for list UIs

### `OGRH.CreateStyledListItem(parent, width, height, frameType)`
**Purpose:** Create standardized list item with background  
**Called From:**
- `_Raid/EncounterMgmt.lua` - 3 calls (lines 940, 1103, 2179)
- `_Modules/OGRH-ConsumeHelper.lua` - 4 calls
- **Status:** ✅ ACTIVE - Used for list items

### `OGRH.AddListItemButtons(...)`
**Purpose:** Add up/down/delete buttons to list items  
**Called From:**
- `_Modules/OGRH-ConsumeHelper.lua:346`
- **Status:** ✅ ACTIVE - Used for editable lists

### `OGRH.SetListItemSelected(item, isSelected)`
**Purpose:** Set list item visual state  
**Called From:**
- `_Raid/EncounterMgmt.lua` - 2 calls (lines 944, 1107)
- `_Modules/OGRH-ConsumeHelper.lua` - 3 calls
- **Status:** ✅ ACTIVE - Used for list selection

### `OGRH.CreateScrollingTextBox(parent, width, height)`
**Purpose:** Create scrolling multi-line text box  
**Called From:**
- `_Infrastructure/DataManagement.lua:640`
- `_Raid/EncounterMgmt.lua:4763`
- **Status:** ✅ ACTIVE - Used for text input areas

### `OGRH.MakeFrameCloseOnEscape(frame, frameName, closeCallback)`
**Purpose:** Register frame for ESC key closing  
**Called From:**
- `_Configuration/Consumes.lua` - 2 calls
- `_Configuration/Promotes.lua:183`
- `_Configuration/Invites.lua` - 3 calls
- `_Raid/EncounterMgmt.lua:758`
- **Status:** ✅ ACTIVE - Used for all closeable dialogs

---

## 11. Auxiliary Panel System

### `OGRH.RegisterAuxiliaryPanel(frame, priority)`
**Purpose:** Register panel for automatic positioning below/above main UI  
**Called From:**
- `_Core/Core.lua` - 4 calls for Structure Sync Panel
- `_Configuration/Invites.lua` - 2 calls (lines 2190, 2207)
- `_Administration/Recruitment.lua` - 2 calls (lines 977, 992)
- `_Configuration/Consumes.lua:605`
- **Status:** ✅ ACTIVE - Used for all auxiliary panels

### `OGRH.UnregisterAuxiliaryPanel(frame)`
**Purpose:** Unregister auxiliary panel  
**Called From:**
- `_Core/Core.lua:1091`
- `_Configuration/Invites.lua:2196`
- `_Administration/Recruitment.lua:983`
- **Status:** ✅ ACTIVE - Panel cleanup

### `OGRH.RepositionAuxiliaryPanels()`
**Purpose:** Reposition all registered auxiliary panels  
**Called From:**
- `_Core/Core.lua` - 3 calls
- `_Configuration/Invites.lua:2210`
- `_Administration/Recruitment.lua:995`
- `_Configuration/Consumes.lua:608`
- **Status:** ✅ ACTIVE - Auto-positioning system

---

## 12. Ready Check System

### `OGRH.ShowReadyCheckTimer()`
**Purpose:** Show ready check countdown timer  
**Called From:**
- `_Core/Core.lua:2042` - Within DoReadyCheck
- `_Core/Core.lua:2980` - During READY_CHECK event
- `_Infrastructure/MessageRouter.lua:376`
- **Status:** ✅ ACTIVE - Part of ready check UI

### `OGRH.HideReadyCheckTimer()`
**Purpose:** Hide ready check timer  
**Called From:**
- `_Core/Core.lua:2989` - During CHAT_MSG_ADDON event
- `_Core/Core.lua:4109` - Within ReportReadyCheckResults
- `_Infrastructure/MessageRouter.lua:386`
- **Status:** ✅ ACTIVE - Timer cleanup

### `OGRH.DoReadyCheck()`
**Purpose:** Initiate ready check  
**Called From:**
- `_UI/MainUI.lua:773` - Ready check button
- **Status:** ✅ ACTIVE - User-triggered function

### `OGRH.ReportReadyCheckResults()`
**Purpose:** Report ready check results to raid  
**Called From:**
- `_Core/Core.lua:4040, 4068` - When ready check completes
- **Status:** ✅ ACTIVE - Results reporting

---

## 13. Announcement System

### `OGRH.SendAnnouncement(lines, testMode)`
**Purpose:** Send announcement lines to raid chat  
**Called From:**
- `_Raid/Announce.lua:791` - Main announcement function
- **Status:** ✅ ACTIVE - Core announcement system

### `OGRH.SendAddonMessage(msgType, data)` ⚠️ DEPRECATED
**Purpose:** Send addon message with prefix  
**Called From:**
- `_Core/Core.lua:2082` - LOGS DEPRECATION WARNING
- **Status:** 🔴 DEPRECATED - Use MessageRouter instead. Function deliberately disabled.

### `OGRH.BroadcastEncounterSelection(raidName, encounterName)` ⚠️ DEPRECATED
**Purpose:** Broadcast encounter selection to raid  
**Called From:**
- `_Core/Core.lua:2091` - LOGS DEPRECATION WARNING
- **Status:** 🔴 DEPRECATED - Use MessageRouter with OGRH.MessageTypes.STATE.CHANGE_ENCOUNTER instead.

### `OGRH.ReAnnounce()`
**Purpose:** Re-announce stored announcement  
**Called From:**
- **Status:** ⚠️ NO CALLS FOUND - May be dead code or manual command

---

## 14. Checksum & Sync Functions

### `OGRH.HashRole(role, columnMultiplier, roleIndex)`
**Purpose:** Hash a role's complete settings for checksum calculation  
**Called From:**
- `_Core/Core.lua:2227, 2233` - Within CalculateStructureChecksum
- `_Core/Core.lua:2403, 2410` - Within CalculateAllStructureChecksum
- `_Infrastructure/Versioning.lua:522, 532`
- **Status:** ✅ ACTIVE - Critical for sync integrity

### `OGRH.CalculateStructureChecksum(raid, encounter)`
**Purpose:** Calculate checksum based on roles configuration  
**Called From:**
- `_Core/Core.lua:2582` - Within BroadcastFullEncounterSync
- `_Core/Core.lua:2745, 3239, 3355, 3559` - Multiple sync validation points
- **Status:** ✅ ACTIVE - Core sync validation

### `OGRH.CalculateAllStructureChecksum()`
**Purpose:** Calculate checksum for ALL structure data  
**Called From:**
- `_Infrastructure/MessageRouter.lua:1508` - Addon version poll
- **Status:** ✅ ACTIVE - Used for version checking

### `OGRH.CalculateAssignmentChecksum(raid, encounter)`
**Purpose:** Calculate checksum for encounter assignments  
**Called From:**
- **Status:** ⚠️ NO DIRECT CALLS FOUND - May be dead code

### `OGRH.CalculateRolesUIChecksum()`
**Purpose:** Calculate checksum for RolesUI data  
**Called From:**
- `_Infrastructure/SyncIntegrity.lua` - 3 calls (lines 254, 371)
- **Status:** ✅ ACTIVE - Used by SyncIntegrity system

### `OGRH.BroadcastFullEncounterSync()`
**Purpose:** Broadcast full encounter assignment sync (assignments only, no structure)  
**Called From:**
- `_Core/Core.lua:3081, 3769` - Multiple sync trigger points
- `_Infrastructure/MessageRouter.lua:514`
- **Status:** ✅ ACTIVE - Core sync function

### `OGRH.HandleAssignmentSync(sender, syncData)`
**Purpose:** Handler for receiving encounter assignment syncs  
**Called From:**
- Called by OGRH.Sync.RouteMessage internally
- **Status:** ✅ ACTIVE - Sync receiver

### `OGRH.HandleEncounterSync(sender, syncData)`
**Purpose:** Handler for receiving encounter structure syncs  
**Called From:**
- Called by OGRH.Sync.RouteMessage internally
- **Status:** ✅ ACTIVE - Sync receiver

### `OGRH.HandleRolesUISync(sender, syncData)`
**Purpose:** Handler for receiving RolesUI sync  
**Called From:**
- Called by OGRH.Sync.RouteMessage and direct messages
- **Status:** ✅ ACTIVE - Sync receiver

---

## 15. Serialization Functions

### `OGRH.Serialize(tbl)`
**Purpose:** Convert table to string for transmission  
**Called From:**
- `_Infrastructure/DataManagement.lua:155` - For export
- `_Core/Core.lua:4663, 4731` - Export operations
- Multiple internal serialization needs
- **Status:** ✅ ACTIVE - Critical for data exchange

### `OGRH.Deserialize(str)`
**Purpose:** Convert string back to table  
**Called From:**
- `_Infrastructure/Sync_v2.lua:215, 458, 653` - Sync operations
- `_Infrastructure/DataManagement.lua:179` - Import operations
- `_Core/Core.lua:3158, 3351` - Multiple deserialization points
- **Status:** ✅ ACTIVE - Critical for data reception

---

## 16. Raid Management Functions

### `OGRH.GetCurrentEncounter()`
**Purpose:** Get currently selected raid/encounter (read-only)  
**Called From:**
- `_Core/Core.lua:2574` - Within BroadcastFullEncounterSync
- Multiple locations needing current selection
- **Status:** ✅ ACTIVE - Read interface for current selection

### `OGRH.SetCurrentEncounter(raidName, encounterName)`
**Purpose:** Set currently selected raid/encounter (centralized write interface)  
**Called From:**
- `_Core/Core.lua:2616` - Within BroadcastFullSync wrapper
- **Status:** ✅ ACTIVE - Write interface for current selection

### `OGRH.BroadcastFullSync(raid, encounter)` (wrapper)
**Purpose:** Legacy wrapper that sets current encounter then broadcasts  
**Called From:**
- **Status:** ⚠️ LIMITED USE - Wrapper for backwards compatibility

### `OGRH.RequestRaidData()`
**Purpose:** Request raid data from raid members  
**Called From:**
- **Status:** ⚠️ NO CALLS FOUND - May be dead code or manual command

### `OGRH.ProcessRaidDataResponses()`
**Purpose:** Process collected raid data responses  
**Called From:**
- `_Core/Core.lua:4393` - Timer callback
- **Status:** ✅ ACTIVE - Helper for RequestRaidData

### `OGRH.RequestCurrentEncounterSync()`
**Purpose:** Request current encounter sync from raid lead  
**Called From:**
- `_Core/Core.lua:4094` - During RAID_ROSTER_UPDATE event
- **Status:** ✅ ACTIVE - Auto-sync on joining raid

### `OGRH.RequestStructureSync()`
**Purpose:** Request structure sync from raid lead  
**Called From:**
- **Status:** ⚠️ NO DIRECT CALLS FOUND - May be manual command or dead code

### `OGRH.BroadcastStructureSync()`
**Purpose:** Broadcast structure sync (raid lead only)  
**Called From:**
- `_Core/Core.lua:3801, 4467` - Structure sync operations
- **Status:** ✅ ACTIVE - Structure sync system

### `OGRH.BroadcastEncounterStructureSync(raidName, encounterName, requester)`
**Purpose:** Broadcast structure for single encounter  
**Called From:**
- Internal structure sync operations
- **Status:** ✅ ACTIVE - Single encounter sync

---

## 17. Player Management Functions

### `OGRH.GetPlayerClass(playerName)`
**Purpose:** Get player class from multiple sources with caching  
**Called From:**
- `_Raid/Announce.lua` - 5 calls (lines 354, 405, 460, 557)
- `_Configuration/Consumes.lua:899`
- `_Configuration/Roster.lua:1387, 1656`
- `_Raid/EncounterMgmt.lua` - 3 calls (lines 1565, 1972, 3399)
- `_Configuration/Invites.lua:330, 709`
- **Status:** ✅ ACTIVE - Heavily used for class information

### `OGRH.ColorName(name)`
**Purpose:** Color player name by class  
**Called From:**
- `_Configuration/ConsumesTracking.lua:1635, 2721`
- Exposed as global `colorName`
- **Status:** ✅ ACTIVE - Used for colored names

### `OGRH.RefreshRoster()`
**Purpose:** Refresh raid roster cache  
**Called From:**
- `_Raid/Poll.lua:129, 239`
- **Status:** ✅ ACTIVE - Roster management

### `OGRH.PruneBucketsToRaid()`
**Purpose:** Remove non-raid members from role buckets  
**Called From:**
- **Status:** ⚠️ NO DIRECT CALLS FOUND - May be legacy or dead code

### `OGRH.InAnyBucket(nm)`
**Purpose:** Check if player is in any role bucket  
**Called From:**
- **Status:** ⚠️ NO DIRECT CALLS FOUND - May be legacy or dead code

### `OGRH.AddTo(role, name)`
**Purpose:** Add player to role bucket  
**Called From:**
- `_Configuration/Invites.lua:865` - Role assignment
- **Status:** ✅ ACTIVE - Role assignment system

### `OGRH.GetPlayerAssignment(playerName)`
**Purpose:** Get player assignment (raid icon or number)  
**Called From:**
- **Status:** ⚠️ NO DIRECT CALLS FOUND - May be legacy or dead code

### `OGRH.SetPlayerAssignment(playerName, assignData)`
**Purpose:** Set player assignment (raid icon or number)  
**Called From:**
- `_Infrastructure/MessageRouter.lua:729, 1454` - Assignment sync
- **Status:** ✅ ACTIVE - Assignment sync system

### `OGRH.ClearAllAssignments()`
**Purpose:** Clear all player assignments  
**Called From:**
- **Status:** ⚠️ NO DIRECT CALLS FOUND - May be manual command or dead code

### `OGRH.MigrateIconOrder()`
**Purpose:** Migration for icon index mapping (old->blizzard)  
**Called From:**
- **Status:** ⚠️ NO CALLS FOUND - One-time migration, may be dead code

---

## 18. Import/Export Functions

### `OGRH.ExportShareData()`
**Purpose:** Export data to string  
**Called From:**
- `_Core/Core.lua:3642` - Within raid data chunk sending
- `_Core/Core.lua:4505` - Legacy reference check
- **Status:** ✅ ACTIVE - Export system

### `OGRH.ExportEncounterShareData(raidName, encounterName)`
**Purpose:** Export single encounter structure data  
**Called From:**
- **Status:** ⚠️ NO DIRECT CALLS FOUND - May be called dynamically

### `OGRH.ImportShareData(dataString, isSingleEncounter)`
**Purpose:** Import data from string  
**Called From:**
- `_Core/Core.lua:2811, 2818, 3888, 3997, 4431` - Multiple import operations
- **Status:** ✅ ACTIVE - Import system

### `OGRH.LoadFactoryDefaults()`
**Purpose:** Load factory defaults from OGRH_Defaults.lua  
**Called From:**
- `_Core/Core.lua:250` - During VARIABLES_LOADED if firstRun
- **Status:** ✅ ACTIVE - First-time setup

---

## 19. Minimap Button

### `CreateMinimapButton()` (local function)
**Purpose:** Create minimap button with context menu  
**Called From:**
- `_Core/Core.lua` - PLAYER_LOGIN event
- **Status:** ✅ ACTIVE - UI initialization

### `OGRH.ShowMinimapMenu` (exposed globally)
**Purpose:** Show minimap context menu  
**Called From:**
- Minimap button click
- RH button in main UI
- **Status:** ✅ ACTIVE - Menu system

---

## 20. Global Helper Functions

### `OGRH.Header(text)`, `OGRH.Role(text)`, `OGRH.Announce(text)`
**Purpose:** Color text for announcements  
**Called From:**
- Multiple announcement locations
- **Status:** ✅ ACTIVE - Announcement formatting

### `OGRH.ClassColorHex(class)`
**Purpose:** Get hex color code for class  
**Called From:**
- Multiple locations needing class colors
- **Status:** ✅ ACTIVE - Color utility

### `OGRH.GetSelectedRaidAndEncounter()`
**Purpose:** Get currently selected raid and encounter from main UI  
**Called From:**
- `_Configuration/ConsumesTracking.lua` - 4 calls (lines 1544, 1860, 1951, 2368)
- **Status:** ✅ ACTIVE - Used by consumables tracking

---

## Summary & Recommendations

### ✅ ACTIVE FUNCTIONS (87 total)
Most functions in Core.lua are actively used throughout the codebase. The core systems are:
- SavedVariables management and migration
- Active Raid management (Phase 1)
- Sync system with checksums
- Timer system
- UI component wrappers (OGST)
- Auxiliary panel system
- Ready check system
- Serialization/Deserialization
- Player and class management
- Import/Export system

### ⚠️ LIMITED USE / CANDIDATE FOR REVIEW (15 functions)
These functions have few or no direct calls found:
1. `OGRH.RegisterModule()` - No calls found
2. `OGRH.GetAvailableModules()` - No calls found
3. `OGRH.Trim()` - No calls found
4. `OGRH.Mod1()` - No calls found
5. `OGRH.FormatConsumeItemLinks()` - No direct calls found
6. `OGRH.CalculateAssignmentChecksum()` - No direct calls found
7. `OGRH.ReAnnounce()` - No calls found
8. `OGRH.RequestRaidData()` - No calls found
9. `OGRH.RequestStructureSync()` - No direct calls found
10. `OGRH.PruneBucketsToRaid()` - No direct calls found
11. `OGRH.InAnyBucket()` - No direct calls found
12. `OGRH.GetPlayerAssignment()` - No direct calls found
13. `OGRH.ClearAllAssignments()` - No direct calls found
14. `OGRH.MigrateIconOrder()` - No calls found (one-time migration)
15. `OGRH.ExportEncounterShareData()` - No direct calls found

### 🔴 DEPRECATED FUNCTIONS (2 total)
These functions are explicitly marked as deprecated:
1. `OGRH.SendAddonMessage()` - Use MessageRouter instead
2. `OGRH.BroadcastEncounterSelection()` - Use MessageRouter instead

### Complexity Reduction Opportunities

1. **Module System** - `RegisterModule()` and `GetAvailableModules()` appear unused. Consider removing if no external modules use them.

2. **Assignment System** - `GetPlayerAssignment()`, `ClearAllAssignments()` may be legacy from old assignment system.

3. **Utility Functions** - `Trim()`, `Mod1()`, `PruneBucketsToRaid()`, `InAnyBucket()` may be dead code from refactoring.

4. **Manual Commands** - Some functions like `ReAnnounce()`, `RequestRaidData()`, `RequestStructureSync()` may only be accessible via manual commands. Document if keeping.

5. **Migration Code** - `MigrateIconOrder()` is a one-time migration. Can be removed after sufficient time has passed.

6. **Deprecated Functions** - Remove `SendAddonMessage()` and `BroadcastEncounterSelection()` after verifying all callers have been migrated to MessageRouter.

### Next Steps

1. Search for manual slash commands that might call the "No calls found" functions
2. Check if any external addons/modules use RegisterModule system
3. Verify deprecated functions have no remaining callers
4. Remove confirmed dead code in phases
5. Document functions that are intentionally manual-only

---
**End of Report**
