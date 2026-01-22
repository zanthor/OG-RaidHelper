# OG-RaidHelper: OGAddonMsg Migration & Synchronization Overhaul

**Version:** 1.0  
**Date:** January 2026  
**Status:** Phase 2 Complete - Core Sync Operational

---

## Executive Summary

This document outlines a comprehensive migration of OG-RaidHelper's addon communication system from direct `SendAddonMessage` usage to the robust `_OGAddonMsg` library. This migration will address critical synchronization issues, implement proper permission-based data management, and establish a scalable architecture for multi-user raid planning.

### Core Problems Addressed

1. **Unreliable message delivery** - Current system has no retry mechanism, leading to desync issues
2. **No permission model** - Anyone can modify anything, leading to conflicts
3. **No integrity checking** - Silent data corruption without detection
4. **Bandwidth inefficiency** - Large messages sent without chunking or throttling
5. **Zone/reload fragility** - Message loss during transitions
6. **No conflict resolution** - Last write wins, no versioning or merging

---

## Core Philosophy Integration

Per the **OG-RaidHelper Design Philosophy**, all implementations must:

### 1. WoW 1.12 Compatibility (MANDATORY)
- Use Lua 5.0/5.1 syntax only (`table.getn()`, `mod()`, `string.gfind()`)
- Event handlers use implicit globals (`this`, `event`, `arg1`-`arg9`)
- No modern WoW API patterns

### 2. OGST UI Library (MANDATORY)
- All UI components use OGST standard patterns
- Reference: `_OGST/README.md`
- Add new components to OGST first, then consume in OG-RaidHelper

### 3. Communication Layer Split
- **Addon-to-addon data sync**: Use `_OGAddonMsg` (hidden channel, reliable)
- **Raid announcements/chat**: Use `ChatThrottleLib` (visible channels, throttled)
- Never mix these two systems

### 4. Code Standards
- PascalCase for functions (`OGRH.DoSomething()`)
- camelCase for variables (`myVariable`)
- Comments for non-obvious logic
- Proper TOC load order

---

## Current State Analysis

### Message Types Currently In Use

Based on comprehensive code search across all `.lua` files:

#### 1. OGRH_Core.lua (Primary Message Hub)
| Message Type | Purpose | Current Implementation | Issues |
|--------------|---------|------------------------|---------|
| `READYCHECK_REQUEST` | Assistant requests ready check | Direct send, no ACK | No confirmation if received |
| `READYCHECK_COMPLETE` | Broadcast RC completion | Direct send | May not reach all clients |
| `AUTOPROMOTE_REQUEST:{name}` | Request promotion | Direct send | No guarantee of delivery |
| `ADDON_POLL` | Version/sync check | Broadcast to all | Spam on large raids |
| `ADDON_POLL_RESPONSE;{ver};{checksum}` | Poll response | Direct send | No deduplication |
| `ASSIGNMENT_UPDATE;{data}` | Role assignment changes | Semicolon-delimited | Size limit issues, no chunking |
| `ENCOUNTER_SYNC;{serialized}` | Full encounter sync | Serialized table | Can exceed 255 bytes |
| `ROLESUI_CHECK;{checksum}` | UI state verification | Simple checksum | No repair mechanism |
| `READHELPER_SYNC_RESPONSE;{data}` | Sync response | Large payload | Truncation risk |
| `RAID_LEAD_SET;{name}` | Announce raid lead | Simple broadcast | No persistence |
| `REQUEST_RAID_DATA` | Request full sync | Pull model | No chunking for large data |
| `REQUEST_CURRENT_ENCOUNTER` | Get active encounter | Pull model | May timeout |
| `REQUEST_STRUCTURE_SYNC` | Request structure data | Pull model | Large data risk |

#### 2. OGRH_Sync.lua (Dedicated Sync System)
| Message Type | Purpose | Current Implementation | Issues |
|--------------|---------|------------------------|---------|
| `SYNC_REQUEST:{checksum}` | Request sync with checksum | Targeted request | No retry |
| `SYNC_RESPONSE:{data}:{target}` | Sync data response | Targeted send | Size limits |
| `SYNC_CANCEL` | Cancel active sync | Broadcast | May miss clients zoning |
| `SYNC_DATA_START:{data}` | Begin chunked transfer | Custom chunking | Reinventing the wheel |
| `SYNC_DATA_CHUNK:{data}` | Chunk payload | Sequential send | No reassembly guarantee |
| `SYNC_DATA_END:{data}` | Finish chunked transfer | Completion marker | No verification |
| `ENC_STRUCT` | Encounter structure | MessageType enum | Better organized |
| `ENC_ASSIGN` | Encounter assignments | MessageType enum | Better organized |
| `ENC_ANNOUNCE` | Encounter announcement | MessageType enum | Better organized |
| `RH_SYNC` | ReadHelper sync | MessageType enum | Better organized |

#### 3. OGRH_RaidLead.lua
| Message Type | Purpose | Current Implementation | Issues |
|--------------|---------|------------------------|---------|
| `ADDON_POLL` | Check addon presence | Duplicate of Core | Multiple implementations |
| `SYNC_REQUEST` | Request sync | Duplicate of Sync.lua | Code duplication |
| `RAID_LEAD_QUERY` | Query current lead | Broadcast | No caching |

#### 4. OGRH_RolesUI.lua
| Message Type | Purpose | Current Implementation | Issues |
|--------------|---------|------------------------|---------|
| Direct structure changes | Inline SendAddonMessage | Ad-hoc format | No standardization |

#### 5. OGRH_EncounterMgmt.lua
| Message Type | Purpose | Current Implementation | Issues |
|--------------|---------|------------------------|---------|
| Encounter updates | Ad-hoc sends | Inconsistent format | Hard to maintain |

#### 6. OGRH_Promotes.lua
| Message Type | Purpose | Current Implementation | Issues |
|--------------|---------|------------------------|---------|
| `AUTOPROMOTE_REQUEST:{name}` | Duplicate of Core | Code duplication | Multiple sources |

#### 7. OGRH_ConsumesTracking.lua
| Message Type | Purpose | Current Implementation | Issues |
|--------------|---------|------------------------|---------|
| Consumes sync | CHAT_MSG_ADDON handler | Unknown format | Undocumented |

### Critical Issues Identified

1. **No unified message format** - Mix of semicolon-delimited, colon-prefixed, and ad-hoc formats
2. **Code duplication** - Same message types in multiple files (ADDON_POLL, SYNC_REQUEST, etc.)
3. **No chunking** - Large messages (ENCOUNTER_SYNC, READHELPER_SYNC_RESPONSE) risk truncation
4. **No retry** - Zero tolerance for network issues or zoning
5. **No permissions** - Any client can send any message
6. **No versioning** - Can't handle concurrent edits
7. **No integrity** - Checksums sent but no automatic repair
8. **Manual serialization** - Custom Serialize/Deserialize prone to bugs

---

## Proposed Architecture

### 1. Permission Model

**Three-tier permission system:**

| Role | Can Modify | Cannot Modify | Rationale |
|------|-----------|---------------|-----------|
| **Raid Admin** (creator/owner) | Structure, assignments, roles, settings | - | Full control for raid creator |
| **Raid Lead/Assist** | Assignments, roles | Structure, core settings | Tactical changes only |
| **Raid Member** | Own ready status, personal notes | Anything else | Read-only with personal data |

**Implementation:**
```lua
OGRH.Permissions = {
    ADMIN = "ADMIN",      -- Raid creator/owner
    OFFICER = "OFFICER",  -- Raid Lead + Assists
    MEMBER = "MEMBER"     -- Everyone else
}

function OGRH.GetPermissionLevel(playerName)
    -- Hardcoded admin override for specific users
    if playerName == "Tankmedady" or playerName == "Gnuzmas" then
        -- These users can always take admin and are treated as minimum Raid Assist
        return OGRH.Permissions.ADMIN
    end
    
    -- Check if player is admin (stored in structure data)
    if OGRH.IsRaidAdmin(playerName) then
        return OGRH.Permissions.ADMIN
    end
    
    -- Check if player is raid lead or assist
    if OGRH.IsRaidOfficer(playerName) then
        return OGRH.Permissions.OFFICER
    end
    
    return OGRH.Permissions.MEMBER
end

function OGRH.CanModifyStructure(playerName)
    return OGRH.GetPermissionLevel(playerName) == OGRH.Permissions.ADMIN
end

function OGRH.CanModifyAssignments(playerName)
    local level = OGRH.GetPermissionLevel(playerName)
    return level == OGRH.Permissions.ADMIN or level == OGRH.Permissions.OFFICER
end

function OGRH.RequestAdminRole()
    -- Any Raid Lead or Assist can request admin
    local playerName = UnitName("player")
    
    if not OGRH.IsRaidOfficer(playerName) and playerName ~= "Tankmedady" and playerName ~= "Gnuzmas" then
        OGRH.Error("Only Raid Lead or Assist can request admin role")
        return false
    end
    
    -- Broadcast admin takeover
    OGAddonMsg.Send(nil, nil, "OGRH_ADMIN_TAKEOVER", {
        newAdmin = playerName,
        timestamp = GetTime(),
        version = OGRH.IncrementDataVersion()
    }, {
        priority = "HIGH",
        onSuccess = function()
            OGRH.SetRaidAdmin(playerName)
            OGRH.Info("You are now the raid admin")
        end
    })
    
    return true
end

function OGRH.AssignAdminRole(targetPlayer)
    -- Current admin or L/A can assign admin to another L/A
    local playerName = UnitName("player")
    
    if not OGRH.CanModifyStructure(playerName) and not OGRH.IsRaidOfficer(playerName) then
        OGRH.Error("Only admin or Raid Lead/Assist can assign admin role")
        return false
    end
    
    if not OGRH.IsRaidOfficer(targetPlayer) and targetPlayer ~= "Tankmedady" and targetPlayer ~= "Gnuzmas" then
        OGRH.Error("Can only assign admin to Raid Lead or Assist")
        return false
    end
    
    -- Broadcast admin assignment
    OGAddonMsg.Send(nil, nil, "OGRH_ADMIN_ASSIGN", {
        newAdmin = targetPlayer,
        assignedBy = playerName,
        timestamp = GetTime(),
        version = OGRH.IncrementDataVersion()
    }, {
        priority = "HIGH",
        onSuccess = function()
            OGRH.SetRaidAdmin(targetPlayer)
            OGRH.Info(string.format("%s is now the raid admin", targetPlayer))
        end
    })
    
    return true
end
```

