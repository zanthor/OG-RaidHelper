--[[
SavedVariablesManager (SVM) - Unified interface for OGRH_SV with integrated sync

USAGE FOR AI AGENTS:
- Reads: Use OGRH.SVM.GetPath("key.subkey") or OGRH.SVM.Get("key", "subkey")
         (Direct access works during v1, but MUST migrate to SVM before v2 cutover)
- Writes: Use OGRH.SVM.Set("key", "subkey", value, syncMetadata)
         or OGRH.SVM.SetPath("key.subkey", value, syncMetadata)

EXAMPLES:
  -- Role assignment (REALTIME sync)
  OGRH.SVM.SetPath("encounterMgmt.roles.MC.Rag.tank1", "PlayerName", {
      syncLevel = "REALTIME",
      componentType = "roles",
      scope = "encounterMgmt.roles"
  })
  
  -- Settings update (BATCH sync)
  OGRH.SVM.Set("settings", "autoSort", true, {
      syncLevel = "BATCH",
      componentType = "settings"
  })
  
  -- Player assignment (REALTIME sync)
  OGRH.SVM.SetPath("playerAssignments.PlayerName", {type="icon", value=1}, {
      syncLevel = "REALTIME",
      componentType = "assignments",
      scope = "playerAssignments"
  })

SYNC LEVELS:
- REALTIME: Instant sync (role assignments, player assignments)
- BATCH: 2-second batching (settings, notes, bulk edits)
- GRANULAR: On-demand repair only (triggered by validation)
- MANUAL: Admin push only (structure changes)

AUTOMATIC FEATURES:
- Dual-write to v2 during migration (Phase 4-6)
- Offline queue (combat/zoning)
- Checksum invalidation
- Network priority management

WoW 1.12 COMPATIBILITY:
- Uses table.getn() instead of #
- Uses string.gfind() instead of gmatch
- No continue statement - uses conditional blocks
- Event handlers use implicit globals (this, event, arg1...)
--]]

OGRH = OGRH or {}
OGRH.SVM = OGRH.SVM or {}

-- ============================================
-- SYNC CONFIGURATION
-- ============================================
OGRH.SVM.SyncConfig = {
    batchDelay = 2.0,
    pendingBatch = {},
    batchTimer = nil,
    offlineQueue = {},
    enabled = true,
    debugRead = false,   -- Toggle with /ogrh debug svm read
    debugWrite = false   -- Toggle with /ogrh debug svm write
}

-- Sync level definitions (priorities must match OGAddonMsg queue levels: CRITICAL, HIGH, NORMAL, LOW)
OGRH.SyncLevels = {
    REALTIME = { delay = 0, priority = "HIGH" },
    BATCH = { delay = 2.0, priority = "NORMAL" },
    GRANULAR = { onDemand = true },
    MANUAL = { onDemand = true }
}

-- ============================================
-- HELPER: Get Active Schema
-- ============================================
function OGRH.SVM.GetActiveSchema()
    -- Route to v2 if schemaVersion is set to "v2"
    if OGRH_SV.schemaVersion == "v2" then
        -- Use v2 schema at OGRH_SV.v2.* (permanent location)
        if not OGRH_SV.v2 then
            OGRH_SV.v2 = {}  -- Initialize if missing
        end
        return OGRH_SV.v2
    else
        -- Use v1 schema at OGRH_SV.* (default)
        return OGRH_SV
    end
end

-- ============================================
-- HELPER: Deep Copy (for dual-write)
-- ============================================
local function DeepCopy(obj, seen)
    if type(obj) ~= 'table' then return obj end
    if seen and seen[obj] then return seen[obj] end
    local s = seen or {}
    local res = setmetatable({}, getmetatable(obj))
    s[obj] = res
    for k, v in pairs(obj) do 
        res[DeepCopy(k, s)] = DeepCopy(v, s) 
    end
    return res
end

