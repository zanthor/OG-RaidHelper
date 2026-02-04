# Phase 2: Write Migration Tracker

**Project:** SavedVariables v2.0 + Sync Consolidation  
**Phase:** Phase 2 - Migrate Write Calls  
**Start Date:** TBD  
**Target Completion:** Week 2  

---

## Overview

**Goal:** Convert all direct `OGRH_SV` write operations to use `OGRH.SVM.SetPath()` with appropriate sync metadata.

**Success Criteria:**
- ✅ All write operations use SVM
- ✅ All manual sync calls removed (OGRH.SyncDelta.RecordXYZChange)
- ✅ Sync happens automatically on writes
- ✅ Network traffic reduced by 40-60%
- ✅ No sync bugs in testing

---

## Discovery Phase Results ✅

**Status:** COMPLETE  
**Date:** January 23, 2026

### Summary

**Writes Found:** ~170 direct OGRH_SV writes  
**Sync Calls Found:** 41 manual sync calls to remove  
**Files Analyzed:** 16 files need migration

### Breakdown by Category

| Category | Files | Writes | Sync Calls |
|----------|-------|--------|------------|
| **Combat-Critical** | 4 | 32 | 35 |
| **Configuration** | 4 | 57+ | 6 |
| **Administrative** | 4 | 14 | 0 |
| **UI State (Local)** | 2 | 9 | 0 |
| **Infrastructure** | 2 | 0 (recv) | 0 |
| **TOTAL** | **16** | **~170** | **41** |

### Key Findings

1. **Highest Impact:** Raid/EncounterMgmt.lua (21 writes + 12 sync calls)
2. **Most Sync Calls:** Raid/EncounterSetup.lua (22 structure sync calls)
3. **Highest Write Count:** Configuration/Invites.lua (30+ local writes)
4. **No Migration Needed:** MessageRouter.lua, SyncGranular.lua (already integrated)
5. **Local-Only:** UI state files don't need sync

### Recommended Conversion Order

1. **Week 2, Day 1-2:** Raid/EncounterMgmt.lua + Raid/EncounterSetup.lua (CRITICAL path)
2. **Week 2, Day 3:** Core/Core.lua active writes (player assignments, roles)
3. **Week 2, Day 4:** Raid/RolesUI.lua + AdvancedSettings.lua + ClassPriority.lua (sync call removal)
4. **Week 2, Day 5:** Configuration files (Consumes, ConsumesTracking, Roster)
5. **Week 2, Day 6-7:** Testing & validation

---

## Migration Strategy

### Priorities (Highest Impact First)

1. **🔴 CRITICAL - Combat Data (REALTIME sync)**
   - Role assignments (12 locations)
   - Player assignments (8 locations)
   - Swap operations (5 locations)

2. **🟡 HIGH - Configuration Data (BATCH sync)**
   - Settings updates (6 locations)
   - Consumable tracking
   - Encounter configurations

3. **🟢 MEDIUM - Administrative Data (BATCH sync)**
   - Roster management
   - Notes/metadata
   - UI state

4. **⚪ LOW - Structure Data (MANUAL sync)**
   - Raid/encounter creation
   - Template operations
   - Schema changes

---

## File Analysis Checklist

### Group 1: Core Encounter Management (CRITICAL)

#### 📁 Raid/EncounterMgmt.lua
- **Status:** ⚪ NOT STARTED
- **Priority:** 🔴 CRITICAL
- **Writes Found:** 21 encounterAssignments writes + 1 role initialization
- **Write Types:**
  - Drag-drop player assignments (10 locations)
  - Slot assignments via messages (7 locations)
  - Clear assignments (3 locations)
  - Role structure initialization (1 location)
- **Sync Calls to Remove:**
  - `OGRH.SyncDelta.RecordAssignmentChange()` - 10 locations
  - `OGRH.SyncDelta.RecordSwapChange()` - 2 locations
- **Notes:** Highest traffic file - drag-drop operations in encounter UI

**Tasks:**
- [x] Grep search completed - 21 writes found
- [ ] Convert drag-drop assignments (lines 2440-2450, 3319-3342)
- [ ] Convert swap operations (lines 3345-3369)
- [ ] Convert clear operations (lines 155, 3436)
- [ ] Remove 12 manual sync calls
- [ ] Test drag-drop with 2+ clients
- [ ] Test swap operations