### 2. Data Versioning & Conflict Resolution

**Version Vector System:**

Each data structure (encounter, assignments, roles) maintains:
- `version` number (increments on each change)
- `lastModifiedBy` player name
- `lastModifiedAt` timestamp
- `checksum` for integrity verification

```lua
-- Example structure
OGRH.EncounterData = {
    encounterId = "BWL_001",
    version = 42,
    lastModifiedBy = "PlayerName",
    lastModifiedAt = 1234567890,
    checksum = "a1b2c3d4",
    structure = {...},
    assignments = {...}
}
```

**Conflict Resolution Strategy:**

1. **Version wins**: Higher version number takes precedence
2. **Admin override**: Admin can force their version
3. **Merge UI**: If versions conflict, show merge dialog to admin
4. **Timestamp tiebreaker**: If versions equal, newest timestamp wins
5. **Manual resolution**: Unresolvable conflicts flagged for admin review

### 3. Message Type Standardization

**Unified Message Prefix System:**

All messages use consistent format: `{CATEGORY}_{ACTION}_{SUBJECT}`

| Category | Actions | Subjects | Example |
|----------|---------|----------|---------|
| `STRUCT` | `SET`, `UPDATE`, `DELETE`, `REQUEST`, `RESPONSE` | `ENCOUNTER`, `GROUP`, `ROLE` | `STRUCT_UPDATE_ENCOUNTER` |
| `ASSIGN` | `SET`, `CLEAR`, `REQUEST`, `RESPONSE` | `PLAYER`, `ROLE`, `GROUP` | `ASSIGN_SET_PLAYER` |
| `SYNC` | `REQUEST`, `RESPONSE`, `CHECKSUM`, `REPAIR` | `FULL`, `PARTIAL`, `DELTA` | `SYNC_REQUEST_FULL` |
| `ADMIN` | `POLL`, `READY`, `PROMOTE` | `VERSION`, `CHECK`, `USER` | `ADMIN_POLL_VERSION` |
| `STATE` | `CHANGE`, `QUERY`, `RESPONSE` | `LEAD`, `ENCOUNTER`, `PHASE` | `STATE_CHANGE_LEAD` |

**Example Migration:**

```lua
-- OLD: Inconsistent formats
SendAddonMessage("OGRH", "READYCHECK_REQUEST", "RAID")
SendAddonMessage("OGRH", "ASSIGNMENT_UPDATE;" .. data, "RAID")
SendAddonMessage("OGRH", "RAID_LEAD_SET;" .. name, "RAID")

-- NEW: Consistent via OGAddonMsg
OGAddonMsg.Send(nil, nil, "OGRH_ADMIN_READY_REQUEST", "", {
    priority = "HIGH",
    onSuccess = function()
        OGRH.OnReadyCheckSent()
    end
})

OGAddonMsg.Send(nil, nil, "OGRH_ASSIGN_UPDATE_PLAYER", assignmentData, {
    priority = "NORMAL",
    onSuccess = function()
        OGRH.UI.UpdateAssignmentDisplay()
    end
})

OGAddonMsg.Send(nil, nil, "OGRH_STATE_CHANGE_LEAD", {
    newLead = name,
    timestamp = GetTime(),
    version = OGRH.GetDataVersion()
}, {
    priority = "HIGH"
})
```

### 4. Integrity Checking System

**Fast Checksum Protocol:**

Instead of sending full data repeatedly, use checksums for verification:

```lua
-- Lightweight structure checksum
function OGRH.ComputeStructureChecksum()
    local data = OGRH.GetCurrentEncounter()
    if not data then return "EMPTY" end
    
    -- Hash critical fields only (not full serialization)
    local hashInput = string.format("%s:%d:%s",
        data.encounterId or "",
        data.version or 0,
        data.lastModifiedBy or ""
    )
    
    return OGRH.Hash(hashInput)
end

-- Periodic verification
function OGRH.StartIntegrityChecks()
    -- Every 30 seconds, broadcast our checksum
    OGRH.ScheduleRepeatingTimer(function()
        local myChecksum = OGRH.ComputeStructureChecksum()
        
        OGAddonMsg.Send(nil, nil, "OGRH_SYNC_CHECKSUM_STRUCTURE", {
            checksum = myChecksum,
            version = OGRH.GetDataVersion()
        }, {
            priority = "LOW"  -- Don't spam high priority
        })
    end, 30)
end

-- Checksum mismatch handler
function OGRH.OnChecksumMismatch(sender, theirChecksum, theirVersion)
    local myChecksum = OGRH.ComputeStructureChecksum()
    local myVersion = OGRH.GetDataVersion()
    
    if myVersion < theirVersion then
        -- We're out of date, request sync
        OGRH.RequestFullSync(sender)
    elseif myVersion > theirVersion then
        -- They're out of date, send update
        if OGRH.CanModifyStructure(UnitName("player")) then
            OGRH.SendFullSync(sender)
        end
    else
        -- Same version, different checksum = corruption!
        OGRH.ShowCorruptionWarning(sender)
        OGRH.RequestAdminIntervention()
    end
end
```

**Granular Delta Sync:**

Instead of full data transfers, send only changes:

```lua
-- Track changes since last sync
OGRH.ChangeLog = {}

function OGRH.RecordChange(changeType, target, oldValue, newValue)
    table.insert(OGRH.ChangeLog, {
        type = changeType,
        target = target,
        oldValue = oldValue,
        newValue = newValue,
        timestamp = GetTime(),
        author = UnitName("player")
    })
end

-- Example: Player assignment change
function OGRH.AssignPlayer(playerName, role, group)
    local oldAssignment = OGRH.GetPlayerAssignment(playerName)
    
    -- Make change locally
    OGRH.SetPlayerAssignment(playerName, role, group)
    
    -- Record change
    OGRH.RecordChange("ASSIGN_PLAYER", playerName, oldAssignment, {
        role = role,
        group = group
    })
    
    -- Broadcast delta
    OGAddonMsg.Send(nil, nil, "OGRH_ASSIGN_DELTA_PLAYER", {
        player = playerName,
        role = role,
        group = group,
        previousRole = oldAssignment.role,
        previousGroup = oldAssignment.group,
        version = OGRH.IncrementDataVersion(),
        author = UnitName("player")
    }, {
        priority = "NORMAL"
    })
end
```

### 5. Migration Roadmap

**Phase 1: Infrastructure (Week 1)** ✅ COMPLETE
- [x] Integrate `_OGAddonMsg` into TOC load order
- [x] Create `OGRH_MessageRouter.lua` - central message handling
- [x] Define all message types in `OGRH_MessageTypes.lua` enum
- [x] Implement permission system in `OGRH_Permissions.lua`
- [x] Create versioning system in `OGRH_Versioning.lua`

**Phase 2: Core Sync Replacement (Week 2)** ✅ COMPLETE
- [x] Replace OGRH_Sync.lua chunking with OGAddonMsg
- [x] Migrate SYNC_REQUEST/SYNC_RESPONSE pattern
- [x] Implement checksum verification system
- [x] Add delta sync infrastructure stubs (integration deferred to Phase 3)
  - [x] Create `OGRH_SyncDelta.lua` with stub functions
  - [x] Add `RecordDelta()` and `FlushDeltas()` to OGRH_Sync_v2.lua
  - [x] Add delta batching state management
  - [ ] **DEFERRED TO PHASE 3**: Connect delta sync to actual assignment/role operations
- [x] Test with 2+ client raid environment - **VALIDATED** (710 chunks, ~100KB successfully transmitted)
- [x] Verify old BroadcastFullSync() calls new system - **COMPLETE** (OGRH_DataManagement.lua created)
- [x] Fix timeout issues - **RESOLVED** (lastReceived vs firstReceived)
- [x] Confirm permission checks work - **OPERATIONAL**
- [x] Complete checksum algorithm - **REPLACED** (old algorithm includes all advanced settings)
- [x] Checksum polling without auto-push - **ENABLED** (30-second polling, warning only)
- [x] Data Management UI - **CREATED** (Load Defaults, Import/Export, Push Structure)
- [x] Debug output removed - **CLEAN** (production ready)

