# v2 Schema: Stable Identifiers Design

**Date:** January 23, 2026  
**Status:** 🔴 CRITICAL FIX - Redesign v2 schema before Phase 2 continues  
**Issue:** v1 uses user-editable display names as table keys (fragile), v2 partially fixed this but encounterAssignments still broken

---

## Executive Summary

**Problem Discovered:** During Phase 2 write migration, drag-drop of player "Kinduosen" to encounter "Tanks and Heals" failed because:
- SetPath() uses dot-separated strings: `"encounterAssignments.MC.Tanks and Heals.1.4"`
- Encounter name has spaces → breaks parsing
- **ROOT CAUSE**: Display names used as table keys throughout v1

**User Mandate:** "The ENTIRE point of this project is to fix the data structure from fragile and problematic to rock solid, efficient and intuitive. When we discover shit like this we need to unfuck it, not just work around it."

**Solution:** Use **stable numeric indices** as keys, store display names as metadata.

---

## Core Design Principle

### ❌ v1 Approach (BROKEN)
```lua
-- Display names as keys (user-editable, fragile)
OGRH_SV.encounterAssignments["MC"]["Tanks and Heals"][1][4] = "PlayerName"
--                            └─┬─┘ └───────┬────────┘
--                         Display name   Display name (with spaces!)
```

### ✅ v2 Approach (STABLE)
```lua
-- Numeric indices as keys (stable, immutable)
OGRH_SV.encounterAssignments[1][5][1][4] = "PlayerName"
--                            │  │  │  └─ slotIndex (numeric)
--                            │  │  └──── roleIndex (numeric)
--                            │  └─────── encounterIndex (numeric)
--                            └────────── raidIndex (numeric)

-- Display names stored separately as metadata
OGRH_SV.encounterMgmt.raids[1].name = "MC"  -- Can change without breaking refs
OGRH_SV.encounterMgmt.raids[1].encounters[5].name = "Tanks and Heals"  -- Can rename!
```

---

## Complete v2 Schema Definition

### 1. Encounter Management (Main Structure)

