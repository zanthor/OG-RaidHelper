-- OGRH_Versioning.lua (Turtle-WoW 1.12)
-- Version vector system for conflict resolution
-- Tracks data versions for encounters, assignments, and roles

OGRH = OGRH or {}
OGRH.Versioning = {}

--[[
    Version State
    Each data structure maintains:
    - version: Increments on each change
    - lastModifiedBy: Player name who made the change
    - lastModifiedAt: Timestamp of the change
    - checksum: Hash for integrity verification
]]

OGRH.Versioning.State = {
    globalVersion = 0,           -- Global version counter
    encounterVersions = {},      -- Per-encounter version tracking
    assignmentVersions = {},     -- Per-assignment version tracking
    changeLog = {}               -- History of all changes
}

--[[
    Version Counter Functions
]]

-- Increment global version counter
function OGRH.IncrementDataVersion()
    OGRH.Versioning.State.globalVersion = OGRH.Versioning.State.globalVersion + 1
    return OGRH.Versioning.State.globalVersion
end

-- Get current global version
function OGRH.GetDataVersion()
    return OGRH.Versioning.State.globalVersion
end

-- Set global version (used for sync from higher version)
function OGRH.SetDataVersion(version)
    if version and version > OGRH.Versioning.State.globalVersion then
        OGRH.Versioning.State.globalVersion = version
        return true
    end
    return false
end

--[[
    Encounter Version Tracking
]]

-- Get encounter version metadata
function OGRH.GetEncounterVersion(encounterId)
    if not encounterId then return nil end
    return OGRH.Versioning.State.encounterVersions[encounterId]
end

-- Set encounter version metadata
function OGRH.SetEncounterVersion(encounterId, version, modifiedBy, checksum)
    if not encounterId then return false end
    
    OGRH.Versioning.State.encounterVersions[encounterId] = {
        version = version or OGRH.IncrementDataVersion(),
        lastModifiedBy = modifiedBy or UnitName("player"),
        lastModifiedAt = time(),
        checksum = checksum or ""
    }
    
    return true
end

-- Increment encounter version
function OGRH.IncrementEncounterVersion(encounterId)
    if not encounterId then return nil end
    
    local currentVersion = OGRH.GetEncounterVersion(encounterId)
    local newVersion = OGRH.IncrementDataVersion()
    
    OGRH.SetEncounterVersion(encounterId, newVersion, UnitName("player"), "")
    
    return newVersion
end

--[[
    Assignment Version Tracking
]]

-- Get assignment version metadata
function OGRH.GetAssignmentVersion(assignmentId)
    if not assignmentId then return nil end
    return OGRH.Versioning.State.assignmentVersions[assignmentId]
end

-- Set assignment version metadata
function OGRH.SetAssignmentVersion(assignmentId, version, modifiedBy, checksum)
    if not assignmentId then return false end
    
    OGRH.Versioning.State.assignmentVersions[assignmentId] = {
        version = version or OGRH.IncrementDataVersion(),
        lastModifiedBy = modifiedBy or UnitName("player"),
        lastModifiedAt = time(),
        checksum = checksum or ""
    }
    
    return true
end

-- Increment assignment version
function OGRH.IncrementAssignmentVersion(assignmentId)
    if not assignmentId then return nil end
    
    local currentVersion = OGRH.GetAssignmentVersion(assignmentId)
    local newVersion = OGRH.IncrementDataVersion()
    
    OGRH.SetAssignmentVersion(assignmentId, newVersion, UnitName("player"), "")
    
    return newVersion
end

--[[
    Change Log Functions
]]

-- Record a change in the change log
function OGRH.RecordChange(changeType, target, oldValue, newValue)
    table.insert(OGRH.Versioning.State.changeLog, {
        type = changeType,
        target = target,
        oldValue = oldValue,
        newValue = newValue,
        timestamp = time(),
        author = UnitName("player"),
        version = OGRH.GetDataVersion()
    })
    
    -- Keep only last 100 changes
    while table.getn(OGRH.Versioning.State.changeLog) > 100 do
        table.remove(OGRH.Versioning.State.changeLog, 1)
    end
end

-- Get recent changes
function OGRH.GetRecentChanges(count)
    count = count or 10
    local changes = {}
    local total = table.getn(OGRH.Versioning.State.changeLog)
    local startIdx = math.max(1, total - count + 1)
    
    for i = startIdx, total do
        table.insert(changes, OGRH.Versioning.State.changeLog[i])
    end
    
    return changes
