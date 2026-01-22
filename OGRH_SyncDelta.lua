-- OGRH_SyncDelta.lua (Turtle-WoW 1.12)
-- Delta sync system for incremental updates
-- Phase 3A Implementation

OGRH = OGRH or {}
OGRH.SyncDelta = {}

--[[
    Delta Sync State
    
    Phase 3A Features:
    - Track changes since last sync
    - Batch changes during rapid edits
    - Smart sync triggers (avoid combat, zoning)
    - Queue changes for offline/combat scenarios
]]

OGRH.SyncDelta.State = {
    pendingChanges = {},
    batchDelay = 2.0,  -- seconds
    lastBatchTime = 0,
    flushTimer = nil,
    offlineQueue = {},
    isZoning = false
}

--[[
    Smart Sync Triggers
]]

-- Check if sync can be performed now
function OGRH.CanSyncNow()
    -- Check combat status
    if UnitAffectingCombat("player") then
        return false, "In combat"
    end
    
    -- Check zoning status
    if OGRH.SyncDelta.State.isZoning then
        return false, "Zoning"
    end
    
    -- Check if in raid
    if GetNumRaidMembers() == 0 then
        return false, "Not in raid"
    end
    
    return true
end

-- Set zoning flag (called from event handlers)
function OGRH.SyncDelta.SetZoning(isZoning)
    OGRH.SyncDelta.State.isZoning = isZoning
end

--[[
    Offline Queue Management
]]

-- Queue change when sync cannot be performed
function OGRH.SyncDelta.QueueChange(changeData)
    if GetNumRaidMembers() == 0 then
        table.insert(OGRH.SyncDelta.State.offlineQueue, changeData)
        return true
    end
    return false
end

-- Flush offline queue when joining raid
function OGRH.SyncDelta.FlushOfflineQueue()
    if table.getn(OGRH.SyncDelta.State.offlineQueue) == 0 then
        return
    end
    
    -- Move offline queue to pending changes
    for i = 1, table.getn(OGRH.SyncDelta.State.offlineQueue) do
        table.insert(OGRH.SyncDelta.State.pendingChanges, OGRH.SyncDelta.State.offlineQueue[i])
    end
    
    OGRH.SyncDelta.State.offlineQueue = {}
    
    -- Flush immediately
    OGRH.SyncDelta.FlushChangeBatch()
end

--[[
    Delta Change Recording
]]

-- Record a role change for delta sync
function OGRH.SyncDelta.RecordRoleChange(playerName, newRole, oldRole)
    local changeData = {
        type = "ROLE",
        player = playerName,
        newValue = newRole,
        oldValue = oldRole,
        timestamp = GetTime(),
        author = UnitName("player")
    }
    
    -- Add to pending batch
    table.insert(OGRH.SyncDelta.State.pendingChanges, changeData)
    
    -- Check if we can sync now (not in combat/zoning)
    local canSync, reason = OGRH.CanSyncNow()
    if canSync then
        -- Schedule flush with batching delay
        OGRH.SyncDelta.ScheduleFlush()
    end
    -- If blocked (combat/zoning), changes stay queued until conditions clear
end

-- Record a swap operation as atomic transaction (both players swapped in one change)
function OGRH.SyncDelta.RecordSwapChange(player1, player2, assignData1, assignData2)
    local changeData = {
        type = "SWAP",
        player1 = player1,
        player2 = player2,
        assignData1 = assignData1,  -- Contains raid, encounter, roleIndex, slotIndex for player1's NEW position
        assignData2 = assignData2,  -- Contains raid, encounter, roleIndex, slotIndex for player2's NEW position
        timestamp = GetTime(),
        author = UnitName("player")
    }
    
    -- Add to pending batch
    table.insert(OGRH.SyncDelta.State.pendingChanges, changeData)
    
    -- Check if we can sync now (not in combat/zoning)
    local canSync, reason = OGRH.CanSyncNow()
    if canSync then
        -- Schedule flush with batching delay
        OGRH.SyncDelta.ScheduleFlush()
    end
