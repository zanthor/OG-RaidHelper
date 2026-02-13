-- OGRH_Permissions.lua (Turtle-WoW 1.12)
-- Three-tier permission system for OG-RaidHelper
-- Implements ADMIN, OFFICER, MEMBER permission levels

OGRH = OGRH or {}
OGRH.Permissions = {}

--[[
    Permission Level Enums
]]
OGRH.Permissions.ADMIN = "ADMIN"      -- Raid creator/owner
OGRH.Permissions.OFFICER = "OFFICER"  -- Raid Lead + Assists
OGRH.Permissions.MEMBER = "MEMBER"    -- Everyone else

--[[
    Permission State
    Stored in SavedVariables for persistence
]]
OGRH.Permissions.State = {
    currentAdmin = nil,           -- Current raid admin name (runtime only, cleared on load)
    lastAdmin = nil,              -- Last confirmed admin (persisted across sessions via SV)
    sessionAdmin = nil,           -- Session-only admin (set via /ogrh sa)
    adminHistory = {},            -- History of admin changes
    permissionDenials = {}        -- Log of permission denials
}

--[[
    Core Permission Functions
]]

-- Check if player is session admin (temporary, set via /ogrh sa command)
function OGRH.Permissions.IsSessionAdmin(playerName)
    if not playerName then return false end
    return OGRH.Permissions.State.sessionAdmin == playerName
end

-- Check if player is raid admin (stored in structure data)
function OGRH.IsRaidAdmin(playerName)
    if not playerName then return false end
    
    -- Check session admin first (temporary admin via /ogrh sa)
    if OGRH.Permissions.IsSessionAdmin(playerName) then
        return true
    end
    
    -- Check if player is the current admin
    if OGRH.Permissions.State.currentAdmin == playerName then
        return true
    end
    
    return false
end

-- Check if player is raid lead or assist
function OGRH.IsRaidOfficer(playerName)
    if not playerName then return false end
    
    -- Session admins are always treated as minimum Raid Assist
    if OGRH.Permissions.IsSessionAdmin(playerName) then
        return true
    end
    
    local numRaidMembers = GetNumRaidMembers()
    if numRaidMembers == 0 then
        -- Not in a raid
        return false
    end
    
    -- Check raid roster for lead/assist status
    for i = 1, numRaidMembers do
        local name, rank = GetRaidRosterInfo(i)
        
        if name == playerName then
            -- rank 2 = Raid Leader, rank 1 = Raid Assist, rank 0 = Member
            return rank >= 1
        end
    end
    
    return false
end

-- Get permission level for a player
function OGRH.GetPermissionLevel(playerName)
    if not playerName then return OGRH.Permissions.MEMBER end
    
    -- Session admin override (temporary via /ogrh sa)
    if OGRH.Permissions.IsSessionAdmin(playerName) then
        return OGRH.Permissions.ADMIN
    end
    
    -- Check if player is admin (stored in structure data)
    if OGRH.IsRaidAdmin(playerName) then
        return OGRH.Permissions.ADMIN
    end
    
    -- Check if player is raid lead or assist
    if OGRH.IsRaidOfficer(playerName) then
        return OGRH.Permissions.OFFICER
    end
    
    return OGRH.Permissions.MEMBER
end

-- Check if player can modify structure (encounters, groups, core settings)
function OGRH.CanModifyStructure(playerName)
    local level = OGRH.GetPermissionLevel(playerName)
    return level == OGRH.Permissions.ADMIN
end

-- Check if player can modify assignments (player assignments, roles)
function OGRH.CanModifyAssignments(playerName)
    local level = OGRH.GetPermissionLevel(playerName)
    return level == OGRH.Permissions.ADMIN or level == OGRH.Permissions.OFFICER
end

-- Check if player can read data (always true for raid members)
function OGRH.CanReadData(playerName)
    -- All raid members can read data
    return true
end

--[[
    Admin Management Functions
]]

