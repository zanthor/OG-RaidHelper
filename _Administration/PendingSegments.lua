-- PendingSegments.lua
-- DPSMate Pending Segment System - Automatic capture of combat segments for delayed ELO ranking

OGRH = OGRH or {}
OGRH.PendingSegments = {}

local PendingSegments = OGRH.PendingSegments

-- State tracking
local hookInstalled = false
local originalCreateSegment = nil

--[[
    Hook Installation
]]

function PendingSegments.Initialize()
    -- Check if DPSMate is available
    if DPSMate and DPSMate.Options and DPSMate.Options.CreateSegment then
        PendingSegments.InstallHook()
    else
        -- Register for ADDON_LOADED to wait for DPSMate
        if not PendingSegments.addonLoadedRegistered then
            PendingSegments.addonLoadedRegistered = true
            
            local frame = CreateFrame("Frame")
            frame:RegisterEvent("ADDON_LOADED")
            frame:SetScript("OnEvent", function()
                if arg1 == "DPSMate" then
                    PendingSegments.InstallHook()
                    frame:UnregisterEvent("ADDON_LOADED")
                end
            end)
        end
    end
    
    -- Initialize schema in SavedVariables
    PendingSegments.InitializeSchema()
end

function PendingSegments.InstallHook()
    if hookInstalled then return end
    
    if not DPSMate or not DPSMate.Options or not DPSMate.Options.CreateSegment then
        OGRH.Msg("|cffff8800[AutoRank]|r DPSMate not available, hook not installed")
        return
    end
    
    -- Store original function
    originalCreateSegment = DPSMate.Options.CreateSegment
    
    -- Hook CreateSegment
    DPSMate.Options.CreateSegment = function(self, name)
        -- Call original function first
        originalCreateSegment(self, name)
        
        -- Check if we should capture this segment
        if PendingSegments.ShouldCaptureSegment() then
            PendingSegments.CaptureSegmentData(name)
        end
    end
    
    hookInstalled = true
    OGRH.Msg("|cff00ff00[AutoRank]|r DPSMate segment capture hook installed")
end

--[[
    Permission & AutoRank Checks
]]

function PendingSegments.ShouldCaptureSegment()
    -- Check raid permissions using existing Permissions API
    if not OGRH.CanModifyAssignments(UnitName("player")) then
        return false
    end
    
    -- Get Active Raid index
    local raidIdx = OGRH.SVM.Get("ui", "selectedRaidIndex")
    if not raidIdx then return false end
    
    -- Get Active Raid
    local raid = OGRH.SVM.GetPath("encounterMgmt.raids." .. raidIdx)
    if not raid then return false end
    
    -- Check if Raid-level AutoRank is enabled
    if raid.autoRank then
        return true
    end
    
    -- Get Active Encounter index
    local encounterIdx = OGRH.SVM.Get("ui", "selectedEncounterIndex")
    if not encounterIdx then return false end
    
    -- Get Active Encounter
    local encounter = OGRH.SVM.GetPath("encounterMgmt.raids." .. raidIdx .. ".encounters." .. encounterIdx)
    if not encounter then return false end
    
    -- Check if Encounter-level AutoRank is enabled
    if encounter.autoRank then
        return true
    end
    
    return false
end

--[[
    Data Capture
]]

