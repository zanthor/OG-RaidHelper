--[[
    OGAddonMsg - Commands
    Slash command handlers
]]

-- Register slash commands
SLASH_OGADDONMSG1 = "/ogmsg"
SLASH_OGADDONMSG2 = "/ogaddonmsg"

SlashCmdList["OGADDONMSG"] = function(msg)
    -- Parse command and arguments
    local _, _, cmd, args = string.find(msg, "^(%S+)%s*(.-)$")
    cmd = cmd or msg
    cmd = string.lower(cmd)
    
    if cmd == "" or cmd == "help" then
        OGAddonMsg.ShowHelp()
        
    elseif cmd == "status" then
        OGAddonMsg.ShowStatus()
        
    elseif cmd == "stats" then
        if args == "reset" then
            OGAddonMsg.ResetStats()
        elseif args == "show" then
            OGAddonMsg.ShowStatsPanel()
        elseif args == "hide" then
            OGAddonMsg.HideStatsPanel()
        elseif args == "" or args == "toggle" then
            OGAddonMsg.ToggleStatsPanel()
        else
            OGAddonMsg.ShowStats()
        end
        
    elseif cmd == "debug" then
        if args == "on" or args == "1" then
            OGAddonMsg.SetConfig("debug", true)
            DEFAULT_CHAT_FRAME:AddMessage("OGAddonMsg: Debug mode ON", 0.5, 1, 0.5)
        elseif args == "off" or args == "0" then
            OGAddonMsg.SetConfig("debug", false)
            DEFAULT_CHAT_FRAME:AddMessage("OGAddonMsg: Debug mode OFF", 0.5, 1, 0.5)
        else
            DEFAULT_CHAT_FRAME:AddMessage("Usage: /ogmsg debug on|off", 1, 1, 0)
        end
        
    elseif cmd == "warnqueue" then
        local value = tonumber(args)
        if value and value > 0 then
            OGAddonMsg.SetConfig("warnQueue", value)
            DEFAULT_CHAT_FRAME:AddMessage(
                string.format("OGAddonMsg: Queue warning threshold set to %.1fs", value),
                0.5, 1, 0.5
            )
        else
            DEFAULT_CHAT_FRAME:AddMessage("Usage: /ogmsg warnqueue <seconds>", 1, 1, 0)
        end
        
    elseif cmd == "warnperiod" then
        local value = tonumber(args)
        if value and value > 0 then
            OGAddonMsg.SetConfig("warnPeriod", value)
            DEFAULT_CHAT_FRAME:AddMessage(
                string.format("OGAddonMsg: Sustained warning period set to %.1fs", value),
                0.5, 1, 0.5
            )
        else
            DEFAULT_CHAT_FRAME:AddMessage("Usage: /ogmsg warnperiod <seconds>", 1, 1, 0)
        end
        
    elseif cmd == "warninterval" then
        local value = tonumber(args)
        if value and value > 0 then
            OGAddonMsg.SetConfig("warnInterval", value)
            DEFAULT_CHAT_FRAME:AddMessage(
                string.format("OGAddonMsg: Periodic warning interval set to %.1fs", value),
                0.5, 1, 0.5
            )
        else
            DEFAULT_CHAT_FRAME:AddMessage("Usage: /ogmsg warninterval <seconds>", 1, 1, 0)
        end
        
    elseif cmd == "retaintime" then
        local value = tonumber(args)
        if value and value > 0 then
            OGAddonMsg.SetConfig("retainTime", value)
            DEFAULT_CHAT_FRAME:AddMessage(
                string.format("OGAddonMsg: Retry retain time set to %.1fs", value),
                0.5, 1, 0.5
            )
        else
            DEFAULT_CHAT_FRAME:AddMessage("Usage: /ogmsg retaintime <seconds>", 1, 1, 0)
        end
        
    elseif cmd == "timeout" then
        local value = tonumber(args)
        if value and value > 0 then
            OGAddonMsg.SetConfig("timeout", value)
            DEFAULT_CHAT_FRAME:AddMessage(
                string.format("OGAddonMsg: Reassembly timeout set to %.1fs", value),
                0.5, 1, 0.5
            )
        else
            DEFAULT_CHAT_FRAME:AddMessage("Usage: /ogmsg timeout <seconds>", 1, 1, 0)
        end
        
    elseif cmd == "maxrate" then
        local value = tonumber(args)
        if value and value > 0 and value <= 20 then
            OGAddonMsg.SetConfig("maxRate", value)
            DEFAULT_CHAT_FRAME:AddMessage(
                string.format("OGAddonMsg: Max rate set to %.1f msgs/sec", value),
                0.5, 1, 0.5
            )
        else
            DEFAULT_CHAT_FRAME:AddMessage("Usage: /ogmsg maxrate <msgs/sec> (1-20)", 1, 1, 0)
        end
        
    elseif cmd == "burstlimit" then
        local value = tonumber(args)
        if value and value > 0 then
            OGAddonMsg.SetConfig("burstLimit", value)
            DEFAULT_CHAT_FRAME:AddMessage(
                string.format("OGAddonMsg: Burst limit set to %d messages", value),
                0.5, 1, 0.5
            )
        else
            DEFAULT_CHAT_FRAME:AddMessage("Usage: /ogmsg burstlimit <count>", 1, 1, 0)
        end
        
    else
        DEFAULT_CHAT_FRAME:AddMessage("Unknown command: " .. cmd, 1, 0, 0)
        DEFAULT_CHAT_FRAME:AddMessage("Type /ogmsg help for commands", 1, 1, 0)
    end
