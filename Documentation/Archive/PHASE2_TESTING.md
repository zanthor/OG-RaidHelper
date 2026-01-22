# Phase 2: Core Sync Replacement - Testing Guide

## What Phase 2 Delivers (INFRASTRUCTURE ONLY)

Phase 2 creates the **framework** for OGAddonMsg-based sync. It does NOT integrate with UI or add automatic triggers.

### Components Added
1. `OGRH_Sync_v2.lua` - New sync system using OGAddonMsg
2. Checksum broadcasting system (every 30 seconds)
3. Full sync request/response infrastructure
4. Delta sync infrastructure (not yet integrated)

### Components Modified
1. `OGRH_Core.lua` - `OGRH.BroadcastFullSync()` now calls new system

### What Does NOT Work Yet
- ❌ Automatic sync on UI changes (Phase 3)
- ❌ Delta sync application (stub only)
- ❌ Direct UI integration
- ❌ Individual message type migrations (Phase 3)

---

## Test Environment Setup

**Requires:**
- 2 WoW clients in same raid
- Client A: Raid Leader (you)
- Client B: Raid member or assist

**Initial Setup:**
```lua
-- On both clients, run:
/reload

-- Verify initialization
-- You should see:
-- [OGRH-Sync] Initialized
-- [OGRH-Sync] Broadcasting checksum: <hash> (v<version>)
```

---

## Test 1: Checksum Broadcasting

**Purpose:** Verify automatic checksum polling works without double-broadcast

**Steps:**
1. `/reload` on both clients
2. Wait 30 seconds
3. Observe chat messages

**Expected Output (Client A):**
```
[OGRH-Sync] Initialized
[OGRH-Sync] Broadcasting checksum: 450094938 (v0)
[OGRH-Sync] Received checksum from <ClientB>: 450094938 (v0)
[OGRH-Sync] My checksum: 450094938 (v0)
-- [30 seconds later]
[OGRH-Sync] Broadcasting checksum: 450094938 (v0)
[OGRH-Sync] Received checksum from <ClientB>: 450094938 (v0)
```

**Success Criteria:**
- ✅ Only ONE broadcast per 30 seconds (not double)
- ✅ Checksums match between clients
- ✅ Version numbers match

**Failure Modes:**
- ❌ Double broadcasts = polling loop issue
- ❌ No received checksums = OGAddonMsg not working
- ❌ Checksum mismatch = data desync

---

## Test 2: Infrastructure Integrity

**Purpose:** Verify Phase 1 and Phase 2 systems loaded correctly

**Run on both clients:**
```lua
/run DEFAULT_CHAT_FRAME:AddMessage("MessageTypes: " .. (OGRH.MessageTypes and "OK" or "MISSING"))
/run DEFAULT_CHAT_FRAME:AddMessage("Permissions: " .. (OGRH.Permissions and "OK" or "MISSING"))
/run DEFAULT_CHAT_FRAME:AddMessage("Versioning: " .. (OGRH.Versioning and "OK" or "MISSING"))
/run DEFAULT_CHAT_FRAME:AddMessage("MessageRouter: " .. (OGRH.MessageRouter and "OK" or "MISSING"))
/run DEFAULT_CHAT_FRAME:AddMessage("Sync v2: " .. (OGRH.Sync and "OK" or "MISSING"))
/run DEFAULT_CHAT_FRAME:AddMessage("Sync State: " .. (OGRH.Sync.State and "OK" or "MISSING"))
```

**Expected Output:**
```
MessageTypes: OK
Permissions: OK
Versioning: OK
MessageRouter: OK
Sync v2: OK
Sync State: OK
```

**Failure:** Any "MISSING" = load order issue in TOC

---

## Test 3: Manual Full Sync (OLD System Integration)

**Purpose:** Verify old `BroadcastFullSync()` calls new system

**Setup:**
1. Client A: Create raid structure (raid + encounter + roles)
2. Client B: Has empty structure or different data
3. Client A: Make them the current encounter

**Trigger Old Sync (Client A):**
```lua
-- This should trigger the NEW sync system
/run if OGRH.BroadcastFullSync then OGRH.BroadcastFullSync("YourRaidName", "YourEncounterName") end
```

