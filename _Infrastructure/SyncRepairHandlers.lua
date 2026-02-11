--[[
    OG-RaidHelper: SyncRepairHandlers.lua
    
    Phase 6: Network message handlers for surgical repair system
    
    Handles:
    - SYNC_REPAIR_START: Admin initiates repair, clients show waiting panel
    - SYNC_REPAIR_PACKET_*: Send/receive layer-specific repair packets
    - SYNC_REPAIR_VALIDATION: Clients send validation checksums to admin
    - SYNC_REPAIR_COMPLETE: Admin confirms completion, dismiss panels
    - SYNC_REPAIR_CANCEL: Admin cancels repair session
]]

if not OGRH then OGRH = {} end
if not OGRH.SyncRepairHandlers then OGRH.SyncRepairHandlers = {} end

-- Retry configuration
local MAX_RETRY_ATTEMPTS = 2   -- Max re-sends per repair session
local RETRY_DELAY = 2.0        -- Seconds before starting retry send

--[[
    ============================================================================
    ADMIN-SIDE HANDLERS (Send packets, collect validations)
    ============================================================================
]]

-- Admin: Start repair session and broadcast to clients
function OGRH.SyncRepairHandlers.InitiateRepair(raidName, failedLayers, selectedEncounterIndex, clientList)
    -- Log what we received
    OGRH.Msg("|cff00ccff[RH-SyncRepair]|r InitiateRepair called:")
    OGRH.Msg(string.format("|cff00ccff[RH-SyncRepair]|r  structure=%s", tostring(failedLayers.structure)))
    if failedLayers.encounters then
        OGRH.Msg(string.format("|cff00ccff[RH-SyncRepair]|r  encounters=%d items", table.getn(failedLayers.encounters)))
    end
    
    -- Validation
    if not OGRH.SyncSession then
        OGRH.Msg("|cffff0000[RH-SyncRepair]|r SyncSession module not loaded")
        return false
    end
    
    if not OGRH.SyncRepair then
        OGRH.Msg("|cffff0000[RH-SyncRepair]|r SyncRepair module not loaded")
        return false
    end
    
    -- Start session
    local token = OGRH.SyncSession.StartSession(raidName, failedLayers)
    if not token then
        OGRH.Msg("|cffff0000[RH-SyncRepair]|r Failed to start session (session already active?)")
        return false
    end
    
    -- Track which clients are participating in this repair
    local clients = clientList or {}
    if OGRH.SyncSession.SetRepairParticipants then
        OGRH.SyncSession.SetRepairParticipants(clients)
    end
    
    -- Build priority order
    local priority = OGRH.SyncRepair.DetermineRepairPriority(raidName, selectedEncounterIndex, failedLayers)
    
    -- Use provided client list (from repair requesters)
    local clients = clientList or {}
    
    -- Show admin UI
    if OGRH.SyncRepairUI and OGRH.SyncRepairUI.ShowAdminPanel then
        OGRH.SyncRepairUI.ShowAdminPanel(token, clients)
    end
    
    -- Broadcast REPAIR_START to all clients
    local totalLayers = 0
    if failedLayers.structure then
        totalLayers = totalLayers + 1
    end
    if failedLayers.encounters then
        totalLayers = totalLayers + table.getn(failedLayers.encounters)
    end
    if failedLayers.roles then
        for encIdx, rolesList in pairs(failedLayers.roles) do
            totalLayers = totalLayers + table.getn(rolesList)
        end
    end
    if failedLayers.assignments then
        for encIdx, assignmentsList in pairs(failedLayers.assignments) do
            totalLayers = totalLayers + table.getn(assignmentsList)
        end
    end
    
    local startData = {
        token = token,
        raidName = raidName,
        priority = priority,
        totalLayers = totalLayers
    }
    
    OGRH.MessageRouter.Send(OGRH.MessageTypes.SYNC.REPAIR_START, startData, {
        priority = "HIGH",
        channel = "RAID"
    })
    
    OGRH.Msg("|cff00ff00[RH-SyncRepair]|r Repair session started: " .. token)
    
    -- Start sending packets (with adaptive delay)
    OGRH.ScheduleTimer(function()
        OGRH.SyncRepairHandlers.SendRepairPackets(token, raidName, failedLayers, priority)
    end, 0.5)  -- 500ms delay before first packet
    
    return true
end