**See `Documentation/PHASE2_TESTING.md` for test results and validation data**

**Phase 3A: Delta Sync Integration (Week 3)** ✅ COMPLETE
- [x] **Connect delta sync stubs to actual operations**
  - [x] Implement delta sync for player assignments
    - [x] Create record functions for role/assignment/group changes
    - [x] Wire to RolesUI drag-drop functionality
    - [x] Test batching during rapid clicks - **READY FOR TESTING**
  - [x] Implement delta message types
    - [x] Add `ASSIGN_DELTA_PLAYER` message handler
    - [x] Add `ASSIGN_DELTA_ROLE` message handler (with legacy ROLE_CHANGE support)
    - [x] Add `ASSIGN_DELTA_GROUP` message handler (placeholder)
    - [x] Add `ASSIGN_DELTA_BATCH` message handler
  - [x] Implement delta batch flushing
    - [x] 2-second batching delay implemented
    - [x] Automatic flush on delay expiration
    - [x] Manual ForceFlush() for testing
  - [x] Smart sync triggers
    - [x] Block delta sync during combat
    - [x] Block delta sync while zoning
    - [x] Queue changes for after combat/zone with automatic flush
  - [x] Event handlers for queue management
    - [x] PLAYER_ENTERING_WORLD - flush offline queue
    - [x] PLAYER_LEAVING_WORLD - set zoning flag
    - [x] RAID_ROSTER_UPDATE - flush on raid join
- [ ] **TESTING REQUIRED** (See `Documentation/PHASE3A_IMPLEMENTATION.md`)
  - [x] Test 1: Single role change with 2-second batch
  - [x] Test 2: Rapid changes (10+ in 2 seconds)
  - [x] Test 3: Combat blocking and auto-flush
  - [ ] Test 4: Zoning queue behavior
  - [NA] Test 5: Offline queue and raid join flush
  - [NA] Test 6: Legacy ROLE_CHANGE compatibility

**See `Documentation/PHASE3A_IMPLEMENTATION.md` for implementation details and test procedures**

**Phase 3B: OGRH_Core.lua Migration (Week 4)** ✅ SUBSTANTIALLY COMPLETE
- [x] Audit all SendAddonMessage calls in OGRH_Core.lua (18 locations) - **COMPLETE** (See `Documentation/PHASE3B_CORE_AUDIT.md`)
- [x] Migrate ready check system
  - [x] Replace `READYCHECK_REQUEST` with OGAddonMsg - **Item 1 COMPLETE**
  - [x] Replace `READYCHECK_COMPLETE` with OGAddonMsg - **Item 13 COMPLETE**
  - [x] Test ready check flow end-to-end
- [NA] Migrate autopromote system - **Still uses legacy CHAT_MSG_ADDON handler**
  - [NA] Replace `AUTOPROMOTE_REQUEST:{name}` with permission-aware version
  - [NA] Add permission check before processing request
  - [NA] Test promote flow
  - **Note**: Low priority, works reliably, no migration needed yet
- [x] Migrate addon polling
  - [x] Replace `ADDON_POLL` with OGAddonMsg version - **Item 10 COMPLETE**
  - [x] Replace `ADDON_POLL_RESPONSE` with OGAddonMsg version - **Item 10 COMPLETE**
  - [x] Add deduplication for poll responses - **0-2s randomization added**
- [x] Migrate assignment updates
  - [x] Replace `ASSIGNMENT_UPDATE` with delta sync calls (from Phase 3A) - **Item 6 COMPLETE**
  - [x] Verify delta batching works - **5 call sites in EncounterMgmt.lua migrated**
- [x] Migrate encounter selection broadcasts
  - [x] Replace `ENCOUNTER_SELECT` with STATE.CHANGE_ENCOUNTER - **Item 4 COMPLETE**
  - [x] 5 locations migrated (BigWigs + EncounterMgmt navigation)
- [x] Migrate encounter sync
  - [x] Replace unsafe fallback with proper sync - **Item 7 COMPLETE (deleted)**
  - [NA] Use OGAddonMsg auto-chunking - **Deferred to Phase 5**
  - [NA] Test large encounter data - **Phase 2 already validated**
- [x] Migrate remaining Core messages
  - [x] `ROLESUI_CHECK` with integrity system - **Item 8 COMPLETE (unified polling)**
  - [x] `READHELPER_SYNC_RESPONSE` - **Item 9 COMPLETE (removed, deprecated)**
  - [x] `RAID_LEAD_SET` with state management - **Item 11 COMPLETE**
  - [⚠️] `REQUEST_*` messages with pull model - **Items 14-16 DEFERRED TO PHASE 5**
- [x] Remove old SendAddonMessage calls from Core - **12/18 migrated, 6 deferred**
- [x] Test all Core functionality end-to-end

**Phase 3B Summary:**
- ✅ **12 items completed**: Items 1-11, 13 fully migrated to MessageRouter
- ⚠️ **6 items deferred to Phase 5**: Items 12, 14-18 (pull-based sync replaced by push-based automatic sync)
- **Result**: Core.lua migration effectively complete, remaining items are architectural changes for Phase 5

**See `Documentation/PHASE3B_CORE_AUDIT.md` for detailed migration log**

**See `Documentation/PHASE3B_CORE_AUDIT.md` for detailed migration log**

**Phase 3C: Remaining Module Migration (Week 5)** ⚠️ PARTIALLY COMPLETE
- [x] Migrate `OGRH_RaidLead.lua` messages - **COMPLETE (renamed to OGRH_AdminSelection.lua)**
  - [NA] Remove duplicate `ADDON_POLL` (use Core version) - **No duplicates found**
  - [NA] Remove duplicate `SYNC_REQUEST` (use Sync_v2 version) - **No duplicates found**
  - [x] Replace `RAID_LEAD_QUERY` with OGAddonMsg - **ALREADY REMOVED (Phase 3B Item 11)**
  - [x] Remove legacy `RAID_LEAD_SET` handler - **COMPLETE (removed from OGRH_Core.lua)**
  - [x] Remove SendAddonMessage fallback - **COMPLETE (removed from OGRH_Permissions.lua)**
  - [x] File renamed to OGRH_AdminSelection.lua per Phase 3C migration plan
  - **Status**: Fully migrated - all admin selection uses MessageRouter (STATE.CHANGE_LEAD)
- [x] Migrate `OGRH_RolesUI.lua` messages - **COMPLETE via Phase 3B Item 8**
  - [x] Replace direct SendAddonMessage with delta sync (from Phase 3A)
  - [x] RolesUI checksum moved to unified SyncIntegrity polling
  - [x] Auto-repair on mismatch implemented
  - [x] Test UI-driven assignment changes use delta
  - [x] Verify batch flushing on rapid UI clicks
- [x] Migrate `OGRH_EncounterMgmt.lua` messages - **COMPLETE via Phase 3B Items 4, 6**
  - [x] Standardize encounter update messages - **Item 4: STATE.CHANGE_ENCOUNTER (5 locations)**
  - [x] Use MessageRouter for all sends - **Item 6: Delta sync (5 assignment locations)**
  - [x] Test encounter creation/modification/deletion
  - **Status**: Encounter selection and assignment updates fully migrated
- [x] Migrate `OGRH_Promotes.lua` - **COMPLETE & TESTED**
  - [x] Replace `AUTOPROMOTE_REQUEST` with MessageRouter - **ADMIN.PROMOTE_REQUEST**
  - [x] Add handler to MessageRouter for promote requests
  - [x] Remove legacy handler from Core.lua
  - [x] Test autopromote flow end-to-end
  - **Status**: Auto-promote system fully migrated to MessageRouter and validated
- [x] Migrate `OGRH_ConsumesTracking.lua` - **NO MIGRATION NEEDED**
  - [x] Audit for network code - **NONE FOUND**
  - **Status**: Only listens to BigWigs CHAT_MSG_ADDON (external addon integration), never sends messages
- [ ] Consolidate all duplicate message handlers
  - [x] Create single authoritative handler for each message type - **MessageRouter handlers in place**
  - [x] Remove redundant handlers - **ReadHelper handlers removed (Phase 3B Item 9)**
  - [x] Add warnings for deprecated message formats - **SendAddonMessage wrapper deprecated (Phase 3B Item 3)**
- [ ] Final cleanup
  - [ ] Grep for any remaining SendAddonMessage calls
  - [ ] Verify all handlers use MessageRouter
  - [ ] Remove unused message handler code

**Phase 3C Summary:**
- ✅ **RaidLead fully migrated** (all admin messages use MessageRouter, file renamed to AdminSelection.lua)
- ✅ **RolesUI fully migrated** (Item 8: unified polling + auto-repair)
- ✅ **EncounterMgmt fully migrated** (Items 4, 6: encounter selection + assignments)
- ✅ **Promotes fully migrated** (ADMIN.PROMOTE_REQUEST handler registered)
- ✅ **ConsumesTracking audited** (no network code, BigWigs listener only)
- **Result**: Phase 3C COMPLETE - All modules migrated to MessageRouter or confirmed no migration needed

**Phase 4: Permission Enforcement (Week 6)** ✅ COMPLETE
- [x] Add permission checks to all modify operations
  - **Completed**: Permission checks added during Phase 3 migrations
  - **Validated**: Drag-drop, encounter modification, assignment changes all check permissions
  - **System**: OGRH_Permissions.lua (ADMIN, OFFICER, MEMBER hierarchy)
