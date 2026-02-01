-- OGRH_SyncGranular.lua (Turtle-WoW 1.12)
-- Phase 6.3: Granular Sync System
-- Implements component/encounter/raid-level sync for surgical data repairs
-- Prioritizes repairs based on user's current UI context

OGRH = OGRH or {}
OGRH.SyncGranular = {}

--[[
    Granular Sync State
]]
OGRH.SyncGranular.State = {
    syncQueue = {},             -- Queued sync operations (prioritized)
    activeSyncs = {},           -- Currently executing syncs
    currentRaid = nil,          -- Currently selected raid in UI
    currentEncounter = nil,     -- Currently selected encounter in UI
    maxConcurrentSyncs = 1,     -- Serialize sync operations
    enabled = true
}

--[[
    Priority Levels (highest to lowest)
    
    1. CRITICAL: Current raid/encounter (user actively working on it)
    2. HIGH: Other encounters in same raid (likely relevant)
    3. NORMAL: Other raids (fix when convenient)
    4. LOW: Background/deferred syncs
]]
local PRIORITY = {
    CRITICAL = 1,
    HIGH = 2,
    NORMAL = 3,
    LOW = 4
}

--[[
    Helper Functions
]]

-- Deep copy table (required for data sync)
function OGRH.DeepCopy(original)
    local copy
    if type(original) == 'table' then
        copy = {}
        for key, value in pairs(original) do
            copy[OGRH.DeepCopy(key)] = OGRH.DeepCopy(value)
        end
    else
        copy = original
    end
    return copy
end

-- Set current UI context (called by UI when selection changes)
function OGRH.SyncGranular.SetContext(raidName, encounterName)
    OGRH.SyncGranular.State.currentRaid = raidName
    OGRH.SyncGranular.State.currentEncounter = encounterName
end

-- Calculate priority for a sync operation
local function GetSyncPriority(raidName, encounterName)
    local state = OGRH.SyncGranular.State
    
    -- Current encounter = CRITICAL
    if raidName == state.currentRaid and encounterName == state.currentEncounter then
        return PRIORITY.CRITICAL
    end
    
    -- Same raid, different encounter = HIGH
    if raidName == state.currentRaid then
        return PRIORITY.HIGH
    end
    
    -- Different raid = NORMAL
    return PRIORITY.NORMAL
end

-- Queue a sync operation with automatic prioritization
local function QueueSync(syncType, raidName, encounterName, componentName, targetPlayer, encounterPosition)
    local priority = GetSyncPriority(raidName, encounterName)
    
    -- Check if this sync is already queued or in progress
    local syncKey = syncType .. ":" .. (raidName or "global") .. ":" .. (encounterName or "") .. ":" .. (componentName or "")
    
    -- Check active syncs
    for syncId, syncOp in pairs(OGRH.SyncGranular.State.activeSyncs) do
        local activeKey = syncOp.syncType .. ":" .. (syncOp.raidName or "global") .. ":" .. (syncOp.encounterName or "") .. ":" .. (syncOp.componentName or "")
        if activeKey == syncKey then
            if OGRH.SyncIntegrity and OGRH.SyncIntegrity.State.debug then
                DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff888888[RH-SyncGranular]|r Skipping duplicate sync (already active): %s", syncKey))
            end
            return  -- Already in progress
        end
    end
    
    -- Check queued syncs
    for i = 1, table.getn(OGRH.SyncGranular.State.syncQueue) do
        local queuedOp = OGRH.SyncGranular.State.syncQueue[i]
        local queuedKey = queuedOp.syncType .. ":" .. (queuedOp.raidName or "global") .. ":" .. (queuedOp.encounterName or "") .. ":" .. (queuedOp.componentName or "")
        if queuedKey == syncKey then
            if OGRH.SyncIntegrity and OGRH.SyncIntegrity.State.debug then
                DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff888888[RH-SyncGranular]|r Skipping duplicate sync (already queued): %s", syncKey))
            end
            return  -- Already queued
        end
    end
    
    local syncOp = {
        syncType = syncType,        -- "component", "encounter", "raid", "global"
        raidName = raidName,
        encounterName = encounterName,
        componentName = componentName,
        targetPlayer = targetPlayer,
        encounterPosition = encounterPosition,  -- Position for encounter creation
        priority = priority,
        timestamp = GetTime()
    }
    
    table.insert(OGRH.SyncGranular.State.syncQueue, syncOp)
    
    -- Sort queue by priority (lower number = higher priority)
    table.sort(OGRH.SyncGranular.State.syncQueue, function(a, b)
        if a.priority ~= b.priority then
            return a.priority < b.priority
        end
        return a.timestamp < b.timestamp  -- FIFO within same priority
    end)
    
    -- Process queue
    OGRH.SyncGranular.ProcessQueue()
end

-- Process sync queue (execute highest priority sync if capacity available)
function OGRH.SyncGranular.ProcessQueue()
    if not OGRH.SyncGranular.State.enabled then
        return
    end
    
    -- Check capacity
    local activeCount = 0
    for syncId, _ in pairs(OGRH.SyncGranular.State.activeSyncs) do
        activeCount = activeCount + 1
    end
    
    if activeCount >= OGRH.SyncGranular.State.maxConcurrentSyncs then
        return  -- At capacity
    end
    
    -- Get next operation
    if table.getn(OGRH.SyncGranular.State.syncQueue) == 0 then
        return  -- Queue empty
    end
    
    local syncOp = table.remove(OGRH.SyncGranular.State.syncQueue, 1)
    
    -- Execute sync
    OGRH.SyncGranular.ExecuteSync(syncOp)
end

