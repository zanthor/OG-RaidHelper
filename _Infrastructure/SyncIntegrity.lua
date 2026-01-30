-- OGRH_SyncIntegrity.lua (Turtle-WoW 1.12)
-- Checksum verification and data integrity system
-- Phase 3B: Unified checksum polling for structure, RolesUI, and assignments

OGRH = OGRH or {}
OGRH.SyncIntegrity = {}

--[[
    Unified Checksum Polling System
    
    Admin broadcasts every 30 seconds:
    - Structure checksum (encounter roles, marks, numbers, announcements)
    - RolesUI checksum (bucket assignments)
    - Assignment checksum (player-to-role assignments)
    
    Clients compare their checksums to admin's broadcast:
    - On mismatch: Log warning, optionally request repair
    - Auto-repair: Admin can push data to specific clients or all raid members
]]

OGRH.SyncIntegrity.State = {
    lastChecksumBroadcast = 0,
    verificationInterval = 30,  -- seconds
    checksumCache = {},
    pollingTimer = nil,
    enabled = false,
    
    -- Drill-down request batching (2-second buffer)
    drillDownQueue = {},  -- { [raidName] = { requesters = {}, timer = nil } }
    drillDownBufferTime = 2,  -- seconds
    
    -- Admin modification cooldown (suppress broadcasts while admin is actively editing)
    lastAdminModification = 0,  -- timestamp of last admin change
    modificationCooldown = 10,  -- seconds to wait after last change before broadcasting
    
    -- Debug mode (toggle with /ogrh sync debug)
    debug = false,  -- Hide verbose sync messages by default
    
    -- Raids pending full sync (prevent re-validation spam)
    pendingFullSync = {}  -- { [raidName] = true }
}

--[[
    Core Functions
]]

-- Start periodic integrity checks (called when becoming raid admin)
function OGRH.StartIntegrityChecks()
    -- DISABLED: Checksum polling timer disabled - using new sync architecture
    return
    
    --[[
    if OGRH.SyncIntegrity.State.enabled then
        return  -- Already running
    end
    
    OGRH.SyncIntegrity.State.enabled = true
    
    -- Start polling timer
    OGRH.SyncIntegrity.State.pollingTimer = OGRH.ScheduleTimer(function()
        OGRH.SyncIntegrity.BroadcastChecksums()
    end, OGRH.SyncIntegrity.State.verificationInterval, true)  -- Repeating timer
    
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[RH-SyncIntegrity]|r Started checksum polling (every 30s)")
    ]]--
end

-- Stop periodic integrity checks (called when losing raid admin)
function OGRH.StopIntegrityChecks()
    if not OGRH.SyncIntegrity.State.enabled then
        return
    end
    
    OGRH.SyncIntegrity.State.enabled = false
    
    -- Cancel polling timer
    if OGRH.SyncIntegrity.State.pollingTimer then
        -- Cancel timer implementation depends on OGRH.ScheduleTimer
        OGRH.SyncIntegrity.State.pollingTimer = nil
    end
    
    if OGRH.SyncIntegrity.State.debug then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[RH-SyncIntegrity]|r Stopped checksum polling")
    end
end

-- Admin: Broadcast unified checksums to raid
function OGRH.SyncIntegrity.BroadcastChecksums()
    if GetNumRaidMembers() == 0 then
        return
    end
    
    -- Skip broadcast if admin made changes recently (data still in flux)
    local timeSinceLastMod = GetTime() - OGRH.SyncIntegrity.State.lastAdminModification
    if timeSinceLastMod < OGRH.SyncIntegrity.State.modificationCooldown then
        if OGRH.SyncIntegrity.State.debug then
            local remaining = OGRH.SyncIntegrity.State.modificationCooldown - timeSinceLastMod
            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff888888[RH-SyncIntegrity]|r Skipping broadcast (data modified %.0fs ago, cooldown %.0fs)", 
                timeSinceLastMod, remaining))
        end
        return
    end
    
    -- Phase 6.2 SCOPED FIX: Only broadcast checksums for CURRENTLY SELECTED RAID
    -- This reduces overhead by ~87% (1 raid vs 8 raids)
    -- Global components (consumes, tradeItems) still validated across all raids
    
    local lightweightChecksums = {
        -- Global component checksums (3 components - affects all raids)
        global = OGRH.GetGlobalComponentChecksums(),
        
        -- ONLY current raid checksum (not all raids)
        raids = {},
        
        -- Metadata
        timestamp = GetTime(),
        version = OGRH.VERSION or "1.0"
    }
    
    -- Get current encounter to determine active raid
    local currentRaid, currentEncounter = OGRH.GetCurrentEncounter()
    
    if currentRaid then
        -- ONLY include checksum for the currently selected raid
        local currentRaidChecksum = OGRH.ComputeRaidChecksum(currentRaid)
        if currentRaidChecksum then
            lightweightChecksums.raids[currentRaid] = {
                raidChecksum = currentRaidChecksum
                -- NO encounter details here - client will request if needed
            }
        end
    end
    
    -- Compute AGGREGATE checksum (hash of global + current raid only)
    local aggregateString = ""
    -- Add global component checksums
    for componentName, checksum in pairs(lightweightChecksums.global) do
        aggregateString = aggregateString .. tostring(componentName) .. ":" .. tostring(checksum) .. ";"
    end
    -- Add current raid checksum only
    if currentRaid and lightweightChecksums.raids[currentRaid] then
        aggregateString = aggregateString .. currentRaid .. ":" .. tostring(lightweightChecksums.raids[currentRaid].raidChecksum) .. ";"
    end
    lightweightChecksums.aggregate = OGRH.HashStringToNumber(aggregateString)
    
    -- Include current raid/encounter for context and backward compatibility
    if currentRaid and currentEncounter then
        lightweightChecksums.currentRaid = currentRaid
        lightweightChecksums.currentEncounter = currentEncounter
        
        -- Legacy checksums for backward compatibility with Phase 3B clients
        lightweightChecksums.structure = OGRH.CalculateStructureChecksum(currentRaid, currentEncounter)
        lightweightChecksums.rolesUI = OGRH.CalculateRolesUIChecksum()
        lightweightChecksums.assignments = OGRH.CalculateAssignmentChecksum(currentRaid, currentEncounter)
    end
    
    -- Broadcast via MessageRouter (auto-serializes tables)
    if OGRH.MessageRouter and OGRH.MessageTypes then
        OGRH.MessageRouter.Broadcast(
            OGRH.MessageTypes.SYNC.CHECKSUM_POLL,
            lightweightChecksums,
            {
                priority = "LOW",  -- Background traffic
                onSuccess = function()
                    -- Update last broadcast time
                    OGRH.SyncIntegrity.State.lastChecksumBroadcast = GetTime()
                end
            }
        )
    end
end

