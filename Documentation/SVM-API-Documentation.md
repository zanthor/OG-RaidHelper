# SavedVariablesManager (SVM) API Documentation

**Version:** 2.0 (Phase 1 - Sync Integration)  
**Last Updated:** January 23, 2026

---

## Overview

The SavedVariablesManager (SVM) is the **unified write interface** for all OG-RaidHelper SavedVariables operations. It provides:

- ✅ **Automatic sync propagation** - Writes trigger appropriate sync based on metadata
- ✅ **Intelligent batching** - Groups rapid changes to reduce network traffic
- ✅ **Offline queue** - Queues changes during combat/zoning/offline
- ✅ **Dual-write support** - Maintains v1 and v2 schemas during migration
- ✅ **Checksum integration** - Automatically invalidates checksums on writes

---

## Core Principle: Use SVM for Reads and Writes

```lua
-- ✅ READS: Use SVM (abstracts v1/v2 schema location)
local roles = OGRH.SVM.GetPath("encounterMgmt.roles")
local pollTime = OGRH.SVM.Get("pollTime")

-- ✅ WRITES: Use SVM (triggers sync)
OGRH.SVM.SetPath("encounterMgmt.roles.MC.Rag.tank1", "PlayerName", {
    syncLevel = "REALTIME",
    componentType = "roles",
    scope = {raid = "MC", encounter = "Rag"}
})
```

**Why?**
- SVM abstracts schema location (v1 at `OGRH_SV.*` vs v2 at `OGRH_SV.v2.*`)
- Writes trigger sync → must go through SVM
- Direct reads (`OGRH_SV.key`) work during v1 phase but break after cutover

---

## API Reference

### Write Functions

#### `OGRH.SVM.Set(key, subkey, value, syncMetadata)`

Write a value to SavedVariables with optional subkey.

**Parameters:**
- `key` (string) - Top-level key in OGRH_SV
- `subkey` (string|nil) - Optional subkey within table
- `value` (any) - Value to write
- `syncMetadata` (table|nil) - Optional sync configuration

**Returns:** `boolean` - True if write succeeded

**Examples:**

```lua
-- Simple key/value
OGRH.SVM.Set("pollTime", nil, 5)

-- Key with subkey
OGRH.SVM.Set("ui", "minimized", false)

-- With sync metadata (triggers sync)
OGRH.SVM.Set("settings", "autoSort", true, {
    syncLevel = "BATCH",
    componentType = "settings"
})
```

---

#### `OGRH.SVM.SetPath(path, value, syncMetadata)`

Write a value to a deep path in SavedVariables (e.g., "key.subkey.nested").

**Parameters:**
- `path` (string) - Dot-separated path (e.g., "encounterMgmt.roles.MC.Rag.tank1")
- `value` (any) - Value to write
- `syncMetadata` (table|nil) - Optional sync configuration

**Returns:** `boolean` - True if write succeeded

**Examples:**

```lua
-- Deep path write
OGRH.SVM.SetPath("encounterMgmt.roles.MC.Rag.tank1", "PlayerName")

-- With sync metadata
OGRH.SVM.SetPath("encounterMgmt.roles.MC.Rag.tank1", "PlayerName", {
    syncLevel = "REALTIME",
    componentType = "roles",
    scope = {raid = "MC", encounter = "Rag"}
})

-- Table value
OGRH.SVM.SetPath("playerAssignments.PlayerName", {type = "icon", value = 1}, {
    syncLevel = "REALTIME",
    componentType = "assignments"
})
```

---

#### `OGRH.SVM.Get(key, subkey)`

Read a value from SavedVariables.

**Parameters:**
- `key` (string) - Top-level key in active schema
- `subkey` (string|nil) - Optional subkey within table

**Returns:** `any` - Value or nil if not found

**Examples:**

```lua
-- Simple read
local pollTime = OGRH.SVM.Get("pollTime")

-- With subkey
local minimized = OGRH.SVM.Get("ui", "minimized")
```

---

#### `OGRH.SVM.GetPath(path)`

Read a value from a deep path in SavedVariables (e.g., "key.subkey.nested").

**Parameters:**
- `path` (string) - Dot-separated path (e.g., "encounterMgmt.roles.MC.Rag")

**Returns:** `any` - Value or nil if not found

**Examples:**

```lua
-- Deep path read
local tank1 = OGRH.SVM.GetPath("encounterMgmt.roles.MC.Rag.tank1")

-- Table read
local allRoles = OGRH.SVM.GetPath("encounterMgmt.roles")

-- Handles missing paths gracefully
local missing = OGRH.SVM.GetPath("does.not.exist")  -- Returns nil
```

