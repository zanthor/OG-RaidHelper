# SavedVariables Optimization - Project Brief

**Project:** OG-RaidHelper SavedVariables Structure Optimization  
**Status:** Analysis Complete - Awaiting Decision  
**Date:** January 23, 2026

---

## Quick Summary

We've identified significant optimization opportunities in the OG-RaidHelper SavedVariables structure that could reduce file size by **63-66%** and improve performance by **~48%** load time reduction.

---

## The Problem

**Current State:**
- SavedVariables file: ~40,000 lines
- 33 top-level keys (many unused/redundant)
- Recruitment data: 43% of entire file (17,000 lines!)
- Consume history: 22% of file (8,773 lines)
- Triple-redundant role storage
- Empty tables that are never used

**Impact:**
- Slow load times (~350ms)
- High memory usage (~2.5MB)
- Difficult to maintain
- Sync conflicts due to redundancy

---

## The Solution (3-Phase Approach)

### Phase 1: Quick Wins (1 week)
**Remove dead code that provides no value:**
- Empty tables: `tankIcon`, `healerIcon`, `tankCategory`, `healerBoss`
- Add schema versioning system
- Create backup mechanism

**Benefits:**
- Minimal risk
- Clean up codebase
- Foundation for future work

**Effort:** 2-4 hours

### Phase 2: Data Consolidation (2-3 weeks)
**Fix bloat and implement limits:**
- Prune recruitment history (17,000 → 500 lines)
- Prune consume history (8,773 → 200 lines)
- Implement history limits
- Add automatic pruning on load

**Benefits:**
- 63% file size reduction
- Faster load times
- Prevents unbounded growth

**Effort:** 8-12 hours

### Phase 3: Structural Optimization (4-6 weeks)
**Optional: Restructure for long-term maintainability:**
- Group related data hierarchically
- Merge ConsumeHelper SavedVariables
- Optimize encounter data structure

**Benefits:**
- Easier to maintain
- Better organization
- Sets foundation for future features

**Effort:** 20-30 hours

---

## Key Findings

### 1. Recruitment System is HUGE
```
Current: 17,000 lines (43% of file!)
- whisperHistory: Every whisper ever received (15,000+)
- playerCache: 1,800 cached players
- deletedContacts: 224 deleted contacts

Optimized: 500 lines
- Last 30 days of whispers only
- 100 most recent players
- 50 recent deleted contacts

Savings: 97% reduction!
```

### 2. Empty Tables Serve No Purpose
```lua
OGRH_SV.tankIcon = {}       -- Always empty
OGRH_SV.healerIcon = {}     -- Always empty  
OGRH_SV.tankCategory = {}   -- Always empty
OGRH_SV.healerBoss = {}     -- Always empty
```
**Why?** Legacy code from old versions, never actually used.

### 3. Three Role Storage Systems (DISTINCT PURPOSES)
```lua
-- Current raid role assignment (dynamic, per-raid)
OGRH_SV.roles["Player"] = "TANKS"

-- Player capability roster (what roles they CAN fill)
OGRH_SV.rosterManagement.players["Player"].primaryRole = "TANKS"

-- Per-player consume preferences (individual, not admin-controlled)
OGRH_ConsumeHelper_SV.playerRoles["Player"]["Tank"] = true
```
**These serve DIFFERENT purposes:**
1. **`OGRH_SV.roles`** - RolesUI system for current raid composition (admin drag-drop interface)
2. **`rosterManagement.primaryRole`** - Player capability tracking for ranking/ELO system
3. **`ConsumeHelper_SV.playerRoles`** - Individual player's consume setup (per-raid basis, player-controlled)

**Note:** These are NOT redundant - they track different aspects of roles.

### 4. **CRITICAL: EncounterMgmt Data Structure Issue**

**The Problem:** Roles and metadata stored in TWO SEPARATE PLACES with mismatched keys:
```lua
-- Roles: STRING KEYS
encounterMgmt.roles["MC"]["Incindis"] = {role configs...}

-- Metadata: ARRAY INDICES
encounterMgmt.raids[1].encounters[2] = {name="Incindis", settings...}
```

**Impact:**
- Syncing ONE encounter requires sending ENTIRE `encounterMgmt` table (~6,600 lines)
- User reported bug: Changed sync from 7 seconds → **15 minutes** due to this structure
- Easy to accidentally send wrong scope (happened in recent release)

**Why it happened:**
- Code tried to sync one encounter
- Had to send `encounterMgmt.roles["MC"]` (all 12 MC encounters)
- Plus `encounterMgmt.raids` for context
- = 6,600+ lines instead of ~100 lines

**Solution:** Nest roles INSIDE encounter objects:
```lua
// After restructure:
encounterMgmt.raids[1].encounters[2] = {
    name = "Incindis",
    roles = {role configs...},  // STORED HERE
    advancedSettings = {...}
}
// Now sync ONE encounter = ONE object = ~100 lines
```

**Benefits:**
- Network sync: 6,600 lines → 100 lines per encounter (98.5% reduction)
- Prevents future bugs: Encounter is atomic unit
- Code clarity: Single access pattern

---

## Performance Gains

| Metric | Current | Optimized | Improvement |
|--------|---------|-----------|-------------|
| File size | 40,000 lines | 14,000 lines | 65% smaller |
| Load time | 350ms | 180ms | 48% faster |
| Memory | 2.5MB | 1.8MB | 28% less |
| **Network sync** | **15 min (broken)** | **~10 sec** | **90x faster** |

---

## Risk Assessment

