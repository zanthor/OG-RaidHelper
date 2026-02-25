--[[
    OG-RaidHelper: SyncSession.lua
    
    Session-based repair system for coordinating structure synchronization.
    Prevents broadcast storms and provides UI feedback during repairs.
    
    PHASE 2 IMPLEMENTATION (STUB)
    
    Responsibilities:
    - Session lifecycle management (start, validate, complete, timeout)
    - Session token generation and tracking
    - Client validation tracking
    - UI/SVM locking during repairs
    - Global repair mode flag coordination
    - Post-repair queue management
    - Version checking and warning system
    - Join-during-repair edge case handling
]]

if not OGRH then OGRH = {} end
if not OGRH.SyncSession then OGRH.SyncSession = {} end

--[[
    ============================================================================
    MODULE STATE
    ============================================================================
]]

OGRH.SyncSession.State = {
    -- Active session tracking
    activeSession = nil,  -- {token, startTime, encounterName, layerIds, clientValidations, isRepairMode}
    
    -- Repair mode flag
    repairModeActive = false,
    
    -- Post-repair change queue
    pendingChangesQueue = {},  -- Array of {changeType, data, timestamp}
    
    -- Raid size tracking for reset detection
    lastRaidSize = 0,
    
    -- Join-during-repair tracking
    pendingJoinValidations = {},  -- Array of player names to validate after repair
    
    -- UI/SVM lock state
    lockState = {
        uiLocked = false,
        svmLocked = false
    }
}

--[[
    ============================================================================
    PHASE 2 FUNCTION STUBS
    ============================================================================
]]

--[[
    ============================================================================
    TOKEN MANAGEMENT
    ============================================================================
]]

-- Generate unique session token
-- Format: "timestamp_random"
function OGRH.SyncSession.GenerateToken()
    local timestamp = GetTime()
    local random = math.random(100000, 999999)
    return string.format("%.2f_%d", timestamp, random)
end

-- Validate session token
-- Returns: isValid, age
function OGRH.SyncSession.ValidateToken(token)
    if not token or type(token) ~= "string" then
        return false, 0
    end
    
    local _, _, timestampStr = string.find(token, "^([%d%.]+)_%d+$")
    if not timestampStr then
        return false, 0
    end
    
    local timestamp = tonumber(timestampStr)
    if not timestamp then
        return false, 0
    end
    
    local age = GetTime() - timestamp
    local isValid = age >= 0 and age < 60  -- Valid for 60 seconds
    
    return isValid, age
end

--[[
    ============================================================================
    SESSION LIFECYCLE
    ============================================================================
]]

-- Session Lifecycle
function OGRH.SyncSession.StartSession(encounterName, layerIds)
    if OGRH.SyncSession.State.activeSession then
        return nil, "Session already active"
    end
    
    local token = OGRH.SyncSession.GenerateToken()
    OGRH.SyncSession.State.activeSession = {
        token = token,
        startTime = GetTime(),
        encounterName = encounterName,
        layerIds = layerIds or {},
        clientValidations = {},
        repairParticipants = {},  -- Clients who requested repair (set by admin)
        isRepairMode = false
    }
    
    -- Phase 5: Enter repair mode (lock UI/SVM and suppress integrity broadcasts)
    OGRH.SyncSession.EnterRepairMode()
    
    return token
end

function OGRH.SyncSession.CompleteSession(token)
    if not OGRH.SyncSession.State.activeSession then
        return false
    end
    
    if OGRH.SyncSession.State.activeSession.token ~= token then
        return false
    end
    
    OGRH.SyncSession.State.activeSession = nil
    
    -- Phase 5: Exit repair mode (unlock UI/SVM and resume integrity broadcasts)
    OGRH.SyncSession.ExitRepairMode()
    
    return true
end

function OGRH.SyncSession.CancelSession(reason)
    if not OGRH.SyncSession.State.activeSession then
        return false
    end
    
    local token = OGRH.SyncSession.State.activeSession.token
    
    -- Broadcast cancellation to all clients BEFORE clearing session
    if OGRH.MessageRouter and OGRH.MessageTypes then
        OGRH.MessageRouter.Send(
            OGRH.MessageTypes.SYNC.REPAIR_CANCEL,
            {
                token = token,
                reason = reason or "Session cancelled"
            },
            {
                priority = "HIGH",
                channel = "RAID"
            }
        )
    end
    
    OGRH.SyncSession.State.activeSession = nil
    
    -- Phase 5: Exit repair mode on cancellation (unlock UI/SVM and resume integrity broadcasts)
    OGRH.SyncSession.ExitRepairMode()
    
    if reason then
        OGRH.Msg("|cffff9900[RH-SyncSession]|r Session cancelled: " .. reason)
    end
    
    return true
end

function OGRH.SyncSession.TimeoutSession(token)
    if not OGRH.SyncSession.State.activeSession then
        return false
    end
    
    if OGRH.SyncSession.State.activeSession.token ~= token then
        return false
    end
    
    OGRH.SyncSession.State.activeSession = nil
    
    -- Phase 5: Exit repair mode on timeout
    if OGRH.SyncIntegrity and OGRH.SyncIntegrity.ExitRepairMode then
        OGRH.SyncIntegrity.ExitRepairMode()
    end
    
    OGRH.Msg("|cffff9900[RH-SyncSession]|r Session timed out")
    
    return true