```lua
OGRH_SV.encounterMgmt = {
    schemaVersion = 2,
    
    raids = {
        [1] = {  -- Raid Index (STABLE)
            id = "mc",           -- Semantic ID (optional, for code readability)
            name = "MC",         -- Display Name (user-editable)
            sortOrder = 1,       -- UI display order
            
            encounters = {
                [1] = {  -- Encounter Index (STABLE)
                    id = "lucifron",        -- Semantic ID (optional)
                    name = "Lucifron",      -- Display Name (user-editable)
                    sortOrder = 1,          -- UI display order
                    
                    -- Roles nested in encounter (v2 improvement)
                    roles = {
                        [1] = {  -- Role Index (STABLE) - was "column1[1]"
                            id = "mt",              -- Semantic ID (optional)
                            name = "Main Tank",     -- Display Name (user-editable)
                            column = 1,             -- UI column (1 or 2) - REQUIRED for display
                            slots = 1,
                            fillOrder = 1,
                            sortOrder = 1,          -- Display order within column
                            defaultRoles = {tanks = 1},
                            showRaidIcons = 1,
                            classPriority = {
                                [1] = {[1] = "Warrior"}
                            }
                        },
                        [2] = {  -- Role Index (STABLE) - was "column1[2]"
                            id = "decurse",
                            name = "Decursers",
                            column = 1,             -- UI column (1 or 2)
                            slots = 4,
                            fillOrder = 2,
                            sortOrder = 2,
                            defaultRoles = {healers = 1},
                            classPriority = {
                                [1] = {[1] = "Mage"},
                                [2] = {[1] = "Mage"},
                                [3] = {[1] = "Druid"},
                                [4] = {[1] = "Druid"}
                            }
                        },
                        [3] = {  -- Role Index (STABLE) - was "column2[1]"
                            id = "ot",
                            name = "Off Tanks",
                            column = 2,             -- UI column 2
                            slots = 2,
                            fillOrder = 3,
                            sortOrder = 1,          -- First in column 2
                            defaultRoles = {tanks = 1},
                            showRaidIcons = 1
                        },
                        [4] = {  -- Role Index (STABLE) - Example: Warriors in different roles
                            id = "dps",
                            name = "Melee DPS",
                            column = 2,
                            slots = 3,
                            fillOrder = 4,
                            sortOrder = 2,
                            defaultRoles = {melee = 1},
                            classPriority = {
                                [1] = {[1] = "Warrior"},  -- Slot 1: Warrior DPS
                                [2] = {[1] = "Rogue"},    -- Slot 2: Rogue
                                [3] = {[1] = "Warrior"}   -- Slot 3: Warrior DPS
                            },
                            classPriorityRoles = {
                                [1] = {
                                    ["Warrior"] = {["Melee"] = true}  -- Warrior from Melee role, not Tanks
                                },
                                [2] = {
                                    ["Rogue"] = {["Melee"] = true}
                                },
                                [3] = {
                                    ["Warrior"] = {["Melee"] = true}  -- Another Warrior from Melee role
                                }
                            }
                        }
                    },
                    
                    advancedSettings = {
                        bigwigs = {
                            enabled = 1,
                            encounterId = "Lucifron",
                            autoAnnounce = 1
                        },
                        consumeTracking = {
                            enabled = 1,
                            readyThreshold = 85
                        }
                    }
                },
                [2] = {  -- Encounter Index 2
                    id = "magmadar",
                    name = "Magmadar",
                    sortOrder = 2,
                    roles = {...}
                }
                -- ... more encounters
            },
            
            advancedSettings = {
                consumeTracking = {
                    enabled = 1,
                    readyThreshold = 85,
                    requiredFlaskRoles = {
                        ["Tanks"] = false,
                        ["Healers"] = false,
                        ["Melee"] = false,
                        ["Ranged"] = false
                    }
                },
                bigwigs = {
                    enabled = 1,
                    raidZone = "Molten Core",
                    autoAnnounce = 1,
                    raidZones = {
                        [1] = "Molten Core",
                        [2] = "MC"
                    }
                }
            }
        },
        [2] = {  -- Raid Index 2
            id = "bwl",
            name = "BWL",
            sortOrder = 2,
            encounters = {
                [1] = {
                    id = "razorgore",
                    name = "Razorgore",
                    sortOrder = 1,
                    roles = {...},
                    advancedSettings = {...}
                }
                -- ... more encounters
            },
            advancedSettings = {
                consumeTracking = {
                    enabled = 1,
                    readyThreshold = 85,
                    requiredFlaskRoles = {
                        ["Tanks"] = false,
                        ["Healers"] = false,
                        ["Melee"] = false,
                        ["Ranged"] = false
                    }
                },
                bigwigs = {
                    enabled = 1,
                    raidZone = "Blackwing Lair",
                    autoAnnounce = 1,
                    raidZones = {
                        [1] = "Blackwing Lair"
                    }
                }
            }
        }
        -- ... 8 total raids
    }
}
```

### 2. Encounter Assignments (Player → Role Mappings)

```lua
-- v1 BROKEN: String keys
OGRH_SV.encounterAssignments = {
    ["MC"] = {
        ["Tanks and Heals"] = {  -- BREAKS with spaces!
            [1] = {[1] = "PlayerName"}
        }
    }
}

-- v2 FIXED: Numeric indices
OGRH_SV.encounterAssignments = {
    [1] = {  -- raidIndex
        [5] = {  -- encounterIndex
            [1] = {  -- roleIndex
                [1] = "PlayerName",     -- slotIndex → playerName
                [2] = "AnotherPlayer"
            },
            [2] = {  -- roleIndex 2
                [1] = "Healer1",
                [2] = "Healer2"
            }
        }
    }
}

-- SetPath now works perfectly:
OGRH.SVM.SetPath("encounterAssignments.1.5.1.1", "PlayerName")
-- No spaces, no special characters, clean numeric path
```

