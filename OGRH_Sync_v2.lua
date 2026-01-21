-- OGRH_Sync_v2.lua
-- Phase 2: Core Sync Replacement using OGAddonMsg
-- Replaces manual chunking with OGAddonMsg reliable delivery
-- Implements checksum verification and delta sync

if not OGRH then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000Error: OGRH_Sync requires OGRH_Core to be loaded first!|r")
    return
end

-- Initialize sync namespace
OGRH.Sync = OGRH.Sync or {}

--[[
    Configuration
]]

OGRH.Sync.Config = {
    CHECKSUM_POLL_INTERVAL = 30, -- Seconds between checksum broadcasts
    SYNC_TIMEOUT = 60, -- Seconds to wait for sync completion
    DELTA_BATCH_DELAY = 2.0, -- Seconds to batch rapid changes
}

--[[
    State Management
]]

OGRH.Sync.State = {
    -- Initialization
    initialized = false,
    
    -- Checksum tracking
    lastKnownChecksums = {}, -- [playerName] = checksum
    checksumMismatches = {}, -- [playerName] = {checksum, version, timestamp}
    lastChecksumBroadcast = 0,
    
    -- Active sync request
    syncRequestActive = false,
    syncRequestSender = nil,
    syncRequestTime = nil,
    
    -- Active sync transmission
    syncTransmitting = false,
    syncReceiving = false,
    syncRecipients = {},
    
    -- Delta batching
    pendingDeltas = {},
    lastDeltaFlush = 0,
    deltaFlushScheduled = false,
}

--[[
    Automatic Sync Triggers
]]

-- Notify that structure data has changed (call after any OGRH_SV modification)
function OGRH.Sync.NotifyStructureChange(changeDescription)
    if GetNumRaidMembers() == 0 then
        return -- Not in raid, no need to sync
    end
    
    if not OGRH.CanModifyStructure(UnitName("player")) then
        return -- Only admin can push structure changes
    end
    
    DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[OGRH-Sync]|r %s", changeDescription or "Structure changed"))
    
    -- Always use full sync for structure changes
    -- (Delta sync is reserved for future rapid-fire changes like assignments)
    OGRH.Versioning.IncrementDataVersion("STRUCTURE", changeDescription or "unknown")
    OGRH.Sync.BroadcastFullSync()
end

--[[
    Checksum Verification System
]]

-- Calculate checksum for current saved data
function OGRH.Sync.ComputeCurrentChecksum()
    if OGRH.EnsureSV then
        OGRH.EnsureSV()
    end
    
    local currentData = {
        encounterMgmt = OGRH_SV.encounterMgmt,
        encounterRaidMarks = OGRH_SV.encounterRaidMarks,
        encounterAssignmentNumbers = OGRH_SV.encounterAssignmentNumbers,
        encounterAnnouncements = OGRH_SV.encounterAnnouncements,
        tradeItems = OGRH_SV.tradeItems,
        consumes = OGRH_SV.consumes,
        rgo = OGRH_SV.rgo
    }
    
    return OGRH.Versioning.ComputeChecksum(currentData)
end

-- Broadcast checksum to raid
function OGRH.Sync.BroadcastChecksum()
    if GetNumRaidMembers() == 0 then
        return
    end
    
    local checksum = OGRH.Sync.ComputeCurrentChecksum()
    local version = OGRH.Versioning.GetGlobalVersion()
    
    -- Simple string format for checksum broadcast (no complex serialization needed)
    local dataString = string.format("%s;%d;%s", checksum, version, UnitName("player"))
    
    OGRH.MessageRouter.Broadcast(OGRH.MessageTypes.SYNC.CHECKSUM_STRUCTURE, dataString, {
        priority = "LOW"
    })
    
    OGRH.Sync.State.lastChecksumBroadcast = GetTime()
end