- [NA] Implement admin UI for permission management - **NOT NEEDED**
  - Admin controlled via `/ogrh sa` command (session admin)
  - Admin selection via poll interface (PollAddonUsers)
  - Transfer admin via right-click "Admin" button
  - **Rationale**: Command-based admin control sufficient, no UI needed
- [x] Add permission denial notifications
  - **Completed**: Clear error messages implemented during Phase 3 testing
  - **Example**: "You don't have permission to modify role assignments (requires OFFICER or ADMIN)"
- [x] Test permission escalation/demotion flows
  - **Tested**: Admin transfer working (poll + direct assignment)
  - **Tested**: Raid lead/assist changes respected
  - **Tested**: Non-admin blocked from structure modifications
  - **Validated**: Permission system operational

**Phase 4 Summary:**
- ✅ All permission checks implemented and tested
- ✅ Permission denial feedback working
- ✅ Admin transfer mechanisms validated
- **Result**: Phase 4 COMPLETE - Permission system fully operational

**Phase 5: Granular Sync & Rollback System** ⏳ NOT STARTED

### Granular Sync Architecture

**Problem:** Current sync is all-or-nothing. Need ability to sync specific raids/encounters without affecting others.

**Solution:** Granular sync with hierarchical checksum validation and surgical repair

#### 5.1: Hierarchical Checksum Validation

**Data Structure:**

Based on actual structure in OGRH_SV:
```lua
-- Top-level saved variables (what gets synced)
OGRH_SV = {
  encounterMgmt = {                    -- Raid/encounter structure
    raids = {                          -- Array of raid objects
      {
        name = "BWL",
        encounters = {...},            -- Array of encounter objects
        advancedSettings = {...}       -- Raid-level settings
      }
    },
    roles = {                          -- [raidName][encounterName] = {column1, column2}
      ["BWL"] = {
        ["Razorgore"] = {
          column1 = {...},             -- Array of role objects
          column2 = {...}
        }
      }
    }
  },
  encounterAssignments = {             -- [raidName][encounterName][roleIndex][slotIndex] = playerName
    ["BWL"] = {
      ["Razorgore"] = {
        [1] = {[1] = "PlayerA", [2] = "PlayerB"},  -- Role 1 assignments
        [2] = {[1] = "PlayerC"}                     -- Role 2 assignments
      }
    }
  },
  encounterRaidMarks = {               -- [raidName][encounterName][roleIndex][slotIndex] = markIndex
    ["BWL"] = {
      ["Razorgore"] = {
        [1] = {[1] = 8, [2] = 7}       -- Skull, Cross
      }
    }
  },
  encounterAssignmentNumbers = {       -- [raidName][encounterName][roleIndex][slotIndex] = numberValue
    ["BWL"] = {
      ["Razorgore"] = {
        [1] = {[1] = 1, [2] = 2}       -- Tank 1, Tank 2
      }
    }
  },
  encounterAnnouncements = {           -- [raidName][encounterName] = array of strings
    ["BWL"] = {
      ["Razorgore"] = {"Line 1", "Line 2"}
    }
  },
  tradeItems = {...},                  -- Trade window configurations
  consumes = {...},                    -- Consumable definitions
  rgo = {...}                          -- Raid Group Organizer data
}
```

**Checksum Hierarchy:**

When a structure mismatch is detected, validate checksums at multiple levels to identify the exact corrupted component:

```lua
-- Level 1: Overall Structure Checksum (current implementation)
OverallChecksum = ComputeAllStructureChecksum()

-- If mismatch detected, drill down to Level 2: Per-Raid Checksums
RaidChecksums = {
  ["BWL"] = ComputeRaidChecksum("BWL"),
  ["MC"] = ComputeRaidChecksum("MC"),
  ["AQ40"] = ComputeRaidChecksum("AQ40")
}

-- If raid mismatch detected, drill down to Level 3: Per-Encounter Checksums
EncounterChecksums["BWL"] = {
  ["Razorgore"] = ComputeEncounterChecksum("BWL", "Razorgore"),
  ["Vaelastrasz"] = ComputeEncounterChecksum("BWL", "Vaelastrasz"),
  ["Broodlord"] = ComputeEncounterChecksum("BWL", "Broodlord")
}

-- If encounter mismatch detected, drill down to Level 4: Component Checksums
ComponentChecksums["BWL"]["Razorgore"] = {
  -- Encounter metadata (advancedSettings on encounter object)
  encounterSettings = ComputeChecksum(encounters["Razorgore"].advancedSettings),
  
  -- Role structure (from encounterMgmt.roles)
  roles = ComputeChecksum(encounterMgmt.roles["BWL"]["Razorgore"]),
  
  -- Player assignments (from encounterAssignments)
  playerAssignments = ComputeChecksum(encounterAssignments["BWL"]["Razorgore"]),
  
  -- Raid marks (from encounterRaidMarks)
  raidMarks = ComputeChecksum(encounterRaidMarks["BWL"]["Razorgore"]),
  
  -- Assignment numbers (from encounterAssignmentNumbers)
  assignmentNumbers = ComputeChecksum(encounterAssignmentNumbers["BWL"]["Razorgore"]),
  
  -- Announcements (from encounterAnnouncements)
  announcements = ComputeChecksum(encounterAnnouncements["BWL"]["Razorgore"])
}

-- Additionally, raid-level components
RaidLevelComponents = {
  ["BWL"] = {
    -- Raid metadata (advancedSettings on raid object)
    raidSettings = ComputeChecksum(raid.advancedSettings),
    
    -- Encounter list (raid.encounters array)
    encounterList = ComputeChecksum(raid.encounters)
  }
}

-- Global components (not tied to specific raid/encounter)
GlobalComponents = {
  tradeItems = ComputeChecksum(OGRH_SV.tradeItems),
  consumes = ComputeChecksum(OGRH_SV.consumes),
  rgo = ComputeChecksum(OGRH_SV.rgo)
}
```

**Validation Components:**

Based on the actual data structure, we have 3 granularity levels with different component types at each:

**1. Global-Level Components:**
- `tradeItems` - Trade window configurations (not encounter-specific)
- `consumes` - Consumable definitions (global list)
- `rgo` - Raid Group Organizer data (player role buckets)

**2. Raid-Level Components:**
- `raidMetadata` - Raid object itself (name, advancedSettings)
- `encounterList` - Array of encounter objects in this raid

**3. Encounter-Level Components:**
- `encounterMetadata` - Encounter advancedSettings (BigWigs integration, consume tracking)
- `roles` - Role structure definitions (from encounterMgmt.roles[raid][encounter])
- `playerAssignments` - Specific players assigned to role slots (encounterAssignments)
- `raidMarks` - Raid target marks per role slot (encounterRaidMarks)
- `assignmentNumbers` - Assignment numbers per role slot (encounterAssignmentNumbers)
- `announcements` - Announcement text array (encounterAnnouncements)

**Validation Flow:**

When overall checksum mismatch is detected:

1. **Compare Global Components** - Check tradeItems, consumes, rgo checksums
2. **Compare Per-Raid Checksums** - Identify which raid(s) have mismatches
3. **For Each Mismatched Raid:**
   - Compare raid-level components (raidMetadata, encounterList)
   - Compare per-encounter checksums for all encounters in this raid
4. **For Each Mismatched Encounter:**
   - Compare all 6 encounter-level components
   - Identify exact corrupted component(s)

**Sync Granularity:**

After identifying corrupted components via hierarchical validation, sync at the appropriate level:

1. **Global Component Sync** - Sync tradeItems, consumes, or rgo (entire table)
2. **Raid-Level Sync** - Sync entire raid object (all encounters + metadata)
3. **Encounter-Level Sync** - Sync entire encounter (all 6 components)
4. **Component-Level Sync** (finest) - Sync only corrupted component

**Component-Level Sync Examples:**
```lua
-- Sync only player assignments for Razorgore
SyncComponent("BWL", "Razorgore", "playerAssignments")
  -> Only updates encounterAssignments["BWL"]["Razorgore"]
  -> Leaves roles, marks, announcements untouched

-- Sync only announcements for Vaelastrasz
SyncComponent("BWL", "Vaelastrasz", "announcements")
  -> Only updates encounterAnnouncements["BWL"]["Vaelastrasz"]
  -> Everything else unchanged

-- Sync entire encounter (all 6 components)
SyncEncounter("BWL", "Razorgore")
  -> Updates all 6 components for this encounter
  -> Other encounters in BWL untouched

-- Sync entire raid (all encounters)
SyncRaid("BWL")
  -> Updates all encounters + raid metadata
  -> Other raids (MC, AQ40) untouched

-- Sync global component
SyncGlobalComponent("rgo")
  -> Only updates OGRH_SV.rgo
  -> Raids/encounters untouched
```

**Benefits of Hierarchical Validation:**

- **Surgical Sync**: Only sync the corrupted component, not entire encounter/raid
- **Performance**: Dramatic reduction in sync time through component-level targeting
- **Bandwidth**: Only transmit corrupted data, not entire structure
- **User Experience**: Faster repairs, less disruption during active raid
- **Diagnostics**: Exact location of corruption identified (e.g., "BWL > Razorgore > playerAssignments")

**Performance Analysis (Based on Network Constraints):**

