# Phase 3 Testing Guide - SyncRepair Module

This guide covers testing the Phase 3 implementation of the Sync Optimization system.

---

## Prerequisites

Before testing Phase 3, ensure:
1. **Phase 1 Complete**: Hierarchical checksums working (`/ogrh checksum`)
2. **Phase 2 Complete**: Session management working (`/ogrh session`)
3. **Active Raid**: Must have an active raid configured with encounters and roles
4. **In-Game**: Must be logged into Turtle WoW with OG-RaidHelper loaded

## Who Should Run This Test?

**Primary: ADMIN (Raid Leader/Assistant)**
- The test primarily validates **admin-side functions**: building packets, priority ordering
- Admin is responsible for initiating repairs and sending packets to clients

**Secondary: CLIENTS (Raid Members)**
- Clients can also run the test to verify their modules loaded correctly
- Validation checksums and adaptive pacing work for both admin and clients
- In production, clients will **apply** packets (not build them)

**Recommendation:** Run `/ogrh repair` on **admin first**, then optionally on a client to verify both sides.

---

## Quick Test Command

```
/ogrh repair
```

This command tests all Phase 3 functionality:
- ✅ Adaptive pacing (queue depth monitoring)
- ✅ Validation checksums (compute and compare)
- ✅ Priority ordering (selected encounter first)
- ✅ Packet builders (all 4 layers)

---

## What to Expect

### 1. Queue Depth and Adaptive Pacing

```
Queue Depth: 0 messages
Adaptive Delay: 0.050s
```

**Expected Behavior:**
- Queue depth comes from `OGAddonMsg.stats.queueDepth`
- Delay adjusts based on queue pressure:
  - **0-5 messages**: 0.05s (clear)
  - **6-15 messages**: 0.1s (light)
  - **16-30 messages**: 0.2s (moderate)
  - **31-50 messages**: 0.5s (heavy)
  - **51+ messages**: 1.0s (critical)

**How to Test Different Queue States:**
- Normal state: 0 messages, 0.05s delay
- Under load: Send multiple messages to trigger higher delays

---

### 2. Validation Checksums

```
Computing validation checksums...
  Structure: abc123def456...
  Encounter[1]: 789ghi012jkl...
  Encounter[2]: mno345pqr678...
  Role[1][1]: stu901vwx234...
  Role[1][2]: yz5678abc901...
```

**Expected Behavior:**
- Structure checksum: Single hash for raid metadata
- Encounter checksums: One per encounter (tests first 2)
- Role checksums: Per-encounter, per-role (tests first 2 roles of encounter 1)
- All checksums should be long hexadecimal strings

**Validation Test:**
```
Self-Validation: PASS
```

The command compares checksums with themselves, should always pass.

---

### 3. Repair Priority Ordering

```
Repair Priority (selected: 2):
  [1] Encounter 2    <-- Selected encounter comes first
  [2] Encounter 1    <-- Remaining encounters sorted
  [3] Encounter 3
```

**Expected Behavior:**
- Selected encounter (2) appears first in priority list
- Remaining encounters (1, 3) appear in sorted order
- This ensures admins see their selected encounter repaired first

**Test Scenario:**
The test uses:
- Selected: Encounter 2
- Failed encounters: 1, 3, 2 (unordered)
- Failed roles: Encounter 2, Role 1
- Failed assignments: Encounter 1, Roles 1-2

Priority should be: [2, 1, 3]

---

### 4. Packet Builders

```
Testing Packet Builders:
  Structure packet: type=STRUCTURE, layer=1
  Encounters packets: 1 packet(s)
  Roles packets: 1 packet(s)
  Assignments packets: 1 packet(s)
```

**Expected Behavior:**
- **Structure packet**: Single packet with raid metadata only
- **Encounters packets**: Array of packets (1 per encounter index)
- **Roles packets**: Array of packets (1 per role index)
- **Assignments packets**: Array of packets (1 per role index)

