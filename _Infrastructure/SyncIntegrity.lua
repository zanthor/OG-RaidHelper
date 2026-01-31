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
    modificationCooldown = 2,  -- seconds to wait after last change before broadcasting
    
    -- Debug mode (toggle with /ogrh sync debug)
    debug = false,  -- Hide verbose sync messages by default
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
function OGRH.SyncIntegrity.BroadcastChecksums()
    OGRH.Msg("|cffff00ff[RH-SyncIntegrity]|r BroadcastChecksums() called")
    
    if GetNumRaidMembers() == 0 then
        OGRH.Msg("|cffff9900[RH-SyncIntegrity]|r Not broadcasting - not in raid")
        return
    end
    
    -- Check if network queue is busy (don't add more traffic if repairs are still sending)
    if OGAddonMsg and OGAddonMsg.stats and OGAddonMsg.stats.queueDepth then
        if OGAddonMsg.stats.queueDepth > 0 then
            OGRH.Msg(string.format("|cff888888[RH-SyncIntegrity]|r Skipping broadcast (network queue busy: %d messages pending)", OGAddonMsg.stats.queueDepth))
            return
        end
    end
    
    -- NEVER broadcast if admin is in combat
    if UnitAffectingCombat("player") then
        OGRH.Msg("|cff888888[RH-SyncIntegrity]|r Skipping broadcast (in combat)")
        return
    end
    
    -- Skip broadcast if admin made changes recently (data still in flux)
    local timeSinceLastMod = GetTime() - OGRH.SyncIntegrity.State.lastAdminModification
    if timeSinceLastMod < OGRH.SyncIntegrity.State.modificationCooldown then
        local remaining = OGRH.SyncIntegrity.State.modificationCooldown - timeSinceLastMod
        OGRH.Msg(string.format("|cff888888[RH-SyncIntegrity]|r Skipping broadcast (data modified %.0fs ago, cooldown %.0fs)", 
            timeSinceLastMod, remaining))
        return
    end
    
    -- Broadcast Active Raid checksums only (index 1)
    local activeRaid = OGRH.GetActiveRaid()
    if not activeRaid then
        OGRH.Msg("|cffff9900[RH-SyncIntegrity]|r No Active Raid found, skipping broadcast")
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
        -- Active Raid structure checksum (all encounters, roles, but no assignments)
        activeRaidStructure = OGRH.ComputeRaidChecksum(activeRaid.name),
        
        -- Active encounter assignments checksum (current encounter only)
        activeEncounterIdx = currentEncounterIdx,
        activeAssignments = currentEncounterIdx and OGRH.ComputeActiveAssignmentsChecksum(currentEncounterIdx) or nil,
        
        -- Global roles (TANKS, HEALERS, MELEE, RANGED)
        rolesUI = OGRH.CalculateRolesUIChecksum(),
        
        -- Global component checksums
        global = OGRH.GetGlobalComponentChecksums(),
        
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
                    if OGRH.SyncIntegrity.State.debug then
                        OGRH.Msg("|cff00ccff[RH-SyncIntegrity]|r Broadcast Active Raid checksums")
                    end
                end
            }
        )
    end
end

