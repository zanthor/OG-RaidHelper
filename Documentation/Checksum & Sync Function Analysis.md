 # Checksum & Sync Function Analysis - Core.lua
**Date:** January 30, 2026  
**Purpose:** Determine which checksum/sync functions in Core.lua are actively used vs dead code after sync infrastructure rebuild

---

## Executive Summary

After analyzing the sync infrastructure, **most of the checksum/sync functions in Core.lua ARE STILL ACTIVE**, but there's significant overlap and confusion due to parallel implementations. The newer sync infrastructure (SyncIntegrity.lua, SyncGranular.lua, SyncRouter.lua) DOES use these Core.lua functions, but also has its own implementations of similar functionality.

### Key Findings:
- ✅ **ACTIVE & USED**: HashRole, CalculateStructureChecksum, CalculateAllStructureChecksum, CalculateRolesUIChecksum, Serialize, Deserialize
- ⚠️ **PARTIAL OVERLAP**: BroadcastStructureSync exists in both Core.lua AND Sync_v2.lua
- ⚠️ **CONFUSING STATE**: Some functions have both old implementations in Core.lua and newer ones in _Infrastructure
- 🔴 **LEGACY DEAD CODE**: HandleAssignmentSync, HandleEncounterSync (replaced by MessageRouter)

---

## Detailed Function Analysis

### 1. HashRole() - ACTIVE ✅
**Location:** `Core.lua:2107`  
**Status:** **ACTIVELY USED** by multiple systems  
**Called From:**
- `Core.lua:2239` - Within CalculateStructureChecksum
- `Core.lua:2245` - Within CalculateStructureChecksum (column 2)
- `Core.lua:2407` - Within CalculateAllStructureChecksum (column 1)
- `Core.lua:2413` - Within CalculateAllStructureChecksum (column 2)
- `_Infrastructure/Versioning.lua:522` - Checksum calculations
- `_Infrastructure/Versioning.lua:532` - Checksum calculations

**Purpose:** Hash a role's complete settings for checksum calculations  
**Verdict:** **KEEP - This is a critical utility function used by multiple checksum systems**

---

### 2. CalculateStructureChecksum(raid, encounter) - ACTIVE ✅
**Location:** `Core.lua:2230`  
**Status:** **ACTIVELY USED**  
**Called From:**
- `Core.lua:3560` - Assignment update validation
- Used by legacy assignment sync system (still in use)

**Purpose:** Calculate checksum for a specific raid/encounter structure  
**Verdict:** **KEEP - Still used for assignment validation**

**NOTE:** SyncIntegrity.lua has `ComputeRaidChecksum()` which is similar but different - it strips assignments for structure-only checksums. These serve different purposes.

---

### 3. CalculateAllStructureChecksum() - ACTIVE ✅
**Location:** `Core.lua:2293`  
**Status:** **ACTIVELY USED**  
**Called From:**
- `_Infrastructure/MessageRouter.lua:1508` - Addon version poll system
- Used for full data integrity checks

**Purpose:** Calculate checksum for ALL structure data (used for version polls)  
**Verdict:** **KEEP - Critical for addon version detection and data consistency**

---

### 4. CalculateRolesUIChecksum() - ACTIVE ✅
**Location:** `Core.lua:2829` (in Core.lua)  
**ALSO Location:** `SyncIntegrity.lua:145` (newer implementation)  
**Status:** **DUAL IMPLEMENTATION - BOTH ACTIVE** ⚠️  

**Called From Core.lua version:**
- Used by legacy code paths

**Called From SyncIntegrity.lua version:**
- `SyncIntegrity.lua:254` - During checksum broadcast
- `SyncIntegrity.lua:371` - During checksum validation

**Issue:** **TWO IMPLEMENTATIONS doing the same thing!**
- Core.lua version: Lines 2829-2849 (simple checksum)
- SyncIntegrity.lua version: Lines 145-160 (same logic)

**Verdict:** **CONSOLIDATE - Keep only ONE version (preferably in Core.lua as utility), remove duplicate from SyncIntegrity.lua**

---

### 5. Serialize(tbl) - ACTIVE ✅
**Location:** `Core.lua:2882`  
**Status:** **ACTIVELY USED**  
**Called From:**
- `_Infrastructure/Sync_v2.lua:643` - Export data serialization
- `_Infrastructure/DataManagement.lua:155` - Export share data

**Purpose:** Convert Lua tables to string format for transmission  
**Verdict:** **KEEP - Essential utility for data transmission**

**NOTE:** There's also `OGAddonMsg.Serialize()` in the _OGAddonMsg library, but OGRH.Serialize() is still used for export/import operations.

---

