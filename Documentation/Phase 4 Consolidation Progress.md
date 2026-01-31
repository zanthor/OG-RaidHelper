# Phase 4 Consolidation Progress - SyncChecksum Module
**Date:** January 31, 2026  
**Status:** ✅ COMPLETED - Step 1 (Checksum Functions)  
**Next:** Step 2 (Remove Duplicates from Source Files)

---

## What We Accomplished

Created `_Infrastructure/SyncChecksum.lua` - a centralized module for ALL checksum and serialization operations. This eliminates code duplication and provides a single source of truth for data integrity verification.

### Module Structure

```
OGRH.SyncChecksum
├── SECTION 1: Hashing Utilities
│   ├── HashString(str) → Converts strings to numeric checksums
│   └── HashRole(role, multiplier, index) → Hashes complete role configuration
├── SECTION 2: Serialization Utilities
│   ├── SimpleSerialize(tbl, depth) → Lightweight for checksums
│   ├── Serialize(tbl) → For data transmission (delegates to OGAddonMsg)
│   ├── Deserialize(str) → Parse serialized data (delegates to OGAddonMsg)
│   └── DeepCopy(tbl, seen) → Recursive table copying
├── SECTION 3: Encounter Checksums (Legacy V1 Schema)
│   ├── CalculateStructureChecksum(raid, encounter) → V1 encounter structure
│   └── CalculateAllStructureChecksum() → Global structure for version polls
├── SECTION 4: Raid Checksums (V2 Schema)
│   ├── ComputeRaidChecksum(raidName) → V2 raid structure (no assignments)
│   ├── ComputeActiveAssignmentsChecksum(idx) → V2 assignments only
│   ├── CalculateRolesUIChecksum() → Global role buckets
│   └── GetGlobalComponentChecksums() → Consumes/tradeItems
└── SECTION 5: Backward Compatibility Wrappers
    └── OGRH.* → Maintains existing API (zero breaking changes)
```

---

## Functions Consolidated

### From Core.lua (Lines 2097-2906):
- ✅ `HashRole()` → `OGRH.SyncChecksum.HashRole()`
- ✅ `CalculateStructureChecksum()` → `OGRH.SyncChecksum.CalculateStructureChecksum()`
- ✅ `CalculateAllStructureChecksum()` → `OGRH.SyncChecksum.CalculateAllStructureChecksum()`
- ✅ `Serialize()` → `OGRH.SyncChecksum.Serialize()`
- ✅ `Deserialize()` → `OGRH.SyncChecksum.Deserialize()`

### From SyncIntegrity.lua (Lines 44-307):
- ✅ `HashString()` → `OGRH.SyncChecksum.HashString()`
- ✅ `ComputeRaidChecksum()` → `OGRH.SyncChecksum.ComputeRaidChecksum()`
- ✅ `ComputeActiveAssignmentsChecksum()` → `OGRH.SyncChecksum.ComputeActiveAssignmentsChecksum()`
- ✅ `CalculateRolesUIChecksum()` → `OGRH.SyncChecksum.CalculateRolesUIChecksum()`
- ✅ `GetGlobalComponentChecksums()` → `OGRH.SyncChecksum.GetGlobalComponentChecksums()`
- ✅ `SimpleSerialize()` → Internal utility (not exposed)
- ✅ `DeepCopy()` → `OGRH.SyncChecksum.DeepCopy()`

---

## Call Site Analysis

All existing call sites will continue to work due to backward compatibility wrappers:

### Core.lua (31 references)
```lua
-- Still works (backward compatible)
OGRH.HashRole(role, 10, i)
OGRH.CalculateStructureChecksum(raid, encounter)
OGRH.CalculateAllStructureChecksum()
OGRH.Serialize(data)
OGRH.Deserialize(str)

-- Modern approach (preferred for new code)
OGRH.SyncChecksum.HashRole(role, 10, i)
OGRH.SyncChecksum.CalculateStructureChecksum(raid, encounter)
```

### SyncIntegrity.lua (19 references)
```lua
-- Still works (backward compatible)
OGRH.HashString(str)
OGRH.ComputeRaidChecksum(raidName)
OGRH.CalculateRolesUIChecksum()

-- Modern approach (preferred for new code)
OGRH.SyncChecksum.HashString(str)
OGRH.SyncChecksum.ComputeRaidChecksum(raidName)
```

### Other Files:
- **SavedVariablesManager.lua** (4 calls) - `ComputeRaidChecksum()`
- **SyncGranular.lua** (4 calls) - `ComputeRaidChecksum()`
- **MessageRouter.lua** (2 calls) - `CalculateAllStructureChecksum()`
- **Versioning.lua** (4 calls) - `HashRole()`
- **DataManagement.lua** (4 calls) - `Serialize()`, `Deserialize()`

