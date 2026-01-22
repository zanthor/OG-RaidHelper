# DEPRECATED: Raid Group Organizer (RGO)

**Status:** Deprecated as of January 2026  
**Replacement:** Roster Management System (`OGRH_Roster.lua`)

---

## Overview

The Raid Group Organizer (RGO) feature has been deprecated and removed from OG-RaidHelper. This document explains what was removed, why, and what to use instead.

---

## What Was Removed

### File
- **`OGRH_RGO.lua`** (1586 lines) - Commented out in TOC, no longer loaded

### Features
1. **Raid Group Composition Tool**
   - Manual slot assignments per group (1-8)
   - Class priority lists for each slot
   - Role filtering (Tanks, Healers, Melee, Ranged)
   - Raid size templates (10/20/40 man)

2. **Auto-Sort Functionality**
   - Automatic player sorting based on slot priorities
   - `OGRH.PerformAutoSort()` function
   - "Sort Raid" menu item under Invites

3. **SavedVariables**
   - `OGRH_SV.rgo` - Entire namespace removed
   - `OGRH_SV.rgo.raidSizes` - Slot priority configurations
   - `OGRH_SV.rgo.currentRaidSize` - Active raid size setting
   - `OGRH_SV.rgo.completedGroups` - Auto-sort state tracking
   - **Migrated settings:**
     - `OGRH_SV.rgo.autoSortEnabled` → `OGRH_SV.invites.autoSortEnabled`
     - `OGRH_SV.rgo.sortSpeed` → `OGRH_SV.sorting.speed`

4. **Menu Items**
   - "Raid Group Organization" - Main menu item removed
   - "Sort Raid" - Invites submenu item removed

### Functions
- `OGRH.ShowRGOWindow()` - Main RGO interface
- `OGRH.ShowRGOClassPriorityDialog()` - Class priority editor
- `OGRH.EnsureRGOSV()` - SavedVariables initialization
- `OGRH.CleanupInvalidRoleFlags()` - Data validation
- `OGRH.PerformAutoSort()` - Auto-sort execution
- All slot management and priority calculation functions

---

## Why Was It Removed

1. **Functional Overlap**
   - RGO and Roster Management had significant overlap in tracking players and roles
   - Maintaining two separate systems was confusing and error-prone

2. **Code Maintenance Burden**
   - 1586 lines of complex code with intricate UI
   - Difficult to debug and extend
   - Frequent conflicts with other raid management features

3. **Limited Usage**
   - Auto-sort feature was problematic (could disconnect players if too fast)
   - Slot priority system was overly complex for most use cases
   - Roster Management provides more practical functionality

4. **Roster Management Supersedes It**
   - Roster Management provides ELO rankings for skill-based organization
   - More flexible role assignment system
   - Better integration with encounter assignments
   - Cleaner, more maintainable architecture

---

## Migration Guide

### If You Used RGO for Player Tracking

**Before (RGO):**
- Added players to slot priorities
- Assigned class/role preferences per slot
- Used auto-sort to organize raid

**After (Roster Management):**
1. Open: `/ogrh` → Roster Management
2. Import players from raid: "Manual Import" button
3. Assign roles: Click player → Toggle role icons (Tank/Heal/Melee/Ranged)
4. Set rankings: Adjust ELO scores to prioritize skilled players
5. Use Invites window to organize raid groups manually

### If You Used Auto-Sort

**Status:** Auto-sort functionality has been removed entirely.

**Alternatives:**
1. **Manual Organization**
   - Use Invites window to drag/drop players into groups
   - Reference Roster Management for player rankings/roles

2. **Role-Based Filtering**
   - Roster Management shows players filtered by role
   - Sort by ELO ranking to see best players first
   - Manually assign to groups based on composition needs

### If You Used Slot Priorities

**Status:** Slot priority system has been removed.

**Alternative:**
- Use Roster Management ELO rankings to track player skill/priority
- Higher ELO = higher priority for raid slots
- Adjust ELO manually or integrate with DPS/performance tracking

---

## Data Migration

### Automatic Migration (Runs on Addon Load)

When you load OG-RaidHelper after this update, the migration function automatically:

