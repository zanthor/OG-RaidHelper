-- OGRH_SyncIntegrity.lua (Turtle-WoW 1.12)
-- Checksum verification and data integrity system
-- Phase 3B: Active Raid checksum polling and automatic repair system

OGRH = OGRH or {}
OGRH.SyncIntegrity = {}

--[[
    Active Raid Checksum Polling System
    
    Admin broadcasts every 30 seconds:
    - Active Raid structure checksum (all encounters/roles, but NO assignments)
    - Active Encounter assignments checksum (current encounter only)
    - RolesUI checksum (global TANKS/HEALERS/MELEE/RANGED buckets)
    - Global components checksum (consumes, tradeItems)
    
    Clients compare their checksums to admin's broadcast:
    - On mismatch: Broadcast repair request to raid
    - Admin buffers repair requests for 1 second (prevent storms)
    - Admin broadcasts repair data once per component
    - Clients receive and apply repair data
]]

OGRH.SyncIntegrity.State = {
    lastChecksumBroadcast = 0,
    verificationInterval = 30,  -- seconds
    checksumCache = {},
    pollingTimer = nil,
    enabled = false,
    
    -- Admin modification cooldown (suppress broadcasts while admin is actively editing)
    lastAdminModification = 0,  -- timestamp of last admin change
    modificationCooldown = 10,  -- seconds to wait after last change before broadcasting
    
    -- Player join tracking
    lastRaidSize = 0,  -- Track raid size to detect joins
    
    -- Encounter broadcast
    lastEncounterBroadcast = 0,  -- timestamp of last encounter broadcast
    encounterBroadcastInterval = 15,  -- seconds
    
    -- Repair cooldown (prevent repair loops)
    repairCooldownUntil = nil,  -- timestamp when cooldown expires
    encounterBroadcastTimer = nil,
    
    -- Debug mode (toggle with /ogrh debug sync)
    debug = false,  -- Hide verbose sync messages by default
    
    -- Phase 5: Repair mode suppression
    repairModeActive = false,  -- Suppress broadcasts during active repairs
    bufferedRequests = {},  -- Buffer repair requests during active repairs
}

--[[
    Helper Functions
    
    NOTE: Checksum and serialization functions have been consolidated into
    _Infrastructure/SyncChecksum.lua. All calls now delegate to that module.
]]

--[[
    Core Functions
]]

-- Admin: Broadcast Active Raid checksums to raid
function OGRH.SyncIntegrity.BroadcastChecksums(forceImmediate)
    if OGRH.SyncIntegrity.State.debug then
        OGRH.Msg("|cff00ccff[RH-SyncIntegrity][DEBUG]|r BroadcastChecksums() called, force=" .. tostring(forceImmediate))
    end
    
    -- Check if sync mode is enabled
    if OGRH.SyncMode then
        if OGRH.SyncMode.IsSyncEnabled then
            local syncEnabled = OGRH.SyncMode.IsSyncEnabled()
            if not syncEnabled then
                OGRH.Msg("|cff888888[RH-SyncIntegrity]|r Skipping broadcast (sync mode disabled)")
                return
            end
        else
            OGRH.Msg("|cffff0000[RH-SyncIntegrity ERROR]|r SyncMode.IsSyncEnabled function not found!")
        end
    else
        OGRH.Msg("|cffff0000[RH-SyncIntegrity ERROR]|r SyncMode module not loaded!")
    end
    
    -- Phase 5: Suppress broadcasts during active repair sessions
    if OGRH.SyncIntegrity.State.repairModeActive then
        if OGRH.SyncIntegrity.State.debug then
            OGRH.Msg("|cff888888[RH-SyncIntegrity]|r Skipping broadcast (repair mode active)")
        end
        return
    end
    
    if GetNumRaidMembers() == 0 then
        OGRH.Msg("|cffff9900[RH-SyncIntegrity]|r Not broadcasting - not in raid")
        return
    end
    
    -- Check if network queue is busy (skip if more than 10 messages pending)
    if OGAddonMsg and OGAddonMsg.stats and OGAddonMsg.stats.queueDepth then
        if OGAddonMsg.stats.queueDepth > 10 then
            if OGRH.SyncIntegrity.State.debug then
                OGRH.Msg(string.format("|cff888888[RH-SyncIntegrity]|r Skipping broadcast (network queue busy: %d messages pending)", OGAddonMsg.stats.queueDepth))
            end
            return
        end
    end
    
    -- NEVER broadcast if admin is in combat
    if UnitAffectingCombat("player") then
        if OGRH.SyncIntegrity.State.debug then
            OGRH.Msg("|cff888888[RH-SyncIntegrity]|r Skipping broadcast (in combat)")
        end
        return
    end
    
    -- Skip broadcast if admin made changes recently (unless forced)
    if not forceImmediate then
        local timeSinceLastMod = GetTime() - OGRH.SyncIntegrity.State.lastAdminModification
        if timeSinceLastMod < OGRH.SyncIntegrity.State.modificationCooldown then
            local remaining = OGRH.SyncIntegrity.State.modificationCooldown - timeSinceLastMod
            if OGRH.SyncIntegrity.State.debug then
                OGRH.Msg(string.format("|cff888888[RH-SyncIntegrity]|r Skipping broadcast (data modified %.0fs ago, cooldown %.0fs)", 
                    timeSinceLastMod, remaining))
            end
            return
        end
    end
    
    -- Broadcast Active Raid checksums only (index 1)
    local activeRaid = OGRH.GetActiveRaid()
    if not activeRaid then
        if OGRH.SyncIntegrity.State.debug then
            OGRH.Msg("|cffff9900[RH-SyncIntegrity]|r No Active Raid found, skipping broadcast")
        end
        return
    end
    
    -- Get current encounter index for assignments checksum
    local currentEncounter = OGRH.SVM and OGRH.SVM.Get("ui", "selectedEncounter") or nil
    local currentEncounterIdx = nil
    if currentEncounter and activeRaid.encounters then
        for i = 1, table.getn(activeRaid.encounters) do
            if activeRaid.encounters[i].name == currentEncounter then
                currentEncounterIdx = i
                break
            end
        end
    end
    
    local lightweightChecksums = {
        -- Raid identification
        activeRaidName = activeRaid.name,  -- CRITICAL: Client needs to know which raid to validate
        
        -- Layer 1: Raid structure checksum (metadata only, no encounters content)
        structureChecksum = OGRH.SyncChecksum.ComputeRaidStructureChecksum(activeRaid.name),
        
        -- Layer 2: Per-encounter structure checksums (array)
        encountersChecksums = OGRH.SyncChecksum.ComputeEncountersChecksums(activeRaid.name),
        
        -- Layer 3: Per-role structure checksums (2D array [enc][role])
        rolesChecksums = OGRH.SyncChecksum.ComputeRolesChecksums(activeRaid.name),
        
        -- Layer 4: Per-role assignment checksums (2D array [enc][role])
        apRoleChecksums = OGRH.SyncChecksum.ComputeApRoleChecksums(activeRaid.name),
        
        -- Layer 5: Global roles (TANKS, HEALERS, MELEE, RANGED)
        rolesUIChecksum = OGRH.SyncChecksum.CalculateRolesUIChecksum(),
        
        -- Active encounter context (for UI display)
        activeEncounterIdx = currentEncounterIdx,
        
        -- Metadata
        timestamp = GetTime(),
        version = OGRH.VERSION or "1.0"
    }
    
    -- Broadcast via MessageRouter
    if OGRH.MessageRouter and OGRH.MessageTypes then
        OGRH.MessageRouter.Broadcast(
            OGRH.MessageTypes.SYNC.CHECKSUM_POLL,
            lightweightChecksums,
            {
                priority = "LOW",  -- Background traffic
                onSuccess = function()
                    OGRH.SyncIntegrity.State.lastChecksumBroadcast = GetTime()
                    OGRH.Msg("|cff00ccff[RH-SyncIntegrity]|r Broadcast Active Raid checksums")
                end
            }
        )
    end
