# OG-RaidHelper Sync Optimization Design Document

**Status:** RFC (Request for Comments)  
**Version:** 1.0  
**Date:** 2026-02-08  
**Author:** System Analysis

---

## Executive Summary

The current sync system experiences catastrophic network traffic when raids form with multiple addon users. This document proposes a hierarchical, session-based repair system with UI feedback, granular checksum validation, and smart packet management to resolve scalability issues while maintaining data integrity.

---

## Problem Statement

### Current Behavior

**Symptoms:**
- Network traffic spikes when raid forms and users join
- Structure sync to clients never completes
- Traffic remains elevated until raid disbands or admin `/reloadui`
- System works with 3-5 users but fails with 15-25+ users

**Root Causes Identified:**

1. **Broadcast Storm on Join:**
   - Every new player joining triggers checksum validation
   - Failed validation triggers repair requests from ALL clients simultaneously
   - Repair buffer (1-2s) insufficient for large raid joins
   - No session management - repairs can overlap/conflict

2. **Oversized Repair Packets:**
   - Current system sends entire raid structure on mismatch
   - No granular repair (all-or-nothing approach)
   - Assignments included in structure repairs (bloat)
   - No chunking or progress tracking

3. **Continuous Re-Validation Loop:**
   - Clients continue requesting checksums while repairs in progress
   - Admin continues broadcasting checksums during repairs
   - Creates feedback loop: repair → checksum → mismatch → repair
   - No state management to suppress validation during repairs

4. **No Client Feedback:**
   - Clients have no visibility into sync status
   - No way to know if repair is needed/in-progress/complete
   - Users can modify data during repairs (causes conflicts)

5. **Queue Saturation:**
   - OGAddonMsg queue overwhelmed with concurrent repair requests
   - Priority system not utilized effectively
   - Large serialized tables exceed practical packet sizes
   - No backpressure mechanism

---

## Proposed Solution: Hierarchical Session-Based Repair System

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                     ADMIN CHECKSUM BROADCAST                    │
│  (structureChecksum, encountersChecksums[],                     │
│   rolesChecksums[enc][role], apRoleChecksums[enc][role],        │
│   rolesUIChecksum)                                              │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│                   CLIENT VALIDATION (Layer 1-4)                 │
│          structureChecksum → Pass/Fail (Raid Metadata)          │
│     encountersChecksums[] → Per-Encounter Pass/Fail Array       │
│    rolesChecksums[][] → Per-Role Structure Pass/Fail Array      │
│   apRoleChecksums[][] → Per-Role Assignments Pass/Fail Array    │
│         rolesUIChecksum → Pass/Fail (Global Roles)              │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                   ┌───────┴───────┐
                   │  Any Failure? │
                   └───────┬───────┘
                           │ YES
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│              CLIENT REPAIR REQUEST (Targeted)                   │
│   {repairSessionToken: nil, failedComponents: ["structure",     │
│    "encounter:1", "encounter:3", "rolesUI"]}                    │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│        ADMIN REPAIR SESSION INITIALIZATION (2s buffer)          │
│  - Generate repairSessionToken (timestamp + UUID)               │
│  - Lock UI/SVM (prevent admin edits)                            │
│  - Aggregate client requests                                    │
│  - Display repair panel with client list                        │
│  - Pause checksum broadcasts                                    │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│       ADMIN REPAIR SESSION BROADCAST (Layer 1 - Structure)      │
│  {sessionToken, structureData, encountersChecksums[],           │
│   rolesChecksums[enc][role], totalPackets, packetIndex}         │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│                 CLIENT VALIDATION (Layer 2 - Roles)             │
│       Validate encountersChecksums[] against local data         │
│     For each failing encounter, validate rolesChecksums[]       │
│      Request only failing roles: {sessionToken, repairs:        │
│         [{encounter: 1, roles: [2,5,8]}, ...]}                  │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│      ADMIN REPAIR SESSION BROADCAST (Layer 2 - Roles Only)      │
│   Chunked role data with: {sessionToken, encounter: 1,          │
│    roleIndex: 2, roleData, apRoleChecksum, packetMeta}          │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│         CLIENT VALIDATION (Layer 3 - Assignments)               │
│    Validate apRoleChecksum (assignments only) per role          │
│     Request assignment repairs: {sessionToken, repairs:         │
│       [{encounter: 1, role: 2, needsAP: true}, ...]}            │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│    ADMIN REPAIR SESSION BROADCAST (Layer 3 - Assignments)       │
│   Minimal assignment payloads: {sessionToken, encounter: 1,     │
│     role: 2, assignedPlayers: [...], raidMarks: {...}}          │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│              CLIENT REPAIR COMPLETE NOTIFICATION                │
│   {sessionToken, newChecksums: {structure, encounters[],        │
│              roles[][], rolesUI}}                               │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│                ADMIN REPAIR SESSION FINALIZATION                │
│  - Wait 1s for all client confirmations                         │
│  - Close repair panel                                           │
│  - Unlock UI/SVM                                                │
│  - Resume checksum broadcasts (30s interval)                    │
└─────────────────────────────────────────────────────────────────┘
```

---

## Checksum Hierarchy

### Layer 1: Raid Structure

**structureChecksum:**
- Raid metadata (name, displayName, enabled, autoRank, advancedSettings)
- Encounters metadata (name, displayName, announcements, advancedSettings)
- **EXCLUDES:** encounters array content, roles arrays, assignedPlayers

**Purpose:** Detect raid-level structural changes (add/remove encounters, rename, settings)

**Computation:**
```lua
-- Serialize raid with encounters array EXCLUDED
local raidCopy = {
    name = raid.name,
    displayName = raid.displayName,
    enabled = raid.enabled,
    autoRank = raid.autoRank,
    advancedSettings = raid.advancedSettings,
    encounterCount = raid.encounters and #raid.encounters or 0
}
checksum = HashString(Serialize(raidCopy))
```

---

### Layer 2: Encounters Structure

**encountersChecksums[idx]:**
- Per-encounter array of checksums
- Encounter metadata + roles structure
- **EXCLUDES:** assignedPlayers, raidMarks, assignmentNumbers

**Purpose:** Detect encounter-level changes (roles added/removed/renamed, settings)

**Computation:**
```lua
-- Per encounter
for idx, encounter in ipairs(raid.encounters) do
    local encCopy = {
        name = encounter.name,
        displayName = encounter.displayName,
        announcements = encounter.announcements,
        advancedSettings = encounter.advancedSettings,
        roles = {}
    }
    
    -- Include role structure (no assignments)
    for roleIdx, role in ipairs(encounter.roles) do
        encCopy.roles[roleIdx] = {
            name = role.name,
            priority = role.priority,
            faction = role.faction,
            isOptionalRole = role.isOptionalRole,
            -- EXCLUDE: assignedPlayers, raidMarks, assignmentNumbers
        }
    end
    
    encountersChecksums[idx] = HashString(Serialize(encCopy))
end
```

---

### Layer 3: Roles Structure

**rolesChecksums[encIdx][roleIdx]:**
- Per-role checksum within each encounter
- Role configuration + assignment slots (empty)
- **EXCLUDES:** assignedPlayers data (player names)

**Purpose:** Detect role-level changes (configuration, settings) without assignment data

**Computation:**
```lua
-- Per encounter, per role
for encIdx, encounter in ipairs(raid.encounters) do
    rolesChecksums[encIdx] = {}
    for roleIdx, role in ipairs(encounter.roles) do
        local roleCopy = {
            name = role.name,
            priority = role.priority,
            faction = role.faction,
            isOptionalRole = role.isOptionalRole,
            slotCount = role.assignedPlayers and #role.assignedPlayers or 0,
            -- EXCLUDE: assignedPlayers array content
        }
        rolesChecksums[encIdx][roleIdx] = HashString(Serialize(roleCopy))
    end
end
```

---

### Layer 4: Assignments (Assignment-Specific Checksums)

**apRoleChecksum[encIdx][roleIdx]:**
- Per-role assignment data ONLY
- Includes: assignedPlayers, raidMarks, assignmentNumbers

**Purpose:** Detect assignment changes without triggering structure repairs

**Computation:**
```lua
-- Per encounter, per role
for encIdx, encounter in ipairs(raid.encounters) do
    apRoleChecksum[encIdx] = {}
    for roleIdx, role in ipairs(encounter.roles) do
        local assignmentsCopy = {
            assignedPlayers = role.assignedPlayers or {},
            raidMarks = role.raidMarks or {},
            assignmentNumbers = role.assignmentNumbers or {}
        }
        apRoleChecksum[encIdx][roleIdx] = HashString(Serialize(assignmentsCopy))
    end
end
```

**apEncounterChecksum[idx]:**
- Aggregate of all apRoleChecksums for an encounter
- Quick validation that ANY role assignments changed

**apRolesChecksum:**
- Aggregate of all apRoleChecksums for all encounters
- Top-level assignments checksum (not currently used, reserve for future)

---

### Layer 5: Global Components

**rolesUIChecksum:**
- Global role bucket assignments (TANKS, HEALERS, MELEE, RANGED)
- Existing implementation (already working well)

**globalComponentsChecksums:**
- `consumes` checksum
- `tradeItems` checksum
- Other global data (future expansion)
- **NOTE:** These checksums are computed in SyncChecksum.lua but are **NOT currently used** in the sync process. They are left in place for future flexibility if global component syncing is needed later.

---

## Repair Session Management

### Session Token Structure

```lua
repairSessionToken = {
    timestamp = GetTime(),           -- Session creation time
    uuid = GenerateUUID(),           -- Unique session identifier
    adminName = UnitName("player"),  -- Admin who initiated
    phase = "init",                  -- init, structure, roles, assignments, complete
    totalPackets = 0,                -- Total repair packets expected
    sentPackets = 0,                 -- Packets sent so far
    respondedClients = {},           -- Clients who confirmed completion
    canceledAt = nil                 -- Timestamp if canceled
}
```

**Token Format (String):**
```
"REPAIR:{timestamp}:{uuid}"
Example: "REPAIR:1234567890.123:a1b2c3d4"
```

---

### Session States

#### Admin States

| State | Description | UI State | SVM State | Checksums |
|-------|-------------|----------|-----------|-----------|
| `IDLE` | No repair active | Unlocked | Unlocked | Broadcasting (30s) |
| `BUFFERING` | Collecting repair requests | Unlocked | Unlocked | Broadcasting |
| `REPAIR_INIT` | Session started, preparing | **Locked** | **Locked** | **Paused** |
| `REPAIR_STRUCTURE` | Sending structure data | **Locked** | **Locked** | **Paused** |
| `REPAIR_ROLES` | Sending role data | **Locked** | **Locked** | **Paused** |
| `REPAIR_ASSIGNMENTS` | Sending assignments | **Locked** | **Locked** | **Paused** |
| `REPAIR_COMPLETE` | Waiting for confirmations | **Locked** | **Locked** | **Paused** |
| `REPAIR_CANCELED` | Manual cancellation | Unlocked | Unlocked | **Paused (60s)** |

#### Client States

| State | Description | Panel Visible | Accepts Repairs |
|-------|-------------|---------------|-----------------|
| `SYNCED` | Data matches admin | No | No |
| `OUT_OF_SYNC` | Mismatch detected | No | No |
| `REPAIR_REQUESTED` | Waiting for session | No | No |
| `REPAIR_IN_PROGRESS` | Receiving repairs | **Yes** | **Yes** (if token matches) |
| `REPAIR_COMPLETE` | All repairs applied | **Yes** (closing) | No |

---

### Repair Request Buffering

**Admin Behavior:**

1. **First Request Received:**
   - Start 2-second buffer timer
   - Aggregate all requests into map: `{clientName: [components]}`
   
2. **During Buffer Period:**
   - Additional requests extend buffer by 0.5s (max 5s total)
   - Track unique clients requesting repairs
   - Build component-to-client mapping for targeted repairs

3. **Buffer Expires:**
   - Generate `repairSessionToken`
   - Build prioritized repair list (see Repair Priority Order below)
   - Transition to `REPAIR_INIT` state
   - Lock UI/SVM
   - Display repair panel
   - Broadcast session initialization

---

### Repair Priority Order

Repairs are batched for ALL clients and sent in priority order. All clients subscribed to the repair session receive and apply all packets.

**Priority Sequence:**

1. **Raid Structure** (if any client needs it)
   - Raid metadata, encounters metadata (no roles/assignments)

2. **Selected Encounter** (if any client needs any part of it)
   - Admin's currently selected encounter from MainUI
   - Complete repair: structure → roles → assignments (hierarchical)
   - **Always has a selection** (required when raid is active)

3. **Remaining Encounters** (only those needed by clients, in sort order)
   - Encounters AFTER selected (ascending order)
   - Encounters BEFORE selected (wrap around)
   - For each: structure → roles → assignments (hierarchical)
   - **Skip encounters not needed by any client**

4. **RolesUI** (if any client needs it)
   - Global role bucket assignments (TANKS, HEALERS, MELEE, RANGED)
   - Sent AFTER all encounter structure repairs complete

**Example:**

```
Admin has Encounter 3 selected
Client1 needs: Encounter 5
Client2 needs: Encounter 1, Encounter 5

