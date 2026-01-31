-- OGRH_SyncChecksum.lua (Turtle-WoW 1.12)
-- Centralized checksum computation and serialization utilities
-- Phase 4: Code Consolidation

--[[
    This module consolidates ALL checksum, hashing, and serialization functions
    from across the addon into a single authoritative location.
    
    Architecture:
    - All checksum functions live here (no duplicates elsewhere)
    - Serialization delegates to OGAddonMsg when possible
    - Legacy OGRH.Serialize/Deserialize maintained for backward compatibility
    - All sync systems reference this module for checksums
    
    Migration Status:
    - ✅ Consolidated from Core.lua (HashRole, CalculateStructureChecksum, CalculateAllStructureChecksum)
    - ✅ Consolidated from SyncIntegrity.lua (HashString, ComputeRaidChecksum, ComputeActiveAssignmentsChecksum, CalculateRolesUIChecksum)
    - ✅ Backward compatibility wrappers in place (OGRH.*)
]]

OGRH = OGRH or {}
OGRH.SyncChecksum = {}

--[[
    ============================================================================
    SECTION 1: HASHING UTILITIES
    ============================================================================
]]

--[[
    Hash a string to a numeric checksum
    
    Simple CRC-style hash algorithm for consistent checksums across clients.
    Uses mod() instead of % operator for Lua 5.0/5.1 compatibility.
    
    @param str string - Input string to hash
    @return string - Numeric hash as string
]]
function OGRH.SyncChecksum.HashString(str)
    if not str or str == "" then
        return "0"
    end
    
    local hash = 0
    for i = 1, string.len(str) do
        local byte = string.byte(str, i)
        hash = mod(hash * 31 + byte, 2147483647)  -- Use mod() for WoW 1.12
    end
    return tostring(hash)
end