end

function OGRH.SyncSession.IsSessionActive()
    return OGRH.SyncSession.State.activeSession ~= nil
end

function OGRH.SyncSession.GetActiveSession()
    return OGRH.SyncSession.State.activeSession
end

--[[
    ============================================================================
    CLIENT VALIDATION TRACKING
    ============================================================================
]]

-- Client Validation
function OGRH.SyncSession.RecordClientValidation(playerName, status, checksums)
    if not OGRH.SyncSession.State.activeSession then
        return
    end
    
    OGRH.SyncSession.State.activeSession.clientValidations[playerName] = {
        status = status,  -- "pass" or "fail"
        checksums = checksums,
        timestamp = GetTime()
    }
end

function OGRH.SyncSession.GetClientValidations()
    if not OGRH.SyncSession.State.activeSession then
        return {}
    end
    
    return OGRH.SyncSession.State.activeSession.clientValidations
end

-- Set which clients are participating in this repair (admin calls this)
function OGRH.SyncSession.SetRepairParticipants(clientList)
    if not OGRH.SyncSession.State.activeSession then
        return
    end
    
    local participants = {}
    if clientList then
        for i = 1, table.getn(clientList) do
            local name = clientList[i].name or clientList[i]
            if name then
                participants[name] = true
            end
        end
    end
    
    OGRH.SyncSession.State.activeSession.repairParticipants = participants
end

function OGRH.SyncSession.AreAllClientsValidated()
    if not OGRH.SyncSession.State.activeSession then
        return false
    end
    
    -- Use actual repair participants (clients who requested this repair)
    local participants = OGRH.SyncSession.State.activeSession.repairParticipants or {}
    
    -- Count participants
    local participantCount = 0
    for _ in pairs(participants) do
        participantCount = participantCount + 1
    end
    
    -- SAFETY: If no participants tracked, require at least 1 validation response
    if participantCount == 0 then
        local validations = OGRH.SyncSession.State.activeSession.clientValidations
        local validationCount = 0
        for _ in pairs(validations) do
            validationCount = validationCount + 1
        end
        return validationCount > 0
    end
    
    -- Check that every participant has sent a validation
    local validations = OGRH.SyncSession.State.activeSession.clientValidations
    for playerName, _ in pairs(participants) do
        if not validations[playerName] then
            return false  -- Missing validation from this participant
        end
    end
    
    return true
end

--[[
    ============================================================================
    UI/SVM LOCKING
    ============================================================================
]]

-- UI/SVM Locking
function OGRH.SyncSession.LockUI()
    OGRH.SyncSession.State.lockState.uiLocked = true
end

function OGRH.SyncSession.UnlockUI()
    OGRH.SyncSession.State.lockState.uiLocked = false
end

function OGRH.SyncSession.IsUILocked()
    return OGRH.SyncSession.State.lockState.uiLocked
end

function OGRH.SyncSession.LockSVM()
    OGRH.SyncSession.State.lockState.svmLocked = true
end

function OGRH.SyncSession.UnlockSVM()
    OGRH.SyncSession.State.lockState.svmLocked = false
end

function OGRH.SyncSession.IsSVMLocked()
    return OGRH.SyncSession.State.lockState.svmLocked
end

--[[
    ============================================================================
    GLOBAL REPAIR MODE
    ============================================================================
]]

-- Global Repair Mode
function OGRH.SyncSession.EnterRepairMode()
    OGRH.SyncSession.State.repairModeActive = true
    
    -- Lock UI and SVM
    OGRH.SyncSession.LockUI()
    OGRH.SyncSession.LockSVM()
end

function OGRH.SyncSession.ExitRepairMode()
    OGRH.SyncSession.State.repairModeActive = false
    
    -- Unlock UI and SVM
    OGRH.SyncSession.UnlockUI()
    OGRH.SyncSession.UnlockSVM()
    
    -- Process queued changes
    OGRH.SyncSession.ProcessQueuedChanges()
end

function OGRH.SyncSession.IsInRepairMode()
    return OGRH.SyncSession.State.repairModeActive
end

--[[
    ============================================================================
    POST-REPAIR QUEUE
    ============================================================================
]]

-- Post-Repair Queue
function OGRH.SyncSession.QueueChange(changeType, data)
    table.insert(OGRH.SyncSession.State.pendingChangesQueue, {
        changeType = changeType,
        data = data,
        timestamp = GetTime()
    })
end

function OGRH.SyncSession.ProcessQueuedChanges()
    local queue = OGRH.SyncSession.State.pendingChangesQueue
    
    if table.getn(queue) == 0 then
        return
    end
    
    -- Wait 2 seconds grace period before processing
    OGRH.ScheduleTimer(function()
        for i = 1, table.getn(queue) do
            local change = queue[i]
            -- Broadcast change via appropriate sync system
            if OGRH.SyncRouter and OGRH.SyncRouter.BroadcastChange then
                OGRH.SyncRouter.BroadcastChange(change.changeType, change.data)
            end
        end
        
        -- Clear queue
        OGRH.SyncSession.ClearQueue()
    end, 2)