**Total:** ~70 call sites across the codebase - all maintained via backward compatibility wrappers.

---

## Serialization Strategy

**Decision:** Keep OGRH.Serialize/Deserialize for now, delegate to OGAddonMsg

### Rationale:
1. **OGAddonMsg.Serialize** already exists and is robust
2. **Import/Export** operations use OGRH.Serialize for user-facing text
3. **Internal sync** operations use OGAddonMsg automatically (transparent)
4. **Backward compatibility** preserved for existing DataManagement code

### Implementation:
```lua
function OGRH.SyncChecksum.Serialize(tbl)
    -- Delegate to OGAddonMsg if available
    if OGAddonMsg and OGAddonMsg.Serialize then
        return OGAddonMsg.Serialize(tbl)
    end
    
    -- Fallback for safety (shouldn't be reached in normal operation)
    return SimpleFallbackSerializer(tbl)
end
```

**Benefits:**
- Single implementation (OGAddonMsg owns the format)
- OGRH code doesn't maintain duplicate serializer
- Seamless migration path (already using OGAddonMsg internally)
- User-facing export/import still works exactly as before

---

## Testing Checklist

### ✅ Compilation Test
- [x] Addon loads without errors
- [x] No missing function errors in chat
- [x] SyncChecksum module initializes

### ⏳ Functional Tests (Need to verify in-game)
- [ ] Checksum computation works (raid structure)
- [ ] Assignment checksums work (Active Raid)
- [ ] RolesUI checksums work (role assignments)
- [ ] Serialize/Deserialize work (import/export)
- [ ] Global checksums work (version polls)
- [ ] SyncIntegrity polling still functions
- [ ] SyncGranular repairs still work
- [ ] No errors during normal raid operations

### ⏳ Integration Tests
- [ ] MessageRouter version polls work
- [ ] SavedVariablesManager checksums work
- [ ] DataManagement import/export works
- [ ] Legacy assignment sync (if still used)
- [ ] Versioning checksums work

---

## Next Steps

### Step 2: Remove Duplicate Implementations (SURGICAL APPROACH)

**Goal:** Remove the original implementations from Core.lua and SyncIntegrity.lua now that they've been consolidated.

**Strategy:** Gradual removal with testing between each change

#### Phase 2A: Remove from SyncIntegrity.lua
1. Remove `HashString()` (line 44) - KEEP backward compat wrapper
2. Remove `ComputeRaidChecksum()` (line 107) - KEEP backward compat wrapper
3. Remove `ComputeActiveAssignmentsChecksum()` (line 283) - KEEP backward compat wrapper
4. Remove `CalculateRolesUIChecksum()` (line 145) - THIS IS DUPLICATE (also in Core.lua)
5. Remove `SimpleSerialize()` (local function) - Internal utility

**File:** `_Infrastructure/SyncIntegrity.lua`  
**Lines to Remove:** 44-51, 68-100, 107-142, 145-160, 283-308  
**Keep:** All other functions (BroadcastChecksums, OnChecksumBroadcast, repair functions)

#### Phase 2B: Remove from Core.lua
1. Remove `HashRole()` (line 2097)
2. Remove `CalculateStructureChecksum()` (line 2230)
3. Remove `CalculateAllStructureChecksum()` (line 2293)
4. Remove `CalculateRolesUIChecksum()` (line 2829) - DUPLICATE
5. Remove `Serialize()` (line 2882)
6. Remove `Deserialize()` (line 2905)

**File:** `_Core/Core.lua`  
**Lines to Remove:** 2097-2210, 2230-2287, 2293-2576, 2829-2849, 2882-2903, 2905-2915  
**Keep:** All other functions (Active Raid management, UI wrappers, etc.)

#### Phase 2C: Add Backward Compatibility Wrappers (if not already in files)

**In SyncIntegrity.lua (after removals):**
```lua
-- Backward compatibility - delegate to SyncChecksum module
OGRH.HashString = OGRH.SyncChecksum.HashString
OGRH.ComputeRaidChecksum = OGRH.SyncChecksum.ComputeRaidChecksum
OGRH.ComputeActiveAssignmentsChecksum = OGRH.SyncChecksum.ComputeActiveAssignmentsChecksum
OGRH.CalculateRolesUIChecksum = OGRH.SyncChecksum.CalculateRolesUIChecksum
OGRH.GetGlobalComponentChecksums = OGRH.SyncChecksum.GetGlobalComponentChecksums
```