-- Execute a sync operation
function OGRH.SyncGranular.ExecuteSync(syncOp)
    local syncId = string.format("%s_%s_%d", syncOp.syncType, syncOp.raidName or "global", GetTime())
    
    -- Mark as active
    OGRH.SyncGranular.State.activeSyncs[syncId] = syncOp
    
    -- Route to appropriate handler - CLIENT requests data from admin
    if syncOp.syncType == "component" then
        OGRH.SyncGranular.RequestComponentSync(syncOp.raidName, syncOp.encounterName, syncOp.componentName, syncOp.encounterPosition)
    elseif syncOp.syncType == "encounter" then
        OGRH.SyncGranular.RequestEncounterSync(syncOp.raidName, syncOp.encounterName, syncOp.encounterPosition)
    elseif syncOp.syncType == "raid" then
        OGRH.SyncGranular.RequestRaidSync(syncOp.raidName)
    elseif syncOp.syncType == "global" then
        OGRH.SyncGranular.RequestGlobalComponentSync(syncOp.componentName)
    end
    
    -- Mark as complete immediately after sending request
    OGRH.SyncGranular.CompleteSyncOperation(syncId, true)
end

-- Mark sync as complete and process queue
function OGRH.SyncGranular.CompleteSyncOperation(syncId, success)
    OGRH.SyncGranular.State.activeSyncs[syncId] = nil
    
    -- Process next queued sync
    OGRH.SyncGranular.ProcessQueue()
end

--[[
    Component-Level Sync
]]

-- Request component sync from admin/officer
function OGRH.SyncGranular.RequestComponentSync(raidName, encounterName, componentName, encounterPosition)
    if not OGRH.MessageRouter or not OGRH.MessageTypes then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[RH-SyncGranular]|r MessageRouter not available")
        return
    end
    
    local requestData = {
        raidName = raidName,
        encounterName = encounterName,
        componentName = componentName,
        encounterPosition = encounterPosition,  -- Pass position through request
        requestor = UnitName("player"),
        timestamp = GetTime()
    }
    
    -- Broadcast request (admin/officers will respond)
    OGRH.MessageRouter.Broadcast(
        OGRH.MessageTypes.SYNC.COMPONENT_REQUEST,
        requestData,
        {priority = "NORMAL"}
    )
    
    DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[RH-SyncGranular]|r Requesting component sync: %s > %s > %s", raidName, encounterName, componentName))
end

-- Send component data to requesting player (admin/officer only)
function OGRH.SyncGranular.SendComponentSync(raidName, encounterName, componentName, targetPlayer, syncId, encounterPosition)
    -- Extract component data
    local componentData = OGRH.SyncGranular.ExtractComponentData(raidName, encounterName, componentName)
    
    if not componentData then
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff0000[RH-SyncGranular]|r Failed to extract component: %s", componentName))
        OGRH.SyncGranular.CompleteSyncOperation(syncId, false)
        return
    end
    
    local syncData = {
        raidName = raidName,
        encounterName = encounterName,
        componentName = componentName,
        data = componentData,
        encounterPosition = encounterPosition,  -- Include position for encounter creation
        sender = UnitName("player"),
        syncId = syncId,
        timestamp = GetTime()
    }
    
    -- Send to target player
    if targetPlayer then
        OGRH.MessageRouter.SendTo(
            targetPlayer,
            OGRH.MessageTypes.SYNC.COMPONENT_RESPONSE,
            syncData,
            {
                priority = "HIGH",
                onSuccess = function()
                    OGRH.SyncGranular.CompleteSyncOperation(syncId, true)
                end,
                onFailure = function()
                    OGRH.SyncGranular.CompleteSyncOperation(syncId, false)
                end
            }
        )
    else
        -- Broadcast to all
        OGRH.MessageRouter.Broadcast(
            OGRH.MessageTypes.SYNC.COMPONENT_RESPONSE,
            syncData,
            {
                priority = "HIGH",
                onSuccess = function()
                    OGRH.SyncGranular.CompleteSyncOperation(syncId, true)
                end,
                onFailure = function()
                    OGRH.SyncGranular.CompleteSyncOperation(syncId, false)
                end
            }
        )
    end
end

-- Receive component data and apply to local saved variables
function OGRH.SyncGranular.ReceiveComponentSync(sender, syncData)
    -- Validate sender permission
    if not OGRH.CanModifyStructure(sender) and not OGRH.CanModifyAssignments(sender) then
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff0000[RH-SyncGranular]|r Permission denied: %s cannot send component sync", sender))
        return
    end
    
    local raidName = syncData.raidName
    local encounterName = syncData.encounterName
    local componentName = syncData.componentName
    local data = syncData.data
    
    if OGRH.SyncIntegrity and OGRH.SyncIntegrity.State.debug then
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ccff[RH-SyncGranular]|r Receiving: %s > %s > %s from %s", 
            raidName, encounterName, componentName, sender))
    end
    
    -- Validate component exists
    if not OGRH.SyncGranular.ValidateComponentStructure(raidName, encounterName, componentName, data) then
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff0000[RH-SyncGranular]|r Invalid component structure: %s", componentName))
        return
    end
    
    -- Extract encounter position if available
    local encounterPosition = syncData.encounterPosition
    
    -- Apply component data
    local success = OGRH.SyncGranular.ApplyComponentData(raidName, encounterName, componentName, data, encounterPosition)
    
    if success then
        if OGRH.SyncIntegrity and OGRH.SyncIntegrity.State.debug then
            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[RH-SyncGranular]|r Applied: %s > %s > %s", 
                raidName, encounterName, componentName))
        end
        
        -- Refresh UI if Encounter Planning window is open
        local encounterFrame = OGRH_EncounterFrame or _G["OGRH_EncounterFrame"]
        if encounterFrame and encounterFrame:IsShown() then
            -- Refresh role containers if this is the currently selected encounter
            if encounterFrame.selectedRaid == raidName and 
               encounterFrame.selectedEncounter == encounterName and
               encounterFrame.RefreshRoleContainers then
                encounterFrame.RefreshRoleContainers()
            end
        end
    else
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff0000[RH-SyncGranular]|r Failed to apply: %s", componentName))
    end