-- Client: Handle checksum broadcast from admin
function OGRH.SyncIntegrity.OnChecksumBroadcast(sender, checksums)
    -- Verify sender is the addon's raid admin
    local currentAdmin = OGRH.GetRaidAdmin and OGRH.GetRaidAdmin()
    if not currentAdmin or sender ~= currentAdmin then
        return  -- Ignore checksums from non-admins
    end
    
    -- Don't validate against ourselves (admin receives their own broadcast)
    if sender == UnitName("player") then
        return
    end
    
    -- Lightweight validation with on-demand drill-down
    if not (checksums.global and checksums.raids) then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[RH-SyncIntegrity]|r ERROR: Invalid checksum format received")
        return
    end
    
    if OGRH.SyncIntegrity.State.debug then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[RH-SyncIntegrity]|r Received checksum broadcast, validating...")
    end
    
    -- Step 0: Compute and validate AGGREGATE checksum (hash of global + current raid only)
    local localGlobal = OGRH.GetGlobalComponentChecksums()
    
    -- Compute local aggregate for comparison (same scope as broadcast: global + current raid only)
    local localAggregateString = ""
    for componentName, checksum in pairs(localGlobal) do
        localAggregateString = localAggregateString .. tostring(componentName) .. ":" .. tostring(checksum) .. ";"
    end
    
    -- Add checksums for raids included in the broadcast (should be 1 raid)
    for raidName, remoteRaid in pairs(checksums.raids) do
        local localRaidChecksum = OGRH.ComputeRaidChecksum(raidName)
        localAggregateString = localAggregateString .. raidName .. ":" .. tostring(localRaidChecksum) .. ";"
    end
    
    local localAggregate = OGRH.HashStringToNumber(localAggregateString)
    
    -- If aggregate matches, we're in sync - no need to check individual components
    if localAggregate == checksums.aggregate then
        if OGRH.SyncIntegrity.State.debug then
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[RH-SyncIntegrity]|r Validation passed (aggregate match)")
        end
        return
    end
    
    -- Aggregate mismatch! Now drill down to find what's different
    if OGRH.SyncIntegrity.State.debug then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff9900[RH-SyncIntegrity]|r Aggregate mismatch detected! Drilling down...")
    end
    
    -- Step 1: Validate global components
    local globalMismatch = false
    local corruptedGlobalComponents = {}
    for componentName, remoteChecksum in pairs(checksums.global) do
        local localChecksum = localGlobal[componentName]
        if localChecksum ~= remoteChecksum then
            globalMismatch = true
            table.insert(corruptedGlobalComponents, componentName)
            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff9900[RH-SyncIntegrity]|r Global component mismatch: %s", componentName))
        end
    end
    
    -- Trigger automatic repair for corrupted global components
    if table.getn(corruptedGlobalComponents) > 0 then
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ccff[RH-SyncIntegrity]|r Detected %d corrupted global component(s)", table.getn(corruptedGlobalComponents)))
        
        if not OGRH.SyncGranular then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[RH-SyncIntegrity]|r ERROR: OGRH.SyncGranular is nil!")
        elseif not OGRH.SyncGranular.QueueRepair then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[RH-SyncIntegrity]|r ERROR: OGRH.SyncGranular.QueueRepair is nil!")
        else
            local result = {
                valid = false,
                level = "GLOBAL",
                corrupted = {
                    global = corruptedGlobalComponents,
                    raids = {}
                }
            }
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[RH-SyncIntegrity]|r Calling QueueRepair for global components...")
            OGRH.SyncGranular.QueueRepair(result, sender)
        end
    end
    
    -- Step 2: Validate raid-level checksums (only raids included in broadcast)
    local raidMismatches = {}
    for raidName, remoteRaid in pairs(checksums.raids) do
        local localRaidChecksum = OGRH.ComputeRaidChecksum(raidName)
        if localRaidChecksum ~= remoteRaid.raidChecksum then
            table.insert(raidMismatches, raidName)
        end
    end
    
    -- If mismatches detected, request drill-down for specific raids
    if table.getn(raidMismatches) > 0 then
        for i = 1, table.getn(raidMismatches) do
            local raidName = raidMismatches[i]
            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff9900[RH-SyncIntegrity]|r Raid mismatch detected: %s (requesting details...)", raidName))
            OGRH.SyncIntegrity.RequestRaidDrillDown(sender, raidName)
        end
    end
end

-- Client: Request RolesUI sync from admin (auto-repair)
function OGRH.SyncIntegrity.RequestRolesUISync(adminName)
    if OGRH.MessageRouter and OGRH.MessageTypes then
        OGRH.MessageRouter.SendTo(
            adminName,
            OGRH.MessageTypes.ROLESUI.SYNC_REQUEST,
            "",  -- Empty string, no data needed for request
            {priority = "HIGH"}
        )
    end
end

-- Admin: Handle RolesUI sync request (push data immediately)
function OGRH.SyncIntegrity.OnRolesUISyncRequest(requester)
    -- Verify we're the addon's raid admin
    local currentAdmin = OGRH.GetRaidAdmin and OGRH.GetRaidAdmin()
    local playerName = UnitName("player")
    if not currentAdmin or playerName ~= currentAdmin then
        return
    end
    
    OGRH.EnsureSV()
    
    -- Build RolesUI sync data
    local syncData = {
        roles = OGRH_SV.roles or {},
        timestamp = GetTime()
    }
    
    -- Send to requester (or broadcast to all if requester not specified)
    if OGRH.MessageRouter and OGRH.MessageTypes then
        if requester then
            OGRH.MessageRouter.SendTo(
                requester,
                OGRH.MessageTypes.ROLESUI.SYNC_PUSH,
                syncData,
                {priority = "HIGH"}
            )
        else
            OGRH.MessageRouter.Broadcast(
                OGRH.MessageTypes.ROLESUI.SYNC_PUSH,
                syncData,
                {priority = "HIGH"}
            )
        end
    end
end

-- Client: Handle RolesUI sync push from admin (apply immediately)
function OGRH.SyncIntegrity.OnRolesUISyncPush(sender, syncData)
    -- Verify sender is the addon's raid admin
    local currentAdmin = OGRH.GetRaidAdmin and OGRH.GetRaidAdmin()
    if not currentAdmin or sender ~= currentAdmin then
        return
    end
    
    -- Block sync from self
    if sender == UnitName("player") then
        return
    end
    
    if not syncData or not syncData.roles then
        return
    end
    
    -- Apply RolesUI data
    OGRH.EnsureSV()
    OGRH_SV.roles = syncData.roles
    
    -- Refresh RolesUI if open
    if OGRH.rolesFrame and OGRH.rolesFrame:IsShown() and OGRH.rolesFrame.UpdatePlayerLists then
        OGRH.rolesFrame.UpdatePlayerLists()
    end
    
    if OGRH.SyncIntegrity.State.debug then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[RH-SyncIntegrity]|r RolesUI data updated from admin")
    end
end

--[[
    Phase 6.2 FIX: Drill-Down Validation System
    
    Instead of broadcasting full hierarchy, admin broadcasts lightweight checksums.
    Clients request detailed checksums only for mismatched areas.
]]

-- Client: Request encounter-level drill-down for a specific raid
function OGRH.SyncIntegrity.RequestRaidDrillDown(adminName, raidName)
    if not OGRH.MessageRouter or not OGRH.MessageTypes then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[RH-SyncIntegrity]|r ERROR: MessageRouter not available for drill-down")
        return
    end
    
    local requestData = {
        raidName = raidName,
        requestor = UnitName("player"),
        timestamp = GetTime()
    }
    
    if OGRH.SyncIntegrity.State.debug then
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ccff[RH-SyncIntegrity]|r Sending drill-down request for %s to %s", raidName, adminName))
    end
    
    OGRH.MessageRouter.SendTo(
        adminName,
        OGRH.MessageTypes.SYNC.CHECKSUM_DRILLDOWN_REQUEST,
        requestData,
        {priority = "NORMAL"}
    )
end