--[[
    Hash a role's complete configuration
    
    Generates a deterministic hash from all role properties including:
    - Basic: roleId, fillOrder, name, slots
    - Flags: isConsumeCheck, showRaidIcons, showAssignment, markPlayer, etc.
    - Filters: defaultRoles, classes, classPriority, classPriorityRoles
    - Consumes: item IDs and allowAlternate flags
    - Links: linkedRoles
    
    @param role table - Role configuration object
    @param columnMultiplier number - Multiplier to distinguish columns (10 for col1, 20 for col2)
    @param roleIndex number - Role's position in the column
    @return number - Computed hash value
]]
function OGRH.SyncChecksum.HashRole(role, columnMultiplier, roleIndex)
    local hash = 0
    
    -- Hash stable roleId and fillOrder
    if role.roleId then
        hash = hash + role.roleId * columnMultiplier * 50
    end
    if role.fillOrder then
        hash = hash + role.fillOrder * columnMultiplier * 60
    end
    
    -- Hash role name
    local name = role.name or ""
    for j = 1, string.len(name) do
        hash = hash + string.byte(name, j) * roleIndex * columnMultiplier
    end
    
    -- Hash slot count
    local slots = role.slots or 1
    hash = hash + slots * roleIndex * columnMultiplier * 100
    
    -- Hash boolean flags
    hash = hash + (role.isConsumeCheck and 1 or 0) * roleIndex * columnMultiplier * 200
    hash = hash + (role.showRaidIcons and 1 or 0) * roleIndex * columnMultiplier * 300
    hash = hash + (role.showAssignment and 1 or 0) * roleIndex * columnMultiplier * 400
    hash = hash + (role.markPlayer and 1 or 0) * roleIndex * columnMultiplier * 500
    hash = hash + (role.allowOtherRoles and 1 or 0) * roleIndex * columnMultiplier * 600
    hash = hash + (role.invertFillOrder and 1 or 0) * roleIndex * columnMultiplier * 610
    hash = hash + (role.linkRole and 1 or 0) * roleIndex * columnMultiplier * 620
    
    -- Hash defaultRoles (tanks, healers, melee, ranged)
    if role.defaultRoles then
        hash = hash + (role.defaultRoles.tanks and 1 or 0) * roleIndex * columnMultiplier * 700
        hash = hash + (role.defaultRoles.healers and 1 or 0) * roleIndex * columnMultiplier * 800
        hash = hash + (role.defaultRoles.melee and 1 or 0) * roleIndex * columnMultiplier * 900
        hash = hash + (role.defaultRoles.ranged and 1 or 0) * roleIndex * columnMultiplier * 1000
    end
    
    -- Hash classes (for consume checks)
    if role.classes then
        hash = hash + (role.classes.all and 1 or 0) * roleIndex * columnMultiplier * 1100
        hash = hash + (role.classes.warrior and 1 or 0) * roleIndex * columnMultiplier * 1200
        hash = hash + (role.classes.rogue and 1 or 0) * roleIndex * columnMultiplier * 1300
        hash = hash + (role.classes.hunter and 1 or 0) * roleIndex * columnMultiplier * 1400
        hash = hash + (role.classes.paladin and 1 or 0) * roleIndex * columnMultiplier * 1500
        hash = hash + (role.classes.priest and 1 or 0) * roleIndex * columnMultiplier * 1600
        hash = hash + (role.classes.shaman and 1 or 0) * roleIndex * columnMultiplier * 1700
        hash = hash + (role.classes.druid and 1 or 0) * roleIndex * columnMultiplier * 1800
        hash = hash + (role.classes.mage and 1 or 0) * roleIndex * columnMultiplier * 1900
        hash = hash + (role.classes.warlock and 1 or 0) * roleIndex * columnMultiplier * 2000
    end
    
    -- Hash consume data (item IDs and allowAlternate flags)
    if role.consumes then
        for k, consume in ipairs(role.consumes) do
            if consume.primaryId then
                hash = hash + consume.primaryId * roleIndex * columnMultiplier * k * 2100
            end
            if consume.secondaryId then
                hash = hash + consume.secondaryId * roleIndex * columnMultiplier * k * 2200
            end
            hash = hash + (consume.allowAlternate and 1 or 0) * roleIndex * columnMultiplier * k * 2300
        end
    end
    
    -- Hash class priority (per-slot class ordering)
    if role.classPriority then
        for slotIndex, classList in pairs(role.classPriority) do
            if type(classList) == "table" then
                local slotNum = tonumber(slotIndex) or 0
                for classIndex, className in ipairs(classList) do
                    if type(className) == "string" then
                        for j = 1, string.len(className) do
                            hash = hash + string.byte(className, j) * roleIndex * columnMultiplier * slotNum * classIndex * 3000
                        end
                    end
                end
            end
        end
    end
    
    -- Hash class priority roles (role checkboxes per class per slot)
    if role.classPriorityRoles then
        for slotIndex, classRoles in pairs(role.classPriorityRoles) do
            if type(classRoles) == "table" then
                local slotNum = tonumber(slotIndex) or 0
                for className, roles in pairs(classRoles) do
                    if type(className) == "string" and type(roles) == "table" then
                        -- Hash class name
                        for j = 1, string.len(className) do
                            hash = hash + string.byte(className, j) * roleIndex * columnMultiplier * slotNum * 4000
                        end
                        -- Hash role flags (Tanks, Healers, Melee, Ranged)
                        hash = hash + (roles.Tanks and 1 or 0) * roleIndex * columnMultiplier * slotNum * 4001
                        hash = hash + (roles.Healers and 1 or 0) * roleIndex * columnMultiplier * slotNum * 4002
                        hash = hash + (roles.Melee and 1 or 0) * roleIndex * columnMultiplier * slotNum * 4003
                        hash = hash + (roles.Ranged and 1 or 0) * roleIndex * columnMultiplier * slotNum * 4004
                    end
                end
            end
        end
    end
    
    -- Hash linked roles
    if role.linkedRoles then
        for i, linkedRoleIndex in ipairs(role.linkedRoles) do
            if type(linkedRoleIndex) == "number" then
                hash = hash + linkedRoleIndex * roleIndex * columnMultiplier * i * 5000
            end
        end
    end
    
    return hash
end

--[[
    ============================================================================
    SECTION 2: SERIALIZATION UTILITIES
    ============================================================================
]]