**Admin vs Client:**
- ⚙️ **Admin builds** packets (tested here)
- 📥 **Clients apply** packets (tested in manual section below)

**Packet Structure:**
Each packet contains:
```lua
{
    type = "STRUCTURE"/"ENCOUNTER"/"ROLE"/"ASSIGNMENTS",
    layer = 1-4,
    raidName = "Molten Core",
    encounterIndex = 1,  -- for layers 2-4
    roleIndex = 1,       -- for layers 3-4
    data = {...},        -- layer-specific data
    timestamp = GetTime()
}
```

---

## Manual Testing Functions

You can test individual functions via Lua:

### Test Adaptive Pacing

```lua
/script OGRH.Msg("Queue: " .. OGRH.SyncRepair.GetQueueDepth())
/script OGRH.SyncRepair.UpdateAdaptiveDelay()
/script OGRH.Msg("Delay: " .. OGRH.SyncRepair.State.currentDelay)
```

### Test Validation Checksums

```lua
/script local layers = {structure = true, encounters = {1}}
/script local checksums = OGRH.SyncRepair.ComputeValidationChecksums("Molten Core", layers)
/script OGRH.Msg("Structure: " .. (checksums.structure or "nil"))
```

### Test Priority Ordering

```lua
/script local failed = {encounters = {3, 1, 2}}
/script local priority = OGRH.SyncRepair.DetermineRepairPriority("Molten Core", 2, failed)
/script for i=1, table.getn(priority) do OGRH.Msg(priority[i]) end
```

### Test Packet Building

**Who:** Admin (builds packets to send)

```lua
/script local pkt = OGRH.SyncRepair.BuildStructurePacket("Molten Core")
/script OGRH.Msg("Type: " .. pkt.type .. ", Layer: " .. pkt.layer)
```

### Test Packet Application

**Who:** Client (applies received packets) or Admin (for testing)

```lua
/script local pkt = OGRH.SyncRepair.BuildStructurePacket("Molten Core")
/script local success = OGRH.SyncRepair.ApplyStructurePacket(pkt)
/script OGRH.Msg("Applied: " .. (success and "YES" or "NO"))
```

**Note:** In production, clients receive packets over network and apply them. This test simulates by building then immediately applying.

---

## Troubleshooting

### "SyncRepair or SyncChecksum module not loaded"

**Cause:** Modules didn't load properly.

**Fix:**
1. Check `OG-RaidHelper.toc` includes:
   ```
   _Infrastructure\SyncChecksum.lua
   _Infrastructure\SyncSession.lua
   _Infrastructure\SyncRepair.lua
   ```
2. Type `/reload` to reload UI
3. Look for load errors in chat

### "No active raid found"

**Cause:** No raid configured.

**Fix:**
1. Open OG-RaidHelper main window
2. Create or select a raid
3. Add at least one encounter with roles

### Checksum Returns "nil"

**Cause:** Raid structure incomplete or malformed.

**Fix:**
1. Ensure raid has:
   - Valid name
   - At least one encounter
   - At least one role per encounter
2. Run `/ogrh checksum` to verify Phase 1 working

### Queue Depth Always 0

**Expected:** This is normal when not actively sending messages.

**To Test Under Load:**
- Have multiple addon users in raid
- Make changes to trigger sync
- Queue depth will increase temporarily

### Priority Ordering Wrong

**Verify:**
1. Selected encounter index matches expected
2. Failed layers contain correct indices
3. Check for duplicate encounters in failed layers

---

## Integration Tests (Future)

Phase 3 functions are building blocks. Full integration testing requires:

1. **Phase 4 (UI)**: Visual feedback during repairs
2. **Phase 5 (Integration)**: Connect to SyncIntegrity.lua
3. **Phase 6 (Network)**: Message handlers for packet transmission
4. **Phase 7 (E2E)**: Full admin → client repair flow

---

## Success Criteria

Phase 3 implementation is successful if:

