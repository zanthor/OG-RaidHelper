# V2 SVM Data Sync Project

**Project Goal:** Implement "Active Raid" concept with centralized sync infrastructure  
**Status:** Design Phase  
**Created:** January 30, 2026  
**Target:** Phase 7 (Post-Migration)

**CRITICAL CLARIFICATIONS:**
- **Planning Tool Only** - This is NOT a combat execution tool. All features designed for out-of-combat raid planning.
- **BigWigs Timing** - BigWigs activates encounter modules on room entry/proximity, NOT on boss pull.
- **Combat Safety** - Checksum broadcasts and sync operations never run while raid admin is in combat.

---

## ⚠️ IMPLEMENTATION REQUIREMENTS

**BEFORE IMPLEMENTING ANY PHASE, THE AI AGENT MUST:**

1. **Read ALL documentation listed below** using `read_file` tool
2. **Comply with ALL constraints** in Design Philosophy document
3. **Follow SVM patterns** exactly as specified in API documentation
4. **Validate against V2 Schema** before making structural changes

**DO NOT rely on memory or references alone - actively read the files before coding.**

### Required Documentation (Must Read Before Each Phase)

| Document | Path | Required For | Purpose |
|----------|------|--------------|---------|
| **Design Philosophy** | `! OG-RaidHelper Design Philososphy.md` | ALL phases | Lua 5.0/5.1 constraints, OGST patterns, coding standards |
| **SVM Quick Reference** | `! SVM-Quick-Reference.md` | ALL phases | Copy-paste code patterns for SVM usage |
| **SVM API Documentation** | `! SVM-API-Documentation.md` | Phase 1-3 | Complete SVM API reference and sync metadata schema |
| **V2 Schema Specification** | `! V2 Schema Specification.md` | Phase 1-3 | Data structure authority, schema validation |
| **Existing Sync Files** | `_Infrastructure/Sync*.lua` | Phase 4 | Understanding current sync architecture before refactoring |

### Pre-Implementation Checklist

**Phase 1: Core Infrastructure**
- [ ] Read Design Philosophy (Lua 5.0/5.1 constraints)
- [ ] Read SVM API Documentation (SetPath, sync metadata)
- [ ] Read V2 Schema Specification (encounterMgmt structure)
- [ ] Verify OGST availability for any UI components

**Phase 2: UI Implementation**
- [ ] Read Design Philosophy (OGST component requirements)
- [ ] Read SVM Quick Reference (permission check patterns)
- [ ] Review existing Main UI code for right-click menu patterns

**Phase 3: Sync Integration**
- [ ] Read all existing Sync*.lua files to understand current implementation
- [ ] Read SVM API Documentation (sync levels, batching, priorities)
- [ ] Review checksum computation in SyncIntegrity.lua

**Phase 4: Code Consolidation**
- [ ] Audit ALL files using `grep_search` for sync-related calls
- [ ] Read existing sync files before refactoring
- [ ] Ensure no sync logic remains outside SVM/SyncRouter/SyncChecksum/SyncRepair

**Phase 5: BigWigs Integration**
- [ ] Review existing BigWigs module integration code
- [ ] Understand BigWigs activation timing (NOT boss pull)

**Phase 6: Testing & Polish**
- [ ] Review all phase documentation
- [ ] Validate against V2 Schema Specification

---

## Executive Summary

This project redesigns OG-RaidHelper's sync system around an "Active Raid" buffer concept. The Active Raid (always at `encounterMgmt.raids[1]`) acts as a staging area for raid planning, allowing clean sync without local data conflicts. All sync logic is centralized through SVM with intelligent sync-level routing based on context (active vs non-active, EncounterSetup vs EncounterMgmt).

**IMPORTANT:** This is a **PLANNING TOOL**, not a combat execution tool. All sync operations are designed for out-of-combat raid preparation.

**Key Benefits:**
- ✅ Eliminates sync conflicts from local data changes
- ✅ Simplifies sync logic (admin is source of truth for active raid)
- ✅ Enables pre-planning with player assignments
- ✅ Centralizes all sync logic (no scattered calls)
- ✅ Unified checksum validation system
- ✅ Supports raid planning workflows

---

## Architecture Overview

### Current State (Pre-Project)

```
Sync System (Fragmented):
├── SVM (SavedVariablesManager) - Read/write with sync metadata
├── Sync_v2.lua - Full sync broadcasts
├── SyncDelta.lua - Batched changes
├── SyncGranular.lua - Component-level repairs
├── SyncIntegrity.lua - Checksum validation
└── [Scattered calls in UI code]

Data Structure:
encounterMgmt.raids = {
    [1] = {name = "Molten Core", ...},      -- User's first raid
    [2] = {name = "Blackwing Lair", ...},   -- User's second raid
    ...
}
```

### Target State (Post-Project)

```
Sync System (Centralized):
├── SVM (Core) - All writes go through here
├── SyncRouter.lua (NEW) - Routes sync based on context
├── SyncChecksum.lua (NEW) - Unified checksum system
├── SyncRepair.lua (REFACTORED from SyncGranular) - Repair operations
└── [UI code only calls SVM]

Data Structure:
encounterMgmt.raids = {
    [1] = {name = "[ACTIVE RAID]", ...},    -- ALWAYS the active buffer
    [2] = {name = "Molten Core", ...},      -- User's first saved raid
    [3] = {name = "Blackwing Lair", ...},   -- User's second saved raid
    ...
}
```

