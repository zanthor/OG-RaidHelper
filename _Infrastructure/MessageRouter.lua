-- OGRH_MessageRouter.lua (Turtle-WoW 1.12)
-- Central message routing and handling system for OGAddonMsg integration
-- Routes all addon messages through a unified handler system

OGRH = OGRH or {}
OGRH.MessageRouter = {}

--[[
    Message Router State
]]
OGRH.MessageRouter.State = {
    handlers = {},              -- Registered message handlers
    messageQueue = {},          -- Outgoing message queue
    receivedMessages = {},      -- Recently received messages (for deduplication)
    isInitialized = false       -- Initialization flag
}

--[[
    Handler Registration
]]

-- Register a message handler
-- messageType: Full message type string (e.g., "OGRH_STRUCT_SET_ENCOUNTER")
-- handler: Function(sender, data, channel) to handle the message
function OGRH.MessageRouter.RegisterHandler(messageType, handler)
    if not messageType or not handler then
        OGRH.Msg("|cff00ccff[RH-MessageRouter]|r Invalid handler registration")
        return false
    end
    
    if not OGRH.IsValidMessageType(messageType) then
        OGRH.Msg(string.format("|cff00ccff[RH-MessageRouter]|r Registering unknown message type: %s", messageType))
    end
    
    OGRH.MessageRouter.State.handlers[messageType] = handler
    return true
end

-- Unregister a message handler
function OGRH.MessageRouter.UnregisterHandler(messageType)
    if not messageType then return false end
    OGRH.MessageRouter.State.handlers[messageType] = nil
    return true
end

-- Get handler for message type
function OGRH.MessageRouter.GetHandler(messageType)
    if not messageType then return nil end
    return OGRH.MessageRouter.State.handlers[messageType]
end

--[[
    Message Sending
]]

-- Send a message via OGAddonMsg with automatic permission checking
-- Accepts both tables and strings (OGAddonMsg auto-serializes tables)
-- @param messageType string - Message type from OGRH.MessageTypes
-- @param data table or string - Data to send (tables auto-serialized by OGAddonMsg)
-- @param options table - Optional {priority, target, channel, onSuccess, onFailure}
-- @return messageId or nil
function OGRH.MessageRouter.Send(messageType, data, options)
    if not messageType then
        OGRH.Msg("|cff00ccff[RH-MessageRouter]|r No message type specified")
        return nil
    end
    
    -- Validate message type (strip @target suffix if present for validation)
    local baseMessageType = messageType
    local atPos = string.find(messageType, "@")
    if atPos then
        baseMessageType = string.sub(messageType, 1, atPos - 1)
    end
    
    if not OGRH.IsValidMessageType(baseMessageType) then
        OGRH.Msg(string.format("|cff00ccff[RH-MessageRouter]|r Sending unknown message type: %s", baseMessageType))
    end
    
    -- Check permissions based on message category
    local category = OGRH.GetMessageCategory(messageType)
    local playerName = UnitName("player")
    
    if category == "STRUCT" then
        -- Structure changes require ADMIN permission
        if not OGRH.CanModifyStructure(playerName) then
            OGRH.HandlePermissionDenied(playerName, "STRUCT change")
            return nil
        end
    elseif category == "ASSIGN" then
        -- Assignment changes require OFFICER or ADMIN permission
        if not OGRH.CanModifyAssignments(playerName) then
            OGRH.HandlePermissionDenied(playerName, "ASSIGN change")
            return nil
        end
    end
    -- SYNC, ADMIN, STATE messages have no permission restrictions (anyone can query)
    
    -- Default options
    options = options or {}
    local priority = options.priority or "NORMAL"
    local target = options.target
    local channel = options.channel
    
    -- Ensure OGAddonMsg is available
    if not OGAddonMsg or not OGAddonMsg.Send then
        OGRH.Msg("|cff00ccff[RH-MessageRouter]|r OGAddonMsg not available")
        return nil
    end
    
    -- Send via OGAddonMsg
    local msgId = OGAddonMsg.Send(channel, target, messageType, data, {
        priority = priority,
        onSuccess = options.onSuccess,
        onFailure = options.onFailure,
        onComplete = options.onComplete
    })
    
    return msgId
end

-- Send a targeted message to a specific player
-- NOTE: WoW 1.12 does not support WHISPER for addon messages in raids
-- We broadcast to RAID with target prefix, receiver filters by target
function OGRH.MessageRouter.SendTo(targetPlayer, messageType, data, options)
    options = options or {}
    options.target = targetPlayer
    options.channel = nil  -- Use auto-detect (will use RAID)
    
    -- Prepend target to message type for filtering on receive
    local targetedMessageType = messageType .. "@" .. targetPlayer
    
    return OGRH.MessageRouter.Send(targetedMessageType, data, options)
end

-- Broadcast a message to all raid/party members
function OGRH.MessageRouter.Broadcast(messageType, data, options)
    if OGRH.SyncIntegrity and OGRH.SyncIntegrity.State.debug then
        OGRH.Msg(string.format("|cff00ccff[RH-MessageRouter][DEBUG]|r Broadcast: messageType=%s", tostring(messageType)))
    end
    
    options = options or {}
    options.channel = nil  -- Auto-detect best channel
    
    return OGRH.MessageRouter.Send(messageType, data, options)
end

--[[
    Message Receiving
]]

-- Check if message was recently received (deduplication)
function OGRH.MessageRouter.WasRecentlyReceived(msgId)
    if not msgId then return false end
    
    -- Check if msgId is in recent messages
    for i = 1, table.getn(OGRH.MessageRouter.State.receivedMessages) do
        if OGRH.MessageRouter.State.receivedMessages[i] == msgId then
            return true
        end
    end
    
    return false
end

-- Mark message as received
function OGRH.MessageRouter.MarkReceived(msgId)
    if not msgId then return end
    
    table.insert(OGRH.MessageRouter.State.receivedMessages, msgId)
    
    -- Keep only last 100 messages for deduplication
    while table.getn(OGRH.MessageRouter.State.receivedMessages) > 100 do
        table.remove(OGRH.MessageRouter.State.receivedMessages, 1)
    end
end

-- Handle incoming message from OGAddonMsg
function OGRH.MessageRouter.OnMessageReceived(sender, messageType, data, channel)
    -- Validate sender
    if not sender or sender == UnitName("player") then
        return  -- Ignore messages from self
    end
    
    if OGRH.SyncIntegrity and OGRH.SyncIntegrity.State.debug then
        OGRH.Msg(string.format("|cff00ccff[RH-MessageRouter][DEBUG]|r OnMessageReceived: sender=%s, messageType=%s", sender, tostring(messageType)))
    end
    
    -- Validate message type
    if not messageType then
        return
    end
    
    -- Check for targeted message (messageType@targetPlayer format)
    local actualMessageType = messageType
    local targetPlayer = nil
    local atPos = string.find(messageType, "@")
    if atPos then
        actualMessageType = string.sub(messageType, 1, atPos - 1)
        targetPlayer = string.sub(messageType, atPos + 1)
        
        -- Filter: only process if we're the target
        if targetPlayer ~= UnitName("player") then
            return
        end
    end
    
    -- Use the actual message type (without target suffix)
    messageType = actualMessageType
    
    -- OGAddonMsg auto-deserializes tables, so data is already in original form
    -- (table if sender sent table, string if sender sent string)
    
    -- Get handler for this message type
    local handler = OGRH.MessageRouter.GetHandler(messageType)
    
    if not handler then
        -- No handler registered - this is normal for some message types
        if OGRH.SyncIntegrity and OGRH.SyncIntegrity.State.debug then
            OGRH.Msg(string.format("|cff00ccff[RH-MessageRouter][DEBUG]|r No handler for messageType: %s", messageType))
        end
        return
    end
    
    if OGRH.SyncIntegrity and OGRH.SyncIntegrity.State.debug then
        OGRH.Msg(string.format("|cff00ccff[RH-MessageRouter][DEBUG]|r Calling handler for messageType: %s", messageType))
    end
    
    -- Call the handler with data (already deserialized by OGAddonMsg)
    local success, err = pcall(handler, sender, data, channel)
    
    if not success then
        OGRH.Msg(string.format("|cffff0000[RH-MessageRouter ERROR]|r Handler error for %s: %s", messageType, tostring(err)))
        if OGRH.SyncIntegrity and OGRH.SyncIntegrity.State.debug then
            OGRH.Msg(string.format("|cffff0000[RH-MessageRouter ERROR]|r Full error details: sender=%s, dataType=%s", sender, type(data)))
        end
    else
        if OGRH.SyncIntegrity and OGRH.SyncIntegrity.State.debug then
            OGRH.Msg(string.format("|cff00ccff[RH-MessageRouter][DEBUG]|r Handler completed successfully for: %s", messageType))
        end
    end