end

-- Extract component data from saved variables
function OGRH.SyncGranular.ExtractComponentData(raidName, encounterName, componentName)
    if not OGRH_SV or not OGRH_SV.encounterMgmt then
        return nil
    end
    
    if componentName == "encounterMetadata" then
        -- Return encounter object itself (excluding components stored elsewhere)
        local raid = OGRH.FindRaidByName(raidName)
        if not raid then 
            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff0000[RH-SyncGranular]|r Raid not found: %s", tostring(raidName)))
            return nil 
        end
        
        local encounter = OGRH.FindEncounterByName(raid, encounterName)
        if not encounter then 
            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff0000[RH-SyncGranular]|r Encounter not found: %s > %s", tostring(raidName), tostring(encounterName)))
            return nil 
        end
        
        return OGRH.DeepCopy(encounter)
        
    elseif componentName == "roles" then
        -- Return roles for this specific encounter only
        if not OGRH_SV.encounterMgmt.roles or 
           not OGRH_SV.encounterMgmt.roles[raidName] or
           not OGRH_SV.encounterMgmt.roles[raidName][encounterName] then
            return {}
        end
        return OGRH.DeepCopy(OGRH_SV.encounterMgmt.roles[raidName][encounterName])
        
    elseif componentName == "playerAssignments" then
        -- Return encounterAssignments table
        if not OGRH_SV.encounterAssignments or 
           not OGRH_SV.encounterAssignments[raidName] or
           not OGRH_SV.encounterAssignments[raidName][encounterName] then
            return {}
        end
        return OGRH.DeepCopy(OGRH_SV.encounterAssignments[raidName][encounterName])
        
    elseif componentName == "raidMarks" then
        -- Return encounterRaidMarks table
        if not OGRH_SV.encounterRaidMarks or
           not OGRH_SV.encounterRaidMarks[raidName] or
           not OGRH_SV.encounterRaidMarks[raidName][encounterName] then
            return {}
        end
        return OGRH.DeepCopy(OGRH_SV.encounterRaidMarks[raidName][encounterName])
        
    elseif componentName == "assignmentNumbers" then
        -- Return encounterAssignmentNumbers table
        if not OGRH_SV.encounterAssignmentNumbers or
           not OGRH_SV.encounterAssignmentNumbers[raidName] or
           not OGRH_SV.encounterAssignmentNumbers[raidName][encounterName] then
            return {}
        end
        return OGRH.DeepCopy(OGRH_SV.encounterAssignmentNumbers[raidName][encounterName])
        
    elseif componentName == "announcements" then
        -- Return encounterAnnouncements table
        if not OGRH_SV.encounterAnnouncements or
           not OGRH_SV.encounterAnnouncements[raidName] or
           not OGRH_SV.encounterAnnouncements[raidName][encounterName] then
            return {}
        end
        return OGRH.DeepCopy(OGRH_SV.encounterAnnouncements[raidName][encounterName])
    end
    
    return nil
end

-- Apply component data to saved variables
function OGRH.SyncGranular.ApplyComponentData(raidName, encounterName, componentName, data, encounterPosition)
    if not OGRH_SV or not OGRH_SV.encounterMgmt then
        return false
    end
    
    if componentName == "encounterMetadata" then
        -- Find raid
        local raid = OGRH.FindRaidByName(raidName)
        if not raid then
            -- Raid doesn't exist - component repair won't work, need FULL RAID SYNC
            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff0000[RH-SyncGranular]|r Cannot apply component - raid missing: %s", raidName))
            return false
        end
        
        -- Create encounter if it doesn't exist
        local encounter = OGRH.FindEncounterByName(raid, encounterName)
        if not encounter then
            encounter = {
                name = encounterName,
                advancedSettings = {}
            }
            
            -- Insert at specified position if provided (maintains encounter order within raid)
            if encounterPosition and encounterPosition <= table.getn(raid.encounters) + 1 then
                table.insert(raid.encounters, encounterPosition, encounter)
                if OGRH.SyncIntegrity and OGRH.SyncIntegrity.State.debug then
                    DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[RH-SyncGranular]|r Created encounter at position %d: %s > %s", encounterPosition, raidName, encounterName))
                end
            else
                table.insert(raid.encounters, encounter)
                if OGRH.SyncIntegrity and OGRH.SyncIntegrity.State.debug then
                    DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[RH-SyncGranular]|r Created encounter: %s > %s", raidName, encounterName))
                end
            end
        end
        
        -- Update encounter properties (excluding role assignments stored elsewhere)
        for key, value in pairs(data) do
            if key ~= "roles" then  -- Don't overwrite role array reference
                encounter[key] = value
            end
        end
        
        return true
        
    elseif componentName == "roles" then
        -- Update role structure for this specific encounter
        OGRH_SV.encounterMgmt.roles = OGRH_SV.encounterMgmt.roles or {}
        OGRH_SV.encounterMgmt.roles[raidName] = OGRH_SV.encounterMgmt.roles[raidName] or {}
        OGRH_SV.encounterMgmt.roles[raidName][encounterName] = OGRH.DeepCopy(data)
        return true
        
    elseif componentName == "playerAssignments" then
        -- Update encounterAssignments
        OGRH_SV.encounterAssignments = OGRH_SV.encounterAssignments or {}
        OGRH_SV.encounterAssignments[raidName] = OGRH_SV.encounterAssignments[raidName] or {}
        OGRH_SV.encounterAssignments[raidName][encounterName] = OGRH.DeepCopy(data)
        return true
        
    elseif componentName == "raidMarks" then
        -- Update encounterRaidMarks
        OGRH_SV.encounterRaidMarks = OGRH_SV.encounterRaidMarks or {}
        OGRH_SV.encounterRaidMarks[raidName] = OGRH_SV.encounterRaidMarks[raidName] or {}
        OGRH_SV.encounterRaidMarks[raidName][encounterName] = OGRH.DeepCopy(data)
        return true
        
    elseif componentName == "assignmentNumbers" then
        -- Update encounterAssignmentNumbers
        OGRH_SV.encounterAssignmentNumbers = OGRH_SV.encounterAssignmentNumbers or {}
        OGRH_SV.encounterAssignmentNumbers[raidName] = OGRH_SV.encounterAssignmentNumbers[raidName] or {}
        OGRH_SV.encounterAssignmentNumbers[raidName][encounterName] = OGRH.DeepCopy(data)
        return true
        
    elseif componentName == "announcements" then
        -- Update encounterAnnouncements
        OGRH_SV.encounterAnnouncements = OGRH_SV.encounterAnnouncements or {}
        OGRH_SV.encounterAnnouncements[raidName] = OGRH_SV.encounterAnnouncements[raidName] or {}
        OGRH_SV.encounterAnnouncements[raidName][encounterName] = OGRH.DeepCopy(data)
        return true
    end
    
    return false
