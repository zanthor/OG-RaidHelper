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
  - [x] ~~`rgo` checksum (Raid Group Organizer)~~ **DEPRECATED** - RGO feature removed
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

**Status:** ✅ COMPLETE ✅ TESTED

#### 6.2.1: Validation Workflow
- [x] Implement `ValidateStructureHierarchy(remoteChecksums)` (top-level validation entry point)
  - [x] Compare overall structure checksum
  - [x] If mismatch, drill down to global components
  - [x] If mismatch, drill down to raid checksums
  - [x] If mismatch, drill down to encounter checksums
  - [x] If mismatch, drill down to component checksums
  - [x] Return validation result with exact corruption location
- [x] Implement validation result structure:
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
- [x] Implement `GetAllHierarchicalChecksums()` - Computes full hierarchy
- [x] Implement `FormatValidationResult(result)` - Human-readable formatting

**Files Created/Modified:**
- `OGRH_SyncIntegrity.lua` (added Phase 6.2 functions)

**Testing:**
- [x] Test functions created: `TestHierarchicalValidation()`, `TestValidationReporting()`
- [x] Self-validation test (should always pass)
- [x] Global corruption detection test
- [x] Component corruption detection test
- [x] Validation reporting format test

---

#### 6.2.2: Checksum Polling Integration
- [x] Extend existing 30-second checksum polling (from Phase 2)
- [x] Replace overall checksum with hierarchical checksums
- [x] Implement progressive validation on mismatch:
  - [x] Overall mismatch → validate global components
  - [x] Global components OK → validate raid checksums
  - [x] Raid mismatch → validate encounter checksums
  - [x] Encounter mismatch → validate component checksums
- [x] Display detailed mismatch report in chat/UI:
  - [x] "Structure mismatch detected: BWL > Razorgore > playerAssignments"
  - [x] "Structure mismatch detected: Global component 'rgo'"
  - [x] "Structure mismatch detected: BWL (raid metadata)"
- [x] Backward compatibility with Phase 3B clients (legacy checksum format)

**Files Modified:**
- `OGRH_SyncIntegrity.lua` (updated BroadcastChecksums, OnChecksumBroadcast)

**Key Features:**
- Admin broadcasts full hierarchical checksums every 30 seconds
- Clients perform progressive drill-down validation
- Detailed mismatch messages show exact corruption location
- Legacy fallback for old clients still on Phase 3B

**Testing Commands:**
```lua
/ogrh test validation   -- Test hierarchical validation
/ogrh test reporting    -- Test validation reporting format
/ogrh test all          -- Run all tests including Phase 6.2
```

**Phase 6.2 Performance Fix (January 22, 2026):**
- ✅ Fixed critical performance issue: Admin was broadcasting FULL hierarchy (17.1s network queue)
- ✅ Replaced with lightweight polling: Only global + raid-level checksums broadcast
- ✅ Implemented on-demand drill-down: Client requests detailed checksums only for mismatched areas
- ✅ Added CHECKSUM_DRILLDOWN_REQUEST/RESPONSE message types
- ✅ Integrated with Phase 6.3 auto-repair (QueueRepair called after corruption identified)
- ✅ Bandwidth reduction: ~95% for checksum polls (broadcasts now <1KB instead of 17.1s queue)

**New Flow:**
1. Admin broadcasts lightweight checksums every 30s (global + raid-level only)
2. Client detects mismatch at raid level → requests drill-down for specific raid
3. Admin responds with encounter + component checksums for that raid only
4. Client identifies exact component corruption
5. Phase 6.3 QueueRepair automatically triggered with prioritization

**In-Game Testing (January 22, 2026):**
- ✅ Clients with matching checksums show "Validation passed"
- ✅ Clients with mismatched checksums detect differences
- ✅ Admin (Tankmedady) broadcasts successfully
- ✅ Lightweight polling confirmed working (no network flood)
- ✅ Drill-down request/response flow working (detected all BWL encounter mismatches)
- ✅ Added 2-second buffer for drill-down requests to batch multiple clients

**Test Configuration:**
- Admin: Tankmedady (checksum: 219755091199)
- Client 1: Gnuzench (checksum: 219755091199) - MATCH ✅
- Client 2: Sunderwhere (checksum: 219751090199) - MISMATCH ⚠️
  - Detected playerAssignments mismatches in all BWL encounters

**Performance Optimization (January 22, 2026):**
- **Issue**: Multiple out-of-sync clients requesting drill-down simultaneously caused duplicate payloads
  - Example: 2 clients both request BWL data → admin sends ~3s payload twice = 6s total