-- Set the current raid admin
-- @param playerName string - Name of the new admin
-- @param suppressBroadcast boolean - If true, don't broadcast STATE.CHANGE_LEAD (receiving from network)
-- @param skipLastAdminUpdate boolean - If true, don't update lastAdmin in SV (temporary admin assignment)
function OGRH.SetRaidAdmin(playerName, suppressBroadcast, skipLastAdminUpdate)
    if not playerName then return false end
    
    local previousAdmin = OGRH.Permissions.State.currentAdmin
    
    -- If admin hasn't changed, don't do anything (prevents broadcast loops)
    if previousAdmin == playerName then
        return true
    end
    
    OGRH.Permissions.State.currentAdmin = playerName
    
    -- Update lastAdmin (persisted across sessions) unless this is a temporary assignment
    if not skipLastAdminUpdate then
        OGRH.Permissions.State.lastAdmin = playerName
    end
    
    -- Clear session admin when normal admin changes
    OGRH.Permissions.State.sessionAdmin = nil
    
    -- Update legacy state for backward compatibility (DEPRECATED - will be removed)
    if OGRH.RaidLead then
        OGRH.RaidLead.currentLead = playerName  -- DEPRECATED: Only for old UI code that hasn't been updated yet
    end
    
    -- Track admin's raid rank for demotion detection
    if OGRH.AdminDiscovery then
        for i = 1, GetNumRaidMembers() do
            local name, rank = GetRaidRosterInfo(i)
            if name == playerName then
                OGRH.AdminDiscovery.lastAdminRank = rank
                break
            end
        end
    end
    
    -- Save to saved variables
    OGRH.EnsureSV()
    
    -- Ensure adminHistory exists
    if not OGRH.Permissions.State.adminHistory then
        OGRH.Permissions.State.adminHistory = {}
    end
    
    -- Record in history
    table.insert(OGRH.Permissions.State.adminHistory, {
        timestamp = time(),
        previousAdmin = previousAdmin,
        newAdmin = playerName
    })
    
    -- Keep only last 20 history entries
    while table.getn(OGRH.Permissions.State.adminHistory) > 20 do
        table.remove(OGRH.Permissions.State.adminHistory, 1)
    end
    
    -- If we're the new admin, start integrity checks
    if playerName == UnitName("player") then
        if OGRH.StartIntegrityChecks then
            OGRH.StartIntegrityChecks()
        end
    else
        -- If we're no longer admin, stop integrity checks
        if OGRH.StopIntegrityChecks then
            OGRH.StopIntegrityChecks()
        end
    end
    
    -- Update UI to reflect admin change (sync button color, etc.)
    if OGRH.UpdateRaidAdminUI then
        OGRH.UpdateRaidAdminUI()
    end
    
    -- Broadcast the change to all raid members (only if not receiving from network)
    if not suppressBroadcast and GetNumRaidMembers() > 0 then
        -- Use MessageRouter for proper tracking and reliability
        if OGRH.MessageRouter and OGRH.MessageTypes then
            OGRH.MessageRouter.Broadcast(
                OGRH.MessageTypes.STATE.CHANGE_LEAD,
                {
                    adminName = playerName,
                    timestamp = GetTime()
                },
                { priority = "HIGH" }
            )
        end
    end
    
    -- Show message to user (unless they're the one becoming admin)
    local selfName = UnitName("player")
    if playerName ~= selfName then
        OGRH.Msg("Raid Admin set to: " .. playerName)
    end
    
    return true
end

-- Get the current raid admin
function OGRH.GetRaidAdmin()
    return OGRH.Permissions.State.currentAdmin
end

-- Get the last confirmed admin (persisted across sessions)
function OGRH.GetLastAdmin()
    return OGRH.Permissions.State.lastAdmin
end

-- Request admin role (only Raid Lead or Assist can request)
function OGRH.RequestAdminRole()
    local playerName = UnitName("player")
    
    if not OGRH.IsRaidOfficer(playerName) and not OGRH.Permissions.IsSessionAdmin(playerName) then
        OGRH.Msg("|cffff0000[Permissions]|r Only Raid Lead or Assist can request admin role")
        return false
    end
    
    -- Broadcast admin takeover via MessageRouter
    if OGRH.MessageRouter and OGRH.MessageTypes then
        OGRH.MessageRouter.Broadcast(
            OGRH.MessageTypes.ADMIN.TAKEOVER,
            {
                newAdmin = playerName,
                timestamp = GetTime(),
                version = OGRH.IncrementDataVersion and OGRH.IncrementDataVersion() or 1
            },
            {
                priority = "HIGH",
                onSuccess = function()
                    OGRH.SetRaidAdmin(playerName)
                    OGRH.Msg("|cff00ff00[Permissions]|r You are now the raid admin")
                    
                    -- Update admin button to show green
                    if OGRH.UpdateAdminButtonColor then
                        OGRH.UpdateAdminButtonColor()
                    end
                end
            }
        )
    else
        -- Fallback if MessageRouter not available
        OGRH.SetRaidAdmin(playerName)
        OGRH.Msg("|cff00ff00[Permissions]|r You are now the raid admin")
        
        -- Update admin button to show green
        if OGRH.UpdateAdminButtonColor then
            OGRH.UpdateAdminButtonColor()
        end
    end
    
    return true
end

-- Poll raid to discover current admin (called on reload, raid join, login)
-- Now delegates to the AdminDiscovery system for proper 3-tier resolution
function OGRH.PollForRaidAdmin()
    if not UnitInRaid("player") then
        return  -- Not in a raid
    end
    
    if not OGRH.MessageRouter or not OGRH.MessageTypes then
        return  -- MessageRouter not initialized yet
    end
    
    -- Delegate to AdminDiscovery system
    if OGRH.AdminDiscovery and OGRH.AdminDiscovery.Start then
        OGRH.AdminDiscovery.Start()
    end
end

-- Set session admin (temporary, for current session only)
function OGRH.SetSessionAdmin(playerName)
    if not playerName then
        playerName = UnitName("player")
    end
    
    OGRH.Permissions.State.sessionAdmin = playerName
    
    -- Start integrity checks if we're becoming admin
    if playerName == UnitName("player") then
        if OGRH.StartIntegrityChecks then
            OGRH.StartIntegrityChecks()
        end
    end
    
    -- Update UI to reflect session admin
    if OGRH.UpdateRaidAdminUI then
        OGRH.UpdateRaidAdminUI()
    end
    
    OGRH.Msg(string.format("|cff00ff00[Permissions]|r %s granted session admin (temporary)", playerName))
    OGRH.Msg("|cffffff00[Permissions]|r Session admin will be cleared when another admin is selected")
    
    return true
end

-- Assign admin role to another player (current admin or L/A can assign to another L/A)
function OGRH.AssignAdminRole(targetPlayer)
    local playerName = UnitName("player")
    
    if not OGRH.CanModifyStructure(playerName) and not OGRH.IsRaidOfficer(playerName) then
        OGRH.Msg("|cffff0000[Permissions]|r Only admin or Raid Lead/Assist can assign admin role")
        return false
    end
    
    if not OGRH.IsRaidOfficer(targetPlayer) and not OGRH.Permissions.IsSessionAdmin(targetPlayer) then
        OGRH.Msg("|cffff0000[Permissions]|r Can only assign admin to Raid Lead or Assist")
        return false
    end
    
    -- Broadcast admin assignment via MessageRouter (applies SyncVersion)
    if OGRH.MessageRouter and OGRH.MessageRouter.Broadcast then
        OGRH.MessageRouter.Broadcast(OGRH.MessageTypes.ADMIN.ASSIGN, {
            newAdmin = targetPlayer,
            assignedBy = playerName,
            timestamp = GetTime(),
            version = OGRH.IncrementDataVersion and OGRH.IncrementDataVersion() or 1
        }, {
            priority = "HIGH",
            onSuccess = function()
                OGRH.SetRaidAdmin(targetPlayer)
                OGRH.Msg(string.format("|cff00ff00[Permissions]|r %s is now the raid admin", targetPlayer))
            end
        })
    else
        -- Fallback if OGAddonMsg not available
        OGRH.SetRaidAdmin(targetPlayer)
        OGRH.Msg(string.format("|cff00ff00[Permissions]|r %s is now the raid admin", targetPlayer))
    end
    
    return true
end

--[[
    Permission Denial Handling
]]

-- Log a permission denial
function OGRH.LogPermissionDenial(playerName, operation, reason)
    table.insert(OGRH.Permissions.State.permissionDenials, {
        timestamp = time(),
        player = playerName,
        operation = operation,
        reason = reason
    })
    
    -- Keep only last 50 denials
    while table.getn(OGRH.Permissions.State.permissionDenials) > 50 do
        table.remove(OGRH.Permissions.State.permissionDenials, 1)
    end
end

-- Handle permission denied for an operation
function OGRH.HandlePermissionDenied(playerName, operation)
    local reason = string.format("Insufficient permissions (%s)", OGRH.GetPermissionLevel(playerName))
    
    -- Log the denial
    OGRH.LogPermissionDenial(playerName, operation, reason)
    
    -- Notify the player
    if playerName == UnitName("player") then
        OGRH.Msg(string.format("|cffff0000[Permissions]|r Permission denied: %s", operation))
        OGRH.Msg(string.format("|cffff0000[Permissions]|r Your level: %s", OGRH.GetPermissionLevel(playerName)))
    end
    
    -- Broadcast permission denial via MessageRouter (applies SyncVersion)
    if OGRH.MessageRouter and OGRH.MessageRouter.Broadcast then
        OGRH.MessageRouter.Broadcast(OGRH.MessageTypes.ADMIN.PERMISSION_DENIED, {
            player = playerName,
            operation = operation,
            timestamp = GetTime(),
            level = OGRH.GetPermissionLevel(playerName)
        }, {
            priority = "LOW"
        })
    end
end

--[[
    Initialization
]]

-- Initialize permission system
function OGRH.Permissions.Initialize()
    -- Load from SavedVariables if available (restores lastAdmin, adminHistory, etc.)
    local storedState = OGRH.SVM.Get("permissions")
    if storedState then
        OGRH.Permissions.State = storedState
    end
    
    -- Clear runtime-only currentAdmin on load
    -- The AdminDiscovery system will determine the correct admin via 3-tier logic:
    --   1. Check if lastAdmin is in raid with OGRH
    --   2. Fall back to Leader with OGRH
    --   3. Fall back to alphabetically first OGRH user (temp, no lastAdmin update)
    OGRH.Permissions.State.currentAdmin = nil
    
    OGRH.Msg("|cff00ccff[RH-Permissions]|r System initialized")
end

-- Save permission state to SavedVariables
function OGRH.Permissions.Save()
    OGRH.SVM.Set("permissions", nil, OGRH.Permissions.State)
end

--[[
    Debug Commands
]]

-- Debug: Print permission info for all raid members
function OGRH.Permissions.DebugPrintRaidPermissions()
    OGRH.Msg("|cff00ccff[Permissions]|r === Raid Permissions ===")
    OGRH.Msg(string.format("|cff00ccff[Permissions]|r Current Admin: %s", OGRH.Permissions.State.currentAdmin or "None"))
    
    local numRaidMembers = GetNumRaidMembers()
    if numRaidMembers == 0 then
        OGRH.Msg("|cff00ccff[Permissions]|r Not in a raid")
        return
    end
    
    for i = 1, numRaidMembers do
        local name, rank = GetRaidRosterInfo(i)
        local level = OGRH.GetPermissionLevel(name)
        local rankStr = "Member"
        
        if rank == 2 then
            rankStr = "Leader"
        elseif rank == 1 then
            rankStr = "Assist"
        end
        
        OGRH.Msg(string.format("|cff00ccff[Permissions]|r %s - Rank: %s, Permission: %s", name, rankStr, level))
    end
    
    OGRH.Msg("|cff00ccff[Permissions]|r === End Permissions ===")
end

-- Debug: Print permission denial log
function OGRH.Permissions.DebugPrintDenials()
    OGRH.Msg("|cff00ccff[Permissions]|r === Permission Denials ===")
    
    if table.getn(OGRH.Permissions.State.permissionDenials) == 0 then
        OGRH.Msg("|cff00ccff[Permissions]|r No denials recorded")
        return
    end
    
    for i = 1, table.getn(OGRH.Permissions.State.permissionDenials) do
        local denial = OGRH.Permissions.State.permissionDenials[i]
        OGRH.Msg(string.format("|cff00ccff[Permissions]|r [%s] %s attempted %s - %s", 
            date("%H:%M:%S", denial.timestamp),
            denial.player,
            denial.operation,
            denial.reason))
    end
    
    OGRH.Msg("|cff00ccff[Permissions]|r === End Denials ===")
end

OGRH.Msg("|cff00ccff[RH-Permissions]|r Loaded")
