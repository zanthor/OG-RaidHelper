--[[
    OGAddonMsg - Configuration
    Manages SavedVariables and configuration
]]

-- Default configuration
local DEFAULT_CONFIG = {
    version = "1.2.0",
    warnQueue = 10,          -- Warn when queue exceeds this many seconds
    warnPeriod = 30,        -- Sustained duration before periodic warnings
    warnInterval = 10,      -- Interval between periodic warnings
    retainTime = 60,        -- How long to retain sent messages for retry
    timeout = 90,           -- When to give up on incomplete receives
    maxRate = 8,            -- Max messages per second
    burstLimit = 15,        -- Max burst messages
    debug = false           -- Debug logging
}

-- Initialize configuration from SavedVariables
function OGAddonMsg.InitializeConfig()
    -- Ensure SavedVariables exists
    if not OGAddonMsg_Config then
        OGAddonMsg_Config = {}
    end
    
    -- Set defaults for missing values
    for key, value in pairs(DEFAULT_CONFIG) do
        if OGAddonMsg_Config[key] == nil then
            OGAddonMsg_Config[key] = value
        end
    end
    
    -- Config migrations: update stale values from older versions
    local savedVer = OGAddonMsg_Config.version or "0"
    if savedVer < DEFAULT_CONFIG.version then
        -- v1.2.0: warnQueue default changed from 5 to 10
        if OGAddonMsg_Config.warnQueue == 5 then
            OGAddonMsg_Config.warnQueue = DEFAULT_CONFIG.warnQueue
        end
        OGAddonMsg_Config.version = DEFAULT_CONFIG.version
    end
    
    -- Initialize statistics (preserve existing stats object to maintain references)
    if not OGAddonMsg.stats then
        OGAddonMsg.stats = {}
    end
    
    -- Set default values for any missing stat fields
    local defaultStats = {
        messagesSent = 0,
        messagesReceived = 0,
        bytesSent = 0,
        bytesReceived = 0,
        chunksSent = 0,
        chunksReceived = 0,
        messagesReassembled = 0,
        retriesRequested = 0,
        retriesSent = 0,
        failures = 0,
        ignored = 0,
        queueDepth = 0,
        queueDepthMax = 0,
        queueTimeEstimate = 0
    }
    
    for key, value in pairs(defaultStats) do
        if OGAddonMsg.stats[key] == nil then
            OGAddonMsg.stats[key] = value
        end
    end
    
    if OGAddonMsg_Config.debug then
        OGAddonMsg.Msg("OGAddonMsg: Config initialized")
    end
end

--[[
    Public API - Configuration
]]
function OGAddonMsg.SetConfig(key, value)
    if OGAddonMsg_Config[key] ~= nil then
        OGAddonMsg_Config[key] = value
        return true
    end
    return false
end

function OGAddonMsg.GetConfig(key)
    if key then
        return OGAddonMsg_Config[key]
    else
        return OGAddonMsg_Config
    end
end

--[[
    Public API - Statistics
]]
function OGAddonMsg.GetStats()
    return OGAddonMsg.stats
end

function OGAddonMsg.ResetStats()
    OGAddonMsg.stats.messagesSent = 0
    OGAddonMsg.stats.messagesReceived = 0
    OGAddonMsg.stats.bytesSent = 0
    OGAddonMsg.stats.bytesReceived = 0
    OGAddonMsg.stats.chunksSent = 0
    OGAddonMsg.stats.chunksReceived = 0
    OGAddonMsg.stats.messagesReassembled = 0
    OGAddonMsg.stats.retriesRequested = 0
    OGAddonMsg.stats.retriesSent = 0
    OGAddonMsg.stats.failures = 0
    OGAddonMsg.stats.ignored = 0
    OGAddonMsg.stats.queueDepthMax = 0
    
    OGAddonMsg.Msg("OGAddonMsg: Statistics reset")
end
