# Phase 6: Granular Sync & Rollback System - Progress Tracking

**Version:** 1.0  
**Started:** Not Started  
**Target Completion:** TBD  
**Status:** ⏳ PLANNING

---

## Overview

Phase 6 implements hierarchical checksum validation and granular sync to enable surgical data repairs without full structure syncs. This dramatically improves performance by syncing only corrupted components rather than entire encounters or raids.

**Key Goals:**
- Reduce sync time from 76.5 seconds (full structure) to 3.9 seconds (single encounter)
- Implement 4-level checksum hierarchy (Global → Raid → Encounter → Component)
- Enable component-level sync for surgical repairs
- Provide diagnostic information about exact corruption location

**Reference:** See [OGAddonMsg Migration - Design Document.md](OGAddonMsg%20Migration%20-%20Design%20Document.md) § Phase 6

---

## Task Breakdown

### 6.1: Hierarchical Checksum System

**Status:** ✅ COMPLETE

#### 6.1.1: Global-Level Checksums
- [x] Implement `ComputeGlobalComponentChecksum(componentName)`
  - [x] `tradeItems` checksum
  - [x] `consumes` checksum
  - [x] `rgo` checksum (Raid Group Organizer)
- [x] Implement `GetGlobalComponentChecksums()` (returns table of all global checksums)
- [ ] Test checksum stability (same data = same checksum)
- [ ] Test checksum sensitivity (1 byte change = different checksum)

**Files to Create/Modify:**
- `OGRH_SyncIntegrity.lua` (extend existing checksum functions)

**Testing Criteria:**
```lua
-- Test 1: Stability
local cs1 = ComputeGlobalComponentChecksum("rgo")
local cs2 = ComputeGlobalComponentChecksum("rgo")
assert(cs1 == cs2, "Same data must produce same checksum")

-- Test 2: Sensitivity
OGRH_SV.rgo.tanks[1] = "PlayerA"
local cs3 = ComputeGlobalComponentChecksum("rgo")
assert(cs1 ~= cs3, "Data change must change checksum")
```

---

#### 6.1.2: Raid-Level Checksums
- [x] Implement `ComputeRaidChecksum(raidName)`
  - [x] Include raid metadata (advancedSettings)
  - [x] Include encounter list structure
  - [x] Exclude encounter-specific data (handled at encounter level)
- [x] Implement `GetRaidChecksums()` (returns table indexed by raid name)
- [ ] Test with all default raids (MC, Onyxia, BWL, ZG, AQ20, AQ40, Naxxramas)
- [ ] Test stability and sensitivity

**Files to Create/Modify:**
- `OGRH_SyncIntegrity.lua`

**Testing Criteria:**
```lua
-- Test 1: Raid metadata change
local cs1 = ComputeRaidChecksum("BWL")
OGRH_SV.encounterMgmt.raids["BWL"].advancedSettings.consumeTracking = false
local cs2 = ComputeRaidChecksum("BWL")
assert(cs1 ~= cs2, "Raid metadata change must change checksum")

-- Test 2: Encounter list change
local cs3 = ComputeRaidChecksum("BWL")
table.insert(OGRH_SV.encounterMgmt.raids["BWL"].encounters, {name = "Test"})
local cs4 = ComputeRaidChecksum("BWL")
assert(cs3 ~= cs4, "Encounter list change must change checksum")

-- Test 3: Other raid unaffected
local mcCs1 = ComputeRaidChecksum("MC")
-- Modify BWL
local mcCs2 = ComputeRaidChecksum("MC")
assert(mcCs1 == mcCs2, "Other raid checksum must be unchanged")
```

---

#### 6.1.3: Encounter-Level Checksums
- [x] Implement `ComputeEncounterChecksum(raidName, encounterName)`
  - [x] Include encounter metadata (advancedSettings)
  - [x] Include all 6 component checksums:
    - [x] `encounterMetadata` - Encounter object itself
    - [x] `roles` - Role structure from encounterMgmt.roles
    - [x] `playerAssignments` - encounterAssignments table
    - [x] `raidMarks` - encounterRaidMarks table
    - [x] `assignmentNumbers` - encounterAssignmentNumbers table
    - [x] `announcements` - encounterAnnouncements table
