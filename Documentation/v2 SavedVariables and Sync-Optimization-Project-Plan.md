# SavedVariables v2.0 + Sync Consolidation Project

**Project Lead:** Solo Developer + AI Assistant  
**Start Date:** January 23, 2026  
**Target Completion:** March 2026 (7 weeks)  
**Version:** OG-RaidHelper v2.0

---

## Executive Summary

**Goal:** Unified architecture overhaul delivering:
1. **Data Optimization:** Reduce SavedVariables file size by 63% (40K → 15K lines)
2. **Sync Consolidation:** Reduce network traffic 40-60% by consolidating 5 sync systems into 1
3. **Network Fix:** Fix critical network sync bug (15 min → 10 sec) through data structure optimization
4. **Developer Experience:** Eliminate 55+ manual sync calls, prevent "forgot to sync" bugs

**Approach:** Versioned schema migration (OGRH_SV.v2) with integrated sync system built into SavedVariablesManager (SVM). Single 4-week beta test validates BOTH improvements.

**Related Documents:**
- [SavedVariables-Optimization-Brief.md](SavedVariables-Optimization-Brief.md) - Executive overview
- [SavedVariables-Optimization-Analysis.md](SavedVariables-Optimization-Analysis.md) - Technical deep-dive
- [Sync-Consolidation-Analysis.md](Sync-Consolidation-Analysis.md) - Sync system analysis & consolidation design
- [EncounterMgmt-Structure-Comparison.md](EncounterMgmt-Structure-Comparison.md) - Before/after examples
- [SavedVariables-Migration-v2-Prototype.lua](SavedVariables-Migration-v2-Prototype.lua) - Migration script

---

## Project Phases

### Phase 1: Migration System Foundation (Week 1)
**Goal:** Build versioned migration infrastructure

### Phase 3: Empty Table Cleanup (Week 3)
**Goal:** Remove unused tables from v2 schema

### Phase 4: Data Retention Policies (Week 3)
**Goal:** Apply historical data pruning to v2 schema

### Phase 5: Dual-Write Deployment (Week 4)
**Goal:** Deploy to beta testers with dual-write enabled

### Phase 6: Validation & Testing (Weeks 5-6)
**Goal:** Validate v2 accuracy against v1 with real usage

### Phase 7: Cutover to V2 (Week 7)
**Goal:** Switch active schema to v2

### Phase 8: Cleanup & Release (Week 8+)
**Goal:** Remove v1 data, public release

### Future: Priority 2 - EncounterMgmt Restructure (v3.0)
**Goal:** Fix network sync bug by nesting roles in encounters

---

## Phase 1: SVM Foundation with Sync Integration

### Status: ✅ COMPLETE - All 23 tests passing, documentation complete

**Completed:**
- ✅ SavedVariablesManager core with integrated sync (590 lines)
- ✅ MessageRouter integration (SYNC.DELTA, ASSIGN.DELTA_BATCH)
- ✅ Event handlers (combat/raid/zoning)
- ✅ Checksum integration (single + batch invalidation)
- ✅ Comprehensive test suite (23 tests, all passing)
- ✅ Complete API documentation
- ✅ WoW 1.12 compliance validation

---

## Phase 2: Migrate Write Calls

### Status: � BLOCKED - v2 schema needs redesign with stable identifiers

**📋 Tracking Documents:** 
- [Phase-2-Write-Migration-Tracker.md](Phase-2-Write-Migration-Tracker.md) - Original tracker
- [v2-Schema-Stable-Identifiers-Design.md](v2-Schema-Stable-Identifiers-Design.md) - **NEW: Critical schema fix**

**🚨 CRITICAL ISSUE DISCOVERED:** During first write conversion, discovered v1 uses user-editable display names as table keys (e.g., "Tanks and Heals" with spaces), which breaks SetPath() parsing. v2 schema partially fixed this but encounterAssignments still broken.

**USER MANDATE:** "The ENTIRE point of this project is to fix the data structure... unfuck it, not just work around it."

### Revised Objectives
- **NEW PRIORITY**: Design v2 schema with stable numeric identifiers
- Implement index lookup system for name→index translation
- Update migration scripts for v1→v2 conversion
- THEN convert writes to use v2 schema with indices
- Remove 55+ manual sync calls
- Reduce network traffic 40-60%

### Approach

**⚠️ CRITICAL PIVOT - Schema Redesign Required First:**

Before converting writes, we MUST fix the v2 schema to use stable identifiers. See [v2-Schema-Stable-Identifiers-Design.md](v2-Schema-Stable-Identifiers-Design.md) for complete design.

**Schema Fix Phase (Week 2, Days 1-4):**
1. Implement index lookup system (name→index translation)
2. Complete migration scripts (v1 string keys → v2 numeric indices)
3. Test migration with real SavedVariables data
4. Validate v1 and v2 data matches

**Write Conversion Phase (Week 2, Days 5-7):**
1. Redo EncounterMgmt.lua with index lookups
2. Convert remaining files using v2 schema
3. Integration testing with 2+ clients

### Files to Convert

| Priority | Group | Files | Status |
|----------|-------|-------|--------|
| 🔴 CRITICAL | Encounter Mgmt | 5 files | ⚪ Not Started |
| 🟡 HIGH | Configuration | 3 files | ⚪ Not Started |
| 🟢 MEDIUM | Administrative/UI | 5 files | ⚪ Not Started |
| ⚪ LOW | Structure | 2 files | ⚪ Not Started |

**See [Phase-2-Write-Migration-Tracker.md](Phase-2-Write-Migration-Tracker.md) for complete file-by-file breakdown.**

---

## Phase 1: Migration System Foundation (DEPRECATED - See Phase 1: SVM Foundation)

### Status: ⚪ DEFERRED - Superseded by SVM-first approach

### Objectives
- [x] Create migration script prototype
- [ ] Integrate into Core.lua
- [ ] Add slash commands
- [ ] Test with sample data
- [ ] Document migration workflow

### Tasks

#### Task 1.1: Integrate Migration Module into Core.lua
**File:** `Core/Core.lua`

```lua
-- Add after OGRH namespace declaration
OGRH.Migration = OGRH.Migration or {}

-- Load migration functions
-- (Functions from SavedVariables-Migration-v2-Prototype.lua)
```

**Implementation Steps:**
1. Open `Core/Core.lua`
2. Find OGRH initialization section
3. Copy migration functions from prototype
4. Ensure OGRH.Migration namespace created early
5. Test: `/reload` should not error

**Validation:**
- No errors on `/reload`
- `OGRH.Migration` table exists
- Functions are callable: `/dump OGRH.Migration.MigrateToV2`