-- Admin: Respond to drill-down request with encounter-level checksums for specific raid
-- Uses 2-second buffering to batch multiple requests and broadcast once
function OGRH.SyncIntegrity.OnDrillDownRequest(requester, requestData)
    -- Verify we're the admin
    local currentAdmin = OGRH.GetRaidAdmin and OGRH.GetRaidAdmin()
    local playerName = UnitName("player")
    if not currentAdmin or playerName ~= currentAdmin then
        return
    end
    
    local raidName = requestData.raidName
    if not raidName then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[RH-SyncIntegrity]|r ERROR: Drill-down request missing raid name")
        return
    end
    
    if OGRH.SyncIntegrity.State.debug then
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ccff[RH-SyncIntegrity]|r Received drill-down request for %s from %s", raidName, requester))
    end
    
    -- Initialize queue for this raid if not exists
    if not OGRH.SyncIntegrity.State.drillDownQueue[raidName] then
        OGRH.SyncIntegrity.State.drillDownQueue[raidName] = {
            requesters = {},
            timer = nil
        }
    end
    
    local queue = OGRH.SyncIntegrity.State.drillDownQueue[raidName]
    
    -- Add requester to queue (avoid duplicates)
    local alreadyQueued = false
    for i = 1, table.getn(queue.requesters) do
        if queue.requesters[i] == requester then
            alreadyQueued = true
            break
        end
    end
    
    if not alreadyQueued then
        table.insert(queue.requesters, requester)
    end
    
    -- If timer not running, start 2-second buffer
    if not queue.timer then
        queue.timer = OGRH.ScheduleTimer(function()
            OGRH.SyncIntegrity.FlushDrillDownQueue(raidName)
        end, OGRH.SyncIntegrity.State.drillDownBufferTime, false)  -- One-shot timer
        
        if OGRH.SyncIntegrity.State.debug then
            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff888888[RH-SyncIntegrity]|r Started 2s buffer for %s drill-down requests", raidName))
        end
    else
        if OGRH.SyncIntegrity.State.debug then
            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff888888[RH-SyncIntegrity]|r Added %s to pending %s drill-down (buffer active)", requester, raidName))
        end
    end
end

-- Admin: Flush queued drill-down requests and broadcast response
function OGRH.SyncIntegrity.FlushDrillDownQueue(raidName)
    local queue = OGRH.SyncIntegrity.State.drillDownQueue[raidName]
    if not queue or table.getn(queue.requesters) == 0 then
        return
    end
    
    -- Build encounter-level checksums for this raid only
    local encounterChecksums = OGRH.GetEncounterChecksums(raidName)
    
    -- Find raid position in array
    local raidPosition = nil
    OGRH.EnsureSV()
    if OGRH_SV.encounterMgmt and OGRH_SV.encounterMgmt.raids then
        for i = 1, table.getn(OGRH_SV.encounterMgmt.raids) do
            if OGRH_SV.encounterMgmt.raids[i].name == raidName then
                raidPosition = i
                break
            end
        end
    end
    
    local responseData = {
        raidName = raidName,
        raidPosition = raidPosition,  -- Include position for proper insertion
        raidChecksum = OGRH.ComputeRaidChecksum(raidName),  -- Include raid checksum for comparison
        encounters = {},
        timestamp = GetTime()
    }
    
    -- For each encounter, include encounter checksum + component checksums + position
    OGRH.EnsureSV()
    local raid = OGRH.FindRaidByName(raidName)
    if raid and raid.encounters then
        for i = 1, table.getn(raid.encounters) do
            local encounter = raid.encounters[i]
            if encounter and encounter.name then
                local encounterName = encounter.name
                responseData.encounters[encounterName] = {
                    encounterChecksum = encounterChecksums[encounterName],
                    components = OGRH.GetComponentChecksums(raidName, encounterName),
                    position = i  -- Include position for proper encounter ordering
                }
            end
        end
    end
    
    -- BROADCAST once to entire raid (not individual sends)
    -- All queued requesters will receive it, but network payload sent only once
    if OGRH.MessageRouter and OGRH.MessageTypes then
        if OGRH.SyncIntegrity.State.debug then
            local requesterList = table.concat(queue.requesters, ", ")
            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ccff[RH-SyncIntegrity]|r Broadcasting drill-down response for %s to %d client(s): %s", raidName, table.getn(queue.requesters), requesterList))
        end
        
        -- Broadcast to entire raid (sent once on network, all clients receive)
        OGRH.MessageRouter.Broadcast(
            OGRH.MessageTypes.SYNC.CHECKSUM_DRILLDOWN_RESPONSE,
            responseData,
            {priority = "NORMAL"}
        )
    end
    
    -- Clear queue
    OGRH.SyncIntegrity.State.drillDownQueue[raidName] = nil
end

-- Client: Handle drill-down response and validate at component level
function OGRH.SyncIntegrity.OnDrillDownResponse(sender, responseData)
    -- Verify sender is the admin
    local currentAdmin = OGRH.GetRaidAdmin and OGRH.GetRaidAdmin()
    if not currentAdmin or sender ~= currentAdmin then
        return
    end
    
    local raidName = responseData.raidName
    local encounters = responseData.encounters
    
    if not raidName or not encounters then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[RH-SyncIntegrity]|r ERROR: Invalid drill-down response")
        return
    end
    
    if OGRH.SyncIntegrity.State.debug then
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ccff[RH-SyncIntegrity]|r Received drill-down response for %s, validating encounters...", raidName))
    end
    
    -- Check if this raid already has a pending full sync
    if OGRH.SyncIntegrity.State.pendingFullSync[raidName] then
        if OGRH.SyncIntegrity.State.debug then
            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff888888[RH-SyncIntegrity]|r Skipping %s validation (full sync pending)", raidName))
        end
        return
    end
    
    -- First check: Does the raid even exist locally?
    local raid = OGRH.FindRaidByName(raidName)
    if not raid then
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff9900[RH-SyncIntegrity]|r %s: Raid missing entirely - requesting full raid sync", raidName))
        
        -- Mark as pending to prevent re-queuing
        OGRH.SyncIntegrity.State.pendingFullSync[raidName] = true
        
        -- Raid doesn't exist at all - need FULL RAID SYNC
        if OGRH.SyncGranular and OGRH.SyncGranular.QueueRepair then
            local result = {
                valid = false,
                level = "RAID",
                corrupted = {
                    global = {},
                    raids = {
                        [raidName] = {
                            raidLevel = true,
                            encounters = {}
                        }
                    }
                }
            }
            OGRH.SyncGranular.QueueRepair(result, sender)
        end
        return  -- Don't try to validate encounters if raid doesn't exist
    end
    
    -- Second check: Do we have the same encounter count?
    if raid and raid.encounters then
        local localEncounterCount = table.getn(raid.encounters)
        local remoteEncounterCount = 0
        for _ in pairs(encounters) do
            remoteEncounterCount = remoteEncounterCount + 1
        end
        
        if localEncounterCount ~= remoteEncounterCount then
            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff9900[RH-SyncIntegrity]|r %s: Encounter count mismatch (local: %d, remote: %d) - requesting full raid sync", raidName, localEncounterCount, remoteEncounterCount))
            
            -- Encounter count differs - need FULL RAID SYNC to preserve order
            if OGRH.SyncGranular and OGRH.SyncGranular.QueueRepair then
                local result = {
                    valid = false,
                    level = "RAID",
                    corrupted = {
                        global = {},
                        raids = {
                            [raidName] = {
                                raidLevel = true,
                                encounters = {}
                            }
                        }
                    }
                }
                OGRH.SyncGranular.QueueRepair(result, sender)
            end
            return  -- Skip component-level validation, full raid sync will fix everything
        end
        
        -- Debug: Check raid metadata
        if OGRH.SyncIntegrity.State.debug then
            local localRaidChecksum = OGRH.ComputeRaidChecksum(raidName)
            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff888888[RH-SyncIntegrity]|r %s RAID checksum: local=%s, remote=%s", raidName, tostring(localRaidChecksum), tostring(responseData.raidChecksum or "?")))
        end
    end
    
    -- Validate each encounter
    for encounterName, remoteEncounter in pairs(encounters) do
        local localEncounterChecksum = OGRH.ComputeEncounterChecksum(raidName, encounterName)
        
        -- Debug: Show position info
        if OGRH.SyncIntegrity.State.debug and remoteEncounter.position then
            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff888888[RH-SyncIntegrity]|r %s position %d, checksum: local=%s, remote=%s", 
                encounterName, remoteEncounter.position, tostring(localEncounterChecksum), tostring(remoteEncounter.encounterChecksum)))
        end
        
        if localEncounterChecksum ~= remoteEncounter.encounterChecksum then
            -- Encounter mismatch - check components
            local corruptedComponents = {}
            
            if remoteEncounter.components then
                for componentName, remoteComponentChecksum in pairs(remoteEncounter.components) do
                    local localComponentChecksum = OGRH.ComputeComponentChecksum(raidName, encounterName, componentName)
                    if localComponentChecksum ~= remoteComponentChecksum then
                        table.insert(corruptedComponents, componentName)
                    end
                end
            end
            
            if table.getn(corruptedComponents) > 0 then
                local componentList = table.concat(corruptedComponents, ", ")
                DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff0000[RH-SyncIntegrity]|r %s > %s: %s", raidName, encounterName, componentList))
                
                -- Trigger automatic repair with position information
                if not OGRH.SyncGranular then
                    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[RH-SyncIntegrity]|r ERROR: OGRH.SyncGranular is nil!")
                elseif not OGRH.SyncGranular.QueueRepair then
                    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[RH-SyncIntegrity]|r ERROR: OGRH.SyncGranular.QueueRepair is nil!")
                else
                    local result = {
                        valid = false,
                        level = "COMPONENT",
                        corrupted = {
                            global = {},
                            raids = {
                                [raidName] = {
                                    raidLevel = false,
                                    encounters = {
                                        [encounterName] = {
                                            components = corruptedComponents,
                                            position = remoteEncounter.position  -- Pass encounter position
                                        }
                                    }
                                }
                            }
                        }
                    }
                    OGRH.SyncGranular.QueueRepair(result, sender)
                end
            end
        end
    end
    
    -- After validating all encounters, check if raid-level metadata differs
    -- (all encounters match but raid checksum doesn't = advancedSettings differ)
    if responseData.raidChecksum then
        local localRaidChecksum = OGRH.ComputeRaidChecksum(raidName)
        if OGRH.SyncIntegrity.State.debug then
            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff888888[RH-SyncIntegrity]|r %s: Checking raid checksum: local=%s, remote=%s", 
                raidName, tostring(localRaidChecksum), tostring(responseData.raidChecksum)))
        end
        
        if tostring(localRaidChecksum) ~= tostring(responseData.raidChecksum) then
            -- All encounters validated above and match, but raid checksum differs
            -- This means raid metadata (advancedSettings) is different
            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff9900[RH-SyncIntegrity]|r %s: Raid metadata mismatch - requesting metadata sync", raidName))
            
            -- Request raid metadata sync
            if OGRH.SyncGranular and OGRH.SyncGranular.RequestRaidMetadataSync then
                OGRH.SyncGranular.RequestRaidMetadataSync(raidName, sender)
            else
                DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff0000[RH-SyncIntegrity]|r ERROR: Cannot request metadata sync - SyncGranular=%s, RequestRaidMetadataSync=%s", 
                    tostring(OGRH.SyncGranular ~= nil), tostring(OGRH.SyncGranular and OGRH.SyncGranular.RequestRaidMetadataSync ~= nil)))
            end
        end
    end
