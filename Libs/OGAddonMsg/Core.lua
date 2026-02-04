--[[
    OGAddonMsg - Core
    Namespace initialization, version checking, and event handling
]]

-- Version check for multi-copy loading (newest version wins)
local LIB_VERSION = 1.1

if OGAddonMsg and OGAddonMsg.__version and OGAddonMsg.__version >= LIB_VERSION then
    -- Newer or equal version already loaded, abort
    return
end

-- Initialize namespace
OGAddonMsg = OGAddonMsg or {}
OGAddonMsg.__version = LIB_VERSION

-- Internal state
OGAddonMsg.loaded = false
OGAddonMsg.initialized = false

-- Statistics (initialized in Config.lua)
OGAddonMsg.stats = {}

-- Queues (initialized in Queue.lua)
OGAddonMsg.queue = {}

-- Reassembly buffer (initialized in Chunker.lua)
OGAddonMsg.reassembly = {}

-- Retry buffer (initialized in Retry.lua)
OGAddonMsg.retryBuffer = {}

-- Handlers (initialized in Handlers.lua)
OGAddonMsg.handlers = {}

-- Latency monitor (initialized in Queue.lua)
OGAddonMsg.latencyMonitor = {}

-- Timers for cleanup tasks
OGAddonMsg.timers = {}

--[[
    Event Frame - handles all WoW events
]]
local eventFrame = CreateFrame("Frame", "OGAddonMsg_EventFrame")

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("VARIABLES_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("CHAT_MSG_ADDON")

eventFrame:SetScript("OnEvent", function()
    if event == "ADDON_LOADED" and arg1 == "_OGAddonMsg" then
        OGAddonMsg.OnLoad()
        
    elseif event == "VARIABLES_LOADED" then
        OGAddonMsg.OnVariablesLoaded()
        
    elseif event == "PLAYER_ENTERING_WORLD" then
        OGAddonMsg.OnEnteringWorld()
        
    elseif event == "CHAT_MSG_ADDON" then
        -- arg1 = prefix, arg2 = message, arg3 = channel, arg4 = sender
        OGAddonMsg.OnAddonMessage(arg1, arg2, arg3, arg4)
    end
end)

--[[
    OnUpdate Frame - handles throttling, queue processing, cleanup
]]
local updateFrame = CreateFrame("Frame", "OGAddonMsg_UpdateFrame")
updateFrame:SetScript("OnUpdate", function()
    -- arg1 = elapsed time since last frame
    OGAddonMsg.OnUpdate(arg1)
end)

--[[
    Initialization
]]
function OGAddonMsg.OnLoad()
    OGAddonMsg.loaded = true
    DEFAULT_CHAT_FRAME:AddMessage("OGAddonMsg v" .. OGAddonMsg.__version .. " loaded", 0.5, 1, 0.5)
end

function OGAddonMsg.OnVariablesLoaded()
    -- Config.lua handles SavedVariables initialization
    OGAddonMsg.InitializeConfig()
    OGAddonMsg.initialized = true
end

function OGAddonMsg.OnEnteringWorld()
    -- Retry.lua handles checking for incomplete messages and requesting retries
    if OGAddonMsg.initialized then
        OGAddonMsg.CheckIncompleteMessages()
        
        -- Auto-show stats panel for specific players
        local playerName = UnitName("player")
        if playerName == "Sunderwhere" or playerName == "Tankmedady" then
            OGAddonMsg.ShowStatsPanel()
        end
    end
end

function OGAddonMsg.OnAddonMessage(prefix, message, channel, sender)
    -- Only process messages with our prefix
    if prefix ~= "OGAM" then
        return
    end
    
    -- Ignore messages from ourselves
    if sender == UnitName("player") then
        return
    end
    
    -- Chunker.lua handles parsing and reassembly
    if OGAddonMsg.initialized then
        OGAddonMsg.ProcessIncomingMessage(prefix, message, channel, sender)
    end
end

function OGAddonMsg.OnUpdate(elapsed)
    if not OGAddonMsg.initialized then
        return
    end
    
    -- Queue.lua handles throttled message sending
    OGAddonMsg.ProcessQueue(elapsed)
    
    -- Queue.lua handles latency warnings
    OGAddonMsg.CheckLatencyWarnings()
    
    -- Retry.lua handles cleanup of expired retry buffer entries
    OGAddonMsg.CleanupRetryBuffer()
    
    -- Retry.lua handles cleanup of old duplicate hashes
    OGAddonMsg.CleanupDuplicateHashes()
    
    -- Chunker.lua handles timeout of incomplete reassembly entries
    OGAddonMsg.CleanupReassemblyBuffer()
end

--[[
    Public API - Version info
]]
function OGAddonMsg.GetVersion()
    return tostring(OGAddonMsg.__version)
end

function OGAddonMsg.IsLoaded()
    return OGAddonMsg.loaded and OGAddonMsg.initialized
end

function OGAddonMsg.GetActiveVersion()
    return OGAddonMsg.GetVersion()
end