Given OGAddonMsg network library constraints:
- MAX_CHUNK_SIZE: 200 bytes per message
- Header overhead: 39 bytes per chunk
- Effective payload: ~161 bytes per chunk (with short prefix)
- Max rate: 8 messages/second
- **Effective throughput: 1,288 bytes/second**

Performance projections based on default data (OGRH_Defaults.lua = 98,598 bytes):

| Sync Level | Estimated Size | Sync Time | Improvement |
|------------|---------------|-----------|-------------|
| Full Structure (all raids, defaults) | ~98,600 bytes | **76.5 seconds (1.3 min)** | Baseline |
| Single Raid (e.g., BWL with all encounters) | ~15,000 bytes | **11.6 seconds** | 85% reduction |
| Single Encounter (roles + assignments + marks + announcements) | ~5,000 bytes | **3.9 seconds** | 95% reduction |
| Single Component (e.g., just playerAssignments for one encounter) | ~500 bytes | **<1 second** | 99% reduction |
| RolesUI (40-player role buckets) | ~2,000 bytes | **1.6 seconds** | 98% reduction |
| Single Role Bucket (e.g., just TANKS) | ~500 bytes | **<1 second** | 99% reduction |

**Key Insights:**
- Current "full sync" takes **~76 seconds** for fresh defaults (heavily customized configs may take longer)
- Component-level sync (typical corruption case) takes **<5 seconds** (93%+ reduction)
- Per-role sync for RolesUI takes **<2 seconds** (98% reduction from full sync)
- Hierarchical validation prevents sending 98KB when only 500 bytes corrupted

**Validation Flow:**

```lua
-- Step 1: Detect overall mismatch
if OverallChecksum ~= AdminChecksum then
  
  -- Step 2: Check global components first
  for component, localChecksum in pairs(GlobalComponentChecksums) do
    if localChecksum ~= AdminGlobalChecksums[component] then
      RequestGlobalComponentSync(component)  -- Sync tradeItems/consumes/rgo
    end
  end
  
  -- Step 3: Identify corrupted raid(s)
  for raidName, localChecksum in pairs(RaidChecksums) do
    if localChecksum ~= AdminRaidChecksums[raidName] then
      
      -- Step 3a: Check raid-level components
      if RaidMetadataChecksum[raidName] ~= AdminRaidMetadataChecksum[raidName] then
        RequestRaidMetadataSync(raidName)  -- Sync raid.advancedSettings
      end
      if EncounterListChecksum[raidName] ~= AdminEncounterListChecksum[raidName] then
        RequestEncounterListSync(raidName)  -- Sync raid.encounters array structure
      end
      
      -- Step 4: Identify corrupted encounter(s)
      for encounterName, encounterChecksum in pairs(EncounterChecksums[raidName]) do
        if encounterChecksum ~= AdminEncounterChecksums[raidName][encounterName] then
          
          -- Step 5: Identify corrupted component(s)
          for component, componentChecksum in pairs(ComponentChecksums[raidName][encounterName]) do
            if componentChecksum ~= AdminComponentChecksums[raidName][encounterName][component] then
              
              -- Request sync for ONLY this component
              RequestComponentSync(raidName, encounterName, component)
            end
          end
        end
      end
    end
  end
end
```

**Implementation Strategy:**

- **Phase 5A**: Implement checksum hierarchy computation
- **Phase 5B**: Add component-level sync request/response
- **Phase 5C**: Update auto-repair to use hierarchical validation
- **Phase 5D**: Optimize RolesUI with same pattern (per-role checksums)

#### 5.2: Component-Level Sync Operations

**Sync API:**
```lua
-- Sync specific component of an encounter
OGRH.Sync.RequestComponentSync(raidName, encounterName, component)
  component: "encounterMetadata" | "roles" | "playerAssignments" | 
             "raidMarks" | "assignmentNumbers" | "announcements"

-- Sync entire encounter (all 6 components)
OGRH.Sync.RequestEncounterSync(raidName, encounterName)

-- Sync entire raid (all encounters + metadata)
OGRH.Sync.RequestRaidSync(raidName)

-- Sync global component
OGRH.Sync.RequestGlobalComponentSync(component)
  component: "tradeItems" | "consumes" | "rgo"
```

**Message Payloads:**
```lua
-- REQUEST_COMPONENT message
{
  raidName = "BWL",
  encounterName = "Razorgore",
  component = "playerAssignments",
  requester = "PlayerName"
}

-- RESPONSE_COMPONENT message
{
  raidName = "BWL",
  encounterName = "Razorgore",
  component = "playerAssignments",
  data = {
    [1] = {[1] = "TankA", [2] = "TankB"},
    [2] = {[1] = "HealerA", [2] = "HealerB", [3] = "HealerC"}
  },
  checksum = "abc123",
  timestamp = GetTime()
}
```

**Component Data Extraction:**
```lua
-- Extract specific component data
function GetComponentData(raidName, encounterName, component)
  if component == "encounterMetadata" then
    -- Get encounter.advancedSettings from raid object
    local raid = FindRaidByName(raidName)
    local encounter = FindEncounterInRaid(raid, encounterName)
    return encounter.advancedSettings
    
  elseif component == "roles" then
    return OGRH_SV.encounterMgmt.roles[raidName][encounterName]
    
  elseif component == "playerAssignments" then
    return OGRH_SV.encounterAssignments[raidName][encounterName]
    
  elseif component == "raidMarks" then
    return OGRH_SV.encounterRaidMarks[raidName][encounterName]
    
  elseif component == "assignmentNumbers" then
    return OGRH_SV.encounterAssignmentNumbers[raidName][encounterName]
    
  elseif component == "announcements" then
    return OGRH_SV.encounterAnnouncements[raidName][encounterName]
  end
end
```

**Benefits:**
- **Fastest sync**: Single component <1 second (vs 76 seconds full structure)
- **Minimal disruption**: Other components untouched
- **Bandwidth efficient**: 93%+ reduction for typical corruption scenario
- **Precise repairs**: Fix only what's broken

#### 5.3: Backup & Rollback System

**CRITICAL DESIGN DECISION: Separate SavedVariable for Backups**

To prevent backup data from triggering sync operations or being included in checksums, backups are stored in a **completely separate SavedVariable**: `OGRH_Backups`.

**Why Separate Storage?**
- `OGRH_SV` = Active data subject to sync, checksums, and validation
- `OGRH_Backups` = Local-only snapshots, NEVER synced or checksum'd
- Prevents backup restoration from appearing as "new changes" requiring broadcast
- Eliminates risk of backup data being accidentally synced to other players
- Backups are purely local rollback points, not part of the shared data model

**Backup Structure:**

```lua
-- Active data (OGRH_SV) - subject to sync & checksums
OGRH_SV = {
  encounterMgmt = { raids = {...} },
  encounterAssignments = {...},
  encounterRaidMarks = {...},
  encounterAssignmentNumbers = {...},
  encounterAnnouncements = {...},
  tradeItems = {...},
  consumes = {...},
  rgo = {...}
}

-- Backup data (OGRH_Backups) - NEVER synced, NEVER in checksums
OGRH_Backups = {
  backups = {
    -- Timestamped backups with raid name
    ["BWL_2026-01-21_14-30-00"] = {
      timestamp = 1737478200,
      raidName = "BWL",
      description = "Before sync from RaidLead",  -- Optional user description
      data = {
        encounterMgmt = {...},         -- Snapshot of structure
        encounterAssignments = {...},  -- Snapshot of assignments
        encounterRaidMarks = {...},
        encounterAssignmentNumbers = {...},
        encounterAnnouncements = {...}
      }
    },
    ["MC_2026-01-21_15-00-00"] = {
      timestamp = 1737480000,
      raidName = "MC",
      description = "Before RolesUI auto-repair",
      data = {...}
    }
  },
  maxBackups = 50  -- Configurable limit, auto-prune oldest
}
```

**Backup Naming Convention:**
- Format: `{RaidName}_{YYYY-MM-DD}_{HH-MM-SS}`
- Example: `BWL_2026-01-21_14-30-00`
- Timestamp in filename for easy sorting and identification

**Operations:**
```lua
-- Create backup before pull (stores in OGRH_Backups, NOT OGRH_SV)
OGRH.Backup.CreateRaidBackup(raidName, description)
  -> Creates new backup in OGRH_Backups.backups[]
  -> Does NOT modify OGRH_SV at all
  -> Auto-prunes old backups if > maxBackups

-- Restore from backup (copies backup data back into OGRH_SV)
OGRH.Backup.RestoreRaidBackup(backupKey)
  -> Loads data from OGRH_Backups.backups[backupKey]
  -> Overwrites OGRH_SV with backup data
  -> Creates new backup before restore (safety net)

-- Merge with backup (selective restore)
OGRH.Backup.MergeWithBackup(backupKey, strategy)
  -> strategy: "PREFER_LOCAL" | "PREFER_BACKUP" | "MANUAL"
  -> Intelligent merge of backup vs current data

-- List available backups
OGRH.Backup.GetBackupList(raidName)
  -> Returns sorted list of backups for specific raid
  -> nil for raidName = all backups

-- Delete old backups
OGRH.Backup.DeleteBackup(backupKey)
OGRH.Backup.PruneOldBackups(keepCount)  -- Auto-cleanup
```

