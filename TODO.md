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



---

## Completed
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
