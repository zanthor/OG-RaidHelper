-- OGRH_Poll.lua
local _G = getfenv(0)
local OGRH = _G.OGRH

-- Initialize Poll functionality
OGRH.Poll = OGRH.Poll or {}

-- Role order must match ROLE_COLUMNS from OGRH_RolesUI.lua
local ROLES_ORDER = {"TANKS", "HEALERS", "MELEE", "RANGED"}

-- Poll state
local activePoll = {
    active = false,
    currentRole = nil,
    lastPlusTime = 0,
    waitTime = 10,
    singleRolePoll = false,
    nextAdvanceTime = 0
}

-- Function to check if poll is active
function OGRH.Poll.IsActive()
    return activePoll.active
end

-- Function to stop the current poll
function OGRH.Poll.StopPoll()
    activePoll.active = false
    activePoll.currentRole = nil
    -- Update the UI
    if OGRH.rolesFrame then
        OGRH.rolesFrame:GetScript("OnEvent")()
    end
end

local function InitializePollMenu()
    -- Create menu for role selection
    OGRH.Poll.menu = CreateFrame("Frame", "OGRH_PollMenu", UIParent)
    OGRH.Poll.menu:SetWidth(100)
    OGRH.Poll.menu:SetHeight(140)
    OGRH.Poll.menu:SetFrameStrata("FULLSCREEN_DIALOG")
    OGRH.Poll.menu:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        edgeSize = 12,
        insets = {left = 4, right = 4, top = 4, bottom = 4}
    })
    OGRH.Poll.menu:SetBackdropColor(0, 0, 0, 0.95)
    OGRH.Poll.menu:Hide()

    -- Set up poll menu buttons
    local menuItems = {"TANKS", "HEALERS", "MELEE", "RANGED"}
    local buttons = {}
    local numItems = table.getn(menuItems)
    for i = 1, numItems do
        local btn = CreateFrame("Button", nil, OGRH.Poll.menu, "UIPanelButtonTemplate")
        btn:SetWidth(80)
        btn:SetHeight(20)
        if i == 1 then
            btn:SetPoint("TOPLEFT", OGRH.Poll.menu, "TOPLEFT", 10, -10)
        else
            btn:SetPoint("TOPLEFT", buttons[i-1], "BOTTOMLEFT", 0, -2)
        end
        btn:SetText(menuItems[i])
        local role = menuItems[i]  -- Store the role in a local variable for the closure
        btn:SetScript("OnClick", function()
            if OGRH.Poll.StartRolePoll then
                OGRH.Poll.StartRolePoll(role)
                OGRH.Poll.menu:Hide()
            end
        end)
        buttons[i] = btn
    end
end

-- Role order must match ROLE_COLUMNS from OGRH_RolesUI.lua
local ROLES_ORDER = {"TANKS", "HEALERS", "MELEE", "RANGED"}

-- Poll state
local activePoll = {
    active = false,
    currentRole = nil,
    lastPlusTime = 0,
    waitTime = 10,
    singleRolePoll = false,
    nextAdvanceTime = 0
}

function OGRH.Poll.StartRolePoll(role)
    -- If a poll is already active, stop it
    if activePoll.active then
        OGRH.Poll.StopPoll()
        return
    end

    activePoll.active = true
    activePoll.currentRole = role
    activePoll.lastPlusTime = GetTime()
    activePoll.singleRolePoll = (role ~= nil)
    
    if role then
        -- For single role poll, use the exact role passed
        activePoll.currentRole = role
        OGRH.SayRW(role .. " put + in raid chat.")
    else
        -- For full sequence, start with first role
        activePoll.currentRole = ROLES_ORDER[1]
        OGRH.SayRW(ROLES_ORDER[1] .. " put + in raid chat.")
    end
    
    activePoll.nextAdvanceTime = GetTime() + activePoll.waitTime

    -- Force UI update
    if OGRH.rolesFrame then
        OGRH.rolesFrame:GetScript("OnEvent")()
    end
end

-- Event frame for handling chat messages
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("CHAT_MSG_RAID")
eventFrame:RegisterEvent("CHAT_MSG_RAID_LEADER")
eventFrame:RegisterEvent("RAID_ROSTER_UPDATE")

eventFrame:SetScript("OnEvent", function()
    -- Keep roster information updated
    if event == "RAID_ROSTER_UPDATE" then
        OGRH.RefreshRoster()
        return
    end

    if not activePoll.active then return end
    
    local text, sender = arg1, arg2
    if not text or not sender then return end
    
    if string.find(text, "%+") then
        local playerName = string.match(sender, "^[^-]+") or sender
        
        -- Add to role using OGRH's system
        OGRH.EnsureSV() -- Ensure saved variables exist
        OGRH.AddTo(activePoll.currentRole, playerName)
        
        -- Force UI refresh
        if OGRH.rolesFrame and OGRH.rolesFrame:GetScript("OnEvent") then
            OGRH.rolesFrame:GetScript("OnEvent")()
        end
        
        activePoll.lastPlusTime = GetTime()
        activePoll.nextAdvanceTime = GetTime() + activePoll.waitTime
    end
end)

