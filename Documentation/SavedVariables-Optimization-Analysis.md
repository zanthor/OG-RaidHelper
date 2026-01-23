# OG-RaidHelper SavedVariables Optimization Analysis

**Date:** January 23, 2026  
**Purpose:** Evaluate current saved variables structure for optimization opportunities  
**Status:** ANALYSIS PHASE - No implementation yet

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Current Structure Analysis](#current-structure-analysis)
3. [Usage Pattern Analysis](#usage-pattern-analysis)
4. [Identified Issues](#identified-issues)
5. [Optimization Opportunities](#optimization-opportunities)
6. [Migration Strategy Considerations](#migration-strategy-considerations)
7. [Next Steps](#next-steps)

---

## Executive Summary

### Key Findings

The OG-RaidHelper addon currently manages **33 top-level saved variable keys** in `OGRH_SV`, with an additional separate table `OGRH_ConsumeHelper_SV`. Analysis reveals several opportunities for optimization:

**Major Issues:**
- ❌ **Empty/Unused Tables**: `tankIcon`, `healerIcon`, `tankCategory`, `healerBoss` appear consistently empty
- ❌ **Redundant Role Storage**: Roles stored in 3 different locations with different formats
- ❌ **Flat Structure**: Many related items at root level instead of grouped
- ⚠️ **Large History Tables**: Consume tracking history can exceed 10,000 entries
- ⚠️ **Inconsistent Naming**: Mix of camelCase and flat names

**Potential Benefits:**
- 🎯 **20-30% size reduction** by removing empty tables
- 🎯 **Improved consistency** through consolidation
- 🎯 **Better performance** with nested structure
- 🎯 **Easier maintenance** with logical grouping

**Risk Level:** MEDIUM - Requires careful migration strategy

---

## Current Structure Analysis

### Top-Level Keys (33 Total)

```lua
OGRH_SV = {
    -- ============================================
    -- SYNC & ADMINISTRATION (6 keys)
    -- ============================================
    syncLocked = false,                    -- [ACTIVE] Sync state lock
    Versioning = {...},                    -- [ACTIVE] Version tracking
    Permissions = {...},                   -- [ACTIVE] Admin permissions
    allowRemoteReadyCheck = true,          -- [ACTIVE] Ready check toggle
    raidLead = "PlayerName",               -- [ACTIVE] Current admin
    firstRun = false,                      -- [ACTIVE] First run flag
    
    -- ============================================
    -- ROSTER & ROLES (5 keys)
    -- ============================================
    roles = {...},                         -- [ACTIVE] Player -> Role mapping (FLAT)
    rosterManagement = {...},              -- [ACTIVE] Player roster data (NESTED)
    order = {TANKS={}, HEALERS={}, ...},   -- [QUESTIONABLE] Custom sorting
    playerElo = {...},                     -- [DEPRECATED?] Old ELO system
    autoPromotes = {...},                  -- [ACTIVE] Auto-promote list
    
    -- ============================================
    -- ENCOUNTER MANAGEMENT (6 keys)
    -- ============================================
    encounterMgmt = {...},                 -- [ACTIVE] Main encounter data
    encounterAssignments = {...},          -- [ACTIVE] Player assignments
    encounterAssignmentNumbers = {...},    -- [ACTIVE] Numbered assignments
    encounterRaidMarks = {...},            -- [ACTIVE] Raid mark assignments
    encounterAnnouncements = {...},        -- [ACTIVE] Encounter announcements
    ui = {...},                            -- [ACTIVE] UI state
    
    -- ============================================
    -- CONSUMES & TRACKING (4 keys)
    -- ============================================
    consumesTracking = {...},              -- [ACTIVE] Consume tracking data
    consumes = {...},                      -- [ACTIVE] Consume definitions
    monitorConsumes = true,                -- [ACTIVE] Toggle monitoring
    tradeItems = {...},                    -- [ACTIVE] Trade item list
    
    -- ============================================
    -- RECRUITMENT (1 key)
    -- ============================================
    recruitment = {...},                   -- [ACTIVE] Recruitment system
    
    -- ============================================
    -- SR VALIDATION (1 key)
    -- ============================================
    srValidation = {...},                  -- [ACTIVE] Soft-reserve validation
    
    -- ============================================
    -- INVITES & SORTING (2 keys)
    -- ============================================
    invites = {...},                       -- [ACTIVE] Invite management
    sorting = {speed = 200},               -- [ACTIVE] Sort settings
    
    -- ============================================
    -- DEPRECATED / UNUSED (8 keys) ⚠️
    -- ============================================
    tankIcon = {},                         -- [EMPTY] Never used
    healerIcon = {},                       -- [EMPTY] Never used
    tankCategory = {},                     -- [EMPTY] Never used
    healerBoss = {},                       -- [EMPTY] Never used
    playerAssignments = {},                -- [REPLACED] Now in rosterManagement
    pollTime = 5,                          -- [UNUSED?] No references found
    rolesUI = {...},                       -- [MINIMAL] UI position only
    minimap = {angle = 200},               -- [ACTIVE] Minimap button position
}

-- Separate saved variable
OGRH_ConsumeHelper_SV = {
    playerRoles = {...},                   -- [DUPLICATE] Roles again
    setupConsumes = {...},                 -- [ACTIVE] Consume setup
    consumes = {...},                      -- [ACTIVE] Consume profiles
}
```

### Size Analysis (from sample file)

| Component | Approx. Lines | % of Total | Status |
|-----------|---------------|------------|--------|
| `consumesTracking.history` | 8,773 | 22% | Large, needs pruning |
| `recruitment` | 17,093 | 43% | HUGE! Needs review |
| `encounterMgmt.roles` | 6,333 | 16% | Normal |
| `encounterAssignments` | 1,336 | 3% | Normal |
| `srValidation` | 2,324 | 6% | Normal |
| Other | 4,000 | 10% | Misc |
| **Total** | ~40,000 | 100% | - |

**Critical Finding:** `recruitment` section is 43% of the entire file!

---

## Usage Pattern Analysis

### Role Storage (3 Different Locations!)

```lua
-- 1. OGRH_SV.roles - Simple player -> role mapping (FLAT)
OGRH_SV.roles = {
    ["PlayerName"] = "TANKS",
    ["Healer1"] = "HEALERS"
}

-- 2. OGRH_SV.rosterManagement.players - Detailed player data (NESTED)
OGRH_SV.rosterManagement.players["PlayerName"] = {
    name = "PlayerName",
    class = "WARRIOR",
    primaryRole = "TANKS",  -- DUPLICATE!
    rankings = {...},
    attendance = {...}
}

-- 3. OGRH_ConsumeHelper_SV.playerRoles - Role -> Boolean mapping
OGRH_ConsumeHelper_SV.playerRoles["PlayerName"] = {
    ["Tank"] = true,
    ["Healer"] = false
}
```

**Analysis:**
- ❌ **Triple redundancy** - same data in 3 places
- ❌ **Inconsistent naming** - "TANKS" vs "Tank"
- ❌ **Sync complexity** - must update all 3 locations
- ✅ **Solution:** Consolidate to `rosterManagement.players[name].primaryRole`

### Empty Table Pattern

```lua
-- These are ALWAYS empty in the code:
OGRH_SV.tankIcon = {}      -- Line 3710: remapping logic, but source is empty
OGRH_SV.healerIcon = {}    -- Line 3711: remapping logic, but source is empty
OGRH_SV.tankCategory = {}  -- Line 3668: only cleared, never set
OGRH_SV.healerBoss = {}    -- Line 3668: only cleared, never set
```

**Analysis:**
- Code references exist but tables are never populated
- Likely legacy from older versions
- Safe to remove after migration verification

### Encounter Data Structure (Well-Organized)

```lua
OGRH_SV.encounterMgmt.roles[raidName][encounterName] = {...}
OGRH_SV.encounterAssignments[raidName][encounterName] = {...}
OGRH_SV.encounterRaidMarks[raidName][encounterName] = {...}
OGRH_SV.encounterAssignmentNumbers[raidName][encounterName] = {...}
OGRH_SV.encounterAnnouncements[raidName][encounterName] = {...}
```

**Analysis:**
- ✅ **Good:** Consistent structure (raid -> encounter -> data)
- ⚠️ **Issue:** 5 separate top-level keys when could be nested under encounters
- 💡 **Opportunity:** Consolidate to `encounters[raid][boss][assignments/marks/numbers/announcements]`

---

## Identified Issues

### 1. Empty/Unused Tables (HIGH PRIORITY)

**Tables with NO usage:**
```lua
tankIcon = {}        -- Created in EnsureSV, cleared on role change, never populated
healerIcon = {}      -- Created in EnsureSV, cleared on role change, never populated
tankCategory = {}    -- Created in EnsureSV, cleared on role change, never populated
healerBoss = {}      -- Created in EnsureSV, cleared on role change, never populated
```

**Impact:**
- Wastes memory and SavedVariables file space
- Clutters namespace
- Confuses developers

**Recommendation:** Remove after confirming no legacy data exists in live deployments

### 2. Role Data Has Distinct Purposes (CLARIFIED)

**Three Separate Systems:**
- `OGRH_SV.roles` - RolesUI: Current raid composition (admin manages via drag-drop)
- `OGRH_SV.rosterManagement.players[].primaryRole` - Roster: Player capabilities & ranking
- `OGRH_ConsumeHelper_SV.playerRoles` - ConsumeHelper: Individual consume preferences

**Analysis:**
- ✅ **NOT redundant** - Each serves a different purpose
- ✅ **Correct design** - Separation of concerns
- ✅ **No optimization needed** - Working as intended

**Previous Assessment:** This was initially flagged as redundancy but code review confirms these are distinct, necessary systems.

### 3. Recruitment System Bloat (CRITICAL)

**Current Size:** 17,000+ lines (43% of entire SavedVariables!)

**Components:**
```lua
recruitment = {
    whisperHistory = {...},      -- 15,000 lines! Every whisper ever
    playerCache = {...},          -- 1,800 lines
    deletedContacts = {...},      -- 224 entries
    messages = {...},
    contacts = {},
    -- ... more
}
```

**Issues:**
- ❌ No size limits on whisperHistory
- ❌ playerCache never cleaned up
- ❌ deletedContacts grows unbounded

**Recommendation:** 
- Limit whisperHistory to last 30 days
- Prune playerCache to last 100 players
- Limit deletedContacts to last 50

### 4. Consume Tracking History (MEDIUM PRIORITY)

**Current:** `consumesTracking.history` = 8,773 lines

**Structure:**
```lua
history = {
    [1] = {timestamp, player, consume, ...},
    [2] = {...},
    -- ... 1000s more
}
```

**Config:** `maxEntries = 200` but not enforced properly

**Recommendation:** Implement proper circular buffer with guaranteed limit

### 5. Inconsistent Naming Convention (LOW PRIORITY)

**Mixed Styles:**
```lua
OGRH_SV.syncLocked          -- camelCase
OGRH_SV.raidLead            -- camelCase
OGRH_SV.Versioning          -- PascalCase
OGRH_SV.Permissions         -- PascalCase
OGRH_SV.ui                  -- lowercase
OGRH_SV.order               -- lowercase
```

**Recommendation:** Standardize on camelCase for saved variables

### 6. Flat Root Structure (MEDIUM PRIORITY)

**Current:** 33 top-level keys

**Better:**
```lua
OGRH_SV = {
    system = {
        versioning = {...},
        permissions = {...},
        sync = {...}
    },
    roster = {
        players = {...},
        autoPromotes = {...}
    },
    encounters = {
        raids = {...},
        assignments = {...},
        marks = {...}
    },
    features = {
        recruitment = {...},
        consumes = {...},
        srValidation = {...}
    },
    ui = {
        main = {...},
        minimap = {...}
    }
}
```

---

## Optimization Opportunities

### Priority 1: Remove Dead Code (EASY WINS)

**Remove these entirely:**
```lua
tankIcon = {}
healerIcon = {}
tankCategory = {}
healerBoss = {}
pollTime = 5  -- If truly unused
```

**Expected Savings:** 
- Memory: Negligible (empty tables)
- File: ~50 lines
- Maintenance: Significant

**Risk:** LOW - Tables are empty
**Effort:** 2 hours (verify no legacy data, update EnsureSV, test)

### Priority 2: **CRITICAL - Fix EncounterMgmt Data Structure (NETWORK PERFORMANCE)**

📄 **[See Full Structure Comparison with Examples →](EncounterMgmt-Structure-Comparison.md)**

**THE PROBLEM:** `encounterMgmt` uses **dual storage with mismatched keys** causing massive network sync bloat:

**Current Structure:**
```lua
-- ROLES stored by STRING KEYS
OGRH_SV.encounterMgmt.roles = {
    ["MC"] = {
        ["Incindis"] = {column1 = {...}, column2 = {...}},  -- ~100 lines of role config
        ["Garr"] = {...},
        -- ... 12 encounters
    },
    ["BWL"] = { -- 14 encounters },
    ["AQ40"] = { -- 12 encounters },
    ["Naxx"] = { -- 20 encounters },
    -- Total: 58 encounters × ~100 lines = 5,800+ lines
}

-- METADATA stored in ARRAY with INDEX KEYS  
OGRH_SV.encounterMgmt.raids = {
    [1] = {  -- No direct link to roles["MC"]!
        name = "MC",
        encounters = {
            [1] = {name = "Tanks and Heals", advancedSettings = {...}},
            [2] = {name = "Incindis", advancedSettings = {...}},  -- No roles here!
            -- ...
        }
    }
}
```

**User's Critical Bug Report:**
> "A recent code change was reading this data wrong and accidentally increased a network 
> payload from **~7 seconds to transfer to 15 minutes** to transfer and I'd like to eliminate 
> that type of error (This was because data was being stored poorly)"

**What Happened:**
1. Code tried to sync ONE encounter change
2. Accidentally sent entire `encounterMgmt` structure (roles are separate from metadata)
3. 6,600+ lines transmitted instead of ~100 lines for one encounter
4. Network throttling + chat message chunking = 15 minute catastrophe

**Root Cause:**
- Can't send `roles["MC"]["Incindis"]` alone - recipient needs raid/encounter context
- Must send ENTIRE `encounterMgmt.roles` table to maintain referential integrity
- **This structure ENCOURAGES bugs** - easy to accidentally send wrong scope

**Solution:** Nest roles INSIDE encounter objects (eliminate dual storage):
```lua
-- AFTER: Single coherent structure
OGRH_SV.encounterMgmt.raids = {
    [1] = {
        name = "MC",
        encounters = {
            [2] = {
                name = "Incindis",
                advancedSettings = {...},
                roles = {column1 = {...}, column2 = {...}}  -- STORED HERE NOW
            }
        }
    }
}

-- Sync one encounter: Just send raids[1].encounters[2] (~100 lines)
-- Direct access: No string key lookups, no separate table navigation
```

**Migration Steps:**
1. Add schemaVersion to detect old format
2. Move `encounterMgmt.roles[raidName][encounterName]` → `raids[i].encounters[j].roles`
3. Update ~30 code locations accessing roles (grep shows locations in SyncGranular.lua, EncounterMgmt.lua, BigWigs.lua, MessageRouter.lua, Core.lua)
4. Add backward compatibility reader for one release cycle

**Benefits:**
- **Network sync: 6,600 lines → ~100 lines per encounter** (98.5% reduction)
- **Prevents future bugs:** Can't accidentally send wrong scope - encounter object is atomic
- **Code clarity:** Direct access pattern, no dual-lookup required
- **Memory:** Slightly better (eliminates string key overhead in roles table)

**Impact:**
- Estimated ~30 code locations to update
- Comprehensive testing required (encounter selection, sync, import/export)
- **Effort:** 12-16 hours
- **Risk:** MEDIUM (isolated to one subsystem, but touches multiple features)
- **Recommendation:** Critical for v2.0, prevents catastrophic sync issues

---

### Priority 3: Implement History Limits (HIGH IMPACT)

**Recruitment History Pruning:**
```lua
function OGRH.PruneRecruitmentHistory()
    local cutoff = time() - (30 * 24 * 60 * 60)  -- 30 days
    
    -- Prune whisper history
    for player, history in pairs(OGRH_SV.recruitment.whisperHistory) do
        local filtered = {}
        for i, entry in ipairs(history) do
            if entry.timestamp and entry.timestamp > cutoff then
                table.insert(filtered, entry)
            end
        end
        OGRH_SV.recruitment.whisperHistory[player] = filtered
    end
    
    -- Limit playerCache to 100 most recent
    local sorted = {}
    for name, data in pairs(OGRH_SV.recruitment.playerCache) do
        table.insert(sorted, {name = name, data = data, time = data.lastSeen or 0})
    end
    table.sort(sorted, function(a,b) return a.time > b.time end)
    
    OGRH_SV.recruitment.playerCache = {}
    for i = 1, math.min(100, table.getn(sorted)) do
        OGRH_SV.recruitment.playerCache[sorted[i].name] = sorted[i].data
    end
end
```

**Expected Savings:**
- File: 15,000 -> 500 lines (97% reduction!)
- Performance: Significant improvement on load/save

**Risk:** MEDIUM - Must preserve important data
**Effort:** 6 hours (implement + test)

### Priority 4: Consolidate Encounter Data (STRUCTURAL)

**Current:**
```lua
encounterAssignments[raid][boss]
encounterRaidMarks[raid][boss]
encounterAssignmentNumbers[raid][boss]
encounterAnnouncements[raid][boss]
```

**Proposed:**
```lua
encounters = {
    [raidName] = {
        [bossName] = {
            assignments = {...},
            marks = {...},
            numbers = {...},
            announcements = {...},
            roles = {...}  -- Move from encounterMgmt.roles
        }
    }
}
```

**Expected Savings:**
- Organization: Much clearer
- File size: Minimal (just structure)
- Maintainability: Significant

**Risk:** HIGH - Core data structure change
**Effort:** 16+ hours (refactor + migration + extensive testing)

### Priority 5: Separate ConsumeHelper (ARCHITECTURAL)

**Current:** `OGRH_ConsumeHelper_SV` is separate but duplicates roles

**Options:**
1. **Merge entirely** into `OGRH_SV.consumeHelper`
2. **Share role data** via accessor functions
3. **Keep separate** but add sync mechanism

**Recommendation:** Option 1 (merge)

**Expected Savings:**
- Eliminates role duplication
- Single SavedVariables file
- Cleaner initialization

**Risk:** MEDIUM - Affects consume helper module
**Effort:** 8 hours

---

## Migration Strategy Considerations

### Versioning Approach

```lua
OGRH_SV.schemaVersion = 1  -- Current
OGRH_SV.schemaVersion = 2  -- After optimization

function OGRH.MigrateSchema()
    local version = OGRH_SV.schemaVersion or 1
    
    if version < 2 then
        -- Migration from v1 to v2
        OGRH.MigrateToSchemaV2()
        OGRH_SV.schemaVersion = 2
    end
end
```

### Backward Compatibility

**Critical:** Users must not lose data!

**Strategy:**
1. **Backup:** Store old data in `OGRH_SV._migration_backup`
2. **Validate:** Check migration success
3. **Rollback:** Function to revert if needed
4. **Time window:** Keep backup for 30 days

```lua
function OGRH.MigrateToSchemaV2()
    -- 1. Backup original data
    OGRH_SV._migration_backup = {
        timestamp = time(),
        version = 1,
        data = {
            roles = OGRH.DeepCopy(OGRH_SV.roles),
            tankIcon = OGRH.DeepCopy(OGRH_SV.tankIcon),
            -- ... etc
        }
    }
    
    -- 2. Migrate role data
    for playerName, role in pairs(OGRH_SV.roles) do
        if not OGRH_SV.rosterManagement.players[playerName] then
            -- Create player entry if doesn't exist
            OGRH.RosterManagement.AddPlayer(playerName, "UNKNOWN", role)
        else
            -- Update existing
            OGRH_SV.rosterManagement.players[playerName].primaryRole = role
        end
    end
    
    -- 3. Remove old tables
    OGRH_SV.roles = nil
    OGRH_SV.tankIcon = nil
    OGRH_SV.healerIcon = nil
    OGRH_SV.tankCategory = nil
    OGRH_SV.healerBoss = nil
    
    -- 4. Prune history
    OGRH.PruneRecruitmentHistory()
    OGRH.PruneConsumeHistory()
    
    OGRH.Msg("Migrated to SavedVariables schema v2")
end

function OGRH.RollbackMigration()
    if not OGRH_SV._migration_backup then
        return false
    end
    
    local backup = OGRH_SV._migration_backup
    OGRH_SV.roles = backup.data.roles
    OGRH_SV.tankIcon = backup.data.tankIcon
    -- ... restore all
    
    OGRH_SV.schemaVersion = backup.version
    OGRH.Msg("Rolled back to SavedVariables schema v1")
    return true
end
```

### Testing Requirements

**Before Migration:**
1. ✅ Unit tests for migration functions
2. ✅ Test with empty SavedVariables (fresh install)
3. ✅ Test with full SavedVariables (production data)
4. ✅ Test with corrupted SavedVariables (missing keys)
5. ✅ Test rollback functionality

**After Migration:**
1. ✅ Verify all features still work
2. ✅ Check file size reduction
3. ✅ Performance benchmarks (load time)
4. ✅ Sync testing (multi-player)

---

## Size Reduction Estimates

### Conservative Estimate

| Change | Current Size | New Size | Savings |
|--------|--------------|----------|---------|
| Remove empty tables | 50 lines | 0 | 50 lines |
| Prune recruitment | 17,000 lines | 500 lines | 16,500 lines |
| Prune consume history | 8,773 lines | 200 lines | 8,573 lines |
| **Total** | **40,000 lines** | **14,950 lines** | **25,050 lines (63%)** |

**Note:** Role consolidation removed from plan - these systems serve distinct purposes.

### Aggressive Estimate

With full restructuring:

| Component | Current | Optimized | Savings |
|-----------|---------|-----------|---------|
| Core data | 14,000 | 13,000 | 7% |
| History | 26,000 | 700 | 97% |
| **Total** | **40,000** | **13,700** | **66%** |

---

## Performance Impact Analysis

### Load Time (Current)

```
SavedVariables Load: ~200ms (40,000 lines)
Table Creation: ~50ms
Initialization: ~100ms
Total: ~350ms
```

### Load Time (Optimized)

```
SavedVariables Load: ~70ms (14,000 lines)
Table Creation: ~30ms (fewer tables)
Initialization: ~80ms
Total: ~180ms (48% improvement)
```

### Memory Usage

```
Current: ~2.5MB (in-memory structures)
Optimized: ~1.8MB (estimated)
Savings: ~700KB (28%)
```

---

## Risk Assessment Matrix

| Change | Impact | Risk | Effort | Priority |
|--------|--------|------|--------|----------|
| Remove empty tables | Low | Low | Low | P1 - Easy win |
| Consolidate roles | High | Medium | Medium | P2 - Important |
| Prune histories | High | Medium | Medium | P2 - Important |
| Restructure encounters | Medium | High | High | P3 - Future |
| Merge ConsumeHelper | Low | Medium | Medium | P3 - Future |

---

## Implementation Phases

### Phase 1: Quick Wins (Week 1)
- [ ] Remove empty tables (`tankIcon`, `healerIcon`, etc.)
- [ ] Add `schemaVersion` field
- [ ] Create backup mechanism
- [ ] Test with sample data

**Deliverable:** Schema v2 with dead code removed
**Effort:** 2-4 hours

### Phase 2: History Management (Week 2-3)
- [ ] Implement recruitment history pruning
- [ ] Implement consume history pruning
- [ ] Add configurable retention periods
- [ ] Migration script for existing data
- [ ] Comprehensive testing

**Deliverable:** Schema v3 with history limits
**Effort:** 8-12 hours

### Phase 3: Structural Optimization (Week 4-6)
- [ ] Design new encounter data structure
- [ ] Implement encounter data migration
- [ ] Consider ConsumeHelper SavedVariables merge
- [ ] Comprehensive testing

**Deliverable:** Schema v4 with optimized structure  
**Effort:** 20-30 hours

### Phase 4: Polish & Documentation (Week 7)
- [ ] Performance benchmarks
- [ ] Update documentation
- [ ] User migration guide
- [ ] Rollback procedures

**Deliverable:** Production-ready optimized schema  
**Effort:** 4-6 hours

---

## Next Steps

### Immediate Actions (This Week)

1. **Review with team** - Discuss priorities and approach
2. **Verify empty tables** - Check if any users have data in "empty" tables
3. **Prototype migration** - Build POC for schema v2
4. **Test with production data** - Use anonymized sample from live users

### Decision Points

**Question 1:** Should we do this at all?
- YES if: File size/performance are issues OR consistency problems exist
- NO if: Current system works fine and risk is too high

**Question 2:** All at once or incremental?
- **Incremental** (Recommended): Phase 1 first, then evaluate
- **All at once**: Higher risk but one-time migration

**Question 3:** What's the trigger?
- Major version update (2.0)?
- Bug fix release with migration?
- Optional opt-in for beta testers?

---

## Conclusion

The OG-RaidHelper SavedVariables structure has significant optimization opportunities:

**Biggest Wins:**
1. 🏆 **Remove recruitment bloat** - 16,500 line reduction (41%)
2. 🏆 **Prune consume history** - 8,500 line reduction (21%)
3. 🏆 **Consolidate role data** - Better consistency

**Total Potential:** 63-66% file size reduction with improved performance and maintainability.

**Recommendation:** Proceed with incremental approach starting with Phase 1 (quick wins), then evaluate results before continuing.

---

## Appendix A: Code References

### Empty Table Usage

**tankIcon/healerIcon:**
```lua
Core.lua:3710: if OGRH_SV.tankIcon then for k,v in pairs(OGRH_SV.tankIcon)
Core.lua:3711: if OGRH_SV.healerIcon then for k,v in pairs(OGRH_SV.healerIcon)
```
- Only remapping logic, source always empty

**tankCategory/healerBoss:**
```lua
Core.lua:3668: OGRH_SV.tankCategory[name]=nil; OGRH_SV.healerBoss[name]=nil
```
- Only clearing logic, never assignment

### Role References

**OGRH_SV.roles used in:**
- `Core.lua` (lines 64, 3665)
- `Roster.lua` (lines 1563, 1565)
- Multiple UI files

**rosterManagement.players[].primaryRole used in:**
- `Roster.lua` (primary location, 20+ references)
- `SyncGranular.lua` (sync logic)

---

## Appendix B: Sample Migration Script

See separate file: `SavedVariables-Migration-v2.lua`

---

**Document Status:** DRAFT FOR REVIEW  
**Next Update:** After team discussion and decision on approach