- [x] Implement `GetEncounterChecksums(raidName)` (returns table indexed by encounter name)
- [ ] Test with representative encounters (Razorgore, Vaelastrasz, Broodlord)
- [ ] Test stability and sensitivity

**Files to Create/Modify:**
- `OGRH_SyncIntegrity.lua`

**Testing Criteria:**
```lua
-- Test 1: Encounter metadata change
local cs1 = ComputeEncounterChecksum("BWL", "Razorgore")
local enc = OGRH.FindEncounterByName("BWL", "Razorgore")
enc.advancedSettings.bigwigsEnabled = false
local cs2 = ComputeEncounterChecksum("BWL", "Razorgore")
assert(cs1 ~= cs2, "Encounter metadata change must change checksum")

-- Test 2: Other encounter unaffected
local vaeCs1 = ComputeEncounterChecksum("BWL", "Vaelastrasz")
-- Modify Razorgore
local vaeCs2 = ComputeEncounterChecksum("BWL", "Vaelastrasz")
assert(vaeCs1 == vaeCs2, "Other encounter checksum must be unchanged")
```

---

#### 6.1.4: Component-Level Checksums
- [x] Implement `ComputeComponentChecksum(raidName, encounterName, componentName)`
  - [x] `encounterMetadata` component
  - [x] `roles` component
  - [x] `playerAssignments` component
  - [x] `raidMarks` component
  - [x] `assignmentNumbers` component
  - [x] `announcements` component
- [x] Implement `GetComponentChecksums(raidName, encounterName)` (returns table indexed by component)
- [ ] Test each component independently
- [ ] Test cross-component isolation

**Files to Create/Modify:**
- `OGRH_SyncIntegrity.lua`

**Testing Criteria:**
```lua
-- Test 1: Component isolation
local cs1 = ComputeComponentChecksum("BWL", "Razorgore", "playerAssignments")
OGRH_SV.encounterAssignments["BWL"]["Razorgore"][1][1] = "NewPlayer"
local cs2 = ComputeComponentChecksum("BWL", "Razorgore", "playerAssignments")
assert(cs1 ~= cs2, "Assignment change must change assignment checksum")

local rolesCs1 = ComputeComponentChecksum("BWL", "Razorgore", "roles")
-- Modify assignments
local rolesCs2 = ComputeComponentChecksum("BWL", "Razorgore", "roles")
assert(rolesCs1 == rolesCs2, "Assignment change must NOT change roles checksum")
```

---

### 6.2: Hierarchical Validation System

**Status:** ⏳ NOT STARTED

#### 6.2.1: Validation Workflow
- [ ] Implement `ValidateStructureHierarchy(remoteChecksums)` (top-level validation entry point)
  - [ ] Compare overall structure checksum
  - [ ] If mismatch, drill down to global components
  - [ ] If mismatch, drill down to raid checksums
  - [ ] If mismatch, drill down to encounter checksums
  - [ ] If mismatch, drill down to component checksums
  - [ ] Return validation result with exact corruption location
- [ ] Implement validation result structure:
```lua
ValidationResult = {
  valid = false,
  level = "COMPONENT", -- STRUCTURE, GLOBAL, RAID, ENCOUNTER, COMPONENT
  corrupted = {
    global = {"rgo"},
    raids = {
      ["BWL"] = {
        raidLevel = false,
        encounters = {
          ["Razorgore"] = {"playerAssignments", "announcements"}
        }
      }
    }
  }
}
```

**Files to Create/Modify:**
- `OGRH_SyncIntegrity.lua`

**Testing Criteria:**
```lua
-- Test 1: Full structure valid
local result = ValidateStructureHierarchy(GetLocalChecksums())
assert(result.valid == true, "Identical structure must validate")

-- Test 2: Component-level corruption detected
-- Corrupt only player assignments for Razorgore
local result = ValidateStructureHierarchy(GetRemoteChecksums())
assert(result.level == "COMPONENT")
assert(result.corrupted.raids["BWL"].encounters["Razorgore"][1] == "playerAssignments")

-- Test 3: Raid-level corruption detected
-- Corrupt entire BWL raid metadata
local result = ValidateStructureHierarchy(GetRemoteChecksums())
assert(result.level == "RAID")
assert(result.corrupted.raids["BWL"].raidLevel == true)
```

---