-- Client: Handle checksum broadcast from admin
function OGRH.SyncIntegrity.OnChecksumBroadcast(sender, checksums)
    -- Verify sender is the addon's raid admin
    local currentAdmin = OGRH.GetRaidAdmin and OGRH.GetRaidAdmin()
    
    OGRH.Msg("|cffaaaaaa[RH-SyncIntegrity DEBUG]|r OnChecksumBroadcast called: sender=" .. (sender or "nil") .. ", currentAdmin=" .. (currentAdmin or "nil"))
    
    if not currentAdmin or sender ~= currentAdmin then
        OGRH.Msg("|cffaaaaaa[RH-SyncIntegrity DEBUG]|r Ignoring: sender is not admin")
        return  -- Ignore checksums from non-admins
    end
    
    -- Don't validate against ourselves (admin receives their own broadcast)
    if sender == UnitName("player") then
        OGRH.Msg("|cffaaaaaa[RH-SyncIntegrity DEBUG]|r Ignoring: sender is self")
        return
    end
    
    OGRH.Msg("|cff00ff00[RH-SyncIntegrity]|r Received checksum broadcast from admin " .. sender)
    
    -- Validate Active Raid checksums
    if not (checksums.activeRaidStructure and checksums.rolesUI and checksums.global) then
        OGRH.Msg("|cffff0000[RH-SyncIntegrity]|r ERROR: Invalid checksum format received")
        return
    end
    
    if OGRH.SyncIntegrity.State.debug then
        OGRH.Msg("|cff00ccff[RH-SyncIntegrity]|r Received Active Raid checksum broadcast, validating...")
    end
    
    local mismatches = {}
    
    -- Validate Active Raid structure
    local activeRaid = OGRH.GetActiveRaid()
    if activeRaid then
        local localStructure = OGRH.ComputeRaidChecksum(activeRaid.name)
        OGRH.Msg(string.format("|cffaaaaaa[RH-SyncIntegrity DEBUG]|r Structure checksums: local=%s, admin=%s", localStructure, checksums.activeRaidStructure))
        if localStructure ~= checksums.activeRaidStructure then
            table.insert(mismatches, {
                type = "ACTIVE_RAID_STRUCTURE",
                component = "structure"
            })
            OGRH.Msg("|cffff8800[RH-SyncIntegrity]|r Active Raid structure mismatch")
        end
    end
    
    -- Validate Active Encounter assignments (if admin has a selected encounter)
    if checksums.activeEncounterIdx and checksums.activeAssignments then
        local localAssignments = OGRH.ComputeActiveAssignmentsChecksum(checksums.activeEncounterIdx)
        OGRH.Msg(string.format("|cffaaaaaa[RH-SyncIntegrity DEBUG]|r Assignment checksums: local=%s, admin=%s", localAssignments, checksums.activeAssignments))
        if localAssignments ~= checksums.activeAssignments then
            table.insert(mismatches, {
                type = "ACTIVE_ASSIGNMENTS",
                component = "assignments",
                encounterIdx = checksums.activeEncounterIdx
            })
            OGRH.Msg("|cffff8800[RH-SyncIntegrity]|r Active Encounter assignments mismatch")
        end
    end
    
    -- Validate RolesUI (global roles)
    local localRolesUI = OGRH.CalculateRolesUIChecksum()
    if localRolesUI ~= checksums.rolesUI then
        table.insert(mismatches, {
            type = "ROLES_UI",
            component = "roles"
        })
        if OGRH.SyncIntegrity.State.debug then
            OGRH.Msg("|cffff8800[RH-SyncIntegrity]|r RolesUI mismatch")
        end
    end
    
    -- Validate global components
    local localGlobal = OGRH.GetGlobalComponentChecksums()
    for componentName, checksum in pairs(checksums.global) do
        if localGlobal[componentName] ~= checksum then
            table.insert(mismatches, {
                type = "GLOBAL_COMPONENT",
                component = componentName
            })
            if OGRH.SyncIntegrity.State.debug then
                OGRH.Msg(string.format("|cffff8800[RH-SyncIntegrity]|r Global component mismatch: %s", componentName))
            end
        end
    end
    
    -- If mismatches found, queue repair requests (1-second buffer)
    if table.getn(mismatches) > 0 then
        OGRH.Msg(string.format("|cffff8800[RH-SyncIntegrity]|r %d checksum mismatch(es) detected, requesting repairs", table.getn(mismatches)))
        for i = 1, table.getn(mismatches) do
            OGRH.SyncIntegrity.QueueRepairRequest(sender, mismatches[i])
        end
    else
        OGRH.Msg("|cff00ff00[RH-SyncIntegrity]|r All checksums validated successfully")
    end
end

-- Client: Broadcast repair request (admin will buffer for 1 second)
function OGRH.SyncIntegrity.QueueRepairRequest(adminName, mismatch)
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
        
        if OGRH.SyncIntegrity.State.debug then
            OGRH.Msg(string.format("|cffff9900[RH-SyncIntegrity]|r Requested repair: %s", mismatch.type))
        end
    end
end

-- Admin: Repair request buffer (prevents broadcast storms)
OGRH.SyncIntegrity.RepairBuffer = {
    requests = {},      -- {component, encounterIdx, requesters = {}}
    timer = nil,
    timeout = 1.0
}

-- Admin: Handle repair request from clients (buffer for 1 second)
function OGRH.SyncIntegrity.OnRepairRequest(sender, data)
    if not data or not data.component then return end
    
    -- Only admin can send repairs
    if not OGRH.CanModifyStructure(UnitName("player")) then
        return
    end
    
    OGRH.Msg("|cffff00ff[RH-SyncIntegrity ADMIN]|r Repair request from " .. tostring(sender) .. " for " .. tostring(data.component))
    
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
    
    -- Start/reset timer
    if buffer.timer then
        OGRH.CancelTimer(buffer.timer)
    end
    
    buffer.timer = OGRH.ScheduleTimer(function()
        OGRH.SyncIntegrity.FlushRepairBuffer()
    end, buffer.timeout)
