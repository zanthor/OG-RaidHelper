# Phase 3C: OGRH_RaidLead.lua → OGRH_AdminSelection.lua Migration

**Status:** Planning  
**Date:** January 21, 2026  
**Goal:** Rename file, remove backward compatibility wrappers, and complete MessageRouter migration

---

## Executive Summary

Per the OG-RaidHelper Design Philosophy, **no backward compatibility is maintained**. This document outlines the complete removal of deprecated `IsRaidLead()` and `SetRaidLead()` wrapper functions, replacing all call sites with direct `IsRaidAdmin()` and `SetRaidAdmin()` calls from `OGRH_Permissions.lua`.

### Key Findings

**Architecture is Correct:**
- `OGRH_Permissions.lua` properly separates addon admin from game raid lead/assist
- `OGRH.IsRaidAdmin()` checks addon admin status (custom permission)
- `OGRH.IsRaidOfficer()` checks game L/A status (WoW rank 2/1)
- `OGRH.SetRaidAdmin()` manages addon admin with MessageRouter broadcasting

**OGRH_RaidLead.lua Status (to be renamed OGRH_AdminSelection.lua):**
- Mostly wrapper functions for backward compatibility (no longer needed)
- ONE legacy `SendAddonMessage` remains: `QueryRaidLead()` line 764
- Direct field manipulation in `InitRaidLead()` (lines 771, 786)
- 14 call sites across 4 files using deprecated wrappers

**Migration Strategy:**
1. Rename file from OGRH_RaidLead.lua to OGRH_AdminSelection.lua
2. Replace all wrapper calls with Permissions functions
3. Migrate `QueryRaidLead()` to MessageRouter
4. Fix `InitRaidLead()` to use `SetRaidAdmin()`
5. Remove deprecated wrapper functions
6. Update field documentation and terminology

---

## Migration Inventory

### Call Sites to Update (14 locations)

#### 1. OGRH_EncounterMgmt.lua (4 calls)
| Line | Current Code | Replacement |
|------|--------------|-------------|
| 743 | `if OGRH.IsRaidAdmin and OGRH.IsRaidAdmin() then` | ✅ Already correct |
| 764 | `if OGRH.IsRaidAdmin and OGRH.IsRaidAdmin() then` | ✅ Already correct |
| 831 | `if OGRH.IsRaidAdmin and OGRH.IsRaidAdmin() then` | ✅ Already correct |
| 854 | `if OGRH.IsRaidAdmin and OGRH.IsRaidAdmin() then` | ✅ Already correct |

**Note:** EncounterMgmt already uses `IsRaidAdmin()` directly - no changes needed!

#### 2. OGRH_Core.lua (2 calls)
| Line | Current Code | Replacement |
|------|--------------|-------------|
| 2385 | Context needed | Replace `IsRaidLead()` → `IsRaidAdmin()` |
| 2399 | Context needed | Replace `IsRaidLead()` → `IsRaidAdmin()` |

#### 3. OGRH_MainUI.lua (1 call)
| Line | Current Code | Replacement |
|------|--------------|-------------|
| 101 | Context needed | Replace `IsRaidLead()` → `IsRaidAdmin()` |

#### 4. OGRH_RaidLead.lua → OGRH_AdminSelection.lua (internal references)
| Line | Current Code | Replacement |
|------|--------------|-------------|
| 16-21 | `function OGRH.IsRaidAdmin()` (no params) | **DELETE** - Duplicate of Permissions.lua version |
| 23-25 | `function OGRH.IsRaidLead()` | **DELETE** entire function |
| 30 | `return OGRH.IsRaidLead()` | Replace with `return OGRH.IsRaidAdmin(UnitName("player"))` |
| 48 | `if OGRH.IsRaidLead() then` | Replace with `if OGRH.IsRaidAdmin(UnitName("player")) then` |
| 70 | `if OGRH.IsRaidLead() then` | Replace with `if OGRH.IsRaidAdmin(UnitName("player")) then` |
| 102-108 | `function OGRH.SetRaidLead()` | **DELETE** entire function |
| 583 | `SetRaidLead(playerName)` | Replace with `OGRH.SetRaidAdmin(playerName)` |
| 689 | `local isRaidLead = OGRH.IsRaidLead()` | Replace with `local isRaidAdmin = OGRH.IsRaidAdmin(UnitName("player"))` |
| 745 | `SendAddonMessage(..., "SYNC_REQUEST", "RAID")` | **MIGRATE** to Phase 2 sync system |

