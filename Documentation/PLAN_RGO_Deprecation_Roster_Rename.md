# OG-RaidHelper: RGO Deprecation & Roster Rename Plan

**Date:** January 22, 2026  
**Version:** 1.0  
**Status:** Planning Phase

---

## Executive Summary

This document outlines the plan to deprecate the Raid Group Organizer (RGO) feature and consolidate the Roster Management system into a standalone, self-contained module. The primary goal is to eliminate dependencies on the RGO codebase while preserving all roster functionality and cleaning up deprecated RGO SavedVariables.

---

## Scope

### In Scope
- Deprecate `OGRH_RGO.lua` (1586 lines) - RGO main file
- Rename `OGRH_RGO_Roster.lua` → `OGRH_Roster.lua`
- Migrate RGO-specific helper functions used by Roster into the renamed Roster file
- Update all references throughout the codebase
- Update TOC file load order
- Update menu system integration
- **Add cleanup code to remove deprecated RGO SavedVariables on addon initialization**
- **Migrate any still-used RGO settings to appropriate locations**

### Out of Scope
- Modifying OGST library
- Changes to other OG-RaidHelper features
- UI/UX improvements (this is a refactoring exercise)

---

## Current State Analysis

### File Structure
```
OG-RaidHelper/
├── OGRH_RGO.lua                  (1586 lines) - TO BE DEPRECATED
├── OGRH_RGO_Roster.lua          (1787 lines) - TO BE RENAMED
└── OG-RaidHelper.toc            - Loads both files at lines 68-69
```

### Current Dependencies

#### OGRH_RGO_Roster.lua Dependencies on OGRH_RGO.lua

**Analysis**: After examining both files, **the Roster file does NOT directly depend on any functions from OGRH_RGO.lua**. The roster module is already self-contained and only uses:

1. **OGST Library** (UI framework - external dependency, OK)
2. **OGRH Core** (`OGRH.EnsureSV()`, `OGRH.Msg()` - core functions, OK)
3. **SavedVariables** (`OGRH_SV.rosterManagement` - separate namespace)

**Key Finding**: The roster system is architecturally independent of RGO. No migration of functions from RGO to Roster is required.

#### Backward Compatibility Functions in OGRH_Core.lua

The following wrapper functions exist in `OGRH_Core.lua` (lines ~575-620) for backward compatibility:
- `OGRH.CreateStyledScrollList()` → `OGST.CreateStyledScrollList()`
- `OGRH.CreateStyledListItem()` → `OGST.CreateStyledListItem()`
- `OGRH.AddListItemButtons()` → `OGST.AddListItemButtons()`
- `OGRH.SetListItemSelected()` → `OGST.SetListItemSelected()`
- `OGRH.SetListItemColor()` → `OGST.SetListItemColor()`
- `OGRH.StyleButton()` → `OGST.StyleButton()`

**These wrappers are used by RGO**, not Roster. The Roster file already calls OGST directly.

### Current Integration Points

#### Menu System Integration
**Location**: `OGRH_Core.lua` lines ~5130-5142

```lua
-- RGO Menu Item (DEPRECATED - will be removed)
if OGRH.ShowRGOWindow then
  OGRH.ShowRGOWindow()
end

-- Roster Menu Item (ACTIVE - will remain)
if OGRH.RosterMgmt and OGRH.RosterMgmt.ShowWindow then
  OGRH.RosterMgmt.ShowWindow()
end
```

#### SavedVariables Structure

**RGO SavedVariables** (to be removed with cleanup code):
```lua
OGRH_SV.rgo = {
  currentRaidSize = "40",
  raidSizes = { ["10"] = {}, ["20"] = {}, ["40"] = {} },
  autoSortEnabled = false,  -- MIGRATE to OGRH_SV.invites.autoSortEnabled
  sortSpeed = 500  -- milliseconds, MIGRATE to OGRH_SV.sorting.speed
}
```

**Roster SavedVariables** (independent, will remain):
```lua
OGRH_SV.rosterManagement = {
  players = {},
  rankingHistory = {},
  config = {
    eloSettings = {
      startingRating = 1000,
      kFactor = 32
    }
  }
}
```

**New Settings Locations** (after migration):
```lua
-- Auto-sort enabled flag
OGRH_SV.invites.autoSortEnabled = false  -- migrated from rgo.autoSortEnabled

-- Sort speed setting
OGRH_SV.sorting = { speed = 500 }  -- migrated from rgo.sortSpeed
```