### 3. Encounter Assignment Numbers

```lua
-- v1 BROKEN: String keys
OGRH_SV.encounterAssignmentNumbers = {
    ["MC"] = {
        ["Tanks and Heals"] = {
            [1] = {[1] = 5}  -- Assigned number
        }
    }
}

-- v2 FIXED: Numeric indices
OGRH_SV.encounterAssignmentNumbers = {
    [1] = {  -- raidIndex
        [5] = {  -- encounterIndex
            [1] = {  -- roleIndex
                [1] = 5  -- slotIndex → number
            }
        }
    }
}
```

### 4. Encounter Raid Marks

```lua
-- v1 BROKEN: String keys
OGRH_SV.encounterRaidMarks = {
    ["MC"] = {
        ["Tanks and Heals"] = {
            [1] = {[1] = "skull"}
        }
    }
}

-- v2 FIXED: Numeric indices
OGRH_SV.encounterRaidMarks = {
    [1] = {  -- raidIndex
        [5] = {  -- encounterIndex
            [1] = {  -- roleIndex
                [1] = "skull"  -- slotIndex → markId
            }
        }
    }
}
```

### 5. Encounter Announcements

```lua
-- v1 BROKEN: String keys
OGRH_SV.encounterAnnouncements = {
    ["MC"] = {
        ["Tanks and Heals"] = {
            [1] = {  -- announcementIndex
                enabled = true,
                channel = "RAID_WARNING",
                text = "Tank swap in 3 seconds!"
            }
        }
    }
}

-- v2 FIXED: Numeric indices
OGRH_SV.encounterAnnouncements = {
    [1] = {  -- raidIndex
        [5] = {  -- encounterIndex
            [1] = {  -- announcementIndex
                enabled = true,
                channel = "RAID_WARNING",
                text = "Tank swap in 3 seconds!"
            }
        }
    }
}
```

### 6. SR+ Validation Records

**Status:** ⚠️ NEEDS V2 OVERHAUL - Current structure fragile, will be redesigned

```lua
-- v1 FRAGILE: Uses player names as keys (can change)
OGRH_SV.srValidation = {
    records = {
        ["PlayerName"] = {  -- ❌ Player name as key (fragile)
            [1] = {
                date = "2025-11-22",
                time = "12:27:58",
                validator = "Tankmedaddy",
                instance = "Naxxramas",
                srPlus = 60,
                items = {
                    [1] = {
                        name = "Eye of the Dead",
                        plus = 60,
                        itemId = 23047
                    },
                    [2] = {
                        name = "Hammer of the Twisting Nether",
                        plus = 60,
                        itemId = 23056
                    }
                }
            }
        }
    }
}

-- v2 TODO: Will be redesigned with stable player identifiers
-- Current migration: NO CHANGE (preserve as-is, mark for v2 overhaul)
-- Future v2: Use numeric player IDs or GUIDs as keys
OGRH_SV.srValidation = {
    records = {
        -- TODO: Redesign with stable player IDs
        -- For now: Keep existing structure but mark as deprecated
        ["PlayerName"] = { ... }  -- Preserved for migration
    }
}
```

**Note:** SR+ validation system requires complete overhaul in v2 release. Current migration preserves existing data structure but marks it as needing redesign. Future v2 should use stable player identifiers (numeric IDs or GUIDs) instead of player names as keys.

---

## Index Lookup System

Since users see names but code uses indices, we need efficient lookup helpers.

### Name → Index Lookup Functions

