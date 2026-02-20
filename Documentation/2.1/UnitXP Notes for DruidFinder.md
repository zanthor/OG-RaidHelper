# UnitXP Service Pack 3 - Raid Helper API

## Overview
This document describes the UnitXP SP3 Lua API functions for calculating distances between units and checking line of sight. These functions are useful for raid scenarios like finding the closest druid to resurrect a dead player.

## Available Functions

### 1. Distance Calculation

**Function**: `UnitXP("distanceBetween", unit1, unit2, [meterType])`

Calculates the distance between two units in yards.

**Parameters**:
- `unit1` (string): Source unit ID (e.g., "player", "raid1", "party2", "target")
- `unit2` (string): Target unit ID
- `meterType` (string, optional): Distance calculation method. Default is "ranged"
  - `"ranged"` - For ranged spells, heals, and charge abilities
  - `"meleeAutoAttack"` - Melee attack range (ignores Z-axis)
  - `"AoE"` - Area of effect spell range
  - `"chains"` - Chain spell range (like cleave, multishot)
  - `"Gaussian"` - Raw 3D distance

**Returns**:
- `number`: Distance in yards
- `nil`: On error (invalid unit, out of range, etc.)

**Example**:
    local distance = UnitXP("distanceBetween", "raid1", "raid10", "ranged")
    if distance then
        print("Distance: " .. distance .. " yards")
    else
        print("Could not calculate distance")
    end

### 2. Line of Sight Check

**Function**: `UnitXP("inSight", unit1, unit2)`

Checks if two units have line of sight to each other (no obstacles blocking view).

**Parameters**:
- `unit1` (string): Source unit ID
- `unit2` (string): Target unit ID

**Returns**:
- `true` (1): Units have line of sight
- `false` (0): Line of sight is blocked
- `nil`: On error (invalid unit, etc.)

**Example**:
    local hasLoS = UnitXP("inSight", "raid1", "raid10")
    if hasLoS == true then
        print("Can see target")
    elseif hasLoS == false then
        print("Line of sight blocked")
    else
        print("Error checking line of sight")
    end

### 3. Relative Direction

**Function**: `UnitXP("relativeDirection", unit1, unit2)`

Returns the angular direction from unit1 to unit2 in radians.

**Parameters**:
- `unit1` (string): Observer unit
- `unit2` (string): Target unit

**Returns**:
- `number`: Angle in radians
- `nil`: On error

### 4. Behind Check

**Function**: `UnitXP("behind", unit1, unit2)`

Checks if unit1 is behind unit2 (useful for backstab mechanics).

**Parameters**:
- `unit1` (string): Attacker unit
- `unit2` (string): Target unit

**Returns**:
- `true` (1): Unit1 is behind unit2
- `false` (0): Unit1 is not behind unit2
- `nil`: On error

## Practical Example: Finding Closest Druid

### Scenario
You have 5 druids in your raid who can combat resurrect, and you need to find which one is closest to a dead rogue with line of sight.

### Solution

    -- Find closest druid with LoS to dead rogue
    function FindClosestDruidToRez(deadUnit)
        local druids = {}
        
        -- Find all druids in raid
        for i = 1, 40 do
            local unit = "raid" .. i
            if UnitExists(unit) and UnitClass(unit) == "Druid" then
                table.insert(druids, unit)
            end
        end
        
        local closestDruid = nil
        local shortestDistance = 9999
        
        for _, druid in ipairs(druids) do
            local distance = UnitXP("distanceBetween", druid, deadUnit, "ranged")
            local hasLoS = UnitXP("inSight", druid, deadUnit)
            
            -- Check if this druid is closer and has LoS
            if distance and hasLoS == true and distance < shortestDistance then
                shortestDistance = distance
                closestDruid = druid
            end
        end
        
        if closestDruid then
            return closestDruid, shortestDistance
        else
            return nil, nil
        end
    end
    
    -- Usage
    local druid, distance = FindClosestDruidToRez("raid10")
    if druid then
        print("Closest druid: " .. UnitName(druid) .. " at " .. string.format("%.1f", distance) .. " yards")
    else
        print("No druid has LoS to target")
    end

### Advanced Example: All Distances with LoS Status

    function GetAllDruidDistances(deadUnit)
        local results = {}
        
        for i = 1, 40 do
            local unit = "raid" .. i
            if UnitExists(unit) and UnitClass(unit) == "Druid" then
                local distance = UnitXP("distanceBetween", unit, deadUnit, "ranged")
                local hasLoS = UnitXP("inSight", unit, deadUnit)
                
                if distance then
                    table.insert(results, {
                        unit = unit,
                        name = UnitName(unit),
                        distance = distance,
                        hasLoS = hasLoS == true,
                        losStatus = hasLoS == true and "Yes" or "No"
                    })
                end
            end
        end
        
        -- Sort by distance
        table.sort(results, function(a, b) return a.distance < b.distance end)
        
        return results
    end
    
    -- Print sorted list
    local druids = GetAllDruidDistances("raid10")
    print("Druids sorted by distance:")
    for i, info in ipairs(druids) do
        print(string.format("%d. %s - %.1f yards - LoS: %s", i, info.name, info.distance, info.losStatus))
    end

## Notes

1. **Unit IDs**: Works with all standard WoW unit IDs:
   - `"player"` - Your character
   - `"target"` - Current target
   - `"raid1"` through `"raid40"` - Raid members
   - `"party1"` through `"party4"` - Party members
   - `"pet"`, `"playerpet"` - Pets

2. **Performance**: These functions use native C++ implementations for optimal performance

3. **Error Handling**: Always check for `nil` returns, which indicate:
   - Invalid unit ID
   - Unit out of range
   - Unit doesn't exist
   - Calculation error

4. **Distance Meters**: 
   - Use `"ranged"` for healing and most spells (default)
   - Use `"meleeAutoAttack"` only for melee calculations
   - Use `"Gaussian"` for raw 3D distance without game-specific adjustments

## Implementation Details

The C++ implementation can be found in:
- `dllmain.cpp` - Lines 47-77 (distanceBetween)
- `dllmain.cpp` - Lines 33-46 (inSight)
- `distanceBetween.h` - Distance meter enum definitions
- `inSight.h` - Line of sight function declarations

## Version
Compatible with UnitXP Service Pack 3 (Konaka-main branch)