-- ============================================
-- CORE: Get Value (Read Interface)
-- ============================================
function OGRH.SVM.Get(key, subkey)
    local sv = OGRH.SVM.GetActiveSchema()
    if not sv then return nil end
    
    local value
    if subkey then
        if sv[key] then
            value = sv[key][subkey]
        else
            value = nil
        end
    else
        value = sv[key]
    end
    
    -- DEBUG: Show what we're reading
    if OGRH.SVM.SyncConfig.debugRead and OGRH.Msg then
        local path = subkey and (key .. "." .. subkey) or key
        local valuePreview = (type(value) == "table") and "{table}" or tostring(value)
        OGRH.Msg(string.format("|cff66ccff[RH-SVM]|r Reading from [%s] = %s", path, valuePreview))
    end
    
    return value
end

-- ============================================
-- CORE: Get Value from Deep Path
-- ============================================
function OGRH.SVM.GetPath(path)
    local sv = OGRH.SVM.GetActiveSchema()
    if not sv then return nil end
    
    -- Parse path using string.gfind (WoW 1.12 compatible)
    local keys = {}
    local iter = string.gfind(path, "[^.]+")
    local key = iter()
    while key do
        table.insert(keys, key)
        key = iter()
    end
    
    if table.getn(keys) == 0 then return nil end
    
    -- Navigate to value
    local current = sv
    for i = 1, table.getn(keys) do
        local k = keys[i]
        -- Convert numeric string keys to numbers for array access
        local numKey = tonumber(k)
        if numKey then k = numKey end
        
        if not current or type(current) ~= "table" then
            -- DEBUG: Show failed read
            if OGRH.SVM.SyncConfig.debugRead and OGRH.Msg then
                OGRH.Msg(string.format("|cff66ccff[RH-SVM]|r Reading from [%s] = nil (path not found)", path))
            end
            return nil
        end
        current = current[k]
    end
    
    -- DEBUG: Show what we're reading
    if OGRH.SVM.SyncConfig.debugRead and OGRH.Msg then
        local valuePreview = (type(current) == "table") and "{table}" or tostring(current)
        OGRH.Msg(string.format("|cff66ccff[RH-SVM]|r Reading from [%s] = %s", path, valuePreview))
    end
    
    return current
end

-- ============================================
-- CORE: Set Value with Integrated Sync
-- ============================================
function OGRH.SVM.Set(key, subkey, value, syncMetadata)
    local sv = OGRH.SVM.GetActiveSchema()
    if not sv then return false end
    
    -- DEBUG: Show what we're writing
    if OGRH.SVM.SyncConfig.debugWrite and OGRH.Msg then
        local path = subkey and (key .. "." .. subkey) or key
        local valuePreview = (type(value) == "table") and "{table}" or tostring(value)
        OGRH.Msg(string.format("|cff66ff66[RH-SVM]|r Writing to [%s] = %s", path, valuePreview))
    end
    
    -- Write value to active schema only
    if subkey then
        if not sv[key] then sv[key] = {} end
        sv[key][subkey] = value
    else
        sv[key] = value
    end
    
    -- Handle sync if metadata provided
    if syncMetadata then
        OGRH.SVM.HandleSync(key, subkey, value, syncMetadata)
    end
    
    return true
end

