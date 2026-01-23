--[[
SavedVariablesManager (SVM) - Write interface for OGRH_SV with integrated sync

USAGE FOR AI AGENTS:
- Reads: Use direct access (OGRH_SV.key.subkey)
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
    enabled = true
}

-- Sync level definitions
OGRH.SyncLevels = {
    REALTIME = { delay = 0, priority = "ALERT" },
    BATCH = { delay = 2.0, priority = "NORMAL" },
    GRANULAR = { onDemand = true },
    MANUAL = { onDemand = true }
}

-- ============================================
-- HELPER: Get Active Schema
-- ============================================
function OGRH.SVM.GetActiveSchema()
    if OGRH_SV.schemaVersion == "v2" then
        return OGRH_SV
    else
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
    
    if subkey then
        if sv[key] then
            return sv[key][subkey]
        end
        return nil
    else
        return sv[key]
    end
end

-- ============================================
-- CORE: Set Value with Integrated Sync
-- ============================================
function OGRH.SVM.Set(key, subkey, value, syncMetadata)
    local sv = OGRH.SVM.GetActiveSchema()
    if not sv then return false end
    
    -- Write value
    if subkey then
        if not sv[key] then sv[key] = {} end
        sv[key][subkey] = value
    else
        sv[key] = value
    end
    
    -- Dual-write to v2 if migrating
    if OGRH_SV.v2 and OGRH_SV.schemaVersion ~= "v2" then
        if subkey then
            if not OGRH_SV.v2[key] then OGRH_SV.v2[key] = {} end
            OGRH_SV.v2[key][subkey] = DeepCopy(value)
        else
            OGRH_SV.v2[key] = DeepCopy(value)
        end
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
    if not sv then return false end
    
    -- Parse path using string.gfind (WoW 1.12 compatible)
    local keys = {}
    local iter = string.gfind(path, "[^.]+")
    local key = iter()
    while key do
        table.insert(keys, key)
        key = iter()
    end
    
    if table.getn(keys) == 0 then return false end
    
    -- Navigate to parent table
    local current = sv
    for i = 1, table.getn(keys) - 1 do
        local k = keys[i]
        if not current[k] then current[k] = {} end
        current = current[k]
    end
    
    -- Set value
    local finalKey = keys[table.getn(keys)]
    current[finalKey] = value
    
    -- Dual-write to v2 if migrating
    if OGRH_SV.v2 and OGRH_SV.schemaVersion ~= "v2" then
        local currentV2 = OGRH_SV.v2
        for i = 1, table.getn(keys) - 1 do
            local k = keys[i]
            if not currentV2[k] then currentV2[k] = {} end
            currentV2 = currentV2[k]
        end
        currentV2[finalKey] = DeepCopy(value)
    end
    
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
    
    -- Send via MessageRouter with high priority
    if OGRH.MessageRouter and OGRH.MessageRouter.SendMessage then
        local componentType = syncMetadata.componentType or "generic"
        OGRH.MessageRouter.SendMessage(componentType, "UPDATE", {
            path = path,
            value = value
        }, "ALERT")  -- High priority for realtime
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
        metadata = syncMetadata
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
    if table.getn(OGRH.SVM.SyncConfig.pendingBatch) == 0 then return end
    
    -- Send batch via MessageRouter
    if OGRH.MessageRouter and OGRH.MessageRouter.SendMessage then
        OGRH.MessageRouter.SendMessage("batch", "UPDATE_BATCH", {
            updates = OGRH.SVM.SyncConfig.pendingBatch
        }, "NORMAL")  -- Normal priority for batch
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
    
    return true
end

-- ============================================
-- INITIALIZATION
-- ============================================
-- Register combat events to flush offline queue
local svmFrame = CreateFrame("Frame")
svmFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
svmFrame:SetScript("OnEvent", function()
    if event == "PLAYER_REGEN_ENABLED" then
        -- Left combat - flush offline queue
        OGRH.SVM.FlushOfflineQueue()
    end
end)

-- Success message
if DEFAULT_CHAT_FRAME then
    OGRH.Msg("|cff66ff66[RH-SVM]|r loaded")
end
