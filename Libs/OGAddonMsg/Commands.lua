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
            OGAddonMsg.Msg("OGAddonMsg: Debug mode ON")
        elseif args == "off" or args == "0" then
            OGAddonMsg.SetConfig("debug", false)
            OGAddonMsg.Msg("OGAddonMsg: Debug mode OFF")
        else
            OGAddonMsg.Msg("Usage: /ogmsg debug on|off")
        end
        
    elseif cmd == "warnqueue" then
        local value = tonumber(args)
        if value and value > 0 then
            OGAddonMsg.SetConfig("warnQueue", value)
            OGAddonMsg.Msg(
                string.format("OGAddonMsg: Queue warning threshold set to %.1fs", value))
        else
            OGAddonMsg.Msg("Usage: /ogmsg warnqueue <seconds>")
        end
        
    elseif cmd == "warnperiod" then
        local value = tonumber(args)
        if value and value > 0 then
            OGAddonMsg.SetConfig("warnPeriod", value)
            OGAddonMsg.Msg(
                string.format("OGAddonMsg: Sustained warning period set to %.1fs", value))
        else
            OGAddonMsg.Msg("Usage: /ogmsg warnperiod <seconds>")
        end
        
    elseif cmd == "warninterval" then
        local value = tonumber(args)
        if value and value > 0 then
            OGAddonMsg.SetConfig("warnInterval", value)
            OGAddonMsg.Msg(
                string.format("OGAddonMsg: Periodic warning interval set to %.1fs", value))
        else
            OGAddonMsg.Msg("Usage: /ogmsg warninterval <seconds>")
        end
        
    elseif cmd == "retaintime" then
        local value = tonumber(args)
        if value and value > 0 then
            OGAddonMsg.SetConfig("retainTime", value)
            OGAddonMsg.Msg(
                string.format("OGAddonMsg: Retry retain time set to %.1fs", value))
        else
            OGAddonMsg.Msg("Usage: /ogmsg retaintime <seconds>")
        end
        
    elseif cmd == "timeout" then
        local value = tonumber(args)
        if value and value > 0 then
            OGAddonMsg.SetConfig("timeout", value)
            OGAddonMsg.Msg(
                string.format("OGAddonMsg: Reassembly timeout set to %.1fs", value))
        else
            OGAddonMsg.Msg("Usage: /ogmsg timeout <seconds>")
        end
        
    elseif cmd == "maxrate" then
        local value = tonumber(args)
        if value and value > 0 and value <= 20 then
            OGAddonMsg.SetConfig("maxRate", value)
            OGAddonMsg.Msg(
                string.format("OGAddonMsg: Max rate set to %.1f msgs/sec", value))
        else
            OGAddonMsg.Msg("Usage: /ogmsg maxrate <msgs/sec> (1-20)")
        end
        
    elseif cmd == "burstlimit" then
        local value = tonumber(args)
        if value and value > 0 then
            OGAddonMsg.SetConfig("burstLimit", value)
            OGAddonMsg.Msg(
                string.format("OGAddonMsg: Burst limit set to %d messages", value))
        else
            OGAddonMsg.Msg("Usage: /ogmsg burstlimit <count>")
        end
        
    elseif cmd == "ratetest" then
        local _, _, rateStr, sizeStr = string.find(args, "^(%S+)%s*(%S*)$")
        local rateNum = tonumber(rateStr)
        local sizeNum = tonumber(sizeStr) -- nil if omitted, will use minimum
        if rateNum and rateNum > 0 then
            OGAddonMsg.RateTest(rateNum, sizeNum)
        else
            OGAddonMsg.Msg("Usage: /ogmsg ratetest <rate> [size]")
            OGAddonMsg.Msg("  rate  = messages per second to attempt")
            OGAddonMsg.Msg("  size  = message size in bytes (0-254, default=0/minimum)")
            OGAddonMsg.Msg("Example: /ogmsg ratetest 10 254  (max size, 10/sec)")
        end
        
    else
        OGAddonMsg.Msg("Unknown command: " .. cmd)
        OGAddonMsg.Msg("Type /ogmsg help for commands")
    end
end