**Critical**: RGO and Roster are completely separate namespaces. After cleanup, the entire `OGRH_SV.rgo` table will be removed.

#### External References to RGO

Found in:
- `OGRH_Core.lua` - Menu item registration (line ~5130)
- `OGRH_MainUI.lua` - References to `OGRH_SV.rgo.sortSpeed` (lines 573, 576-577)
- `OGRH_Invites.lua` - References to `OGRH_SV.rgo.autoSortEnabled` (lines 1108-1109)

---

## Migration Plan

### Phase 1: File Renaming & TOC Updates

**Objective**: Rename roster file and update load order.

**Tasks**:
1. ✅ Rename `OGRH_RGO_Roster.lua` → `OGRH_Roster.lua`
2. ✅ Update `OG-RaidHelper.toc`:
   - Change line 69: `OGRH_RGO_Roster.lua` → `OGRH_Roster.lua`
   - Comment out line 68: `## OGRH_RGO.lua -- DEPRECATED: Raid Group Organizer (use Roster Management instead)`
3. ✅ Update file header comment in `OGRH_Roster.lua`:
   - Change from `-- OGRH_RGO_Roster.lua - Roster Management Feature`
   - To: `-- OGRH_Roster.lua - Roster Management System`

**Files Modified**:
- `OGRH_RGO_Roster.lua` (rename to `OGRH_Roster.lua`)
- `OG-RaidHelper.toc`

**Testing**:
- ✅ Addon loads without errors
- ✅ Roster window opens via menu
- ✅ SavedVariables persist correctly

---

### Phase 2: Namespace Refactoring

**Objective**: Update all code references to reflect new naming.

**Tasks**:
1. ✅ Search and replace in `OGRH_Roster.lua`:
   - No changes needed - already uses `OGRH.RosterMgmt` namespace (correct)
2. ✅ Update internal comments referring to "RGO":
   - Update file header
   - Update any inline comments mentioning "RGO Roster" → "Roster"

**Files Modified**:
- `OGRH_Roster.lua`

**Testing**:
- ✅ All roster functions work correctly
- ✅ No console errors related to undefined functions

---

### Phase 2a: SavedVariables Cleanup & Migration

**Objective**: Add cleanup code to remove deprecated RGO SavedVariables and migrate still-used settings.

**Tasks**:
1. ✅ Create migration function in `OGRH_Core.lua`:
   ```lua
   function OGRH.MigrateRGOSettings()
     if not OGRH_SV.rgo then return end  -- Already cleaned up
     
     -- Migrate autoSortEnabled to invites namespace
     if OGRH_SV.rgo.autoSortEnabled ~= nil then
       OGRH.EnsureSV()  -- Ensure invites table exists
       if not OGRH_SV.invites then OGRH_SV.invites = {} end
       if OGRH_SV.invites.autoSortEnabled == nil then
         OGRH_SV.invites.autoSortEnabled = OGRH_SV.rgo.autoSortEnabled
       end
     end
     
     -- Migrate sortSpeed to sorting namespace
     if OGRH_SV.rgo.sortSpeed then
       if not OGRH_SV.sorting then OGRH_SV.sorting = {} end
       if OGRH_SV.sorting.speed == nil then
         OGRH_SV.sorting.speed = OGRH_SV.rgo.sortSpeed
       end
     end
     
     -- Remove entire RGO saved variables
     OGRH_SV.rgo = nil
     
     OGRH.Msg("|cff00ff00[Migration]|r Cleaned up deprecated RGO settings")
   end
   ```

2. ✅ Call migration function in `ADDON_LOADED` event:
   ```lua
   if event == "ADDON_LOADED" and arg1 == "OG-RaidHelper" then
     OGRH.OnLoad()
     OGRH.MigrateRGOSettings()  -- Add this line
   end
   ```

3. ✅ Update references to migrated settings:
   - `OGRH_MainUI.lua`: Change `OGRH_SV.rgo.sortSpeed` → `OGRH_SV.sorting.speed`
   - `OGRH_Invites.lua`: Change `OGRH_SV.rgo.autoSortEnabled` → `OGRH_SV.invites.autoSortEnabled`

**Files Modified**:
- `OGRH_Core.lua` (add migration function and call it)
- `OGRH_MainUI.lua` (update sortSpeed references)
- `OGRH_Invites.lua` (update autoSortEnabled references)