#### 6.2.2: Checksum Polling Integration
- [ ] Extend existing 30-second checksum polling (from Phase 2)
- [ ] Replace overall checksum with hierarchical checksums
- [ ] Implement progressive validation on mismatch:
  - [ ] Overall mismatch → validate global components
  - [ ] Global components OK → validate raid checksums
  - [ ] Raid mismatch → validate encounter checksums
  - [ ] Encounter mismatch → validate component checksums
- [ ] Display detailed mismatch report in chat/UI:
  - [ ] "Structure mismatch detected: BWL > Razorgore > playerAssignments"
  - [ ] "Structure mismatch detected: Global component 'rgo'"
  - [ ] "Structure mismatch detected: BWL (raid metadata)"

**Files to Modify:**
- `OGRH_SyncIntegrity.lua` (StartIntegrityChecks function)
- `OGRH_MessageRouter.lua` (SYNC.CHECKSUM_POLL handler)

**Testing Criteria:**
```lua
-- Test 1: Automatic validation on checksum mismatch
-- Simulate remote player with different assignment
-- Verify automatic validation triggers
-- Verify detailed report displayed

-- Test 2: Multiple corruption points
-- Corrupt BWL > Razorgore > playerAssignments
-- Corrupt MC > Garr > announcements
-- Verify both detected and reported

-- Test 3: False positive prevention
-- Ensure identical structures never report mismatch
-- Verify checksums stable across multiple polls
```

---

### 6.3: Granular Sync System

**Status:** ⏳ NOT STARTED

#### 6.3.1: Component-Level Sync
- [ ] Implement `SyncComponent(raidName, encounterName, componentName, targetPlayer)`
  - [ ] Extract component data from saved variables
  - [ ] Serialize component data
  - [ ] Send via OGAddonMsg with chunking
  - [ ] Validate component type
  - [ ] Handle missing raids/encounters gracefully
- [ ] Implement `ReceiveComponentSync(raidName, encounterName, componentName, data, sender)`
  - [ ] Validate sender permission (ADMIN/OFFICER)
  - [ ] Validate component structure
  - [ ] Apply component data to saved variables
  - [ ] Recompute checksums after update
  - [ ] Trigger UI refresh for affected component
- [ ] Register message handlers:
  - [ ] `SYNC.COMPONENT_REQUEST` - Request specific component
  - [ ] `SYNC.COMPONENT_RESPONSE` - Send component data

**Files to Create/Modify:**
- `OGRH_MessageRouter.lua` (new message types)
- `OGRH_SyncGranular.lua` (NEW FILE - granular sync logic)

**Testing Criteria:**
```lua
-- Test 1: Single component sync
-- Corrupt BWL > Razorgore > playerAssignments
-- Request sync from remote player
-- Verify only playerAssignments updated
-- Verify roles, marks, announcements unchanged

-- Test 2: Permission enforcement
-- Non-admin requests component sync
-- Verify rejection
-- Admin requests component sync
-- Verify acceptance

-- Test 3: Missing data handling
-- Request component for non-existent encounter
-- Verify graceful error message
-- Verify no saved variable corruption
```

---

#### 6.3.2: Encounter-Level Sync
- [ ] Implement `SyncEncounter(raidName, encounterName, targetPlayer)`
  - [ ] Sync all 6 components in single operation
  - [ ] Use component sync infrastructure
  - [ ] Batch component updates
  - [ ] Single checksum recomputation after all components applied
- [ ] Implement `ReceiveEncounterSync(raidName, encounterName, allComponentsData, sender)`
  - [ ] Validate sender permission
  - [ ] Validate all component structures
  - [ ] Apply all components atomically (all or nothing)
  - [ ] Recompute checksums
  - [ ] Trigger full encounter UI refresh
- [ ] Register message handlers:
  - [ ] `SYNC.ENCOUNTER_REQUEST`
  - [ ] `SYNC.ENCOUNTER_RESPONSE`

**Files to Modify:**
- `OGRH_SyncGranular.lua`
- `OGRH_MessageRouter.lua`

**Testing Criteria:**
```lua
-- Test 1: Full encounter sync
-- Corrupt all components for BWL > Razorgore
-- Request encounter sync
-- Verify all 6 components updated
-- Verify other encounters unchanged

-- Test 2: Atomic application
-- Simulate partial data corruption during sync
-- Verify either all components applied or none
-- Verify no half-synced state

-- Test 3: Performance
-- Sync single encounter (BWL > Razorgore)
-- Measure sync time
-- Verify < 5 seconds (target: 3.9 seconds)
```

