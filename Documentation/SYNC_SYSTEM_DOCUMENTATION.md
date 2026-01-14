# OG-RaidHelper Sync System Documentation

## Overview
The OG-RaidHelper addon implements three distinct synchronization systems to keep raid members coordinated. This document defines the terminology and behavior of each sync type.

---

## Sync Type 1: STRUCTURE SYNC (Import/Export Sync)

### Trigger Points
- **Manual - Full Structure**: Main menu (Minimap icon or RH button) → Import/Export → Sync button
- **Manual - Single Encounter**: Encounter Planning window → Structure Sync button
  - Syncs only the selected encounter's structure (roles, marks, numbers, announcements)
  - Does NOT sync other encounters or trade items/consumes
- **Automatic**: None - this is always a manual operation

### What Gets Synced
This is a **FULL STRUCTURE** sync that includes:
- ✅ **Raid definitions** (raid names)
- ✅ **Encounter definitions** (encounter names per raid)
- ✅ **Role structure** (role names, slot counts, column layout)
- ✅ **Raid Marks** (mark assignments per role/slot)
- ✅ **Raid Assignment Numbers** (number assignments per role/slot)
- ✅ **Announcement Templates** (announcement text with tags)
- ✅ **Trade Items** (tradeable item configuration)
- ✅ **Consumes** (consumable item configuration)

### What Does NOT Get Synced
- ❌ **Player assignments** (which player is in which slot)
- ❌ **Player role data** (tank/healer/melee/ranged from Roles UI)
- ❌ **Player pools** (encounter-specific player pools)
- ❌ **Current UI state** (which raid/encounter is currently selected)

### Authorization
- **Sender**: Must be the designated Raid Lead (elected via Shift+Click Sync button or right-click menu)
- **Recipients**: All raid members running the addon

### Technical Details

#### Full Structure Sync
- **Message Prefix**: `STRUCTURE_SYNC_CHUNK`
- **Functions Used**:
  - `OGRH.BroadcastStructureSync()` - Broadcasts full structure to raid
  - `OGRH.RequestStructureSync()` - Requests full structure from raid lead
  - `OGRH.ExportShareData()` - Exports all structure data
  - `OGRH.ImportShareData()` - Imports structure data
- **Data Format**: Serialized table sent in 200-byte chunks with 0.5s delay between chunks
- **Validation**: Structure checksum used to detect mismatches
- **Error Handling**: 90-second timeout, displays error messages if structure mismatch detected

#### Single Encounter Structure Sync
- **Message Prefix**: `ENCOUNTER_STRUCTURE_SYNC_CHUNK`
- **Functions Used**:
  - `OGRH.BroadcastEncounterStructureSync(raid, encounter)` - Broadcasts single encounter structure
  - `OGRH.ExportEncounterShareData(raid, encounter)` - Exports single encounter structure data
  - `OGRH.ImportShareData()` - Imports structure data (same as full sync)
- **Data Format**: Serialized table with only selected encounter's data, sent in 200-byte chunks with 0.5s delay
- **Scope**: Only syncs the specified encounter; does not include trade items or consumes

### User Messages

#### Full Structure Sync
- "Broadcasting structure sync to raid..."
- "Sending structure sync: X/Y chunks..." (every 10 chunks)
- "Receiving structure sync: X/Y chunks..." (every 10 chunks)
- "Structure sync complete (X chunks sent)."
- "Structure sync complete from [Player]."
- "Requesting structure sync from raid lead..."
- "Structure sync timed out."

#### Single Encounter Structure Sync
- "Broadcasting structure sync for [Encounter] to raid..."
- "Sending structure sync: X/Y chunks..." (every 10 chunks)
- "Receiving structure sync: X/Y chunks..." (every 10 chunks)
- "Structure sync complete (X chunks sent)."
- "Structure sync complete from [Player]."
- "Select an encounter first."

---

## Sync Type 2: NAVIGATION SYNC (Encounter Selection Sync)

### Trigger Points
- **Main UI Navigation**: 
  - Clicking `<` (Previous Encounter) button
  - Clicking `>` (Next Encounter) button
- **Raid Selection Menu**: 
  - Right-clicking "Select Raid" button → Selecting a raid from menu

### What Gets Synced
This is a **UI STATE** sync that includes:
- ✅ **Selected Raid Name** - Which raid is currently active on Main UI
- ✅ **Selected Encounter Name** - Which encounter is currently active on Main UI

