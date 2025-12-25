# ShaguDPS Integration Notes for OG-RaidHelper

**Date:** December 22, 2025  
**Purpose:** Document findings for potential DPS ranking system integration

---

## Executive Summary

✅ **NO MODIFICATIONS TO ShaguDPS REQUIRED**

All DPS data is accessible through the global `ShaguDPS` table. ShaguDPS has a simpler, more modern API than DPSMate and can be used as an optional dependency.

---

## Data Structure

### Global Table (All data accessible via `ShaguDPS`)

```lua
-- Main data table (accessible as ShaguDPS.data)
ShaguDPS.data = {
    damage = {
        [0] = {},  -- Overall damage (all fights)
        [1] = {},  -- Current segment (current fight)
    },
    
    heal = {
        [0] = {},  -- Overall healing
        [1] = {},  -- Current segment
    },
    
    classes = {}  -- Player class/owner lookup
}

-- Structure for each player in damage/heal tables:
ShaguDPS.data.damage[segment][playerName] = {
    ["_sum"] = totalDamage,           -- Total damage/healing
    ["_ctime"] = combatTime,          -- Combat time in seconds
    ["_tick"] = lastUpdateTime,       -- Last update timestamp
    ["_esum"] = effectiveHealing,     -- (heal only) Effective healing
    ["_effective"] = {                -- (heal only) Per-spell effective
        [spellName] = effectiveAmount
    },
    [spellName] = damageAmount,       -- Damage per spell/ability
    ["Pet: PetName"] = damage,        -- Pet damage (if merge_pets disabled)
}

-- Class/owner lookup
ShaguDPS.data.classes[playerName] = "WARRIOR"  -- Class name
ShaguDPS.data.classes[petName] = ownerName     -- Pet's owner name
ShaguDPS.data.classes[unitName] = "__other__"  -- Non-tracked units

-- Config (accessible as ShaguDPS.config)
ShaguDPS.config = {
    track_all_units = 0,  -- 0=group only, 1=all units
    merge_pets = 1,       -- 1=merge pet damage with owner, 0=separate
    -- ... UI settings
}

-- Internal field markers (ignore these)
ShaguDPS.internals = {
    ["_sum"] = true,
    ["_ctime"] = true,
    ["_tick"] = true,
    ["_esum"] = true,
    ["_effective"] = true,
}
```

### Saved Variables

```lua
-- Only UI/config settings are saved
-- SavedVariablesPerCharacter: ShaguDPS_Config
-- Combat data is NOT persisted between sessions
```

---

## Key Differences from DPSMate

| Feature | ShaguDPS | DPSMate |
|---------|----------|---------|
| **Data Storage** | Runtime only (lost on logout) | Saved to disk |
| **Segments** | 2 only (Overall, Current) | 8+ configurable segments |
| **History** | No historical data | Full boss fight history |
| **User IDs** | Direct name keys | Numeric IDs with lookup |
| **Pet Handling** | Merged by default | Configurable |
| **Complexity** | Simple, lightweight | Complex, feature-rich |
| **API Style** | Direct table access | Mix of tables + functions |

---

## Implementation Examples

### Example 1: Get DPS Rankings

```lua
function OGRH:GetShaguDPSRankings(segment)
    -- Check if ShaguDPS is loaded
    if not ShaguDPS or not ShaguDPS.data then
        return nil, "ShaguDPS not loaded"
    end
    
    segment = segment or 0  -- 0 = overall, 1 = current fight
    local damageData = ShaguDPS.data.damage[segment]
    local classes = ShaguDPS.data.classes
    local internals = ShaguDPS.internals
    
    local rankings = {}
    
    -- Iterate through all players
    for playerName, data in pairs(damageData) do
        -- Skip internal fields and non-player entries
        if not internals[playerName] and classes[playerName] then
            local class = classes[playerName]
            
            -- Skip pets (they have owner names as class) and "__other__"
            if class and class ~= "__other__" and 
               not classes[class] then  -- Not a pet (class isn't another player)
                
                local totalDamage = data["_sum"] or 0
                local combatTime = data["_ctime"] or 1
                local dps = totalDamage / combatTime
                
                table.insert(rankings, {
                    name = playerName,
                    class = class,
                    damage = totalDamage,
                    dps = dps,
                    combatTime = combatTime
                })
            end
        end
    end
    
    -- Sort by DPS descending
    table.sort(rankings, function(a, b) return a.dps > b.dps end)
    
    return rankings
end
```

