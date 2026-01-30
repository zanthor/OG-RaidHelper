# V2 Schema Specification

**Version:** 2.0 (Post-Migration)  
**Last Updated:** January 30, 2026  
**Authority:** Based on actual migrated SavedVariables data

---

## Quick Reference

### Schema Location & Version Flag

```lua
OGRH_SV = {
    schemaVersion = "v2",  -- Indicates v2 is active
    v2 = {
        -- All v2 data lives here
    },
    -- v1 data auto-pruned 14 days after v2 qmigration triggered.
}
```

### Top-Level v2 Structure

```lua
OGRH_SV.v2 = {
    -- Sync & Core Settings
    syncLocked = false,                    -- boolean: Prevents sync operations
    pollTime = 5,                          -- number: Seconds between polls
    monitorConsumes = true,                -- boolean: Track consumables
    allowRemoteReadyCheck = true,          -- boolean: Allow remote ready checks
    firstRun = false,                      -- boolean: First-time setup flag
    
    -- Management Subsystems
    autoPromotes = {},                     -- table: Auto-promotion rules
    rosterManagement = {},                 -- table: Ranking/ELO system
    invites = {},                          -- table: RaidHelper.io integration
    srValidation = {},                     -- table: SoftRes validation
    consumesTracking = {},                 -- table: Consumable tracking config
    recruitment = {},                      -- table: Recruitment automation
    
    -- UI State
    ui = {},                               -- table: Main window position/state
    rolesUI = {},                          -- table: Roles window position
    minimap = {},                          -- table: Minimap button position
    
    -- Player Data
    roles = {},                            -- table: Player role assignments (HEALERS, MELEE, TANKS, RANGED)
    
    -- Configuration
    consumes = {},                         -- array: Consumable definitions
    tradeItems = {},                       -- array: Items to trade
    
    -- Main Data Structure (Raids & Encounters)
    encounterMgmt = {},                    -- table: All raid/encounter data
    
    -- Versioning & Permissions
    versioning = {},                       -- table: Version tracking
    permissions = {},                      -- table: Permission system
    
    -- Utilities
    sorting = {speed = 200},               -- table: Sorting animation speed
}
```

---

## Subsystem Structures

### 1. encounterMgmt (Primary Data Structure)

**Design Philosophy:** Numeric indices as stable keys, display names as metadata.

```lua
OGRH_SV.v2.encounterMgmt = {
    schemaVersion = 2,  -- Schema version for encounterMgmt subsystem
    
    raids = {
        [1] = {  -- RAID INDEX (stable numeric key)
            -- Metadata
            id = "mc",                    -- string: Semantic ID (optional, for readability)
            name = "Molten Core",         -- string: Display name (user-editable)
            displayName = "Molten Core",  -- string: Alias for name
            sortOrder = 1,                -- number: UI display order
            
            -- Encounters
            encounters = {
                [1] = {  -- ENCOUNTER INDEX (stable numeric key)
                    -- Metadata
                    id = "lucifron",              -- string: Semantic ID (optional)
                    name = "Lucifron",            -- string: Display name (user-editable)
                    displayName = "Lucifron",     -- string: Alias for name
                    sortOrder = 1,                -- number: UI display order
                    
                    -- Roles Structure
                    roles = {
                        [1] = {  -- ROLE INDEX (stable numeric key)
                            -- Metadata
                            id = "mt",                    -- string: Semantic ID (optional)
                            name = "Main Tank",           -- string: Display name
                            displayName = "Main Tank",    -- string: Alias for name
                            
                            -- Configuration
                            column = 1,                   -- number: UI column (1 or 2)
                            slots = 1,                    -- number: Number of slots
                            fillOrder = 1,                -- number: Auto-fill priority
                            sortOrder = 1,                -- number: Display order in column
                            showRaidIcons = 1,            -- number: Show raid icons (0/1)
                            
                            -- Assignment Data
                            assignments = {
                                [1] = "PlayerName",       -- SLOT INDEX: Assigned player
                                [2] = "PlayerName2",
                                -- ... up to slots count
                            },
                            
                            -- Role Restrictions
                            defaultRoles = {
                                tanks = 1,                -- Only tanks can fill this role
                            },
                            
                            -- Class Priority
                            classPriority = {
                                [1] = {[1] = "Warrior"},  -- Slot 1 prefers Warrior
                                [2] = {[1] = "Druid", [2] = "Paladin"},  -- Slot 2 prefers Druid, fallback Paladin
                            }
                        },
                        [2] = {
                            -- Next role...
                        }
                    },
                    
                    -- Advanced Settings
                    advancedSettings = {
                        consumeTracking = {
                            enabled = true,
                            trackOnPull = true,
                            -- ... other consume tracking settings
                        },
                        -- ... other encounter-specific settings
                    }
                }
            }
        },
        [2] = {
            -- Next raid...
        }
    }
}
```