end

-- Admin: Flush repair buffer and broadcast repairs (once per component)
function OGRH.SyncIntegrity.FlushRepairBuffer()
    local buffer = OGRH.SyncIntegrity.RepairBuffer
    
    local count = 0
    for _ in pairs(buffer.requests) do count = count + 1 end
    OGRH.Msg("|cffff00ff[RH-SyncIntegrity ADMIN]|r Flushing " .. tostring(count) .. " repair request(s), broadcasting repairs")
    
    -- Broadcast repair for each unique component (once per component)
    for key, request in pairs(buffer.requests) do
        OGRH.Msg("|cffaaffaa[RH-SyncIntegrity DEBUG]|r Processing repair for component: " .. tostring(request.component))
        
        if request.component == "structure" then
            OGRH.SyncIntegrity.BroadcastActiveRaidRepair()
        elseif request.component == "assignments" and request.encounterIdx then
            OGRH.SyncIntegrity.BroadcastAssignmentsRepair(request.encounterIdx)
        elseif request.component == "roles" then
            OGRH.SyncIntegrity.BroadcastRolesRepair()
        elseif request.component == "global" then
            OGRH.SyncIntegrity.BroadcastGlobalRepair()
        else
            OGRH.Msg("|cffff0000[RH-SyncIntegrity DEBUG]|r Unknown component: " .. tostring(request.component))
        end
    end
    
    -- Clear buffer
    buffer.requests = {}
    buffer.timer = nil
end

-- Admin: Broadcast Active Raid structure for repair
function OGRH.SyncIntegrity.BroadcastActiveRaidRepair()
    OGRH.Msg("|cffaaffaa[RH-SyncIntegrity DEBUG]|r BroadcastActiveRaidRepair() called")
    
    local activeRaid = OGRH_SV.v2.encounterMgmt.raids[1]
    if not activeRaid then 
        OGRH.Msg("|cffff0000[RH-SyncIntegrity DEBUG]|r No active raid found")
        return 
    end
    
    OGRH.Msg("|cffaaffaa[RH-SyncIntegrity DEBUG]|r Active raid exists, preparing copy")
    
    -- Deep copy and strip assignments for structure-only sync
    local raidCopy = OGRH.DeepCopy(activeRaid)
    for i = 1, table.getn(raidCopy.encounters or {}) do
        local enc = raidCopy.encounters[i]
        if enc.roles then
            for j = 1, table.getn(enc.roles) do
                enc.roles[j].assignedPlayers = {} -- Strip assignments
            end
        end
    end
    
    OGRH.Msg("|cffaaffaa[RH-SyncIntegrity DEBUG]|r Calling MessageRouter.Broadcast...")
    
    local msgId = OGRH.MessageRouter.Broadcast(
        OGRH.MessageTypes.SYNC.REPAIR_ACTIVE_RAID,
        raidCopy,
        {
            priority = "LOW",
            compress = true
        }
    )
    
    OGRH.Msg("|cffff00ff[RH-SyncIntegrity ADMIN]|r Broadcast Active Raid structure repair (msgId: " .. tostring(msgId) .. ")")
end

-- Admin: Broadcast Active Raid assignments for specific encounter
function OGRH.SyncIntegrity.BroadcastAssignmentsRepair(encounterIdx)
    local activeRaid = OGRH_SV.v2.encounterMgmt.raids[1]
    if not activeRaid or not activeRaid.encounters or not activeRaid.encounters[encounterIdx] then
        return
    end
    
    local encounter = activeRaid.encounters[encounterIdx]
    local assignments = {}
    
    -- Extract assignments from encounter
    if encounter.roles then
        for i = 1, table.getn(encounter.roles) do
            assignments[i] = encounter.roles[i].assignedPlayers or {}
        end
    end
    
    OGRH.MessageRouter.Broadcast(
        OGRH.MessageTypes.SYNC.REPAIR_ASSIGNMENTS,
        {
            encounterIdx = encounterIdx,
            assignments = assignments
        },
        {
            priority = "LOW",
            compress = true
        }
    )
    
    if OGRH.SyncIntegrity.State.debug then
        OGRH.Msg("|cff00ccff[RH-SyncIntegrity]|r Broadcast assignments repair for encounter " .. tostring(encounterIdx))
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