-- Handle received checksum
function OGRH.Sync.OnChecksumReceived(sender, dataString)
    -- Ignore our own broadcasts
    if sender == UnitName("player") then
        return
    end
    
    if not dataString or dataString == "" then
        return
    end
    
    -- Parse simple format: checksum;version;sender
    local checksum, versionStr, dataSender = string.match(dataString, "^([^;]+);([^;]+);(.+)$")
    if not checksum or not versionStr then
        return
    end
    
    local theirVersion = tonumber(versionStr) or 0
    
    -- Store their checksum
    OGRH.Sync.State.lastKnownChecksums[sender] = {
        checksum = checksum,
        version = theirVersion,
        timestamp = GetTime()
    }
    
    local myChecksum = OGRH.Sync.ComputeCurrentChecksum()
    local myVersion = OGRH.Versioning.GetGlobalVersion()
    
    -- Check for mismatch - WARN ONLY, do not auto-push
    if checksum ~= myChecksum then
        -- Track mismatch
        if not OGRH.Sync.State.checksumMismatches then
            OGRH.Sync.State.checksumMismatches = {}
        end
        OGRH.Sync.State.checksumMismatches[sender] = {
            checksum = checksum,
            version = theirVersion,
            timestamp = GetTime()
        }
        
        -- Count total mismatches
        local mismatchCount = 0
        for name, _ in pairs(OGRH.Sync.State.checksumMismatches) do
            mismatchCount = mismatchCount + 1
        end
        
        -- Show warning (only if admin)
        if OGRH.CanModifyStructure(UnitName("player")) then
            DEFAULT_CHAT_FRAME:AddMessage(
                string.format("|cffffff00[OGRH]|r WARNING: %d player(s) in raid with out-of-sync checksums. Use Data Management > Push Structure to sync.", mismatchCount),
                1, 0.82, 0
            )
        end
    else
        -- Remove from mismatch list if they match now
        if OGRH.Sync.State.checksumMismatches then
            OGRH.Sync.State.checksumMismatches[sender] = nil
        end
    end
end

-- Start periodic checksum broadcasts
function OGRH.Sync.StartChecksumPolling()
    -- Broadcast immediately
    OGRH.Sync.BroadcastChecksum()
    
    -- Schedule next poll cycle
    OGRH.ScheduleFunc(function()
        if OGRH.Sync and OGRH.Sync.StartChecksumPolling then
            OGRH.Sync.StartChecksumPolling()
        end
    end, OGRH.Sync.Config.CHECKSUM_POLL_INTERVAL)
end

--[[
    Full Sync System
]]

-- Request full sync from another player
function OGRH.Sync.RequestFullSync(targetPlayer)
    -- Simple string format: requester;version;checksum
    local dataString = string.format("%s;%d;%s", 
        UnitName("player"),
        OGRH.Versioning.GetGlobalVersion(),
        OGRH.Sync.ComputeCurrentChecksum()
    )
    
    OGRH.MessageRouter.SendTo(targetPlayer, OGRH.MessageTypes.SYNC.REQUEST_FULL, dataString, {
        priority = "HIGH",
        onSuccess = function()
            DEFAULT_CHAT_FRAME:AddMessage(string.format("[OGRH] Requested full sync from %s", targetPlayer))
        end,
        onFailure = function(reason)
            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff0000[OGRH]|r Full sync request failed: %s", reason))
        end
    })
end

-- Handle full sync request
function OGRH.Sync.OnFullSyncRequest(sender, dataString)
    -- Deserialize request data (not currently used, but validate format)
    local data = OGRH.Deserialize(dataString or "")
    
    if not OGRH.CanModifyStructure(UnitName("player")) then
        -- Only admins can send full sync
        DEFAULT_CHAT_FRAME:AddMessage(string.format("[OGRH] Ignoring full sync request from %s (not admin)", sender))
        return
    end
    
    -- Send full data
    OGRH.Sync.SendFullSyncTo(sender)
end

