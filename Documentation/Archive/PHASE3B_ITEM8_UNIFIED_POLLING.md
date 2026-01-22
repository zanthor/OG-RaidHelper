# Phase 3B Item 8: Unified Checksum Polling System

**Date:** January 2026  
**Status:** ✅ COMPLETE

---

## Overview

Moved RolesUI checksum verification from Core to a unified polling system in `OGRH_SyncIntegrity.lua`. Admin now broadcasts all checksums (structure, RolesUI, assignments) every 30 seconds in a single message.

---

## Architecture

### Unified Polling System

**Admin broadcasts every 30 seconds:**
```lua
{
  structure = "12345",           -- Encounter roles, marks, numbers, announcements
  rolesUI = "67890",             -- Bucket assignments (Tanks/Healers/Melee/Ranged)
  assignments = "abcdef",        -- Player-to-role assignments
  raid = "BWL",
  encounter = "Vaelastrasz",
  timestamp = 1234567890
}
```

**Clients compare checksums:**
- Silent comparison (no network traffic if matched)
- Warning message on mismatch
- User-initiated repair via Data Management window

**Benefits:**
- Single timer instead of multiple polling systems
- Single network message per interval (efficient)
- Centralized logic in one file
- Easy to extend with additional checksums

---

## Changes Made

### 1. OGRH_SyncIntegrity.lua - Implemented Unified Polling

**Added Functions:**
- `OGRH.StartIntegrityChecks()` - Start 30-second polling (admin only)
- `OGRH.StopIntegrityChecks()` - Stop polling when losing admin
- `OGRH.SyncIntegrity.BroadcastChecksums()` - Admin sends unified checksum
- `OGRH.SyncIntegrity.OnChecksumBroadcast()` - Client compares checksums

**Polling Logic:**
```lua
-- Admin starts polling when becoming raid lead
OGRH.StartIntegrityChecks()

-- Every 30 seconds, admin broadcasts:
OGRH.MessageRouter.Broadcast(
    OGRH.MessageTypes.SYNC.CHECKSUM_POLL,
    {
        structure = ...,
        rolesUI = ...,
        assignments = ...,
        raid = ...,
        encounter = ...
    }
)

-- Clients receive and compare silently:
if myStructure ~= theirStructure then
    -- Log warning, suggest repair
end
```

### 2. OGRH_MessageTypes.lua - Added CHECKSUM_POLL

```lua
OGRH.MessageTypes.SYNC = {
    ...
    CHECKSUM_POLL = "OGRH_SYNC_CHECKSUM_POLL",  -- Unified checksum broadcast
    ...
}
```

### 3. OGRH_Core.lua - Removed Obsolete Functions

**Deleted:**
- `OGRH.RequestRolesUISync()` - Pull model (obsolete)
- `OGRH.BroadcastRolesUISync()` - Direct broadcast (obsolete)
- `ROLESUI_CHECK` handler in CHAT_MSG_ADDON - Legacy protocol

**Replaced with:**
- Comment redirecting to `OGRH_SyncIntegrity.lua`
- Kept `OGRH.CalculateRolesUIChecksum()` for checksum calculation

---

## Usage

### For Raid Admins

Polling starts automatically when you become raid lead:
```lua
-- Triggered by RAID_ROSTER_UPDATE event
if OGRH.IsRaidLead() then
    OGRH.StartIntegrityChecks()
end
```

### For Raid Members

Checksums are compared automatically every 30 seconds. On mismatch:
```
[RH-SyncIntegrity] Checksum mismatch: RolesUI
[RH-SyncIntegrity] Your data may be out of sync. Use Data Management to pull latest.
```

Manual repair:
1. Open Data Management window
2. Click "Pull Structure from Admin"
3. Checksums will match after pull completes

---

## Testing Checklist

- [ ] Admin: Verify polling starts when becoming raid lead
- [ ] Admin: Confirm broadcasts every 30 seconds
- [ ] Client: Verify silent operation when checksums match
- [ ] Client: Confirm warning on structure mismatch
- [ ] Client: Confirm warning on RolesUI mismatch
- [ ] Client: Confirm warning on assignment mismatch
- [ ] Multiple mismatches: Verify all are listed (e.g., "structure, RolesUI")
- [ ] Performance: Verify no lag with 40-player raid
- [ ] Network: Verify single message per poll (not 3 separate messages)
- [ ] Admin loss: Verify polling stops when demoted

---

## Future Enhancements

### Phase 4: Auto-Repair
- Admin detects mismatch responses
- Auto-pushes specific data to out-of-sync clients
- No user intervention required

### Phase 5: Conflict Detection
- Track which clients have mismatched checksums
- Show admin UI with list of out-of-sync players
- One-click "Sync All" button

---

## Related Files

- `OGRH_SyncIntegrity.lua` - Unified polling implementation
- `OGRH_MessageTypes.lua` - CHECKSUM_POLL message type
- `OGRH_Core.lua` - Checksum calculation functions (kept)
- `OGRH_MessageRouter.lua` - Message routing for CHECKSUM_POLL

---

## Migration Notes

**Backwards Compatibility:** None required (project spec)

**Old Protocol:** `ROLESUI_CHECK;{checksum}` - **REMOVED**
**New Protocol:** `OGRH_SYNC_CHECKSUM_POLL` with unified checksum data

All clients must be running Phase 3B to participate in checksum polling.