### 6. Deserialize(str) - ACTIVE ✅
**Location:** `Core.lua:2906`  
**Status:** **ACTIVELY USED**  
**Called From:**
- `_Infrastructure/Sync_v2.lua:215` - Request data deserialization
- `_Infrastructure/Sync_v2.lua:458` - Import data deserialization
- `_Infrastructure/Sync_v2.lua:653` - Import data deserialization (duplicate call)
- `_Infrastructure/DataManagement.lua:179` - Import share data

**Purpose:** Convert string format back to Lua tables  
**Verdict:** **KEEP - Essential utility for data reception**

---

### 7. BroadcastStructureSync() - CONFUSING OVERLAP ⚠️
**Location:** `Core.lua:4498`  
**ALSO Location:** `Sync_v2.lua:367` (wrapper)  
**Status:** **DUAL IMPLEMENTATION**  

**Called From:**
- `Core.lua:3801` - Structure sync request handler
- `Core.lua:4467` - RequestStructureSync when player is admin

**The Problem:**
```lua
// In Sync_v2.lua:367
function OGRH.Sync.BroadcastStructureSync()
  return OGRH.OldBroadcastStructureSync()  // Wrapper
end

// In Sync_v2.lua:373
function OGRH.Sync.OldBroadcastStructureSync()
  // Actual implementation
end
```

**So we have:**
1. `Core.lua:4498` - `OGRH.BroadcastStructureSync()` (original)
2. `Sync_v2.lua:367` - `OGRH.Sync.BroadcastStructureSync()` (wrapper)
3. `Sync_v2.lua:373` - `OGRH.Sync.OldBroadcastStructureSync()` (new implementation)

**Verdict:** **CONSOLIDATE**
- Current code calls `OGRH.BroadcastStructureSync()` (Core.lua version)
- The Sync_v2.lua versions are NOT being called
- **Recommendation:** Remove the wrapper functions from Sync_v2.lua, keep the Core.lua version OR fully migrate to Sync_v2 version and update all callers

---

### 8. RequestStructureSync() - ACTIVE ✅
**Location:** `Core.lua:4449`  
**Status:** **ACTIVELY USED**  
**Called From:**
- `Core.lua:4467` - Called by itself when player is admin (calls BroadcastStructureSync)

**Purpose:** Request structure sync from raid lead  
**Verdict:** **KEEP - Active request mechanism**

---

### 9. RequestCurrentEncounterSync() - ACTIVE ✅
**Location:** `Core.lua:4439`  
**Status:** **ACTIVELY USED**  
**Called From:**
- `Core.lua:4093-4094` - RAID_ROSTER_UPDATE event handler

**Purpose:** Request current encounter sync when joining raid  
**Verdict:** **KEEP - Auto-sync mechanism when joining raids**

---

### 10. HandleAssignmentSync() - LEGACY DEAD CODE 🔴
**Location:** `Core.lua` (searched but not found as standalone function)  
**Status:** **POTENTIALLY REMOVED OR RENAMED**  

The code shows inline handling in the CHAT_MSG_ADDON event handler:
- Lines 3512-3597: "ASSIGNMENT_UPDATE;" message handler

**Verdict:** **This is NOT a standalone function** - it's embedded in the event handler. The grep search was looking for a function that doesn't exist as a named function. **No action needed.**

---

### 11. HandleEncounterSync() - MIGRATED TO MessageRouter 🔴
**Location:** `Core.lua:2801`  
**Status:** **LEGACY - Being replaced by MessageRouter**  

**Called From:**
- Used by old `OGRH.Sync.RouteMessage` system
- Comments in code say: "used by OGRH.Sync.RouteMessage"

**Verdict:** **LEGACY - EVENTUALLY REMOVE once MessageRouter migration complete**

---

### 12. HandleRolesUISync() - LEGACY 🔴
**Location:** `Core.lua:2858`  
**Status:** **REPLACED by SyncIntegrity.lua system**  

Comments in Core.lua say:
```lua
-- RolesUI sync functions removed - now handled by OGRH_SyncIntegrity.lua
-- See unified checksum polling system for RolesUI integrity checks
```

But the function still exists! It's just not being called by the new infrastructure.

**Verdict:** **LEGACY - Can be removed after confirming no legacy callers**

---

## Recommendations

### ✅ COMPLETED - Phase 4 Consolidation (January 31, 2026):

**Created `_Infrastructure/SyncChecksum.lua`** - Centralized module containing ALL checksum and serialization functions:

1. **Consolidated from Core.lua:**
   - `HashRole()` - Complete role configuration hashing
   - `CalculateStructureChecksum()` - Legacy v1 encounter checksums
   - `CalculateAllStructureChecksum()` - Global structure checksum for version polls
   - `Serialize()` / `Deserialize()` - Data transmission utilities