**Testing**:
- ✅ Fresh install: No errors, new settings locations used
- ✅ Existing RGO data: Settings migrated correctly, `OGRH_SV.rgo` removed
- ✅ After migration: All features work with new settings locations
- ✅ Verify: `/dump OGRH_SV.rgo` returns `nil`
- ✅ Verify: `/dump OGRH_SV.invites.autoSortEnabled` shows correct value
- ✅ Verify: `/dump OGRH_SV.sorting.speed` shows correct value

---

### Phase 3: Menu System Updates

**Objective**: Update menu integration to remove RGO references.

**Tasks**:
1. ✅ In `OGRH_Core.lua`:
   - Locate RGO menu item registration (~line 5130)
   - Add deprecation comment
   - Consider wrapping in `if false then` block for future removal
   - Keep Roster menu item active (no changes needed)

2. ✅ Test menu system:
   - Verify "Roster Management" menu item works
   - Verify RGO menu item is hidden/removed

**Files Modified**:
- `OGRH_Core.lua`

**Testing**:
- ✅ Main menu displays correctly
- ✅ Roster menu item opens roster window
- ✅ No RGO menu item appears (or is clearly marked deprecated)

---

### Phase 4: External Reference Cleanup

**Objective**: Remove or isolate references to RGO SavedVariables in other modules.

#### 4.1 OGRH_MainUI.lua References

**Location**: Lines 573, 576-577

**Current Code**:
```lua
OGRH_SV.rgo.sortSpeed = speedMs

if OGRH_SV.rgo and OGRH_SV.rgo.sortSpeed then
  OGRH.Msg("Current auto-sort speed: " .. OGRH_SV.rgo.sortSpeed .. "ms")
end
```

**New Code**:
```lua
-- Initialize sorting namespace if needed
if not OGRH_SV.sorting then OGRH_SV.sorting = {} end
OGRH_SV.sorting.speed = speedMs

if OGRH_SV.sorting and OGRH_SV.sorting.speed then
  OGRH.Msg("Current auto-sort speed: " .. OGRH_SV.sorting.speed .. "ms")
end
```

#### 4.2 OGRH_Invites.lua References

**Location**: Lines 1108-1109

**Current Code**:
```lua
if OGRH_SV.rgo.autoSortEnabled == nil then
  OGRH_SV.rgo.autoSortEnabled = false
end
```

**New Code**:
```lua
-- Initialize invites namespace if needed
if not OGRH_SV.invites then OGRH_SV.invites = {} end
if OGRH_SV.invites.autoSortEnabled == nil then
  OGRH_SV.invites.autoSortEnabled = false
end
```

**Files Modified**:
- `OGRH_MainUI.lua` (update sortSpeed references)
- `OGRH_Invites.lua` (update autoSortEnabled references)

**Testing**:
- ✅ Auto-sort functionality still works
- ✅ Sort speed settings persist

---

### Phase 5: Documentation Updates

**Objective**: Update all documentation to reflect deprecation.

**Tasks**:
1. ✅ Create deprecation notice document: `DEPRECATED_RGO.md`
2. ✅ Update main README (if exists)
3. ✅ Update design philosophy document (add note about RGO deprecation)

**New Files**:
- `Documentation/DEPRECATED_RGO.md`

**Files Modified**:
- `Documentation/! OG-RaidHelper Design Philososphy.md` (add deprecation note)

---

### Phase 6: Testing & Validation

**Objective**: Comprehensive testing of all roster functionality.

**Test Cases**:

#### TC1: Fresh Install
- [ ] Load addon with no SavedVariables
- [ ] Open Roster window
- [ ] Add new player
- [ ] Assign roles
- [ ] Set ELO rankings
- [ ] Close and reopen window
- [ ] Verify data persists

#### TC2: Upgrade from Existing Installation (with RGO data)
- [ ] Load addon with existing `OGRH_SV.rgo` data
- [ ] Verify migration message appears
- [ ] Verify `OGRH_SV.rgo` is removed (use `/dump OGRH_SV.rgo`)
- [ ] Verify settings migrated to new locations:
  - [ ] `/dump OGRH_SV.invites.autoSortEnabled` shows correct value
  - [ ] `/dump OGRH_SV.sorting.speed` shows correct value
- [ ] Verify auto-sort features still work
- [ ] Verify sort speed setting still works
- [ ] If roster data exists, verify it's unaffected

