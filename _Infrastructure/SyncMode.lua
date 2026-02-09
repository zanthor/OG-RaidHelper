-- SyncMode.lua
-- Manages admin-controlled sync mode (enable/disable all sync processes)

if not OGRH then
    return
end

OGRH.SyncMode = OGRH.SyncMode or {}

-- State
OGRH.SyncMode.State = {
    broadcastTimer = nil,
    broadcastInterval = 5.0, -- Broadcast every 5 seconds
    isClientWaiting = false,
    enabled = true, -- In-memory only, not persisted
    clientTimeoutTimer = nil,
    lastSyncOffReceived = nil
}

--[[
    ============================================================================
    ADMIN SIDE: Sync Mode Broadcasts
    ============================================================================
]]

-- Start broadcasting sync-off status
function OGRH.SyncMode.StartSyncOffBroadcast()
    OGRH.Msg("|cffaaaaaa[RH-SyncMode]|r StartSyncOffBroadcast() called")
    
    -- Stop any existing broadcast
    OGRH.SyncMode.StopSyncOffBroadcast()
    
    -- Send initial broadcast
    OGRH.SyncMode.BroadcastSyncOff()
    
    -- Show waiting panel on admin's client too
    if OGRH.SyncRepairUI and OGRH.SyncRepairUI.ShowWaitingPanel then
        OGRH.SyncRepairUI.ShowWaitingPanel("sync_disabled_admin")
    end
    
    -- Schedule repeating broadcast
    local function repeatBroadcast()
        OGRH.SyncMode.BroadcastSyncOff()
        
        -- Schedule next broadcast
        OGRH.SyncMode.State.broadcastTimer = OGRH.ScheduleTimer(repeatBroadcast, OGRH.SyncMode.State.broadcastInterval)
    end
    
    OGRH.SyncMode.State.broadcastTimer = OGRH.ScheduleTimer(repeatBroadcast, OGRH.SyncMode.State.broadcastInterval)
    OGRH.Msg(string.format("|cffaaaaaa[RH-SyncMode]|r Scheduled repeating broadcasts every %.0fs", OGRH.SyncMode.State.broadcastInterval))
end

-- Stop broadcasting sync-off status
function OGRH.SyncMode.StopSyncOffBroadcast()
    OGRH.Msg("|cffaaaaaa[RH-SyncMode]|r StopSyncOffBroadcast() called")
    
    if OGRH.SyncMode.State.broadcastTimer then
        OGRH.CancelTimer(OGRH.SyncMode.State.broadcastTimer)
        OGRH.SyncMode.State.broadcastTimer = nil
        OGRH.Msg("|cffaaaaaa[RH-SyncMode]|r Cancelled repeating broadcast timer")
    end
    
    -- Hide waiting panel on admin's client
    if OGRH.SyncRepairUI and OGRH.SyncRepairUI.HideWaitingPanel then
        OGRH.SyncRepairUI.HideWaitingPanel()
    end
    
    -- Send sync-on broadcast
    OGRH.SyncMode.BroadcastSyncOn()
    
    -- Update UI button after a brief delay to ensure state is propagated
    OGRH.ScheduleTimer(function()
        if OGRH_EncounterFrame and OGRH_EncounterFrame.UpdateSyncButton then
            OGRH_EncounterFrame.UpdateSyncButton()
            OGRH.Msg("|cff00ff00[RH-SyncMode]|r Button updated via delayed call")
        end
    end, 0.1)
end

-- Broadcast sync-off message
function OGRH.SyncMode.BroadcastSyncOff()
    if not OGRH.MessageRouter or not OGRH.MessageTypes then
        OGRH.Msg("|cffff0000[RH-SyncMode ERROR]|r MessageRouter or MessageTypes not available")
        return
    end
    
    OGRH.Msg("|cffaaaaaa[RH-SyncMode DEBUG]|r Broadcasting sync-off message")
    
    local success = OGRH.MessageRouter.Broadcast(
        OGRH.MessageTypes.SYNC.MODE_OFF,
        {
            timestamp = GetTime()
        },
        {
            priority = "HIGH",
            channel = "RAID"
        }
    )
    
    if success then
        OGRH.Msg("|cff00ff00[RH-SyncMode]|r Sync-off broadcast sent successfully")
    else
        OGRH.Msg("|cffff0000[RH-SyncMode ERROR]|r Sync-off broadcast FAILED!")
    end
