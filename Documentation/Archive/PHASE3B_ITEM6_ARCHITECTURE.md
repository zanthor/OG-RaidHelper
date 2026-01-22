# Assignment Broadcasting: Architectural Decision

**Date:** January 21, 2026  
**Decision**: Keep assignment broadcasting logic in Core, replace with delta sync  
**Status**: Implemented

---

## Question

Should `OGRH.BroadcastAssignmentUpdate()` be moved from OGRH_Core.lua to OGRH_EncounterMgmt.lua since all call sites are in EncounterMgmt?

---

## Decision: Keep in Core (but Deprecate)

**Rationale**: The function represents a **communication layer primitive**, not UI-specific business logic. Moving it would violate the layered architecture pattern.

### Architectural Layers

```
┌─────────────────────────────────────┐
│  OGRH_EncounterMgmt.lua            │  ← UI Layer: User interactions, UI state
│  (User clicks, drags, UI events)   │
└─────────────────────────────────────┘
              ↓ (calls)
┌─────────────────────────────────────┐
│  OGRH_SyncDelta.lua                │  ← Business Logic: Change tracking, batching
│  (RecordAssignmentChange)           │
└─────────────────────────────────────┘
              ↓ (calls)
┌─────────────────────────────────────┐
│  OGRH_MessageRouter.lua            │  ← Communication: Message routing, priority
│  (Broadcast, SendTo)                │
└─────────────────────────────────────┘
              ↓ (uses)
┌─────────────────────────────────────┐
│  _OGAddonMsg Library               │  ← Transport: Chunking, retry, reliability
│  (OGAddonMsg.Send)                  │
└─────────────────────────────────────┘
```

### Why Not Move?

1. **Shared Dependencies**: Function uses Core utilities (`CalculateStructureChecksum`, `IsRaidLead`, `ADDON_PREFIX`)
2. **Communication Primitive**: Broadcast is a communication concern, not a UI concern
3. **Already Being Replaced**: Function is obsolete - delta sync is the future
4. **Code Duplication**: Moving would require duplicating Core utilities or creating circular dependencies

---

## Implementation Strategy

Instead of moving the function, we:

1. **Replaced all call sites** with `OGRH.SyncDelta.RecordAssignmentChange`
2. **Deprecated Core function** with warning wrapper for backward compatibility
3. **Enhanced swap logic** to properly track both sides of the transaction

---

## Changes Made

### Before (All in EncounterMgmt.lua)
```lua
-- Player list drag
OGRH.BroadcastAssignmentUpdate(raid, encounter, roleIdx, slotIdx, playerName)

-- Slot swap (BROKEN: only moved one player, cleared the other)
OGRH.BroadcastAssignmentUpdate(raid, encounter, targetRoleIdx, targetSlotIdx, draggedPlayer)
OGRH.BroadcastAssignmentUpdate(raid, encounter, sourceRoleIdx, sourceSlotIdx, targetPlayer)

-- Slot move
OGRH.BroadcastAssignmentUpdate(raid, encounter, targetRoleIdx, targetSlotIdx, draggedPlayer)
OGRH.BroadcastAssignmentUpdate(raid, encounter, sourceRoleIdx, sourceSlotIdx, nil)

-- Remove
OGRH.BroadcastAssignmentUpdate(raid, encounter, roleIdx, slotIdx, nil)
```

### After (All in EncounterMgmt.lua)
```lua
-- Player list drag
OGRH.SyncDelta.RecordAssignmentChange(
    playerName,
    "ENCOUNTER_ROLE",
    {raid, encounter, roleIndex, slotIndex, playerName},
    oldPlayerAtTarget  -- Track old value
)

-- Slot swap (FIXED: both players recorded)
OGRH.SyncDelta.RecordAssignmentChange(draggedPlayer, "ENCOUNTER_ROLE", {...}, targetPlayer)
OGRH.SyncDelta.RecordAssignmentChange(targetPlayer, "ENCOUNTER_ROLE", {...}, draggedPlayer)

-- Slot move (both operations tracked)
OGRH.SyncDelta.RecordAssignmentChange(draggedPlayer, "ENCOUNTER_ROLE", {...}, nil)
OGRH.SyncDelta.RecordAssignmentChange("", "ENCOUNTER_ROLE", {...clear...}, draggedPlayer)

-- Remove (old value tracked)
OGRH.SyncDelta.RecordAssignmentChange("", "ENCOUNTER_ROLE", {...clear...}, oldPlayerName)
```