```lua
OGRH.SVM.Lookup = {}

-- Get raid index by name
function OGRH.SVM.Lookup.GetRaidIndex(raidName)
    if not OGRH_SV.encounterMgmt or not OGRH_SV.encounterMgmt.raids then
        return nil
    end
    
    for raidIdx, raid in ipairs(OGRH_SV.encounterMgmt.raids) do
        if raid.name == raidName then
            return raidIdx
        end
    end
    return nil
end

-- Get encounter index by name (within raid)
function OGRH.SVM.Lookup.GetEncounterIndex(raidIndex, encounterName)
    if not OGRH_SV.encounterMgmt or 
       not OGRH_SV.encounterMgmt.raids[raidIndex] or 
       not OGRH_SV.encounterMgmt.raids[raidIndex].encounters then
        return nil
    end
    
    local encounters = OGRH_SV.encounterMgmt.raids[raidIndex].encounters
    for encIdx, encounter in ipairs(encounters) do
        if encounter.name == encounterName then
            return encIdx
        end
    end
    return nil
end

-- Get role index by name (within encounter)
function OGRH.SVM.Lookup.GetRoleIndex(raidIndex, encounterIndex, roleName)
    if not OGRH_SV.encounterMgmt or 
       not OGRH_SV.encounterMgmt.raids[raidIndex] or 
       not OGRH_SV.encounterMgmt.raids[raidIndex].encounters[encounterIndex] or
       not OGRH_SV.encounterMgmt.raids[raidIndex].encounters[encounterIndex].roles then
        return nil
    end
    
    local roles = OGRH_SV.encounterMgmt.raids[raidIndex].encounters[encounterIndex].roles
    for roleIdx, role in ipairs(roles) do
        if role.name == roleName then
            return roleIdx
        end
    end
    return nil
end

-- Convenience: Get all indices from names
function OGRH.SVM.Lookup.ResolveNames(raidName, encounterName, roleName)
    local raidIdx = OGRH.SVM.Lookup.GetRaidIndex(raidName)
    if not raidIdx then return nil, nil, nil end
    
    local encIdx = OGRH.SVM.Lookup.GetEncounterIndex(raidIdx, encounterName)
    if not encIdx then return raidIdx, nil, nil end
    
    local roleIdx = nil
    if roleName then
        roleIdx = OGRH.SVM.Lookup.GetRoleIndex(raidIdx, encIdx, roleName)
    end
    
    return raidIdx, encIdx, roleIdx
end
```

### Usage Examples

```lua
-- Old v1 approach (BROKEN):
OGRH_SV.encounterAssignments["MC"]["Tanks and Heals"][1][1] = "PlayerName"

-- New v2 approach with lookup:
local raidIdx, encIdx = OGRH.SVM.Lookup.ResolveNames("MC", "Tanks and Heals")
if raidIdx and encIdx then
    OGRH.SVM.SetPath(
        string.format("encounterAssignments.%d.%d.1.1", raidIdx, encIdx),
        "PlayerName",
        {syncLevel = "REALTIME", componentType = "assignments"}
    )
end

-- Or use helper (even cleaner):
OGRH.SVM.SetAssignment("MC", "Tanks and Heals", 1, 1, "PlayerName")
```

---

## Migration Strategy

### Phase 1: Analyze v1 Data

```lua
function OGRH.Migration.AnalyzeV1Structure()
    local analysis = {
        raids = {},
        totalEncounters = 0,
        totalRoles = 0,
        encountersWithSpaces = {}
    }
    
    -- Analyze encounterMgmt structure
    if OGRH_SV.encounterMgmt and OGRH_SV.encounterMgmt.raids then
        for raidIdx, raid in ipairs(OGRH_SV.encounterMgmt.raids) do
            local raidName = raid.name
            local raidInfo = {
                name = raidName,
                encounters = {},
                encounterCount = 0
            }
            
            if raid.encounters then
                for encIdx, encounter in ipairs(raid.encounters) do
                    local encName = encounter.name
                    analysis.totalEncounters = analysis.totalEncounters + 1
                    raidInfo.encounterCount = raidInfo.encounterCount + 1
                    
                    -- Check for problematic characters
                    if string.find(encName, " ") then
                        table.insert(analysis.encountersWithSpaces, {
                            raid = raidName,
                            encounter = encName
                        })
                    end
                    
                    table.insert(raidInfo.encounters, encName)
                end
            end
            
            table.insert(analysis.raids, raidInfo)
        end
    end
    
    return analysis
end
```