---

#### Task 1.2: Add Slash Commands
**File:** `Commands.lua`

```lua
-- Add to existing slash command handler
if msg == "migration create" or msg == "migrate" then
    OGRH.Migration.MigrateToV2()
    
elseif msg == "migration validate" then
    OGRH.Migration.ValidateV2()
    
elseif msg == "migration cutover confirm" then
    OGRH.Migration.CutoverToV2()
    
elseif msg == "migration rollback" then
    OGRH.Migration.RollbackFromV2()
    
elseif msg == "migration help" then
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[OGRH Migration]|r Available commands:")
    DEFAULT_CHAT_FRAME:AddMessage("  /ogrh migration create - Create v2 schema")
    DEFAULT_CHAT_FRAME:AddMessage("  /ogrh migration validate - Compare v1 vs v2")
    DEFAULT_CHAT_FRAME:AddMessage("  /ogrh migration cutover confirm - Switch to v2")
    DEFAULT_CHAT_FRAME:AddMessage("  /ogrh migration rollback - Revert to v1")
end
```

**Implementation Steps:**
1. Open `Commands.lua`
2. Find slash command parser
3. Add migration commands after existing commands
4. Add help text for migration commands
5. Test each command

**Validation:**
- `/ogrh migration help` shows all commands
- Each command executes without errors
- Commands work with partial matches if system supports it

---

#### Task 1.3: Test with Sample SavedVariables
**File:** `Documentation/sv-Sample-OG-RaidHelper.lua`

**Test Procedure:**
1. **Backup Current SavedVariables:**
   ```bash
   cd "D:\games\TurtleWow\WTF\Account\<ACCOUNT>\SavedVariables"
   Copy-Item "OG-RaidHelper.lua" "OG-RaidHelper.lua.backup"
   ```

2. **Load Sample Data:**
   ```bash
   Copy-Item "D:\games\TurtleWow\Interface\AddOns\OG-RaidHelper\Documentation\sv-Sample-OG-RaidHelper.lua" "OG-RaidHelper.lua"
   ```

3. **Test Migration:**
   - Launch WoW, login
   - `/ogrh migration create`
   - Check output: Should show copied keys, pruned entries
   - `/ogrh migration validate`
   - Check output: Should show v1 vs v2 comparison

4. **Verify Data:**
   ```lua
   -- In-game checks
   /dump OGRH_SV.schemaVersion  -- Should be "v1"
   /dump OGRH_SV.v2 ~= nil      -- Should be true
   /dump OGRH_SV.v2.tankIcon    -- Should be nil (excluded)
   /dump OGRH_SV.tankIcon       -- Should still exist (v1 preserved)
   ```

5. **Test Rollback:**
   - `/ogrh migration rollback`
   - `/dump OGRH_SV.v2`  -- Should be nil
   - Verify v1 data still intact

6. **Restore Original:**
   ```bash
   Copy-Item "OG-RaidHelper.lua.backup" "OG-RaidHelper.lua"
   ```

**Validation Checklist:**
- [x] Sample data loads without errors
- [x] Migration creates v2 schema
- [x] Validation shows correct key counts
- [x] v1 data remains unchanged
- [x] Rollback removes v2 schema
- [x] No data loss in any step

---

#### Task 1.5: Create SavedVariablesManager with Integrated Sync
**Files:** `Core/SavedVariablesManager.lua` (new), `Core/Core.lua`, `Core/Core.toc`

**📄 Reference:** [Sync-Consolidation-Analysis.md](Sync-Consolidation-Analysis.md) for full design

**Objective:** Build write interface that consolidates ALL sync logic into one place.

**Why This Matters:**
- Current system: 55+ manual sync calls scattered across codebase
- New system: 0 manual sync calls - automatic sync on write
- Eliminates "forgot to sync" bugs
- 31% code reduction (1,100 lines removed)
- 40-60% network traffic reduction

**Implementation Steps:**

**Step 1: Create SVM Core (2 hours)**
```lua
-- Core/SavedVariablesManager.lua

OGRH.SVM = OGRH.SVM or {}

-- Get value (reads from active schema)
function OGRH.SVM.Get(key, subkey)
    local sv = OGRH.SVM.GetActiveSchema()
    if not sv then return nil end
    
    if subkey then
        return sv[key] and sv[key][subkey]
    else
        return sv[key]
    end
end

-- Set value with integrated sync
function OGRH.SVM.Set(key, subkey, value, syncMetadata)
    local sv = OGRH.SVM.GetActiveSchema()
    if not sv then return false end
    
    -- Write to active schema
    if subkey then
        if not sv[key] then sv[key] = {} end
        sv[key][subkey] = value
    else
        sv[key] = value
    end
    
    -- Dual-write to v2 during migration
    if OGRH_SV.v2 and OGRH_SV.schemaVersion == "v1" then
        if subkey then
            if not OGRH_SV.v2[key] then OGRH_SV.v2[key] = {} end
            OGRH_SV.v2[key][subkey] = value
        else
            OGRH_SV.v2[key] = value
        end
    end
    
    -- NEW: Integrated sync
    if syncMetadata then
        OGRH.SVM.HandleSync(key, subkey, value, syncMetadata)
    end
    
    return true
end

-- Deep set with integrated sync
function OGRH.SVM.SetPath(path, value, syncMetadata)
    local keys = {}
    for key in string.gfind(path, "[^.]+") do
        table.insert(keys, key)
    end
    
    local sv = OGRH.SVM.GetActiveSchema()
    if not sv then return false end
    
    -- Navigate and set
    local t = sv
    for i = 1, table.getn(keys) - 1 do
        if not t[keys[i]] then t[keys[i]] = {} end
        t = t[keys[i]]
    end
    t[keys[table.getn(keys)]] = value
    
    -- Dual-write to v2
    if OGRH_SV.v2 and OGRH_SV.schemaVersion == "v1" then
        t = OGRH_SV.v2
        for i = 1, table.getn(keys) - 1 do
            if not t[keys[i]] then t[keys[i]] = {} end
            t = t[keys[i]]
        end
        t[keys[table.getn(keys)]] = value
    end
    
    -- NEW: Integrated sync
    if syncMetadata then
        OGRH.SVM.HandleSync(path, nil, value, syncMetadata)
    end
    
    return true
end

-- Helper: Get active schema
function OGRH.SVM.GetActiveSchema()
    if OGRH_SV.schemaVersion == "v2" then
        return OGRH_SV
    else
        return OGRH_SV
    end
end
```