**Expected Output (Client A):**
```
[DEBUG] Calling [OGRH.Sync.BroadcastFullSync]
[DEBUG] Permission check passed
[DEBUG] In raid with N members
[DEBUG] Serialized type: string, length: XXXXX
About to broadcast, msgType: OGRH_SYNC_RESPONSE_FULL
OGAddonMsg: Network queue at XX.Xs for XXs (informational - shows throttling during large transfer)
[OGRH] Structure broadcast complete
```

**Expected Output (Client B):**
```
[DEBUG] OnFullSyncResponse called: sender=<ClientA>
[DEBUG] Attempting to deserialize...
[DEBUG] Deserialized successfully, applying data...
[OGRH] Full sync completed from <ClientA>
```

**Success Criteria:**
- ✅ Client A broadcasts using OGAddonMsg (710 chunks for ~100KB data)
- ✅ Client B receives all chunks (710 sent, 710 rcvd, 1 message reassembled)
- ✅ Client B deserializes and applies data
- ✅ Network queue warnings are informational (throttling system working correctly)
- ✅ UI refreshes with new data on Client B

**Failure Modes:**
- ❌ "Must be in raid" = not in raid group
- ❌ No broadcast = BroadcastFullSync not calling new system
- ❌ Client B doesn't receive = OGAddonMsg routing issue

---

## Test 4: Checksum Mismatch Detection

**Purpose:** Verify system detects when clients have different data

**Setup:**
1. Both clients in raid, synced data
2. Client B: Manually corrupt data

**Corrupt Data (Client B ONLY):**
```lua
-- Modify structure to create mismatch
/run OGRH_SV.encounterMgmt.raids[1].name = "CORRUPTED"
/run DEFAULT_CHAT_FRAME:AddMessage("Data corrupted for testing")
```

**Wait for Next Checksum Broadcast (30 seconds):**

**Expected Output (Client A):**
```
[OGRH-Sync] Received checksum from <ClientB>: <different_hash> (v0)
[OGRH-Sync] My checksum: <original_hash> (v0)
[cffffff00[OGRH]|r CHECKSUM MISMATCH with <ClientB>!
[cffff0000[OGRH]|r Checksum mismatch with <ClientB> at same version v0!
[cff00ff00[OGRH]|r Pushing to resolve corruption
```

**Expected Output (Client B):**
```
[OGRH] Received full sync from <ClientA>
```

**Success Criteria:**
- ✅ Mismatch detected within 30 seconds
- ✅ Admin (Client A) auto-pushes to fix
- ✅ Client B data restored to match

**Restore Data (Client B):**
```lua
/reload
```

---

## Test 5: Permission Check

**Purpose:** Verify permission system blocks non-admins

**Client B (Non-Admin) Attempts Broadcast:**
```lua
/run if OGRH.Sync and OGRH.Sync.BroadcastFullSync then OGRH.Sync.BroadcastFullSync() end
```

**Expected Output (Client B):**
```
[cffff0000[OGRH]|r Only admin can broadcast structure
```

**Success Criteria:**
- ✅ Non-admin blocked from broadcasting
- ✅ Error message shown

---

## Test 6: Version Increment

**Purpose:** Verify version tracking works

**Client A:**
```lua
-- Check current version
/run DEFAULT_CHAT_FRAME:AddMessage("Current version: " .. OGRH.Versioning.GetGlobalVersion())

-- Increment version
/run local v = OGRH.Versioning.IncrementDataVersion("TEST", "Manual test"); DEFAULT_CHAT_FRAME:AddMessage("New version: " .. v)

-- Verify increment
/run DEFAULT_CHAT_FRAME:AddMessage("Current version: " .. OGRH.Versioning.GetGlobalVersion())
```

**Expected Output:**
```
Current version: 0
New version: 1
Current version: 1
```

**Success Criteria:**
- ✅ Version increments by 1
- ✅ Persists across function calls

---

## Test 7: Message Router

**Purpose:** Verify message routing and OGAddonMsg integration

**Client A:**
```lua
-- Send test broadcast
/run OGRH.MessageRouter.Broadcast(OGRH.MessageTypes.SYNC.CHECKSUM_STRUCTURE, json.encode({test = true, sender = UnitName("player")}), {priority = "LOW"})
```

