--[[
    OGAddonMsg - Handlers
    Callback registration and message dispatching
]]

-- Initialize handlers
OGAddonMsg.handlers = {
    byPrefix = {},      -- [prefix] = {handlerId = callback, ...}
    wildcard = {},      -- [handlerId] = callback
    nextId = 1
}

--[[
    Handler Registration
]]
function OGAddonMsg.RegisterHandler(prefix, callback)
    if not prefix or not callback then
        return nil
    end
    
    if not OGAddonMsg.handlers.byPrefix[prefix] then
        OGAddonMsg.handlers.byPrefix[prefix] = {}
    end
    
    local handlerId = OGAddonMsg.handlers.nextId
    OGAddonMsg.handlers.nextId = OGAddonMsg.handlers.nextId + 1
    
    OGAddonMsg.handlers.byPrefix[prefix][handlerId] = callback
    
    if OGAddonMsg_Config.debug then
        DEFAULT_CHAT_FRAME:AddMessage(
            string.format("OGAddonMsg: Registered handler %d for prefix '%s'", handlerId, prefix),
            0.5, 1, 0.5
        )
    end
    
    return handlerId
end

function OGAddonMsg.UnregisterHandler(handlerId)
    -- Remove from byPrefix
    for prefix, handlers in pairs(OGAddonMsg.handlers.byPrefix) do
        if handlers[handlerId] then
            handlers[handlerId] = nil
            
            if OGAddonMsg_Config.debug then
                DEFAULT_CHAT_FRAME:AddMessage(
                    string.format("OGAddonMsg: Unregistered handler %d", handlerId),
                    0.5, 1, 0.5
                )
            end
            return true
        end
    end
    
    -- Remove from wildcard
    if OGAddonMsg.handlers.wildcard[handlerId] then
        OGAddonMsg.handlers.wildcard[handlerId] = nil
        return true
    end
    
    return false
end

function OGAddonMsg.RegisterWildcard(callback)
    if not callback then
        return nil
    end
    
    local handlerId = OGAddonMsg.handlers.nextId
    OGAddonMsg.handlers.nextId = OGAddonMsg.handlers.nextId + 1
    
    OGAddonMsg.handlers.wildcard[handlerId] = callback
    
    if OGAddonMsg_Config.debug then
        DEFAULT_CHAT_FRAME:AddMessage(
            string.format("OGAddonMsg: Registered wildcard handler %d", handlerId),
            0.5, 1, 0.5
        )
    end
    
    return handlerId
end

--[[
    Message Dispatching
]]
function OGAddonMsg.DispatchToHandlers(sender, prefix, data, channel)
    -- Call handlers registered for this prefix
    if OGAddonMsg.handlers.byPrefix[prefix] then
        for handlerId, callback in pairs(OGAddonMsg.handlers.byPrefix[prefix]) do
            -- Protected call to prevent handler errors from breaking system
            local success, err = pcall(callback, sender, data, channel)
            if not success then
                DEFAULT_CHAT_FRAME:AddMessage(
                    string.format("OGAddonMsg: Handler %d error: %s", handlerId, tostring(err)),
                    1, 0, 0
                )
            end
        end
    end
    
    -- Call wildcard handlers
    for handlerId, callback in pairs(OGAddonMsg.handlers.wildcard) do
        local success, err = pcall(callback, sender, prefix, data, channel)
        if not success then
            DEFAULT_CHAT_FRAME:AddMessage(
                string.format("OGAddonMsg: Wildcard handler %d error: %s", handlerId, tostring(err)),
                1, 0, 0
            )
        end
    end
end