**Step 2: Add Sync Router (2 hours)**
```lua
-- Sync configuration
OGRH.SVM.SyncConfig = {
    batchDelay = 2.0,
    pendingBatch = {},
    batchTimer = nil,
    offlineQueue = {},
    enabled = true
}

-- Sync level definitions (priorities must match OGAddonMsg: CRITICAL, HIGH, NORMAL, LOW)
OGRH.SyncLevels = {
    REALTIME = { delay = 0, priority = "HIGH" },
    BATCH = { delay = 2.0, priority = "NORMAL" },
    GRANULAR = { onDemand = true },
    MANUAL = { onDemand = true }
}

-- Route sync based on level
function OGRH.SVM.HandleSync(key, subkey, value, syncMetadata)
    if not OGRH.SVM.SyncConfig.enabled then return end
    if GetNumRaidMembers() == 0 then
        OGRH.SVM.QueueOffline(key, subkey, value, syncMetadata)
        return
    end
    if not OGRH.CanModifyStructure(UnitName("player")) then return end
    
    local syncLevel = syncMetadata.syncLevel or "BATCH"
    
    if syncLevel == "REALTIME" then
        OGRH.SVM.SyncRealtime(key, subkey, value, syncMetadata)
    elseif syncLevel == "BATCH" then
        OGRH.SVM.SyncBatch(key, subkey, value, syncMetadata)
    end
    -- GRANULAR and MANUAL are on-demand only
end

-- Realtime sync: Send immediately
function OGRH.SVM.SyncRealtime(key, subkey, value, syncMetadata)
    if not OGRH.CanSyncNow() then
        OGRH.SVM.QueueOffline(key, subkey, value, syncMetadata)
        return
    end
    
    local changeData = {
        type = syncMetadata.componentType or "GENERIC",
        key = key,
        subkey = subkey,
        value = value,
        scope = syncMetadata.scope,
        timestamp = GetTime(),
        author = UnitName("player")
    }
    
    OGRH.MessageRouter.Broadcast(
        OGRH.MessageTypes.ASSIGN.DELTA_REALTIME,
        changeData,
        { priority = "HIGH" }  -- Must match OGAddonMsg queue levels
    )
    
    OGRH.SVM.InvalidateChecksum(syncMetadata.scope)
end

-- Batch sync: Queue and flush after delay
function OGRH.SVM.SyncBatch(key, subkey, value, syncMetadata)
    if not OGRH.CanSyncNow() then
        OGRH.SVM.QueueOffline(key, subkey, value, syncMetadata)
        return
    end
    
    table.insert(OGRH.SVM.SyncConfig.pendingBatch, {
        type = syncMetadata.componentType or "GENERIC",
        key = key,
        subkey = subkey,
        value = value,
        scope = syncMetadata.scope,
        timestamp = GetTime(),
        author = UnitName("player")
    })
    
    OGRH.SVM.ScheduleBatchFlush()
end

-- Schedule batch flush
function OGRH.SVM.ScheduleBatchFlush()
    if OGRH.SVM.SyncConfig.batchTimer then return end
    
    OGRH.SVM.SyncConfig.batchTimer = OGRH.ScheduleFunc(function()
        OGRH.SVM.FlushBatch()
        OGRH.SVM.SyncConfig.batchTimer = nil
    end, OGRH.SVM.SyncConfig.batchDelay)
end

-- Flush batch
function OGRH.SVM.FlushBatch()
    if table.getn(OGRH.SVM.SyncConfig.pendingBatch) == 0 then return end
    
    OGRH.MessageRouter.Broadcast(
        OGRH.MessageTypes.ASSIGN.DELTA_BATCH,
        { changes = OGRH.SVM.SyncConfig.pendingBatch },
        { priority = "NORMAL" }
    )
    
    OGRH.SVM.SyncConfig.pendingBatch = {}
end

-- Offline queue
function OGRH.SVM.QueueOffline(key, subkey, value, syncMetadata)
    table.insert(OGRH.SVM.SyncConfig.offlineQueue, {
        key = key, subkey = subkey, value = value,
        syncMetadata = syncMetadata, timestamp = GetTime()
    })
end

-- Flush offline queue
function OGRH.SVM.FlushOfflineQueue()
    for i = 1, table.getn(OGRH.SVM.SyncConfig.offlineQueue) do
        local q = OGRH.SVM.SyncConfig.offlineQueue[i]
        OGRH.SVM.HandleSync(q.key, q.subkey, q.value, q.syncMetadata)
    end
    OGRH.SVM.SyncConfig.offlineQueue = {}
end

-- Checksum invalidation
function OGRH.SVM.InvalidateChecksum(scope)
    if OGRH.SyncIntegrity and OGRH.SyncIntegrity.RecordAdminModification then
        OGRH.SyncIntegrity.RecordAdminModification()
    end
end
```

**Step 3: Add to TOC (5 minutes)**
```toc
## Core
Core\Core.lua
Core\SavedVariablesManager.lua
```

**Step 4: Documentation (30 minutes)**
Add clear comments for AI agents:
```lua
--[[
SavedVariablesManager - Write interface for OGRH_SV with integrated sync

USAGE FOR AI AGENTS:
- Reads: Use direct access (OGRH_SV.key.subkey)
- Writes: Use OGRH.SVM.SetPath("key.subkey", value, syncMetadata)

EXAMPLES:
  -- Role assignment (REALTIME sync)
  OGRH.SVM.SetPath("encounterMgmt.roles.MC.Rag.column1.slots.1", "Tankadin", {
      syncLevel = "REALTIME",
      componentType = "roles",
      scope = {raid = "MC", encounter = "Rag"}
  })
  
  -- Settings update (BATCH sync, 2s delay)
  OGRH.SVM.SetPath("encounterMgmt.raids.MC.encounters.Rag.advancedSettings", data, {
      syncLevel = "BATCH",
      componentType = "settings",
      scope = {raid = "MC", encounter = "Rag"}
  })
  
  -- Structure change (MANUAL sync only)
  OGRH.SVM.SetPath("encounterMgmt.raids.NewRaid", data, {
      syncLevel = "MANUAL",
      componentType = "structure"
  })

SYNC LEVELS:
- REALTIME: Instant sync (role assignments, player assignments)
- BATCH: 2-second batching (settings, notes, bulk edits)
- GRANULAR: On-demand repair only (triggered by validation)
- MANUAL: Admin push only (structure changes)

AUTOMATIC FEATURES:
- Dual-write to v2 during migration (Phase 4-6)
- Offline queue (combat/zoning)
- Checksum invalidation
- Network priority management
--]]
```

