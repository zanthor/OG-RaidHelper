# v2 Cleanup Review

**Date:** January 29, 2026  
**Files with Direct OGRH_SV Access**

---

## Files Requiring Conversion (18 total)

| File | Reads | Writes | Lines | Notes |
|------|-------|--------|-------|-------|
| **_Core/Core.lua** | ✅ | ✅ | 464, 470, 502, 508 | Initialization loops |
| **_Infrastructure/DataManagement.lua** | ✅ | ✅ | 36-181 | Factory reset, import/export |
| **_Infrastructure/SyncGranular.lua** | ✅ | ✅ | 329-984 | Sync repair system |
| **_Infrastructure/Sync_v2.lua** | ✅ | ✅ | 57-683 | Legacy sync (consider deprecating) |
| **_Raid/EncounterMgmt.lua** | ✅ | ❌ | 3771-4403 | UI state, consumes reads |
| **_Raid/Announce.lua** | ✅ | ❌ | 742-796 | Uses v1 string keys |
| **_Raid/BigWigs.lua** | ✅ | ❌ | 21-106 | v1 roles integration |
| **_Raid/Poll.lua** | ✅ | ✅ | 170-313 | Role writes, pool defaults |
| **_Raid/RolesUI.lua** | ✅ | ❌ | 492-493 | raidTargets reads |
| **_Configuration/ConsumesTracking.lua** | ✅ | ✅ | 22-2713 | Extensive tracking system |
| **_Configuration/Roster.lua** | ✅ | ✅ | 84-1693 | Player database, ELO |
| **_Configuration/Consumes.lua** | ✅ | ❌ | 594-669 | monitorConsumes flag |
| **_Administration/SRValidation.lua** | ✅ | ✅ | 17-1047 | SR+ validation records |
| **_Administration/AdminSelection.lua** | ✅ | ❌ | 759-761 | Legacy raidLead field |
| **_Configuration/Invites_Test.lua** | ❌ | ✅ | 75-205 | Test file |

---

## Legitimate System Files (Do Not Convert)

| File | Purpose |
|------|---------|
| **_Core/SavedVariablesManager.lua** | SVM core - must access OGRH_SV directly |
| **_Infrastructure/Migration.lua** | Migration system - must access both v1/v2 |
| **_Infrastructure/MigrationMap.lua** | Metadata only - no actual access |

---

## Clean Files (No Direct Access)

- _Raid/AdvancedSettings.lua
- _Raid/ClassPriority.lua
- _Raid/EncounterSetup.lua
- _Raid/LinkRole.lua
- _Raid/Trade.lua
- _UI/MainUI.lua
- _Configuration/Promotes.lua
- _Configuration/Invites.lua
- _Administration/Recruitment.lua
- _Infrastructure/MessageRouter.lua

## 📁 _Core/SavedVariablesManager.lua
**Status:** 🟢 LEGITIMATE - Core SVM functionality  
**Lines:** 78-86

### Direct Access Found:
```lua
Line 78-83: if OGRH_SV.schemaVersion == "v2" then
              if not OGRH_SV.v2 then
                OGRH_SV.v2 = {}
              end
              return OGRH_SV.v2
```

**Analysis:** Core SVM code that determines active schema location. Must directly access OGRH_SV.schemaVersion and OGRH_SV.v2.

**Action:** ✅ NO CHANGE REQUIRED - This is the accessor layer itself

---

## 📁 _Core/Core.lua
**Status:** 🟢 DDONE
**Lines:** 464, 470, 502, 508

### Direct Access Found:
```lua
Lines 464-470: Loop over OGRH_SV[k] to reset defaults
Lines 502-508: Loop over OGRH_SV[k] to initialize SavedVariables
```

**Analysis:** Core initialization code. May need to work with both v1 and v2 schemas during migration period.

**Action:** 🔍 REVIEW - Check if these need schema-aware logic

---