**Expected Output (Client B):**
```
-- Should trigger OGRH.Sync.OnChecksumReceived
-- Will see error because we sent invalid checksum data, but proves routing works
```

**Success Criteria:**
- ✅ Message sent via OGAddonMsg
- ✅ Received on Client B
- ✅ Routed to correct handler

---

## Test 8: OGAddonMsg Callback

**Purpose:** Verify OGAddonMsg success/failure callbacks work

**Client A:**
```lua
/run OGRH.MessageRouter.Broadcast(OGRH.MessageTypes.SYNC.CHECKSUM_STRUCTURE, json.encode({checksum = "TEST", version = 999, sender = UnitName("player")}), {priority = "LOW", onSuccess = function() DEFAULT_CHAT_FRAME:AddMessage("CALLBACK SUCCESS") end})
```

**Expected Output (Client A):**
```
CALLBACK SUCCESS
```

**Success Criteria:**
- ✅ Callback fires after send
- ✅ No errors

---

## Test 9: Large Data Transfer

**Purpose:** Verify OGAddonMsg handles chunking of large payloads

**Setup:**
1. Create large raid structure (multiple raids, encounters, roles)

**Client A:**
```lua
-- Force full sync with large data
/run if OGRH.Sync and OGRH.Sync.BroadcastFullSync then OGRH.Sync.BroadcastFullSync() end
```

**Expected:**
- ✅ Data sent in chunks (OGAddonMsg handles automatically)
- ✅ Client B receives complete data
- ✅ No truncation errors

---

## Debugging Commands

**Check Sync State:**
```lua
/run local s = OGRH.Sync.State; DEFAULT_CHAT_FRAME:AddMessage("Initialized: " .. tostring(s.initialized))
/run local s = OGRH.Sync.State; DEFAULT_CHAT_FRAME:AddMessage("Last checksum: " .. s.lastChecksumBroadcast)
```

**Force Checksum Broadcast:**
```lua
/run if OGRH.Sync and OGRH.Sync.BroadcastChecksum then OGRH.Sync.BroadcastChecksum() end
```

**Check Checksum:**
```lua
/run if OGRH.Sync then DEFAULT_CHAT_FRAME:AddMessage("Checksum: " .. OGRH.Sync.ComputeCurrentChecksum()) end
```

**Check Version:**
```lua
/run DEFAULT_CHAT_FRAME:AddMessage("Version: " .. OGRH.Versioning.GetGlobalVersion())
```

**List Registered Handlers:**
```lua
/run for msgType, handler in pairs(OGRH.MessageRouter.State.handlers) do DEFAULT_CHAT_FRAME:AddMessage(msgType .. " -> " .. tostring(handler)) end
```

---

## Known Limitations (Phase 2)

1. **No UI integration** - Changes made in UI don't auto-sync (Phase 3)
2. **Delta sync incomplete** - Infrastructure exists but ApplyDelta() is stub
3. **Manual triggers only** - Must call BroadcastFullSync() explicitly
4. **Old message types still exist** - Not migrated yet (Phase 3)

---

## Success Criteria for Phase 2 Completion

✅ **PHASE 2 COMPLETE** ✅

- [x] Checksum broadcasts every 30 seconds (single, not double)
- [x] Checksum mismatch detection works
- [x] Manual sync commands trigger new system
- [x] Permission checks block non-admins
- [x] Version tracking increments correctly
- [x] OGAddonMsg integration functional
- [x] Large data transfers complete successfully (710 chunks, ~100KB)
- [x] No Lua errors on load or during sync
- [x] Message reassembly works (timeout fixed to use lastReceived)
- [x] Wildcard handler registration connects OGAddonMsg to MessageRouter
- [x] Data Management UI created (Load Defaults, Import/Export, Push Structure)
- [x] Checksum system uses complete algorithm (includes advanced settings)
- [x] Auto-push disabled - manual sync on demand only
- [x] Clean output - debug messages removed

---

## Next Phase Preview

**Phase 3 will:**
- Migrate individual message types from old system
- Add automatic sync triggers to UI components
- Remove old sync code completely
- Integrate delta sync for assignments