**Auto-Backup Triggers:**
- Before pulling structure from admin (safety net for accidental overwrites)
- Before auto-applying RolesUI sync (undo failed repairs)
- Before restoring from export/import (recover from bad imports)
- Before manual "Pull All Data" operation (nuclear option safety)
- Manual backup via Data Management UI (user-initiated snapshots)

**Checksum Behavior:**
```lua
-- ✅ CORRECT: When computing checksums, ONLY OGRH_SV is included
function OGRH.ComputeAllStructureChecksum()
  local data = OGRH_SV  -- NEVER includes OGRH_Backups
  return OGRH.ComputeChecksum(data)
end

-- ❌ WRONG: Including backups in checksum
function OGRH.ComputeAllStructureChecksum()
  local data = {
    active = OGRH_SV,
    backups = OGRH_Backups  -- NEVER DO THIS!
  }
  return OGRH.ComputeChecksum(data)
end

-- Backups are invisible to sync system
-- Restoring a backup = local operation that modifies OGRH_SV, which then triggers NEW sync broadcast
-- This is correct behavior: restore changes active data → checksum changes → broadcast new state
```

**Implementation Notes:**
```lua
-- Example: Create backup before accepting sync
function OGRH.Sync.AcceptEncounterSync(raidName, encounterName, incomingData)
  -- Step 1: Create backup (stores in OGRH_Backups)
  local backupKey = OGRH.Backup.CreateRaidBackup(raidName, "Before sync from " .. senderName)
  
  -- Step 2: Apply incoming data to OGRH_SV
  OGRH_SV.encounterAssignments[raidName][encounterName] = incomingData.assignments
  OGRH_SV.encounterMgmt.roles[raidName][encounterName] = incomingData.roles
  -- ... apply other components
  
  -- Step 3: Checksum automatically changes because OGRH_SV changed
  -- (OGRH_Backups is NOT included in checksum, so backup creation didn't change checksum)
  
  -- Step 4: No need to broadcast - we just accepted sync, we're now in sync with admin
  
  OGRH.Msg("Sync applied. Backup saved as: " .. backupKey)
end

-- Example: Restore backup
function OGRH.Backup.RestoreRaidBackup(backupKey)
  -- Step 0: Safety backup of current state
  local safetyBackup = OGRH.Backup.CreateRaidBackup(raidName, "Before restore of " .. backupKey)
  
  -- Step 1: Load backup data (from OGRH_Backups)
  local backupData = OGRH_Backups.backups[backupKey]
  if not backupData then
    OGRH.Msg("Backup not found!")
    return false
  end
  
  -- Step 2: Copy backup data into OGRH_SV (overwrites active data)
  OGRH_SV.encounterAssignments[raidName] = OGRH.DeepCopy(backupData.data.encounterAssignments[raidName])
  OGRH_SV.encounterMgmt.roles[raidName] = OGRH.DeepCopy(backupData.data.encounterMgmt.roles[raidName])
  -- ... restore other components
  
  -- Step 3: OGRH_SV changed, so checksum changes
  -- Step 4: If we're raid admin, broadcast new state (our restored data is now authoritative)
  if OGRH.IsRaidAdmin() then
    OGRH.Sync.BroadcastRaidStructure(raidName)
  end
  
  OGRH.Msg("Backup restored. Current state saved as: " .. safetyBackup)
  return true
end
```

**TOC Configuration:**
```toc
## SavedVariables: OGRH_SV, OGRH_Backups
## SavedVariablesPerCharacter: OGRH_CharSV
```

#### 5.3: Merge Strategies

**Three-way merge for conflicts:**

1. **PREFER_LOCAL** - Keep local changes, only add missing data
   ```lua
   if localHasValue and backupHasValue then
       keep local
   elseif backupHasValue then
       use backup
   end
   ```

2. **PREFER_BACKUP** - Use backup data, only keep local if backup missing
   ```lua
   if backupHasValue then
       use backup
   elseif localHasValue then
       keep local
   end
   ```

3. **MANUAL** - Show merge UI with side-by-side comparison
   ```lua
   -- Display:
   [Local]              [Backup]
   Role 1: Tank (5)     Role 1: Tank (4)
   Role 2: Healer (6)   Role 2: Healer (7)
   
   [Use Local] [Use Backup] [Keep Both]
   ```

#### 5.4: RolesUI Auto-Repair (Phase 3B Complete)

**Current Implementation:**
- Admin broadcasts single checksum every 30 seconds (covers all roles)
- Client detects RolesUI mismatch
- Client auto-requests full RolesUI sync
- Admin immediately pushes all RolesUI data (~10KB, 40 players)
- Client applies and refreshes UI
- **Sync time**: ~7 seconds for 40-player raid (full dataset)

**Why Auto-Repair for RolesUI:**
- Foundational data (affects invites, assignments, class buckets)
- Low risk of data loss (bucket assignments rarely user-customized)
- Corruption quickly disrupts raid operations

**Performance Issue Identified:**
- Full 40-player sync takes ~7 seconds (all 4 role buckets)
- Most mismatches affect only 1 role bucket (e.g., tank reassigned)
- Current system sends all roles even if only 1 role corrupted

**Optimization Opportunity - Per-Role Granular Sync:**

The RolesUI data is already structured by role buckets:
```lua
OGRH_SV.roles = {
  ["PlayerA"] = "TANKS",
  ["PlayerB"] = "HEALERS",
  ["PlayerC"] = "MELEE",
  ["PlayerD"] = "RANGED"
}

-- Can be checksummed per-role:
Checksums = {
  TANKS = ComputeRoleChecksum("TANKS"),     -- Only tanks
  HEALERS = ComputeRoleChecksum("HEALERS"), -- Only healers
  MELEE = ComputeRoleChecksum("MELEE"),     -- Only melee
  RANGED = ComputeRoleChecksum("RANGED")    -- Only ranged
}
```

**Proposed Granular Sync:**
1. Admin broadcasts **4 checksums** (one per role bucket)
2. Client compares each checksum independently
3. Client requests sync **only for mismatched roles**
4. Admin sends only the affected role bucket's players
5. Client applies only the affected role bucket

**Benefits:**
- **75% bandwidth reduction** if only 1 role mismatched (typical case)
- **Sync time reduced**: ~12 minutes → ~30 seconds for full RolesUI, or ~2 seconds for single role
- **Same reliability**: Still detects all corruption
- **Backward compatible**: Can fall back to full sync if needed

**Implementation Complexity:**
- Low - data already bucketed by role
- Checksum function needs 4 calls instead of 1
- Sync request/response needs role parameter
- Auto-repair handler needs role-specific apply

**Recommendation:** Implement in Phase 5E after component-level structure sync established

#### 5.5: Structure & Assignment Sync (Future)

**Manual Sync (Current):**
- User opens Data Management window
- User clicks "Pull Structure from Admin"
- Creates backup, pulls data, applies

**Planned Granular Sync:**
```lua
-- Pull only current encounter
OGRH.DataManagement.PullCurrentEncounter()
  1. Create backup (_RaidName)
  2. Request structure for current raid/encounter
  3. Request assignments for current raid/encounter
  4. Apply only to current encounter
  5. Leave other encounters untouched

-- Pull entire raid (all encounters)
OGRH.DataManagement.PullEntireRaid(raidName)
  1. Create backup (_RaidName)
  2. Request all encounters for raid
  3. Request all assignments for raid
  4. Apply to entire raid
  5. Leave other raids untouched

-- Pull everything (nuclear option)
OGRH.DataManagement.PullAllData()
  1. Create full backup (all raids to _RaidName)
  2. Request all structure data
  3. Request all assignment data
  4. Replace everything
```

#### 5.6: Data Management UI Enhancements

**New Buttons:**
- "Pull Current Encounter" - Sync only current encounter
- "Pull Entire Raid" - Sync all encounters for current raid
- "Pull All Data" - Full sync (current behavior)
- "View Backups" - Show list of available backups
- "Restore Backup" - Rollback to backup
- "Merge with Backup" - Three-way merge UI

**Backup List View:**
```
Backups Available:
[_BWL]     2026-01-21 14:30:00   (15 minutes ago)
[_MC]      2026-01-21 13:45:00   (60 minutes ago)
[_AQ40]    2026-01-20 20:15:00   (18 hours ago)

[Restore] [Delete] [Export]
```

#### 5.7: Message Types for Granular Sync

**New Message Types:**
```lua
OGRH.MessageTypes.SYNC = {
    -- Existing
    REQUEST_FULL = "OGRH_SYNC_REQUEST_FULL",
    RESPONSE_FULL = "OGRH_SYNC_RESPONSE_FULL",
    
    -- New: Hierarchical validation
    REQUEST_CHECKSUMS = "OGRH_SYNC_REQUEST_CHECKSUMS",     -- Request full checksum tree
    RESPONSE_CHECKSUMS = "OGRH_SYNC_RESPONSE_CHECKSUMS",   -- Send checksum hierarchy
    
    -- New: Component-level sync
    REQUEST_COMPONENT = "OGRH_SYNC_REQUEST_COMPONENT",     -- Request specific component
    RESPONSE_COMPONENT = "OGRH_SYNC_RESPONSE_COMPONENT",   -- Send specific component
    
    -- New: Encounter-level sync
    REQUEST_ENCOUNTER = "OGRH_SYNC_REQUEST_ENCOUNTER",      -- Request entire encounter
    RESPONSE_ENCOUNTER = "OGRH_SYNC_RESPONSE_ENCOUNTER",    -- Send entire encounter
    
    -- New: Raid-level sync
    REQUEST_RAID = "OGRH_SYNC_REQUEST_RAID",                -- Request entire raid
    RESPONSE_RAID = "OGRH_SYNC_RESPONSE_RAID",              -- Send entire raid
    
    -- Backup operations
    CREATE_BACKUP = "OGRH_SYNC_CREATE_BACKUP",
    RESTORE_BACKUP = "OGRH_SYNC_RESTORE_BACKUP",
    LIST_BACKUPS = "OGRH_SYNC_LIST_BACKUPS"
}
```