**Step 5: Testing (2 hours)**

Test checklist:
```lua
-- Test 1: Basic writes
/dump OGRH.SVM.Set("testKey", nil, "testValue")
/dump OGRH_SV.testKey  -- Should be "testValue"

-- Test 2: REALTIME sync
OGRH.SVM.SetPath("encounterMgmt.roles.MC.Rag.test", "value", {
    syncLevel = "REALTIME",
    componentType = "roles"
})
-- Check MessageRouter was called

-- Test 3: BATCH sync
for i = 1, 5 do
    OGRH.SVM.SetPath("test." .. i, i, { syncLevel = "BATCH" })
end
-- Wait 2s, check batch flushed

-- Test 4: Offline queue
-- Enter combat
-- Make changes
-- Leave combat
-- Verify queue flushed

-- Test 5: Dual-write
-- Create v2 schema
OGRH.Migration.MigrateToV2()
-- Write via SVM
OGRH.SVM.Set("testKey2", nil, "value")
-- Verify written to both v1 and v2
/dump OGRH_SV.testKey2
/dump OGRH_SV.v2.testKey2
```

**Validation:**
- [ ] SVM handles REALTIME sync (immediate)
- [ ] SVM handles BATCH sync (2s delay)
- [ ] Offline queue works during combat
- [ ] Dual-write works for v2 migration
- [ ] Checksums update on writes
- [ ] No errors on `/reload`

**Time Estimate:** 6-8 hours total

---

#### Task 1.4: Document Migration Workflow
**File:** `README.md` or `Documentation/MIGRATION.md`

**Content to Document:**
- User-facing migration steps
- What to expect during transition
- How to check migration status
- Rollback procedure if issues found
- When v1 data will be removed

**Implementation:**
Create simple guide for users experiencing migration

---

### Phase 1 Completion Criteria

- [x] Migration script prototype exists
- [ ] Migration integrated into Core.lua
- [ ] Slash commands working
- [ ] **SavedVariablesManager created with integrated sync** ⭐
- [ ] Tested with sample SavedVariables
- [ ] No errors on fresh install
- [ ] No errors with existing v1 data
- [ ] Documentation complete
- [ ] Code reviewed for WoW 1.12 compatibility

**🎯 Phase 1 Success = Solid foundation for v2.0 migration + sync consolidation**

---

## Phase 2: Empty Table Cleanup + Sync Migration

### Status: ⚪ NOT STARTED - Depends on Phase 1

### Objectives

**Data Cleanup:**
- Remove 4 confirmed empty tables from v2 schema
- Validate they're truly unused in codebase
- Ensure no code references them

**Sync Migration (NEW):**
- Convert high-traffic write calls to use SVM with sync metadata
- Eliminate manual sync calls (target: 55+ → 0)
- Validate sync happens automatically on writes

### Tasks

#### Task 2.1: Grep Search for Table References
**Action:** Search entire codebase for references to empty tables

```bash
# In PowerShell
cd "D:\games\TurtleWow\Interface\AddOns\OG-RaidHelper"

# Search for each empty table
Select-String -Path "*.lua" -Pattern "tankIcon" -CaseSensitive
Select-String -Path "*.lua" -Pattern "healerIcon" -CaseSensitive
Select-String -Path "*.lua" -Pattern "tankCategory" -CaseSensitive
Select-String -Path "*.lua" -Pattern "healerBoss" -CaseSensitive
```

**Expected Result:** Only initialization/migration code references

**If Found:** Investigate each reference to determine:
- Is it legacy code that can be removed?
- Is it actually using these tables?
- Can we safely remove the reference?

---

#### Task 2.2: Verify Empty in Production Data
**Action:** Check sample SavedVariables file

Already confirmed in `sv-Sample-OG-RaidHelper.lua`:
- `tankIcon = {}`
- `healerIcon = {}`
- `tankCategory = {}`
- `healerBoss = {}`

**Additional Check:** Request production data from users
- Ask beta testers to check their SavedVariables
- Verify these tables are empty across multiple users
- Document any exceptions

---

#### Task 2.3: Update Migration Script
**File:** `SavedVariables-Migration-v2-Prototype.lua`

Already implemented - migration script excludes these tables when creating v2:

```lua
local emptyTables = {
    tankIcon = true,
    healerIcon = true,
    tankCategory = true,
    healerBoss = true
}

for key, value in pairs(OGRH_SV) do
    if key ~= "v2" and key ~= "schemaVersion" and not emptyTables[key] then
        OGRH_SV.v2[key] = DeepCopy(value)
    end
end
```

**Validation:** Verify in Phase 1 testing

---

#### Task 2.4: Migrate High-Traffic Write Calls to SVM (NEW)
**Files:** Various - RolesUI, Assignment handlers, Settings UI

**Priority Paths to Convert:**

1. **Role Assignments** (12 locations) - REALTIME sync
   ```lua
   -- Before
   OGRH_SV.encounterMgmt.roles[raid][enc].column1.slots[slot] = player
   OGRH.SyncDelta.RecordRoleChange(player, newRole, oldRole)
   
   -- After
   OGRH.SVM.SetPath("encounterMgmt.roles."..raid.."."..enc..".column1.slots."..slot, player, {
       syncLevel = "REALTIME",
       componentType = "roles",
       scope = {raid = raid, encounter = enc}
   })
   ```

2. **Player Assignments** (8 locations) - REALTIME sync
3. **Settings Updates** (6 locations) - BATCH sync
4. **Swap Operations** (5 locations) - REALTIME sync

**Implementation Strategy:**
- Use grep to find all write locations
- Convert one subsystem at a time (roles, then assignments, then settings)
- Test each conversion before moving to next
- Leave infrequent writes as-is (not worth effort)

**Validation:**
- [ ] Role writes use SVM with REALTIME sync
- [ ] Assignment writes use SVM with REALTIME sync
- [ ] Settings writes use SVM with BATCH sync
- [ ] No manual `RecordRoleChange()` calls remain
- [ ] Sync happens automatically (verify in beta testing)

---

#### Task 2.4: Migrate High-Traffic Write Calls to SVM (NEW)
**Files:** Various - RolesUI, Assignment handlers, Settings UI

**Priority Paths to Convert:**

1. **Role Assignments** (12 locations) - REALTIME sync
   ```lua
   -- Before
   OGRH_SV.encounterMgmt.roles[raid][enc].column1.slots[slot] = player
   OGRH.SyncDelta.RecordRoleChange(player, newRole, oldRole)
   
   -- After
   OGRH.SVM.SetPath("encounterMgmt.roles."..raid.."."..enc..".column1.slots."..slot, player, {
       syncLevel = "REALTIME",
       componentType = "roles",
       scope = {raid = raid, encounter = enc}
   })
   ```