Aggregate needs: Enc1, Enc5 (Enc3 not needed by anyone)
Repair order: 
  1. Raid Structure (if needed)
  2. Enc5 (after selected, needed by clients)
  3. Enc1 (before selected, needed by clients)
  4. RolesUI (if needed)

Note: Enc3 skipped - selected but not needed by any client
```

**Why This Order:**
- Selected encounter likely represents current raid progression
- Clients can use addon immediately for active fight
- Remaining encounters sync in background
- RolesUI repairs after structure ensures role buckets reference valid data

**Buffer Extension Logic:**
```lua
function OnRepairRequest(sender, data)
    if not repairBuffer.active then
        -- First request
        repairBuffer.active = true
        repairBuffer.deadline = GetTime() + 2.0
        repairBuffer.requests[sender] = data.components
        StartBufferTimer()
    else
        -- Additional request
        repairBuffer.requests[sender] = data.components
        local now = GetTime()
        local remaining = repairBuffer.deadline - now
        
        -- Extend by 0.5s if less than 1s remaining, cap at 5s total
        if remaining < 1.0 then
            local newDeadline = now + 0.5
            local totalTime = newDeadline - repairBuffer.startTime
            if totalTime <= 5.0 then
                repairBuffer.deadline = newDeadline
                ResetBufferTimer()
            end
        end
    end
end
```

---

## UI Components

### Admin Repair Panel (Docked to Main UI)

**Location:** Docked below main UI window (similar to Invite Mode panel)

**Layout:**
```
╔═══════════════════════════════════════════════════════════╗
║  🔧 Repair Session In Progress                            ║
╠═══════════════════════════════════════════════════════════╣
║  Status: Sending Role Repairs (Phase 2/3)                ║
║  Progress: ████████████░░░░░░░░░░░ 63% (15/24 packets)   ║
║                                                            ║
║  Clients Awaiting Repair (8):                            ║
║    ✓ PlayerOne    (Structure, Enc1, Enc3)                ║
║    ✓ PlayerTwo    (Enc2, Roles)                          ║
║    ⏳ PlayerThree  (Structure, All Encounters)            ║
║    ⏳ PlayerFour   (RolesUI)                              ║
║    ✓ PlayerFive   (Enc1)                                 ║
║    ⏳ PlayerSix    (Structure, Enc1-5)                    ║
║    ✓ PlayerSeven  (Enc3, RolesUI)                        ║
║    ⏳ PlayerEight  (All)                                  ║
║                                                            ║
║  [Cancel Repair]                                          ║
╚═══════════════════════════════════════════════════════════╝
```

**Fields:**
- **Status:** Current phase (Buffering, Structure, Roles, Assignments, Complete)
- **Progress Bar:** Packet progress (packets sent / total packets)
- **Client List:** 
  - ✓ = Confirmed complete
  - ⏳ = Awaiting repairs
  - Components = What they need repaired
- **Cancel Button:** Abort session (triggers 60s pause)

**Cancel Behavior:**
```
When clicked:
  1. Broadcast REPAIR_SESSION_CANCELED with token
  2. Unlock UI/SVM immediately
  3. Close panel → Show countdown panel
  4. Countdown panel shows "Checksums paused for 60s" with timer
  5. After 60s, close countdown panel and resume checksum broadcasts
```

**Countdown Panel (After Cancel):**
```
╔═══════════════════════════════════════════════════════════╗
║  ⏸️  Checksum Broadcasts Paused                           ║
╠═══════════════════════════════════════════════════════════╣
║  Resuming in: 47 seconds                                  ║
║                                                            ║
║  Use this time to fix sync issues manually.               ║
║  [Resume Now]                                             ║
╚═══════════════════════════════════════════════════════════╝
```

---

### Client Repair Panel (Docked to Main UI)

**Location:** Docked below main UI (if main UI open) or standalone frame

**Layout:**
```
╔═══════════════════════════════════════════════════════════╗
║  🔄 Receiving Data from Admin                             ║
╠═══════════════════════════════════════════════════════════╣
║  Status: Applying Role Repairs (Phase 2/3)               ║
║  Progress: ████████████░░░░░░░░░░░ 63% (15/24 packets)   ║
║                                                            ║
║  Estimated Time: 8 seconds remaining                      ║
║                                                            ║
║  Components Updated:                                      ║
║    ✓ Raid Structure                                       ║
║    ✓ Encounter: Razorgore (Roles 1-4)                    ║
║    ⏳ Encounter: Vaelastrasz (In Progress)                ║
║    ⏳ Encounter: Broodlord (Pending)                      ║
║    ✓ Global Roles (RolesUI)                              ║
╚═══════════════════════════════════════════════════════════╝
```

**Fields:**
- **Status:** Current phase receiving
- **Progress Bar:** Packet progress (estimated based on totalPackets)
- **ETA:** Estimated completion time (based on packet rate)
- **Component List:** What's been updated
  - ✓ = Complete
  - ⏳ = In progress/pending

**Auto-Close:**
- Stays open for 2 seconds after completion
- Shows "✓ Sync Complete" message
- Fades out

---

## Repair Data Structures

### Repair Request (Client → Admin)

```lua
{
    type = "REPAIR_REQUEST",
    sessionToken = nil,  -- nil for initial request
    sender = UnitName("player"),
    components = {
        structure = false,           -- Need raid structure?
        encounters = {               -- Per-encounter needs
            [1] = {
                structure = true,    -- Need encounter metadata/roles?
                roles = {2, 5, 8}    -- Specific role indices (or nil for all)
            },
            [3] = {
                structure = false,
                roles = {1, 3}
            }
        },
        rolesUI = true,              -- Need global roles?
        globalComponents = {"consumes"}  -- Specific global components
    }
}
```

---

### Repair Session Init (Admin → Clients)

```lua
{
    type = "REPAIR_SESSION_INIT",
    sessionToken = "REPAIR:1234567890.123:a1b2c3d4",
    totalPhases = 3,          -- Structure, Roles, Assignments
    totalPackets = 24,        -- Estimated total packets
    affectedClients = {       -- Who needs repairs
        "PlayerOne", "PlayerTwo", "PlayerThree"
    },
    checksums = {
        structure = "abc123",
        encounters = {
            [1] = "def456",
            [2] = "ghi789",
            [3] = "jkl012"
        },
        rolesUI = "mno345"
    }
}
```

---

### Structure Repair Packet (Admin → Clients)

```lua
{
    type = "REPAIR_STRUCTURE",
    sessionToken = "REPAIR:1234567890.123:a1b2c3d4",
    phase = "structure",
    packetIndex = 1,
    totalPackets = 24,
    
    -- Raid metadata (NO encounters array)
    raidData = {
        name = "BWL",
        displayName = "Blackwing Lair",
        enabled = true,
        autoRank = 3,
        advancedSettings = { ... }
    },
    
    -- Encounter metadata (NO roles arrays)
    encountersMetadata = {
        [1] = {
            name = "Razorgore",
            displayName = "Razorgore the Untamed",
            announcements = { ... },
            advancedSettings = { ... }
        },
        -- ... more encounters
    },
    
    -- Next layer checksums for validation
    encountersChecksums = {
        [1] = "def456",
        [2] = "ghi789",
        [3] = "jkl012"
    }
}
```

---

### Roles Repair Packet (Admin → Clients)

**Sent once per encounter-role combination that failed validation.**

```lua
{
    type = "REPAIR_ROLES",
    sessionToken = "REPAIR:1234567890.123:a1b2c3d4",
    phase = "roles",
    packetIndex = 5,
    totalPackets = 24,
    
    encounterIndex = 1,
    encounterName = "Razorgore",
    roleIndex = 2,
    
    -- Role structure (NO assignments)
    roleData = {
        name = "MT Dragonkin Tanks",
        priority = 1,
        faction = "both",
        isOptionalRole = false,
        slotCount = 3
        -- EXCLUDE: assignedPlayers, raidMarks, assignmentNumbers
    },
    
    -- Assignment checksum for next layer
    apRoleChecksum = "xyz789"
}
```

---

### Assignment Repair Packet (Admin → Clients)

**Sent only if apRoleChecksum fails after role repair.**

```lua
{
    type = "REPAIR_ASSIGNMENTS",
    sessionToken = "REPAIR:1234567890.123:a1b2c3d4",
    phase = "assignments",
    packetIndex = 15,
    totalPackets = 24,
    
    encounterIndex = 1,
    roleIndex = 2,
    
    -- Assignments only (minimal payload)
    assignments = {
        assignedPlayers = {"PlayerOne", "PlayerTwo", "PlayerThree"},
        raidMarks = {
            [1] = 8,  -- PlayerOne = skull
            [2] = 7   -- PlayerTwo = cross
        },
        assignmentNumbers = {
            [1] = 1,  -- PlayerOne = #1
            [2] = 2   -- PlayerTwo = #2
        }
    }
}
```

---

### RolesUI Repair Packet (Admin → Clients)

```lua
{
    type = "REPAIR_ROLESUI",
    sessionToken = "REPAIR:1234567890.123:a1b2c3d4",
    phase = "rolesUI",
    packetIndex = 23,
    totalPackets = 24,
    
    -- Global role assignments
    roles = {
        PlayerOne = "TANKS",
        PlayerTwo = "TANKS",
        PlayerThree = "HEALERS",
        PlayerFour = "MELEE",
        -- ... all players
    }
}
```

---

### Validation Response (Client → Admin)

**Sent after every checksum broadcast - BOTH pass AND fail results**

```lua
{
    type = "VALIDATION_RESPONSE",
    sender = UnitName("player"),
    addonVersion = "2.1.4",
    timestamp = GetTime(),
    
    -- Validation results (sent regardless of pass/fail)
    validationResult = {
        structureMatch = true,           -- true/false
        encountersMatch = {              -- Per-encounter results
            [1] = true,
            [2] = false,  -- Mismatch
            [3] = true
        },
        rolesUIMatch = true,
        globalComponentsMatch = {
            consumes = true,
            tradeItems = false  -- Mismatch
        },
        allMatch = false  -- Overall pass/fail (any false = false)
    }
}
```

**Admin Processing:**
```lua
-- Admin handler for validation responses
function OGRH.SyncSession.OnValidationResponse(sender, data)
    -- Update client sync status tracking
    OGRH.SyncSession.State.clientSyncStatus[sender] = {
        lastValidation = GetTime(),
        synced = data.validationResult.allMatch,
        version = data.addonVersion,
        isRepairing = false,
        failedComponents = ExtractFailedComponents(data.validationResult)
    }
    
    -- Check for newer client version (warn once per raid)
    OGRH.SyncSession.CheckClientVersion(sender, data.addonVersion)
    
    -- Update admin button tooltip
    OGRH.SyncRepairUI.UpdateAdminButtonTooltip()
    
    -- If ANY component failed, queue for repair
    if not data.validationResult.allMatch then
        OGRH.SyncSession.BufferRepairRequest(sender, {
            components = data.validationResult
        })
    end
