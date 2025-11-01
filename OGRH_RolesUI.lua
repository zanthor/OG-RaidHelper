-- OG-RaidHelper Roles UI
-- Author: Will + ChatGPT
-- Version: 1.15.0

--[[
  SIMPLIFIED ROLES UI
  
  This UI provides basic role column management with drag/drop functionality.
  Players are displayed alphabetically within each role column.
  
  REMOVED FEATURES (functionality exists elsewhere):
  - Encounter button: Use OGRH.ShowEncounterManagementWindow() directly
  - Marks button: Mark management integrated into Encounter system
  - Assignments button: Assignment system integrated into Encounter system
  - Test button: Test mode removed
  - Raid target icons: Marking handled by Encounter system
  - Tank assignment icons: Assignment handled by Encounter system
  - Up/Down arrows: Manual ordering replaced with alphabetical sort
  
  ACTIVE FEATURES:
  - Poll button: Start/cancel full role poll sequence (left click)
  - Role column headers: Click any role header to poll that specific role
  - Drag/drop: Move players between role columns
  - Alphabetical sorting: Players automatically sorted A-Z in each column
  - Class colors: Player names colored by class
  - Role persistence: Assigned roles saved in OGRH_SV.roles
--]]

-- Local Variables
local _G = getfenv(0)
local OGRH = _G.OGRH
local L = {}  -- Localization table

-- Constants for raid targets (in reverse order 8->1 as requested)
local RAID_TARGETS = {
    {id = 8, name = "Skull"},
    {id = 7, name = "Cross"},
    {id = 6, name = "Square"},
    {id = 5, name = "Moon"},
    {id = 4, name = "Triangle"},
    {id = 3, name = "Diamond"},
    {id = 2, name = "Circle"},
    {id = 1, name = "Star"}
}

-- Function to set raid target icon texture
local function SetRaidTargetIconTexture(texture, iconId)
    texture:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    local coords = {
        [1] = {0, 0.25, 0, 0.25},    -- Star
        [2] = {0.25, 0.5, 0, 0.25},  -- Circle
        [3] = {0.5, 0.75, 0, 0.25},  -- Diamond
        [4] = {0.75, 1, 0, 0.25},    -- Triangle
        [5] = {0, 0.25, 0.25, 0.5},  -- Moon
        [6] = {0.25, 0.5, 0.25, 0.5},-- Square
        [7] = {0.5, 0.75, 0.25, 0.5},-- Cross
        [8] = {0.75, 1, 0.25, 0.5},  -- Skull
    }
    local c = coords[iconId] or coords[1]
    texture:SetTexCoord(c[1], c[2], c[3], c[4])
end

-- Role columns
-- Storage for player raid target icons (kept for compatibility with other modules)
local PLAYER_RAID_TARGETS = {}

local ROLE_COLUMNS = {
    {name = "Tanks", players = {}},
    {name = "Healers", players = {}},
    {name = "Melee", players = {}},
    {name = "Ranged", players = {}}
}