### Phase 2: Create Index Mapping

```lua
function OGRH.Migration.BuildIndexMapping()
    local mapping = {
        raids = {},      -- [raidName] = raidIndex
        encounters = {}, -- [raidName][encounterName] = encounterIndex
        roles = {}       -- [raidName][encounterName][roleName] = roleIndex
    }
    
    if not OGRH_SV.encounterMgmt or not OGRH_SV.encounterMgmt.raids then
        return mapping
    end
    
    for raidIdx, raid in ipairs(OGRH_SV.encounterMgmt.raids) do
        local raidName = raid.name
        mapping.raids[raidName] = raidIdx
        mapping.encounters[raidName] = {}
        mapping.roles[raidName] = {}
        
        if raid.encounters then
            for encIdx, encounter in ipairs(raid.encounters) do
                local encName = encounter.name
                mapping.encounters[raidName][encName] = encIdx
                mapping.roles[raidName][encName] = {}
                
                -- v1 has roles in separate table
                if OGRH_SV.encounterMgmt.roles and 
                   OGRH_SV.encounterMgmt.roles[raidName] and 
                   OGRH_SV.encounterMgmt.roles[raidName][encName] then
                    
                    local rolesData = OGRH_SV.encounterMgmt.roles[raidName][encName]
                    local roleIdx = 1
                    
                    -- Flatten column1/column2 into sequential array
                    -- Store column info in role object for UI display
                    if rolesData.column1 then
                        for i = 1, table.getn(rolesData.column1) do
                            local role = rolesData.column1[i]
                            if role and role.name then
                                mapping.roles[raidName][encName][role.name] = {
                                    index = roleIdx,
                                    column = 1,
                                    sortOrder = i
                                }
                                roleIdx = roleIdx + 1
                            end
                        end
                    end
                    
                    if rolesData.column2 then
                        for i = 1, table.getn(rolesData.column2) do
                            local role = rolesData.column2[i]
                            if role and role.name then
                                mapping.roles[raidName][encName][role.name] = {
                                    index = roleIdx,
                                    column = 2,
                                    sortOrder = i
                                }
                                roleIdx = roleIdx + 1
                            end
                        end
                    end
                end
            end
        end
    end
    
    return mapping
end
```

### Phase 3: Migrate Roles Structure

```lua
function OGRH.Migration.MigrateRolesToV2(mapping)
    if not OGRH_SV.encounterMgmt or 
       not OGRH_SV.encounterMgmt.raids or
       not OGRH_SV.encounterMgmt.roles then
        return
    end
    
    -- v1: roles stored separately by string keys
    -- v2: roles nested in encounter with column field
    
    for raidIdx, raid in ipairs(OGRH_SV.encounterMgmt.raids) do
        local raidName = raid.name
        
        if raid.encounters and OGRH_SV.encounterMgmt.roles[raidName] then
            for encIdx, encounter in ipairs(raid.encounters) do
                local encName = encounter.name
                
                if OGRH_SV.encounterMgmt.roles[raidName][encName] then
                    local v1Roles = OGRH_SV.encounterMgmt.roles[raidName][encName]
                    encounter.roles = {}
                    local roleIdx = 1
                    
                    -- Migrate column1 roles
                    if v1Roles.column1 then
                        for i = 1, table.getn(v1Roles.column1) do
                            local role = v1Roles.column1[i]
                            if role then
                                -- Add column field for UI
                                role.column = 1
                                role.sortOrder = i
                                encounter.roles[roleIdx] = role
                                roleIdx = roleIdx + 1
                            end
                        end
                    end
                    
                    -- Migrate column2 roles
                    if v1Roles.column2 then
                        for i = 1, table.getn(v1Roles.column2) do
          5                 local role = v1Roles.column2[i]
                            if role then
                                -- Add column field for UI
                                role.column = 2
                                role.sortOrder = i
                                encounter.roles[roleIdx] = role
                                roleIdx = roleIdx + 1
                            end
                        end
                    end
                else
                    -- Initialize empty roles
                    encounter.roles = {}
                end
            end
        end
    end
    
    -- Remove old separate roles table
    OGRH_SV.encounterMgmt.roles = nil
end
```