### Legacy SendAddonMessage (1 location)

**OGRH_AdminSelection.lua (formerly OGRH_RaidLead.lua) Line 764:**
```lua
-- OLD (legacy)
function OGRH.QueryRaidLead()
  if GetNumRaidMembers() == 0 then
    return
  end
  
  SendAddonMessage(OGRH.ADDON_PREFIX, "RAID_LEAD_QUERY", "RAID")
end
```

**NEW (MessageRouter):**
```lua
-- Query raid for current admin
function OGRH.QueryRaidAdmin()
  if GetNumRaidMembers() == 0 then
    return
  end
  
  -- Use MessageRouter for reliable query
  if OGRH.MessageRouter and OGRH.MessageTypes then
    OGRH.MessageRouter.Broadcast(OGRH.MessageTypes.ADMIN.QUERY, "", {
      priority = "HIGH"
    })
  end
end
```

**Handler Status:**
✅ **ALREADY REMOVED** - `RAID_LEAD_QUERY` handler no longer exists in OGRH_Core.lua  
✅ Response handler migrated to `MessageRouter.ADMIN.QUERY` (Phase 3B Item 11 complete)

### Direct Field Manipulation (2 locations)

**OGRH_AdminSelection.lua `InitRaidLead()` function:**

**Line 771: Load from SavedVariables**
```lua
-- OLD (direct manipulation)
if OGRH_SV.raidLead then
  OGRH.RaidLead.currentLead = OGRH_SV.raidLead
end

-- NEW (use SetRaidAdmin for proper initialization)
if OGRH_SV.raidLead then
  -- SetRaidAdmin handles updating both Permissions and RaidLead state
  OGRH.SetRaidAdmin(OGRH_SV.raidLead, true)  -- suppressBroadcast = true
end
```

**Line 786: Clear on raid leave**
```lua
-- OLD (direct manipulation)
OGRH.RaidLead.currentLead = nil
OGRH_SV.raidLead = nil

-- NEW (use Permissions state)
OGRH.Permissions.State.currentAdmin = nil
OGRH_SV.raidLead = nil
```

---

## Code Removal Plan

### Functions to Delete

**OGRH_AdminSelection.lua (formerly OGRH_RaidLead.lua):**

1. **Lines 16-21: `OGRH.IsRaidAdmin()` duplicate (no parameters)**
```lua
-- DELETE THIS DUPLICATE - Conflicts with Permissions.lua version
function OGRH.IsRaidAdmin()
  local playerName = UnitName("player")
  local currentAdmin = OGRH.GetRaidAdmin and OGRH.GetRaidAdmin()
  return currentAdmin == playerName
end
```
**Issue:** `OGRH_Permissions.lua` line 45 defines `OGRH.IsRaidAdmin(playerName)` which takes a parameter to check ANY player. This version (no parameter) only checks local player and creates a function signature conflict.

2. **Lines 23-25: `IsRaidLead()` wrapper**
```lua
-- DELETE THIS ENTIRE FUNCTION
function OGRH.IsRaidLead()
  return OGRH.IsRaidAdmin()
end
```

3. **Lines 102-108: `SetRaidLead()` wrapper**
4. **Lines 758-765: `QueryRaidLead()` legacy function**
```lua
-- DELETE THIS ENTIRE FUNCTION (replaced with QueryRaidAdmin)
function OGRH.QueryRaidLead()
  if GetNumRaidMembers() == 0 then
    return
  end
  
  SendAddonMessage(OGRH.ADDON_PREFIX, "RAID_LEAD_QUERY", "RAID")
end
```