### Example 2: Get Healing Rankings

```lua
function OGRH:GetShaguHealingRankings(segment, useEffective)
    if not ShaguDPS or not ShaguDPS.data then
        return nil, "ShaguDPS not loaded"
    end
    
    segment = segment or 0
    useEffective = useEffective or true
    local healData = ShaguDPS.data.heal[segment]
    local classes = ShaguDPS.data.classes
    local internals = ShaguDPS.internals
    
    local rankings = {}
    
    for playerName, data in pairs(healData) do
        if not internals[playerName] and classes[playerName] then
            local class = classes[playerName]
            
            if class and class ~= "__other__" and not classes[class] then
                local totalHealing = data["_sum"] or 0
                local effectiveHealing = data["_esum"] or 0
                local combatTime = data["_ctime"] or 1
                
                local healing = useEffective and effectiveHealing or totalHealing
                local hps = healing / combatTime
                local overheal = totalHealing - effectiveHealing
                local overhealPercent = totalHealing > 0 and (overheal / totalHealing * 100) or 0
                
                table.insert(rankings, {
                    name = playerName,
                    class = class,
                    healing = healing,
                    hps = hps,
                    totalHealing = totalHealing,
                    effectiveHealing = effectiveHealing,
                    overheal = overheal,
                    overhealPercent = overhealPercent,
                    combatTime = combatTime
                })
            end
        end
    end
    
    table.sort(rankings, function(a, b) return a.hps > b.hps end)
    
    return rankings
end
```

### Example 3: Get Player Details

```lua
function OGRH:GetShaguPlayerDetails(playerName, segment)
    if not ShaguDPS or not ShaguDPS.data then
        return nil, "ShaguDPS not loaded"
    end
    
    segment = segment or 0
    local damageData = ShaguDPS.data.damage[segment][playerName]
    local healData = ShaguDPS.data.heal[segment][playerName]
    local internals = ShaguDPS.internals
    
    if not damageData and not healData then
        return nil, "Player not found"
    end
    
    local details = {
        name = playerName,
        class = ShaguDPS.data.classes[playerName],
        damage = {},
        healing = {}
    }
    
    -- Collect damage breakdown
    if damageData then
        details.totalDamage = damageData["_sum"] or 0
        details.combatTime = damageData["_ctime"] or 1
        details.dps = details.totalDamage / details.combatTime
        
        for spellName, amount in pairs(damageData) do
            if not internals[spellName] then
                local percent = details.totalDamage > 0 and 
                    (amount / details.totalDamage * 100) or 0
                table.insert(details.damage, {
                    spell = spellName,
                    damage = amount,
                    percent = percent
                })
            end
        end
        
        -- Sort by damage
        table.sort(details.damage, function(a, b) return a.damage > b.damage end)
    end
    
    -- Collect healing breakdown
    if healData then
        details.totalHealing = healData["_sum"] or 0
        details.effectiveHealing = healData["_esum"] or 0
        details.overheal = details.totalHealing - details.effectiveHealing
        details.combatTime = healData["_ctime"] or 1
        details.hps = details.effectiveHealing / details.combatTime
        
        for spellName, amount in pairs(healData) do
            if not internals[spellName] then
                local effective = healData["_effective"] and 
                    healData["_effective"][spellName] or 0
                local percent = details.totalHealing > 0 and 
                    (amount / details.totalHealing * 100) or 0
                    
                table.insert(details.healing, {
                    spell = spellName,
                    healing = amount,
                    effective = effective,
                    overheal = amount - effective,
                    percent = percent
                })
            end
        end
        
        table.sort(details.healing, function(a, b) return a.healing > b.healing end)
    end
    
    return details
end
```

### Example 4: Check Availability and Get Segment Info