end

-- Broadcast sync-on message
function OGRH.SyncMode.BroadcastSyncOn()
    if not OGRH.MessageRouter or not OGRH.MessageTypes then
        OGRH.Msg("|cffff0000[RH-SyncMode ERROR]|r MessageRouter or MessageTypes not available")
        return
    end
    
    OGRH.Msg("|cffaaaaaa[RH-SyncMode DEBUG]|r Broadcasting sync-on message")
    
    local success = OGRH.MessageRouter.Broadcast(
        OGRH.MessageTypes.SYNC.MODE_ON,
        {
            timestamp = GetTime()
        },
        {
            priority = "HIGH",
            channel = "RAID"
        }
    )
    
    if success then
        OGRH.Msg("|cff00ff00[RH-SyncMode]|r Sync-on broadcast sent successfully")
    else
        OGRH.Msg("|cffff0000[RH-SyncMode ERROR]|r Sync-on broadcast FAILED!")
    end
end

-- Enable sync mode (for admin button)
function OGRH.SyncMode.EnableSync()
    OGRH.Msg("|cffaaaaaa[RH-SyncMode]|r EnableSync() called")
    
    -- Enable sync mode in memory
    OGRH.SyncMode.State.enabled = true
    
    -- Stop broadcasting and send sync-on
    OGRH.SyncMode.StopSyncOffBroadcast()
    
    -- Update UI button if it exists (use global frame name)
    if OGRH_EncounterFrame and OGRH_EncounterFrame.UpdateSyncButton then
        OGRH_EncounterFrame.UpdateSyncButton()
        OGRH.Msg("|cff00ff00[RH-SyncMode]|r Updated button via OGRH_EncounterFrame")
    else
        OGRH.Msg("|cffff9900[RH-SyncMode]|r OGRH_EncounterFrame or UpdateSyncButton not found")
    end
    
    OGRH.Msg("|cff00ff00[RH-SyncMode]|r Sync mode re-enabled")
end

--[[
    ============================================================================
    CLIENT SIDE: Handle Sync Mode Messages
    ============================================================================
]]

-- Handle sync-off message
function OGRH.SyncMode.OnSyncModeOff(sender, data, channel)
    OGRH.Msg("|cff00ff00>>> SYNC MODE OFF HANDLER CALLED <<<|r")
    OGRH.Msg(string.format("|cffaaaaaa[RH-SyncMode]|r OnSyncModeOff received from %s (channel: %s)", sender, tostring(channel)))
    
    -- Verify sender is raid admin
    if not OGRH.IsRaidAdmin or not OGRH.IsRaidAdmin(sender) then
        OGRH.Msg("|cffff0000[RH-SyncMode]|r Ignoring sync-off from non-admin: " .. sender)
        return
    end
    
    OGRH.Msg("|cff00ff00[RH-SyncMode]|r Sender verified as raid admin")
    
    -- Update last received timestamp
    OGRH.SyncMode.State.lastSyncOffReceived = GetTime()
    
    -- Show waiting panel if not already shown
    if not OGRH.SyncMode.State.isClientWaiting then
        OGRH.SyncMode.State.isClientWaiting = true
        OGRH.Msg("|cffaaaaaa[RH-SyncMode]|r Attempting to show waiting panel...")
        
        if OGRH.SyncRepairUI and OGRH.SyncRepairUI.ShowWaitingPanel then
            -- Pass special "sync_disabled" mode to ShowWaitingPanel
            OGRH.SyncRepairUI.ShowWaitingPanel("sync_disabled")
            OGRH.Msg("|cff00ff00[RH-SyncMode]|r Waiting panel shown successfully")
        else
            OGRH.Msg("|cffff0000[RH-SyncMode ERROR]|r SyncRepairUI.ShowWaitingPanel not available!")
        end
    end
    
    -- Start/restart client timeout (auto-hide after 10 seconds of no messages)
    if OGRH.SyncMode.State.clientTimeoutTimer then
        OGRH.CancelTimer(OGRH.SyncMode.State.clientTimeoutTimer)
    end
    
    OGRH.SyncMode.State.clientTimeoutTimer = OGRH.ScheduleTimer(function()
        local timeSinceLastMsg = GetTime() - (OGRH.SyncMode.State.lastSyncOffReceived or 0)
        if timeSinceLastMsg >= 10 then
            OGRH.Msg("|cffff9900[RH-SyncMode]|r No sync-off packet for 10s - assuming admin re-enabled sync")
            OGRH.SyncMode.State.isClientWaiting = false
            if OGRH.SyncRepairUI and OGRH.SyncRepairUI.HideWaitingPanel then
                OGRH.SyncRepairUI.HideWaitingPanel()
            end
        end
    end, 10.0)