- ✅ `/ogrh repair` runs without errors
- ✅ Queue depth reports correctly (0 when idle)
- ✅ Adaptive delay calculates correctly based on queue
- ✅ Validation checksums compute for all 4 layers
- ✅ Self-validation always passes
- ✅ Priority ordering puts selected encounter first
- ✅ All 4 packet builders create valid packets
- ✅ Packet appliers successfully apply packets

---

## Next Steps After Phase 3

Once Phase 3 testing passes:

1. **Phase 4**: Implement SyncRepairUI.lua
   - Admin repair panel (progress tracking)
   - Client repair panel (countdown, ETA)
   - Waiting panel (join-during-repair)
   - Admin button tooltip (sync status)

2. **Phase 5**: Integration with SyncIntegrity.lua
   - Suppress checksum broadcasts during repairs
   - Buffer repair requests
   - Resume broadcasts after finalization

3. **Phase 6**: Message handlers
   - SYNC_REPAIR_START
   - SYNC_REPAIR_PACKET_*
   - SYNC_REPAIR_VALIDATION
   - SYNC_REPAIR_COMPLETE

4. **Phase 7**: End-to-end testing
   - Multi-user repair scenarios
   - Network load testing
   - Error handling and recovery

---

## Performance Metrics

Monitor these during testing:

### Checksum Performance
- **Cold compute**: ~10-20ms (first time)
- **Warm compute**: <1ms (cached)

### Packet Size
- **Structure**: ~500 bytes (raid metadata only)
- **Encounter**: ~1-2 KB (metadata + roles structure)
- **Role**: ~200-500 bytes (role config)
- **Assignments**: ~500-2000 bytes (depends on slot count)

### Network Impact
- **Traditional full sync**: 15-25 KB per client
- **Surgical Layer 4 repair**: 500-2000 bytes per role
- **Reduction**: 90-95% for assignment-only changes

---

## Test Scenarios

### Scenario 1: Structure Change
**Change:** Raid name, display name, enabled status
**Expected:** Layer 1 packet only (minimal traffic)

### Scenario 2: New Role Added
**Change:** Add role to encounter
**Expected:** Layer 2 (encounter) + Layer 3 (role) packets

### Scenario 3: Assignment Change
**Change:** Assign player to role
**Expected:** Layer 4 (assignments) packet only

### Scenario 4: Multiple Encounters
**Change:** Assignments in encounters 1, 3, 5
**Expected:** 3 separate Layer 4 packets, selected encounter first

---

## Debugging Tips

### Enable Verbose Logging

Add debug prints to SyncRepair.lua:

```lua
-- In packet builders
OGRH.Msg("[REPAIR-DEBUG] Building structure packet for " .. raidName)

-- In appliers
OGRH.Msg("[REPAIR-DEBUG] Applying " .. packet.type .. " packet")

-- In validation
OGRH.Msg("[REPAIR-DEBUG] Validation result: " .. (success and "PASS" or "FAIL"))
```

### Inspect Packet Contents

```lua
/script local pkt = OGRH.SyncRepair.BuildStructurePacket("Molten Core")
/script OGRH.Msg("Data fields: " .. table.getn(pkt.data))
/script for k, v in pairs(pkt.data) do OGRH.Msg("  " .. k .. ": " .. tostring(v)) end
```

### Compare Checksums

```lua
/script local before = OGRH.SyncChecksum.ComputeRaidStructureChecksum("Molten Core")
-- Make a change
/script local after = OGRH.SyncChecksum.ComputeRaidStructureChecksum("Molten Core")
/script OGRH.Msg("Changed: " .. (before ~= after and "YES" or "NO"))
```

---

## Conclusion

Phase 3 implementation provides the core packet system for surgical repairs:
- **Builders** extract minimal data per layer
- **Appliers** apply packets to client data
- **Validation** verifies repairs succeeded
- **Adaptive Pacing** prevents network congestion
- **Priority Ordering** ensures selected encounter repairs first

All functionality is testable via `/ogrh repair` command. Successful testing confirms readiness for Phase 4 (UI implementation).