```lua
function OGRH:IsShaguDPSAvailable()
    return ShaguDPS and ShaguDPS.data and true or false
end

function OGRH:GetShaguSegmentInfo()
    if not OGRH:IsShaguDPSAvailable() then
        return nil
    end
    
    local info = {}
    
    -- Overall segment
    local overallCount = 0
    local overallTime = 0
    for name, data in pairs(ShaguDPS.data.damage[0]) do
        if not ShaguDPS.internals[name] then
            overallCount = overallCount + 1
            overallTime = math.max(overallTime, data["_ctime"] or 0)
        end
    end
    
    -- Current segment
    local currentCount = 0
    local currentTime = 0
    for name, data in pairs(ShaguDPS.data.damage[1]) do
        if not ShaguDPS.internals[name] then
            currentCount = currentCount + 1
            currentTime = math.max(currentTime, data["_ctime"] or 0)
        end
    end
    
    return {
        overall = {
            players = overallCount,
            duration = overallTime
        },
        current = {
            players = currentCount,
            duration = currentTime
        },
        mergePets = ShaguDPS.config.merge_pets == 1
    }
end
```

---

## Important Notes

### Data Persistence

⚠️ **ShaguDPS does NOT save combat data between sessions**
- Only UI/config settings are saved in `ShaguDPS_Config`
- All combat data resets on logout/reload
- No historical boss fight data available
- Only two segments: Overall (0) and Current (1)

**Impact**: Cannot track performance across multiple days or create long-term statistics. Only useful for real-time or current-session rankings.

### Pet Handling

- By default, pets are merged with owner (`merge_pets = 1`)
- When merged, pet damage appears as `["Pet: PetName"] = damage` in owner's data
- Pet entries in `classes` table point to owner name: `classes[petName] = ownerName`
- To identify pets: `classes[classes[name]]` exists (class is another player name)

### Combat Time Tracking

- Combat time (`_ctime`) increments only during active combat
- Uses 5-second tick system for time tracking
- More accurate than simple elapsed time
- Each player has individual combat time

### Segment Behavior

- **Segment 0 (Overall)**: Accumulates from addon load until manually reset
- **Segment 1 (Current)**: Auto-resets when combat ends and new combat starts
- New combat detected when player leaves combat state
- No configurable auto-segment creation like DPSMate

---

## Testing Commands

### Check if ShaguDPS is Loaded
```lua
/run if ShaguDPS then print("ShaguDPS loaded") else print("ShaguDPS not found") end
```

### Show Overall DPS Leaders
```lua
/run if ShaguDPS then local d=ShaguDPS.data.damage[0]; for n,v in pairs(d) do if v["_sum"] then print(n..": "..math.floor(v["_sum"]/v["_ctime"]).." DPS") end end end
```

### Show Current Fight DPS
```lua
/run if ShaguDPS then local d=ShaguDPS.data.damage[1]; for n,v in pairs(d) do if v["_sum"] then print(n..": "..math.floor(v["_sum"]/v["_ctime"]).." DPS") end end end
```

### Check Segment Info
```lua
/run if ShaguDPS then local overall=0; local current=0; for n,v in pairs(ShaguDPS.data.damage[0]) do if v["_sum"] then overall=overall+1 end end; for n,v in pairs(ShaguDPS.data.damage[1]) do if v["_sum"] then current=current+1 end end; print("Overall: "..overall.." players, Current: "..current.." players") end
```

### Get Player DPS
```lua
/run local p="PlayerName"; if ShaguDPS and ShaguDPS.data.damage[0][p] then local d=ShaguDPS.data.damage[0][p]; print(p..": "..d["_sum"].." damage in "..d["_ctime"].."s = "..math.floor(d["_sum"]/d["_ctime"]).." DPS") end
```

---

## Comparison: ShaguDPS vs DPSMate

### Advantages of ShaguDPS

✅ **Simpler API** - Direct table access, no ID lookups  
✅ **Cleaner data structure** - Player names as keys  
✅ **Modern design** - Well-organized, maintainable code  
✅ **Lightweight** - Lower memory footprint  
✅ **Effective healing** - Built-in overheal tracking  
✅ **Pet merging** - Automatic by default

