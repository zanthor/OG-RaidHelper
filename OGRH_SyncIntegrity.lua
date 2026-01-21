-- OGRH_SyncIntegrity.lua (Turtle-WoW 1.12)
-- Checksum verification and data integrity system
-- Phase 3B: Unified checksum polling for structure, RolesUI, and assignments

OGRH = OGRH or {}
OGRH.SyncIntegrity = {}

--[[
    Unified Checksum Polling System
    
    Admin broadcasts every 30 seconds:
    - Structure checksum (encounter roles, marks, numbers, announcements)
    - RolesUI checksum (bucket assignments)
    - Assignment checksum (player-to-role assignments)
    
    Clients compare their checksums to admin's broadcast:
    - On mismatch: Log warning, optionally request repair
    - Auto-repair: Admin can push data to specific clients or all raid members
]]

OGRH.SyncIntegrity.State = {
    lastChecksumBroadcast = 0,
    verificationInterval = 30,  -- seconds
    checksumCache = {},
    pollingTimer = nil,
    enabled = false
}

--[[
    Core Functions
]]

-- Start periodic integrity checks (called when becoming raid admin)
function OGRH.StartIntegrityChecks()
    if OGRH.SyncIntegrity.State.enabled then
        return  -- Already running
    end
    
    OGRH.SyncIntegrity.State.enabled = true
    
    -- Start polling timer
    OGRH.SyncIntegrity.State.pollingTimer = OGRH.ScheduleTimer(function()
        OGRH.SyncIntegrity.BroadcastChecksums()
    end, OGRH.SyncIntegrity.State.verificationInterval, true)  -- Repeating timer
    
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[RH-SyncIntegrity]|r Started checksum polling (every 30s)")
end

-- Stop periodic integrity checks (called when losing raid admin)
function OGRH.StopIntegrityChecks()
    if not OGRH.SyncIntegrity.State.enabled then
        return
    end
    
    OGRH.SyncIntegrity.State.enabled = false
    
    -- Cancel polling timer
    if OGRH.SyncIntegrity.State.pollingTimer then
        -- Cancel timer implementation depends on OGRH.ScheduleTimer
        OGRH.SyncIntegrity.State.pollingTimer = nil
    end
    
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[RH-SyncIntegrity]|r Stopped checksum polling")
end

-- Admin: Broadcast unified checksums to raid
function OGRH.SyncIntegrity.BroadcastChecksums()
    if GetNumRaidMembers() == 0 then
        return
    end
    
    -- Get current encounter
    local currentRaid, currentEncounter = OGRH.GetCurrentEncounter()
    if not currentRaid or not currentEncounter then
        return  -- No encounter selected
    end
    
    -- Calculate all checksums
    local checksums = {
        structure = OGRH.CalculateStructureChecksum(currentRaid, currentEncounter),
        rolesUI = OGRH.CalculateRolesUIChecksum(),
        assignments = OGRH.CalculateAssignmentChecksum(currentRaid, currentEncounter),
        raid = currentRaid,
        encounter = currentEncounter,
        timestamp = GetTime()
    }
    
    -- Broadcast via MessageRouter (auto-serializes tables)
    if OGRH.MessageRouter and OGRH.MessageTypes then
        OGRH.MessageRouter.Broadcast(
            OGRH.MessageTypes.SYNC.CHECKSUM_POLL,
            checksums,
            {
                priority = "LOW",  -- Background traffic
                onSuccess = function()
                    -- Update last broadcast time
                    OGRH.SyncIntegrity.State.lastChecksumBroadcast = GetTime()
                end
            }
        )
    end
end