---

## Active Raid Concept

### Definition

The **Active Raid** is a special raid slot at `encounterMgmt.raids[1]` that acts as:
- **Staging buffer** for current raid operations
- **Sync source** - Admin's active raid is source of truth
- **Planning workspace** - Includes player assignments for pre-planning
- **Live execution area** - Real-time changes during raid

### Properties

| Property | Value |
|----------|-------|
| Location | `OGRH_SV.v2.encounterMgmt.raids[1]` |
| Name | `"__active__"` (semantic identifier) |
| Display Name | `"[AR] Source Raid Name"` (e.g., "[AR] Molten Core") |
| ID | `"__active__"` (semantic identifier) |
| Sync | REALTIME (EncounterMgmt) / BATCH (EncounterSetup) |
| Source | Copy of any saved raid + assignments |
| Context | **Planning tool** - not for use during combat |

### Initialization

```lua
-- On first run or migration
function OGRH.EncounterMgmt.EnsureActiveRaid()
    if not OGRH_SV.v2.encounterMgmt.raids then
        OGRH_SV.v2.encounterMgmt.raids = {}
    end
    
    -- Check if index 1 is the active raid
    local raid1 = OGRH_SV.v2.encounterMgmt.raids[1]
    if not raid1 or raid1.id ~= "__active__" then
        -- Shift all raids up by one index
        for i = table.getn(OGRH_SV.v2.encounterMgmt.raids), 1, -1 do
            OGRH_SV.v2.encounterMgmt.raids[i + 1] = OGRH_SV.v2.encounterMgmt.raids[i]
        end
        
        -- Require user to select a source raid
        -- Active raid slot created but must be populated via "Set Active Raid"
        OGRH_SV.v2.encounterMgmt.raids[1] = {
            id = "__active__",
            name = "__active__",
            displayName = "[AR] No Raid Selected",
            sortOrder = 0,
            encounters = {},
            advancedSettings = {},
            sourceRaidId = nil  -- Must select source via UI
        }
        
        -- Show prompt to user
        OGRH.Msg("|cffff9900[RH]|r Right-click Encounter button and select 'Set Active Raid' to begin")
    end
end
```

---

## UI Changes

### Main UI Window

#### Left Click on Encounter Button (EXISTING BEHAVIOR)
- Opens Encounter Planning window
- **NEW:** Always selects Active Raid (index 1)
- **NEW:** Selects encounter matching `ui.selectedEncounter`

#### Right Click on Encounter Button (MODIFIED BEHAVIOR)
**Current:** Opens context menu to select raid/encounter  
**New:** Opens context menu with:
1. Quick navigation to active raid encounters (top section)
2. Set active raid selection (bottom section)

Context menu structure:
```
┌─────────────────────────────────┐
│ Active Raid                  ►  │ → Lucifron
├─────────────────────────────────┤   Magmadar
│ Set Active Raid:                │   Gehennas
│   Molten Core                   │   ...
│   Blackwing Lair                │
│   Ahn'Qiraj 40                  │
│   Naxxramas                     │
└─────────────────────────────────┘
```

**Behavior:**
- **"Active Raid" → Encounter:** Immediately switches to that encounter (existing quick nav behavior)
- **"Set Active Raid" → Raid Name:** Prompts confirmation dialog to set as active raid

Selecting a raid prompts:
```
┌─────────────────────────────────────────────┐
│  Set Active Raid                            │
├─────────────────────────────────────────────┤
│  This will copy "Molten Core" to the active │
│  raid slot and overwrite current active     │
│  raid data.                                 │
│                                             │
│  Existing player assignments in the active  │
│  raid will be PRESERVED (not overwritten).  │
│                                             │
│  Continue?                                  │
│                                             │
│         [Yes]         [No]                  │
└─────────────────────────────────────────────┘
```

**On "Yes":**
1. Deep copy selected raid structure → `encounterMgmt.raids[1]`
2. Set `displayName = "[AR] " .. sourceRaid.name`
3. Preserve existing player assignments (do NOT overwrite)
4. Set `ui.selectedRaid = 1` (always active)
5. Sync active raid to all clients (BATCH sync)

**On selecting "Active Raid" → Encounter:**
1. Set `ui.selectedEncounter` to selected encounter name
2. Sync to all clients (REALTIME)
3. Update Main UI to show selected encounter

### Encounter Planning Window

**UI Changes:** None (dropdown remains functional)

**Backend Changes:**
- Detect when user is editing Active Raid (index 1) vs saved raids (index 2+)
- Apply appropriate sync level based on target
- Apply permissions checks based on target

**Permission Rules:**
| Target | Who Can Edit | Sync Level |
|--------|--------------|------------|
| Active Raid (index 1) | Admin/L/A only | BATCH (from EncounterSetup) |
| Saved Raids (index 2+) | Anyone (local) | MANUAL (no auto-sync) |