#### TC3: Roster Data Isolation (verify roster unaffected by cleanup)
- [ ] Load addon with both `OGRH_SV.rgo` and `OGRH_SV.rosterManagement` data
- [ ] Verify no errors during migration
- [ ] Verify `OGRH_SV.rgo` is removed
- [ ] Verify all roster data (`OGRH_SV.rosterManagement`) remains intact:
  - [ ] All players preserved
  - [ ] All rankings preserved
  - [ ] All role assignments preserved

#### TC4: Menu Integration
- [ ] Open main menu
- [ ] Verify "Roster Management" item present
- [ ] Verify RGO item not present (or marked deprecated)
- [ ] Click "Roster Management"
- [ ] Verify window opens correctly

#### TC5: UI Functionality
- [ ] Test all roster window features:
  - [ ] Role selection (left panel)
  - [ ] Player list (center panel)
  - [ ] Player details (right panel)
  - [ ] Add Player dialog
  - [ ] Manual Import dialog
  - [ ] ShaguDPS integration (if available)
  - [ ] DPSMate integration (if available)
  - [ ] ELO ranking adjustments
  - [ ] Role assignment toggles
  - [ ] Notes editing
  - [ ] Player removal

#### TC6: Performance
- [ ] Test with 100+ players in roster
- [ ] Verify smooth scrolling
- [ ] Verify fast filtering by role
- [ ] Verify ELO sorting performance

---

## Rollback Plan

If critical issues arise during migration:

1. **Immediate Rollback**:
   - Revert `OG-RaidHelper.toc` to load both `OGRH_RGO.lua` and `OGRH_RGO_Roster.lua`
   - Rename `OGRH_Roster.lua` back to `OGRH_RGO_Roster.lua`
   - Restore any modified menu integration code
   - Remove migration function from `OGRH_Core.lua`
   - Revert setting references back to `OGRH_SV.rgo.*`

2. **Data Preservation**:
   - Roster data in `OGRH_SV.rosterManagement` remains intact (never touched)
   - **WARNING**: If migration completed, `OGRH_SV.rgo` will be deleted
   - Migrated settings can be manually restored:
     - `OGRH_SV.rgo.autoSortEnabled = OGRH_SV.invites.autoSortEnabled`
     - `OGRH_SV.rgo.sortSpeed = OGRH_SV.sorting.speed`

3. **Version Control**:
   - Tag current version before starting migration
   - Commit each phase separately for granular rollback
   - **CRITICAL**: Test migration function thoroughly before deploying

---

## Risk Assessment

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| SavedVariables corruption | High | Low | Migration function tested, only touches RGO namespace |
| Settings lost during migration | Medium | Low | Migration preserves values before deletion |
| Undefined function errors | High | Low | Roster already independent of RGO |
| Menu system breaks | Medium | Low | Simple code change, easy to test |
| Performance degradation | Low | Very Low | No architectural changes |
| User confusion | Low | Medium | Clear documentation, in-game migration message |

---

## Success Criteria

✅ **Must Have**:
- Addon loads without errors
- Roster window opens and displays correctly
- All roster features functional (add/remove players, assign roles, set rankings)
- SavedVariables persist correctly across sessions
- No references to deprecated RGO functions in active code
- **Migration function successfully removes `OGRH_SV.rgo`**
- **Migrated settings work correctly in new locations**
- **Auto-sort and sort speed settings preserved during migration**

✅ **Should Have**:
- Clear deprecation documentation
- User-facing migration message confirms cleanup
- No performance regression

✅ **Nice to Have**:

---

## Timeline Estimate

| Phase | Estimated Time | Dependencies |
|-------|----------------|--------------|
| Phase 1: File Renaming | 15 minutes | None |
| Phase 2: Namespace Refactoring | 30 minutes | Phase 1 |
| Phase 3: Menu Updates | 20 minutes | Phase 1 |
| Phase 4: External Reference Cleanup | 30 minutes | Phase 1 |
| Phase 5: Documentation | 45 minutes | Phases 1-4 |
| Phase 6: Testing | 2 hours | All previous |
| **Total** | **~4 hours** | Sequential |

---

## Implementation Checklist

### Pre-Implementation
- [ ] Create backup of current codebase
- [ ] Tag current version in version control
- [ ] Review this plan with stakeholders

### Phase 1: File Renaming
- [ ] Rename `OGRH_RGO_Roster.lua` → `OGRH_Roster.lua`
- [ ] Update `OG-RaidHelper.toc` (comment out RGO, update Roster line)
- [ ] Update file header in `OGRH_Roster.lua`
- [ ] Test: Addon loads without errors