function PendingSegments.CaptureSegmentData(segmentName)
    -- Validate DPSMate tables exist
    if not DPSMateDamageDone or not DPSMateTHealing or not DPSMateCombatTime then
        OGRH.Msg("|cffff0000[AutoRank]|r Cannot capture segment: DPSMate data unavailable")
        return
    end
    
    -- Get Active Raid/Encounter context
    local raidIdx = OGRH.SVM.Get("ui", "selectedRaidIndex")
    local raid = OGRH.SVM.GetPath("encounterMgmt.raids." .. raidIdx)
    local encounterIdx = OGRH.SVM.Get("ui", "selectedEncounterIndex")
    local encounter = encounterIdx and OGRH.SVM.GetPath("encounterMgmt.raids." .. raidIdx .. ".encounters." .. encounterIdx)
    
    if not raid then
        OGRH.Msg("|cffff0000[AutoRank]|r Cannot capture segment: No active raid")
        return
    end
    
    -- Generate unique segment ID
    local timestamp = time()
    local segmentId = "seg_" .. timestamp .. "_" .. string.gsub(string.lower(segmentName), "%s", "_")
    
    -- Check for duplicates
    local pendingSegments = OGRH.SVM.GetPath("rosterManagement.pendingSegments") or {}
    for i, seg in ipairs(pendingSegments) do
        if seg.segmentId == segmentId then
            OGRH.Msg("|cffaaaaaa[AutoRank]|r Segment already captured: " .. segmentName)
            return
        end
    end
    
    -- Extract data from DPSMate tables
    local damageData = PendingSegments.ExtractDamageData()
    local totalHealingData = PendingSegments.ExtractHealingData(false)
    local effectiveHealingData = PendingSegments.ExtractHealingData(true)
    local playerRoles = PendingSegments.ExtractPlayerRoles(damageData, effectiveHealingData)
    
    local segment = {
        segmentId = segmentId,
        name = segmentName,
        timestamp = timestamp,
        createdAt = date("%Y-%m-%d %H:%M:%S", timestamp),
        
        raidName = raid.displayName or raid.name,
        raidIndex = raidIdx,
        encounterName = encounter and (encounter.displayName or encounter.name),
        encounterIndex = encounterIdx,
        
        combatTime = DPSMateCombatTime.current or 0,
        effectiveCombatTime = PendingSegments.ConvertEffectiveTimeToNames(DPSMateCombatTime.effective and DPSMateCombatTime.effective[2] or {}),
        
        damageData = damageData,
        totalHealingData = totalHealingData,
        effectiveHealingData = effectiveHealingData,
        playerRoles = playerRoles,
        
        imported = false,
        importedAt = nil,
        importedBy = nil,
        
        expiresAt = timestamp + (2 * 86400),  -- 2 days
        
        playerCount = PendingSegments.CountPlayers(DPSMateDamageDone[2], DPSMateTHealing[2]),
        topDPS = PendingSegments.GetTopPlayer(DPSMateDamageDone[2]),
        topHealer = PendingSegments.GetTopPlayer(DPSMateTHealing[2]),
    }
    
    -- Store segment
    table.insert(pendingSegments, 1, segment)  -- Insert at front (newest first)
    
    OGRH.SVM.SetPath("rosterManagement.pendingSegments", pendingSegments, {
        source = "PendingSegments",
        action = "capture",
        sync = false,  -- Don't sync pending segments
    })
    
    -- Write to combat log for crash recovery
    PendingSegments.WriteSegmentToCombatLog(segment)
    
    OGRH.Msg("|cff00ff00[AutoRank]|r Captured segment: " .. segmentName)
end

--[[
    Helper Functions - Data Extraction
]]

function PendingSegments.ExtractDamageData()
    local data = {}
    local damageTable = DPSMateDamageDone[2] or {}
    local effectiveTime = DPSMateCombatTime.effective and DPSMateCombatTime.effective[2] or {}
    
    for playerId, playerData in pairs(damageTable) do
        local total = playerData.i or 0
        local time = effectiveTime[playerId] or 1
        
        -- Convert numeric ID to player name
        local playerName = DPSMate:GetUserById(playerId)
        if playerName and playerName ~= "Unknown" then
            data[playerName] = {
                total = total,
                value = total,  -- Renamed from dps - stores total damage for ranking
            }
        end
    end
    
    return data
end

function PendingSegments.ExtractHealingData(effective)
    local data = {}
    local healingTable = effective and DPSMateEHealing and DPSMateEHealing[2] or DPSMateTHealing and DPSMateTHealing[2]
    healingTable = healingTable or {}
    local effectiveTime = DPSMateCombatTime.effective and DPSMateCombatTime.effective[2] or {}
    
    for playerId, playerData in pairs(healingTable) do
        local total = playerData.i or 0
        local time = effectiveTime[playerId] or 1
        
        -- Convert numeric ID to player name
        local playerName = DPSMate:GetUserById(playerId)
        if playerName and playerName ~= "Unknown" then
            data[playerName] = {
                total = total,
                value = total,  -- Renamed from hps - stores total healing for ranking
            }
        end
    end
    
    return data
