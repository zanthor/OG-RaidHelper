# DPSMate Integration Notes for OG-RaidHelper

**Date:** December 22, 2025  
**Purpose:** Document findings for potential DPS ranking system integration

---

## Executive Summary

✅ **NO MODIFICATIONS TO DPSMate REQUIRED**

All DPS data is accessible through global saved variables. DPSMate can be used as an optional dependency without any compatibility issues.

---

## Data Structure

### Global Saved Variables (Accessible from any addon)

```lua
-- Damage data arrays: [1] = total session, [2] = current fight
DPSMateDamageDone = {
    [1] = {  -- Total damage
        [userId] = {
            ["i"] = totalDamage,  -- Total damage by this user
            [abilityId] = {
                [1] = hits,
                [2] = hitMin,
                [3] = hitMax,
                [4] = hitTotal,
                [5] = crits,
                [6] = critMin,
                [7] = critMax,
                [8] = critTotal,
                [9] = misses,
                [10] = parries,
                [11] = dodges,
                [12] = resists,
                [13] = totalDamage,  -- Damage for this ability
                [14] = glances,
                -- ... more stats
                ["i"] = {[time] = damage}  -- Time-indexed damage
            }
        }
    },
    [2] = { -- Current fight (same structure) }
}

-- Player information lookup
DPSMateUser = {
    ["PlayerName"] = {
        [1] = userId,              -- Numeric ID
        [2] = class,               -- Lowercase: "warrior", "mage", etc.
        [3] = faction,             -- 1=Alliance, -1=Horde
        [4] = isPet,               -- boolean
        [5] = petName,             -- string or ""
        [6] = ownerId,             -- if pet, owner's userId
        [7] = guildName,           -- string
        [8] = level                -- number
    }
}

-- Ability lookup
DPSMateAbility = {
    ["AbilityName"] = {
        [1] = abilityId,           -- Numeric ID
        [2] = kind,                -- Type of ability
        [3] = school               -- Damage school
    }
}

-- Combat time tracking
DPSMateCombatTime = {
    total = number,                -- Total session combat time
    current = number,              -- Current fight time
    segments = {                   -- Array of saved segments
        [1] = {
            [1] = combatTime,
            [2] = effectiveTimeTable
        }
    },
    effective = {
        [1] = {[playerName] = time}, -- Effective combat time per player (total)
        [2] = {[playerName] = time}  -- Effective combat time per player (current)
    }
}

-- Historical segments
DPSMateHistory = {
    names = {                      -- Array of segment names (most recent first)
        [1] = "BossName - HH:MM AM/PM",
        [2] = "BossName - HH:MM AM/PM",
        -- ...
    },
    DMGDone = {                    -- Array of damage data snapshots
        [1] = {[userId] = data},
        [2] = {[userId] = data},
        -- ...
    },
    -- Similar arrays for: DMGTaken, EDDone, EDTaken, THealing, 
    -- EHealing, OHealing, THealingTaken, EHealingTaken, 
    -- OHealingTaken, Absorbs, Deaths, Interrupts, Dispels, 
    -- Auras, Threat, Fail, CCBreaker
}
```

---

## Public API Methods

### Available DPSMate Functions

```lua
-- Convert IDs to names
DPSMate:GetUserById(userId)        -- Returns player name
DPSMate:GetAbilityById(abilityId)  -- Returns ability name

-- Get sorted DPS rankings (uses DPSMate's own sorting logic)
local sortedValues, totalDamage, sortedNames = 
    DPSMate.Modules.DPS:GetSortedTable(damageArray, windowKey)

-- Table utilities
DPSMate:TableLength(table)         -- Get table length
DPSMate:CopyTable(table)           -- Deep copy
DPSMate:ApplyFilter(k, name)       -- Check if player passes filters
```

---

## Implementation Examples

### Example 1: Get DPS Rankings (Direct Access)