--[[
    Simple table-to-string serializer for checksum computation
    
    Lightweight serializer that produces consistent string output for hashing.
    NOT suitable for data transmission (use Serialize/Deserialize for that).
    
    @param tbl table - Table to serialize
    @param depth number - Current recursion depth (prevents infinite loops)
    @return string - Serialized representation
]]
local function SimpleSerialize(tbl, depth)
    depth = depth or 0
    if depth > 10 then 
        return "..." 
    end
    
    if type(tbl) ~= "table" then
        return tostring(tbl)
    end
    
    local parts = {}
    
    -- Sort keys for consistent ordering
    local keys = {}
    for k in pairs(tbl) do
        table.insert(keys, k)
    end
    table.sort(keys, function(a, b)
        return tostring(a) < tostring(b)
    end)
    
    for i = 1, table.getn(keys) do
        local k = keys[i]
        local v = tbl[k]
        
        table.insert(parts, tostring(k))
        table.insert(parts, "=")
        
        if type(v) == "table" then
            table.insert(parts, SimpleSerialize(v, depth + 1))
        else
            table.insert(parts, tostring(v))
        end
        table.insert(parts, ";")
    end
    
    return table.concat(parts, "")
end

--[[
    Serialize table to string (for data transmission)
    
    Delegates to OGAddonMsg.Serialize for robust serialization.
    Handles nested tables, strings, numbers, booleans.
    
    @param tbl table - Table to serialize
    @return string - Serialized representation
]]
function OGRH.SyncChecksum.Serialize(tbl)
    if OGAddonMsg and OGAddonMsg.Serialize then
        return OGAddonMsg.Serialize(tbl)
    end
    
    -- Fallback implementation if OGAddonMsg not available
    if type(tbl) ~= "table" then 
        return tostring(tbl) 
    end
    
    local result = "{"
    for k, v in pairs(tbl) do
        if type(k) == "string" then
            result = result .. k .. "="
        end
        
        if type(v) == "table" then
            result = result .. OGRH.SyncChecksum.Serialize(v) .. ","
        elseif type(v) == "string" then
            result = result .. string.format("%q", v) .. ","
        elseif type(v) == "number" or type(v) == "boolean" then
            result = result .. tostring(v) .. ","
        end
    end
    result = result .. "}"
    return result
end

--[[
    Deserialize string to table
    
    Delegates to OGAddonMsg.Deserialize for robust deserialization.
    Uses loadstring to evaluate serialized data.
    
    @param str string - Serialized table string
    @return table or nil - Deserialized table, or nil on error
]]
function OGRH.SyncChecksum.Deserialize(str)
    if OGAddonMsg and OGAddonMsg.Deserialize then
        return OGAddonMsg.Deserialize(str)
    end
    
    -- Fallback implementation if OGAddonMsg not available
    if not str or str == "" then 
        return nil 
    end
    
    local func = loadstring("return " .. str)
    if func then
        return func()
    end
    
    return nil
end

--[[
    Deep copy a table (recursively)
    
    Creates a complete copy of a table with no shared references.
    Handles nested tables and prevents infinite recursion.
    
    @param original table - Table to copy
    @param seen table - Internal tracking for circular references
    @return table - Deep copy of original
]]
function OGRH.SyncChecksum.DeepCopy(original, seen)
    seen = seen or {}
    local copy
    
    if type(original) == 'table' then
        if seen[original] then
            return seen[original]
        end
        copy = {}
        seen[original] = copy
        for k, v in pairs(original) do
            copy[OGRH.SyncChecksum.DeepCopy(k, seen)] = OGRH.SyncChecksum.DeepCopy(v, seen)
        end
    else
        copy = original
    end
    
    return copy
end

--[[
    ============================================================================
    SECTION 3: ENCOUNTER CHECKSUMS
    ============================================================================
]]

