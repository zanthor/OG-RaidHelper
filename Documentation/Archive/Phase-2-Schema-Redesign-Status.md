# Phase 2: Schema Redesign Status

**Date:** January 23, 2026  
**Context:** Critical pivot during Phase 2 write migration - discovered v1 schema uses display names as keys

---

## The Discovery

### What Happened
During first write conversion in EncounterMgmt.lua (drag-drop player assignment), attempted to use:
```lua
OGRH.SVM.SetPath("encounterAssignments.MC.Tanks and Heals.1.4", "Kinduosen")
```

**Result:** SetPath() failed to parse because encounter name "Tanks and Heals" has spaces in it.

### Root Cause
```lua
-- v1 structure uses display names as table keys:
OGRH_SV.encounterAssignments = {
    ["MC"] = {
        ["Tanks and Heals"] = {  -- USER-EDITABLE NAME WITH SPACES!
            [1] = {[1] = "PlayerName"}
        }
    }
}
```

### User Decision
**User:** "The ENTIRE point of this project is to fix the data structure from fragile and problematic to rock solid, efficient and intuitive. When we discover shit like this we need to unfuck it, not just work around it. This is why we are doing a migration!"

**Decision:** Redesign v2 schema to use stable numeric identifiers instead of display names.

---

## Work Status Matrix

### ✅ Complete & Valid (No Changes Needed)

| Component | Lines | Status | Notes |
|-----------|-------|--------|-------|
| SavedVariablesManager Core | 634 | ✅ GOOD | Core read/write logic is solid |
| Integrated Sync System | ~200 | ✅ GOOD | Routing, batching, permissions work |
| OGAddonMsg Queue Integration | ~100 | ✅ GOOD | Priority system fixed (ALERT→HIGH) |
| Permission System | ~50 | ✅ GOOD | ComponentType-based routing works |
| Test Suite | 23 tests | ✅ PASSING | All SVM core tests pass |
| Combat Queue | ~50 | ✅ GOOD | Offline queue during combat works |
| Checksum Integration | ~30 | ✅ GOOD | Invalidation on write works |

**Total Valid Code:** ~1,117 lines  
**Effort Saved:** This code doesn't need to be rewritten!

---

### ⚠️ Needs Minor Updates

| Component | Current Status | Updates Needed | Effort |
|-----------|----------------|----------------|--------|
| SVM Path Validation | Works but basic | Add numeric-only validation after first key | 1 hour |
| SVM.GetActiveSchema() | Reads from OGRH_SV or v2 | May need index awareness | 1 hour |
| Documentation | Has old schema examples | Update with v2 numeric indices | 2 hours |
| Test Suite | Tests v1-style paths | Add tests for numeric paths + lookups | 2 hours |

**Total Effort:** ~6 hours

---

### ❌ Needs Complete Redo

| Component | Original Effort | Current State | Redo Effort | Reason |
|-----------|----------------|---------------|-------------|--------|
| EncounterMgmt.lua conversions | 4 hours | 3 locations converted | 4 hours | Used v1 string keys, need index lookups |
| Phase 2 tracker population | 2 hours | Partially done | 1 hour | Grep results valid, approach needs update |
| Write conversion examples | 1 hour | Documentation created | 1 hour | Examples use string keys, need indices |

**Total Wasted:** ~7 hours of work  
**Total Redo:** ~6 hours (slightly faster second time)

---

### 📋 New Work Required (Not Started)

| Component | Description | Effort | Priority |
|-----------|-------------|--------|----------|
| Index Lookup System | OGRH.SVM.Lookup.GetRaidIndex(), etc. | 3 hours | 🔴 CRITICAL |
| Migration Script (v1→v2) | Convert name keys to numeric indices | 6 hours | 🔴 CRITICAL |
| Migration Testing | Test with real SavedVariables files | 4 hours | 🔴 CRITICAL |
| Validation System | Compare v1 vs v2 data | 3 hours | 🟡 HIGH |
| Schema Documentation | Complete v2 schema reference | 2 hours | 🟡 HIGH |
| Helper Functions | SetAssignment(), GetAssignment() wrappers | 2 hours | 🟢 MEDIUM |

**Total New Work:** ~20 hours

---

## Effort Summary