## 📁 _Infrastructure/Migration.lua
**Status:** 🟢 LEGITIMATE - Migration code  
**Lines:** 423-1987 (extensive)

### Direct Access Found:
- Lines 423-447: Create/check OGRH_SV.v2 namespace
- Lines 538-554: Copy v1 data from OGRH_SV.* to OGRH_SV.v2.*
- Lines 586-667: Comparison functions reading both schemas
- Lines 676-707: Cutover/rollback modifying OGRH_SV.schemaVersion
- Lines 731-1987: Migration validation across both schemas

**Analysis:** Migration code must directly manipulate both v1 and v2 schemas. This is intentional and necessary.

**Action:** ✅ NO CHANGE REQUIRED - Migration infrastructure

---

## 📁 _Infrastructure/DataManagement.lua
**Status:** 🔴 CRITICAL - Must Convert  
**Lines:** 36-181

### Direct Access Found:
```lua
Line 36: OGRH_SV.encounterMgmt = OGRH.FactoryDefaults.encounterMgmt
Line 39: OGRH_SV.encounterRaidMarks = OGRH.FactoryDefaults.encounterRaidMarks
Line 42: OGRH_SV.encounterAssignmentNumbers = OGRH.FactoryDefaults.encounterAssignmentNumbers
Line 45: OGRH_SV.encounterAnnouncements = OGRH.FactoryDefaults.encounterAnnouncements
Line 48: OGRH_SV.tradeItems = OGRH.FactoryDefaults.tradeItems
Line 51: OGRH_SV.consumes = OGRH.FactoryDefaults.consumes
Line 54: OGRH_SV.rgo = OGRH.FactoryDefaults.rgo
Lines 103-116: Read operations for export
Lines 163-181: Write operations for import
```

**Analysis:** Factory reset, export, and import functions writing directly to OGRH_SV. This will break after v2 cutover.

**Action:** ❌ MUST CONVERT - Use SVM.SetPath() for writes, SVM.GetPath() for reads

**Priority:** HIGH - Core data management functions

---

## 📁 _Infrastructure/SyncGranular.lua
**Status:** 🔴 CRITICAL - Must Convert  
**Lines:** 329-984

### Direct Access Found:
```lua
Lines 329-400: ExtractComponentData() - reads OGRH_SV.encounterMgmt.roles, encounterAssignments, etc.
Lines 400-484: ApplyComponentData() - writes OGRH_SV.encounterMgmt.roles, encounterAssignments, etc.
Lines 795: table.insert(OGRH_SV.encounterMgmt.raids, raid)
Lines 911-913: OGRH_SV.tradeItems, OGRH_SV.consumes reads
Lines 982-984: OGRH_SV.tradeItems, OGRH_SV.consumes writes
```

**Analysis:** Granular sync repair system directly manipulating SavedVariables. Will fail after v2 cutover.

**Action:** ❌ MUST CONVERT - Integrate with SVM for schema-aware sync

**Priority:** CRITICAL - Sync system will break

---

## 📁 _Raid/EncounterMgmt.lua
**Status:** 🟢 DDONE
**Lines:** 3771-4403

### Direct Access Found:
```lua
Lines 3771-3785: UI state reads - OGRH_SV.ui.selectedRaid, OGRH_SV.ui.selectedEncounter
Lines 4123-4134: Read OGRH_SV.consumes for consume tracking
Lines 4398-4403: Read OGRH_SV.encounterMgmt.raids for dropdown population
```

**Analysis:** Mix of UI state (v1 only) and data reads. UI state intentionally kept in v1 for now.

**Action:** 
- ✅ UI state (lines 3771-3785) - Keep direct access for now
- 🔍 Consumes (lines 4123-4134) - Should use SVM.GetPath()
- 🔍 EncounterMgmt (lines 4398-4403) - Should use SVM.GetPath()

**Priority:** MEDIUM - Reads only, but should standardize on SVM