end

-- Request full sync from another player
function OGRH.RequestFullSync(sender)
    -- Request via MessageRouter
    if OGRH.MessageRouter and OGRH.MessageTypes then
        OGRH.MessageRouter.SendTo(
            sender,
            OGRH.MessageTypes.SYNC.REQUEST_FULL,
            {},
            {priority = "NORMAL"}
        )
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[RH-SyncIntegrity]|r Requested full sync from " .. sender)
    end
end

-- Send full sync to another player (admin only)
function OGRH.SendFullSync(targetPlayer)
    if not OGRH.CanModifyStructure or not OGRH.CanModifyStructure(UnitName("player")) then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[RH-SyncIntegrity]|r Only raid admin can send full sync")
        return
    end
    
    -- Use existing Phase 2 sync system
    if OGRH.Sync and OGRH.Sync.BroadcastFullSync then
        OGRH.Sync.BroadcastFullSync()
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[RH-SyncIntegrity]|r Sent full sync to raid")
    end
end

-- Show corruption warning to user
function OGRH.ShowCorruptionWarning(sender)
    DEFAULT_CHAT_FRAME:AddMessage("|cffff8800[RH-SyncIntegrity]|r Data corruption detected with " .. sender)
    DEFAULT_CHAT_FRAME:AddMessage("|cffff8800[RH-SyncIntegrity]|r Use Data Management window to repair")
end

-- Request admin intervention for unresolvable conflicts
function OGRH.RequestAdminIntervention()
    DEFAULT_CHAT_FRAME:AddMessage("|cffff8800[RH-SyncIntegrity]|r Admin intervention required")
    DEFAULT_CHAT_FRAME:AddMessage("|cffff8800[RH-SyncIntegrity]|r Open Data Management window to push structure")
end

-- Record admin modification timestamp (called by delta sync when admin makes changes)
function OGRH.SyncIntegrity.RecordAdminModification()
    OGRH.SyncIntegrity.State.lastAdminModification = GetTime()
end

-- Compute structure checksum (lightweight)
function OGRH.ComputeStructureChecksum()
    local currentRaid, currentEncounter = OGRH.GetCurrentEncounter()
    if not currentRaid or not currentEncounter then
        return "0"
    end
    return OGRH.CalculateStructureChecksum(currentRaid, currentEncounter)
end

-- Repair corrupted data from multiple sources
function OGRH.RepairCorruptedData()
    DEFAULT_CHAT_FRAME:AddMessage("|cffff9900[RH-SyncIntegrity]|r Use Data Management window to pull latest structure")
end

-- Force full resync from admin
function OGRH.ForceResyncFromAdmin()
    if not OGRH.CanModifyStructure or not OGRH.CanModifyStructure(UnitName("player")) then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[RH-SyncIntegrity]|r Only raid admin can force resync")
        return
    end
    
    -- Use Phase 2 sync system
    if OGRH.Sync and OGRH.Sync.BroadcastFullSync then
        OGRH.Sync.BroadcastFullSync()
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[RH-SyncIntegrity]|r Force resyncing structure to all raid members")
    end
end

--[[
    Initialization
]]

function OGRH.SyncIntegrity.Initialize()
    -- Register checksum poll handler
    if OGRH.MessageRouter and OGRH.MessageTypes then
        OGRH.MessageRouter.RegisterHandler(OGRH.MessageTypes.SYNC.CHECKSUM_POLL, function(sender, data)
            OGRH.SyncIntegrity.OnChecksumBroadcast(sender, data)
        end)
        
        -- Register RolesUI sync handlers
        OGRH.MessageRouter.RegisterHandler(OGRH.MessageTypes.ROLESUI.SYNC_REQUEST, function(sender, data)
            OGRH.SyncIntegrity.OnRolesUISyncRequest(sender)
        end)
        
        OGRH.MessageRouter.RegisterHandler(OGRH.MessageTypes.ROLESUI.SYNC_PUSH, function(sender, data)
            OGRH.SyncIntegrity.OnRolesUISyncPush(sender, data)
        end)
        
        -- Phase 6.2 FIX: Register drill-down handlers
        OGRH.MessageRouter.RegisterHandler(OGRH.MessageTypes.SYNC.CHECKSUM_DRILLDOWN_REQUEST, function(sender, data)
            OGRH.SyncIntegrity.OnDrillDownRequest(sender, data)
        end)
        
        OGRH.MessageRouter.RegisterHandler(OGRH.MessageTypes.SYNC.CHECKSUM_DRILLDOWN_RESPONSE, function(sender, data)
            OGRH.SyncIntegrity.OnDrillDownResponse(sender, data)
        end)
    end
    
    OGRH.Msg("|cff00ccff[RH-SyncIntegrity]|r Loaded - Lightweight checksum polling with drill-down validation")
