--[[
    OG-RaidHelper: SyncRepair.lua
    
    Packet construction and application for hierarchical structure repairs.
    Handles all 4 layers of the checksum hierarchy.
    
    PHASE 3 IMPLEMENTATION (STUB)
    
    Responsibilities:
    - Admin repair packet construction (Layer 1-4)
    - Client packet application
    - Validation checksum computation
    - Adaptive pacing with queue monitoring
    - Repair priority ordering (selected encounter first)
]]

if not OGRH then OGRH = {} end
if not OGRH.SyncRepair then OGRH.SyncRepair = {} end

--[[
    ============================================================================
    MODULE STATE
    ============================================================================
]]

OGRH.SyncRepair.State = {
    -- Adaptive pacing
    lastPacketTime = 0,           -- timestamp of last packet sent
    currentDelay = 0.1,           -- current adaptive delay (0.05s - 1.0s)
    
    -- Repair tracking
    packetsInFlight = 0,          -- number of packets sent but not applied
    totalPacketsExpected = 0,     -- total packets for current repair
}

--[[
    ============================================================================
    PHASE 3 FUNCTION STUBS - ADMIN PACKET CONSTRUCTION
    ============================================================================
]]

--[[
    ============================================================================
    LAYER 1: STRUCTURE REPAIR PACKETS
    ============================================================================
]]

-- Build structure packet for active raid (raids[1])
-- Returns: packet table ready for serialization
function OGRH.SyncRepair.BuildStructurePacket()
    local sv = OGRH.SVM and OGRH.SVM.GetActiveSchema() or OGRH_SV.v2
    if not sv or not sv.encounterMgmt or not sv.encounterMgmt.raids then
        return nil
    end
    
    -- Active Raid is always raids[1]
    local raid = sv.encounterMgmt.raids[1]
    if not raid then
        return nil
    end
    
    -- Extract structure (raid metadata only, not global roles)
    local structure = {
        name = raid.name,
        displayName = raid.displayName,
        enabled = raid.enabled,
        autoRank = raid.autoRank,
        advancedSettings = raid.advancedSettings,
        encounterCount = raid.encounters and table.getn(raid.encounters) or 0
    }
    
    return {
        type = "STRUCTURE",
        layer = 1,
        data = structure,
        timestamp = GetTime()
    }
end

function OGRH.SyncRepair.SendStructurePacket(packet, token) 
    -- TODO: Implement sending via OGAddonMsg
end

-- Build RolesUI packet for global role assignments
function OGRH.SyncRepair.BuildRolesUIPacket()
    local sv = OGRH.SVM and OGRH.SVM.GetActiveSchema() or OGRH_SV.v2
    if not sv then
        return nil
    end
    
    -- Extract global role assignments (TANKS/HEALERS/MELEE/RANGED buckets)
    local rolesUI = {
        roles = sv.roles or {}
    }
    
    return {
        type = "ROLESUI",
        layer = "1b",
        data = rolesUI,
        timestamp = GetTime()
    }
end

--[[
    ============================================================================
    LAYER 2: ENCOUNTERS REPAIR PACKETS
    ============================================================================
]]