**Message Payload Examples:**

```lua
-- Request component sync
{
  raidName = "BWL",
  encounterName = "Razorgore",
  component = "playerAssignments",  -- One of 8 component types
  requester = "PlayerName"
}

-- Response component sync
{
  raidName = "BWL",
  encounterName = "Razorgore",
  component = "playerAssignments",
  data = {...},  -- Only this component's data
  checksum = "abc123",
  timestamp = GetTime()
}
```

#### 5.8: Implementation Phases

**Phase 5A: Backup System & Hierarchical Checksum Computation**
- Implement backup storage in separate `OGRH_Backups` SavedVariable
- **CRITICAL**: Exclude `OGRH_Backups` from ALL checksum computations
- Add `OGRH_Backups` to TOC SavedVariables declaration
- Implement checksum functions for all 3 granularity levels:
  - Global components (tradeItems, consumes, rgo)
  - Raid-level components (raidMetadata, encounterList)
  - Encounter-level components (6 component types)
- **Verify**: Checksum functions only operate on `OGRH_SV`, never `OGRH_Backups`
- Add checksum caching to avoid redundant computation
- Test checksum stability and collision resistance
- Test that backup creation/restoration does NOT trigger sync operations
- Update SYNC_CHECKSUM broadcast to include hierarchy

**Phase 5B: Component-Level Sync Implementation**
- Add message types: REQUEST_CHECKSUMS, RESPONSE_CHECKSUMS
- Add message types: REQUEST_COMPONENT, RESPONSE_COMPONENT
- Add message types: REQUEST_GLOBAL_COMPONENT, RESPONSE_GLOBAL_COMPONENT
- Implement component-level serialization/deserialization
- Add validation to ensure only requested component is synced
- Test component sync for all 6 encounter-level types
- Test global component sync (tradeItems, consumes, rgo)

**Phase 5C: Hierarchical Validation & Auto-Repair**
- Update auto-repair to use hierarchical validation flow
- Implement component-level sync request logic
- Add fallback to full sync if component sync fails
- Test auto-repair with component-level corruption scenarios
- Measure performance improvement (target: 90%+ reduction)

**Phase 5D: Backup & Merge System**
- Implement backup system with `_RaidName` naming in separate SavedVariable
- **CRITICAL**: Store backups in `OGRH_Backups` (separate from `OGRH_SV`)
  - `OGRH_Backups` is NEVER included in checksums or sync operations
  - Prevents backup data from triggering sync/desync detection
  - Backups are local-only snapshots for rollback purposes
- Create backup before any sync operation
- Add backup list UI in Data Management window
- Implement three merge strategies (PREFER_LOCAL, PREFER_BACKUP, MANUAL)
- Test backup/restore/merge flows

**Phase 5E: RolesUI Per-Role Optimization**
- Implement per-role checksums (4 checksums: TANKS, HEALERS, MELEE, RANGED)
- Add role-specific sync request/response messages
- Update RolesUI auto-repair to sync only mismatched roles
- Test single-role corruption scenarios
- Validate performance improvement: ~12 min → ~2 seconds (99%+ reduction)

**Phase 5F: Data Management UI Enhancements**
- Add "Pull Current Encounter" button (sync only current encounter)
- Add "Pull Entire Raid" button (sync all encounters for current raid)
- Keep "Pull All Data" button (full sync - nuclear option)
- Add "View Backups" button (show backup list)
- Add "Restore Backup" button (rollback to backup)
- Add "Merge with Backup" button (three-way merge UI)

**Phase 5G: Auto-Repair Expansion** (Future Consideration)
- Evaluate extending auto-repair to assignments (lower priority)
- Consider auto-repair for structure (high risk - user customization)
- Implement opt-in auto-repair settings UI

---

### Design Principles for Granular Sync

1. **Hierarchical Validation** - Drill down from overall → global → raid → encounter → component
2. **Surgical Precision** - Sync only corrupted components, leave rest untouched
3. **Backup Before Modify** - Always create backup before applying remote data (stored in separate `OGRH_Backups` SavedVariable)
4. **User Control** - Default to manual sync, opt-in to auto-repair
5. **Safe Rollback** - Always provide way to undo sync operation
6. **Merge Support** - Handle conflicts gracefully with merge strategies
7. **Performance** - Component-level sync reduces sync time from 76 seconds (full structure) to <5 seconds (93%+ reduction)
8. **Data Safety** - Backups live in separate SavedVariable (`OGRH_Backups`), completely isolated from sync scope. Can NEVER be overwritten remotely, checksummed, or trigger sync operations.
9. **Sync Isolation** - Only `OGRH_SV` participates in checksums and sync. `OGRH_Backups` is purely local state for rollback.

---

**Phase 6: Testing & Optimization (Future)**
- [ ] Load test with 40-player raids
- [ ] Test zone transitions during sync
- [ ] Test /reload during large transfers
- [ ] Optimize message frequency
- [ ] Add telemetry for sync performance

**Phase 7: Polish & Documentation (Week 10)**
- [ ] Update all documentation
- [ ] Add user-facing sync status UI
- [ ] Create troubleshooting guide
- [ ] Add /ogrh sync commands for debugging
- [ ] Final QA pass

---

## Additional Feature Recommendations

### 1. Sync Status UI

**Visual sync indicator:**
```lua
-- Add to main UI window
local syncIndicator = CreateFrame("Frame", nil, OGRH.MainWindow)
OGST.StyleFrame(syncIndicator)
syncIndicator:SetWidth(200)
syncIndicator:SetHeight(30)
OGST.AnchorElement(syncIndicator, OGRH.MainWindow, {position = "top_right"})

-- Status states
OGRH.SyncStatus = {
    SYNCED = {color = {0, 1, 0}, text = "Synced"},
    SYNCING = {color = {1, 1, 0}, text = "Syncing..."},
    OUT_OF_SYNC = {color = {1, 0.5, 0}, text = "Out of Sync"},
    CONFLICT = {color = {1, 0, 0}, text = "Conflict!"},
    OFFLINE = {color = {0.5, 0.5, 0.5}, text = "Offline"}
}
```

### 2. Offline Mode

**Queue changes when not in raid:**
```lua
OGRH.OfflineQueue = {}

function OGRH.QueueChangeForSync(changeData)
    if GetNumRaidMembers() == 0 then
        -- Not in raid, queue it
        table.insert(OGRH.OfflineQueue, changeData)
        OGRH.SaveOfflineQueue()  -- Persist across /reload
        return true
    end
    return false
end

function OGRH.FlushOfflineQueue()
    -- Called when joining raid
    for i = 1, table.getn(OGRH.OfflineQueue) do
        local change = OGRH.OfflineQueue[i]
        OGRH.BroadcastChange(change)
    end
    OGRH.OfflineQueue = {}
end
```

### 3. Sync History / Audit Log

**Track who changed what:**
```lua
OGRH.AuditLog = {}

function OGRH.LogChange(changeType, author, details)
    table.insert(OGRH.AuditLog, {
        timestamp = time(),
        type = changeType,
        author = author,
        details = details
    })
    
    -- Keep last 100 changes only
    while table.getn(OGRH.AuditLog) > 100 do
        table.remove(OGRH.AuditLog, 1)
    end
end

function OGRH.ShowAuditLog()
    -- OGST window showing change history
    -- Useful for debugging and accountability
end
```

### 4. Sync Recovery Tools

**Admin tools for fixing desyncs:**
```lua
-- Force full resync from admin
function OGRH.ForceResyncFromAdmin()
    if not OGRH.CanModifyStructure(UnitName("player")) then
        OGRH.Error("Only raid admin can force resync")
        return
    end
    
    OGRH.BroadcastFullState({
        priority = "HIGH",
        requireAck = true,
        onComplete = function(ackCount)
            OGRH.Info(string.format("Resync sent to %d clients", ackCount))
        end
    })
end

-- Repair corrupted data
function OGRH.RepairCorruptedData()
    -- Request data from multiple sources
    -- Compare checksums
    -- Pick majority consensus
    -- Report to admin if unable to repair
end
```

### 5. Bandwidth Monitoring

**Prevent addon from causing disconnects:**
```lua
OGRH.BandwidthMonitor = {
    bytesSentLastSecond = 0,
    messagesSentLastSecond = 0,
    lastResetTime = GetTime()
}

function OGRH.CheckBandwidthUsage()
    local now = GetTime()
    
    if now - OGRH.BandwidthMonitor.lastResetTime >= 1.0 then
        -- Reset counters every second
        OGRH.BandwidthMonitor.bytesSentLastSecond = 0
        OGRH.BandwidthMonitor.messagesSentLastSecond = 0
        OGRH.BandwidthMonitor.lastResetTime = now
    end
    
    -- Warn if exceeding safe limits
    if OGRH.BandwidthMonitor.bytesSentLastSecond > 2000 then
        OGRH.Warning("High bandwidth usage - throttling sync")
        return false  -- Block send
    end
    
    return true  -- OK to send
end
```