- **Solution**: Added 2-second request batching buffer
  - Admin queues drill-down requests instead of responding immediately
  - After 2 seconds, broadcasts response to ALL queued requesters at once
  - Eliminates duplicate payloads for concurrent requests
- **Benefit**: If 5 clients are all out of sync, admin sends data once instead of 5 times

**Architectural Refinement Needed (January 22, 2026):**

The drill-down system works correctly but exposes a scope issue: we're validating ALL raids when only the currently active raid matters for immediate gameplay.

**Proposed Changes:**
1. **Scope checksum broadcasts to admin's currently selected raid only**
   - Only broadcast checksums for the raid the admin is actively viewing/managing
   - Reduces bandwidth and focuses validation on what's immediately relevant
   - Other raids don't need real-time validation during gameplay

2. **Identify truly global components that need cross-raid validation:**
   - `rgo` (Raid Group Organizer) - affects all raids, needs validation
   - `consumes` - affects all raids, needs validation
   - `tradeItems` - less critical, possibly exclude or lower priority

3. **Add explicit "Full Structure Validation" option:**
   - Manual validation button in Data Management for all raids
   - Used during raid setup or when switching raids
   - Not part of 30-second polling cycle

**Benefits:**
- Dramatically reduces validation overhead (1 raid vs 8 raids)
- Focuses validation on immediately relevant data
- Still detects corruption where it matters (active raid)
- Admin's current raid selection naturally indicates priority
- Clients only need to sync data for the raid they're actually doing

**Implementation Plan:**
- Modify `BroadcastChecksums()` to accept optional `currentRaid` parameter
- Only include encounter checksums for currently selected raid
- Keep global component validation (rgo, consumes) in all broadcasts
- Add UI selector or auto-detect admin's current raid selection

---

### 6.3: Granular Sync System

**Status:** ✅ COMPLETE

**Design Note: Repair Prioritization**

When corruption is detected (via Phase 6.2 validation), repairs should be prioritized by relevance to the user's current context:

1. **Highest Priority: Currently Selected Raid/Encounter**
   - User is actively viewing/editing this encounter
   - Corruption directly impacts their current work
   - Fix immediately to avoid confusion/errors

2. **Medium Priority: Other Encounters in Same Raid**
   - User likely to navigate to these encounters
   - Related to current raid planning context
   - Fix proactively to prevent disruption

3. **Lowest Priority: Other Raids**
   - User not currently working on these
   - Fix when convenient
   - Can defer until user switches raids

**Implementation**: Track current raid/encounter selection in UI state. When multiple corruptions detected, queue repairs in priority order rather than arbitrary order. Consider batching low-priority repairs to reduce overhead.

---

#### 6.3.1: Component-Level Sync
- [x] Implement `SyncComponent(raidName, encounterName, componentName, targetPlayer)`
  - [x] Extract component data from saved variables
  - [x] Serialize component data
  - [x] Send via OGAddonMsg with chunking
  - [x] Validate component type
  - [x] Handle missing raids/encounters gracefully
- [x] Implement `ReceiveComponentSync(raidName, encounterName, componentName, data, sender)`
  - [x] Validate sender permission (ADMIN/OFFICER)
  - [x] Validate component structure
  - [x] Apply component data to saved variables
  - [x] Recompute checksums after update
  - [x] Trigger UI refresh for affected component
- [x] Register message handlers:
  - [x] `SYNC.COMPONENT_REQUEST` - Request specific component
  - [x] `SYNC.COMPONENT_RESPONSE` - Send component data

**Files Created/Modified:**
- `Infrastructure/SyncGranular.lua` (NEW FILE - 950+ lines)
- `Infrastructure/MessageTypes.lua` (added 8 new message types)
- `Infrastructure/MessageRouter.lua` (handlers registered automatically)
- `Core/Core.lua` (added initialization call)

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
- [x] Implement `SyncEncounter(raidName, encounterName, targetPlayer)`
  - [x] Sync all 6 components in single operation
  - [x] Use component sync infrastructure
  - [x] Batch component updates
  - [x] Single checksum recomputation after all components applied
- [x] Implement `ReceiveEncounterSync(raidName, encounterName, allComponentsData, sender)`
  - [x] Validate sender permission
  - [x] Validate all component structures
  - [x] Apply all components atomically (all or nothing)
  - [x] Recompute checksums
  - [x] Trigger full encounter UI refresh
