# Phase 3B Item 6: Assignment Delta Sync Testing

**Date:** January 21, 2026  
**Status:** Implementation Complete - Testing Required

---

## Changes Made

### 1. Replaced All BroadcastAssignmentUpdate Calls
Migrated from direct `SendAddonMessage` to `OGRH.SyncDelta.RecordAssignmentChange` system:

#### Modified Files
- **OGRH_EncounterMgmt.lua**: 4 call sites replaced
- **OGRH_Core.lua**: Function deprecated with warning wrapper

#### Call Sites Migrated

**Location 1: Player List Drag Assignment (~line 2478)**
- **Before**: Immediate broadcast on drag from player list
- **After**: Records delta change with old value tracking
- **Enhancement**: Now tracks if another player was already in the target slot

**Location 2: Slot Drag Swap (~line 3331-3339)**
- **Before**: Two separate broadcasts (one for each player)
- **After**: Two delta records in same batch (will be sent together)
- **Critical Fix**: Both players now properly assigned to new slots instead of just moving one

**Location 3: Slot Drag Move (~line 3352-3360)**
- **Before**: Two broadcasts (assign target, clear source)
- **After**: Two delta records (both batched together)
- **Enhancement**: Clear operation properly tracked as assignment change

**Location 4: Right-Click Remove (~line 3417)**
- **Before**: Broadcast nil assignment
- **After**: Delta record with old player name tracked
- **Enhancement**: Proper history tracking for who was removed

**Location 5: Core Wrapper (OGRH_Core.lua line 1833)**
- **Before**: Direct `SendAddonMessage` with checksum
- **After**: Deprecated wrapper with red warning + delta sync fallback
- **Purpose**: Backward compatibility while encouraging migration

---

## Test Plan

### Prerequisites
- OG-RaidHelper loaded with Phase 3A delta sync module
- Two or more clients in a raid (one raid lead, one+ raid member)
- Encounter selected with roles configured
- Debug output enabled if available

### Test 1: Simple Player Assignment ✅
**Objective**: Verify basic assignment from player list to empty slot

**Steps**:
1. Open Encounter Planning window
2. Drag player "PlayerA" from player list to empty slot in Role 1, Slot 1
3. Wait 2 seconds (batch delay)
4. Observe chat output on both clients

**Expected Results**:
- Delta change recorded locally
- After 2 seconds, batch flushed
- MessageRouter broadcasts `ASSIGN.DELTA_BATCH`
- Second client receives update and shows PlayerA in Role 1, Slot 1
- No deprecated warning messages

**Validation**:
- [ ] Assignment visible on both clients
- [ ] 2-second batch delay honored
- [ ] No errors in chat

---

### Test 2: Player Swap Between Slots ✅ CRITICAL
**Objective**: Verify BOTH players are assigned to their new slots (not just one moved and other cleared)

**Steps**:
1. Assign "PlayerA" to Role 1, Slot 1
2. Assign "PlayerB" to Role 1, Slot 2
3. Drag PlayerA from Slot 1 onto Slot 2 (swap with PlayerB)
4. Wait 2 seconds
5. Check assignments on both clients

**Expected Results**:
- **PlayerA now in Role 1, Slot 2**
- **PlayerB now in Role 1, Slot 1** ← CRITICAL: Must not be cleared
- Delta batch contains TWO assignment changes
- Both clients show correct swap results

**Validation**:
- [ ] PlayerA in new slot (Slot 2)
- [ ] PlayerB in new slot (Slot 1) ← **MUST PASS**
- [ ] No player unassigned during swap
- [ ] Both changes in same batch (check delta sync state)

---

### Test 3: Player Move (Empty Target Slot)
**Objective**: Verify move operation clears source and assigns target

**Steps**:
1. Assign "PlayerA" to Role 1, Slot 1
2. Drag PlayerA from Slot 1 to empty Slot 3
3. Wait 2 seconds
4. Check assignments

**Expected Results**:
- PlayerA in Role 1, Slot 3
- Role 1, Slot 1 is now empty
- Delta batch contains TWO changes (assign + clear)
- Both clients synchronized

**Validation**:
- [ ] Player moved to new slot
- [ ] Old slot cleared
- [ ] Both operations in same batch
- [ ] No duplicate messages

---

### Test 4: Right-Click Remove
**Objective**: Verify removal properly tracked with old value

**Steps**:
1. Assign "PlayerA" to Role 1, Slot 1
2. Right-click on PlayerA's name
3. Wait 2 seconds
4. Check assignments

**Expected Results**:
- Slot 1 now empty
- Delta record shows oldValue = "PlayerA"
- Both clients synchronized

**Validation**:
- [ ] Player removed from slot
- [ ] Delta record includes old player name
- [ ] Second client updated

---

### Test 5: Rapid Assignments (Batch Testing)
**Objective**: Verify multiple rapid changes batched into single broadcast

**Steps**:
1. Drag PlayerA to Slot 1
2. Immediately drag PlayerB to Slot 2
3. Immediately drag PlayerC to Slot 3
4. Wait 2 seconds
5. Check MessageRouter debug output (if available)

**Expected Results**:
- All three assignments recorded
- Only ONE MessageRouter.Broadcast call after 2 seconds
- Delta batch contains 3 changes
- All clients receive all updates

**Validation**:
- [ ] All three players assigned
- [ ] Single batched message sent
- [ ] No message spam
- [ ] All clients synchronized

---

### Test 6: Combat/Zoning Queue
**Objective**: Verify changes queued when sync blocked