**Implementation:**
```lua
-- In EncounterSetup.lua before any SVM.SetPath call
function OGRH.CanEditRaid(raidIndex)
    if raidIndex == 1 then
        -- Active raid: requires admin/officer permissions
        return OGRH.CanModifyStructure(UnitName("player"))
    else
        -- Saved raids: always editable locally
        return true
    end
end

-- Before write operations
if not OGRH.CanEditRaid(selectedRaidIndex) then
    OGRH.Msg("|cffff0000[RH]|r Only raid admin can edit the active raid")
    return
end
```

**User Experience:**
- User selects any raid from dropdown (existing behavior)
- If editing active raid without permissions → Error message
- If editing saved raid → Changes local only (no sync)
- If admin editing active raid → Changes sync to all clients (BATCH)

---

## Architecture Decision: Permission & Sync Enforcement

### Approach: Centralized Enforcement at SVM Level

**Rationale:**
- ✅ Single source of truth (impossible to bypass)
- ✅ No scattered permission checks across UI code
- ✅ Consistent behavior regardless of call path
- ✅ Automatic sync level assignment based on context
- ✅ Easier to audit and maintain

**Key Decision:** Permissions and sync routing enforced at SVM level, with optional UI-level pre-checks for better UX.

---

## Sync Level Routing

### Decision Tree

```
Is the data being modified in Active Raid (index 1)?
│
├─ YES → Check permissions FIRST
│   │
│   ├─ NO PERMISSION → Block write, return error
│   │
│   └─ HAS PERMISSION → Check source of modification
│       │
│       ├─ EncounterMgmt.lua (Main UI)
│       │   └─ syncLevel = "REALTIME"
│       │      (Immediate propagation: assignments, swaps, etc.)
│       │
│       └─ EncounterSetup.lua (Planning UI)
│           └─ syncLevel = "BATCH"
│              (Batched: role configs, priorities, etc.)
│
└─ NO → Non-active raid (always allowed, local only)
    └─ syncLevel = "MANUAL"
       (Saved raids: requires manual admin push)
```

### Implementation

```lua
-- In SVM write wrapper (SavedVariablesManager.lua)
function OGRH.SVM.SetPath(path, value, syncMetadata)
    local sv = OGRH.SVM.GetActiveSchema()
    if not sv then return false end
    
    -- Parse path to determine if targeting active raid
    local isActiveRaid = string.find(path, "encounterMgmt%.raids%.1%.")
    
    if isActiveRaid then
        -- ENFORCE PERMISSIONS for active raid modification
        if not OGRH.CanModifyStructure(UnitName("player")) then
            if OGRH.Msg then
                OGRH.Msg("|cffff0000[RH-SVM]|r Only raid admin/officers can modify the active raid")
            end
            return false  -- Block write
        end
        
        -- Auto-assign sync level based on caller context (if not provided)
        if not syncMetadata then
            local caller = debugstack(2) -- Get calling function
            
            if string.find(caller, "EncounterMgmt%.lua") then
                syncMetadata = {
                    syncLevel = "REALTIME",
                    componentType = "assignments",
                    scope = {raid = 1}
                }
            elseif string.find(caller, "EncounterSetup%.lua") then
                syncMetadata = {
                    syncLevel = "BATCH",
                    componentType = "settings",
                    scope = {raid = 1}
                }
            end
        end
    elseif not isActiveRaid and not syncMetadata then
        -- Non-active raid: manual sync only (no permission check needed - local edits)
        syncMetadata = {
            syncLevel = "MANUAL",
            componentType = "structure"
        }
    end
    
    -- Continue with write...
    [existing SetPath logic]
end
```

**Optional UI-Level Pre-Checks:**

UI code CAN optionally check permissions before calling SVM to provide better UX:

```lua
-- In EncounterSetup.lua (optional - for better UX)
function OGRH.EncounterSetup.OnRaidSelected(raidIndex)
    if raidIndex == 1 and not OGRH.CanModifyStructure(UnitName("player")) then
        -- Show visual indicator that active raid is read-only
        OGRH.EncounterSetup.ShowReadOnlyWarning("Active Raid - Admin/Officer Only")
        -- Optionally disable edit controls
    else
        OGRH.EncounterSetup.HideReadOnlyWarning()
    end
end
```

**Benefits of Dual-Layer Approach:**
- SVM enforces security (required - cannot be bypassed)
- UI provides better UX (optional - can be added incrementally)
- UI checks can be added per-window as polish
- Core security guaranteed regardless of UI implementation

---
        syncMetadata = {
            syncLevel = "MANUAL",
            componentType = "structure"
        }
    end
    
    -- Continue with write...