2. **Player Assignments** (8 locations) - REALTIME sync
3. **Settings Updates** (6 locations) - BATCH sync
4. **Swap Operations** (5 locations) - REALTIME sync

**Implementation Strategy:**
- Use grep to find all write locations
- Convert one subsystem at a time (roles, then assignments, then settings)
- Test each conversion before moving to next
- Leave infrequent writes as-is (not worth effort)

**Validation:**
- [ ] Role writes use SVM with REALTIME sync
- [ ] Assignment writes use SVM with REALTIME sync
- [ ] Settings writes use SVM with BATCH sync
- [ ] No manual `RecordRoleChange()` calls remain
- [ ] Sync happens automatically (verify in beta testing)

---

### Phase 2 Completion Criteria

**Data Cleanup:**
- [ ] Grep search confirms no active usage
- [ ] Production data confirms tables empty
- [ ] Migration script excludes tables (already done)
- [ ] No errors when tables missing in v2

**Sync Migration:**
- [ ] High-traffic writes converted to SVM
- [ ] Manual sync calls eliminated (55+ → <10)
- [ ] Sync metadata documented for each write type
- [ ] No sync-related errors in testing

**Overall:**
- [ ] Documentation updated

---

## Phase 3: Data Retention + Sync Consolidation Cleanup

### Status: ⚪ NOT STARTED - Depends on Phase 2

### Objectives

**Data Retention:**
- Apply 30-day retention to recruitment data
- Apply 90-day retention to consume tracking
- Make retention periods configurable
- Ensure data still useful after pruning

**Sync Cleanup (NEW):**
- Deprecate old sync systems (SyncDelta.lua, parts of Sync_v2.lua)
- Remove redundant sync code now handled by SVM
- Update documentation to reflect new sync patterns
- Verify no code still calling old sync functions

### Tasks

#### Task 3.1: Implement Configurable Retention
**File:** `Core/Core.lua` or new `Modules/DataRetention.lua`

```lua
OGRH.DataRetention = {
    recruitmentDays = 30,
    consumeTrackingDays = 90,
}

function OGRH.DataRetention.SetRetention(category, days)
    if category == "recruitment" then
        OGRH.DataRetention.recruitmentDays = days
    elseif category == "consume" then
        OGRH.DataRetention.consumeTrackingDays = days
    end
    
    -- Optionally save to SavedVariables
    OGRH_SV.retentionSettings = OGRH.DataRetention
end
```

**Implementation:**
1. Create DataRetention module
2. Add configuration to settings UI
3. Save retention preferences to SavedVariables
4. Update migration script to use configured values

---

#### Task 3.2: Add Manual Cleanup Command
**File:** `Commands.lua`

```lua
if msg == "cleanup recruitment" then
    local pruned = OGRH.DataRetention.PruneRecruitment()
    DEFAULT_CHAT_FRAME:AddMessage(string.format("Pruned %d recruitment entries", pruned))
    
elseif msg == "cleanup consume" then
    local pruned = OGRH.DataRetention.PruneConsumes()
    DEFAULT_CHAT_FRAME:AddMessage(string.format("Pruned %d consume entries", pruned))
    
elseif msg == "cleanup all" then
    local r = OGRH.DataRetention.PruneRecruitment()
    local c = OGRH.DataRetention.PruneConsumes()
    DEFAULT_CHAT_FRAME:AddMessage(string.format("Pruned %d recruitment, %d consume entries", r, c))
end
```

---

#### Task 3.3: Test Retention Logic
**Test Cases:**

1. **Fresh Data (within retention):**
   - Create recruitment entry today
   - Run migration
   - Verify entry preserved

2. **Old Data (outside retention):**
   - Manually create old timestamp entry
   - Run migration
   - Verify entry removed

3. **Edge Cases:**
   - Entry with missing timestamp
   - Entry with invalid timestamp
   - Empty recruitment table

4. **Boundary Testing:**
   - Entry exactly 30 days old
   - Entry 29.9 days old
   - Entry 30.1 days old

**Validation:**
- All test cases pass
- No data loss for recent entries
- Old entries correctly removed
- No errors on edge cases

---

#### Task 3.4: Deprecate Old Sync Systems (NEW)
**Files:** `SyncDelta.lua`, `Sync_v2.lua`

**Actions:**

1. **Mark as Deprecated:**
   ```lua
   -- At top of SyncDelta.lua
   DEFAULT_CHAT_FRAME:AddMessage("|cffff9900[OGRH]|r Warning: SyncDelta is deprecated. Sync now handled by SavedVariablesManager.")
   
   -- Redirect old functions to SVM
   function OGRH.SyncDelta.RecordRoleChange(player, newRole, oldRole)
       DEFAULT_CHAT_FRAME:AddMessage("|cffff9900[OGRH]|r RecordRoleChange is deprecated. Use OGRH.SVM.SetPath() instead.")
       -- Don't crash - just warn
   end
   ```

2. **Remove Redundant Code:**
   - Remove delta batching logic (now in SVM)
   - Remove offline queue (now in SVM)
   - Keep granular sync (still needed for repairs)
   - Simplify SyncIntegrity (no delta tracking needed)

3. **Update Documentation:**
   - Mark old sync patterns as deprecated in comments
   - Add migration guide for any remaining manual sync calls
   - Update Design Philosophy document with SVM patterns

**Validation:**
- [ ] Old sync functions marked deprecated
- [ ] No errors when old code paths called
- [ ] Grep confirms no active usage of deprecated functions
- [ ] SyncGranular still works (needed for repairs)
- [ ] Documentation updated

---

### Phase 3 Completion Criteria

**Data Retention:**
- [ ] Retention periods configurable
- [ ] Migration script uses configured values
- [ ] Manual cleanup commands work
- [ ] All test cases pass
- [ ] Beta testers confirm useful data retained

**Sync Cleanup:**
- [ ] Old sync systems deprecated
- [ ] Redundant code removed (target: 1,100 lines)
- [ ] No active calls to deprecated sync functions
- [ ] Documentation reflects new patterns

**Overall:**
- [ ] Documentation updated with retention policy and sync patterns

---

## Phase 4: Dual-Write Deployment + Consolidated Sync Beta

### Status: ⚪ NOT STARTED - Depends on Phase 3

### Objectives
- Deploy addon with v2 migration to beta testers
- Implement dual-write to keep v1 and v2 in sync
- **Beta test consolidated sync system** (NEW)
- **Measure network traffic improvements** (NEW)
- Collect feedback and validate v2 accuracy + sync reliability