---

## Sync Metadata Schema

The `syncMetadata` table controls how writes are synced to other raid members.

### Required Fields

| Field | Type | Description |
|-------|------|-------------|
| `syncLevel` | string | Sync urgency level (see below) |
| `componentType` | string | Component being modified ("roles", "assignments", "settings", etc.) |

### Optional Fields

| Field | Type | Description |
|-------|------|-------------|
| `scope` | table/string | Scope of change (e.g., `{raid = "MC", encounter = "Rag"}` or `"encounterMgmt.roles"`) |

---

## Sync Levels

### REALTIME - Instant Sync

**Use For:** Combat-critical data that must sync immediately

**Examples:**
- Role assignments during encounter
- Player assignments (marks, icons)
- Encounter phase changes

**Behavior:**
- ✅ Sends immediately (no batching)
- ✅ High priority network message (ALERT)
- ✅ Queues during combat/zoning (flushes when safe)

**Example:**
```lua
-- Role assignment (must sync immediately)
OGRH.SVM.SetPath("encounterMgmt.roles.MC.Rag.tank1", "Tankadin", {
    syncLevel = "REALTIME",
    componentType = "roles",
    scope = {raid = "MC", encounter = "Rag"}
})
```

---

### BATCH - Delayed Sync (2 seconds)

**Use For:** Bulk edits, settings, non-critical data

**Examples:**
- Multiple role assignments in rapid succession
- Settings updates
- Notes, annotations
- Raid metadata

**Behavior:**
- ✅ Batches changes for 2 seconds
- ✅ Groups multiple writes into single network message
- ✅ Normal priority (NORMAL)
- ✅ Queues during combat/zoning

**Example:**
```lua
-- Settings update (can be batched)
OGRH.SVM.SetPath("encounterMgmt.raids.MC.encounters.Rag.advancedSettings.consumeTracking.enabled", true, {
    syncLevel = "BATCH",
    componentType = "settings",
    scope = {raid = "MC", encounter = "Rag"}
})
```

---

### GRANULAR - On-Demand Only

**Use For:** Surgical repairs triggered by validation system

**Behavior:**
- ❌ Not triggered by normal writes
- ✅ Only triggered by SyncGranular repair system
- ✅ Used for checksum mismatch repairs

**Note:** Don't use GRANULAR in `syncMetadata` - it's handled by SyncGranular.lua

---

### MANUAL - Admin Push Only

**Use For:** Structure changes that require manual admin approval

**Examples:**
- Creating new raid/encounter
- Deleting raid/encounter
- Major structural changes

**Behavior:**
- ❌ Not auto-synced
- ✅ Admin must manually push via `/ogrh sync push`

**Example:**
```lua
-- Add new raid (no auto-sync)
OGRH.SVM.SetPath("encounterMgmt.raids.NewRaid", newRaidData, {
    syncLevel = "MANUAL",
    componentType = "structure"
})
```

---

## Usage Patterns

### Pattern 1: Role Assignments (REALTIME)

```lua
-- Assign player to role
function OGRH.AssignPlayerToRole(raid, encounter, roleIndex, slotIndex, playerName)
    local path = string.format("encounterMgmt.roles.%s.%s.column%d.slots.%d", 
        raid, encounter, roleIndex, slotIndex)
    
    OGRH.SVM.SetPath(path, playerName, {
        syncLevel = "REALTIME",
        componentType = "roles",
        scope = {raid = raid, encounter = encounter}
    })
end
```

---

### Pattern 2: Settings Update (BATCH)

```lua
-- Update encounter settings
function OGRH.UpdateEncounterSettings(raid, encounter, settingPath, value)
    local path = string.format("encounterMgmt.raids.%s.encounters.%s.advancedSettings.%s",
        raid, encounter, settingPath)
    
    OGRH.SVM.SetPath(path, value, {
        syncLevel = "BATCH",
        componentType = "settings",
        scope = {raid = raid, encounter = encounter}
    })
end
```

---

### Pattern 3: Player Assignment (REALTIME)

```lua
-- Assign raid mark to player
function OGRH.AssignMark(playerName, markId)
    OGRH.SVM.SetPath("playerAssignments." .. playerName, {type = "icon", value = markId}, {
        syncLevel = "REALTIME",
        componentType = "assignments",
        scope = "playerAssignments"
    })
end
```