end

-- Client: Handle checksum broadcast from admin
function OGRH.SyncIntegrity.OnChecksumBroadcast(sender, checksums)
    -- CRITICAL: Skip validation if client is currently in an active repair session
    -- Validating during repair causes false mismatches (packets still being applied)
    if OGRH.SyncRepairHandlers and OGRH.SyncRepairHandlers.currentToken then
        if OGRH.SyncIntegrity.State.debug then
            OGRH.Msg("|cffaaaaaa[RH-SyncIntegrity DEBUG]|r Skipping validation: repair session active (token=" .. tostring(OGRH.SyncRepairHandlers.currentToken) .. ")")
        end
        return
    end
    
    -- Skip validation if we just completed a repair (data still settling)
    if OGRH.SyncRepairHandlers and OGRH.SyncRepairHandlers.skipNextChecksumValidation then
        OGRH.SyncRepairHandlers.skipNextChecksumValidation = false  -- Consume the flag
        OGRH.Msg("|cff888888[RH-SyncIntegrity]|r Skipping post-repair validation (data settling)")
        return
    end
    
    -- Client-side post-repair cooldown: don't re-validate too soon after a repair
    if OGRH.SyncRepairHandlers and OGRH.SyncRepairHandlers.repairCompletedAt then
        local elapsed = GetTime() - OGRH.SyncRepairHandlers.repairCompletedAt
        if elapsed < 30 then
            if OGRH.SyncIntegrity.State.debug then
                OGRH.Msg(string.format("|cff888888[RH-SyncIntegrity]|r Skipping validation: post-repair cooldown (%.0fs remaining)", 30 - elapsed))
            end
            return
        end
    end
    
    -- Verify sender is the addon's raid admin
    local currentAdmin = OGRH.GetRaidAdmin and OGRH.GetRaidAdmin()
    
    if OGRH.SyncIntegrity.State.debug then
        OGRH.Msg("|cffaaaaaa[RH-SyncIntegrity DEBUG]|r OnChecksumBroadcast called: sender=" .. (sender or "nil") .. ", currentAdmin=" .. (currentAdmin or "nil"))
    end
    
    if not currentAdmin or sender ~= currentAdmin then
        if OGRH.SyncIntegrity.State.debug then
            OGRH.Msg("|cffaaaaaa[RH-SyncIntegrity DEBUG]|r Ignoring: sender is not admin")
        end
        return  -- Ignore checksums from non-admins
    end
    
    -- Don't validate against ourselves (admin receives their own broadcast)
    if sender == UnitName("player") then
        if OGRH.SyncIntegrity.State.debug then
            OGRH.Msg("|cffaaaaaa[RH-SyncIntegrity DEBUG]|r Ignoring: sender is self")
        end
        return
    end
    
    OGRH.Msg("|cff00ff00[RH-SyncIntegrity]|r Received checksum broadcast from admin " .. sender)
    
    -- Validate hierarchical checksums
    if not (checksums.structureChecksum and checksums.encountersChecksums and checksums.rolesChecksums and checksums.apRoleChecksums and checksums.rolesUIChecksum) then
        OGRH.Msg("|cffff0000[RH-SyncIntegrity]|r ERROR: Invalid checksum format received")
        return
    end
    
    local mismatches = {}
    
    -- Hierarchical validation: Track mismatches per encounter
    local activeRaid = OGRH.GetActiveRaid()
    if activeRaid then
        local localStructure = OGRH.SyncChecksum.ComputeRaidStructureChecksum(activeRaid.name)
        if OGRH.SyncIntegrity.State.debug then
            OGRH.Msg(string.format("|cffaaaaaa[RH-SyncIntegrity][DEBUG]|r Structure checksums: local=%s, admin=%s", localStructure, checksums.structureChecksum))
        end
        
        -- Layer 1: Validate Raid structure
        if localStructure ~= checksums.structureChecksum then
            table.insert(mismatches, {
                type = "STRUCTURE",
                component = "structure"
            })
            if OGRH.SyncIntegrity.State.debug then
                OGRH.Msg("|cffff8800[RH-SyncIntegrity][DEBUG]|r Mismatch detected: Raid structure")
            end
        end
        
        -- Hierarchical encounter validation: Track highest-level mismatch per encounter
        local encounterMismatches = {}  -- [encIdx] = {level, data}
        
        -- Layer 2: Check encounter structure (highest priority)
        local localEncounters = OGRH.SyncChecksum.ComputeEncountersChecksums(activeRaid.name)
        for encIdx, adminChecksum in pairs(checksums.encountersChecksums) do
            local localChecksum = localEncounters[encIdx]
            if localChecksum ~= adminChecksum then
                encounterMismatches[encIdx] = {
                    level = 2,  -- Encounter structure
                    type = "ENCOUNTER_STRUCTURE",
                    component = "encounter",
                    encounterIdx = encIdx
                }
                if OGRH.SyncIntegrity.State.debug then
                    OGRH.Msg(string.format("|cffff8800[RH-SyncIntegrity][DEBUG]|r Mismatch detected: Encounter #%d structure", encIdx))
                end
            end
        end
        
        -- Layer 3: Check roles (only if encounter structure matched)
        local localRoles = OGRH.SyncChecksum.ComputeRolesChecksums(activeRaid.name)
        for encIdx, roleChecksums in pairs(checksums.rolesChecksums) do
            if not encounterMismatches[encIdx] then  -- Only check if encounter structure matched
                for roleIdx, adminChecksum in pairs(roleChecksums) do
                    local localChecksum = localRoles[encIdx] and localRoles[encIdx][roleIdx]
                    if localChecksum ~= adminChecksum then
                        -- Role mismatch detected, but encounter repair fixes this too
                        if not encounterMismatches[encIdx] or encounterMismatches[encIdx].level > 3 then
                            encounterMismatches[encIdx] = {
                                level = 3,  -- Role structure (but will trigger encounter repair)
                                type = "ENCOUNTER_STRUCTURE",
                                component = "encounter",
                                encounterIdx = encIdx
                            }
                            if OGRH.SyncIntegrity.State.debug then
                                OGRH.Msg(string.format("|cffff8800[RH-SyncIntegrity][DEBUG]|r Mismatch detected: Encounter #%d, Role #%d - requesting encounter repair", encIdx, roleIdx))
                            end
                        end
                        break  -- One role mismatch means whole encounter needs repair
                    end
                end
            end
        end
        
        -- Layer 4: Check assignments (only if encounter and roles matched)
        local localAssignments = OGRH.SyncChecksum.ComputeApRoleChecksums(activeRaid.name)
        for encIdx, roleAssignments in pairs(checksums.apRoleChecksums) do
            if not encounterMismatches[encIdx] then  -- Only check if encounter and roles matched
                for roleIdx, adminChecksum in pairs(roleAssignments) do
                    local localChecksum = localAssignments[encIdx] and localAssignments[encIdx][roleIdx]
                    if localChecksum ~= adminChecksum then
                        -- Assignment mismatch detected, but encounter repair fixes this too
                        if not encounterMismatches[encIdx] then
                            encounterMismatches[encIdx] = {
                                level = 4,  -- Assignments (but will trigger encounter repair)
                                type = "ENCOUNTER_STRUCTURE",
                                component = "encounter",
                                encounterIdx = encIdx
                            }
                            if OGRH.SyncIntegrity.State.debug then
                                OGRH.Msg(string.format("|cffff8800[RH-SyncIntegrity][DEBUG]|r Mismatch detected: Encounter #%d, Role #%d assignments - requesting encounter repair", encIdx, roleIdx))
                            end
                        end
                        break  -- One assignment mismatch means whole encounter needs repair
                    end
                end
            end
        end
        
        -- Add encounter mismatches to main list
        for encIdx, mismatch in pairs(encounterMismatches) do
            table.insert(mismatches, mismatch)
        end
    end
    
    -- Layer 5: Validate RolesUI (global roles)
    local localRolesUI = OGRH.SyncChecksum.CalculateRolesUIChecksum()
    if OGRH.SyncIntegrity.State.debug then
        OGRH.Msg(string.format("|cffaaaaaa[RH-SyncIntegrity][DEBUG]|r RolesUI checksums: local=%s, admin=%s", localRolesUI, checksums.rolesUIChecksum))
    end
    if localRolesUI ~= checksums.rolesUIChecksum then
        table.insert(mismatches, {
            type = "ROLES_UI",
            component = "rolesui"
        })
        if OGRH.SyncIntegrity.State.debug then
            OGRH.Msg("|cffff8800[RH-SyncIntegrity][DEBUG]|r Mismatch detected: RolesUI (global role assignments)")
        end
    end
    
    -- If mismatches found, queue repair requests
    if table.getn(mismatches) > 0 then
        OGRH.Msg(string.format("|cffff9900[RH-SyncIntegrity]|r %d checksum mismatch(es) detected - requesting repairs from admin", table.getn(mismatches)))
        
        -- Mark that THIS client has requested repairs (will accept next repair session)
        OGRH.SyncRepairHandlers.hasRequestedRepair = true
        
        for i = 1, table.getn(mismatches) do
            OGRH.SyncIntegrity.QueueRepairRequest(sender, mismatches[i])
        end
    else
        OGRH.Msg("|cff00ff00[RH-SyncIntegrity]|r All checksums validated successfully - data in sync")
    end