end
```

---

### Version Check Warning

**Purpose:** Warn ANY player (admin or client) once per raid if their version is lower than the highest version in raid.

**Mechanism:**
1. Admin tracks highest version from all validation responses
2. Admin includes `highestVersion` in checksum broadcasts
3. Each player (admin + clients) compares their version to highest
4. Players with lower versions see warning (once per raid)

**Implementation:**

**Admin-side (tracking highest version):**
```lua
OGRH.SyncSession.State.versionWarnings = {
    warnedThisRaid = false,  -- Reset on raid form/disband
    highestVersion = nil     -- Highest version seen in raid
}

function OGRH.SyncSession.CheckClientVersion(sender, clientVersion)
    local myVersion = OGRH.VERSION  -- e.g., "2.1.4"
    
    -- Parse versions (major.minor.patch)
    local function ParseVersion(versionStr)
        local major, minor, patch = string.match(versionStr, "(%d+)%.(%d+)%.(%d+)")
        return {
            major = tonumber(major) or 0,
            minor = tonumber(minor) or 0,
            patch = tonumber(patch) or 0,
            str = versionStr
        }
    end
    
    -- Compare two version tables (returns true if v1 > v2)
    local function IsHigher(v1, v2)
        if v1.major > v2.major then return true end
        if v1.major < v2.major then return false end
        if v1.minor > v2.minor then return true end
        if v1.minor < v2.minor then return false end
        return v1.patch > v2.patch
    end
    
    local client = ParseVersion(clientVersion)
    
    -- Track highest version seen in raid
    if not OGRH.SyncSession.State.versionWarnings.highestVersion then
        OGRH.SyncSession.State.versionWarnings.highestVersion = client
    else
        local highest = OGRH.SyncSession.State.versionWarnings.highestVersion
        if IsHigher(client, highest) then
            OGRH.SyncSession.State.versionWarnings.highestVersion = client
        end
    end
    
    -- Check admin's own version against highest
    local highest = OGRH.SyncSession.State.versionWarnings.highestVersion
    local my = ParseVersion(myVersion)
    if IsHigher(highest, my) and not OGRH.SyncSession.State.versionWarnings.warnedThisRaid then
        OGRH.SyncSession.State.versionWarnings.warnedThisRaid = true
        
        DEFAULT_CHAT_FRAME:AddMessage(
            string.format("|cffff9900[OG-RaidHelper]|r Your OG-RaidHelper may need updated. Your Version: %s is lower than %s", 
                myVersion, highest.str),
            1.0, 0.6, 0.0
        )
    end
end
```

**Modified Checksum Broadcast (include highest version):**
```lua
-- In OGRH.SyncIntegrity.BroadcastChecksums()
local checksums = {
    -- ... existing checksum fields
    highestVersion = OGRH.SyncSession.State.versionWarnings.highestVersion and 
                     OGRH.SyncSession.State.versionWarnings.highestVersion.str or 
                     OGRH.VERSION,  -- Default to own version if no clients yet
    timestamp = GetTime(),
    version = OGRH.VERSION
}
```

**Client-side (check own version against highest):**
```lua
-- In OGRH.SyncIntegrity.OnChecksumBroadcast()
function OGRH.SyncIntegrity.OnChecksumBroadcast(sender, checksums)
    -- ... existing validation logic
    
    -- Check own version against highest in raid
    if checksums.highestVersion then
        OGRH.SyncSession.CheckOwnVersion(checksums.highestVersion)
    end
end

-- Client version check
OGRH.SyncSession.State.versionWarnings = {
    warnedThisRaid = false
}

function OGRH.SyncSession.CheckOwnVersion(highestVersionStr)
    if OGRH.SyncSession.State.versionWarnings.warnedThisRaid then
        return  -- Already warned this raid
    end
    
    local myVersion = OGRH.VERSION
    
    -- Parse versions
    local function ParseVersion(versionStr)
        local major, minor, patch = string.match(versionStr, "(%d+)%.(%d+)%.(%d+)")
        return {
            major = tonumber(major) or 0,
            minor = tonumber(minor) or 0,
            patch = tonumber(patch) or 0,
            str = versionStr
        }
    end
    
    local function IsHigher(v1, v2)
        if v1.major > v2.major then return true end
        if v1.major < v2.major then return false end
        if v1.minor > v2.minor then return true end
        if v1.minor < v2.minor then return false end
        return v1.patch > v2.patch
    end
    
    local my = ParseVersion(myVersion)
    local highest = ParseVersion(highestVersionStr)
    
    if IsHigher(highest, my) then
        OGRH.SyncSession.State.versionWarnings.warnedThisRaid = true
        
        DEFAULT_CHAT_FRAME:AddMessage(
            string.format("|cffff9900[OG-RaidHelper]|r Your OG-RaidHelper may need updated. Your Version: %s is lower than %s", 
                myVersion, highestVersionStr),
            1.0, 0.6, 0.0
        )
    end
end
```

**Reset on raid form/disband:**
```lua
function OGRH.SyncSession.OnRaidRosterUpdate()
    local currentSize = GetNumRaidMembers()
    
    -- Raid disbanded or reformed
    if currentSize == 0 or (OGRH.SyncSession.State.lastRaidSize == 0 and currentSize > 0) then
        OGRH.SyncSession.State.versionWarnings.warnedThisRaid = false
        OGRH.SyncSession.State.versionWarnings.highestVersion = nil  -- Admin only
    end
    
    OGRH.SyncSession.State.lastRaidSize = currentSize
end
```

**Trigger Points:**
- Admin: Checks when receiving validation responses from clients
- Clients: Check when receiving checksum broadcasts from admin (includes highest version)
- Warning shows in DEFAULT_CHAT_FRAME (yellow/orange text)
- Only warns once per raid formation per player
- Resets on raid disband or new raid form
- Does NOT warn players who already have the highest version

**Warning Format:**
```
[OG-RaidHelper] Your OG-RaidHelper may need updated. Your Version: 2.1.4 is lower than 2.1.5
```

---

### Repair Complete Confirmation (Client → Admin)

```lua
{
    type = "REPAIR_COMPLETE",
    sessionToken = "REPAIR:1234567890.123:a1b2c3d4",
    sender = UnitName("player"),
    
    -- New local checksums for verification
    checksums = {
        structure = "abc123",
        encounters = {
            [1] = "def456",
            [2] = "ghi789",
            [3] = "jkl012"
        },
        rolesUI = "mno345"
    }
}
```

---

### Repair Session Finalize (Admin → Clients)

```lua
{
    type = "REPAIR_SESSION_FINALIZE",
    sessionToken = "REPAIR:1234567890.123:a1b2c3d4",
    
    -- Summary stats
    totalClientsRepaired = 8,
    totalPacketsSent = 24,
    duration = 12.5,  -- seconds
    
    -- Resume normal operations
    nextChecksumBroadcast = GetTime() + 30
}
```

---

## Implementation Phases

### Phase 1: New Checksum Functions (SyncChecksum.lua)

**Objectives:**
- Implement 4-layer checksum hierarchy
- Add per-encounter, per-role granular checksums
- Add assignment-only checksums (apRoleChecksum, apEncounterChecksum)

**New Functions:**
```lua
-- Layer 1: Structure
OGRH.SyncChecksum.ComputeRaidStructureChecksum(raidName)

-- Layer 2: Encounters (returns array)
OGRH.SyncChecksum.ComputeEncountersChecksums(raidName)

-- Layer 3: Roles (returns 2D array [enc][role])
OGRH.SyncChecksum.ComputeRolesChecksums(raidName)

-- Layer 4: Assignments (returns 2D array [enc][role])
OGRH.SyncChecksum.ComputeApRoleChecksums(raidName)
OGRH.SyncChecksum.ComputeApEncounterChecksums(raidName)  -- Aggregate
```

**Testing:**
- Unit tests for each checksum level
- Verify exclusion of expected data (assignments from structure, etc.)
- Verify consistency (same data = same checksum)
- Verify sensitivity (change detection)

---

### Phase 2: Repair Session Manager (SyncSession.lua - NEW MODULE)

**Objectives:**
- Session lifecycle management (create, cancel, finalize)
- Token generation and validation
- State transitions (Admin + Client)
- UI/SVM locking mechanisms
- Repair mode flag and coordination
- Post-repair change queue processing
- Player join handling during active repairs
- Version checking and compatibility warnings

**New Module:**
```lua
OGRH.SyncSession = {
    State = {
        currentSession = nil,        -- Active session object
        adminState = "IDLE",         -- Admin state machine
        clientState = "SYNCED",      -- Client state machine
        repairBuffer = {},           -- Request buffer
        repairModeActive = false,    -- NEW: Global repair mode flag
        postRepairQueue = {},        -- NEW: Queued changes during repair
        selectedEncounterIdx = nil,  -- NEW: Admin's active encounter (for priority)
        versionWarnings = {          -- NEW: Version check tracking
            warnedThisRaid = false,
            highestVersion = nil     -- Highest version seen in raid (table with major/minor/patch/str)
        },
        lastRaidSize = 0,            -- NEW: Track raid size for reset detection
        clientSyncStatus = {},       -- NEW: Track all client sync states
        lockState = {
            uiLocked = false,
            svmLocked = false
        }
    }
}
```

**Key Functions:**
```lua
-- Admin functions
OGRH.SyncSession.InitiateSession(clientRequests)
OGRH.SyncSession.BuildRepairPriority(clientRequests, selectedEncIdx)  -- NEW: Priority builder
OGRH.SyncSession.CancelSession(reason)
OGRH.SyncSession.FinalizeSession()
OGRH.SyncSession.EnterRepairMode()        -- NEW: Suppress other sync systems
OGRH.SyncSession.ExitRepairMode()         -- NEW: Resume normal sync
OGRH.SyncSession.ProcessPostRepairQueue() -- NEW: Broadcast queued changes
OGRH.SyncSession.CheckClientVersion(sender, version)  -- NEW: Version checking (admin-side)
OGRH.SyncSession.OnRaidRosterUpdate()     -- NEW: Reset version warnings on raid form
OGRH.SyncSession.LockUI()
OGRH.SyncSession.UnlockUI()
OGRH.SyncSession.LockSVM()
OGRH.SyncSession.UnlockSVM()

-- Client functions
OGRH.SyncSession.ValidateSessionToken(token)
OGRH.SyncSession.IsSessionActive()
OGRH.SyncSession.IsRepairModeActive()     -- NEW: Check if repairs blocking sync
OGRH.SyncSession.IgnoreSession(token)
OGRH.SyncSession.CheckOwnVersion(highestVersionStr)  -- NEW: Version checking (client-side)

-- Both
OGRH.SyncSession.GetSessionState()
OGRH.SyncSession.UpdateProgress(packetIndex, totalPackets)
OGRH.SyncSession.QueuePostRepairChange(changeData)  -- NEW: Queue during repair
```

-- Both
OGRH.SyncSession.GetSessionState()
OGRH.SyncSession.UpdateProgress(packetIndex, totalPackets)
```

