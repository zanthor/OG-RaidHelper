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
    isInitialized = false,      -- Initialization flag
    syncVersionWarned = {}      -- [senderName] = true  (one warning per sender per session)
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
    
    -- Inject SyncVersion into the OGAddonMsg prefix
    -- "OGRH_ADMIN_QUERY" → "OGRH00_ADMIN_QUERY"  (version inserted after "OGRH")
    local versionedType = "OGRH" .. OGRH.SYNC_VERSION .. string.sub(messageType, 5)
    
    -- Send via OGAddonMsg
    local msgId = OGAddonMsg.Send(channel, target, versionedType, data, {
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
        -- Only process OGRH messages (prefix starts with "OGRH")
        if string.sub(prefix, 1, 4) ~= "OGRH" then
            return
        end
        
        -- Extract SyncVersion (2 hex chars after "OGRH", before the underscore)
        -- Versioned format: "OGRH00_ADMIN_QUERY"  (positions 5-6 = version)
        -- Legacy format:    "OGRH_ADMIN_QUERY"    (position 5 = underscore)
        local incomingVersion = string.sub(prefix, 5, 6)
        
        if incomingVersion ~= OGRH.SYNC_VERSION then
            -- Version mismatch — warn once per sender, then silently drop
            if not OGRH.MessageRouter.State.syncVersionWarned[sender] then
                OGRH.MessageRouter.State.syncVersionWarned[sender] = true
                OGRH.Msg(string.format(
                    "|cffff6600[RH-MessageRouter]|r Ignoring traffic from %s (SyncVersion '%s' ~= ours '%s')",
                    sender, tostring(incomingVersion), OGRH.SYNC_VERSION))
            end
            if OGRH.SyncIntegrity and OGRH.SyncIntegrity.State.debug then
                OGRH.Msg(string.format("|cffff6600[RH-MessageRouter][DEBUG]|r REJECTED sender=%s, prefix=%s (v '%s' ~= '%s')",
                    tostring(sender), tostring(prefix), tostring(incomingVersion), OGRH.SYNC_VERSION))
            end
            return
        end
        
        -- Strip version from prefix: "OGRH00_ADMIN_QUERY" → "OGRH_ADMIN_QUERY"
        local cleanPrefix = "OGRH" .. string.sub(prefix, 7)
        
        if OGRH.SyncIntegrity and OGRH.SyncIntegrity.State.debug then
            OGRH.Msg(string.format("|cff00ccff[RH-MessageRouter][DEBUG]|r ACCEPTED sender=%s, msg=%s, channel=%s",
                tostring(sender), tostring(cleanPrefix), tostring(channel)))
        end
        
        OGRH.MessageRouter.OnMessageReceived(sender, cleanPrefix, data, channel)
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
        
        -- Part 2: Discovery roll-call - OTHER OGRH clients respond
        -- Skip if this is our own echo (WoW echoes broadcasts back to sender).
        -- The querier doesn't know who admin is, so self-responses would pollute
        -- AdminDiscovery.responses and prevent correct sole-user detection.
        if sender == UnitName("player") then return end
        
        -- Respond immediately (no stagger delay). ADMIN.RESPONSE is a small,
        -- critical protocol message that must arrive within the 5s collection window.
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
        
        OGRH.MessageRouter.Broadcast(OGRH.MessageTypes.ADMIN.RESPONSE, {
            purpose = "discovery",
            playerName = playerName,
            rank = rank,
            isCurrentAdmin = (currentAdmin ~= nil and currentAdmin == playerName),
            knownAdmin = currentAdmin,  -- Who this client believes is admin (may differ from self)
            version = OGRH.VERSION
        }, {priority = "HIGH"})
    end)
    
    OGRH.MessageRouter.RegisterHandler(OGRH.MessageTypes.ADMIN.RESPONSE, function(sender, data, channel)
        if not data then return end
        
        -- Ignore our own echoed responses (WoW echoes broadcasts back)
        -- Our own ADMIN.RESPONSE would have our name and our admin state,
        -- which we already know. Only other clients' responses matter.
        if sender == UnitName("player") then return end
        
        -- Handle discovery roll-call responses
        if data.purpose == "discovery" then
            -- Feed into AdminDiscovery if active
            if OGRH.AdminDiscovery and OGRH.AdminDiscovery.active then
                OGRH.AdminDiscovery.AddResponse(
                    data.playerName or sender,
                    data.rank or 0,
                    data.isCurrentAdmin or false,
                    data.knownAdmin  -- Who this responder believes is admin
                )
            end
            
            -- If sender claims to be current admin, accept immediately
            -- This short-circuits discovery for the common case (self is admin)
            if data.isCurrentAdmin then
                local adminName = data.playerName or sender
                OGRH.SetRaidAdmin(adminName, true)  -- suppress broadcast (we received it)
                if OGRH.AdminDiscovery then
                    OGRH.AdminDiscovery.Cancel()
                end
                return
            end
            
            -- If sender reports who they believe is admin (e.g., Conrii knows Tankmedady is admin),
            -- accept that as well — short-circuits for the common case (admin reloaded)
            if data.knownAdmin and data.knownAdmin ~= "" then
                OGRH.SetRaidAdmin(data.knownAdmin, true)  -- suppress broadcast
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
            checksum = OGRH.SyncChecksum and OGRH.SyncChecksum.CalculateAllStructureChecksum and tostring(OGRH.SyncChecksum.CalculateAllStructureChecksum()) or "UNKNOWN"
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
    
    OGRH.MessageRouter.RegisterHandler(OGRH.MessageTypes.ADMIN.LOOT_REQUEST, function(sender, data, channel)
        if IsRaidLeader and IsRaidLeader() == 1 then
            if data and data.method then
                OGRH.ExecuteLootSettings(data.method, data.mlName, data.thresholdValue)
            end
        end
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
    -- Delegates to SVM.OnBatchReceived which handles the {updates: [{path, value}]} format
    -- that SVM.FlushBatch() actually produces. The previous handler expected a "changes" field
    -- with typed domain objects (SWAP, ROLE, ASSIGNMENT, etc.) that no producer ever created,
    -- causing all BATCH delta messages to be silently dropped and triggering unnecessary 
    -- granular repairs when the next checksum poll detected the resulting mismatches.
    OGRH.MessageRouter.RegisterHandler(OGRH.MessageTypes.ASSIGN.DELTA_BATCH, function(sender, data, channel)
        if OGRH.SVM and OGRH.SVM.OnBatchReceived then
            OGRH.SVM.OnBatchReceived(sender, data, channel)
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
