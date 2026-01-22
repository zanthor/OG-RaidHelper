# OG-RaidHelper TODO List

## Current Tasks

### Phase 1: Encounter Setup Extraction (IN PROGRESS)
- ✅ Created OGRH_EncounterSetup.lua file
- ✅ Updated OG-RaidHelper.toc to load new file
- ✅ Copied lines 3138-5476 from OGRH_EncounterMgmt.lua
- ⏸️ **BLOCKED:** Fix `InitializeSavedVars()` dependency error
  - Need to copy function or use `OGRH.EnsureSV()` instead
- ⏳ Test Phase 2 after fix
- ⏳ Remove extracted code from OGRH_EncounterMgmt.lua (Phase 3)

## Discovered Issues

### [Issue] Roles list doesn't clear when selecting different raid
**Description:** 
In the Encounter Setup interface the roles lists do not clear when you select a different raid.

**Status:** Open

## Feature Requests

### Raid Invites System Improvements
**Description:**
Enhancements to the Raid Invites system for better automation and visibility:
- Add Toggle for "Active Invite" mode - periodically scans the guild roster for signed up players not in raid and invites them
- Add status panel below main UI showing X/Total in raid
- Periodically announce to guild "Whisper *player* for raid invites"
- Automatically toggle off when all players invited

**Status:** Planned

### Add Cooldown Role to Encounter Setup/Manager
**Description:**
Add Cooldown Role assignment feature to Encounter Setup/Manager to better track and coordinate class-specific cooldowns during encounters.
- Support for Druid cooldowns
- Support for Warrior cooldowns
- Support for Tank Druid cooldowns

**Status:** Planned

### Line Based Announcements
**Description:**
Add support for line-based announcements in the encounter system.

**Status:** Planned

### Announcement Keybind System
**Description:**
Add advanced setting for Announcement Keybind to allow raid admin or leader to announce specific encounter announcement without switching encounter.

**Status:** Planned

### Announcement Linking
**Description:**
Add Announcement Linking - if encounter is set to a keybind you can announce more than one at a time.

**Status:** Planned

### Announcement LineCode and Command Syntax
**Description:**
Add announcement "LineCode" and `/ogrh announce code` syntax so we can set specific lines to be announced.

**Status:** Planned

### Announcement Queue System
**Description:**
Add Announcement Queue to bypass spam limitation and pace communications to not be throttled.

**Status:** Planned

### Advanced Settings - Auto Assign on Encounter Select
**Description:**
Add advanced setting feature to automatically assign roles when an encounter is selected.

**Status:** Planned

### Advanced Settings - Activate After Encounter Ends Trigger
**Description:**
Add advanced setting to link an encounter to activate when a specific encounter ends. This allows automatic encounter transitions based on boss completion.

**Status:** Planned

### Cooldown Assignment Tag
**Description:**
Add "Cooldown Assignment tag" which will add a player to an announcement from a list based on if their cooldown is available. This allows dynamic cooldown rotation announcements.

**Status:** Planned

### Update Auto-Assign Right-Click for Invite Method
**Description:**
Update the auto-assign right-click functionality to respect the current invite method (RollFor, Raid Roster, or other sources) when assigning players to roles.

**Status:** Planned



---

## Completed
- ✅ Add sync button to Roles UI
- ✅ Fix encounter Sync
- ✅ Need to fix Mark button in Encounter Planning.
- ✅ Fixed Import/Export editbox sizing and positioning
- ✅ Fixed ESC key handler for Data Management window
- ✅ Fixed CTRL+V single-press operation
- ✅ Removed old Share window from Main Menu
- ✅ Updated CHANGELOG.md Version 1.21.0 and 1.22.0
- ✅ Created migration plan document
- ✅ Implemented stable role IDs (roleId field)
- ✅ Added fillOrder field to roles for future use
- ✅ Created MigrateRolesToStableIDs() migration function
- ✅ Updated all role index calculations to use roleId
- ✅ Removed UpdateAnnouncementTagsForRoleChanges() function
- ✅ New roles automatically assigned unique roleId and fillOrder