function OGAddonMsg.ShowHelp()
    OGAddonMsg.Msg("=== OGAddonMsg Commands ===")
    OGAddonMsg.Msg("/ogmsg status - Show queue status and config")
    OGAddonMsg.Msg("/ogmsg stats - Toggle stats panel")
    OGAddonMsg.Msg("/ogmsg stats show|hide - Show/hide stats panel")
    OGAddonMsg.Msg("/ogmsg stats reset - Reset statistics")
    OGAddonMsg.Msg("/ogmsg debug on|off - Toggle debug mode")
    OGAddonMsg.Msg(" ")
    OGAddonMsg.Msg("Configuration:")
    OGAddonMsg.Msg("/ogmsg warnqueue <sec> - Queue warning threshold")
    OGAddonMsg.Msg("/ogmsg warnperiod <sec> - Sustained warning duration")
    OGAddonMsg.Msg("/ogmsg warninterval <sec> - Periodic warning interval")
    OGAddonMsg.Msg("/ogmsg retaintime <sec> - Retry buffer retention")
    OGAddonMsg.Msg("/ogmsg timeout <sec> - Reassembly timeout")
    OGAddonMsg.Msg("/ogmsg maxrate <msgs/sec> - Throttling rate")
    OGAddonMsg.Msg("/ogmsg burstlimit <count> - Burst limit")
    OGAddonMsg.Msg(" ")
    OGAddonMsg.Msg("Testing:")
    OGAddonMsg.Msg("/ogmsg ratetest <rate> [size] - Rate test (size 0-254 bytes)")
end

function OGAddonMsg.ShowStatus()
    local config = OGAddonMsg_Config
    local stats = OGAddonMsg.stats
    
    OGAddonMsg.Msg("=== OGAddonMsg Status ===")
    OGAddonMsg.Msg(string.format("Version: %s (standalone: %s)",
        OGAddonMsg.GetVersion(), OGAddonMsg.__standalone and "yes" or "no"))
    OGAddonMsg.Msg(string.format("Queue Depth: %d messages (%.1fs estimated)",
        stats.queueDepth, stats.queueTimeEstimate))
    OGAddonMsg.Msg(string.format("Debug Mode: %s", config.debug and "ON" or "OFF"))
    OGAddonMsg.Msg(" ")
    
    -- ChatThrottleLib status
    if ChatThrottleLib then
        OGAddonMsg.Msg(string.format("ChatThrottleLib: v%d (active)", ChatThrottleLib.version or 0))
        OGAddonMsg.Msg(string.format("  CPS: %d | Burst: %d | Overhead: %d",
            ChatThrottleLib.MAX_CPS or 0, ChatThrottleLib.BURST or 0, ChatThrottleLib.MSG_OVERHEAD or 0))
        if ChatThrottleLib.bQueueing then
            OGAddonMsg.Msg("  CTL Status: QUEUEING (throttled)")
        else
            OGAddonMsg.Msg("  CTL Status: IDLE (bandwidth available)")
        end
    else
        OGAddonMsg.Msg("ChatThrottleLib: NOT LOADED (no throttle protection!)")
    end
    
    OGAddonMsg.Msg(" ")
    OGAddonMsg.Msg("Configuration:")
    OGAddonMsg.Msg(string.format("  Queue Warning: %.1fs", config.warnQueue))
    OGAddonMsg.Msg(string.format("  Retain Time: %.1fs", config.retainTime))
end

function OGAddonMsg.ShowStats()
    local stats = OGAddonMsg.stats
    
    OGAddonMsg.Msg("=== OGAddonMsg Statistics ===")
    OGAddonMsg.Msg(string.format("Messages: %d sent, %d received",
        stats.messagesSent, stats.messagesReceived))
    OGAddonMsg.Msg(string.format("Bytes: %d sent, %d received",
        stats.bytesSent, stats.bytesReceived))
    OGAddonMsg.Msg(string.format("Chunks: %d sent, %d received",
        stats.chunksSent, stats.chunksReceived))
    OGAddonMsg.Msg(string.format("Reassembled: %d multi-chunk messages",
        stats.messagesReassembled))
    OGAddonMsg.Msg(string.format("Retries: %d requested, %d sent",
        stats.retriesRequested, stats.retriesSent))
    OGAddonMsg.Msg(string.format("Failures: %d", stats.failures))
    OGAddonMsg.Msg(string.format("Ignored: %d", stats.ignored))
    OGAddonMsg.Msg(string.format("Queue: %d current, %d max",
        stats.queueDepth, stats.queueDepthMax))
end

--[[
    Rate Test - Send addon messages at a given rate via RAID/PARTY/GUILD
    Uses ChatThrottleLib when available for realistic throttled throughput.
    The test queues messages at the requested rate and tracks how many
    CTL actually delivers within the 5-second window.
    
    Receiving clients with OGAddonMsg will display incoming test messages.
]]
local rateTestFrame = nil
local rateTestData = nil
local rateTestHandlerId = nil