-- Send full sync to specific player
function OGRH.Sync.SendFullSyncTo(targetPlayer)
    if OGRH.EnsureSV then
        OGRH.EnsureSV()
    end
    
    -- Build data payload (exclude pools and assignments - structure only)
    local encounterMgmt = {}
    if OGRH_SV.encounterMgmt then
        encounterMgmt.raids = OGRH_SV.encounterMgmt.raids
        encounterMgmt.roles = OGRH_SV.encounterMgmt.roles
    end
    
    local syncData = {
        encounterMgmt = encounterMgmt,
        encounterRaidMarks = OGRH_SV.encounterRaidMarks or {},
        encounterAssignmentNumbers = OGRH_SV.encounterAssignmentNumbers or {},
        encounterAnnouncements = OGRH_SV.encounterAnnouncements or {},
        tradeItems = OGRH_SV.tradeItems or {},
        consumes = OGRH_SV.consumes or {},
        rgo = OGRH_SV.rgo or {},
        version = OGRH.Versioning.GetGlobalVersion(),
        checksum = OGRH.Sync.ComputeCurrentChecksum(),
        timestamp = GetTime()
    }
    
    OGRH.MessageRouter.SendTo(targetPlayer, OGRH.MessageTypes.SYNC.RESPONSE_FULL, syncData, {
        priority = "BULK",
        onSuccess = function()
            DEFAULT_CHAT_FRAME:AddMessage(string.format("[OGRH] Sent full sync to %s", targetPlayer))
        end,
        onFailure = function(reason)
            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff0000[OGRH]|r Full sync send failed: %s", reason))
        end
    })
end

-- Handle full sync response
function OGRH.Sync.OnFullSyncResponse(sender, dataString)
    -- Ignore our own broadcasts
    if sender == UnitName("player") then
        return
    end
    
    if not dataString or dataString == "" then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[OGRH]|r Invalid full sync data received")
        return
    end
    
    local data = OGRH.Deserialize(dataString)
    if not data or not data.encounterMgmt then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[OGRH]|r Invalid full sync data received")
        return
    end
    
    -- Apply all data
    if data.encounterMgmt then
        OGRH_SV.encounterMgmt = data.encounterMgmt
    end
    if data.encounterRaidMarks then
        OGRH_SV.encounterRaidMarks = data.encounterRaidMarks
    end
    if data.encounterAssignmentNumbers then
        OGRH_SV.encounterAssignmentNumbers = data.encounterAssignmentNumbers
    end
    if data.encounterAnnouncements then
        OGRH_SV.encounterAnnouncements = data.encounterAnnouncements
    end
    if data.tradeItems then
        OGRH_SV.tradeItems = data.tradeItems
    end
    if data.consumes then
        OGRH_SV.consumes = data.consumes
    end
    if data.rgo then
        OGRH_SV.rgo = data.rgo
    end
    
    -- Update version
    if data.version then
        OGRH.Versioning.SetGlobalVersion(data.version)
    end
    
    -- Verify checksum
    local newChecksum = OGRH.Sync.ComputeCurrentChecksum()
    if data.checksum and newChecksum ~= data.checksum then
        DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[OGRH]|r Warning: Checksum mismatch after full sync")
    else
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[OGRH]|r Full sync completed from %s", sender))
    end
    
    -- Refresh UI
    OGRH.Sync.RefreshAllWindows()
end

--[[
    Broadcast Sync System (for admin push)
]]

-- Broadcast full sync to all raid members
function OGRH.Sync.BroadcastFullSync()
    DEFAULT_CHAT_FRAME:AddMessage("[DEBUG] BroadcastFullSync v2 called")
    
    if not OGRH.CanModifyStructure(UnitName("player")) then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[OGRH]|r Only admin can broadcast structure")
        return
    end
    
    if GetNumRaidMembers() == 0 then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[OGRH]|r You must be in a raid to broadcast")
        return
    end
    
    if OGRH.EnsureSV then
        OGRH.EnsureSV()
    end
    
    -- Build data payload
    local encounterMgmt = {}
    if OGRH_SV.encounterMgmt then
        encounterMgmt.raids = OGRH_SV.encounterMgmt.raids
        encounterMgmt.roles = OGRH_SV.encounterMgmt.roles
    end
    
    -- Full sync = entire dataset
    local syncData = {
        encounterMgmt = encounterMgmt,
        encounterRaidMarks = OGRH_SV.encounterRaidMarks or {},
        encounterAssignmentNumbers = OGRH_SV.encounterAssignmentNumbers or {},
        encounterAnnouncements = OGRH_SV.encounterAnnouncements or {},
        tradeItems = OGRH_SV.tradeItems or {},
        consumes = OGRH_SV.consumes or {},
        rgo = OGRH_SV.rgo or {},
        version = OGRH.Versioning.IncrementDataVersion("BROADCAST", "Full structure sync"),
        checksum = OGRH.Sync.ComputeCurrentChecksum(),
        timestamp = GetTime(),
        sender = UnitName("player")
    }
    
    OGRH.MessageRouter.Broadcast(OGRH.MessageTypes.SYNC.RESPONSE_FULL, syncData, {
        priority = "BULK"
    })
