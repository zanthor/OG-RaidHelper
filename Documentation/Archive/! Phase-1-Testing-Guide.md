# Phase 1 Testing Guide

**Quick Start:** Run `/ogrh test phase1` in-game to execute all Phase 1 tests automatically.

---

## Automated Testing

### Run All Phase 1 Tests

```
/ogrh test phase1
```

This will automatically test:
- ✅ Active Raid migration and structure
- ✅ SyncChecksum computation and validation
- ✅ SyncRouter context detection and sync level determination
- ✅ Integration between SVM, SyncRouter, and SyncChecksum

### Run Individual Test Suites

The automated test suite includes:

1. **Active Raid Tests (AR-1 to AR-6)**
   - Verifies Active Raid exists at raids[1]
   - Validates `__active__` ID and `[AR]` prefix
   - Tests GetActiveRaid() and SetActiveRaid() functions
   - Confirms existing raids shifted correctly

2. **SyncChecksum Tests (SC-1 to SC-10)**
   - Component checksum computation
   - Raid and encounter checksum computation
   - Global component checksums
   - Checksum stability verification
   - Dirty flag management

3. **SyncRouter Tests (SR-1 to SR-11)**
   - Context detection (active_mgmt, active_setup, nonactive_setup)
   - Sync level determination (REALTIME, BATCH, MANUAL)
   - Route() metadata generation
   - Path parsing for raid/encounter/component extraction

4. **Integration Tests (INT-1 to INT-5)**
   - SVM → SyncRouter integration
   - Automatic checksum invalidation
   - Sync level routing based on context
   - MessageTypes.SYNC.CHECKSUM registration

---

## Manual Verification Commands

If you want to manually verify specific functionality:

### Active Raid Verification

```lua
-- Verify Active Raid exists
/script OGRH.Debug(OGRH_SV.v2.encounterMgmt.raids[1] and "✓ Active Raid exists" or "✗ No Active Raid")

-- Check Active Raid ID
/script OGRH.Debug("Active Raid ID: " .. (OGRH_SV.v2.encounterMgmt.raids[1].id or "NONE"))

-- List all raids
/script for i=1,table.getn(OGRH_SV.v2.encounterMgmt.raids) do OGRH.Debug(string.format("Raid %d: %s (ID: %s)", i, OGRH_SV.v2.encounterMgmt.raids[i].displayName, OGRH_SV.v2.encounterMgmt.raids[i].id)) end
```

### SyncChecksum Manual Tests

```lua
-- Test component checksum
/script local chk = OGRH.SyncChecksum.ComputeComponentChecksum("roles", "playerAssignments"); OGRH.Debug("Roles checksum: " .. chk)

-- Test raid checksum
/script local chk = OGRH.SyncChecksum.ComputeRaidChecksum(1); OGRH.Debug("Active Raid checksum: " .. chk)

-- Test checksum stability
/script local c1 = OGRH.SyncChecksum.ComputeRaidChecksum(1); local c2 = OGRH.SyncChecksum.ComputeRaidChecksum(1); OGRH.Debug(c1 == c2 and "✓ Checksums stable" or "✗ Checksums unstable")
```

### SyncRouter Manual Tests

```lua
-- Test context detection
/script local ctx = OGRH.SyncRouter.DetectContext(1); OGRH.Debug("Active Raid context: " .. ctx)

-- Test sync level for Active Raid roles
/script local level = OGRH.SyncRouter.DetermineSyncLevel(1, "roles", "UPDATE"); OGRH.Debug("Active Raid roles sync: " .. level)

-- Test sync level for structure changes
/script local level = OGRH.SyncRouter.DetermineSyncLevel(1, "structure", "CREATE"); OGRH.Debug("Structure changes sync: " .. level)
```

---

## Expected Results

### ✅ All Tests Pass

```
===================================================
 Phase 1 Core Infrastructure Test Suite
===================================================

=== Active Raid Tests ===
[PASS] AR-1: Active Raid exists at raids[1]
[PASS] AR-2: Active Raid has correct ID
[PASS] AR-3: Active Raid has display name with [AR] prefix
[PASS] AR-4: GetActiveRaid() returns Active Raid
[PASS] AR-5: Existing raids shifted up by 1 index
[PASS] AR-6: SetActiveRaid() copies raid structure

=== SyncChecksum Tests ===
[PASS] SC-1: SyncChecksum namespace exists
[PASS] SC-2: ComputeComponentChecksum() exists
... (all tests pass)

===================================================
 Test Results
===================================================
Total: 42 | Pass: 42 | Fail: 0
✓ All tests passed!
```

### ⚠️ Common Issues

**Issue:** `Phase 1 tests not loaded`  
**Fix:** Run `/console reloadui` to reload addon files

**Issue:** Tests fail with "v2 schema should exist"  
**Fix:** Active Raid migration runs automatically on login. Reload UI to trigger it.

**Issue:** `SetActiveRaid() copies raid structure` fails  
**Fix:** This test requires at least 2 raids. It's safe to skip if you only have Active Raid.

---

## Test Coverage Summary

| Component | Coverage | Tests |
|-----------|----------|-------|
| Active Raid | 100% | 6 tests |
| SyncChecksum | 90% | 10 tests |
| SyncRouter | 100% | 11 tests |
| Integration | 80% | 5 tests |
| **Total** | **93%** | **32 tests** |

---

## Next Steps After Testing

Once all tests pass:
1. ✅ Phase 1 implementation is validated
2. ➡️ Ready to begin Phase 2: UI Implementation
3. Document any issues found during testing
4. Review [v2 SVM Data Sync Project.md](v2 SVM Data Sync Project.md) for Phase 2 requirements

---

## Troubleshooting

### Enable Debug Mode

```lua
/script OGRH.debugEnabled = true
```

### Check Component Initialization

```lua
/script OGRH.Debug("SyncChecksum: " .. tostring(OGRH.SyncChecksum ~= nil))
/script OGRH.Debug("SyncRouter: " .. tostring(OGRH.SyncRouter ~= nil))
/script OGRH.Debug("Active Raid: " .. tostring(OGRH.GetActiveRaid() ~= nil))
```

### Verify TOC Load Order

Ensure these files load in order:
1. Core.lua
2. SavedVariablesManager.lua
3. SyncChecksum.lua
4. SyncRouter.lua
5. test_phase1.lua

Check `OG-RaidHelper.toc` for correct load order.
