--[[
    _OGAddonMsg - Message Router
    
    Routes OGAddonMsg output to _OGAALogger if available.
]]

OGAddonMsg = OGAddonMsg or {}

-- Message routing function
OGAddonMsg.Msg = function(text)
    if OGAALogger and OGAALogger.AddMessage and type(OGAALogger.AddMessage) == "function" then
        -- Send to OGAALogger with "AM" as source
        local success, err = pcall(OGAALogger.AddMessage, "AM", tostring(text))
        if not success then
            -- Fallback to DEFAULT_CHAT_FRAME on error
            local formattedText = "|cffcc66ff[AM]|r" .. tostring(text)
            DEFAULT_CHAT_FRAME:AddMessage(formattedText, 0.8, 0.4, 1)
        end
    else
        -- Fallback to DEFAULT_CHAT_FRAME
        local formattedText = "|cffcc66ff[AM]|r" .. tostring(text)
        DEFAULT_CHAT_FRAME:AddMessage(formattedText, 0.8, 0.4, 1)
    end
end

-- Auto-register for error capture
if OGAALogger and OGAALogger.RegisterAddon then
    OGAALogger.RegisterAddon("_OGAddonMsg")
end