### What Does NOT Get Synced
- ❌ **Player assignments** (assignments are independent of navigation)
- ❌ **Structure data** (roles, marks, numbers, announcements)
- ❌ **Encounter Planning window state** (planning window is independent)
- ❌ **Player data**

### Authorization
- **Sender**: Must be Raid Leader (rank 2) OR Raid Assistant (rank 1) - checked via `GetRaidRosterInfo()`
- **Recipients**: All raid members running the addon

### Technical Details
- **Message Prefix**: `ENCOUNTER_SELECT`
- **Functions Used**:
  - `OGRH.BroadcastEncounterSelection(raidName, encounterName)` - Broadcasts selection
  - Receivers validate sender rank before applying
- **Data Format**: `"ENCOUNTER_SELECT;" .. raidName .. ";" .. encounterName`
- **Validation**: 
  - Sender must be raid leader or assistant
  - Raid and encounter must exist in local structure
  - Updates silently ignored if not authorized or invalid
- **Side Effects**: 
  - Updates Main UI encounter button
  - Refreshes Consume Monitor if visible
  - Does NOT affect Encounter Planning window

### User Messages
- No explicit messages - sync happens silently
- Silently ignores unauthorized senders

---

## Sync Type 3: ASSIGNMENT SYNC (Player Assignment Sync)

### Trigger Points
- **Single Assignment Change**: When raid lead drags a player to a slot in Encounter Planning
- **Swap/Move Operations**: When raid lead swaps or moves players between slots
- **Clear Assignment**: When raid lead removes a player from a slot
- **Auto Assign**: When raid lead clicks "Auto Assign" button (sends full encounter)
- **Clear Encounter**: When raid lead clicks "Clear" button (sends full encounter)
- **Manual Full Sync**: When raid lead clicks "Sync" button on Main UI (broadcasts current encounter)
- **Request Sync**: When non-raid-lead clicks "Sync" button on Main UI (requests current encounter)

### What Gets Synced

#### 3A. Single Assignment Update
- ✅ **One player assignment** - Single role/slot player assignment
- ✅ **Structure checksum** - Validates receiver has same structure

#### 3B. Full Encounter Sync
- ✅ **All player assignments** for the current encounter
- ✅ **Structure checksum** - Validates receiver has same structure

### What Does NOT Get Synced
- ❌ **Structure elements** (roles, marks, numbers) - use STRUCTURE SYNC instead
- ❌ **Announcement templates**
- ❌ **Role data from Roles UI** (separate system - see ROLE SYNC)
- ❌ **Other encounters** (only syncs current encounter)

### Authorization
- **Sender**: Must be the designated Raid Lead (elected via addon)
- **Recipients**: All raid members running the addon
- **Validation**: Structure checksum must match or sync is rejected

### Technical Details

#### Single Assignment Update
- **Message Prefix**: `ASSIGNMENT_UPDATE`
- **Functions Used**: `OGRH.BroadcastAssignmentUpdate(raid, encounter, roleIndex, slotIndex, playerName)`
- **Data Format**: `"ASSIGNMENT_UPDATE;" .. raid .. ";" .. encounter .. ";" .. roleIndex .. ";" .. slotIndex .. ";" .. playerName .. ";" .. checksum`
- **Sent On**: Drag-drop operations, player removal

#### Full Encounter Sync
- **Message Prefix**: `ENCOUNTER_SYNC` or `ENCOUNTER_SYNC_CHUNK` (for large data)
- **Functions Used**: 
  - `OGRH.BroadcastFullEncounterSync()` - Broadcasts all assignments for current encounter
  - `OGRH.BroadcastFullSync(raid, encounter)` - Wrapper that sets encounter then broadcasts
- **Data Format**: Serialized table with `{raid, encounter, structureChecksum, assignments}`
- **Chunking**: Messages >220 bytes split into 200-byte chunks with 0.3s delay
- **Sent On**: Auto Assign, Clear encounter, Manual Sync button

### Error Handling
- **Structure Mismatch**: 
  - Error message: "Assignment update error: Structure mismatch!"
  - Prompts user: "Use Import/Export > Sync to update from raid lead."
  - Sync button turns red with text "|cffff0000Sync|r"
- **Checksum Clear**: When structure matches again, sync button returns to normal

