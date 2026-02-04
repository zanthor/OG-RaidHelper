# SR+ Master Loot & Validation System - Design Document

**Version:** 3.0 (Post-RollFor Replacement)  
**Target Release:** 2.1 (Post-v2 Schema Migration)  
**Last Updated:** February 3, 2026  
**Status:** Design Phase

---

## Executive Summary

The SR+ Master Loot & Validation System is a comprehensive replacement for RollFor that provides:

- ✅ **Master Looting Interface** - Replace RollFor with native OGRH loot distribution
- ✅ **SR+ Accumulation Tracking** - Per-character, per-raid, per-item tracking with history
- ✅ **Blockchain-Style Sync** - Distributed ledger via guild/raid chat for multi-officer transparency
- ✅ **Validation & Audit** - Historical records with cryptographic verification
- ✅ **Offline Resilience** - Officers can validate SR+ without central authority
- ✅ **Zero External Dependencies** - No RollFor, RaidHelper.io, or external imports required

**Key Innovation:** Blockchain-style message chain where each SR+ transaction references previous transactions, creating an immutable audit trail that syncs via chat and can be verified by any officer.

---

## Problem Statement

### Current State (SR+ Validation Module)

The existing `SRValidation.lua` has critical flaws:

1. **RollFor Dependency** - Requires RollFor addon and external data import
2. **No Historical Tracking** - Only stores "last validation" per player
3. **Single-Point Authority** - Only raid leader has authoritative data
4. **No Audit Trail** - Can't prove when/why SR+ changed
5. **Manual Validation** - Officers must manually check each player
6. **Offline Sync Gap** - Officers who miss raids have no way to sync
7. **No Loot Distribution** - Still need RollFor for actual master looting

### SR+ Rules to Enforce

**Accumulation:**
- SR+ starts at 0 for new item
- Increases by +10 each week for same item (consecutive raids attended)
- Resets to 0 if switching items
- Resets to 0 if item is won
- Can miss raids without reset (based on "Previous Raid SR+ Sheet")

**Limits:**
- 40-person raids: Max 2 SR+ entries (2 items)
- 20-person raids: Max 1 SR+ entry (1 item)

**Raider Responsibility:**
- Track their "Previous Raid SR+ Sheet" when missing raids
- Reference sheet link to Raid Leads/Master Looters when needed

---

## Solution Architecture

### Core Components

```
SR+ Master Loot System
│
├── Master Loot Interface (UI)
│   ├── Loot Assignment Window
│   ├── SR+ Display & Validation
│   ├── Manual Override Controls
│   └── History Viewer
│
├── SR+ Ledger (Data)
│   ├── Character Ledger (per-character SR+ history)
│   ├── Raid Ledger (per-raid SR+ snapshot)
│   ├── Transaction Log (blockchain-style entries)
│   └── Item Catalog (all SR+ items tracked)
│
├── Blockchain Sync (Communication)
│   ├── Transaction Broadcaster (chat messages)
│   ├── Chain Validator (verify integrity)
│   ├── Conflict Resolver (fork detection)
│   └── Catchup Protocol (sync missing blocks)
│
└── Validation Engine (Logic)
    ├── SR+ Calculator (compute current SR+)
    ├── Rule Enforcer (max SR+, item limits)
    ├── Conflict Detector (duplicate claims)
    └── Audit Verifier (cryptographic proof)
```

---

## Data Schema (v2 Integration)

### 1. Top-Level Structure

```lua
OGRH_SV.v2.srMasterLoot = {
    schemaVersion = 3,  -- v3 = blockchain-enabled
    
    -- Blockchain Ledger
    transactionChain = {},    -- Array of all SR+ transactions (immutable)
    blockHeight = 0,          -- Current block height (auto-increment)
    chainHash = "",           -- Hash of entire chain (for integrity check)
    
    -- Character State (computed from chain)
    characters = {},          -- table: Character SR+ state (indexed by name)
    
    -- Raid Snapshots
    raids = {},               -- Array: Per-raid SR+ snapshots
    
    -- Configuration
    config = {
        enabled = true,
        raidSize = 40,        -- 40 or 20 (affects max SR+ slots)
        maxSRPlus40 = 2,      -- Max SR+ entries for 40-person
        maxSRPlus20 = 1,      -- Max SR+ entries for 20-person
        srPlusIncrement = 10, -- SR+ increase per week
        
        -- Blockchain Settings
        syncChannel = "GUILD",           -- GUILD, OFFICER, or RAID
        broadcastTransactions = true,    -- Auto-broadcast via chat
        acceptRemoteTransactions = true, -- Accept transactions from officers
        verifyChainIntegrity = true,     -- Validate hashes on receive
        pruneAfterDays = 180,            -- Archive old transactions
    },
    
    -- Audit & Administration
    officers = {},            -- table: Authorized officers (can submit transactions)
    conflicts = {},           -- Array: Detected chain conflicts/forks
    auditLog = {},            -- Array: Manual overrides and corrections
}
```

---

### 2. Transaction Chain (Blockchain)

**Design Philosophy:** Each transaction is a signed, timestamped, hash-verified entry that references the previous transaction. This creates an immutable audit trail.