-- Build encounters packets for active raid (raids[1])
-- Returns: array of packets
function OGRH.SyncRepair.BuildEncountersPackets(encounterIndices)
    local sv = OGRH.SVM and OGRH.SVM.GetActiveSchema() or OGRH_SV.v2
    if not sv or not sv.encounterMgmt or not sv.encounterMgmt.raids then
        return {}
    end
    
    -- Active Raid is always raids[1]
    local raid = sv.encounterMgmt.raids[1]
    if not raid or not raid.encounters then
        return {}
    end
    
    local packets = {}
    local indices = encounterIndices or {}
    
    -- If no specific indices, do all encounters
    if table.getn(indices) == 0 then
        for i = 1, table.getn(raid.encounters) do
            table.insert(indices, i)
        end
    end
    
    for i = 1, table.getn(indices) do
        local encIdx = indices[i]
        local encounter = raid.encounters[encIdx]
        
        if encounter then
            -- Extract encounter metadata + roles structure (no assignments)
            local encData = {
                index = encIdx,
                name = encounter.name,
                displayName = encounter.displayName,
                announcements = encounter.announcements,
                advancedSettings = encounter.advancedSettings,
                roles = {}
            }
            
            -- Include COMPLETE roles (including assignedPlayers)
            if encounter.roles then
                for roleIdx = 1, table.getn(encounter.roles) do
                    local role = encounter.roles[roleIdx]
                    
                    -- Copy ALL fields (complete role)
                    local roleCopy = {}
                    for k, v in pairs(role) do
                        roleCopy[k] = v
                    end
                    
                    -- DEBUG: Log what we're sending
                    local playerCount = roleCopy.assignedPlayers and table.getn(roleCopy.assignedPlayers) or 0
                    OGRH.Msg(string.format("|cffff9900[RH-SyncRepair]|r BUILD: Enc %d Role %d: name='%s', column=%s, slots=%s, players=%d",
                        encIdx, roleIdx, 
                        roleCopy.name or "NIL",
                        tostring(roleCopy.column),
                        tostring(roleCopy.slots),
                        playerCount))
                    
                    encData.roles[roleIdx] = roleCopy
                end
            end
            
            local pkt = {
                type = "ENCOUNTER",
                layer = 2,
                encounterIndex = encIdx,
                data = encData,
                timestamp = GetTime()
            }
            
            table.insert(packets, pkt)
        end
    end
    
    return packets
end

function OGRH.SyncRepair.SendEncountersPackets(packets, token) 
    -- TODO: Implement sending via OGAddonMsg
end

--[[
    ============================================================================
    LAYER 3: ROLES REPAIR PACKETS
    ============================================================================
]]

-- Build roles packets for specific encounter/roles
-- Returns: array of packets
function OGRH.SyncRepair.BuildRolesPackets(encounterIdx, roleIndices)
    local sv = OGRH.SVM and OGRH.SVM.GetActiveSchema() or OGRH_SV.v2
    if not sv or not sv.encounterMgmt or not sv.encounterMgmt.raids then
        return {}
    end
    
    -- Active Raid is always raids[1]
    local raid = sv.encounterMgmt.raids[1]
    if not raid or not raid.encounters or not raid.encounters[encounterIdx] then
        return {}
    end
    
    local encounter = raid.encounters[encounterIdx]
    if not encounter.roles then
        return {}
    end
    
    local packets = {}
    local indices = roleIndices or {}
    
    -- If no specific indices, do all roles
    if table.getn(indices) == 0 then
        for i = 1, table.getn(encounter.roles) do
            table.insert(indices, i)
        end
    end
    
    for i = 1, table.getn(indices) do
        local roleIdx = indices[i]
        local role = encounter.roles[roleIdx]
        
        if role then
            -- Extract role configuration (no assignments)
            local roleData = {
                index = roleIdx,
                name = role.name,
                priority = role.priority,
                faction = role.faction,
                isOptionalRole = role.isOptionalRole,
                slotCount = role.assignedPlayers and table.getn(role.assignedPlayers) or 0
            }
            
            table.insert(packets, {
                type = "ROLE",
                layer = 3,
                encounterIndex = encounterIdx,
                roleIndex = roleIdx,
                data = roleData,
                timestamp = GetTime()
            })
        end
    end
    
    return packets
end

function OGRH.SyncRepair.SendRolesPackets(packets, token, encounterIdx) 
    -- TODO: Implement sending via OGAddonMsg
end

--[[
    ============================================================================
    LAYER 4: ASSIGNMENTS REPAIR PACKETS
    ============================================================================
]]

-- Build assignments packets for specific encounter/roles
-- Returns: array of packets
function OGRH.SyncRepair.BuildAssignmentsPackets(encounterIdx, roleIndices)
    local sv = OGRH.SVM and OGRH.SVM.GetActiveSchema() or OGRH_SV.v2
    if not sv or not sv.encounterMgmt or not sv.encounterMgmt.raids then
        return {}
    end
    
    -- Active Raid is always raids[1]
    local raid = sv.encounterMgmt.raids[1]
    if not raid or not raid.encounters or not raid.encounters[encounterIdx] then
        return {}
    end
    
    local encounter = raid.encounters[encounterIdx]
    if not encounter.roles then
        return {}
    end
    
    local packets = {}
    local indices = roleIndices or {}
    
    -- If no specific indices, do all roles
    if table.getn(indices) == 0 then
        for i = 1, table.getn(encounter.roles) do
            table.insert(indices, i)
        end
    end
    
    for i = 1, table.getn(indices) do
        local roleIdx = indices[i]
        local role = encounter.roles[roleIdx]
        
        if role then
            -- Extract assignments only
            local assignmentsData = {
                index = roleIdx,
                assignedPlayers = role.assignedPlayers or {},
                raidMarks = role.raidMarks or {},
                assignmentNumbers = role.assignmentNumbers or {}
            }
            
            table.insert(packets, {
                type = "ASSIGNMENTS",
                layer = 4,
                encounterIndex = encounterIdx,
                roleIndex = roleIdx,
                data = assignmentsData,
                timestamp = GetTime()
            })
        end
    end
    
    return packets