**Key Improvements over v1:**
- ✅ Numeric indices prevent issues with spaces/special characters
- ✅ Display names can be renamed without breaking references
- ✅ Roles nested within encounters (better organization)
- ✅ Consistent metadata structure (id, name, sortOrder)
- ✅ Explicit column assignment for UI layout

---

### 2. roles (Player Role Assignments)

```lua
OGRH_SV.v2.roles = {
    ["PlayerName"] = "TANKS",      -- string: TANKS, HEALERS, MELEE, RANGED
    ["PlayerName2"] = "HEALERS",
    -- ... keyed by player name
}
```

**Note:** This is a **global role assignment** (cross-encounter). Encounter-specific assignments are in `encounterMgmt.raids[].encounters[].roles[].assignments`.

---

### 3. invites (RaidHelper.io Integration)

```lua
OGRH_SV.v2.invites = {
    -- Current Source
    currentSource = "raidhelper",  -- string: "raidhelper" or "manual"
    autoSortEnabled = false,       -- boolean: Auto-sort by RaidHelper groups
    
    -- Invite Mode State
    inviteMode = {
        enabled = false,           -- boolean: Invite mode active
        totalPlayers = 20,         -- number: Expected total players
        interval = 60,             -- number: Seconds between invites
        lastInviteTime = 0,        -- number: Timestamp of last invite
        invitedCount = 0,          -- number: Players invited so far
    },
    
    -- RaidHelper Event Data
    raidhelperData = {
        id = "1463359972531245180",  -- string: RaidHelper event ID
        name = "Molten Core",         -- string: Event name
        players = {
            [1] = {
                name = "PlayerName",
                class = "Warrior",
                spec = "Tank",
                status = "accepted",  -- "accepted", "declined", "tentative"
                -- ... other player metadata
            },
            -- ... array of players
        }
    },
    
    -- RaidHelper Group Composition
    raidhelperGroupsData = {
        hash = "1463359972531245180",  -- string: Matches raidhelperData.id
        title = "Composition Tool",    -- string: Tool title
        groupAssignments = {
            ["PlayerName"] = 1,        -- number: Group number (1-8)
            ["PlayerName2"] = 2,
            -- ... keyed by player name
        },
        players = {
            [1] = {
                name = "PlayerName",
                class = "Warrior",
                -- ... same structure as raidhelperData.players
            },
            -- ... array of players
        }
    },
    
    -- Declined Players
    declinedPlayers = {},  -- table: Players who declined invite
    
    -- UI State
    invitePanelPosition = {
        point = "BOTTOMRIGHT",
        x = -20,
        y = 200,
    }
}
```

---

### 4. consumesTracking (Consumable Tracking)

```lua
OGRH_SV.v2.consumesTracking = {
    -- Core Settings
    enabled = true,                -- boolean: Tracking enabled
    trackOnPull = true,            -- boolean: Track on pull countdown
    logToMemory = true,            -- boolean: Store in memory
    logToCombatLog = true,         -- boolean: Write to combat log
    maxEntries = 200,              -- number: Max log entries
    secondsBeforePull = 2,         -- number: How early to check buffs
    
    -- Pull Detection
    pullTriggers = {
        [1] = "pull%s+(%d+)",      -- string: Lua pattern for pull countdown
        [2] = "пулл%s+(%d+)",      -- string: Russian
        [3] = "тянем%s+(%d+)",     -- string: Russian
        [4] = "пул%s+(%d+)",       -- string: Russian
    },
    
    -- Consumable Weights (for scoring)
    weights = {
        ["Flask of the Titans"] = 3,
        ["Flask of Supreme Power"] = 3,
        ["titans"] = 5,
        ["wisdom"] = 5,
        ["flask"] = 5,
        -- ... keyed by consumable name/alias
    },
    
    -- Tracking Profiles (empty by default, populated at runtime)
    trackingProfiles = {},
    
    -- Conflict Resolution
    conflicts = {
        [1] = {
            profile1 = "dreamwater_1",
            profile2 = "dreamwater_2",
            items = {"Dreamwater 1", "Dreamwater 2"},
            profileIndex = 1,
        },
        -- ... array of conflict definitions
    },
    
    -- Role Mapping
    roleMapping = {
        ["mongoose_13"] = {
            tanks = true,
            melee = true,
            ranged = false,
            healers = false,
        },
        -- ... keyed by profile name
    },
    
    -- Item Mapping (empty by default)
    mapping = {}
}
```