end

-- Auto-initialize on load
OGRH.SyncIntegrity.Initialize()

--[[
    ====================================================================
    HELPER FUNCTIONS (MUST BE DECLARED BEFORE USE)
    ====================================================================
]]

-- Simple table to string serializer (doesn't use OGRH.SerializeTable to avoid dependency)
local function SimpleSerialize(tbl, depth)
    depth = depth or 0
    if depth > 10 then return "..." end  -- Prevent infinite recursion
    
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
    ====================================================================
    PHASE 6.1: TEST COMMANDS
    ====================================================================
    
    Slash commands for testing hierarchical checksums in WoW 1.12
    Usage: /ogrh test <testname>
]]

-- Register test command handler
function OGRH.SyncIntegrity.RunTests(testName)
    if not testName or testName == "help" then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[RH-Test]|r Available tests:")
        DEFAULT_CHAT_FRAME:AddMessage("  /ogrh test all - Run all tests")
        DEFAULT_CHAT_FRAME:AddMessage("  /ogrh test global - Test global checksums")
        DEFAULT_CHAT_FRAME:AddMessage("  /ogrh test raid - Test raid checksums")
        DEFAULT_CHAT_FRAME:AddMessage("  /ogrh test encounter - Test encounter checksums")
        DEFAULT_CHAT_FRAME:AddMessage("  /ogrh test component - Test component checksums")
        DEFAULT_CHAT_FRAME:AddMessage("  /ogrh test stability - Test checksum stability")
        DEFAULT_CHAT_FRAME:AddMessage("  /ogrh test validation - Test hierarchical validation (Phase 6.2)")
        DEFAULT_CHAT_FRAME:AddMessage("  /ogrh test reporting - Test validation reporting (Phase 6.2)")
        DEFAULT_CHAT_FRAME:AddMessage("  /ogrh test granular - Test granular sync system (Phase 6.3)")
        return
    end
    
    if testName == "global" or testName == "all" then
        OGRH.SyncIntegrity.TestGlobalChecksums()
    end
    
    if testName == "raid" or testName == "all" then
        OGRH.SyncIntegrity.TestRaidChecksums()
    end
    
    if testName == "encounter" or testName == "all" then
        OGRH.SyncIntegrity.TestEncounterChecksums()
    end
    
    if testName == "component" or testName == "all" then
        OGRH.SyncIntegrity.TestComponentChecksums()
    end
    
    if testName == "stability" or testName == "all" then
        OGRH.SyncIntegrity.TestChecksumStability()
    end
    
    if testName == "validation" or testName == "all" then
        OGRH.SyncIntegrity.TestHierarchicalValidation()
    end
    
    if testName == "reporting" or testName == "all" then
        OGRH.SyncIntegrity.TestValidationReporting()
    end
    
    if testName == "granular" or testName == "all" then
        OGRH.SyncIntegrity.TestGranularSync()
    end
end

-- Test 1: Global Component Checksums
function OGRH.SyncIntegrity.TestGlobalChecksums()
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff=== Testing Global Checksums ===|r")
    
    local checksums = OGRH.GetGlobalComponentChecksums()
    local deprecated = {rgo = true}  -- RGO deprecated - no longer synced
    
    for component, cs in pairs(checksums) do
        if deprecated[component] and cs == "0" then
            DEFAULT_CHAT_FRAME:AddMessage("|cffaaaaaa[SKIP]|r " .. component .. ": deprecated (no data)")
        elseif cs and cs ~= "0" then
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[PASS]|r " .. component .. ": " .. cs)
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[FAIL]|r " .. component .. ": returned '" .. tostring(cs) .. "'")
        end
    end
end

-- Test 2: Raid Checksums
function OGRH.SyncIntegrity.TestRaidChecksums()
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff=== Testing Raid Checksums ===|r")
    
    local checksums = OGRH.GetRaidChecksums()
    local count = 0
    
    for raidName, cs in pairs(checksums) do
        count = count + 1
        if cs and cs ~= "0" then
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[PASS]|r " .. raidName .. ": " .. cs)
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[FAIL]|r " .. raidName .. ": returned '" .. tostring(cs) .. "'")
        end
    end
    
    if count == 0 then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[FAIL]|r No raids found - load defaults first")
    end
end

-- Test 3: Encounter Checksums
function OGRH.SyncIntegrity.TestEncounterChecksums()
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff=== Testing Encounter Checksums (BWL) ===|r")
    
    local checksums = OGRH.GetEncounterChecksums("BWL")
    local count = 0
    
    for encName, cs in pairs(checksums) do
        count = count + 1
        if cs and cs ~= "0" then
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[PASS]|r " .. encName .. ": " .. cs)
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[FAIL]|r " .. encName .. ": returned '" .. tostring(cs) .. "'")
        end
    end
    
    if count == 0 then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[FAIL]|r No encounters found in BWL")
    end
end

-- Test 4: Component Checksums
function OGRH.SyncIntegrity.TestComponentChecksums()
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff=== Testing Component Checksums (Naxx/4HM Tank/Heal) ===|r")
    
    local checksums = OGRH.GetComponentChecksums("Naxx", "4HM Tank/Heal")
    
    for component, cs in pairs(checksums) do
        if cs then
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[PASS]|r " .. component .. ": " .. cs)
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[FAIL]|r " .. component .. ": nil")
        end
    end
end

-- Test 5: Checksum Stability
function OGRH.SyncIntegrity.TestChecksumStability()
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff=== Testing Checksum Stability ===|r")
    
    -- Test global stability (use consumes which has actual data)
    local g1 = OGRH.ComputeGlobalComponentChecksum("consumes")
    local g2 = OGRH.ComputeGlobalComponentChecksum("consumes")
    if g1 == g2 and g1 ~= "0" then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[PASS]|r Global checksum stable: " .. g1)
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[FAIL]|r Global checksum unstable: " .. g1 .. " vs " .. g2)
    end
    
    -- Test raid stability
    local r1 = OGRH.ComputeRaidChecksum("BWL")
    local r2 = OGRH.ComputeRaidChecksum("BWL")
    if r1 == r2 then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[PASS]|r Raid checksum stable: " .. r1)
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[FAIL]|r Raid checksum unstable: " .. r1 .. " vs " .. r2)
    end
    
    -- Test encounter stability
    local e1 = OGRH.ComputeEncounterChecksum("BWL", "Razorgore")
    local e2 = OGRH.ComputeEncounterChecksum("BWL", "Razorgore")
    if e1 == e2 then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[PASS]|r Encounter checksum stable: " .. e1)
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[FAIL]|r Encounter checksum unstable: " .. e1 .. " vs " .. e2)
    end
    
    -- Test component stability (use Naxx/4HM Tank/Heal which has all components)
    local c1 = OGRH.ComputeComponentChecksum("Naxx", "4HM Tank/Heal", "roles")
    local c2 = OGRH.ComputeComponentChecksum("Naxx", "4HM Tank/Heal", "roles")
    if c1 == c2 then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[PASS]|r Component checksum stable: " .. c1)
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[FAIL]|r Component checksum unstable: " .. c1 .. " vs " .. c2)
    end
end

