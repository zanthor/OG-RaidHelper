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
        -- First, collect tanks by their marks
        local nearTanks = {}
        local skullTank, crossTank
        local mainTank = nil
        
        -- Check for OGRH
        if not OGRH then return end
        
        local tankCount = OGRH.GetRoleCount("TANKS")
        
        OGRH.ForEachRolePlayer("TANKS", function(playerName)
            local markId = OGRH_SV and OGRH_SV.raidTargets and OGRH_SV.raidTargets[playerName]
            
            if markId then
                if markId == 8 then  -- Skull
                    skullTank = {
                        name = playerName,
                        class = OGRH.Roles.nameClass[playerName],
                        mark = markId,
                        healers = {}
                    }
                    mainTank = skullTank
                    table.insert(nearTanks, skullTank)
                elseif markId == 7 then  -- Cross
                    crossTank = {
                        name = playerName,
                        class = OGRH.Roles.nameClass[playerName],
                        mark = markId,
                        healers = {}
                    }
                    table.insert(nearTanks, crossTank)
                    end
            end
        end)

        -- Find Far Side tanks (Square and Moon)
        local farTanks = {}
        local squareTank, moonTank
        OGRH.ForEachRolePlayer("TANKS", function(playerName)
            local markId = OGRH_SV and OGRH_SV.raidTargets and OGRH_SV.raidTargets[playerName]
            if markId then
                if markId == 6 then  -- Square
                    squareTank = {
                        name = playerName,
                        class = OGRH.Roles.nameClass[playerName],
                        mark = markId,
                        healers = {}
                    }
                    table.insert(farTanks, squareTank)
                elseif markId == 5 then  -- Moon
                    moonTank = {
                        name = playerName,
                        class = OGRH.Roles.nameClass[playerName],
                        mark = markId,
                        healers = {}
                    }
                    table.insert(farTanks, moonTank)
                end
            end
        end)

        -- Get healers list from roles frame
        
        local healerCount = OGRH.GetRoleCount("HEALERS")
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00OGRH Debug:|r Healer count: " .. healerCount)

        -- Collect healers assigned to tanks
        OGRH.ForEachRolePlayer("HEALERS", function(playerName)
            local tankMarkId = OGRH_SV.healerTankAssigns and OGRH_SV.healerTankAssigns[playerName]
            if tankMarkId then
                local targetTank
                if tankMarkId == 8 and skullTank then  -- Skull
                    targetTank = skullTank
                elseif tankMarkId == 7 and crossTank then  -- Cross
                    targetTank = crossTank
                elseif tankMarkId == 6 and squareTank then  -- Square
                    targetTank = squareTank
                elseif tankMarkId == 5 and moonTank then  -- Moon
                    targetTank = moonTank
                end
                
                if targetTank then
                    table.insert(targetTank.healers, {
                        name = playerName,
                        class = OGRH.Roles.nameClass[playerName]
                    })
                end
            end
        end)
        
        -- Begin announcements in order: Orb Control -> Main Tank -> Near Side -> Far Side
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00OGRH Debug:|r Starting announcements")

        -- 1. Announce orb controller if assigned
        local orbController
        for _, column in ipairs(ROLE_COLUMNS) do
            DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00OGRH Debug:|r Checking column for orb controller")
            for _, playerName in ipairs(column.players) do
                local markId = OGRH_SV.raidTargets and OGRH_SV.raidTargets[playerName]
                if markId == 2 then -- Circle (Orange)
                    orbController = {
                        name = playerName,
                        class = OGRH.Roles.nameClass[playerName]
                    }
                    DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00OGRH Debug:|r Found orb controller: " .. playerName)
                    break
                end
            end
            if orbController then break end
        end

        if orbController then
            local msg = "|cff00ff00[ORB]:|r " .. OGRH.ClassColorHex(orbController.class) .. orbController.name .. "|r"
            if OGRH.testMode then
                DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00OGRH:|r " .. msg)
            else
                SendChatMessage(msg, "RAID_WARNING")
            end
        end

        -- 2. Announce the Main Tank
        if mainTank then
            local msg = "|cff00ff00[Main Tank]:|r " .. OGRH.ClassColorHex(mainTank.class) .. mainTank.name .. "|r"
            if mainTank.healers and table.getn(mainTank.healers) > 0 then
                msg = msg .. " - |cff00ff00Healers:|r "
                local healerStrings = {}
                for _, healer in ipairs(mainTank.healers) do
                    table.insert(healerStrings, OGRH.ClassColorHex(healer.class) .. healer.name .. "|r")
                end
                msg = msg .. table.concat(healerStrings, " ")
            end
            if OGRH.testMode then
                DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00OGRH:|r " .. msg)
            else
                SendChatMessage(msg, "RAID_WARNING")
            end
        end

        -- 3. Announce Near Side assignments
        if table.getn(nearTanks) > 0 then
            local msg = "|cff00ff00[Near]:|r "
            local tankStrings = {}
            for _, tank in ipairs(nearTanks) do
                table.insert(tankStrings, OGRH.ClassColorHex(tank.class) .. tank.name .. "|r")
            end
            msg = msg .. table.concat(tankStrings, ", ")
            
            -- Collect all healers for near side
            local allHealers = {}
            for _, tank in ipairs(nearTanks) do
                if tank.healers and table.getn(tank.healers) > 0 then
                    for _, healer in ipairs(tank.healers) do
                        table.insert(allHealers, OGRH.ClassColorHex(healer.class) .. healer.name .. "|r")
                    end
                end
            end
            if table.getn(allHealers) > 0 then
                msg = msg .. " - |cff00ff00Healers:|r " .. table.concat(allHealers, " ")
            end
            
            if OGRH.testMode then
                DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00OGRH:|r " .. msg)
            else
                SendChatMessage(msg, "RAID_WARNING")
            end
        end

        -- 4. Announce Far Side assignments
        if table.getn(farTanks) > 0 then
            local msg = "|cff00ff00[Far]:|r "
            local tankStrings = {}
            for _, tank in ipairs(farTanks) do
                table.insert(tankStrings, OGRH.ClassColorHex(tank.class) .. tank.name .. "|r")
            end
            msg = msg .. table.concat(tankStrings, ", ")
            
            -- Collect all healers for far side
            local allHealers = {}
            for _, tank in ipairs(farTanks) do
                if tank.healers and table.getn(tank.healers) > 0 then
                    for _, healer in ipairs(tank.healers) do
                        table.insert(allHealers, OGRH.ClassColorHex(healer.class) .. healer.name .. "|r")
                    end
                end
            end
            if table.getn(allHealers) > 0 then
                msg = msg .. " - |cff00ff00Healers:|r " .. table.concat(allHealers, " ")
            end
            
            if OGRH.testMode then
                DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00OGRH:|r " .. msg)
            else
                SendChatMessage(msg, "RAID_WARNING")
            end
            if OGRH.testMode then
                DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00OGRH:|r " .. farMsg)
            else
                SendChatMessage(farMsg, "RAID_WARNING")
            end
        end
    end)

    return panel