**Testing:**
- Token uniqueness and validation
- State transition correctness
- Lock/unlock behavior
- Session expiration (timeout after 60s inactivity)
- Repair mode flag coordination
- Post-repair queue processing
- Player join handling during repairs
- Multiple simultaneous joiners during repairs
- Repair priority ordering (selected encounter first)
- Skipping unneeded encounters correctly
- All clients apply all packets in session (batched repair validation)
- Version checking: Admin with lower version sees warning
- Version checking: Clients with lower version see warning
- Version checking: Players with highest version do NOT see warning
- Version checking: Warning only shows once per raid per player
- Version checking: Warning resets on raid disband/reform
- Version checking: Highest version tracked correctly as clients join
- Version checking: Highest version included in checksum broadcasts

---

### Phase 3: Repair Packet Construction (SyncRepair.lua - NEW MODULE)

**Objectives:**
- Build layered repair packets (Structure, Roles, Assignments)
- Extract minimal required data for each layer
- Packet size management (chunk if needed)
- Compression for large payloads (if OGAddonMsg supports)

**New Module:**
```lua
OGRH.SyncRepair = {
    -- Packet builders
    BuildStructurePacket = function(raidName, sessionToken),
    BuildRolesPacket = function(raidName, encounterIdx, roleIdx, sessionToken),
    BuildAssignmentsPacket = function(raidName, encounterIdx, roleIdx, sessionToken),
    BuildRolesUIPacket = function(sessionToken),
    
    -- Packet appliers
    ApplyStructurePacket = function(packet),
    ApplyRolesPacket = function(packet),
    ApplyAssignmentsPacket = function(packet),
    ApplyRolesUIPacket = function(packet),
    
    -- Validation
    ValidatePacketIntegrity = function(packet),
    ValidatePacketChecksum = function(packet, expectedChecksum)
}
```

**Packet Size Management:**
- **Target:** Stay under WoW 1.12 addon message limit (~255 bytes)
- **OGAddonMsg handles serialization** but we must chunk large structures
- **Chunking strategy for role data:**
  - If full role exceeds limit: Split role structure from assignments
  - Structure packet: Role metadata only
  - Assignment packets: Batches of 5-10 player assignments each
  - Each chunk includes: `{packetIndex, totalPackets, chunkOf: "roleX"}`
- **Example:** Role with 25 players → 1 structure packet + 3 assignment packets

**Why Addon Must Chunk (Not OGAddonMsg):**
- OGAddonMsg doesn't know our data structure boundaries
- We need semantic chunking (structure vs assignments)
- Allows progressive validation as chunks arrive
- Enables UI progress updates per-component

**Testing:**
- Packet serialization/deserialization
- Size limits enforcement
- Checksum validation after apply
- Error handling for corrupted packets

---

### Phase 4: Repair UI Components (SyncRepairUI.lua - NEW MODULE)

**Objectives:**
- Admin repair panel (docked frame)
- Client repair panel (docked frame)
- Countdown panel (after cancel)
- Progress tracking and ETA calculation
- Admin button tooltip with sync status
- Client sync status tracking

**New Module:**
```lua
OGRH.SyncRepairUI = {
    -- Admin UI
    ShowAdminPanel = function(session),
    UpdateAdminProgress = function(packetIndex, totalPackets),
    UpdateClientList = function(clients),
    CloseAdminPanel = function(),
    ShowCountdownPanel = function(seconds),
    
    -- Client UI
    ShowClientPanel = function(session),
    UpdateClientProgress = function(packetIndex, totalPackets, eta),
    UpdateComponentList = function(components),
    CloseClientPanel = function(delay),
    
    -- Waiting Panel (for players joining during repair)
    ShowWaitingPanel = function(sessionInfo),  -- NEW
    UpdateWaitingPanelETA = function(eta),     -- NEW
    CloseWaitingPanel = function(),            -- NEW
    
    -- Admin Button Tooltip
    UpdateAdminButtonTooltip = function(),
    FormatSyncStatusTooltip = function(clientList),
    GetClassColor = function(playerName),
    GetRaidRank = function(playerName),  -- Returns "Admin", "L" (lead), "A" (assist), "" (member)
    
    -- Common
    CalculateETA = function(packetsSent, totalPackets, startTime)
}
```

**UI Specs:**
- Docked frames use `SetPoint("TOP", parentFrame, "BOTTOM", 0, -5)`
- Width: Match parent frame width
- Height: Auto-adjust based on content (min 80px, max 200px)
- Fade in/out animations (0.3s)
- Progress bar: Smooth animation (not jumpy)
- **Auxiliary Panel Registration (CRITICAL):**
  - Register with `OGRH.RegisterAuxiliaryPanel(frame, priority)` on `OnShow`
  - Unregister with `OGRH.UnregisterAuxiliaryPanel(frame)` on `OnHide`
  - Priority determines stacking order (lower = closer to main UI)
  - Suggested priorities:
    - Admin Repair Panel: `20` (below recruiting at 15, invite mode at 16)
    - Client Repair Panel: `20`
    - Waiting Panel: `20`
    - Countdown Panel: `20`
  - Registration system handles collision detection and automatic repositioning

**Admin Button Tooltip Enhancement:**

**Layout:**
```
Select Raid Admin
Current Raid Admin: PlayerName

Left-click: Open admin poll interface
Right-click: Take over as raid admin

═══════════════════════════════════
Addon Users (8):
  Tankadin v2.1.4 [Admin] [✓ Synced]
  Healbot v2.1.4 [L] [✓ Synced]
  Rogueone v2.1.3 [A] [⚠ Out of Sync]
  Mageyboy v2.1.4 [⏳ Repairing...]
  Warriorgal v2.1.4 [✓ Synced]
  Hunterpet v2.0.1 [✗ Offline]
  Priestess v2.1.4 [✓ Synced]
  Warlockz v2.1.4 [⏳ Repairing...]
```

**Sync Status Icons:**
- `[✓ Synced]` - Green - All checksums match
- `[⚠ Out of Sync]` - Yellow - Checksums mismatch, repair not started
- `[⏳ Repairing...]` - Orange - Active repair session in progress
- `[✗ Offline]` - Gray - Player not in raid or addon not responding
- `[? Unknown]` - Gray - No validation response received yet

**Implementation:**
```lua
function OGRH.SyncRepairUI.FormatSyncStatusTooltip()
    local lines = {}
    
    -- Header
    table.insert(lines, "Select Raid Admin")
    local adminName = OGRH.GetRaidAdmin()
    table.insert(lines, "Current Raid Admin: " .. (adminName or "None"))
    table.insert(lines, "")
    table.insert(lines, "Left-click: Open admin poll interface")
    table.insert(lines, "Right-click: Take over as raid admin")
    table.insert(lines, "")
    table.insert(lines, "═══════════════════════════════════")
    
    -- Get addon users with sync status
    local addonUsers = OGRH.SyncSession.GetAddonUsers()  -- Returns sorted list
    table.insert(lines, string.format("Addon Users (%d):", #addonUsers))
    
    for _, user in ipairs(addonUsers) do
        -- Get class color
        local classColor = OGRH.SyncRepairUI.GetClassColor(user.name)
        
        -- Format: Name vVersion [Rank] [Status]
        local rankStr = ""
        if user.isAdmin then
            rankStr = " [Admin]"
        elseif user.isRaidLeader then
            rankStr = " [L]"
        elseif user.isAssistant then
            rankStr = " [A]"
        end
        
        -- Sync status
        local statusStr, statusColor = OGRH.SyncSession.GetSyncStatusDisplay(user.name)
        
        -- Build line with color codes
        local line = string.format("  %s%s|r v%s%s %s",
            classColor,
            user.name,
            user.version or "?.?.?",
            rankStr,
            statusStr
        )
        
        table.insert(lines, line)
    end
    
    return lines
end

-- Sync status tracking (Admin-side)
OGRH.SyncSession.State.clientSyncStatus = {
    -- Example:
    -- ["PlayerName"] = {
    --     lastValidation = GetTime(),
    --     synced = true,  -- All checksums match
    --     version = "2.1.4",
    --     isRepairing = false,
    --     failedComponents = {}  -- ["structure", "enc1", etc]
    -- }
}

function OGRH.SyncSession.OnValidationResponse(sender, data)
    -- Store validation result
    OGRH.SyncSession.State.clientSyncStatus[sender] = {
        lastValidation = GetTime(),
        synced = data.validationResult.allMatch,  -- Computed from validationResult
        version = data.addonVersion,
        isRepairing = OGRH.SyncSession.IsClientInActiveSession(sender),
        failedComponents = ExtractFailedComponents(data.validationResult)
    }
    
    -- Update tooltip
    OGRH.SyncRepairUI.UpdateAdminButtonTooltip()
end

function OGRH.SyncSession.GetSyncStatusDisplay(playerName)
    local status = OGRH.SyncSession.State.clientSyncStatus[playerName]
    
    if not status then
        return "|cff888888[? Unknown]|r", "gray"
    end
    
    -- Check if offline
    if not UnitInRaid(playerName) then
        return "|cff888888[✗ Offline]|r", "gray"
    end
    
    -- Check if repairing
    if status.isRepairing then
        return "|cffff9900[⏳ Repairing...]|r", "orange"
    end
    
    -- Check if synced
    if status.synced then
        return "|cff00ff00[✓ Synced]|r", "green"
    end
    
    -- Out of sync
    return "|cffffff00[⚠ Out of Sync]|r", "yellow"
end
```

**Tooltip Update Triggers:**
- Client validation response received
- Player joins/leaves raid
- Repair session starts/ends
- Admin button mouseover (refresh)

**Panel Registration Example:**
```lua
-- Example: Admin Repair Panel registration
function OGRH.SyncRepairUI.ShowAdminPanel(session)
    local panel = OGRH_AdminRepairPanel
    if not panel then
        panel = CreateFrame("Frame", "OGRH_AdminRepairPanel", UIParent)
        -- ... panel setup code
        
        -- Register with auxiliary panel system
        panel:SetScript("OnShow", function()
            if OGRH.RegisterAuxiliaryPanel then
                OGRH.RegisterAuxiliaryPanel(this, 20)  -- Priority 20
            end
        end)
        
        panel:SetScript("OnHide", function()
            if OGRH.UnregisterAuxiliaryPanel then
                OGRH.UnregisterAuxiliaryPanel(this)
            end
        end)
        
        OGRH_AdminRepairPanel = panel
    end
    
    panel:Show()  -- Triggers OnShow -> registration
end
```

**Testing:**
- UI rendering on different resolutions
- Docking behavior when parent moves/resizes
- Auxiliary panel registration (verify stacking with invite mode/recruiting panels)
- Multiple repair panels don't conflict
- Panel priority ordering correct
- Tooltip line wrapping with long player names
- Class color accuracy
- Sync status updates in real-time
- Tooltip performance with 25+ addon users
- Progress bar smoothness
- Auto-close timing

---

### Phase 5: Integration with SyncIntegrity.lua

**Objectives:**
- Replace current repair logic with session-based system
- Pause checksum broadcasts during repairs
- Resume broadcasts after session finalization
- Integrate with existing MessageRouter

**Changes to SyncIntegrity.lua:**
```lua
-- NEW: Checksum broadcast respects session state
function OGRH.SyncIntegrity.BroadcastChecksums()
    -- Check if repair session active
    if OGRH.SyncSession.IsSessionActive() then
        return  -- Suppress broadcasts during repair
    end
    
    -- Check if in cooldown after cancel
    if OGRH.SyncSession.IsInCooldown() then
        return  -- Suppress broadcasts during cooldown
    end
    
    -- ... existing broadcast logic with NEW hierarchical checksums
end

-- MODIFIED: Repair request triggers session instead of immediate repair
function OGRH.SyncIntegrity.OnRepairRequest(sender, data)
    -- Add to buffer
    OGRH.SyncSession.BufferRepairRequest(sender, data)
    
    -- Buffer timer expires → InitiateSession
end

-- NEW: Session-aware validation
function OGRH.SyncIntegrity.OnChecksumBroadcast(sender, checksums)
    -- Ignore checksums if repair session active
    if OGRH.SyncSession.IsSessionActive() then
        return
    end
    
    -- ... existing validation with NEW hierarchical checksums
end
```