end

-- Validate component structure (basic sanity checks)
function OGRH.SyncGranular.ValidateComponentStructure(raidName, encounterName, componentName, data)
    if not raidName or not encounterName or not componentName or not data then
        return false
    end
    
    -- Type checking
    if type(data) ~= "table" then
        return false
    end
    
    -- Component-specific validation could go here
    -- For now, basic table check is sufficient
    
    return true
end

--[[
    Encounter-Level Sync
]]

-- Request full encounter sync
function OGRH.SyncGranular.RequestEncounterSync(raidName, encounterName)
    if not OGRH.MessageRouter or not OGRH.MessageTypes then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[RH-SyncGranular]|r MessageRouter not available")
        return
    end
    
    local requestData = {
        raidName = raidName,
        encounterName = encounterName,
        requestor = UnitName("player"),
        timestamp = GetTime()
    }
    
    OGRH.MessageRouter.Broadcast(
        OGRH.MessageTypes.SYNC.ENCOUNTER_REQUEST,
        requestData,
        {priority = "NORMAL"}
    )
    
    if OGRH.SyncIntegrity and OGRH.SyncIntegrity.State.debug then
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[RH-SyncGranular]|r Requesting encounter sync: %s > %s", raidName, encounterName))
    end
end

-- Send full encounter (all 6 components)
function OGRH.SyncGranular.SendEncounterSync(raidName, encounterName, targetPlayer, syncId)
    local components = {
        "encounterMetadata",
        "roles",
        "playerAssignments",
        "raidMarks",
        "assignmentNumbers",
        "announcements"
    }
    
    local encounterData = {}
    
    -- Extract all components
    for i = 1, table.getn(components) do
        local componentName = components[i]
        encounterData[componentName] = OGRH.SyncGranular.ExtractComponentData(raidName, encounterName, componentName)
        
        if not encounterData[componentName] then
            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff0000[RH-SyncGranular]|r Failed to extract component: %s", componentName))
            OGRH.SyncGranular.CompleteSyncOperation(syncId, false)
            return
        end
    end
    
    local syncData = {
        raidName = raidName,
        encounterName = encounterName,
        components = encounterData,
        sender = UnitName("player"),
        syncId = syncId,
        timestamp = GetTime()
    }
    
    -- Send to target
    if targetPlayer then
        OGRH.MessageRouter.SendTo(
            targetPlayer,
            OGRH.MessageTypes.SYNC.ENCOUNTER_RESPONSE,
            syncData,
            {
                priority = "HIGH",
                onSuccess = function()
                    OGRH.SyncGranular.CompleteSyncOperation(syncId, true)
                end,
                onFailure = function()
                    OGRH.SyncGranular.CompleteSyncOperation(syncId, false)
                end
            }
        )
    else
        OGRH.MessageRouter.Broadcast(
            OGRH.MessageTypes.SYNC.ENCOUNTER_RESPONSE,
            syncData,
            {
                priority = "HIGH",
                onSuccess = function()
                    OGRH.SyncGranular.CompleteSyncOperation(syncId, true)
                end,
                onFailure = function()
                    OGRH.SyncGranular.CompleteSyncOperation(syncId, false)
                end
            }
        )
    end
end