### Low Risk Items (Phase 1)
✅ Removing empty tables  
✅ Adding versioning  
✅ Backup mechanism  

**Why safe?** Tables are confirmed empty, no user data lost.

### Medium Risk Items (Phase 2)
⚠️ Pruning histories  
⚠️ **EncounterMgmt restructure** (NEW)

**Why medium risk?** 
- Pruning: Must preserve important data, correct thresholds needed
- **EncounterMgmt:** Touches ~30 code locations, comprehensive testing required

**Mitigation:**
- Automatic backup before migration
- Configurable retention periods
- Extensive testing with real data

### High Risk Items (Phase 3)
❌ Complete restructuring  

**Why high risk?**
- Core data structure changes
- Affects many modules
- Complex migration

**Recommendation:** Phase 3 is optional, evaluate after Phase 2.

---

## Decision Points

### Question 1: Should we do this at all?

**YES if:**
- Users complain about addon load times
- SavedVariables file corruption issues
- Recruitment bloat causing problems
- Planning significant new features

**NO if:**
- Current system works fine
- Limited development resources
- Risk outweighs benefits

### Question 2: Which phases?

**Option A: Phase 1 only** (Quick wins)
- Low effort, low risk
- Immediate cleanup
- Foundation for future

**Option B: Phase 1 + 2** (Recommended)
- Significant benefits
- Manageable risk
- Good ROI

**Option C: All phases**
- Maximum benefits
- Highest risk
- Only if planning major refactor

### Question 3: When to release?

**Option A: Next major version (2.0)**
- Users expect changes
- More testing time
- Can market as "optimization update"

**Option B: Point release (1.32)**
- Faster deployment
- Less fanfare
- May surprise users

**Option C: Beta testers first**
- Safest approach
- Get feedback
- Iron out issues before wide release

---

## 6. MIGRATION STRATEGY: VERSIONED SCHEMA

### Dual-Schema Approach for Maximum Safety

Instead of in-place migration, we'll create `OGRH_SV.v2` alongside the original:

```lua
OGRH_SV = {
    schemaVersion = "v1",      -- Active version
    
    -- Original v1 data (unchanged)
    syncLocked = false,
    encounterMgmt = { ... },
    -- ... all existing data ...
    
    -- New optimized structure
    v2 = {
        encounterMgmt = { ... },  -- Future: with nested roles
        recruitment = { ... },    -- With retention
        -- ... optimized data ...
    }
}
```

### 4-Week Migration Timeline

| Week | Phase | Description |
|------|-------|-------------|
| 1 | Dual-Write | Create v2, write to both, read from v1 |
| 2-3 | Validation | Read from v2, validate against v1 |
| 4 | Cutover | Switch `schemaVersion="v2"`, monitor |
| 5+ | Cleanup | Remove v1 data after validation |

### Key Benefits

✅ **Zero-risk rollback:** Change one variable to revert  
✅ **Direct comparison:** Can validate v2 vs v1 accuracy  
✅ **Incremental testing:** Migrate subsystems gradually  
✅ **Production safety:** Original data never touched  

### Temporary Cost

- Memory: ~2x during transition (5MB total)
- File size: ~80K lines for 4 weeks
- **Worth it** for mission-critical raid data

---

## 7. Recommended Approach

### Our Recommendation: Phase 1 + 2, Major Version Release

**Timeline:**
1. **Week 1:** Implement migration system + Phase 1 (dead code removal)
2. **Week 2:** Implement Phase 2 (history pruning)
3. **Week 3:** Dual-write deployment, testing
4. **Week 4-5:** Validation with beta testers
5. **Week 6:** Cutover to v2
6. **Week 7+:** Monitor and cleanup

**Why this approach?**
- ✅ Significant benefits (63% file reduction)
- ✅ Zero-risk rollback via versioning
- ✅ Original data never lost
- ✅ Can validate v2 against v1
- ✅ Sets foundation for future improvements (Priority 2)
- ✅ Reasonable effort (16-20 hours total including versioning)

**What users will see:**
```
OG-RaidHelper v2.0 Update:
- 63% smaller SavedVariables file
- 48% faster loading
- Automatic history cleanup
- Safe migration with rollback support
```

---

## 8. Next Steps

1. **Review this document** with team
2. **Decide on approach** (Phase 1+2 recommended, Priority 2 for v3.0)
3. **Set timeline** based on resources
4. **Review migration script** (SavedVariables-Migration-v2-Prototype.lua)
5. **Test with sample data** before production deployment
4. **Begin Phase 1** if approved
5. **Test with production data** from volunteers

---

## Resources Provided

1. **SavedVariables-Optimization-Analysis.md** - Detailed technical analysis
2. **SavedVariables-Migration-v2-Prototype.lua** - Working migration script
3. **This document** - Decision guide

---

## Questions for Discussion

1. Are users experiencing performance issues with the addon?
2. How much development time can we allocate?
3. What's our risk tolerance for this change?
4. Should we do Phase 3 (full restructure) or save for later?
5. When should we target release? (1.32, 2.0, later?)

---

## Conclusion

We have a clear path to significantly improve the addon's performance and maintainability with manageable risk. The question is whether now is the right time and how far we want to go.

**The analysis is complete. The migration script is prototyped. We're ready to proceed when you give the word.**

---

*For detailed technical information, see [SavedVariables-Optimization-Analysis.md](SavedVariables-Optimization-Analysis.md)*  
*For migration code, see [SavedVariables-Migration-v2-Prototype.lua](SavedVariables-Migration-v2-Prototype.lua)*