**Testing:**
- Checksum suppression during repairs
- Broadcast resumption after finalization
- Buffer expiration triggers session correctly
- No broadcast storms after cancel

---

### Phase 6: Message Types and Handlers (MessageRouter.lua)

**Objectives:**
- Register new message types for repair system
- Add handlers for session lifecycle messages
- Prioritize repair packets (HIGH priority in OGAddonMsg)

**New Message Types:**
```lua
OGRH.MessageTypes = {
    -- ... existing types
    
    -- Session management
    SYNC_REPAIR_REQUEST = "OGRH_SYNC_REPAIR_REQUEST",
    SYNC_VALIDATION_RESPONSE = "OGRH_SYNC_VALIDATION_RESPONSE",  -- NEW: Client validation response
    SYNC_REPAIR_SESSION_INIT = "OGRH_SYNC_REPAIR_SESSION_INIT",
    SYNC_REPAIR_SESSION_CANCEL = "OGRH_SYNC_REPAIR_SESSION_CANCEL",
    SYNC_REPAIR_SESSION_FINALIZE = "OGRH_SYNC_REPAIR_SESSION_FINALIZE",
    
    -- Repair packets
    SYNC_REPAIR_STRUCTURE = "OGRH_SYNC_REPAIR_STRUCTURE",
    SYNC_REPAIR_ROLES = "OGRH_SYNC_REPAIR_ROLES",
    SYNC_REPAIR_ASSIGNMENTS = "OGRH_SYNC_REPAIR_ASSIGNMENTS",
    SYNC_REPAIR_ROLESUI = "OGRH_SYNC_REPAIR_ROLESUI",
    
    -- Confirmation
    SYNC_REPAIR_COMPLETE = "OGRH_SYNC_REPAIR_COMPLETE"
}
```

**Handlers:**
```lua
-- Admin handlers
OGRH.MessageRouter.RegisterHandler("OGRH_SYNC_VALIDATION_RESPONSE", 
    function(sender, data) 
        OGRH.SyncSession.OnValidationResponse(sender, data)
    end)

OGRH.MessageRouter.RegisterHandler("OGRH_SYNC_REPAIR_REQUEST", 
    function(sender, data) 
        OGRH.SyncSession.BufferRepairRequest(sender, data)
    end)

OGRH.MessageRouter.RegisterHandler("OGRH_SYNC_REPAIR_COMPLETE",
    function(sender, data)
        OGRH.SyncSession.OnClientComplete(sender, data)
    end)

-- Client handlers
OGRH.MessageRouter.RegisterHandler("OGRH_SYNC_REPAIR_SESSION_INIT",
    function(sender, data)
        OGRH.SyncSession.OnSessionInit(sender, data)
    end)

OGRH.MessageRouter.RegisterHandler("OGRH_SYNC_REPAIR_STRUCTURE",
    function(sender, data)
        OGRH.SyncRepair.ApplyStructurePacket(data)
    end)

-- ... more handlers
```

**Priority:**
- Session management: `URGENT` (OGAddonMsg priority)
- Structure repairs: `HIGH`
- Role repairs: `HIGH`
- Assignment repairs: `NORMAL`
- Confirmations: `NORMAL`