end

-- DEPRECATED: Old function signature compatibility
function OGRH.Sync.BroadcastStructureSync()
    -- Check if data exists
    if not OGRH_SV or not OGRH_SV.encounterMgmt then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[OGRH]|r Failed to serialize sync data")
        return
    end
    
    OGRH.MessageRouter.Broadcast(OGRH.MessageTypes.SYNC.RESPONSE_FULL, syncDataString, {
        priority = "LOW",
        onSuccess = function()
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[OGRH]|r Structure broadcast complete")
        end,
        onFailure = function(reason)
            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff0000[OGRH]|r Broadcast failed: %s", reason))
        end
    })
end

--[[
    Delta Sync System (for incremental updates)
]]

-- Record a delta change (batched)
function OGRH.Sync.RecordDelta(changeType, target, oldValue, newValue)
    table.insert(OGRH.Sync.State.pendingDeltas, {
        type = changeType,
        target = target,
        oldValue = oldValue,
        newValue = newValue,
        timestamp = GetTime(),
        author = UnitName("player")
    })
    
    -- Auto-flush after delay
    local now = GetTime()
    if now - OGRH.Sync.State.lastDeltaFlush >= OGRH.Sync.Config.DELTA_BATCH_DELAY then
        OGRH.Sync.FlushDeltas()
    else
        -- Schedule delayed flush if not already scheduled
        if not OGRH.Sync.State.deltaFlushScheduled then
            OGRH.Sync.State.deltaFlushScheduled = true
            OGRH.ScheduleFunc(function()
                OGRH.Sync.State.deltaFlushScheduled = false
                OGRH.Sync.FlushDeltas()
            end, OGRH.Sync.Config.DELTA_BATCH_DELAY)
        end
    end
end

-- Flush pending deltas
function OGRH.Sync.FlushDeltas()
    if table.getn(OGRH.Sync.State.pendingDeltas) == 0 then
        return
    end
    
    if GetNumRaidMembers() == 0 then
        -- Not in raid, clear deltas
        OGRH.Sync.State.pendingDeltas = {}
        return
    end
    
    local deltaCount = table.getn(OGRH.Sync.State.pendingDeltas)
    DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[OGRH-Sync]|r Flushing %d delta(s)", deltaCount))
    
    local version = OGRH.Versioning.IncrementDataVersion("DELTA", "Batch delta sync")
    
    local deltaData = {
        deltas = OGRH.Sync.State.pendingDeltas,
        version = version,
        checksum = OGRH.Sync.ComputeCurrentChecksum()
    }
    
    OGRH.MessageRouter.Broadcast(OGRH.MessageTypes.SYNC.DELTA, deltaData, {
        priority = "NORMAL"
    })
    
    OGRH.Sync.State.pendingDeltas = {}
    OGRH.Sync.State.lastDeltaFlush = GetTime()
end