end

-- Client: Broadcast repair request (admin will buffer for 1 second)
function OGRH.SyncIntegrity.QueueRepairRequest(adminName, mismatch)
    -- Check if sync mode is enabled
    if OGRH.SyncMode and not OGRH.SyncMode.CanRequestRepair() then
        if OGRH.SyncIntegrity.State.debug then
            OGRH.Msg("|cff888888[RH-SyncIntegrity]|r Skipping repair request (sync mode disabled)")
        end
        return
    end
    
    -- Broadcast repair request to raid (admin will buffer)
    if OGRH.MessageRouter and OGRH.MessageTypes then
        local requestData = {
            type = mismatch.type,
            component = mismatch.component,
            encounterIdx = mismatch.encounterIdx
        }
        
        OGRH.MessageRouter.Broadcast(
            OGRH.MessageTypes.SYNC.REPAIR_REQUEST,
            requestData,
            {
                priority = "LOW"
            }
        )
        
        -- Always log repair requests
        local componentDesc = mismatch.component
        if mismatch.encounterIdx then
            componentDesc = string.format("%s (Enc %d)", mismatch.component, mismatch.encounterIdx)
        end
        OGRH.Msg(string.format("|cffff9900[RH-SyncIntegrity]|r Requesting repair: %s", componentDesc))
    end
end

-- Admin: Repair request buffer (prevents broadcast storms)
OGRH.SyncIntegrity.RepairBuffer = {
    requests = {},      -- {component, encounterIdx, requesters = {}}
    timer = nil,
    timeout = 1.0
}

-- Get repair buffer timeout based on Invite Mode
local function GetRepairBufferTimeout()
    -- Check if Invite Mode is active
    local inviteMode = OGRH_SV and OGRH_SV.v2 and OGRH_SV.v2.invites and OGRH_SV.v2.invites.enabled
    return inviteMode and 5.0 or 1.0
end

