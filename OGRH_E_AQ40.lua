local _G = getfenv(0)
local OGRH = _G.OGRH

-- Get ROLE_COLUMNS from the parent frame when the panel is created
local ROLE_COLUMNS

-- Global table to track raid target assignments
local PLAYER_RAID_TARGETS = {}

-- Constants for zone assignments
local ZONE_MARKS = {
    [1] = 8,  -- Zone 1: Skull
    [2] = 7,  -- Zone 2: Cross (X)
    [3] = 6,  -- Zone 3: Square
    [4] = 5,  -- Zone 4: Moon
    [5] = 4,  -- Zone 5: Triangle
    [6] = 3,  -- Zone 6: Diamond
    [7] = 2,  -- Zone 7: Circle
    [8] = 1   -- Zone 8: Star
}

-- Assignment order for better coverage (1,4,8,5,2,6,7,3)
local ZONE_ORDER = {1, 4, 8, 5, 2, 6, 7, 3}

-- Linear order for announcements
local ANNOUNCE_ORDER = {1, 2, 3, 4, 5, 6, 7, 8}

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

-- Create C'Thun UI elements
local function CreateCThunPanel(parent, encounterBtn)
    -- Get ROLE_COLUMNS from the parent frame
    ROLE_COLUMNS = parent.ROLE_COLUMNS
    
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetWidth(384)  -- Width of two columns (190 * 2) + gap (4)
    panel:SetHeight(60)  -- Same height as other panels
    panel:SetPoint("TOPLEFT", parent, "TOPLEFT", 210, -20)
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

    -- Create main info area
    local infoFrame = CreateFrame("Frame", nil, panel)
    infoFrame:SetWidth(280)
    infoFrame:SetHeight(52)
    infoFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -4)

    -- Helper function to create icon labels
    local function CreateIconLabel(parent, iconId1, iconId2, text, yOffset)
        local container = CreateFrame("Frame", nil, parent)
        container:SetWidth(280)
        container:SetHeight(20)
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

    -- Create labels
    CreateIconLabel(infoFrame, 8, 1, "Tanks: Zone 1 & 8", 0)  -- Skull and Star
    CreateIconLabel(infoFrame, nil, nil, "Melee: Auto-assigned by zone", -20)

    -- Add Announce button
    local announceBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    announceBtn:SetWidth(80)
    announceBtn:SetHeight(24)
    announceBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -4)
    announceBtn:SetText("Announce")
    announceBtn:SetScript("OnClick", function()
        -- Initialize zone assignments
        local zoneAssignments = {}
        for i = 1, 8 do
            zoneAssignments[i] = {
                tanks = {},
                melee = {},
                healers = {},
                ranged = {},
                mark = ZONE_MARKS[i]
            }
        end

        -- Find and assign tanks to zones 1 and 8 first
        local assignedTanks = {}
        -- First, look for tanks already marked with Skull and Diamond
        for _, playerName in ipairs(ROLE_COLUMNS[1].players) do
            local markId = OGRH_SV.raidTargets and OGRH_SV.raidTargets[playerName]
            if markId == 8 and table.getn(zoneAssignments[1].tanks) == 0 then -- Skull tank to Zone 1
                table.insert(zoneAssignments[1].tanks, playerName)
                assignedTanks[playerName] = true
            elseif markId == 1 and table.getn(zoneAssignments[8].tanks) == 0 then -- Star tank to Zone 8
                table.insert(zoneAssignments[8].tanks, playerName)
                assignedTanks[playerName] = true
            end
        end

        -- If we still need tanks, assign from unmarked tanks, prioritizing highest HP tanks
        local availableTanks = {}
        for _, playerName in ipairs(ROLE_COLUMNS[1].players) do
            if not assignedTanks[playerName] then
                local health = GetPlayerMaxHealth(playerName)
                table.insert(availableTanks, {name = playerName, health = health})
            end
        end
        -- Sort tanks by HP descending
        table.sort(availableTanks, function(a, b) return a.health > b.health end)

        -- Assign remaining tanks by HP
        for _, tank in ipairs(availableTanks) do
            if table.getn(zoneAssignments[1].tanks) == 0 then
                table.insert(zoneAssignments[1].tanks, tank.name)
                assignedTanks[tank.name] = true
            elseif table.getn(zoneAssignments[8].tanks) == 0 then
                table.insert(zoneAssignments[8].tanks, tank.name)
                assignedTanks[tank.name] = true
            end
        end

        -- Assign remaining melee to zones in order
        local currentZoneIndex = 1
        for _, playerName in ipairs(ROLE_COLUMNS[3].players) do
            while currentZoneIndex <= table.getn(ZONE_ORDER) do
                local zoneNum = ZONE_ORDER[currentZoneIndex]
                if table.getn(zoneAssignments[zoneNum].melee) == 0 then
                    table.insert(zoneAssignments[zoneNum].melee, playerName)
                    -- Set raid target
                    OGRH_SV.raidTargets[playerName] = ZONE_MARKS[zoneNum]
                    break
                end
                currentZoneIndex = currentZoneIndex + 1
            end
        end

        -- Function to get player max health
        local function GetPlayerMaxHealth(playerName)
            local maxHealth = 0
            local numRaidMembers = GetNumRaidMembers()
            for i = 1, numRaidMembers do
                local name, _, _, _, _, _, _, _, _, _, _ = GetRaidRosterInfo(i)
                if name == playerName then
                    local unit = "raid" .. i
                    maxHealth = UnitHealthMax(unit)
                    break
                end
            end
            return maxHealth
        end

        -- Assign any remaining melee to zones with highest HP melee
        local highestHPZones = {}
        for zoneNum, zoneData in pairs(zoneAssignments) do
            if table.getn(zoneData.melee) > 0 then
                local maxHealth = 0
                for _, playerName in ipairs(zoneData.melee) do
                    local health = GetPlayerMaxHealth(playerName)
                    if health > maxHealth then maxHealth = health end
                end
                table.insert(highestHPZones, {zone = zoneNum, hp = maxHealth})
            end
        end
        table.sort(highestHPZones, function(a, b) return a.hp > b.hp end)

        -- Distribute remaining melee
        for _, playerName in ipairs(ROLE_COLUMNS[3].players) do
            local assigned = false
            for zoneNum = 1, 8 do
                local zoneData = zoneAssignments[zoneNum]
                for _, existingPlayer in ipairs(zoneData.melee) do
                    if existingPlayer == playerName then
                        assigned = true
                        break
                    end
                end
                if assigned then break end
            end
            
            if not assigned and table.getn(highestHPZones) > 0 then
                local targetZone = highestHPZones[1].zone
                table.insert(zoneAssignments[targetZone].melee, playerName)
            end
        end

        -- Distribute healers using ZONE_ORDER
        local healerIndex = 1
        local healers = ROLE_COLUMNS[2].players
        -- First pass: assign to zones with tanks or melee
        for _, zoneNum in ipairs(ZONE_ORDER) do
            if table.getn(zoneAssignments[zoneNum].tanks) > 0 or table.getn(zoneAssignments[zoneNum].melee) > 0 then
                if healerIndex <= table.getn(healers) then
                    table.insert(zoneAssignments[zoneNum].healers, healers[healerIndex])
                    healerIndex = healerIndex + 1
                end
            end
        end
        -- Second pass: distribute remaining healers
        for _, zoneNum in ipairs(ZONE_ORDER) do
            if healerIndex <= table.getn(healers) and table.getn(zoneAssignments[zoneNum].healers) == 0 then
                table.insert(zoneAssignments[zoneNum].healers, healers[healerIndex])
                healerIndex = healerIndex + 1
            end
        end

        -- Organize ranged and druids by party
        local partyGroups = {}
        local unassignedRanged = {}
        
        -- First, identify druids and their party members
        for _, playerName in ipairs(ROLE_COLUMNS[4].players) do
            local partyNum = 0
            local numRaidMembers = GetNumRaidMembers()
            for i = 1, numRaidMembers do
                local name, _, subgroup = GetRaidRosterInfo(i)
                if name == playerName then
                    partyNum = subgroup
                    break
                end
            end
            
            if not partyGroups[partyNum] then
                partyGroups[partyNum] = {
                    druid = nil,
                    members = {}
                }
            end
            
            if OGRH.Roles.nameClass[playerName] == "DRUID" then
                partyGroups[partyNum].druid = playerName
            else
                table.insert(partyGroups[partyNum].members, playerName)
            end
        end
        
        -- Identify parties without druids
        for _, playerName in ipairs(ROLE_COLUMNS[4].players) do
            local partyNum = 0
            local numRaidMembers = GetNumRaidMembers()
            for i = 1, numRaidMembers do
                local name, _, subgroup = GetRaidRosterInfo(i)
                if name == playerName then
                    partyNum = subgroup
                    break
                end
            end
            
            if not partyGroups[partyNum] or not partyGroups[partyNum].druid then
                table.insert(unassignedRanged, playerName)
            end
        end

        -- Helper function to find adjacent zones
        local function getAdjacentZones(zoneNum)
            local adjacentMap = {
                [1] = {2, 8},
                [2] = {1, 3},
                [3] = {2, 4},
                [4] = {3, 5},
                [5] = {4, 6},
                [6] = {5, 7},
                [7] = {6, 8},
                [8] = {7, 1}
            }
            return adjacentMap[zoneNum] or {}
        end

        -- First, assign druid parties to adjacent zones
        for _, party in pairs(partyGroups) do
            if party.druid then
                -- Find a zone near the middle of the circle for the druid
                local bestZone = nil
                local leastOccupied = 999
                -- Prefer zones 2-7 for druids to ensure party members can be adjacent
                for _, zoneNum in ipairs({2,3,4,5,6,7}) do
                    local totalInZone = table.getn(zoneAssignments[zoneNum].ranged)
                    if totalInZone < leastOccupied then
                        leastOccupied = totalInZone
                        bestZone = zoneNum
                    end
                end
                
                if bestZone then
                    -- Place druid
                    table.insert(zoneAssignments[bestZone].ranged, party.druid)
                    
                    -- Get truly adjacent zones using our adjacency map
                    local adjacent = getAdjacentZones(bestZone)
                    -- Add zones adjacent to those zones for wider coverage
                    local nearbyZones = {}
                    for _, adj in ipairs(adjacent) do
                        table.insert(nearbyZones, adj)
                        for _, nextAdj in ipairs(getAdjacentZones(adj)) do
                            if nextAdj ~= bestZone then
                                local alreadyIn = false
                                for _, existing in ipairs(nearbyZones) do
                                    if existing == nextAdj then
                                        alreadyIn = true
                                        break
                                    end
                                end
                                if not alreadyIn then
                                    table.insert(nearbyZones, nextAdj)
                                end
                            end
                        end
                    end
                    
                    -- Place party members in nearby zones, prioritizing truly adjacent zones first
                    for _, playerName in ipairs(party.members) do
                        local placed = false
                        -- Try adjacent zones first
                        for _, adjZone in ipairs(adjacent) do
                            if table.getn(zoneAssignments[adjZone].ranged) < 2 then
                                table.insert(zoneAssignments[adjZone].ranged, playerName)
                                placed = true
                                break
                            end
                        end
                        -- If not placed, try nearby zones
                        if not placed then
                            for _, nearZone in ipairs(nearbyZones) do
                                if table.getn(zoneAssignments[nearZone].ranged) < 2 then
                                    table.insert(zoneAssignments[nearZone].ranged, playerName)
                                    placed = true
                                    break
                                end
                            end
                        end
                        -- If still not placed, find next best spot following ZONE_ORDER
                        if not placed then
                            for _, zoneNum in ipairs(ZONE_ORDER) do
                                if table.getn(zoneAssignments[zoneNum].ranged) < 2 then
                                    table.insert(zoneAssignments[zoneNum].ranged, playerName)
                                    break
                                end
                            end
                        end
                    end
                end
            end
        end

        -- Distribute remaining ranged following ZONE_ORDER strictly
        for _, playerName in ipairs(unassignedRanged) do
            local placed = false
            
            -- First pass: try to place in ZONE_ORDER with limit of 2 per zone
            for _, zoneNum in ipairs(ZONE_ORDER) do
                if table.getn(zoneAssignments[zoneNum].ranged) < 2 then
                    table.insert(zoneAssignments[zoneNum].ranged, playerName)
                    placed = true
                    break
                end
            end
            
            -- If not placed, do another pass allowing up to 3 per zone
            if not placed then
                for _, zoneNum in ipairs(ZONE_ORDER) do
                    if table.getn(zoneAssignments[zoneNum].ranged) < 3 then
                        table.insert(zoneAssignments[zoneNum].ranged, playerName)
                        placed = true
                        break
                    end
                end
            end
            
            -- If still not placed, put them in the least populated zone
            if not placed then
                local leastPopulated = ZONE_ORDER[1]
                local minCount = table.getn(zoneAssignments[ZONE_ORDER[1]].ranged)
                for _, zoneNum in ipairs(ZONE_ORDER) do
                    local count = table.getn(zoneAssignments[zoneNum].ranged)
                    if count < minCount then
                        minCount = count
                        leastPopulated = zoneNum
                    end
                end
                table.insert(zoneAssignments[leastPopulated].ranged, playerName)
            end
        end

        -- Announce assignments in numerical order
        for _, zoneNum in ipairs(ANNOUNCE_ORDER) do
            local zoneData = zoneAssignments[zoneNum]
            if table.getn(zoneData.tanks) > 0 or table.getn(zoneData.melee) > 0 or
               table.getn(zoneData.healers) > 0 or table.getn(zoneData.ranged) > 0 then
                
                local msg = "Zone " .. zoneNum .. ":"

                -- Apply raid targets and add marked players first
                local markedPlayers = {}
                
                -- Initialize tables if needed
                if not OGRH_SV then OGRH_SV = {} end
                if not OGRH_SV.raidTargets then OGRH_SV.raidTargets = {} end
                if not PLAYER_RAID_TARGETS then PLAYER_RAID_TARGETS = {} end

                -- Handle tanks in zones 1 and 8 (Skull and Star)
                if zoneNum == 1 or zoneNum == 8 then
                    local markId = (zoneNum == 1 and 8) or (zoneNum == 8 and 1) -- Skull for zone 1, Star for zone 8
                    for _, playerName in ipairs(zoneData.tanks) do
                        -- Only mark if they already have the correct mark
                        local existingMark = OGRH_SV.raidTargets[playerName]
                        if existingMark and existingMark == markId then
                            local numRaidMembers = GetNumRaidMembers()
                            for i = 1, numRaidMembers do
                                local name, _, _, _, _, _, _, _, _, _, _ = GetRaidRosterInfo(i)
                                if name == playerName then
                                    SetRaidTarget("raid"..i, existingMark)
                                    break
                                end
                            end
                        end
                        -- Add to marked players list
                        table.insert(markedPlayers, OGRH.ClassColorHex(OGRH.Roles.nameClass[playerName]) .. playerName .. "|r")
                    end
                    -- Add mark name to message after player list
                    if table.getn(markedPlayers) > 0 then
                        msg = msg .. " " .. OGRH.GetColoredMarkName(markId) .. ": " .. table.concat(markedPlayers, ", ")
                    end
                end

                -- Handle melee auto-marking
                for _, playerName in ipairs(zoneData.melee) do
                    local markId = ZONE_MARKS[zoneNum]
                    if markId then
                        -- Apply the mark in-game
                        local numRaidMembers = GetNumRaidMembers()
                        for i = 1, numRaidMembers do
                            local name, _, _, _, _, _, _, _, _, _, _ = GetRaidRosterInfo(i)
                            if name == playerName then
                                -- Update both the game mark and our saved mark
                                SetRaidTarget("raid"..i, markId)
                                if not PLAYER_RAID_TARGETS then PLAYER_RAID_TARGETS = {} end
                                PLAYER_RAID_TARGETS[playerName] = markId
                                OGRH_SV.raidTargets[playerName] = markId
                                break
                            end
                        end
                        table.insert(markedPlayers, OGRH.ClassColorHex(OGRH.Roles.nameClass[playerName]) .. playerName .. "|r")
                    end
                end

                if parent.RefreshColumnDisplays then
                    parent.RefreshColumnDisplays()
                elseif OGRH.rolesFrame and OGRH.rolesFrame.RefreshColumnDisplays then
                    OGRH.rolesFrame.RefreshColumnDisplays()
                end

                -- Also update the player list to ensure marks are visible
                if OGRH.rolesFrame and OGRH.rolesFrame.UpdatePlayerLists then
                    OGRH.rolesFrame.UpdatePlayerLists()
                end
                
                if table.getn(markedPlayers) > 0 then
                    msg = msg .. " " .. OGRH.GetColoredMarkName(ZONE_MARKS[zoneNum]) .. ": " .. table.concat(markedPlayers, ", ")
                end

                -- Add other players
                local otherPlayers = {}
                for _, playerName in ipairs(zoneData.melee) do
                    if not OGRH_SV.raidTargets or not OGRH_SV.raidTargets[playerName] then
                        table.insert(otherPlayers, OGRH.ClassColorHex(OGRH.Roles.nameClass[playerName]) .. playerName .. "|r")
                    end
                end
                for _, playerName in ipairs(zoneData.healers) do
                    table.insert(otherPlayers, OGRH.ClassColorHex(OGRH.Roles.nameClass[playerName]) .. playerName .. "|r")
                end
                for _, playerName in ipairs(zoneData.ranged) do
                    table.insert(otherPlayers, OGRH.ClassColorHex(OGRH.Roles.nameClass[playerName]) .. playerName .. "|r")
                end

                if table.getn(otherPlayers) > 0 then
                    if table.getn(markedPlayers) > 0 then
                        msg = msg .. " +"
                    end
                    msg = msg .. " " .. table.concat(otherPlayers, ", ")
                end

                SendChatMessage(msg, "RAID_WARNING")
            end
        end
    end)

    return panel
end

-- Initialize immediately
if not OGRH then
    print("Error: OGRH_E_AQ40 requires OGRH_Core to be loaded first!")
    return
end

-- Add our functions to the OGRH namespace
OGRH.AQ40 = {
    CreateCThunPanel = CreateCThunPanel
}