-- Handle received delta
function OGRH.Sync.OnDeltaReceived(sender, dataString)
    -- Ignore our own broadcasts
    if sender == UnitName("player") then
        return
    end
    
    if not dataString or dataString == "" then
        return
    end
    
    local data = OGRH.Deserialize(dataString)
    if not data or not data.deltas then
        return
    end
    
    -- Check permissions
    if not OGRH.CanModifyStructure(sender) then
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff0000[OGRH]|r Ignoring delta from %s (no permission)", sender))
        return
    end
    
    -- Apply each delta
    for i = 1, table.getn(data.deltas) do
        local delta = data.deltas[i]
        OGRH.Sync.ApplyDelta(delta)
    end
    
    -- Update version
    if data.version then
        OGRH.Versioning.SetGlobalVersion(data.version)
    end
    
    -- Verify checksum
    if data.checksum then
        local newChecksum = OGRH.Sync.ComputeCurrentChecksum()
        if newChecksum ~= data.checksum then
            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffffff00[OGRH]|r Checksum mismatch after delta from %s", sender))
        end
    end
    
    -- Refresh UI
    OGRH.Sync.RefreshAllWindows()
end

-- Apply a single delta change
function OGRH.Sync.ApplyDelta(delta)
    if not delta or not delta.type then
        return
    end
    
    -- TODO: Implement delta application based on change type
    -- This will be filled in as we migrate specific message types
    -- For now, just log it
    DEFAULT_CHAT_FRAME:AddMessage(string.format("[OGRH] Applying delta: %s on %s", delta.type, delta.target or "unknown"))
end

--[[
    UI Refresh Helper
]]

function OGRH.Sync.RefreshAllWindows()
    -- Refresh encounter setup
    if OGRH_EncounterSetupFrame and OGRH_EncounterSetupFrame.RefreshAll then
        OGRH_EncounterSetupFrame.RefreshAll()
    end
    
    -- Refresh trade settings
    if OGRH_TradeSettingsFrame and OGRH_TradeSettingsFrame.RefreshList then
        OGRH_TradeSettingsFrame.RefreshList()
    end
    
    -- Refresh encounter frame
    if OGRH_EncounterFrame and OGRH_EncounterFrame.RefreshRaidsList then
        OGRH_EncounterFrame.RefreshRaidsList()
    end
    
    -- Refresh consumes
    if OGRH_ConsumesFrame and OGRH_ConsumesFrame.RefreshConsumesList then
        OGRH_ConsumesFrame.RefreshConsumesList()
    end
    
    -- Refresh RGO
    if RGOFrame then
        for groupNum = 1, 8 do
            for slotNum = 1, 5 do
                if OGRH.UpdateRGOSlotDisplay then
                    OGRH.UpdateRGOSlotDisplay(groupNum, slotNum)
                end
            end
        end
    end
end

--[[
    Message Handler Registration
]]

function OGRH.Sync.Initialize()
    if OGRH.Sync.State.initialized then
        return -- Already initialized
    end
    OGRH.Sync.State.initialized = true
    
    -- Register message handlers
    OGRH.MessageRouter.RegisterHandler(OGRH.MessageTypes.SYNC.CHECKSUM_STRUCTURE, OGRH.Sync.OnChecksumReceived)
    OGRH.MessageRouter.RegisterHandler(OGRH.MessageTypes.SYNC.REQUEST_FULL, OGRH.Sync.OnFullSyncRequest)
    OGRH.MessageRouter.RegisterHandler(OGRH.MessageTypes.SYNC.RESPONSE_FULL, OGRH.Sync.OnFullSyncResponse)
    OGRH.MessageRouter.RegisterHandler(OGRH.MessageTypes.SYNC.DELTA, OGRH.Sync.OnDeltaReceived)
    
    -- Start checksum polling
    OGRH.Sync.StartChecksumPolling()
    
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[OGRH-Sync]|r Initialized")
end

-- Save state (called from Core on logout)
function OGRH.Sync.SaveState()
    -- Flush any pending deltas before logout
    OGRH.Sync.FlushDeltas()
end

--[[
    Data Management Functions (Import/Export/Defaults)
]]