---

#### 6.3.3: Raid-Level Sync
- [ ] Implement `SyncRaid(raidName, targetPlayer)`
  - [ ] Sync raid metadata
  - [ ] Sync all encounters in raid
  - [ ] Use encounter sync infrastructure
  - [ ] Batch encounter updates
- [ ] Implement `ReceiveRaidSync(raidName, raidData, sender)`
  - [ ] Validate sender permission
  - [ ] Validate raid structure
  - [ ] Apply raid metadata
  - [ ] Apply all encounters
  - [ ] Recompute checksums
  - [ ] Trigger full raid UI refresh
- [ ] Register message handlers:
  - [ ] `SYNC.RAID_REQUEST`
  - [ ] `SYNC.RAID_RESPONSE`

**Files to Modify:**
- `OGRH_SyncGranular.lua`
- `OGRH_MessageRouter.lua`

**Testing Criteria:**
```lua
-- Test 1: Full raid sync
-- Corrupt entire BWL raid
-- Request raid sync
-- Verify all BWL encounters updated
-- Verify other raids (MC, AQ40) unchanged

-- Test 2: Performance
-- Sync single raid (BWL with 8 encounters)
-- Measure sync time
-- Verify < 15 seconds (target: 11.6 seconds)

-- Test 3: Large raid handling
-- Sync Naxxramas (15 encounters)
-- Verify successful completion
-- Verify no message truncation
```

---

#### 6.3.4: Global Component Sync
- [ ] Implement `SyncGlobalComponent(componentName, targetPlayer)`
  - [ ] Support "tradeItems", "consumes", "rgo"
  - [ ] Extract component from OGRH_SV
  - [ ] Serialize and send
- [ ] Implement `ReceiveGlobalComponentSync(componentName, data, sender)`
  - [ ] Validate sender permission
  - [ ] Validate component structure
  - [ ] Apply to OGRH_SV
  - [ ] Recompute checksums
  - [ ] Trigger UI refresh if applicable
- [ ] Register message handlers:
  - [ ] `SYNC.GLOBAL_REQUEST`
  - [ ] `SYNC.GLOBAL_RESPONSE`

**Files to Modify:**
- `OGRH_SyncGranular.lua`
- `OGRH_MessageRouter.lua`

**Testing Criteria:**
```lua
-- Test 1: RGO sync
-- Corrupt OGRH_SV.rgo
-- Request sync
-- Verify rgo updated
-- Verify other global components unchanged

-- Test 2: Consumes sync
-- Corrupt OGRH_SV.consumes
-- Request sync
-- Verify consumes updated
-- Verify raids/encounters unchanged
```

---

### 6.4: Automatic Repair System

**Status:** ⏳ NOT STARTED

#### 6.4.1: Mismatch Detection & Auto-Request
- [ ] Integrate with checksum polling (from 6.2.2)
- [ ] On validation failure, automatically request appropriate sync level:
  - [ ] Component mismatch → request component sync
  - [ ] Encounter mismatch (multiple components) → request encounter sync
  - [ ] Raid mismatch → request raid sync
  - [ ] Global component mismatch → request global sync
- [ ] Implement smart sync selection:
  - [ ] If 1-2 components corrupted → request component sync
  - [ ] If 3+ components corrupted → request encounter sync
  - [ ] If multiple encounters corrupted → request raid sync
- [ ] Add user notification:
  - [ ] "Detected structure mismatch: BWL > Razorgore > playerAssignments"
  - [ ] "Requesting repair from raid admin..."
  - [ ] "Repair completed successfully"

**Files to Modify:**
- `OGRH_SyncIntegrity.lua`
- `OGRH_SyncGranular.lua`

**Testing Criteria:**
```lua
-- Test 1: Single component auto-repair
-- Corrupt BWL > Razorgore > playerAssignments
-- Wait for checksum poll (30 seconds)
-- Verify automatic repair request
-- Verify repair completes
-- Verify next checksum poll passes

-- Test 2: Multi-component auto-repair
-- Corrupt BWL > Razorgore > playerAssignments, announcements, raidMarks
-- Verify system requests encounter sync (not 3 component syncs)

-- Test 3: No admin available
-- Corrupt data with no admin online
-- Verify graceful error message
-- Verify no infinite retry loop
```