---

### Pattern 4: Bulk Edit (BATCH)

```lua
-- Update multiple settings at once (all batched together)
function OGRH.BulkUpdateSettings(raid, encounter, settingsTable)
    for settingKey, settingValue in pairs(settingsTable) do
        local path = string.format("encounterMgmt.raids.%s.encounters.%s.advancedSettings.%s",
            raid, encounter, settingKey)
        
        OGRH.SVM.SetPath(path, settingValue, {
            syncLevel = "BATCH",
            componentType = "settings",
            scope = {raid = raid, encounter = encounter}
        })
    end
    -- All writes batched into single network message after 2 seconds
end
```

---

### Pattern 5: No Sync (Local Only)

```lua
-- UI state (no sync needed)
OGRH.SVM.Set("ui", "minimized", true)  -- No syncMetadata = no sync

-- Or use direct write for UI state
OGRH_SV.ui.minimized = true  -- Also acceptable for local-only data
```

---

## Migration Guide: From Manual Sync to SVM

### Before (Manual Sync Calls)

```lua
-- ❌ OLD: Manual sync required
OGRH_SV.encounterMgmt.roles[raid][enc].column1.slots[slot] = playerName

-- Remember to call sync!
OGRH.SyncDelta.RecordRoleChange(playerName, newRole, oldRole)

-- Don't forget checksum update!
OGRH.SyncIntegrity.RecordAdminModification()
```

### After (SVM Integrated Sync)

```lua
-- ✅ NEW: Sync happens automatically
OGRH.SVM.SetPath("encounterMgmt.roles." .. raid .. "." .. enc .. ".column1.slots." .. slot, playerName, {
    syncLevel = "REALTIME",
    componentType = "roles",
    scope = {raid = raid, encounter = enc}
})
```

### Migration Checklist

1. ✅ Find all direct writes to `OGRH_SV.*`
2. ✅ Replace with `OGRH.SVM.SetPath()` or `OGRH.SVM.Set()`
3. ✅ Add appropriate `syncMetadata`
4. ✅ Remove manual `SyncDelta.RecordXYZChange()` calls
5. ✅ Remove manual `SyncIntegrity.RecordAdminModification()` calls
6. ✅ Test sync behavior

---

## Component Type Reference

| Component Type | Examples | Sync Level |
|---------------|----------|------------|
| `"roles"` | Role assignments, role slots | REALTIME |
| `"assignments"` | Player assignments, marks, icons | REALTIME |
| `"settings"` | Encounter settings, preferences | BATCH |
| `"structure"` | Raid/encounter creation, deletion | MANUAL |
| `"metadata"` | Raid metadata, descriptions | BATCH |
| `"consumes"` | Consumable tracking | BATCH |
| `"tradeItems"` | Trade item lists | BATCH |

---

## Offline Queue System

The SVM automatically queues changes when sync is not possible:

### Queue Conditions

Changes are queued when:
- ❌ Player is in combat (`UnitAffectingCombat`)
- ❌ Player is not in raid (`not UnitInRaid`)
- ❌ Player is zoning (`OGRH.SVM.SyncConfig.isZoning`)

### Flush Conditions

Queue is automatically flushed when:
- ✅ Player leaves combat (`PLAYER_REGEN_ENABLED` event)
- ✅ Player joins raid (`RAID_ROSTER_UPDATE` event)
- ✅ Player finishes zoning (`PLAYER_ENTERING_WORLD` event)

### Manual Flush

```lua
-- Manually flush offline queue (rarely needed)
OGRH.SVM.FlushOfflineQueue()
```

---

## Schema Version Support (v1 → v2 Migration)

SVM reads/writes to the **active schema only** based on `OGRH_SV.schemaVersion`:

```lua
-- Before cutover: schemaVersion = "v1" (or nil)
-- SVM accesses OGRH_SV.* (v1 data at top level)

-- After cutover: schemaVersion = "v2"  
-- SVM accesses OGRH_SV.v2.* (v2 data in nested location)
-- v1 data remains at OGRH_SV.* for rollback capability
```

**Schema Locations:**
- **v1 Active:** Data at `OGRH_SV.*`, `schemaVersion` is `nil` or `"v1"`
- **v2 Active:** Data at `OGRH_SV.v2.*`, `schemaVersion` is `"v2"`
- **After Cutover:** v1 remains at `OGRH_SV.*` (read-only, rollback capability)