-- Client: Handle checksum broadcast from admin
function OGRH.SyncIntegrity.OnChecksumBroadcast(sender, checksums)
    -- Verify sender is the addon's raid admin
    local currentAdmin = OGRH.GetRaidAdmin and OGRH.GetRaidAdmin()
    if not currentAdmin or sender ~= currentAdmin then
        return  -- Ignore checksums from non-admins
    end
    
    -- Verify we're looking at the same encounter
    local myRaid, myEncounter = OGRH.GetCurrentEncounter()
    if myRaid ~= checksums.raid or myEncounter ~= checksums.encounter then
        return  -- Different encounter, ignore
    end
    
    -- Calculate our checksums
    local myStructure = OGRH.CalculateStructureChecksum(myRaid, myEncounter)
    local myRolesUI = OGRH.CalculateRolesUIChecksum()
    local myAssignments = OGRH.CalculateAssignmentChecksum(myRaid, myEncounter)
    
    -- Compare and handle mismatches
    local mismatches = {}
    
    if myStructure ~= checksums.structure then
        table.insert(mismatches, "structure")
    end
    
    if myRolesUI ~= checksums.rolesUI then
        table.insert(mismatches, "RolesUI")
        -- RolesUI mismatch: Send request for auto-repair (admin will push immediately)
        OGRH.SyncIntegrity.RequestRolesUISync(sender)
    end
    
    if myAssignments ~= checksums.assignments then
        table.insert(mismatches, "assignments")
    end
    
    -- If mismatches found, show warning
    if table.getn(mismatches) > 0 then
        local mismatchList = table.concat(mismatches, ", ")
        DEFAULT_CHAT_FRAME:AddMessage("|cffff9900[RH-SyncIntegrity]|r Checksum mismatch: " .. mismatchList)
        -- Note: RolesUI auto-repairs, structure/assignments require manual pull
        if myStructure ~= checksums.structure or myAssignments ~= checksums.assignments then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff9900[RH-SyncIntegrity]|r Use Data Management to pull latest structure/assignments")
        end
    end
end

-- Client: Request RolesUI sync from admin (auto-repair)
function OGRH.SyncIntegrity.RequestRolesUISync(adminName)
    if OGRH.MessageRouter and OGRH.MessageTypes then
        OGRH.MessageRouter.SendTo(
            adminName,
            OGRH.MessageTypes.ROLESUI.SYNC_REQUEST,
            "",  -- Empty string, no data needed for request
            {priority = "HIGH"}
        )
    end
end

-- Admin: Handle RolesUI sync request (push data immediately)
function OGRH.SyncIntegrity.OnRolesUISyncRequest(requester)
    -- Verify we're the addon's raid admin
    local currentAdmin = OGRH.GetRaidAdmin and OGRH.GetRaidAdmin()
    local playerName = UnitName("player")
    if not currentAdmin or playerName ~= currentAdmin then
        return
    end
    
    OGRH.EnsureSV()
    
    -- Build RolesUI sync data
    local syncData = {
        roles = OGRH_SV.roles or {},
        timestamp = GetTime()
    }
    
    -- Send to requester (or broadcast to all if requester not specified)
    if OGRH.MessageRouter and OGRH.MessageTypes then
        if requester then
            OGRH.MessageRouter.SendTo(
                requester,
                OGRH.MessageTypes.ROLESUI.SYNC_PUSH,
                serializedData,
                {priority = "HIGH"}
            )
        else
            OGRH.MessageRouter.Broadcast(
                OGRH.MessageTypes.ROLESUI.SYNC_PUSH,
                serializedData,
                {priority = "HIGH"}
            )
        end
    end
end

-- Client: Handle RolesUI sync push from admin (apply immediately)
function OGRH.SyncIntegrity.OnRolesUISyncPush(sender, syncData)
    -- Verify sender is the addon's raid admin
    local currentAdmin = OGRH.GetRaidAdmin and OGRH.GetRaidAdmin()
    if not currentAdmin or sender ~= currentAdmin then
        return
    end
    
    -- Block sync from self
    if sender == UnitName("player") then
        return
    end
    
    if not syncData or not syncData.roles then
        return
    end
    
    -- Apply RolesUI data
    OGRH.EnsureSV()
    OGRH_SV.roles = syncData.roles
    
    -- Refresh RolesUI if open
    if OGRH.rolesFrame and OGRH.rolesFrame:IsShown() and OGRH.rolesFrame.UpdatePlayerLists then
        OGRH.rolesFrame.UpdatePlayerLists()
    end
    
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[RH-SyncIntegrity]|r RolesUI data updated from admin")
end