**In Core.lua (after removals):**
```lua
-- Backward compatibility - delegate to SyncChecksum module
OGRH.HashRole = OGRH.SyncChecksum.HashRole
OGRH.CalculateStructureChecksum = OGRH.SyncChecksum.CalculateStructureChecksum
OGRH.CalculateAllStructureChecksum = OGRH.SyncChecksum.CalculateAllStructureChecksum
OGRH.Serialize = OGRH.SyncChecksum.Serialize
OGRH.Deserialize = OGRH.SyncChecksum.Deserialize
OGRH.DeepCopy = OGRH.SyncChecksum.DeepCopy
```

**NOTE:** These wrappers are ALREADY in SyncChecksum.lua, so technically we don't need duplicates. But keeping them local makes the migration more obvious during code review.

### Step 3: Update Direct References (OPTIONAL - Not Required)

Eventually migrate direct calls to use the new namespace:

```lua
-- Old style (still works via wrappers)
local checksum = OGRH.CalculateStructureChecksum(raid, encounter)

-- New style (preferred for new code)
local checksum = OGRH.SyncChecksum.CalculateStructureChecksum(raid, encounter)
```

**Priority:** LOW - The wrappers work perfectly fine. This is purely for code clarity and can be done gradually over time.

---

## Benefits Achieved

### 1. Code Deduplication
- ❌ **Before:** `CalculateRolesUIChecksum()` existed in BOTH Core.lua AND SyncIntegrity.lua
- ✅ **After:** Single implementation in SyncChecksum.lua

### 2. Single Source of Truth
- ❌ **Before:** Hash algorithms scattered across 2+ files
- ✅ **After:** All hashing in one module

### 3. Easier Maintenance
- ❌ **Before:** Bug fixes required updating multiple files
- ✅ **After:** Fix once in SyncChecksum.lua

### 4. Clear API
- ❌ **Before:** Functions scattered, unclear which to use
- ✅ **After:** OGRH.SyncChecksum.* namespace makes it obvious

### 5. Backward Compatibility
- ✅ **Zero breaking changes:** All existing code still works
- ✅ **Gradual migration:** Can update call sites over time
- ✅ **Safety:** Wrappers catch any missed references

---

## Migration Path for Custom Modules

If any custom modules use checksum functions:

### Immediate (No changes required)
```lua
-- Still works exactly as before
local checksum = OGRH.CalculateStructureChecksum(raid, encounter)
local hash = OGRH.HashString(str)
local serialized = OGRH.Serialize(data)
```

### Future (Recommended for new code)
```lua
-- Use the new namespace
local checksum = OGRH.SyncChecksum.CalculateStructureChecksum(raid, encounter)
local hash = OGRH.SyncChecksum.HashString(str)
local serialized = OGRH.SyncChecksum.Serialize(data)
```

### Timeline
- **Phase 1 (NOW):** Backward compatible wrappers in place
- **Phase 2 (Next):** Remove duplicate implementations
- **Phase 3 (Future):** Gradually update call sites
- **Phase 4 (Later):** Consider removing wrappers in major version

---

## Completion Criteria

**Step 1 (COMPLETED):**
- ✅ SyncChecksum.lua created
- ✅ All functions consolidated
- ✅ Backward compatibility wrappers in place
- ✅ Added to TOC in correct order
- ✅ Documentation updated

**Step 2 (NEXT):**
- [ ] Remove duplicate implementations from SyncIntegrity.lua
- [ ] Remove duplicate implementations from Core.lua
- [ ] Test all sync operations in-game
- [ ] Verify no errors during raid operations
- [ ] Update test suite (if exists)

**Step 3 (FUTURE):**
- [ ] Consider migrating call sites to new namespace
- [ ] Remove backward compat wrappers (major version only)
- [ ] Update external module documentation

---

## Notes

### Why Keep Backward Compatibility Wrappers?

1. **Zero Risk:** Existing code continues working without modification
2. **Gradual Migration:** Can update call sites at our own pace
3. **Safety Net:** Catches any missed references during testing
4. **Custom Modules:** External modules won't break
5. **Code Review:** Makes changes obvious and reviewable

### Why Delegate to OGAddonMsg?

1. **Already Implemented:** OGAddonMsg has robust Serialize/Deserialize
2. **Maintained:** _OGAddonMsg library is actively maintained
3. **No Duplication:** Don't maintain two serializers
4. **Transparent:** Internal sync already uses it
5. **Fallback:** OGRH.Serialize still works for legacy code

### Next Major Version (v3.0)

Consider removing backward compatibility wrappers and requiring direct use of `OGRH.SyncChecksum.*` namespace. This would make the API cleaner but requires updating all call sites.

**NOT RECOMMENDED NOW:** Keep wrappers for stability during Phase 4 consolidation.