```lua
function OGRH:GetDPSRankings(mode)
    -- Check if DPSMate is loaded
    if not DPSMateDamageDone or not DPSMateUser or not DPSMateCombatTime then
        return nil, "DPSMate not loaded"
    end
    
    mode = mode or 1  -- 1 = total, 2 = current fight
    local damageData = DPSMateDamageDone[mode]
    local combatTime = mode == 1 and DPSMateCombatTime.total or DPSMateCombatTime.current
    local effectiveTime = DPSMateCombatTime.effective[mode]
    
    local rankings = {}
    
    -- Iterate through all players
    for userId, data in pairs(damageData) do
        local playerName = DPSMate:GetUserById(userId)
        if playerName and DPSMateUser[playerName] then
            local userInfo = DPSMateUser[playerName]
            
            -- Skip pets unless you want to merge them
            if not userInfo[4] then
                local totalDamage = data["i"] or 0
                local effectiveCombatTime = (effectiveTime and effectiveTime[playerName]) or combatTime
                local dps = totalDamage / math.max(effectiveCombatTime, 0.0001)
                
                table.insert(rankings, {
                    name = playerName,
                    class = userInfo[2],
                    damage = totalDamage,
                    dps = dps,
                    combatTime = effectiveCombatTime
                })
            end
        end
    end
    
    -- Sort by DPS descending
    table.sort(rankings, function(a, b) return a.dps > b.dps end)
    
    return rankings
end
```

### Example 2: Get Rankings from Specific Segment

```lua
function OGRH:GetSegmentDPSRankings(segmentIndex)
    if not DPSMateHistory or not DPSMateHistory.DMGDone then
        return nil, "No segment data"
    end
    
    if not DPSMateHistory.DMGDone[segmentIndex] then
        return nil, "Invalid segment"
    end
    
    local damageData = DPSMateHistory.DMGDone[segmentIndex]
    local combatTime = DPSMateCombatTime.segments[segmentIndex][1]
    local effectiveTime = DPSMateCombatTime.segments[segmentIndex][2]
    
    local rankings = {}
    
    for userId, data in pairs(damageData) do
        local playerName = DPSMate:GetUserById(userId)
        if playerName and DPSMateUser[playerName] and not DPSMateUser[playerName][4] then
            local totalDamage = data["i"] or 0
            local effectiveCombatTime = (effectiveTime and effectiveTime[playerName]) or combatTime
            local dps = totalDamage / math.max(effectiveCombatTime, 0.0001)
            
            table.insert(rankings, {
                name = playerName,
                class = DPSMateUser[playerName][2],
                damage = totalDamage,
                dps = dps,
                segmentName = DPSMateHistory.names[segmentIndex]
            })
        end
    end
    
    table.sort(rankings, function(a, b) return a.dps > b.dps end)
    return rankings
end
```

### Example 3: Merge Pet Damage with Owner

```lua
function OGRH:MergePetDamage(damageData)
    local merged = {}
    
    for userId, data in pairs(damageData) do
        local playerName = DPSMate:GetUserById(userId)
        local userInfo = DPSMateUser[playerName]
        
        if userInfo then
            -- If it's a pet, add to owner
            if userInfo[4] and userInfo[6] then
                local ownerName = DPSMate:GetUserById(userInfo[6])
                if ownerName then
                    merged[ownerName] = (merged[ownerName] or 0) + (data["i"] or 0)
                end
            else
                -- Add player damage
                merged[playerName] = (merged[playerName] or 0) + (data["i"] or 0)
                
                -- Add pet damage if they have one
                local petName = userInfo[5]
                if petName and petName ~= "" and DPSMateUser[petName] then
                    local petId = DPSMateUser[petName][1]
                    if damageData[petId] then
                        merged[playerName] = merged[playerName] + (damageData[petId]["i"] or 0)
                    end
                end
            end
        end
    end
    
    return merged
end
```

### Example 4: Check if DPSMate is Available

```lua
function OGRH:IsDPSMateAvailable()
    return (DPSMateDamageDone ~= nil and 
            DPSMateUser ~= nil and 
            DPSMateCombatTime ~= nil and
            DPSMate ~= nil)
end
```

---

## Important Notes

### Segment Data Limitations

1. **No Date Storage**: DPSMate only stores time-of-day (HH:MM AM/PM), not dates
   - Cannot reliably filter for "today's" segments
   - Segment names format: `"BossName - 3:45 PM - CBT: 4:32"`