---

### 5. consumes (Consumable Definitions)

```lua
OGRH_SV.v2.consumes = {
    [1] = {
        itemId = 13461,                                -- number: Item ID
        primaryName = "Greater Arcane Protection Potion",  -- string: Display name
        aliases = {"Greater Arcane Prot", "GAPP"},     -- array: Alternate names (optional)
    },
    [2] = {
        itemId = 13457,
        primaryName = "Greater Fire Protection Potion",
        aliases = {"Greater Fire Prot", "GFPP"},
    },
    -- ... array of consumable definitions
}
```

---

### 6. tradeItems (Auto-Trade Items)

```lua
OGRH_SV.v2.tradeItems = {
    [1] = {
        itemId = 19183,         -- number: Item ID
        name = "Hourglass Sand", -- string: Item name
        quantity = 5,           -- number: Quantity to trade
    },
    [2] = {
        itemId = 13461,
        name = "Greater Arcane Protection Potion",
        quantity = 1,
    },
    -- ... array of items
}
```

---

### 7. recruitment (Recruitment Automation)

```lua
OGRH_SV.v2.recruitment = {
    -- Recruitment State
    enabled = false,                  -- boolean: Recruitment active
    autoAd = false,                   -- boolean: Auto-post ads
    isRecruiting = false,             -- boolean: Currently recruiting
    interval = 300,                   -- number: Seconds between ads
    lastAdTime = 0,                   -- number: Timestamp of last ad
    lastRotationIndex = 4,            -- number: Last message index used
    
    -- Channel Settings
    selectedChannel = "world",        -- string: "world", "lookingforgroup", "guild", etc.
    targetTime = "1930",              -- string: Raid start time (HHMM format)
    
    -- Messages
    selectedMessageIndex = 5,         -- number: Currently selected message
    message = "<Blood and Thunder>...", -- string: Current message text
    messages = {
        [1] = "Message 1",
        [2] = "Message 2",
        -- ... array of saved messages
    },
    messages2 = {
        [1] = "",
        [2] = "",
        -- ... secondary message set (optional follow-up messages)
    },
    rotateMessages = {
        [1] = 1,  -- Indices of messages to rotate
    },
    
    -- Player Cache
    playerCache = {
        ["PlayerName"] = {
            name = "PlayerName",
            class = "Warrior",
            level = 60,
            zone = "Orgrimmar",
            guild = "Some Guild",
            lastSeen = 1234567890,  -- timestamp
            -- ... player metadata
        },
        -- ... keyed by player name
    },
    
    -- Contact Management
    contacts = {},           -- table: Saved contacts
    deletedContacts = {
        ["PlayerName"] = true,
    },
    whisperHistory = {},     -- table: Whisper history
}
```

---

### 8. rosterManagement (Ranking System)

```lua
OGRH_SV.v2.rosterManagement = {
    config = {
        rankingSource = "DPSMate",       -- string: Source addon for rankings
        useEffectiveHealing = true,      -- boolean: Use EH for healers
        historySize = 10,                -- number: Number of rankings to keep
        
        autoRankingEnabled = {
            TANKS = true,
            HEALERS = true,
            MELEE = true,
            RANGED = true,
        },
        
        eloSettings = {
            startingRating = 1000,       -- number: Default ELO rating
            kFactor = 32,                -- number: ELO K-factor (optional)
            -- ... other ELO settings
        }
    },
    
    syncMeta = {
        version = 1,                     -- number: Sync version
        syncChecksum = "",               -- string: Checksum for validation
        lastSync = 0,                    -- number: Timestamp of last sync
    },
    
    rankingHistory = {}  -- table: Historical ranking data
}
```

---

### 9. srValidation (SoftRes Validation)

```lua
OGRH_SV.v2.srValidation = {
    records = {}  -- table: Validation records (structure TBD)
}
```

---

### 10. permissions (Permission System)