### Core Function (OGRH_Core.lua)
```lua
-- DEPRECATED wrapper
function OGRH.BroadcastAssignmentUpdate(raid, encounter, roleIndex, slotIndex, playerName)
    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[OGRH]|r DEPRECATED: Use OGRH.SyncDelta.RecordAssignmentChange instead.")
    
    -- Fallback for backward compatibility
    if OGRH.SyncDelta and OGRH.SyncDelta.RecordAssignmentChange then
        OGRH.SyncDelta.RecordAssignmentChange(playerName or "", "ENCOUNTER_ROLE", {...}, nil)
    end
end
```

---

## Benefits of New Approach

### 1. Proper Swap Handling
**Old System**: Sent two separate messages, often resulting in one player cleared
```lua
-- Message 1: PlayerA -> Slot 2
-- Message 2: PlayerB -> Slot 1
-- Problem: Race conditions could result in PlayerB being cleared instead of moved
```

**New System**: Records both changes in a single batch
```lua
-- Delta Batch (sent together after 2s):
-- Change 1: PlayerA -> Slot 2 (oldValue: PlayerB)
-- Change 2: PlayerB -> Slot 1 (oldValue: PlayerA)
-- Result: Both players always assigned, atomic transaction
```

### 2. Message Batching
- **Reduces network spam** during rapid edits
- **Groups related changes** (swap = 2 changes in 1 batch)
- **2-second window** allows multiple edits before broadcast

### 3. Change History
- **Old value tracking** enables undo/conflict resolution
- **Timestamp and author** for audit trail
- **Delta records** can be replayed for sync repair

### 4. Smart Sync
- **Avoids combat/zoning** - queues changes for later
- **Offline queue** - handles disconnects gracefully
- **Auto-flush** on combat end or raid join

### 5. OGAddonMsg Integration
- **Automatic chunking** for large batches
- **Reliable delivery** with retry
- **Priority handling** (NORMAL priority for assignments)

---

## Testing Focus

### Critical Test: Swap Operation
**Must verify**: When dragging PlayerA onto PlayerB's slot:
- ✅ PlayerA ends up in PlayerB's old slot
- ✅ PlayerB ends up in PlayerA's old slot
- ❌ PlayerB is NOT cleared/unassigned

This was the primary motivation for the change - old system had race conditions causing one player to be cleared during swaps.

---

## Migration Path

### Phase 1: ✅ Complete
- Replace all EncounterMgmt call sites with delta sync
- Deprecate Core function with warning wrapper
- Test swap operations

### Phase 2: Future
- Remove deprecated wrapper after all external callers migrated
- Remove old `ASSIGNMENT_UPDATE` message handler
- Clean up legacy code

### Phase 3: Future
- Consider reducing batch delay from 2s to 1s if user feedback says it's too slow
- Add visual indicator for pending changes
- Add "Force Flush" button for immediate sync

---

## Lessons Learned

### Architecture Principles Validated
1. **Layered architecture works**: UI → Logic → Communication → Transport
2. **Don't violate layers**: UI should not do raw communication
3. **Deprecation over deletion**: Provide migration path for legacy code
4. **Fix root causes**: Don't just move broken code, fix it properly

### Best Practices Applied
1. **Track old values**: Essential for conflict resolution and undo
2. **Batch related changes**: Swaps are atomic transactions
3. **Smart delays**: Combat/zoning awareness prevents data loss
4. **Comprehensive testing**: 9-test plan covers all scenarios

---

## Related Documents

- [Phase 3B Core Audit](PHASE3B_CORE_AUDIT.md) - Item 6
- [Phase 3B Item 6 Testing Plan](PHASE3B_ITEM6_TESTING.md)
- [Phase 3A Delta Sync Implementation](PHASE3A_IMPLEMENTATION.md)
- [OGAddonMsg Migration Design](OGAddonMsg Migration - Design Document.md)

---

## Future Considerations

### Potential Enhancements
1. **Reduce batch delay**: 2s → 1s if users report sluggishness
2. **Visual feedback**: Show "sync pending" indicator in UI
3. **Manual flush**: Button to force immediate sync
4. **Undo support**: Use old values to implement undo functionality
5. **Conflict UI**: Show merge dialog when versions conflict

### Performance Monitoring
- Track batch sizes (how many changes per flush)
- Monitor flush frequency
- Measure network message reduction
- User feedback on perceived latency

---

## Conclusion

**Decision**: Keep `BroadcastAssignmentUpdate` in Core as deprecated wrapper  
**Action**: Replace all call sites with `OGRH.SyncDelta.RecordAssignmentChange`  
**Benefit**: Proper swap handling, batching, history tracking, smart sync  
**Result**: Better architecture, more reliable sync, enhanced user experience  

This approach follows best practices, maintains architectural boundaries, and fixes the root cause (race conditions in swaps) rather than just moving code around.