```lua
OGRH_SV.v2.srMasterLoot.transactionChain = {
    [1] = {
        -- Transaction Metadata
        blockHeight = 1,
        transactionId = "TX-20260203-001234-ABCD1234",  -- Unique ID
        timestamp = 1738540800,  -- Unix timestamp
        previousHash = "",       -- Hash of block N-1 (empty for genesis)
        currentHash = "abc123...",  -- Hash of this block
        
        -- Transaction Type
        type = "SR_DECLARE",  -- SR_DECLARE, SR_WIN, SR_RESET, SR_ADJUST, RAID_SNAPSHOT
        
        -- Transaction Data
        character = "Tankadin",
        realm = "Turtle WoW",     -- Support multi-realm guilds
        raidId = "MC-20260203",   -- Raid identifier
        raidSize = 40,
        
        -- SR+ Specific
        itemId = 17076,           -- Thunderfury (example)
        itemName = "Thunderfury, Blessed Blade of the Windseeker",
        previousSRPlus = 0,
        newSRPlus = 10,
        reason = "ATTENDANCE",    -- ATTENDANCE, WIN, RESET, SWITCH, MANUAL
        
        -- Authority & Verification
        submittedBy = "RaidLeader",  -- Officer who submitted transaction
        validatedBy = {},            -- Array: Officers who validated (multi-sig)
        signature = "xyz789...",     -- HMAC signature for verification
        
        -- Context
        notes = "First SR for Thunderfury",
        previousRaidId = nil,        -- Reference to previous raid attended
        missedRaids = 0,             -- Number of raids missed since last attendance
    },
    
    [2] = {
        blockHeight = 2,
        transactionId = "TX-20260210-001245-BCDE2345",
        timestamp = 1739145600,
        previousHash = "abc123...",  -- Links to block 1
        currentHash = "def456...",
        
        type = "SR_DECLARE",
        character = "Tankadin",
        realm = "Turtle WoW",
        raidId = "MC-20260210",
        raidSize = 40,
        
        itemId = 17076,
        itemName = "Thunderfury, Blessed Blade of the Windseeker",
        previousSRPlus = 10,
        newSRPlus = 20,            -- +10 for consecutive attendance
        reason = "ATTENDANCE",
        
        submittedBy = "RaidLeader",
        validatedBy = {"Officer1", "Officer2"},
        signature = "uvw456...",
        
        notes = "Week 2, same item",
        previousRaidId = "MC-20260203",
        missedRaids = 0,
    },
    
    [3] = {
        blockHeight = 3,
        transactionId = "TX-20260217-001256-CDEF3456",
        timestamp = 1739750400,
        previousHash = "def456...",
        currentHash = "ghi789...",
        
        type = "SR_WIN",
        character = "Tankadin",
        realm = "Turtle WoW",
        raidId = "MC-20260217",
        raidSize = 40,
        
        itemId = 17076,
        itemName = "Thunderfury, Blessed Blade of the Windseeker",
        previousSRPlus = 20,
        newSRPlus = 0,             -- Reset to 0 on win
        reason = "WIN",
        
        submittedBy = "MasterLooter",
        validatedBy = {"RaidLeader"},
        signature = "rst123...",
        
        notes = "Item won via master loot",
        lootMethod = "SR_PLUS",    -- SR_PLUS, MANUAL, COUNCIL
        lootedFrom = "Baron Geddon",
    },
    
    -- ... continues chronologically
}
```

---

### 3. Character State (Computed View)

**Design Philosophy:** Character state is **computed from the transaction chain**, not stored directly. This ensures a single source of truth and allows historical reconstruction.

```lua
OGRH_SV.v2.srMasterLoot.characters = {
    ["Tankadin-Turtle WoW"] = {
        -- Metadata
        name = "Tankadin",
        realm = "Turtle WoW",
        class = "PALADIN",
        
        -- Current SR+ State (computed from chain)
        activeSRPlus = {
            [1] = {
                itemId = 17076,
                itemName = "Thunderfury, Blessed Blade of the Windseeker",
                currentSRPlus = 0,         -- Won, reset to 0
                raidsSRed = 3,             -- Attended 3 raids with this SR
                firstSRDate = 1738540800,  -- Feb 3, 2026
                lastUpdateDate = 1739750400,  -- Feb 17, 2026
                lastRaidId = "MC-20260217",
                status = "WON",            -- ACTIVE, WON, SWITCHED
            },
            [2] = {
                itemId = 18422,
                itemName = "Head of Onyxia",
                currentSRPlus = 30,
                raidsSRed = 4,
                firstSRDate = 1738540800,
                lastUpdateDate = 1739750400,
                lastRaidId = "ONY-20260217",
                status = "ACTIVE",
            },
            -- Only 2 entries max for 40-person raids
        },
        
        -- Historical Statistics
        stats = {
            totalRaidsAttended = 12,
            totalItemsWon = 3,
            totalSRResets = 5,
            averageSRPlusAtWin = 18.3,
            highestSRPlus = 50,
        },
        
        -- Chain References
        firstTransaction = "TX-20260203-001234-ABCD1234",
        lastTransaction = "TX-20260217-001256-CDEF3456",
        transactionCount = 15,
        
        -- Validation
        lastValidated = 1739750400,
        validatedBy = "RaidLeader",
        validationStatus = "VALID",  -- VALID, NEEDS_REVIEW, CONFLICT
    },
    
    -- ... other characters
}
```

---

### 4. Raid Snapshots

**Design Philosophy:** Each raid creates a snapshot of all attendees' SR+ state. This provides a "Previous Raid SR+ Sheet" for reference.