### Tasks

#### Task 4.1: Implement Dual-Write System
**Files:** Various - anywhere OGRH_SV is modified

**Strategy:** Add wrapper functions for SavedVariables writes

```lua
-- File: Core/SavedVariablesManager.lua (new)

OGRH.SVM = OGRH.SVM or {}

function OGRH.SVM.Set(path, value)
    -- Parse path: "recruitment.applicantData.PlayerName"
    local keys = {}
    for key in string.gfind(path, "[^.]+") do
        table.insert(keys, key)
    end
    
    -- Write to v1 (active schema)
    local t = OGRH_SV
    for i = 1, table.getn(keys) - 1 do
        local key = keys[i]
        if not t[key] then t[key] = {} end
        t = t[key]
    end
    t[keys[table.getn(keys)]] = value
    
    -- If v2 exists, also write there
    if OGRH_SV.v2 then
        t = OGRH_SV.v2
        for i = 1, table.getn(keys) - 1 do
            local key = keys[i]
            if not t[key] then t[key] = {} end
            t = t[key]
        end
        t[keys[table.getn(keys)]] = value
    end
end

function OGRH.SVM.Get(path)
    -- Read from active schema
    if OGRH_SV.schemaVersion == "v2" and OGRH_SV.v2 then
        return OGRH.SVM.GetFromTable(OGRH_SV.v2, path)
    else
        return OGRH.SVM.GetFromTable(OGRH_SV, path)
    end
end
```

**Implementation Steps:**
1. Create SavedVariablesManager module
2. Add Get/Set wrapper functions
3. **Gradually** replace direct `OGRH_SV.foo = bar` with `OGRH.SVM.Set("foo", bar)`
4. Focus on frequently-written data first (recruitment, assignments)
5. Test each conversion thoroughly

**Priority Write Paths to Convert:**
- Recruitment: applicant data updates
- Consume tracking: new history entries
- Roster management: player updates
- Encounter assignments: role changes

---

#### Task 4.2: Add Dual-Write Validation
**File:** `Modules/MigrationValidator.lua` (new)

```lua
OGRH.MigrationValidator = {}

function OGRH.MigrationValidator.CompareSchemas()
    if not OGRH_SV.v2 then
        return false, "v2 schema not found"
    end
    
    local differences = {}
    
    -- Compare recruitment data
    local v1Count = OGRH.CountEntries(OGRH_SV.recruitment.applicantData)
    local v2Count = OGRH.CountEntries(OGRH_SV.v2.recruitment.applicantData)
    
    if v1Count ~= v2Count then
        table.insert(differences, string.format("Recruitment: v1=%d, v2=%d", v1Count, v2Count))
    end
    
    -- Compare consume tracking
    -- Compare roster data
    -- etc.
    
    if table.getn(differences) > 0 then
        return false, differences
    else
        return true, "Schemas match"
    end
end
```

**Schedule Regular Validation:**
```lua
-- Run comparison every 5 minutes during beta
OGRH.ScheduleTimer(function()
    local success, msg = OGRH.MigrationValidator.CompareSchemas()
    if not success then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[OGRH Beta]|r Schema mismatch detected!", 1, 0, 0)
        for i = 1, table.getn(msg) do
            DEFAULT_CHAT_FRAME:AddMessage("  " .. msg[i], 1, 0.5, 0)
        end
    end
end, 300, true)  -- Every 5 min, repeating
```

---

#### Task 4.3: Beta Deployment Checklist

**Pre-Deployment:**
- [ ] All Phase 1-3 tasks complete
- [ ] Dual-write system implemented
- [ ] Validation system implemented
- [ ] Migration tested with sample data
- [ ] Code reviewed for WoW 1.12 compatibility
- [ ] Changelog prepared

**Deployment:**
- [ ] Create beta release branch
- [ ] Package addon with migration script
- [ ] Update version number to 2.0-beta1
- [ ] Distribute to 5-10 beta testers
- [ ] Provide beta testing guide

**Beta Testing Guide Contents:**
```
OG-RaidHelper v2.0 Beta Testing Guide

What's New:
- New SavedVariables schema (v2) for better performance
- Automatic data cleanup (old entries pruned)
- 63% smaller file size
- NEW: Consolidated sync system (automatic sync on all writes)
- NEW: Reduced network traffic (40-60% less bandwidth)

What to Expect:
1. First login: Addon will create v2 schema automatically
2. Both v1 and v2 will be maintained during beta
3. No data loss - original data preserved
4. Periodic validation messages
5. Sync happens automatically (no manual sync needed)

What to Report:
- Any error messages
- Features not working correctly
- "Schema mismatch detected" warnings
- Sync delays or failures
- Performance improvements/issues
- Network bandwidth observations

How to Revert:
/ogrh migration rollback
/reload

Duration: 2 weeks
```

---

### Phase 4 Completion Criteria

- [ ] Dual-write system implemented
- [ ] Validation running automatically
- [ ] Beta deployed to testers
- [ ] Testing guide distributed
- [ ] Feedback collection process established

---

## Phase 5: Validation & Testing

### Status: ⚪ NOT STARTED - Depends on Phase 4

### Objectives
- Collect 2+ weeks of real-world usage data
- Validate v2 accuracy vs v1
- Fix any bugs or discrepancies
- Measure performance improvements

### Tasks

#### Task 5.1: Monitor Beta Feedback
**Daily Tasks:**
- Check Discord/forum for bug reports
- Review error logs from beta testers
- Track schema mismatch reports
- Document any issues found

**Weekly Tasks:**
- Survey beta testers on experience
- Collect performance metrics
- Review SavedVariables file sizes
- Compare v1 vs v2 data integrity

---

#### Task 5.2: Validation Checklist

**Data Integrity:**
- [ ] Recruitment data matches v1 vs v2
- [ ] Consume tracking matches v1 vs v2
- [ ] Roster data matches v1 vs v2
- [ ] Encounter assignments match v1 vs v2
- [ ] Sync data consistent across raid members

**Functionality:**
- [ ] All UI features work with v2 data
- [ ] Network sync works with v2 data
- [ ] **Consolidated sync system working** (NEW)
- [ ] **No manual sync calls needed** (NEW)
- [ ] **Sync happens automatically on writes** (NEW)
- [ ] Migration doesn't break existing features
- [ ] Rollback successfully reverts to v1
- [ ] Fresh install works (no v1 data)