end

-- Handle sync-on message
function OGRH.SyncMode.OnSyncModeOn(sender, data, channel)
    OGRH.Msg(string.format("|cffaaaaaa[RH-SyncMode]|r OnSyncModeOn received from %s (channel: %s)", sender, tostring(channel)))
    
    -- Cancel client timeout timer
    if OGRH.SyncMode.State.clientTimeoutTimer then
        OGRH.CancelTimer(OGRH.SyncMode.State.clientTimeoutTimer)
        OGRH.SyncMode.State.clientTimeoutTimer = nil
    end
    
    -- Verify sender is raid admin
    if not OGRH.IsRaidAdmin or not OGRH.IsRaidAdmin(sender) then
        OGRH.Msg("|cffff0000[RH-SyncMode]|r Ignoring sync-on from non-admin: " .. sender)
        return
    end
    
    OGRH.Msg("|cff00ff00[RH-SyncMode]|r Sender verified as raid admin")
    
    -- Hide waiting panel
    if OGRH.SyncMode.State.isClientWaiting then
        OGRH.SyncMode.State.isClientWaiting = false
        
        if OGRH.SyncRepairUI and OGRH.SyncRepairUI.HideWaitingPanel then
            OGRH.SyncRepairUI.HideWaitingPanel()
            OGRH.Msg("|cff00ff00[RH-SyncMode]|r Waiting panel hidden")
        end
        
        OGRH.Msg("|cff00ff00[RH-Sync]|r Sync mode re-enabled by admin")
    else
        OGRH.Msg("|cffaaaaaa[RH-SyncMode]|r Client was not in waiting state")
    end
end

--[[
    ============================================================================
    SYNC MODE CHECKS
    ============================================================================
]]

-- Check if sync mode is enabled
function OGRH.SyncMode.IsSyncEnabled()
    -- Use in-memory state only (not saved variables)
    return OGRH.SyncMode.State.enabled
end

-- Check if we should allow checksum broadcasts
function OGRH.SyncMode.CanBroadcastChecksum()
    -- Admin can always broadcast (to tell clients sync is off)
    if OGRH.IsRaidAdmin and OGRH.IsRaidAdmin(UnitName("player")) then
        return true
    end
    
    -- Clients should not broadcast if sync is disabled
    return OGRH.SyncMode.IsSyncEnabled()
end

-- Check if we should allow delta updates
function OGRH.SyncMode.CanSendDeltaUpdate()
    return OGRH.SyncMode.IsSyncEnabled()
end

-- Check if we should allow repair requests
function OGRH.SyncMode.CanRequestRepair()
    return OGRH.SyncMode.IsSyncEnabled()
end

--[[
    ============================================================================
    INITIALIZATION
    ============================================================================
]]