```lua
OGRH_SV.v2.srMasterLoot.raids = {
    [1] = {
        -- Raid Metadata
        raidId = "MC-20260203",
        raidName = "Molten Core",
        date = 1738540800,
        raidSize = 40,
        instanceId = "MC",
        
        -- Attendance
        attendees = {
            ["Tankadin-Turtle WoW"] = {
                name = "Tankadin",
                realm = "Turtle WoW",
                class = "PALADIN",
                role = "TANK",
                
                -- SR+ State at Raid Start
                srPlusAtStart = {
                    [1] = {itemId = 17076, srPlus = 0, status = "NEW"},
                    [2] = {itemId = 18422, srPlus = 10, status = "ACTIVE"},
                },
                
                -- SR+ Changes During Raid
                srPlusChanges = {
                    [1] = {
                        itemId = 17076,
                        oldSRPlus = 0,
                        newSRPlus = 10,
                        reason = "ATTENDANCE",
                        transactionId = "TX-20260203-001234-ABCD1234",
                    },
                },
                
                -- Loot Received
                lootReceived = {},
            },
            
            -- ... other attendees
        },
        
        -- Loot Distributed
        lootDistributed = {
            [1] = {
                itemId = 17076,
                itemName = "Thunderfury, Blessed Blade of the Windseeker",
                source = "Baron Geddon",
                winner = "Tankadin-Turtle WoW",
                method = "SR_PLUS",
                srPlusAtWin = 0,
                timestamp = 1738544400,
                transactionId = "TX-20260203-001300-XXXX1111",
            },
            -- ... other loot
        },
        
        -- Blockchain State
        blockHeightAtStart = 45,
        blockHeightAtEnd = 52,
        raidHash = "raid_snapshot_hash_123",  -- Hash of entire snapshot
        
        -- Raid Leadership
        raidLeader = "GuildLeader",
        masterLooter = "MasterLooter",
        officers = {"Officer1", "Officer2"},
    },
    
    -- ... other raids (chronological)
}
```

---

### 5. Configuration & Officers

```lua
-- Officers authorized to submit transactions
OGRH_SV.v2.srMasterLoot.officers = {
    ["RaidLeader-Turtle WoW"] = {
        name = "RaidLeader",
        realm = "Turtle WoW",
        role = "GUILD_MASTER",  -- GUILD_MASTER, OFFICER, RAID_LEADER
        permissions = {
            submitTransactions = true,
            validateTransactions = true,
            manualOverride = true,
            distributeLoot = true,
        },
        publicKey = "key_abc123...",  -- For signature verification
        addedBy = "GuildLeader",
        addedDate = 1738540800,
    },
    -- ... other officers
}

-- Conflict Detection
OGRH_SV.v2.srMasterLoot.conflicts = {
    [1] = {
        conflictId = "CONFLICT-20260203-001",
        type = "FORK_DETECTED",
        timestamp = 1738544400,
        
        -- Conflicting Chains
        chainA = {
            blockHeight = 50,
            hash = "abc123...",
            source = "Officer1",
        },
        chainB = {
            blockHeight = 50,
            hash = "def456...",
            source = "Officer2",
        },
        
        -- Resolution
        resolved = true,
        resolution = "CHAIN_A_ACCEPTED",  -- Manual decision
        resolvedBy = "GuildLeader",
        resolvedDate = 1738550000,
        notes = "Officer2's chain had incorrect timestamp",
    },
}
```

---

## Blockchain Sync Protocol

### Design Philosophy

Traditional sync (SyncRealtime, SyncDelta, SyncGranular) requires a central authority and doesn't work when officers are offline. Blockchain-style sync distributes authority across multiple officers.

**Key Principles:**
1. **Distributed Ledger** - Every officer has a complete copy of the transaction chain
2. **Chat-Based Broadcast** - Transactions broadcast via GUILD/OFFICER chat (no addon channel needed)
3. **Hash Verification** - Each block references previous block's hash
4. **Multi-Signature** - Multiple officers can validate same transaction
5. **Fork Detection** - System detects conflicting chains and flags for resolution
6. **Catchup Protocol** - Officers who miss transactions can request backfill

### Transaction Message Format

```lua
-- Broadcast via ChatThrottleLib to GUILD/OFFICER channel
-- Format: [OGRH:SR] <compressed_transaction_data>

ChatThrottleLib:SendChatMessage(
    "NORMAL",  -- Priority (not ALERT since it's not time-critical)
    "OGRH",
    "[OGRH:SR] " .. compressedData,
    "GUILD"
)
```

**Compressed Transaction Data:**
```lua
-- Example: SR_DECLARE transaction
{
    h = 123,                    -- blockHeight (short keys to save space)
    t = "SR_DECLARE",           -- type
    c = "Tankadin",             -- character
    r = "Turtle WoW",           -- realm
    i = 17076,                  -- itemId
    s = 10,                     -- newSRPlus
    rs = "ATTENDANCE",          -- reason
    ph = "abc123...",           -- previousHash (first 8 chars)
    ts = 1738540800,            -- timestamp
    by = "RaidLeader",          -- submittedBy
    sig = "xyz789...",          -- signature (first 16 chars)
}

-- Serialized and compressed (estimate: ~200 bytes per transaction)
```

### Sync Flow

```
Officer A (Master Looter)          Officer B (Offline)          Officer C (Online)
        |                                   |                            |
        | [Loot Item to Player]             |                            |
        |                                   |                            |
        | Create Transaction                |                            |
        | blockHeight++                     |                            |
        | hash(prev + data)                 |                            |
        | sign(transaction)                 |                            |
        |                                   |                            |
        | Broadcast to GUILD                |                            |
        |-------------------------------------------------------------->|
        |                                   |                            |
        |                                   |                   Receive Transaction
        |                                   |                   Verify Hash Chain
        |                                   |                   Validate Signature
        |                                   |                   Append to Local Chain
        |                                   |                            |
        |<--------------------------------------------------------------|
        |                          Validation Ack                        |
        |                                   |                            |
        
        ... Officer B logs in ...
        
        |                                   | Request Catchup            |
        |                                   |--------------------------->|
        |                                   |                            |
        |                                   | Send Missing Blocks        |
        |                                   |<---------------------------|
        |                                   | (Batch via whisper)        |
        |                                   |                            |
        |                                   | Verify & Rebuild Chain     |
        |                                   | Detect Conflicts (if any)  |
```

### Conflict Resolution

**Fork Detection:**
```lua
-- Officer A and Officer B submit transactions at same blockHeight
-- Creates two competing chains:

Chain A: Block 50 (hash_A) -> Block 51 (hash_A1)
Chain B: Block 50 (hash_B) -> Block 51 (hash_B1)

-- System detects fork when receiving Block 51 with different previousHash
-- Flags conflict and requires manual resolution
```