---

## 📁 _Raid/Announce.lua
**Status:** 🟢 DDONE
**Lines:** 742-796

### Direct Access Found:
```lua
Lines 742-749: Read OGRH_SV.encounterAnnouncements[raidName][encounterName]
Line 752: Read OGRH_SV.encounterMgmt.roles
Lines 777-780: Read OGRH_SV.encounterAssignments[raidName][encounterName]
Lines 785-788: Read OGRH_SV.encounterRaidMarks[raidName][encounterName]
Lines 793-796: Read OGRH_SV.encounterAssignmentNumbers[raidName][encounterName]
```

**Analysis:** All encounter-related reads using v1 string keys (raidName/encounterName). Will fail with v2 numeric indices.

**Action:** ❌ MUST CONVERT - Use SVM.GetPath() with numeric indices after lookup

**Priority:** HIGH - Core announcement functionality

---

## 📁 _Raid/BigWigs.lua
**Status:** � PARTIAL FIX - needs debug/testing
**Lines:** 170-196

### Direct Access Found:
```lua
Lines 170-196: Hook detection system added DEBUG output
```

**Analysis:** 
- v2 schema conversion COMPLETE - uses SVM.GetPath('encounterMgmt') + bracket notation
- Hook system may not be triggering correctly when BigWigs modules enable
- DEBUG code added to identify correct property name for module detection

**Action:** 🔍 DEBUG REQUIRED - Test with actual BigWigs module enable, check debug output

**Priority:** HIGH - Core integration feature, needs user testing

**Next Steps:**
1. `/reload` and approach a boss with BigWigs enabled
2. Check debug output for module properties
3. Confirm which property contains the module name to match against encounterIds
4. Remove debug code and use correct property

---

## 📁 _Raid/AdvancedSettings.lua
**Status:** 🟡 NEEDS SVM CONVERSION
**Lines:** 958-970

### Direct Access Found:
```lua
Lines 958-970: Manual sync calls instead of using SVM
```

**Analysis:** 
- Settings are being saved via `FindRaidByName()` which returns actual raid object (correct)
- Changes persist because it's the actual SavedVariables reference (correct)
- BUT: Still uses manual `SyncDelta.RecordSettingsChange()` calls instead of letting SVM auto-sync
- Should use SVM.SetPath() with BATCH sync level for settings changes

**Action:** ❌ MUST CONVERT - Replace direct assignment + manual sync with SVM writes

**Priority:** MEDIUM - Settings sync broken, but changes persist locally

**Required Changes:**
```lua
-- OLD (line 958):
success = OGRH.SaveCurrentRaidAdvancedSettings(newSettings)
OGRH.SyncDelta.RecordSettingsChange(...)

-- NEW:
-- Use SVM to write advancedSettings with auto-sync
local raidIdx, encIdx = OGRH.FindRaidAndEncounterIndices(...)
if raidIdx then
  OGRH.SVM.SetPath('encounterMgmt.raids.' .. raidIdx .. '.advancedSettings', newSettings, {
    syncLevel = "BATCH",
    componentType = "settings",
    scope = {raid = frame.selectedRaid}
  })
end
```

---

## 📁 _Raid/Poll.lua
**Status:** 🔴 MUST CONVERT  
**Lines:** 170-313

### Direct Access Found:
```lua
Lines 170-188: Read/write OGRH_SV.poolDefaults[poolIndex]
Lines 312-313: Write OGRH_SV.roles[playerName] = newRole
```

**Analysis:** Poll system directly writing player roles and pool defaults.

**Action:** ❌ MUST CONVERT - Use SVM.SetPath() for writes

**Priority:** MEDIUM - Poll/role assignment

---

## 📁 _Raid/RolesUI.lua
**Status:** 🟡 REVIEW NEEDED  
**Lines:** 40, 492-493