-- Admin: Handle repair request from clients (buffer dynamically)
function OGRH.SyncIntegrity.OnRepairRequest(sender, data)
    if not data or not data.component then return end
    
    -- Only admin can send repairs
    if not OGRH.CanModifyStructure(UnitName("player")) then
        return
    end
    
    -- Phase 5: Buffer requests during active repair
    if OGRH.SyncIntegrity.State.repairModeActive then
        if OGRH.SyncIntegrity.State.debug then
            OGRH.Msg(string.format("|cffff00ff[RH-SyncIntegrity ADMIN]|r Buffering repair request from %s (repair mode active)", sender))
        end
        OGRH.SyncIntegrity.BufferRepairRequest(sender, data.component, nil)
        return
    end
    
    if OGRH.SyncIntegrity.State.debug then
        OGRH.Msg("|cffff00ff[RH-SyncIntegrity ADMIN]|r Repair request from " .. tostring(sender) .. " for " .. tostring(data.component))
    end
    
    -- Add to buffer
    local buffer = OGRH.SyncIntegrity.RepairBuffer
    local key = data.component .. "_" .. tostring(data.encounterIdx or "")
    
    if not buffer.requests[key] then
        buffer.requests[key] = {
            component = data.component,
            encounterIdx = data.encounterIdx,
            requesters = {}
        }
    end
    
    -- Track who requested (for debugging)
    table.insert(buffer.requests[key].requesters, sender)
    
    -- Start/reset timer with dynamic timeout
    if buffer.timer then
        OGRH.CancelTimer(buffer.timer)
    end
    
    local timeout = GetRepairBufferTimeout()
    if OGRH.SyncIntegrity.State.debug then
        OGRH.Msg(string.format("|cff00ccff[RH-SyncIntegrity][DEBUG]|r Buffering repair request (timeout: %.1fs)", timeout))
    end
    
    buffer.timer = OGRH.ScheduleTimer(function()
        OGRH.SyncIntegrity.FlushRepairBuffer()
    end, buffer.timeout)
end

-- Admin: Flush repair buffer and initiate surgical repair session (Phase 6)
function OGRH.SyncIntegrity.FlushRepairBuffer()
    local buffer = OGRH.SyncIntegrity.RepairBuffer
    
    -- Check cooldown (prevent repair loops)
    local now = GetTime()
    if OGRH.SyncIntegrity.State.repairCooldownUntil and now < OGRH.SyncIntegrity.State.repairCooldownUntil then
        local remaining = math.ceil(OGRH.SyncIntegrity.State.repairCooldownUntil - now)
        if OGRH.SyncIntegrity.State.debug then
            OGRH.Msg(string.format("|cffff9900[RH-SyncIntegrity]|r Repair on cooldown (%ds remaining), buffering requests", remaining))
        end
        -- Reschedule for after cooldown
        if buffer.timer then
            OGRH.CancelTimer(buffer.timer)
        end
        buffer.timer = OGRH.ScheduleTimer(function()
            OGRH.SyncIntegrity.FlushRepairBuffer()
        end, remaining + 1.0)
        return
    end
    
    local count = 0
    for _ in pairs(buffer.requests) do count = count + 1 end
    
    if count == 0 then
        return  -- Nothing to repair
    end
    
    if OGRH.SyncIntegrity.State.debug then
        OGRH.Msg("|cffff00ff[RH-SyncIntegrity ADMIN]|r Flushing " .. tostring(count) .. " repair request(s), initiating surgical repair session")
    end
    
    -- Phase 6: Build failedLayers from buffered requests
    local failedLayers = {
        structure = false,
        rolesui = false,
        encounters = {},
        roles = {},
        assignments = {}
    }
    
    local encounterSet = {}
    
    -- Log what we're processing (use count variable, not table.getn for dictionary)
    OGRH.Msg(string.format("|cffff00ff[RH-SyncIntegrity ADMIN]|r Processing %d repair request(s) from buffer", count))
    
    for key, request in pairs(buffer.requests) do
        OGRH.Msg(string.format("|cffff00ff[RH-SyncIntegrity ADMIN]|r  Request: component=%s, encounterIdx=%s", tostring(request.component), tostring(request.encounterIdx)))
        
        if request.component == "structure" then
            failedLayers.structure = true
            OGRH.Msg("|cffff00ff[RH-SyncIntegrity ADMIN]|r    → Set structure=true")
        elseif request.component == "encounter" and request.encounterIdx then
            encounterSet[request.encounterIdx] = true
            OGRH.Msg(string.format("|cffff00ff[RH-SyncIntegrity ADMIN]|r    → Added encounter %d", request.encounterIdx))
        elseif request.component == "role" and request.encounterIdx then
            encounterSet[request.encounterIdx] = true
        elseif request.component == "assignments" and request.encounterIdx then
            encounterSet[request.encounterIdx] = true
        elseif request.component == "rolesui" then
            -- Global roles is its own layer
            failedLayers.rolesui = true
            OGRH.Msg("|cffff00ff[RH-SyncIntegrity ADMIN]|r    → Set rolesui=true")
        end
    end
    
    -- Convert encounter set to array
    for encIdx, _ in pairs(encounterSet) do
        table.insert(failedLayers.encounters, encIdx)
    end
    
    -- NOTE: We do NOT auto-queue assignments when repairing encounters
    -- Encounter repairs include role structure (name, column, slots, raidMarks, assignmentNumbers)
    -- Assignments repairs ONLY contain assignedPlayers (player names)
    -- If assignedPlayers checksums fail, clients will request ASSIGNMENTS repairs separately
    
    -- Build client list from requesters BEFORE clearing buffer
    local clientMap = {}  -- Deduplicate client names
    for key, request in pairs(buffer.requests) do
        if request.requesters then
            for i = 1, table.getn(request.requesters) do
                local clientName = request.requesters[i]
                if not clientMap[clientName] then
                    clientMap[clientName] = {
                        name = clientName,
                        components = {},
                        priority = 999  -- Lower number = higher priority
                    }
                end
                
                -- Track component and determine priority
                table.insert(clientMap[clientName].components, request.component)
                
                -- Priority: structure (1) > encounter (2) > role (3) > assignments (4)
                local componentPriority = 999
                if request.component == "structure" then
                    componentPriority = 1
                elseif request.component == "encounter" then
                    componentPriority = 2
                elseif request.component == "role" then
                    componentPriority = 3
                elseif request.component == "assignments" then
                    componentPriority = 4
                end
                
                -- Track highest priority (lowest number)
                if componentPriority < clientMap[clientName].priority then
                    clientMap[clientName].priority = componentPriority
                    clientMap[clientName].displayComponent = request.component
                end
            end
        end
    end
    
    -- Convert map to array
    local clientList = {}
    for _, client in pairs(clientMap) do
        -- Use only the highest priority component for display
        client.components = client.displayComponent or "Unknown"
        table.insert(clientList, client)
    end
    
    -- Clear buffer
    buffer.requests = {}
    buffer.timer = nil
    
    -- Initiate surgical repair session
    if OGRH.SyncRepairHandlers and OGRH.SyncRepairHandlers.InitiateRepair then
        local activeRaid = OGRH.GetActiveRaid()
        if activeRaid and activeRaid.name then
            OGRH.SyncRepairHandlers.InitiateRepair(activeRaid.name, failedLayers, 1, clientList)
        end
    else
        OGRH.Msg("|cffff0000[RH-SyncIntegrity]|r ERROR: SyncRepairHandlers not loaded")
    end