---

#### 6.4.2: Manual Repair UI
- [ ] Add "Data Management" window options (extend existing window from Phase 2):
  - [ ] "Validate Structure" button
  - [ ] Display validation result with detailed corruption report
  - [ ] "Repair" button (visible if validation fails)
  - [ ] Repair level selector (Component, Encounter, Raid, Full)
  - [ ] Target player selector (admin/officer list)
- [ ] Implement validation display:
  - [ ] Tree view of corruption (Raid > Encounter > Component)
  - [ ] Checksum comparison (local vs remote)
  - [ ] Corruption severity indicator
- [ ] Implement manual repair flow:
  - [ ] User clicks "Repair"
  - [ ] System requests sync at selected level
  - [ ] Progress indicator during repair
  - [ ] Success/failure notification

**Files to Modify:**
- `OGRH_DataManagement.lua` (extend existing UI)
- `OGRH_SyncGranular.lua`

**Testing Criteria:**
```lua
-- Test 1: Validation display
-- Corrupt BWL > Razorgore > playerAssignments
-- Open Data Management window
-- Click "Validate Structure"
-- Verify corruption displayed in tree view
-- Verify checksum mismatch shown

-- Test 2: Manual component repair
-- Select "Component" repair level
-- Select corrupted component from tree
-- Click "Repair"
-- Verify repair request sent
-- Verify progress indicator shown
-- Verify success notification

-- Test 3: Manual encounter repair
-- Corrupt multiple components
-- Select "Encounter" repair level
-- Click "Repair"
-- Verify all components repaired
```

---

### 6.5: Performance Validation

**Status:** ⏳ NOT STARTED

#### 6.5.1: Benchmark Testing
- [ ] Create benchmark suite in `Tests/` directory
- [ ] Measure sync times for different scenarios:
  - [ ] Full structure sync (baseline: 76.5 seconds)
  - [ ] Single raid sync (target: 11.6 seconds)
  - [ ] Single encounter sync (target: 3.9 seconds)
  - [ ] Single component sync (target: < 1 second)
- [ ] Test with various network conditions:
  - [ ] Local (same machine)
  - [ ] LAN (low latency)
  - [ ] Internet (realistic latency)
- [ ] Measure bandwidth usage:
  - [ ] Bytes transmitted per sync operation
  - [ ] Number of messages sent
  - [ ] Compare to Phase 2 full sync

**Files to Create:**
- `Tests/benchmark_granular_sync.lua`

**Success Criteria:**
- Full structure sync: 60-80 seconds (no worse than Phase 2)
- Single raid sync: < 15 seconds
- Single encounter sync: < 5 seconds
- Single component sync: < 1 second
- Bandwidth usage: 85-95% reduction vs full sync for component repairs

---

#### 6.5.2: Load Testing
- [ ] Test with maximum data size:
  - [ ] All default raids/encounters loaded
  - [ ] 40-player raid with all assignments
  - [ ] Maximum announcements, marks, numbers
- [ ] Test concurrent operations:
  - [ ] Multiple players requesting sync simultaneously
  - [ ] Sync during active combat
  - [ ] Sync during zone transitions
- [ ] Verify no message loss or corruption
- [ ] Verify no OOM errors