**OGRH_Core.lua:**

5unction OGRH.QueryRaidLead()
  if GetNumRaidMembers() == 0 then
    return
  end
  
  SendAddonMessage(OGRH.ADDON_PREFIX, "RAID_LEAD_QUERY", "RAID")
end
```

**OGRH_Core.lua:**

5. **Lines 2356-2362: `RAID_LEAD_SET;` legacy handler**
```lua
-- DELETE THIS HANDLER - violates no-backwards-compatibility policy
elseif string.sub(message, 1, 14) == "RAID_LEAD_SET;" then
  local leadName = string.sub(message, 15)
  if OGRH.SetRaidAdmin then
    OGRH.SetRaidAdmin(leadName, true)
  end
```

**OGRH_Permissions.lua:**

6. **Lines 189-195: SendAddonMessage fallback**
```lua
-- DELETE THIS FALLBACK - MessageRouter is always available
else
  -- Fallback to old method if MessageRouter not available
  local message = "RAID_LEAD_SET;" .. playerName
  SendAddonMessage(OGRH.ADDON_PREFIX, message, "RAID")
end
```
**Rationale:** MessageRouter is loaded before Permissions (checked in TOC order), so fallback is unnecessary and violates no-backwards-compatibility policy.

### Additional Migrations

**OGRH_AdminSelection.lua Line 745: `RequestSyncFromLead()` uses legacy SendAddonMessage**

```lua
-- OLD (legacy SendAddonMessage)
function OGRH.RequestSyncFromLead()
  if not OGRH.RaidLead.currentLead then
    OGRH.Msg("No raid lead is currently set.")
    return
  end
  
  if GetNumRaidMembers() == 0 then
    OGRH.Msg("You must be in a raid.")
    return
  end
  
  SendAddonMessage(OGRH.ADDON_PREFIX, "SYNC_REQUEST", "RAID")
  OGRH.Msg("Requesting encounter sync from raid lead...")
end

-- NEW (use Phase 2 sync system)
function OGRH.RequestSyncFromAdmin()
  local currentAdmin = OGRH.GetRaidAdmin()
  if not currentAdmin then
    OGRH.Msg("No raid admin is currently set.")
    return
  end
  
  if GetNumRaidMembers() == 0 then
    OGRH.Msg("You must be in a raid.")
    return
  end
  
  -- Use Phase 2 pull sync system
  if OGRH.Sync and OGRH.Sync.RequestFullSync then
    OGRH.Sync.RequestFullSync(currentAdmin)
    OGRH.Msg("Requesting encounter sync from raid admin...")
  else
    OGRH.Msg("Sync system not available.")
  end
end
```

### Field Documentation to Update

**OGRH_AdminSelection.lua Line 7:**
```lua
-- OLD comment
currentLead = nil,  -- DEPRECATED: Use OGRH.GetRaidAdmin() instead (kept for backward compatibility)