end

--[[
    ============================================================================
    LEGACY BROADCAST REPAIR SYSTEM (Phase 1-3) - COMMENTED OUT
    ============================================================================
    
    These functions are replaced by Phase 6 Surgical Repair System.
    Kept commented out for troubleshooting if needed.
    
    New flow uses:
    - SyncRepairHandlers.InitiateRepair() (admin)
    - SyncRepairHandlers.OnRepairPacket() (client)
    
    Legacy flow used:
    - BroadcastActiveRaidRepair() → OnActiveRaidRepair()
    - BroadcastAssignmentsRepair() → OnAssignmentsRepair()
    - BroadcastRolesRepair() → OnRolesRepair()
    
    ============================================================================
    ADMIN-SIDE BROADCAST FUNCTIONS
    ============================================================================

-- Admin: Broadcast Active Raid structure for repair
function OGRH.SyncIntegrity.BroadcastActiveRaidRepair()
    if OGRH.SyncIntegrity.State.debug then
        OGRH.Msg("|cffaaffaa[RH-SyncIntegrity DEBUG]|r BroadcastActiveRaidRepair() called")
    end
    
    local activeRaid = OGRH_SV.v2.encounterMgmt.raids[1]
    if not activeRaid then 
        if OGRH.SyncIntegrity.State.debug then
            OGRH.Msg("|cffff0000[RH-SyncIntegrity DEBUG]|r No active raid found")
        end
        return 
    end
    
    if OGRH.SyncIntegrity.State.debug then
        OGRH.Msg("|cffaaffaa[RH-SyncIntegrity DEBUG]|r Active raid exists, preparing copy")
    end
    
    local raidCopy = OGRH.DeepCopy(activeRaid)
    
    if OGRH.SyncIntegrity.State.debug then
        OGRH.Msg("|cffaaffaa[RH-SyncIntegrity DEBUG]|r Calling MessageRouter.Broadcast...")
    end
    
    local msgId = OGRH.MessageRouter.Broadcast(
        OGRH.MessageTypes.SYNC.REPAIR_ACTIVE_RAID,
        raidCopy,
        {
            priority = "LOW",
            compress = true
        }
    )
    
    if OGRH.SyncIntegrity.State.debug then
        OGRH.Msg("|cffff00ff[RH-SyncIntegrity ADMIN]|r Broadcast Active Raid structure repair (msgId: " .. tostring(msgId) .. ")")
    end
end

-- Admin: Broadcast Active Raid assignments for ALL encounters
function OGRH.SyncIntegrity.BroadcastAssignmentsRepair(encounterIdx)
    local activeRaid = OGRH_SV.v2.encounterMgmt.raids[1]
    if not activeRaid or not activeRaid.encounters then
        return
    end
    
    local allAssignments = {}
    local singleEncounterSize = 0
    local totalSize = 0
    
    for encIdx = 1, table.getn(activeRaid.encounters) do
        local encounter = activeRaid.encounters[encIdx]
        allAssignments[encIdx] = {}
        
        if encounter.roles then
            for roleIdx = 1, table.getn(encounter.roles) do
                local role = encounter.roles[roleIdx]
                allAssignments[encIdx][roleIdx] = {
                    assignedPlayers = role.assignedPlayers or {},
                    raidMarks = role.raidMarks or {},
                    assignmentNumbers = role.assignmentNumbers or {}
                }
                
                local encSize = table.getn(role.assignedPlayers or {}) + table.getn(role.raidMarks or {}) + table.getn(role.assignmentNumbers or {})
                totalSize = totalSize + encSize
                if encIdx == (encounterIdx or 1) then
                    singleEncounterSize = singleEncounterSize + encSize
                end
            end
        end
    end
    
    if OGRH.SyncIntegrity.State.debug then
        OGRH.Msg(string.format("|cff00ccff[RH-SyncIntegrity][DEBUG]|r Assignment payload: Single encounter ~%d items, All encounters ~%d items (%dx larger)", 
            singleEncounterSize, totalSize, totalSize > 0 and math.floor(totalSize / math.max(singleEncounterSize, 1)) or 0))
    end
    
    OGRH.MessageRouter.Broadcast(
        OGRH.MessageTypes.SYNC.REPAIR_ASSIGNMENTS,
        {
            allEncounters = allAssignments
        },
        {
            priority = "LOW",
            compress = true
        }
    )
    
    if OGRH.SyncIntegrity.State.debug then
        OGRH.Msg("|cff00ccff[RH-SyncIntegrity]|r Broadcast assignments repair for ALL encounters")
    end
end

-- Admin: Broadcast RolesUI for repair
function OGRH.SyncIntegrity.BroadcastRolesRepair()
    local roles = OGRH_SV.v2.roles
    if not roles then return end
    
    OGRH.MessageRouter.Broadcast(
        OGRH.MessageTypes.SYNC.REPAIR_ROLES,
        roles,
        {
            priority = "LOW",
            compress = true
        }
    )
    
    if OGRH.SyncIntegrity.State.debug then
        OGRH.Msg("|cff00ccff[RH-SyncIntegrity]|r Broadcast RolesUI repair")
    end
end

-- ============================================================================
-- CLIENT-SIDE REPAIR HANDLERS
-- ============================================================================

-- Client: Receive and apply Active Raid structure repair
function OGRH.SyncIntegrity.OnActiveRaidRepair(sender, data)
    if not data then return end
    
    -- Only accept repairs from admin
    if not OGRH.CanModifyStructure(sender) then
        return
    end
    
    OGRH.Msg("|cff00ff00[RH-SyncIntegrity]|r Received Active Raid structure repair from " .. sender)
    
    -- Apply repair data to Active Raid (index 1)
    OGRH_SV.v2.encounterMgmt.raids[1] = OGRH.DeepCopy(data)
    
    if OGRH.SyncIntegrity.State.debug then
        OGRH.Msg("|cff00ff00[RH-SyncIntegrity]|r Active Raid structure repaired from " .. tostring(sender))
    else
        OGRH.Msg("|cff00ff00[RH]|r Raid data updated")
    end
    
    -- Refresh UI if needed
    if OGRH.MainUI and OGRH.MainUI.Refresh then
        OGRH.MainUI.Refresh()
    end    
    -- Refresh encounter planning interface
    if OGRH_EncounterFrame and OGRH_EncounterFrame.RefreshRoleContainers then
        OGRH_EncounterFrame.RefreshRoleContainers()
    end    
    -- Refresh encounter planning interface
    if OGRH_EncounterFrame and OGRH_EncounterFrame.RefreshRoleContainers then
        OGRH_EncounterFrame.RefreshRoleContainers()
    end
    
    -- Query admin for current encounter selection
    OGRH.MessageRouter.SendTo(sender, OGRH.MessageTypes.STATE.QUERY_ENCOUNTER, {
        requester = UnitName("player")
    })
end

-- Client: Receive and apply assignments repair for ALL encounters
function OGRH.SyncIntegrity.OnAssignmentsRepair(sender, data)
    if not data or not data.allEncounters then return end
    
    -- Only accept repairs from admin
    if not OGRH.CanModifyStructure(sender) then
        return
    end
    
    OGRH.Msg("|cff00ff00[RH-SyncIntegrity]|r Received assignments repair for ALL encounters from " .. sender)
    
    local activeRaid = OGRH_SV.v2.encounterMgmt.raids[1]
    if not activeRaid or not activeRaid.encounters then
        return
    end
    
    -- Apply assignments to ALL encounters
    local repairCount = 0
    for encIdx, encounterAssignments in pairs(data.allEncounters) do
        local encounter = activeRaid.encounters[encIdx]
        if encounter and encounter.roles then
            for roleIdx, roleAssignments in pairs(encounterAssignments) do
                if encounter.roles[roleIdx] then
                    encounter.roles[roleIdx].assignedPlayers = roleAssignments.assignedPlayers or {}
                    encounter.roles[roleIdx].raidMarks = roleAssignments.raidMarks or {}
                    encounter.roles[roleIdx].assignmentNumbers = roleAssignments.assignmentNumbers or {}
                    repairCount = repairCount + 1
                end
            end
        end
    end
    
    if OGRH.SyncIntegrity.State.debug then
        OGRH.Msg(string.format("|cff00ccff[RH-SyncIntegrity]|r Applied assignments repair for ALL encounters (%d roles updated)", repairCount))
    end
    
    if OGRH.SyncIntegrity.State.debug then
        OGRH.Msg("|cff00ff00[RH-SyncIntegrity]|r Assignments repaired for encounter " .. tostring(data.encounterIdx) .. " from " .. tostring(sender))
    else
        OGRH.Msg("|cff00ff00[RH]|r Assignments updated")
    end
    
    -- Refresh UI if needed
    if OGRH.MainUI and OGRH.MainUI.Refresh then
        OGRH.MainUI.Refresh()
    end
    
    -- Refresh encounter planning interface
    if OGRH_EncounterFrame and OGRH_EncounterFrame.RefreshRoleContainers then
        OGRH_EncounterFrame.RefreshRoleContainers()
    end
end

-- Client: Receive and apply RolesUI repair
function OGRH.SyncIntegrity.OnRolesRepair(sender, data)
    if not data then return end
    
    -- Only accept repairs from admin
    if not OGRH.CanModifyStructure(sender) then
        return
    end
    
    OGRH.Msg("|cff00ff00[RH-SyncIntegrity]|r Received RolesUI repair from " .. sender)
    
    -- Apply repair data to RolesUI
    OGRH_SV.v2.roles = OGRH.DeepCopy(data)
    
    if OGRH.SyncIntegrity.State.debug then
        OGRH.Msg("|cff00ff00[RH-SyncIntegrity]|r RolesUI repaired from " .. tostring(sender))
    else
        OGRH.Msg("|cff00ff00[RH]|r Roles updated")
    end
    
    -- Refresh RolesUI if open (use UpdatePlayerLists to rebuild display)
    if OGRH.rolesFrame and OGRH.rolesFrame.UpdatePlayerLists then
        OGRH.rolesFrame.UpdatePlayerLists(false)
    elseif OGRH_RolesFrame and OGRH_RolesFrame:IsVisible() and OGRH.RenderRoles then
        OGRH.RenderRoles()
    end
    
    -- Refresh encounter planning interface
    if OGRH_EncounterFrame and OGRH_EncounterFrame.RefreshRoleContainers then
        OGRH_EncounterFrame.RefreshRoleContainers()
    end
end
]]