-- Receive and apply full encounter sync
function OGRH.SyncGranular.ReceiveEncounterSync(sender, syncData)
    -- Validate sender permission
    if not OGRH.CanModifyStructure(sender) then
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff0000[RH-SyncGranular]|r Permission denied: %s cannot send encounter sync", sender))
        return
    end
    
    local raidName = syncData.raidName
    local encounterName = syncData.encounterName
    local components = syncData.components
    
    if not components then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[RH-SyncGranular]|r Invalid encounter sync data")
        return
    end
    
    -- Apply all components atomically
    local componentNames = {
        "encounterMetadata",
        "roles",
        "playerAssignments",
        "raidMarks",
        "assignmentNumbers",
        "announcements"
    }
    
    local allSuccess = true
    for i = 1, table.getn(componentNames) do
        local componentName = componentNames[i]
        local componentData = components[componentName]
        
        if componentData then
            local success = OGRH.SyncGranular.ApplyComponentData(raidName, encounterName, componentName, componentData)
            if not success then
                DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff0000[RH-SyncGranular]|r Failed to apply component: %s", componentName))
                allSuccess = false
            end
        end
    end
    
    if allSuccess then
        -- Recompute checksums
        if OGRH.ComputeEncounterChecksum then
            OGRH.ComputeEncounterChecksum(raidName, encounterName)
        end
        
        -- Trigger UI refresh
        if OGRH.RefreshEncounterUI then
            OGRH.RefreshEncounterUI(raidName, encounterName)
        end
        
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[RH-SyncGranular]|r Applied encounter sync: %s > %s (from %s)", 
            raidName, encounterName, sender))
    else
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff8800[RH-SyncGranular]|r Partially applied encounter sync: %s > %s", 
            raidName, encounterName))
    end
end

--[[
    Raid-Level Sync
]]

-- Request full raid sync
function OGRH.SyncGranular.RequestRaidSync(raidName)
    if not OGRH.MessageRouter or not OGRH.MessageTypes then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[RH-SyncGranular]|r MessageRouter not available")
        return
    end
    
    local requestData = {
        raidName = raidName,
        requestor = UnitName("player"),
        timestamp = GetTime()
    }
    
    OGRH.MessageRouter.Broadcast(
        OGRH.MessageTypes.SYNC.RAID_REQUEST,
        requestData,
        {priority = "NORMAL"}
    )
    
    if OGRH.SyncIntegrity and OGRH.SyncIntegrity.State.debug then
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[RH-SyncGranular]|r Requesting raid sync: %s", raidName))
    end
end

-- Send full raid sync (metadata + all encounters)
function OGRH.SyncGranular.SendRaidSync(raidName, targetPlayer, syncId)
    local raid = OGRH.FindRaidByName(raidName)
    if not raid then
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff0000[RH-SyncGranular]|r Raid not found: %s", raidName))
        OGRH.SyncGranular.CompleteSyncOperation(syncId, false)
        return
    end
    
    -- Extract raid metadata
    local raidMetadata = {
        name = raid.name,
        advancedSettings = OGRH.DeepCopy(raid.advancedSettings or {})
    }
    
    -- Extract all encounters
    local encounters = {}
    if raid.encounters then
        for i = 1, table.getn(raid.encounters) do
            local encounter = raid.encounters[i]
            local encounterName = encounter.name
            
            -- Extract all components for this encounter
            local components = {
                "encounterMetadata",
                "roles",
                "playerAssignments",
                "raidMarks",
                "assignmentNumbers",
                "announcements"
            }
            
            encounters[encounterName] = {
                position = i  -- Preserve encounter position in raid
            }
            for j = 1, table.getn(components) do
                local componentName = components[j]
                encounters[encounterName][componentName] = OGRH.SyncGranular.ExtractComponentData(raidName, encounterName, componentName)
            end
        end
    end
    
    local syncData = {
        raidName = raidName,
        raidMetadata = raidMetadata,
        encounters = encounters,
        sender = UnitName("player"),
        syncId = syncId,
        timestamp = GetTime()
    }
    
    -- Send to target
    if targetPlayer then
        OGRH.MessageRouter.SendTo(
            targetPlayer,
            OGRH.MessageTypes.SYNC.RAID_RESPONSE,
            syncData,
            {
                priority = "HIGH",
                onSuccess = function()
                    OGRH.SyncGranular.CompleteSyncOperation(syncId, true)
                end,
                onFailure = function()
                    OGRH.SyncGranular.CompleteSyncOperation(syncId, false)
                end
            }
        )
    else
        OGRH.MessageRouter.Broadcast(
            OGRH.MessageTypes.SYNC.RAID_RESPONSE,
            syncData,
            {
                priority = "HIGH",
                onSuccess = function()
                    OGRH.SyncGranular.CompleteSyncOperation(syncId, true)
                end,
                onFailure = function()
                    OGRH.SyncGranular.CompleteSyncOperation(syncId, false)
                end
            }
        )
    end
end