### Phase 4: Migrate encounterAssignments

```lua
function OGRH.Migration.MigrateEncounterAssignments(mapping)
    if not OGRH_SV.encounterAssignments then return end
    
    local v2Assignments = {}
    
    -- v1: encounterAssignments[raidName][encounterName][roleIndex][slotIndex]
    -- v2: encounterAssignments[raidIdx][encIdx][roleIdx][slotIdx]
    
    for raidName, raidData in pairs(OGRH_SV.encounterAssignments) do
        local raidIdx = mapping.raids[raidName]
        if not raidIdx then
            OGRH.Msg(string.format("WARNING: Raid '%s' not found in mapping", raidName))
        else
            if not v2Assignments[raidIdx] then
                v2Assignments[raidIdx] = {}
            end
            
            for encounterName, encounterData in pairs(raidData) do
                local encIdx = mapping.encounters[raidName][encounterName]
                if not encIdx then
                    OGRH.Msg(string.format("WARNING: Encounter '%s' not found in mapping", encounterName))
                else
                    if not v2Assignments[raidIdx][encIdx] then
                        v2Assignments[raidIdx][encIdx] = {}
                    end
                    
                    -- Copy role/slot data (already using numeric indices)
                    for roleIdx, roleData in pairs(encounterData) do
                        v2Assignments[raidIdx][encIdx][roleIdx] = roleData
                    end
                end
            end
        end
    end
    
    return v2Assignments
end
```

### Phase 4: Migrate Other Tables

```lua
function OGRH.Migration.MigrateAllAssignmentTables(mapping)
    local migrations = {}
    
    -- Migrate encounterAssignments
    migrations.encounterAssignments = OGRH.Migration.MigrateEncounterAssignments(mapping)
    
    -- Migrate encounterAssignmentNumbers (same structure)
    if OGRH_SV.encounterAssignmentNumbers then
        migrations.encounterAssignmentNumbers = {}
        for raidName, raidData in pairs(OGRH_SV.encounterAssignmentNumbers) do
            local raidIdx = mapping.raids[raidName]
            if raidIdx then
                if not migrations.encounterAssignmentNumbers[raidIdx] then
                    migrations.encounterAssignmentNumbers[raidIdx] = {}
                end
                for encounterName, encounterData in pairs(raidData) do
                    local encIdx = mapping.encounters[raidName][encounterName]
                    if encIdx then
                        migrations.encounterAssignmentNumbers[raidIdx][encIdx] = encounterData
                    end
                end
            end
        end
    end
    
    -- Migrate encounterRaidMarks (same structure)
    if OGRH_SV.encounterRaidMarks then
        migrations.encounterRaidMarks = {}
        for raidName, raidData in pairs(OGRH_SV.encounterRaidMarks) do
            local raidIdx = mapping.raids[raidName]
            if raidIdx then
                if not migrations.encounterRaidMarks[raidIdx] then
                    migrations.encounterRaidMarks[raidIdx] = {}
                end
                for encounterName, encounterData in pairs(raidData) do
                    local encIdx = mapping.encounters[raidName][encounterName]
                    if encIdx then
                        migrations.encounterRaidMarks[raidIdx][encIdx] = encounterData
                    end
                end
            end
        end
    end
    
    -- Migrate encounterAnnouncements (same structure)
    if OGRH_SV.encounterAnnouncements then
        migrations.encounterAnnouncements = {}
        for raidName, raidData in pairs(OGRH_SV.encounterAnnouncements) do
            local raidIdx = mapping.raids[raidName]
            if raidIdx then
                if not migrations.encounterAnnouncements[raidIdx] then
                    migrations.encounterAnnouncements[raidIdx] = {}
                end
                for encounterName, encounterData in pairs(raidData) do
                    local encIdx = mapping.encounters[raidName][encounterName]
                    if encIdx then
                        migrations.encounterAnnouncements[raidIdx][encIdx] = encounterData
                    end
                end
            end
        end
    end
    
    return migrations
end
```