end

-- Clear change log (session only)
function OGRH.ClearChangeLog()
    OGRH.Versioning.State.changeLog = {}
end

--[[
    Conflict Resolution
]]

-- Compare two versions and determine which should win
function OGRH.CompareVersions(version1, version2, timestamp1, timestamp2, author1, author2)
    -- Higher version wins
    if version1 > version2 then
        return 1  -- version1 wins
    elseif version2 > version1 then
        return -1  -- version2 wins
    end
    
    -- Same version, use timestamp as tiebreaker
    if timestamp1 and timestamp2 then
        if timestamp1 > timestamp2 then
            return 1  -- version1 wins (newer)
        elseif timestamp2 > timestamp1 then
            return -1  -- version2 wins (newer)
        end
    end
    
    -- Same version and timestamp, check if either author is admin
    if author1 and OGRH.IsRaidAdmin and OGRH.IsRaidAdmin(author1) then
        return 1  -- admin wins
    end
    if author2 and OGRH.IsRaidAdmin and OGRH.IsRaidAdmin(author2) then
        return -1  -- admin wins
    end
    
    -- Completely equal - no clear winner
    return 0
end

-- Resolve conflict between local and remote data
function OGRH.ResolveConflict(localData, remoteData)
    if not localData or not remoteData then
        return remoteData or localData
    end
    
    local localVersion = localData.version or 0
    local remoteVersion = remoteData.version or 0
    local localTimestamp = localData.lastModifiedAt or 0
    local remoteTimestamp = remoteData.lastModifiedAt or 0
    local localAuthor = localData.lastModifiedBy or ""
    local remoteAuthor = remoteData.lastModifiedBy or ""
    
    local result = OGRH.CompareVersions(
        localVersion, remoteVersion,
        localTimestamp, remoteTimestamp,
        localAuthor, remoteAuthor
    )
    
    if result > 0 then
        -- Local wins
        return localData, "LOCAL_WINS"
    elseif result < 0 then
        -- Remote wins
        return remoteData, "REMOTE_WINS"
    else
        -- Conflict - requires manual resolution
        return nil, "CONFLICT"
    end
end

--[[
    Version Metadata Helpers
]]

-- Create version metadata for a data structure
function OGRH.CreateVersionMetadata(checksum)
    return {
        version = OGRH.IncrementDataVersion(),
        lastModifiedBy = UnitName("player"),
        lastModifiedAt = time(),
        checksum = checksum or ""
    }
end

-- Update version metadata
function OGRH.UpdateVersionMetadata(data, checksum)
    if not data then return nil end
    
    data.version = OGRH.IncrementDataVersion()
    data.lastModifiedBy = UnitName("player")
    data.lastModifiedAt = time()
    if checksum then
        data.checksum = checksum
    end
    
    return data
end

-- Check if data needs update (remote is newer)
function OGRH.NeedsUpdate(localData, remoteData)
    if not localData then return true end
    if not remoteData then return false end
    
    local localVersion = localData.version or 0
    local remoteVersion = remoteData.version or 0
    
    return remoteVersion > localVersion
end

--[[
    Checksum Functions
]]

-- Simple hash function for integrity checking
function OGRH.Hash(str)
    if not str then return "0" end
    
    local hash = 0
    for i = 1, string.len(str) do
        local char = string.byte(str, i)
        hash = mod((hash * 31 + char), 2147483647)
    end
    
    return tostring(hash)
end

-- Compute checksum for a table
function OGRH.ComputeChecksum(data)
    if not data then return "EMPTY" end
    
    -- Create a string representation of critical fields
    local str = ""
    
    if type(data) == "table" then
        -- Sort keys for consistent ordering
        local keys = {}
        for k in pairs(data) do
            table.insert(keys, tostring(k))
        end
        table.sort(keys)
        
        -- Concatenate key-value pairs
        for i = 1, table.getn(keys) do
            local key = keys[i]
            local value = data[key]
            
            -- Skip metadata fields
            if key ~= "version" and key ~= "lastModifiedBy" and key ~= "lastModifiedAt" and key ~= "checksum" then
                if type(value) == "table" then
                    str = str .. key .. ":" .. OGRH.ComputeChecksum(value) .. ";"
                else
                    str = str .. key .. ":" .. tostring(value) .. ";"
                end
            end
        end
    else
        str = tostring(data)
    end
    
    return OGRH.Hash(str)