-- Update frame for poll timing
local updateFrame = CreateFrame("Frame")
updateFrame:SetScript("OnUpdate", function()
    if not activePoll.active then return end
    
    local currentTime = GetTime()
    if currentTime >= activePoll.nextAdvanceTime then
        -- Print completion message for current role
        print("|cFFFFFF00OGRH:|r Poll for " .. activePoll.currentRole .. " complete.")
        
        if activePoll.singleRolePoll then
            activePoll.active = false
            return
        end
        
        -- Find next role in sequence
        local nextRole = nil
        local roleCount = table.getn(ROLES_ORDER)
        for i = 1, roleCount do
            if ROLES_ORDER[i] == activePoll.currentRole then
                if i < roleCount then
                    nextRole = ROLES_ORDER[i + 1]
                end
                break
            end
        end
        
        if nextRole then
            -- Move to next role
            activePoll.currentRole = nextRole
            activePoll.lastPlusTime = currentTime
            activePoll.nextAdvanceTime = currentTime + activePoll.waitTime
            OGRH.SayRW(nextRole .. " put + in raid chat.")
        else
            -- End of sequence
            activePoll.active = false
            print("|cFFFFFF00OGRH:|r All role polls complete.")
        end
    end
end)

-- Initialize when the UI loads
local loader = CreateFrame("Frame")
loader:RegisterEvent("VARIABLES_LOADED")
loader:SetScript("OnEvent", function()
    if OGRH then
        -- Initialize everything needed
        OGRH.EnsureSV()
        OGRH.RefreshRoster()
        if not OGRH.Roles.buckets then 
            OGRH.Roles.buckets = { TANKS={}, HEALERS={}, MELEE={}, RANGED={} }
        end
        InitializePollMenu()
    end
end)

local ROLES_ORDER = {"TANKS", "HEALERS", "MELEE", "RANGED"}

-- Local variables for poll state
local activePoll = {
    active = false,
    currentRole = nil,
    lastPlusTime = 0,
    waitTime = 10,  -- 10 seconds wait time as requested
    singleRolePoll = false
}

-- Function to say messages in raid warning
local function sayRW(msg)
    if IsRaidLeader() or IsRaidOfficer() then
        SendChatMessage(msg, "RAID_WARNING")
    else
        SendChatMessage(msg, "RAID")
    end
end

-- Function to handle role changes
local function handleRoleChange(playerName, newRole)
    -- Check if player is in raid
    local isInRaid = false
    for i = 1, GetNumRaidMembers() do
        local name = GetRaidRosterInfo(i)
        if name and string.match(name, "^([^-]+)") == playerName then
            isInRaid = true
            break
        end
    end
    
    if not isInRaid then
        OGRH.Print(playerName .. " is not in the raid.")
        return
    end
    
    -- Remove from all roles first
    for _, roleColumn in ipairs(OGRH.ROLE_COLUMNS) do
        for i, name in ipairs(roleColumn.players) do
            if name == playerName then
                table.remove(roleColumn.players, i)
                break
            end
        end
    end

    -- Add to new role
    for i, column in ipairs(OGRH.ROLE_COLUMNS) do
        if column.name:upper() == newRole then
            table.insert(column.players, playerName)
            -- Save the role change
            if not OGRH_SV then OGRH_SV = {} end
            if not OGRH_SV.roles then OGRH_SV.roles = {} end
            OGRH_SV.roles[playerName] = newRole
            break
        end
    end
    
    -- Refresh the display
    RefreshColumnDisplays()
end

-- Function to start polling a specific role
local function startRolePoll(role)
    activePoll.active = true
    activePoll.currentRole = role
    activePoll.lastPlusTime = GetTime()
    activePoll.singleRolePoll = (role ~= nil)
    
    if role then
        sayRW(role .. " put + in raid chat.")
    else
        -- Start with first role in sequence
        activePoll.currentRole = ROLES_ORDER[1]
        sayRW(ROLES_ORDER[1] .. " put + in raid chat.")
    end
end

-- Function to stop polling
local function stopPoll()
    activePoll.active = false
    activePoll.currentRole = nil
end

-- Event frame for handling chat messages
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("CHAT_MSG_RAID")
eventFrame:RegisterEvent("CHAT_MSG_RAID_LEADER")
eventFrame:SetScript("OnEvent", function()
    if not activePoll.active then return end
    
    local text, sender = arg1, arg2
    if not text or not sender then return end
    
    if string.find(text, "%+") then
        local playerName = string.match(sender, "^[^-]+") or sender
        handleRoleChange(playerName, activePoll.currentRole)
        activePoll.lastPlusTime = GetTime()
    end
end)

-- Update frame for handling poll timing
local updateFrame = CreateFrame("Frame")
updateFrame:SetScript("OnUpdate", function()
    if not activePoll.active then return end
    
    local currentTime = GetTime()
    if currentTime - activePoll.lastPlusTime >= activePoll.waitTime then
        if activePoll.singleRolePoll then
            -- Stop polling if it was a single role poll
            stopPoll()
            return
        end
        
        -- Find next role in sequence
        local nextRole = nil
        for i, role in ipairs(ROLES_ORDER) do
            if role == activePoll.currentRole then
                if i < table.getn(ROLES_ORDER) then
                    nextRole = ROLES_ORDER[i + 1]
                end
                break
            end
        end
        
        if nextRole then
            -- Move to next role
            activePoll.currentRole = nextRole
            activePoll.lastPlusTime = currentTime
            sayRW(nextRole .. " put + in raid chat.")
        else
            -- End of sequence
            stopPoll()
        end
    end
end)