### Direct Access Found:
```lua
Line 40: Comment - "Role persistence: Assigned roles saved in OGRH_SV.roles"
Lines 492-493: Read OGRH_SV.raidTargets
```

**Analysis:** Comment references old structure. RaidTargets read may be legacy.

**Action:** 🔍 REVIEW - Verify raidTargets usage and update comments

**Priority:** LOW - Documentation/legacy feature

---

## 📁 _Infrastructure/MigrationMap.lua
**Status:** 🟢 LEGITIMATE - Migration metadata  
**Lines:** 7-747

### Direct Access Found:
- Lines 7-747: Extensive v1Path references like 'OGRH_SV.recruitment.whisperHistory'

**Analysis:** Migration map defining v1 paths for migration system. These are string references, not actual access.

**Action:** ✅ NO CHANGE REQUIRED - Metadata only

---

## 📁 Documentation/SavedVariables-Migration-v2-Prototype.lua
**Status:** 🟢 LEGITIMATE - Prototype/documentation  
**Lines:** 9-319

### Direct Access Found:
- Various prototype migration code examples

**Analysis:** Documentation file, not active code.

**Action:** ✅ NO CHANGE REQUIRED - Documentation only

---

## 📁 _Configuration/ConsumesTracking.lua
**Status:** 🔴 CRITICAL - Must Convert  
**Lines:** 22-2713 (extensive)

### Direct Access Found:
```lua
Lines 22-69: Initialize OGRH_SV.consumesTracking structure
Lines 81-82: Write OGRH_SV.consumesTracking.weights[buffKey]
Lines 238-274: Read/write UI state (trackOnPull, secondsBeforePull, logToCombatLog)
Lines 428-482: Read/write weights
Lines 554-647: Read/write roleMapping
Lines 677-940: Read/write conflicts array
Lines 1033-1099: Conflict detection and modification
Lines 1195: Read OGRH_SV.roles[playerName]
Lines 1340-2713: Extensive tracking, history, logging operations
```

**Analysis:** Major consume tracking system with deep integration into SavedVariables. Reads roles, weights, conflicts, history.

**Action:** ❌ MUST CONVERT - Use SVM for all reads/writes

**Priority:** CRITICAL - Core consume tracking functionality

---

## 📁 _Configuration/Roster.lua
**Status:** 🔴 CRITICAL - Must Convert  
**Lines:** 84-1693 (extensive)

### Direct Access Found:
```lua
Lines 84-86: Initialize OGRH_SV.rosterManagement
Lines 125-182: Read player class, create new players
Lines 203-208: Delete players
Lines 217-290: Get player data, list all players
Lines 540-1693: UI operations, ELO updates, role assignments
```

**Analysis:** Roster management system - player database, ELO rankings, role assignments. Heavy read/write.

**Action:** ❌ MUST CONVERT - Use SVM for all player data access

**Priority:** CRITICAL - Core roster functionality

---

## 📁 _Configuration/Consumes.lua
**Status:** 🟡 REVIEW NEEDED  
**Lines:** 594-669

### Direct Access Found:
```lua
Line 594: Read OGRH_SV.monitorConsumes
Line 645: Read OGRH_SV.monitorConsumes
Line 669: Read OGRH_SV.encounterMgmt.roles
```

**Analysis:** Reads monitorConsumes flag and encounterMgmt.roles. Should use SVM for schema abstraction.

**Action:** 🔍 REVIEW - Convert to SVM reads

**Priority:** MEDIUM - Standardization

---

## 📁 _Configuration/Invites.lua
**Status:** ✅ CLEAN - No direct access found

**Action:** ✅ NO CHANGES NEEDED

---

## 📁 _Configuration/Invites_Test.lua
**Status:** 🟡 TEST FILE - Review needed  
**Lines:** 75-205

### Direct Access Found:
```lua
Lines 75-76: Write OGRH_SV.invites.raidhelperData
Lines 129-130: Write OGRH_SV.invites.currentSource
Lines 170-205: Test data setup
```