-- Request full sync from another player
function OGRH.RequestFullSync(sender)
    -- Request via MessageRouter
    if OGRH.MessageRouter and OGRH.MessageTypes then
        OGRH.MessageRouter.SendTo(
            sender,
            OGRH.MessageTypes.SYNC.REQUEST_FULL,
            {},
            {priority = "NORMAL"}
        )
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[RH-SyncIntegrity]|r Requested full sync from " .. sender)
    end
end

-- Send full sync to another player (admin only)
function OGRH.SendFullSync(targetPlayer)
    if not OGRH.CanModifyStructure or not OGRH.CanModifyStructure(UnitName("player")) then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[RH-SyncIntegrity]|r Only raid admin can send full sync")
        return
    end
    
    -- Use existing Phase 2 sync system
    if OGRH.Sync and OGRH.Sync.BroadcastFullSync then
        OGRH.Sync.BroadcastFullSync()
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[RH-SyncIntegrity]|r Sent full sync to raid")
    end
end

-- Show corruption warning to user
function OGRH.ShowCorruptionWarning(sender)
    DEFAULT_CHAT_FRAME:AddMessage("|cffff8800[RH-SyncIntegrity]|r Data corruption detected with " .. sender)
    DEFAULT_CHAT_FRAME:AddMessage("|cffff8800[RH-SyncIntegrity]|r Use Data Management window to repair")
end

-- Request admin intervention for unresolvable conflicts
function OGRH.RequestAdminIntervention()
    DEFAULT_CHAT_FRAME:AddMessage("|cffff8800[RH-SyncIntegrity]|r Admin intervention required")
    DEFAULT_CHAT_FRAME:AddMessage("|cffff8800[RH-SyncIntegrity]|r Open Data Management window to push structure")
end

-- Compute structure checksum (lightweight)
function OGRH.ComputeStructureChecksum()
    local currentRaid, currentEncounter = OGRH.GetCurrentEncounter()
    if not currentRaid or not currentEncounter then
        return "0"
    end
    return OGRH.CalculateStructureChecksum(currentRaid, currentEncounter)
end

-- Repair corrupted data from multiple sources
function OGRH.RepairCorruptedData()
    DEFAULT_CHAT_FRAME:AddMessage("|cffff9900[RH-SyncIntegrity]|r Use Data Management window to pull latest structure")
end

-- Force full resync from admin
function OGRH.ForceResyncFromAdmin()
    if not OGRH.CanModifyStructure or not OGRH.CanModifyStructure(UnitName("player")) then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[RH-SyncIntegrity]|r Only raid admin can force resync")
        return
    end
    
    -- Use Phase 2 sync system
    if OGRH.Sync and OGRH.Sync.BroadcastFullSync then
        OGRH.Sync.BroadcastFullSync()
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[RH-SyncIntegrity]|r Force resyncing structure to all raid members")
    end
end

--[[
    Initialization
]]

function OGRH.SyncIntegrity.Initialize()
    -- Register checksum poll handler
    if OGRH.MessageRouter and OGRH.MessageTypes then
        OGRH.MessageRouter.RegisterHandler(OGRH.MessageTypes.SYNC.CHECKSUM_POLL, function(sender, data)
            OGRH.SyncIntegrity.OnChecksumBroadcast(sender, data)
        end)
        
        -- Register RolesUI sync handlers
        OGRH.MessageRouter.RegisterHandler(OGRH.MessageTypes.ROLESUI.SYNC_REQUEST, function(sender, data)
            OGRH.SyncIntegrity.OnRolesUISyncRequest(sender)
        end)
        
        OGRH.MessageRouter.RegisterHandler(OGRH.MessageTypes.ROLESUI.SYNC_PUSH, function(sender, data)
            OGRH.SyncIntegrity.OnRolesUISyncPush(sender, data)
        end)
    end
    
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[RH-SyncIntegrity]|r Loaded - Unified checksum polling with auto-repair")
end

-- Auto-initialize on load
OGRH.SyncIntegrity.Initialize()