function OGAddonMsg.RateTest(rate, size)
    -- Cancel existing test if running
    if rateTestFrame then
        rateTestFrame:Hide()
        rateTestFrame = nil
        OGAddonMsg.Msg("OGAddonMsg: Previous rate test cancelled")
    end
    
    -- Detect channel
    local channel = OGAddonMsg.DetectBestChannel()
    if not channel then
        OGAddonMsg.Msg("OGAddonMsg: Not in a raid, party, or guild. Cannot run rate test.")
        return
    end
    
    local useCTL = ChatThrottleLib and ChatThrottleLib.SendAddonMessage
    local playerName = UnitName("player")
    
    -- Calculate message sizing
    -- Header format: "RATETEST:<sender>:<count>:"
    -- With a 12-char name and 5-digit count: "RATETEST:Playername99:99999:" = ~30 bytes
    -- We measure the actual header per-message and pad to reach requested size
    -- Max SendAddonMessage payload (with OGAM prefix) is ~254 bytes
    local MAX_PAYLOAD = 254
    
    -- Build a sample header to measure minimum overhead
    local sampleHeader = "RATETEST:" .. playerName .. ":99999:"
    local headerLen = string.len(sampleHeader)
    local minSize = headerLen  -- minimum message size = just the header
    
    -- Resolve requested size
    if not size or size < 0 then
        size = 0  -- use minimum (header only)
    end
    if size > MAX_PAYLOAD then
        size = MAX_PAYLOAD
    end
    
    -- Actual target: at least headerLen, up to requested size
    local targetSize = size
    if targetSize > 0 and targetSize < minSize then
        OGAddonMsg.Msg(
            string.format("OGAddonMsg: Minimum message size is %d bytes (header overhead). Using %d.", minSize, minSize))
        targetSize = minSize
    end
    
    -- Pre-generate padding string (reused for all messages)
    local padChar = "X"
    local maxPadNeeded = MAX_PAYLOAD - headerLen
    local paddingPool = ""
    if maxPadNeeded > 0 then
        local parts = {}
        for i = 1, maxPadNeeded do
            table.insert(parts, padChar)
        end
        paddingPool = table.concat(parts)
    end
    
    -- Initialize test data
    rateTestData = {
        channel = channel,
        rate = rate,
        interval = 1.0 / rate,
        count = 0,
        startTime = GetTime(),
        duration = 5.0,
        lastSend = 0,
        queuedCount = 0,
        deliveredCount = 0,
        targetSize = targetSize,
        paddingPool = paddingPool
    }
    
    -- Create test frame
    rateTestFrame = CreateFrame("Frame")
    rateTestFrame:SetScript("OnUpdate", function()
        local now = GetTime()
        local elapsed = now - rateTestData.startTime
        
        -- Check if test duration complete
        if elapsed >= rateTestData.duration then
            -- Report results
            local queuedRate = rateTestData.queuedCount / elapsed
            local deliveredRate = rateTestData.deliveredCount / elapsed
            OGAddonMsg.Msg("=== OGAddonMsg Rate Test Complete ===")
            OGAddonMsg.Msg(
                string.format("  Channel: %s | Size: %d bytes", rateTestData.channel, rateTestData.targetSize))
            OGAddonMsg.Msg(
                string.format("  Queued: %d messages in %.2fs (%.1f msg/sec)",
                    rateTestData.queuedCount, elapsed, queuedRate))
            OGAddonMsg.Msg(
                string.format("  Delivered: %d messages in %.2fs (%.1f msg/sec)",
                    rateTestData.deliveredCount, elapsed, deliveredRate))
            OGAddonMsg.Msg(
                string.format("  Method: %s", useCTL and "ChatThrottleLib" or "Direct SendAddonMessage"))
            if rateTestData.queuedCount > rateTestData.deliveredCount then
                local remaining = rateTestData.queuedCount - rateTestData.deliveredCount
                OGAddonMsg.Msg(
                    string.format("  Note: %d messages still in CTL queue (will deliver after test)", remaining))
            end
            
            -- Cleanup
            rateTestFrame:Hide()
            rateTestFrame = nil
            rateTestData = nil
            return
        end
        
        -- Check if it's time to send next message
        if now - rateTestData.lastSend >= rateTestData.interval then
            rateTestData.count = rateTestData.count + 1
            
            -- Build message: RATETEST:<sender>:<count>:<padding>
            local header = "RATETEST:" .. playerName .. ":" .. rateTestData.count .. ":"
            local msg
            if rateTestData.targetSize > 0 then
                local padNeeded = rateTestData.targetSize - string.len(header)
                if padNeeded > 0 then
                    msg = header .. string.sub(rateTestData.paddingPool, 1, padNeeded)
                else
                    msg = header
                end
            else
                -- Size 0 = minimum, no padding
                msg = header
            end
            
            if useCTL then
                ChatThrottleLib:SendAddonMessage("NORMAL", "OGAM", msg, rateTestData.channel, nil, "OGAMRateTest", function()
                    if rateTestData then
                        rateTestData.deliveredCount = rateTestData.deliveredCount + 1
                    end
                end)
            else
                local success = pcall(SendAddonMessage, "OGAM", msg, rateTestData.channel)
                if success then
                    rateTestData.deliveredCount = rateTestData.deliveredCount + 1
                end
            end
            
            rateTestData.lastSend = now
            rateTestData.queuedCount = rateTestData.queuedCount + 1
        end
    end)
    
    -- Report actual message size
    local sampleMsg = "RATETEST:" .. playerName .. ":1:"
    local actualSize = targetSize
    if actualSize == 0 then
        actualSize = string.len(sampleMsg)
    end
    
    OGAddonMsg.Msg(
        string.format("OGAddonMsg: Rate test - %d msgs/sec, %d bytes/msg on %s for 5s (%s)",
            rate, actualSize, channel, useCTL and "via CTL" or "direct"))