--[[
    Calculate checksum for a specific encounter's structure
    
    Includes: roles, raid marks, assignment numbers, announcements
    Does NOT include: player assignments (those are separate)
    
    Legacy function maintained for backward compatibility.
    Uses old v1 schema paths.
    
    @param raid string - Raid name
    @param encounter string - Encounter name
    @return string - Checksum value
]]
function OGRH.SyncChecksum.CalculateStructureChecksum(raid, encounter)
    OGRH.EnsureSV()
    
    if not OGRH_SV.encounterMgmt or not OGRH_SV.encounterMgmt.roles or
       not OGRH_SV.encounterMgmt.roles[raid] or
       not OGRH_SV.encounterMgmt.roles[raid][encounter] then
        return "0"
    end
    
    local roles = OGRH_SV.encounterMgmt.roles[raid][encounter]
    local checksum = 0
    
    -- Hash roles from both columns
    if roles.column1 then
        for i, role in ipairs(roles.column1) do
            checksum = checksum + OGRH.SyncChecksum.HashRole(role, 10, i)
        end
    end
    
    if roles.column2 then
        for i, role in ipairs(roles.column2) do
            checksum = checksum + OGRH.SyncChecksum.HashRole(role, 20, i)
        end
    end
    
    -- Include raid marks (position-sensitive)
    if OGRH_SV.encounterRaidMarks and OGRH_SV.encounterRaidMarks[raid] and
       OGRH_SV.encounterRaidMarks[raid][encounter] then
        local marks = OGRH_SV.encounterRaidMarks[raid][encounter]
        for roleIdx, roleMarks in pairs(marks) do
            for slotIdx, markValue in pairs(roleMarks) do
                if type(markValue) == "number" then
                    checksum = checksum + (markValue * slotIdx * roleIdx * 1000)
                end
            end
        end
    end
    
    -- Include assignment numbers (position-sensitive)
    if OGRH_SV.encounterAssignmentNumbers and OGRH_SV.encounterAssignmentNumbers[raid] and
       OGRH_SV.encounterAssignmentNumbers[raid][encounter] then
        local numbers = OGRH_SV.encounterAssignmentNumbers[raid][encounter]
        for roleIdx, roleNumbers in pairs(numbers) do
            for slotIdx, numberValue in pairs(roleNumbers) do
                if type(numberValue) == "number" then
                    checksum = checksum + (numberValue * slotIdx * roleIdx * 500)
                end
            end
        end
    end
    
    -- Include announcement template
    if OGRH_SV.encounterAnnouncements and OGRH_SV.encounterAnnouncements[raid] and
       OGRH_SV.encounterAnnouncements[raid][encounter] then
        local announcements = OGRH_SV.encounterAnnouncements[raid][encounter]
        if type(announcements) == "table" then
            for i, line in ipairs(announcements) do
                if type(line) == "string" then
                    for j = 1, string.len(line) do
                        checksum = checksum + string.byte(line, j) * i
                    end
                end
            end
        elseif type(announcements) == "string" then
            for j = 1, string.len(announcements) do
                checksum = checksum + string.byte(announcements, j)
            end
        end
    end
    
    return tostring(checksum)
end