-- ============================================
-- CORE: Deep Set with Path (e.g., "key.subkey.nested")
-- ============================================
function OGRH.SVM.SetPath(path, value, syncMetadata)
    local sv = OGRH.SVM.GetActiveSchema()
    if not sv then
        if OGRH.Msg then OGRH.Msg("|cffff0000[RH-SVM]|r ERROR: GetActiveSchema returned nil") end
        return false
    end
    
    -- Parse path using string.gfind (WoW 1.12 compatible)
    local keys = {}
    local iter = string.gfind(path, "[^.]+")
    local key = iter()
    while key do
        table.insert(keys, key)
        key = iter()
    end
    
    if table.getn(keys) == 0 then
        if OGRH.Msg then OGRH.Msg("|cffff0000[RH-SVM]|r ERROR: No keys parsed from path: " .. path) end
        return false
    end
    
    -- DEBUG: Show what we're writing
    if OGRH.SVM.SyncConfig.debugWrite and OGRH.Msg then
        local valuePreview = type(value) == "table" and ("table: " .. tostring(value)) or tostring(value)
        OGRH.Msg(string.format("|cff66ff66[RH-SVM]|r Writing to [%s] = %s", path, valuePreview))
    end
    
    -- Navigate to parent table
    local current = sv
    for i = 1, table.getn(keys) - 1 do
        local k = keys[i]
        -- Convert numeric string keys to numbers for array access
        local numKey = tonumber(k)
        if numKey then k = numKey end
        
        if not current[k] then current[k] = {} end
        current = current[k]
    end
    
    -- Set value in active schema only
    local finalKey = keys[table.getn(keys)]
    -- Convert numeric string keys to numbers for array access
    local numFinalKey = tonumber(finalKey)
    if numFinalKey then finalKey = numFinalKey end
    
    current[finalKey] = value
    
    -- Handle sync if metadata provided
    if syncMetadata then
        OGRH.SVM.HandleSync(keys[1], table.concat(keys, ".", 2), value, syncMetadata)
    end
    
    return true
end

-- ============================================
-- SYNC: Route Based on Level
-- ============================================
function OGRH.SVM.HandleSync(key, subkey, value, syncMetadata)
    if not OGRH.SVM.SyncConfig.enabled then return end
    if not syncMetadata or not syncMetadata.syncLevel then return end
    
    local level = syncMetadata.syncLevel
    
    if level == "REALTIME" then
        OGRH.SVM.SyncRealtime(key, subkey, value, syncMetadata)
    elseif level == "BATCH" then
        OGRH.SVM.SyncBatch(key, subkey, value, syncMetadata)
    end
    -- GRANULAR and MANUAL are on-demand only (not triggered by writes)
end

-- ============================================
-- SYNC: Realtime (Immediate)
-- ============================================
function OGRH.SVM.SyncRealtime(key, subkey, value, syncMetadata)
    -- Check permissions based on componentType
    local playerName = UnitName("player")
    local componentType = syncMetadata.componentType or "generic"
    
    if componentType == "structure" or componentType == "metadata" then
        -- Structure changes require admin permission
        if not OGRH.CanModifyStructure or not OGRH.CanModifyStructure(playerName) then
            OGRH.SVM.QueueOffline(key, subkey, value, syncMetadata)
            return
        end
    elseif componentType == "assignments" or componentType == "roles" or componentType == "marks" or componentType == "numbers" then
        -- Assignment changes require officer/admin permission
        if not OGRH.CanModifyAssignments or not OGRH.CanModifyAssignments(playerName) then
            OGRH.SVM.QueueOffline(key, subkey, value, syncMetadata)
            return
        end
    end
    -- Other types (settings, consumes, etc.) don't require special permissions
    
    -- Check if we can sync now
    if not OGRH.CanSyncNow or not OGRH.CanSyncNow() then
        OGRH.SVM.QueueOffline(key, subkey, value, syncMetadata)
        return
    end
    
    -- Build path for sync
    local path = key
    if subkey then
        path = key .. "." .. subkey
    end
    
    -- Prepare delta change data
    local changeData = {
        type = "REALTIME_UPDATE",
        path = path,
        value = value,
        componentType = syncMetadata.componentType or "generic",
        scope = syncMetadata.scope,
        timestamp = GetTime(),
        author = UnitName("player")
    }
    
    -- Send via MessageRouter with high priority
    if OGRH.MessageRouter and OGRH.MessageTypes then
        OGRH.MessageRouter.Broadcast(
            OGRH.MessageTypes.SYNC.DELTA,
            changeData,
            {
                priority = "HIGH",  -- High priority for realtime (was "ALERT", fixed to match OGAddonMsg queue levels)
                onFailure = function()
                    -- If send fails, queue for retry
                    OGRH.SVM.QueueOffline(key, subkey, value, syncMetadata)
                end
            }
        )
    end
    
    -- Invalidate checksum for affected scope
    if syncMetadata.scope then
        OGRH.SVM.InvalidateChecksum(syncMetadata.scope)
    end