**Resolution Strategies:**
1. **Timestamp Priority** - Earlier transaction wins (automatic)
2. **Authority Priority** - Guild Master > Officer > Raid Leader (automatic)
3. **Manual Resolution** - Guild Master manually selects correct chain (UI)
4. **Merge Chains** - Both transactions valid, reorder by timestamp (advanced)

---

## Master Loot UI

### Loot Window (Replaces RollFor)

```
┌─────────────────────────────────────────────────────┐
│ Master Loot - Molten Core (Feb 3, 2026)            │
├─────────────────────────────────────────────────────┤
│                                                     │
│ Item: [Thunderfury, Blessed Blade of the Windseeker]│
│ Source: Baron Geddon                               │
│ Quality: Legendary                                 │
│                                                     │
├─────────────────────────────────────────────────────┤
│ SR+ Eligible (Sorted by SR+):                      │
├─────────────────────────────────────────────────────┤
│ ✓ Tankadin          SR+ 30  [Validate] [Award]    │
│ ✓ Holypriest        SR+ 20  [Validate] [Award]    │
│ ✓ Rogue1            SR+ 10  [Validate] [Award]    │
│   Warrior1          SR+  0  [Validate] [Award]    │
│                                                     │
├─────────────────────────────────────────────────────┤
│ Manual Override:                                   │
│ [Select Player ▼] [Award (No SR+)]                │
│                                                     │
├─────────────────────────────────────────────────────┤
│ [Show History] [Disenchant] [Cancel]              │
└─────────────────────────────────────────────────────┘
```

**Features:**
- Auto-detect SR+ from transaction chain
- Sort by SR+ (highest first)
- ✓ = Validated (hash chain verified)
- [Validate] = Manually check SR+ history
- [Award] = Create SR_WIN transaction and assign loot
- Manual Override = Award without SR+ (creates MANUAL transaction)

### SR+ Validation Panel

```
┌─────────────────────────────────────────────────────┐
│ SR+ History - Tankadin                             │
├─────────────────────────────────────────────────────┤
│ Item: Thunderfury, Blessed Blade of the Windseeker │
│ Current SR+: 30                                    │
│                                                     │
├─────────────────────────────────────────────────────┤
│ Transaction History:                               │
├─────────────────────────────────────────────────────┤
│ Block 120 │ Feb 3, 2026  │ SR+ 0→10  │ ATTENDANCE │
│ Block 125 │ Feb 10, 2026 │ SR+ 10→20 │ ATTENDANCE │
│ Block 130 │ Feb 17, 2026 │ SR+ 20→30 │ ATTENDANCE │
│                                                     │
├─────────────────────────────────────────────────────┤
│ Validation:                                        │
│ ✓ Hash chain verified                             │
│ ✓ No missed raids                                 │
│ ✓ Within SR+ limits (2/2 used)                    │
│ ✓ Signatures valid                                │
│                                                     │
├─────────────────────────────────────────────────────┤
│ [Approve] [Flag for Review] [Manual Adjust]       │
└─────────────────────────────────────────────────────┘
```

---

## API Design

### Core Functions

#### `OGRH.SRMasterLoot.CreateTransaction(transactionData)`

Create and broadcast a new SR+ transaction.

**Parameters:**
```lua
{
    type = "SR_DECLARE",  -- SR_DECLARE, SR_WIN, SR_RESET, SR_ADJUST
    character = "Tankadin",
    realm = "Turtle WoW",
    itemId = 17076,
    previousSRPlus = 20,
    newSRPlus = 30,
    reason = "ATTENDANCE",
    notes = "Week 3 attendance",
}
```

**Returns:** `transactionId` (string) or `nil` on failure

**Example:**
```lua
local txId = OGRH.SRMasterLoot.CreateTransaction({
    type = "SR_WIN",
    character = "Tankadin",
    realm = "Turtle WoW",
    itemId = 17076,
    previousSRPlus = 30,
    newSRPlus = 0,
    reason = "WIN",
    notes = "Won Thunderfury",
})
```

---

#### `OGRH.SRMasterLoot.GetCharacterSRPlus(characterName, realm)`

Get current SR+ state for a character (computed from chain).

**Returns:**
```lua
{
    activeSRPlus = {
        [1] = {itemId = 17076, currentSRPlus = 30, status = "ACTIVE", ...},
        [2] = {itemId = 18422, currentSRPlus = 20, status = "ACTIVE", ...},
    },
    stats = {...},
    validationStatus = "VALID",
}
```

---

#### `OGRH.SRMasterLoot.VerifyChain(startBlock, endBlock)`

Verify hash chain integrity for a range of blocks.

**Returns:** `boolean, errorMessage`

```lua
local valid, err = OGRH.SRMasterLoot.VerifyChain(1, 150)
if not valid then
    OGRH.Msg("|cffff0000[SR-MasterLoot] Chain verification failed: " .. err)
end
```

---

#### `OGRH.SRMasterLoot.RequestCatchup(fromBlock)`

Request missing blocks from other officers (whisper protocol).

**Example:**
```lua
-- Officer logs in and detects missing blocks
local myHeight = OGRH.SVM.GetPath("srMasterLoot.blockHeight")
-- Broadcast request to GUILD/OFFICER channel
OGRH.SRMasterLoot.RequestCatchup(myHeight + 1)
```

---

#### `OGRH.SRMasterLoot.AwardLoot(itemId, winner, srPlus, method)`

Award loot and create SR_WIN transaction.

**Parameters:**
- `itemId` (number) - Item ID
- `winner` (string) - Character name
- `srPlus` (number) - SR+ at time of win
- `method` (string) - "SR_PLUS", "MANUAL", "COUNCIL"