end

--[[
    Rate Test Receiver
    Listens for RATETEST messages from other players and displays them.
    Messages from self are ignored (handled by Core.lua sender filter).
    Tracks per-sender receive rates and prints a summary when messages stop.
]]
local rateTestReceivers = {}

local function RateTestReport(sender)
    local data = rateTestReceivers[sender]
    if not data then return end
    
    local duration = data.lastTime - data.firstTime
    local rate = 0
    local bps = 0
    if duration > 0 then
        rate = data.count / duration
        bps = data.totalBytes / duration
    end
    
    OGAddonMsg.Msg(
        string.format("OGAddonMsg RateTest Summary from %s:", sender))
    OGAddonMsg.Msg(
        string.format("  %d msgs in %.1fs | %.1f msg/sec | %d bytes/msg | %.0f bytes/sec",
            data.count, duration, rate, data.lastMsgSize, bps))
    
    rateTestReceivers[sender] = nil
end

local function OnRateTestMessage(prefix, message, channel, sender)
    if prefix ~= "OGAM" then return end
    
    -- Check for RATETEST: prefix in the message body
    -- Format: RATETEST:<sender>:<count>:<optional padding>
    local _, _, rtSender, rtCount = string.find(message, "^RATETEST:(.+):(%d+):")
    if not rtSender or not rtCount then return end
    
    local msgSize = string.len(message)
    
    local now = GetTime()
    local data = rateTestReceivers[rtSender]
    
    if not data then
        -- First message from this sender
        data = {
            firstTime = now,
            lastTime = now,
            count = 0,
            totalBytes = 0,
            lastMsgSize = 0,
            reportFrame = CreateFrame("Frame")
        }
        rateTestReceivers[rtSender] = data
    end
    
    data.count = data.count + 1
    data.lastTime = now
    data.totalBytes = data.totalBytes + msgSize
    data.lastMsgSize = msgSize
    
    -- Calculate running rate
    local elapsed = now - data.firstTime
    local rate = 0
    if elapsed > 0 then
        rate = data.count / elapsed
    end
    
    OGAddonMsg.Msg(
        string.format("OGAddonMsg RateTest: #%s from %s [%s] %dB (%.1f msg/sec)",
            rtCount, rtSender, channel, msgSize, rate))
    
    -- Reset the inactivity timer - report summary 3s after last message
    local reportSender = rtSender
    data.reportFrame.elapsed = 0
    data.reportFrame:SetScript("OnUpdate", function()
        this.elapsed = this.elapsed + arg1
        if this.elapsed >= 3 then
            this:SetScript("OnUpdate", nil)
            RateTestReport(reportSender)
        end
    end)
end

-- Register the rate test receiver on the raw CHAT_MSG_ADDON event
local rateTestEventFrame = CreateFrame("Frame")
rateTestEventFrame:RegisterEvent("CHAT_MSG_ADDON")
rateTestEventFrame:SetScript("OnEvent", function()
    -- arg1=prefix, arg2=message, arg3=channel, arg4=sender
    if arg1 == "OGAM" then
        OnRateTestMessage(arg1, arg2, arg3, arg4)
    end
end)