end

-- ============================================
-- SYNC: Batch (Delayed)
-- ============================================
function OGRH.SVM.SyncBatch(key, subkey, value, syncMetadata)
    -- Check permissions based on componentType
    local playerName = UnitName("player")
    local componentType = syncMetadata.componentType or "generic"
    
    if componentType == "structure" or componentType == "metadata" then
        -- Structure changes require admin permission
        if not OGRH.CanModifyStructure or not OGRH.CanModifyStructure(playerName) then
            OGRH.SVM.QueueOffline(key, subkey, value, syncMetadata)
            return
        end
    elseif componentType == "assignments" or componentType == "roles" or componentType == "marks" or componentType == "numbers" then
        -- Assignment changes require officer/admin permission
        if not OGRH.CanModifyAssignments or not OGRH.CanModifyAssignments(playerName) then
            OGRH.SVM.QueueOffline(key, subkey, value, syncMetadata)
            return
        end
    end
    -- Other types (settings, consumes, etc.) don't require special permissions
    
    -- Check if we can sync now
    if not OGRH.CanSyncNow or not OGRH.CanSyncNow() then
        OGRH.SVM.QueueOffline(key, subkey, value, syncMetadata)
        return
    end
    
    -- Add to pending batch
    local path = key
    if subkey then
        path = key .. "." .. subkey
    end
    
    table.insert(OGRH.SVM.SyncConfig.pendingBatch, {
        path = path,
        value = value,
        metadata = syncMetadata,
        timestamp = GetTime(),
        author = UnitName("player")
    })
    
    -- Schedule flush
    OGRH.SVM.ScheduleBatchFlush()
end

-- ============================================
-- SYNC: Schedule Batch Flush
-- ============================================
function OGRH.SVM.ScheduleBatchFlush()
    if OGRH.SVM.SyncConfig.batchTimer then return end
    
    -- Use OGRH.ScheduleTimer if available (from Core.lua)
    if OGRH.ScheduleTimer then
        OGRH.SVM.SyncConfig.batchTimer = OGRH.ScheduleTimer(function()
            OGRH.SVM.FlushBatch()
        end, OGRH.SVM.SyncConfig.batchDelay)
    end
end

-- ============================================
-- SYNC: Flush Batch
-- ============================================
function OGRH.SVM.FlushBatch()
    if table.getn(OGRH.SVM.SyncConfig.pendingBatch) == 0 then 
        OGRH.SVM.SyncConfig.batchTimer = nil
        return 
    end
    
    -- Prepare batch data
    local batchData = {
        type = "BATCH_UPDATE",
        updates = OGRH.SVM.SyncConfig.pendingBatch,
        timestamp = GetTime(),
        author = UnitName("player")
    }
    
    -- Send batch via MessageRouter
    if OGRH.MessageRouter and OGRH.MessageTypes then
        OGRH.MessageRouter.Broadcast(
            OGRH.MessageTypes.ASSIGN.DELTA_BATCH,
            batchData,
            {
                priority = "NORMAL",  -- Normal priority for batch
                onFailure = function()
                    -- On failure, items stay in queue and will retry on next flush
                    OGRH.Msg("|cffff0000[RH-SVM]|r Failed to send batch sync, will retry")
                end,
                onSuccess = function()
                    -- Invalidate checksums for all affected scopes
                    OGRH.SVM.InvalidateChecksumsBatch(batchData.updates)
                end
            }
        )
    end
    
    -- Clear batch and timer
    OGRH.SVM.SyncConfig.pendingBatch = {}
    OGRH.SVM.SyncConfig.batchTimer = nil