end
```

---

## Data to Sync

### Synced Data (Admin → Clients)

| Data Path | Sync Level | Direction | Notes |
|-----------|-----------|-----------|-------|
| `ui.selectedEncounter` | REALTIME | Admin → All | Follow admin's encounter |
| `roles.*` | REALTIME | Admin → All | Player role assignments |
| `encounterMgmt.raids[1]` | BATCH/REALTIME | Admin → All | Active raid structure + assignments |

### Local-Only Data (No Sync)

| Data Path | Reason |
|-----------|--------|
| `ui.point`, `ui.x`, `ui.y` | Window position is client preference |
| `ui.width`, `ui.height` | Window size is client preference |
| `ui.minimized` | Client UI state |
| `minimap.angle` | Minimap button position |
| `encounterMgmt.raids[2+]` | Saved raids (manual sync only) |

---

## Checksum System

### Checksum Types

#### 1. Active Raid Checksum (Structure Only)
```lua
-- Excludes player assignments for pure structure validation
function OGRH.SyncChecksum.ComputeActiveRaidChecksum()
    local activeRaid = OGRH_SV.v2.encounterMgmt.raids[1]
    
    -- Deep copy and strip assignments
    local raidCopy = OGRH.DeepCopy(activeRaid)
    for i = 1, table.getn(raidCopy.encounters) do
        local enc = raidCopy.encounters[i]
        if enc.roles then
            for j = 1, table.getn(enc.roles) do
                enc.roles[j].assignments = {} -- Strip assignments
            end
        end
    end
    
    return OGRH.HashTable(raidCopy)
end
```

**Purpose:** Validate raid structure consistency  
**Mismatch Action:** Request full active raid sync

#### 2. Active Assignments Checksum (Per-Encounter)
```lua
-- Validates player assignments for current encounter
function OGRH.SyncChecksum.ComputeActiveAssignmentsChecksum(encounterIndex)
    local encounter = OGRH_SV.v2.encounterMgmt.raids[1].encounters[encounterIndex]
    if not encounter or not encounter.roles then return "" end
    
    -- Extract only assignments
    local assignments = {}
    for i = 1, table.getn(encounter.roles) do
        assignments[i] = encounter.roles[i].assignments or {}
    end
    
    return OGRH.HashTable(assignments)
end
```

**Purpose:** Validate assignment consistency for current encounter  
**Mismatch Action:** Request encounter-level assignment sync

#### 3. RolesUI Checksum (Global Roles)
```lua
-- Validates global role assignments (TANKS, HEALERS, MELEE, RANGED)
function OGRH.SyncChecksum.ComputeRolesUIChecksum()
    return OGRH.HashTable(OGRH_SV.v2.roles or {})
end
```

**Purpose:** Validate global role assignments  
**Mismatch Action:** Request full roles sync

### Checksum Broadcast Protocol

#### Admin Broadcast (Every 30 seconds + after changes)
```lua
-- Broadcast function (called by timer or after changes)
function OGRH.SyncChecksum.BroadcastChecksums()
    -- NEVER broadcast if admin is in combat
    if UnitAffectingCombat("player") then
        return  -- Skip this broadcast cycle
    end
    
    -- Message format
    local message = {
        type = "CHECKSUM_BROADCAST",
        activeRaid = "a1b2c3d4",           -- Structure checksum
        activeEncounter = 5,                -- Current encounter index
        assignments = "e5f6g7h8",          -- Assignments for current encounter
        rolesUI = "i9j0k1l2",              -- Global roles
        version = 123                       -- Global version number
    }
    
    -- Broadcast to raid
    OGRH.SendAddonMessage(message, "RAID")
end
```

#### Client Validation
```lua
function OGRH.SyncChecksum.ValidateChecksums(broadcastData)
    local mismatches = {}
    
    -- Check active raid structure
    local localRaid = OGRH.SyncChecksum.ComputeActiveRaidChecksum()
    if localRaid ~= broadcastData.activeRaid then
        table.insert(mismatches, {
            type = "ACTIVE_RAID",
            component = "structure",
            repair = "REQUEST_ACTIVE_RAID_SYNC"
        })
    end
    
    -- Check assignments for current encounter
    if broadcastData.activeEncounter then
        local localAssignments = OGRH.SyncChecksum.ComputeActiveAssignmentsChecksum(broadcastData.activeEncounter)
        if localAssignments ~= broadcastData.assignments then
            table.insert(mismatches, {
                type = "ASSIGNMENTS",
                component = "encounterAssignments",
                encounterIndex = broadcastData.activeEncounter,
                repair = "REQUEST_ENCOUNTER_ASSIGNMENTS_SYNC"
            })
        end
    end
    
    -- Check global roles
    local localRoles = OGRH.SyncChecksum.ComputeRolesUIChecksum()
    if localRoles ~= broadcastData.rolesUI then
        table.insert(mismatches, {
            type = "ROLES_UI",
            component = "roles",
            repair = "REQUEST_ROLES_SYNC"
        })
    end
    
    return mismatches
end
```

#### Repair Request (1-Second Buffer)
```lua
-- Client sends repair request
{
    type = "REPAIR_REQUEST",
    component = "ACTIVE_RAID" | "ASSIGNMENTS" | "ROLES_UI",
    encounterIndex = 5  -- Only for ASSIGNMENTS
}

-- Admin buffers for 1 second, then broadcasts repair once
OGRH.SyncChecksum.RepairBuffer = {
    requests = {},      -- {playerName, component, encounterIndex}
    timer = nil,
    timeout = 1.0
}

function OGRH.SyncChecksum.QueueRepairRequest(player, component, encounterIndex)
    -- Add to buffer
    table.insert(OGRH.SyncChecksum.RepairBuffer.requests, {
        player = player,
        component = component,
        encounterIndex = encounterIndex
    })
    
    -- Start/reset timer
    if OGRH.SyncChecksum.RepairBuffer.timer then
        OGRH.CancelTimer(OGRH.SyncChecksum.RepairBuffer.timer)
    end
    
    OGRH.SyncChecksum.RepairBuffer.timer = OGRH.ScheduleTimer(function()
        OGRH.SyncChecksum.FlushRepairBuffer()
    end, 1.0)