-- NEW comment
currentLead = nil,  -- Maintained by OGRH.Permissions.State.currentAdmin (DO NOT manipulate directly)
```

---

## Testing Plan

### Pre-Migration Validation

**Setup:**
1. Two clients in same raid (Client A = raid leader, Client B = member)
2. Both clients have addon installed
3. Record current admin via `/script DEFAULT_CHAT_FRAME:AddMessage(tostring(OGRH.GetRaidAdmin()))`

**Baseline Tests:**
1. ✅ Admin selection UI works (can see both clients)
2. ✅ Clicking a player sets them as admin
3. ✅ Admin broadcasts to all raid members
4. ✅ Sync button changes color based on admin status
5. ✅ Encounter edit controls enable/disable correctly

### Migration Tests

#### Test 1: Call Site Replacements
**Goal:** Verify all IsRaidLead/SetRaidLead calls work after replacement

**Procedure:**
1. Replace all call sites per migration inventory
2. `/reload` both clients
3. Open encounter management UI
4. Try to modify encounter (only admin should succeed)
5. Verify no Lua errors in chat

**Expected:**
- ✅ No "attempt to call nil value" errors
- ✅ Admin can edit encounters
- ✅ Non-admin cannot edit encounters
- ✅ UI buttons enable/disable correctly

#### Test 2: QueryRaidAdmin Migration
**Goal:** Verify admin query works via MessageRouter

**Procedure:**
1. Client A is admin
2. Client B joins raid
3. Client B joins/reloads (auto-queries admin after 1 second delay)
4. Wait 2 seconds
5. Check Client B knows admin: `/script DEFAULT_CHAT_FRAME:AddMessage("Admin: " .. tostring(OGRH.GetRaidAdmin()))`

**Expected:**
- ✅ Client B receives admin info (should show Client A's name)
- ✅ No legacy "RAID_LEAD_QUERY" messages sent
- ✅ MessageRouter logs show ADMIN.QUERY broadcast

#### Test 3: InitRaidLead on Reload
**Goal:** Verify admin persists across /reload

**Procedure:**
1. Set Client A as admin
2. Client A: `/reload`
3. After reload, check: `/script DEFAULT_CHAT_FRAME:AddMessage("Admin: " .. tostring(OGRH.GetRaidAdmin()))`
4. Check UI sync button color

**Expected:**
- ✅ Admin persists (Client A still admin)
- ✅ Sync button shows green (admin color)
- ✅ No broadcast on reload (suppressBroadcast works)

#### Test 4: Raid Leave/Join
**Goal:** Verify admin clears on raid leave

**Procedure:**
1. Client A is admin in raid
2. Client A leaves raid
3. Check: `/script DEFAULT_CHAT_FRAME:AddMessage("Admin: " .. tostring(OGRH.GetRaidAdmin()))`
4. Client A rejoins raid
5. Check: `/script DEFAULT_CHAT_FRAME:AddMessage("Admin: " .. tostring(OGRH.GetRaidAdmin()))`

**Expected:**
- ✅ Admin cleared on leave (returns nil)
- ✅ Admin queried on rejoin (auto-discovery)
- ✅ Sync button returns to yellow (non-admin color)

#### Test 5: UI Functionality
**Goal:** Verify all UI operations still work

**Procedure:**
1. Open encounter management (`/ogrh enc`)
2. Try navigation (prev/next encounter)
3. Try role assignment (drag player to role)
4. Open roles UI (`/ogrh roles`)
5. Try adding/removing assignments

**Expected:**
- ✅ Navigation works (only for admin or L/A)
- ✅ Role assignment works (only for admin or L/A)
- ✅ Roles UI shows/hides edit controls correctly
- ✅ Non-admin sees read-only interface

#### Test 6: ~~Cross-Version Compatibility~~ REMOVED
**Status:** NOT APPLICABLE - No backwards compatibility per project design

**Rationale:**
Per OG-RaidHelper design philosophy, **no cross-version backwards compatibility is maintained**. Old clients cannot communicate with new clients. Legacy message handlers must be **deleted**, not tested.

**Code to Remove:**
1. **OGRH_Core.lua line 2356**: Delete `RAID_LEAD_SET;` handler
2. **OGRH_Permissions.lua line 193**: Delete SendAddonMessage fallback (MessageRouter required)

### Post-Migration Validation

**Final Checks:**
1. ✅ No `IsRaidLead()` calls remain (except documentation)
2. ✅ No `SetRaidLead()` calls remain
3. ✅ No `SendAddonMessage("RAID_LEAD_QUERY")` calls
4. ✅ No direct `RaidLead.currentLead` manipulation
5. ✅ All functionality tested and working

**Grep Commands:**
```powershell
# Should return 0 results (except in this doc)
grep -r "IsRaidLead()" --include="*.lua" .