-- Receive and apply full raid sync
function OGRH.SyncGranular.ReceiveRaidSync(sender, syncData)
    -- Validate sender permission
    if not OGRH.CanModifyStructure(sender) then
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff0000[RH-SyncGranular]|r Permission denied: %s cannot send raid sync", sender))
        return
    end
    
    local raidName = syncData.raidName
    local raidMetadata = syncData.raidMetadata
    local encounters = syncData.encounters
    
    if not raidMetadata or not encounters then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[RH-SyncGranular]|r Invalid raid sync data")
        return
    end
    
    -- First, ensure raid exists (create if missing)
    OGRH.EnsureSV()
    local raid = OGRH.FindRaidByName(raidName)
    if not raid then
        -- Create new raid structure
        raid = {
            name = raidName,
            encounters = {},
            advancedSettings = OGRH.DeepCopy(raidMetadata.advancedSettings)
        }
        table.insert(OGRH_SV.encounterMgmt.raids, raid)
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[RH-SyncGranular]|r Created missing raid: %s", raidName))
    else
        -- Clear existing encounters array to rebuild from scratch
        raid.encounters = {}
        raid.advancedSettings = OGRH.DeepCopy(raidMetadata.advancedSettings)
    end
    
    -- Build sorted list of encounters by position
    local sortedEncounters = {}
    for encounterName, encounterData in pairs(encounters) do
        if type(encounterData) == "table" and encounterData.position then
            table.insert(sortedEncounters, {
                name = encounterName,
                position = encounterData.position,
                data = encounterData
            })
        end
    end
    
    -- Sort by position
    table.sort(sortedEncounters, function(a, b) return a.position < b.position end)
    
    -- Rebuild raid encounters array in correct order
    for i = 1, table.getn(sortedEncounters) do
        local encounterInfo = sortedEncounters[i]
        local encounterName = encounterInfo.name
        local encounterData = encounterInfo.data
        
        -- Create encounter structure
        local encounter = {
            name = encounterName,
            advancedSettings = {}
        }
        
        -- Apply encounterMetadata first to set up the encounter
        if encounterData.encounterMetadata then
            for key, value in pairs(encounterData.encounterMetadata) do
                if key ~= "roles" then
                    encounter[key] = OGRH.DeepCopy(value)
                end
            end
        end
        
        -- Insert encounter at correct position
        table.insert(raid.encounters, encounter)
        
        if OGRH.SyncIntegrity and OGRH.SyncIntegrity.State.debug then
            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff888888[RH-SyncGranular]|r Applying encounter %d: %s", i, encounterName))
        end
        
        -- Now apply all other components (roles, assignments, etc.)
        local componentNames = {"roles", "playerAssignments", "raidMarks", "assignmentNumbers", "announcements"}
        for j = 1, table.getn(componentNames) do
            local componentName = componentNames[j]
            if encounterData[componentName] then
                local success = OGRH.SyncGranular.ApplyComponentData(raidName, encounterName, componentName, encounterData[componentName])
                if not success and OGRH.SyncIntegrity and OGRH.SyncIntegrity.State.debug then
                    DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff8800[RH-SyncGranular]|r Failed to apply %s for %s", componentName, encounterName))
                end
            end
        end
    end
    
    local encounterCount = table.getn(sortedEncounters)
    
    -- Recompute checksums
    if OGRH.SyncChecksum and OGRH.SyncChecksum.ComputeRaidChecksum then
        OGRH.SyncChecksum.ComputeRaidChecksum(raidName)
    end
    
    -- Trigger UI refresh
    if OGRH.RefreshRaidUI then
        OGRH.RefreshRaidUI(raidName)
    end
    
    -- Clear pending full sync flag
    if OGRH.SyncIntegrity and OGRH.SyncIntegrity.State.pendingFullSync then
        OGRH.SyncIntegrity.State.pendingFullSync[raidName] = nil
    end
    
    DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[RH-SyncGranular]|r Applied raid sync: %s (%d encounters, from %s)", 
        raidName, encounterCount, sender))
end

--[[
    Global Component Sync
]]

-- Request global component sync
function OGRH.SyncGranular.RequestGlobalComponentSync(componentName)
    if not OGRH.MessageRouter or not OGRH.MessageTypes then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[RH-SyncGranular]|r MessageRouter not available")
        return
    end
    
    local requestData = {
        componentName = componentName,
        requestor = UnitName("player"),
        timestamp = GetTime()
    }
    
    OGRH.MessageRouter.Broadcast(
        OGRH.MessageTypes.SYNC.GLOBAL_REQUEST,
        requestData,
        {priority = "NORMAL"}
    )
    
    DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[RH-SyncGranular]|r Requesting global component sync: %s", componentName))
end

-- Send global component data
function OGRH.SyncGranular.SendGlobalComponentSync(componentName, targetPlayer, syncId)
    local componentData = nil
    
    if componentName == "tradeItems" then
        componentData = OGRH.DeepCopy(OGRH_SV.tradeItems or {})
    elseif componentName == "consumes" then
        componentData = OGRH.DeepCopy(OGRH_SV.consumes or {})
    -- RGO deprecated - no longer synced
    else
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff0000[RH-SyncGranular]|r Unknown global component: %s", componentName))
        OGRH.SyncGranular.CompleteSyncOperation(syncId, false)
        return
    end
    
    DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[RH-SyncGranular]|r Sending global component: %s to %s", componentName, targetPlayer or "ALL"))
    
    local syncData = {
        componentName = componentName,
        data = componentData,
        sender = UnitName("player"),
        syncId = syncId,
        timestamp = GetTime()
    }
    
    -- Send to target
    if targetPlayer then
        OGRH.MessageRouter.SendTo(
            targetPlayer,
            OGRH.MessageTypes.SYNC.GLOBAL_RESPONSE,
            syncData,
            {
                priority = "HIGH",
                onSuccess = function()
                    OGRH.SyncGranular.CompleteSyncOperation(syncId, true)
                end,
                onFailure = function()
                    OGRH.SyncGranular.CompleteSyncOperation(syncId, false)
                end
            }
        )
    else
        OGRH.MessageRouter.Broadcast(
            OGRH.MessageTypes.SYNC.GLOBAL_RESPONSE,
            syncData,
            {
                priority = "HIGH",
                onSuccess = function()
                    OGRH.SyncGranular.CompleteSyncOperation(syncId, true)
                end,
                onFailure = function()
                    OGRH.SyncGranular.CompleteSyncOperation(syncId, false)
                end
            }
        )
    end
end