end

--[[
    OGAddonMsg Integration
]]

-- Initialize OGAddonMsg message listener
function OGRH.MessageRouter.InitializeOGAddonMsg()
    if not OGAddonMsg or not OGAddonMsg.RegisterWildcard then
        OGRH.Msg("|cff00ccff[RH-MessageRouter]|r OGAddonMsg not available for initialization")
        return false
    end
    
    -- Register a wildcard handler for all messages
    OGAddonMsg.RegisterWildcard(function(sender, prefix, data, channel)
        if OGRH.SyncIntegrity and OGRH.SyncIntegrity.State.debug then
            OGRH.Msg(string.format("|cff00ccff[RH-MessageRouter][DEBUG]|r Wildcard received: sender=%s, prefix=%s, channel=%s", 
                tostring(sender), tostring(prefix), tostring(channel)))
        end
        
        -- Only process OGRH messages
        if string.sub(prefix, 1, 5) == "OGRH_" then
            OGRH.MessageRouter.OnMessageReceived(sender, prefix, data, channel)
        end
    end)
    
    OGRH.Msg("|cff00ccff[RH-MessageRouter]|r Registered wildcard handler with OGAddonMsg")
    return true
end

--[[
    Legacy SendAddonMessage Wrapper (for gradual migration)
]]

-- Wrapper for old SendAddonMessage calls - redirects to MessageRouter
function OGRH.SendAddonMessage(msg, channel, target)
    -- Parse legacy message format
    local messageType = msg
    local data = nil
    
    -- Extract data if message has colon or semicolon delimiter
    local colonPos = string.find(msg, ":")
    local semicolonPos = string.find(msg, ";")
    
    if colonPos then
        messageType = string.sub(msg, 1, colonPos - 1)
        data = string.sub(msg, colonPos + 1)
    elseif semicolonPos then
        messageType = string.sub(msg, 1, semicolonPos - 1)
        data = string.sub(msg, semicolonPos + 1)
    end
    
    -- Translate legacy message type to new format
    local newMessageType = OGRH.TranslateLegacyMessage(messageType)
    
    if not newMessageType then
        -- No translation available - use original format with prefix
        newMessageType = "OGRH_LEGACY_" .. messageType
        OGRH.Msg(string.format("|cff00ccff[RH-MessageRouter]|r Untranslated legacy message: %s", messageType))
    end
    
    -- Send via MessageRouter
    local options = {
        channel = channel,
        target = target,
        priority = "NORMAL"
    }
    
    return OGRH.MessageRouter.Send(newMessageType, data, options)
end

--[[
    Initialization
]]

-- Initialize message router
function OGRH.MessageRouter.Initialize()
    if OGRH.MessageRouter.State.isInitialized then
        OGRH.Msg("|cff00ccff[RH-MessageRouter]|r Already initialized")
        return false
    end
    
    -- Initialize OGAddonMsg integration
    if not OGRH.MessageRouter.InitializeOGAddonMsg() then
        OGRH.Msg("|cff00ccff[RH-MessageRouter]|r Failed to initialize OGAddonMsg")
        return false
    end
    
    -- Register default handlers (will be expanded in future phases)
    OGRH.MessageRouter.RegisterDefaultHandlers()
    
    OGRH.MessageRouter.State.isInitialized = true
    OGRH.Msg("|cff00ccff[RH-MessageRouter]|r Initialized")
    
    return true
end

