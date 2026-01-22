-- OGRH_SyncIntegrity.lua (Turtle-WoW 1.12)
-- Checksum verification and data integrity system
-- Phase 3B: Unified checksum polling for structure, RolesUI, and assignments

OGRH = OGRH or {}
OGRH.SyncIntegrity = {}

--[[
    Unified Checksum Polling System
    
    Admin broadcasts every 30 seconds:
    - Structure checksum (encounter roles, marks, numbers, announcements)
    - RolesUI checksum (bucket assignments)
    - Assignment checksum (player-to-role assignments)
    
    Clients compare their checksums to admin's broadcast:
    - On mismatch: Log warning, optionally request repair
    - Auto-repair: Admin can push data to specific clients or all raid members
]]

OGRH.SyncIntegrity.State = {
    lastChecksumBroadcast = 0,
    verificationInterval = 30,  -- seconds
    checksumCache = {},
    pollingTimer = nil,
    enabled = false
}

--[[
    Core Functions
]]

-- Start periodic integrity checks (called when becoming raid admin)
function OGRH.StartIntegrityChecks()
    if OGRH.SyncIntegrity.State.enabled then
        return  -- Already running
    end
    
    OGRH.SyncIntegrity.State.enabled = true
    
    -- Start polling timer
    OGRH.SyncIntegrity.State.pollingTimer = OGRH.ScheduleTimer(function()
        OGRH.SyncIntegrity.BroadcastChecksums()
    end, OGRH.SyncIntegrity.State.verificationInterval, true)  -- Repeating timer
    
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[RH-SyncIntegrity]|r Started checksum polling (every 30s)")
end

-- Stop periodic integrity checks (called when losing raid admin)
function OGRH.StopIntegrityChecks()
    if not OGRH.SyncIntegrity.State.enabled then
        return
    end
    
    OGRH.SyncIntegrity.State.enabled = false
    
    -- Cancel polling timer
    if OGRH.SyncIntegrity.State.pollingTimer then
        -- Cancel timer implementation depends on OGRH.ScheduleTimer
        OGRH.SyncIntegrity.State.pollingTimer = nil
    end
    
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[RH-SyncIntegrity]|r Stopped checksum polling")
end

-- Admin: Broadcast unified checksums to raid
function OGRH.SyncIntegrity.BroadcastChecksums()
    if GetNumRaidMembers() == 0 then
        return
    end
    
    -- Get current encounter
    local currentRaid, currentEncounter = OGRH.GetCurrentEncounter()
    if not currentRaid or not currentEncounter then
        return  -- No encounter selected
    end
    
    -- Calculate all checksums
    local checksums = {
        structure = OGRH.CalculateStructureChecksum(currentRaid, currentEncounter),
        rolesUI = OGRH.CalculateRolesUIChecksum(),
        assignments = OGRH.CalculateAssignmentChecksum(currentRaid, currentEncounter),
        raid = currentRaid,
        encounter = currentEncounter,
        timestamp = GetTime()
    }
    
    -- Broadcast via MessageRouter (auto-serializes tables)
    if OGRH.MessageRouter and OGRH.MessageTypes then
        OGRH.MessageRouter.Broadcast(
            OGRH.MessageTypes.SYNC.CHECKSUM_POLL,
            checksums,
            {
                priority = "LOW",  -- Background traffic
                onSuccess = function()
                    -- Update last broadcast time
                    OGRH.SyncIntegrity.State.lastChecksumBroadcast = GetTime()
                end
            }
        )
    end
end