### User Messages
- "No encounter selected. Navigate to an encounter using < > buttons first."
- "Select an encounter first." (from Encounter Planning buttons)
- "Broadcasting player assignments for [Encounter Name]..."
- "Sending encounter sync: X/Y chunks..." (every 10 chunks)
- "Receiving encounter sync: X/Y chunks..." (every 10 chunks)
- "Requesting encounter sync from raid lead..."
- "Assignment update error: Structure mismatch!"
- "Your encounter structure is out of date."
- "Use Import/Export > Sync to update from raid lead."

---

## Sync Type 4: ROLE SYNC (Role Assignment Sync) - NOT CURRENTLY IMPLEMENTED

### Current Behavior
**⚠️ IMPORTANT: Role changes in the Roles UI are NOT currently broadcast to other addon users.**

### What Should Get Synced (Future Implementation)
When a player with Assistant rank OR the designated Raid Admin moves a player between role columns:
- ✅ **Player name**
- ✅ **New role** (TANKS, HEALERS, MELEE, RANGED)

### Current Storage Location
- **Saved Variable**: `OGRH_SV.roles[playerName] = "TANKS"|"HEALERS"|"MELEE"|"RANGED"`
- **Changed In**: `OGRH_RolesUI.lua` - drag/drop handler (line ~190)
- **Integration**: Syncs to Puppeteer and pfUI locally but NOT to raid

### Trigger Points (Where Broadcast Should Be Added)
1. **Drag/Drop**: When a player is dragged from one role column to another
   - Location: `OGRH_RolesUI.lua` around line 190 after `OGRH_SV.roles[draggedName] = newRole`
2. **Poll Results**: When poll results assign/change roles
   - Location: `OGRH_Poll.lua` around line 313 after `OGRH_SV.roles[playerName] = newRole`

### Authorization (Recommended)
- **Sender**: Must be Raid Lead OR any player with Assistant rank
- **Recipients**: All raid members running the addon

### Technical Details (Proposed)
- **Message Prefix**: `ROLE_UPDATE` (suggested)
- **Proposed Function**: `OGRH.BroadcastRoleUpdate(playerName, newRole)`
- **Data Format**: `"ROLE_UPDATE;" .. playerName .. ";" .. newRole`
- **Handler**: Would need to be added to `OGRH_Core.lua` message handler

---

## Message Flow Summary

```
┌─────────────────────────────────────────────────────────────────┐
│ STRUCTURE SYNC (Import/Export → Sync)                           │
│ ================================================================│
│ Raid Lead → [STRUCTURE_SYNC_CHUNK] → All Members               │
│ Includes: Roles, Marks, Numbers, Announcements, Encounters     │
│ Does NOT include: Player assignments, Role data                 │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ NAVIGATION SYNC (< > buttons, Select Raid menu)                 │
│ ================================================================│
│ Leader/Assistant → [ENCOUNTER_SELECT] → All Members             │
│ Includes: Raid name, Encounter name                             │
│ Does NOT include: Assignments, Structure, Planning window       │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ ASSIGNMENT SYNC (Drag/drop, Auto Assign, Sync button)           │
│ ================================================================│
│ Raid Lead → [ASSIGNMENT_UPDATE] → All Members (single slot)    │
│ Raid Lead → [ENCOUNTER_SYNC] → All Members (full encounter)    │
│ Includes: Player assignments + structure checksum               │
│ Does NOT include: Structure elements, Role data                 │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ ROLE SYNC (Roles UI drag/drop) - NOT IMPLEMENTED                │
│ ================================================================│
│ Lead/Assistant → [ROLE_UPDATE] → All Members (proposed)        │
│ Would include: Player name, Role assignment                     │
│ Currently: Changes are local only                               │
└─────────────────────────────────────────────────────────────────┘
```

---

## Key Distinctions

### Structure vs Assignments
- **STRUCTURE SYNC**: Defines "what roles/marks/announcements exist" (the template)
- **ASSIGNMENT SYNC**: Defines "which players fill which slots" (the data)
- **Separation**: Assignment syncs explicitly exclude structure elements to prevent confusion

### Main UI vs Planning Window
- **Main UI Navigation**: Synced via NAVIGATION SYNC (< > buttons, Select Raid)
- **Encounter Planning Window**: NOT synced - each user maintains independent selection
- **Rationale**: Planning window is for raid lead preparation, doesn't affect raid members

### Roles UI vs Encounter Assignments
- **Roles UI**: General raid composition (TANKS/HEALERS/MELEE/RANGED) - NOT synced
- **Encounter Assignments**: Specific encounter role slots - synced via ASSIGNMENT SYNC
- **Different Systems**: Roles UI affects RollFor integration, Puppeteer, pfUI but not encounter planning

