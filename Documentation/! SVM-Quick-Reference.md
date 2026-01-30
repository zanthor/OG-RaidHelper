# SVM Quick Reference Guide

**For Developers: How to Use SavedVariablesManager**

---

## The Golden Rule

```lua
-- ✅ READS: Use SVM (abstracts v1/v2 schema location)
local value = OGRH.SVM.GetPath("key.subkey")

-- ✅ WRITES: Use SVM (triggers sync)
OGRH.SVM.SetPath("key.subkey", value, syncMetadata)
```

---

## Common Patterns (Copy-Paste Ready)

### 1. Role Assignment (REALTIME)

```lua
-- Assign player to role slot
OGRH.SVM.SetPath(
    string.format("encounterMgmt.roles.%s.%s.column%d.slots.%d", raid, encounter, roleIdx, slotIdx),
    playerName,
    {
        syncLevel = "REALTIME",
        componentType = "roles",
        scope = {raid = raid, encounter = encounter}
    }
)
```

### 2. Player Assignment (REALTIME)

```lua
-- Assign mark/icon to player
OGRH.SVM.SetPath(
    "playerAssignments." .. playerName,
    {type = "icon", value = markId},
    {
        syncLevel = "REALTIME",
        componentType = "assignments",
        scope = "playerAssignments"
    }
)
```

### 3. Settings Update (BATCH)

```lua
-- Update encounter setting
OGRH.SVM.SetPath(
    string.format("encounterMgmt.raids.%s.encounters.%s.advancedSettings.%s", raid, encounter, settingKey),
    settingValue,
    {
        syncLevel = "BATCH",
        componentType = "settings",
        scope = {raid = raid, encounter = encounter}
    }
)
```

### 4. UI State (NO SYNC)

```lua
-- Local UI state (no sync needed)
OGRH.SVM.Set("ui", "minimized", true)
-- OR direct write:
OGRH_SV.ui.minimized = true
```

### 5. Structure Change (MANUAL)

```lua
-- Add new raid/encounter (no auto-sync)
OGRH.SVM.SetPath(
    "encounterMgmt.raids." .. raidName,
    raidData,
    {
        syncLevel = "MANUAL",
        componentType = "structure"
    }
)
-- Admin must manually push via /ogrh sync push
```

---

## Sync Level Cheat Sheet

| Level | Use For | Behavior |
|-------|---------|----------|
| `REALTIME` | Combat-critical data | Instant sync, high priority |
| `BATCH` | Bulk edits, settings | 2-second batching, normal priority |
| `GRANULAR` | (Don't use) | Triggered by repair system only |
| `MANUAL` | Structure changes | No auto-sync, admin push only |

---

## Component Types

| Type | Examples |
|------|----------|
| `"roles"` | Role assignments |
| `"assignments"` | Player marks, icons |
| `"settings"` | Encounter settings |
| `"structure"` | Raid/encounter creation |
| `"metadata"` | Descriptions, notes |
| `"consumes"` | Consumable tracking |

---

## Migration Checklist

Convert existing code to v2 schema:

1. Find: `OGRH_SV.encounterMgmt.roles[raidName][encounterName]`
2. Replace with: `OGRH_SV.encounterMgmt.raids[raidIdx].encounters[encIdx]`
3. Update SVM calls to use numeric indices
4. Test with v1 active (`schemaVersion = "v1"`)
5. Run `/ogrh migration create` to generate v2
6. Run `/ogrh migration comp` commands to verify
7. Run `/ogrh migration cutover confirm` to switch to v2
8. Test with v2 active (`schemaVersion = "v2"`)
9. Compare behavior between v1 and v2 testing

---

## Testing

```
-- Run SVM tests
/ogrh test svm

-- Check offline queue
/script DEFAULT_CHAT_FRAME:AddMessage("Queue: " .. table.getn(OGRH.SVM.SyncConfig.offlineQueue))

-- Check pending batch
/script DEFAULT_CHAT_FRAME:AddMessage("Batch: " .. table.getn(OGRH.SVM.SyncConfig.pendingBatch))
```

---

## Full Documentation

See [SVM-API-Documentation.md](SVM-API-Documentation.md) for complete reference.