-- Admin: Send repair packets with adaptive pacing
function OGRH.SyncRepairHandlers.SendRepairPackets(token, raidName, failedLayers, priority)
    -- Verify session still active
    local session = OGRH.SyncSession.GetActiveSession()
    if not session or session.token ~= token then
        OGRH.Msg("|cffff9900[RH-SyncRepair]|r Session no longer active, aborting packet send")
        return
    end
    
    local packetsSent = 0
    local totalPackets = 0
    
    -- Build all packets
    local packets = {}
    
    -- Get raid displayName for logging
    local sv = OGRH.SVM and OGRH.SVM.GetActiveSchema() or OGRH_SV.v2
    local raid = sv and sv.encounterMgmt and sv.encounterMgmt.raids and sv.encounterMgmt.raids[1]
    local raidDisplayName = raid and (raid.displayName or raid.name) or raidName
    
    OGRH.Msg("|cff00ccff[RH-SyncRepair]|r Building packets for: " .. raidDisplayName)
    
    -- Layer 1: Structure
    if failedLayers.structure then
        local pkt = OGRH.SyncRepair.BuildStructurePacket()
        if pkt then
            pkt.token = token
            table.insert(packets, pkt)
            totalPackets = totalPackets + 1
            OGRH.Msg("|cff00ccff[RH-SyncRepair]|r Built STRUCTURE packet for " .. raidDisplayName)
        else
            OGRH.Msg("|cffff9900[RH-SyncRepair]|r Failed to build STRUCTURE packet")
        end
    end
    
    -- Layer 1b: RolesUI (global roles)
    if failedLayers.rolesui then
        local pkt = OGRH.SyncRepair.BuildRolesUIPacket()
        if pkt then
            pkt.token = token
            table.insert(packets, pkt)
            totalPackets = totalPackets + 1
            OGRH.Msg("|cff00ccff[RH-SyncRepair]|r Built ROLESUI packet")
        else
            OGRH.Msg("|cffff9900[RH-SyncRepair]|r Failed to build ROLESUI packet")
        end
    end
    
    -- Layer 2: Encounters (ordered by priority)
    if failedLayers.encounters then
        for i = 1, table.getn(priority) do
            local encIdx = priority[i]
            local pkts = OGRH.SyncRepair.BuildEncountersPackets({encIdx})
            for j = 1, table.getn(pkts) do
                pkts[j].token = token
                table.insert(packets, pkts[j])
                totalPackets = totalPackets + 1
                
                -- Log what we built
                local encName = (pkts[j].data and pkts[j].data.displayName) or (pkts[j].data and pkts[j].data.name) or "Unknown"
                OGRH.Msg(string.format("|cff00ccff[RH-SyncRepair]|r Built ENCOUNTER packet %d: %s", encIdx, encName))
            end
        end
    end
    
    -- Layer 3: Roles (ordered by priority)
    if failedLayers.roles then
        for encIdx, roleIndices in pairs(failedLayers.roles) do
            local pkts = OGRH.SyncRepair.BuildRolesPackets(encIdx, roleIndices)
            for j = 1, table.getn(pkts) do
                pkts[j].token = token
                table.insert(packets, pkts[j])
                totalPackets = totalPackets + 1
            end
        end
    end
    
    -- Layer 4: Assignments (ordered by priority)
    if failedLayers.assignments then
        for encIdx, roleIndices in pairs(failedLayers.assignments) do
            local pkts = OGRH.SyncRepair.BuildAssignmentsPackets(encIdx, roleIndices)
            for j = 1, table.getn(pkts) do
                pkts[j].token = token
                table.insert(packets, pkts[j])
                totalPackets = totalPackets + 1
            end
        end
    end
    
    OGRH.Msg("|cff00ccff[RH-SyncRepair]|r Total packets built: " .. totalPackets)
    
    -- Send packets with adaptive delay
    OGRH.SyncRepairHandlers.SendPacketsWithPacing(packets, token, totalPackets)
end

-- Admin: Send packets with adaptive pacing to prevent network congestion
function OGRH.SyncRepairHandlers.SendPacketsWithPacing(packets, token, totalPackets)
    -- Check if session is still active (could be cancelled)
    local session = OGRH.SyncSession.GetActiveSession()
    if not session or session.token ~= token then
        OGRH.Msg("|cffff9900[RH-SyncRepair]|r Session cancelled, stopping packet transmission")
        return
    end
    
    if table.getn(packets) == 0 then
        -- All packets queued to CTL - wait for CTL to finish delivering before requesting validation
        OGRH.SyncRepairHandlers.WaitForCTLDrain(token, 0)
        return
    end
    
    -- Send next packet
    local packet = table.remove(packets, 1)
    local packetsSent = totalPackets - table.getn(packets)
    
    -- Determine message type based on packet type
    local messageType
    if packet.type == "STRUCTURE" then
        messageType = OGRH.MessageTypes.SYNC.REPAIR_PACKET_STRUCTURE
    elseif packet.type == "ROLESUI" then
        messageType = OGRH.MessageTypes.SYNC.REPAIR_PACKET_ROLESUI
    elseif packet.type == "ENCOUNTER" then
        messageType = OGRH.MessageTypes.SYNC.REPAIR_PACKET_ENCOUNTER
    elseif packet.type == "ROLE" then
        messageType = OGRH.MessageTypes.SYNC.REPAIR_PACKET_ROLE
    elseif packet.type == "ASSIGNMENTS" then
        messageType = OGRH.MessageTypes.SYNC.REPAIR_PACKET_ASSIGNMENTS
    end
    
    if messageType then
        -- Build descriptive name for logging
        local displayName = packet.type
        if packet.type == "ENCOUNTER" then
            local encName = (packet.data and packet.data.displayName) or (packet.data and packet.data.name) or "Unknown"
            local encIdx = packet.encounterIndex or "?"
            displayName = string.format("ENCOUNTER #%s (%s)", tostring(encIdx), encName)
        elseif packet.type == "ROLE" and packet.data and packet.data.role and packet.data.role.name then
            displayName = string.format("ROLE (%s)", packet.data.role.name)
        elseif packet.type == "STRUCTURE" then
            local sv = OGRH.SVM and OGRH.SVM.GetActiveSchema() or OGRH_SV.v2
            local raid = sv and sv.encounterMgmt and sv.encounterMgmt.raids and sv.encounterMgmt.raids[1]
            if raid and raid.displayName then
                displayName = string.format("STRUCTURE (%s)", raid.displayName)
            end
        end
        
        OGRH.Msg(string.format("|cff00ccff[RH-SyncRepair]|r Sending: %s", displayName))
        
        OGRH.MessageRouter.Send(messageType, packet, {
            priority = "HIGH",
            channel = "RAID"
        })
        
        -- Reset admin timeout (activity detected - packet sent)
        if OGRH.SyncRepairUI and OGRH.SyncRepairUI.ResetAdminTimeout then
            OGRH.SyncRepairUI.ResetAdminTimeout()
        end
    end
    
    -- Update admin UI
    local phaseText = "Sending " .. packet.type
    if packet.encounterIndex then
        phaseText = phaseText .. " (Enc " .. packet.encounterIndex .. ")"
    end
    
    if OGRH.SyncRepairUI and OGRH.SyncRepairUI.UpdateAdminProgress then
        OGRH.SyncRepairUI.UpdateAdminProgress(packetsSent, totalPackets, phaseText, {})
    end
    
    -- Calculate adaptive delay
    OGRH.SyncRepair.UpdateAdaptiveDelay()
    local delay = OGRH.SyncRepair.State.currentDelay
    
    -- Schedule next packet
    OGRH.ScheduleTimer(function()
        OGRH.SyncRepairHandlers.SendPacketsWithPacing(packets, token, totalPackets)
    end, delay)