- [x] Register message handlers:
  - [x] `SYNC.ENCOUNTER_REQUEST`
  - [x] `SYNC.ENCOUNTER_RESPONSE`

**Files Modified:**
- `Infrastructure/SyncGranular.lua`

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
- [x] Implement `SyncRaid(raidName, targetPlayer)`
  - [x] Sync raid metadata
  - [x] Sync all encounters in raid
  - [x] Use encounter sync infrastructure
  - [x] Batch encounter updates
- [x] Implement `ReceiveRaidSync(raidName, raidData, sender)`
  - [x] Validate sender permission
  - [x] Validate raid structure
  - [x] Apply raid metadata
  - [x] Apply all encounters
  - [x] Recompute checksums
  - [x] Trigger full raid UI refresh
- [x] Register message handlers:
  - [x] `SYNC.RAID_REQUEST`
  - [x] `SYNC.RAID_RESPONSE`

**Files Modified:**
- `Infrastructure/SyncGranular.lua`

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
- [x] Implement `SyncGlobalComponent(componentName, targetPlayer)`
  - [x] Support "tradeItems", "consumes", "rgo"
  - [x] Extract component from OGRH_SV
  - [x] Serialize and send
- [x] Implement `ReceiveGlobalComponentSync(componentName, data, sender)`
  - [x] Validate sender permission
  - [x] Validate component structure
  - [x] Apply to OGRH_SV
  - [x] Recompute checksums
  - [x] Trigger UI refresh if applicable
- [x] Register message handlers:
  - [x] `SYNC.GLOBAL_REQUEST`
  - [x] `SYNC.GLOBAL_RESPONSE`

**Files Modified:**
- `Infrastructure/SyncGranular.lua`

**Testing:**
- [x] Test function created: `TestGranularSync()` in SyncIntegrity.lua
- [x] Module initialization test
- [x] Priority calculation test
- [x] Component extraction test (all 6 components)
- [x] Validation result integration test
- [x] Message type registration test (all 8 types)

**Testing Command:**
```lua
/ogrh test granular   -- Test granular sync system
/ogrh test all        -- Run all tests including Phase 6.3
```

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
- [x] Integrate with checksum polling (from 6.2.2)
- [x] On validation failure, automatically request appropriate sync level:
  - [x] Component mismatch → request component sync
  - [x] Encounter mismatch (multiple components) → request encounter sync
  - [x] Raid mismatch → request raid sync
  - [x] Global component mismatch → request global sync
- [ ] Implement smart sync selection:
  - [ ] If 1-2 components corrupted → request component sync
  - [ ] If 3+ components corrupted → request encounter sync
  - [ ] If multiple encounters corrupted → request raid sync
- [x] Add user notification:
  - [x] "Detected structure mismatch: BWL > Razorgore > playerAssignments"
  - [x] "Requesting repair from raid admin..."
  - [x] "Repair completed successfully"

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

### 6.5: Rollback System

**Status:** ⏳ NOT STARTED

**Design Philosophy:** Enable users to recover from sync corruption, accidental changes, or bad data by maintaining automatic backups and providing restore functionality.

---

#### 6.5.1: Automatic Backup System
- [ ] Implement `CreateBackup(label)` function
  - [ ] Snapshot entire OGRH_SV structure
  - [ ] Store with timestamp and label
  - [ ] Compress backup data to reduce memory
  - [ ] Limit backup history (keep last 10 backups)
- [ ] Implement automatic backup triggers:
  - [ ] Before full structure sync (Phase 2)
  - [ ] Before raid-level sync (Phase 6.3.3)
  - [ ] Before manual "Load Defaults" operation
  - [ ] On admin role transfer
  - [ ] Before applying major UI changes
- [ ] Implement backup pruning:
  - [ ] Delete backups older than 7 days
  - [ ] Keep minimum 3 backups regardless of age
  - [ ] Provide "Pin" option to prevent auto-deletion
- [ ] Add backup metadata:
  - [ ] Timestamp
  - [ ] User-provided label
  - [ ] Trigger reason ("Before Full Sync", "Manual", etc.)
  - [ ] Data size
  - [ ] Pinned status

**Files to Create/Modify:**
- `Infrastructure/Rollback.lua` (NEW FILE)
- `SavedVariables/SavedVariables.lua` (add backup storage)