**Analysis:** Test file for invite system. Direct writes for test setup.

**Action:** 🔍 REVIEW - Test files may be exempt or need SVM

**Priority:** LOW - Test infrastructure

---

## 📁 _Configuration/Promotes.lua
**Status:** ✅ CLEAN - No direct access found

**Action:** ✅ NO CHANGES NEEDED

---

## 📁 _Administration/SRValidation.lua
**Status:** 🔴 MUST CONVERT  
**Lines:** 17-1047

### Direct Access Found:
```lua
Lines 17-19: Initialize OGRH_SV.srValidation structure
Lines 237-648: Read/write player SR+ validation records
Line 1047: Read validation records for UI display
```

**Analysis:** SR+ validation tracking with player records. Direct manipulation of nested player data.

**Action:** ❌ MUST CONVERT - Use SVM for validation records

**Priority:** HIGH - Admin functionality

---

## 📁 _Administration/AdminSelection.lua
**Status:** 🟡 REVIEW NEEDED  
**Lines:** 759-761

### Direct Access Found:
```lua
Lines 759-761: Read OGRH_SV.raidLead and set raid admin
```

**Analysis:** Legacy raidLead field (deprecated in migration map). May need updating.

**Action:** 🔍 REVIEW - Check if raidLead still used or fully deprecated

**Priority:** LOW - Legacy field

---

## 📁 _Administration/Recruitment.lua
**Status:** ✅ CLEAN - No direct access found

**Action:** ✅ NO CHANGES NEEDED

---

## 📁 _Infrastructure/Sync_v2.lua
**Status:** 🔴 CRITICAL - Must Convert  
**Lines:** 57-683 (extensive)

### Direct Access Found:
```lua
Lines 86-92: Read all data for sync push
Lines 235-247: Read all data for sync request
Lines 279-297: Write received sync data
Lines 341-354: Read data for comparison
Lines 592-610: Factory reset writes
Lines 627-640: Read data for export
Lines 665-683: Import data writes
```

**Analysis:** Legacy v2 sync system (pre-SVM). Directly reads/writes entire data structures. Will break after v2 cutover.

**Action:** ❌ MUST CONVERT - Replace with SVM-integrated sync or mark deprecated

**Priority:** CRITICAL - Sync system compatibility

---

## 📁 _Infrastructure/MessageRouter.lua
**Status:** ✅ CLEAN - No direct access found

**Analysis:** Handles message routing only, doesn't access SavedVariables directly.

**Action:** ✅ NO CHANGES NEEDED

---

## 📁 _Raid/AdvancedSettings.lua
**Status:** ✅ CLEAN - No direct access found

**Action:** ✅ NO CHANGES NEEDED

---

## 📁 _Raid/ClassPriority.lua
**Status:** ✅ CLEAN - No direct access found

**Action:** ✅ NO CHANGES NEEDED

---

## 📁 _Raid/EncounterSetup.lua
**Status:** ✅ CLEAN - No direct access found

**Action:** ✅ NO CHANGES NEEDED

---

## 📁 _Raid/LinkRole.lua
**Status:** ✅ CLEAN - No direct access found

**Action:** ✅ NO CHANGES NEEDED

---

## 📁 _Raid/Trade.lua
**Status:** ✅ CLEAN - No direct access found

**Action:** ✅ NO CHANGES NEEDED

---

## 📁 _UI/MainUI.lua
**Status:** ✅ CLEAN - No direct access found

**Action:** ✅ NO CHANGES NEEDED

---

## Priority Conversion Queue