### Phase 6: Full Migration Execute

```lua
function OGRH.Migration.ExecuteV2Migration()
    OGRH.Msg("Starting v2 migration to stable identifiers...")
    
    -- Step 1: Analyze current structure
    local analysis = OGRH.Migration.AnalyzeV1Structure()
    OGRH.Msg(string.format("Found %d raids, %d encounters", 
        table.getn(analysis.raids), analysis.totalEncounters))
    
    if table.getn(analysis.encountersWithSpaces) > 0 then
        OGRH.Msg(string.format("Found %d encounters with spaces in name (will be fixed)", 
            table.getn(analysis.encountersWithSpaces)))
    end
    
    -- Step 2: Build index mapping
    local mapping = OGRH.Migration.BuildIndexMapping()
    
    -- Step 3: Migrate roles structure (adds column field, nests in encounters)
    OGRH.Migration.MigrateRolesToV2(mapping)
    
    -- Step 4: Migrate all assignment tables
    local migrations = OGRH.Migration.MigrateAllAssignmentTables(mapping)
    
    -- Step 5: Apply migrations (store in v2 namespace)
    if not OGRH_SV.v2 then OGRH_SV.v2 = {} end
    
    OGRH_SV.v2.encounterAssignments = migrations.encounterAssignments
    OGRH_SV.v2.encounterAssignmentNumbers = migrations.encounterAssignmentNumbers
    OGRH_SV.v2.encounterRaidMarks = migrations.encounterRaidMarks
    OGRH_SV.v2.encounterAnnouncements = migrations.encounterAnnouncements
    
    -- Step 6: Copy migrated encounterMgmt to v2
    OGRH_SV.v2.encounterMgmt = OGRH.DeepCopy(OGRH_SV.encounterMgmt)
    
    -- Step 7: Mark migration complete
    OGRH_SV.v2.migrationDate = date("%Y-%m-%d %H:%M:%S")
    OGRH_SV.v2.schemaVersion = 2
    
    OGRH.Msg("v2 migration complete! Use /ogrh migration validate to verify.")
end
```

---

## UI Helper Functions

Since roles now have a `column` field, here are helpers for UI code:

```lua
-- Get roles for a specific column
function OGRH.SVM.GetRolesByColumn(raidIndex, encounterIndex, columnNum)
    if not OGRH_SV.v2 or 
       not OGRH_SV.v2.encounterMgmt or
       not OGRH_SV.v2.encounterMgmt.raids[raidIndex] or
       not OGRH_SV.v2.encounterMgmt.raids[raidIndex].encounters[encounterIndex] then
        return {}
    end
    
    local roles = OGRH_SV.v2.encounterMgmt.raids[raidIndex].encounters[encounterIndex].roles
    local columnRoles = {}
    
    for roleIdx, role in ipairs(roles) do
        if role.column == columnNum then
            table.insert(columnRoles, {
                index = roleIdx,
                role = role
            })
        end
    end
    
    -- Sort by sortOrder
    table.sort(columnRoles, function(a, b)
        return (a.role.sortOrder or 999) < (b.role.sortOrder or 999)
    end)
    
    return columnRoles
end

-- Example UI usage:
function OGRH.EncounterMgmt.RenderRoleColumns(raidIdx, encIdx)
    -- Render left column
    local column1Roles = OGRH.SVM.GetRolesByColumn(raidIdx, encIdx, 1)
    for _, roleData in ipairs(column1Roles) do
        local roleIdx = roleData.index
        local role = roleData.role
        -- Render role in left column
        RenderRole(role, roleIdx, 1)
    end
    
    -- Render right column
    local column2Roles = OGRH.SVM.GetRolesByColumn(raidIdx, encIdx, 2)
    for _, roleData in ipairs(column2Roles) do
        local roleIdx = roleData.index
        local role = roleData.role
        -- Render role in right column
        RenderRole(role, roleIdx, 2)
    end
end
```