**Testing Criteria:**
```lua
-- Test 1: Automatic backup creation
-- Trigger full sync
-- Verify backup created before sync
-- Verify backup contains pre-sync data

-- Test 2: Backup pruning
-- Create 15 backups
-- Verify only last 10 retained
-- Pin 3 old backups
-- Verify pinned backups not deleted

-- Test 3: Backup compression
-- Create backup of full structure
-- Verify compressed size < raw size
-- Restore and verify data integrity
```

---

#### 6.5.2: Manual Backup Creation
- [ ] Add "Create Backup" button to Data Management window
- [ ] Implement backup label dialog:
  - [ ] Text input for custom label
  - [ ] Display current data size estimate
  - [ ] Confirm/Cancel buttons
- [ ] Implement `CreateManualBackup(label)` function
  - [ ] Same as automatic backup
  - [ ] Mark as "Manual" in metadata
  - [ ] Auto-pin manual backups
- [ ] Add visual feedback:
  - [ ] "Backup created successfully: [label]"
  - [ ] Display backup size
  - [ ] Add to backup history list

**Files to Modify:**
- `UI/DataManagement.lua`
- `Infrastructure/Rollback.lua`

**Testing Criteria:**
```lua
-- Test 1: Manual backup creation
-- Click "Create Backup" button
-- Enter label "Before BWL Changes"
-- Verify backup created with label
-- Verify backup auto-pinned

-- Test 2: Backup during active raid
-- Create backup during combat
-- Verify no performance impact
-- Verify backup completes successfully
```

---

#### 6.5.3: Restore from Backup
- [ ] Add "Restore from Backup" UI to Data Management window
- [ ] Implement backup browser:
  - [ ] List all available backups (timestamp, label, size)
  - [ ] Sort by timestamp (newest first)
  - [ ] Show pinned status
  - [ ] Preview backup metadata
- [ ] Implement `RestoreBackup(backupId)` function
  - [ ] Create safety backup of current state first
  - [ ] Replace OGRH_SV with backup data
  - [ ] Recompute all checksums
  - [ ] Broadcast structure update to raid
  - [ ] Refresh all UI elements
- [ ] Add confirmation dialog:
  - [ ] "This will replace all current data. Continue?"
  - [ ] Show backup timestamp and label
  - [ ] "Safety backup will be created first"
  - [ ] Confirm/Cancel buttons
- [ ] Add restore validation:
  - [ ] Verify backup structure valid
  - [ ] Check for corrupted backup data
  - [ ] Graceful error if backup invalid

**Files to Modify:**
- `UI/DataManagement.lua`
- `Infrastructure/Rollback.lua`
- `Infrastructure/SyncIntegrity.lua` (checksum recomputation)

**Testing Criteria:**
```lua
-- Test 1: Basic restore
-- Create backup
-- Modify data (delete encounter, change assignments)
-- Restore from backup
-- Verify data restored to backup state
-- Verify checksums recomputed

-- Test 2: Safety backup creation
-- Restore from old backup
-- Verify safety backup created first
-- Verify safety backup contains pre-restore data
-- Verify restore completes successfully

-- Test 3: Corrupted backup handling
-- Corrupt backup data in SavedVariables
-- Attempt restore
-- Verify graceful error message
-- Verify current data unchanged

-- Test 4: Admin restore broadcast
-- Admin restores from backup
-- Verify structure broadcast to raid
-- Verify other players receive updated data
```

---

#### 6.5.4: Backup Management UI
- [ ] Add "Backup History" section to Data Management window
- [ ] Implement backup list display:
  - [ ] Timestamp (formatted: "Jan 22, 2026 3:45 PM")
  - [ ] Label
  - [ ] Size (formatted: "245 KB")
  - [ ] Trigger reason
  - [ ] Pinned indicator
- [ ] Add backup actions:
  - [ ] "Restore" button (per backup)
  - [ ] "Delete" button (per backup)
  - [ ] "Pin/Unpin" toggle
  - [ ] "Export" button (save backup to file)
- [ ] Implement backup deletion:
  - [ ] Confirmation dialog for manual backups
  - [ ] No confirmation for auto-backups
  - [ ] Cannot delete if < 3 backups remain
- [ ] Add backup export:
  - [ ] Serialize backup to text format
  - [ ] Copy to clipboard or save to file
  - [ ] Include metadata header

**Files to Modify:**
- `UI/DataManagement.lua`
- `Infrastructure/Rollback.lua`