end

-- Verify checksum matches data
function OGRH.VerifyChecksum(data, expectedChecksum)
    if not data or not expectedChecksum then return false end
    
    local actualChecksum = OGRH.ComputeChecksum(data)
    return actualChecksum == expectedChecksum
end

--[[
    Initialization
]]

-- Initialize versioning system
function OGRH.Versioning.Initialize()
    -- Load from SavedVariables if available
    if OGRH_SV and OGRH_SV.Versioning then
        OGRH.Versioning.State.globalVersion = OGRH_SV.Versioning.globalVersion or 0
        OGRH.Versioning.State.encounterVersions = OGRH_SV.Versioning.encounterVersions or {}
        OGRH.Versioning.State.assignmentVersions = OGRH_SV.Versioning.assignmentVersions or {}
        -- Don't load changeLog (session only)
    end
    
    OGRH.Msg(string.format("|cff00ccff[RH-Versioning]|r Initialized (v%d)", OGRH.Versioning.State.globalVersion))
end

-- Save versioning state to SavedVariables
function OGRH.Versioning.Save()
    if OGRH_SV then
        OGRH_SV.Versioning = {
            globalVersion = OGRH.Versioning.State.globalVersion,
            encounterVersions = OGRH.Versioning.State.encounterVersions,
            assignmentVersions = OGRH.Versioning.State.assignmentVersions
            -- Don't save changeLog (session only)
        }
    end
end

--[[
    Debug Commands
]]

-- Debug: Print version state
function OGRH.Versioning.DebugPrintState()
    DEFAULT_CHAT_FRAME:AddMessage("[OGRH] === Version State ===")
    DEFAULT_CHAT_FRAME:AddMessage(string.format("[OGRH] Global Version: %d", OGRH.Versioning.State.globalVersion))
    
    DEFAULT_CHAT_FRAME:AddMessage("[OGRH] Encounter Versions:")
    for encounterId, versionData in pairs(OGRH.Versioning.State.encounterVersions) do
        DEFAULT_CHAT_FRAME:AddMessage(string.format("[OGRH]   %s: v%d by %s at %s", 
            encounterId, 
            versionData.version,
            versionData.lastModifiedBy,
            date("%H:%M:%S", versionData.lastModifiedAt)))
    end
    
    DEFAULT_CHAT_FRAME:AddMessage("[OGRH] Assignment Versions:")
    for assignmentId, versionData in pairs(OGRH.Versioning.State.assignmentVersions) do
        DEFAULT_CHAT_FRAME:AddMessage(string.format("[OGRH]   %s: v%d by %s at %s", 
            assignmentId, 
            versionData.version,
            versionData.lastModifiedBy,
            date("%H:%M:%S", versionData.lastModifiedAt)))
    end
    
    DEFAULT_CHAT_FRAME:AddMessage("[OGRH] === End Version State ===")
end

-- Debug: Print recent changes
function OGRH.Versioning.DebugPrintChanges(count)
    count = count or 10
    DEFAULT_CHAT_FRAME:AddMessage(string.format("[OGRH] === Recent Changes (last %d) ===", count))
    
    local changes = OGRH.GetRecentChanges(count)
    
    if table.getn(changes) == 0 then
        DEFAULT_CHAT_FRAME:AddMessage("[OGRH] No changes recorded")
    else
        for i = 1, table.getn(changes) do
            local change = changes[i]
            DEFAULT_CHAT_FRAME:AddMessage(string.format("[OGRH] [v%d] %s: %s by %s at %s", 
                change.version,
                change.type,
                change.target,
                change.author,
                date("%H:%M:%S", change.timestamp)))
        end
    end
    
    DEFAULT_CHAT_FRAME:AddMessage("[OGRH] === End Changes ===")
end

--[[
    Checksum Computation (for sync verification)
]]