---

## What Needs to be Redone

### ✅ Already Complete (Still Valid)

1. **SavedVariablesManager Core** (634 lines)
   - Status: ✅ Core logic is solid
   - Action: Minor updates needed for better numeric path handling
   
2. **Integrated Sync System**
   - Status: ✅ Sync routing, batching, permission checks all work
   - Action: No changes needed
   
3. **Test Suite** (23 tests)
   - Status: ✅ Tests pass for SVM core
   - Action: Add new tests for lookup functions
   
4. **Documentation Fixes**
   - Status: ✅ Priority values, permission checks documented
   - Action: Update with new schema

### ⚠️ Needs Updates

5. **SVM Path Handling**
   - Current: Works but could be more robust with numeric indices
   - Action: Add validation that paths are all numeric after first key
   
6. **Migration Scripts**
   - Current: Partially defined, not tested with new schema
   - Action: Complete migration functions above, test thoroughly

### ❌ Needs Complete Redo

7. **EncounterMgmt.lua Write Conversions**
   - Status: ❌ Converted using v1 schema (name-based keys)
   - Action: **REDO with index lookups**
   - Lines: 2420-2456 (drag-drop), 3298-3377 (swaps), 155/3418 (clear)
   
8. **Phase 2 Write Migration**
   - Status: ❌ Only started, blocked by schema issues
   - Action: **RESTART after v2 schema finalized**

### 📋 New Work Required

9. **Index Lookup System**
   - Status: ❌ Not implemented
   - Action: Create OGRH.SVM.Lookup namespace with functions above
   
10. **Migration Testing**
    - Status: ❌ Not done
    - Action: Test migration with real SavedVariables data
    
11. **Validation System**
    - Status: ❌ Not implemented
    - Action: Create validation to ensure v1 and v2 have same data
    
12. **Cutover Logic**
    - Status: ❌ Not implemented
    - Action: Switch reads/writes from v1 to v2 when ready

---

## Implementation Timeline

### Week 2, Day 1-2: Schema Foundation
- ✅ Create this design document
- [ ] Implement index lookup functions
- [ ] Add lookup tests to test suite
- [ ] Update SVM path validation for numeric indices

### Week 2, Day 3: Migration System
- [ ] Implement analysis functions
- [ ] Implement mapping builder
- [ ] Implement migration functions
- [ ] Test with sample data

### Week 2, Day 4: Validation & Testing
- [ ] Create validation system (v1 vs v2 comparison)
- [ ] Test migration with multiple SavedVariables files
- [ ] Fix any migration bugs
- [ ] Document migration process

### Week 2, Day 5: Write Conversion Redo
- [ ] Redo EncounterMgmt.lua conversions with lookups
- [ ] Convert remaining Phase 2 files
- [ ] Test all conversions with v2 schema

### Week 2, Day 6-7: Integration Testing
- [ ] Test full workflow with v2 schema
- [ ] Test sync with v2 indices
- [ ] Verify all write locations work
- [ ] Performance testing

---

## Success Criteria

- ✅ All encounter names can have spaces, special characters
- ✅ SetPath() works with all encounter names
- ✅ Users can rename encounters without breaking data
- ✅ Migration preserves 100% of v1 data
- ✅ Validation confirms v1 and v2 match
- ✅ All writes use v2 schema with indices
- ✅ Sync works correctly with numeric paths
- ✅ No "forgot to lookup index" bugs

---

## Next Steps

1. **Review this design** - Get user approval before implementing
2. **Implement lookup system** - Foundation for all v2 work
3. **Test migration** - Ensure no data loss
4. **Redo Phase 2 conversions** - Use new schema
5. **Continue project** - Resume Phase 2 with confidence
