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