-- Start integrity checks timer (30-second polling)
-- Called when local player becomes admin. Includes 5-second delay before first broadcast
-- to allow admin announcement to propagate to all raid members.
function OGRH.SyncIntegrity.StartIntegrityChecks()
    -- Guard against double-start
    if OGRH.SyncIntegrity.State.enabled then
        return
    end
    
    if not OGRH.ScheduleTimer then
        OGRH.Msg("|cffff0000[RH-SyncIntegrity]|r CRITICAL: ScheduleTimer not available!")
        return
    end
    
    OGRH.SyncIntegrity.State.enabled = true
    
    if OGRH.SyncIntegrity.State.debug then
        OGRH.Msg("|cff00ccff[RH-SyncIntegrity][DEBUG]|r Admin confirmed, delaying first broadcast by 5 seconds")
    end
    
    -- Delay first broadcasts by 5 seconds (let admin announcement propagate)
    OGRH.ScheduleTimer(function()
        -- Verify still admin and in raid
        if not OGRH.SyncIntegrity.State.enabled then return end
        if not OGRH.CanModifyStructure or not OGRH.CanModifyStructure(UnitName("player")) then return end
        if GetNumRaidMembers() == 0 then return end
        
        -- First broadcast (force immediate)
        OGRH.SyncIntegrity.BroadcastChecksums(true)
        
        -- Start repeating timer (30 seconds) for checksums
        OGRH.SyncIntegrity.State.timer = OGRH.ScheduleTimer(function()
            if OGRH.CanModifyStructure(UnitName("player")) then
                OGRH.SyncIntegrity.BroadcastChecksums()
            end
        end, 30, true)  -- 30 seconds, repeating
        
        -- Start repeating timer (15 seconds) for encounter selection
        OGRH.SyncIntegrity.State.encounterBroadcastTimer = OGRH.ScheduleTimer(function()
            OGRH.SyncIntegrity.BroadcastCurrentEncounter()
        end, 15, true)  -- 15 seconds, repeating
        
        if OGRH.SyncIntegrity.State.debug then
            OGRH.Msg("|cff00ccff[RH-SyncIntegrity][DEBUG]|r Active Raid checksum polling started (broadcasts every 30s)")
            OGRH.Msg("|cff00ccff[RH-SyncIntegrity][DEBUG]|r Encounter broadcast started (every 15s)")
        end
    end, 5.0)