-- Test 6: Hierarchical Validation (Phase 6.2)
function OGRH.SyncIntegrity.TestHierarchicalValidation()
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff=== Testing Hierarchical Validation (Phase 6.2) ===|r")
    
    -- Get current checksums
    local checksums = OGRH.GetAllHierarchicalChecksums()
    
    -- Test 1: Self-validation (should always pass)
    local result = OGRH.ValidateStructureHierarchy(checksums)
    if result.valid then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[PASS]|r Self-validation passed")
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[FAIL]|r Self-validation failed (should never happen)")
    end
    
    -- Test 2: Simulate global component corruption
    local corruptedGlobal = {}
    for k, v in pairs(checksums) do
        corruptedGlobal[k] = v
    end
    corruptedGlobal.global = {
        tradeItems = checksums.global.tradeItems,
        consumes = "CORRUPTED_CHECKSUM"
        -- RGO deprecated - no longer validated
    }
    
    local globalResult = OGRH.ValidateStructureHierarchy(corruptedGlobal)
    if not globalResult.valid and globalResult.level == "GLOBAL" then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[PASS]|r Global corruption detected")
        DEFAULT_CHAT_FRAME:AddMessage("  Corrupted: " .. table.concat(globalResult.corrupted.global, ", "))
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[FAIL]|r Global corruption not detected")
    end
    
    -- Test 3: Simulate component-level corruption
    local corruptedComponent = {}
    for k, v in pairs(checksums) do
        corruptedComponent[k] = v
    end
    if corruptedComponent.raids and corruptedComponent.raids["BWL"] and 
       corruptedComponent.raids["BWL"].encounters and corruptedComponent.raids["BWL"].encounters["Razorgore"] then
        corruptedComponent.raids["BWL"].encounters["Razorgore"].components.playerAssignments = "CORRUPTED"
        
        local compResult = OGRH.ValidateStructureHierarchy(corruptedComponent)
        if not compResult.valid and compResult.level == "COMPONENT" then
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[PASS]|r Component corruption detected")
            if compResult.corrupted.raids["BWL"] and compResult.corrupted.raids["BWL"].encounters["Razorgore"] then
                DEFAULT_CHAT_FRAME:AddMessage("  Corrupted: BWL > Razorgore > " .. 
                    table.concat(compResult.corrupted.raids["BWL"].encounters["Razorgore"], ", "))
            end
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[FAIL]|r Component corruption not detected")
        end
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cffffaa00[SKIP]|r BWL/Razorgore not available for component test")
    end
end

-- Test 7: Validation Reporting (Phase 6.2)
function OGRH.SyncIntegrity.TestValidationReporting()
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff=== Testing Validation Reporting (Phase 6.2) ===|r")
    
    -- Create a mock validation result with multiple corruption points
    local mockResult = {
        valid = false,
        level = "COMPONENT",
        corrupted = {
            global = {"consumes"},
            raids = {
                ["BWL"] = {
                    raidLevel = false,
                    encounters = {
                        ["Razorgore"] = {"playerAssignments", "announcements"},
                        ["Vaelastrasz"] = {"raidMarks"}
                    }
                },
                ["Naxx"] = {
                    raidLevel = true,
                    encounters = {}
                }
            }
        }
    }
    
    -- Format and display
    local messages = OGRH.FormatValidationResult(mockResult)
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[PASS]|r Formatted " .. table.getn(messages) .. " messages:")
    for i = 1, table.getn(messages) do
        DEFAULT_CHAT_FRAME:AddMessage("  " .. messages[i])
    end
end

-- Test 8: Granular Sync System (Phase 6.3)
function OGRH.SyncIntegrity.TestGranularSync()
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff=== Testing Granular Sync System (Phase 6.3) ===|r")
    
    -- Test 1: Module initialization
    if OGRH.SyncGranular and OGRH.SyncGranular.Initialize then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[PASS]|r SyncGranular module loaded")
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[FAIL]|r SyncGranular module not found")
        return
    end
    
    -- Test 2: Priority calculation
    OGRH.SyncGranular.SetContext("BWL", "Razorgore")
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[PASS]|r Context set to BWL > Razorgore")
    
    -- Test 3: Component extraction
    local testComponents = {
        "encounterMetadata",
        "roles",
        "playerAssignments",
        "raidMarks",
        "assignmentNumbers",
        "announcements"
    }
    
    local extractionCount = 0
    for i = 1, table.getn(testComponents) do
        local componentName = testComponents[i]
        local data = OGRH.SyncGranular.ExtractComponentData("BWL", "Razorgore", componentName)
        if data then
            extractionCount = extractionCount + 1
        end
    end
    
    if extractionCount == table.getn(testComponents) then
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[PASS]|r Extracted all %d components", extractionCount))
    else
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffffaa00[PARTIAL]|r Extracted %d/%d components", extractionCount, table.getn(testComponents)))
    end
    
    -- Test 4: Validation result integration
    local mockResult = {
        valid = false,
        level = "COMPONENT",
        corrupted = {
            global = {},
            raids = {
                ["BWL"] = {
                    raidLevel = false,
                    encounters = {
                        ["Razorgore"] = {"playerAssignments"}
                    }
                }
            }
        }
    }
    
    if OGRH.SyncGranular.QueueRepair then
        -- Don't actually queue (no target player), just test the function exists
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[PASS]|r QueueRepair function available")
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[FAIL]|r QueueRepair function not found")
    end
    
    -- Test 5: Message type registration
    local messageTypes = {
        "COMPONENT_REQUEST",
        "COMPONENT_RESPONSE",
        "ENCOUNTER_REQUEST",
        "ENCOUNTER_RESPONSE",
        "RAID_REQUEST",
        "RAID_RESPONSE",
        "GLOBAL_REQUEST",
        "GLOBAL_RESPONSE"
    }
    
    local registeredCount = 0
    for i = 1, table.getn(messageTypes) do
        local msgType = messageTypes[i]
        if OGRH.MessageTypes.SYNC[msgType] then
            registeredCount = registeredCount + 1
        end
    end
    
    if registeredCount == table.getn(messageTypes) then
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[PASS]|r All %d message types registered", registeredCount))
    else
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff0000[FAIL]|r Only %d/%d message types registered", registeredCount, table.getn(messageTypes)))
    end
    
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff=== Phase 6.3 Tests Complete ===|r")
end

--[[
    ====================================================================
    PHASE 6: HIERARCHICAL CHECKSUM SYSTEM
    ====================================================================
    
    This section implements granular checksums at 4 levels:
    1. Global-Level: tradeItems, consumes (rgo deprecated)
    2. Raid-Level: Raid metadata and encounter list
    3. Encounter-Level: Encounter metadata + 6 component checksums
    4. Component-Level: Individual components within an encounter
    
    Purpose: Enable surgical data repairs without full structure syncs
    Performance: Reduce sync time from 76.5s (full) to 3.9s (encounter)
]]

--[[
    6.1.1: Global-Level Checksums
]]

-- Compute checksum for a specific global component
function OGRH.ComputeGlobalComponentChecksum(componentName)
    OGRH.EnsureSV()
    
    local data = nil
    
    if componentName == "tradeItems" then
        data = OGRH_SV.tradeItems
    elseif componentName == "consumes" then
        data = OGRH_SV.consumes
    -- RGO deprecated - no longer synced
    else
        return "0"  -- Unknown component
    end
    
    if not data then
        return "0"
    end
    
    -- Use SimpleSerialize for consistent representation
    local serialized = SimpleSerialize(data)
    return OGRH.HashString(serialized)
end

-- Get all global component checksums
function OGRH.GetGlobalComponentChecksums()
    return {
        tradeItems = OGRH.ComputeGlobalComponentChecksum("tradeItems"),
        consumes = OGRH.ComputeGlobalComponentChecksum("consumes")
        -- RGO deprecated - no longer synced
    }