end

-- Create Vael Trash UI elements
local function CreateVaelTrashPanel(parent, encounterBtn)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetWidth(384)  -- Width of two columns (190 * 2) + gap (4)
    panel:SetHeight(60)  -- Same height as Razorgore panel
    panel:SetPoint("TOPLEFT", parent, "TOPLEFT", 210, -20)  -- Same position as Razorgore panel
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
    leftCol:SetWidth(85)
    leftCol:SetHeight(52)
    leftCol:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -4)

    local rightCol = CreateFrame("Frame", nil, panel)
    rightCol:SetWidth(85)
    rightCol:SetHeight(52)
    rightCol:SetPoint("TOPLEFT", leftCol, "TOPRIGHT", 24, 0)

    local function CreateIconLabel(parent, iconId1, iconId2, iconId3, text, yOffset)
        local container = CreateFrame("Frame", nil, parent)
        container:SetWidth(120)
        container:SetHeight(30)
        container:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yOffset)

        -- Icons
        if iconId1 then
            local icon1 = container:CreateTexture(nil, "ARTWORK")
            icon1:SetWidth(16)
            icon1:SetHeight(16)
            icon1:SetPoint("LEFT", container, "LEFT", 0, 0)
            SetRaidTargetIconTexture(icon1, iconId1)
        end

        if iconId2 then
            local icon2 = container:CreateTexture(nil, "ARTWORK")
            icon2:SetWidth(16)
            icon2:SetHeight(16)
            icon2:SetPoint("LEFT", container, "LEFT", 20, 0)
            SetRaidTargetIconTexture(icon2, iconId2)
        end

        if iconId3 then
            local icon3 = container:CreateTexture(nil, "ARTWORK")
            icon3:SetWidth(16)
            icon3:SetHeight(16)
            icon3:SetPoint("LEFT", container, "LEFT", 40, 0)
            SetRaidTargetIconTexture(icon3, iconId3)
        end

        local label = container:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        label:SetPoint("LEFT", container, "LEFT", (iconId3 and 60) or (iconId2 and 40) or 20, 0)
        label:SetText(text)
    end

    -- Left column - Tank assignments
    CreateIconLabel(leftCol, 8, 7, 4, "Tank", 0)  -- Skull, Cross, Triangle
    CreateIconLabel(leftCol, 6, 5, nil, "Sleep", -20) -- Square, Moon

    -- Right column - Kiter assignment
    CreateIconLabel(rightCol, 2, nil, nil, "Kite", 0)  -- Circle

    -- Add Announce button in same position as Razorgore panel
    local announceBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    announceBtn:SetWidth(80)
    announceBtn:SetHeight(24)
    announceBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -4)
    announceBtn:SetText("Announce")
    announceBtn:SetScript("OnClick", function()
        -- Get ROLE_COLUMNS from parent frame
        local ROLE_COLUMNS = parent.ROLE_COLUMNS
        if not ROLE_COLUMNS then return end

        -- Find tanks for each mark (Skull, Cross, Triangle)
        local tankMarks = {8, 7, 4}  -- Skull, Cross, Triangle
        for _, markId in ipairs(tankMarks) do
            local tankName
            local healers = {}

            -- Find tank with this mark
            for _, playerName in ipairs(ROLE_COLUMNS[1].players) do
                if OGRH_SV.raidTargets and OGRH_SV.raidTargets[playerName] == markId then
                    tankName = playerName
                    break
                end
            end

            -- Find healers assigned to this tank
            if tankName then
                for _, playerName in ipairs(ROLE_COLUMNS[2].players) do
                    if OGRH_SV.healerTankAssigns and OGRH_SV.healerTankAssigns[playerName] == markId then
                        table.insert(healers, OGRH.ClassColorHex(OGRH.Roles.nameClass[playerName]) .. playerName .. "|r")
                    end
                end

                -- Announce tank and healers
                local msg = "Tank - " .. OGRH.GetColoredMarkName(markId) .. ": " .. 
                          OGRH.ClassColorHex(OGRH.Roles.nameClass[tankName]) .. tankName .. "|r"
                if table.getn(healers) > 0 then
                    msg = msg .. " - Healers: " .. table.concat(healers, ", ")
                end
                if OGRH.testMode then
                    DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00OGRH:|r " .. msg)
                else
                    SendChatMessage(msg, "RAID_WARNING")
                end
            end
        end

        -- Find and announce sleepers (Square, Moon)
        local sleepMarks = {6, 5}  -- Square, Moon
        for _, markId in ipairs(sleepMarks) do
            for _, column in ipairs(ROLE_COLUMNS) do
                for _, playerName in ipairs(column.players) do
                    if OGRH_SV.raidTargets and OGRH_SV.raidTargets[playerName] == markId then
                        local msg = OGRH.ClassColorHex(OGRH.Roles.nameClass[playerName]) .. playerName .. "|r sleeps " .. 
                                      OGRH.GetColoredMarkName(markId)
                        if OGRH.testMode then
                            DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00OGRH:|r " .. msg)
                        else
                            SendChatMessage(msg, "RAID_WARNING")
                        end
                        break
                    end
                end
            end
        end

        -- Find and announce kiter (Circle)
        for _, column in ipairs(ROLE_COLUMNS) do
            for _, playerName in ipairs(column.players) do
                if OGRH_SV.raidTargets and OGRH_SV.raidTargets[playerName] == 2 then -- Circle
                    local msg = OGRH.ClassColorHex(OGRH.Roles.nameClass[playerName]) .. playerName .. "|r kites " .. 
                                  OGRH.GetColoredMarkName(2)
                    if OGRH.testMode then
                        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00OGRH:|r " .. msg)
                    else
                        SendChatMessage(msg, "RAID_WARNING")
                    end
                    break
                end
            end
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
    CreateRazorgorePanel = CreateRazorgorePanel,
    CreateVaelTrashPanel = CreateVaelTrashPanel
}