end

function OGRH.SyncChecksum.FlushRepairBuffer()
    -- Group requests by component
    local components = {}
    for i = 1, table.getn(OGRH.SyncChecksum.RepairBuffer.requests) do
        local req = OGRH.SyncChecksum.RepairBuffer.requests[i]
        if not components[req.component] then
            components[req.component] = {}
        end
        table.insert(components[req.component], req.player)
    end
    
    -- Broadcast repair for each component (once per component)
    for component, players in pairs(components) do
        if component == "ACTIVE_RAID" then
            OGRH.SyncRepair.BroadcastActiveRaid()
        elseif component == "ASSIGNMENTS" then
            -- Get encounter index from first request
            local encIdx = OGRH.SyncChecksum.RepairBuffer.requests[1].encounterIndex
            OGRH.SyncRepair.BroadcastEncounterAssignments(encIdx)
        elseif component == "ROLES_UI" then
            OGRH.SyncRepair.BroadcastRoles()
        end
    end
    
    -- Clear buffer
    OGRH.SyncChecksum.RepairBuffer.requests = {}
    OGRH.SyncChecksum.RepairBuffer.timer = nil
end
```

---

## BigWigs Integration

### Current Behavior
BigWigs calls `OGRH.SetEncounter()` when **BigWigs module activates** (typically when entering boss room or proximity triggers).

**IMPORTANT:** This is NOT triggered on boss pull - it activates earlier when BigWigs loads the encounter module.

### Required Changes

**Issue:** Need to ensure BigWigs triggers only set the **active encounter**, not change the active raid.

```lua
-- In EncounterMgmt.lua
function OGRH.SetEncounter(encounterName)
    -- Find encounter in ACTIVE RAID (index 1 only)
    local activeRaid = OGRH_SV.v2.encounterMgmt.raids[1]
    if not activeRaid or not activeRaid.encounters then return end
    
    for i = 1, table.getn(activeRaid.encounters) do
        local enc = activeRaid.encounters[i]
        if enc.name == encounterName or enc.displayName == encounterName then
            -- Set selected encounter (synced to all clients)
            OGRH.SVM.SetPath("ui.selectedEncounter", encounterName, {
                syncLevel = "REALTIME",
                componentType = "ui",
                scope = "encounterSelection"
            })
            return
        end
    end
    
    OGRH.Msg("|cffff0000[RH]|r BigWigs encounter '" .. encounterName .. "' not found in active raid")
end
```

**Testing Required:**
- [ ] Enter boss room → verify BigWigs module activates → verify encounter switches
- [ ] Verify all clients follow admin's encounter selection
- [ ] Verify no crashes if encounter not in active raid

---

## Sync Architecture Consolidation

### Files to Keep

| File | Purpose | Changes Needed |
|------|---------|----------------|
| **SavedVariablesManager.lua** | Core read/write with sync routing | Add context-aware sync level assignment |
| **SyncChecksum.lua** (NEW) | Unified checksum system | Centralize all checksum logic |
| **SyncRepair.lua** (REFACTORED) | Granular repair operations | Refactor from SyncGranular.lua |
| **SyncRouter.lua** (NEW) | Sync level decision logic | Extract from SVM |

### Files to Deprecate

| File | Reason | Migration Path |
|------|--------|----------------|
| **Sync_v2.lua** | Full sync logic scattered | Move to SyncRepair.lua |
| **SyncDelta.lua** | Batching now in SVM | Delete (SVM handles batching) |
| **SyncGranular.lua** | Rename to SyncRepair.lua | Refactor and consolidate |
| **SyncIntegrity.lua** | Checksum logic scattered | Move to SyncChecksum.lua |
| **SyncUI.lua** | Stub only | Delete (Phase 2 stub) |

### Scattered Sync Calls (TO AUDIT)

**Action Required:** Search codebase for direct sync calls outside SVM.

```bash
# Find scattered sync calls
grep -r "Broadcast" --include="*.lua" | grep -v "^_Infrastructure/Sync"
grep -r "MessageRouter" --include="*.lua" | grep -v "^_Infrastructure"
grep -r "OGAddonMsg" --include="*.lua" | grep -v "^_Infrastructure"
```

**Expected Locations:**
- `_Raid/EncounterMgmt.lua` - Role assignments, swaps
- `_Raid/EncounterSetup.lua` - Configuration changes
- `_Raid/RolesUI.lua` - Role button clicks
- `_UI/MainUI.lua` - Encounter selection

**Required Changes:**
- Replace all direct sync calls with `OGRH.SVM.SetPath()` + appropriate metadata
- Remove manual checksum calls (centralize in SyncChecksum.lua)

---

## Migration Considerations

### V1 → V2 Migration (Already Complete)

✅ Numeric indices implemented  
✅ Schema nesting at `OGRH_SV.v2.*`  
✅ SVM routing active

### V2 → V2.1 Migration (This Project)

**Data Changes:**
1. Insert Active Raid at index 1
2. Shift existing raids up by 1 index
3. Update `ui.selectedRaid` references

```lua
-- Migration function
function OGRH.Migration.MigrateToActiveRaid()
    if OGRH_SV.schemaVersion ~= "v2" then
        OGRH.Msg("[Migration] Not on v2 schema, cannot migrate to Active Raid")
        return false
    end
    
    -- Check if already migrated
    local raid1 = OGRH_SV.v2.encounterMgmt.raids[1]
    if raid1 and raid1.id == "__active__" then
        OGRH.Msg("[Migration] Active Raid already exists")
        return true
    end
    
    -- Shift raids
    local raids = OGRH_SV.v2.encounterMgmt.raids
    for i = table.getn(raids), 1, -1 do
        raids[i + 1] = raids[i]
    end
    
    -- Create active raid slot (requires user to set source)
    raids[1] = {
        id = "__active__",
        name = "__active__",
        displayName = "[AR] No Raid Selected",
        sortOrder = 0,
        encounters = {},
        advancedSettings = {},
        sourceRaidId = nil
    }
    
    -- Update UI references
    if OGRH_SV.v2.ui.selectedRaid and OGRH_SV.v2.ui.selectedRaid > 0 then
        OGRH_SV.v2.ui.selectedRaid = OGRH_SV.v2.ui.selectedRaid + 1
    end
    
    OGRH.Msg("[Migration] Active Raid migration complete")
    return true