end

-- Extract player roles from RolesUI or fallback to default logic
function PendingSegments.ExtractPlayerRoles(damageData, healingData)
    local roles = {}
    local allPlayers = OGRH.SVM.GetPath("rosterManagement.players") or {}
    
    -- Collect all unique player names
    local playerNames = {}
    for playerName in pairs(damageData) do
        playerNames[playerName] = true
    end
    for playerName in pairs(healingData) do
        playerNames[playerName] = true
    end
    
    -- Determine role for each player
    for playerName in pairs(playerNames) do
        local role = "RANGED"  -- Default fallback
        local class = OGRH.GetPlayerClass(playerName) or "UNKNOWN"
        
        -- Priority 1: Check RolesUI
        if OGRH_GetPlayerRole then
            local rolesUIRole = OGRH_GetPlayerRole(playerName)
            if rolesUIRole then
                role = rolesUIRole
            end
        end
        
        -- Priority 2: Check rosterManagement primaryRole (only if RolesUI didn't have a role)
        if not role or role == "RANGED" then
            if allPlayers[playerName] and allPlayers[playerName].primaryRole then
                role = allPlayers[playerName].primaryRole
            end
        end
        
        -- Priority 3: Use default role for class (only if still no role assigned)
        if not role or role == "RANGED" then
            if OGRH.RosterMgmt and OGRH.RosterMgmt.GetDefaultRoleForClass then
                role = OGRH.RosterMgmt.GetDefaultRoleForClass(string.upper(class))
            end
        end
        
        roles[playerName] = role
    end
    
    return roles
end

function PendingSegments.CountPlayers(damageTable, healingTable)
    local players = {}
    
    -- Count damage dealers
    for playerId, _ in pairs(damageTable or {}) do
        local playerName = DPSMate:GetUserById(playerId)
        if playerName and playerName ~= "Unknown" then
            players[playerName] = true
        end
    end
    
    -- Count healers
    for playerId, _ in pairs(healingTable or {}) do
        local playerName = DPSMate:GetUserById(playerId)
        if playerName and playerName ~= "Unknown" then
            players[playerName] = true
        end
    end
    
    local count = 0
    for _ in pairs(players) do
        count = count + 1
    end
    return count
end

function PendingSegments.GetTopPlayer(dataTable)
    local topPlayerId = nil
    local topValue = 0
    
    for playerId, playerData in pairs(dataTable or {}) do
        local value = playerData.i or 0
        if value > topValue then
            topValue = value
            topPlayerId = playerId
        end
    end
    
    -- Convert ID to name
    if topPlayerId then
        local playerName = DPSMate:GetUserById(topPlayerId)
        return playerName ~= "Unknown" and playerName or nil
    end
    
    return nil
end

function PendingSegments.CopyTable(src)
    local dest = {}
    for k, v in pairs(src) do
        if type(v) == "table" then
            dest[k] = PendingSegments.CopyTable(v)
        else
            dest[k] = v
        end
    end
    return dest
end

function PendingSegments.ConvertEffectiveTimeToNames(effectiveTimeTable)
    local converted = {}
    for playerId, time in pairs(effectiveTimeTable) do
        local playerName = DPSMate:GetUserById(playerId)
        if playerName and playerName ~= "Unknown" then
            converted[playerName] = time
        end
    end
    return converted
end

--[[
    Schema Management
]]

function PendingSegments.InitializeSchema()
    -- Ensure rosterManagement exists
    local rosterManagement = OGRH.SVM.GetPath("rosterManagement")
    if not rosterManagement then
        OGRH.SVM.SetPath("rosterManagement", {
            config = {},
            syncMeta = {},
            rankingHistory = {},
            pendingSegments = {},
        }, {
            source = "PendingSegments",
            action = "initialize",
            sync = false,
        })
    else
        -- Ensure pendingSegments array exists
        if not rosterManagement.pendingSegments then
            rosterManagement.pendingSegments = {}
            OGRH.SVM.SetPath("rosterManagement.pendingSegments", {}, {
                source = "PendingSegments",
                action = "initialize",
                sync = false,
            })
        end
    end
end

--[[
    Combat Log Export (Crash Recovery)
]]

function PendingSegments.IsSuperWoWAvailable()
    return CombatLogAdd ~= nil
end

function PendingSegments.WriteSegmentToCombatLog(segment)
    if not PendingSegments.IsSuperWoWAvailable() then
        return false, "SuperWoW not available"
    end
    
    if not segment then
        return false, "No segment provided"
    end
    
    -- Format: OGRH_SEGMENT_HEADER: segmentId&name&timestamp&createdAt&raidName&raidIndex&encounterName&encounterIndex&combatTime&playerCount
    local header = string.format("OGRH_SEGMENT_HEADER: %s&%s&%s&%s&%s&%d&%s&%d&%.2f&%d",
        segment.segmentId or "",
        segment.name or "",
        tostring(segment.timestamp or time()),
        segment.createdAt or "",
        segment.raidName or "",
        segment.raidIndex or 0,
        segment.encounterName or "",
        segment.encounterIndex or 0,
        segment.combatTime or 0,
        segment.playerCount or 0
    )
    
    CombatLogAdd(header)
    
    -- Write each player's data
    -- Format: OGRH_SEGMENT_PLAYER: playerName&class&role&damage&effectiveHealing&totalHealing
    local playerList = {}
    
    -- Collect all unique players
    if segment.damageData then
        for playerName in pairs(segment.damageData) do
            playerList[playerName] = true
        end
    end
    if segment.effectiveHealingData then
        for playerName in pairs(segment.effectiveHealingData) do
            playerList[playerName] = true
        end
    end
    
    -- Write each player's complete data
    for playerName in pairs(playerList) do
        local class = OGRH.GetPlayerClass(playerName) or "UNKNOWN"
        local role = segment.playerRoles and segment.playerRoles[playerName] or "RANGED"
        
        local damage = 0
        if segment.damageData and segment.damageData[playerName] then
            damage = segment.damageData[playerName].value or segment.damageData[playerName].total or 0
        end
        
        local effectiveHealing = 0
        if segment.effectiveHealingData and segment.effectiveHealingData[playerName] then
            effectiveHealing = segment.effectiveHealingData[playerName].value or segment.effectiveHealingData[playerName].total or 0
        end
        
        local totalHealing = 0
        if segment.totalHealingData and segment.totalHealingData[playerName] then
            totalHealing = segment.totalHealingData[playerName].value or segment.totalHealingData[playerName].total or 0
        end
        
        local playerLine = string.format("OGRH_SEGMENT_PLAYER: %s&%s&%s&%d&%d&%d",
            playerName,
            class,
            role,
            damage,
            effectiveHealing,
            totalHealing
        )
        CombatLogAdd(playerLine)
    end
    
    -- End marker
    CombatLogAdd(string.format("OGRH_SEGMENT_END: %s", segment.segmentId or ""))
    
    return true
end

--[[
    Public API
]]

function PendingSegments.GetPendingSegments()
    return OGRH.SVM.GetPath("rosterManagement.pendingSegments") or {}
end

function PendingSegments.GetPendingSegmentCount(excludeImported)
    local segments = PendingSegments.GetPendingSegments()
    if not excludeImported then
        return table.getn(segments)
    end
    
    local count = 0
    for i, segment in ipairs(segments) do
        if not segment.imported then
            count = count + 1
        end
    end
    return count
end

function PendingSegments.HasPendingSegments()
    return PendingSegments.GetPendingSegmentCount(true) > 0
end

function PendingSegments.GetPendingSegment(segmentIndex)
    local segments = PendingSegments.GetPendingSegments()
    return segments[segmentIndex]
end

--[[
    Debug/Test Command
]]

function PendingSegments.PrintSegmentList()
    local segments = PendingSegments.GetPendingSegments()
    local totalCount = table.getn(segments)
    local readyCount = 0
    
    for i, segment in ipairs(segments) do
        if not segment.imported then
            readyCount = readyCount + 1
        end
    end
    
    OGRH.Msg("|cff00ccff[RH-PendingSegments]|r === Pending Segments ===")
    OGRH.Msg(string.format("Total: %d | Ready: %d | Imported: %d", totalCount, readyCount, totalCount - readyCount))
    
    if totalCount == 0 then
        OGRH.Msg("|cff888888No segments captured yet|r")
        return
    end
    
    for i, segment in ipairs(segments) do
        local status = segment.imported and "|cff888888[IMPORTED]|r" or "|cff00ff00[READY]|r"
        local age = time() - segment.timestamp
        local ageStr = ""
        if age < 3600 then
            ageStr = string.format("%dm ago", math.floor(age / 60))
        elseif age < 86400 then
            ageStr = string.format("%dh ago", math.floor(age / 3600))
        else
            ageStr = string.format("%dd ago", math.floor(age / 86400))
        end
        
        OGRH.Msg(string.format("%d. %s %s - %d players (%s)", 
            i, status, segment.name, segment.playerCount or 0, ageStr))
        
        if segment.imported then
            OGRH.Msg(string.format("   Imported by %s at %s", 
                segment.importedBy or "Unknown", 
                segment.importedAt and date("%Y-%m-%d %H:%M", segment.importedAt) or "Unknown"))
        end
    end
    
    OGRH.Msg("|cff00ccff[RH-PendingSegments]|r === End Segments ===")
end

--[[
    Purge System (Phase 2)
]]

-- Auto-purge expired or imported segments
function PendingSegments.PurgeExpiredSegments()
    local pendingSegments = OGRH.SVM.GetPath("rosterManagement.pendingSegments") or {}
    local currentTime = time()
    local purgedCount = 0
    
    -- Iterate backwards to safely remove items
    for i = table.getn(pendingSegments), 1, -1 do
        local segment = pendingSegments[i]
        
        -- Remove if expired OR if imported more than 2 days ago
        local shouldPurge = false
        if segment.expiresAt and currentTime > segment.expiresAt then
            shouldPurge = true
        elseif segment.imported and segment.importedAt and (currentTime - segment.importedAt) > (2 * 86400) then
            shouldPurge = true
        end
        
        if shouldPurge then
            table.remove(pendingSegments, i)
            purgedCount = purgedCount + 1
        end
    end
    
    if purgedCount > 0 then
        OGRH.SVM.SetPath("rosterManagement.pendingSegments", pendingSegments, {
            source = "PendingSegments",
            action = "purge",
            sync = false,
        })
        OGRH.Msg("|cffaaaaaa[AutoRank]|r Purged " .. purgedCount .. " expired segment(s)")
    end
end

-- Manual purge command (for testing/admin use)
function PendingSegments.ManualPurge()
    PendingSegments.PurgeExpiredSegments()
end

--[[
    Timer & Event System
]]

-- Schedule repeating purge (every hour)
local purgeTimer = nil
local purgeFrame = CreateFrame("Frame")

function PendingSegments.StartPurgeTimer()
    if purgeTimer then return end -- Already running
    
    purgeFrame:SetScript("OnUpdate", function()
        if not purgeTimer then
            purgeTimer = 0
        end
        
        purgeTimer = purgeTimer + arg1
        
        -- Run purge every hour (3600 seconds)
        if purgeTimer >= 3600 then
            PendingSegments.PurgeExpiredSegments()
            purgeTimer = 0
        end
    end)
    
    purgeFrame:Show()
end

-- Register login event to trigger purge
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:SetScript("OnEvent", function()
    if event == "PLAYER_ENTERING_WORLD" then
        -- Run purge on login
        PendingSegments.PurgeExpiredSegments()
        
        -- Start the hourly timer
        PendingSegments.StartPurgeTimer()
    end
end)

-- Initialize on load
PendingSegments.Initialize()