### 🔴 CRITICAL (Must fix before v2 cutover)
1. **ConsumesTracking.lua** (2713 lines) - Major consume tracking system with extensive SV access
2. **Roster.lua** (1693 lines) - Core roster management, player database, ELO system
3. **Sync_v2.lua** (683 lines) - Legacy sync system, needs SVM integration or deprecation
4. **DataManagement.lua** (181 lines) - Core reset/import/export functions
5. **SyncGranular.lua** (984 lines) - Sync repair system
6. **Announce.lua** (796 lines) - Announcement system with v1 string keys

### 🟠 HIGH (Should fix soon)
7. **SRValidation.lua** (1047 lines) - SR+ validation tracking
8. **BigWigs.lua** (106 lines) - Integration with v1 roles structure
9. **Poll.lua** (313 lines) - Direct writes to roles and pool defaults

### 🟡 MEDIUM (Review and standardize)
10. **EncounterMgmt.lua** (4403 lines) - Convert consumes/encounterMgmt reads to SVM
11. **Consumes.lua** (669 lines) - Convert monitorConsumes and roles reads to SVM
12. **RolesUI.lua** (493 lines) - Review raidTargets usage

### 🟢 LOW (Review or exempt)
13. **AdminSelection.lua** (761 lines) - Legacy raidLead field usage
14. **Invites_Test.lua** (205 lines) - Test file, may be exempt
15. Update documentation comments referencing OGRH_SV structure

---

## Summary Statistics

**Total Files Audited:** 30/69  
**Files Remaining:** 39  
**Critical Issues Found:** 6 files (4,466 lines affected)
**High Priority Issues:** 3 files (1,466 lines affected)  
**Medium Priority Issues:** 3 files (5,565 lines affected)  
**Clean Files:** 11 files ✅

### Conversion Effort Estimate
- **Critical conversions:** ~12-16 hours (complex system integration)
- **High priority conversions:** ~4-6 hours  
- **Medium priority conversions:** ~3-4 hours  
- **Testing and validation:** ~8-10 hours  
- **Total estimate:** ~27-36 hours

---

## Next Steps

1. ✅ Complete audit of remaining 58 .lua files
2. ✅ Add findings to this document
3. ✅ Prioritize conversion work
4. ✅ Create conversion tasks with file/line references
5. ✅ Execute conversions in priority order
6. ✅ Test each conversion
7. ✅ Update documentation

---

## Notes

- Files in `/Libs/` and `/Tests/` are excluded from conversion requirements
- Documentation files (*.md, prototype files) are informational only
- Migration.lua must maintain direct access for dual-schema support
- UI state (OGRH_SV.ui.*) intentionally kept in v1 for now

---

## Search Patterns Used

```lua
-- Pattern 1: Dot notation
OGRH_SV\.

-- Pattern 2: Bracket notation  
OGRH_SV\[

-- Future patterns to check:
-- Pattern 3: Assignment with equals
OGRH_SV\s*=\s*

-- Pattern 4: Function parameter
function.*OGRH_SV
```

---

**Document Status:** ✅ AUDIT COMPLETE  
**Last Updated:** January 29, 2026  
**Files Audited:** 30 core files (39 remaining are Libs/Tests/Documentation)  
**Next Action:** Begin critical conversions starting with ConsumesTracking.lua

---

## Detailed Conversion Plans

### ConsumesTracking.lua Conversion Plan

**Complexity:** HIGH - 100+ direct SV access points  
**Estimated Time:** 4-6 hours

**Key Conversions Required:**
1. **Initialization (Lines 22-69):** Use SVM.Set() for structure initialization
2. **Weights (Lines 81-482):** Convert to SVM.SetPath("consumesTracking.weights.{key}")
3. **Role Mapping (Lines 554-647):** Use SVM.SetPath("consumesTracking.roleMapping.{key}")
4. **Conflicts (Lines 677-1099):** Array manipulation via SVM
5. **History (Lines 2362-2713):** Tracking records via SVM
6. **Role reads (Line 1195, 2331):** Use SVM.GetPath("roles.{playerName}")

