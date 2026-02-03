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
    
    -- Player join tracking
    lastRaidSize = 0,  -- Track raid size to detect joins
    
    -- Encounter broadcast
    lastEncounterBroadcast = 0,  -- timestamp of last encounter broadcast
    encounterBroadcastInterval = 15,  -- seconds
    encounterBroadcastTimer = nil,
    
    -- Debug mode (toggle with /ogrh debug sync)
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
    if OGRH.SyncIntegrity.State.debug then
        OGRH.Msg("|cff00ccff[RH-SyncIntegrity][DEBUG]|r BroadcastChecksums() called")
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
    
    -- Skip broadcast if admin made changes recently (data still in flux)
    local timeSinceLastMod = GetTime() - OGRH.SyncIntegrity.State.lastAdminModification
    if timeSinceLastMod < OGRH.SyncIntegrity.State.modificationCooldown then
        local remaining = OGRH.SyncIntegrity.State.modificationCooldown - timeSinceLastMod
        if OGRH.SyncIntegrity.State.debug then
            OGRH.Msg(string.format("|cff888888[RH-SyncIntegrity]|r Skipping broadcast (data modified %.0fs ago, cooldown %.0fs)", 
                timeSinceLastMod, remaining))
        end
        return
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
        -- Active Raid structure checksum (all encounters, roles, but no assignments)
        activeRaidStructure = OGRH.SyncChecksum.ComputeRaidChecksum(activeRaid.name),
        
        -- Active encounter assignments checksum (current encounter only)
        activeEncounterIdx = currentEncounterIdx,
        activeAssignments = currentEncounterIdx and OGRH.SyncChecksum.ComputeActiveAssignmentsChecksum(currentEncounterIdx) or nil,
        
        -- Global roles (TANKS, HEALERS, MELEE, RANGED)
        rolesUI = OGRH.SyncChecksum.CalculateRolesUIChecksum(),
        
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
    if not (checksums.activeRaidStructure and checksums.rolesUI) then
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
        local localStructure = OGRH.SyncChecksum.ComputeRaidChecksum(activeRaid.name)
        if OGRH.SyncIntegrity.State.debug then
            OGRH.Msg(string.format("|cffaaaaaa[RH-SyncIntegrity][DEBUG]|r Structure checksums: local=%s, admin=%s", localStructure, checksums.activeRaidStructure))
        end
        if localStructure ~= checksums.activeRaidStructure then
            table.insert(mismatches, {
                type = "ACTIVE_RAID_STRUCTURE",
                component = "structure"
            })
            if OGRH.SyncIntegrity.State.debug then
                OGRH.Msg("|cffff8800[RH-SyncIntegrity][DEBUG]|r Mismatch detected - Requesting repair: Active Raid structure")
            end
        end
    end
    
    -- Validate Active Encounter assignments (if admin has a selected encounter)
    if checksums.activeEncounterIdx and checksums.activeAssignments then
        local localAssignments = OGRH.SyncChecksum.ComputeActiveAssignmentsChecksum(checksums.activeEncounterIdx)
        if OGRH.SyncIntegrity.State.debug then
            OGRH.Msg(string.format("|cffaaaaaa[RH-SyncIntegrity][DEBUG]|r Assignment checksums: local=%s, admin=%s", localAssignments, checksums.activeAssignments))
        end
        if localAssignments ~= checksums.activeAssignments then
            table.insert(mismatches, {
                type = "ACTIVE_ASSIGNMENTS",
                component = "assignments",
                encounterIdx = checksums.activeEncounterIdx
            })
            if OGRH.SyncIntegrity.State.debug then
                OGRH.Msg(string.format("|cffff8800[RH-SyncIntegrity][DEBUG]|r Mismatch detected - Requesting repair: Active Encounter assignments (encounter #%d)", checksums.activeEncounterIdx))
            end
        end
    end
    
    -- Validate RolesUI (global roles)
    local localRolesUI = OGRH.SyncChecksum.CalculateRolesUIChecksum()
    if OGRH.SyncIntegrity.State.debug then
        OGRH.Msg(string.format("|cffaaaaaa[RH-SyncIntegrity][DEBUG]|r RolesUI checksums: local=%s, admin=%s", localRolesUI, checksums.rolesUI))
    end
    if localRolesUI ~= checksums.rolesUI then
        table.insert(mismatches, {
            type = "ROLES_UI",
            component = "roles"
        })
        if OGRH.SyncIntegrity.State.debug then
            OGRH.Msg("|cffff8800[RH-SyncIntegrity][DEBUG]|r Mismatch detected - Requesting repair: RolesUI (global role assignments)")
        end
    end
    
    -- If mismatches found, queue repair requests (1-second buffer)
    if table.getn(mismatches) > 0 then
        if OGRH.SyncIntegrity.State.debug then
            OGRH.Msg(string.format("|cffff8800[RH-SyncIntegrity][DEBUG]|r %d checksum mismatch(es) detected, requesting repairs from admin", table.getn(mismatches)))
        end
        for i = 1, table.getn(mismatches) do
            OGRH.SyncIntegrity.QueueRepairRequest(sender, mismatches[i])
        end
    else
        if OGRH.SyncIntegrity.State.debug then
            OGRH.Msg("|cff00ff00[RH-SyncIntegrity][DEBUG]|r All checksums validated successfully")
        end
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