**Testing:**
- Message delivery order (session init before repairs)
- Priority enforcement
- Handler error isolation (one handler failure doesn't break others)
- Targeted message delivery (client-specific repairs)

---

### Phase 7: Testing and Optimization

**Load Testing:**
- Simulate 5, 10, 15, 20, 25, 30 clients joining simultaneously
- Measure:
  - Repair session duration
  - Total packets sent
  - Network bandwidth usage
  - Memory usage
  - UI responsiveness

**Stress Testing:**
- Rapid join/leave cycles
- Admin cancel during repair
- Client disconnect during repair
- Multiple concurrent repair requests
- Corrupted packet handling
- Version mismatch scenarios (older admin, newer clients)
- Version warning triggers correctly

**Performance Targets:**
- 25 clients: Repair complete in < 15 seconds (typical case)
- Adaptive send rate: 1-20 packets/second based on queue depth
- Memory overhead: < 5 MB for session state
- UI lag: < 50ms frame time during repairs
- OGAddonMsg queue depth: Stay below 10 packets queued

**Functional Testing:**
- Version warning shows once per raid for ANY player with lower version (admin or client)
- Version warning shows highest version found, not list of players
- Version warning does NOT show to players with highest version
- Version warning resets on raid disband
- Version warning resets on new raid formation
- Version comparison works correctly (2.1.4 < 2.1.5 < 2.2.0 < 3.0.0)
- Highest version tracking updates as new clients join
- Clients receive highest version in checksum broadcasts
- Both admin and clients warn themselves independently

**Optimization Opportunities:**
- **Packet Batching:** Combine multiple small packets into one (if under size limit)
- **Delta Sync:** Send only changed data (future enhancement)
- **Compression:** Use LibCompress for large payloads (if OGAddonMsg supports)
- **Adaptive Pacing:** Monitor OGAddonMsg queue depth and adjust send rate dynamically
- **Checksum Caching:** Don't recompute unchanged checksums (dirty tracking)

---

## Edge Cases and Error Handling

### Admin Disconnects During Repair

**Scenario:** Admin starts repair session, then disconnects

**Behavior:**
1. Clients detect admin offline (RAID_ROSTER_UPDATE)
2. Clients cancel local session state
3. Clients close repair panel with message: "Admin disconnected - repair canceled"
4. New admin (if elected) starts fresh checksums after 10s grace period

**Implementation:**
```lua
-- Client-side
function OnRaidRosterUpdate()
    local session = OGRH.SyncSession.State.currentSession
    if session and session.adminName then
        if not UnitInRaid(session.adminName) then
            OGRH.SyncSession.CancelSession("Admin disconnected")
            OGRH.SyncRepairUI.ShowMessage("Repair canceled - Admin offline")
        end
    end
end
```

---

### Client Disconnects During Repair

**Scenario:** Client receiving repairs disconnects mid-session

**Behavior:**
1. Admin detects client offline (not required - admin just completes repair)
2. Admin continues repair for remaining clients
3. If client reconnects, they'll fail next checksum validation and request new repair

**No special handling required** - next validation cycle handles it.

---

### Player Joins During Active Repair

**Scenario:** New player joins raid while repair session is in progress

**Behavior:**

1. **New Player Handshake:**
   - New player's addon broadcasts admin query: `OGRH_ADMIN_QUERY`
   - Admin detects active repair session and responds with special message

2. **Admin Response:**
```lua
{
    type = "ADMIN_QUERY_RESPONSE",
    adminName = UnitName("player"),
    addonVersion = "2.1.4",
    repairInProgress = true,  -- NEW FLAG
    repairSessionToken = "REPAIR:1234567890.123:a1b2c3d4",
    estimatedCompletion = 8.5  -- seconds (estimated)
}
```

3. **New Player UI:**
   - Show docked panel: "Waiting for sync..." with ETA
   - Suppress normal checksum requests
   - Display message: "Repair in progress - waiting for completion"

**Waiting Panel Layout:**
```
╔═══════════════════════════════════════════════════════════╗
║  ⏳ Sync In Progress                                      ║
╠═══════════════════════════════════════════════════════════╣
║  A data repair is currently active.                      ║
║  Your data will be synced once the repair completes.     ║
║                                                            ║
║  Estimated wait: 6 seconds                                ║
╚═══════════════════════════════════════════════════════════╝
```

4. **Repair Completion Flow:**
   - Admin completes current repair session
   - Admin waits 2 seconds (post-repair grace period)
   - Admin broadcasts checksums to ALL clients (including new joiners)
   - All clients validate their local data
   - Mismatches trigger new repair request (buffered as normal)
   - New repair cycle may start if needed

5. **New Joiner in Buffer:**
   - New joiner validation responses added to repair buffer
   - Treated same as other clients - no special priority
   - May be included in next repair session if data mismatches

**Implementation:**
```lua
-- Admin: Handle admin query during active repair
function OGRH.SyncIntegrity.OnAdminQuery(sender, data)
    local activeSession = OGRH.SyncSession.State.currentSession
    
    if activeSession then
        -- Repair in progress - send special response
        local remainingPackets = activeSession.totalPackets - activeSession.sentPackets
        local avgPacketTime = 0.2  -- seconds (estimated from send rate)
        local eta = remainingPackets * avgPacketTime
        
        OGRH.MessageRouter.SendTo(sender, "OGRH_ADMIN_QUERY_RESPONSE", {
            adminName = UnitName("player"),
            addonVersion = OGRH.VERSION,
            repairInProgress = true,
            repairSessionToken = activeSession.token,
            estimatedCompletion = eta
        })
        
        -- Track new joiner (will get checksums after repair completes)
        activeSession.pendingJoiners = activeSession.pendingJoiners or {}
        table.insert(activeSession.pendingJoiners, sender)
        
        return  -- Don't send normal response
    end
    
    -- Normal handshake (no repair active)
    -- ... existing logic
end

-- Client: Handle admin response with repair in progress
function OGRH.SyncIntegrity.OnAdminQueryResponse(sender, data)
    if data.repairInProgress then
        -- Show waiting panel
        OGRH.SyncRepairUI.ShowWaitingPanel({
            adminName = sender,
            sessionToken = data.repairSessionToken,
            eta = data.estimatedCompletion
        })
        
        -- Set state to waiting
        OGRH.SyncSession.State.clientState = "WAITING_FOR_REPAIR"
        
        return  -- Don't proceed with normal handshake
    end
    
    -- Normal handshake processing
    -- ... existing logic
end

-- Admin: Post-repair checksum broadcast
function OGRH.SyncSession.FinalizeSession()
    local session = OGRH.SyncSession.State.currentSession
    
    -- Wait for all confirmations (existing logic)
    -- ...
    
    -- Close admin panel
    OGRH.SyncRepairUI.CloseAdminPanel()
    
    -- Unlock UI/SVM
    OGRH.SyncSession.UnlockUI()
    OGRH.SyncSession.UnlockSVM()
    
    -- Schedule post-repair checksum broadcast (2-second grace period)
    OGRH.ScheduleTimer(function()
        if OGRH.SyncIntegrity.State.debug then
            OGRH.Msg("|cff00ccff[RH-SyncIntegrity]|r Post-repair checksum broadcast")
        end
        
        -- Broadcast checksums to ALL clients (including joiners)
        OGRH.SyncIntegrity.BroadcastChecksums()
        
        -- Clear pending joiners list
        if session.pendingJoiners then
            session.pendingJoiners = {}
        end
    end, 2.0)
    
    -- Clear session
    OGRH.SyncSession.State.currentSession = nil
    OGRH.SyncSession.State.adminState = "IDLE"
    
    -- Resume normal operations
    OGRH.SyncIntegrity.State.enabled = true
end

-- Client: Close waiting panel when repair completes
function OGRH.SyncSession.OnSessionFinalize(sender, data)
    -- If in waiting state, close waiting panel
    if OGRH.SyncSession.State.clientState == "WAITING_FOR_REPAIR" then
        OGRH.SyncRepairUI.CloseWaitingPanel()
        OGRH.SyncSession.State.clientState = "SYNCED"
    end
    
    -- ... existing finalize logic
end
```

**Edge Case: Multiple Joiners During Repair**
- All joiners get same "repair in progress" response
- All tracked in `pendingJoiners` array
- All receive post-repair checksum broadcast
- All validate and may trigger new repair if needed

---

### Packet Loss or Corruption

**Scenario:** Client misses packet #5 of 24

**Behavior:**
1. Client receives packet #6 (packetIndex mismatch detected)
2. Client sends REPAIR_PACKET_MISSING message to admin: `{sessionToken, missingPackets: [5]}`
3. Admin resends missing packets (HIGH priority)
4. Client applies packets in order (buffers out-of-order packets)

**Implementation:**
```lua
-- Client-side packet receiver
function OnRepairPacket(sender, packet)
    local session = OGRH.SyncSession.State.currentSession
    
    -- Validate session token
    if not session or packet.sessionToken ~= session.token then
        return  -- Ignore packet from different/expired session
    end
    
    -- Check for missing packets
    local expected = session.nextExpectedPacket or 1
    if packet.packetIndex > expected then
        -- Missing packets detected
        local missing = {}
        for i = expected, packet.packetIndex - 1 do
            table.insert(missing, i)
        end
        
        -- Request retransmit
        OGRH.MessageRouter.SendTo(sender, "OGRH_SYNC_REPAIR_RETRANSMIT", {
            sessionToken = session.token,
            missingPackets = missing
        })
        
        -- Buffer this packet
        session.packetBuffer[packet.packetIndex] = packet
        return
    end
    
    -- Apply packet
    ApplyPacketByType(packet)
    session.nextExpectedPacket = packet.packetIndex + 1
    
    -- Check buffer for next packet
    while session.packetBuffer[session.nextExpectedPacket] do
        local bufferedPacket = session.packetBuffer[session.nextExpectedPacket]
        ApplyPacketByType(bufferedPacket)
        session.packetBuffer[session.nextExpectedPacket] = nil
        session.nextExpectedPacket = session.nextExpectedPacket + 1
    end
end
```

---

### Repair Session Timeout

**Scenario:** Repair session starts but never completes (hung state)

**Behavior:**
1. Admin/Client tracks session duration
2. If no packets received for 60 seconds → timeout
3. Admin: Cancel session automatically, show error message
4. Client: Reset state, close panel, show error message

**Implementation:**
```lua
-- Session timeout watchdog
function OGRH.SyncSession.StartWatchdog()
    local session = OGRH.SyncSession.State.currentSession
    if not session then return end
    
    session.watchdogTimer = OGRH.ScheduleTimer(function()
        local lastActivity = session.lastPacketTime or session.startTime
        local elapsed = GetTime() - lastActivity
        
        if elapsed > 60 then
            -- Timeout
            OGRH.SyncSession.CancelSession("Session timeout")
            OGRH.Msg("|cffff0000[RH-Sync]|r Repair session timed out after 60s inactivity")
        else
            -- Reschedule
            OGRH.SyncSession.StartWatchdog()
        end
    end, 10, false)  -- Check every 10s
end
```

---

### UI/SVM Lock Deadlock

**Scenario:** Admin locks UI/SVM but crashes before unlocking

**Behavior:**
1. On addon reload (ADDON_LOADED), check for stale locks
2. If locks exist but no active session → force unlock
3. Log warning message

**Implementation:**
```lua
-- On addon load
function OGRH.SyncSession.Initialize()
    -- Check for stale locks
    local lockState = OGRH.SyncSession.State.lockState
    local activeSession = OGRH.SyncSession.State.currentSession
    
    if (lockState.uiLocked or lockState.svmLocked) and not activeSession then
        -- Stale locks detected
        OGRH.Msg("|cffff9900[RH-Sync]|r Stale UI/SVM locks detected - forcing unlock")
        OGRH.SyncSession.UnlockUI()
        OGRH.SyncSession.UnlockSVM()
    end
end
```

---

## Sync Process Coordination During Repairs

### Pausing Existing Sync Systems

**Problem:** Multiple sync systems operating simultaneously during repairs can cause:
- Broadcast storms (RolesUI sync + repair packets + assignment sync)
- Data conflicts (admin edits during repair)
- Queue saturation (competing for OGAddonMsg bandwidth)

**Solution: Global Repair Mode Flag**

```lua
OGRH.SyncSession.State = {
    -- ... existing state
    repairModeActive = false,  -- NEW: Global flag to suppress other sync systems
    repairModeStartTime = 0
}

-- Enter repair mode
function OGRH.SyncSession.EnterRepairMode()
    OGRH.SyncSession.State.repairModeActive = true
    OGRH.SyncSession.State.repairModeStartTime = GetTime()
    
    if OGRH.SyncIntegrity.State.debug then
        OGRH.Msg("|cffff9900[RH-SyncSession]|r Entering repair mode - suppressing all other sync")
    end
end

-- Exit repair mode
function OGRH.SyncSession.ExitRepairMode()
    OGRH.SyncSession.State.repairModeActive = false
    
    local duration = GetTime() - OGRH.SyncSession.State.repairModeStartTime
    if OGRH.SyncIntegrity.State.debug then
        OGRH.Msg(string.format("|cffff9900[RH-SyncSession]|r Exiting repair mode (duration: %.1fs)", duration))
    end
end

-- Check if repair mode is active (used by all sync systems)
function OGRH.SyncSession.IsRepairModeActive()
    return OGRH.SyncSession.State.repairModeActive
end
```

---

### RolesUI Sync Pause

**Current Implementation (needs modification):**
- RolesUI sync currently broadcasts on every role bucket change
- No awareness of repair mode

**Updated Implementation:**

```lua
-- In RolesUI sync module (wherever it broadcasts)
function OGRH.RolesUI.BroadcastRoleChange(playerName, newRole)
    -- CHECK: Suppress if repair mode active
    if OGRH.SyncSession.IsRepairModeActive() then
        if OGRH.SyncIntegrity.State.debug then
            OGRH.Msg("|cff888888[RH-RolesUI]|r Broadcast suppressed - repair mode active")
        end
        return
    end
    
    -- Normal broadcast logic
    OGRH.MessageRouter.Broadcast("OGRH_ROLES_UPDATE", {
        playerName = playerName,
        role = newRole,
        timestamp = GetTime()
    })
end
```

**Benefits:**
- No RolesUI broadcasts during structure repairs
- Prevents role bucket changes from interfering with repair packets
- After repair completes, normal RolesUI sync resumes

---

### Player Assignment Sync Pause

**Current Implementation (needs evaluation):**
- Assignment sync in EncounterMgmt UI (live assignment changes)
- Likely broadcasts on every drag-and-drop assignment

**Updated Implementation:**

```lua
-- In EncounterMgmt assignment sync
function OGRH.EncounterMgmt.BroadcastAssignment(encounterIdx, roleIdx, playerName, slot)
    -- CHECK: Suppress if repair mode active
    if OGRH.SyncSession.IsRepairModeActive() then
        -- Queue assignment for post-repair sync
        OGRH.SyncSession.QueuePostRepairChange({
            type = "assignment",
            encounterIdx = encounterIdx,
            roleIdx = roleIdx,
            playerName = playerName,
            slot = slot,
            timestamp = GetTime()
        })
        
        if OGRH.SyncIntegrity.State.debug then
            OGRH.Msg("|cff888888[RH-EncounterMgmt]|r Assignment queued - repair mode active")
        end
        return
    end
    
    -- Normal broadcast logic
    OGRH.MessageRouter.Broadcast("OGRH_ASSIGNMENT_UPDATE", {
        encounterIdx = encounterIdx,
        roleIdx = roleIdx,
        playerName = playerName,
        slot = slot,
        timestamp = GetTime()
    })
end

-- Process queued changes after repair completes
function OGRH.SyncSession.ProcessPostRepairQueue()
    local queue = OGRH.SyncSession.State.postRepairQueue or {}
    
    if #queue == 0 then return end
    
    if OGRH.SyncIntegrity.State.debug then
        OGRH.Msg(string.format("|cff00ff00[RH-SyncSession]|r Processing %d queued changes", #queue))
    end
    
    -- Broadcast all queued changes
    for _, change in ipairs(queue) do
        if change.type == "assignment" then
            OGRH.EncounterMgmt.BroadcastAssignment(
                change.encounterIdx,
                change.roleIdx,
                change.playerName,
                change.slot
            )
        elseif change.type == "role" then
            OGRH.RolesUI.BroadcastRoleChange(change.playerName, change.role)
        end
        -- ... other change types
    end
    
    -- Clear queue
    OGRH.SyncSession.State.postRepairQueue = {}
end
```

---

### Checksum Broadcast Pause

**Already Implemented (verify):**
- `BroadcastChecksums()` checks `IsSessionActive()` and returns early
- No checksums broadcast during active repairs

**Ensure coverage:**
```lua
function OGRH.SyncIntegrity.BroadcastChecksums()
    -- Check if repair session active
    if OGRH.SyncSession.IsSessionActive() or OGRH.SyncSession.IsRepairModeActive() then
        return  -- Suppress broadcasts during repair
    end
    
    -- Check if in cooldown after cancel
    if OGRH.SyncSession.IsInCooldown() then
        return  -- Suppress broadcasts during cooldown
    end
    
    -- ... existing broadcast logic
end
```

---

### Broadcast Storm Prevention

**Evaluation Checklist:**

| Sync System | Current State | Action Required |
|-------------|--------------|-----------------|
| **Checksum Broadcasts** | ✅ Paused during repairs | None - already implemented |
| **RolesUI Sync** | ❓ Unknown | Add repair mode check |
| **Assignment Sync** | ❓ Unknown | Add repair mode check + queue |
| **Structure Changes** | ✅ UI locked during repairs | None - already protected |
| **Encounter Selection** | ⚠️ May broadcast | Add repair mode check |
| **Settings Changes** | ⚠️ May broadcast | Add repair mode check |

**Implementation Strategy:**

1. **Phase 1: Add Global Check**
   - Every sync broadcast function checks `IsRepairModeActive()`
   - Suppresses broadcast if true

2. **Phase 2: Queue Non-Critical Changes**
   - RolesUI changes → queue for post-repair
   - Assignment changes → queue for post-repair
   - Settings changes → queue for post-repair

3. **Phase 3: Process Queue After Repair**
   - `FinalizeSession()` calls `ProcessPostRepairQueue()`
   - Broadcasts all queued changes in batch
   - Prevents lost data during repair window

**Example: Unified Broadcast Function**

```lua
-- Wrapper for all sync broadcasts
function OGRH.Sync.SafeBroadcast(messageType, data, options)
    -- Check repair mode
    if OGRH.SyncSession.IsRepairModeActive() then
        -- Queue for post-repair
        OGRH.SyncSession.QueuePostRepairChange({
            messageType = messageType,
            data = data,
            options = options,
            timestamp = GetTime()
        })
        return false  -- Broadcast suppressed
    end
    
    -- Normal broadcast
    OGRH.MessageRouter.Broadcast(messageType, data, options)
    return true  -- Broadcast sent
end

-- All sync systems use SafeBroadcast
function OGRH.RolesUI.BroadcastRoleChange(playerName, newRole)
    OGRH.Sync.SafeBroadcast("OGRH_ROLES_UPDATE", {
        playerName = playerName,
        role = newRole
    })
end

function OGRH.EncounterMgmt.BroadcastAssignment(...)
    OGRH.Sync.SafeBroadcast("OGRH_ASSIGNMENT_UPDATE", {
        -- ... assignment data
    })
end
```

**Benefits:**
- Single point of control for repair mode suppression
- Automatic queueing of changes during repairs
- No lost data (queue processes after repair)
- Prevents broadcast storms across ALL sync systems

---

## Performance Considerations

### Checksum Computation Overhead

**Current Concern:**
- Computing checksums for entire raid on every broadcast (30s) is expensive
- 8 encounters × 6 roles/enc × 4 checksum layers = 192+ checksums per broadcast

**Optimization: Dirty Tracking**

Only recompute checksums for modified components:

```lua
OGRH.SyncChecksum.State = {
    checksumCache = {},
    dirtyFlags = {
        raidStructure = false,
        encounters = {},  -- [idx] = true/false
        roles = {},       -- [encIdx][roleIdx] = true/false
        rolesUI = false
    }
}

-- Mark dirty on SVM changes
function OGRH.SVM.Set(path, value)
    -- ... existing set logic
    
    -- Mark relevant checksums dirty
    OGRH.SyncChecksum.MarkDirty(path)
end

-- Compute only dirty checksums
function OGRH.SyncChecksum.GetAllChecksums()
    local cached = OGRH.SyncChecksum.State.checksumCache
    local dirty = OGRH.SyncChecksum.State.dirtyFlags
    
    -- Raid structure
    if dirty.raidStructure or not cached.structure then
        cached.structure = ComputeRaidStructureChecksum("Active Raid")
        dirty.raidStructure = false
    end
    
    -- Encounters
    for encIdx, isDirty in pairs(dirty.encounters) do
        if isDirty or not cached.encounters[encIdx] then
            cached.encounters[encIdx] = ComputeEncounterChecksum(encIdx)
            dirty.encounters[encIdx] = false
        end
    end
    
    -- ... similar for roles
    
    return cached
end
```

**Expected Improvement:**
- Initial broadcast: Full computation (200ms)
- Subsequent broadcasts (if no changes): Cache lookup (< 1ms)
- Partial changes: Only recompute affected (10-50ms)

---

### Adaptive Pacing with Queue Monitoring

**Current Concern:**
- Sending 24 packets in rapid succession may overwhelm OGAddonMsg queue
- Fixed throttling wastes time when network is clear
- Need to balance speed (when possible) with stability (when busy)

**Optimization: Queue-Aware Adaptive Pacing**

**Why Not Fixed Throttling?**
- OGAddonMsg already handles WoW API rate limits and channel congestion
- Fixed "5 packets/second" is arbitrary and may be too slow when network is clear
- We risk double-throttling: addon throttles, then OGAddonMsg throttles again
- Creates artificial delays when repairs could complete faster

**Better Approach: Monitor OGAddonMsg Queue Depth**

```lua
OGRH.SyncRepair.SendQueue = {
    packets = {},
    sending = false,
    currentPacketIndex = 0,
    
    -- Adaptive pacing thresholds
    queueThresholds = {
        CLEAR = 0,      -- Queue empty - send immediately
        LIGHT = 4,      -- Light load - pace gently
        MODERATE = 8,   -- Moderate load - slow down
        HEAVY = 12      -- Heavy load - significant backoff
    }
}

function OGRH.SyncRepair.QueuePacket(packet, priority)
    table.insert(OGRH.SyncRepair.SendQueue.packets, {
        packet = packet,
        priority = priority or "NORMAL",
        timestamp = GetTime()
    })
    
    -- Start sender if not running
    if not OGRH.SyncRepair.SendQueue.sending then
        OGRH.SyncRepair.StartPacketSender()
    end
end

function OGRH.SyncRepair.StartPacketSender()
    local queue = OGRH.SyncRepair.SendQueue
    queue.sending = true
    queue.currentPacketIndex = 0
    
    OGRH.SyncRepair.ProcessSendQueue()
end

function OGRH.SyncRepair.ProcessSendQueue()
    local queue = OGRH.SyncRepair.SendQueue
    
    if #queue.packets == 0 then
        queue.sending = false
        return
    end
    
    -- Check OGAddonMsg queue depth
    local queueDepth = 0
    if OGAddonMsg and OGAddonMsg.stats and OGAddonMsg.stats.queueDepth then
        queueDepth = OGAddonMsg.stats.queueDepth
    end
    
    -- Adaptive delay based on queue depth
    local delay = 0.05  -- Minimum delay (just for UI updates)
    
    if queueDepth >= queue.queueThresholds.HEAVY then
        -- Heavy load - significant backoff
        delay = 1.0
        if OGRH.SyncIntegrity and OGRH.SyncIntegrity.State.debug then
            OGRH.Msg(string.format("|cffff9900[RH-SyncRepair]|r Queue heavy (%d) - backing off 1.0s", queueDepth))
        end
    elseif queueDepth >= queue.queueThresholds.MODERATE then
        -- Moderate load - slow down
        delay = 0.5
    elseif queueDepth >= queue.queueThresholds.LIGHT then
        -- Light load - gentle pacing
        delay = 0.2
    else
        -- Queue clear - send quickly (minimal delay for UI responsiveness)
        delay = 0.05
    end
    
    -- Send next packet
    local item = table.remove(queue.packets, 1)
    queue.currentPacketIndex = queue.currentPacketIndex + 1
    
    OGRH.MessageRouter.Broadcast(item.packet.type, item.packet, {
        priority = item.priority
    })
    
    -- Update session progress (if applicable)
    if OGRH.SyncSession.State.currentSession then
        OGRH.SyncSession.UpdateProgress(queue.currentPacketIndex, 
            queue.currentPacketIndex + #queue.packets)
    end
    
    -- Schedule next with adaptive delay
    OGRH.ScheduleTimer(OGRH.SyncRepair.ProcessSendQueue, delay, false)
end
```

**Expected Results:**
- **Best case** (clear network): 24 packets @ 20 pps = 1.2 seconds
- **Typical case** (light load): 24 packets @ 5 pps = 4.8 seconds  
- **Worst case** (heavy load): 24 packets @ 1 pps = 24 seconds
- **Prevents queue saturation** - backs off automatically when OGAddonMsg is busy
- **Allows UI updates** - small delays allow progress bar redraws
- **Plays nice with other addons** - doesn't monopolize OGAddonMsg

**Key Principles:**
1. **Addon chunks data** - Must split structures into message-sized pieces (WoW limit)
2. **Addon paces bursts** - Prevents dumping 50 packets instantly
3. **OGAddonMsg controls transmission** - Handles actual channel throughput
4. **Monitor, don't duplicate** - Watch queue depth, don't guess at rates

---

### Memory Usage

**Current Concern:**
- Buffering out-of-order packets could consume significant memory

**Optimization: Bounded Packet Buffer**

```lua
-- Client-side
OGRH.SyncSession.State.currentSession.packetBuffer = {}
OGRH.SyncSession.State.currentSession.packetBufferSize = 0
OGRH.SyncSession.State.currentSession.maxBufferSize = 10  -- Max 10 packets

function BufferPacket(packet)
    local session = OGRH.SyncSession.State.currentSession
    
    -- Check buffer size
    if session.packetBufferSize >= session.maxBufferSize then
        -- Buffer full - request retransmit of expected packet
        OGRH.MessageRouter.SendTo(session.adminName, "OGRH_SYNC_REPAIR_RETRANSMIT", {
            sessionToken = session.token,
            missingPackets = {session.nextExpectedPacket}
        })
        return false  -- Drop this packet
    end
    
    -- Add to buffer
    if not session.packetBuffer[packet.packetIndex] then
        session.packetBuffer[packet.packetIndex] = packet
        session.packetBufferSize = session.packetBufferSize + 1
    end
    
    return true
end
```

**Expected Result:**
- Max 10 buffered packets × ~3 KB/packet = ~30 KB buffer
- Prevents memory exhaustion from packet storms
- Triggers retransmit requests instead of unbounded buffering

---

## Migration Path

### Backward Compatibility

**Goal:** New clients can sync with old admins (degraded), old clients ignore new system

**Strategy:**

1. **Old Message Types Preserved:**
   - Keep existing `OGRH_SYNC_STRUCTURE_*` messages
   - New system uses new message types (`OGRH_SYNC_REPAIR_*`)
   - Old clients ignore new messages (unknown type)

2. **Checksum Broadcast Version Flag:**
   ```lua
   {
       type = "OGRH_SYNC_CHECKSUM_BROADCAST",
       version = 2,  -- NEW: Version 2 includes hierarchical checksums
       checksums = {
           -- v2 format
       }
   }
   ```
   
   - Old clients ignore v2 broadcasts (unknown format)
   - New clients handle v1 broadcasts (fallback to old behavior)

3. **Feature Detection:**
   ```lua
   -- New clients announce capability
   OGRH.SyncSession.AnnounceCapability()  -- Sends version number
   
   -- Admin tracks client versions
   OGRH.SyncSession.State.clientVersions = {
       ["PlayerOne"] = 2,    -- Supports new system
       ["PlayerTwo"] = 1,    -- Old client (fallback)
       ["PlayerThree"] = 2
   }
   
   -- Admin uses new system only if all clients v2+
   function CanUseNewRepairSystem()
       for player, version in pairs(clientVersions) do
           if version < 2 then
               return false
           end
       end
       return true
   end
   ```

4. **Gradual Rollout:**
   - Phase 1 (Week 1): Deploy new system (disabled by default)
   - Phase 2 (Week 2): Enable for testing (opt-in `/ogrh debug syncv2`)
   - Phase 3 (Week 3): Enable by default (opt-out available)
   - Phase 4 (Week 4+): Remove old system code (deprecation)

---

### Database Migration

**No SavedVariables changes required** - all changes are runtime state only.

Existing `OGRH_SV.v2` structure unchanged.

---

## Monitoring and Debugging

### Debug Logging

**Toggle:** `/ogrh debug syncv2` (enable verbose logging)

**Log Categories:**
- `[RH-SyncSession]` - Session lifecycle
- `[RH-SyncRepair]` - Packet send/receive
- `[RH-SyncChecksum]` - Checksum computation
- `[RH-SyncUI]` - UI state changes

**Example Logs:**
```
[RH-SyncSession] Repair request from PlayerOne (structure, enc1, enc3)
[RH-SyncSession] Buffer timeout - initiating repair session (token: REPAIR:1234567890.123:a1b2c3d4)
[RH-SyncSession] Session state: IDLE → REPAIR_INIT
[RH-SyncSession] Locked UI/SVM
[RH-SyncRepair] Sending packet 1/24 (STRUCTURE) to 8 clients
[RH-SyncRepair] Sending packet 2/24 (ROLES enc1 role2) to PlayerOne, PlayerThree
[RH-SyncChecksum] Computing structure checksum (cache miss)
[RH-SyncChecksum] Structure checksum: abc123def456 (computed in 45ms)
[RH-SyncUI] Showing admin repair panel (8 clients)
[RH-SyncSession] Client PlayerOne confirmed repair complete
[RH-SyncSession] All clients complete (8/8) - finalizing session
[RH-SyncSession] Session state: REPAIR_COMPLETE → IDLE
[RH-SyncSession] Unlocked UI/SVM
```

---

### Metrics Collection

**Track:**
- Repair session count (per play session)
- Average session duration
- Average packets per session
- Client count per session
- Timeout/cancel rate
- Checksum cache hit rate

**Display:** `/ogrh stats sync`

```
=== Sync Statistics ===
Repair Sessions: 12 total
  - Average Duration: 8.3 seconds
  - Average Clients: 6.2 clients/session
  - Average Packets: 18.5 packets/session
  - Canceled: 1 (8.3%)
  - Timed Out: 0 (0%)

Checksum Performance:
  - Cache Hit Rate: 87.2%
  - Avg Compute Time: 12ms (cold), 0.5ms (cached)

Network Stats:
  - Total Packets Sent: 222
  - Total Bytes Sent: 684 KB
  - Average Packet Size: 3.1 KB
```

---

### Admin Tools

**Manual Session Control:**
```
/ogrh sync start         → Force start repair session
/ogrh sync cancel        → Cancel active session
/ogrh sync status        → Show current session state
/ogrh sync checksums     → Print all checksums (debug)
/ogrh sync validate      → Validate local data integrity
```

**Force Sync Client:**
```
/ogrh sync request       → Request repair from admin (client)
/ogrh sync repair <name> → Force send repair to specific client (admin)
```

---

## Success Criteria

### Functional Requirements

- ✅ Repair sessions complete successfully with 25+ clients
- ✅ No broadcast storms when raid forms
- ✅ Clients receive only needed data (not entire structure)
- ✅ UI feedback on both admin and client sides
- ✅ Admin can cancel repairs without breaking system
- ✅ Checksums only broadcast when no repairs active

### Performance Requirements

- ✅ 25-client repair completes in < 15 seconds
- ✅ Total packets sent < 1000 during raid formation
- ✅ Memory overhead < 10 MB
- ✅ No UI freezing during repairs (< 50ms frame time)
- ✅ Network traffic drops to normal after repair complete

### Reliability Requirements

- ✅ Handles client disconnects gracefully
- ✅ Handles admin disconnects without deadlock
- ✅ Recovers from packet loss (retransmit)
- ✅ Timeouts prevent hung sessions
- ✅ Backward compatible with old clients (degraded)

---

## Open Questions

1. **OGAddonMsg Compression:**
   - Does OGAddonMsg support compression? (Could reduce packet sizes by 50-70%)
   - If yes, should we compress all repair packets?

2. **Checksum Algorithm:**
   - Current hash is simple string-based (collision risk?)
   - Should we use CRC32 or MD5 for higher reliability?

3. **Packet Chunking Strategy:**
   - What's the optimal packet size? (2 KB? 4 KB? 8 KB?)
   - Should we dynamically adjust based on network conditions?

4. **Priority Tuning:**
   - What priority levels does OGAddonMsg actually support?
   - Do we need sub-priorities (e.g., CRITICAL_HIGH, CRITICAL_LOW)?

5. **UI Placement:**
   - Should repair panels be movable/dockable by user?
   - Should they auto-hide when not relevant?

6. **Session Expiration:**
   - 60-second timeout reasonable?
   - Should it scale with client count (more clients = longer timeout)?

---

## Appendix A: File Structure

```
_Infrastructure/
├── SyncChecksum.lua         (MODIFIED - new checksum functions)
├── SyncIntegrity.lua        (MODIFIED - session integration)
├── SyncRouter.lua           (No changes)
├── SyncGranular.lua         (No changes - future integration)
├── MessageRouter.lua        (MODIFIED - new message handlers)
├── SyncSession.lua          (NEW - session manager)
├── SyncRepair.lua           (NEW - packet builder/applier)
└── SyncRepairUI.lua         (NEW - UI components)
```

---

## Appendix B: Message Flow Diagram

```
┌─────────┐                                                    ┌─────────┐
│ Client1 │                                                    │ Client2 │
└────┬────┘                                                    └────┬────┘
     │                                                              │
     │◄─────────────────────────────────────────────────────────►│
     │         OGRH_SYNC_CHECKSUM_BROADCAST (every 30s)           │
     │         {structure, encounters[], rolesUI}                  │
     │                                                              │
     │  OGRH_SYNC_REPAIR_REQUEST                                   │
     │  {components: [structure, enc1]}                            │
     ├──────────────────────────────────────────┐                  │
     │                                           │                  │
     │                                      ┌────▼─────┐            │
     │                                      │  Admin   │            │
     │                                      │ (Buffer  │            │
     │  OGRH_SYNC_REPAIR_REQUEST            │  2s)     │            │
     │  {components: [enc1, enc3]}          │          │            │
     │◄─────────────────────────────────────┤          │            │
     │                                      │          │            │
     │                                      │ Initiate │            │
     │                                      │ Session  │            │
     │                                      └────┬─────┘            │
     │                                           │                  │
     │  OGRH_SYNC_REPAIR_SESSION_INIT            │                  │
     │  {token, checksums, totalPackets: 12}    │                  │
     │◄──────────────────────────────────────────┤                  │
     │                                           │                  │
     │◄──────────────────────────────────────────┼──────────────────┤
     │                                           │                  │
     │  OGRH_SYNC_REPAIR_STRUCTURE (pkt 1/12)   │                  │
     │◄──────────────────────────────────────────┤                  │
     │◄──────────────────────────────────────────┼──────────────────┤
     │                                           │                  │
     │  OGRH_SYNC_REPAIR_ROLES (pkt 2/12)        │                  │
     │◄──────────────────────────────────────────┤                  │
     │                                           │                  │
     │  (validate roles checksum)                │                  │
     │  (role 2 mismatch - need assignments)     │                  │
     │                                           │                  │
     │  OGRH_SYNC_REPAIR_ASSIGNMENTS (pkt 8/12)  │                  │
     │◄──────────────────────────────────────────┤                  │
     │                                           │                  │
     │  OGRH_SYNC_REPAIR_COMPLETE                │                  │
     │  {newChecksums}                           │                  │
     ├──────────────────────────────────────────►│                  │
     │                                           │                  │
     │                          OGRH_SYNC_REPAIR_COMPLETE           │
     │                          {newChecksums}   │                  │
     │◄──────────────────────────────────────────┼──────────────────┤
     │                                           │                  │
     │  OGRH_SYNC_REPAIR_SESSION_FINALIZE        │                  │
     │◄──────────────────────────────────────────┤                  │
     │◄──────────────────────────────────────────┼──────────────────┤
     │                                           │                  │
     │  (Resume checksums in 30s)                │                  │
     │                                           │                  │
```

---

## Appendix C: State Machine Diagrams

### Admin State Machine

```
                          ┌──────────────┐
                          │     IDLE     │◄─────────────┐
                          └──────┬───────┘              │
                                 │                      │
                    Repair Request Received            │
                                 │                      │
                                 ▼                      │
                          ┌──────────────┐              │
                          │  BUFFERING   │              │
                          └──────┬───────┘              │
                                 │                      │
                        Buffer Expires (2s)            │
                                 │                      │
                                 ▼                      │
                          ┌──────────────┐              │
                          │ REPAIR_INIT  │              │
                          │ (Lock UI/SVM)│              │
                          └──────┬───────┘              │
                                 │                      │
                        Generate Session Token         │
                                 │                      │
                                 ▼                      │
                       ┌──────────────────┐             │
                       │ REPAIR_STRUCTURE │             │
                       │  (Send Layer 1)  │             │
                       └──────┬───────────┘             │
                              │                         │
                     Structure Sent                    │
                              │                         │
                              ▼                         │
                       ┌──────────────────┐             │
                       │  REPAIR_ROLES    │             │
                       │  (Send Layer 2)  │             │
                       └──────┬───────────┘             │
                              │                         │
                        Roles Sent                     │
                              │                         │
                              ▼                         │
                     ┌────────────────────┐             │
                     │ REPAIR_ASSIGNMENTS │             │
                     │  (Send Layer 3)    │             │
                     └──────┬─────────────┘             │
                            │                           │
                   Assignments Sent                    │
                            │                           │
                            ▼                           │
                     ┌──────────────────┐               │
                     │ REPAIR_COMPLETE  │               │
                     │ (Wait Confirms)  │               │
                     └──────┬───────────┘               │
                            │                           │
                   All Clients Confirmed               │
                            │                           │
                            ▼                           │
                     ┌──────────────────┐               │
                     │  FINALIZE        │               │
                     │ (Unlock UI/SVM)  │               │
                     └──────┬───────────┘               │
                            │                           │
                            └───────────────────────────┘

                            
                    [REPAIR_CANCELED] ──────┐
                            ▲               │
                            │               │
                       Manual Cancel       │
                            │               │
                            │               ▼
                      (From Any State)  ┌──────────────────┐
                                        │   COOLDOWN       │
                                        │ (Pause 60s)      │
                                        └──────┬───────────┘
                                               │
                                               │
                                               ▼
                                        ┌──────────────────┐
                                        │     IDLE         │
                                        └──────────────────┘
```

### Client State Machine

```
                          ┌──────────────┐
                          │    SYNCED    │◄─────────────┐
                          └──────┬───────┘              │
                                 │                      │
                    Checksum Mismatch                  │
                                 │                      │
                                 ▼                      │
                          ┌──────────────┐              │
                          │OUT_OF_SYNC   │              │
                          └──────┬───────┘              │
                                 │                      │
                        Send REPAIR_REQUEST            │
                                 │                      │
                                 ▼                      │
                          ┌──────────────┐              │
                          │ REPAIR_      │              │
                          │ REQUESTED    │              │
                          └──────┬───────┘              │
                                 │                      │
                    SESSION_INIT Received              │
                                 │                      │
                                 ▼                      │
                       ┌──────────────────┐             │
                       │ REPAIR_          │             │
                       │ IN_PROGRESS      │             │
                       │ (Show Panel)     │             │
                       └──────┬───────────┘             │
                              │                         │
                       Receive Packets                 │
                              │                         │
                              ▼                         │
                       ┌──────────────────┐             │
                       │ REPAIR_COMPLETE  │             │
                       │ (Send Confirm)   │             │
                       └──────┬───────────┘             │
                              │                         │
                     SESSION_FINALIZE Received         │
                              │                         │
                              └─────────────────────────┘


                    [REPAIR_CANCELED] ──────┐
                            ▲               │
                            │               │
                       SESSION_CANCEL      │
                            │               │
                            │               ▼
                      (From Any State)  ┌──────────────────┐
                                        │   OUT_OF_SYNC    │
                                        │ (Close Panel)    │
                                        └──────────────────┘
```

---

## Appendix D: Testing Checklist

### Unit Tests

- [ ] SyncChecksum: All 4 layers compute correctly
- [ ] SyncChecksum: Dirty tracking marks correctly
- [ ] SyncChecksum: Cache hit/miss logic
- [ ] SyncSession: Token generation uniqueness
- [ ] SyncSession: State transitions valid
- [ ] SyncSession: Lock/unlock mechanisms
- [ ] SyncRepair: Packet builder produces valid structure
- [ ] SyncRepair: Packet applier doesn't corrupt data
- [ ] SyncRepair: Checksum validation after apply

### Integration Tests

- [ ] 5 clients: Repair completes successfully
- [ ] 10 clients: Repair completes successfully
- [ ] 25 clients: Repair completes successfully
- [ ] Client joins during repair: Shows waiting panel, syncs after repair complete
- [ ] Multiple clients join during repair: All queued properly
- [ ] Post-repair validation triggers new repair cycle correctly
- [ ] RolesUI sync suppressed during repair mode
- [ ] Assignment sync suppressed during repair mode
- [ ] Post-repair queue processes all changes correctly
- [ ] Admin cancels repair: Cooldown activates correctly
- [ ] Client disconnects: No deadlock
- [ ] Admin disconnects: Clients reset gracefully
- [ ] Packet loss: Retransmit works
- [ ] Out-of-order packets: Buffer and reorder works
- [ ] Checksum broadcasts paused during repair
- [ ] Checksum broadcasts resume after finalize (2s delay)

### Load Tests

- [ ] 30 clients join simultaneously: System stable
- [ ] Rapid join/leave cycles: No memory leak
- [ ] 100 repairs in 1 hour: No degradation
- [ ] Network saturation test: OGAddonMsg queue doesn't overflow

### UI Tests

- [ ] Admin panel displays correctly
- [ ] Client panel displays correctly
- [ ] Countdown panel shows after cancel
- [ ] Progress bars animate smoothly
- [ ] Panels dock to main UI correctly
- [ ] Panels auto-close when done

---

**End of Document**