| Category | Hours | Percentage |
|----------|-------|------------|
| ✅ Valid (kept) | ~20 | 45% |
| ⚠️ Minor updates | ~6 | 14% |
| ❌ Wasted (redo) | ~7 | 16% |
| 📋 New required | ~20 | 45% |
| **TOTAL** | **~44** | **100%** |

**Key Insight:** 45% of Phase 1 work is still valid! The SVM core, sync system, and permissions were done right. We only need to add the lookup layer and redo the initial conversions.

---

## Revised Timeline

### Original Phase 2 Plan
- Week 2, Days 1-7: Convert ~170 writes
- Estimated: 40 hours total

### Revised Phase 2 Plan

#### Week 2, Days 1-2: Schema Foundation (8 hours)
- [x] Create v2 schema design document ✅
- [ ] Implement index lookup functions (3 hours)
- [ ] Update SVM path validation (1 hour)
- [ ] Add lookup tests to test suite (2 hours)
- [ ] Update documentation examples (2 hours)

#### Week 2, Day 3: Migration System (6 hours)
- [ ] Implement v1 structure analysis (1 hour)
- [ ] Implement index mapping builder (2 hours)
- [ ] Implement migration functions (3 hours)

#### Week 2, Day 4: Migration Testing (4 hours)
- [ ] Test migration with sample data (2 hours)
- [ ] Create validation system (v1 vs v2 comparison) (1 hour)
- [ ] Test with multiple SavedVariables files (1 hour)

#### Week 2, Day 5: Write Conversions Redo (6 hours)
- [ ] Redo EncounterMgmt.lua with lookups (3 hours)
- [ ] Convert remaining critical files (3 hours)

#### Week 2, Days 6-7: Completion (8 hours)
- [ ] Convert remaining files (4 hours)
- [ ] Integration testing with 2+ clients (2 hours)
- [ ] Sync validation and performance testing (2 hours)

**Total Revised Effort:** ~32 hours (vs 40 original)  
**Reason for reduction:** Better approach from the start

---

## What Changed in Implementation

### ❌ Old Approach (Broken)
```lua
-- Direct write with string keys
OGRH.SVM.SetPath("encounterAssignments.MC.Tanks and Heals.1.4", "PlayerName")
-- FAILS: Can't parse "Tanks and Heals" with spaces
```

### ✅ New Approach (Fixed)
```lua
-- Lookup indices from names
local raidIdx, encIdx = OGRH.SVM.Lookup.ResolveNames("MC", "Tanks and Heals")

-- Write with numeric indices
OGRH.SVM.SetPath(
    string.format("encounterAssignments.%d.%d.1.4", raidIdx, encIdx),
    "PlayerName",
    {syncLevel = "REALTIME", componentType = "assignments"}
)
-- WORKS: Clean numeric path
```

### 🎯 Even Better Approach (Helper)
```lua
-- High-level helper that does lookup internally
OGRH.SVM.SetAssignment("MC", "Tanks and Heals", 1, 4, "PlayerName")
-- Internally: resolves names → indices → SetPath()
```

---

## Files That Need Redo

### 1. Raid/EncounterMgmt.lua
**Lines Changed:** 2420-2456, 3298-3377, 155, 3418  
**Current State:** Uses direct writes to v1 structure  
**Required Changes:**
- Add index lookups before all writes
- Replace string keys with numeric indices
- Test drag-drop with spaces in names

**Before:**
```lua
OGRH_SV.encounterAssignments[frame.selectedRaid][frame.selectedEncounter][targetRoleIndex][targetSlotIndex] = frame.draggedPlayerName
```

**After:**
```lua
local raidIdx, encIdx = OGRH.SVM.Lookup.ResolveNames(frame.selectedRaid, frame.selectedEncounter)
if raidIdx and encIdx then
    OGRH.SVM.SetPath(
        string.format("encounterAssignments.%d.%d.%d.%d", raidIdx, encIdx, targetRoleIndex, targetSlotIndex),
        frame.draggedPlayerName,
        {syncLevel = "REALTIME", componentType = "assignments"}
    )
end
```

---

## Testing Strategy