-- Compute checksum for data structure
function OGRH.Versioning.ComputeChecksum(data)
    if not data or type(data) ~= "table" then
        return "0"
    end
    
    local checksum = 0
    
    -- Hash raids list and encounters (from new nested structure)
    if data.encounterMgmt and data.encounterMgmt.raids then
        for i = 1, table.getn(data.encounterMgmt.raids) do
            local raid = data.encounterMgmt.raids[i]
            
            -- Hash raid name
            local raidName = raid.name or raid  -- Support both new (table) and old (string) structure
            if type(raidName) == "string" then
                for j = 1, string.len(raidName) do
                    checksum = checksum + string.byte(raidName, j) * i * 50
                end
            end
            
            -- Hash raid-level advanced settings
            if type(raid) == "table" and raid.advancedSettings and raid.advancedSettings.consumeTracking then
                local ct = raid.advancedSettings.consumeTracking
                checksum = checksum + (ct.enabled and 1 or 0) * 50000023
                checksum = checksum + (ct.readyThreshold or 0) * 500029
                
                if ct.requiredFlaskRoles then
                    local roleNames = {"Tanks", "Healers", "Melee", "Ranged"}
                    for _, roleName in ipairs(roleNames) do
                        if ct.requiredFlaskRoles[roleName] then
                            for k = 1, string.len(roleName) do
                                checksum = checksum + string.byte(roleName, k) * (k + 311) * 1019
                            end
                        end
                    end
                end
            end
            
            -- Hash encounters from nested structure
            if type(raid) == "table" and raid.encounters then
                for j = 1, table.getn(raid.encounters) do
                    local encounter = raid.encounters[j]
                    local encounterName = encounter.name or encounter  -- Support both formats
                    if type(encounterName) == "string" then
                        for k = 1, string.len(encounterName) do
                            checksum = checksum + string.byte(encounterName, k) * j * 100
                        end
                    end
                    
                    -- Hash encounter-level advanced settings
                    if type(encounter) == "table" and encounter.advancedSettings then
                        -- BigWigs settings
                        if encounter.advancedSettings.bigwigs then
                            local bw = encounter.advancedSettings.bigwigs
                            checksum = checksum + (bw.enabled and 1 or 0) * 10000019
                            
                            if bw.encounterId and bw.encounterId ~= "" then
                                for k = 1, string.len(bw.encounterId) do
                                    checksum = checksum + string.byte(bw.encounterId, k) * (k + 107) * 1009
                                end
                            end
                        end
                        
                        -- Consume tracking settings
                        if encounter.advancedSettings.consumeTracking then
                            local ct = encounter.advancedSettings.consumeTracking
                            
                            -- Hash enabled flag (nil=inherit, false=disabled, true=enabled)
                            local enabledValue = 0
                            if ct.enabled == true then
                                enabledValue = 2
                            elseif ct.enabled == false then
                                enabledValue = 1
                            end
                            checksum = checksum + enabledValue * 100000037
                            
                            if ct.readyThreshold ~= nil then
                                checksum = checksum + ct.readyThreshold * 1000039
                            end
                            
                            if ct.requiredFlaskRoles then
                                local roleNames = {"Tanks", "Healers", "Melee", "Ranged"}
                                for _, roleName in ipairs(roleNames) do
                                    if ct.requiredFlaskRoles[roleName] ~= nil then
                                        for k = 1, string.len(roleName) do
                                            checksum = checksum + string.byte(roleName, k) * (k + 211) * 1013
                                        end
                                        local roleValue = ct.requiredFlaskRoles[roleName] and 2 or 1
                                        checksum = checksum + roleValue * 1017
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    
    -- Hash all encounter roles (from encounterMgmt.roles)
    if data.encounterMgmt and data.encounterMgmt.roles then
        for raidName, raids in pairs(data.encounterMgmt.roles) do
            for encounterName, encounter in pairs(raids) do
                -- Hash roles from column1
                if encounter.column1 then
                    for i = 1, table.getn(encounter.column1) do
                        local role = encounter.column1[i]
                        if OGRH.HashRole then
                            checksum = checksum + OGRH.HashRole(role, 10, i)
                        end
                    end
                end
                
                -- Hash roles from column2
                if encounter.column2 then
                    for i = 1, table.getn(encounter.column2) do
                        local role = encounter.column2[i]
                        if OGRH.HashRole then
                            checksum = checksum + OGRH.HashRole(role, 20, i)
                        end
                    end
                end
            end
        end
    end
    
    -- Hash all raid marks
    if data.encounterRaidMarks then
        for raidName, raids in pairs(data.encounterRaidMarks) do
            for encounterName, encounter in pairs(raids) do
                for roleIdx, roleMarks in pairs(encounter) do
                    for slotIdx, markValue in pairs(roleMarks) do
                        if type(markValue) == "number" then
                            checksum = checksum + (markValue * slotIdx * roleIdx * 1000)
                        end
                    end
                end
            end
        end
    end
    
    -- Hash all assignment numbers
    if data.encounterAssignmentNumbers then
        for raidName, raids in pairs(data.encounterAssignmentNumbers) do
            for encounterName, encounter in pairs(raids) do
                for roleIdx, roleNumbers in pairs(encounter) do
                    for slotIdx, numberValue in pairs(roleNumbers) do
                        if type(numberValue) == "number" then
                            checksum = checksum + (numberValue * slotIdx * roleIdx * 500)
                        end
                    end
                end
            end
        end
    end
    
    -- Hash all announcements
    if data.encounterAnnouncements then
        for raidName, raids in pairs(data.encounterAnnouncements) do
            for encounterName, announcements in pairs(raids) do
                if type(announcements) == "table" then
                    for i = 1, table.getn(announcements) do
                        local line = announcements[i]
                        if type(line) == "string" then
                            for j = 1, string.len(line) do
                                checksum = checksum + string.byte(line, j) * i
                            end
                        end
                    end
                elseif type(announcements) == "string" then
                    for j = 1, string.len(announcements) do
                        checksum = checksum + string.byte(announcements, j)
                    end
                end
            end
        end
    end
    
    -- Hash tradeItems
    if data.tradeItems then
        for itemName, itemData in pairs(data.tradeItems) do
            for j = 1, string.len(itemName) do
                checksum = checksum + string.byte(itemName, j) * 30
            end
        end
    end
    
    -- Hash consumes
    if data.consumes then
        for consumeName, consumeData in pairs(data.consumes) do
            for j = 1, string.len(consumeName) do
                checksum = checksum + string.byte(consumeName, j) * 40
            end
        end
    end
    
    -- Hash RGO data (raid group organization)
    if data.rgo then
        -- Hash current raid size
        if data.rgo.currentRaidSize then
            local sizeStr = tostring(data.rgo.currentRaidSize)
            for j = 1, string.len(sizeStr) do
                checksum = checksum + string.byte(sizeStr, j) * 6000
            end
        end
        
        -- Hash all raid size configurations
        if data.rgo.raidSizes then
            for raidSize, groups in pairs(data.rgo.raidSizes) do
                local sizeNum = tonumber(raidSize) or 0
                for groupNum, slots in pairs(groups) do
                    for slotNum, slotData in pairs(slots) do
                        -- Hash priority list
                        if slotData.priorityList and type(slotData.priorityList) == "table" then
                            for classIndex, className in ipairs(slotData.priorityList) do
                                if type(className) == "string" then
                                    for j = 1, string.len(className) do
                                        checksum = checksum + string.byte(className, j) * sizeNum * groupNum * slotNum * classIndex * 7000
                                    end
                                end
                            end
                        end
                        
                        -- Hash priority roles
                        if slotData.priorityRoles and type(slotData.priorityRoles) == "table" then
                            for priorityIndex, roles in pairs(slotData.priorityRoles) do
                                if type(roles) == "table" then
                                    local prioIdx = tonumber(priorityIndex) or 0
                                    -- Hash role flags
                                    checksum = checksum + (roles.Tanks and 1 or 0) * sizeNum * groupNum * slotNum * prioIdx * 8001
                                    checksum = checksum + (roles.Healers and 1 or 0) * sizeNum * groupNum * slotNum * prioIdx * 8002
                                    checksum = checksum + (roles.Melee and 1 or 0) * sizeNum * groupNum * slotNum * prioIdx * 8003
                                    checksum = checksum + (roles.Ranged and 1 or 0) * sizeNum * groupNum * slotNum * prioIdx * 8004
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    
    return tostring(checksum)
end

-- Convenience wrappers for versioning functions at OGRH namespace
function OGRH.Versioning.IncrementDataVersion(changeType, description)
    local newVersion = OGRH.IncrementDataVersion()
    -- RecordChange expects (changeType, target, oldValue, newValue)
    -- We're using it for version tracking, so pass description as target
    if changeType and description then
        OGRH.RecordChange(changeType, description, nil, newVersion)
    end
    return newVersion
end

function OGRH.Versioning.GetGlobalVersion()
    return OGRH.GetDataVersion()
end

function OGRH.Versioning.SetGlobalVersion(version)
    return OGRH.SetDataVersion(version)
end

OGRH.Msg("|cff00ccff[RH-Versioning]|r Loaded")