end
```

**Command:**
```
/ogrh migration activeraid
```

---

## Implementation Phases

### Phase 1: Core Infrastructure
- [ ] Create `SyncChecksum.lua` with all checksum functions
- [ ] Create `SyncRouter.lua` for sync level routing
- [ ] Update `SavedVariablesManager.lua` with context-aware routing
- [ ] Implement Active Raid initialization in Core.lua
- [ ] Write migration function for Active Raid insertion

### Phase 2: UI Implementation
- [ ] Modify right-click menu on Encounter button (Main UI)
- [ ] Add "Active Raid" submenu for quick encounter navigation
- [ ] Add "Set Active Raid" section below with raid list
- [ ] Implement "Set Active Raid" confirmation dialog
- [ ] Add active raid indicator to Main UI
- [ ] Test raid copying with assignments
- [ ] Add permission checks to EncounterSetup for active raid edits

### Phase 3: Sync Integration
- [ ] Update EncounterMgmt.lua to use SVM with REALTIME metadata
- [ ] Update EncounterSetup.lua to use SVM with BATCH metadata
- [ ] Implement checksum broadcast (30s + after changes)
- [ ] Implement client validation and repair requests
- [ ] Implement admin repair buffer (1-second delay)

### Phase 4: Code Consolidation
- [ ] Audit all sync calls (grep search)
- [ ] Migrate scattered calls to SVM
- [ ] Refactor SyncGranular → SyncRepair
- [ ] Move checksum logic from SyncIntegrity → SyncChecksum
- [ ] Delete deprecated files (SyncDelta, SyncUI, Sync_v2)

### Phase 5: BigWigs Integration
- [ ] Update OGRH.SetEncounter() for active raid only
- [ ] Test BigWigs module activation (entering boss room)
- [ ] Test encounter auto-selection
- [ ] Verify sync to all clients

### Phase 6: Testing & Polish
- [ ] Unit tests for checksum functions
- [ ] Integration tests for sync flow
- [ ] Raid testing (10+ players)
- [ ] Performance profiling
- [ ] Documentation updates

---

## Testing Strategy

### Unit Tests

```lua
-- Test Active Raid initialization
function OGRH.Test.ActiveRaidInit()
    OGRH.EncounterMgmt.EnsureActiveRaid()
    assert(OGRH_SV.v2.encounterMgmt.raids[1].id == "__active__")
    assert(OGRH_SV.v2.encounterMgmt.raids[1].name == "__active__")
end

-- Test raid copying
function OGRH.Test.CopyRaidToActive()
    local sourceRaid = OGRH_SV.v2.encounterMgmt.raids[2]
    OGRH.EncounterMgmt.SetActiveRaid(2)
    
    local activeRaid = OGRH_SV.v2.encounterMgmt.raids[1]
    assert(activeRaid.displayName == "[AR] " .. sourceRaid.name)
    assert(table.getn(activeRaid.encounters) == table.getn(sourceRaid.encounters))
end

-- Test checksum computation
function OGRH.Test.ActiveRaidChecksum()
    local checksum1 = OGRH.SyncChecksum.ComputeActiveRaidChecksum()
    assert(type(checksum1) == "string")
    assert(string.len(checksum1) == 32) -- MD5 length
    
    -- Modify structure
    OGRH_SV.v2.encounterMgmt.raids[1].name = "Modified"
    local checksum2 = OGRH.SyncChecksum.ComputeActiveRaidChecksum()
    assert(checksum1 ~= checksum2)
end