-- Admin: Broadcast global components for repair
function OGRH.SyncIntegrity.BroadcastGlobalRepair()
    local globalData = {
        consumes = OGRH_SV.v2.consumes,
        tradeItems = OGRH_SV.v2.tradeItems
    }
    
    OGRH.MessageRouter.Broadcast(
        OGRH.MessageTypes.SYNC.REPAIR_GLOBAL,
        globalData,
        {
            priority = "LOW",
            compress = true
        }
    )
    
    if OGRH.SyncIntegrity.State.debug then
        OGRH.Msg("|cff00ccff[RH-SyncIntegrity]|r Broadcast global components repair")
    end
end

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

-- Client: Receive and apply assignments repair
function OGRH.SyncIntegrity.OnAssignmentsRepair(sender, data)
    if not data or not data.encounterIdx or not data.assignments then return end
    
    -- Only accept repairs from admin
    if not OGRH.CanModifyStructure(sender) then
        return
    end    
    OGRH.Msg("|cff00ff00[RH-SyncIntegrity]|r Received assignments repair for encounter " .. data.encounterIdx .. " from " .. sender)    
    local activeRaid = OGRH_SV.v2.encounterMgmt.raids[1]
    if not activeRaid or not activeRaid.encounters or not activeRaid.encounters[data.encounterIdx] then
        return
    end
    
    local encounter = activeRaid.encounters[data.encounterIdx]
    
    -- Apply assignments to roles
    if encounter.roles then
        for i = 1, table.getn(encounter.roles) do
            encounter.roles[i].assignedPlayers = data.assignments[i] or {}
        end
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

-- Client: Receive and apply global components repair
function OGRH.SyncIntegrity.OnGlobalRepair(sender, data)
    if not data then return end
    
    -- Only accept repairs from admin
    if not OGRH.CanModifyStructure(sender) then
        return
    end
    
    OGRH.Msg("|cff00ff00[RH-SyncIntegrity]|r Received global components repair from " .. sender)
    
    -- Apply repair data to global components
    if data.consumes then
        OGRH_SV.v2.consumes = OGRH.DeepCopy(data.consumes)
    end
    if data.tradeItems then
        OGRH_SV.v2.tradeItems = OGRH.DeepCopy(data.tradeItems)
    end
    
    if OGRH.SyncIntegrity.State.debug then
        OGRH.Msg("|cff00ff00[RH-SyncIntegrity]|r Global components repaired from " .. tostring(sender))
    else
        OGRH.Msg("|cff00ff00[RH]|r Configuration updated")
    end
end

-- Start integrity checks timer (30-second polling)
function OGRH.SyncIntegrity.StartIntegrityChecks()
    if not OGRH.ScheduleTimer then
        OGRH.Msg("|cffff0000[RH-SyncIntegrity]|r CRITICAL: ScheduleTimer not available!")
        return
    end
    
    OGRH.SyncIntegrity.State.enabled = true
    
    -- Start repeating timer (30 seconds)
    OGRH.SyncIntegrity.State.timer = OGRH.ScheduleTimer(function()
        if OGRH.CanModifyStructure(UnitName("player")) then
            OGRH.SyncIntegrity.BroadcastChecksums()
        end
    end, 30, true)  -- 30 seconds, repeating
    
    OGRH.Msg("|cff00ccff[RH-SyncIntegrity]|r Active Raid checksum polling started (broadcasts every 30s)")
end

-- Record admin modification (resets cooldown timer)
function OGRH.SyncIntegrity.RecordAdminModification()
    OGRH.SyncIntegrity.State.lastAdminModification = GetTime()
    OGRH.Msg("|cffffaa00[RH-SyncIntegrity]|r Admin modification recorded, broadcasts will resume in 2s")
end

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
    
    OGRH.MessageRouter.RegisterHandler(
        OGRH.MessageTypes.SYNC.REPAIR_GLOBAL,
        function(sender, data, channel)
            OGRH.SyncIntegrity.OnGlobalRepair(sender, data)
        end
    )
    
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
        OGRH.Msg("|cff00ff00[RH-SyncIntegrity]|r Starting Active Raid checksum broadcasting (you are raid admin)")
        OGRH.SyncIntegrity.StartIntegrityChecks()
    elseif (not isAdmin or not inRaid) and OGRH.SyncIntegrity.State.enabled then
        -- Lost admin or left raid - stop broadcasting
        OGRH.Msg("|cffff9900[RH-SyncIntegrity]|r Stopping checksum broadcasting (no longer admin or left raid)")
        if OGRH.SyncIntegrity.State.timer then
            OGRH.CancelTimer(OGRH.SyncIntegrity.State.timer)
            OGRH.SyncIntegrity.State.timer = nil
        end
        OGRH.SyncIntegrity.State.enabled = false
    end
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
