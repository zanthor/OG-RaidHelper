# EncounterMgmt Structure Comparison

## Current Structure (Dual Storage with Mismatched Keys)

### Current: Data Split Across Two Locations

```lua
-- LOCATION 1: Roles stored by STRING KEYS
OGRH_SV.encounterMgmt.roles = {
    ["BWL"] = {
        ["Razorgore"] = {
            column1 = {
                [1] = {
                    roleId = 1,
                    name = "Main Tank",
                    slots = 1,
                    fillOrder = 1,
                    defaultRoles = {
                        tanks = 1
                    },
                    showRaidIcons = 1,
                    classPriority = {
                        [1] = {
                            [1] = "Warrior"
                        }
                    },
                    classPriorityRoles = {
                        [1] = {
                            ["Warrior"] = {
                                ["Tanks"] = true
                            }
                        }
                    }
                },
                [2] = {
                    roleId = 2,
                    name = "Orb Clickers",
                    slots = 4,
                    fillOrder = 2,
                    defaultRoles = {
                        melee = 1,
                        ranged = 1
                    },
                    showAssignment = 1
                }
            },
            column2 = {
                [1] = {
                    roleId = 3,
                    name = "Dragonkin Tanks",
                    slots = 2,
                    fillOrder = 3,
                    defaultRoles = {
                        tanks = 1
                    },
                    showRaidIcons = 1
                }
            }
        },
        ["Vael"] = {
            column1 = {
                [1] = {
                    roleId = 1,
                    name = "Main Tank",
                    slots = 1,
                    fillOrder = 1,
                    defaultRoles = {
                        tanks = 1
                    },
                    showRaidIcons = 1
                },
                [2] = {
                    roleId = 2,
                    name = "Tank #2",
                    slots = 1,
                    fillOrder = 2,
                    defaultRoles = {
                        tanks = 1
                    },
                    showRaidIcons = 1
                }
            },
            column2 = {}
        }
    }
}

-- LOCATION 2: Raid/Encounter metadata stored by ARRAY INDICES
OGRH_SV.encounterMgmt.raids = {
    [1] = {
        name = "MC",
        encounters = {
            [1] = {
                name = "Lucifron",
                advancedSettings = {
                    bigwigs = {
                        enabled = 1,
                        encounterId = "Lucifron",
                        encounterIds = {
                            [1] = "Lucifron"
                        },
                        autoAnnounce = 1
                    },
                    consumeTracking = {
                        enabled = 1,
                        readyThreshold = 85,
                        requiredFlaskRoles = {
                            ["Tanks"] = false,
                            ["Healers"] = false,
                            ["Melee"] = false,
                            ["Ranged"] = false
                        }
                    }
                }
            },
            -- ... 11 more encounters
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
    [2] = {
        name = "BWL",
        encounters = {
            [1] = {
                -- NO ROLES HERE! They're in encounterMgmt.roles["BWL"]["Razorgore"]
                name = "Razorgore",
                advancedSettings = {
                    bigwigs = {
                        enabled = 1,
                        encounterId = "Razorgore the Untamed",
                        encounterIds = {
                            [1] = "Razorgore the Untamed"
                        },
                        autoAnnounce = 1
                    },
                    consumeTracking = {
                        enabled = 1,
                        readyThreshold = 85,
                        requiredFlaskRoles = {
                            ["Tanks"] = false,
                            ["Healers"] = false,
                            ["Melee"] = false,
                            ["Ranged"] = false
                        }
                    }
                }
            },
            [2] = {
                -- NO ROLES HERE! They're in encounterMgmt.roles["BWL"]["Vael"]
                name = "Vael",
                advancedSettings = {
                    bigwigs = {
                        enabled = 1,
                        encounterId = "Vaelastrasz the Corrupt",
                        encounterIds = {
                            [1] = "Vaelastrasz the Corrupt"
                        },
                        autoAnnounce = 1
                    },
                    consumeTracking = {
                        enabled = 1,
                        readyThreshold = 85,
                        requiredFlaskRoles = {
                            ["Tanks"] = false,
                            ["Healers"] = false,
                            ["Melee"] = false,
                            ["Ranged"] = false
                        }
                    }
                }
            },
            -- ... 12 more encounters
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
}
```

### Problem: To Sync ONE Encounter

```lua
-- Want to sync just Razorgore changes
-- PROBLEM: Can't send roles["BWL"]["Razorgore"] alone - no context!
-- MUST send:
{
    roles = OGRH_SV.encounterMgmt.roles["BWL"],  -- ALL 14 BWL encounters!
    raids = {
        [2] = OGRH_SV.encounterMgmt.raids[2]     -- Entire BWL raid object
    }
}
-- Result: ~1,400 lines sent instead of ~100 for one encounter
```