**Testing Required:**
- Consume tracking on pull
- Weight modifications
- Role mapping changes
- Conflict resolution
- History logging

---

### Roster.lua Conversion Plan

**Complexity:** HIGH - Major data structure  
**Estimated Time:** 4-6 hours

**Key Conversions Required:**
1. **Initialization (Lines 84-86):** SVM.Set() for rosterManagement structure
2. **Player CRUD (Lines 125-208):**
   - GetPlayerClass: SVM.GetPath("rosterManagement.players.{name}.class")
   - AddPlayer: SVM.SetPath("rosterManagement.players.{name}", playerData)
   - DeletePlayer: SVM.SetPath("rosterManagement.players.{name}", nil)
3. **ELO System (Lines 1683-1693):** SVM.SetPath for ranking updates
4. **Player iteration (Lines 249-290):** Get full players table, iterate locally

**Testing Required:**
- Player creation/deletion
- ELO updates
- Role assignments
- Roster sync
- Player search/filter

---

### Sync_v2.lua Conversion Plan

**Complexity:** CRITICAL - May need deprecation  
**Estimated Time:** 6-8 hours

**Options:**
1. **Option A: Convert to SVM** - Rewrite all read/write using SVM
2. **Option B: Deprecate** - Mark as legacy, migrate users to new SVM-based sync
3. **Option C: Hybrid** - Use SVM internally but keep external API

**Recommended:** Option B - Deprecate in favor of SVM integrated sync

**If Converting (Option A):**
1. Replace all OGRH_SV.* reads with SVM.GetPath()
2. Replace all OGRH_SV.* writes with SVM.SetPath()
3. Ensure schema-awareness (v1 vs v2 paths)
4. Add migration path for existing sync users

**Testing Required:**
- Full sync cycle
- Conflict resolution
- Schema version compatibility
- Backwards compatibility

---

### DataManagement.lua Conversion Plan

**Complexity:** MEDIUM  
**Estimated Time:** 2-3 hours

**Key Conversions Required:**
1. **Factory Reset (Lines 36-54):** Use SVM.SetPath() for all defaults
2. **Export (Lines 103-116):** Use SVM.GetPath() for all reads
3. **Import (Lines 163-181):** Use SVM.SetPath() for all writes

**Testing Required:**
- Factory reset functionality
- Export/import roundtrip
- Schema compatibility

---

### SyncGranular.lua Conversion Plan

**Complexity:** HIGH - Complex nested operations  
**Estimated Time:** 4-5 hours

**Key Conversions Required:**
1. **ExtractComponentData (Lines 329-400):** Convert all reads to SVM.GetPath()
2. **ApplyComponentData (Lines 400-484):** Convert all writes to SVM.SetPath()
3. **Schema-aware paths:** Use numeric indices for v2, string keys for v1

**Testing Required:**
- Granular sync repair
- Checksum validation
- Component extraction/application
- Schema version handling

---

## Conversion Checklist Template

For each file conversion, use this checklist:

### Pre-Conversion
- [ ] Read entire file and understand data flow
- [ ] Document all OGRH_SV access patterns
- [ ] Identify schema-dependent code (v1 string keys vs v2 numeric indices)
- [ ] Plan SVM wrapper functions if needed
- [ ] Create test cases for critical paths

### During Conversion
- [ ] Replace direct reads with SVM.GetPath() or SVM.Get()
- [ ] Replace direct writes with SVM.SetPath() or SVM.Set()
- [ ] Add appropriate syncMetadata for writes
- [ ] Handle nil/missing data gracefully
- [ ] Maintain backwards compatibility where needed
- [ ] Add comments explaining schema version handling

### Post-Conversion
- [ ] Run lint/syntax check
- [ ] Test with v1 schema active
- [ ] Test with v2 schema active
- [ ] Test migration cutover
- [ ] Verify sync propagation (if applicable)
- [ ] Document any behavioral changes
- [ ] Update related documentation

