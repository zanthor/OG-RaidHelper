--[[
    OGAddonMsg - Queue
    Priority queue management, CTL integration, and latency monitoring
    
    Throttling is delegated to ChatThrottleLib (CTL), which is the standard
    for WoW addon bandwidth management. Our queue handles OGAddonMsg-level
    priority ordering, then hands messages to CTL for safe delivery.
    
    CTL priorities mapped from OGAddonMsg priorities:
        CRITICAL -> "ALERT"
        HIGH     -> "NORMAL" 
        NORMAL   -> "NORMAL"
        LOW      -> "BULK"
]]

-- Initialize queue with priority levels
OGAddonMsg.queue = {
    CRITICAL = {},
    HIGH = {},
    NORMAL = {},
    LOW = {}
}

-- Initialize latency monitor
OGAddonMsg.latencyMonitor = {
    queueExceededAt = nil,
    lastWarning = 0
}

-- Map OGAddonMsg priorities to CTL priorities
local CTL_PRIORITY_MAP = {
    CRITICAL = "ALERT",
    HIGH = "NORMAL",
    NORMAL = "NORMAL",
    LOW = "BULK"
}

--[[
    Queue Management
]]
function OGAddonMsg.Enqueue(priority, message, channel, target, callbacks)
    priority = priority or "NORMAL"
    
    local item = {
        msg = message,
        channel = channel,
        target = target,
        callbacks = callbacks,
        enqueueTime = GetTime()
    }
    
    table.insert(OGAddonMsg.queue[priority], item)
    
    -- Update queue depth stat
    OGAddonMsg.UpdateQueueStats()
end

local function Dequeue()
    -- Check priorities in order
    for _, priority in ipairs({"CRITICAL", "HIGH", "NORMAL", "LOW"}) do
        if table.getn(OGAddonMsg.queue[priority]) > 0 then
            return table.remove(OGAddonMsg.queue[priority], 1), priority
        end
    end
    return nil, nil
end

--[[
    Queue Processing - delegates to ChatThrottleLib for actual sending
]]
function OGAddonMsg.ProcessQueue(elapsed)
    -- Dequeue and hand to CTL
    local item, priority = Dequeue()
    if not item then
        return
    end
    
    -- Resolve CTL priority
    local ctlPrio = CTL_PRIORITY_MAP[priority] or "NORMAL"
    
    -- Build a unique queue name for CTL round-robin (per channel+target)
    local queueName = "OGAM:" .. (item.channel or "AUTO") .. ":" .. (item.target or "")
    
    -- Use ChatThrottleLib if available, otherwise fall back to direct send
    if ChatThrottleLib and ChatThrottleLib.SendAddonMessage then
        -- CTL callback fires when the message actually leaves the wire
        local function ctlCallback()
            if OGAddonMsg_Config.debug then
                DEFAULT_CHAT_FRAME:AddMessage(
                    string.format("OGAddonMsg: TX -> %s (%d bytes) [CTL:%s]", 
                        item.channel or "AUTO", string.len(item.msg), ctlPrio),
                    0.5, 1, 0.5
                )
            end
            
            -- Update stats
            OGAddonMsg.stats.messagesSent = OGAddonMsg.stats.messagesSent + 1
            OGAddonMsg.stats.bytesSent = OGAddonMsg.stats.bytesSent + string.len(item.msg)
            OGAddonMsg.stats.chunksSent = OGAddonMsg.stats.chunksSent + 1
            
            -- Callback
            if item.callbacks and item.callbacks.onSuccess then
                item.callbacks.onSuccess()
            end
        end
        
        ChatThrottleLib:SendAddonMessage(ctlPrio, "OGAM", item.msg, item.channel, item.target, queueName, ctlCallback)
    else
        -- Fallback: direct send (no throttle protection)
        local success = pcall(SendAddonMessage, "OGAM", item.msg, item.channel, item.target)
        
        if success then
            if OGAddonMsg_Config.debug then
                DEFAULT_CHAT_FRAME:AddMessage(
                    string.format("OGAddonMsg: TX -> %s (%d bytes) [NO CTL]", 
                        item.channel or "AUTO", string.len(item.msg)),
                    0.5, 1, 0.5
                )
            end
            
            OGAddonMsg.stats.messagesSent = OGAddonMsg.stats.messagesSent + 1
            OGAddonMsg.stats.bytesSent = OGAddonMsg.stats.bytesSent + string.len(item.msg)
            OGAddonMsg.stats.chunksSent = OGAddonMsg.stats.chunksSent + 1
            
            if item.callbacks and item.callbacks.onSuccess then
                item.callbacks.onSuccess()
            end
        else
            OGAddonMsg.stats.failures = OGAddonMsg.stats.failures + 1
            
            if OGAddonMsg_Config.debug then
                DEFAULT_CHAT_FRAME:AddMessage("OGAddonMsg: Send failed (no CTL)", 1, 0, 0)
            end
            
            if item.callbacks and item.callbacks.onFailure then
                item.callbacks.onFailure("Send failed")
            end
        end
    end
    
    -- Update queue stats
    OGAddonMsg.UpdateQueueStats()
end

--[[
    Queue Statistics
]]
function OGAddonMsg.UpdateQueueStats()
    local totalItems = 0
    local totalBytes = 0
    
    for _, priority in ipairs({"CRITICAL", "HIGH", "NORMAL", "LOW"}) do
        for i = 1, table.getn(OGAddonMsg.queue[priority]) do
            totalItems = totalItems + 1
            totalBytes = totalBytes + string.len(OGAddonMsg.queue[priority][i].msg)
        end
    end
    
    OGAddonMsg.stats.queueDepth = totalItems
    
    if totalItems > OGAddonMsg.stats.queueDepthMax then
        OGAddonMsg.stats.queueDepthMax = totalItems
    end
    
    -- Estimate queue time based on CTL's bandwidth (~800 CPS with 40 byte overhead)
    local ctlCPS = 800
    local ctlOverhead = 40
    OGAddonMsg.stats.queueTimeEstimate = (totalBytes + (totalItems * ctlOverhead)) / ctlCPS
end

--[[
    Latency Monitoring
]]
function OGAddonMsg.CheckLatencyWarnings()
    local queueTime = OGAddonMsg.stats.queueTimeEstimate
    local config = OGAddonMsg_Config
    local now = GetTime()
    
    if queueTime > config.warnQueue then
        if not OGAddonMsg.latencyMonitor.queueExceededAt then
            -- First warning
            OGAddonMsg.latencyMonitor.queueExceededAt = now
            DEFAULT_CHAT_FRAME:AddMessage(
                string.format("OGAddonMsg: Network queue at %.1fs", queueTime),
                1, 1, 0
            )
        else
            -- Check for sustained high queue
            local duration = now - OGAddonMsg.latencyMonitor.queueExceededAt
            if duration > config.warnPeriod then
                if now - OGAddonMsg.latencyMonitor.lastWarning > config.warnInterval then
                    DEFAULT_CHAT_FRAME:AddMessage(
                        string.format("OGAddonMsg: Network queue at %.1fs for %.0fs",
                            queueTime, duration),
                        1, 0.5, 0
                    )
                    OGAddonMsg.latencyMonitor.lastWarning = now
                end
            end
        end
    else
        -- Queue back to normal
        OGAddonMsg.latencyMonitor.queueExceededAt = nil
    end
end