2. **Segment Storage**: 
   - Most recent segment is at index [1]
   - Configurable limit (default 8 segments via `DPSMateSettings["datasegments"]`)
   - Older segments are automatically pruned

3. **Accessing Segments**:
   ```lua
   -- List recent segments
   for i=1, math.min(10, getn(DPSMateHistory.names)) do
       local segmentName = DPSMateHistory.names[i]
       local combatTime = DPSMateCombatTime.segments[i][1]
       print(i..". "..segmentName.." ("..combatTime.."s)")
   end
   ```

### Combat Time Considerations

- **Total combat time**: Global for entire session
- **Effective combat time**: Per-player, accounts for death/disconnect
- Always use effective time when available for accurate DPS calculations
- Formula: `DPS = totalDamage / max(effectiveTime, 0.0001)`

### Pet Handling

- Pets have `DPSMateUser[petName][4] = true`
- Pet owner ID stored in `DPSMateUser[petName][6]`
- Player's pet name in `DPSMateUser[playerName][5]`
- DPSMate has `DPSMateSettings["mergepets"]` option
- Consider providing option to merge or separate pet damage

### Lua Version Compatibility

⚠️ **WoW 1.12 uses Lua 5.0**:
- Use `getn(table)` instead of `#table`
- Use `table.getn(table)` for length
- No `continue` statement (use workarounds)

---

## Testing Commands

### List Recent Segments
```lua
/run if DPSMateHistory and DPSMateHistory.names then local count = math.min(10, getn(DPSMateHistory.names)); print("Last "..count.." segments:"); for i=1, count do local time = DPSMateCombatTime.segments[i] and DPSMateCombatTime.segments[i][1] or 0; print(i..". "..DPSMateHistory.names[i].." ("..string.format("%.0f", time).."s)") end else print("No segments") end
```

### Check DPSMate Status
```lua
/run if DPSMate then print("DPSMate loaded. Segments: "..getn(DPSMateHistory.names or {})) else print("DPSMate not loaded") end
```

### Show Total Combat Time
```lua
/run print("Total: "..DPSMateCombatTime.total.."s, Current: "..DPSMateCombatTime.current.."s")
```

---

## Recommended Integration Approach

### Phase 1: Basic Integration
1. Add optional DPSMate detection
2. Implement simple DPS ranking display
3. Use "Total" mode for session rankings

### Phase 2: Enhanced Features
1. Add segment selection UI
2. Implement pet damage merging options
3. Add class-based filtering
4. Show top N performers per role

### Phase 3: Advanced Features
1. Compare player performance across segments
2. Track DPS trends over multiple fights
3. Export rankings for roster evaluation
4. Integration with existing OG-RaidHelper roster management

---

## Advantages of This Approach

✅ No DPSMate modifications required  
✅ No compatibility issues with DPSMate updates  
✅ Works as optional dependency  
✅ Access to real-time and historical data  
✅ Can leverage DPSMate's filtering and sorting  
✅ Access to other metrics (healing, damage taken, etc.)

---

## Additional Metrics Available

Beyond DPS, you can also access:
- **Healing**: `DPSMateTHealing`, `DPSMateEHealing`, `DPSMateOverhealing`
- **Damage Taken**: `DPSMateDamageTaken`
- **Deaths**: `DPSMateDeaths`
- **Threat**: `DPSMateThreat`
- **Interrupts**: `DPSMateInterrupts`
- **Dispels**: `DPSMateDispels`

All use similar data structures and can be accessed the same way.

---

## Questions to Answer Before Implementation

1. **Data Source**: Use Total, Current Fight, or Segments?
2. **Pet Handling**: Merge with owner or show separately?
3. **Display Format**: Simple list, detailed breakdown, or comparison view?
4. **Filtering**: Class-based, role-based, or guild-only?
5. **Integration Point**: New UI window, chat command, or MainUI integration?
6. **Persistence**: Store rankings in OGRH_SV or use real-time only?

---

## End Notes

This integration is straightforward and low-risk. DPSMate's global variable approach makes it ideal for addon interoperability. No hooks, no modifications, just read the data and build your rankings.

**Estimated Development Time**: 2-4 hours for basic implementation