---

## Checksums and Validation

### Structure Checksum
- **Calculation**: `OGRH.CalculateStructureChecksum(raid, encounter)`
- **Based On**: Role names, slot counts, column layout
- **Purpose**: Ensures all raid members have same encounter structure before accepting assignments
- **On Mismatch**: Assignment updates rejected, user prompted to use STRUCTURE SYNC

### Assignment Checksum  
- **Calculation**: `OGRH.CalculateAssignmentChecksum(raid, encounter)`
- **Based On**: Player names and their assigned positions
- **Purpose**: Verify data integrity (currently not used for validation)

---

## Internal Reference Terminology

For consistency in future development, use these terms:

1. **STRUCTURE SYNC** - Full structure broadcast (Import/Export → Sync)
2. **NAVIGATION SYNC** - Encounter selection broadcast (< > buttons, Select Raid menu)
3. **ASSIGNMENT SYNC** - Player assignment broadcast (drag/drop, Auto Assign)
   - **3A. Single Assignment Update** - One slot change
   - **3B. Full Encounter Sync** - All assignments for current encounter
4. **ROLE SYNC** - Role assignment broadcast (Roles UI changes) - NOT IMPLEMENTED

---

## Files Involved

### Core Sync Logic
- `OGRH_Core.lua` - All sync broadcast and receive functions
  - Lines 580-754: Broadcast functions
  - Lines 1213-1340: Message receive handlers
  - Lines 2225-2320: Structure sync functions
  - Lines 1965-2165: Import/Export UI

### UI Trigger Points
- `OGRH_MainUI.lua` - Encounter Sync button (broadcasts/requests assignments)
- `OGRH_EncounterMgmt.lua` - Navigation (< > buttons, Raid menu), assignments (drag/drop), Auto Assign, Encounter Sync button, Structure Sync button
- `OGRH_RolesUI.lua` - Role changes (180-220) - NO BROADCAST

### Related Systems
- `OGRH_RaidLead.lua` - Raid lead election system
- `OGRH_Poll.lua` - Role polling (saves to OGRH_SV.roles)

---

## Notes for Future Development

### ROLE SYNC Implementation
To implement Role Sync, you would need to:

1. **Add Broadcast Function** (in `OGRH_Core.lua`):
```lua
function OGRH.BroadcastRoleUpdate(playerName, newRole)
  if GetNumRaidMembers() == 0 then return end
  
  -- Check authorization (Raid Lead or Assistant)
  local isAuthorized = false
  if OGRH.IsRaidLead and OGRH.IsRaidLead() then
    isAuthorized = true
  else
    -- Check for assistant rank
    local myName = UnitName("player")
    for i = 1, GetNumRaidMembers() do
      local name, rank = GetRaidRosterInfo(i)
      if name == myName and rank == 1 then
        isAuthorized = true
        break
      end
    end
  end
  
  if not isAuthorized then return end
  
  local message = "ROLE_UPDATE;" .. playerName .. ";" .. newRole
  SendAddonMessage(OGRH.ADDON_PREFIX, message, "RAID")
end
```

2. **Add Message Handler** (in `OGRH_Core.lua` around line 1340):
```lua
elseif string.sub(message, 1, 12) == "ROLE_UPDATE;" then
  -- Parse playerName;newRole
  local content = string.sub(message, 13)
  local semicolonPos = string.find(content, ";", 1, true)
  
  if semicolonPos then
    local playerName = string.sub(content, 1, semicolonPos - 1)
    local newRole = string.sub(content, semicolonPos + 1)
    
    -- Validate sender authorization (Lead or Assistant)
    -- ... authorization check ...
    
    -- Apply role update
    OGRH.EnsureSV()
    if not OGRH_SV.roles then OGRH_SV.roles = {} end
    OGRH_SV.roles[playerName] = newRole
    
    -- Refresh Roles UI if visible
    if OGRH_RolesFrame and OGRH_RolesFrame:IsVisible() then
      -- Trigger refresh function
    end
  end
```

3. **Add Broadcast Calls** in `OGRH_RolesUI.lua`:
   - After line 190: `OGRH.BroadcastRoleUpdate(draggedName, newRole)`
   - In `OGRH_Poll.lua` after line 313: `OGRH.BroadcastRoleUpdate(playerName, newRole)`

---

## Conclusion

This document provides the definitive reference for OG-RaidHelper's sync systems. Use this terminology when discussing sync-related issues or implementing new sync features.