--[[
    Calculate checksum for ALL structure data
    
    Used by addon version polls to detect if clients have matching data.
    Includes: raids, encounters, roles, marks, numbers, announcements, consumes, tradeItems, RGO
    
    @return string - Global structure checksum
]]
function OGRH.SyncChecksum.CalculateAllStructureChecksum()
    OGRH.EnsureSV()
    local checksum = 0
    local raidCount = 0
    local encounterCount = 0
    
    -- Hash raids list (v2 structure)
    if OGRH_SV.encounterMgmt and OGRH_SV.encounterMgmt.raids then
        for i = 1, table.getn(OGRH_SV.encounterMgmt.raids) do
            local raid = OGRH_SV.encounterMgmt.raids[i]
            local raidName = raid.name
            raidCount = raidCount + 1
            for j = 1, string.len(raidName) do
                checksum = checksum + string.byte(raidName, j) * i * 50
            end
            
            -- Hash raid-level advanced settings
            if raid.advancedSettings and raid.advancedSettings.consumeTracking then
                local ct = raid.advancedSettings.consumeTracking
                checksum = checksum + (ct.enabled and 1 or 0) * 50000023
                checksum = checksum + (ct.readyThreshold or 85) * 500029
                
                if ct.requiredFlaskRoles then
                    local roleNames = {"Tanks", "Healers", "Melee", "Ranged"}
                    for _, roleName in ipairs(roleNames) do
                        if ct.requiredFlaskRoles[roleName] then
                            for k = 1, string.len(roleName) do
                                checksum = checksum + string.byte(roleName, k) * (k + 311) * 1019
                            end
                        end
                    end
                end
            end
        end
    end
    
    -- Hash encounters (from nested structure)
    if OGRH_SV.encounterMgmt and OGRH_SV.encounterMgmt.raids then
        for i = 1, table.getn(OGRH_SV.encounterMgmt.raids) do
            local raid = OGRH_SV.encounterMgmt.raids[i]
            if raid.encounters then
                for j = 1, table.getn(raid.encounters) do
                    local encounter = raid.encounters[j]
                    local encounterName = encounter.name
                    encounterCount = encounterCount + 1
                    for k = 1, string.len(encounterName) do
                        checksum = checksum + string.byte(encounterName, k) * j * 100
                    end
                    
                    -- Hash encounter-level advanced settings (BigWigs, consume tracking)
                    if encounter.advancedSettings then
                        if encounter.advancedSettings.bigwigs then
                            local bw = encounter.advancedSettings.bigwigs
                            checksum = checksum + (bw.enabled and 1 or 0) * 10000019
                            
                            if bw.encounterId and bw.encounterId ~= "" then
                                for k = 1, string.len(bw.encounterId) do
                                    checksum = checksum + string.byte(bw.encounterId, k) * (k + 107) * 1009
                                end
                            end
                        end
                        
                        if encounter.advancedSettings.consumeTracking then
                            local ct = encounter.advancedSettings.consumeTracking
                            
                            -- Hash enabled flag (nil=inherit, false=disabled, true=enabled)
                            local enabledValue = 0
                            if ct.enabled == true then
                                enabledValue = 2
                            elseif ct.enabled == false then
                                enabledValue = 1
                            end
                            checksum = checksum + enabledValue * 100000037
                            
                            -- Hash ready threshold
                            if ct.readyThreshold ~= nil then
                                checksum = checksum + ct.readyThreshold * 1000039
                            end
                            
                            -- Hash required flask roles
                            if ct.requiredFlaskRoles then
                                local roleNames = {"Tanks", "Healers", "Melee", "Ranged"}
                                for _, roleName in ipairs(roleNames) do
                                    if ct.requiredFlaskRoles[roleName] ~= nil then
                                        for k = 1, string.len(roleName) do
                                            checksum = checksum + string.byte(roleName, k) * (k + 211) * 1013
                                        end
                                        local roleValue = ct.requiredFlaskRoles[roleName] and 2 or 1
                                        checksum = checksum + roleValue * 1017
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    
    -- Hash all encounter roles
    if OGRH_SV.encounterMgmt and OGRH_SV.encounterMgmt.roles then
        for raidName, raids in pairs(OGRH_SV.encounterMgmt.roles) do
            for encounterName, encounter in pairs(raids) do
                if encounter.column1 then
                    for i, role in ipairs(encounter.column1) do
                        checksum = checksum + OGRH.SyncChecksum.HashRole(role, 10, i)
                    end
                end
                
                if encounter.column2 then
                    for i, role in ipairs(encounter.column2) do
                        checksum = checksum + OGRH.SyncChecksum.HashRole(role, 20, i)
                    end
                end
            end
        end
    end
    
    -- Hash all raid marks
    if OGRH_SV.encounterRaidMarks then
        for raidName, raids in pairs(OGRH_SV.encounterRaidMarks) do
            for encounterName, encounter in pairs(raids) do
                for roleIdx, roleMarks in pairs(encounter) do
                    for slotIdx, markValue in pairs(roleMarks) do
                        if type(markValue) == "number" then
                            checksum = checksum + (markValue * slotIdx * roleIdx * 1000)
                        end
                    end
                end
            end
        end
    end
    
    -- Hash all assignment numbers
    if OGRH_SV.encounterAssignmentNumbers then
        for raidName, raids in pairs(OGRH_SV.encounterAssignmentNumbers) do
            for encounterName, encounter in pairs(raids) do
                for roleIdx, roleNumbers in pairs(encounter) do
                    for slotIdx, numberValue in pairs(roleNumbers) do
                        if type(numberValue) == "number" then
                            checksum = checksum + (numberValue * slotIdx * roleIdx * 500)
                        end
                    end
                end
            end
        end
    end
    
    -- Hash all announcements
    if OGRH_SV.encounterAnnouncements then
        for raidName, raids in pairs(OGRH_SV.encounterAnnouncements) do
            for encounterName, announcements in pairs(raids) do
                if type(announcements) == "table" then
                    for i, line in ipairs(announcements) do
                        if type(line) == "string" then
                            for j = 1, string.len(line) do
                                checksum = checksum + string.byte(line, j) * i
                            end
                        end
                    end
                elseif type(announcements) == "string" then
                    for j = 1, string.len(announcements) do
                        checksum = checksum + string.byte(announcements, j)
                    end
                end
            end
        end
    end
    
    -- Hash tradeItems
    if OGRH_SV.tradeItems then
        for itemName, itemData in pairs(OGRH_SV.tradeItems) do
            for j = 1, string.len(itemName) do
                checksum = checksum + string.byte(itemName, j) * 30
            end
        end
    end
    
    -- Hash consumes
    local consumes = OGRH.SVM and OGRH.SVM.Get("consumes") or OGRH_SV.consumes
    if consumes then
        for consumeName, consumeData in pairs(consumes) do
            for j = 1, string.len(consumeName) do
                checksum = checksum + string.byte(consumeName, j) * 40
            end
        end
    end
    
    -- Hash RGO data
    if OGRH_SV.rgo then
        if OGRH_SV.rgo.currentRaidSize then
            local sizeStr = tostring(OGRH_SV.rgo.currentRaidSize)
            for j = 1, string.len(sizeStr) do
                checksum = checksum + string.byte(sizeStr, j) * 6000
            end
        end
        
        if OGRH_SV.rgo.raidSizes then
            for raidSize, groups in pairs(OGRH_SV.rgo.raidSizes) do
                local sizeNum = tonumber(raidSize) or 0
                checksum = checksum + sizeNum * 7000
                
                for groupNum, players in pairs(groups) do
                    if type(players) == "table" then
                        checksum = checksum + table.getn(players) * groupNum * 8000
                    end
                end
            end
        end
    end
    
    return tostring(checksum)