-- Test sync level routing
function OGRH.Test.SyncLevelRouting()
    -- Mock caller context
    local metadata = OGRH.SyncRouter.GetSyncMetadata("encounterMgmt.raids.1.encounters.1", "EncounterMgmt.lua")
    assert(metadata.syncLevel == "REALTIME")
    
    metadata = OGRH.SyncRouter.GetSyncMetadata("encounterMgmt.raids.1.encounters.1", "EncounterSetup.lua")
    assert(metadata.syncLevel == "BATCH")
    
    metadata = OGRH.SyncRouter.GetSyncMetadata("encounterMgmt.raids.2.encounters.1", nil)
    assert(metadata.syncLevel == "MANUAL")
end
```

### Integration Tests

**Scenario 1: Set Active Raid**
1. Admin right-clicks Encounter button
2. Selects "Molten Core" from menu
3. Confirms overwrite dialog
4. Verify:
   - Active raid updated (index 1)
   - All encounters copied
   - Assignments copied
   - Synced to all clients (BATCH)
   - Clients see same active raid

**Scenario 2: Live Raid Execution**
1. Admin makes assignment change in EncounterMgmt
2. Verify:
   - Change written to active raid (index 1)
   - REALTIME sync triggered
   - All clients receive update immediately
   - Checksum validation passes

**Scenario 3: Planning Mode**
1. Admin opens Encounter Planning
2. Changes role configuration
3. Verify:
   - Change written to active raid (index 1)
   - BATCH sync triggered (2-second delay)
   - All clients receive update after batch
   - Checksum validation passes

**Scenario 4: Checksum Mismatch**
1. Admin broadcasts checksums
2. Client manually corrupts local data
3. Verify:
   - Client detects mismatch
   - Client sends repair request
   - Admin buffers for 1 second
   - Admin broadcasts repair data
   - Client applies repair
   - Checksum validation passes

---

## File-by-File Changes

### New Files

#### `_Infrastructure/SyncChecksum.lua`
**Purpose:** Centralized checksum computation and validation

**Functions:**
- `ComputeActiveRaidChecksum()` → string
- `ComputeActiveAssignmentsChecksum(encounterIndex)` → string
- `ComputeRolesUIChecksum()` → string
- `BroadcastChecksums()` → void
- `ValidateChecksums(broadcastData)` → mismatches[]
- `QueueRepairRequest(player, component, encounterIndex)` → void
- `FlushRepairBuffer()` → void

#### `_Infrastructure/SyncRouter.lua`
**Purpose:** Sync level decision logic

**Functions:**
- `GetSyncMetadata(path, callerFile)` → syncMetadata
- `IsActiveRaidPath(path)` → boolean
- `GetCallerContext()` → filename

#### `_Infrastructure/SyncRepair.lua` (Refactored from SyncGranular.lua)
**Purpose:** Granular repair operations

**Functions:**
- `BroadcastActiveRaid()` → void
- `BroadcastEncounterAssignments(encounterIndex)` → void
- `BroadcastRoles()` → void
- `RequestActiveRaidSync()` → void
- `RequestEncounterAssignmentsSync(encounterIndex)` → void
- `RequestRolesSync()` → void

### Modified Files

#### `_Core/SavedVariablesManager.lua`
**Changes:**
- Integrate SyncRouter for auto-metadata assignment
- Add context detection (caller filename)
- Update SetPath() to route based on active raid context

**Lines to Modify:**
- Line 213-235 (SetPath function)

#### `_Core/Core.lua`
**Changes:**
- Add Active Raid initialization on startup
- Call `OGRH.EncounterMgmt.EnsureActiveRaid()` in bootstrap

**Lines to Add:**
- After line 120 (schema bootstrap)

#### `_Raid/EncounterMgmt.lua`
**Changes:**
- Add `EnsureActiveRaid()` function
- Add `SetActiveRaid(sourceRaidIndex)` function
- Update all SVM.SetPath calls to omit metadata (auto-routed)
- Update `OGRH.SetEncounter()` to target active raid only

**Estimated Changes:** 20+ SetPath calls

#### `_Raid/EncounterSetup.lua`
**Changes:**
- Add permission check before writes to active raid (index 1)
- Keep raid dropdown functional (no UI changes)
- Update all SVM.SetPath calls to omit metadata (auto-routed based on raid index)
- Add error messaging for permission failures

**Estimated Changes:** 
- 30+ SetPath calls (metadata removal)
- 5+ permission checks (before write operations)

#### `_UI/MainUI.lua`
**Changes:**
- Modify existing right-click handler on Encounter button
- Change context menu from "Select Raid/Encounter" to "Set Active Raid"
- Implement confirmation dialog for overwrite warning
- Add active raid indicator (text label or icon)

**Lines to Modify:** Existing right-click menu handler (~50 lines)

#### `_Raid/RolesUI.lua`
**Changes:**
- Update all SVM.SetPath calls to omit metadata (auto-routed)
- Ensure role changes target `roles.*` (not active raid specific)

**Estimated Changes:** 5+ SetPath calls

### Files to Delete

- `_Infrastructure/Sync_v2.lua`
- `_Infrastructure/SyncDelta.lua`
- `_Infrastructure/SyncUI.lua`

**Migration:** Move critical functions to SyncRepair.lua before deletion

### Files to Audit (Scattered Sync Calls)

**Search Pattern:**
```bash
grep -rn "MessageRouter.Broadcast\|OGAddonMsg.SendAddonMessage" --include="*.lua" \
  | grep -v "_Infrastructure/Sync"