-- Load factory defaults from OGRH_Defaults.lua
function OGRH.Sync.LoadDefaults()
    if not OGRH.FactoryDefaults or type(OGRH.FactoryDefaults) ~= "table" then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[OGRH]|r No factory defaults configured in OGRH_Defaults.lua")
        DEFAULT_CHAT_FRAME:AddMessage("Edit OGRH_Defaults.lua and paste your export string after the = sign.")
        return
    end
    
    if not OGRH.FactoryDefaults.version then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[OGRH]|r Invalid factory defaults format in OGRH_Defaults.lua")
        return
    end
    
    if OGRH.EnsureSV then
        OGRH.EnsureSV()
    end
    
    -- Import all data from factory defaults
    if OGRH.FactoryDefaults.encounterMgmt then
        OGRH_SV.encounterMgmt = OGRH.FactoryDefaults.encounterMgmt
    end
    if OGRH.FactoryDefaults.encounterRaidMarks then
        OGRH_SV.encounterRaidMarks = OGRH.FactoryDefaults.encounterRaidMarks
    end
    if OGRH.FactoryDefaults.encounterAssignmentNumbers then
        OGRH_SV.encounterAssignmentNumbers = OGRH.FactoryDefaults.encounterAssignmentNumbers
    end
    if OGRH.FactoryDefaults.encounterAnnouncements then
        OGRH_SV.encounterAnnouncements = OGRH.FactoryDefaults.encounterAnnouncements
    end
    if OGRH.FactoryDefaults.tradeItems then
        OGRH_SV.tradeItems = OGRH.FactoryDefaults.tradeItems
    end
    if OGRH.FactoryDefaults.consumes then
        OGRH_SV.consumes = OGRH.FactoryDefaults.consumes
    end
    if OGRH.FactoryDefaults.rgo then
        OGRH_SV.rgo = OGRH.FactoryDefaults.rgo
    end
    
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[OGRH]|r Factory defaults loaded successfully!")
    
    -- Refresh UI
    OGRH.Sync.RefreshAllWindows()
end

-- Export current data to serialized string
function OGRH.Sync.ExportData()
    if OGRH.EnsureSV then
        OGRH.EnsureSV()
    end
    
    -- Only export raids and roles from encounterMgmt
    local encounterMgmt = {}
    if OGRH_SV.encounterMgmt then
        encounterMgmt.raids = OGRH_SV.encounterMgmt.raids
        encounterMgmt.roles = OGRH_SV.encounterMgmt.roles
    end
    
    local exportData = {
        version = "1.0",
        encounterMgmt = encounterMgmt,
        encounterRaidMarks = OGRH_SV.encounterRaidMarks or {},
        encounterAssignmentNumbers = OGRH_SV.encounterAssignmentNumbers or {},
        encounterAnnouncements = OGRH_SV.encounterAnnouncements or {},
        tradeItems = OGRH_SV.tradeItems or {},
        consumes = OGRH_SV.consumes or {},
        rgo = OGRH_SV.rgo or {}
    }
    
    return OGRH.Serialize(exportData)
end

-- Import data from serialized string
function OGRH.Sync.ImportData(serializedData)
    if not serializedData or serializedData == "" then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[OGRH]|r No data to import")
        return false
    end
    
    local data = OGRH.Deserialize(serializedData)
    if not data then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[OGRH]|r Invalid import data format")
        return false
    end
    
    if OGRH.EnsureSV then
        OGRH.EnsureSV()
    end
    
    -- Import all data
    if data.encounterMgmt then
        OGRH_SV.encounterMgmt = data.encounterMgmt
    end
    if data.encounterRaidMarks then
        OGRH_SV.encounterRaidMarks = data.encounterRaidMarks
    end
    if data.encounterAssignmentNumbers then
        OGRH_SV.encounterAssignmentNumbers = data.encounterAssignmentNumbers
    end
    if data.encounterAnnouncements then
        OGRH_SV.encounterAnnouncements = data.encounterAnnouncements
    end
    if data.tradeItems then
        OGRH_SV.tradeItems = data.tradeItems
    end
    if data.consumes then
        OGRH_SV.consumes = data.consumes
    end
    if data.rgo then
        OGRH_SV.rgo = data.rgo
    end
    
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[OGRH]|r Data imported successfully!")
    
    -- Refresh UI
    OGRH.Sync.RefreshAllWindows()
    
    return true
end

DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[RH-Sync]|r Loaded (Phase 2)")