end

--[[
    ============================================================================
    SECTION 4: RAID CHECKSUMS (V2 Schema)
    ============================================================================
]]

--[[
    Compute checksum for a raid (by name from v2 structure)
    
    Strips assignments to create a structure-only checksum.
    Used by Active Raid integrity polling system.
    
    @param raidName string - Raid name to compute checksum for
    @return string - Structure checksum (excludes assignments)
]]
function OGRH.SyncChecksum.ComputeRaidChecksum(raidName)
    local sv = OGRH_SV.v2
    if not sv or not sv.encounterMgmt or not sv.encounterMgmt.raids then
        return "0"
    end
    
    -- Find raid by name
    local targetRaid = nil
    for i = 1, table.getn(sv.encounterMgmt.raids) do
        if sv.encounterMgmt.raids[i].name == raidName then
            targetRaid = sv.encounterMgmt.raids[i]
            break
        end
    end
    
    if not targetRaid then
        return "0"
    end
    
    -- Deep copy and strip assignments for structure-only checksum
    local raidCopy = OGRH.SyncChecksum.DeepCopy(targetRaid)
    if raidCopy.encounters then
        for i = 1, table.getn(raidCopy.encounters) do
            if raidCopy.encounters[i].roles then
                for j = 1, table.getn(raidCopy.encounters[i].roles) do
                    raidCopy.encounters[i].roles[j].assignedPlayers = nil
                    raidCopy.encounters[i].roles[j].raidMarks = nil
                    raidCopy.encounters[i].roles[j].assignmentNumbers = nil
                end
            end
        end
    end
    
    -- Serialize and hash
    local serialized = SimpleSerialize(raidCopy)
    return OGRH.SyncChecksum.HashString(serialized)
