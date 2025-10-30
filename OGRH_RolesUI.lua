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
-- Storage for player raid target icons
local PLAYER_RAID_TARGETS = {}

-- Global test mode state for module
OGRH.testMode = false

-- Function to get player mark (checks PLAYER_RAID_TARGETS in test mode, OGRH_SV otherwise)
function OGRH.GetPlayerMark(playerName)
    -- First check PLAYER_RAID_TARGETS (works in both test and normal mode)
    local mark = PLAYER_RAID_TARGETS[playerName]
    if mark then
        return mark
    end
    -- Fall back to saved variables (only populated in normal mode)
    if OGRH_SV and OGRH_SV.raidTargets then
        return OGRH_SV.raidTargets[playerName]
    end
    return nil
end

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
                    
                    -- Raid Target Icon
                    local targetIconBtn = CreateFrame("Button", nil, playerFrame)
                    targetIconBtn:SetWidth(16)
                    targetIconBtn:SetHeight(16)
                    targetIconBtn:SetPoint("LEFT", 0, 0)
                    
                    -- Create background for empty state
                    local background = targetIconBtn:CreateTexture(nil, "BACKGROUND")
                    background:SetAllPoints(targetIconBtn)
                    background:SetTexture("Interface\\Buttons\\WHITE8X8")
                    background:SetVertexColor(0.2, 0.2, 0.2, 0.5)
                    
                    -- Create icon texture
                    local targetIconTexture = targetIconBtn:CreateTexture(nil, "ARTWORK")
                    targetIconTexture:SetAllPoints(targetIconBtn)
                    
                    -- Create text for "None" state
                    local noneText = targetIconBtn:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
                    noneText:SetPoint("CENTER", targetIconBtn, "CENTER", 0, 0)
                    noneText:SetText("O")
                    
                    -- Function to update icon display
                    local function UpdateIconDisplay(iconId)
                        if iconId then
                            targetIconTexture:Show()
                            noneText:Hide()
                            SetRaidTargetIconTexture(targetIconTexture, iconId)
                        else
                            targetIconTexture:Hide()
                            noneText:Show()
                        end
                        
                        -- Save state if it changed
                        if PLAYER_RAID_TARGETS[playerName] ~= iconId then
                            PLAYER_RAID_TARGETS[playerName] = iconId
                            if not OGRH.testMode then
                                -- Only save to SavedVariables and set raid target when not in test mode
                                if not OGRH_SV then OGRH_SV = {} end
                                if not OGRH_SV.raidTargets then OGRH_SV.raidTargets = {} end
                                OGRH_SV.raidTargets[playerName] = iconId
                                -- Try to find unit in raid and set mark
                                for i = 1, GetNumRaidMembers() do
                                    if GetRaidRosterInfo(i) == playerName then
                                        SetRaidTarget("raid"..i, iconId or 0)
                                        break
                                    end
                                end
                            end
                        end
                    end
                    
                    -- Set initial state
                    UpdateIconDisplay(PLAYER_RAID_TARGETS[playerName])
                    
                    -- Handle clicks to cycle through icons
                    targetIconBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
                    targetIconBtn:SetScript("OnClick", function()
                        local button = arg1 or "LeftButton"
                        --print("OGRH Debug: Icon clicked with " .. button)
                        local currentIcon = PLAYER_RAID_TARGETS[playerName]
                        
                        if button == "LeftButton" then
                            -- Cycle forward (nil->8->7->...->1)
                            if not currentIcon then
                                UpdateIconDisplay(8)
                            elseif currentIcon == 1 then
                                UpdateIconDisplay(nil)
                            else
                                UpdateIconDisplay(currentIcon - 1)
                            end
                        elseif button == "RightButton" then
                            -- Cycle backward (1->2->...->8->nil)
                            if not currentIcon then
                                UpdateIconDisplay(1)
                            elseif currentIcon == 8 then
                                UpdateIconDisplay(nil)
                            else
                                UpdateIconDisplay(currentIcon + 1)
                            end
                        end
                    end)
                    
                    -- Up button
                    local upBtn = CreateFrame("Button", nil, playerFrame)
                    upBtn:SetWidth(25)
                    upBtn:SetHeight(25)
                    upBtn:SetPoint("LEFT", targetIconBtn, "RIGHT", 2, 0)
                    upBtn:SetNormalTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Up")
                    upBtn:SetPushedTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Down")
                    upBtn:SetHighlightTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Highlight")
                    
                    local currentIndex = playerIndex
                    local currentColumn = column  -- Store column reference for closure
                    upBtn:SetScript("OnClick", function()
                        if currentIndex > 1 then
                            local temp = currentColumn.players[currentIndex]
                            currentColumn.players[currentIndex] = currentColumn.players[currentIndex-1]
                            currentColumn.players[currentIndex-1] = temp
                            RefreshColumnDisplays()
                        end
                    end)
                    
                    -- Down button
                    local downBtn = CreateFrame("Button", nil, playerFrame)
                    downBtn:SetWidth(25)
                    downBtn:SetHeight(25)
                    downBtn:SetPoint("LEFT", upBtn, "RIGHT", -8, 0)
                    downBtn:SetNormalTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up")
                    downBtn:SetPushedTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Down")
                    downBtn:SetHighlightTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Highlight")
                    
                    downBtn:SetScript("OnClick", function()
                        if currentIndex < table.getn(currentColumn.players) then
                            local temp = currentColumn.players[currentIndex]
                            currentColumn.players[currentIndex] = currentColumn.players[currentIndex+1]
                            currentColumn.players[currentIndex+1] = temp
                            RefreshColumnDisplays()
                        end
                    end)
                    
                    -- Player assignment button (for all roles)
                    local assignBtn = CreateFrame("Button", nil, playerFrame)
                    assignBtn:SetWidth(16)
                    assignBtn:SetHeight(16)
                    assignBtn:SetPoint("LEFT", downBtn, "RIGHT", 2, 0)
                    
                    -- Create background for empty state
                    local assignBackground = assignBtn:CreateTexture(nil, "BACKGROUND")
                    assignBackground:SetAllPoints(assignBtn)
                    assignBackground:SetTexture("Interface\\Buttons\\WHITE8X8")
                    assignBackground:SetVertexColor(0.2, 0.2, 0.2, 0.5)
                    
                    -- Create icon texture for raid icons (1-8)
                    local assignTexture = assignBtn:CreateTexture(nil, "ARTWORK")
                    assignTexture:SetAllPoints(assignBtn)
                    
                    -- Create text for "None" state and numbers (0-9)
                    local assignText = assignBtn:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
                    assignText:SetPoint("CENTER", assignBtn, "CENTER", 0, 0)
                    assignText:SetText("O")
                    
                    -- Function to update assignment display
                    local function UpdateAssignDisplay(assignData)
                        if assignData and assignData.type == "icon" and assignData.value >= 1 and assignData.value <= 8 then
                            -- Display as raid icon
                            assignTexture:Show()
                            assignText:Hide()
                            SetRaidTargetIconTexture(assignTexture, assignData.value)
                        elseif assignData and assignData.type == "number" and assignData.value >= 0 and assignData.value <= 9 then
                            -- Display as number (0-9)
                            assignTexture:Hide()
                            assignText:Show()
                            assignText:SetText(tostring(assignData.value))
                        else
                            -- Display as empty/none
                            assignTexture:Hide()
                            assignText:Show()
                            assignText:SetText("O")
                        end
                        
                        -- Save state (always save, even in test mode)
                        OGRH.SetPlayerAssignment(playerName, assignData)
                    end
                    
                    -- Set initial state
                    local initialValue = OGRH.GetPlayerAssignment(playerName)
                    UpdateAssignDisplay(initialValue)
                    
                    -- Handle clicks to cycle through values
                    -- Cycle order: nil -> {icon,8} -> {icon,7} -> ... -> {icon,1} -> {num,9} -> {num,8} -> ... -> {num,0} -> nil
                    assignBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
                    assignBtn:SetScript("OnClick", function()
                        local button = arg1 or "LeftButton"
                        local currentValue = OGRH.GetPlayerAssignment(playerName)
                        
                        if button == "LeftButton" then
                            -- Cycle forward (nil->{icon,8}->{icon,7}->...{icon,1}->{num,9}->{num,8}->...{num,0}->nil)
                            if not currentValue then
                                UpdateAssignDisplay({type = "icon", value = 8})
                            elseif currentValue.type == "icon" and currentValue.value == 1 then
                                UpdateAssignDisplay({type = "number", value = 9})
                            elseif currentValue.type == "icon" and currentValue.value > 1 then
                                UpdateAssignDisplay({type = "icon", value = currentValue.value - 1})
                            elseif currentValue.type == "number" and currentValue.value == 0 then
                                UpdateAssignDisplay(nil)
                            elseif currentValue.type == "number" and currentValue.value > 0 then
                                UpdateAssignDisplay({type = "number", value = currentValue.value - 1})
                            else
                                UpdateAssignDisplay(nil)
                            end
                        elseif button == "RightButton" then
                            -- Cycle backward (nil->{num,0}->{num,1}->...{num,9}->{icon,1}->{icon,2}->...{icon,8}->nil)
                            if not currentValue then
                                UpdateAssignDisplay({type = "number", value = 0})
                            elseif currentValue.type == "number" and currentValue.value == 9 then
                                UpdateAssignDisplay({type = "icon", value = 1})
                            elseif currentValue.type == "number" and currentValue.value < 9 then
                                UpdateAssignDisplay({type = "number", value = currentValue.value + 1})
                            elseif currentValue.type == "icon" and currentValue.value == 8 then
                                UpdateAssignDisplay(nil)
                            elseif currentValue.type == "icon" and currentValue.value < 8 then
                                UpdateAssignDisplay({type = "icon", value = currentValue.value + 1})
                            else
                                UpdateAssignDisplay(nil)
                            end
                        end
                    end)
                    
                    -- Player name text with class color and drag functionality
                    local nameButton = CreateFrame("Button", nil, playerFrame)
                    nameButton:SetWidth(columnWidth - 100)  -- Adjust width for all columns now have assignBtn
                    nameButton:SetHeight(20)
                    nameButton:SetPoint("LEFT", assignBtn, "RIGHT", 4, 0)
                    
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
    
    -- Background (matching MainUI border style)
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = {left = 4, right = 4, top = 4, bottom = 4}
    })
    frame:SetBackdropColor(0, 0, 0, 0.85)
    
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
    
    -- Create Encounters button and menu
    local encounterBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    encounterBtn:SetWidth(80)
    encounterBtn:SetHeight(24)
    encounterBtn:SetPoint("LEFT", pollBtn, "RIGHT", 5, 0)
    encounterBtn:SetText("Encounter")
    
    -- Create encounter menu
    local encounterMenu = CreateFrame("Frame", "OGRH_EncounterMenu", UIParent)
    encounterMenu:SetWidth(120)
    encounterMenu:SetHeight(100)
    encounterMenu:SetFrameStrata("FULLSCREEN_DIALOG")
    encounterMenu:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        edgeSize = 12,
        insets = {left = 4, right = 4, top = 4, bottom = 4}
    })
    encounterMenu:SetBackdropColor(0, 0, 0, 0.95)
    encounterMenu:Hide()

    -- Create encounter menu buttons
    local buttons = {}
    
    -- Helper function to add menu button
    local function AddEncounterButton(text, handler)
        local i = table.getn(buttons) + 1
        local btn = CreateFrame("Button", nil, encounterMenu, "UIPanelButtonTemplate")
        btn:SetWidth(110)
        btn:SetHeight(20)
        if i == 1 then
            btn:SetPoint("TOPLEFT", encounterMenu, "TOPLEFT", 5, -5)
        else
            btn:SetPoint("TOPLEFT", buttons[i-1], "BOTTOMLEFT", 0, -2)
        end
        btn:SetText(text)
        btn:SetScript("OnClick", function()
            encounterMenu:Hide()
            handler()
        end)
        table.insert(buttons, btn)
    end

    -- Add each encounter button
    AddEncounterButton("BWL - Razorgore", function()
        OGRH.ShowRazorgorePanel()
    end)
    
    AddEncounterButton("BWL - Firemaw", function()
        OGRH.ShowFiremawPanel()
    end)
    
    AddEncounterButton("BWL - Nefarion", function()
        DEFAULT_CHAT_FRAME:AddMessage("Coming soon: BWL - Nefarion")
    end)
    
    AddEncounterButton("AQ40 - Skeram", function()
        DEFAULT_CHAT_FRAME:AddMessage("Coming soon: AQ40 - Skeram")
    end)
    
    AddEncounterButton("AQ40 - Bug Trio", function()
        DEFAULT_CHAT_FRAME:AddMessage("Coming soon: AQ40 - Bug Trio")
    end)
    
    AddEncounterButton("AQ40 - Twins", function()
        DEFAULT_CHAT_FRAME:AddMessage("Coming soon: AQ40 - Twins")
    end)
    
    AddEncounterButton("AQ40 - C'Thun", function()
        OGRH.ShowCThunPanel()
    end)
    
    AddEncounterButton("Naxx - Gothik", function()
        DEFAULT_CHAT_FRAME:AddMessage("Coming soon: Naxx - Gothik")
    end)
    
    AddEncounterButton("Naxx - 4HM", function()
        DEFAULT_CHAT_FRAME:AddMessage("Coming soon: Naxx - 4HM")
    end)
    
    AddEncounterButton("Naxx - Kel'Thuzad", function()
        DEFAULT_CHAT_FRAME:AddMessage("Coming soon: Naxx - Kel'Thuzad")
    end)
    
    encounterMenu:SetHeight(15 + (table.getn(buttons) * 20) + ((table.getn(buttons) - 1) * 2) + 5)

    encounterBtn:SetScript("OnClick", function()
        if encounterMenu:IsVisible() then
            encounterMenu:Hide()
        else
            encounterMenu:ClearAllPoints()
            encounterMenu:SetPoint("TOPLEFT", encounterBtn, "BOTTOMLEFT", 0, -2)
            encounterMenu:Show()
        end
    end)
    pollBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
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
        local button = arg1 or "LeftButton"
        if OGRH.Poll then
            if OGRH.Poll.IsActive and OGRH.Poll.IsActive() then
                -- Cancel ongoing poll
                if OGRH.Poll.StopPoll then
                    OGRH.Poll.StopPoll()
                    if OGRH.Poll.menu then
                        OGRH.Poll.menu:Hide()
                    end
                    print("|cFFFFFF00OGRH:|r Poll cancelled.")
                end
            else
                if button == "LeftButton" then
                    -- Start full role poll sequence
                    if OGRH.Poll.StartRolePoll then
                        OGRH.Poll.StartRolePoll()
                    else
                        print("Error: Poll functionality not loaded")
                    end
                else
                    -- Show role selection menu
                    if OGRH.Poll.menu then
                        OGRH.Poll.menu:ClearAllPoints()
                        OGRH.Poll.menu:SetPoint("TOPLEFT", pollBtn, "BOTTOMLEFT", 0, -2)
                        OGRH.Poll.menu:Show()
                    else
                        print("Error: Poll menu not loaded")
                    end
                end
            end
            UpdatePollButtonText()
        else
            print("Error: Poll functionality not loaded")
        end
    end)

    -- Set initial button text
    UpdatePollButtonText()
    
    -- Add Marks button below Poll
    local marksBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    -- Helper function to get colored mark name - make it available to other modules
    OGRH.GetColoredMarkName = function(markId)
        local markColors = {
            [1] = "ffff00", -- Star (Yellow)
            [2] = "ff8000", -- Circle (Orange)
            [3] = "ff00ff", -- Diamond (Purple)
            [4] = "00ff00", -- Triangle (Green)
            [5] = "ffffff", -- Moon (White)
            [6] = "00ffff", -- Square (Blue)
            [7] = "ff0000", -- Cross (Red)
            [8] = "ffffff", -- Skull (White)
        }
        local markNames = {
            [1] = "Star",
            [2] = "Circle",
            [3] = "Diamond",
            [4] = "Triangle",
            [5] = "Moon",
            [6] = "Square",
            [7] = "Cross",
            [8] = "Skull"
        }
        if markId and markNames[markId] then
            return "|cff" .. markColors[markId] .. markNames[markId] .. "|r"
        end
        return "None"
    end
    -- Create a local reference for use in this file
    local GetColoredMarkName = OGRH.GetColoredMarkName

    marksBtn:SetWidth(80)
    marksBtn:SetHeight(24)
    marksBtn:SetPoint("TOPLEFT", pollBtn, "BOTTOMLEFT", 0, -5)  -- 5 pixels gap below Poll button
    marksBtn:SetText("Marks")
    marksBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    marksBtn:SetScript("OnClick", function()
        local button = arg1 or "LeftButton"
        if button == "LeftButton" then
            -- Announce all marks
            if OGRH.testMode then
                print("|cFFFFFF00OGRH:|r Announcing test raid marks")
            else
                print("OGRH: Announcing raid marks")
            end
            
            -- Collect announcement lines
            local announcementLines = {}
            
            -- First, collect tanks by their marks
            local markGroups = {}
            for _, playerName in ipairs(ROLE_COLUMNS[1].players) do
                local markId = PLAYER_RAID_TARGETS[playerName]
                if markId then
                    if not markGroups[markId] then
                        markGroups[markId] = {
                            tanks = {},
                            healers = {},
                            mark = markId
                        }
                    end
                    table.insert(markGroups[markId].tanks, {
                        name = playerName,
                        class = OGRH.Roles.nameClass[playerName]
                    })
                end
            end
            
            -- Then collect healers and their assignments
            for _, playerName in ipairs(ROLE_COLUMNS[2].players) do
                local assignData = OGRH.GetPlayerAssignment(playerName)
                local tankMarkId = assignData and assignData.type == "icon" and assignData.value
                if tankMarkId and markGroups[tankMarkId] then
                    table.insert(markGroups[tankMarkId].healers, {
                        name = playerName,
                        class = OGRH.Roles.nameClass[playerName]
                    })
                end
            end
            
            -- Sort mark groups by mark ID
            local sortedGroups = {}
            for _, group in pairs(markGroups) do
                table.insert(sortedGroups, group)
            end
            table.sort(sortedGroups, function(a, b) return a.mark < b.mark end)
            
            -- Build announcement lines for each mark group
            for _, group in ipairs(sortedGroups) do
                -- Build tank names list
                local tankNames = {}
                for _, tank in ipairs(group.tanks) do
                    table.insert(tankNames, OGRH.ClassColorHex(tank.class) .. tank.name .. "|r")
                end
                
                -- Format: Tank: Player Healer(s): Player
                local msg = OGRH.Header("Tank: ") .. table.concat(tankNames, ", ") .. " " .. GetColoredMarkName(group.mark)
                
                if table.getn(group.healers) > 0 then
                    local healerList = {}
                    for _, healer in ipairs(group.healers) do
                        table.insert(healerList, OGRH.ClassColorHex(healer.class) .. healer.name .. "|r")
                    end
                    
                    msg = msg .. OGRH.Header("  ->  ") .. OGRH.Role(table.getn(group.healers) == 1 and "Healer: " or "Healers: ")
                    msg = msg .. table.concat(healerList, " ")
                end
                
                table.insert(announcementLines, msg)
            end
            
            -- Use the helper function to send and store announcements
            if OGRH.SendAnnouncement then
                OGRH.SendAnnouncement(announcementLines, OGRH.testMode)
            end
            
        else
            -- Right click: Clear all marks and assignments
            print("OGRH: Clearing all marks and assignments")
            
            -- Clear saved mark assignments
            PLAYER_RAID_TARGETS = {}
            
            -- Only clear raid marks and saved variables if not in test mode
            if not OGRH.testMode then
                -- Clear actual raid marks
                local numRaidMembers = GetNumRaidMembers()
                for i = 1, numRaidMembers do
                    SetRaidTarget("raid" .. i, 0)
                end
                
                -- Clear saved assignments
                if OGRH_SV then
                    OGRH_SV.raidTargets = {}
                    OGRH_SV.playerAssignments = {}
                end
            end
            
            -- Refresh the UI
            RefreshColumnDisplays()
            print("OGRH: All marks and assignments cleared")
        end
    end)
    
    -- Add Assignments button to the right of Marks and below Encounter
    local assignmentsBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    assignmentsBtn:SetWidth(80)
    assignmentsBtn:SetHeight(24)
    assignmentsBtn:SetPoint("LEFT", marksBtn, "RIGHT", 5, 0)
    assignmentsBtn:SetText("Assignments")
    assignmentsBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    assignmentsBtn:SetScript("OnClick", function()
        local button = arg1 or "LeftButton"
        if button == "LeftButton" then
            -- Left-click functionality to be added
            print("|cFFFFFF00OGRH:|r Assignments announce functionality coming soon")
        else
            -- Right-click: Clear all assignments
            print("|cFFFFFF00OGRH:|r Clearing all player assignments")
            
            if not OGRH.testMode then
                -- Clear saved assignments in SavedVariables
                if OGRH_SV then
                    OGRH_SV.playerAssignments = {}
                end
            else
                -- In test mode, still clear the assignments
                OGRH.ClearAllAssignments()
            end
            
            -- Refresh the UI to show cleared assignments
            RefreshColumnDisplays()
            print("|cFFFFFF00OGRH:|r All player assignments cleared")
        end
    end)
    
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    closeBtn:SetWidth(80)
    closeBtn:SetHeight(24)
    closeBtn:SetPoint("TOPRIGHT", -20, -20)
    closeBtn:SetText("Close")
    closeBtn:SetScript("OnClick", function()
        frame:Hide()
    end)

    -- Add Test button and menu
    local testBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    testBtn:SetWidth(80)
    testBtn:SetHeight(24)
    testBtn:SetPoint("TOPLEFT", closeBtn, "BOTTOMLEFT", 0, -5)
    testBtn:SetText("Test")
    
    -- Create test menu
    local testMenu = CreateFrame("Frame", "OGRH_TestMenu", UIParent)
    testMenu:SetWidth(80)
    testMenu:SetHeight(85)
    testMenu:SetFrameStrata("FULLSCREEN_DIALOG")
    testMenu:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        edgeSize = 12,
        insets = {left = 4, right = 4, top = 4, bottom = 4}
    })
    testMenu:SetBackdropColor(0, 0, 0, 0.95)
    testMenu:Hide()

    -- Create test menu buttons
    local lastButton = nil
    local function CreateTestButton(text, size)
        local btn = CreateFrame("Button", nil, testMenu, "UIPanelButtonTemplate")
        btn:SetWidth(70)
        btn:SetHeight(20)
        if text == "15" then
            btn:SetPoint("TOPLEFT", testMenu, "TOPLEFT", 5, -5)
        else
            btn:SetPoint("TOPLEFT", lastButton, "BOTTOMLEFT", 0, -2)
        end
        lastButton = btn
        btn:SetText(text)
        btn:SetScript("OnClick", function()
            OGRH.testMode = true
            testMenu:Hide()
            
            -- Clear current lists
            for i = 1, table.getn(ROLE_COLUMNS) do
                ROLE_COLUMNS[i].players = {}
            end
            
            -- Test data setup with class role distribution
            local classRoles = {
                WARRIOR = {
                    roles = {"TANKS", "MELEE"},
                    weights = {0.4, 0.6}  -- 40% tanks, 60% melee
                },
                PRIEST = {
                    roles = {"HEALERS", "RANGED"},
                    weights = {0.8, 0.2}  -- 80% healers, 20% ranged
                },
                DRUID = {
                    roles = {"TANKS", "HEALERS", "RANGED"},
                    weights = {0.2, 0.5, 0.3}  -- 20% tanks, 50% healers, 30% ranged
                },
                SHAMAN = {
                    roles = {"HEALERS", "MELEE", "RANGED"},
                    weights = {0.5, 0.3, 0.2}  -- 50% healers, 30% melee, 20% ranged
                },
                ROGUE = {
                    roles = {"MELEE"},
                    weights = {1.0}  -- 100% melee
                },
                WARLOCK = {
                    roles = {"RANGED"},
                    weights = {1.0}  -- 100% ranged
                },
                MAGE = {
                    roles = {"RANGED"},
                    weights = {1.0}  -- 100% ranged
                },
                HUNTER = {
                    roles = {"RANGED", "MELEE"},
                    weights = {0.8, 0.2}  -- 80% ranged, 20% melee
                },
                PALADIN = {
                    roles = {"TANKS", "HEALERS", "MELEE"},
                    weights = {0.2, 0.5, 0.3}  -- 20% tanks, 50% healers, 30% melee
                }
            }

            -- Define class list for random selection
            local classList = {
                "WARRIOR", "WARRIOR", "WARRIOR",  -- 15%
                "PRIEST", "PRIEST",               -- 10%
                "DRUID", "DRUID",                -- 10%
                "SHAMAN", "SHAMAN",              -- 10%
                "ROGUE", "ROGUE",                -- 10%
                "WARLOCK", "WARLOCK",            -- 10%
                "MAGE", "MAGE", "MAGE",          -- 15%
                "HUNTER", "HUNTER",              -- 10%
                "PALADIN", "PALADIN"             -- 10%
            }

            local testPlayers = {}
            
            -- Set required numbers based on raid size
            local requiredTanks = 2  -- default for 15
            local requiredHealers = 3 -- default for 15
            if size == 25 then
                requiredTanks = 4
                requiredHealers = 6
            elseif size == 40 then
                requiredTanks = 8
                requiredHealers = 12
            end

            local tankCount = 0
            local healerCount = 0
            local testNames = {}
            local tankCapableClasses = {"WARRIOR", "DRUID", "PALADIN"}
            local healerCapableClasses = {"PRIEST", "DRUID", "SHAMAN", "PALADIN"}

            -- Generate all names and their classes
            for i = 1, size do
                local name = "Test"
                if i < 10 then
                    name = name.."0"..i
                else
                    name = name..i
                end
                
                -- Select class based on position
                local selectedClass
                if i <= requiredTanks then
                    -- Assign tank-capable class
                    local tankClassIndex = math.random(1, table.getn(tankCapableClasses))
                    selectedClass = tankCapableClasses[tankClassIndex]
                elseif i <= (requiredTanks + requiredHealers) then
                    -- Assign healer-capable class
                    local healerClassIndex = math.random(1, table.getn(healerCapableClasses))
                    selectedClass = healerCapableClasses[healerClassIndex]
                else
                    -- Random class for remaining positions
                    local classIndex = math.random(1, table.getn(classList))
                    selectedClass = classList[classIndex]
                end

                -- Store name and class
                OGRH.Roles.nameClass[name] = selectedClass
                table.insert(testNames, {name = name, class = selectedClass})
            end

            -- Assign roles based on position
            for i = 1, table.getn(testNames) do
                local name = testNames[i].name
                local class = testNames[i].class
                local selectedRole
                local roleColumn

                if i <= requiredTanks then
                    selectedRole = "TANKS"
                    roleColumn = 1
                elseif i <= (requiredTanks + requiredHealers) then
                    selectedRole = "HEALERS"
                    roleColumn = 2
                else
                    -- Determine DPS role based on class
                    if class == "WARRIOR" or class == "ROGUE" or class == "PALADIN" or 
                       (class == "SHAMAN" and math.random(1, 10) <= 6) then
                        selectedRole = "MELEE"
                        roleColumn = 3
                    else
                        selectedRole = "RANGED"
                        roleColumn = 4
                    end
                end

                -- Add to appropriate column
                table.insert(ROLE_COLUMNS[roleColumn].players, name)

                -- Save role assignment
                if not OGRH_SV.roles then 
                    OGRH_SV.roles = {} 
                end
                OGRH_SV.roles[name] = selectedRole
            end            -- Removed redundant role distribution code as roles are now assigned during player generation
            
            -- Refresh display
            RefreshColumnDisplays()
            print("|cFFFFFF00OGRH:|r Test mode enabled with " .. size .. " players")
        end)
        return btn
    end

    CreateTestButton("15", 15)
    CreateTestButton("25", 25)
    CreateTestButton("40", 40)

    testBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    testBtn:SetScript("OnClick", function()
        local button = arg1 or "LeftButton"
        if button == "LeftButton" then
            if testMenu:IsVisible() then
                testMenu:Hide()
            else
                testMenu:ClearAllPoints()
                testMenu:SetPoint("TOPRIGHT", testBtn, "BOTTOMRIGHT", 0, -2)
                testMenu:Show()
            end
        else
            -- Right click disables test mode
            if OGRH.testMode then
                OGRH.testMode = false
                if OGRH.rolesFrame and OGRH.rolesFrame.UpdatePlayerLists then
                    OGRH.rolesFrame.UpdatePlayerLists() -- Refresh with real raid data
                end
                print("|cFFFFFF00OGRH:|r Test mode disabled")
            end
        end
    end)
    
    -- Create Role Columns
    local columnStartY = -80
    
    for i, column in ipairs(ROLE_COLUMNS) do
        local columnFrame = CreateFrame("Frame", nil, frame)
        columnFrame:SetWidth(columnWidth)
        columnFrame:SetHeight(columnHeight)
        columnFrame:SetPoint("TOPLEFT", 20 + ((i-1) * columnWidth), columnStartY)
        
        local headerText = columnFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        headerText:SetPoint("TOP", 0, -8)  -- Added 5 pixels of padding at the top
        headerText:SetText(column.name)
        
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
    local razorgorePanel, firemawPanel, cthunPanel
    
    -- Create BWL panels
    if OGRH.BWL then
        razorgorePanel = OGRH.BWL.CreateRazorgorePanel(frame, encounterBtn)
        firemawPanel = OGRH.BWL.CreateFiremawPanel(frame, encounterBtn)
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
        if firemawPanel then firemawPanel:Hide() end
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

    OGRH.ShowFiremawPanel = function()
        HideAllPanels()
        if firemawPanel then
            firemawPanel:Show()
        else
            print("|cFFFFFF00OGRH:|r Error: Firemaw panel could not be created!")
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