**Steps**:
1. Assign PlayerA to Slot 1
2. Enter combat (use `/script UnitAffectingCombat("player")` to simulate if needed)
3. Try to assign PlayerB to Slot 2
4. Exit combat
5. Wait for auto-flush

**Expected Results**:
- Changes recorded but not sent during combat
- After exiting combat, PLAYER_REGEN_ENABLED event triggers flush
- All queued changes sent
- Clients synchronized

**Validation**:
- [ ] Changes held during combat
- [ ] Auto-flush on combat end
- [ ] No data loss
- [ ] No errors

---

### Test 7: Deprecated Function Warning
**Objective**: Verify old code paths show warnings

**Steps**:
1. Use Lua console to call: `/script OGRH.BroadcastAssignmentUpdate("BWL", "Vaelastrasz", 1, 1, "TestPlayer")`
2. Observe chat output

**Expected Results**:
- **Red warning message**: "DEPRECATED: BroadcastAssignmentUpdate called. Use OGRH.SyncDelta.RecordAssignmentChange instead."
- Assignment still recorded via wrapper
- Delta sync called with proper parameters

**Validation**:
- [ ] Warning displayed in red
- [ ] Assignment still works
- [ ] No errors

---

### Test 8: Player List Drag Over Occupied Slot
**Objective**: Verify dragging from player list onto occupied slot tracks old player

**Steps**:
1. Assign "PlayerA" to Role 1, Slot 1
2. Drag "PlayerB" from player list onto Slot 1 (replacing PlayerA)
3. Wait 2 seconds

**Expected Results**:
- PlayerB now in Slot 1
- Delta record includes oldValue = "PlayerA"
- Both clients show PlayerB in Slot 1
- PlayerA removed from assignments

**Validation**:
- [ ] PlayerB replaces PlayerA
- [ ] Old value tracked
- [ ] Clients synchronized

---

### Test 9: Cross-Role Swap
**Objective**: Verify swaps work across different roles

**Steps**:
1. Assign "PlayerA" to Role 1, Slot 1
2. Assign "PlayerB" to Role 2, Slot 1
3. Drag PlayerA from Role 1, Slot 1 onto Role 2, Slot 1 (swap across roles)
4. Wait 2 seconds

**Expected Results**:
- PlayerA in Role 2, Slot 1
- PlayerB in Role 1, Slot 1
- Both assignments synced
- No errors

**Validation**:
- [ ] Cross-role swap works
- [ ] Both players assigned correctly
- [ ] No role index errors

---

## Regression Testing

### Verify No Breaking Changes
- [ ] Existing encounters still load
- [ ] Player list still filters properly
- [ ] Role containers render correctly
- [ ] Edit button (class priority) still works
- [ ] Assignment numbers (1-9) still work
- [ ] Raid mark icons still work
- [ ] Auto-assign still works
- [ ] Announce button still works
- [ ] Mark players button still works

---

## Performance Metrics

### Expected Improvements
- **Message Count**: 50-70% reduction for rapid edits (batching)
- **Latency**: ~2 second delay for non-urgent changes (acceptable trade-off)
- **Network**: Lower bandwidth usage from fewer messages
- **Reliability**: Higher success rate (OGAddonMsg chunking + retry)

### Measurements
- [ ] Count messages sent during 10 rapid assignments
  - **Old System**: ~10 messages
  - **New System**: ~1 batched message (expected)
- [ ] Verify no duplicate messages
- [ ] Verify no lost assignments

---

## Known Issues / Edge Cases

### Potential Issues to Watch For
1. **Batch delay feels slow**: 2 seconds may feel sluggish for single edits
   - **Mitigation**: Could add "flush on idle" or reduce delay to 1 second
2. **Old code using BroadcastAssignmentUpdate**: Will show deprecation warnings
   - **Action**: Grep for remaining usage and migrate
3. **Delta sync disabled**: If module not loaded, changes won't sync
   - **Action**: Ensure OGRH_SyncDelta.lua in TOC load order

### Error Scenarios
- [ ] Delta sync module not loaded - verify graceful degradation
- [ ] MessageRouter not loaded - verify error handling
- [ ] Serialize fails on delta data - verify error message
- [ ] Network timeout - verify retry logic (OGAddonMsg layer)

---

## Success Criteria

### Must Pass
- ✅ All 9 core tests pass
- ✅ Test 2 (swap) MUST show both players assigned to new slots
- ✅ No errors or warnings in normal operation
- ✅ Clients stay synchronized
- ✅ Regression tests pass

### Nice to Have
- Message count reduction verified
- Performance feels responsive
- No user complaints about 2-second delay

---

## Rollback Plan

If critical issues found:

1. **Immediate**: Revert OGRH_EncounterMgmt.lua changes
2. **Restore**: `OGRH.BroadcastAssignmentUpdate` to original implementation
3. **Test**: Verify old system still works
4. **Analyze**: Debug issues before re-attempting migration

### Revert Command
```bash
git checkout HEAD -- OGRH_EncounterMgmt.lua OGRH_Core.lua
```

---

## Next Steps After Testing

1. **If all tests pass**:
   - Mark Phase 3B Item 6 as complete
   - Update migration roadmap
   - Move to Phase 3B Item 7 (Encounter Sync Fallback)

2. **If issues found**:
   - Document issues in this file
   - Create GitHub issues if applicable
   - Fix and re-test

3. **Future enhancements**:
   - Consider reducing batch delay from 2s to 1s if feedback says it's too slow
   - Add "Force Flush" button in UI for immediate sync
   - Add visual indicator when changes are pending flush
