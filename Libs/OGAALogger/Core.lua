--[[
    _OGAALogger - Core Logging System
    
    Captures addon output from DEFAULT_CHAT_FRAME and stores in circular buffer.
    Maintains session markers and provides message management.
]]

-- Global namespace
OGAALogger = OGAALogger or {}

-- Internal state
OGAALogger.State = {
    initialized = false,
    messages = {},
    maxMessages = 500,
    sessionCount = 0,
    originalErrorHandler = nil
}

-- SavedVariables initialization (will be nil until ADDON_LOADED)
OGAAL_SV = OGAAL_SV or {}

-- Initialize SavedVariables structure
local function InitializeSavedVars()
    OGAAL_SV.messages = OGAAL_SV.messages or {}
    OGAAL_SV.sessionCount = OGAAL_SV.sessionCount or 0
    OGAAL_SV.registeredAddons = OGAAL_SV.registeredAddons or {}
    
    -- Remove any duplicate registrations
    local seen = {}
    local cleaned = {}
    for i = 1, table.getn(OGAAL_SV.registeredAddons) do
        local addon = OGAAL_SV.registeredAddons[i]
        if not seen[addon] then
            seen[addon] = true
            table.insert(cleaned, addon)
        end
    end
    OGAAL_SV.registeredAddons = cleaned
end

--[[
    Initialize the logger system
]]
function OGAALogger.Initialize()
    if OGAALogger.State.initialized then
        return
    end
    
    -- Initialize SavedVariables structure first
    InitializeSavedVars()
    
    -- Preserve any messages captured before Initialize() ran (during file load)
    local preinitMessages = OGAALogger.State.messages or {}
    
    -- Restore messages from SavedVariables
    if OGAAL_SV.messages and table.getn(OGAAL_SV.messages) > 0 then
        -- Merge: old saved messages at bottom, new preinit messages at top
        for i = table.getn(OGAAL_SV.messages), 1, -1 do
            table.insert(preinitMessages, OGAAL_SV.messages[i])
        end
    end
    OGAALogger.State.messages = preinitMessages
    
    if OGAAL_SV.sessionCount then
        OGAALogger.State.sessionCount = OGAAL_SV.sessionCount
    end
    
    -- Register self for error capture
    table.insert(OGAAL_SV.registeredAddons, "_OGAALogger")
    
    -- Hook error frame for addon error capture
    OGAALogger.HookErrorFrame()
    
    -- Add session marker
    OGAALogger.AddSessionMarker()
    
    OGAALogger.State.initialized = true
end

--[[
    Hook DEFAULT_CHAT_FRAME to capture error messages
]]
function OGAALogger.HookErrorFrame()
    if OGAALogger.State.originalErrorHandler then
        return  -- Already hooked
    end
    
    -- Store original AddMessage
    OGAALogger.State.originalErrorHandler = DEFAULT_CHAT_FRAME.AddMessage
    
    -- Replace with hooked version
    DEFAULT_CHAT_FRAME.AddMessage = function(frame, text, r, g, b, id, unknown)
        -- Call original function first
        OGAALogger.State.originalErrorHandler(frame, text, r, g, b, id, unknown)
        
        -- Check if this is an error message (red text) and matches registered addon
        if r and r > 0.9 and g and g < 0.2 and b and b < 0.2 then  -- Red text
            -- Check if error contains any registered addon folder
            if text and OGAAL_SV.registeredAddons then
                for i = 1, table.getn(OGAAL_SV.registeredAddons) do
                    local addonFolder = OGAAL_SV.registeredAddons[i]
                    if string.find(text, addonFolder) then
                        -- Capture this error
                        OGAALogger.CaptureMessage("LUA-ERROR", text)
                        break
                    end
                end
            end
        end
    end
end

