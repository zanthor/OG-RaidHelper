--[[
    _OGST - Message Router
    
    Routes OGST output to _OGAALogger if available.
]]

OGST = OGST or {}

-- Message routing function
OGST.Msg = function(text)
    if OGAALogger and OGAALogger.AddMessage and type(OGAALogger.AddMessage) == "function" then
        -- Send to OGAALogger with "ST" as source
        local success, err = pcall(OGAALogger.AddMessage, "ST", tostring(text))
        if not success then
            -- Fallback to DEFAULT_CHAT_FRAME on error
            local formattedText = "|cffffff66[ST]|r" .. tostring(text)
            DEFAULT_CHAT_FRAME:AddMessage(formattedText, 1, 1, 0.4)
        end
    else
        -- Fallback to DEFAULT_CHAT_FRAME
        local formattedText = "|cffffff66[ST]|r" .. tostring(text)
        DEFAULT_CHAT_FRAME:AddMessage(formattedText, 1, 1, 0.4)
    end
end

-- Auto-register for error capture
if OGAALogger and OGAALogger.RegisterAddon then
    OGAALogger.RegisterAddon("_OGST")
end