end

-- ============================================
-- SYNC: Offline Queue
-- ============================================
function OGRH.SVM.QueueOffline(key, subkey, value, syncMetadata)
    table.insert(OGRH.SVM.SyncConfig.offlineQueue, {
        key = key,
        subkey = subkey,
        value = value,
        metadata = syncMetadata
    })
end

-- ============================================
-- SYNC: Flush Offline Queue
-- ============================================
function OGRH.SVM.FlushOfflineQueue()
    if table.getn(OGRH.SVM.SyncConfig.offlineQueue) == 0 then return end
    
    for i = 1, table.getn(OGRH.SVM.SyncConfig.offlineQueue) do
        local item = OGRH.SVM.SyncConfig.offlineQueue[i]
        OGRH.SVM.HandleSync(item.key, item.subkey, item.value, item.metadata)
    end
    
    OGRH.SVM.SyncConfig.offlineQueue = {}
end

-- ============================================
-- SYNC: Checksum Invalidation
-- ============================================
function OGRH.SVM.InvalidateChecksum(scope)
    if OGRH.SyncIntegrity and OGRH.SyncIntegrity.RecordAdminModification then
        OGRH.SyncIntegrity.RecordAdminModification(scope)
    end
end

-- Invalidate checksums for batch of changes
function OGRH.SVM.InvalidateChecksumsBatch(updates)
    if not OGRH.SyncIntegrity or not OGRH.SyncIntegrity.RecordAdminModification then
        return
    end
    
    -- Collect unique scopes from all updates
    local scopes = {}
    for i = 1, table.getn(updates) do
        local update = updates[i]
        if update.metadata and update.metadata.scope then
            local scope = update.metadata.scope
            scopes[scope] = true
        end
    end
    
    -- Invalidate each unique scope once
    for scope, _ in pairs(scopes) do
        OGRH.SyncIntegrity.RecordAdminModification(scope)
    end
end

-- ============================================
-- HELPER: Check if Sync is Possible
-- ============================================
function OGRH.CanSyncNow()
    -- Can't sync in combat
    if UnitAffectingCombat("player") then
        return false
    end
    
    -- Can't sync if not in raid
    if not UnitInRaid("player") then
        return false
    end
    
    -- Can't sync while zoning
    if OGRH.SVM.SyncConfig.isZoning then
        return false
    end
    
    return true
end

-- ============================================
-- INITIALIZATION AND EVENT HANDLING
-- ============================================
-- Register combat and raid events to manage offline queue
local svmFrame = CreateFrame("Frame")
svmFrame:RegisterEvent("PLAYER_REGEN_ENABLED")  -- Left combat
svmFrame:RegisterEvent("RAID_ROSTER_UPDATE")    -- Raid roster changed
svmFrame:RegisterEvent("PLAYER_ENTERING_WORLD") -- Zoning complete
svmFrame:SetScript("OnEvent", function()
    if event == "PLAYER_REGEN_ENABLED" then
        -- Left combat - flush offline queue
        OGRH.SVM.SyncConfig.isZoning = false
        OGRH.SVM.FlushOfflineQueue()
        
    elseif event == "RAID_ROSTER_UPDATE" then
        -- Raid roster changed - flush offline queue if we just joined raid
        if GetNumRaidMembers() > 0 then
            OGRH.SVM.FlushOfflineQueue()
        end
        
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Zoning complete - clear zoning flag and flush queue
        OGRH.SVM.SyncConfig.isZoning = false
        OGRH.SVM.FlushOfflineQueue()
    end
end)

-- Track zoning state
OGRH.SVM.SyncConfig.isZoning = false

-- Hook into zone change detection (called from other systems)
function OGRH.SVM.OnZoningStart()
    OGRH.SVM.SyncConfig.isZoning = true
end

function OGRH.SVM.OnZoningEnd()
    OGRH.SVM.SyncConfig.isZoning = false
    OGRH.SVM.FlushOfflineQueue()