--[[
    Capture a message and add to log buffer
    
    @param source (string) - Message source
    @param message (string) - Pre-formatted message text
]]
function OGAALogger.CaptureMessage(source, message)
    if not source or not message or source == "" or message == "" then
        return
    end
    
    -- Create timestamp
    local timestamp = date("%Y-%m-%d %H:%M:%S")
    
    -- Create message object
    local msgObj = {
        timestamp = timestamp,
        source = source,
        text = message
    }
    
    -- Add to buffer (newest at top)
    table.insert(OGAALogger.State.messages, 1, msgObj)
    
    -- Enforce max message limit
    while table.getn(OGAALogger.State.messages) > OGAALogger.State.maxMessages do
        table.remove(OGAALogger.State.messages)
    end
    
    -- Update UI if open
    if OGAALogger.UI and OGAALogger.UI.IsShown() then
        OGAALogger.UI.Refresh()
    end
end

--[[
    Add a session marker to the log
]]
function OGAALogger.AddSessionMarker()
    OGAALogger.State.sessionCount = OGAALogger.State.sessionCount + 1
    
    local timestamp = date("%Y-%m-%d %H:%M:%S")
    local sessionMsg = string.format("[%s] ==================== SESSION %d START ====================", timestamp, OGAALogger.State.sessionCount)
    
    local msgObj = {
        timestamp = timestamp,
        source = "SYSTEM",
        text = sessionMsg,
        isSessionMarker = true
    }
    
    -- Add to buffer (newest at top)
    table.insert(OGAALogger.State.messages, 1, msgObj)
    
    -- Enforce max message limit
    while table.getn(OGAALogger.State.messages) > OGAALogger.State.maxMessages do
        table.remove(OGAALogger.State.messages)
    end
    
    -- Update UI if open
    if OGAALogger.UI and OGAALogger.UI.IsShown() then
        OGAALogger.UI.Refresh()
    end
end

--[[
    Clear all logged messages
]]
function OGAALogger.ClearMessages()
    OGAALogger.State.messages = {}
    OGAAL_SV.messages = {}
    
    -- Update UI if open
    if OGAALogger.UI and OGAALogger.UI.IsShown() then
        OGAALogger.UI.Refresh()
    end
end

--[[
    Get all logged messages
    
    @return (table) - Array of message objects
]]
function OGAALogger.GetMessages()
    return OGAALogger.State.messages
end

--[[
    Save messages to SavedVariables
]]
function OGAALogger.Save()
    OGAAL_SV.messages = OGAALogger.State.messages
    OGAAL_SV.sessionCount = OGAALogger.State.sessionCount
    -- registeredAddons saved automatically as part of OGAAL_SV
end

--[[
    Register an addon folder for error capture
    
    @param addonFolder (string) - Addon folder name (e.g., "OG-RaidHelper")
    @return (boolean) - True if registered, false if already registered
]]
function OGAALogger.RegisterAddon(addonFolder)
    if not addonFolder or addonFolder == "" then
        return false
    end
    
    -- Ensure SavedVariables are initialized
    InitializeSavedVars()
    
    -- Check if already registered
    for i = 1, table.getn(OGAAL_SV.registeredAddons) do
        if OGAAL_SV.registeredAddons[i] == addonFolder then
            return false  -- Already registered
        end
    end
    
    table.insert(OGAAL_SV.registeredAddons, addonFolder)
    return true
end

--[[
    Unregister an addon by index
    
    @param index (number) - Index in registered addons list
    @return (boolean) - True if removed
]]
function OGAALogger.UnregisterAddon(index)
    if not index or index < 1 or index > table.getn(OGAAL_SV.registeredAddons) then
        return false
    end
    
    table.remove(OGAAL_SV.registeredAddons, index)
    return true
end

--[[
    Get list of registered addons
    
    @return (table) - Array of registered addon folders
]]
function OGAALogger.GetRegisteredAddons()
    return OGAAL_SV.registeredAddons or {}
end

-- Event frame for initialization
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGOUT")

eventFrame:SetScript("OnEvent", function()
    if event == "ADDON_LOADED" and arg1 == "_OGAALogger" then
        OGAALogger.Initialize()
    elseif event == "PLAYER_LOGOUT" then
        -- Save on logout
        OGAALogger.Save()
    end
end)
