--[[
    OGAddonMsg - Queue
    Priority queue management, throttling, and latency monitoring
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

-- Throttling state
local lastSendTime = 0
local burstCount = 0
local burstResetTime = 0

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
            return table.remove(OGAddonMsg.queue[priority], 1)
        end
    end
    return nil
end

--[[
    Throttling Engine
]]
function OGAddonMsg.ProcessQueue(elapsed)
    local now = GetTime()
    local config = OGAddonMsg_Config
    
    -- Reset burst counter every second
    if now - burstResetTime >= 1.0 then
        burstCount = 0
        burstResetTime = now
    end
    
    -- Check burst limit
    if burstCount >= config.burstLimit then
        return
    end
    
    -- Check rate limit
    local minInterval = 1.0 / config.maxRate
    if now - lastSendTime < minInterval then
        return
    end
    
    -- Dequeue and send
    local item = Dequeue()
    if not item then
        return
    end
    
    -- Send via WoW API
    -- SendAddonMessage(prefix, message, channel, target)
    local success = pcall(SendAddonMessage, "OGAM", item.msg, item.channel, item.target)
    
    if success then
        if OGAddonMsg_Config.debug then
            DEFAULT_CHAT_FRAME:AddMessage(
                string.format("OGAddonMsg: TX -> %s (%d bytes)", 
                    item.channel or "AUTO", string.len(item.msg)),
                0.5, 1, 0.5
            )
        end
        
        -- Update throttling state
        lastSendTime = now
        burstCount = burstCount + 1
        
        -- Update stats
        OGAddonMsg.stats.messagesSent = OGAddonMsg.stats.messagesSent + 1
        OGAddonMsg.stats.bytesSent = OGAddonMsg.stats.bytesSent + string.len(item.msg)
        OGAddonMsg.stats.chunksSent = OGAddonMsg.stats.chunksSent + 1
        
        -- Callback
        if item.callbacks and item.callbacks.onSuccess then
            item.callbacks.onSuccess()
        end
    else
        -- Send failed
        OGAddonMsg.stats.failures = OGAddonMsg.stats.failures + 1
        
        if OGAddonMsg_Config.debug then
            DEFAULT_CHAT_FRAME:AddMessage("OGAddonMsg: Send failed", 1, 0, 0)
        end
        
        if item.callbacks and item.callbacks.onFailure then
            item.callbacks.onFailure("Send failed")
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
    
    -- Estimate queue time
    local avgBytes = 150
    local config = OGAddonMsg_Config
    OGAddonMsg.stats.queueTimeEstimate = totalBytes / (config.maxRate * avgBytes)
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