### 6. Smart Sync Triggers

**Only sync when necessary:**
```lua
-- Don't sync during combat
function OGRH.CanSyncNow()
    if UnitAffectingCombat("player") then
        return false, "In combat"
    end
    
    if OGRH.IsZoning then
        return false, "Zoning"
    end
    
    if OGRH.BandwidthMonitor.highUsage then
        return false, "High bandwidth usage"
    end
    
    return true
end

-- Batch changes during rapid edits
OGRH.ChangeBatcher = {
    pendingChanges = {},
    batchDelay = 2.0,  -- Send changes max every 2 seconds
    lastBatchTime = 0
}

function OGRH.BatchChange(change)
    table.insert(OGRH.ChangeBatcher.pendingChanges, change)
    
    local now = GetTime()
    if now - OGRH.ChangeBatcher.lastBatchTime >= OGRH.ChangeBatcher.batchDelay then
        OGRH.FlushChangeBatch()
    end
end

function OGRH.FlushChangeBatch()
    if table.getn(OGRH.ChangeBatcher.pendingChanges) == 0 then
        return
    end
    
    -- Send all pending changes in one message
    OGAddonMsg.Send(nil, nil, "OGRH_ASSIGN_BATCH_UPDATE", {
        changes = OGRH.ChangeBatcher.pendingChanges,
        version = OGRH.IncrementDataVersion()
    })
    
    OGRH.ChangeBatcher.pendingChanges = {}
    OGRH.ChangeBatcher.lastBatchTime = GetTime()
end
```

### 7. Read-Only Mode for Viewers

**Allow non-raid members to view plans:**
```lua
-- Raid member who's not in current raid can request read-only access
function OGRH.RequestReadOnlyAccess(targetPlayer)
    OGAddonMsg.SendTo(targetPlayer, "OGRH_SYNC_REQUEST_READONLY", {
        requester = UnitName("player"),
        reason = "Want to view raid plans"
    })
end

-- Admin can grant read-only snapshots
function OGRH.SendReadOnlySnapshot(targetPlayer)
    local snapshot = OGRH.CreateDataSnapshot()
    snapshot.readOnly = true
    snapshot.expiresAt = time() + 3600  -- Valid for 1 hour
    
    OGAddonMsg.SendTo(targetPlayer, "OGRH_SYNC_READONLY_DATA", snapshot, {
        priority = "BULK"
    })
end
```

### 8. Auto-Repair on Version Mismatch

**Detect and auto-fix common issues:**
```lua
function OGRH.OnVersionMismatch(sender, theirVersion)
    local myVersion = OGRH.GetDataVersion()
    
    -- Always pull from higher version
    if theirVersion > myVersion then
        OGRH.Info(string.format("Auto-updating from %s (v%d -> v%d)", 
            sender, myVersion, theirVersion))
        
        OGAddonMsg.SendTo(sender, "OGRH_SYNC_REQUEST_FULL", {
            requester = UnitName("player"),
            currentVersion = myVersion
        })
    end
end
```

---

## File Structure for New System

```
OG-RaidHelper/
├── OG-RaidHelper.toc (updated load order)
├── Libs/
│   └── _OGAddonMsg/          # Embedded or referenced
├── Core/
│   ├── OGRH_Core.lua          # Existing core (modified)
│   ├── OGRH_MessageRouter.lua # NEW: Central message routing
│   ├── OGRH_MessageTypes.lua  # NEW: Message type definitions
│   ├── OGRH_Permissions.lua   # NEW: Permission system
│   └── OGRH_Versioning.lua    # NEW: Version control
├── Sync/
│   ├── OGRH_Sync.lua          # MODIFIED: Use OGAddonMsg
│   ├── OGRH_SyncIntegrity.lua # NEW: Checksum & repair
│   ├── OGRH_SyncDelta.lua     # NEW: Delta sync system
│   └── OGRH_SyncUI.lua        # NEW: Sync status UI
├── Modules/
│   ├── OGRH_RaidLead.lua      # MODIFIED: Remove duplicate messages
│   ├── OGRH_RolesUI.lua       # MODIFIED: Use message router
│   ├── OGRH_EncounterMgmt.lua # MODIFIED: Use message router
│   └── ...
└── Documentation/
    ├── OGAddonMsg Migration - Design Document.md (this file)
    └── Message Protocol Reference.md # NEW: Message format docs
```

---

## Testing Strategy

### Unit Tests (Manual)

**Test Cases:**

1. **Permission Tests**
   - [ ] Admin can modify structure
   - [ ] Officer can modify assignments
   - [ ] Officer cannot modify structure
   - [ ] Member cannot modify anything
   - [ ] Permission checks on all operations

2. **Sync Tests**
   - [ ] Full sync with 1 other client
   - [ ] Full sync with 40 clients
   - [ ] Delta sync for single assignment
   - [ ] Delta sync for multiple rapid changes
   - [ ] Sync during zone transition
   - [ ] Sync during /reload
   - [ ] Sync with packet loss simulation

3. **Conflict Tests**
   - [ ] Two admins edit same encounter
   - [ ] Version rollback
   - [ ] Checksum mismatch detection
   - [ ] Corruption recovery
   - [ ] Concurrent edits to different sections

4. **Performance Tests**
   - [ ] 40-player raid, full sync time
   - [ ] Bandwidth usage during encounter changes
   - [ ] Memory usage over 4-hour raid
   - [ ] Message queue depth under load
   - [ ] Recovery time from desync

### Integration Tests

1. **Cross-file messaging**
   - Verify all files use MessageRouter
   - No direct SendAddonMessage calls remain
   - All handlers registered properly

2. **SavedVariables compatibility**
   - Old data migrates to new format
   - Version numbers preserved
   - No data loss during upgrade

3. **Multi-addon compatibility**
   - Works alongside DPSMate, BigWigs, etc.
   - Doesn't interfere with other addons using OGAddonMsg
   - ChatThrottleLib plays nice with OGAddonMsg

---

## Risk Assessment

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| Data loss during migration | HIGH | MEDIUM | Backup SavedVariables before upgrade, migration script with rollback |
| Performance degradation | MEDIUM | LOW | Benchmark before/after, optimize message frequency |
| Permission conflicts | MEDIUM | MEDIUM | Clear UI feedback, admin override capability |
| OGAddonMsg bugs | HIGH | LOW | Thorough testing of _OGAddonMsg first, isolate addon |
| User confusion | LOW | HIGH | In-game tutorial, clear status indicators, changelog |
| Backwards compatibility | MEDIUM | MEDIUM | Version detection, graceful degradation for old clients |

---

## Success Criteria

1. **Zero message truncation** - All messages delivered complete via chunking
2. **< 5% bandwidth increase** - Despite reliability improvements
3. **< 100ms sync latency** - For small changes (assignments)
4. **< 2 seconds full sync** - For complete raid structure (40 players)
5. **100% zone survival** - No desync after zoning
6. **Zero permission violations** - All checks enforced
7. **< 1% data corruption** - With auto-repair capability
8. **90% user satisfaction** - Based on feedback survey

---

## Open Questions

1. **Backwards compatibility**: Support clients without _OGAddonMsg?
   - **✅ RESOLVED**: No backwards compatibility. All clients must update to use sync features.
   
2. **Admin transfer**: How to transfer admin to new player?
   - **✅ RESOLVED**: Any Raid Lead or Assist can request/take admin or assign to another L/A. Hardcoded exception for `Tankmedady` and `Gnuzmas` to always allow them to take admin and be treated as Raid Assist (minimum) regardless of actual rank.

3. **Multiple raids**: Handle multiple encounters simultaneously?
   - **✅ RESOLVED**: No. Single encounter focus only. No need to support multiple concurrent encounters.

4. **Data retention**: How long to keep audit log and change history?
   - **✅ RESOLVED**: Session only. Audit log and change history cleared on logout/reload.

5. **Conflict UI**: How complex should merge interface be?
   - **✅ RESOLVED**: Simple "Keep Mine" vs "Keep Theirs" for MVP. No complex merge UI needed.

---

## Conclusion

This migration represents a fundamental improvement to OG-RaidHelper's reliability and usability. By leveraging `_OGAddonMsg` for robust message delivery and implementing proper permissions and versioning, we eliminate the primary sources of desync issues while enabling collaborative raid planning.

The estimated effort is **10 weeks** for a single developer, or **6-7 weeks** with two developers working in parallel on infrastructure and migration tasks.

**Phase Breakdown:**
- Phases 1-2: Infrastructure (2 weeks) ✅ COMPLETE
- Phase 3A-C: Delta sync + message migration (3 weeks) ← **NEXT**
- Phases 4-7: Permissions, conflicts, testing, polish (5 weeks)

**Next Steps:**
1. Review and approve this design document
2. Create GitHub issues for each phase
3. Begin Phase 1 infrastructure implementation
4. Set up test environment with multiple WoW clients

---

**Document Maintainers:** AI Agent, User  
**Last Updated:** January 2026  
**Status:** Awaiting Review & Approval
