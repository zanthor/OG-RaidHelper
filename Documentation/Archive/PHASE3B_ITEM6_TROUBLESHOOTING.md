# Delta Sync Troubleshooting Guide

**Date:** January 21, 2026  
**Issue:** No updates reaching other clients after assignment changes

---

## Problem Identified

**Root Cause**: The `ASSIGN.DELTA_BATCH` message handler in OGRH_MessageRouter.lua was not correctly processing encounter assignment changes. 

### Specific Issues Fixed

1. **Handler Expected Wrong Structure**
   - Handler was looking for generic `OGRH.SetPlayerAssignment()` calls
   - Our EncounterMgmt code sends `assignmentType = "ENCOUNTER_ROLE"` with nested data
   - Handler needed to extract and apply encounter-specific assignment data

2. **No Debug Output**
   - No visibility into what was being sent or received
   - Made debugging impossible

---

## Changes Made

### 1. Fixed ASSIGN.DELTA_BATCH Handler (OGRH_MessageRouter.lua)

**Before**: Generic assignment handling that didn't understand encounter structure

**After**: 
- Properly extracts encounter assignment data from `change.newValue` table
- Initializes nested `OGRH_SV.encounterAssignments` structure
- Applies assignments to correct raid/encounter/role/slot
- Refreshes both Encounter Planning UI and RolesUI
- **Debug output** showing every change processed

### 2. Added Debug Output (OGRH_SyncDelta.lua)

**Sender Side**:
- `RecordAssignmentChange()` now logs when changes are recorded
- Shows pending change count
- Reports if sync is blocked (combat/zoning)
- `FlushChangeBatch()` logs:
  - When flush starts
  - How many changes in batch
  - Serialized size
  - If MessageRouter.Broadcast succeeds

**Receiver Side (in MessageRouter)**:
- Logs when delta batch received
- Shows sender name and change count
- Logs each individual change applied
- Reports UI refresh operations
- Confirms when batch processing complete

---

## How to Test

### Step 1: Reload Both Clients
```
/reload
```

### Step 2: Make an Assignment
1. Open Encounter Planning on raid lead client
2. Drag a player to a role slot
3. **Watch for debug output in chat**

### Expected Debug Output (Sender)

```
[OGRH-Delta] Recorded assignment change: PlayerName (R1S1) (pending: 1)
[OGRH-Delta] Flushing 1 pending changes...
[OGRH-Delta] Serialized delta batch: 234 bytes
[OGRH-Delta] Delta batch sent via MessageRouter
```

### Expected Debug Output (Receiver)

```
[OGRH] Received delta batch from SenderName with 1 changes
[OGRH]  - Encounter assignment: BWL/Vaelastrasz Role 1 Slot 1 = PlayerName
[OGRH]  -> Refreshed Encounter Planning UI
[OGRH] Delta batch processing complete
```

### Step 3: Verify Assignment Synced
- Open Encounter Planning on second client
- Select same raid/encounter
- **PlayerName should appear in Role 1, Slot 1**

---

## Debugging Commands

### Check if Delta Sync Module Loaded
```lua
/script if OGRH.SyncDelta then DEFAULT_CHAT_FRAME:AddMessage("Delta Sync: LOADED") else DEFAULT_CHAT_FRAME:AddMessage("Delta Sync: NOT LOADED") end
```

### Check Pending Changes
```lua
/script if OGRH.SyncDelta and OGRH.SyncDelta.State then DEFAULT_CHAT_FRAME:AddMessage("Pending: " .. table.getn(OGRH.SyncDelta.State.pendingChanges) .. " Offline: " .. table.getn(OGRH.SyncDelta.State.offlineQueue)) else DEFAULT_CHAT_FRAME:AddMessage("Delta Sync State not found") end
```

### Force Flush Pending Changes
```lua
/script if OGRH.SyncDelta and OGRH.SyncDelta.ForceFlush then OGRH.SyncDelta.ForceFlush() else DEFAULT_CHAT_FRAME:AddMessage("ForceFlush not available") end
```

### Check MessageRouter Loaded
```lua
/script if OGRH.MessageRouter and OGRH.MessageRouter.Broadcast then DEFAULT_CHAT_FRAME:AddMessage("MessageRouter: LOADED") else DEFAULT_CHAT_FRAME:AddMessage("MessageRouter: NOT LOADED") end
```

### Check Current Encounter
```lua
/script local r, e = OGRH.GetCurrentEncounter(); DEFAULT_CHAT_FRAME:AddMessage("Raid: " .. (r or "nil") .. " Encounter: " .. (e or "nil"))
```

