# SavedVariables Migration System - v1 to v2

## Overview
CSV-driven migration system that transforms OGRH_SV from v1 (string keys) to v2 (numeric indices).

## Files Created/Modified

### New Files
1. **Infrastructure/MigrationMap.lua** (1769 lines)
   - Embedded Lua table with 176 transformation records
   - Generated from Documentation/v1-to-v2-deep-migration-map.csv
   - Loaded as global `_G.OGRH_MIGRATION_MAP`

2. **Infrastructure/Migration.lua** (new version, ~800 lines)
   - Complete migration engine
   - Handles 7 transformation types
   - Provides 4 commands: create, validate, cutover, rollback

### Modified Files
3. **OG-RaidHelper.toc**
   - Added MigrationMap.lua (Phase 2, before Migration.lua)
   - Added Migration.lua (Phase 2, Infrastructure section)

## Migration Commands

```
/ogrh migration create     → Creates OGRH_SV.v2 alongside v1
/ogrh migration validate   → Compares v1 and v2, reports differences
/ogrh migration cutover confirm → Replaces v1 with v2 (backs up v1)
/ogrh migration rollback   → Restores v1 from backup
```

## Transformation Types (176 total records)

1. **NO CHANGE** (135 records)
   - Direct copy from v1 to v2
   - Examples: recruitment, srValidation, consumesTracking, invites, rosterManagement, UI state

2. **PATH CHANGE** (22 records)
   - Path renamed, data preserved
   - Examples: encounterMgmt.raids[raidIdx].advancedSettings, roles[roleIdx].classPriority

3. **STRING KEY -> NUMERIC INDEX** (10 records)
   - Named keys become numeric indices
   - **Fixes spaces-in-names bug**
   - Examples: raids[raidName] → raids[raidIdx], encounters[encounterName] → encounters[encIdx]

4. **STRUCTURAL** (7 records)
   - Complex restructuring
   - **Major change:** encounterMgmt.roles table ELIMINATED
   - Roles moved into encounters[encIdx].roles array
   - column1/column2 flattened into single array with column field

5. **SEMANTIC CHANGE** (2 records)
   - Data structure transformation
   - Examples: ui.selectedRaid (name) → ui.selectedRaidIndex (number)
   - Examples: bigwigs.encounterId → bigwigs.encounterIds (array)

6. **DEPRECATED** (6 records)
   - Fields removed from v2
   - Examples: playerElo (moved to rosterManagement), schemaVersion, healerBoss, healerIcon, tankCategory, tankIcon

7. **NEW FIELD ADDED** (10 records)
   - New v2-only fields
   - Examples: roles[roleIdx].column, roleType, isConsumeCheck, isCustomModule, linkRole, invertFillOrder, etc.

## Migration Strategy

### Phase 1: Migrate encounterMgmt.raids
- Build raid/encounter name-to-index mapping
- Convert raids from keyed table to array
- Convert encounters from keyed table to array
- Store original names as metadata (.name field)

### Phase 2: Migrate encounterMgmt.roles (STRUCTURAL)
- Flatten column1/column2 into single roles array
- Add .column field (1 or 2) to each role
- Move roles from separate table into encounters[encIdx].roles
- Remove roleId field (use array index instead)

### Phase 3: Migrate encounter data (STRING KEY -> INDEX)
- encounterAssignments[raidName][encounterName] → [raidIdx][encIdx]
- encounterRaidMarks[raidName][encounterName] → [raidIdx][encIdx]
- encounterAssignmentNumbers[raidName][encounterName] → [raidIdx][encIdx]
- encounterAnnouncements[raidName][encounterName] → [raidIdx][encIdx]

### Phase 4: Process remaining transformations
- Apply NO CHANGE transformations
- Apply PATH CHANGE transformations
- Skip DEPRECATED fields
- Initialize NEW FIELD defaults

### Phase 5: Apply SEMANTIC transformations
- Convert selectedRaid name to selectedRaidIndex
- Convert selectedEncounter name to selectedEncounterIndex
- Convert single IDs to arrays where needed

## Data Safety

- **Non-destructive:** v1 data preserved in OGRH_SV (top level)
- **Validation:** Compare v1 vs v2 before cutover
- **Rollback:** Full backup created during cutover
- **Testing:** Use v2 data in-game before committing

## Breaking Changes

### Major
1. **Raid/Encounter Access:** `raids[raidName]` → `raids[raidIdx]`
   - Need to lookup index via raidName first
   - Names stored in `raids[idx].name` metadata field

2. **Roles Structure:** `roles[raidName][encounterName].column1[idx]` → `encounters[encIdx].roles[roleIdx]`
   - Completely different path
   - Separate roles table eliminated
   - Column flattened into single array

3. **Spaces in Names:** Fixed by numeric indices
   - Can now have raid/encounter names with spaces
   - Names are just metadata, not keys

### Minor
- UI selection uses indices instead of names
- BigWigs settings use arrays instead of single values
- Some fields renamed (encounterId → encounterIds)

## Next Steps

1. ✅ CSV → Lua table conversion complete
2. ✅ Migration engine implemented
3. ✅ TOC files updated
4. ⏳ Test in-game with real SavedVariables
5. ⏳ Validate all transformations work correctly
6. ⏳ Document rollback procedures
7. ⏳ Create migration guide for users

## Implementation Notes

### CSV-to-Lua Conversion
- PowerShell script converts CSV to embedded Lua table
- Handles escaping, booleans, empty fields
- 1769 lines total (176 records + structure)

### WoW 1.12 Compatibility
- No io.open() available - use embedded data
- Global variable `_G.OGRH_MIGRATION_MAP` set by MigrationMap.lua
- Loaded via TOC before Migration.lua

### Raid/Encounter Index Mapping
- Built dynamically from v1 data
- Order preserved via sortOrder field
- Bidirectional lookup: name ↔ index

### STRUCTURAL Transformation
- Most complex transformation type
- Requires custom logic in MigrateEncounterRoles()
- Flattens 2D column structure to 1D array
- Adds metadata fields (column = 1 or 2)

## Testing Checklist

- [ ] Load addon in-game
- [ ] Run `/ogrh migration create`
- [ ] Verify OGRH_SV.v2 exists
- [ ] Check encounterMgmt.raids is array (not keyed table)
- [ ] Verify raids have .name metadata fields
- [ ] Check encounters[idx].roles exists (roles table eliminated)
- [ ] Run `/ogrh migration validate`
- [ ] Review validation output
- [ ] Test addon functionality with v2 data
- [ ] Run `/ogrh migration cutover confirm`
- [ ] Verify v1 backup exists (OGRH_SV_BACKUP_V1)
- [ ] Test `/ogrh migration rollback`
- [ ] Confirm v1 restored correctly

## Known Issues

None currently. System is ready for in-game testing.

## References

- CSV Map: Documentation/v1-to-v2-deep-migration-map.csv (178 lines, 8 columns)
- V2 Schema: Documentation/v2-Schema-Stable-Identifiers-Design.md
- Original Prototype: Documentation/SavedVariables-Migration-v2-Prototype.lua (archived)