**Success Criteria:**
- Handle 40-player raid with full data
- No message loss with 5+ concurrent sync requests
- No OOM errors with maximum data size
- Graceful degradation under load (queue, don't drop)

---

### 6.6: Documentation & Migration

**Status:** ⏳ NOT STARTED

#### 6.6.1: Code Documentation
- [ ] Document all new functions with usage examples
- [ ] Document checksum hierarchy architecture
- [ ] Document sync level selection algorithm
- [ ] Document repair workflow (auto and manual)
- [ ] Add inline comments for complex logic

**Files to Document:**
- `OGRH_SyncIntegrity.lua`
- `OGRH_SyncGranular.lua`
- `OGRH_DataManagement.lua`

---

#### 6.6.2: Update Migration Document
- [ ] Update [OGAddonMsg Migration - Design Document.md](OGAddonMsg%20Migration%20-%20Design%20Document.md)
- [ ] Mark Phase 6 as COMPLETE
- [ ] Document performance improvements achieved
- [ ] Document known limitations
- [ ] Add migration notes for future phases

---

#### 6.6.3: User Documentation
- [ ] Update user guide with Data Management window usage
- [ ] Document validation and repair process
- [ ] Add troubleshooting section for sync issues
- [ ] Document performance characteristics
- [ ] Add FAQ for common scenarios

**Files to Create/Update:**
- `Documentation/USER_GUIDE.md`
- `Documentation/TROUBLESHOOTING.md`

---

## Testing Checklist

### Unit Tests
- [ ] Checksum functions (stability, sensitivity, isolation)
- [ ] Validation workflow (all corruption types)
- [ ] Component sync (all 6 components)
- [ ] Encounter sync (atomic application)
- [ ] Raid sync (full raid update)
- [ ] Global component sync (rgo, consumes, tradeItems)

### Integration Tests
- [ ] Checksum polling with hierarchical validation
- [ ] Auto-repair flow (detection → request → repair → validation)
- [ ] Manual repair flow (UI → request → repair → notification)
- [ ] Permission enforcement (all sync operations)
- [ ] Concurrent sync requests (queue handling)

### Performance Tests
- [ ] Full structure sync (baseline)
- [ ] Single raid sync (< 15s)
- [ ] Single encounter sync (< 5s)
- [ ] Single component sync (< 1s)
- [ ] Load testing (40 players, max data)

### Regression Tests
- [ ] Phase 2 full sync still works
- [ ] Phase 3A delta sync still works
- [ ] Phase 4 permissions still enforced
- [ ] Phase 5 UI integrations still functional
- [ ] All existing features unaffected

---

## Known Issues & Risks

### Risks
1. **Checksum collision**: Hash function may produce collisions for different data
   - **Mitigation**: Use 64-bit hash, test with large dataset
2. **Race conditions**: Concurrent sync requests may conflict
   - **Mitigation**: Queue sync requests, serialize execution
3. **Partial sync corruption**: Component sync failure may leave inconsistent state
   - **Mitigation**: Atomic application (all or nothing), rollback on failure
4. **Performance regression**: Hierarchical validation may be slower than single checksum
   - **Mitigation**: Cache checksums, only recompute on data change

### Limitations
1. **Hierarchical validation requires admin online**: No auto-repair if no admin available
   - **Workaround**: Manual repair from any online admin
2. **Checksum computation cost**: Full checksum recomputation expensive for large data
   - **Optimization**: Incremental checksum updates (future phase)
3. **UI refresh after repair**: May be disruptive during active raid
   - **Optimization**: Batch UI updates, defer non-critical refreshes

---

## Success Metrics

### Performance
- ✅ Component sync < 1 second
- ✅ Encounter sync < 5 seconds  
- ✅ Raid sync < 15 seconds
- ✅ 85%+ bandwidth reduction vs full sync

### Reliability
- ✅ 100% detection rate for corruption
- ✅ No false positives in validation
- ✅ No data loss during repair
- ✅ Graceful handling of missing admins

### User Experience
- ✅ Automatic repair (no user intervention)
- ✅ Clear validation reports
- ✅ Manual repair option available
- ✅ Minimal disruption during repair

---

## Phase 6 Completion Criteria

- [ ] All 6.1-6.6 tasks completed
- [ ] All unit tests passing
- [ ] All integration tests passing
- [ ] Performance benchmarks met
- [ ] Regression tests passing
- [ ] Documentation complete
- [ ] User guide updated
- [ ] Code reviewed and approved
- [ ] 2+ week beta testing with live raids

---

**Last Updated:** January 22, 2026  
**Next Review:** After Phase 6.1 in-game testing

---

## Phase 6.1 Status Update (January 22, 2026)

**Implementation:** ✅ COMPLETE  
**Testing:** ⏳ IN PROGRESS

### Completed Items
- ✅ All 4 checksum levels implemented (Global, Raid, Encounter, Component)
- ✅ Helper functions created (HashString, HashStringToNumber)
- ✅ Test suite created (29 tests)
- ✅ Documentation complete

### Pending Items
- [ ] Run test suite in-game
- [ ] Validate all 29 tests pass
- [ ] Performance benchmarking
- [ ] Integration preparation for Phase 6.2

**See:** [PHASE6_1_IMPLEMENTATION.md](PHASE6_1_IMPLEMENTATION.md) for detailed implementation notes