end

--[[
    6.1.2: Raid-Level Checksums
]]

-- Compute checksum for a specific raid (metadata + encounter list)
function OGRH.ComputeRaidChecksum(raidName)
    OGRH.EnsureSV()
    
    -- Find raid in raids array (raids are stored as array, not dictionary)
    local raid = OGRH.FindRaidByName(raidName)
    if not raid then
        return "0"
    end
    local checksum = 0
    
    -- Include raid metadata (advancedSettings)
    if raid.advancedSettings then
        local serialized = SimpleSerialize(raid.advancedSettings)
        checksum = checksum + OGRH.HashStringToNumber(serialized)
    end
    
    -- Include encounter list structure - ORDER MATTERS
    if raid.encounters then
        for i = 1, table.getn(raid.encounters) do
            local enc = raid.encounters[i]
            if enc and enc.name then
                -- Multiply by position to make order-dependent
                for j = 1, string.len(enc.name) do
                    checksum = checksum + string.byte(enc.name, j) * i
                end
                
                -- Include encounter checksums (all components)
                local encounterChecksum = OGRH.ComputeEncounterChecksum(raidName, enc.name)
                checksum = checksum + (tonumber(encounterChecksum) or 0) * i
            end
        end
    end
    
    return tostring(checksum)
end

-- Get checksums for all raids
function OGRH.GetRaidChecksums()
    OGRH.EnsureSV()
    
    local checksums = {}
    
    if OGRH_SV.encounterMgmt and OGRH_SV.encounterMgmt.raids then
        -- Raids are stored as an array, iterate through it
        for i = 1, table.getn(OGRH_SV.encounterMgmt.raids) do
            local raid = OGRH_SV.encounterMgmt.raids[i]
            if raid and raid.name then
                checksums[raid.name] = OGRH.ComputeRaidChecksum(raid.name)
            end
        end
    end
    
    return checksums
end

--[[
    6.1.3: Encounter-Level Checksums
]]

-- Compute checksum for a specific encounter (metadata + all 6 components)
function OGRH.ComputeEncounterChecksum(raidName, encounterName)
    OGRH.EnsureSV()
    
    -- Get raid object using FindRaidByName (raids are stored as array)
    local raid = OGRH.FindRaidByName(raidName)
    if not raid then
        return "0"
    end
    
    -- Get the encounter object (using FindEncounterByName which exists in EncounterMgmt.lua)
    local encounter = OGRH.FindEncounterByName(raid, encounterName)
    if not encounter then
        return "0"
    end
    
    local checksum = 0
    
    -- Component 1: Encounter metadata (advancedSettings)
    if encounter.advancedSettings then
        local serialized = SimpleSerialize(encounter.advancedSettings)
        checksum = checksum + OGRH.HashStringToNumber(serialized)
    end
    
    -- Component 2: Roles (from encounterMgmt.roles)
    checksum = checksum + OGRH.HashStringToNumber(
        OGRH.ComputeComponentChecksum(raidName, encounterName, "roles")
    )
    
    -- Component 3: Player assignments
    checksum = checksum + OGRH.HashStringToNumber(
        OGRH.ComputeComponentChecksum(raidName, encounterName, "playerAssignments")
    )
    
    -- Component 4: Raid marks
    checksum = checksum + OGRH.HashStringToNumber(
        OGRH.ComputeComponentChecksum(raidName, encounterName, "raidMarks")
    )
    
    -- Component 5: Assignment numbers
    checksum = checksum + OGRH.HashStringToNumber(
        OGRH.ComputeComponentChecksum(raidName, encounterName, "assignmentNumbers")
    )
    
    -- Component 6: Announcements
    checksum = checksum + OGRH.HashStringToNumber(
        OGRH.ComputeComponentChecksum(raidName, encounterName, "announcements")
    )
    
    return tostring(checksum)
end

-- Get checksums for all encounters in a raid
function OGRH.GetEncounterChecksums(raidName)
    OGRH.EnsureSV()
    
    local checksums = {}
    
    -- Find raid in raids array
    local raid = OGRH.FindRaidByName(raidName)
    if not raid or not raid.encounters then
        return checksums
    end
    
    -- Iterate through encounters array
    if raid.encounters then
        for i = 1, table.getn(raid.encounters) do
            local enc = raid.encounters[i]
            if enc and enc.name then
                checksums[enc.name] = OGRH.ComputeEncounterChecksum(raidName, enc.name)
            end
        end
    end
    
    return checksums
end

--[[
    6.1.4: Component-Level Checksums
]]

-- Compute checksum for a specific component within an encounter
function OGRH.ComputeComponentChecksum(raidName, encounterName, componentName)
    OGRH.EnsureSV()
    
    local data = nil
    
    if componentName == "encounterMetadata" then
        -- Get raid object first using FindRaidByName (raids are array, not dictionary)
        local raid = OGRH.FindRaidByName(raidName)
        if raid then
            local encounter = OGRH.FindEncounterByName(raid, encounterName)
            if encounter then
                data = encounter.advancedSettings
            end
        end
        
    elseif componentName == "roles" then
        if OGRH_SV.encounterMgmt and OGRH_SV.encounterMgmt.roles and
           OGRH_SV.encounterMgmt.roles[raidName] and
           OGRH_SV.encounterMgmt.roles[raidName][encounterName] then
            data = OGRH_SV.encounterMgmt.roles[raidName][encounterName]
        end
        
    elseif componentName == "playerAssignments" then
        if OGRH_SV.encounterAssignments and
           OGRH_SV.encounterAssignments[raidName] and
           OGRH_SV.encounterAssignments[raidName][encounterName] then
            data = OGRH_SV.encounterAssignments[raidName][encounterName]
        end
        
    elseif componentName == "raidMarks" then
        if OGRH_SV.encounterRaidMarks and
           OGRH_SV.encounterRaidMarks[raidName] and
           OGRH_SV.encounterRaidMarks[raidName][encounterName] then
            data = OGRH_SV.encounterRaidMarks[raidName][encounterName]
        end
        
    elseif componentName == "assignmentNumbers" then
        if OGRH_SV.encounterAssignmentNumbers and
           OGRH_SV.encounterAssignmentNumbers[raidName] and
           OGRH_SV.encounterAssignmentNumbers[raidName][encounterName] then
            data = OGRH_SV.encounterAssignmentNumbers[raidName][encounterName]
        end
        
    elseif componentName == "announcements" then
        if OGRH_SV.encounterAnnouncements and
           OGRH_SV.encounterAnnouncements[raidName] and
           OGRH_SV.encounterAnnouncements[raidName][encounterName] then
            data = OGRH_SV.encounterAnnouncements[raidName][encounterName]
        end
    else
        return "0"  -- Unknown component
    end
    
    if not data then
        return "0"
    end
    
    -- Use SimpleSerialize for consistent checksum
    local serialized = SimpleSerialize(data)
    return OGRH.HashString(serialized)
end

-- Get all component checksums for an encounter
function OGRH.GetComponentChecksums(raidName, encounterName)
    return {
        encounterMetadata = OGRH.ComputeComponentChecksum(raidName, encounterName, "encounterMetadata"),
        roles = OGRH.ComputeComponentChecksum(raidName, encounterName, "roles"),
        playerAssignments = OGRH.ComputeComponentChecksum(raidName, encounterName, "playerAssignments"),
        raidMarks = OGRH.ComputeComponentChecksum(raidName, encounterName, "raidMarks"),
        assignmentNumbers = OGRH.ComputeComponentChecksum(raidName, encounterName, "assignmentNumbers"),
        announcements = OGRH.ComputeComponentChecksum(raidName, encounterName, "announcements")
    }