2. **Consolidated from SyncIntegrity.lua:**
   - `HashString()` - String-to-number hashing
   - `ComputeRaidChecksum()` - V2 raid structure checksums (strips assignments)
   - `ComputeActiveAssignmentsChecksum()` - V2 assignments-only checksums
   - `CalculateRolesUIChecksum()` - Global role bucket checksums
   - `GetGlobalComponentChecksums()` - Consumes/tradeItems checksums
   - `SimpleSerialize()` - Lightweight serializer for checksums
   - `DeepCopy()` - Recursive table copying

3. **Architecture:**
   - All functions moved to `OGRH.SyncChecksum.*` namespace
   - Backward compatibility wrappers maintained at `OGRH.*` level
   - Delegatesization to `OGAddonMsg.Serialize/Deserialize` when available
   - Single source of truth for all checksum computations

4. **Benefits:**
   - ✅ No more duplicate implementations
   - ✅ Consistent hashing across all sync systems
   - ✅ Centralized maintenance (one place to fix bugs)
   - ✅ Clear API for new sync features
   - ✅ Backward compatibility preserved (zero breaking changes)

**Next Steps:**
- Monitor for any edge cases or compatibility issues
- Consider removing legacy wrappers in future major version
- Document migration path for custom modules

### Immediate Actions (Safe to do now):

1. ~~**Remove HandleRolesUISync()**~~ (Core.lua:2858) - ⚠️ **DEFER** - Keep for now as safety fallback

2. **Consolidate CalculateRolesUIChecksum()** - Remove duplicate from SyncIntegrity.lua, keep Core.lua version, update SyncIntegrity.lua to call OGRH.CalculateRolesUIChecksum()

### Near-term Actions (After testing):

3. **Resolve BroadcastStructureSync() confusion:**
   - **Option A:** Keep Core.lua version, remove Sync_v2.lua wrappers (simpler)
   - **Option B:** Migrate all callers to use Sync_v2.lua version, remove Core.lua version (cleaner separation)
   - **Current recommendation:** Option A (less code churn)

4. **Remove HandleEncounterSync()** (Core.lua:2801) after confirming MessageRouter handles all cases

### Long-term Actions (Migration complete):

5. **Remove legacy CHAT_MSG_ADDON handlers** from Core.lua event handler once MessageRouter handles:
   - "ASSIGNMENT_UPDATE;" (lines 3512-3597)
   - "ROLE_CHANGE;" (lines 3015+)
   - All other inline message handlers

---

## Summary Table

| Function | Location | Status | Action |
|----------|----------|--------|--------|
| HashRole() | Core.lua:2107 | ✅ ACTIVE | **KEEP** |
| CalculateStructureChecksum() | Core.lua:2230 | ✅ ACTIVE | **KEEP** |
| CalculateAllStructureChecksum() | Core.lua:2293 | ✅ ACTIVE | **KEEP** |
| CalculateRolesUIChecksum() | Core.lua:2829 & SyncIntegrity.lua:145 | ⚠️ DUPLICATE | **CONSOLIDATE** (keep Core version) |
| Serialize() | Core.lua:2882 | ✅ ACTIVE | **KEEP** |
| Deserialize() | Core.lua:2906 | ✅ ACTIVE | **KEEP** |
| BroadcastStructureSync() | Core.lua:4498 & Sync_v2.lua:367 | ⚠️ DUPLICATE | **CONSOLIDATE** (keep Core version or migrate) |
| RequestStructureSync() | Core.lua:4449 | ✅ ACTIVE | **KEEP** |
| RequestCurrentEncounterSync() | Core.lua:4439 | ✅ ACTIVE | **KEEP** |
| HandleAssignmentSync() | N/A | ❌ DOESN'T EXIST | No action (inline code only) |
| HandleEncounterSync() | Core.lua:2801 | 🔴 LEGACY | **REMOVE after MessageRouter migration** |
| HandleRolesUISync() | Core.lua:2858 | 🔴 LEGACY | **REMOVE NOW** (already replaced) |

---

## Conclusion

**You were partially right** - there IS some "tangled web" of overlapping implementations, but it's not ALL dead code. The core checksum functions (HashRole, CalculateStructureChecksum, CalculateAllStructureChecksum) are very much alive and being used by the new infrastructure.

The main issues are:
1. **Duplicate implementations** (CalculateRolesUIChecksum, BroadcastStructureSync)
2. **Legacy handlers** still in Core.lua that could be cleaned up (HandleRolesUISync, HandleEncounterSync)
3. **Confusing naming** where Sync_v2.lua has wrappers that aren't actually being called

The new sync infrastructure (SyncIntegrity, SyncGranular, SyncRouter) correctly uses the Core.lua checksum functions - they just ALSO have their own implementations of some functions, creating confusion.

**Next steps:** Focus on consolidating the duplicates (CalculateRolesUIChecksum, BroadcastStructureSync) and removing confirmed legacy handlers (HandleRolesUISync).
