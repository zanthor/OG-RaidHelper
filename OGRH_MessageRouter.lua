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
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[RH-MessageRouter]|r Invalid handler registration")
        return false
    end
    
    if not OGRH.IsValidMessageType(messageType) then
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff8800[RH-MessageRouter]|r Registering unknown message type: %s", messageType))
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
function OGRH.MessageRouter.Send(messageType, data, options)
    if not messageType then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[RH-MessageRouter]|r No message type specified")
        return nil
    end
    
    -- Validate message type
    if not OGRH.IsValidMessageType(messageType) then
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff8800[RH-MessageRouter]|r Sending unknown message type: %s", messageType))
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
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[RH-MessageRouter]|r OGAddonMsg not available")
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
function OGRH.MessageRouter.SendTo(targetPlayer, messageType, data, options)
    options = options or {}
    options.target = targetPlayer
    options.channel = "WHISPER"
    
    return OGRH.MessageRouter.Send(messageType, data, options)
end

-- Broadcast a message to all raid/party members
function OGRH.MessageRouter.Broadcast(messageType, data, options)
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
    
    -- Validate message type
    if not messageType then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff8800[RH-MessageRouter]|r Received message with no type")
        return
    end
    
    -- Check for legacy message format and translate
    local translatedType = OGRH.TranslateLegacyMessage(messageType)
    if translatedType then
        messageType = translatedType
    end
    
    -- Get handler for this message type
    local handler = OGRH.MessageRouter.GetHandler(messageType)
    
    if not handler then
        -- No handler registered - this is normal for some message types
        -- OGRH.Debug(string.format("MessageRouter: No handler for %s", messageType))
        return
    end
    
    -- Call the handler
    local success, err = pcall(handler, sender, data, channel)
    
    if not success then
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff0000[RH-MessageRouter]|r Handler error for %s: %s", messageType, tostring(err)))
    end
end

--[[
    OGAddonMsg Integration
]]

-- Initialize OGAddonMsg message listener
function OGRH.MessageRouter.InitializeOGAddonMsg()
    if not OGAddonMsg or not OGAddonMsg.RegisterWildcard then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[RH-MessageRouter]|r OGAddonMsg not available for initialization")
        return false
    end
    
    -- Register a wildcard handler for all messages
    OGAddonMsg.RegisterWildcard(function(sender, prefix, data, channel)
        -- Only process OGRH messages
        if string.sub(prefix, 1, 5) == "OGRH_" then
            OGRH.MessageRouter.OnMessageReceived(sender, prefix, data, channel)
        end
    end)
    
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[RH-MessageRouter]|r Registered wildcard handler with OGAddonMsg")
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
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff8800[RH-MessageRouter]|r Untranslated legacy message: %s", messageType))
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
        DEFAULT_CHAT_FRAME:AddMessage("|cffff8800[RH-MessageRouter]|r Already initialized")
        return false
    end
    
    -- Initialize OGAddonMsg integration
    if not OGRH.MessageRouter.InitializeOGAddonMsg() then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[RH-MessageRouter]|r Failed to initialize OGAddonMsg")
        return false
    end
    
    -- Register default handlers (will be expanded in future phases)
    OGRH.MessageRouter.RegisterDefaultHandlers()
    
    OGRH.MessageRouter.State.isInitialized = true
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[RH-MessageRouter]|r Initialized")
    
    return true
end

-- Register default message handlers
function OGRH.MessageRouter.RegisterDefaultHandlers()
    -- ADMIN messages
    OGRH.MessageRouter.RegisterHandler(OGRH.MessageTypes.ADMIN.TAKEOVER, function(sender, data, channel)
        if data and data.newAdmin then
            OGRH.SetRaidAdmin(data.newAdmin)
            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[RH]|r %s is now the raid admin", data.newAdmin))
        end
    end)
    
    OGRH.MessageRouter.RegisterHandler(OGRH.MessageTypes.ADMIN.ASSIGN, function(sender, data, channel)
        if data and data.newAdmin then
            OGRH.SetRaidAdmin(data.newAdmin)
            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[RH]|r %s assigned %s as raid admin", data.assignedBy or sender, data.newAdmin))
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
    
    -- More handlers will be added in future phases
end

--[[
    Debug Commands
]]

-- Debug: Print registered handlers
function OGRH.MessageRouter.DebugPrintHandlers()
    DEFAULT_CHAT_FRAME:AddMessage("[OGRH] === Registered Message Handlers ===")
    
    local count = 0
    for messageType, handler in pairs(OGRH.MessageRouter.State.handlers) do
        DEFAULT_CHAT_FRAME:AddMessage(string.format("[OGRH]   %s", messageType))
        count = count + 1
    end
    
    DEFAULT_CHAT_FRAME:AddMessage(string.format("[OGRH] Total: %d handlers", count))
    DEFAULT_CHAT_FRAME:AddMessage("[OGRH] === End Handlers ===")
end

-- Debug: Print recent received messages
function OGRH.MessageRouter.DebugPrintReceivedMessages()
    DEFAULT_CHAT_FRAME:AddMessage("[OGRH] === Recent Received Messages ===")
    
    if table.getn(OGRH.MessageRouter.State.receivedMessages) == 0 then
        DEFAULT_CHAT_FRAME:AddMessage("[OGRH] No messages received")
    else
        for i = 1, table.getn(OGRH.MessageRouter.State.receivedMessages) do
            DEFAULT_CHAT_FRAME:AddMessage(string.format("[OGRH]   %s", OGRH.MessageRouter.State.receivedMessages[i]))
        end
    end
    
    DEFAULT_CHAT_FRAME:AddMessage("[OGRH] === End Messages ===")
end

DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[RH-MessageRouter]|r Loaded")
