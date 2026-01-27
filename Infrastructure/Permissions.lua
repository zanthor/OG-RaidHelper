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
    currentAdmin = nil,           -- Current raid admin name
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
function OGRH.SetRaidAdmin(playerName, suppressBroadcast)
    if not playerName then return false end
    
    local previousAdmin = OGRH.Permissions.State.currentAdmin
    
    -- If admin hasn't changed, don't do anything (prevents broadcast loops)
    if previousAdmin == playerName then
        return true
    end
    
    OGRH.Permissions.State.currentAdmin = playerName
    
    -- Clear session admin when normal admin changes
    OGRH.Permissions.State.sessionAdmin = nil
    
    -- Update legacy state for backward compatibility
    if OGRH.RaidLead then
        OGRH.RaidLead.currentLead = playerName
    end
    
    -- Save to saved variables
    OGRH.EnsureSV()
    
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
    if OGRH.UpdateRaidLeadUI then
        OGRH.UpdateRaidLeadUI()
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

-- Request admin role (only Raid Lead or Assist can request)
function OGRH.RequestAdminRole()
    local playerName = UnitName("player")
    
    if not OGRH.IsRaidOfficer(playerName) and not OGRH.Permissions.IsSessionAdmin(playerName) then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[RH]|r Only Raid Lead or Assist can request admin role")
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
                    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[OGRH]|r You are now the raid admin")
                end
            }
        )
    else
        -- Fallback if MessageRouter not available
        OGRH.SetRaidAdmin(playerName)
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[RH]|r You are now the raid admin")
    end
    
    return true
end

-- Poll raid to discover current admin (called on reload, raid join, login)
function OGRH.PollForRaidAdmin()
    if not UnitInRaid("player") then
        return  -- Not in a raid
    end
    
    if not OGRH.MessageRouter or not OGRH.MessageTypes then
        return  -- MessageRouter not initialized yet
    end
    
    -- Broadcast query to all raid members
    OGRH.MessageRouter.Broadcast(OGRH.MessageTypes.ADMIN.QUERY, "", {
        priority = "HIGH"
    })
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
    if OGRH.UpdateRaidLeadUI then
        OGRH.UpdateRaidLeadUI()
    end
    
    DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[OGRH]|r %s granted session admin (temporary)", playerName))
    DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[OGRH]|r Session admin will be cleared when another admin is selected")
    
    return true
end

-- Assign admin role to another player (current admin or L/A can assign to another L/A)
function OGRH.AssignAdminRole(targetPlayer)
    local playerName = UnitName("player")
    
    if not OGRH.CanModifyStructure(playerName) and not OGRH.IsRaidOfficer(playerName) then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[RH]|r Only admin or Raid Lead/Assist can assign admin role")
        return false
    end
    
    if not OGRH.IsRaidOfficer(targetPlayer) and not OGRH.Permissions.IsSessionAdmin(targetPlayer) then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[RH]|r Can only assign admin to Raid Lead or Assist")
        return false
    end
    
    -- Broadcast admin assignment via OGAddonMsg
    if OGAddonMsg and OGAddonMsg.Send then
        OGAddonMsg.Send(nil, nil, OGRH.MessageTypes.ADMIN.ASSIGN, {
            newAdmin = targetPlayer,
            assignedBy = playerName,
            timestamp = GetTime(),
            version = OGRH.IncrementDataVersion and OGRH.IncrementDataVersion() or 1
        }, {
            priority = "HIGH",
            onSuccess = function()
                OGRH.SetRaidAdmin(targetPlayer)
                DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[OGRH]|r %s is now the raid admin", targetPlayer))
            end
        })
    else
        -- Fallback if OGAddonMsg not available
        OGRH.SetRaidAdmin(targetPlayer)
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[RH]|r %s is now the raid admin", targetPlayer))
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
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff0000[RH]|r Permission denied: %s", operation))
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff0000[RH]|r Your level: %s", OGRH.GetPermissionLevel(playerName)))
    end
    
    -- Broadcast permission denial (optional, for audit purposes)
    if OGAddonMsg and OGAddonMsg.Send then
        OGAddonMsg.Send(nil, nil, OGRH.MessageTypes.ADMIN.PERMISSION_DENIED, {
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
    -- Load from SavedVariables if available
    if OGRH_SV and OGRH_SV.Permissions then
        OGRH.Permissions.State = OGRH_SV.Permissions
    end
    
    -- Auto-detect admin if not set (raid leader becomes admin)
    if not OGRH.Permissions.State.currentAdmin then
        local numRaidMembers = GetNumRaidMembers()
        if numRaidMembers > 0 then
            for i = 1, numRaidMembers do
                local name, rank = GetRaidRosterInfo(i)
                if rank == 2 then
                    -- Raid leader found
                    OGRH.SetRaidAdmin(name)
                    DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[RH]|r Auto-assigned %s as raid admin", name))
                    break
                end
            end
        end
    end
    
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[RH-Permissions]|r System initialized")
end

-- Save permission state to SavedVariables
function OGRH.Permissions.Save()
    if OGRH_SV then
        OGRH_SV.Permissions = OGRH.Permissions.State
    end
end

--[[
    Debug Commands
]]

-- Debug: Print permission info for all raid members
function OGRH.Permissions.DebugPrintRaidPermissions()
    DEFAULT_CHAT_FRAME:AddMessage("[OGRH] === Raid Permissions ===")
    DEFAULT_CHAT_FRAME:AddMessage(string.format("[OGRH] Current Admin: %s", OGRH.Permissions.State.currentAdmin or "None"))
    
    local numRaidMembers = GetNumRaidMembers()
    if numRaidMembers == 0 then
        DEFAULT_CHAT_FRAME:AddMessage("[OGRH] Not in a raid")
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
        
        DEFAULT_CHAT_FRAME:AddMessage(string.format("[OGRH] %s - Rank: %s, Permission: %s", name, rankStr, level))
    end
    
    DEFAULT_CHAT_FRAME:AddMessage("[OGRH] === End Permissions ===")
end

-- Debug: Print permission denial log
function OGRH.Permissions.DebugPrintDenials()
    DEFAULT_CHAT_FRAME:AddMessage("[OGRH] === Permission Denials ===")
    
    if table.getn(OGRH.Permissions.State.permissionDenials) == 0 then
        DEFAULT_CHAT_FRAME:AddMessage("[OGRH] No denials recorded")
        return
    end
    
    for i = 1, table.getn(OGRH.Permissions.State.permissionDenials) do
        local denial = OGRH.Permissions.State.permissionDenials[i]
        DEFAULT_CHAT_FRAME:AddMessage(string.format("[OGRH] [%s] %s attempted %s - %s", 
            date("%H:%M:%S", denial.timestamp),
            denial.player,
            denial.operation,
            denial.reason))
    end
    
    DEFAULT_CHAT_FRAME:AddMessage("[OGRH] === End Denials ===")
end

OGRH.Msg("|cff00ccff[RH-Permissions]|r Loaded")