### Dump Assignment Data
```lua
/script if OGRH_SV.encounterAssignments then local count = 0; for r, raids in pairs(OGRH_SV.encounterAssignments) do for e, enc in pairs(raids) do for role, slots in pairs(enc) do for slot, player in pairs(slots) do count = count + 1; end; end; end; end; DEFAULT_CHAT_FRAME:AddMessage("Total assignments: " .. count) else DEFAULT_CHAT_FRAME:AddMessage("No assignment data") end
```

---

## Common Issues

### Issue: "Cannot sync now: In combat"
**Cause**: UnitAffectingCombat("player") returns true  
**Solution**: Wait for combat to end, changes will auto-flush via PLAYER_REGEN_ENABLED event

### Issue: "Cannot sync now: Not in raid"
**Cause**: GetNumRaidMembers() returns 0  
**Solution**: Changes moved to offline queue, will flush when raid joined

### Issue: "Cannot sync now: Zoning"
**Cause**: OGRH.SyncDelta.State.isZoning is true  
**Solution**: Wait for PLAYER_ENTERING_WORLD event to clear flag

### Issue: No debug output at all
**Possible Causes**:
1. **OGRH_SyncDelta.lua not loaded** - Check TOC file load order
2. **RecordAssignmentChange not being called** - Check EncounterMgmt code
3. **MessageRouter not loaded** - Check TOC file load order
4. **Serialize function failing** - Check OGRH.Serialize exists

### Issue: Debug output shows "Flushing" but no "Received" on other client
**Possible Causes**:
1. **OGAddonMsg not loaded** - Check _OGAddonMsg in TOC
2. **Message handler not registered** - Check MessageRouter initialization
3. **Channel mismatch** - Should be "RAID" channel
4. **Not in same raid group** - Verify raid roster

### Issue: "Received delta batch" but no UI update
**Possible Causes**:
1. **Different raid/encounter selected** - Both clients must have same encounter open
2. **RefreshRoleContainers not defined** - Check OGRH_EncounterFrame loaded
3. **Assignment data structure mismatch** - Check serialization/deserialization

---

## Rollback Instructions

If issues persist and you need to revert:

### Step 1: Revert Code Changes
```bash
git checkout HEAD -- OGRH_MessageRouter.lua OGRH_SyncDelta.lua OGRH_EncounterMgmt.lua OGRH_Core.lua
```

### Step 2: Reload Clients
```
/reload
```

### Step 3: Verify Old System Works
- Try making an assignment
- Check if `BroadcastAssignmentUpdate` warnings appear (expected with old code)

---

## Next Steps

### If Debug Output Shows Messages Sent/Received:
✅ **System is working!** 
- Remove debug output after testing complete
- Mark Phase 3B Item 6 as tested and validated

### If No Debug Output:
❌ **Deeper issue exists**
1. Check TOC load order
2. Verify all modules loaded
3. Check for Lua errors on load
4. Try `/console scriptErrors 1` to enable error reporting

### If Messages Received But UI Not Updating:
🔧 **UI refresh issue**
1. Check if Encounter Planning window open
2. Verify same raid/encounter selected
3. Check RefreshRoleContainers function exists
4. Manually refresh by closing/reopening window

---

## Success Criteria

✅ **Test Passed When**:
1. Debug output shows "Recorded assignment change"
2. Debug output shows "Flushing X pending changes"
3. Debug output shows "Delta batch sent"
4. **Receiver shows** "Received delta batch"
5. **Receiver shows** "Encounter assignment: ..."
6. **Receiver shows** "Delta batch processing complete"
7. Assignment visible in UI on both clients
8. **No errors in chat**

---

## Debug Output Removal

Once testing complete and system validated, remove debug output:

### OGRH_SyncDelta.lua
- Remove `DEFAULT_CHAT_FRAME:AddMessage` calls from:
  - `RecordAssignmentChange()`
  - `FlushChangeBatch()`

### OGRH_MessageRouter.lua
- Remove `DEFAULT_CHAT_FRAME:AddMessage` calls from:
  - `ASSIGN.DELTA_BATCH` handler
  - Keep only critical error messages

### Commit Message
```
Phase 3B Item 6: Remove debug output from delta sync

- Production-ready after testing validation
- Keeps critical error messages
- Removes verbose change logging
```

---

## Contact

If issues persist after following this guide, document:
1. Full debug output from both clients
2. TOC load order
3. Loaded module list (`/script for k,v in pairs(OGRH.LoadedModules) do DEFAULT_CHAT_FRAME:AddMessage(k) end`)
4. Any Lua errors
5. Steps to reproduce

And create a GitHub issue with this information.