---

## Proposed Structure (Nested, Single Location)

### Proposed: Roles Stored INSIDE Encounter Objects

```lua
OGRH_SV.encounterMgmt.raids = {
    [1] = {
        name = "MC",
        encounters = {
            [1] = {
                name = "Lucifron",
                -- ROLES STORED HERE NOW
                roles = {
                    column1 = {
                        [1] = {
                            roleId = 1,
                            name = "Main Tank",
                            slots = 1,
                            fillOrder = 1,
                            defaultRoles = {tanks = 1},
                            showRaidIcons = 1
                        },
                        [2] = {
                            roleId = 2,
                            name = "Decursers",
                            slots = 4,
                            fillOrder = 2,
                            defaultRoles = {healers = 1},
                            classPriority = {
                                [1] = {[1] = "Mage"},
                                [2] = {[1] = "Mage"},
                                [3] = {[1] = "Druid"},
                                [4] = {[1] = "Druid"}
                            }
                        }
                    },
                    column2 = {}
                },
                advancedSettings = {
                    bigwigs = {
                        enabled = 1,
                        encounterId = "Lucifron",
                        encounterIds = {[1] = "Lucifron"},
                        autoAnnounce = 1
                    },
                    consumeTracking = {
                        enabled = 1,
                        readyThreshold = 85,
                        requiredFlaskRoles = {
                            ["Tanks"] = false,
                            ["Healers"] = false,
                            ["Melee"] = false,
                            ["Ranged"] = false
                        }
                    }
                }
            },
            -- ... 11 more encounters
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
                raidZones = {[1] = "Molten Core", [2] = "MC"}
            }
        }
    },
    [2] = {
        name = "BWL",
        encounters = {
            [1] = {
                name = "Razorgore",
                -- ROLES STORED HERE NOW
                roles = {
                    column1 = {
                        [1] = {
                            roleId = 1,
                            name = "Main Tank",
                            slots = 1,
                            fillOrder = 1,
                            defaultRoles = {tanks = 1},
                            showRaidIcons = 1,
                            classPriority = {
                                [1] = {[1] = "Warrior"}
                            },
                            classPriorityRoles = {
                                [1] = {
                                    ["Warrior"] = {["Tanks"] = true}
                                }
                            }
                        },
                        [2] = {
                            roleId = 2,
                            name = "Orb Clickers",
                            slots = 4,
                            fillOrder = 2,
                            defaultRoles = {melee = 1, ranged = 1},
                            showAssignment = 1
                        }
                    },
                    column2 = {
                        [1] = {
                            roleId = 3,
                            name = "Dragonkin Tanks",
                            slots = 2,
                            fillOrder = 3,
                            defaultRoles = {tanks = 1},
                            showRaidIcons = 1
                        }
                    }
                },
                advancedSettings = {
                    bigwigs = {
                        enabled = 1,
                        encounterId = "Razorgore the Untamed",
                        encounterIds = {[1] = "Razorgore the Untamed"},
                        autoAnnounce = 1
                    },
                    consumeTracking = {
                        enabled = 1,
                        readyThreshold = 85,
                        requiredFlaskRoles = {
                            ["Tanks"] = false,
                            ["Healers"] = false,
                            ["Melee"] = false,
                            ["Ranged"] = false
                        }
                    }
                }
            },
            [2] = {
                name = "Vael",
                -- ROLES STORED HERE NOW
                roles = {
                    column1 = {
                        [1] = {
                            roleId = 1,
                            name = "Main Tank",
                            slots = 1,
                            fillOrder = 1,
                            defaultRoles = {tanks = 1},
                            showRaidIcons = 1
                        },
                        [2] = {
                            roleId = 2,
                            name = "Tank #2",
                            slots = 1,
                            fillOrder = 2,
                            defaultRoles = {tanks = 1},
                            showRaidIcons = 1
                        }
                    },
                    column2 = {}
                },
                advancedSettings = {
                    bigwigs = {
                        enabled = 1,
                        encounterId = "Vaelastrasz the Corrupt",
                        encounterIds = {[1] = "Vaelastrasz the Corrupt"},
                        autoAnnounce = 1
                    },
                    consumeTracking = {
                        enabled = 1,
                        readyThreshold = 85,
                        requiredFlaskRoles = {
                            ["Tanks"] = false,
                            ["Healers"] = false,
                            ["Melee"] = false,
                            ["Ranged"] = false
                        }
                    }
                }
            },
            -- ... 12 more encounters
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
                raidZones = {[1] = "Blackwing Lair"}
            }
        }
    }
}
```