-- Initialize sync mode state (always defaults to enabled on load)
function OGRH.SyncMode.Initialize()
    if not OGRH.SVM then
        OGRH.Msg("|cffff0000[RH-SyncMode]|r Cannot initialize - SVM not available")
        return
    end
    
    -- Delete the saved variable entry so it doesn't persist across reloads
    local sv = OGRH.SVM.GetActiveSchema()
    if sv and sv.syncMode then
        sv.syncMode = nil
        OGRH.Msg("|cff00ff00[RH-SyncMode]|r Cleared persisted sync mode state")
    end
    
    -- Set to enabled in memory only (won't persist since we're using in-memory state)
    OGRH.SyncMode.State.enabled = true
    OGRH.Msg("|cff00ff00[RH-SyncMode]|r Initialized - sync mode enabled by default")
end

-- Register message handlers
function OGRH.SyncMode.RegisterHandlers()
    if not OGRH.MessageRouter or not OGRH.MessageTypes then
        OGRH.Msg("|cffff0000[RH-SyncMode]|r Cannot register handlers - MessageRouter or MessageTypes not available")
        return false
    end
    
    if not OGRH.MessageTypes.SYNC or not OGRH.MessageTypes.SYNC.MODE_OFF or not OGRH.MessageTypes.SYNC.MODE_ON then
        OGRH.Msg("|cffff0000[RH-SyncMode ERROR]|r Message type constants not found in MessageTypes.SYNC!")
        return false
    end
    
    OGRH.Msg("|cff00ff00[RH-SyncMode]|r Registering sync mode message handlers")
    
    -- Register sync mode messages
    local success1 = OGRH.MessageRouter.RegisterHandler(
        OGRH.MessageTypes.SYNC.MODE_OFF,
        OGRH.SyncMode.OnSyncModeOff
    )
    
    local success2 = OGRH.MessageRouter.RegisterHandler(
        OGRH.MessageTypes.SYNC.MODE_ON,
        OGRH.SyncMode.OnSyncModeOn
    )
    
    if success1 == false or success2 == false then
        OGRH.Msg("|cffff0000[RH-SyncMode ERROR]|r Handler registration failed!")
        return false
    end
    
    OGRH.Msg("|cff00ff00[RH-SyncMode]|r Message handlers registered successfully")
    return true
end

-- Initialize on load
OGRH.SyncMode.Initialize()

-- Update UI button after initialization
if OGRH_EncounterFrame and OGRH_EncounterFrame.UpdateSyncButton then
    OGRH_EncounterFrame.UpdateSyncButton()
end

local handlersRegistered = false
if OGRH.MessageRouter and OGRH.MessageTypes then
    handlersRegistered = OGRH.SyncMode.RegisterHandlers()
    
    -- Verify message types exist
    if handlersRegistered and OGRH.MessageTypes.SYNC and OGRH.MessageTypes.SYNC.MODE_OFF and OGRH.MessageTypes.SYNC.MODE_ON then
        OGRH.Msg(string.format("|cff00ff00[RH-SyncMode]|r Message types verified: MODE_OFF=%s, MODE_ON=%s", 
            OGRH.MessageTypes.SYNC.MODE_OFF, OGRH.MessageTypes.SYNC.MODE_ON))
    end
else
    OGRH.Msg("|cffff9900[RH-SyncMode]|r MessageRouter not ready - will retry handler registration...")
end

-- Delayed registration fallback if initial registration failed
if not handlersRegistered then
    OGRH.ScheduleTimer(function()
        if not handlersRegistered and OGRH.MessageRouter and OGRH.MessageTypes then
            OGRH.Msg("|cffff9900[RH-SyncMode]|r Retrying handler registration...")
            handlersRegistered = OGRH.SyncMode.RegisterHandlers()
        end
    end, 2.0)
end

-- Delayed UI button update to ensure it's created
OGRH.ScheduleTimer(function()
    if OGRH_EncounterFrame and OGRH_EncounterFrame.UpdateSyncButton then
        OGRH_EncounterFrame.UpdateSyncButton()
        OGRH.Msg("|cff00ff00[RH-SyncMode]|r UI button updated after reload")
    end
end, 0.5)