end

--[[
    Compute Active Raid assignments checksum for a specific encounter
    
    Only includes assignments (assignedPlayers, raidMarks, assignmentNumbers).
    Used for detecting assignment mismatches during live execution.
    
    @param encounterIdx number - Encounter index in Active Raid
    @return string - Assignments-only checksum
]]
function OGRH.SyncChecksum.ComputeActiveAssignmentsChecksum(encounterIdx)
    local activeRaid = OGRH.GetActiveRaid and OGRH.GetActiveRaid()
    if not activeRaid or not activeRaid.encounters or not activeRaid.encounters[encounterIdx] then
        return "0"
    end
    
    local encounter = activeRaid.encounters[encounterIdx]
    if not encounter.roles then
        return "0"
    end
    
    -- Extract only assignments (assignedPlayers, raidMarks, assignmentNumbers)
    local assignments = {}
    for i = 1, table.getn(encounter.roles) do
        local role = encounter.roles[i]
        assignments[i] = {
            assignedPlayers = role.assignedPlayers or {},
            raidMarks = role.raidMarks or {},
            assignmentNumbers = role.assignmentNumbers or {}
        }
    end
    
    -- Serialize and hash
    local serialized = SimpleSerialize(assignments)
    return OGRH.SyncChecksum.HashString(serialized)
end

--[[
    Calculate checksum for RolesUI (global role assignments)
    
    Includes TANKS, HEALERS, MELEE, RANGED bucket assignments.
    Used for detecting role assignment mismatches.
    
    @return string - RolesUI checksum
]]
function OGRH.SyncChecksum.CalculateRolesUIChecksum()
    local sv = OGRH_SV.v2
    if not sv or not sv.roles then
        return "0"
    end
    
    -- Create sorted list for consistent checksum
    local sortedRoles = {}
    for playerName, role in pairs(sv.roles) do
        table.insert(sortedRoles, playerName .. "=" .. role)
    end
    table.sort(sortedRoles)
    
    local roleString = table.concat(sortedRoles, "|")
    return OGRH.SyncChecksum.HashString(roleString)
end

--[[
    Compute checksums for global components
    
    Includes: consumes, tradeItems
    Used for detecting global data mismatches.
    
    @return table - Table of component checksums {consumes="...", tradeItems="..."}
]]
function OGRH.SyncChecksum.GetGlobalComponentChecksums()
    local sv = OGRH_SV.v2
    if not sv then
        return {}
    end
    
    local checksums = {}
    
    -- Consumes checksum
    if sv.consumes then
        local serialized = SimpleSerialize(sv.consumes)
        checksums.consumes = OGRH.SyncChecksum.HashString(serialized)
    else
        checksums.consumes = "0"
    end
    
    -- TradeItems checksum
    if sv.tradeItems then
        local serialized = SimpleSerialize(sv.tradeItems)
        checksums.tradeItems = OGRH.SyncChecksum.HashString(serialized)
    else
        checksums.tradeItems = "0"
    end
    
    return checksums
end

--[[
    ============================================================================
    SECTION 5: DIRTY TRACKING (Placeholder)
    ============================================================================
    
    These functions are called by SavedVariablesManager to track which
    components need to be synced. Currently implemented as no-ops since
    the actual dirty tracking logic hasn't been migrated yet.
    
    TODO: Implement proper dirty tracking when consolidating sync logic
]]

--[[
    Mark an encounter as dirty (needs sync)
    
    @param raidIdx number - Raid index
    @param encounterIdx number - Encounter index
]]
function OGRH.SyncChecksum.MarkEncounterDirty(raidIdx, encounterIdx)
    -- Placeholder: actual implementation in future consolidation phase
    -- For now, this is a no-op
end