-- Receive and apply global component sync
function OGRH.SyncGranular.ReceiveGlobalComponentSync(sender, syncData)
    -- Validate sender permission
    if not OGRH.CanModifyStructure(sender) then
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff0000[RH-SyncGranular]|r Permission denied: %s cannot send global component sync", sender))
        return
    end
    
    local componentName = syncData.componentName
    local data = syncData.data
    
    if not componentName or not data then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[RH-SyncGranular]|r Invalid global component sync data")
        return
    end
    
    -- Apply data
    if componentName == "tradeItems" then
        OGRH_SV.tradeItems = OGRH.DeepCopy(data)
    elseif componentName == "consumes" then
        OGRH_SV.consumes = OGRH.DeepCopy(data)
    -- RGO deprecated - no longer synced
    else
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff0000[RH-SyncGranular]|r Unknown global component: %s", componentName))
        return
    end
    
    -- Recompute checksum
    if OGRH.ComputeGlobalComponentChecksum then
        OGRH.ComputeGlobalComponentChecksum(componentName)
    end
    
    -- RGO deprecated - UI refresh no longer needed
    
    DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[RH-SyncGranular]|r Applied global component sync: %s (from %s)", 
        componentName, sender))
end

--[[
    Raid Metadata Sync (advancedSettings only)
]]

-- Request raid metadata (advancedSettings) sync
function OGRH.SyncGranular.RequestRaidMetadataSync(raidName, targetPlayer)
    if OGRH.SyncIntegrity and OGRH.SyncIntegrity.State.debug then
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff888888[RH-SyncGranular]|r RequestRaidMetadataSync called for %s", raidName))
    end
    
    if not OGRH.MessageRouter or not OGRH.MessageTypes then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[RH-SyncGranular]|r MessageRouter not available")
        return
    end
    
    if not OGRH.MessageTypes.SYNC or not OGRH.MessageTypes.SYNC.RAID_METADATA_REQUEST then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[RH-SyncGranular]|r RAID_METADATA_REQUEST message type not defined")
        return
    end
    
    local requestData = {
        raidName = raidName,
        requestor = UnitName("player"),
        timestamp = GetTime()
    }
    
    -- Always broadcast (no single-target messaging in Turtle WoW)
    OGRH.MessageRouter.Broadcast(
        OGRH.MessageTypes.SYNC.RAID_METADATA_REQUEST,
        requestData,
        {priority = "NORMAL"}
    )
    
    DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[RH-SyncGranular]|r Requesting raid metadata sync: %s", raidName))
end

-- Handle raid metadata request (admin/officer only)
function OGRH.SyncGranular.OnRaidMetadataRequest(sender, requestData)
    if OGRH.SyncIntegrity and OGRH.SyncIntegrity.State.debug then
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff888888[RH-SyncGranular]|r Received raid metadata request from %s", sender))
    end
    
    -- Verify we're authorized to send
    local currentAdmin = OGRH.GetRaidAdmin and OGRH.GetRaidAdmin()
    local playerName = UnitName("player")
    if not currentAdmin or playerName ~= currentAdmin then
        if OGRH.SyncIntegrity and OGRH.SyncIntegrity.State.debug then
            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff888888[RH-SyncGranular]|r Not admin (currentAdmin=%s, playerName=%s) - ignoring metadata request", tostring(currentAdmin), tostring(playerName)))
        end
        return  -- Only admin sends metadata
    end
    
    local raidName = requestData.raidName
    if not raidName then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[RH-SyncGranular]|r Metadata request missing raid name")
        return
    end
    
    local raid = OGRH.FindRaidByName(raidName)
    if not raid then
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff0000[RH-SyncGranular]|r Cannot send metadata - raid not found: %s", raidName))
        return
    end
    
    local syncData = {
        raidName = raidName,
        advancedSettings = OGRH.DeepCopy(raid.advancedSettings or {}),
        sender = UnitName("player"),
        timestamp = GetTime()
    }
    
    -- Broadcast to raid
    OGRH.MessageRouter.Broadcast(
        OGRH.MessageTypes.SYNC.RAID_METADATA_RESPONSE,
        syncData,
        {priority = "NORMAL"}
    )
    
    if OGRH.SyncIntegrity and OGRH.SyncIntegrity.State.debug then
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[RH-SyncGranular]|r Sent raid metadata: %s", raidName))
    end
end

-- Apply raid metadata (advancedSettings)
function OGRH.SyncGranular.OnRaidMetadataReceived(sender, syncData)
    -- Verify sender is admin
    local currentAdmin = OGRH.GetRaidAdmin and OGRH.GetRaidAdmin()
    if not currentAdmin or sender ~= currentAdmin then
        return
    end
    
    local raidName = syncData.raidName
    local advancedSettings = syncData.advancedSettings
    
    if not raidName or not advancedSettings then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[RH-SyncGranular]|r Invalid raid metadata sync data")
        return
    end
    
    local raid = OGRH.FindRaidByName(raidName)
    if not raid then
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff0000[RH-SyncGranular]|r Cannot apply metadata - raid not found: %s", raidName))
        return
    end
    
    -- Apply metadata
    raid.advancedSettings = OGRH.DeepCopy(advancedSettings)
    
    -- Verify checksum now matches (if we have validation)
    if OGRH.SyncChecksum and OGRH.SyncChecksum.ComputeRaidChecksum then
        local newChecksum = OGRH.SyncChecksum.ComputeRaidChecksum(raidName)
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[RH-SyncGranular]|r Applied raid metadata: %s (checksum=%s)", 
            raidName, tostring(newChecksum)))
    else
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[RH-SyncGranular]|r Applied raid metadata: %s (from %s)", 
            raidName, sender))
    end
end

--[[
    Public API for Auto-Repair Integration
]]