end

-- Record a player assignment change for delta sync
function OGRH.SyncDelta.RecordAssignmentChange(playerName, assignmentType, assignmentValue, oldValue)
    local changeData = {
        type = "ASSIGNMENT",
        player = playerName,
        assignmentType = assignmentType,
        newValue = assignmentValue,
        oldValue = oldValue,
        timestamp = GetTime(),
        author = UnitName("player")
    }
    
    -- Add to pending batch
    table.insert(OGRH.SyncDelta.State.pendingChanges, changeData)
    
    -- Check if we can sync now (not in combat/zoning)
    local canSync, reason = OGRH.CanSyncNow()
    if canSync then
        -- Schedule flush with batching delay
        OGRH.SyncDelta.ScheduleFlush()
    end
    -- If blocked (combat/zoning), changes stay queued until conditions clear
end

-- Record a group assignment change for delta sync
function OGRH.SyncDelta.RecordGroupChange(playerName, newGroup, oldGroup)
    local changeData = {
        type = "GROUP",
        player = playerName,
        newValue = newGroup,
        oldValue = oldGroup,
        timestamp = GetTime(),
        author = UnitName("player")
    }
    
    -- Add to pending batch
    table.insert(OGRH.SyncDelta.State.pendingChanges, changeData)
    
    -- Check if we can sync now (not in combat/zoning)
    local canSync, reason = OGRH.CanSyncNow()
    if canSync then
        -- Schedule flush with batching delay
        OGRH.SyncDelta.ScheduleFlush()
    end
    -- If blocked (combat/zoning), changes stay queued until conditions clear
end

-- Record a structure change (raid/encounter/role CRUD operations) for delta sync
function OGRH.SyncDelta.RecordStructureChange(structureType, operation, details)
    local changeData = {
        type = "STRUCTURE",
        structureType = structureType,  -- "RAID", "ENCOUNTER", "ROLE"
        operation = operation,  -- "ADD", "DELETE", "RENAME", "REORDER"
        details = details,  -- Table with operation-specific details (names, old/new values, positions, etc.)
        timestamp = GetTime(),
        author = UnitName("player")
    }
    
    -- Add to pending batch
    table.insert(OGRH.SyncDelta.State.pendingChanges, changeData)
    
    -- Check if we can sync now (not in combat/zoning)
    local canSync, reason = OGRH.CanSyncNow()
    if canSync then
        -- Schedule flush with batching delay
        OGRH.SyncDelta.ScheduleFlush()
    end
    -- If blocked (combat/zoning), changes stay queued until conditions clear
end

-- Record a settings change (advanced settings for raids/encounters) for delta sync
function OGRH.SyncDelta.RecordSettingsChange(raidName, encounterName, settingsData)
    local changeData = {
        type = "SETTINGS",
        raidName = raidName,
        encounterName = encounterName,  -- nil for raid-level settings
        settings = settingsData,  -- Complete settings object (consumeTracking and bigwigs)
        timestamp = GetTime(),
        author = UnitName("player")
    }
    
    -- Add to pending batch
    table.insert(OGRH.SyncDelta.State.pendingChanges, changeData)
    
    -- Check if we can sync now (not in combat/zoning)
    local canSync, reason = OGRH.CanSyncNow()
    if canSync then
        -- Schedule flush with batching delay
        OGRH.SyncDelta.ScheduleFlush()
    end
    -- If blocked (combat/zoning), changes stay queued until conditions clear
end

--[[
    Batch Flushing
]]