### Advantages of DPSMate

✅ **Historical data** - Stores boss fight segments  
✅ **Persistence** - Data saved between sessions  
✅ **More segments** - Up to 8+ saved fights  
✅ **More metrics** - Threat, interrupts, dispels, deaths  
✅ **Timestamps** - Fight time recorded  
✅ **Sync system** - Share data across raid

### Recommendation

**For OG-RaidHelper:**

- **Use ShaguDPS** if you want:
  - Simple, clean integration
  - Real-time rankings during current raid session
  - Lightweight dependency
  - Easy-to-access healing data with overheal

- **Use DPSMate** if you need:
  - Historical boss fight data
  - Performance tracking across multiple days
  - Specific segment selection (Boss 1 vs Boss 2)
  - More diverse metrics (threat, interrupts, etc.)

- **Support Both** (Recommended):
  - Check for ShaguDPS first (simpler)
  - Fall back to DPSMate if available
  - Provide unified ranking interface

---

## Implementation Strategy

### Phase 1: Basic ShaguDPS Integration
1. Add ShaguDPS detection
2. Implement simple DPS ranking display
3. Toggle between Overall and Current segment
4. Show top N performers

### Phase 2: Enhanced Features
1. Add healing rankings with overheal %
2. Per-player detailed breakdown
3. Class-based filtering
4. Export to chat/whisper

### Phase 3: Dual Support
1. Add DPSMate fallback support
2. Unified API wrapper for both addons
3. User preference for which meter to use
4. Automatic detection and selection

---

## Example Unified API Wrapper

```lua
-- Universal DPS meter interface
OGRH.Meter = {}

function OGRH.Meter:IsAvailable()
    if ShaguDPS and ShaguDPS.data then
        return "ShaguDPS"
    elseif DPSMateDamageDone and DPSMateUser then
        return "DPSMate"
    end
    return nil
end

function OGRH.Meter:GetDPSRankings(options)
    local meter = self:IsAvailable()
    
    if meter == "ShaguDPS" then
        return OGRH:GetShaguDPSRankings(options.segment or 0)
    elseif meter == "DPSMate" then
        return OGRH:GetDPSRankings(options.mode or 1)
    end
    
    return nil, "No damage meter found"
end

-- Usage:
local rankings, err = OGRH.Meter:GetDPSRankings({ segment = 0 })
```

---

## Advantages of This Approach

✅ No ShaguDPS modifications required  
✅ No compatibility issues  
✅ Works as optional dependency  
✅ Simple, clean data access  
✅ Real-time rankings perfect for active raids  
✅ Easy to extend to other meters  

---

## Limitations

⚠️ **No historical data** - Cannot track performance over multiple days  
⚠️ **No saved segments** - Only current and overall available  
⚠️ **Session-only** - Data lost on logout  
⚠️ **Limited metrics** - Only damage and healing (no threat, interrupts, etc.)  
⚠️ **No timestamps** - Cannot determine when fights occurred  

---

## Questions to Answer Before Implementation

1. **Session vs Historical**: Do you need historical data or just current session?
2. **Primary Meter**: Support ShaguDPS only, DPSMate only, or both?
3. **Healing Rankings**: Include healing alongside damage?
4. **Overheal Display**: Show overheal percentages for healers?
5. **Real-time Updates**: Update rankings during combat or after?
6. **Fallback Strategy**: What if no meter addon installed?

---

## Recommended Approach

**Best Strategy**: Support both ShaguDPS and DPSMate with automatic detection

- ShaguDPS: Perfect for active raid real-time rankings
- DPSMate: Better for post-raid analysis and historical data
- Provide unified interface that works with either

**Estimated Development Time**: 
- ShaguDPS only: 1-2 hours
- DPSMate only: 2-4 hours  
- Both with unified API: 4-6 hours

---

## End Notes

ShaguDPS provides a cleaner, simpler API than DPSMate but lacks historical data persistence. For real-time rankings during an active raid session, ShaguDPS is ideal. For roster evaluation over time, DPSMate is better. Supporting both gives maximum flexibility.