end

-- Stop integrity checks (called when player loses admin or leaves raid)
function OGRH.SyncIntegrity.StopIntegrityChecks()
    if OGRH.SyncIntegrity.State.timer then
        OGRH.CancelTimer(OGRH.SyncIntegrity.State.timer)
        OGRH.SyncIntegrity.State.timer = nil
    end
    if OGRH.SyncIntegrity.State.encounterBroadcastTimer then
        OGRH.CancelTimer(OGRH.SyncIntegrity.State.encounterBroadcastTimer)
        OGRH.SyncIntegrity.State.encounterBroadcastTimer = nil
    end
    OGRH.SyncIntegrity.State.enabled = false
    if OGRH.SyncIntegrity.State.debug then
        OGRH.Msg("|cff00ccff[RH-SyncIntegrity][DEBUG]|r Integrity checks stopped")
    end
end

-- Global aliases (referenced by Permissions.lua SetRaidAdmin)
OGRH.StartIntegrityChecks = function()
    OGRH.SyncIntegrity.StartIntegrityChecks()
end
OGRH.StopIntegrityChecks = function()
    OGRH.SyncIntegrity.StopIntegrityChecks()
end

-- Broadcast current encounter selection to raid
function OGRH.SyncIntegrity.BroadcastCurrentEncounter()
    -- Only admin broadcasts
    if not OGRH.CanModifyStructure or not OGRH.CanModifyStructure(UnitName("player")) then
        return
    end
    
    -- Skip if not in raid
    if GetNumRaidMembers() == 0 then
        return
    end
    
    -- Skip if in combat
    if UnitAffectingCombat("player") then
        if OGRH.SyncIntegrity.State.debug then
            OGRH.Msg("|cffffaa00[RH-SyncIntegrity][DEBUG]|r Skipping encounter broadcast (in combat)")
        end
        return
    end
    
    -- Get current encounter selection
    local raidIdx = OGRH.SVM.Get("ui", "selectedRaidIndex")
    local encounterIdx = OGRH.SVM.Get("ui", "selectedEncounterIndex")
    
    if not raidIdx or not encounterIdx then
        return
    end
    
    -- Broadcast encounter selection
    OGRH.MessageRouter.Broadcast(
        OGRH.MessageTypes.STATE.CHANGE_ENCOUNTER,
        {
            raidIndex = raidIdx,
            encounterIndex = encounterIdx
        },
        {
            priority = "LOW"
        }
    )
    
    OGRH.SyncIntegrity.State.lastEncounterBroadcast = GetTime()
    
    if OGRH.SyncIntegrity.State.debug then
        OGRH.Msg(string.format("|cff00ccff[RH-SyncIntegrity][DEBUG]|r Broadcast encounter selection: raid=%d, encounter=%d", raidIdx, encounterIdx))
    end
end

-- Record admin modification (resets cooldown timer)
function OGRH.SyncIntegrity.RecordAdminModification()
    OGRH.SyncIntegrity.State.lastAdminModification = GetTime()
    if OGRH.SyncIntegrity.State.debug then
        OGRH.Msg("|cffffaa00[RH-SyncIntegrity]|r Admin modification recorded, broadcasts will resume in 10s")
    end
end

-- Client: Request checksums from admin (called when joining raid)
function OGRH.SyncIntegrity.RequestChecksums()
    if OGRH.CanModifyStructure and OGRH.CanModifyStructure(UnitName("player")) then
        return  -- Admin doesn't request from themselves
    end
    
    if OGRH.SyncIntegrity.State.debug then
        OGRH.Msg("|cff00ccff[RH-SyncIntegrity][DEBUG]|r Requesting checksums from admin")
    end
    
    OGRH.MessageRouter.Broadcast(
        OGRH.MessageTypes.ADMIN.QUERY,
        {requestType = "checksums"},
        {priority = "NORMAL"}
    )
end