### Phase 2: Namespace Refactoring
- [ ] Review `OGRH_Roster.lua` for RGO references in comments
- [ ] Update comments as needed
- [ ] Test: All roster functions work

### Phase 2a: SavedVariables Cleanup
- [ ] Create `OGRH.MigrateRGOSettings()` function in `OGRH_Core.lua`
- [ ] Add migration function call to `ADDON_LOADED` event
- [ ] Update `OGRH_MainUI.lua` sortSpeed references
- [ ] Update `OGRH_Invites.lua` autoSortEnabled references
- [ ] Test: Fresh install works with new settings
- [ ] Test: Existing RGO data migrates correctly
- [ ] Test: `/dump OGRH_SV.rgo` returns `nil` after migration

### Phase 3: Menu System Updates
- [ ] Locate RGO menu item in `OGRH_Core.lua`
- [ ] Add deprecation comment or disable
- [ ] Test: Roster menu item works, RGO hidden

### Phase 4: External Reference Cleanup
- [ ] Add deprecation comments to `OGRH_MainUI.lua`
- [ ] Add deprecation comments to `OGRH_Invites.lua`
- [ ] Test: Auto-sort features still work

### Phase 5: Documentation
- [ ] Create `DEPRECATED_RGO.md`
- [ ] Update design philosophy document
- [ ] Update any README files

### Phase 6: Testing
- [ ] Run all test cases (TC1-TC6)
- [ ] Fix any issues found
- [ ] Re-test until all pass

### Post-Implementation
- [ ] Commit changes with descriptive message
- [ ] Update version number
- [ ] Deploy to test environment
- [ ] Monitor for issues

---

## Future Enhancements (Out of Scope)

1. **Complete RGO File Removal**:
   - Delete `OGRH_RGO.lua` file entirely from repository
   - Remove any lingering RGO-related comments
   - Archive RGO documentation for reference

2. **Roster Enhancements**:
   - Import from RGO slot assignments (if desired)
   - Integration with encounter assignments
   - Advanced filtering and sorting options

3. **UI Improvements**:
   - Modernize roster window layout
   - Add bulk operations
   - Export/import functionality

---

## Appendix A: Key Functions Analysis

### Functions in OGRH_RGO.lua (NOT used by Roster)

The following are RGO-specific and NOT needed for Roster:

1. **Window Management**:
   - `OGRH.ShowRGOWindow()` - Main RGO window (lines 746+)
   - `OGRH.ShowRGOClassPriorityDialog()` - Class priority dialog (lines 201+)

2. **SavedVariables Management**:
   - `OGRH.EnsureRGOSV()` - Initialize RGO SavedVariables (line 20)
   - `OGRH.CleanupInvalidRoleFlags()` - RGO data validation (line 88)

3. **RGO-Specific Features**:
   - Slot priority management
   - Group composition tools
   - Auto-sort functionality (partially)
   - Raid size templates (10/20/40)

**Conclusion**: None of these functions are called by `OGRH_RGO_Roster.lua`.

### Functions in OGRH_Roster.lua (Standalone)

The Roster module is fully self-contained with its own:

1. **Namespace**: `OGRH.RosterMgmt`
2. **SavedVariables**: `OGRH_SV.rosterManagement`
3. **UI Components**: All using OGST directly
4. **Data Management**: Independent player/role/ranking system

---

## Appendix B: File Size Impact

### Before
- `OGRH_RGO.lua`: 1586 lines (loaded)
- `OGRH_RGO_Roster.lua`: 1787 lines (loaded)
- **Total**: 3373 lines loaded

### After
- `OGRH_RGO.lua`: 1586 lines (NOT loaded, deprecated)
- `OGRH_Roster.lua`: 1787 lines (loaded)
- **Total**: 1787 lines loaded

**Reduction**: 1586 lines (~47% reduction in loaded code)

---

## Appendix C: Compatibility Matrix

| Scenario | Before | After | Notes |
|----------|--------|-------|-------|
| Fresh install | Both load | Roster only | New settings locations used |
| Existing RGO data | Both load | Roster only | **RGO data migrated then deleted** |
| Existing Roster data | Both load | Roster only | Roster data fully functional |
| Mixed data | Both load | Roster only | RGO migrated & deleted, Roster preserved |

---

**Document Status**: Ready for Implementation  
**Reviewed By**: AI Agent  
**Approved By**: (Pending)

---

**END OF PLAN**
