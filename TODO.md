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

### [Issue] 
**Description:** 
In the Encounter Setup interface the roles lists do not clear when you select a different raid.

### [Issue] 
**Description:** 
When you change the role order the roles are re-numbered, if you delete one they are re-numbered.  The announcements are supposed to update their mapping but this doesn't work properly.  Change to static numbers that never change so the announcements never change.

Add fill order to each role so we can control which order they fill without changing which order they display.



---

## Completed
- ✅ Fixed Import/Export editbox sizing and positioning
- ✅ Fixed ESC key handler for Data Management window
- ✅ Fixed CTRL+V single-press operation
- ✅ Removed old Share window from Main Menu
- ✅ Updated CHANGELOG.md Version 1.21.0
- ✅ Created migration plan document