**Example:**
```lua
OGRH.SRMasterLoot.AwardLoot(17076, "Tankadin-Turtle WoW", 30, "SR_PLUS")
```

---

### Integration with SVM

**All writes use SVM with blockchain metadata:**

```lua
-- Append transaction to chain
OGRH.SVM.SetPath(
    "srMasterLoot.transactionChain." .. blockHeight,
    transactionData,
    {
        syncLevel = "MANUAL",  -- Don't use SyncRealtime (blockchain has own sync)
        componentType = "sr_transaction",
        scope = {
            blockHeight = blockHeight,
            transactionType = "SR_DECLARE",
        }
    }
)

-- Update block height
OGRH.SVM.SetPath(
    "srMasterLoot.blockHeight",
    blockHeight,
    {
        syncLevel = "MANUAL",
        componentType = "sr_blockchain",
    }
)
```

**Note:** Blockchain sync is handled by `SRMasterLoot` module directly via ChatThrottleLib, not via SVM's sync system.

---

## Message Routing & Chat Integration

### Chat Message Format

**Module Prefix:** `[RH-SRMasterLoot]`  
**Color Code:** `|cffcc99ff` (Light Purple - Administration category)

```lua
-- Module load
OGRH.Msg("|cffcc99ff[RH-SRMasterLoot]|r Loaded (Block Height: 150)")

-- Transaction broadcast (GUILD chat)
-- Format: [OGRH:SR] <compressed_data>
ChatThrottleLib:SendChatMessage("NORMAL", "OGRH", 
    "[OGRH:SR] h=151,t=WIN,c=Tankadin,i=17076,s=0...", 
    "GUILD")

-- User feedback
OGRH.Msg("|cff00ff00[RH-SRMasterLoot]|r SR+ transaction created (Block 151)")

-- Error
OGRH.Msg("|cffff0000[RH-SRMasterLoot]|r Error: Chain verification failed")

-- Debug
if OGRH.SRMasterLoot.State.debug then
    OGRH.Msg("|cffcc99ff[RH-SRMasterLoot][DEBUG]|r VerifyChain called for blocks 1-150")
end
```

### ChatThrottleLib Integration

```lua
-- Transaction broadcast (GUILD/OFFICER channel)
ChatThrottleLib:SendChatMessage(
    "NORMAL",  -- Priority (not time-critical)
    "OGRH",    -- Prefix
    "[OGRH:SR] " .. OGRH.SRMasterLoot.CompressTransaction(transaction),
    "GUILD",   -- Channel (or "OFFICER")
    nil,       -- Target (nil for broadcast)
    nil        -- Queue name
)

-- Catchup response (whisper)
ChatThrottleLib:SendChatMessage(
    "BULK",    -- Low priority (batch data)
    "OGRH",
    "[OGRH:SR:CATCHUP] " .. OGRH.SRMasterLoot.CompressBlocks(blocks),
    "WHISPER",
    requesterName,
    nil
)
```

### Message Parser (Event Handler)

```lua
-- Register for chat events
function OGRH.SRMasterLoot.OnChatMessage(msg, sender)
    -- Parse [OGRH:SR] messages
    if string.find(msg, "^%[OGRH:SR%]") then
        local compressed = string.sub(msg, 11)  -- Skip "[OGRH:SR] "
        local transaction = OGRH.SRMasterLoot.DecompressTransaction(compressed)
        
        if transaction then
            OGRH.SRMasterLoot.ReceiveTransaction(transaction, sender)
        end
    end
    
    -- Parse catchup responses
    if string.find(msg, "^%[OGRH:SR:CATCHUP%]") then
        local compressed = string.sub(msg, 19)
        local blocks = OGRH.SRMasterLoot.DecompressBlocks(compressed)
        
        if blocks then
            OGRH.SRMasterLoot.ReceiveCatchup(blocks, sender)
        end
    end
end

-- Register event handlers
frame:RegisterEvent("CHAT_MSG_GUILD")
frame:RegisterEvent("CHAT_MSG_OFFICER")
frame:RegisterEvent("CHAT_MSG_WHISPER")
frame:SetScript("OnEvent", function()
    if event == "CHAT_MSG_GUILD" or event == "CHAT_MSG_OFFICER" then
        OGRH.SRMasterLoot.OnChatMessage(arg1, arg2)
    elseif event == "CHAT_MSG_WHISPER" then
        OGRH.SRMasterLoot.OnChatMessage(arg1, arg2)
    end
end)
```

---

## Cryptographic Design

### Hash Function

Use Lua-compatible hash function (no external dependencies):

```lua
-- Simple but effective hash for WoW 1.12 Lua
function OGRH.SRMasterLoot.Hash(data)
    local str = OGRH.SRMasterLoot.Serialize(data)
    local hash = 5381
    
    for i = 1, string.len(str) do
        local byte = string.byte(str, i)
        hash = bit.bxor(bit.lshift(hash, 5) + hash, byte)
    end
    
    return string.format("%08x", hash)
end
```

**Note:** WoW 1.12 has limited `bit` library. May need to implement bit operations in pure Lua.

### Signature Generation

```lua
-- HMAC-style signature using officer's "private key" (really just a guild-shared secret)
function OGRH.SRMasterLoot.Sign(transaction, officerKey)
    local data = OGRH.SRMasterLoot.Serialize(transaction)
    local signature = OGRH.SRMasterLoot.HMAC(data, officerKey)
    return signature
end

-- Verify signature
function OGRH.SRMasterLoot.VerifySignature(transaction, signature, officerKey)
    local expectedSig = OGRH.SRMasterLoot.Sign(transaction, officerKey)
    return signature == expectedSig
end
```

**Note:** This is not true public-key cryptography (not available in Lua 5.0), but provides tamper detection within a trusted guild environment.

---

## File Structure