-- Admin: Flush repair buffer and broadcast repairs (once per component)
function OGRH.SyncIntegrity.FlushRepairBuffer()
    local buffer = OGRH.SyncIntegrity.RepairBuffer
    
    local count = 0
    for _ in pairs(buffer.requests) do count = count + 1 end
    if OGRH.SyncIntegrity.State.debug then
        OGRH.Msg("|cffff00ff[RH-SyncIntegrity ADMIN]|r Flushing " .. tostring(count) .. " repair request(s), broadcasting repairs")
    end
    
    -- Broadcast repair for each unique component (once per component)
    for key, request in pairs(buffer.requests) do
        if OGRH.SyncIntegrity.State.debug then
            OGRH.Msg("|cffaaffaa[RH-SyncIntegrity DEBUG]|r Processing repair for component: " .. tostring(request.component))
        end
        
        if request.component == "structure" then
            OGRH.SyncIntegrity.BroadcastActiveRaidRepair()
        elseif request.component == "assignments" and request.encounterIdx then
            OGRH.SyncIntegrity.BroadcastAssignmentsRepair(request.encounterIdx)
        elseif request.component == "roles" then
            OGRH.SyncIntegrity.BroadcastRolesRepair()
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
    
    -- Deep copy Active Raid with ALL data (structure + assignments)
    -- Structure repair includes everything: roles, columns, metadata, assignedPlayers, raidMarks, assignmentNumbers
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
    
    -- Extract ALL encounter assignments
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
                
                -- Track size for debug
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

-- Start integrity checks timer (30-second polling)
function OGRH.SyncIntegrity.StartIntegrityChecks()
    if not OGRH.ScheduleTimer then
        OGRH.Msg("|cffff0000[RH-SyncIntegrity]|r CRITICAL: ScheduleTimer not available!")
        return
    end
    
    OGRH.SyncIntegrity.State.enabled = true
    
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
        OGRH.Msg("|cffffaa00[RH-SyncIntegrity]|r Admin modification recorded, broadcasts will resume in 2s")
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
    
    -- Then send checksums immediately (after short delay to ensure admin response is processed first)
    OGRH.ScheduleTimer(function()
        OGRH.SyncIntegrity.BroadcastChecksums()
    end, 0.1)
end

-- Detect player joins and request checksums
local function OnRaidRosterUpdate()
    local currentRaidSize = GetNumRaidMembers()
    local previousRaidSize = OGRH.SyncIntegrity.State.lastRaidSize
    
    -- Player joined (size increased)
    if currentRaidSize > previousRaidSize and currentRaidSize > 0 then
        if OGRH.SyncIntegrity.State.debug then
            OGRH.Msg(string.format("|cff00ccff[RH-SyncIntegrity][DEBUG]|r Raid size changed: %d -> %d", previousRaidSize, currentRaidSize))
        end
        
        -- If we just joined (went from 0 to >0), request checksums
        if previousRaidSize == 0 then
            OGRH.ScheduleTimer(function()
                OGRH.SyncIntegrity.RequestChecksums()
            end, 1.0)  -- Wait 1 second for raid to stabilize
        end
    end
    
    OGRH.SyncIntegrity.State.lastRaidSize = currentRaidSize
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
    
    -- Register handler for admin queries
    OGRH.MessageRouter.RegisterHandler(
        OGRH.MessageTypes.ADMIN.QUERY,
        function(sender, data, channel)
            OGRH.SyncIntegrity.OnAdminQuery(sender, data)
        end
    )
    
    -- Register RAID_ROSTER_UPDATE event
    local eventFrame = CreateFrame("Frame")
    eventFrame:RegisterEvent("RAID_ROSTER_UPDATE")
    eventFrame:SetScript("OnEvent", function()
        if event == "RAID_ROSTER_UPDATE" then
            OnRaidRosterUpdate()
        end
    end)

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
        if OGRH.SyncIntegrity.State.timer then
            OGRH.CancelTimer(OGRH.SyncIntegrity.State.timer)
            OGRH.SyncIntegrity.State.timer = nil
        end
        if OGRH.SyncIntegrity.State.encounterBroadcastTimer then
            OGRH.CancelTimer(OGRH.SyncIntegrity.State.encounterBroadcastTimer)
            OGRH.SyncIntegrity.State.encounterBroadcastTimer = nil
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
