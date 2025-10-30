-- OG-RaidHelper BWL Encounters
-- Author: Will + ChatGPT
-- Version: 1.14.0

local _G = getfenv(0)
local OGRH = _G.OGRH

-- Get ROLE_COLUMNS from the parent frame when the panel is created
local ROLE_COLUMNS

-- Function to set raid target icon texture (local helper)
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

-- Create Razorgore UI elements
local function CreateRazorgorePanel(parent, encounterBtn)
    -- Get ROLE_COLUMNS from the parent frame
    ROLE_COLUMNS = parent.ROLE_COLUMNS
    
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetWidth(384)  -- Width of two columns (190 * 2) + gap (4)
    panel:SetHeight(60)  -- Reduced height
    panel:SetPoint("TOPLEFT", parent, "TOPLEFT", 210, -20)  -- Align with Healers column (20 + 190)
    panel:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = {left = 4, right = 4, top = 4, bottom = 4}
    })
    panel:SetBackdropColor(0, 0, 0, 0.5)
    panel:Hide()

    -- Create two columns
    local leftCol = CreateFrame("Frame", nil, panel)
    leftCol:SetWidth(120)
    leftCol:SetHeight(52)
    leftCol:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -4)

    local rightCol = CreateFrame("Frame", nil, panel)
    rightCol:SetWidth(120)
    rightCol:SetHeight(52)
    rightCol:SetPoint("TOPLEFT", leftCol, "TOPRIGHT", 4, 0)

    local function CreateIconLabel(parent, iconId1, iconId2, text, yOffset)
        local container = CreateFrame("Frame", nil, parent)
        container:SetWidth(120)
        container:SetHeight(30)
        container:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yOffset)

        -- First icon if provided
        if iconId1 then
            local icon1 = container:CreateTexture(nil, "ARTWORK")
            icon1:SetWidth(16)
            icon1:SetHeight(16)
            icon1:SetPoint("LEFT", container, "LEFT", 0, 0)
            SetRaidTargetIconTexture(icon1, iconId1)
        end

        -- Second icon if provided
        if iconId2 then
            local icon2 = container:CreateTexture(nil, "ARTWORK")
            icon2:SetWidth(16)
            icon2:SetHeight(16)
            icon2:SetPoint("LEFT", container, "LEFT", 20, 0)
            SetRaidTargetIconTexture(icon2, iconId2)
        end

        local label = container:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        label:SetPoint("LEFT", container, "LEFT", iconId2 and 40 or 20, 0)
        label:SetText(text)
    end

    -- Left column - Near/Far assignments
    CreateIconLabel(leftCol, 8, 7, "Near Side", 0)    -- Skull and Cross
    CreateIconLabel(leftCol, 3, 2, "Far Side", -20)   -- Diamond and Circle

    -- Right column - Orb/Main Tank assignments
    CreateIconLabel(rightCol, 1, nil, "Orb Control", 0)  -- Star
    CreateIconLabel(rightCol, 8, nil, "Main Tank", -20)  -- Skull

    -- Add Sleep label below Main Tank (no column, position to the right)
    local sleepContainer = CreateFrame("Frame", nil, panel)
    sleepContainer:SetWidth(120)
    sleepContainer:SetHeight(30)
    sleepContainer:SetPoint("TOPLEFT", rightCol, "TOPRIGHT", 4, -20)
    
    local sleepIcon1 = sleepContainer:CreateTexture(nil, "ARTWORK")
    sleepIcon1:SetWidth(16)
    sleepIcon1:SetHeight(16)
    sleepIcon1:SetPoint("LEFT", sleepContainer, "LEFT", 0, 0)
    SetRaidTargetIconTexture(sleepIcon1, 5)  -- Moon
    
    local sleepIcon2 = sleepContainer:CreateTexture(nil, "ARTWORK")
    sleepIcon2:SetWidth(16)
    sleepIcon2:SetHeight(16)
    sleepIcon2:SetPoint("LEFT", sleepContainer, "LEFT", 20, 0)
    SetRaidTargetIconTexture(sleepIcon2, 6)  -- Square
    
    local sleepLabel = sleepContainer:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    sleepLabel:SetPoint("LEFT", sleepContainer, "LEFT", 40, 0)
    sleepLabel:SetText("Sleep")

    -- Add Announce button
    local announceBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    announceBtn:SetWidth(80)
    announceBtn:SetHeight(24)
    announceBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -4)
    announceBtn:SetText("Announce")
    announceBtn:SetScript("OnClick", function()
        -- Check for OGRH
        if not OGRH then return end
        
        -- Collect announcement lines
        local announcementLines = {}
        
        -- Helper to get player data by mark
        local function FindPlayersByMarks(markIds)
            local players = {}
            for _, column in ipairs(ROLE_COLUMNS) do
                for _, playerName in ipairs(column.players) do
                    local markId = OGRH_SV and OGRH_SV.raidTargets and OGRH_SV.raidTargets[playerName]
                    if markId then
                        for _, targetMark in ipairs(markIds) do
                            if markId == targetMark then
                                table.insert(players, {
                                    name = playerName,
                                    class = OGRH.Roles.nameClass[playerName],
                                    mark = markId
                                })
                            end
                        end
                    end
                end
            end
            return players
        end
        
        -- Helper to get healers assigned to specific marks
        local function GetHealersForMarks(markIds)
            local healers = {}
            for _, column in ipairs(ROLE_COLUMNS) do
                for _, playerName in ipairs(column.players) do
                    local assignData = OGRH.GetPlayerAssignment(playerName)
                    if assignData and assignData.type == "icon" then
                        for _, targetMark in ipairs(markIds) do
                            if assignData.value == targetMark then
                                table.insert(healers, {
                                    name = playerName,
                                    class = OGRH.Roles.nameClass[playerName],
                                    mark = assignData.value
                                })
                            end
                        end
                    end
                end
            end
            return healers
        end
        
        -- 1. MT: Player with Skull mark / Orb: Player with Star assignment
        local mtPlayers = FindPlayersByMarks({8}) -- Skull mark
        local orbAssigned = {}
        
        -- Check for players assigned Star (for orb control) - assignment only, not mark
        for _, column in ipairs(ROLE_COLUMNS) do
            for _, playerName in ipairs(column.players) do
                local assignData = OGRH.GetPlayerAssignment(playerName)
                if assignData and assignData.type == "icon" and assignData.value == 1 then
                    table.insert(orbAssigned, {
                        name = playerName,
                        class = OGRH.Roles.nameClass[playerName]
                    })
                end
            end
        end
        
        if table.getn(mtPlayers) > 0 or table.getn(orbAssigned) > 0 then
            local parts = {}
            
            if table.getn(mtPlayers) > 0 then
                table.insert(parts, OGRH.Header("MT: ") .. OGRH.ClassColorHex(mtPlayers[1].class) .. mtPlayers[1].name .. "|r")
            end
            
            if table.getn(orbAssigned) > 0 then
                local orbControllers = {}
                for _, orbPlayer in ipairs(orbAssigned) do
                    table.insert(orbControllers, OGRH.ClassColorHex(orbPlayer.class) .. orbPlayer.name .. "|r")
                end
                table.insert(parts, OGRH.Header("Orb: ") .. table.concat(orbControllers, ", "))
            end
            
            if table.getn(parts) > 0 then
                table.insert(announcementLines, table.concat(parts, " - "))
            end
        end
        
        -- 2. Near Side: Players with Skull and Cross
        local nearPlayers = FindPlayersByMarks({8, 7}) -- Skull and Cross
        local nearHealers = GetHealersForMarks({8, 7})
        
        if table.getn(nearPlayers) > 0 then
            local nearParts = {}
            for _, player in ipairs(nearPlayers) do
                local markName = OGRH.GetColoredMarkName(player.mark)
                table.insert(nearParts, OGRH.ClassColorHex(player.class) .. player.name .. "|r " .. markName)
            end
            
            local msg = OGRH.Header("Near Side: ") .. table.concat(nearParts, " / ")
            
            if table.getn(nearHealers) > 0 then
                local healerParts = {}
                for _, healer in ipairs(nearHealers) do
                    local markName = OGRH.GetColoredMarkName(healer.mark)
                    table.insert(healerParts, OGRH.ClassColorHex(healer.class) .. healer.name .. "|r " .. markName)
                end
                msg = msg .. OGRH.Header("  ->  Healers: ") .. table.concat(healerParts, ", ")
            end
            
            table.insert(announcementLines, msg)
        end
        
        -- 3. Far Side: Players with Circle and Diamond
        local farPlayers = FindPlayersByMarks({2, 3}) -- Circle and Diamond
        local farHealers = GetHealersForMarks({2, 3})
        
        if table.getn(farPlayers) > 0 then
            local farParts = {}
            for _, player in ipairs(farPlayers) do
                local markName = OGRH.GetColoredMarkName(player.mark)
                table.insert(farParts, OGRH.ClassColorHex(player.class) .. player.name .. "|r " .. markName)
            end
            
            local msg = OGRH.Header("Far Side: ") .. table.concat(farParts, " / ")
            
            if table.getn(farHealers) > 0 then
                local healerParts = {}
                for _, healer in ipairs(farHealers) do
                    local markName = OGRH.GetColoredMarkName(healer.mark)
                    table.insert(healerParts, OGRH.ClassColorHex(healer.class) .. healer.name .. "|r " .. markName)
                end
                msg = msg .. OGRH.Header("  ->  Healers: ") .. table.concat(healerParts, ", ")
            end
            
            table.insert(announcementLines, msg)
        end
        
        -- 4. Trash after Vael section
        local moonSleepers = {}
        local squareSleepers = {}
        local starKiters = FindPlayersByMarks({1}) -- Star mark for kiting
        
        -- Find players with Moon (5) and Square (6) assignments for sleeping
        for _, column in ipairs(ROLE_COLUMNS) do
            for _, playerName in ipairs(column.players) do
                local assignData = OGRH.GetPlayerAssignment(playerName)
                if assignData and assignData.type == "icon" then
                    if assignData.value == 5 then  -- Moon assignment
                        table.insert(moonSleepers, {
                            name = playerName,
                            class = OGRH.Roles.nameClass[playerName]
                        })
                    elseif assignData.value == 6 then  -- Square assignment
                        table.insert(squareSleepers, {
                            name = playerName,
                            class = OGRH.Roles.nameClass[playerName]
                        })
                    end
                end
            end
        end
        
        if table.getn(moonSleepers) > 0 or table.getn(squareSleepers) > 0 or table.getn(starKiters) > 0 then
            table.insert(announcementLines, OGRH.Header("Trash after Vael:"))
            
            if table.getn(moonSleepers) > 0 then
                local msg = OGRH.ClassColorHex(moonSleepers[1].class) .. moonSleepers[1].name .. "|r sleeps " .. OGRH.GetColoredMarkName(5)
                table.insert(announcementLines, msg)
            end
            
            if table.getn(squareSleepers) > 0 then
                local msg = OGRH.ClassColorHex(squareSleepers[1].class) .. squareSleepers[1].name .. "|r sleeps " .. OGRH.GetColoredMarkName(6)
                table.insert(announcementLines, msg)
            end
            
            if table.getn(starKiters) > 0 then
                local msg = OGRH.ClassColorHex(starKiters[1].class) .. starKiters[1].name .. "|r kites captain"
                table.insert(announcementLines, msg)
            end
        end
        
        -- Use the helper function to send and store announcements
        if OGRH.SendAnnouncement then
            OGRH.SendAnnouncement(announcementLines, OGRH.testMode)
        end
    end)

    return panel
end

-- Initialize immediately
if not OGRH then
    print("Error: OGRH_E_BWL requires OGRH_Core to be loaded first!")
    return
end

-- Add our functions to the OGRH namespace
OGRH.BWL = {
    CreateRazorgorePanel = CreateRazorgorePanel
}