```
OG-RaidHelper/
├── _Administration/
│   ├── SRMasterLoot.lua          -- Main module (replaces SRValidation.lua)
│   ├── SRBlockchain.lua          -- Blockchain sync protocol
│   ├── SRLootUI.lua              -- Master loot interface
│   ├── SRValidationUI.lua        -- SR+ validation panel
│   ├── SRCrypto.lua              -- Hash/signature functions
│   └── SRMigration.lua           -- Migrate from RollFor (optional)
│
└── Documentation/
    ├── SR+ Master Loot & Validation Design.md  (this file)
    └── SR+ API Reference.md        (generated after implementation)
```

---

## Implementation Phases

### Phase 1: Core Blockchain (2-3 weeks)

**Deliverables:**
- [ ] Transaction chain data structure (v2 schema)
- [ ] Hash function (pure Lua implementation)
- [ ] Transaction creation/append
- [ ] Chain verification
- [ ] Character state computation (from chain)

**Testing:**
- Unit tests for hash function
- Chain integrity tests (detect tampering)
- Character state computation accuracy

---

### Phase 2: Chat Sync Protocol (2 weeks)

**Deliverables:**
- [ ] ChatThrottleLib integration
- [ ] Transaction broadcast (GUILD/OFFICER)
- [ ] Message parser (receive transactions)
- [ ] Catchup protocol (sync missing blocks)
- [ ] Conflict detection

**Testing:**
- Multi-client sync tests (2+ officers online)
- Offline catchup tests (officer logs in after raid)
- Fork detection tests (simulate conflicting transactions)

---

### Phase 3: Master Loot UI (3 weeks)

**Deliverables:**
- [ ] Loot window (item, eligible players, SR+ display)
- [ ] SR+ sorting (highest first)
- [ ] Award loot button (creates SR_WIN transaction)
- [ ] Manual override (no SR+ award)
- [ ] Disenchant option
- [ ] History viewer (per-item SR+ history)

**Testing:**
- Master loot workflow (from loot to award)
- SR+ calculation accuracy
- UI responsiveness (scrollable lists)

---

### Phase 4: Validation & Audit (2 weeks)

**Deliverables:**
- [ ] SR+ validation panel (verify chain, detect issues)
- [ ] Manual adjustment UI (officer override)
- [ ] Conflict resolution UI (choose correct chain)
- [ ] Audit log (manual changes, overrides)
- [ ] Officer management (add/remove authorized officers)

**Testing:**
- Validation accuracy (detect invalid SR+)
- Manual adjustment workflow
- Conflict resolution (fork detection)

---

### Phase 5: Raid Snapshots (1 week)

**Deliverables:**
- [ ] Raid snapshot creation (start of raid)
- [ ] Attendance tracking (who attended)
- [ ] SR+ state snapshot (before/after raid)
- [ ] Loot distribution log (what was awarded)
- [ ] Snapshot viewer UI (historical raids)

**Testing:**
- Snapshot accuracy (SR+ state matches chain)
- Historical reconstruction (rebuild chain from snapshots)

---

### Phase 6: Polish & Documentation (1 week)

**Deliverables:**
- [ ] Slash commands (`/ogrh sr`, `/ogrh loot`)
- [ ] Tooltips (hover over SR+ to see history)
- [ ] Help tooltips (explain SR+ rules)
- [ ] API documentation
- [ ] User guide (for officers)
- [ ] Migration guide (from RollFor)

**Testing:**
- End-to-end testing (full raid workflow)
- Performance testing (100+ transactions)
- Usability testing (officer feedback)

---

## Migration from RollFor (Optional)

### Import RollFor SR+ History

**Goal:** Import existing RollFor SR+ data into blockchain as genesis blocks.

```lua
function OGRH.SRMasterLoot.ImportFromRollFor()
    if not OGRH.ROLLFOR_AVAILABLE then
        OGRH.Msg("|cffff0000[RH-SRMasterLoot]|r RollFor not detected")
        return false
    end
    
    -- Get RollFor data
    local players = OGRH.Invites.GetSoftResPlayers()
    if not players or table.getn(players) == 0 then
        return false
    end
    
    -- Create genesis block for each player's current SR+
    local blockHeight = 0
    for _, playerData in ipairs(players) do
        if playerData.srPlus and playerData.srPlus > 0 then
            blockHeight = blockHeight + 1
            
            local transaction = {
                blockHeight = blockHeight,
                transactionId = "GENESIS-" .. playerData.name,
                timestamp = GetTime(),
                previousHash = blockHeight == 1 and "" or OGRH.SVM.GetPath("srMasterLoot.transactionChain." .. (blockHeight - 1) .. ".currentHash"),
                
                type = "SR_DECLARE",
                character = playerData.name,
                realm = GetRealmName(),
                itemId = playerData.itemId,  -- From RollFor data
                previousSRPlus = 0,
                newSRPlus = playerData.srPlus,
                reason = "IMPORTED",
                
                submittedBy = UnitName("player"),
                validatedBy = {},
                notes = "Imported from RollFor on " .. date("%Y-%m-%d"),
            }
            
            -- Calculate hash
            transaction.currentHash = OGRH.SRMasterLoot.Hash(transaction)
            transaction.signature = OGRH.SRMasterLoot.Sign(transaction, "IMPORT")
            
            -- Append to chain
            OGRH.SVM.SetPath(
                "srMasterLoot.transactionChain." .. blockHeight,
                transaction,
                {syncLevel = "MANUAL", componentType = "sr_transaction"}
            )
        end
    end
    
    OGRH.SVM.SetPath("srMasterLoot.blockHeight", blockHeight, {syncLevel = "MANUAL", componentType = "sr_blockchain"})
    
    OGRH.Msg("|cff00ff00[RH-SRMasterLoot]|r Imported " .. blockHeight .. " transactions from RollFor")
    return true
end
```