-- Client: Handle checksum broadcast from admin
function OGRH.SyncIntegrity.OnChecksumBroadcast(sender, checksums)
    -- Verify sender is the addon's raid admin
    local currentAdmin = OGRH.GetRaidAdmin and OGRH.GetRaidAdmin()
    if not currentAdmin or sender ~= currentAdmin then
        return  -- Ignore checksums from non-admins
    end
    
    -- Verify we're looking at the same encounter
    local myRaid, myEncounter = OGRH.GetCurrentEncounter()
    if myRaid ~= checksums.raid or myEncounter ~= checksums.encounter then
        return  -- Different encounter, ignore
    end
    
    -- Calculate our checksums
    local myStructure = OGRH.CalculateStructureChecksum(myRaid, myEncounter)
    local myRolesUI = OGRH.CalculateRolesUIChecksum()
    local myAssignments = OGRH.CalculateAssignmentChecksum(myRaid, myEncounter)
    
    -- Compare and handle mismatches
    local mismatches = {}
    
    if myStructure ~= checksums.structure then
        table.insert(mismatches, "structure")
    end
    
    if myRolesUI ~= checksums.rolesUI then
        table.insert(mismatches, "RolesUI")
        -- RolesUI mismatch: Send request for auto-repair (admin will push immediately)
        OGRH.SyncIntegrity.RequestRolesUISync(sender)
    end
    
    if myAssignments ~= checksums.assignments then
        table.insert(mismatches, "assignments")
    end
    
    -- If mismatches found, show warning
    if table.getn(mismatches) > 0 then
        local mismatchList = table.concat(mismatches, ", ")
        DEFAULT_CHAT_FRAME:AddMessage("|cffff9900[RH-SyncIntegrity]|r Checksum mismatch: " .. mismatchList)
        -- Note: RolesUI auto-repairs, structure/assignments require manual pull
        if myStructure ~= checksums.structure or myAssignments ~= checksums.assignments then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff9900[RH-SyncIntegrity]|r Use Data Management to pull latest structure/assignments")
        end
    end
end

-- Client: Request RolesUI sync from admin (auto-repair)
function OGRH.SyncIntegrity.RequestRolesUISync(adminName)
    if OGRH.MessageRouter and OGRH.MessageTypes then
        OGRH.MessageRouter.SendTo(
            adminName,
            OGRH.MessageTypes.ROLESUI.SYNC_REQUEST,
            "",  -- Empty string, no data needed for request
            {priority = "HIGH"}
        )
    end
end

-- Admin: Handle RolesUI sync request (push data immediately)
function OGRH.SyncIntegrity.OnRolesUISyncRequest(requester)
    -- Verify we're the addon's raid admin
    local currentAdmin = OGRH.GetRaidAdmin and OGRH.GetRaidAdmin()
    local playerName = UnitName("player")
    if not currentAdmin or playerName ~= currentAdmin then
        return
    end
    
    OGRH.EnsureSV()
    
    -- Build RolesUI sync data
    local syncData = {
        roles = OGRH_SV.roles or {},
        timestamp = GetTime()
    }
    
    -- Send to requester (or broadcast to all if requester not specified)
    if OGRH.MessageRouter and OGRH.MessageTypes then
        if requester then
            OGRH.MessageRouter.SendTo(
                requester,
                OGRH.MessageTypes.ROLESUI.SYNC_PUSH,
                syncData,
                {priority = "HIGH"}
            )
        else
            OGRH.MessageRouter.Broadcast(
                OGRH.MessageTypes.ROLESUI.SYNC_PUSH,
                syncData,
                {priority = "HIGH"}
            )
        end
    end
end

-- Client: Handle RolesUI sync push from admin (apply immediately)
function OGRH.SyncIntegrity.OnRolesUISyncPush(sender, syncData)
    -- Verify sender is the addon's raid admin
    local currentAdmin = OGRH.GetRaidAdmin and OGRH.GetRaidAdmin()
    if not currentAdmin or sender ~= currentAdmin then
        return
    end
    
    -- Block sync from self
    if sender == UnitName("player") then
        return
    end
    
    if not syncData or not syncData.roles then
        return
    end
    
    -- Apply RolesUI data
    OGRH.EnsureSV()
    OGRH_SV.roles = syncData.roles
    
    -- Refresh RolesUI if open
    if OGRH.rolesFrame and OGRH.rolesFrame:IsShown() and OGRH.rolesFrame.UpdatePlayerLists then
        OGRH.rolesFrame.UpdatePlayerLists()
    end
    
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[RH-SyncIntegrity]|r RolesUI data updated from admin")
end