end

function OGRH.SyncSession.ClearQueue()
    OGRH.SyncSession.State.pendingChangesQueue = {}
end

function OGRH.SyncSession.OnRaidRosterUpdate()
    local currentSize = GetNumRaidMembers()
    local lastSize = OGRH.SyncSession.State.lastRaidSize
    
    -- Check if player left raid (not in raid anymore)
    if lastSize > 0 and currentSize == 0 then
        -- Player left raid - cancel any active repair panels
        if OGRH.SyncRepairUI then
            local adminPanel = OGRH.SyncRepairUI.State.adminPanel
            local clientPanel = OGRH.SyncRepairUI.State.clientPanel
            local waitingPanel = OGRH.SyncRepairUI.State.waitingPanel
            
            if (adminPanel and adminPanel:IsShown()) or 
               (clientPanel and clientPanel:IsShown()) or 
               (waitingPanel and waitingPanel:IsShown()) then
                
                OGRH.Msg("|cffff9900[RH-SyncRepair]|r Left raid - closing repair panels")
                
                if OGRH.SyncRepairUI.HideAdminPanel then
                    OGRH.SyncRepairUI.HideAdminPanel()
                end
                if OGRH.SyncRepairUI.HideClientPanel then
                    OGRH.SyncRepairUI.HideClientPanel()
                end
                if OGRH.SyncRepairUI.HideWaitingPanel then
                    OGRH.SyncRepairUI.HideWaitingPanel()
                end
                
                -- Cancel session
                if OGRH.SyncSession.CancelSession then
                    OGRH.SyncSession.CancelSession("Player left raid")
                end
            end
        end
    end
    
    -- Check if admin disconnected (client-side check)
    local session = OGRH.SyncSession.GetActiveSession()
    if session and session.adminName and currentSize > 0 then
        -- Check if admin is still in raid
        local adminFound = false
        for i = 1, GetNumRaidMembers() do
            local name = GetRaidRosterInfo(i)
            if name == session.adminName then
                adminFound = true
                break
            end
        end
        
        if not adminFound then
            -- Admin disconnected - cancel repair
            OGRH.Msg("|cffff9900[RH-SyncRepair]|r Admin disconnected - closing repair panels")
            
            if OGRH.SyncRepairUI then
                if OGRH.SyncRepairUI.HideClientPanel then
                    OGRH.SyncRepairUI.HideClientPanel()
                end
                if OGRH.SyncRepairUI.HideWaitingPanel then
                    OGRH.SyncRepairUI.HideWaitingPanel()
                end
            end
            
            -- Cancel session
            if OGRH.SyncSession.CancelSession then
                OGRH.SyncSession.CancelSession("Admin disconnected")
            end
            
            -- Clear client state
            if OGRH.SyncRepairHandlers then
                OGRH.SyncRepairHandlers.currentToken = nil
                OGRH.SyncRepairHandlers.waitingForRepair = false
                OGRH.SyncRepairHandlers.waitingToken = nil
            end
        end
    end
    
    OGRH.SyncSession.State.lastRaidSize = currentSize
end

--[[
    ============================================================================
    JOIN-DURING-REPAIR
    ============================================================================
]]

-- Join-During-Repair
function OGRH.SyncSession.AddPendingJoinValidation(playerName)
    table.insert(OGRH.SyncSession.State.pendingJoinValidations, {
        playerName = playerName,
        timestamp = GetTime()
    })
end

function OGRH.SyncSession.ProcessPendingJoinValidations()
    local pending = OGRH.SyncSession.State.pendingJoinValidations
    
    if table.getn(pending) == 0 then
        return
    end
    
    -- Broadcast validation request to pending joiners
    for i = 1, table.getn(pending) do
        local join = pending[i]
        if OGRH.SyncIntegrity and OGRH.SyncIntegrity.RequestClientValidation then
            OGRH.SyncIntegrity.RequestClientValidation(join.playerName)
        end
    end
    
    -- Clear pending list
    OGRH.SyncSession.State.pendingJoinValidations = {}
end

--[[
    ============================================================================
    MODULE INITIALIZATION
    ============================================================================
]]

function OGRH.SyncSession.Initialize()
    -- Phase 2 implementation placeholder
    -- Module state initialized at declaration
    
    -- Register RAID_ROSTER_UPDATE event for version tracking
    local rosterFrame = CreateFrame("Frame")
    rosterFrame:RegisterEvent("RAID_ROSTER_UPDATE")
    rosterFrame:SetScript("OnEvent", function()
        if event == "RAID_ROSTER_UPDATE" then
            OGRH.SyncSession.OnRaidRosterUpdate()
        end
    end)
end

-- Auto-initialize on load
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:SetScript("OnEvent", function()
    if event == "ADDON_LOADED" and arg1 == "OG-RaidHelper" then
        OGRH.ScheduleTimer(function()
            OGRH.SyncSession.Initialize()
        end, 0.5)
    end
end)