-- Schedule a delayed flush
function OGRH.SyncDelta.ScheduleFlush()
    local now = GetTime()
    local timeSinceLastFlush = now - OGRH.SyncDelta.State.lastBatchTime
    
    -- If enough time has passed, flush immediately
    if timeSinceLastFlush >= OGRH.SyncDelta.State.batchDelay then
        OGRH.SyncDelta.FlushChangeBatch()
        return
    end
    
    -- Otherwise, schedule a delayed flush if not already scheduled
    if not OGRH.SyncDelta.State.flushTimer then
        local delay = OGRH.SyncDelta.State.batchDelay - timeSinceLastFlush
        OGRH.SyncDelta.State.flushTimer = OGRH.ScheduleFunc(function()
            OGRH.SyncDelta.State.flushTimer = nil
            OGRH.SyncDelta.FlushChangeBatch()
        end, delay)
    end
end

-- Flush pending batched changes
function OGRH.SyncDelta.FlushChangeBatch()
    if table.getn(OGRH.SyncDelta.State.pendingChanges) == 0 then
        return
    end
    
    -- Clear flush timer
    OGRH.SyncDelta.State.flushTimer = nil
    
    -- Check if we can sync now
    local canSync, reason = OGRH.CanSyncNow()
    if not canSync then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff9900[OGRH-Delta]|r Cannot sync now: " .. (reason or "unknown") .. " - Queuing " .. table.getn(OGRH.SyncDelta.State.pendingChanges) .. " changes")
        -- Move to offline queue
        for i = 1, table.getn(OGRH.SyncDelta.State.pendingChanges) do
            table.insert(OGRH.SyncDelta.State.offlineQueue, OGRH.SyncDelta.State.pendingChanges[i])
        end
        OGRH.SyncDelta.State.pendingChanges = {}
        return
    end
    
    -- Increment version
    local version = OGRH.Versioning and OGRH.Versioning.IncrementDataVersion and 
                    OGRH.Versioning.IncrementDataVersion("DELTA", "Batch delta sync") or 1
    
    -- Build delta data
    local deltaData = {
        changes = OGRH.SyncDelta.State.pendingChanges,
        version = version,
        timestamp = GetTime(),
        author = UnitName("player")
    }
    
    -- Send via MessageRouter (auto-serializes tables)
    if OGRH.MessageRouter and OGRH.MessageRouter.Broadcast then
        OGRH.MessageRouter.Broadcast(OGRH.MessageTypes.ASSIGN.DELTA_BATCH, deltaData, {
            priority = "NORMAL"
        })
    end
    
    -- Clear pending changes
    OGRH.SyncDelta.State.pendingChanges = {}
    OGRH.SyncDelta.State.lastBatchTime = GetTime()
end

-- Force immediate flush (for testing or manual triggers)
function OGRH.SyncDelta.ForceFlush()
    OGRH.SyncDelta.FlushChangeBatch()
end

--[[
    Initialization
]]

function OGRH.SyncDelta.Initialize()
    -- Set up event handlers for zoning detection and combat state
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("PLAYER_LEAVING_WORLD")
    frame:RegisterEvent("RAID_ROSTER_UPDATE")
    frame:RegisterEvent("PLAYER_REGEN_ENABLED")  -- Leaving combat
    
    frame:SetScript("OnEvent", function()
        if event == "PLAYER_ENTERING_WORLD" then
            OGRH.SyncDelta.SetZoning(false)
            -- Flush offline queue when entering world/raid
            OGRH.SyncDelta.FlushOfflineQueue()
        elseif event == "PLAYER_LEAVING_WORLD" then
            OGRH.SyncDelta.SetZoning(true)
        elseif event == "RAID_ROSTER_UPDATE" then
            -- Check if we just joined a raid
            if GetNumRaidMembers() > 0 and table.getn(OGRH.SyncDelta.State.offlineQueue) > 0 then
                OGRH.SyncDelta.FlushOfflineQueue()
            end
        elseif event == "PLAYER_REGEN_ENABLED" then
            -- Left combat - flush any pending changes
            if table.getn(OGRH.SyncDelta.State.pendingChanges) > 0 then
                OGRH.SyncDelta.FlushChangeBatch()
            end
        end
    end)
    
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[RH-SyncDelta]|r Loaded (Phase 3A)")
end

DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[RH-SyncDelta]|r Loaded")
