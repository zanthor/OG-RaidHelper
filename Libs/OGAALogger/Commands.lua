--[[
    _OGAALogger - Slash Commands
    
    Command interface for the logger.
]]

-- Register slash commands
SLASH_OGAAL1 = "/ogl"
SLASH_OGAAL2 = "/ogaal"
SLASH_OGAAL3 = "/ogaalogger"

SlashCmdList["OGAAL"] = function(msg)
    -- Parse command
    local cmd = string.lower(msg or "")
    
    if cmd == "" then
        -- Default: toggle window
        OGAALogger.Toggle()
        
    elseif cmd == "show" then
        OGAALogger.Show()
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[OGAALogger]|r Log viewer opened.")
        
    elseif cmd == "hide" then
        OGAALogger.Hide()
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[OGAALogger]|r Log viewer closed.")
        
    elseif cmd == "clear" then
        OGAALogger.Clear()
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[OGAALogger]|r All messages cleared.")
        
    elseif cmd == "regs" or cmd == "registrations" then
        OGAALogger.ShowRegistrations()
        
    elseif string.find(cmd, "^reg%s+(.+)") then
        -- Register addon: /ogl reg OG-RaidHelper
        local addonFolder = string.match(cmd, "^reg%s+(.+)")
        if OGAALogger.RegisterAddon(addonFolder) then
            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ccff[OGAALogger]|r Registered '%s' for error capture.", addonFolder))
        else
            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff0000[OGAALogger]|r '%s' is already registered.", addonFolder))
        end
        
    elseif string.find(cmd, "^unreg%s+(%d+)") then
        -- Unregister by index: /ogl unreg 1
        local indexStr = string.match(cmd, "^unreg%s+(%d+)")
        local index = tonumber(indexStr)
        
        if index and OGAALogger.UnregisterAddon(index) then
            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ccff[OGAALogger]|r Unregistered addon at index %d.", index))
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[OGAALogger]|r Invalid index. Use /ogl regs to see registered addons.")
        end
        
    elseif cmd == "stats" or cmd == "info" then
        local count = OGAALogger.GetMessageCount()
        local max = OGAALogger.GetMaxMessages()
        local session = OGAALogger.GetSessionCount()
        
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[OGAALogger]|r Statistics:")
        DEFAULT_CHAT_FRAME:AddMessage(string.format("  Messages: %d/%d", count, max))
        DEFAULT_CHAT_FRAME:AddMessage(string.format("  Session: %d", session))
        
    elseif string.find(cmd, "^max%s+(%d+)") then
        -- Set max messages: /ogl max 1000
        local maxStr = string.match(cmd, "^max%s+(%d+)")
        local newMax = tonumber(maxStr)
        
        if newMax and newMax >= 50 and newMax <= 5000 then
            OGAALogger.SetMaxMessages(newMax)
            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ccff[OGAALogger]|r Max messages set to %d.", newMax))
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[OGAALogger]|r Invalid value. Must be between 50 and 5000.")
        end
        
    elseif cmd == "help" then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[OGAALogger]|r Command Help:")
        DEFAULT_CHAT_FRAME:AddMessage("  |cffffff00/ogl|r - Toggle log viewer")
        DEFAULT_CHAT_FRAME:AddMessage("  |cffffff00/ogl show|r - Open log viewer")
        DEFAULT_CHAT_FRAME:AddMessage("  |cffffff00/ogl hide|r - Close log viewer")
        DEFAULT_CHAT_FRAME:AddMessage("  |cffffff00/ogl clear|r - Clear all messages")
        DEFAULT_CHAT_FRAME:AddMessage("  |cffffff00/ogl stats|r - Show statistics")
        DEFAULT_CHAT_FRAME:AddMessage("  |cffffff00/ogl max <number>|r - Set max messages (50-5000)")
        DEFAULT_CHAT_FRAME:AddMessage("  |cffffff00/ogl regs|r - Show registered addons")
        DEFAULT_CHAT_FRAME:AddMessage("  |cffffff00/ogl reg <folder>|r - Register addon for error capture")
        DEFAULT_CHAT_FRAME:AddMessage("  |cffffff00/ogl unreg <index>|r - Unregister addon by index")
        DEFAULT_CHAT_FRAME:AddMessage("  |cffffff00/ogl help|r - Show this help")
        
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[OGAALogger]|r Unknown command. Type |cffffff00/ogl help|r for usage.")
    end
end