end

function OGRH.SyncRepair.SendAssignmentsPackets(packets, token, encounterIdx) 
    -- TODO: Implement sending via OGAddonMsg
end

-- Priority Ordering
function OGRH.SyncRepair.DetermineRepairPriority(selectedEncounterIdx, failedLayers) 
    if not failedLayers then
        return {}
    end
    -- TODO: Implement priority ordering (selected encounter first)
    return {}
end

--[[
    ============================================================================
    PHASE 3 FUNCTION STUBS - CLIENT PACKET APPLICATION
    ============================================================================
]]

-- Layer 1: Apply Structure to active raid (raids[1])
function OGRH.SyncRepair.ApplyStructurePacket(packet)
    if not packet or packet.type ~= "STRUCTURE" or not packet.data then
        OGRH.Msg("|cffff0000[RH-SyncRepair]|r Invalid STRUCTURE packet")
        return false
    end
    
    local sv = OGRH.SVM and OGRH.SVM.GetActiveSchema() or OGRH_SV.v2
    if not sv or not sv.encounterMgmt or not sv.encounterMgmt.raids then
        OGRH.Msg("|cffff0000[RH-SyncRepair]|r No encounterMgmt available")
        return false
    end
    
    -- Active Raid is ALWAYS raids[1]
    local raid = sv.encounterMgmt.raids[1]
    if not raid then
        OGRH.Msg("|cffff0000[RH-SyncRepair]|r No active raid (raids[1])")
        return false
    end
    
    local structure = packet.data
    
    -- Apply structure fields (NOT name - that's always "[ACTIVE RAID]")
    raid.displayName = structure.displayName
    raid.enabled = structure.enabled
    raid.autoRank = structure.autoRank
    raid.advancedSettings = structure.advancedSettings
    
    -- CRITICAL: Resize encounters array to match admin's count
    -- Clear all existing encounters and create empty stubs
    local targetCount = structure.encounterCount or 0
    raid.encounters = {}
    for i = 1, targetCount do
        raid.encounters[i] = {
            name = "",  -- Will be filled by encounter repair
            displayName = "",
            announcements = {},
            advancedSettings = {},
            roles = {}
        }
    end
    
    return true
end

-- Layer 1b: Apply RolesUI (global roles)
function OGRH.SyncRepair.ApplyRolesUIPacket(packet)
    if not packet or packet.type ~= "ROLESUI" or not packet.data then
        OGRH.Msg("|cffff0000[RH-SyncRepair]|r Invalid ROLESUI packet")
        return false
    end
    
    local sv = OGRH.SVM and OGRH.SVM.GetActiveSchema() or OGRH_SV.v2
    if not sv then
        OGRH.Msg("|cffff0000[RH-SyncRepair]|r No SavedVariables available")
        return false
    end
    
    -- Apply global role assignments (TANKS/HEALERS/MELEE/RANGED buckets)
    sv.roles = packet.data.roles or {}
    
    OGRH.Msg("|cff00ff00[RH-SyncRepair]|r Applied RolesUI (global roles)")
    
    return true
end

-- Layer 2: Apply Encounters
function OGRH.SyncRepair.ApplyEncountersPacket(packet)
    if not packet or packet.type ~= "ENCOUNTER" or not packet.data then
        OGRH.Msg("|cffff0000[RH-SyncRepair]|r ENCOUNTER: Invalid packet or type")
        return false
    end
    
    local sv = OGRH.SVM and OGRH.SVM.GetActiveSchema() or OGRH_SV.v2
    if not sv or not sv.encounterMgmt or not sv.encounterMgmt.raids then
        OGRH.Msg("|cffff0000[RH-SyncRepair]|r ENCOUNTER: No SavedVariables")
        return false
    end
    
    -- Active Raid is always raids[1]
    local raid = sv.encounterMgmt.raids[1]
    if not raid or not raid.encounters then
        OGRH.Msg("|cffff0000[RH-SyncRepair]|r ENCOUNTER: No raid or encounters array")
        return false
    end
    
    local encIdx = packet.encounterIndex
    local encounter = raid.encounters[encIdx]
    
    if not encounter then
        OGRH.Msg(string.format("|cffff0000[RH-SyncRepair]|r ENCOUNTER: Encounter %d not found (total: %d)", 
            encIdx, table.getn(raid.encounters)))
        return false
    end
    
    local encData = packet.data
    
    -- Apply encounter fields (including name - critical for lookups)
    encounter.name = encData.name
    encounter.displayName = encData.displayName
    encounter.announcements = encData.announcements
    encounter.advancedSettings = encData.advancedSettings
    
    -- COMPLETELY REPLACE roles array to avoid orphaned roles
    if encData.roles then
        local roleCount = table.getn(encData.roles)
        OGRH.Msg(string.format("|cff00ccff[RH-SyncRepair]|r ENCOUNTER: Packet has %d roles for encounter %d (%s)", 
            roleCount, encIdx, encData.displayName or encData.name or "Unknown"))
        
        encounter.roles = {}  -- Clear existing roles
        
        for roleIdx = 1, roleCount do
            local roleData = encData.roles[roleIdx]
            
            if roleData then
                -- DEBUG: Log what we're receiving
                local playerCount = roleData.assignedPlayers and table.getn(roleData.assignedPlayers) or 0
                OGRH.Msg(string.format("|cff00ccff[RH-SyncRepair]|r ENCOUNTER: Received role %d data: name='%s', column=%s, slots=%s, players=%d",
                    roleIdx,
                    roleData.name or "NIL",
                    tostring(roleData.column),
                    tostring(roleData.slots),
                    playerCount))
                
                -- Copy ALL received fields (complete role including assignedPlayers)
                local newRole = {}
                for k, v in pairs(roleData) do
                    newRole[k] = v
                end
                
                encounter.roles[roleIdx] = newRole
                OGRH.Msg(string.format("|cff00ccff[RH-SyncRepair]|r ENCOUNTER: Created role %d: '%s' with %d players", 
                    roleIdx, roleData.name or "Unknown", playerCount))
            else
                OGRH.Msg(string.format("|cffff0000[RH-SyncRepair]|r ENCOUNTER: Role %d data is NIL!", roleIdx))
            end
        end
        
        OGRH.Msg(string.format("|cff00ff00[RH-SyncRepair]|r ENCOUNTER: Successfully applied %d roles to encounter %d", 
            table.getn(encounter.roles), encIdx))
        
        -- VERIFY: Dump role names to confirm they still exist
        for verifyIdx = 1, table.getn(encounter.roles) do
            local r = encounter.roles[verifyIdx]
            if r then
                OGRH.Msg(string.format("|cff00ff00[RH-SyncRepair]|r ENCOUNTER:   Verify role %d: name='%s', column=%s, slots=%s, fillOrder=%s", 
                    verifyIdx, r.name or "NIL", tostring(r.column), tostring(r.slots), tostring(r.fillOrder)))
            else
                OGRH.Msg(string.format("|cffff0000[RH-SyncRepair]|r ENCOUNTER:   Verify role %d: ROLE IS NIL!", verifyIdx))
            end
        end
    else
        OGRH.Msg(string.format("|cffff0000[RH-SyncRepair]|r ENCOUNTER: Packet has NO roles array for encounter %d!", encIdx))
    end
    
    return true
end

-- Layer 3: Apply Roles
function OGRH.SyncRepair.ApplyRolesPacket(packet)
    if not packet or packet.type ~= "ROLE" or not packet.data then
        return false
    end
    
    local sv = OGRH.SVM and OGRH.SVM.GetActiveSchema() or OGRH_SV.v2
    if not sv or not sv.encounterMgmt or not sv.encounterMgmt.raids then
        return false
    end
    
    -- Active Raid is always raids[1]
    local raid = sv.encounterMgmt.raids[1]
    if not raid or not raid.encounters then
        return false
    end
    
    local encounter = raid.encounters[packet.encounterIndex]
    if not encounter or not encounter.roles then
        return false
    end
    
    local roleIdx = packet.roleIndex
    local role = encounter.roles[roleIdx]
    local roleData = packet.data
    
    if not role then
        -- Create new role
        encounter.roles[roleIdx] = {
            name = roleData.name,
            priority = roleData.priority,
            faction = roleData.faction,
            isOptionalRole = roleData.isOptionalRole,
            assignedPlayers = {},
            raidMarks = {},
            assignmentNumbers = {}
        }
    else
        -- Update existing role, preserve assignments
        role.name = roleData.name
        role.priority = roleData.priority
        role.faction = roleData.faction
        role.isOptionalRole = roleData.isOptionalRole
    end
    
    return true
end

-- Layer 4: Apply Assignments
function OGRH.SyncRepair.ApplyAssignmentsPacket(packet)
    if not packet or packet.type ~= "ASSIGNMENTS" or not packet.data then
        OGRH.Msg("|cffff0000[RH-SyncRepair]|r ASSIGNMENTS: Invalid packet or type")
        return false
    end
    
    local sv = OGRH.SVM and OGRH.SVM.GetActiveSchema() or OGRH_SV.v2
    if not sv or not sv.encounterMgmt or not sv.encounterMgmt.raids then
        OGRH.Msg("|cffff0000[RH-SyncRepair]|r ASSIGNMENTS: No SavedVariables")
        return false
    end
    
    -- Active Raid is always raids[1]
    local raid = sv.encounterMgmt.raids[1]
    if not raid or not raid.encounters then
        OGRH.Msg("|cffff0000[RH-SyncRepair]|r ASSIGNMENTS: No raid or encounters array")
        return false
    end
    
    local encIdx = packet.encounterIndex
    local encounter = raid.encounters[encIdx]
    if not encounter then
        OGRH.Msg(string.format("|cffff0000[RH-SyncRepair]|r ASSIGNMENTS: Encounter %d not found (total: %d)", 
            encIdx, table.getn(raid.encounters)))
        return false
    end
    
    if not encounter.roles then
        OGRH.Msg(string.format("|cffff0000[RH-SyncRepair]|r ASSIGNMENTS: Encounter %d has no roles array", encIdx))
        return false
    end
    
    local roleIdx = packet.roleIndex
    local role = encounter.roles[roleIdx]
    
    if not role then
        OGRH.Msg(string.format("|cffff0000[RH-SyncRepair]|r ASSIGNMENTS: Role %d not found in encounter %d (total roles: %d)", 
            roleIdx, encIdx, table.getn(encounter.roles)))
        return false
    end
    
    local assignmentsData = packet.data
    local playerCount = assignmentsData.assignedPlayers and table.getn(assignmentsData.assignedPlayers) or 0
    
    -- Replace assignments
    role.assignedPlayers = assignmentsData.assignedPlayers or {}
    role.raidMarks = assignmentsData.raidMarks or {}
    role.assignmentNumbers = assignmentsData.assignmentNumbers or {}
    
    local roleName = role.name or "Unknown"
    local encName = encounter.displayName or encounter.name or "Unknown"
    OGRH.Msg(string.format("|cff00ff00[RH-SyncRepair]|r ASSIGNMENTS: Applied %d players to role '%s' (enc %d: %s)", 
        playerCount, roleName, encIdx, encName))
    
    return true
end

-- Generic dispatcher
function OGRH.SyncRepair.ApplyPacket(packet)
    if not packet or not packet.type then
        return false
    end
    
    if packet.type == "STRUCTURE" then
        return OGRH.SyncRepair.ApplyStructurePacket(packet)
    elseif packet.type == "ENCOUNTER" then
        return OGRH.SyncRepair.ApplyEncountersPacket(packet)
    elseif packet.type == "ROLE" then
        return OGRH.SyncRepair.ApplyRolesPacket(packet)
    elseif packet.type == "ASSIGNMENTS" then
        return OGRH.SyncRepair.ApplyAssignmentsPacket(packet)
    else
        return false
    end
end

--[[
    ============================================================================
    PHASE 3 - VALIDATION
    ============================================================================
]]

-- Compute checksums after applying packets for validation
-- Returns table matching the layerIds structure
function OGRH.SyncRepair.ComputeValidationChecksums(raidName, layerIds)
    if not raidName or not layerIds then
        return {}
    end
    
    local checksums = {}
    
    -- Layer 1: Structure checksum
    if layerIds.structure then
        checksums.structure = OGRH.SyncChecksum.ComputeRaidStructureChecksum(raidName)
    end
    
    -- Layer 2: Encounters checksums
    if layerIds.encounters and table.getn(layerIds.encounters) > 0 then
        checksums.encounters = {}
        local allEncounterChecksums = OGRH.SyncChecksum.ComputeEncountersChecksums(raidName)
        for i = 1, table.getn(layerIds.encounters) do
            local encIdx = layerIds.encounters[i]
            if allEncounterChecksums[encIdx] then
                checksums.encounters[encIdx] = allEncounterChecksums[encIdx]
            end
        end
    end
    
    -- Layer 3: Roles checksums
    if layerIds.roles then
        checksums.roles = {}
        local allRolesChecksums = OGRH.SyncChecksum.ComputeRolesChecksums(raidName)
        for encIdx, roleIndices in pairs(layerIds.roles) do
            if allRolesChecksums[encIdx] then
                checksums.roles[encIdx] = {}
                for i = 1, table.getn(roleIndices) do
                    local roleIdx = roleIndices[i]
                    if allRolesChecksums[encIdx][roleIdx] then
                        checksums.roles[encIdx][roleIdx] = allRolesChecksums[encIdx][roleIdx]
                    end
                end
            end
        end
    end
    
    -- Layer 4: Assignments checksums
    if layerIds.assignments then
        checksums.assignments = {}
        local allApRoleChecksums = OGRH.SyncChecksum.ComputeApRoleChecksums(raidName)
        for encIdx, roleIndices in pairs(layerIds.assignments) do
            if allApRoleChecksums[encIdx] then
                checksums.assignments[encIdx] = {}
                for i = 1, table.getn(roleIndices) do
                    local roleIdx = roleIndices[i]
                    if allApRoleChecksums[encIdx][roleIdx] then
                        checksums.assignments[encIdx][roleIdx] = allApRoleChecksums[encIdx][roleIdx]
                    end
                end
            end
        end
    end
    
    return checksums
end

-- Compare client checksums with admin checksums
-- Returns: success (boolean), mismatches (table of failed layers)
function OGRH.SyncRepair.ValidateRepair(raidName, adminChecksums, clientChecksums)
    if not raidName or not adminChecksums or not clientChecksums then
        return false, {}
    end
    
    local mismatches = {}
    
    -- Layer 1: Structure validation
    if adminChecksums.structure then
        if adminChecksums.structure ~= clientChecksums.structure then
            table.insert(mismatches, {
                layer = 1,
                type = "structure",
                admin = adminChecksums.structure,
                client = clientChecksums.structure
            })
        end
    end
    
    -- Layer 2: Encounters validation
    if adminChecksums.encounters then
        for encIdx, adminHash in pairs(adminChecksums.encounters) do
            local clientHash = clientChecksums.encounters and clientChecksums.encounters[encIdx]
            if adminHash ~= clientHash then
                table.insert(mismatches, {
                    layer = 2,
                    type = "encounter",
                    encounterIndex = encIdx,
                    admin = adminHash,
                    client = clientHash or "nil"
                })
            end
        end
    end
    
    -- Layer 3: Roles validation
    if adminChecksums.roles then
        for encIdx, roles in pairs(adminChecksums.roles) do
            for roleIdx, adminHash in pairs(roles) do
                local clientHash = clientChecksums.roles 
                    and clientChecksums.roles[encIdx] 
                    and clientChecksums.roles[encIdx][roleIdx]
                if adminHash ~= clientHash then
                    table.insert(mismatches, {
                        layer = 3,
                        type = "role",
                        encounterIndex = encIdx,
                        roleIndex = roleIdx,
                        admin = adminHash,
                        client = clientHash or "nil"
                    })
                end
            end
        end
    end
    
    -- Layer 4: Assignments validation
    if adminChecksums.assignments then
        for encIdx, roles in pairs(adminChecksums.assignments) do
            for roleIdx, adminHash in pairs(roles) do
                local clientHash = clientChecksums.assignments 
                    and clientChecksums.assignments[encIdx] 
                    and clientChecksums.assignments[encIdx][roleIdx]
                if adminHash ~= clientHash then
                    table.insert(mismatches, {
                        layer = 4,
                        type = "assignments",
                        encounterIndex = encIdx,
                        roleIndex = roleIdx,
                        admin = adminHash,
                        client = clientHash or "nil"
                    })
                end
            end
        end
    end
    
    local success = table.getn(mismatches) == 0
    return success, mismatches
end

--[[
    ============================================================================
    PHASE 3 - ADAPTIVE PACING
    ============================================================================
]]

-- Monitor OGAddonMsg queue depth
function OGRH.SyncRepair.GetQueueDepth()
    if OGAddonMsg and OGAddonMsg.stats and OGAddonMsg.stats.queueDepth then
        return OGAddonMsg.stats.queueDepth
    end
    return 0
end

-- Adjust delay based on queue pressure
-- Queue depth thresholds:
-- 0-5: Clear (0.05s)
-- 6-15: Light (0.1s)
-- 16-30: Moderate (0.2s)
-- 31-50: Heavy (0.5s)
-- 51+: Critical (1.0s)
function OGRH.SyncRepair.UpdateAdaptiveDelay()
    local queueDepth = OGRH.SyncRepair.GetQueueDepth()
    
    if queueDepth <= 5 then
        OGRH.SyncRepair.State.currentDelay = 0.05
    elseif queueDepth <= 15 then
        OGRH.SyncRepair.State.currentDelay = 0.1
    elseif queueDepth <= 30 then
        OGRH.SyncRepair.State.currentDelay = 0.2
    elseif queueDepth <= 50 then
        OGRH.SyncRepair.State.currentDelay = 0.5
    else
        OGRH.SyncRepair.State.currentDelay = 1.0
    end
end

-- Wait with adaptive delay, updating delay before each wait
function OGRH.SyncRepair.AdaptiveWait()
    OGRH.SyncRepair.UpdateAdaptiveDelay()
    local delay = OGRH.SyncRepair.State.currentDelay
    OGRH.SyncRepair.State.lastPacketTime = GetTime()
    
    -- Use coroutine-friendly wait if available, otherwise use timer
    if OGRH.ScheduleTimer then
        OGRH.ScheduleTimer(function() end, delay)
    end
end

--[[
    ============================================================================
    PHASE 3 - PRIORITY ORDERING
    ============================================================================
]]

-- Determine repair priority: selected encounter first, then remaining encounters sorted
-- Returns ordered array of encounter indices
function OGRH.SyncRepair.DetermineRepairPriority(raidName, selectedEncounterIdx, failedLayers)
    if not raidName or not failedLayers then
        return {}
    end
    
    local priority = {}
    local encIndices = {}
    
    -- Collect all unique encounter indices from failed layers
    if failedLayers.encounters then
        for i = 1, table.getn(failedLayers.encounters) do
            local encIdx = failedLayers.encounters[i]
            encIndices[encIdx] = true
        end
    end
    
    if failedLayers.roles then
        for encIdx, _ in pairs(failedLayers.roles) do
            encIndices[encIdx] = true
        end
    end
    
    if failedLayers.assignments then
        for encIdx, _ in pairs(failedLayers.assignments) do
            encIndices[encIdx] = true
        end
    end
    
    -- Add selected encounter first if it has failures
    if selectedEncounterIdx and encIndices[selectedEncounterIdx] then
        table.insert(priority, selectedEncounterIdx)
        encIndices[selectedEncounterIdx] = nil
    end
    
    -- Add remaining encounters in sorted order
    local remaining = {}
    for encIdx, _ in pairs(encIndices) do
        table.insert(remaining, encIdx)
    end
    table.sort(remaining)
    
    for i = 1, table.getn(remaining) do
        table.insert(priority, remaining[i])
    end
    
    return priority
end

--[[
    ============================================================================
    MODULE INITIALIZATION
    ============================================================================
]]

function OGRH.SyncRepair.Initialize()
    -- Phase 3 implementation placeholder
    -- Module state initialized at declaration
end

-- Auto-initialize on load
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:SetScript("OnEvent", function()
    if event == "ADDON_LOADED" and arg1 == "OG-RaidHelper" then
        OGRH.ScheduleTimer(function()
            OGRH.SyncRepair.Initialize()
        end, 0.5)
    end
end)