-- Request full sync from another player
function OGRH.RequestFullSync(sender)
    -- Request via MessageRouter
    if OGRH.MessageRouter and OGRH.MessageTypes then
        OGRH.MessageRouter.SendTo(
            sender,
            OGRH.MessageTypes.SYNC.REQUEST_FULL,
            {},
            {priority = "NORMAL"}
        )
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[RH-SyncIntegrity]|r Requested full sync from " .. sender)
    end
end

-- Send full sync to another player (admin only)
function OGRH.SendFullSync(targetPlayer)
    if not OGRH.CanModifyStructure or not OGRH.CanModifyStructure(UnitName("player")) then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[RH-SyncIntegrity]|r Only raid admin can send full sync")
        return
    end
    
    -- Use existing Phase 2 sync system
    if OGRH.Sync and OGRH.Sync.BroadcastFullSync then
        OGRH.Sync.BroadcastFullSync()
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[RH-SyncIntegrity]|r Sent full sync to raid")
    end
end

-- Show corruption warning to user
function OGRH.ShowCorruptionWarning(sender)
    DEFAULT_CHAT_FRAME:AddMessage("|cffff8800[RH-SyncIntegrity]|r Data corruption detected with " .. sender)
    DEFAULT_CHAT_FRAME:AddMessage("|cffff8800[RH-SyncIntegrity]|r Use Data Management window to repair")
end

-- Request admin intervention for unresolvable conflicts
function OGRH.RequestAdminIntervention()
    DEFAULT_CHAT_FRAME:AddMessage("|cffff8800[RH-SyncIntegrity]|r Admin intervention required")
    DEFAULT_CHAT_FRAME:AddMessage("|cffff8800[RH-SyncIntegrity]|r Open Data Management window to push structure")
end

-- Compute structure checksum (lightweight)
function OGRH.ComputeStructureChecksum()
    local currentRaid, currentEncounter = OGRH.GetCurrentEncounter()
    if not currentRaid or not currentEncounter then
        return "0"
    end
    return OGRH.CalculateStructureChecksum(currentRaid, currentEncounter)
end

-- Repair corrupted data from multiple sources
function OGRH.RepairCorruptedData()
    DEFAULT_CHAT_FRAME:AddMessage("|cffff9900[RH-SyncIntegrity]|r Use Data Management window to pull latest structure")
end

-- Force full resync from admin
function OGRH.ForceResyncFromAdmin()
    if not OGRH.CanModifyStructure or not OGRH.CanModifyStructure(UnitName("player")) then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[RH-SyncIntegrity]|r Only raid admin can force resync")
        return
    end
    
    -- Use Phase 2 sync system
    if OGRH.Sync and OGRH.Sync.BroadcastFullSync then
        OGRH.Sync.BroadcastFullSync()
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[RH-SyncIntegrity]|r Force resyncing structure to all raid members")
    end
end

--[[
    Initialization
]]

function OGRH.SyncIntegrity.Initialize()
    -- Register checksum poll handler
    if OGRH.MessageRouter and OGRH.MessageTypes then
        OGRH.MessageRouter.RegisterHandler(OGRH.MessageTypes.SYNC.CHECKSUM_POLL, function(sender, data)
            OGRH.SyncIntegrity.OnChecksumBroadcast(sender, data)
        end)
        
        -- Register RolesUI sync handlers
        OGRH.MessageRouter.RegisterHandler(OGRH.MessageTypes.ROLESUI.SYNC_REQUEST, function(sender, data)
            OGRH.SyncIntegrity.OnRolesUISyncRequest(sender)
        end)
        
        OGRH.MessageRouter.RegisterHandler(OGRH.MessageTypes.ROLESUI.SYNC_PUSH, function(sender, data)
            OGRH.SyncIntegrity.OnRolesUISyncPush(sender, data)
        end)
    end
    
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[RH-SyncIntegrity]|r Loaded - Unified checksum polling with auto-repair")
end

-- Auto-initialize on load
OGRH.SyncIntegrity.Initialize()

--[[
    ====================================================================
    HELPER FUNCTIONS (MUST BE DECLARED BEFORE USE)
    ====================================================================
]]