# Should return 0 results (except in this doc)
grep -r "SetRaidLead(" --include="*.lua" .
Delete duplicate `OGRH.IsRaidAdmin()` in RaidLead.lua (lines 16-21)
- [ ] Update OGRH_Core.lua (2 locations)
- [ ] Update OGRH_MainUI.lua (1 location)
- [ ] Update OGRH_AdminSelection.lua internal calls (5 locations with playerName parameter)

# Should only return Permissions.lua and this doc
grep -r "IsRaidAdmin()" --include="*.lua" .
```

---

## Risk Assessment

### Low Risk Items
- ✅ Call site replacements (simple search/replace)
- ✅ Function deletions (wrappers have no side effects)
- ✅ Field comment updates (documentation only)

### Medium Risk Items
- ⚠️ `InitRaidLead()` changes (affects saved variable loading)
- ⚠️ `QueryRaidAdmin()` migration (network protocol change)
- ⚠️ Handler removal in Core.lua (must verify no other callers)

### Mitigation Strategies

**SavedVariables Safety:**
- Test with existing `OGRH_SV.raidLead` data
- Verify `SetRaidAdmin()` handles nil gracefully
- Ensure suppressBroadcast prevents spam on reload

**Network Protocol:**
- Verify `ADMIN.QUERY` handler exists in MessageRouter
- Test with MessageRouter unavailable (init order)
- Add fallback for graceful degradation

**Handler Removal:**
- Grep for all `RAID_LEAD_QUERY` references before deletion
- Verify Phase 3B Item 11 completed (ADMIN.QUERY handler)
- Test cross-client communication

---

## Implementation Checklist

### Phase 1: Replace Call Sites
- [ ] Update OGRH_Core.lua (2 locations)
- [ ] Update OGRH_MainUI.lua (1 location)
- [ ] Update OGRH_AdminSelection.lua internal calls (5 locations with playerName parameter)
- [ ] Test: Reload and verify no Lua errors

### Phase 2: Migrate QueryRaidLead
- [ ] Create `QueryRaidAdmin()` function
- [ ] Replace all `QueryRaidLead()` calls with `QueryRaidAdmin()`
- [ ] Update `InitRaidLead()` to call `QueryRaidAdmin()`
- [ ] Test: Query works via MessageRouter

### Phase 3: Fix InitRaidLead
- [ ] Replace line 771: Use `SetRaidAdmin()` with suppressBroadcast
- [ ] Replace line 786: Use Permissions.State.currentAdmin
- [ ] Test: Reload preserves admin, raid leave clears admin
Migrate RequestSyncFromLead
- [ ] Rename `RequestSyncFromLead()` to `RequestSyncFromAdmin()`
- [ ] Replace SendAddonMessage with Phase 2 sync system
- [ ] Update any call sites to use new function name
- [ ] Test: Sync request works via Phase 2 system

### Phase 5: Remove Legacy Code
- [ ] Dele6: Update Documentation
- [ ] Update field comment for `currentLead`
- [ ] Update this document status to "Complete"
- [ ] Update OGAddonMsg Migration doc Phase 3C section
- [ ] Grep verify no deprecated calls remain

### Phase 7 No functionality broken

### Phase 5: Update Documentation
- [ ] Update field comment for `currentLead`
- [ ] Update this document status to "Complete"
- [ ] Update OGAddonMsg Migration doc Phase 3C section
- [ ] Grep verify no deprecated calls remain

### Phase 6: Final Testing
- [ ] Run all tests in Testing Plan
- [ ] Test with 2+ clients in raid
- [ ] Test raid leave/join scenarios
- [ ] Test /reload and login scenarios
- [ ]Duplicate `OGRH.IsRaidAdmin()` removed from RaidLead.lua
2. ✅ All call sites updated to use `OGRH.IsRaidAdmin(playerName)` with parameter
3. ✅ All wrapper functions (`IsRaidLead`, `SetRaidLead`) removed
4. ✅ `QueryRaidAdmin()` uses MessageRouter (ADMIN.QUERY)
5. ✅ `RequestSyncFromAdmin()` uses Phase 2 sync system
6. ✅ `InitRaidLead()` uses proper Permissions functions
7. ✅ No legacy `RAID_LEAD_QUERY` or `SYNC_REQUEST` messages sent
8. ✅ All tests pass
9. ✅ No Lua errors on reload/raid join
10. ✅ All 14 call sites updated to use `IsRaidAdmin()`
2. ✅ All wrapper functions removed
3. ✅ `QueryRaidAdmin()` uses MessageRouter
4. ✅ `InitRaidLead()` uses proper Permissions functions
5. ✅ No legacy `RAID_LEAD_QUERY` messages sent
6. ✅ All tests pass
7. ✅ No Lua errors on reload/raid join
8. ✅ Admin selection UI fully functional

**Verification:**
```lua
-- Admin status check
/script DEFAULT_CHAT_FRAME:AddMessage("IsRaidAdmin: " .. tostring(OGRH.IsRaidAdmin(UnitName("player"))))