---

## Security Considerations

### Threat Model

**Trusted Environment Assumption:**
- Officers are trusted guild members
- No adversarial actors within officer team
- Goal is audit trail and conflict detection, not cryptographic security

**Potential Issues:**
1. **Malicious Officer** - Could submit false transactions
   - **Mitigation:** Multi-signature validation (multiple officers approve)
   - **Mitigation:** Audit log flags manual changes
   - **Mitigation:** Guild Master can review and rollback

2. **Chain Tampering** - Officer modifies local chain
   - **Mitigation:** Hash chain breaks on tampering (detected immediately)
   - **Mitigation:** Multiple officers have copies (Byzantine fault tolerance)

3. **Replay Attack** - Old transaction re-broadcast
   - **Mitigation:** Transaction IDs are unique (timestamp + random)
   - **Mitigation:** Block height prevents reordering

4. **Fork Attack** - Officer creates competing chain
   - **Mitigation:** Fork detection algorithm
   - **Mitigation:** Manual resolution by Guild Master

### Best Practices

1. **Multiple Officers Online** - Requires 2+ officers online during raids for validation
2. **Regular Backups** - Export chain to external file (guild website)
3. **Audit Reviews** - Guild Master reviews audit log weekly
4. **Officer Rotation** - Remove inactive officers from authorized list

---

## Performance Considerations

### Chain Size

**Estimate:**
- 40-person raid, 30 items per raid = 30 loot transactions per raid
- 2 raids per week = 60 transactions per week
- 52 weeks = 3,120 transactions per year
- Average transaction size: ~500 bytes
- **Total: ~1.5 MB per year**

**Mitigation:**
- Prune old transactions after 180 days (configurable)
- Archive pruned transactions to external file
- Compress transaction data (50% reduction)

### Sync Bandwidth

**Estimate:**
- 30 transactions per raid (2 hours) = 15 transactions/hour
- Compressed transaction: ~200 bytes
- **Network usage: ~3 KB/hour** (negligible)

**Mitigation:**
- Batch multiple transactions into single chat message (reduce overhead)
- Use BULK priority for catchup (low priority queue)

### Computation

**Hash Verification:**
- Verify 150 blocks: ~50ms (acceptable on login)
- Incremental verification: ~1ms per new block (real-time)

**Character State Computation:**
- Rebuild state from 150 transactions: ~100ms (acceptable on demand)
- Cache computed state (invalidate on new transaction)

---

## Open Questions

1. **Multi-Realm Support** - Should we support characters from multiple realms in same guild?
   - **Proposed:** Yes, use `"CharacterName-RealmName"` as key

2. **SR+ Decay** - Should SR+ decay after long absences (e.g., 4+ weeks)?
   - **Proposed:** No decay (raiders track via "Previous Raid SR+ Sheet")

3. **SR+ Transfer** - Can players transfer SR+ between alts?
   - **Proposed:** No (SR+ is per-character, not per-player)

4. **Signature Key Distribution** - How do officers get their signing key?
   - **Proposed:** Guild-shared secret (set by Guild Master, distributed via officer chat)

5. **Conflict Resolution Automation** - Can we auto-resolve forks without manual intervention?
   - **Proposed:** Auto-resolve by timestamp (earlier wins), flag for review if >5min difference

6. **Integration with Encounter Planning** - Should SR+ assignments show in EncounterMgmt UI?
   - **Proposed:** Yes, add SR+ column to role assignments (read-only display)

---

## Success Metrics

### Phase 1 Success Criteria

- [ ] 150+ transaction chain loads in <100ms
- [ ] Hash verification detects single-bit tampering
- [ ] Character state computation matches manual calculation
- [ ] Zero data loss after addon reload

### Phase 2 Success Criteria

- [ ] 3+ officers sync transactions in <5 seconds
- [ ] Offline officer catches up in <30 seconds
- [ ] Fork detection triggers on conflicting chains
- [ ] Zero duplicate transactions

### Phase 3 Success Criteria

- [ ] Master loot workflow completes in <30 seconds
- [ ] SR+ sorting matches expected order (highest first)
- [ ] Loot award creates valid SR_WIN transaction
- [ ] UI responsive with 40+ eligible players

### Phase 4 Success Criteria

- [ ] Validation panel loads in <200ms
- [ ] Manual adjustment creates audit log entry
- [ ] Conflict resolution UI clearly shows both chains
- [ ] Officer management persists across sessions

### Final Release Criteria

- [ ] Full raid workflow (invite -> loot -> snapshot) completes successfully
- [ ] 100+ transactions synced across 5+ officers
- [ ] Zero RollFor dependencies
- [ ] Positive officer feedback (usability survey)

---

## Future Enhancements (Post-2.1)

### v2.2 - Advanced Features
- [ ] SR+ Projections (predict SR+ for next raid)
- [ ] SR+ Recommendations (suggest optimal SR choices)
- [ ] Loot Council Integration (hybrid SR+/Council system)
- [ ] Cross-Guild SR+ (support multiple guilds)