**Performance:**
- [ ] File size reduced as expected (~63%)
- [ ] Load time improved (~48%)
- [ ] Memory usage reduced (~28%)
- [ ] **Network traffic reduced (40-60%)** (NEW)
- [ ] **Sync latency acceptable (<2s for batch)** (NEW)
- [ ] No performance regressions

---

#### Task 5.3: Bug Fix Process

**When Bug Found:**
1. **Reproduce:** Get steps to reproduce
2. **Diagnose:** Use grep_search to find affected code
3. **Fix:** Implement fix in development branch
4. **Test:** Verify fix with sample data
5. **Deploy:** Push to beta testers
6. **Verify:** Confirm fix resolved issue

**Track Issues:**
Create simple issue list in this document or separate file

---

### Phase 5 Completion Criteria

- [ ] 2+ weeks of beta testing complete
- [ ] All critical bugs fixed
- [ ] Data integrity validated
- [ ] Performance improvements confirmed
- [ ] Beta testers approve for production
- [ ] Rollback tested successfully

---

## Phase 6: Cutover to V2

### Status: ⚪ NOT STARTED - Depends on Phase 5

### Objectives
- Switch active schema from v1 to v2
- Continue monitoring for issues
- Keep v1 data for one more week (safety)

### Tasks

#### Task 6.1: Cutover Implementation
**File:** Update migration script or add auto-cutover

**Option A: Manual Cutover (Recommended)**
```lua
-- Beta testers manually cutover when ready
/ogrh migration cutover confirm
```

**Option B: Auto-Cutover**
```lua
-- After X days of successful dual-write, auto-cutover
if OGRH_SV.v2 and OGRH_SV.v2.migrationDate then
    local daysSince = (time() - OGRH_SV.v2.migrationDate) / 86400
    if daysSince >= 14 then
        -- Prompt user for cutover
        OGRH.ShowCutoverDialog()
    end
end
```

---

#### Task 6.2: Cutover Checklist

**Pre-Cutover:**
- [ ] All Phase 5 validation passed
- [ ] No open critical bugs
- [ ] Beta testers ready for cutover
- [ ] Rollback procedure documented
- [ ] Backup instructions provided

**Cutover:**
- [ ] Beta testers run `/ogrh migration cutover confirm`
- [ ] Verify `OGRH_SV.schemaVersion = "v2"`
- [ ] Verify v1 data backed up to `OGRH_SV_BACKUP_V1`
- [ ] Verify addon still functions
- [ ] Verify file size reduced

**Post-Cutover:**
- [ ] Monitor for 1 week
- [ ] Address any issues immediately
- [ ] Collect performance metrics
- [ ] Keep v1 backup available

---

### Phase 6 Completion Criteria

- [ ] Cutover successful for all beta testers
- [ ] No critical issues in first week
- [ ] Performance improvements confirmed
- [ ] Users satisfied with changes
- [ ] Ready for public release

---

## Phase 7: Cleanup & Public Release

### Status: ⚪ NOT STARTED - Depends on Phase 6

### Objectives
- Remove v1 data and dual-write code
- Public release as OG-RaidHelper v2.0
- Document changes for users

### Tasks

#### Task 7.1: Code Cleanup

**Remove Dual-Write System:**
- [ ] Remove `OGRH.SVM` wrapper (if implemented)
- [ ] Revert to direct `OGRH_SV` access
- [ ] Remove validation scheduler
- [ ] Clean up migration debug logging

**Remove v1 Backup:**
- [ ] After 30 days, optionally remove `OGRH_SV_BACKUP_V1`
- [ ] Add cleanup function to migration module
- [ ] Document manual cleanup if desired

**Update Code Comments:**
- [ ] Remove "dual-write" comments
- [ ] Update documentation to reflect v2 as standard
- [ ] Remove beta warnings

---

#### Task 7.2: Public Release Preparation

**Changelog:**
```
OG-RaidHelper v2.0 - Major Optimization Update

New Features:
- Optimized SavedVariables structure (63% smaller file)
- Automatic historical data cleanup
- Improved load times (48% faster)
- Reduced memory usage (28% less)

Migration:
- Automatic migration on first load
- Old data preserved for 30 days
- Rollback available: /ogrh migration rollback

Performance Improvements:
- File: 40,000 lines → 15,000 lines
- Load: 350ms → 180ms
- Memory: 2.5MB → 1.8MB

Bug Fixes:
- [List any bugs fixed during beta]

Known Issues:
- None

Upgrade Notes:
- First load may take slightly longer (one-time migration)
- Old SavedVariables backed up automatically
- No action required from users
```

**Distribution:**
- [ ] Update version to 2.0 (remove -beta)
- [ ] Package release
- [ ] Update GitHub/download links
- [ ] Post announcement to Discord/forums
- [ ] Update README with v2.0 changes

---

#### Task 7.3: User Documentation

**Update README.md:**
- Document new slash commands
- Explain migration process
- Provide troubleshooting guide
- Link to optimization documents

**FAQ:**
```markdown
### Will I lose my data?
No. The migration preserves all current data and backs up the original.

### How do I revert if something goes wrong?
Type `/ogrh migration rollback` and `/reload`

### Why is my SavedVariables file larger temporarily?
During migration, both old and new schemas exist. After 30 days, 
the old data is removed and file size will be much smaller.

### What data is being removed?
Only very old historical data:
- Recruitment entries older than 30 days
- Consume tracking older than 90 days
```

---

### Phase 7 Completion Criteria

- [ ] Code cleanup complete
- [ ] Public release deployed
- [ ] Documentation updated
- [ ] Announcement posted
- [ ] Users successfully upgrading
- [ ] No critical issues reported

---

## Future: Priority 2 - EncounterMgmt Restructure

### Status: ⚪ NOT STARTED - Target: v3.0 (After v2.0 stable)

### Objectives
- Fix critical network sync bug (15 min → 10 sec)
- Nest roles inside encounter objects
- Prevent future scope bugs

### Reference Document
[EncounterMgmt-Structure-Comparison.md](EncounterMgmt-Structure-Comparison.md)

### High-Level Tasks (Detailed plan TBD)
1. Design v3 schema with nested roles
2. Create v2→v3 migration script
3. Update ~30 code locations accessing encounterMgmt
4. Test network sync extensively
5. Beta test for 4+ weeks (critical change)
6. Release as v3.0

**Estimated Effort:** 16-20 hours  
**Risk Level:** MEDIUM (touches network sync)  
**Timeline:** 2-3 months after v2.0 release

---

## Project Tracking

### Current Status: Phase 1 (Week 1)