**Testing Criteria:**
```lua
-- Test 1: Backup list display
-- Create 5 backups with different labels
-- Verify all displayed in history list
-- Verify sorted by timestamp (newest first)
-- Verify metadata displayed correctly

-- Test 2: Pin/Unpin backup
-- Click pin icon on backup
-- Verify backup marked as pinned
-- Trigger pruning (create 15 backups)
-- Verify pinned backup not deleted

-- Test 3: Delete backup
-- Delete auto-backup
-- Verify no confirmation dialog
-- Delete manual backup
-- Verify confirmation dialog shown
-- Verify backup deleted after confirm

-- Test 4: Cannot delete last 3 backups
-- Delete backups until 3 remain
-- Attempt to delete another
-- Verify error: "Cannot delete - minimum 3 backups required"

-- Test 5: Export backup
-- Click "Export" on backup
-- Verify serialized data copied to clipboard
-- Verify metadata header included
-- Verify can be imported on another client
```

---

### 6.6: Performance Validation

**Status:** ⏳ NOT STARTED

**Note:** Performance benchmarks moved from original 6.5. Conducted as final validation before Phase 6 completion.

#### 6.6.1: Benchmark Testing
- [ ] Measure sync times for different scenarios:
  - [ ] Full structure sync (baseline comparison to Phase 2)
  - [ ] Single raid sync (target: < 15 seconds)
  - [ ] Single encounter sync (target: < 5 seconds)
  - [ ] Single component sync (target: < 1 second)
- [ ] Test with realistic network conditions (in-game raid environment)
- [ ] Measure bandwidth reduction vs Phase 2 full sync
- [ ] Test with maximum data size (40-player raid, all encounters configured)
- [ ] Verify no performance regression in UI responsiveness

**Success Criteria:**
- Single component sync: < 1 second
- Single encounter sync: < 5 seconds
- Single raid sync: < 15 seconds
- Bandwidth reduction: 85%+ vs full sync for component repairs
- No UI lag during sync operations

---

#### 6.6.2: Load Testing
- [ ] Test concurrent sync requests (5+ players simultaneously)
- [ ] Test sync during combat (no performance impact)
- [ ] Test sync during zone transitions (no message loss)
- [ ] Test maximum backup history (10 backups, no OOM errors)
- [ ] Verify graceful degradation under load (queue, don't drop)

**Success Criteria:**
- Handle 5+ concurrent sync requests without message loss
- No FPS drop during sync operations
- No OOM errors with 10 backups + full data
- Queue properly handles burst requests

---

### 6.7: Documentation & Migration

**Status:** ⏳ NOT STARTED

#### 6.7.1: Code Documentation
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

- [ ] All 6.1-6.7 tasks completed
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

---

## Phase 6.3 Status Update (January 22, 2026)

**Implementation:** ✅ COMPLETE  
**Testing:** ⏳ PENDING

### Completed Items
- ✅ Created `Infrastructure/SyncGranular.lua` (950+ lines)
- ✅ Implemented component-level sync (all 6 components)
- ✅ Implemented encounter-level sync (atomic batch updates)
- ✅ Implemented raid-level sync (metadata + all encounters)
- ✅ Implemented global component sync (tradeItems, consumes, rgo)
- ✅ Added 8 new message types to MessageTypes.lua
- ✅ Message handlers registered automatically via Initialize()
- ✅ Repair prioritization system (CRITICAL → HIGH → NORMAL → LOW)
- ✅ Sync queue with priority-based execution
- ✅ Integration with Phase 6.2 validation (QueueRepair function)
- ✅ Test function created (TestGranularSync)
- ✅ Module initialization added to Core.lua
- ✅ TOC file updated

### Key Features
- **Priority-Based Repair**: Current raid/encounter = CRITICAL, same raid = HIGH, other raids = NORMAL
- **Queued Execution**: Serializes sync operations to prevent conflicts
- **Atomic Updates**: Encounter/raid syncs apply all-or-nothing
- **Permission Validation**: All sync operations validate sender permissions
- **Checksum Recomputation**: Automatic checksum updates after data changes
- **UI Refresh Hooks**: Triggers UI updates after successful sync

### Pending Items
- [ ] In-game testing with 2+ clients
- [ ] Test component sync (single component update)
- [ ] Test encounter sync (all 6 components)
- [ ] Test raid sync (all encounters)
- [ ] Test global component sync (rgo, consumes, tradeItems)
- [ ] Validate repair prioritization logic
- [ ] Performance benchmarking (< 5s for encounter sync)
- [ ] Integration with Phase 6.4 (automatic repair)

### Testing Commands
```lua
/ogrh test granular   -- Test granular sync system
/ogrh test all        -- Run all tests including Phase 6.3
```

