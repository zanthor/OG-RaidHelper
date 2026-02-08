--[[
    _OGAALogger - Public API
    
    Public interface for embedding the logger in other addons.
    Similar to _OGAddonMsg embedding pattern.
]]

--[[
    Add a message to the log programmatically
    
    @param source (string) - Source addon/system name
    @param message (string) - Pre-formatted message text (can include color codes)
]]
function OGAALogger.AddMessage(source, message)
    OGAALogger.CaptureMessage(source, message)
end

--[[
    Clear all logged messages
]]
function OGAALogger.Clear()
    OGAALogger.ClearMessages()
end

--[[
    Get all logged messages
    
    @return (table) - Array of message objects with fields:
                      - timestamp (string)
                      - source (string)
                      - text (string)
                      - r, g, b (number)
]]
function OGAALogger.GetMessages()
    return OGAALogger.State.messages
end

--[[
    Get the number of messages currently logged
    
    @return (number) - Message count
]]
function OGAALogger.GetMessageCount()
    return table.getn(OGAALogger.State.messages)
end

--[[
    Get the maximum message limit
    
    @return (number) - Max messages
]]
function OGAALogger.GetMaxMessages()
    return OGAALogger.State.maxMessages
end

--[[
    Set the maximum message limit
    
    @param max (number) - New maximum (min: 50, max: 5000)
]]
function OGAALogger.SetMaxMessages(max)
    if type(max) ~= "number" or max < 50 or max > 5000 then
        return
    end
    
    OGAALogger.State.maxMessages = max
    
    -- Enforce new limit
    while table.getn(OGAALogger.State.messages) > OGAALogger.State.maxMessages do
        table.remove(OGAALogger.State.messages)
    end
    
    -- Update UI if open
    if OGAALogger.UI and OGAALogger.UI.IsShown() then
        OGAALogger.UI.Refresh()
    end
end

--[[
    Export messages as plain text
    
    @return (string) - Formatted log text
]]
function OGAALogger.ExportText()
    local messages = OGAALogger.GetMessages()
    local lines = {}
    
    for i = 1, table.getn(messages) do
        local msg = messages[i]
        
        if msg.isSessionMarker then
            table.insert(lines, msg.text)
        else
            table.insert(lines, string.format("[%s] [%s] %s", 
                msg.timestamp, 
                msg.source, 
                msg.text))
        end
    end
    
    return table.concat(lines, "\n")
end

--[[
    Check if the logger is initialized
    
    @return (boolean) - True if initialized
]]
function OGAALogger.IsInitialized()
    return OGAALogger.State.initialized
end

--[[
    Get current session count
    
    @return (number) - Session count
]]
function OGAALogger.GetSessionCount()
    return OGAALogger.State.sessionCount
end

-- Expose key functions as aliases (for embedding compatibility)
_G["OGAALogger_AddMessage"] = OGAALogger.AddMessage
_G["OGAALogger_Clear"] = OGAALogger.Clear
_G["OGAALogger_Show"] = OGAALogger.Show
_G["OGAALogger_Hide"] = OGAALogger.Hide
_G["OGAALogger_Toggle"] = OGAALogger.Toggle
_G["OGAALogger_GetMessages"] = OGAALogger.GetMessages
_G["OGAALogger_RegisterAddon"] = OGAALogger.RegisterAddon
_G["OGAALogger_UnregisterAddon"] = OGAALogger.UnregisterAddon
_G["OGAALogger_GetRegisteredAddons"] = OGAALogger.GetRegisteredAddons