end

-- ============================================
-- MESSAGE HANDLERS: Receive Sync Messages
-- ============================================

-- Handle incoming REALTIME delta update
function OGRH.SVM.OnDeltaReceived(sender, data, channel)
    -- Verify sender is admin
    local currentAdmin = OGRH.GetRaidAdmin and OGRH.GetRaidAdmin()
    if not currentAdmin or sender ~= currentAdmin then
        return  -- Ignore updates from non-admins
    end
    
    -- Don't apply our own updates
    if sender == UnitName("player") then
        return
    end
    
    -- Validate data
    if not data or not data.path or not data.value then
        OGRH.Msg("|cffff0000[RH-SVM]|r Received invalid delta update")
        return
    end
    
    -- Apply update to local SavedVariables
    local success = OGRH.SVM.SetPath(data.path, data.value, nil)  -- nil = no sync (we're receiving)
    
    if success then
        -- Trigger UI updates if needed
        if OGRH.RolesUI and OGRH.RolesUI.RefreshDisplay then
            OGRH.RolesUI.RefreshDisplay()
        end
    else
        OGRH.Msg("|cffff0000[RH-SVM]|r Failed to apply delta update: " .. data.path)
    end
end

-- Handle incoming BATCH delta updates
function OGRH.SVM.OnBatchReceived(sender, data, channel)
    -- Verify sender is admin
    local currentAdmin = OGRH.GetRaidAdmin and OGRH.GetRaidAdmin()
    if not currentAdmin or sender ~= currentAdmin then
        return  -- Ignore updates from non-admins
    end
    
    -- Don't apply our own updates
    if sender == UnitName("player") then
        return
    end
    
    -- Validate data
    if not data or not data.updates then
        OGRH.Msg("|cffff0000[RH-SVM]|r Received invalid batch update")
        return
    end
    
    -- Apply all updates in batch
    local successCount = 0
    local failCount = 0
    
    for i = 1, table.getn(data.updates) do
        local update = data.updates[i]
        if update.path and update.value then
            local success = OGRH.SVM.SetPath(update.path, update.value, nil)  -- nil = no sync
            if success then
                successCount = successCount + 1
            else
                failCount = failCount + 1
            end
        end
    end
    
    -- Trigger UI updates if any succeeded
    if successCount > 0 then
        if OGRH.RolesUI and OGRH.RolesUI.RefreshDisplay then
            OGRH.RolesUI.RefreshDisplay()
        end
    end
    
    if failCount > 0 then
        OGRH.Msg(string.format("|cffffaa00[RH-SVM]|r Batch update: %d succeeded, %d failed", successCount, failCount))
    end
end

-- Register message handlers with MessageRouter
function OGRH.SVM.RegisterMessageHandlers()
    if not OGRH.MessageRouter or not OGRH.MessageTypes then
        -- MessageRouter not loaded yet - will register later
        return
    end
    
    -- Register handler for realtime delta updates
    OGRH.MessageRouter.RegisterHandler(
        OGRH.MessageTypes.SYNC.DELTA,
        OGRH.SVM.OnDeltaReceived
    )
    
    -- Register handler for batch delta updates
    OGRH.MessageRouter.RegisterHandler(
        OGRH.MessageTypes.ASSIGN.DELTA_BATCH,
        OGRH.SVM.OnBatchReceived
    )
end

-- ============================================
-- DELAYED INITIALIZATION
-- ============================================
-- Register handlers after MessageRouter loads
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:SetScript("OnEvent", function()
    if event == "ADDON_LOADED" and arg1 == "OG-RaidHelper" then
        -- Wait a moment for all modules to load
        OGRH.ScheduleTimer(function()
            OGRH.SVM.RegisterMessageHandlers()
        end, 0.5)
    end
end)

-- Success message
if DEFAULT_CHAT_FRAME then
    OGRH.Msg("|cff66ff66[RH-SVM]|r loaded")
end