1. **Preserves** these settings by moving them:
   - `OGRH_SV.rgo.autoSortEnabled` → `OGRH_SV.invites.autoSortEnabled`
   - `OGRH_SV.rgo.sortSpeed` → `OGRH_SV.sorting.speed`

2. **Deletes** these permanently:
   - `OGRH_SV.rgo.raidSizes` (slot priorities)
   - `OGRH_SV.rgo.currentRaidSize`
   - `OGRH_SV.rgo.completedGroups`
   - Entire `OGRH_SV.rgo` table removed

3. **Shows** confirmation message:
   ```
   [Migration] Cleaned up deprecated RGO settings
   ```

### Verify Migration

After loading the addon, verify migration completed:

```lua
-- Should return nil (RGO data removed)
/dump OGRH_SV.rgo

-- Should show migrated value (or false if never set)
/dump OGRH_SV.invites.autoSortEnabled

-- Should show migrated value (or nil if never set)
/dump OGRH_SV.sorting.speed
```

### Manual Rollback (If Needed)

If you need to revert:

1. **Restore RGO file in TOC:**
   ```toc
   OGRH_RGO.lua
   OGRH_Roster.lua
   ```

2. **Restore settings manually:**
   ```lua
   OGRH_SV.rgo = {
     autoSortEnabled = OGRH_SV.invites.autoSortEnabled,
     sortSpeed = OGRH_SV.sorting.speed
   }
   ```

3. `/reload` to reload addon

---

## Frequently Asked Questions

### Q: Can I still use auto-sort?
**A:** No, auto-sort has been completely removed. It was problematic and could cause disconnects.

### Q: How do I organize my raid now?
**A:** Use the Invites window for manual organization and Roster Management for player tracking and role assignments.

### Q: Will my RGO data be preserved?
**A:** No. Only the two settings (autoSortEnabled and sortSpeed) are migrated. All slot priorities and raid size configurations are deleted.

### Q: Can I export my RGO data before upgrading?
**A:** Yes, use `/ogrh export` before upgrading. However, RGO data cannot be imported back after migration completes.

### Q: What happens to roster data?
**A:** Roster Management data (`OGRH_SV.rosterManagement`) is completely separate and **not affected** by RGO removal.

### Q: Why isn't there a migration path for slot priorities?
**A:** The RGO and Roster systems are architecturally different. Slot priorities don't map cleanly to ELO rankings. Manual re-configuration in Roster Management is recommended.

### Q: Can I still access old RGO exports?
**A:** Old exports that include RGO data can still be imported for backward compatibility, but the RGO portion will be ignored.

---

## Technical Details

### Code Changes

**Files Modified:**
- `OG-RaidHelper.toc` - Commented out `OGRH_RGO.lua`
- `OGRH_Core.lua` - Added migration function, removed menu items
- `OGRH_MainUI.lua` - Updated sortSpeed references
- `OGRH_Invites.lua` - Updated autoSortEnabled references
- `OGRH_Sync_v2.lua` - Added deprecation comment

**Files Renamed:**
- `OGRH_RGO_Roster.lua` → `OGRH_Roster.lua`

**Code Reduction:**
- 1586 lines removed from loaded code (~47% reduction)

### Backward Compatibility

**Export/Import:** Old exports with RGO data can be imported, but RGO data is ignored.

**Sync System:** RGO data in sync messages is ignored (syncs as `nil`).

**Factory Defaults:** RGO data in factory defaults is ignored.

---

## Timeline

- **January 2026:** RGO deprecated and removed
- **Replacement:** Roster Management System
- **Migration:** Automatic on addon load

---

## Support

If you encounter issues after RGO removal:

1. **Check migration:** `/dump OGRH_SV.rgo` should return `nil`
2. **Check roster data:** `/dump OGRH_SV.rosterManagement` should be intact
3. **Report issues:** Include error messages and steps to reproduce

---

## See Also

- [Roster Management Documentation](TODO: Add link when available)
- [OG-RaidHelper Design Philosophy](! OG-RaidHelper Design Philososphy.md)
- [RGO Deprecation Plan](PLAN_RGO_Deprecation_Roster_Rename.md)

---

**Last Updated:** January 22, 2026  
**Status:** Complete - RGO fully deprecated and removed