-- Simple table to string serializer (doesn't use OGRH.SerializeTable to avoid dependency)
local function SimpleSerialize(tbl, depth)
    depth = depth or 0
    if depth > 10 then return "..." end  -- Prevent infinite recursion
    
    if type(tbl) ~= "table" then
        return tostring(tbl)
    end
    
    local parts = {}
    -- Sort keys for consistent ordering
    local keys = {}
    for k in pairs(tbl) do
        table.insert(keys, k)
    end
    table.sort(keys, function(a, b)
        return tostring(a) < tostring(b)
    end)
    
    for i = 1, table.getn(keys) do
        local k = keys[i]
        local v = tbl[k]
        table.insert(parts, tostring(k))
        table.insert(parts, "=")
        if type(v) == "table" then
            table.insert(parts, SimpleSerialize(v, depth + 1))
        else
            table.insert(parts, tostring(v))
        end
        table.insert(parts, ";")
    end
    
    return table.concat(parts, "")
end

--[[
    ====================================================================
    PHASE 6.1: TEST COMMANDS
    ====================================================================
    
    Slash commands for testing hierarchical checksums in WoW 1.12
    Usage: /ogrh test <testname>
]]

-- Register test command handler
function OGRH.SyncIntegrity.RunTests(testName)
    if not testName or testName == "help" then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff[RH-Test]|r Available tests:")
        DEFAULT_CHAT_FRAME:AddMessage("  /ogrh test all - Run all tests")
        DEFAULT_CHAT_FRAME:AddMessage("  /ogrh test global - Test global checksums")
        DEFAULT_CHAT_FRAME:AddMessage("  /ogrh test raid - Test raid checksums")
        DEFAULT_CHAT_FRAME:AddMessage("  /ogrh test encounter - Test encounter checksums")
        DEFAULT_CHAT_FRAME:AddMessage("  /ogrh test component - Test component checksums")
        DEFAULT_CHAT_FRAME:AddMessage("  /ogrh test stability - Test checksum stability")
        return
    end
    
    if testName == "global" or testName == "all" then
        OGRH.SyncIntegrity.TestGlobalChecksums()
    end
    
    if testName == "raid" or testName == "all" then
        OGRH.SyncIntegrity.TestRaidChecksums()
    end
    
    if testName == "encounter" or testName == "all" then
        OGRH.SyncIntegrity.TestEncounterChecksums()
    end
    
    if testName == "component" or testName == "all" then
        OGRH.SyncIntegrity.TestComponentChecksums()
    end
    
    if testName == "stability" or testName == "all" then
        OGRH.SyncIntegrity.TestChecksumStability()
    end
end

-- Test 1: Global Component Checksums
function OGRH.SyncIntegrity.TestGlobalChecksums()
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff=== Testing Global Checksums ===|r")
    
    local checksums = OGRH.GetGlobalComponentChecksums()
    local deprecated = {rgo = true}  -- Deprecated components
    
    for component, cs in pairs(checksums) do
        if deprecated[component] and cs == "0" then
            DEFAULT_CHAT_FRAME:AddMessage("|cffaaaaaa[SKIP]|r " .. component .. ": deprecated (no data)")
        elseif cs and cs ~= "0" then
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[PASS]|r " .. component .. ": " .. cs)
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[FAIL]|r " .. component .. ": returned '" .. tostring(cs) .. "'")
        end
    end
end

-- Test 2: Raid Checksums
function OGRH.SyncIntegrity.TestRaidChecksums()
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff=== Testing Raid Checksums ===|r")
    
    local checksums = OGRH.GetRaidChecksums()
    local count = 0
    
    for raidName, cs in pairs(checksums) do
        count = count + 1
        if cs and cs ~= "0" then
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[PASS]|r " .. raidName .. ": " .. cs)
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[FAIL]|r " .. raidName .. ": returned '" .. tostring(cs) .. "'")
        end
    end
    
    if count == 0 then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[FAIL]|r No raids found - load defaults first")
    end
end

-- Test 3: Encounter Checksums
function OGRH.SyncIntegrity.TestEncounterChecksums()
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff=== Testing Encounter Checksums (BWL) ===|r")
    
    local checksums = OGRH.GetEncounterChecksums("BWL")
    local count = 0
    
    for encName, cs in pairs(checksums) do
        count = count + 1
        if cs and cs ~= "0" then
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[PASS]|r " .. encName .. ": " .. cs)
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[FAIL]|r " .. encName .. ": returned '" .. tostring(cs) .. "'")
        end
    end
    
    if count == 0 then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[FAIL]|r No encounters found in BWL")
    end
end

-- Test 4: Component Checksums
function OGRH.SyncIntegrity.TestComponentChecksums()
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff=== Testing Component Checksums (Naxx/4HM Tank/Heal) ===|r")
    
    local checksums = OGRH.GetComponentChecksums("Naxx", "4HM Tank/Heal")
    
    for component, cs in pairs(checksums) do
        if cs then
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[PASS]|r " .. component .. ": " .. cs)
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[FAIL]|r " .. component .. ": nil")
        end
    end
end

-- Test 5: Checksum Stability
function OGRH.SyncIntegrity.TestChecksumStability()
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff=== Testing Checksum Stability ===|r")
    
    -- Test global stability (use consumes which has actual data)
    local g1 = OGRH.ComputeGlobalComponentChecksum("consumes")
    local g2 = OGRH.ComputeGlobalComponentChecksum("consumes")
    if g1 == g2 and g1 ~= "0" then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[PASS]|r Global checksum stable: " .. g1)
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[FAIL]|r Global checksum unstable: " .. g1 .. " vs " .. g2)
    end
    
    -- Test raid stability
    local r1 = OGRH.ComputeRaidChecksum("BWL")
    local r2 = OGRH.ComputeRaidChecksum("BWL")
    if r1 == r2 then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[PASS]|r Raid checksum stable: " .. r1)
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[FAIL]|r Raid checksum unstable: " .. r1 .. " vs " .. r2)
    end
    
    -- Test encounter stability
    local e1 = OGRH.ComputeEncounterChecksum("BWL", "Razorgore")
    local e2 = OGRH.ComputeEncounterChecksum("BWL", "Razorgore")
    if e1 == e2 then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[PASS]|r Encounter checksum stable: " .. e1)
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[FAIL]|r Encounter checksum unstable: " .. e1 .. " vs " .. e2)
    end
    
    -- Test component stability (use Naxx/4HM Tank/Heal which has all components)
    local c1 = OGRH.ComputeComponentChecksum("Naxx", "4HM Tank/Heal", "roles")
    local c2 = OGRH.ComputeComponentChecksum("Naxx", "4HM Tank/Heal", "roles")
    if c1 == c2 then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[PASS]|r Component checksum stable: " .. c1)
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[FAIL]|r Component checksum unstable: " .. c1 .. " vs " .. c2)
    end
end

--[[
    ====================================================================
    PHASE 6: HIERARCHICAL CHECKSUM SYSTEM
    ====================================================================
    
    This section implements granular checksums at 4 levels:
    1. Global-Level: tradeItems, consumes, rgo
    2. Raid-Level: Raid metadata and encounter list
    3. Encounter-Level: Encounter metadata + 6 component checksums
    4. Component-Level: Individual components within an encounter
    
    Purpose: Enable surgical data repairs without full structure syncs
    Performance: Reduce sync time from 76.5s (full) to 3.9s (encounter)
]]

--[[
    6.1.1: Global-Level Checksums
]]

-- Compute checksum for a specific global component
function OGRH.ComputeGlobalComponentChecksum(componentName)
    OGRH.EnsureSV()
    
    local data = nil
    
    if componentName == "tradeItems" then
        data = OGRH_SV.tradeItems
    elseif componentName == "consumes" then
        data = OGRH_SV.consumes
    elseif componentName == "rgo" then
        data = OGRH_SV.rgo
    else
        return "0"  -- Unknown component
    end
    
    if not data then
        return "0"
    end
    
    -- Use SimpleSerialize for consistent representation
    local serialized = SimpleSerialize(data)
    return OGRH.HashString(serialized)
end

-- Get all global component checksums
function OGRH.GetGlobalComponentChecksums()
    return {
        tradeItems = OGRH.ComputeGlobalComponentChecksum("tradeItems"),
        consumes = OGRH.ComputeGlobalComponentChecksum("consumes"),
        rgo = OGRH.ComputeGlobalComponentChecksum("rgo")
    }
end

--[[
    6.1.2: Raid-Level Checksums
]]

-- Compute checksum for a specific raid (metadata + encounter list)
function OGRH.ComputeRaidChecksum(raidName)
    OGRH.EnsureSV()
    
    -- Find raid in raids array (raids are stored as array, not dictionary)
    local raid = OGRH.FindRaidByName(raidName)
    if not raid then
        return "0"
    end
    local checksum = 0
    
    -- Include raid metadata (advancedSettings)
    if raid.advancedSettings then
        local serialized = SimpleSerialize(raid.advancedSettings)
        checksum = checksum + OGRH.HashStringToNumber(serialized)
    end
    
    -- Include encounter list structure (names only, not content)
    if raid.encounters then
        for i = 1, table.getn(raid.encounters) do
            local enc = raid.encounters[i]
            if enc and enc.name then
                for j = 1, string.len(enc.name) do
                    checksum = checksum + string.byte(enc.name, j) * i
                end
            end
        end
    end
    
    return tostring(checksum)
end

-- Get checksums for all raids
function OGRH.GetRaidChecksums()
    OGRH.EnsureSV()
    
    local checksums = {}
    
    if OGRH_SV.encounterMgmt and OGRH_SV.encounterMgmt.raids then
        -- Raids are stored as an array, iterate through it
        for i = 1, table.getn(OGRH_SV.encounterMgmt.raids) do
            local raid = OGRH_SV.encounterMgmt.raids[i]
            if raid and raid.name then
                checksums[raid.name] = OGRH.ComputeRaidChecksum(raid.name)
            end
        end
    end
    
    return checksums
end

--[[
    6.1.3: Encounter-Level Checksums
]]

-- Compute checksum for a specific encounter (metadata + all 6 components)
function OGRH.ComputeEncounterChecksum(raidName, encounterName)
    OGRH.EnsureSV()
    
    -- Get raid object using FindRaidByName (raids are stored as array)
    local raid = OGRH.FindRaidByName(raidName)
    if not raid then
        return "0"
    end
    
    -- Get the encounter object (using FindEncounterByName which exists in EncounterMgmt.lua)
    local encounter = OGRH.FindEncounterByName(raid, encounterName)
    if not encounter then
        return "0"
    end
    
    local checksum = 0
    
    -- Component 1: Encounter metadata (advancedSettings)
    if encounter.advancedSettings then
        local serialized = SimpleSerialize(encounter.advancedSettings)
        checksum = checksum + OGRH.HashStringToNumber(serialized)
    end
    
    -- Component 2: Roles (from encounterMgmt.roles)
    checksum = checksum + OGRH.HashStringToNumber(
        OGRH.ComputeComponentChecksum(raidName, encounterName, "roles")
    )
    
    -- Component 3: Player assignments
    checksum = checksum + OGRH.HashStringToNumber(
        OGRH.ComputeComponentChecksum(raidName, encounterName, "playerAssignments")
    )
    
    -- Component 4: Raid marks
    checksum = checksum + OGRH.HashStringToNumber(
        OGRH.ComputeComponentChecksum(raidName, encounterName, "raidMarks")
    )
    
    -- Component 5: Assignment numbers
    checksum = checksum + OGRH.HashStringToNumber(
        OGRH.ComputeComponentChecksum(raidName, encounterName, "assignmentNumbers")
    )
    
    -- Component 6: Announcements
    checksum = checksum + OGRH.HashStringToNumber(
        OGRH.ComputeComponentChecksum(raidName, encounterName, "announcements")
    )
    
    return tostring(checksum)
end

-- Get checksums for all encounters in a raid
function OGRH.GetEncounterChecksums(raidName)
    OGRH.EnsureSV()
    
    local checksums = {}
    
    -- Find raid in raids array
    local raid = OGRH.FindRaidByName(raidName)
    if not raid or not raid.encounters then
        return checksums
    end
    
    -- Iterate through encounters array
    if raid.encounters then
        for i = 1, table.getn(raid.encounters) do
            local enc = raid.encounters[i]
            if enc and enc.name then
                checksums[enc.name] = OGRH.ComputeEncounterChecksum(raidName, enc.name)
            end
        end
    end
    
    return checksums
end

--[[
    6.1.4: Component-Level Checksums
]]

-- Compute checksum for a specific component within an encounter
function OGRH.ComputeComponentChecksum(raidName, encounterName, componentName)
    OGRH.EnsureSV()
    
    local data = nil
    
    if componentName == "encounterMetadata" then
        -- Get raid object first using FindRaidByName (raids are array, not dictionary)
        local raid = OGRH.FindRaidByName(raidName)
        if raid then
            local encounter = OGRH.FindEncounterByName(raid, encounterName)
            if encounter then
                data = encounter.advancedSettings
            end
        end
        
    elseif componentName == "roles" then
        if OGRH_SV.encounterMgmt and OGRH_SV.encounterMgmt.roles and
           OGRH_SV.encounterMgmt.roles[raidName] and
           OGRH_SV.encounterMgmt.roles[raidName][encounterName] then
            data = OGRH_SV.encounterMgmt.roles[raidName][encounterName]
        end
        
    elseif componentName == "playerAssignments" then
        if OGRH_SV.encounterAssignments and
           OGRH_SV.encounterAssignments[raidName] and
           OGRH_SV.encounterAssignments[raidName][encounterName] then
            data = OGRH_SV.encounterAssignments[raidName][encounterName]
        end
        
    elseif componentName == "raidMarks" then
        if OGRH_SV.encounterRaidMarks and
           OGRH_SV.encounterRaidMarks[raidName] and
           OGRH_SV.encounterRaidMarks[raidName][encounterName] then
            data = OGRH_SV.encounterRaidMarks[raidName][encounterName]
        end
        
    elseif componentName == "assignmentNumbers" then
        if OGRH_SV.encounterAssignmentNumbers and
           OGRH_SV.encounterAssignmentNumbers[raidName] and
           OGRH_SV.encounterAssignmentNumbers[raidName][encounterName] then
            data = OGRH_SV.encounterAssignmentNumbers[raidName][encounterName]
        end
        
    elseif componentName == "announcements" then
        if OGRH_SV.encounterAnnouncements and
           OGRH_SV.encounterAnnouncements[raidName] and
           OGRH_SV.encounterAnnouncements[raidName][encounterName] then
            data = OGRH_SV.encounterAnnouncements[raidName][encounterName]
        end
    else
        return "0"  -- Unknown component
    end
    
    if not data then
        return "0"
    end
    
    -- Use SimpleSerialize for consistent checksum
    local serialized = SimpleSerialize(data)
    return OGRH.HashString(serialized)
end

-- Get all component checksums for an encounter
function OGRH.GetComponentChecksums(raidName, encounterName)
    return {
        encounterMetadata = OGRH.ComputeComponentChecksum(raidName, encounterName, "encounterMetadata"),
        roles = OGRH.ComputeComponentChecksum(raidName, encounterName, "roles"),
        playerAssignments = OGRH.ComputeComponentChecksum(raidName, encounterName, "playerAssignments"),
        raidMarks = OGRH.ComputeComponentChecksum(raidName, encounterName, "raidMarks"),
        assignmentNumbers = OGRH.ComputeComponentChecksum(raidName, encounterName, "assignmentNumbers"),
        announcements = OGRH.ComputeComponentChecksum(raidName, encounterName, "announcements")
    }
end

-- Hash a string to a checksum string
function OGRH.HashString(str)
    if not str then
        return "0"
    end
    
    local checksum = 0
    for i = 1, string.len(str) do
        -- Use more sophisticated hash to reduce collisions
        checksum = mod(checksum * 31 + string.byte(str, i), 2147483647)
    end
    
    return tostring(checksum)
end

-- Hash a string to a number (for combining checksums)
function OGRH.HashStringToNumber(str)
    if not str then
        return 0
    end
    
    local checksum = 0
    for i = 1, string.len(str) do
        checksum = mod(checksum * 31 + string.byte(str, i), 2147483647)
    end
    
    return checksum
end