### Phase 1: Unit Tests (Lookup System)
```lua
-- Test lookup functions
function TestIndexLookup()
    -- Test GetRaidIndex
    local mcIdx = OGRH.SVM.Lookup.GetRaidIndex("MC")
    assert(mcIdx == 1, "MC should be raid index 1")
    
    -- Test GetEncounterIndex
    local lucIdx = OGRH.SVM.Lookup.GetEncounterIndex(1, "Lucifron")
    assert(lucIdx == 1, "Lucifron should be encounter index 1")
    
    -- Test with spaces
    local customIdx = OGRH.SVM.Lookup.GetEncounterIndex(1, "Tanks and Heals")
    assert(customIdx ~= nil, "Should find encounter with spaces")
    
    -- Test ResolveNames
    local raidIdx, encIdx = OGRH.SVM.Lookup.ResolveNames("MC", "Tanks and Heals")
    assert(raidIdx and encIdx, "Should resolve both indices")
end
```

### Phase 2: Migration Tests
```lua
-- Test migration preserves data
function TestMigration()
    -- Create v1 test data
    OGRH_SV.encounterAssignments = {
        ["MC"] = {
            ["Tanks and Heals"] = {
                [1] = {[1] = "TestPlayer"}
            }
        }
    }
    
    -- Run migration
    OGRH.Migration.ExecuteV2Migration()
    
    -- Verify v2 has same data
    local v2Data = OGRH_SV.v2.encounterAssignments[1][5][1][1]
    assert(v2Data == "TestPlayer", "Migration should preserve player assignment")
end
```

### Phase 3: Integration Tests
```lua
-- Test write → read cycle
function TestWriteReadCycle()
    -- Write using names (with spaces)
    OGRH.SVM.SetAssignment("MC", "Tanks and Heals", 1, 1, "TestPlayer")
    
    -- Read back using indices
    local raidIdx, encIdx = OGRH.SVM.Lookup.ResolveNames("MC", "Tanks and Heals")
    local value = OGRH_SV.v2.encounterAssignments[raidIdx][encIdx][1][1]
    
    assert(value == "TestPlayer", "Should read back same value")
end
```

---

## Success Metrics

### Code Quality
- ✅ All writes use numeric indices
- ✅ No string keys in v2 structure
- ✅ Lookup functions handle edge cases (nil, not found)
- ✅ Helper functions available for common operations

### Data Integrity
- ✅ Migration preserves 100% of v1 data
- ✅ Validation confirms v1 ≈ v2 (after index mapping)
- ✅ No data loss during migration
- ✅ Rollback capability exists

### Functionality
- ✅ SetPath() works with all encounter names
- ✅ Users can rename encounters without breaking data
- ✅ Drag-drop works with spaces in names
- ✅ Sync works correctly with numeric paths

### Performance
- ✅ Lookup functions are fast (< 1ms)
- ✅ No performance regression vs v1
- ✅ Sync traffic reduced as planned (40-60%)

---

## Lessons Learned

### What Went Right
1. **SVM core design was solid** - No regrets on the architecture
2. **Caught the issue early** - Only 3 write locations converted before discovery
3. **User involvement** - Clear mandate to fix properly, not paper over
4. **Test suite exists** - Can verify changes don't break core

### What Went Wrong
1. **Didn't validate v2 schema thoroughly** - Assumed it was complete
2. **Started conversions before schema review** - Should have validated first
3. **Didn't test with real encounter names** - Would have caught spaces issue

### What We'll Do Different
1. **Schema review first** - Always validate structure before writing code
2. **Test with real data early** - Use actual SavedVariables files
3. **Document edge cases** - Spaces, special chars, unicode in design phase
4. **Build validation tools first** - Migration verification should exist from day 1

---

## Next Steps

### Immediate (Today)
1. ✅ Create this status document
2. [ ] Get user approval on v2 schema design
3. [ ] Start implementing lookup functions

### This Week
1. [ ] Complete lookup system (Day 1-2)
2. [ ] Complete migration system (Day 3-4)
3. [ ] Redo write conversions (Day 5-7)

### Blockers
- None currently - clear path forward

### Questions for User
1. Approve v2 schema design in [v2-Schema-Stable-Identifiers-Design.md](v2-Schema-Stable-Identifiers-Design.md)?
2. Should we add semantic IDs (e.g., `id = "lucifron"`) or just use indices?
3. Any other edge cases we should consider (unicode, very long names, etc.)?
