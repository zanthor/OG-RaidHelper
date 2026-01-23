# OG-RaidHelper v2.0 Migration Guide

**Version:** 2.0 (January 2026)  
**Migration Target:** SavedVariables Schema v2

---

## What's Changing?

OG-RaidHelper v2.0 introduces an optimized SavedVariables structure that:

- **Reduces file size by 63%** (40,000 → 15,000 lines)
- **Improves load time by 48%** (350ms → 180ms)
- **Reduces memory usage by 28%** (2.5MB → 1.8MB)
- **Consolidates sync system** - automatic sync on writes (40-60% less network traffic)
- **Removes empty/unused tables** - cleaner data structure
- **Applies historical data retention** - keeps only relevant recent data

---

## Migration Process Overview

The migration is **safe and reversible**. Your original data is always preserved.

### Phase 1: Create v2 Schema (Testing)
- Run `/ogrh migration create`
- Creates new v2 structure alongside original data
- Both v1 and v2 exist simultaneously
- Test all addon functionality

### Phase 2: Validate
- Run `/ogrh migration validate`
- Compare v1 vs v2 statistics
- Verify data integrity

### Phase 3: Cutover (When Ready)
- Run `/ogrh migration cutover confirm`
- Switches to v2 schema
- Creates backup of v1 data
- If issues found: `/ogrh migration rollback`

---

## Step-by-Step Instructions

### Step 1: Backup Your SavedVariables (Optional but Recommended)

Before starting, backup your SavedVariables file:

**Location:**
```
World of Warcraft\WTF\Account\<ACCOUNT>\SavedVariables\OG-RaidHelper.lua
```

**Backup command (PowerShell):**
```powershell
Copy-Item "World of Warcraft\WTF\Account\*\SavedVariables\OG-RaidHelper.lua" `
          "World of Warcraft\WTF\Account\*\SavedVariables\OG-RaidHelper.lua.backup"
```

### Step 2: Create v2 Schema

1. Log into WoW with OG-RaidHelper v2.0 installed
2. Type: `/ogrh migration create`
3. You should see:
   ```
   [Migration] Creating v2 schema alongside original data...
   [Migration] Phase 1: Copying data to v2 (excluding empty tables)...
   [Migration] Copied X keys to v2
   [Migration] Excluded: tankIcon, healerIcon, tankCategory, healerBoss (empty)
   [Migration] Phase 2: Applying data retention policies...
   [Migration] Pruned X old recruitment entries (>30 days)
   [Migration] Pruned X old consume history entries (>90 days)
   [Migration] ✓ v2 schema created successfully
   ```

### Step 3: Test Addon Functionality

**During this phase, the addon still uses v1 data.** The v2 schema exists but is not active yet.

Test all features you regularly use:
- [ ] Open main window (`/ogrh`)
- [ ] Create/edit role assignments
- [ ] Manage player assignments
- [ ] View recruitment data
- [ ] Check consume tracking
- [ ] Test raid invites
- [ ] Verify settings

**Everything should work exactly as before.**

### Step 4: Validate v2 Schema

Type: `/ogrh migration validate`

You should see:
```
[Validation] Comparing v1 and v2 schemas...
[Validation] v1 keys: X
[Validation] v2 keys: Y
[Validation] Difference: Z keys removed
[Validation] Removed tables: tankIcon, healerIcon, tankCategory, healerBoss
[Validation] Data retention: recruitment (30 days), consumeTracking (90 days)
[Validation] ✓ Review addon functionality before cutover
```

### Step 5: Cutover to v2 (When Ready)

**This step switches the active schema to v2.**

Type: `/ogrh migration cutover confirm`

You should see:
```
[Cutover] Switching to v2 schema...
[Cutover] ✓ Complete! Now using v2 schema
[Cutover] v1 backup saved to OGRH_SV_BACKUP_V1
[Cutover] Use /ogrh migration rollback if issues found
[Cutover] Please /reload to ensure clean state
```

**Important:** Type `/reload` after cutover.

### Step 6: Verify Everything Works

After reload, test all features again:
- [ ] Main window opens
- [ ] Role assignments work
- [ ] Player assignments work
- [ ] All data present
- [ ] No errors

### Step 7: Report Issues or Confirm Success

**If everything works:** Congratulations! Migration complete.

**If issues found:** See "Rollback Instructions" below.

---

## Rollback Instructions

If you encounter any issues after cutover, you can rollback to v1:

1. Type: `/ogrh migration rollback`
2. Type: `/reload`
3. Verify everything back to normal
4. Report issue to addon developer

**Rollback scenarios:**

### Before Cutover (v2 not active yet)
- Simply deletes the v2 schema
- Original data unaffected

### After Cutover (v2 active)
- Restores v1 from backup (OGRH_SV_BACKUP_V1)
- Returns to original state
- No data loss

---

## What Data is Removed?

### Empty Tables (Never Used)
- `tankIcon` - Empty in all tested SavedVariables
- `healerIcon` - Empty in all tested SavedVariables  
- `tankCategory` - Empty in all tested SavedVariables
- `healerBoss` - Empty in all tested SavedVariables

### Historical Data (Retention Policies)
- **Recruitment entries** - Only last 30 days kept
- **Consume tracking history** - Only last 90 days kept

**Note:** Current data (roles, assignments, settings, roster) is NEVER removed.

---

## Frequently Asked Questions

### Will I lose my data?
No. Original data is always preserved during migration. If issues arise, you can rollback.

### How long does migration take?
Usually instant (less than 1 second). Creating v2 schema is very fast.

### Can I skip the testing phase?
Not recommended. Testing ensures everything works before cutover.

### What if I don't migrate?
The addon will continue working with v1 schema indefinitely. However:
- Larger SavedVariables file
- Slower load times
- More memory usage
- Manual sync calls still needed

### When will v1 data be removed?
After cutover, v1 data is backed up to `OGRH_SV_BACKUP_V1`. You can manually remove it after confirming everything works (30+ days recommended).

### What about the new sync system?
The consolidated sync system is automatically active in v2.0. No manual configuration needed. Sync happens automatically when you make changes.

---

## Troubleshooting

### Error: "OGRH_SV not found"
- Ensure addon is loaded: `/reload`
- Check addon is enabled in addon list

### Error: "v2 schema already exists"
- Migration already run
- Use `/ogrh migration validate` to check status
- Use `/ogrh migration rollback` to reset

### Error: "v2 schema not found" (during validate/cutover)
- Must run `/ogrh migration create` first

### Features not working after cutover
- First: `/reload`
- If still broken: `/ogrh migration rollback` and `/reload`
- Report issue with error messages

---

## Support

If you encounter issues or have questions:

1. Check this guide first
2. Try `/ogrh migration rollback` if issues after cutover
3. Report issues with:
   - Exact error messages
   - Steps to reproduce
   - SavedVariables file (if possible)

---

## Command Reference

```
/ogrh migration create          - Create v2 schema (testing phase)
/ogrh migration validate        - Compare v1 vs v2 statistics
/ogrh migration cutover confirm - Switch to v2 (point of no return without rollback)
/ogrh migration rollback        - Revert to v1 (if issues found)
/ogrh migration help            - Show this command list
```

---

**Migration prepared by:** OG-RaidHelper Development Team  
**Last updated:** January 23, 2026