end

-- Admin: Wait for ChatThrottleLib to finish delivering all queued messages
-- before requesting validation from clients
function OGRH.SyncRepairHandlers.WaitForCTLDrain(token, elapsed)
    local session = OGRH.SyncSession.GetActiveSession()
    if not session or session.token ~= token then
        return
    end
    
    local CTL = ChatThrottleLib
    local MAX_DRAIN_WAIT = 120  -- Safety cap: don't wait more than 2 minutes
    local POLL_INTERVAL = 1.0   -- Check every second
    
    if elapsed >= MAX_DRAIN_WAIT then
        OGRH.Msg("|cffff9900[RH-SyncRepair]|r CTL drain wait exceeded 120s, requesting validation anyway")
        OGRH.SyncRepairHandlers.RequestValidation(token)
        return
    end
    
    -- Check if CTL still has messages queued
    local isQueueing = CTL and CTL.bQueueing
    
    if isQueueing then
        -- CTL still sending - update UI and check again
        if OGRH.SyncRepairUI and OGRH.SyncRepairUI.UpdateAdminProgress then
            OGRH.SyncRepairUI.UpdateAdminProgress(0, 0, 
                string.format("Waiting for delivery (%ds)", elapsed), {})
        end
        
        -- Reset admin timeout (we're still working)
        if OGRH.SyncRepairUI and OGRH.SyncRepairUI.ResetAdminTimeout then
            OGRH.SyncRepairUI.ResetAdminTimeout()
        end
        
        OGRH.ScheduleTimer(function()
            OGRH.SyncRepairHandlers.WaitForCTLDrain(token, elapsed + POLL_INTERVAL)
        end, POLL_INTERVAL)
    else
        -- CTL queue is empty - all messages delivered
        if elapsed > 2 then
            OGRH.Msg(string.format("|cff00ccff[RH-SyncRepair]|r CTL queue drained after %.1fs", elapsed))
        end
        
        -- Small additional delay to ensure last message is processed by clients
        OGRH.ScheduleTimer(function()
            OGRH.SyncRepairHandlers.RequestValidation(token)
        end, 1.5)
    end
end

-- Admin: Request validation from all clients
function OGRH.SyncRepairHandlers.RequestValidation(token)
    -- Verify session still active
    local session = OGRH.SyncSession.GetActiveSession()
    if not session or session.token ~= token then
        return
    end
    
    -- Broadcast validation request
    OGRH.MessageRouter.Send(OGRH.MessageTypes.SYNC.REPAIR_VALIDATION, {
        token = token,
        request = true
    }, {
        priority = "HIGH",
        channel = "RAID"
    })
    
    OGRH.Msg("|cff00ff00[RH-SyncRepair]|r Requesting validation from clients...")
    
    -- Update admin UI
    if OGRH.SyncRepairUI and OGRH.SyncRepairUI.UpdateAdminProgress then
        OGRH.SyncRepairUI.UpdateAdminProgress(0, 0, "Validating repairs...", {})
    end
    
    -- Set timeout for validation (safety fallback - should be long enough 
    -- for clients to compute checksums and respond through CTL)
    session.validationTimerToken = token  -- Track which timer is active
    OGRH.ScheduleTimer(function()
        -- Only fire if this is still the active validation timer
        local s = OGRH.SyncSession.GetActiveSession()
        if s and s.token == token and s.validationTimerToken == token then
            OGRH.SyncRepairHandlers.CheckValidationComplete(token)
        end
    end, 45.0)  -- 45s safety timeout (CTL drain already waited)
end

-- Admin: Check if all clients have validated
function OGRH.SyncRepairHandlers.CheckValidationComplete(token)
    local session = OGRH.SyncSession.GetActiveSession()
    if not session or session.token ~= token then
        return
    end
    
    -- Check if all clients validated
    local allValidated = OGRH.SyncSession.AreAllClientsValidated()
    
    if not allValidated then
        OGRH.Msg("|cffff9900[RH-SyncRepair]|r Some clients didn't respond to validation, completing anyway")
    end
    
    -- Compare admin checksums with client checksums to find mismatches
    local failedEncounters = OGRH.SyncRepairHandlers.CompareValidationChecksums(token)
    
    if failedEncounters and table.getn(failedEncounters) > 0 then
        -- Track retry attempts
        local retryCount = session.retryCount or 0
        
        if retryCount < MAX_RETRY_ATTEMPTS then
            session.retryCount = retryCount + 1
            OGRH.Msg(string.format("|cffff9900[RH-SyncRepair]|r %d encounter(s) failed validation - retry %d/%d",
                table.getn(failedEncounters), session.retryCount, MAX_RETRY_ATTEMPTS))
            
            -- Log which encounters need retry
            for i = 1, table.getn(failedEncounters) do
                OGRH.Msg(string.format("|cffff9900[RH-SyncRepair]|r   Retrying encounter #%d", failedEncounters[i]))
            end
            
            -- Clear client validations so we can collect fresh ones
            if session.clientValidations then
                session.clientValidations = {}
            end
            
            -- Re-send only the failed encounters
            OGRH.ScheduleTimer(function()
                OGRH.SyncRepairHandlers.RetryFailedEncounters(token, failedEncounters)
            end, RETRY_DELAY)
            return
        else
            OGRH.Msg(string.format("|cffff9900[RH-SyncRepair]|r %d encounter(s) still mismatched after %d retries - completing anyway",
                table.getn(failedEncounters), MAX_RETRY_ATTEMPTS))
        end
    else
        OGRH.Msg("|cff00ff00[RH-SyncRepair]|r All validations passed")
    end
    
    OGRH.SyncRepairHandlers.CompleteRepair(token)
end

-- Admin: Complete repair session
function OGRH.SyncRepairHandlers.CompleteRepair(token)
    local session = OGRH.SyncSession.GetActiveSession()
    if not session or session.token ~= token then
        return
    end
    
    -- Broadcast completion
    OGRH.MessageRouter.Send(OGRH.MessageTypes.SYNC.REPAIR_COMPLETE, {
        token = token
    }, {
        priority = "HIGH",
        channel = "RAID"
    })
    
    OGRH.Msg("|cff00ff00[RH-SyncRepair]|r Repair session completed successfully")
    
    -- Hide admin UI
    if OGRH.SyncRepairUI and OGRH.SyncRepairUI.HideAdminPanel then
        OGRH.ScheduleTimer(function()
            OGRH.SyncRepairUI.HideAdminPanel()
        end, 2.0)  -- 2 second delay for user to see completion
    end
    
    -- Complete session (exits repair mode)
    OGRH.SyncSession.CompleteSession(token)
end

--[[
    ============================================================================
    CLIENT-SIDE HANDLERS (Receive packets, apply, validate)
    ============================================================================
]]

-- Client: Handle REPAIR_START message
function OGRH.SyncRepairHandlers.OnRepairStart(sender, data, channel)
    if not data or not data.token then
        return
    end
    
    -- SECURITY: Verify sender is raid admin
    if not OGRH.IsRaidAdmin or not OGRH.IsRaidAdmin(sender) then
        OGRH.Msg("|cffff0000[RH-SyncRepair]|r Ignoring REPAIR_START from non-admin: " .. sender)
        return
    end
    
    -- CRITICAL: Only accept repair if THIS client requested it
    if not OGRH.SyncRepairHandlers.hasRequestedRepair then
        -- Client joined mid-sync or didn't request repair - mark as waiting
        OGRH.SyncRepairHandlers.waitingForRepair = true
        OGRH.SyncRepairHandlers.waitingToken = data.token
        OGRH.SyncRepairHandlers.currentAdminName = sender
        
        -- Store admin name in session for disconnect detection
        local session = OGRH.SyncSession.GetActiveSession()
        if session then
            session.adminName = sender
        end
        
        if OGRH.SyncRepairUI and OGRH.SyncRepairUI.ShowWaitingPanel then
            OGRH.SyncRepairUI.ShowWaitingPanel(nil)
        end
        
        OGRH.Msg("|cffff9900[RH-SyncRepair]|r Repair session started, but not requested by this client - waiting...")
        return
    end
    
    -- Clear request flag (will be set again if needed after next checksum)
    OGRH.SyncRepairHandlers.hasRequestedRepair = false
    
    -- Store session token and admin name
    OGRH.SyncRepairHandlers.currentToken = data.token
    OGRH.SyncRepairHandlers.currentAdminName = sender
    OGRH.SyncRepairHandlers.expectedPackets = data.totalLayers or 0
    OGRH.SyncRepairHandlers.receivedPackets = 0
    
    -- Store admin name in session for disconnect detection
    local session = OGRH.SyncSession.GetActiveSession()
    if session then
        session.adminName = sender
    end

    -- CLIENT: Enter repair mode to lock UI/SVM during repair
    if OGRH.SyncIntegrity and OGRH.SyncIntegrity.EnterRepairMode then
        OGRH.SyncIntegrity.EnterRepairMode()
    end

    -- Show CLIENT panel (not waiting - waiting is for mid-repair joins only)
    if OGRH.SyncRepairUI and OGRH.SyncRepairUI.ShowClientPanel then
        OGRH.SyncRepairUI.ShowClientPanel(data.token)
    end
    
    -- Reset timeout (activity received)
    if OGRH.SyncRepairUI and OGRH.SyncRepairUI.ResetClientTimeout then
        OGRH.SyncRepairUI.ResetClientTimeout()
    end

    -- Track start time for ETA calculation
    OGRH.SyncRepairHandlers.repairStartTime = GetTime()
    
    OGRH.Msg(string.format("|cff00ff00[RH-SyncRepair]|r Repair session started by %s", sender))
end

-- Client: Handle REPAIR_PACKET_* messages
function OGRH.SyncRepairHandlers.OnRepairPacket(sender, data, channel)
    if not data or not data.token or not data.type then
        OGRH.Msg("|cffff0000[RH-SyncRepair]|r Invalid repair packet received")
        return
    end
    
    -- CRITICAL: Admin should not process their own repair packets
    if sender == UnitName("player") then
        return
    end
    
    -- SECURITY: Verify sender is raid admin
    if not OGRH.IsRaidAdmin or not OGRH.IsRaidAdmin(sender) then
        return  -- Silently ignore packets from non-admin
    end
    
    -- Check if this client requested repair for this session
    if data.token ~= OGRH.SyncRepairHandlers.currentToken then
        -- Player joined mid-sync or didn't request this repair - IGNORE ALL PACKETS
        if not OGRH.SyncRepairHandlers.waitingForRepair then
            OGRH.SyncRepairHandlers.waitingForRepair = true
            OGRH.SyncRepairHandlers.waitingToken = data.token
            
            if OGRH.SyncRepairUI and OGRH.SyncRepairUI.ShowWaitingPanel then
                OGRH.SyncRepairUI.ShowWaitingPanel(nil)  -- Unknown ETA
            end
            
            OGRH.Msg("|cffff9900[RH-SyncRepair]|r Joined during active repair, waiting for completion...")
        else
            -- Reset waiting timeout (packets still coming)
            if OGRH.SyncRepairUI and OGRH.SyncRepairUI.ResetWaitingTimeout then
                OGRH.SyncRepairUI.ResetWaitingTimeout()
            end
        end
        return  -- CRITICAL: Do not process packets for repairs we didn't request
    end
    
    -- Reset client timeout (activity detected)
    if OGRH.SyncRepairUI and OGRH.SyncRepairUI.ResetClientTimeout then
        OGRH.SyncRepairUI.ResetClientTimeout()
    end
    
    -- Build descriptive name for logging
    local displayName = data.type
    if data.type == "STRUCTURE" and data.data and data.data.displayName then
        displayName = string.format("STRUCTURE (%s)", data.data.displayName)
    elseif data.type == "ROLESUI" then
        displayName = "ROLESUI (global roles)"
    elseif data.type == "ENCOUNTER" and data.data and data.data.displayName then
        displayName = string.format("ENCOUNTER (%s)", data.data.displayName)
    elseif data.type == "ROLE" and data.data and data.data.role and data.data.role.name then
        displayName = string.format("ROLE (%s)", data.data.role.name)
    end
    
    OGRH.Msg(string.format("|cff00ccff[RH-SyncRepair]|r Repair Received: %s", displayName))
    
    -- Apply packet based on type
    local success = false
    if data.type == "STRUCTURE" then
        success = OGRH.SyncRepair.ApplyStructurePacket(data)
    elseif data.type == "ROLESUI" then
        success = OGRH.SyncRepair.ApplyRolesUIPacket(data)
    elseif data.type == "ENCOUNTER" then
        success = OGRH.SyncRepair.ApplyEncountersPacket(data)
    elseif data.type == "ROLE" then
        success = OGRH.SyncRepair.ApplyRolesPacket(data)
    elseif data.type == "ASSIGNMENTS" then
        success = OGRH.SyncRepair.ApplyAssignmentsPacket(data)
    end
    
    if not success then
        OGRH.Msg("|cffff9900[RH-SyncRepair]|r Failed to apply repair")
    end
    
    if success then
        OGRH.SyncRepairHandlers.receivedPackets = OGRH.SyncRepairHandlers.receivedPackets + 1
        
        local received = OGRH.SyncRepairHandlers.receivedPackets
        local total = OGRH.SyncRepairHandlers.expectedPackets
        
        -- Update client UI
        if OGRH.SyncRepairUI and OGRH.SyncRepairUI.UpdateClientProgress then
            local phaseText = "Applying " .. data.type
            OGRH.SyncRepairUI.UpdateClientProgress(received, total, phaseText)
        end
        
        -- Calculate and update ETA
        if OGRH.SyncRepairUI and OGRH.SyncRepairUI.UpdateClientCountdown then
            local startTime = OGRH.SyncRepairHandlers.repairStartTime
            if startTime and received > 1 and total > 0 then
                local elapsed = GetTime() - startTime
                local rate = received / elapsed  -- packets per second
                local remaining = total - received
                local etaSeconds = remaining / rate
                OGRH.SyncRepairUI.UpdateClientCountdown(math.ceil(etaSeconds))
            end
        end
    end
end

-- Client: Handle REPAIR_VALIDATION request
function OGRH.SyncRepairHandlers.OnRepairValidation(sender, data, channel)
    if not data or not data.token or not data.request then
        return
    end
    
    -- SECURITY: Verify sender is raid admin
    if not OGRH.IsRaidAdmin or not OGRH.IsRaidAdmin(sender) then
        return
    end
    
    -- Verify token matches
    if data.token ~= OGRH.SyncRepairHandlers.currentToken then
        return
    end
    
    -- Reset client timeout (activity detected)
    if OGRH.SyncRepairUI and OGRH.SyncRepairUI.ResetClientTimeout then
        OGRH.SyncRepairUI.ResetClientTimeout()
    end
    
    -- Compute validation checksums
    local activeRaid = OGRH.GetActiveRaid()
    if not activeRaid or not activeRaid.displayName then
        return
    end
    
    local raidName = activeRaid.displayName
    
    -- Compute checksums for all layers
    local layerIds = {
        structure = true,
        encounters = {},
        roles = {},
        assignments = {}
    }
    
    -- Add all encounters/roles
    local activeRaid = OGRH.GetActiveRaid()
    if activeRaid and activeRaid.encounters then
        for i = 1, table.getn(activeRaid.encounters) do
            table.insert(layerIds.encounters, i)
            layerIds.roles[i] = {}
            layerIds.assignments[i] = {}
            
            if activeRaid.encounters[i].roles then
                for j = 1, table.getn(activeRaid.encounters[i].roles) do
                    table.insert(layerIds.roles[i], j)
                    table.insert(layerIds.assignments[i], j)
                end
            end
        end
    end
    
    local checksums = OGRH.SyncRepair.ComputeValidationChecksums(raidName, layerIds)
    
    -- Send validation response to admin (broadcast to RAID since WHISPER doesn't work in Turtle WoW)
    OGRH.MessageRouter.Send(OGRH.MessageTypes.SYNC.REPAIR_VALIDATION, {
        token = data.token,
        checksums = checksums,
        status = "complete"
    }, {
        priority = "HIGH",
        channel = "RAID"
    })
    
    OGRH.Msg("|cff00ff00[RH-SyncRepair]|r Validation checksums sent to admin")
end

-- Admin: Handle REPAIR_VALIDATION response from client
function OGRH.SyncRepairHandlers.OnValidationResponse(sender, data, channel)
    if not data or not data.token then
        return
    end
    
    local session = OGRH.SyncSession.GetActiveSession()
    if not session or session.token ~= data.token then
        return
    end
    
    -- Log validation response received
    OGRH.Msg(string.format("|cff00ff00[RH-SyncRepair]|r Validation received from %s: %s", sender, tostring(data.status)))
    
    -- Reset admin timeout (activity detected)
    if OGRH.SyncRepairUI and OGRH.SyncRepairUI.ResetAdminTimeout then
        OGRH.SyncRepairUI.ResetAdminTimeout()
    end
    
    -- Record client validation (including checksums for comparison)
    if OGRH.SyncSession.RecordClientValidation then
        OGRH.SyncSession.RecordClientValidation(sender, data.status or "unknown", data.checksums)
    end
    
    -- Check if ALL participants have now responded - complete early if so
    if OGRH.SyncSession.AreAllClientsValidated() then
        OGRH.Msg("|cff00ff00[RH-SyncRepair]|r All clients responded, checking validation...")
        -- Cancel the safety timer by clearing token
        local session = OGRH.SyncSession.GetActiveSession()
        if session then
            session.validationTimerToken = nil
        end
        -- Check immediately
        OGRH.SyncRepairHandlers.CheckValidationComplete(data.token)
    end
    
    -- Update admin UI with validated client
    local validations = OGRH.SyncSession.GetClientValidations()
    if OGRH.SyncRepairUI and OGRH.SyncRepairUI.UpdateAdminProgress then
        OGRH.SyncRepairUI.UpdateAdminProgress(0, 0, "Validating repairs...", validations)
    end
end

-- Admin: Compare all client validation checksums against admin's own
-- Returns array of encounter indices that have mismatches, or nil if all good
function OGRH.SyncRepairHandlers.CompareValidationChecksums(token)
    local session = OGRH.SyncSession.GetActiveSession()
    if not session or session.token ~= token then
        return nil
    end
    
    -- Compute admin's current checksums
    local activeRaid = OGRH.GetActiveRaid()
    if not activeRaid or not activeRaid.displayName then
        return nil
    end
    
    local raidName = activeRaid.displayName
    local layerIds = {
        structure = true,
        encounters = {},
        roles = {},
        assignments = {}
    }
    
    if activeRaid.encounters then
        for i = 1, table.getn(activeRaid.encounters) do
            table.insert(layerIds.encounters, i)
            layerIds.roles[i] = {}
            layerIds.assignments[i] = {}
            if activeRaid.encounters[i].roles then
                for j = 1, table.getn(activeRaid.encounters[i].roles) do
                    table.insert(layerIds.roles[i], j)
                    table.insert(layerIds.assignments[i], j)
                end
            end
        end
    end
    
    local adminChecksums = OGRH.SyncRepair.ComputeValidationChecksums(raidName, layerIds)
    
    -- Compare against each client's validation
    local validations = OGRH.SyncSession.GetClientValidations()
    local failedEncounters = {}  -- Set of encounter indices that failed
    local failedSet = {}  -- Prevent duplicates
    
    for playerName, validation in pairs(validations) do
        if validation.checksums then
            local success, mismatches = OGRH.SyncRepair.ValidateRepair(raidName, adminChecksums, validation.checksums)
            
            if not success then
                for i = 1, table.getn(mismatches) do
                    local m = mismatches[i]
                    local encIdx = m.encounterIndex
                    if encIdx and not failedSet[encIdx] then
                        failedSet[encIdx] = true
                        table.insert(failedEncounters, encIdx)
                    end
                    
                    OGRH.Msg(string.format("|cffff9900[RH-SyncRepair]|r Validation mismatch from %s: layer %d, type=%s, enc=%s",
                        playerName, m.layer or 0, m.type or "?", tostring(encIdx or "global")))
                end
            end
        end
    end
    
    -- Sort encounter indices
    table.sort(failedEncounters)
    
    if table.getn(failedEncounters) == 0 then
        return nil  -- All good
    end
    
    return failedEncounters
end

-- Admin: Re-send only the specific encounters that failed validation
function OGRH.SyncRepairHandlers.RetryFailedEncounters(token, failedEncounters)
    local session = OGRH.SyncSession.GetActiveSession()
    if not session or session.token ~= token then
        OGRH.Msg("|cffff9900[RH-SyncRepair]|r Session no longer active, aborting retry")
        return
    end
    
    -- Build packets for only the failed encounters
    local packets = {}
    
    for i = 1, table.getn(failedEncounters) do
        local encIdx = failedEncounters[i]
        local pkts = OGRH.SyncRepair.BuildEncountersPackets({encIdx})
        for j = 1, table.getn(pkts) do
            pkts[j].token = token
            table.insert(packets, pkts[j])
            
            local encName = (pkts[j].data and pkts[j].data.displayName) or (pkts[j].data and pkts[j].data.name) or "Unknown"
            OGRH.Msg(string.format("|cff00ccff[RH-SyncRepair]|r Retry: ENCOUNTER #%d (%s)", encIdx, encName))
        end
    end
    
    local totalPackets = table.getn(packets)
    OGRH.Msg(string.format("|cff00ccff[RH-SyncRepair]|r Retrying %d encounter packet(s)", totalPackets))
    
    -- Update admin UI
    if OGRH.SyncRepairUI and OGRH.SyncRepairUI.UpdateAdminProgress then
        OGRH.SyncRepairUI.UpdateAdminProgress(0, totalPackets, 
            string.format("Retrying %d encounter(s)...", totalPackets), {})
    end
    
    -- Reset admin timeout
    if OGRH.SyncRepairUI and OGRH.SyncRepairUI.ResetAdminTimeout then
        OGRH.SyncRepairUI.ResetAdminTimeout()
    end
    
    -- Send retry packets with pacing, then request validation again
    OGRH.SyncRepairHandlers.SendPacketsWithPacing(packets, token, totalPackets)
end

-- Client: Handle REPAIR_COMPLETE message
function OGRH.SyncRepairHandlers.OnRepairComplete(sender, data, channel)
    if not data or not data.token then
        return
    end
    
    -- SECURITY: Verify sender is raid admin
    if not OGRH.IsRaidAdmin or not OGRH.IsRaidAdmin(sender) then
        return
    end
    
    -- If we were waiting (joined mid-sync), request validation now
    local wasWaiting = OGRH.SyncRepairHandlers.waitingForRepair and OGRH.SyncRepairHandlers.waitingToken == data.token
    
    if wasWaiting then
        OGRH.SyncRepairHandlers.waitingForRepair = false
        OGRH.SyncRepairHandlers.waitingToken = nil
        
        -- Record completion timestamp for client-side cooldown
        OGRH.SyncRepairHandlers.repairCompletedAt = GetTime()
        
        OGRH.Msg("|cff00ff00[RH-SyncRepair]|r Repair completed, skipping next checksum validation...")
        
        -- Hide waiting panel
        if OGRH.SyncRepairUI and OGRH.SyncRepairUI.HideWaitingPanel then
            OGRH.SyncRepairUI.HideWaitingPanel()
        end
        
        -- Set flag to skip NEXT checksum validation (data already received during repair)
        OGRH.SyncRepairHandlers.skipNextChecksumValidation = true
        OGRH.ScheduleTimer(function()
            -- Clear flag after 20 seconds (ensure we don't skip too many)
            OGRH.SyncRepairHandlers.skipNextChecksumValidation = false
        end, 20.0)
        
        -- Clear token so we don't try to verify it below
        OGRH.SyncRepairHandlers.currentToken = data.token
    end
    
    -- Verify token matches
    if data.token ~= OGRH.SyncRepairHandlers.currentToken then
        return
    end
    
    OGRH.Msg("|cff00ff00[RH-SyncRepair]|r Repair session completed successfully")
    
    -- Record completion timestamp for client-side cooldown
    OGRH.SyncRepairHandlers.repairCompletedAt = GetTime()
    
    -- CRITICAL: Save repaired data to disk BEFORE next validation
    if OGRH.SVM and OGRH.SVM.Save then
        OGRH.SVM.Save()
        if OGRH.SyncIntegrity.State.debug then
            OGRH.Msg("|cffaaaaaa[RH-SyncRepair DEBUG]|r Saved repaired data to SavedVariables")
        end
    end
    
    -- CLIENT: Exit repair mode to unlock UI/SVM
    if OGRH.SyncIntegrity and OGRH.SyncIntegrity.ExitRepairMode then
        OGRH.SyncIntegrity.ExitRepairMode()
    end
    
    -- Hide client UI
    if OGRH.SyncRepairUI and OGRH.SyncRepairUI.HideClientPanel then
        OGRH.ScheduleTimer(function()
            OGRH.SyncRepairUI.HideClientPanel()
        end, 2.0)
    end
    
    if OGRH.SyncRepairUI and OGRH.SyncRepairUI.HideWaitingPanel then
        OGRH.ScheduleTimer(function()
            OGRH.SyncRepairUI.HideWaitingPanel()
        end, 2.0)
    end
    
    -- Clear session token
    OGRH.SyncRepairHandlers.currentToken = nil
end

-- Both: Handle REPAIR_CANCEL message
function OGRH.SyncRepairHandlers.OnRepairCancel(sender, data, channel)
    if not data or not data.token then
        return
    end
    
    -- Clear waiting state
    if OGRH.SyncRepairHandlers.waitingForRepair then
        OGRH.SyncRepairHandlers.waitingForRepair = false
        OGRH.SyncRepairHandlers.waitingToken = nil
    end
    
    local reason = data.reason or "Unknown"
    OGRH.Msg(string.format("|cffff9900[RH-SyncRepair]|r Repair session cancelled: %s", reason))
    
    -- CLIENT: Exit repair mode to unlock UI/SVM
    if OGRH.SyncIntegrity and OGRH.SyncIntegrity.ExitRepairMode then
        OGRH.SyncIntegrity.ExitRepairMode()
    end
    
    -- Hide UI
    if OGRH.SyncRepairUI then
        if OGRH.SyncRepairUI.HideAdminPanel then
            OGRH.SyncRepairUI.HideAdminPanel()
        end
        if OGRH.SyncRepairUI.HideClientPanel then
            OGRH.SyncRepairUI.HideClientPanel()
        end
        if OGRH.SyncRepairUI.HideWaitingPanel then
            OGRH.SyncRepairUI.HideWaitingPanel()
        end
    end
    
    -- Cancel session
    if OGRH.SyncSession and OGRH.SyncSession.CancelSession then
        OGRH.SyncSession.CancelSession(reason)
    end
    
    -- Clear session token
    OGRH.SyncRepairHandlers.currentToken = nil
end

--[[
    ============================================================================
    HANDLER REGISTRATION
    ============================================================================
]]

-- Initialize module and register all message handlers
function OGRH.SyncRepairHandlers.Initialize()
    if not OGRH.MessageRouter or not OGRH.MessageRouter.RegisterHandler then
        OGRH.Msg("|cffff0000[RH-SyncRepair]|r MessageRouter not loaded, cannot register handlers")
        return false
    end
    
    -- Client handlers
    OGRH.MessageRouter.RegisterHandler(
        OGRH.MessageTypes.SYNC.REPAIR_START,
        OGRH.SyncRepairHandlers.OnRepairStart
    )
    
    OGRH.MessageRouter.RegisterHandler(
        OGRH.MessageTypes.SYNC.REPAIR_PACKET_STRUCTURE,
        OGRH.SyncRepairHandlers.OnRepairPacket
    )
    
    OGRH.MessageRouter.RegisterHandler(
        OGRH.MessageTypes.SYNC.REPAIR_PACKET_ROLESUI,
        OGRH.SyncRepairHandlers.OnRepairPacket
    )
    
    OGRH.MessageRouter.RegisterHandler(
        OGRH.MessageTypes.SYNC.REPAIR_PACKET_ENCOUNTER,
        OGRH.SyncRepairHandlers.OnRepairPacket
    )
    
    OGRH.MessageRouter.RegisterHandler(
        OGRH.MessageTypes.SYNC.REPAIR_PACKET_ROLE,
        OGRH.SyncRepairHandlers.OnRepairPacket
    )
    
    OGRH.MessageRouter.RegisterHandler(
        OGRH.MessageTypes.SYNC.REPAIR_PACKET_ASSIGNMENTS,
        OGRH.SyncRepairHandlers.OnRepairPacket
    )
    
    OGRH.MessageRouter.RegisterHandler(
        OGRH.MessageTypes.SYNC.REPAIR_VALIDATION,
        function(sender, data, channel)
            if data.request then
                -- Client handles validation request
                OGRH.SyncRepairHandlers.OnRepairValidation(sender, data, channel)
            else
                -- Admin handles validation response
                OGRH.SyncRepairHandlers.OnValidationResponse(sender, data, channel)
            end
        end
    )
    
    OGRH.MessageRouter.RegisterHandler(
        OGRH.MessageTypes.SYNC.REPAIR_COMPLETE,
        OGRH.SyncRepairHandlers.OnRepairComplete
    )
    
    OGRH.MessageRouter.RegisterHandler(
        OGRH.MessageTypes.SYNC.REPAIR_CANCEL,
        OGRH.SyncRepairHandlers.OnRepairCancel
    )
    
    OGRH.Msg("|cff00ccff[RH-SyncRepair]|r Initialized repair handlers")
end
