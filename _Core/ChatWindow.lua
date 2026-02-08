--[[
    ChatWindow.lua - OGRH Message Routing
    
    Routes OGRH addon messages to either _OGAALogger (if available) or DEFAULT_CHAT_FRAME.
    
    Features:
    - Auto-detects _OGAALogger addon
    - Routes to OGAALogger.AddMessage("OG", message) if available
    - Falls back to DEFAULT_CHAT_FRAME if OGAALogger not present
--]]

OGRH = OGRH or {}

-- ============================================
-- MESSAGE ROUTING
-- ============================================
-- Main message function - routes to OGAALogger or DEFAULT_CHAT_FRAME
OGRH.Msg = function(text)
    -- Check if OGAALogger is available
    if OGAALogger and OGAALogger.AddMessage and type(OGAALogger.AddMessage) == "function" then
        -- Send to OGAALogger with "OGRH" as source (pre-formatted message)
        local success, err = pcall(OGAALogger.AddMessage, "OGRH", tostring(text))
        if not success then
            -- If logger fails, fall back to chat frame
            local formattedText = "|cffff0000[OG-ERROR]|r Logger failed: " .. tostring(err)
            DEFAULT_CHAT_FRAME:AddMessage(formattedText, 1, 0.5, 0.5)
            -- Also send original message to chat
            local fallbackText = "|cff66ccff[OG]|r" .. tostring(text)
            DEFAULT_CHAT_FRAME:AddMessage(fallbackText, 1, 1, 1)
        end
    else
        -- Fallback to DEFAULT_CHAT_FRAME - logger not available yet
        local formattedText = "|cff66ccff[OGRH]|r" .. tostring(text)
        DEFAULT_CHAT_FRAME:AddMessage(formattedText, 0.4, 0.8, 1)
    end
end

-- ============================================
-- OGAALOGGER REGISTRATION
-- ============================================
-- Auto-register OG-RaidHelper for error capture
-- Check if OGAALogger is already loaded (it loads alphabetically before OG-RaidHelper)
if OGAALogger and OGAALogger.RegisterAddon then
    OGAALogger.RegisterAddon("OG-RaidHelper")
end