end

function OGAddonMsg.ShowHelp()
    DEFAULT_CHAT_FRAME:AddMessage("=== OGAddonMsg Commands ===", 0.5, 1, 0.5)
    DEFAULT_CHAT_FRAME:AddMessage("/ogmsg status - Show queue status and config", 1, 1, 1)
    DEFAULT_CHAT_FRAME:AddMessage("/ogmsg stats - Toggle stats panel", 1, 1, 1)
    DEFAULT_CHAT_FRAME:AddMessage("/ogmsg stats show|hide - Show/hide stats panel", 1, 1, 1)
    DEFAULT_CHAT_FRAME:AddMessage("/ogmsg stats reset - Reset statistics", 1, 1, 1)
    DEFAULT_CHAT_FRAME:AddMessage("/ogmsg debug on|off - Toggle debug mode", 1, 1, 1)
    DEFAULT_CHAT_FRAME:AddMessage(" ", 1, 1, 1)
    DEFAULT_CHAT_FRAME:AddMessage("Configuration:", 0.5, 1, 0.5)
    DEFAULT_CHAT_FRAME:AddMessage("/ogmsg warnqueue <sec> - Queue warning threshold", 1, 1, 1)
    DEFAULT_CHAT_FRAME:AddMessage("/ogmsg warnperiod <sec> - Sustained warning duration", 1, 1, 1)
    DEFAULT_CHAT_FRAME:AddMessage("/ogmsg warninterval <sec> - Periodic warning interval", 1, 1, 1)
    DEFAULT_CHAT_FRAME:AddMessage("/ogmsg retaintime <sec> - Retry buffer retention", 1, 1, 1)
    DEFAULT_CHAT_FRAME:AddMessage("/ogmsg timeout <sec> - Reassembly timeout", 1, 1, 1)
    DEFAULT_CHAT_FRAME:AddMessage("/ogmsg maxrate <msgs/sec> - Throttling rate", 1, 1, 1)
    DEFAULT_CHAT_FRAME:AddMessage("/ogmsg burstlimit <count> - Burst limit", 1, 1, 1)
end

function OGAddonMsg.ShowStatus()
    local config = OGAddonMsg_Config
    local stats = OGAddonMsg.stats
    
    DEFAULT_CHAT_FRAME:AddMessage("=== OGAddonMsg Status ===", 0.5, 1, 0.5)
    DEFAULT_CHAT_FRAME:AddMessage(string.format("Version: %s", OGAddonMsg.GetVersion()), 1, 1, 1)
    DEFAULT_CHAT_FRAME:AddMessage(string.format("Queue Depth: %d messages (%.1fs estimated)",
        stats.queueDepth, stats.queueTimeEstimate), 1, 1, 1)
    DEFAULT_CHAT_FRAME:AddMessage(string.format("Debug Mode: %s", config.debug and "ON" or "OFF"), 1, 1, 1)
    DEFAULT_CHAT_FRAME:AddMessage(" ", 1, 1, 1)
    DEFAULT_CHAT_FRAME:AddMessage("Configuration:", 0.5, 1, 0.5)
    DEFAULT_CHAT_FRAME:AddMessage(string.format("  Queue Warning: %.1fs", config.warnQueue), 1, 1, 1)
    DEFAULT_CHAT_FRAME:AddMessage(string.format("  Max Rate: %.1f msgs/sec", config.maxRate), 1, 1, 1)
    DEFAULT_CHAT_FRAME:AddMessage(string.format("  Burst Limit: %d messages", config.burstLimit), 1, 1, 1)
    DEFAULT_CHAT_FRAME:AddMessage(string.format("  Retain Time: %.1fs", config.retainTime), 1, 1, 1)
end

function OGAddonMsg.ShowStats()
    local stats = OGAddonMsg.stats
    
    DEFAULT_CHAT_FRAME:AddMessage("=== OGAddonMsg Statistics ===", 0.5, 1, 0.5)
    DEFAULT_CHAT_FRAME:AddMessage(string.format("Messages: %d sent, %d received",
        stats.messagesSent, stats.messagesReceived), 1, 1, 1)
    DEFAULT_CHAT_FRAME:AddMessage(string.format("Bytes: %d sent, %d received",
        stats.bytesSent, stats.bytesReceived), 1, 1, 1)
    DEFAULT_CHAT_FRAME:AddMessage(string.format("Chunks: %d sent, %d received",
        stats.chunksSent, stats.chunksReceived), 1, 1, 1)
    DEFAULT_CHAT_FRAME:AddMessage(string.format("Reassembled: %d multi-chunk messages",
        stats.messagesReassembled), 1, 1, 1)
    DEFAULT_CHAT_FRAME:AddMessage(string.format("Retries: %d requested, %d sent",
        stats.retriesRequested, stats.retriesSent), 1, 1, 1)
    DEFAULT_CHAT_FRAME:AddMessage(string.format("Failures: %d", stats.failures), 1, 1, 1)
    DEFAULT_CHAT_FRAME:AddMessage(string.format("Ignored: %d", stats.ignored), 1, 1, 1)
    DEFAULT_CHAT_FRAME:AddMessage(string.format("Queue: %d current, %d max",
        stats.queueDepth, stats.queueDepthMax), 1, 1, 1)
end