---

#### 📁 Raid/RolesUI.lua
- **Status:** ⚪ NOT STARTED
- **Priority:** 🔴 CRITICAL
- **Writes Found:** 0 direct writes (uses Core.lua functions)
- **Write Types:**
  - Calls `OGRH.Roles.AddToRole()` which writes to Core.lua
- **Sync Calls to Remove:**
  - `OGRH.SyncDelta.RecordRoleChange()` - 1 location (line 220)
- **Notes:** Only sync call, actual writes happen in Core.lua via function calls

**Tasks:**
- [x] Grep search completed - no direct writes, 1 sync call
- [ ] Remove sync call at line 220
- [ ] Verify AddToRole() handles sync (check Core.lua migration)
- [ ] Test drag-drop after Core.lua conversion

---

#### 📁 Raid/PlayerAssignments.lua
- **Status:** ⚪ NOT STARTED
- **Priority:** 🔴 CRITICAL
- **Estimated Writes:** 8-10
- **Write Types:**
  - Mark assignments (skull → ✅ NO FILE EXISTS
- **Priority:** 🔴 CRITICAL → N/A
- **Writes Found:** 0 (file doesn't exist)
- **Write Types:**
  - playerAssignments writes happen in Core.lua (3 locations)
- **Sync Calls to Remove:** None in this file
- **Notes:** Assignments handled in Core.lua lines 90, 3953, 3957

**Tasks:**
- [x] Verified file doesn't exist - writes in Core.lua
- [ ] Handle playerAssignments during Core.lua migrationITICAL)

#### 📁 Raid/RaidSwap.lua
- **Status:** ⚪ NOT STARTED
- **Priority:** 🔴 CRITICAL
- **Estimated Writes:** 5-7
- **Write Types:**
  - Player swap operations
  - Swap history tracking
- **Sync Calls to Remove:** → ✅ NO FILE EXISTS
- **Priority:** 🔴 CRITICAL → N/A
- **Writes Found:** 0 (file doesn't exist)
- **Write Types:**
  - Swaps handled in EncounterMgmt.lua
- **Sync Calls to Remove:**
  - Handled in EncounterMgmt.lua (2 locations)
- **Notes:** Swap logic integrated into EncounterMgmt.lua drag-drop

**Tasks:**
- [x] Verified file doesn't exist
- [ ] Handle swaps during EncounterMgmt.lua migration
- **EstimatedEncounterSetup.lua (NEWLY IDENTIFIED)
- **Status:** ⚪ NOT STARTED
- **Priority:** 🔴 CRITICAL
- **Writes Found:** 6 structure writes
- **Write Types:**
  - Role structure initialization (line 613)
  - Encounter rename operations (lines 1415-1416, 1421-1422)
- **Sync Calls to Remove:**
  - `OGRH.SyncDelta.RecordStructureChange()` - 22 locations
- **Notes:** Structure changes (add/delete/reorder raids, encounters, roles)

**Tasks:**
- [x] Grep search completed
- [ ] Convert structure writes (6 locations)
- [ ] Remove 22 sync calls
- [ ] All structure changes should use MANUAL sync (admin push only)
### Group 3: Configuration & Settings (HIGH)

#### 📁 Raid/AdvancedSettings.lua (CORRECTED)
- **Status:** ⚪ NOT STARTED
- **Priority:** 🟡 HIGH
- **Writes Found:** 0 direct writes (reads via EncounterMgmt structure)
- **Write Types:**
  - Settings stored in encounterMgmt.raids[raid].encounters[enc].advancedSettings
  - Writes happen through encounterMgmt, not separate settings table
- **Sync Calls to Remove:**
  - `OGRH.SyncDelta.RecordSettingsChange()` - 4 locations (lines 962, 969)
- **Notes:** Use BATCH sync, settings nested in encounterMgmt structure

**Tasks:**
- [x] Grep search completed
- [ ] Remove 4 sync calls
- [ ] Verify encounterMgmt migration covers advancedSettings
- [ ] Test batch behavior with multiple setting changes

---

#### 📁 Configuration/Consumes.lua
- **Status:** ⚪ NOT STARTED
- **Priority:** 🟡 HIGH
- **Writes Found:** 7 direct writes to OGRH_SV.consumes
- **Write Types:**
  - Initialize consumes table (lines 99, 328, 362)
  - Reorder consumes (lines 131-132, 138-139)
  - Save consume data (line 504)
- **Sync Calls to Remove:** None found (consumes may not sync)
- **Notes:** May not need sync - likely local configuration

**Tasks:**
- [x] Grep search completed - 7 writes found
- [ ] Determine if consumes should sync (check design)
- [ ] If sync needed: convert 7 writes with BATCH level
- [ ] If no sync: leave as direct writes or use SVM without sync metadata

---

#### 📁 Configuration/Invites.lua
- **Status:** ⚪ NOT STARTED
- **Writes Found:** 30+ writes to OGRH_SV.invites table
- **Write Types:**
  - Initialize invites structure (lines 54-112)
  - Source selection (lines 87, 929, 1406, 1412, 1425, 1426)
  - Settings updates (lines 1065, 1109, 2584)
  - Declined players tracking (lines 682, 689)
  - RaidHelper data imports (lines 1406-1426)
- **Sync Calls to Remove:** None found (invites likely local only)
- **Notes:** High write count but likely local configuration, not synced

**Tasks:**
- [x] Grep search completed - 30+ writes found
- [ ] Verify invites don't need sync (local invite management)
- [ ] If local: consider using SVM for consistency without sync
- [ ] If sync needed: add BATCH level metadatas exist
- [ ] Test invite flow
Configuration/ConsumesTracking.lua (NEWLY IDENTIFIED)
- **Status:** ⚪ NOT STARTED
- **Priority:** 🟡 HIGH (moved from MEDIUM)
- **Writes Found:** 15+ writes to OGRH_SV.consumesTracking
- **Write Types:**
  - Initialize tracking structure (lines 23-69)
  - Settings updates (lines 240, 259, 274)
  - Weight adjustments (lines 82, 467, 482)
  - Role mapping (lines 558, 582, 647)
  - Conflicts (lines 678, 841, 940, 1034)
  - History management (line 2713)
- **Sync Calls to Remove:** None found
- **Notes:** Configuration data, likely BATCH sync or local only

**Tasks:**
- [x] Grep search completed - 15+ writes found
- [ ] Determine sync requirements
- [ ] Convert to SVM with appropriate sync level

---

#### 📁 Administration/Roster.lua
- **Status:** ⚪ NOT STARTED
- **Priority:** 🟢 MEDISRValidation.lua (NEWLY IDENTIFIED)
- **Status:** ⚪ NOT STARTED
- **Priority:** 🟢 MEDIUM
- **Writes Found:** 4 writes to OGRH_SV.srValidation
- **Write Types:**
  - Initialize structure (lines 18-19)
  - Record validation (line 567)
  - Store latest record (line 632)
- **Sync Calls to Remove:** None found
- **Notes:** Validation records, likely local only or BATCH sync

**Tasks:**
- [x] Grep search completed - 4 writes found
- [ ] Determine if validation records should sync
- [ ] Convert to SVM if needed

---

#### 📁 Configuration/Promotes.lua (NEWLY IDENTIFIED)
- **Status:** ⚪ NOT STARTED
- **Priority:** 🟢 MEDIUM
- **Writes Found:** 6 writes to OGRH_SV.ui (all local-only)
- **Write Types:**
  - Initialize UI table (line 18)
  - Save window position (line 20)
  - Lock state (line 432)
  - Remote ready check setting (line 458)
  - Sorting speed (lines 572-573)
- **Sync Calls to Remove:** None (UI state doesn't sync)
- **Notes:** ALL UI state is local-only, no sync needed

**Tasks:**
- [x] Grep search completed - 6 local writes
- [ ] Leave as direct writes (no sync) OR
- [ ] Convert to SVM without syncMetadata for consistency
- [ ] Decision: Keep direct writes for UI state
- [ ] Test roster sync across clientsconfiguration

**Tasks:**
- [ ] Grep search for roster writes
- [ ] Convert roster operations
- [ ] Test roster sync

---

#### 📁 Administration/Notes.lua (if exists)
- **Status:** ⚪ NOT STARTED
- **Priority:** 🟢 MEDIUM
- **Estimated Writes:** 2-4
- **Write Types:**
  - Encounter notes
  - Strategy notes
- **Notes:** Batch sync appropriate

**Tasks:**
- [ ] Verify file exists
- [ ] Analyze write patterns
- [ ] Convert if needed

---Raid/BigWigs.lua (NEWLY IDENTIFIED)
- **Status:** ⚪ NOT STARTED
- **Priority:** 🟢 MEDIUM
- **Writes Found:** 3 writes to OGRH_SV.ui (local-only)
- **Write Types:**
  - Initialize UI table (line 86)
  - Selected raid/encounter (lines 89-90)
- **Sync Calls to Remove:** None
- **Notes:** UI state selection, local only

**Tasks:**
- [x] Grep search completed - 3 local writes
- [ ] Leave as direct writes (UI state)

#### 📁 UI/MainUI.lua
- **Status:** ⚪ NOT STARTED
- **Priority:** 🟢 MEDIUM
- **Estimated Writes:** 3-5
- **Write Types:**
  - Window positions
  - UI state (minimized, etc.)
  - View preferences
- **Notes:** Most UI state should NOT sync (local only)

**Tasks:**
- [ ] Grep search for `OGRH_SV.ui`
- [ ] Identify which state should sync vs stay local
- [ ] Convert only synced state
- [ ] Leave local state as direct writes

---

#### 📁 UI/RolesUI.lua
- **Status:** ⚪ DUPLICATE (See Raid/RolesUI.lua)
- **Notes:** Check if this is separate from Raid/RolesUI.lua

---

### Group 6: Modules & Encounters (MEDIUM)

#### 📁 Modules/*.lua (All encounter modules)
- **Status:** ⚪ NOT STARTED
- **Priority:** 🟢 MEDIUM
- **Estimated Writes:** Varies per module
- **Write Types:**
  - Module-specific data
  - Encounter tracking
- **Notes:** Analyze per module
Core Infrastructure (SPECIAL - Already Integrated)

#### 📁 Core/Core.lua
- **Status:** 🟡 NEEDS ANALYSIS
- **Priority:** 🔴 CRITICAL (foundational)
- **Writes Found:** 50+ writes (mostly initialization)
- **Write Types:**
  - **One-time initialization** (lines 67-84): roles, order, UI, icons, etc.
  - **Migration code** (lines 189-421): Schema v1→v2, data retention
  - **Sync receive handlers** (lines 2331, 2823, 2949, 3147): Already integrated
  - **Player assignments** (lines 90, 3953, 3957): Need conversion
  - **Role assignments** (lines 2565, 2587, 3892): Need conversion
- **Sync Calls to Remove:** None (uses old full sync system)
- **Notes:** Complex - mix of one-time init, migrations, and active writes

**Tasks:**
- [x] Grep search completed - 50+ writes found
- [ ] Categorize: init vs migration vs active writes
- [ ] Convert active writes only (playerAssignments, roles)
- [ ] Leave init code as-is (runs once on load)
- [ ] Leave migration code as-is (v1→v2 transition)

---

#### 📁 Infrastructure/MessageRouter.lua
- **Status:** ✅ ALREADY INTEGRATED
- **Priority:** ⚪ N/A
- **Writes Found:** 15+ sync receive handlers
- **Write Types:**
  - Receive delta sync messages
  - Apply remote changes to OGRH_SV
- **Notes:** These are RECEIVE handlers, not user writes - already integrated

**Tasks:**
- [x] Verified - these handle incoming sync, not outgoing writes
- [ ] No action needed

---

#### 📁 Infrastructure/SyncGranular.lua
- **Status:** ✅ ALREADY INTEGRATED
- **Priority:** ⚪ N/A
- **Writes Found:** 2 sync receive handlers (lines 448, 455)
- **Notes:** Repair system - receives and applies granular sync data

**Tasks:**
- [x] Verified - repair system handlers only
- [ ] No action needed

---

#### 📁 Raid/ClassPriority.lua (NEWLY IDENTIFIED)
- **Status:** ⚪ NOT STARTED
- **Priority:** 🟡 HIGH
- **Writes Found:** 0 direct writes
- **Sync Calls to Remove:**
  - `OGRH.SyncDelta.RecordClassPriorityChange()` - 2 locations (lines 347, 352)
- **Notes:** Writes through encounterMgmt structure

**Tasks:**
- [x] Grep search completed
- [ ] Remove 2 sync calls
- [ ] Verify encounterMgmt migration covers class prioritynt

---

#### 📁 Core/Migration.lua
- **Status:** ⚪ NOT STARTED
- **Priority:** ⚪ LOW
- **Estimated Writes:** Multiple (migration only)
- **Notes:** Migration code writes entire v2 structure

**Tasks:**
- [ ] Review migration script
- [ ] Ensure dual-write support works
- [ ] Test migration → cutover flow

---

## Grep Search Commands (Run These First)

### Find All Direct Writes
```powershell
# Find all direct writes to OGRH_SV
Select-String -Path "*.lua" -Pattern "OGRH_SV\.[a-zA-Z_]+ ?=" -CaseSensitive | Select-Object -First 50

# Find all deep writes (multiple levels)
Select-String -Path "*.lua" -Pattern "OGRH_SV\.[a-zA-Z_]+\.[a-zA-Z_]+ ?=" -CaseSensitive | Select-Object -First 50
```

### Find All Sync Calls (To Be Removed)
```powershell
# Find all SyncDelta calls
Select-String -Path "*.lua" -Pattern "SyncDelta\.Record" -CaseSensitive

# Find all SyncIntegrity calls
Select-String -Path "*.lua" -Pattern "SyncIntegrity\.Record" -CaseSensitive

# Find all explicit sync calls
Select-String -Path "*.lua" -Pattern "BroadcastFullSync|FlushChangeBatch" -CaseSensitive
```

### Find High-Frequency Writes
```powershell
# Role assignments
Select-String -Path "*.lua" -Pattern "encounterMgmt\.roles\[" -CaseSensitive

# Player assignments
Select-String -Path "*.lua" -Pattern "playerAssignments\[" -CaseSensitive

# Settings
Select-String -Path "*.lua" -Pattern "advancedSettings\." -CaseSensitive
```

---

## Conversion Template

For each write location found:

### Before:
```lua
-- Direct write
OGRH_SV.encounterMgmt.roles[raid][enc].column1.slots[slot] = playerName

-- Manual sync call
OGRH.SyncDelta.RecordRoleChange(playerName, roleName, oldPlayer)

-- Manual checksum update
OGRH.SyncIntegrity.RecordAdminModification()
```

### After:4 | ⚪ Not Started | 0% |
| 🟡 HIGH | 4 | ⚪ Not Started | 0% |
| 🟢 MEDIUM | 5 | ⚪ Not Started | 0% |
| ⚪ SPECIAL | 3 | 🟡 Analyzed | 10% |
| **TOTAL** | **16"encounterMgmt.roles.%s.%s.column%d.slots.%d", raid, enc, roleIdx, slot),
    playerName,
    {
        syncLevel = "REALTIME",  -- Choose: REALTIME, BATCH, GRANULAR, MANUAL
        componentType = "roles",  -- Choose: roles, assignments, settings, structure, metadata
        scope = {raid = raid, encounter = enc}  -- For targeted checksums
    }
)

-- That's it! Sync, checksums, batching all automatic.
```

---

## Testing Checklist (Per File)

Af**CRITICAL** |
| Raid/EncounterMgmt.lua | 🔴 | ⚪ | 21 | 0 | 0/12 |
| Raid/EncounterSetup.lua | 🔴 | ⚪ | 6 | 0 | 0/22 |
| Raid/RolesUI.lua | 🔴 | ⚪ | 0 | 0 | 0/1 |
| Core/Core.lua (active writes) | 🔴 | ⚪ | 5 | 0 | 0 |
| **HIGH** |
| Raid/AdvancedSettings.lua | 🟡 | ⚪ | 0 | 0 | 0/4 |
| Raid/ClassPriority.lua | 🟡 | ⚪ | 0 | 0 | 0/2 |
| Configuration/Consumes.lua | 🟡 | ⚪ | 7 | 0 | 0 |
| Configuration/ConsumesTracking.lua | 🟡 | ⚪ | 15+ | 0 | 0 |
| **MEDIUM** |
| Configuration/Invites.lua | 🟢 | ⚪ | 30+ | 0 | 0 |
| Administration/Roster.lua | 🟢 | ⚪ | 6 | 0 | 0 |
| Administration/SRValidation.lua | 🟢 | ⚪ | 4 | 0 | 0 |
| Configuration/Promotes.lua | 🟢 | ⚪ | 4 | 0 | 0 |
| UI/MainUI.lua | 🟢 | ⚪ | 6 (local) | 0 | 0 |
| Raid/BigWigs.lua | 🟢 | ⚪ | 3 (local) | 0 | 0 |
| **SPECIAL** |
| Core/Core.lua (init) | ⚪ | 🟡 | 45+ (init only) | N/A | N/A |
| Infrastructure/MessageRouter.lua | ⚪ | ✅ | 15 (recv) | N/A | N/A |
| Infrastructure/SyncGranular.lua | ⚪ | ✅ | 2 (recv) | N/A | N/A |
| **TOTALS** | | | **~170** | **0** | **0/41**

### Status Key
- ⚪ NOT STARTED
- 🟡 IN PROGRESS
- ✅ COMPLETE
- ❌ BLOCKED

### By Priority

| Priority | Files | Status | Completion % |
|----------|-------|--------|--------------|
| 🔴 CRITICAL | 5 | ⚪ Not Started | 0% |
| 🟡 HIGH | 3 | ⚪ Not Started | 0% |
| 🟢 MEDIUM | 5 | ⚪ Not Started | 0% |
| ⚪ LOW | 2 | ⚪ Not Started | 0% |
| **TOTAL** | **15** | | **0%** |

### By File

| File | Priority | Status | Writes Found | Writes Converted | Sync Calls Removed |
|------|----------|--------|--------------|------------------|-------------------|
| Raid/EncounterMgmt.lua | 🔴 | ⚪ | ? | 0 | 0 |
| Raid/RolesUI.lua | 🔴 | ⚪ | ? | 0 | 0 |
| Raid/PlayerAssignments.lua | 🔴 | ⚪ | ? | 0 | 0 |
| Raid/RaidSwap.lua | 🔴 | ⚪ | ? | 0 | 0 |
| Raid/RaidCooldowns.lua | 🔴 | ⚪ | ? | 0 | 0 |
| Configuration/Settings.lua | 🟡 | ⚪ | ? | 0 | 0 |
| Configuration/Consumes.lua | 🟡 | ⚪ | ? | 0 | 0 |
| Configuration/Invites.lua | 🟡 | ⚪ | ? | 0 | 0 |
| Administration/Roster.lua | 🟢 | ⚪ | ? | 0 | 0 |
| Administration/Notes.lua | 🟢 | ⚪ | ? | 0 | 0 |
| UI/MainUI.lua | 🟢 | ⚪ | ? | 0 | 0 |
| Modules/*.lua | 🟢 | ⚪ | ? | 0 | 0 |
| Core/Templates.lua | ⚪ | ⚪ | ? | 0 | 0 |
| Core/Migration.lua | ⚪ | ⚪ | ? | 0 | 0 |

---

## Network Traffic Metrics (To Measure)

**Goal:** Reduce network traffic by 40-60%

### Baseline (Before Migration)

| Metric | Current | Target |
|--------|---------|--------|
| Messages per role assignment | 3-4 | 1 |
| Checksum broadcasts per 30s | 12 components | 2-3 components |
| Average message size | ~500 bytes | ~300 bytes |
| Batch efficiency | 0% (no batching) | 60%+ (2s batching) |

### To Measure

- [ ] Record MessageRouter traffic before migration
- [ ] Record traffic after each major file conversion
- [ ] Compare total messages sent during 1-hour raid
- [ ] Validate 40-60% reduction achieved

---

## Issues & Blockers

| Issue | Impact | Status | Resolution |
|-------|--------|--------|------------|
| None yet | - | - | - |

---

## Notes & Learnings

### Conversion Patterns Discovered

(Add patterns as we discover them during migration)

### Common Pitfalls

(Document common mistakes to avoid)

### Testing Tips

(Add testing shortcuts discovered during work)

---

## Next Steps

1. **Run grep searches** to populate "Writes Found" column
2. **Start with 🔴 CRITICAL files** (highest impact)
3. **Convert one file at a time** with full testing
4. **Update this tracker** after each file completion
5. **Measure network traffic** before/after each group

---

**Last Updated:** January 23, 2026  
**Phase Status:** 🟡 Ready to Start - Tracker Created