--[[
    Mark a raid as dirty (needs sync)
    
    @param raidIdx number - Raid index
]]
function OGRH.SyncChecksum.MarkRaidDirty(raidIdx)
    -- Placeholder: actual implementation in future consolidation phase
    -- For now, this is a no-op
end

--[[
    Mark a global component as dirty (needs sync)
    
    @param componentType string - Component type (e.g., "roles", "consumes")
]]
function OGRH.SyncChecksum.MarkComponentDirty(componentType)
    -- Placeholder: actual implementation in future consolidation phase
    -- For now, this is a no-op
end

--[[
    ============================================================================
    SECTION 6: BACKWARD COMPATIBILITY WRAPPERS
    ============================================================================
    
    These maintain compatibility with existing code that calls OGRH.* functions.
    All new code should use OGRH.SyncChecksum.* directly.
    
    Debug mode: Set OGRH_CHECKSUM_DEBUG = true to log all wrapper calls
]]

-- Debug flag for tracking legacy function calls
OGRH_CHECKSUM_DEBUG = true  -- Set to false to disable wrapper debug logging

-- Helper function to log wrapper calls
local function LogWrapperCall(funcName)
    if not OGRH_CHECKSUM_DEBUG then return end
    
    if OGRH and OGRH.Msg then
        OGRH.Msg(string.format("|cffff9900[CHECKSUM-WRAPPER]|r %s called", funcName))
    end
end

-- Hashing
OGRH.HashString = function(str)
    LogWrapperCall("OGRH.HashString")
    return OGRH.SyncChecksum.HashString(str)
end

OGRH.HashRole = function(role, columnMultiplier, roleIndex)
    LogWrapperCall("OGRH.HashRole")
    return OGRH.SyncChecksum.HashRole(role, columnMultiplier, roleIndex)
end

-- Checksums (legacy v1 schema)
OGRH.CalculateStructureChecksum = function(raid, encounter)
    LogWrapperCall("OGRH.CalculateStructureChecksum")
    return OGRH.SyncChecksum.CalculateStructureChecksum(raid, encounter)
end

OGRH.CalculateAllStructureChecksum = function()
    LogWrapperCall("OGRH.CalculateAllStructureChecksum")
    return OGRH.SyncChecksum.CalculateAllStructureChecksum()
end

OGRH.CalculateRolesUIChecksum = function()
    LogWrapperCall("OGRH.CalculateRolesUIChecksum")
    return OGRH.SyncChecksum.CalculateRolesUIChecksum()
end

-- Checksums (v2 schema)
OGRH.ComputeRaidChecksum = function(raidName)
    LogWrapperCall("OGRH.ComputeRaidChecksum")
    return OGRH.SyncChecksum.ComputeRaidChecksum(raidName)
end

OGRH.ComputeActiveAssignmentsChecksum = function(encounterIdx)
    LogWrapperCall("OGRH.ComputeActiveAssignmentsChecksum")
    return OGRH.SyncChecksum.ComputeActiveAssignmentsChecksum(encounterIdx)
end

OGRH.GetGlobalComponentChecksums = function()
    LogWrapperCall("OGRH.GetGlobalComponentChecksums")
    return OGRH.SyncChecksum.GetGlobalComponentChecksums()
end

-- Serialization
OGRH.Serialize = function(tbl)
    LogWrapperCall("OGRH.Serialize")
    return OGRH.SyncChecksum.Serialize(tbl)
end

OGRH.Deserialize = function(str)
    LogWrapperCall("OGRH.Deserialize")
    return OGRH.SyncChecksum.Deserialize(str)
end

OGRH.DeepCopy = function(tbl)
    LogWrapperCall("OGRH.DeepCopy")
    return OGRH.SyncChecksum.DeepCopy(tbl)
end

--[[
    ============================================================================
    INITIALIZATION
    ============================================================================
]]

-- Module initialization
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:SetScript("OnEvent", function()
    if event == "ADDON_LOADED" and arg1 == "OG-RaidHelper" then
        OGRH.Msg("|cff00ccff[RH-SyncChecksum]|r Checksum & serialization utilities loaded")
    end
end)