### v2.3 - Analytics
- [ ] SR+ Statistics Dashboard (average SR+ at win, etc.)
- [ ] Loot Distribution Heatmap (who won what)
- [ ] Attendance Trends (SR+ accumulation over time)
- [ ] Item Popularity (most SR'd items)

### v2.4 - External Integration
- [ ] Export to Guild Website (JSON API)
- [ ] Import from External SR Systems (CSV)
- [ ] Discord Bot Integration (query SR+ via bot)
- [ ] RaidHelper.io Import (if they add SR+ support)

---

## Appendix A: Sample Workflows

### Workflow 1: New Player First SR

```
1. Player joins raid
2. Player announces SR: "Thunderfury"
3. Officer opens SR Management UI
4. Officer selects player, enters itemId 17076
5. Officer clicks "Create SR+ Entry"
6. System creates SR_DECLARE transaction (SR+ = 0)
7. Transaction broadcasts to GUILD chat
8. Other officers receive and validate transaction
9. Player's SR+ entry appears in Master Loot UI
```

### Workflow 2: Weekly SR+ Accumulation

```
1. Raid starts (same player, same item SR'd as last week)
2. Officer opens Raid Snapshot UI
3. Officer clicks "Start Raid Snapshot"
4. System scans raid roster for attendance
5. For each attendee with active SR+:
   - Create SR_DECLARE transaction (SR+ += 10)
   - Broadcast to GUILD chat
6. All SR+ values updated automatically
7. Raid Snapshot saved (block height recorded)
```

### Workflow 3: Item Drop & Award

```
1. Boss dies, item drops
2. Master Looter sees loot window pop-up
3. UI shows: "Thunderfury dropped"
4. UI lists eligible players sorted by SR+:
   - Tankadin (SR+ 30)
   - Holypriest (SR+ 20)
   - Warrior1 (SR+ 10)
5. ML clicks [Validate] on Tankadin
6. Validation panel shows clean history
7. ML clicks [Award] on Tankadin
8. System creates SR_WIN transaction (SR+ 30 -> 0)
9. Transaction broadcasts to GUILD chat
10. Loot assigned to Tankadin
11. Tankadin's SR+ resets to 0
12. Raid Snapshot updated
```

### Workflow 4: Officer Logs In (Catchup)

```
1. Officer logs in (missed last raid)
2. System detects blockHeight mismatch:
   - Local chain: 145 blocks
   - Latest broadcast: 160 blocks
3. System broadcasts catchup request to GUILD
4. Online officer whispers missing blocks (146-160)
5. System verifies hash chain (all valid)
6. Local chain updated to 160 blocks
7. Character states recomputed
8. Officer now synced
```

### Workflow 5: Conflict Detection & Resolution

```
1. Two officers submit transactions simultaneously
   - Officer A: Block 150 (hash_A)
   - Officer B: Block 150 (hash_B)
2. Officer C receives both transactions
3. System detects fork (same blockHeight, different hashes)
4. Conflict flagged in OGRH.SVM.GetPath("srMasterLoot.conflicts")
5. Officers notified via chat: "SR+ chain fork detected!"
6. Guild Master opens Conflict Resolution UI
7. UI shows both chains side-by-side
8. GM selects correct chain (based on timestamp/context)
9. System broadcasts resolution to GUILD
10. All officers accept resolution and rebuild chain
```

---

## Appendix B: Data Structure Examples

### Complete Transaction Chain (3 blocks)

```lua
OGRH_SV.v2.srMasterLoot.transactionChain = {
    [1] = {
        blockHeight = 1,
        transactionId = "TX-20260203-120534-A1B2C3D4",
        timestamp = 1738584334,
        previousHash = "",
        currentHash = "e3b0c442",
        
        type = "SR_DECLARE",
        character = "Tankadin",
        realm = "Turtle WoW",
        raidId = "MC-20260203",
        raidSize = 40,
        
        itemId = 17076,
        itemName = "Thunderfury, Blessed Blade of the Windseeker",
        previousSRPlus = 0,
        newSRPlus = 10,
        reason = "ATTENDANCE",
        
        submittedBy = "RaidLeader",
        validatedBy = {},
        signature = "a3f5c9d7e2b4",
        
        notes = "First SR for Thunderfury",
        previousRaidId = nil,
        missedRaids = 0,
    },
    
    [2] = {
        blockHeight = 2,
        transactionId = "TX-20260210-121045-B2C3D4E5",
        timestamp = 1739189445,
        previousHash = "e3b0c442",
        currentHash = "98d85c8f",
        
        type = "SR_DECLARE",
        character = "Tankadin",
        realm = "Turtle WoW",
        raidId = "MC-20260210",
        raidSize = 40,
        
        itemId = 17076,
        itemName = "Thunderfury, Blessed Blade of the Windseeker",
        previousSRPlus = 10,
        newSRPlus = 20,
        reason = "ATTENDANCE",
        
        submittedBy = "RaidLeader",
        validatedBy = {"Officer1"},
        signature = "b4e6a8c9f1d3",
        
        notes = "Week 2, consecutive attendance",
        previousRaidId = "MC-20260203",
        missedRaids = 0,
    },
    
    [3] = {
        blockHeight = 3,
        transactionId = "TX-20260217-122156-C3D4E5F6",
        timestamp = 1739794316,
        previousHash = "98d85c8f",
        currentHash = "7f4a3b2c",
        
        type = "SR_WIN",
        character = "Tankadin",
        realm = "Turtle WoW",
        raidId = "MC-20260217",
        raidSize = 40,
        
        itemId = 17076,
        itemName = "Thunderfury, Blessed Blade of the Windseeker",
        previousSRPlus = 20,
        newSRPlus = 0,
        reason = "WIN",
        
        submittedBy = "MasterLooter",
        validatedBy = {"RaidLeader", "Officer1"},
        signature = "c5f7b9d1a3e5",
        
        notes = "Item won via SR+ master loot",
        lootMethod = "SR_PLUS",
        lootedFrom = "Baron Geddon",
    },
}
```

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | February 3, 2026 | Initial design document |

---

## Contributors

- **Design Lead:** AI Agent (GitHub Copilot)
- **Requirements:** User (Guild Leader)
- **Review:** Pending

---

## References

- [V2 Schema Specification](! V2 Schema Specification.md)
- [SVM API Documentation](! SVM-API-Documentation.md)
- [OG-RaidHelper Design Philosophy](! OG-RaidHelper Design Philososphy.md)
- [OG-RaidHelper API](! OG-RaidHelper API.md)

---

**END OF DOCUMENT**