```

**Expected Files:**
- `_Raid/EncounterMgmt.lua`
- `_Raid/EncounterSetup.lua`
- `_Raid/RolesUI.lua`
- `_UI/MainUI.lua`
- `_Configuration/ConsumesTracking.lua`
- `_Configuration/Roster.lua`

**Action:** Replace all direct sync calls with SVM.SetPath()

---

## Open Questions & Feedback

### Design Decisions (User Confirmed)

1. **Active Raid Display Name:**
   - ✅ Format: `"[AR] Source Raid Name"` (e.g., "[AR] Molten Core")
   - The `[AR]` prefix clearly indicates active raid status

2. **Multiple Admins:**
   - ❌ **Cannot occur** - addon enforces single admin
   - Multiple admins would be a configuration error
   - Last write wins if somehow multiple admins exist (error recovery)

3. **Empty Active Raid:**
   - ❌ **Not allowed** - Active raid with no encounters is allowed, but must have source raid selected
   - User must select source via "Set Active Raid" on first use
   - Display shows `"[AR] No Raid Selected"` until configured

4. **Saved Raid Changes:**
   - ✅ No prompts - saved raid edits are local only
   - User explicitly uses "Set Active Raid" when ready to sync

5. **Assignment Pre-Planning:**
   - ✅ **Preserved** - When setting active raid, existing assignments are kept
   - Allows incremental planning without losing work

### Potential Issues Identified

#### Issue 1: Index Shifting on Migration
**Problem:** Existing code may reference raid indices directly  
**Solution:** Audit all `encounterMgmt.raids[n]` references, ensure they're relative or use semantic IDs

#### Issue 2: Sync Loops
**Problem:** Client repair request → Admin broadcast → Client validates → Repeat  
**Solution:** Include checksum in repair broadcast so clients skip validation if already synced

#### Issue 3: Combat Sync Blocking
**Problem:** Active raid changes during combat may be blocked by SVM  
**Solution:** Queue changes and flush after combat (already implemented in SVM.SyncConfig.offlineQueue)

#### Issue 4: Checksum Performance
**Problem:** Computing checksums for large raids may cause lag  
**Solution:** Cache checksums, invalidate only on write, compute asynchronously

---

## Success Metrics

### Performance Targets

| Metric | Target | Current (Estimated) |
|--------|--------|---------------------|
| Checksum computation | < 50ms | N/A |
| Sync latency (REALTIME) | < 200ms | ~500ms |
| Sync latency (BATCH) | 2-3s | ~5s |
| Memory overhead | < 5MB | ~15MB |
| Repair time (full active raid) | < 5s | ~30s |

### Code Quality Targets

- [ ] Zero scattered sync calls (all through SVM)
- [ ] Single checksum implementation (SyncChecksum.lua)
- [ ] < 5 sync-related files (down from 8)
- [ ] 100% SVM coverage for active raid writes
- [ ] Zero manual sync calls in UI code

### User Experience Targets

- [ ] < 2 clicks to set active raid
- [ ] Clear visual indicator of active raid
- [ ] Automatic sync (no manual intervention)
- [ ] Sub-second sync for assignments
- [ ] Graceful degradation (offline queue)

---

## Risks & Mitigation

### Risk 1: Data Corruption During Migration
**Likelihood:** Medium  
**Impact:** High  
**Mitigation:**
- Backup SavedVariables before migration
- Implement rollback command (`/ogrh migration rollback activeraid`)
- Extensive testing on test server first

### Risk 2: Sync Loops
**Likelihood:** Low  
**Impact:** Medium  
**Mitigation:**
- Include checksums in all broadcasts
- Clients skip processing if checksum matches
- Rate limit repair requests (1/minute per client)

### Risk 3: Performance Degradation
**Likelihood:** Medium  
**Impact:** Medium  
**Mitigation:**
- Profile checksum computation
- Implement caching
- Async computation for non-critical paths

### Risk 4: Breaking BigWigs Integration
**Likelihood:** Low  
**Impact:** High  
**Mitigation:**
- Thorough testing of boss pull detection
- Maintain backward compatibility layer
- Fuzzy encounter name matching

### Risk 5: User Confusion (Active Raid Concept)
**Likelihood:** Medium  
**Impact:** Low  
**Mitigation:**
- Clear UI labels ("[ACTIVE RAID]")
- Confirmation dialogs with explanations
- In-game help command (`/ogrh help activeraid`)

---

## Conclusion

This design implements a clean separation between "planning" (saved raids) and "execution" (active raid), with intelligent sync routing based on context. The centralized checksum system ensures data consistency while minimizing sync traffic. The 1-second repair buffer prevents broadcast storms during desync events.

**Key Advantages:**
- ✅ Eliminates race conditions (admin is source of truth)
- ✅ Reduces sync complexity (active raid is always synced)
- ✅ Enables pre-planning with assignments
- ✅ Centralizes all sync logic (maintainable)
- ✅ Performance optimizations (batching, buffering)

**Next Steps:**
1. Review and approve design
2. Create GitHub issues for each phase
3. Begin Phase 1 implementation
4. Set up test server for integration testing

---

**Document Version:** 1.0  
**Last Updated:** January 30, 2026  
**Status:** Awaiting Review