-- Queue a repair based on validation result (called by Phase 6.2 validation)
function OGRH.SyncGranular.QueueRepair(validationResult, targetPlayer)
    if not validationResult or validationResult.valid then
        return  -- No repair needed
    end
    
    -- Global components
    if validationResult.corrupted and validationResult.corrupted.global then
        for i = 1, table.getn(validationResult.corrupted.global) do
            local componentName = validationResult.corrupted.global[i]
            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ccff[RH-SyncGranular]|r Queueing global repair: %s (from %s)", componentName, targetPlayer or "?"))
            QueueSync("global", nil, nil, componentName, targetPlayer, nil)
        end
    end
    
    -- Raid/encounter components
    if validationResult.corrupted and validationResult.corrupted.raids then
        for raidName, raidData in pairs(validationResult.corrupted.raids) do
            if type(raidData) == "table" then
                if raidData.raidLevel then
                    -- Full raid sync
                    if OGRH.SyncIntegrity and OGRH.SyncIntegrity.State.debug then
                        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ccff[RH-SyncGranular]|r Queueing raid repair: %s", raidName))
                    end
                    QueueSync("raid", raidName, nil, nil, targetPlayer, nil)
                elseif raidData.encounters then
                    -- Per-encounter sync
                    for encounterName, encounterData in pairs(raidData.encounters) do
                        local components = encounterData.components or encounterData
                        local position = encounterData.position
                        
                        if type(components) == "table" then
                            local componentCount = table.getn(components)
                            
                            if componentCount >= 3 then
                                -- 3+ components = encounter sync
                                if OGRH.SyncIntegrity and OGRH.SyncIntegrity.State.debug then
                                    DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ccff[RH-SyncGranular]|r Queueing encounter repair: %s > %s", raidName, encounterName))
                                end
                                QueueSync("encounter", raidName, encounterName, nil, targetPlayer, position)
                            else
                                -- 1-2 components = individual component sync
                                for j = 1, componentCount do
                                    local componentName = components[j]
                                    if OGRH.SyncIntegrity and OGRH.SyncIntegrity.State.debug then
                                        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ccff[RH-SyncGranular]|r Queueing component repair: %s > %s > %s", raidName, encounterName, componentName))
                                    end
                                    QueueSync("component", raidName, encounterName, componentName, targetPlayer, position)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

-- Initialize module (register message handlers)
function OGRH.SyncGranular.Initialize()
    if not OGRH.MessageRouter then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[RH-SyncGranular]|r Cannot initialize: MessageRouter not available")
        return
    end
    
    -- Register handlers
    OGRH.MessageRouter.RegisterHandler(OGRH.MessageTypes.SYNC.COMPONENT_REQUEST, function(sender, data)
        -- Admin/officer responds to component request
        if OGRH.CanModifyStructure(UnitName("player")) or OGRH.CanModifyAssignments(UnitName("player")) then
            local syncId = string.format("component_%s_%d", data.raidName or "?", GetTime())
            OGRH.SyncGranular.SendComponentSync(data.raidName, data.encounterName, data.componentName, data.requestor, syncId, data.encounterPosition)
        end
    end)
    
    OGRH.MessageRouter.RegisterHandler(OGRH.MessageTypes.SYNC.COMPONENT_RESPONSE, function(sender, data)
        OGRH.SyncGranular.ReceiveComponentSync(sender, data)
    end)
    
    OGRH.MessageRouter.RegisterHandler(OGRH.MessageTypes.SYNC.ENCOUNTER_REQUEST, function(sender, data)
        if OGRH.CanModifyStructure(UnitName("player")) then
            local syncId = string.format("encounter_%s_%d", data.raidName or "?", GetTime())
            OGRH.SyncGranular.SendEncounterSync(data.raidName, data.encounterName, data.requestor, syncId)
        end
    end)
    
    OGRH.MessageRouter.RegisterHandler(OGRH.MessageTypes.SYNC.ENCOUNTER_RESPONSE, function(sender, data)
        OGRH.SyncGranular.ReceiveEncounterSync(sender, data)
    end)
    
    OGRH.MessageRouter.RegisterHandler(OGRH.MessageTypes.SYNC.RAID_REQUEST, function(sender, data)
        if OGRH.CanModifyStructure(UnitName("player")) then
            local syncId = string.format("raid_%s_%d", data.raidName or "?", GetTime())
            OGRH.SyncGranular.SendRaidSync(data.raidName, data.requestor, syncId)
        end
    end)
    
    OGRH.MessageRouter.RegisterHandler(OGRH.MessageTypes.SYNC.RAID_RESPONSE, function(sender, data)
        OGRH.SyncGranular.ReceiveRaidSync(sender, data)
    end)
    
    OGRH.MessageRouter.RegisterHandler(OGRH.MessageTypes.SYNC.GLOBAL_REQUEST, function(sender, data)
        if OGRH.CanModifyStructure(UnitName("player")) then
            local syncId = string.format("global_%s_%d", data.componentName or "?", GetTime())
            OGRH.SyncGranular.SendGlobalComponentSync(data.componentName, data.requestor, syncId)
        end
    end)
    
    OGRH.MessageRouter.RegisterHandler(OGRH.MessageTypes.SYNC.GLOBAL_RESPONSE, function(sender, data)
        OGRH.SyncGranular.ReceiveGlobalComponentSync(sender, data)
    end)
    
    OGRH.MessageRouter.RegisterHandler(OGRH.MessageTypes.SYNC.RAID_METADATA_REQUEST, function(sender, data)
        OGRH.SyncGranular.OnRaidMetadataRequest(sender, data)
    end)
    
    OGRH.MessageRouter.RegisterHandler(OGRH.MessageTypes.SYNC.RAID_METADATA_RESPONSE, function(sender, data)
        OGRH.SyncGranular.OnRaidMetadataReceived(sender, data)
    end)
    
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[RH-SyncGranular]|r Initialized granular sync system")
end
