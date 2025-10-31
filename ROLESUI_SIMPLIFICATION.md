# RolesUI Simplification Summary

## Version Update
- Updated from v1.14.0 to v1.15.0

## Changes Made

### Removed Buttons
1. **Encounter Button** (was right of Poll button)
   - Opened menu to access BWL, AQ40, Naxx encounters
   - Functionality still available via `/ogrh encounter` or addon menu
   - Encounter system fully intact in OGRH_EncounterMgmt.lua

2. **Marks Button** (was below Poll button)
   - Left click: Announced tank marks with assigned healers
   - Right click: Cleared all raid marks
   - Marking functionality integrated into Encounter system
   - Can still mark via encounter planning interface

3. **Test Button** (was below Close button)
   - Generated test raids of 15/25/40 players
   - Used for development/testing
   - Test mode completely removed (OGRH.testMode)

### Removed Player Controls
1. **Raid Target Icons** (left side of each player entry)
   - Cycling buttons for raid marks (Star, Circle, Diamond, etc.)
   - Saved to OGRH_SV.raidTargets
   - Marking now handled exclusively by Encounter system

2. **Up/Down Arrow Buttons** (middle of each player entry)
   - Manual player reordering within columns
   - Saved player order to OGRH_SV.order
   - Replaced with automatic alphabetical sorting

3. **Tank Assignment Icons** (healers column only)
   - Showed which tank the healer was assigned to
   - Saved to OGRH_SV.healerTankAssigns
   - Assignment now handled exclusively by Encounter system

### New Features
1. **Alphabetical Sorting**
   - All players automatically sorted A-Z within their role columns
   - Case-insensitive sorting
   - Applied after every roster update

2. **Cleaner Player Display**
   - Just player name with class color
   - Full width drag/drop area
   - More visual space per player

### Preserved Features
- **Poll Button**: Left click starts poll sequence, right click shows menu
- **Drag/Drop**: Move players between role columns
- **Class Colors**: Player names colored by class
- **Role Persistence**: Role assignments saved in OGRH_SV.roles
- **Auto-refresh**: Updates on RAID_ROSTER_UPDATE event

## Files Modified
- `OGRH_RolesUI.lua`: ~600 lines removed, simplified player display

## Files Unchanged
- `OGRH_EncounterMgmt.lua`: All encounter functionality intact
- `OGRH_Core.lua`: Core addon functionality unchanged
- `OGRH_Poll.lua`: Poll system unchanged
- All other modules: Unchanged

## SavedVariables Impact
### Still Used
- `OGRH_SV.roles[playerName]`: Role assignments (TANKS/HEALERS/MELEE/RANGED)
- `OGRH_SV.rolesUI`: Window position

### No Longer Used (but not removed for compatibility)
- `OGRH_SV.order`: Manual player ordering (replaced with alphabetical)
- `OGRH_SV.raidTargets`: Raid mark assignments (moved to encounter system)
- `OGRH_SV.healerTankAssigns`: Tank assignments (moved to encounter system)

## Testing Checklist
- [ ] Roles window opens with `/ogrh roles`
- [ ] Poll button works (left and right click)
- [ ] Players appear in alphabetical order
- [ ] Drag/drop works between columns
- [ ] Player names show with class colors
- [ ] Role changes persist after reload
- [ ] Window position persists after reload
- [ ] Encounter system still works independently
- [ ] No Lua errors on load or during use

## Rollback Instructions
If you need to revert these changes:
1. Replace `OGRH_RolesUI.lua` with backup from v1.14.0
2. No other files need to be reverted
3. SavedVariables are backward compatible

## Notes
- The encounter system (OGRH_EncounterMgmt.lua) is fully independent and still has all marking and assignment features
- This simplification focuses the Roles UI on its core purpose: managing player role assignments
- Advanced features (marks, assignments, encounter planning) are accessed through the encounter interface