| Phase | Status | Start | Complete | Notes |
|-------|--------|-------|----------|-------|
| 1. Migration Foundation | 🟡 In Progress | Jan 23 | TBD | Migration script created |
| 2. Empty Table Cleanup | ⚪ Not Started | TBD | TBD | Depends on Phase 1 |
| 3. Data Retention | ⚪ Not Started | TBD | TBD | Depends on Phase 2 |
| 4. Dual-Write Deployment | ⚪ Not Started | TBD | TBD | Depends on Phase 3 |
| 5. Validation & Testing | ⚪ Not Started | TBD | TBD | Depends on Phase 4 |
| 6. Cutover to V2 | ⚪ Not Started | TBD | TBD | Depends on Phase 5 |
| 7. Cleanup & Release | ⚪ Not Started | TBD | TBD | Depends on Phase 6 |

### Legend
- 🟢 Complete
- 🟡 In Progress
- 🔴 Blocked
- ⚪ Not Started

---

## Risk Management

### Known Risks

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| Data loss during migration | HIGH | LOW | Versioned schema, v1 preserved |
| Migration bugs corrupt SavedVariables | HIGH | LOW | Automatic backup, rollback command |
| v2 schema has different behavior | MEDIUM | MEDIUM | 2-week validation period |
| Users don't understand migration | LOW | MEDIUM | Clear documentation, auto-migration |
| Beta testing finds critical bugs | MEDIUM | MEDIUM | 2+ week beta period, quick fixes |
| Performance not as expected | LOW | LOW | Already measured with sample data |

### Rollback Plan

**If Critical Issue Found:**
1. Identify affected users
2. Provide rollback command: `/ogrh migration rollback`
3. Fix bug in development
4. Test fix thoroughly
5. Redeploy to beta testers
6. Resume migration after validation

**If Need to Abort Project:**
1. Remove migration code from public release
2. Keep v1 schema permanently
3. Document decision for future reference
4. v2 work not wasted - can revisit later

---

## Success Metrics

### Quantitative Goals - Data Optimization
- [x] File size: 40K → 15K lines (63% reduction) - Measured in analysis
- [ ] Load time: 350ms → 180ms (48% improvement) - Measure post-migration
- [ ] Memory: 2.5MB → 1.8MB (28% reduction) - Measure post-migration
- [ ] Network sync: Would improve from 15 min → 10 sec (Priority 2 - v3.0)

### Quantitative Goals - Sync Consolidation (NEW)
- [ ] Code size: 3,500 lines → 2,400 lines (31% reduction)
- [ ] Manual sync calls: 55+ → 0 (100% elimination)
- [ ] Network traffic: 40-60% reduction (measured in beta)
- [ ] Sync-related bugs: 80% reduction target
- [ ] Sync systems: 5 → 1 (with granular repairs)

### Qualitative Goals
- [ ] No data loss reported
- [ ] Users report faster loading
- [ ] **Developers report easier to add features** (NEW)
- [ ] **No "forgot to sync" bugs reported** (NEW)
- [ ] Beta testers approve for production
- [ ] No increase in bug reports
- [ ] Smooth migration experience

---

## Communication Plan

### Weekly Updates
Post status update to Discord/forum:
- Current phase
- Progress this week
- Blockers (if any)
- Next steps
- ETA for next phase

### Beta Testing
- Direct communication with beta testers
- Quick response to issues (<24 hours)
- Weekly check-in surveys

### Public Release
- Announcement post with changelog
- FAQ for common questions
- Support thread for issues

---

## Next Steps (Immediate)

### This Week (January 23-29)
1. **TODAY:** Complete Phase 1, Task 1.1 - Integrate migration into Core.lua
2. **Jan 24:** Complete Task 1.2 - Add slash commands
3. **Jan 25:** Complete Task 1.3 - Test with sample SavedVariables
4. **Jan 26-27:** Complete Task 1.5 - Create SVM with integrated sync ⭐
5. **Jan 28:** Complete Task 1.4 - Document migration workflow
6. **Jan 29:** Phase 1 review and validation

### Next Week (Jan 30 - Feb 5)
- Complete Phase 2 (Empty Table Cleanup + Sync Migration)
- Start Phase 3 (Data Retention + Sync Consolidation)

---

## Code Review Checklist

Before committing each phase:

**WoW 1.12 Compatibility:**
- [ ] No `#table` (use `table.getn()`)
- [ ] No `%` modulo (use `mod()`)
- [ ] No `string.gmatch()` (use `string.gfind()`)
- [ ] Event handlers use implicit globals (`this`, `event`, `arg1...`)
- [ ] No `continue` statements
- [ ] No modern varargs `...` (use `arg` table)

**Best Practices:**
- [ ] Functions in OGRH namespace
- [ ] Local functions for helpers
- [ ] Proper error handling
- [ ] User-friendly messages
- [ ] Code comments for complex logic
- [ ] No direct UI creation (use OGST)

**Testing:**
- [ ] Tested with sample SavedVariables
- [ ] Tested with fresh install (no SavedVariables)
- [ ] No errors on `/reload`
- [ ] No errors in combat
- [ ] Works with other addons present

---

## Questions & Clarifications

**Open Questions:**
1. Should retention periods be configurable in v2.0 or later?
2. Should cutover be automatic or manual?
3. When to remove v1 backup (30 days? 60 days? manual?)?
4. Should we validate during dual-write or only on-demand?

**Decisions Made:**
- Using versioned schema (OGRH_SV.v2)
- 4-week beta testing minimum
- Manual cutover recommended
- Keep v1 backup for 30 days

---

## References

- [! OG-RaidHelper Design Philosophy.md](! OG-RaidHelper Design Philosophy.md) - Development constraints
- [SavedVariables-Optimization-Brief.md](SavedVariables-Optimization-Brief.md) - Executive summary
- [SavedVariables-Optimization-Analysis.md](SavedVariables-Optimization-Analysis.md) - Technical analysis
- [Sync-Consolidation-Analysis.md](Sync-Consolidation-Analysis.md) - Sync system consolidation design ⭐
- [EncounterMgmt-Structure-Comparison.md](EncounterMgmt-Structure-Comparison.md) - Network sync fix (v3.0)
- [sv-Sample-OG-RaidHelper.lua](sv-Sample-OG-RaidHelper.lua) - Test data

---

**Last Updated:** January 23, 2026  
**Next Review:** Weekly (every Friday)  
**Project Lead:** [Your Name]  
**AI Assistant:** GitHub Copilot (Claude Sonnet 4.5)

**Project Scope Update:** Combined SavedVariables v2.0 + Sync Consolidation into unified release to avoid double work on migration and testing.