```lua
OGRH_SV.v2.permissions = {
    currentAdmin = "PlayerName",  -- string: Current admin player name
    
    adminHistory = {
        [1] = {
            admin = "PlayerName",
            timestamp = 1234567890,
            reason = "Initial setup",
        },
        -- ... array of admin changes
    },
    
    permissionDenials = {}  -- table: Denied permission requests
}
```

---

### 11. versioning (Version Tracking)

```lua
OGRH_SV.v2.versioning = {
    globalVersion = 76,            -- number: Global version counter
    
    encounterVersions = {}         -- table: Per-encounter version tracking
    assignmentVersions = {}        -- table: Per-assignment version tracking
}
```

---

### 12. UI State

#### Main UI Window
```lua
OGRH_SV.v2.ui = {
    point = "TOPLEFT",              -- string: Anchor point
    relPoint = "TOPLEFT",           -- string: Relative anchor point
    x = 545.8751474685334,          -- number: X offset
    y = -163.2500089074379,         -- number: Y offset
    minimized = false,              -- boolean: Window minimized
    hidden = false,                 -- boolean: Window hidden
    locked = false,                 -- boolean: Window locked
    selectedRaid = "Molten Core",   -- string: Currently selected raid
    selectedEncounter = "Tanks and Heals",  -- string: Currently selected encounter
}
```

#### Roles UI Window
```lua
OGRH_SV.v2.rolesUI = {
    point = "TOPLEFT",
    relPoint = "TOPLEFT",
    x = 370.3750297399008,
    y = -108.1249481368273,
}
```

#### Minimap Button
```lua
OGRH_SV.v2.minimap = {
    angle = 200,  -- number: Angle around minimap (0-360)
}
```

---

### 13. Sorting

```lua
OGRH_SV.v2.sorting = {
    speed = 200,  -- number: Animation speed in milliseconds
}
```

---

## Companion SavedVariable: OGRH_ConsumeHelper_SV

**Location:** Separate top-level variable (not nested in OGRH_SV)

```lua
OGRH_ConsumeHelper_SV = {
    -- Player Role Cache
    playerRoles = {
        ["PlayerName"] = {
            class = "WARLOCK",
            ["Caster DPS"] = true,  -- Role flags
        },
        ["PlayerName2"] = {
            class = "PALADIN",
            ["Tank"] = true,
        },
        -- ... keyed by player name
    },
    
    -- Setup Consumables (Master List)
    setupConsumes = {
        [1] = 12458,  -- Item IDs
        [2] = 20749,
        -- ... array of item IDs
    },
    
    -- Per-Raid/Role Consumable Requirements
    consumes = {
        ["BWL"] = {
            ["All"] = {
                [1] = 13457,  -- Item IDs required for all roles
                [2] = 13461,
            },
            ["Tank"] = {
                [1] = 12451,  -- Item IDs required for tanks
            },
            ["Healer"] = {
                [1] = 13444,
            },
            -- ... other roles
        },
        ["Molten Core"] = {
            ["All"] = {},
            ["Paladin"] = {},  -- Class-specific requirements
        },
        ["AQ40"] = {
            -- ... raid-specific requirements
        },
        ["Naxx"] = {
            -- ... raid-specific requirements
        },
        ["Onyxia"] = {
            -- ... raid-specific requirements
        },
        ["General"] = {
            -- Default/global requirements
            ["Paladin"] = {},
            ["Ranged DPS"] = {},
            ["Caster DPS"] = {},
            ["Melee DPS"] = {},
            ["All"] = {},
            ["Tank"] = {},
            ["Healer"] = {},
        }
    }
}
```

---

## Schema Evolution & Migration Notes

### From v1 to v2

**Key Changes:**
1. ✅ **Stable Numeric Indices:** Display names moved to metadata, numeric indices as keys
2. ✅ **Nested Structure:** Roles moved inside encounters (was separate `encounterAssignments` table)
3. ✅ **Explicit Columns:** `column` field explicitly defines UI layout (1 or 2)
4. ✅ **Schema Version:** `schemaVersion = 2` at encounterMgmt level
5. ✅ **Consistent Metadata:** All entities have `id`, `name`/`displayName`, `sortOrder`

**Location:**
- **v1 Active:** Data at `OGRH_SV.*` (top level)
- **v2 Active:** Data at `OGRH_SV.v2.*` (nested)
- **After Cutover:** v1 remains at `OGRH_SV.*` (read-only, rollback capability)