### Solution: To Sync ONE Encounter

```lua
-- Want to sync just Razorgore changes
-- SOLUTION: Send only the encounter object itself
{
    raidIndex = 2,
    encounterIndex = 1,
    encounter = OGRH_SV.encounterMgmt.raids[2].encounters[1]  -- Contains everything!
}
-- Result: ~100 lines sent (encounter is complete atomic unit)
-- Recipient: raids[2].encounters[1] = receivedData.encounter
```

---

## Code Access Comparison

### Current Access Pattern (Dual Lookup)

```lua
-- Get encounter metadata
local raid = OGRH_SV.encounterMgmt.raids[2]
local encounter = raid.encounters[1]
local encounterName = encounter.name  -- "Razorgore"
local raidName = raid.name           -- "BWL"

-- Get encounter roles (SEPARATE TABLE!)
local roles = OGRH_SV.encounterMgmt.roles[raidName][encounterName]
local mainTankRole = roles.column1[1]

-- Problem: Two separate lookups, must maintain string keys
```

### Proposed Access Pattern (Direct)

```lua
-- Get everything in one place
local raid = OGRH_SV.encounterMgmt.raids[2]
local encounter = raid.encounters[1]
local encounterName = encounter.name  -- "Razorgore"
local roles = encounter.roles         -- RIGHT HERE!
local mainTankRole = roles.column1[1]
local settings = encounter.advancedSettings

-- Solution: Single object, direct access, atomic sync
```

---

## Network Sync Size Comparison

### Current Structure
```
Syncing Razorgore role changes:
├─ Must send: encounterMgmt.roles["BWL"] (all 14 encounters)
├─ Must send: encounterMgmt.raids[2] (for context)
└─ Total: ~1,400 lines

Syncing all BWL encounters:
├─ Must send: encounterMgmt.roles["BWL"]
├─ Must send: encounterMgmt.raids[2]
└─ Total: ~1,400 lines (same as one encounter!)
```

### Proposed Structure
```
Syncing Razorgore role changes:
├─ Send: raids[2].encounters[1]
└─ Total: ~100 lines

Syncing all BWL encounters:
├─ Send: raids[2] (includes all encounters with roles)
└─ Total: ~1,400 lines (only when actually needed)
```

---

## Migration Code Example

```lua
function OGRH.MigrateEncounterMgmtToV2()
    if not OGRH_SV.encounterMgmt then return end
    
    -- Check if already migrated
    if OGRH_SV.encounterMgmt.schemaVersion and 
       OGRH_SV.encounterMgmt.schemaVersion >= 2 then
        return -- Already migrated
    end
    
    -- Backup old structure
    if not OGRH_SV._backups then OGRH_SV._backups = {} end
    OGRH_SV._backups.encounterMgmt_v1 = {
        roles = OGRH.DeepCopy(OGRH_SV.encounterMgmt.roles),
        timestamp = time()
    }
    
    -- Migrate roles into encounter objects
    if OGRH_SV.encounterMgmt.raids and OGRH_SV.encounterMgmt.roles then
        for raidIdx, raid in ipairs(OGRH_SV.encounterMgmt.raids) do
            local raidName = raid.name
            
            if raid.encounters and OGRH_SV.encounterMgmt.roles[raidName] then
                for encIdx, encounter in ipairs(raid.encounters) do
                    local encounterName = encounter.name
                    
                    -- Move roles from separate table into encounter
                    if OGRH_SV.encounterMgmt.roles[raidName][encounterName] then
                        encounter.roles = OGRH_SV.encounterMgmt.roles[raidName][encounterName]
                    else
                        -- Initialize empty if no roles exist
                        encounter.roles = {column1 = {}, column2 = {}}
                    end
                end
            end
        end
        
        -- Remove old roles table
        OGRH_SV.encounterMgmt.roles = nil
    end
    
    -- Mark as migrated
    OGRH_SV.encounterMgmt.schemaVersion = 2
    
    OGRH.Msg("EncounterMgmt migrated to v2 schema")
end
```

---

## Summary

| Aspect | Current | Proposed | Benefit |
|--------|---------|----------|---------|
| Storage | Dual (roles separate) | Single (roles nested) | Simpler |
| Sync 1 encounter | ~1,400 lines | ~100 lines | 93% smaller |
| Access pattern | 2 lookups (string keys) | 1 lookup (direct) | Faster |
| Bug prevention | Easy to send wrong scope | Atomic units | Safer |
| Code locations | ~30 to update | - | One-time migration |