-- Admin: Handle checksum request and respond
function OGRH.SyncIntegrity.OnAdminQuery(sender, data)
    if not OGRH.CanModifyStructure or not OGRH.CanModifyStructure(UnitName("player")) then
        return  -- Only admin responds
    end
    
    -- Handle case where data might be nil or string (defensive)
    if not data then
        if OGRH.SyncIntegrity.State.debug then
            OGRH.Msg("|cffff0000[RH-SyncIntegrity][DEBUG]|r OnAdminQuery: data is nil")
        end
        return
    end
    
    -- If data is a string, it might need deserialization (shouldn't happen with MessageRouter, but defensive)
    if type(data) == "string" then
        if OGRH.SyncIntegrity.State.debug then
            OGRH.Msg("|cffffaa00[RH-SyncIntegrity][DEBUG]|r OnAdminQuery: data is string, attempting deserialize")
        end
        data = OGRH.SyncChecksum.Deserialize(data) or {}
    end
    
    if type(data) ~= "table" then
        if OGRH.SyncIntegrity.State.debug then
            OGRH.Msg(string.format("|cffff0000[RH-SyncIntegrity][DEBUG]|r OnAdminQuery: data is %s, expected table", type(data)))
        end
        return
    end
    
    if data.requestType ~= "checksums" then
        return
    end
    
    if OGRH.SyncIntegrity.State.debug then
        OGRH.Msg(string.format("|cff00ccff[RH-SyncIntegrity][DEBUG]|r Responding to checksum request from %s", sender))
    end
    
    -- First, identify ourselves as admin (so client will accept our checksums)
    OGRH.MessageRouter.Broadcast(
        OGRH.MessageTypes.ADMIN.RESPONSE,
        {
            currentAdmin = UnitName("player"),
            timestamp = GetTime(),
            version = OGRH.VERSION
        },
        {priority = "HIGH"}
    )
    
    -- Auto-broadcast checksums when admin status changes
    OGRH.ScheduleTimer(function()
        OGRH.SyncIntegrity.BroadcastChecksums()
    end, 0.1)
end

-- NOTE: OnRaidRosterUpdate has been removed.
-- Raid roster changes are now handled by the consolidated handler in AdminSelection.lua.
-- Checksum requests are triggered by AdminDiscovery after admin resolution.

-- Initialize (register message handlers)
function OGRH.SyncIntegrity.Initialize()
    if not OGRH.MessageRouter or not OGRH.MessageTypes then
        OGRH.Msg("|cffff0000[RH-SyncIntegrity]|r CRITICAL: MessageRouter or MessageTypes not available!")
        return
    end
    
    -- Register handlers for checksum broadcasts
    OGRH.MessageRouter.RegisterHandler(
        OGRH.MessageTypes.SYNC.CHECKSUM_POLL,
        function(sender, data, channel)
            OGRH.SyncIntegrity.OnChecksumBroadcast(sender, data)
        end
    )
    
    -- Register handlers for repair requests
    OGRH.MessageRouter.RegisterHandler(
        OGRH.MessageTypes.SYNC.REPAIR_REQUEST,
        function(sender, data, channel)
            OGRH.SyncIntegrity.OnRepairRequest(sender, data)
        end
    )
    
    -- Register handlers for repair data
    OGRH.MessageRouter.RegisterHandler(
        OGRH.MessageTypes.SYNC.REPAIR_ACTIVE_RAID,
        function(sender, data, channel)
            OGRH.SyncIntegrity.OnActiveRaidRepair(sender, data)
        end
    )
    
    OGRH.MessageRouter.RegisterHandler(
        OGRH.MessageTypes.SYNC.REPAIR_ASSIGNMENTS,
        function(sender, data, channel)
            OGRH.SyncIntegrity.OnAssignmentsRepair(sender, data)
        end
    )
    
    OGRH.MessageRouter.RegisterHandler(
        OGRH.MessageTypes.SYNC.REPAIR_ROLES,
        function(sender, data, channel)
            OGRH.SyncIntegrity.OnRolesRepair(sender, data)
        end
    )
    
    -- NOTE: ADMIN.QUERY handler is now unified in MessageRouter.Initialize()
    -- It handles both discovery roll-call (all clients) and checksum requests (delegates here).
    -- No separate registration needed.
    
    OGRH.Msg("|cff00ccff[RH-SyncIntegrity]|r Active Raid checksum system loaded")
    
    -- Check periodically if we become admin and start broadcasting
    OGRH.ScheduleTimer(function()
        OGRH.SyncIntegrity.CheckAdminStatus()
    end, 5.0, true)  -- Check every 5 seconds
end

-- Check if player is raid admin and start/stop broadcasting accordingly
function OGRH.SyncIntegrity.CheckAdminStatus()
    local isAdmin = OGRH.CanModifyStructure and OGRH.CanModifyStructure(UnitName("player"))
    local inRaid = GetNumRaidMembers() > 0
    
    if isAdmin and inRaid and not OGRH.SyncIntegrity.State.enabled then
        -- Just became admin in a raid - start broadcasting
        if OGRH.SyncIntegrity.State.debug then
            OGRH.Msg("|cff00ccff[RH-SyncIntegrity][DEBUG]|r Starting Active Raid checksum broadcasting (you are raid admin)")
        end
        OGRH.SyncIntegrity.StartIntegrityChecks()
    elseif (not isAdmin or not inRaid) and OGRH.SyncIntegrity.State.enabled then
        -- Lost admin or left raid - stop broadcasting
        if OGRH.SyncIntegrity.State.debug then
            OGRH.Msg("|cff00ccff[RH-SyncIntegrity][DEBUG]|r Stopping checksum broadcasting (no longer admin or left raid)")
        end
        OGRH.SyncIntegrity.StopIntegrityChecks()
    end
end

--[[
    ============================================================================
    PHASE 5: REPAIR MODE CONTROL
    ============================================================================
]]

-- Enter repair mode (suppress broadcasts, buffer requests)
function OGRH.SyncIntegrity.EnterRepairMode()
    OGRH.SyncIntegrity.State.repairModeActive = true
    OGRH.SyncIntegrity.State.bufferedRequests = {}
    
    if OGRH.SyncIntegrity.State.debug then
        OGRH.Msg("|cff00ccff[RH-SyncIntegrity]|r Entered repair mode (broadcasts suppressed)")
    end
end

-- Exit repair mode (resume broadcasts, process buffered requests)
function OGRH.SyncIntegrity.ExitRepairMode()
    OGRH.SyncIntegrity.State.repairModeActive = false
    
    -- Process buffered requests
    local buffered = OGRH.SyncIntegrity.State.bufferedRequests
    if buffered and table.getn(buffered) > 0 then
        if OGRH.SyncIntegrity.State.debug then
            OGRH.Msg(string.format("|cff00ccff[RH-SyncIntegrity]|r Processing %d buffered repair requests", table.getn(buffered)))
        end
        
        -- TODO: Process buffered requests (Phase 6)
        -- For now, just clear them
    end
    
    OGRH.SyncIntegrity.State.bufferedRequests = {}
    
    -- Set cooldown to prevent immediate re-repairs
    OGRH.SyncIntegrity.State.repairCooldownUntil = GetTime() + 30.0  -- 30 second cooldown
    
    if OGRH.SyncIntegrity.State.debug then
        OGRH.Msg("|cff00ccff[RH-SyncIntegrity]|r Exited repair mode (broadcasts resumed, 30s cooldown active)")
    end
    
    -- Auto-broadcast checksums after repair to validate everyone (including mid-sync joins)
    if OGRH.SyncIntegrity.State.enabled then
        OGRH.ScheduleTimer(function()
            OGRH.SyncIntegrity.BroadcastChecksums()
        end, 20.0)  -- 20 second delay to allow CTL to drain and clients to save
    end
end

-- Buffer a repair request during active repair
function OGRH.SyncIntegrity.BufferRepairRequest(playerName, component, checksum)
    if not OGRH.SyncIntegrity.State.repairModeActive then
        return false  -- Not in repair mode, don't buffer
    end
    
    table.insert(OGRH.SyncIntegrity.State.bufferedRequests, {
        playerName = playerName,
        component = component,
        checksum = checksum,
        timestamp = GetTime()
    })
    
    if OGRH.SyncIntegrity.State.debug then
        OGRH.Msg(string.format("|cff888888[RH-SyncIntegrity]|r Buffered repair request from %s (%s)", playerName, component))
    end
    
    return true  -- Request buffered
end


-- Auto-initialize on load
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:SetScript("OnEvent", function()
    if event == "ADDON_LOADED" and arg1 == "OG-RaidHelper" then
        OGRH.ScheduleTimer(function()
            OGRH.SyncIntegrity.Initialize()
        end, 1.0)
    end
end)