-- Register default message handlers
function OGRH.MessageRouter.RegisterDefaultHandlers()
    -- ADMIN messages
    OGRH.MessageRouter.RegisterHandler(OGRH.MessageTypes.ADMIN.TAKEOVER, function(sender, data, channel)
        if data and data.newAdmin then
            OGRH.SetRaidAdmin(data.newAdmin)
            OGRH.Msg(string.format("|cff00ccff[RH]|r %s is now the raid admin", data.newAdmin))
        end
    end)
    
    OGRH.MessageRouter.RegisterHandler(OGRH.MessageTypes.ADMIN.ASSIGN, function(sender, data, channel)
        if data and data.newAdmin then
            OGRH.SetRaidAdmin(data.newAdmin)
            OGRH.Msg(string.format("|cff00ccff[RH]|r %s assigned %s as raid admin", data.assignedBy or sender, data.newAdmin))
        end
    end)
    
    OGRH.MessageRouter.RegisterHandler(OGRH.MessageTypes.ADMIN.QUERY, function(sender, data, channel)
        -- Part 1: Delegate checksum requests to SyncIntegrity (admin only)
        -- This prevents SyncIntegrity from needing to register a duplicate handler
        if type(data) == "table" and data.requestType == "checksums" then
            if OGRH.SyncIntegrity and OGRH.SyncIntegrity.OnAdminQuery then
                OGRH.SyncIntegrity.OnAdminQuery(sender, data)
            end
            -- NOTE: Fall through to also send discovery response
            -- so the querier knows we're running OGRH
        end
        
        -- Part 2: Discovery roll-call - ALL OGRH clients respond
        -- Add random delay (0-2s) to stagger responses from 40-man raids
        local delay = math.random() * 2
        OGRH.ScheduleTimer(function()
            if GetNumRaidMembers() == 0 then return end
            
            local playerName = UnitName("player")
            local rank = 0
            for i = 1, GetNumRaidMembers() do
                local name, r = GetRaidRosterInfo(i)
                if name == playerName then
                    rank = r
                    break
                end
            end
            
            local currentAdmin = OGRH.GetRaidAdmin and OGRH.GetRaidAdmin()
            
            -- Broadcast response so ALL clients can build the same picture
            -- (needed for deterministic alphabetical tie-breaking)
            OGRH.MessageRouter.Broadcast(OGRH.MessageTypes.ADMIN.RESPONSE, {
                purpose = "discovery",
                playerName = playerName,
                rank = rank,
                isCurrentAdmin = (currentAdmin ~= nil and currentAdmin == playerName),
                version = OGRH.VERSION
            }, {priority = "NORMAL"})
        end, delay)
    end)
    
    OGRH.MessageRouter.RegisterHandler(OGRH.MessageTypes.ADMIN.RESPONSE, function(sender, data, channel)
        if not data then return end
        
        -- Handle discovery roll-call responses
        if data.purpose == "discovery" then
            -- Feed into AdminDiscovery if active
            if OGRH.AdminDiscovery and OGRH.AdminDiscovery.active then
                OGRH.AdminDiscovery.AddResponse(
                    data.playerName or sender,
                    data.rank or 0,
                    data.isCurrentAdmin or false
                )
            end
            
            -- If sender claims to be current admin, accept immediately
            -- This short-circuits discovery for the common case (joining existing raid)
            if data.isCurrentAdmin then
                local adminName = data.playerName or sender
                OGRH.SetRaidAdmin(adminName, true)  -- suppress broadcast (we received it)
                -- Cancel discovery since we found admin
                if OGRH.AdminDiscovery then
                    OGRH.AdminDiscovery.Cancel()
                end
            end
            return
        end
        
        -- Legacy admin claim response (from SyncIntegrity or direct admin response)
        if data.currentAdmin then
            OGRH.SetRaidAdmin(data.currentAdmin, true)
            -- Cancel discovery since admin confirmed
            if OGRH.AdminDiscovery and OGRH.AdminDiscovery.active then
                OGRH.AdminDiscovery.Cancel()
            end
        end
    end)
    
    OGRH.MessageRouter.RegisterHandler(OGRH.MessageTypes.ADMIN.POLL_VERSION, function(sender, data, channel)
        -- Respond to version poll
        OGRH.MessageRouter.SendTo(sender, OGRH.MessageTypes.ADMIN.POLL_RESPONSE, {
            version = OGRH.VERSION,
            dataVersion = OGRH.GetDataVersion(),
            checksum = OGRH.ComputeChecksum and OGRH.ComputeChecksum(OGRH.GetCurrentEncounter and OGRH.GetCurrentEncounter() or {}) or "UNKNOWN"
        }, {
            priority = "LOW"
        })
    end)
    
    OGRH.MessageRouter.RegisterHandler(OGRH.MessageTypes.ADMIN.READY_REQUEST, function(sender, data, channel)
        -- Only process if we are the raid leader
        if IsRaidLeader and IsRaidLeader() == 1 then
            -- Check if remote ready checks are allowed
            if OGRH.SVM.Get("allowRemoteReadyCheck") then
                -- Set flag to capture ready check responses
                OGRH.readyCheckInProgress = true
                OGRH.readyCheckResponses = {
                    notReady = {},
                    afk = {}
                }
                -- Show timer
                OGRH.ShowReadyCheckTimer()
                DoReadyCheck()
            else
                OGRH.Msg("Remote ready checks are disabled in settings.")
            end
        end
    end)
    
    OGRH.MessageRouter.RegisterHandler(OGRH.MessageTypes.ADMIN.READY_COMPLETE, function(sender, data, channel)
        -- Hide timer when raid leader reports results
        OGRH.HideReadyCheckTimer()
    end)
    
    -- STATE messages
    OGRH.MessageRouter.RegisterHandler(OGRH.MessageTypes.STATE.QUERY_LEAD, function(sender, data, channel)
        -- Respond with current raid lead
        local currentLead = OGRH.GetRaidAdmin and OGRH.GetRaidAdmin() or "Unknown"
        
        OGRH.MessageRouter.SendTo(sender, OGRH.MessageTypes.STATE.RESPONSE_LEAD, {
            lead = currentLead
        }, {
            priority = "LOW"
        })
    end)
    
    OGRH.MessageRouter.RegisterHandler(OGRH.MessageTypes.STATE.CHANGE_ENCOUNTER, function(sender, data, channel)
        -- Data is already deserialized by MessageRouter
        local encounterData = data
        if not encounterData then return end
        
        -- Security: Only accept encounter changes from raid admin
        if GetNumRaidMembers() > 0 then
            if not OGRH.IsRaidAdmin or not OGRH.IsRaidAdmin(sender) then
                return
            end
        end
        
        -- Update local UI to match encounter selection using indices
        if encounterData.raidIndex and encounterData.encounterIndex then
            -- Don't re-broadcast - just update local state silently
            OGRH.SVM.Set("ui", "selectedRaidIndex", encounterData.raidIndex)
            OGRH.SVM.Set("ui", "selectedEncounterIndex", encounterData.encounterIndex)
            
            -- Also update legacy name fields for backward compatibility
            local raids = OGRH.SVM.GetPath("encounterMgmt.raids")
            if raids and raids[encounterData.raidIndex] then
                local raid = raids[encounterData.raidIndex]
                local raidDisplayName = raid.displayName or raid.name
                OGRH.SVM.Set("ui", "selectedRaid", raidDisplayName)
                
                if raid.encounters and raid.encounters[encounterData.encounterIndex] then
                    local encounterName = raid.encounters[encounterData.encounterIndex].name
                    OGRH.SVM.Set("ui", "selectedEncounter", encounterName)
                end
            end
            
            -- Update UI button if available
            if OGRH.UpdateEncounterNavButton then
                OGRH.UpdateEncounterNavButton()
            end
            
            -- Refresh Encounter Planning window if it's open
            if OGRH_EncounterFrame and OGRH_EncounterFrame:IsVisible() then
                if OGRH_EncounterFrame.RefreshRoleContainers then
                    OGRH_EncounterFrame.RefreshRoleContainers()
                end
                if OGRH_EncounterFrame.UpdateAnnouncementBuilder then
                    OGRH_EncounterFrame.UpdateAnnouncementBuilder()
                end
            end
            
            -- Update consume monitor if available
            if OGRH.ShowConsumeMonitor then
                OGRH.ShowConsumeMonitor()
            end
        end
    end)
    
    OGRH.MessageRouter.RegisterHandler(OGRH.MessageTypes.STATE.REQUEST_ENCOUNTER, function(sender, data, channel)
        -- Only admin should process encounter change requests
        if not OGRH.IsRaidAdmin or not OGRH.IsRaidAdmin(UnitName("player")) then
            return
        end
        
        -- Validate request data (now using indices)
        if not data or not data.raidIndex or not data.encounterIndex then
            return
        end
        
        -- Apply encounter change locally (will trigger broadcast to all via SetCurrentEncounter)
        if OGRH.SetCurrentEncounter then
            OGRH.SetCurrentEncounter(data.raidIndex, data.encounterIndex)
        end
        
        -- Update Admin's own UI
        if OGRH.UpdateEncounterNavButton then
            OGRH.UpdateEncounterNavButton()
        end
        
        -- Refresh Encounter Planning window if it's open
        if OGRH_EncounterFrame and OGRH_EncounterFrame:IsVisible() then
            if OGRH_EncounterFrame.RefreshRoleContainers then
                OGRH_EncounterFrame.RefreshRoleContainers()
            end
            if OGRH_EncounterFrame.UpdateAnnouncementBuilder then
                OGRH_EncounterFrame.UpdateAnnouncementBuilder()
            end
        end
        
        -- Update consume monitor if enabled
        if OGRH.ShowConsumeMonitor then
            OGRH.ShowConsumeMonitor()
        end
    end)
    
    OGRH.MessageRouter.RegisterHandler(OGRH.MessageTypes.STATE.QUERY_ENCOUNTER, function(sender, data, channel)
        -- Only admin should respond to encounter queries
        if not OGRH.IsRaidAdmin or not OGRH.IsRaidAdmin(UnitName("player")) then
            return
        end
        
        -- Get current encounter selection
        local raidName, encounterName = OGRH.GetCurrentEncounter()
        if raidName and encounterName then
            OGRH.MessageRouter.SendTo(sender, OGRH.MessageTypes.STATE.RESPONSE_ENCOUNTER, {
                raidName = raidName,
                encounterName = encounterName
            })
        end
    end)
    
    OGRH.MessageRouter.RegisterHandler(OGRH.MessageTypes.STATE.RESPONSE_ENCOUNTER, function(sender, data, channel)
        -- Only accept encounter responses from admin
        if not OGRH.IsRaidAdmin or not OGRH.IsRaidAdmin(sender) then
            return
        end
        
        -- Apply encounter selection
        if data and data.raidName and data.encounterName then
            OGRH.SVM.SetPath("ui.selectedRaid", data.raidName)
            OGRH.SVM.SetPath("ui.selectedEncounter", data.encounterName)
            
            -- Update UI
            if OGRH.UpdateEncounterNavButton then
                OGRH.UpdateEncounterNavButton()
            end
            
            -- Refresh Encounter Planning window if open
            if OGRH_EncounterFrame and OGRH_EncounterFrame:IsVisible() then
                if OGRH_EncounterFrame.RefreshRoleContainers then
                    OGRH_EncounterFrame.RefreshRoleContainers()
                end
                if OGRH_EncounterFrame.UpdateAnnouncementBuilder then
                    OGRH_EncounterFrame.UpdateAnnouncementBuilder()
                end
            end
        end
    end)
    
    -- SYNC delta messages (Phase 2)
    -- Delegates to SVM for processing
    OGRH.MessageRouter.RegisterHandler(OGRH.MessageTypes.SYNC.DELTA, function(sender, data, channel)
        if OGRH.SVM and OGRH.SVM.OnDeltaReceived then
            OGRH.SVM.OnDeltaReceived(sender, data, channel)
        end
    end)
    
    OGRH.MessageRouter.RegisterHandler(OGRH.MessageTypes.SYNC.REQUEST_PARTIAL, function(sender, data, channel)
        -- Only admin should respond to partial sync requests
        if not OGRH.IsRaidAdmin or not OGRH.IsRaidAdmin() then
            return
        end
        
        -- Data already deserialized by OGAddonMsg
        local requestData = data
        if not requestData then return end
        
        -- If data contains raidName and encounterName, sync that specific encounter
        if requestData.raidName and requestData.encounterName then
            if OGRH.BroadcastFullEncounterSync then
                OGRH.BroadcastFullEncounterSync()
            end
        end
    end)
    
    -- ASSIGN delta messages (Phase 3A)
    OGRH.MessageRouter.RegisterHandler(OGRH.MessageTypes.ASSIGN.DELTA_BATCH, function(sender, data, channel)
        -- MessageRouter auto-deserializes, so data is already a table
        local deltaData = data
        
        if not deltaData or type(deltaData) ~= "table" or not deltaData.changes then
            return
        end
        
        -- Apply each change
        for i = 1, table.getn(deltaData.changes) do
            local change = deltaData.changes[i]
            
            if change.type == "SWAP" then
                -- Handle atomic swap operation
                if change.assignData1 and change.assignData2 then
                    local data1 = change.assignData1
                    local data2 = change.assignData2
                    
                    -- Validate both have required fields
                    if data1.raid and data1.encounter and data1.roleIndex and data1.slotIndex and
                       data2.raid and data2.encounter and data2.roleIndex and data2.slotIndex then
                        
                        -- Get current encounterAssignments table
                        local encounterAssignments = OGRH.SVM.Get("encounterAssignments") or {}
                        
                        -- Initialize nested tables
                        if not encounterAssignments[data1.raid] then 
                            encounterAssignments[data1.raid] = {} 
                        end
                        if not encounterAssignments[data1.raid][data1.encounter] then 
                            encounterAssignments[data1.raid][data1.encounter] = {} 
                        end
                        if not encounterAssignments[data1.raid][data1.encounter][data1.roleIndex] then 
                            encounterAssignments[data1.raid][data1.encounter][data1.roleIndex] = {} 
                        end
                        if not encounterAssignments[data1.raid][data1.encounter][data2.roleIndex] then 
                            encounterAssignments[data1.raid][data1.encounter][data2.roleIndex] = {} 
                        end
                        
                        -- Apply BOTH assignments atomically (no UI refresh between)
                        encounterAssignments[data1.raid][data1.encounter][data1.roleIndex][data1.slotIndex] = change.player1
                        encounterAssignments[data2.raid][data2.encounter][data2.roleIndex][data2.slotIndex] = change.player2  -- nil for empty slot
                        
                        -- Save back to SVM
                        OGRH.SVM.Set("encounterAssignments", encounterAssignments)
                    end
                end
                
            elseif change.type == "ROLE" then
                -- Apply role change (RolesUI bucket assignments)
                local roles = OGRH.SVM.Get("roles") or {}
                roles[change.player] = change.newValue
                OGRH.SVM.Set("roles", roles)
                
            elseif change.type == "ASSIGNMENT" then
                -- Apply assignment changes (check assignmentType to determine what kind)
                
                if change.assignmentType == "RAID_MARK" then
                    -- Apply raid mark change
                    if change.newValue and type(change.newValue) == "table" and change.newValue.assignData then
                        local assignData = change.newValue.assignData
                        if assignData.raid and assignData.encounter and assignData.roleIndex and assignData.slotIndex then
                            -- Get current encounterRaidMarks table
                            local encounterRaidMarks = OGRH.SVM.Get("encounterRaidMarks") or {}
                            
                            -- Initialize nested tables
                            if not encounterRaidMarks[assignData.raid] then 
                                encounterRaidMarks[assignData.raid] = {} 
                            end
                            if not encounterRaidMarks[assignData.raid][assignData.encounter] then 
                                encounterRaidMarks[assignData.raid][assignData.encounter] = {} 
                            end
                            if not encounterRaidMarks[assignData.raid][assignData.encounter][assignData.roleIndex] then 
                                encounterRaidMarks[assignData.raid][assignData.encounter][assignData.roleIndex] = {} 
                            end
                            
                            -- Apply the mark
                            local markValue = change.newValue.mark or 0
                            encounterRaidMarks[assignData.raid][assignData.encounter][assignData.roleIndex][assignData.slotIndex] = markValue
                            
                            -- Save back to SVM
                            OGRH.SVM.Set("encounterRaidMarks", encounterRaidMarks)
                        end
                    end
                    
                elseif change.assignmentType == "ASSIGNMENT_NUMBER" then
                    -- Apply assignment number change
                    if change.newValue and type(change.newValue) == "table" and change.newValue.assignData then
                        local assignData = change.newValue.assignData
                        if assignData.raid and assignData.encounter and assignData.roleIndex and assignData.slotIndex then
                            -- Get current encounterAssignmentNumbers table
                            local encounterAssignmentNumbers = OGRH.SVM.Get("encounterAssignmentNumbers") or {}
                            
                            -- Initialize nested tables
                            if not encounterAssignmentNumbers[assignData.raid] then 
                                encounterAssignmentNumbers[assignData.raid] = {} 
                            end
                            if not encounterAssignmentNumbers[assignData.raid][assignData.encounter] then 
                                encounterAssignmentNumbers[assignData.raid][assignData.encounter] = {} 
                            end
                            if not encounterAssignmentNumbers[assignData.raid][assignData.encounter][assignData.roleIndex] then 
                                encounterAssignmentNumbers[assignData.raid][assignData.encounter][assignData.roleIndex] = {} 
                            end
                            
                            -- Apply the number
                            local numberValue = change.newValue.number or 0
                            encounterAssignmentNumbers[assignData.raid][assignData.encounter][assignData.roleIndex][assignData.slotIndex] = numberValue
                            
                            -- Save back to SVM
                            OGRH.SVM.Set("encounterAssignmentNumbers", encounterAssignmentNumbers)
                        end
                    end
                    
                elseif change.assignmentType == "ANNOUNCEMENT" then
                    -- Apply announcement change
                    if change.newValue and type(change.newValue) == "table" and change.newValue.announcementData then
                        local announcementData = change.newValue.announcementData
                        if announcementData.raid and announcementData.encounter and announcementData.lineIndex then
                            -- Get current encounterAnnouncements table
                            local encounterAnnouncements = OGRH.SVM.Get("encounterAnnouncements") or {}
                            
                            -- Initialize nested tables
                            if not encounterAnnouncements[announcementData.raid] then 
                                encounterAnnouncements[announcementData.raid] = {} 
                            end
                            if not encounterAnnouncements[announcementData.raid][announcementData.encounter] then 
                                encounterAnnouncements[announcementData.raid][announcementData.encounter] = {} 
                            end
                            
                            -- Apply the announcement text
                            local textValue = change.newValue.text or ""
                            encounterAnnouncements[announcementData.raid][announcementData.encounter][announcementData.lineIndex] = textValue
                            
                            -- Save back to SVM
                            OGRH.SVM.Set("encounterAnnouncements", encounterAnnouncements)
                        end
                    end
                    
                elseif change.assignmentType == "CONSUME_SELECTION" then
                    -- Apply consume selection change
                    if change.newValue and type(change.newValue) == "table" and change.newValue.consumeData then
                        local consumeData = change.newValue.consumeData
                        if consumeData.raid and consumeData.encounter and consumeData.roleIndex and consumeData.slotIndex then
                            -- Get the role from encounterMgmt.roles
                            local encounterMgmt = OGRH.SVM.Get("encounterMgmt") or {raids = {}, roles = {}}
                            if not encounterMgmt.roles then encounterMgmt.roles = {} end
                            if not encounterMgmt.roles[consumeData.raid] then 
                                encounterMgmt.roles[consumeData.raid] = {} 
                            end
                            if not encounterMgmt.roles[consumeData.raid][consumeData.encounter] then 
                                encounterMgmt.roles[consumeData.raid][consumeData.encounter] = {column1 = {}, column2 = {}} 
                            end
                            
                            local encounterRoles = encounterMgmt.roles[consumeData.raid][consumeData.encounter]
                            local column1 = encounterRoles.column1 or {}
                            local column2 = encounterRoles.column2 or {}
                            
                            -- Find the role based on roleIndex (1-based across both columns)
                            local role = nil
                            if consumeData.roleIndex <= table.getn(column1) then
                                role = column1[consumeData.roleIndex]
                            else
                                role = column2[consumeData.roleIndex - table.getn(column1)]
                            end
                            
                            if role then
                                -- Initialize consumes array if needed
                                if not role.consumes then
                                    role.consumes = {}
                                end
                                
                                -- Apply the consume selection
                                role.consumes[consumeData.slotIndex] = change.newValue.consume
                                
                                -- Save back to SVM
                                OGRH.SVM.Set("encounterMgmt", encounterMgmt)
                            end
                        end
                    end
                
                elseif change.assignmentType == "ENCOUNTER_ROLE" then
                    -- Extract encounter assignment data from newValue table
                    local assignData = change.newValue
                    if type(assignData) == "table" and assignData.raid and assignData.encounter and 
                       assignData.roleIndex and assignData.slotIndex then
                        
                        -- Get current encounterAssignments table
                        local encounterAssignments = OGRH.SVM.Get("encounterAssignments") or {}
                        
                        -- Initialize nested tables
                        if not encounterAssignments[assignData.raid] then 
                            encounterAssignments[assignData.raid] = {} 
                        end
                        if not encounterAssignments[assignData.raid][assignData.encounter] then 
                            encounterAssignments[assignData.raid][assignData.encounter] = {} 
                        end
                        if not encounterAssignments[assignData.raid][assignData.encounter][assignData.roleIndex] then 
                            encounterAssignments[assignData.raid][assignData.encounter][assignData.roleIndex] = {} 
                        end
                        
                        -- Apply the assignment
                        encounterAssignments[assignData.raid][assignData.encounter][assignData.roleIndex][assignData.slotIndex] = assignData.playerName
                        
                        -- Save back to SVM
                        OGRH.SVM.Set("encounterAssignments", encounterAssignments)
                    end
                else
                    -- Generic assignment (fallback for other types)
                    if OGRH.SetPlayerAssignment then
                        OGRH.SetPlayerAssignment(change.player, {
                            type = change.assignmentType,
                            value = change.newValue
                        })
                    end
                end
                
            elseif change.type == "GROUP" then
                -- Apply group change (if group assignment system exists)
                -- (Implementation pending)
                
            elseif change.type == "STRUCTURE" then
                -- Apply structure changes (raid/encounter/role CRUD operations)
                
                if change.structureType == "RAID" then
                    local encounterMgmt = OGRH.SVM.Get("encounterMgmt") or {raids = {}, roles = {}}
                    if not encounterMgmt.raids then encounterMgmt.raids = {} end
                    
                    if change.operation == "ADD" and change.details and change.details.raidName then
                        -- Add new raid
                        local raidName = change.details.raidName
                        local exists = false
                        for i = 1, table.getn(encounterMgmt.raids) do
                            if encounterMgmt.raids[i].name == raidName then
                                exists = true
                                break
                            end
                        end
                        if not exists then
                            table.insert(encounterMgmt.raids, {
                                name = raidName,
                                encounters = {},
                                advancedSettings = {
                                    consumeTracking = {
                                        enabled = false,
                                        readyThreshold = 85,
                                        requiredFlaskRoles = {
                                            ["Tanks"] = false,
                                            ["Healers"] = false,
                                            ["Melee"] = false,
                                            ["Ranged"] = false,
                                        }
                                    }
                                }
                            })
                        end
                        -- Save after ADD
                        OGRH.SVM.Set("encounterMgmt", encounterMgmt)
                        
                    elseif change.operation == "DELETE" and change.details and change.details.raidName then
                        -- Delete raid
                        local raidName = change.details.raidName
                        for i = 1, table.getn(encounterMgmt.raids) do
                            if encounterMgmt.raids[i].name == raidName then
                                table.remove(encounterMgmt.raids, i)
                                break
                            end
                        end
                        -- Save after DELETE
                        OGRH.SVM.Set("encounterMgmt", encounterMgmt)
                        
                    elseif change.operation == "RENAME" and change.details and change.details.oldName and change.details.newName then
                        -- Rename raid
                        local oldName = change.details.oldName
                        local newName = change.details.newName
                        
                        -- Update raid name in raids list
                        for i = 1, table.getn(encounterMgmt.raids) do
                            if encounterMgmt.raids[i].name == oldName then
                                encounterMgmt.raids[i].name = newName
                                break
                            end
                        end
                        
                        -- Update all related data structures
                        if encounterMgmt.roles and encounterMgmt.roles[oldName] then
                            encounterMgmt.roles[newName] = encounterMgmt.roles[oldName]
                            encounterMgmt.roles[oldName] = nil
                        end
                        
                        -- Handle encounterAssignments rename
                        local encounterAssignments = OGRH.SVM.Get("encounterAssignments") or {}
                        if encounterAssignments[oldName] then
                            encounterAssignments[newName] = encounterAssignments[oldName]
                            encounterAssignments[oldName] = nil
                            OGRH.SVM.Set("encounterAssignments", encounterAssignments)
                        end
                        
                        -- Handle encounterRaidMarks rename
                        local encounterRaidMarks = OGRH.SVM.Get("encounterRaidMarks") or {}
                        if encounterRaidMarks[oldName] then
                            encounterRaidMarks[newName] = encounterRaidMarks[oldName]
                            encounterRaidMarks[oldName] = nil
                            OGRH.SVM.Set("encounterRaidMarks", encounterRaidMarks)
                        end
                        
                        -- Handle encounterAssignmentNumbers rename
                        local encounterAssignmentNumbers = OGRH.SVM.Get("encounterAssignmentNumbers") or {}
                        if encounterAssignmentNumbers[oldName] then
                            encounterAssignmentNumbers[newName] = encounterAssignmentNumbers[oldName]
                            encounterAssignmentNumbers[oldName] = nil
                            OGRH.SVM.Set("encounterAssignmentNumbers", encounterAssignmentNumbers)
                        end
                        
                        -- Handle encounterAnnouncements rename
                        local encounterAnnouncements = OGRH.SVM.Get("encounterAnnouncements") or {}
                        if encounterAnnouncements[oldName] then
                            encounterAnnouncements[newName] = encounterAnnouncements[oldName]
                            encounterAnnouncements[oldName] = nil
                            OGRH.SVM.Set("encounterAnnouncements", encounterAnnouncements)
                        end
                        
                        -- Save encounterMgmt after RENAME
                        OGRH.SVM.Set("encounterMgmt", encounterMgmt)
                    
                    elseif change.operation == "REORDER" and change.details and change.details.raidName and change.details.oldPosition and change.details.newPosition then
                        -- Reorder raid in list
                        local raidName = change.details.raidName
                        local oldPos = change.details.oldPosition
                        local newPos = change.details.newPosition
                        
                        -- Find raid by name and position
                        local raidIndex = nil
                        for i = 1, table.getn(encounterMgmt.raids) do
                            if encounterMgmt.raids[i].name == raidName then
                                raidIndex = i
                                break
                            end
                        end
                        
                        if raidIndex and raidIndex == oldPos then
                            -- Swap elements
                            local temp = encounterMgmt.raids[newPos]
                            encounterMgmt.raids[newPos] = encounterMgmt.raids[oldPos]
                            encounterMgmt.raids[oldPos] = temp
                        end
                        
                        -- Save after REORDER
                        OGRH.SVM.Set("encounterMgmt", encounterMgmt)
                    end
                    
                elseif change.structureType == "ENCOUNTER" then
                    local encounterMgmt = OGRH.SVM.Get("encounterMgmt") or {raids = {}, roles = {}}
                    if not encounterMgmt or not encounterMgmt.raids then return end
                    
                    if change.operation == "ADD" and change.details and change.details.raidName and change.details.encounterName then
                        -- Add new encounter
                        local raidName = change.details.raidName
                        local encounterName = change.details.encounterName
                        
                        -- Find raid
                        local raidObj = nil
                        for i = 1, table.getn(encounterMgmt.raids) do
                            if encounterMgmt.raids[i].name == raidName then
                                raidObj = encounterMgmt.raids[i]
                                break
                            end
                        end
                        
                        if raidObj then
                            if not raidObj.encounters then raidObj.encounters = {} end
                            
                            -- Check if encounter already exists
                            local exists = false
                            for i = 1, table.getn(raidObj.encounters) do
                                if raidObj.encounters[i].name == encounterName then
                                    exists = true
                                    break
                                end
                            end
                            
                            if not exists then
                                table.insert(raidObj.encounters, {
                                    name = encounterName,
                                    advancedSettings = {
                                        bigwigs = {
                                            enabled = false,
                                            encounterId = "",
                                            autoAnnounce = false
                                        },
                                        consumeTracking = {
                                            enabled = nil,
                                            readyThreshold = nil,
                                            requiredFlaskRoles = {}
                                        }
                                    }
                                })
                            end
                        end
                        
                    elseif change.operation == "DELETE" and change.details and change.details.raidName and change.details.encounterName then
                        -- Delete encounter
                        local raidName = change.details.raidName
                        local encounterName = change.details.encounterName
                        
                        -- Get encounterMgmt from SVM
                        local encounterMgmt = OGRH.SVM.Get("encounterMgmt") or {raids = {}, roles = {}}
                        
                        -- Find raid
                        local raidObj = nil
                        for i = 1, table.getn(encounterMgmt.raids) do
                            if encounterMgmt.raids[i].name == raidName then
                                raidObj = encounterMgmt.raids[i]
                                break
                            end
                        end
                        
                        if raidObj and raidObj.encounters then
                            for i = 1, table.getn(raidObj.encounters) do
                                if raidObj.encounters[i].name == encounterName then
                                    table.remove(raidObj.encounters, i)
                                    break
                                end
                            end
                        end
                        
                        -- Save back to SVM
                        OGRH.SVM.Set("encounterMgmt", encounterMgmt)
                        
                    elseif change.operation == "RENAME" and change.details and change.details.raidName and change.details.oldName and change.details.newName then
                        -- Rename encounter
                        local raidName = change.details.raidName
                        local oldName = change.details.oldName
                        local newName = change.details.newName
                        
                        -- Get all related tables from SVM
                        local encounterMgmt = OGRH.SVM.Get("encounterMgmt") or {raids = {}, roles = {}}
                        local encounterAssignments = OGRH.SVM.Get("encounterAssignments") or {}
                        local encounterRaidMarks = OGRH.SVM.Get("encounterRaidMarks") or {}
                        local encounterAssignmentNumbers = OGRH.SVM.Get("encounterAssignmentNumbers") or {}
                        local encounterAnnouncements = OGRH.SVM.Get("encounterAnnouncements") or {}
                        
                        -- Find raid
                        local raidObj = nil
                        for i = 1, table.getn(encounterMgmt.raids) do
                            if encounterMgmt.raids[i].name == raidName then
                                raidObj = encounterMgmt.raids[i]
                                break
                            end
                        end
                        
                        if raidObj and raidObj.encounters then
                            -- Update encounter name
                            for i = 1, table.getn(raidObj.encounters) do
                                if raidObj.encounters[i].name == oldName then
                                    raidObj.encounters[i].name = newName
                                    break
                                end
                            end
                            
                            -- Update all related data structures
                            if encounterMgmt.roles and encounterMgmt.roles[raidName] and encounterMgmt.roles[raidName][oldName] then
                                encounterMgmt.roles[raidName][newName] = encounterMgmt.roles[raidName][oldName]
                                encounterMgmt.roles[raidName][oldName] = nil
                            end
                            if encounterAssignments[raidName] and encounterAssignments[raidName][oldName] then
                                encounterAssignments[raidName][newName] = encounterAssignments[raidName][oldName]
                                encounterAssignments[raidName][oldName] = nil
                            end
                            if encounterRaidMarks[raidName] and encounterRaidMarks[raidName][oldName] then
                                encounterRaidMarks[raidName][newName] = encounterRaidMarks[raidName][oldName]
                                encounterRaidMarks[raidName][oldName] = nil
                            end
                            if encounterAssignmentNumbers[raidName] and encounterAssignmentNumbers[raidName][oldName] then
                                encounterAssignmentNumbers[raidName][newName] = encounterAssignmentNumbers[raidName][oldName]
                                encounterAssignmentNumbers[raidName][oldName] = nil
                            end
                            if encounterAnnouncements[raidName] and encounterAnnouncements[raidName][oldName] then
                                encounterAnnouncements[raidName][newName] = encounterAnnouncements[raidName][oldName]
                                encounterAnnouncements[raidName][oldName] = nil
                            end
                        end
                        
                        -- Save all modified tables back to SVM
                        OGRH.SVM.Set("encounterMgmt", encounterMgmt)
                        OGRH.SVM.Set("encounterAssignments", encounterAssignments)
                        OGRH.SVM.Set("encounterRaidMarks", encounterRaidMarks)
                        OGRH.SVM.Set("encounterAssignmentNumbers", encounterAssignmentNumbers)
                        OGRH.SVM.Set("encounterAnnouncements", encounterAnnouncements)
                    
                    elseif change.operation == "REORDER" and change.details and change.details.raidName and change.details.encounterName and change.details.oldPosition and change.details.newPosition then
                        -- Reorder encounter in list
                        local raidName = change.details.raidName
                        local encounterName = change.details.encounterName
                        local oldPos = change.details.oldPosition
                        local newPos = change.details.newPosition
                        
                        -- Get encounterMgmt from SVM
                        local encounterMgmt = OGRH.SVM.Get("encounterMgmt") or {raids = {}, roles = {}}
                        
                        -- Find raid
                        local raidObj = nil
                        for i = 1, table.getn(encounterMgmt.raids) do
                            if encounterMgmt.raids[i].name == raidName then
                                raidObj = encounterMgmt.raids[i]
                                break
                            end
                        end
                        
                        if raidObj and raidObj.encounters then
                            -- Find encounter by name and verify position
                            local encounterIndex = nil
                            for i = 1, table.getn(raidObj.encounters) do
                                if raidObj.encounters[i].name == encounterName then
                                    encounterIndex = i
                                    break
                                end
                            end
                            
                            if encounterIndex and encounterIndex == oldPos then
                                -- Swap elements
                                local temp = raidObj.encounters[newPos]
                                raidObj.encounters[newPos] = raidObj.encounters[oldPos]
                                raidObj.encounters[oldPos] = temp
                            end
                        end
                        
                        -- Save back to SVM
                        OGRH.SVM.Set("encounterMgmt", encounterMgmt)
                    end
                    
                elseif change.structureType == "ROLE" then
                    -- Role CRUD operations (requires raid and encounter context)
                    if not change.details or not change.details.raidName or not change.details.encounterName then
                        return
                    end
                    
                    -- Get encounterMgmt from SVM
                    local encounterMgmt = OGRH.SVM.Get("encounterMgmt") or {raids = {}, roles = {}}
                    if not encounterMgmt.roles then encounterMgmt.roles = {} end
                    if not encounterMgmt.roles[change.details.raidName] then 
                        encounterMgmt.roles[change.details.raidName] = {} 
                    end
                    if not encounterMgmt.roles[change.details.raidName][change.details.encounterName] then 
                        encounterMgmt.roles[change.details.raidName][change.details.encounterName] = {column1 = {}, column2 = {}} 
                    end
                    
                    local encounterRoles = encounterMgmt.roles[change.details.raidName][change.details.encounterName]
                    if not encounterRoles.column1 then encounterRoles.column1 = {} end
                    if not encounterRoles.column2 then encounterRoles.column2 = {} end
                    
                    if change.operation == "ADD" and change.details.roleName and change.details.roleId then
                        -- Add role to appropriate column
                        local targetColumn = (change.details.column == 2) and encounterRoles.column2 or encounterRoles.column1
                        
                        -- Check if role already exists (by roleId)
                        local exists = false
                        for i = 1, table.getn(targetColumn) do
                            if targetColumn[i].roleId == change.details.roleId then
                                exists = true
                                break
                            end
                        end
                        
                        if not exists then
                            table.insert(targetColumn, {
                                name = change.details.roleName,
                                roleId = change.details.roleId,
                                slots = 1,
                                fillOrder = change.details.roleId
                            })
                        end
                        
                    elseif change.operation == "DELETE" and change.details.roleId then
                        -- Delete role from appropriate column
                        local targetColumn = (change.details.column == 2) and encounterRoles.column2 or encounterRoles.column1
                        
                        for i = 1, table.getn(targetColumn) do
                            if targetColumn[i].roleId == change.details.roleId then
                                table.remove(targetColumn, i)
                                break
                            end
                        end
                        
                    elseif change.operation == "RENAME" and change.details.roleId and change.details.oldName and change.details.newName then
                        -- Rename role (search both columns)
                        local allColumns = {encounterRoles.column1, encounterRoles.column2}
                        
                        for _, column in ipairs(allColumns) do
                            for i = 1, table.getn(column) do
                                if column[i].roleId == change.details.roleId then
                                    column[i].name = change.details.newName
                                    break
                                end
                            end
                        end
                        
                    elseif change.operation == "REORDER" and change.details.roleId and change.details.oldPosition and change.details.newPosition then
                        -- Reorder within column
                        local targetColumn = (change.details.column == 2) and encounterRoles.column2 or encounterRoles.column1
                        
                        -- Find role by ID and move it
                        local roleToMove = nil
                        local currentIndex = nil
                        for i = 1, table.getn(targetColumn) do
                            if targetColumn[i].roleId == change.details.roleId then
                                roleToMove = targetColumn[i]
                                currentIndex = i
                                break
                            end
                        end
                        
                        if roleToMove and currentIndex then
                            table.remove(targetColumn, currentIndex)
                            table.insert(targetColumn, change.details.newPosition, roleToMove)
                        end
                        
                    elseif change.operation == "MOVE_COLUMN" and change.details.roleId and change.details.fromColumn and change.details.toColumn then
                        -- Move role between columns
                        local fromColumn = (change.details.fromColumn == 2) and encounterRoles.column2 or encounterRoles.column1
                        local toColumn = (change.details.toColumn == 2) and encounterRoles.column2 or encounterRoles.column1
                        
                        -- Find and remove from source column
                        local roleToMove = nil
                        for i = 1, table.getn(fromColumn) do
                            if fromColumn[i].roleId == change.details.roleId then
                                roleToMove = fromColumn[i]
                                table.remove(fromColumn, i)
                                break
                            end
                        end
                        
                        -- Add to target column
                        if roleToMove then
                            table.insert(toColumn, roleToMove)
                        end
                        
                    elseif change.operation == "UPDATE" and change.details.roleId and change.details.roleData then
                        -- Update role properties (search both columns)
                        local allColumns = {encounterRoles.column1, encounterRoles.column2}
                        
                        for _, column in ipairs(allColumns) do
                            for i = 1, table.getn(column) do
                                if column[i].roleId == change.details.roleId then
                                    -- Update all properties from roleData
                                    local role = column[i]
                                    local newData = change.details.roleData
                                    
                                    role.name = newData.name or role.name
                                    role.slots = newData.slots or role.slots
                                    role.fillOrder = newData.fillOrder or role.fillOrder
                                    role.isConsumeCheck = newData.isConsumeCheck
                                    role.isCustomModule = newData.isCustomModule
                                    role.roleType = newData.roleType
                                    role.invertFillOrder = newData.invertFillOrder
                                    role.linkRole = newData.linkRole
                                    role.showRaidIcons = newData.showRaidIcons
                                    role.showAssignment = newData.showAssignment
                                    role.markPlayer = newData.markPlayer
                                    role.allowOtherRoles = newData.allowOtherRoles
                                    role.defaultRoles = newData.defaultRoles
                                    role.classes = newData.classes
                                    role.modules = newData.modules
                                    
                                    break
                                end
                            end
                        end
                    end
                end
                
                -- Save encounterMgmt back to SVM after role operations
                OGRH.SVM.Set("encounterMgmt", encounterMgmt)
            
            elseif change.type == "SETTINGS" then
                -- Apply settings changes (raid or encounter advanced settings)
                local encounterMgmt = OGRH.SVM.Get("encounterMgmt") or {raids = {}, roles = {}}
                if not encounterMgmt.raids then return end
                
                if not change.raidName or not change.settings then
                    return
                end
                
                -- Find raid
                local raidObj = nil
                for i = 1, table.getn(encounterMgmt.raids) do
                    if encounterMgmt.raids[i].name == change.raidName then
                        raidObj = encounterMgmt.raids[i]
                        break
                    end
                end
                
                if not raidObj then return end
                
                if not change.encounterName then
                    -- Raid-level settings
                    OGRH.EnsureRaidAdvancedSettings(raidObj)
                    raidObj.advancedSettings = change.settings
                else
                    -- Encounter-level settings
                    local encounterObj = nil
                    if raidObj.encounters then
                        for i = 1, table.getn(raidObj.encounters) do
                            if raidObj.encounters[i].name == change.encounterName then
                                encounterObj = raidObj.encounters[i]
                                break
                            end
                        end
                    end
                    
                    if encounterObj then
                        OGRH.EnsureEncounterAdvancedSettings(raidObj, encounterObj)
                        encounterObj.advancedSettings = change.settings
                    end
                end
                
                -- Save back to SVM
                OGRH.SVM.Set("encounterMgmt", encounterMgmt)
            
            elseif change.type == "CLASSPRIORITY" then
                -- Apply class priority changes (slot-level class priority and role flags)
                local encounterMgmt = OGRH.SVM.Get("encounterMgmt") or {raids = {}, roles = {}}
                if not encounterMgmt.roles then return end
                
                if not change.raidName or not change.encounterName or not change.roleIndex or not change.slotIndex then
                    return
                end
                
                -- Find role in encounterMgmt.roles structure
                if not encounterMgmt.roles[change.raidName] then return end
                if not encounterMgmt.roles[change.raidName][change.encounterName] then return end
                
                local encounterRoles = encounterMgmt.roles[change.raidName][change.encounterName]
                local column1 = encounterRoles.column1 or {}
                local column2 = encounterRoles.column2 or {}
                
                -- Build complete roles list using stable roleId
                local allRoles = {}
                for i = 1, table.getn(column1) do
                    table.insert(allRoles, column1[i])
                end
                for i = 1, table.getn(column2) do
                    table.insert(allRoles, column2[i])
                end
                
                -- Find the role by roleIndex (using stable roleId)
                local targetRole = nil
                for i = 1, table.getn(allRoles) do
                    if allRoles[i].roleId == change.roleIndex then
                        targetRole = allRoles[i]
                        break
                    end
                end
                
                if not targetRole then return end
                
                -- Initialize classPriority structure if needed
                if not targetRole.classPriority then
                    targetRole.classPriority = {}
                end
                
                -- Apply class priority array
                targetRole.classPriority[change.slotIndex] = change.classPriority or {}
                
                -- Apply class priority roles (hybrid class role flags)
                if change.classPriorityRoles then
                    if not targetRole.classPriorityRoles then
                        targetRole.classPriorityRoles = {}
                    end
                    targetRole.classPriorityRoles[change.slotIndex] = change.classPriorityRoles
                end
                
                -- Save encounterMgmt back to SVM after class priority changes
                OGRH.SVM.Set("encounterMgmt", encounterMgmt)
            end
        end
    
        -- Update Class Priority dialog if open (must be done after all changes applied)
        local classPriorityDialog = OGRH_ClassPriorityFrame
        if classPriorityDialog and classPriorityDialog:IsShown() then
            -- Check if any CLASSPRIORITY changes occurred for the currently viewed role/slot
            local needsClassPriorityRefresh = false
            for i = 1, table.getn(deltaData.changes) do
                local change = deltaData.changes[i]
                if change.type == "CLASSPRIORITY" then
                    -- Check if this change is for the currently viewed role/slot
                    if change.raidName == classPriorityDialog.raidName and
                       change.encounterName == classPriorityDialog.encounterName and
                       change.roleIndex == classPriorityDialog.roleIndex and
                       change.slotIndex == classPriorityDialog.slotIndex then
                        needsClassPriorityRefresh = true
                        break
                    end
                end
            end
            
            if needsClassPriorityRefresh and OGRH.ShowClassPriorityDialog then
                -- Refresh the dialog by calling ShowClassPriorityDialog with current context
                OGRH.ShowClassPriorityDialog(
                    classPriorityDialog.raidName,
                    classPriorityDialog.encounterName,
                    classPriorityDialog.roleIndex,
                    classPriorityDialog.slotIndex,
                    classPriorityDialog.roleData,
                    classPriorityDialog.refreshCallback
                )
            end
        end
        
        -- Update Advanced Settings dialog if open (must be done after all changes applied)
        local advancedDialog = OGRH_AdvancedSettingsFrame
        if advancedDialog and advancedDialog:IsShown() then
            -- Check if any SETTINGS changes occurred for the currently viewed raid/encounter
            local needsAdvancedRefresh = false
            local encounterFrame = OGRH_EncounterFrame
            if encounterFrame then
                for i = 1, table.getn(deltaData.changes) do
                    local change = deltaData.changes[i]
                    if change.type == "SETTINGS" then
                        -- Check if this SETTINGS change is for the currently viewed raid/encounter
                        if advancedDialog.isRaidMode then
                            -- Raid mode: refresh if change is for selected raid and no encounter specified
                            if change.raidName == encounterFrame.selectedRaid and not change.encounterName then
                                needsAdvancedRefresh = true
                                break
                            end
                        else
                            -- Encounter mode: refresh if change is for selected raid+encounter
                            if change.raidName == encounterFrame.selectedRaid and 
                               change.encounterName == encounterFrame.selectedEncounter then
                                needsAdvancedRefresh = true
                                break
                            end
                        end
                    end
                end
            end
            
            if needsAdvancedRefresh and OGRH.ShowAdvancedSettingsDialog then
                -- Refresh the dialog by calling ShowAdvancedSettingsDialog with the current mode
                local mode = advancedDialog.isRaidMode and "raid" or "encounter"
                OGRH.ShowAdvancedSettingsDialog(mode)
            end
        end
        
        -- Update Encounter Planning UI if open (must be done after all changes applied)
        local encounterFrame = OGRH_EncounterFrame or _G["OGRH_EncounterFrame"]
        if encounterFrame and encounterFrame:IsShown() then
            -- Check if any STRUCTURE changes occurred
            local hasStructureChanges = false
            for i = 1, table.getn(deltaData.changes) do
                if deltaData.changes[i].type == "STRUCTURE" then
                    hasStructureChanges = true
                    break
                end
            end
            
            -- If structure changed, refresh raids/encounters/roles lists
            if hasStructureChanges then
                if encounterFrame.RefreshRaidsList then
                    encounterFrame.RefreshRaidsList()
                end
                if encounterFrame.RefreshEncountersList then
                    encounterFrame.RefreshEncountersList()
                end
            end
            
            -- Refresh role containers (includes assignments, marks, numbers, and announcements)
            if encounterFrame.RefreshRoleContainers then
                encounterFrame.RefreshRoleContainers()
            end
            
            -- Also refresh announcement EditBoxes specifically if they exist and the change affects current selection
            if encounterFrame.announcementLines and encounterFrame.selectedRaid and encounterFrame.selectedEncounter then
                for i = 1, table.getn(deltaData.changes) do
                    local change = deltaData.changes[i]
                    if change.type == "ASSIGNMENT" and change.assignmentType == "ANNOUNCEMENT" and change.newValue and change.newValue.announcementData then
                        local announcementData = change.newValue.announcementData
                        -- Only update if this announcement is for the currently selected encounter
                        if announcementData.raid == encounterFrame.selectedRaid and 
                           announcementData.encounter == encounterFrame.selectedEncounter then
                            local lineIndex = announcementData.lineIndex
                            if lineIndex and lineIndex >= 1 and lineIndex <= table.getn(encounterFrame.announcementLines) then
                                encounterFrame.announcementLines[lineIndex]:SetText(change.newValue.text or "")
                            end
                        end
                    end
                end
            end
        end
        
        -- Update Encounter Setup UI if open
        local setupFrame = OGRH_EncounterSetupFrame or _G["OGRH_EncounterSetupFrame"]
        if setupFrame and setupFrame:IsShown() then
            -- Check if any STRUCTURE changes occurred
            local hasStructureChanges = false
            for i = 1, table.getn(deltaData.changes) do
                if deltaData.changes[i].type == "STRUCTURE" then
                    hasStructureChanges = true
                    break
                end
            end
            
            -- If structure changed, refresh all lists
            if hasStructureChanges then
                if setupFrame.RefreshRaidsList then
                    setupFrame.RefreshRaidsList()
                end
                if setupFrame.RefreshEncountersList then
                    setupFrame.RefreshEncountersList()
                end
                if setupFrame.RefreshRolesList then
                    setupFrame.RefreshRolesList()
                end
            end
        end
        
        -- Update RolesUI if open
        local rolesFrame = OGRH.rolesFrame or _G["OGRH_RolesFrame"]
        if rolesFrame and rolesFrame:IsShown() and rolesFrame.UpdatePlayerLists then
            rolesFrame.UpdatePlayerLists()
        end
        
        -- Update data version if provided
        if deltaData.version and OGRH.Versioning and OGRH.Versioning.UpdateDataVersion then
            OGRH.Versioning.UpdateDataVersion("SYNC", deltaData.version)
        end
    end)
    
    OGRH.MessageRouter.RegisterHandler(OGRH.MessageTypes.ASSIGN.DELTA_PLAYER, function(sender, data, channel)
        -- Handle individual player assignment delta (for backwards compatibility)
        -- Data already deserialized by OGAddonMsg
        local changeData = data
        if not changeData then return end
        
        OGRH.SetPlayerAssignment(changeData.player, {
            type = changeData.assignmentType,
            value = changeData.newValue
        })
    end)
    
    OGRH.MessageRouter.RegisterHandler(OGRH.MessageTypes.ASSIGN.DELTA_ROLE, function(sender, data, channel)
        -- Handle individual role delta (modern format only)
        -- Data already deserialized by OGAddonMsg
        local changeData = data
        
        if not changeData or not changeData.player or not changeData.newValue then
            return
        end
        
        local roles = OGRH.SVM.Get("roles") or {}
        roles[changeData.player] = changeData.newValue
        OGRH.SVM.Set("roles", roles)
        
        -- Update UI if open
        local frame = OGRH.rolesFrame or _G["OGRH_RolesFrame"]
        if frame and frame:IsShown() and frame.RefreshColumnDisplays then
            frame.RefreshColumnDisplays()
        end
    end)
    
    OGRH.MessageRouter.RegisterHandler(OGRH.MessageTypes.ASSIGN.DELTA_GROUP, function(sender, data, channel)
        -- Handle individual group delta
        -- Data already deserialized by OGAddonMsg
        local changeData = data
        if not changeData then return end
        
        -- Placeholder for group assignment feature
    end)

    -- Item 10: Addon Poll (version/checksum detection for raid lead selection)
    OGRH.MessageRouter.RegisterHandler(OGRH.MessageTypes.ADMIN.POLL_VERSION, function(sender, data, channel)
        -- Don't respond to our own poll (we add ourselves manually in PollAddonUsers)
        local playerName = UnitName("player")
        if sender == playerName then
            return
        end
        
        -- Only respond if in a raid
        if GetNumRaidMembers() == 0 then
            return
        end
        
        -- Randomize response delay 0-2 seconds to spread out 40 raid member responses
        local delay = math.random() * 2
        OGRH.ScheduleFunc(function()
            -- Calculate checksum for ALL structure data
            local checksum = "0"
            if OGRH.CalculateAllStructureChecksum then
                checksum = OGRH.CalculateAllStructureChecksum()
            end
            
            -- Send response with version and checksum
            local response = {
                version = OGRH.VERSION,
                tocVersion = OGRH.TOC_VERSION,
                checksum = checksum
            }
            OGRH.MessageRouter.Broadcast(OGRH.MessageTypes.ADMIN.POLL_RESPONSE, response)
        end, delay)
    end)

    OGRH.MessageRouter.RegisterHandler(OGRH.MessageTypes.ADMIN.POLL_RESPONSE, function(sender, data, channel)
        if OGRH.HandleAddonPollResponse then
            local version = data.version or "Unknown"
            local checksum = data.checksum or "0"
            local tocVersion = data.tocVersion or version
            OGRH.HandleAddonPollResponse(sender, version, checksum, tocVersion)
        end
    end)

    -- Item 11: Raid Admin/Lead Change Notification
    OGRH.MessageRouter.RegisterHandler(OGRH.MessageTypes.STATE.CHANGE_LEAD, function(sender, data, channel)
        if OGRH.SetRaidAdmin then
            local adminName = data.adminName
            if adminName then
                -- Pass true to suppress re-broadcast (we're receiving from network)
                OGRH.SetRaidAdmin(adminName, true)
            end
        end
    end)
    
    -- Auto-Promote Request Handler
    OGRH.MessageRouter.RegisterHandler(OGRH.MessageTypes.ADMIN.PROMOTE_REQUEST, function(sender, data, channel)
        -- Only process if we are the raid leader
        if not IsRaidLeader or IsRaidLeader() ~= 1 then
            return
        end
        
        local playerToPromote = data.playerName
        if not playerToPromote or playerToPromote == "" then
            return
        end
        
        -- Find the player in the raid and promote them
        local numRaid = GetNumRaidMembers()
        for i = 1, numRaid do
            local name, rank = GetRaidRosterInfo(i)
            if name == playerToPromote and rank == 0 then
                PromoteToAssistant(playerToPromote)
                OGRH.Msg(string.format("|cff00ccffOGRH:|r Auto-promoted %s to assistant (requested by %s).", playerToPromote, sender))
                break
            end
        end
    end)
    
    -- More handlers will be added in future phases
end

--[[
    Debug Commands
]]

-- Debug: Print registered handlers
function OGRH.MessageRouter.DebugPrintHandlers()
    OGRH.Msg("|cff00ccff[OGRH] === Registered Message Handlers ===")
    
    local count = 0
    for messageType, handler in pairs(OGRH.MessageRouter.State.handlers) do
        OGRH.Msg(string.format("|cff00ccff[OGRH]   %s", messageType))
        count = count + 1
    end
    
    OGRH.Msg(string.format("|cff00ccff[OGRH] Total: %d handlers", count))
    OGRH.Msg("|cff00ccff[OGRH] === End Handlers ===")
end

-- Debug: Print recent received messages
function OGRH.MessageRouter.DebugPrintReceivedMessages()
    OGRH.Msg("|cff00ccff[OGRH] === Recent Received Messages ===")
    
    if table.getn(OGRH.MessageRouter.State.receivedMessages) == 0 then
        OGRH.Msg("|cff00ccff[OGRH] No messages received")
    else
        for i = 1, table.getn(OGRH.MessageRouter.State.receivedMessages) do
            OGRH.Msg(string.format("|cff00ccff[OGRH]   %s", OGRH.MessageRouter.State.receivedMessages[i]))
        end
    end
    
    OGRH.Msg("|cff00ccff[OGRH] === End Messages ===")
end

OGRH.Msg("|cff00ccff[RH-MessageRouter]|r Loaded")