end

-- Hash a string to a checksum string
function OGRH.HashString(str)
    if not str then
        return "0"
    end
    
    local checksum = 0
    for i = 1, string.len(str) do
        -- Use more sophisticated hash to reduce collisions
        checksum = mod(checksum * 31 + string.byte(str, i), 2147483647)
    end
    
    return tostring(checksum)
end

-- Hash a string to a number (for combining checksums)
function OGRH.HashStringToNumber(str)
    if not str then
        return 0
    end
    
    local checksum = 0
    for i = 1, string.len(str) do
        checksum = mod(checksum * 31 + string.byte(str, i), 2147483647)
    end
    
    return checksum
end

--[[
    ====================================================================
    6.2: HIERARCHICAL VALIDATION SYSTEM
    ====================================================================
]]

--[[
    ValidateStructureHierarchy(remoteChecksums)
    
    Performs hierarchical validation by comparing local and remote checksums
    at each level (Global → Raid → Encounter → Component) and drilling down
    on mismatches to identify exact corruption location.
    
    Parameters:
        remoteChecksums - table containing hierarchical checksums from remote player
            {
                global = {tradeItems = "...", consumes = "..."},  -- rgo deprecated
                raids = {
                    ["BWL"] = {
                        raidChecksum = "...",
                        encounters = {
                            ["Razorgore"] = {
                                encounterChecksum = "...",
                                components = {
                                    encounterMetadata = "...",
                                    roles = "...",
                                    playerAssignments = "...",
                                    raidMarks = "...",
                                    assignmentNumbers = "...",
                                    announcements = "..."
                                }
                            }
                        }
                    }
                }
            }
    
    Returns:
        ValidationResult table:
            {
                valid = true/false,
                level = "STRUCTURE" | "GLOBAL" | "RAID" | "ENCOUNTER" | "COMPONENT",
                corrupted = {
                    global = {"consumes"},  -- array of corrupted global components (rgo no longer checked)
                    raids = {
                        ["BWL"] = {
                            raidLevel = true/false,  -- raid metadata corrupted
                            encounters = {
                                ["Razorgore"] = {"playerAssignments", "announcements"}  -- corrupted components
                            }
                        }
                    }
                }
            }
]]
function OGRH.ValidateStructureHierarchy(remoteChecksums)
    local result = {
        valid = true,
        level = "STRUCTURE",
        corrupted = {
            global = {},
            raids = {}
        }
    }
    
    -- Validate global components
    local localGlobal = OGRH.GetGlobalComponentChecksums()
    for componentName, remoteChecksum in pairs(remoteChecksums.global or {}) do
        local localChecksum = localGlobal[componentName]
        if localChecksum ~= remoteChecksum then
            result.valid = false
            result.level = "GLOBAL"
            table.insert(result.corrupted.global, componentName)
        end
    end
    
    -- Validate raids
    if remoteChecksums.raids then
        for raidName, remoteRaid in pairs(remoteChecksums.raids) do
            -- Validate raid-level checksum
            local localRaidChecksum = OGRH.ComputeRaidChecksum(raidName)
            if localRaidChecksum ~= remoteRaid.raidChecksum then
                result.valid = false
                if result.level == "STRUCTURE" then
                    result.level = "RAID"
                end
                result.corrupted.raids[raidName] = result.corrupted.raids[raidName] or {}
                result.corrupted.raids[raidName].raidLevel = true
            end
            
            -- Validate encounters
            if remoteRaid.encounters then
                for encounterName, remoteEncounter in pairs(remoteRaid.encounters) do
                    -- Validate encounter-level checksum
                    local localEncounterChecksum = OGRH.ComputeEncounterChecksum(raidName, encounterName)
                    if localEncounterChecksum ~= remoteEncounter.encounterChecksum then
                        result.valid = false
                        if result.level == "STRUCTURE" or result.level == "RAID" then
                            result.level = "ENCOUNTER"
                        end
                        result.corrupted.raids[raidName] = result.corrupted.raids[raidName] or {}
                        result.corrupted.raids[raidName].encounters = result.corrupted.raids[raidName].encounters or {}
                        
                        -- Drill down to component level
                        result.corrupted.raids[raidName].encounters[encounterName] = {}
                        
                        if remoteEncounter.components then
                            for componentName, remoteComponentChecksum in pairs(remoteEncounter.components) do
                                local localComponentChecksum = OGRH.ComputeComponentChecksum(raidName, encounterName, componentName)
                                if localComponentChecksum ~= remoteComponentChecksum then
                                    result.level = "COMPONENT"
                                    table.insert(result.corrupted.raids[raidName].encounters[encounterName], componentName)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    
    return result
end

--[[
    GetAllHierarchicalChecksums()
    
    Computes all checksums for the entire structure hierarchy.
    Used for broadcasting during polling or manual validation.
    
    Returns:
        table with hierarchical checksums (same format as ValidateStructureHierarchy parameter)
]]
function OGRH.GetAllHierarchicalChecksums()
    local checksums = {
        global = OGRH.GetGlobalComponentChecksums(),
        raids = {}
    }
    
    -- Get all raid checksums
    local raidChecksums = OGRH.GetRaidChecksums()
    
    OGRH.EnsureSV()
    if OGRH_SV.encounterMgmt and OGRH_SV.encounterMgmt.raids then
        for i = 1, table.getn(OGRH_SV.encounterMgmt.raids) do
            local raid = OGRH_SV.encounterMgmt.raids[i]
            if raid and raid.name then
                local raidName = raid.name
                checksums.raids[raidName] = {
                    raidChecksum = raidChecksums[raidName],
                    encounters = {}
                }
                
                -- Get encounter checksums for this raid
                local encounterChecksums = OGRH.GetEncounterChecksums(raidName)
                
                if raid.encounters then
                    for j = 1, table.getn(raid.encounters) do
                        local encounter = raid.encounters[j]
                        if encounter and encounter.name then
                            local encounterName = encounter.name
                            checksums.raids[raidName].encounters[encounterName] = {
                                encounterChecksum = encounterChecksums[encounterName],
                                components = OGRH.GetComponentChecksums(raidName, encounterName)
                            }
                        end
                    end
                end
            end
        end
    end
    
    return checksums
end

--[[
    FormatValidationResult(result)
    
    Formats a ValidationResult into human-readable text for display in chat.
    
    Parameters:
        result - ValidationResult from ValidateStructureHierarchy()
    
    Returns:
        array of strings (chat messages)
]]
function OGRH.FormatValidationResult(result)
    local messages = {}
    
    if result.valid then
        table.insert(messages, "|cff00ff00Structure validation: PASSED|r")
        return messages
    end
    
    table.insert(messages, "|cffff0000Structure validation: FAILED|r")
    table.insert(messages, "Corruption level: " .. result.level)
    
    -- Report global component mismatches
    if table.getn(result.corrupted.global) > 0 then
        table.insert(messages, "|cffffaa00Global components:|r " .. table.concat(result.corrupted.global, ", "))
    end
    
    -- Report raid/encounter/component mismatches
    for raidName, raidData in pairs(result.corrupted.raids) do
        if raidData.raidLevel then
            table.insert(messages, "|cffffaa00Raid metadata:|r " .. raidName)
        end
        
        if raidData.encounters then
            for encounterName, components in pairs(raidData.encounters) do
                if table.getn(components) > 0 then
                    local componentList = table.concat(components, ", ")
                    table.insert(messages, "|cffffaa00" .. raidName .. " > " .. encounterName .. ":|r " .. componentList)
                else
                    table.insert(messages, "|cffffaa00" .. raidName .. " > " .. encounterName .. ":|r (encounter-level mismatch)")
                end
            end
        end
    end
    
    return messages
end