**Migration Process:**
1. Code updated to use SVM read wrappers (`GetPath()`, `Get()`)
2. v2 schema generated at `OGRH_SV.v2.*` via `/ogrh migration create`
3. Comparison/validation via `/ogrh migration comp` commands
4. Cutover via `/ogrh migration cutover confirm` sets `schemaVersion = "v2"`
5. v1 data preserved for emergency rollback

---

## Known Issues & Recommendations

### 🔴 Critical Issues

**RESOLVED:** ~~Duplicate Keys: Both `permissions`/`Permissions` and `versioning`/`Versioning` existed~~
   - ✅ **Fixed:** Consolidated to lowercase in migration code (January 30, 2026)
   - **Impact:** None - migration now generates correct lowercase keys only

**RESOLVED:** ~~Deprecated `order` field~~
   - ✅ **Fixed:** All runtime code removed (January 30, 2026)
   - ✅ **Migrated but frozen:** Field will be copied from v1 to v2 during migration to preserve existing data, but will remain static
   - **Details:** Manual player ordering feature was previously replaced with alphabetical sort; all maintenance code removed
   - **Impact:** None - field is unused and frozen; no new data will be written to it

### 🟡 Remaining Improvement Opportunities

1. **Inconsistent Metadata:** Some entities have both `name` and `displayName`
   - **Recommendation:** Standardize on `name` only
   - **Impact:** Low (both fields contain same value)

2. **Semantic IDs:** Not all entities have `id` field populated
   - **Recommendation:** Populate during migration or make optional
   - **Impact:** Low (numeric indices work without IDs)

3. **Column Assignment:** Mixing UI layout (`column`) with data structure
   - **Recommendation:** Consider separating UI layout from data model in future
   - **Impact:** Low (current structure works)

4. **Role Restrictions:** `defaultRoles` uses numeric flags (0/1) vs booleans
   - **Recommendation:** Standardize on booleans
   - **Impact:** Low (code handles both)

---

## SVM Integration

### Read Operations

```lua
-- Access v2 data through SVM (abstracts schema location)
local raids = OGRH.SVM.GetPath("encounterMgmt.raids")
local tank1 = OGRH.SVM.GetPath("encounterMgmt.raids.1.encounters.5.roles.1.assignments.1")
```

### Write Operations

```lua
-- Write with sync metadata
OGRH.SVM.SetPath(
    "encounterMgmt.raids.1.encounters.5.roles.1.assignments.1",
    "PlayerName",
    {
        syncLevel = "REALTIME",
        componentType = "roles",
        scope = {raid = 1, encounter = 5}
    }
)
```

**Note:** SVM automatically routes to `OGRH_SV.v2.*` when `schemaVersion = "v2"`.

---

## Schema Validation Checklist

When working with v2 schema:

- [ ] Use numeric indices for raids, encounters, roles, slots
- [ ] Include metadata: `name`, `sortOrder`, (optional: `id`)
- [ ] Specify `column` (1 or 2) for each role
- [ ] Use `assignments` array (not `slots` as table keys)
- [ ] Include `schemaVersion = 2` in `encounterMgmt`
- [ ] Access via SVM for automatic v1/v2 routing
- [ ] Provide sync metadata for all writes

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 2.0 | January 30, 2026 | Initial specification from migrated SavedVariables |
| 2.0.1 | January 30, 2026 | Fixed: Consolidated permissions/Permissions and versioning/Versioning to lowercase; Removed deprecated `order` field from migration and runtime code |
| 2.0.2 | January 30, 2026 | Fixed: Added explicit cleanup of orphaned `order` field in cutover and purge operations |

---

## Authority & Conflicts

**This specification is based on:**
- ✅ **Primary Source:** Actual migrated SavedVariables (OG-RaidHelperSV Post Migration Post Purge.lua)
- ⚠️ **Secondary Source:** Design documents (v2-Schema-Stable-Identifiers-Design.md)

**If conflicts exist between this spec and design docs:**
- Trust the **actual SavedVariables data** (user's working system)
- Note discrepancies for review
- Update design docs to match reality

---

## See Also

- [SVM API Documentation](! SVM-API-Documentation.md) - Read/write interface
- [SVM Quick Reference](! SVM-Quick-Reference.md) - Common patterns
- [v2 Schema Design](v2-Schema-Stable-Identifiers-Design.md) - Design rationale
- [Migration Guide](Migration-Guide.md) - v1 to v2 migration process