local function CreateRolesFrame()
    -- Define column dimensions at the start
    local columnWidth = 190  -- (800 - 40) / 4
    local columnHeight = 500  -- (600 - 100)
    
    local function RefreshColumnDisplays()
        for colIndex, column in ipairs(ROLE_COLUMNS) do
            local yOffset = 0
            local content = column.contentFrame
            
            -- Clear existing entries
            local children = {content:GetChildren()}
            for i = 1, table.getn(children) do
                if children[i] then
                    children[i]:Hide()
                    children[i]:SetParent(nil)
                end
            end
            
            -- Add players
            for playerIndex = 1, table.getn(column.players) do
                local playerName = column.players[playerIndex]
                if playerName then
                    local playerFrame = CreateFrame("Frame", nil, content)
                    playerFrame:SetWidth(columnWidth - 40)
                    playerFrame:SetHeight(20)
                    playerFrame:SetPoint("TOPLEFT", 0, -yOffset)
                    
                    -- Player name text with class color and drag functionality
                    local nameButton = CreateFrame("Button", nil, playerFrame)
                    nameButton:SetWidth(columnWidth - 40)
                    nameButton:SetHeight(20)
                    nameButton:SetPoint("LEFT", 0, 0)
                    
                    -- Make it look like text but clickable
                    local nameText = nameButton:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
                    nameText:SetPoint("LEFT", 0, 0)
                    local class = OGRH.Roles.nameClass[playerName]
                    if class then
                        local coloredName = OGRH.ClassColorHex(class) .. playerName .. "|r"
                        nameText:SetText(coloredName)
                    else
                        nameText:SetText(playerName)
                    end
                    
                    -- Add drag functionality
                    nameButton:RegisterForDrag("LeftButton")
                    nameButton:SetMovable(true)
                    
                    -- Store references for the drag handlers
                    local currentColumn = column
                    local draggedIndex = playerIndex
                    local draggedName = playerName
                    
                    -- Create a drag frame that follows the cursor
                    local dragFrame = CreateFrame("Frame", nil, UIParent)
                    dragFrame:SetWidth(nameButton:GetWidth())
                    dragFrame:SetHeight(nameButton:GetHeight())
                    dragFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
                    dragFrame:Hide()
                    
                    local dragText = dragFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                    dragText:SetPoint("CENTER", dragFrame, "CENTER", 0, 0)
                    dragText:SetText(nameText:GetText())
                    
                    nameButton:SetScript("OnDragStart", function()
                        dragFrame:Show()
                        dragFrame:SetScript("OnUpdate", function()
                            local x, y = GetCursorPosition()
                            local scale = UIParent:GetEffectiveScale()
                            dragFrame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x/scale, y/scale)
                        end)
                    end)
                    
                    nameButton:SetScript("OnDragStop", function()
                        dragFrame:Hide()
                        dragFrame:SetScript("OnUpdate", nil)
                        
                        -- Find which column we're over
                        local x, y = GetCursorPosition()
                        local scale = UIParent:GetEffectiveScale()
                        x = x/scale
                        y = y/scale
                        
                        -- Check each column frame to see if we're over it
                        for colIndex, roleColumn in ipairs(ROLE_COLUMNS) do
                            local columnFrame = roleColumn.contentFrame:GetParent()
                            local left, right, bottom, top = columnFrame:GetLeft(), columnFrame:GetRight(), columnFrame:GetBottom(), columnFrame:GetTop()
                            
                            if x >= left and x <= right and y >= bottom and y <= top then
                                -- Only move if we're dropping into a different column
                                if colIndex ~= currentIndex then
                                    -- Remove from current column
                                    table.remove(currentColumn.players, draggedIndex)
                                    
                                    -- Add to new column
                                    table.insert(roleColumn.players, draggedName)
                                    
                                    -- Save the role change
                                    if not OGRH_SV then OGRH_SV = {} end
                                    if not OGRH_SV.roles then OGRH_SV.roles = {} end
                                    
                                    local newRole
                                    if colIndex == 1 then newRole = "TANKS"
                                    elseif colIndex == 2 then newRole = "HEALERS"
                                    elseif colIndex == 3 then newRole = "MELEE"
                                    else newRole = "RANGED" end
                                    
                                    OGRH_SV.roles[draggedName] = newRole
                                    
                                    -- Refresh display
                                    RefreshColumnDisplays()
                                end
                                break
                            end
                        end
                    end)
                    
                    yOffset = yOffset + 25
                end
            end
            
            -- Add headers
            if column.headers then
                for i = 1, table.getn(column.headers) do
                    local header = column.headers[i]
                    if header then
                        local headerFrame = CreateFrame("Frame", nil, content)
                        headerFrame:SetWidth(columnWidth - 40)
                        headerFrame:SetHeight(20)
                        headerFrame:SetPoint("TOPLEFT", 0, -yOffset)
                        
                        local headerText = headerFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
                        headerText:SetPoint("CENTER", 0, 0)
                        headerText:SetText(header)
                        
                        yOffset = yOffset + 25
                    end
                end
            end
            
            -- Set final content height
            content:SetHeight(math.max(columnHeight, yOffset))
        end
    end
    
    -- Main frame
    local frame
    if UIParent then
        frame = CreateFrame("Frame", "OGRH_RolesFrame", UIParent)
        if frame then
            frame:SetWidth(800)
            frame:SetHeight(600)
            -- Set initial position or restore saved position
            frame:ClearAllPoints()
            frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        else
            print("Error: Failed to create OGRH_RolesFrame")
            return
        end
    else
        print("Error: UIParent not available")
        return
    end
    frame:EnableMouse(true)
    frame:SetMovable(true)
    
    -- Background
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = {left = 4, right = 4, top = 4, bottom = 4}
    })
    frame:SetBackdropColor(0, 0, 0, 0.9)
    
    -- Make frame draggable
    frame:SetScript("OnMouseDown", function()
        frame:StartMoving()
    end)
    frame:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        -- Save position
        if not OGRH_SV then OGRH_SV = {} end
        if not OGRH_SV.rolesUI then OGRH_SV.rolesUI = {} end
        local point, _, relPoint, x, y = frame:GetPoint()
        OGRH_SV.rolesUI.point = point
        OGRH_SV.rolesUI.relPoint = relPoint
        OGRH_SV.rolesUI.x = x
        OGRH_SV.rolesUI.y = y
    end)
    
    -- Create buttons
    local pollBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    pollBtn:SetWidth(80)
    pollBtn:SetHeight(24)
    pollBtn:SetPoint("TOPLEFT", 20, -20)
    pollBtn:SetText("Poll")
    
    pollBtn:RegisterForClicks("LeftButtonUp")
    local function UpdatePollButtonText()
        -- Double check to ensure OGRH.Poll exists
        if not OGRH.Poll then return end
        
        -- Just update the text directly based on current state
        if OGRH.Poll.IsActive and OGRH.Poll.IsActive() then
            pollBtn:SetText("Cancel")
        else
            pollBtn:SetText("Poll")
        end
    end

    pollBtn:SetScript("OnClick", function()
        if OGRH.Poll then
            if OGRH.Poll.IsActive and OGRH.Poll.IsActive() then
                -- Cancel ongoing poll
                if OGRH.Poll.StopPoll then
                    OGRH.Poll.StopPoll()
                    print("|cFFFFFF00OGRH:|r Poll cancelled.")
                end
            else
                -- Start full role poll sequence
                if OGRH.Poll.StartRolePoll then
                    OGRH.Poll.StartRolePoll()
                else
                    print("Error: Poll functionality not loaded")
                end
            end
            UpdatePollButtonText()
        else
            print("Error: Poll functionality not loaded")
        end
    end)

    -- Set initial button text
    UpdatePollButtonText()
    
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    closeBtn:SetWidth(80)
    closeBtn:SetHeight(24)
    closeBtn:SetPoint("TOPRIGHT", -20, -20)
    closeBtn:SetText("Close")
    closeBtn:SetScript("OnClick", function()
        frame:Hide()
    end)

    
    -- Create Role Columns
    local columnStartY = -80
    
    for i, column in ipairs(ROLE_COLUMNS) do
        local columnFrame = CreateFrame("Frame", nil, frame)
        columnFrame:SetWidth(columnWidth)
        columnFrame:SetHeight(columnHeight)
        columnFrame:SetPoint("TOPLEFT", 20 + ((i-1) * columnWidth), columnStartY)
        
        -- Create clickable header button
        local headerBtn = CreateFrame("Button", nil, columnFrame)
        headerBtn:SetWidth(columnWidth - 16)
        headerBtn:SetHeight(20)
        headerBtn:SetPoint("TOP", 0, -4)
        
        local headerText = headerBtn:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        headerText:SetPoint("CENTER", 0, 0)
        headerText:SetText(column.name)
        
        -- Map column names to role constants used by poll system
        local roleMap = {
            ["Tanks"] = "TANKS",
            ["Healers"] = "HEALERS",
            ["Melee"] = "MELEE",
            ["Ranged"] = "RANGED"
        }
        local pollRole = roleMap[column.name]
        
        -- Add click functionality to start role-specific poll
        headerBtn:SetScript("OnClick", function()
            if OGRH.Poll then
                if OGRH.Poll.IsActive and OGRH.Poll.IsActive() then
                    -- Poll is active, cancel it
                    if OGRH.Poll.StopPoll then
                        OGRH.Poll.StopPoll()
                        print("|cFFFFFF00OGRH:|r Poll cancelled.")
                    end
                else
                    -- Start role-specific poll
                    if OGRH.Poll.StartRolePoll and pollRole then
                        OGRH.Poll.StartRolePoll(pollRole)
                    else
                        print("Error: Poll functionality not loaded")
                    end
                end
            else
                print("Error: Poll functionality not loaded")
            end
        end)
        
        -- Add highlight on hover
        headerBtn:SetScript("OnEnter", function()
            headerText:SetTextColor(1, 1, 0)  -- Yellow on hover
        end)
        
        headerBtn:SetScript("OnLeave", function()
            headerText:SetTextColor(1, 1, 1)  -- White normally
        end)
        
        columnFrame:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 16,
            insets = {left = 4, right = 4, top = 4, bottom = 4}
        })
        columnFrame:SetBackdropColor(0, 0, 0, 0.5)
        
        local content = CreateFrame("Frame", nil, columnFrame)
        content:SetPoint("TOPLEFT", 8, -24)
        content:SetPoint("BOTTOMRIGHT", -8, 8)
        
        column.contentFrame = content
    end
    
    -- Function to update player lists
    local function UpdatePlayerLists()
        -- Load saved raid target assignments
        if OGRH_SV and OGRH_SV.raidTargets then
            for name, iconId in pairs(OGRH_SV.raidTargets) do
                PLAYER_RAID_TARGETS[name] = iconId
            end
        end
        
        -- Create temporary copy of raid targets
        local tempTargets = {}
        for name, iconId in pairs(PLAYER_RAID_TARGETS) do
            tempTargets[name] = iconId
        end
        
        -- Clear lists
        for i = 1, table.getn(ROLE_COLUMNS) do
            ROLE_COLUMNS[i].players = {}
        end
        PLAYER_RAID_TARGETS = tempTargets
        
        local numRaidMembers = GetNumRaidMembers()
        if numRaidMembers > 0 then
            for i = 1, numRaidMembers do
                local name, _, _, _, class = GetRaidRosterInfo(i)
                if name then
                    if class then
                        class = string.upper(class)
                        OGRH.Roles.nameClass[name] = class
                    
                        local roleIndex = 4  -- Default to Ranged
                        
                        if OGRH_SV and OGRH_SV.roles and OGRH_SV.roles[name] then
                            local savedRole = OGRH_SV.roles[name]
                            if savedRole == "TANKS" then roleIndex = 1
                            elseif savedRole == "HEALERS" then roleIndex = 2
                            elseif savedRole == "MELEE" then roleIndex = 3
                            end
                        else
                            if class == "WARRIOR" then
                                roleIndex = 1  -- Tanks
                            elseif class == "PRIEST" or (class == "PALADIN") or (class == "DRUID") then
                                roleIndex = 2  -- Healers
                            elseif class == "ROGUE" then
                                roleIndex = 3  -- Melee
                            end
                        end
                        
                        table.insert(ROLE_COLUMNS[roleIndex].players, name)
                    end
                end
            end
        end
        
        -- Sort all columns alphabetically
        for i = 1, table.getn(ROLE_COLUMNS) do
            table.sort(ROLE_COLUMNS[i].players, function(a, b) 
                return string.upper(a) < string.upper(b)
            end)
        end
        
        RefreshColumnDisplays()
    end
    
    -- Initial update and event registration
    UpdatePlayerLists()
    
    frame:RegisterEvent("RAID_ROSTER_UPDATE")
    frame:SetScript("OnEvent", function()
        UpdatePlayerLists()
    end)
    
    -- Make ROLE_COLUMNS accessible to child frames
    frame.ROLE_COLUMNS = ROLE_COLUMNS
    
    frame:Hide()
    
    OGRH.rolesFrame = frame
    OGRH.rolesFrame.RefreshColumnDisplays = RefreshColumnDisplays
    OGRH.rolesFrame.UpdatePlayerLists = UpdatePlayerLists
    
    -- Standardized role access functions
    OGRH.GetRolePlayers = function(role)
        if role == "TANKS" then
            return ROLE_COLUMNS[1].players
        elseif role == "HEALERS" then
            return ROLE_COLUMNS[2].players
        elseif role == "MELEE" then
            return ROLE_COLUMNS[3].players
        elseif role == "RANGED" then
            return ROLE_COLUMNS[4].players
        end
        return {}
    end
    
    -- Get count of players in a role
    OGRH.GetRoleCount = function(role)
        local players = OGRH.GetRolePlayers(role)
        return players and table.getn(players) or 0
    end
    
    -- Iterate through players in a role with a callback
    OGRH.ForEachRolePlayer = function(role, callback)
        if not callback then return end
        local players = OGRH.GetRolePlayers(role)
        for i = 1, table.getn(players) do
            callback(players[i], i)
        end
    end
    
    -- Backward compatibility for existing code
    OGRH.rolesFrame.tanksList = ROLE_COLUMNS[1].players
    OGRH.rolesFrame.getHealers = function()
        return ROLE_COLUMNS[2].players
    end
    
    OGRH.ShowRolesUI = function()
        frame:Show()
    end
    OGRH.HideRolesUI = function()
        frame:Hide()
    end

    -- Create encounter panels
    local razorgorePanel, vaelTrashPanel, cthunPanel
    
    -- Create BWL panels
    if OGRH.BWL then
        razorgorePanel = OGRH.BWL.CreateRazorgorePanel(frame, encounterBtn)
        vaelTrashPanel = OGRH.BWL.CreateVaelTrashPanel(frame, encounterBtn)
    else
        print("|cFFFFFF00OGRH:|r Error: BWL module not found!")
    end

    -- Create AQ40 panels
    if OGRH.AQ40 then
        cthunPanel = OGRH.AQ40.CreateCThunPanel(frame, encounterBtn)
    else
        print("|cFFFFFF00OGRH:|r Error: AQ40 module not found!")
    end

    local function HideAllPanels()
        if razorgorePanel then razorgorePanel:Hide() end
        if vaelTrashPanel then vaelTrashPanel:Hide() end
        if cthunPanel then cthunPanel:Hide() end
    end

    OGRH.ShowRazorgorePanel = function()
        HideAllPanels()
        if razorgorePanel then
            razorgorePanel:Show()
        else
            print("|cFFFFFF00OGRH:|r Error: Razorgore panel could not be created!")
        end
    end

    OGRH.ShowVaelTrashPanel = function()
        HideAllPanels()
        if vaelTrashPanel then
            vaelTrashPanel:Show()
        else
            print("|cFFFFFF00OGRH:|r Error: Vael Trash panel could not be created!")
        end
    end

    OGRH.ShowCThunPanel = function()
        HideAllPanels()
        if cthunPanel then
            cthunPanel:Show()
        else
            print("|cFFFFFF00OGRH:|r Error: C'Thun panel could not be created!")
        end
    end
end

-- Initialize when addon loads
local _loader = CreateFrame("Frame")
_loader:RegisterEvent("VARIABLES_LOADED")
_loader:SetScript("OnEvent", function()
    if OGRH then
        CreateRolesFrame()
    else
        print("Error: OGRH_RolesUI requires OGRH_Core to be loaded first!")
    end
end)