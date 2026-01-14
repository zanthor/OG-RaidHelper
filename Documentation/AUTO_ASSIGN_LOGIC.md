# Auto Assign Logic Documentation

## Overview
The Auto Assign feature automatically fills encounter role slots with players from the raid based on their assigned roles in the RolesUI system.

## Location
- **File**: `OGRH_EncounterMgmt.lua`
- **Function**: Auto Assign button OnClick handler (lines 748-940)
- **Button**: Located at bottom-left of encounter planning panel

## Button Behavior
- **Left-Click**: Performs auto-assignment
- **Right-Click**: Clears all encounter data (assignments, marks, numbers, announcement text)

## Auto-Assign Algorithm

### 1. Role Processing Order
Roles are processed in a specific order to ensure consistent assignments:
1. All roles from Column 1 (top to bottom)
2. All roles from Column 2 (top to bottom)

### 2. Player Eligibility
For each role, the system checks:

#### A. Role Matching (using `role.defaultRoles`)
Players must match at least one enabled default role:
- `role.defaultRoles.tanks` → Matches players with TANKS role
- `role.defaultRoles.healers` → Matches players with HEALERS role
- `role.defaultRoles.melee` → Matches players with MELEE role
- `role.defaultRoles.ranged` → Matches players with RANGED role

#### B. Raid Membership
- Player must be in the current raid group
- Uses `GetNumRaidMembers()` and `GetRaidRosterInfo()` to verify
- **Includes offline players** - GetRaidRosterInfo returns all raid members regardless of online status

#### C. Assignment Status
- By default, players can only be assigned to ONE role
- If `role.allowOtherRoles = true`, player can be assigned to multiple roles
- Previously assigned players are skipped unless the new role allows other roles

### 3. Assignment Process
For each role:

**Phase 1 - Class Priority Assignment (Bottom-Up):**
1. Check if `role.classPriority[slotIndex]` exists for each slot (starting from bottom slot)
2. For each slot with class priority configured:
   - Iterate through priority class list in order
   - For each class, find unassigned players of that class in raid
   - Check if player's RolesUI role matches `role.defaultRoles`
   - For hybrid classes, check `role.classPriorityRoles[slotIndex][className]` flags
   - Sort matching players alphabetically
   - Assign first matching player to the slot
   - Mark player as assigned and move to next slot (upward)
   - Stop if all slots filled or priority list exhausted

**Phase 2 - Default Role Assignment (Top-Down):**
3. Build list of eligible players (matching defaultRoles, in raid, not already assigned)
4. Sort eligible players alphabetically for consistent results
5. Fill remaining empty slots sequentially from top to bottom
6. Mark assigned players in tracking table
7. Continue to next role

### 4. Data Storage
Assignments are stored in:
```lua
OGRH_SV.encounterAssignments[raidName][encounterName][roleIndex][slotIndex] = playerName
```

### 5. Sync and Refresh
After assignment:
1. Broadcast full sync to raid (assignments, marks, numbers)
2. Refresh UI to display new assignments
3. Show message: "Auto-assigned X players"

## Current Implementation (v1.17.0+)

### Class Priority Integration ✅
The auto-assign logic **NOW USES** the Class Priority system:
- Phase 1: Fills slots bottom-up using `role.classPriority[slotIndex]`
- Respects `role.classPriorityRoles[slotIndex][className]` for hybrid class role matching
- Phase 2: Falls back to `role.defaultRoles` for unfilled slots
- Uses `role.allowOtherRoles` to control duplicate assignments

### Assignment Order ✅
Players are now assigned with consistent ordering:
- **Alphabetical sorting** within each class/role group
- **Priority-based ordering** using classPriority configuration
- **Class-based ordering** respecting class priority lists

### Smart Matching ✅
The current logic now:
- ✅ Considers class priority preferences per slot
- ✅ Matches hybrid classes to appropriate role types (Tanks/Healers/Melee/Ranged)
- ✅ Fills slots bottom-up for priority assignments, top-down for fallback
- ✅ Backward compatible: Falls back to defaultRoles if no priority set

## Remaining Limitations

### Multi-Slot Optimization
Currently treats each slot independently. Does not:
- Balance class distribution across multiple slots of same role
- Prevent assigning same class to adjacent slots when alternatives exist
- Optimize for raid composition diversity

## Future Enhancements

### 1. Multi-Slot Optimization
For roles with multiple slots:
- Try to fill all slots with different players if possible
- Only duplicate players if `allowOtherRoles = true` and not enough unique players
- Balance class distribution across slots

## Example Scenario

### Current Behavior
```
Role: Main Tank (1 slot)
defaultRoles: {tanks = true}
```
Auto-assign finds ANY player with TANKS role and assigns them. No consideration of class or priority.

### Desired Behavior with Class Priority
```
Role: Main Tank (1 slot)
defaultRoles: {tanks = true}
classPriority[1] = {"Warrior", "Paladin", "Druid"}
classPriorityRoles[1]["Warrior"] = {Tanks = true}
classPriorityRoles[1]["Paladin"] = {Tanks = true}
classPriorityRoles[1]["Druid"] = {Tanks = true}
```

Auto-assign should:
1. Look for Warriors with TANKS role → Assign first one found
2. If no Warriors, look for Paladins with TANKS role
3. If no Paladins, look for Druids with TANKS role
4. If none found, leave slot empty

## Implementation Notes

### Data Structures to Consider
- `OGRH_SV.roles` → Player's assigned role (TANKS, HEALERS, MELEE, RANGED)
- `role.defaultRoles` → Which role types this slot accepts (tanks, healers, melee, ranged flags)
- `role.classPriority[slotIndex]` → Ordered list of classes to prefer
- `role.classPriorityRoles[slotIndex][className]` → Which roles this class can fill for this slot (Tanks, Healers, Melee, Ranged flags)
- `role.allowOtherRoles` → Can player be assigned to multiple roles?

### Matching Logic
For a player to be assigned to a slot:
1. Player must be in the raid
2. Player's RolesUI role must match `role.defaultRoles` (TANKS→tanks, HEALERS→healers, etc.)
3. If class priority is set and player's class is in the list:
   - If player's class has role checkboxes configured, their RolesUI role must match one of the enabled flags
   - Example: Druid with HEALERS role can only fill slots where Druid has `Healers` checkbox enabled
4. Player must not be already assigned (unless `allowOtherRoles = true`)

### Compatibility
The enhanced auto-assign should be backward compatible:
- If no `classPriority` is set, fall back to current behavior
- If `classPriority` is empty array, fall back to current behavior
- If `classPriorityRoles` is not set for a class, match any role type (current behavior)