-- Get current admin
/script DEFAULT_CHAT_FRAME:AddMessage("Current Admin: " .. tostring(OGRH.GetRaidAdmin()))

-- Permission level
/script DEFAULT_CHAT_FRAME:AddMessage("Permission: " .. tostring(OGRH.GetPermissionLevel(UnitName("player"))))

-- Test query (should use MessageRouter, triggers automatically on raid join)
/script if OGRH.QueryRaidAdmin then OGRH.QueryRaidAdmin(); DEFAULT_CHAT_FRAME:AddMessage("Admin query sent") end
```

---File Purpose After Migration

**OGRH_AdminSelection.lua will contain:**
- ✅ Admin selection poll system (`PollAddonUsers`, response handlers)
- ✅ Admin selection UI (`ShowRaidLeadSelectionUI` ~400 lines)
- ✅ Permission wrapper functions (`CanEdit`, `CanManageRoles`, `CanNavigateEncounter`)
- ✅ UI state management (`UpdateRaidLeadUI`)
- ✅ Initialization (`InitRaidLead`)
- ✅ Utility functions (`ScheduleFunc`)

**What was removed:**
- ❌ Duplicate `OGRH.IsRaidAdmin()` function (use Permissions.lua version)
- ❌ Legacy wrapper functions (`IsRaidLead`, `SetRaidLead`)
- ❌ Legacy message handlers (`QueryRaidLead`, `RequestSyncFromLead`)
- ❌ Direct field manipulation (use Permissions functions)

**File remains focused on:** Admin selection UI + poll system + permission wrappers used by other files.

**Why rename?** The original name "RaidLead" confused game raid lead (L/A rank) with addon admin. The new name accurately reflects the file's purpose: admin selection and polling.

## Notes

**Design Philosophy Alignment:**
- ✅ No backward compatibility (complete wrapper removal)
- ✅ Use MessageRouter for all network communication
- ✅ Proper separation of concerns (Permissions vs RaidLead)
- ✅ Single source of truth (IsRaidAdmin only in Permissions.lua)
- ✅ WoW 1.12 compatible (no modern API usage)

**Related Documents:**
- `PHASE3B_CORE_AUDIT.md` - Item 11 (RAID_LEAD_SET response)
- `OGAddonMsg Migration - Design Document.md` - Phase 3C section
- `OGRH_Permissions.lua` - Authoritative permission system

**File Rename:**
- Old: `OGRH_RaidLead.lua`
- New: `OGRH_AdminSelection.lua`
- TOC update required: Change load order entry

**Dependencies:**
- OGRH_Permissions.lua (Phase 1)
- OGRH_MessageRouter.lua (Phase 1)
- OGRH_MessageTypes.lua (Phase 1)
- ADMIN.QUERY handler (Phase 3B Item 11)