**Migration Workflow:**
1. Migrate code to use SVM read wrappers (`GetPath()`, `Get()`)
2. Update code to use v2 numeric indices in paths
3. Test with v1 active (code reads/writes v1 schema via SVM)
4. Run `/ogrh migration create` to generate v2 at `OGRH_SV.v2.*`
5. Run comparison commands to verify v2 data
6. Run `/ogrh migration cutover confirm` to set `schemaVersion = "v2"`
7. Test with v2 active (code now reads/writes v2 schema via SVM)
8. v1 data remains at `OGRH_SV.*` for emergency rollback

**No dual-write** - SVM only touches the active schema.

**Why v2 stays nested:**
- Preserves v1 data for rollback without complex archiving
- Clear separation between schemas
- Prevents accidental v1/v2 data mixing
- All config and UI data migrated to v2 for consistency

---

## Checksum Integration

SVM automatically invalidates checksums on writes:

```lua
-- Write with scope
OGRH.SVM.SetPath("encounterMgmt.roles.MC.Rag.tank1", "PlayerName", {
    syncLevel = "REALTIME",
    componentType = "roles",
    scope = {raid = "MC", encounter = "Rag"}  -- ← Checksum invalidated for this scope
})

-- Batch writes invalidate all unique scopes once
-- (Avoids redundant checksum invalidation)
```

**Integration with SyncIntegrity:**
- Calls `OGRH.SyncIntegrity.RecordAdminModification(scope)`
- Suppresses checksum broadcast for 10 seconds (cooldown)
- Next broadcast includes new checksum

---

## Advanced: Custom Sync Handlers

For special cases, you can hook into sync events:

```lua
-- Hook before sync (e.g., validate data)
local originalSyncRealtime = OGRH.SVM.SyncRealtime
OGRH.SVM.SyncRealtime = function(key, subkey, value, syncMetadata)
    -- Custom validation
    if not MyCustomValidation(value) then
        OGRH.Msg("|cffff0000[Custom]|r Sync rejected: invalid data")
        return
    end
    
    -- Call original
    originalSyncRealtime(key, subkey, value, syncMetadata)
end
```

---

## Debugging

### Enable Sync Debug Mode

```lua
-- Enable verbose sync logging
OGRH.SVM.SyncConfig.debug = true

-- Disable sync temporarily
OGRH.SVM.SyncConfig.enabled = false

-- Check offline queue size
DEFAULT_CHAT_FRAME:AddMessage("Queue size: " .. table.getn(OGRH.SVM.SyncConfig.offlineQueue))

-- Check pending batch size
DEFAULT_CHAT_FRAME:AddMessage("Batch size: " .. table.getn(OGRH.SVM.SyncConfig.pendingBatch))
```

---

## Performance Considerations

### Batching Efficiency

```lua
-- ❌ BAD: Individual syncs (8 network messages)
for i = 1, 8 do
    OGRH.SVM.SetPath("setting" .. i, value, {syncLevel = "REALTIME"})
end

-- ✅ GOOD: Batched syncs (1 network message after 2s)
for i = 1, 8 do
    OGRH.SVM.SetPath("setting" .. i, value, {syncLevel = "BATCH"})
end
```

### Read Performance

```lua
-- ✅ CORRECT: Use SVM for all reads
local value = OGRH.SVM.GetPath("encounterMgmt.roles")

-- ❌ WRONG: Direct access breaks after v2 cutover
local value = OGRH_SV.encounterMgmt.roles  -- Works in v1, fails in v2
```

**Rule:** Always use SVM for reads and writes to ensure compatibility across schema versions.

---

## Testing

Run SVM test suite in-game:

```
/ogrh test svm
```

Tests cover:
- Core read/write operations
- Dual-write during migration
- Sync level routing
- Offline queue behavior
- Batch system
- Checksum integration
- Error handling

---

## Future Enhancements (Phase 2+)

Planned features:
- [ ] Conflict resolution (concurrent writes from multiple admins)
- [ ] Write transaction rollback (undo support)
- [ ] Schema migration helpers (v1 → v2 auto-migration)
- [ ] Performance metrics (sync latency, queue depth)

---

## Summary

✅ **Use SVM for all writes** - Automatic sync, batching, offline queue  
✅ **Use direct access for reads** - No overhead  
✅ **Choose appropriate sync level** - REALTIME for critical, BATCH for bulk  
✅ **Trust the system** - Offline queue, dual-write, checksums handled automatically  

**Questions? Issues?** See [Design Philosophy](! OG-RaidHelper Design Philososphy.md) or file a bug report.
