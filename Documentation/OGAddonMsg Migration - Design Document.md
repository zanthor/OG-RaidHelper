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
- [x] Add delta sync infrastructure (not integrated yet)
- [x] Test with 2+ client raid environment - **VALIDATED** (710 chunks, ~100KB successfully transmitted)
- [x] Verify old BroadcastFullSync() calls new system - **COMPLETE** (OGRH_DataManagement.lua created)
- [x] Fix timeout issues - **RESOLVED** (lastReceived vs firstReceived)
- [x] Confirm permission checks work - **OPERATIONAL**
- [x] Complete checksum algorithm - **REPLACED** (old algorithm includes all advanced settings)
- [x] Checksum polling without auto-push - **ENABLED** (30-second polling, warning only)
- [x] Data Management UI - **CREATED** (Load Defaults, Import/Export, Push Structure)
- [x] Debug output removed - **CLEAN** (production ready)

**See `Documentation/PHASE2_TESTING.md` for test results and validation data**

**Phase 3: Message Migration (Week 3-4)**
- [ ] Migrate `OGRH_Core.lua` messages (18 send locations)
- [ ] Migrate `OGRH_RaidLead.lua` messages
- [ ] Migrate `OGRH_RolesUI.lua` messages
- [ ] Migrate `OGRH_EncounterMgmt.lua` messages
- [ ] Consolidate duplicate message handlers

**Phase 4: Permission Enforcement (Week 5)**
- [ ] Add permission checks to all modify operations
- [ ] Implement admin UI for permission management
- [ ] Add permission denial notifications
- [ ] Test permission escalation/demotion flows
- [ ] Add audit logging for permission changes

**Phase 5: Conflict Resolution (Week 6)**
- [ ] Implement version vector tracking
- [ ] Create merge conflict UI (OGST-styled)
- [ ] Add manual conflict resolution for admins
- [ ] Test concurrent edit scenarios
- [ ] Add rollback capability for bad merges

**Phase 6: Testing & Optimization (Week 7-8)**
- [ ] Load test with 40-player raids
- [ ] Test zone transitions during sync
- [ ] Test /reload during large transfers
- [ ] Optimize message frequency
- [ ] Add telemetry for sync performance

**Phase 7: Polish & Documentation (Week 9)**
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

The estimated effort is **9 weeks** for a single developer, or **5-6 weeks** with two developers working in parallel on infrastructure and migration tasks.

**Next Steps:**
1. Review and approve this design document
2. Create GitHub issues for each phase
3. Begin Phase 1 infrastructure implementation
4. Set up test environment with multiple WoW clients

---

**Document Maintainers:** AI Agent, User  
**Last Updated:** January 2026  
**Status:** Awaiting Review & Approval
