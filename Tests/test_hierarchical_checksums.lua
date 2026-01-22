-- test_hierarchical_checksums.lua
-- Phase 6.1 Testing: Hierarchical Checksum System
-- Run this in-game with: /script dofile("Interface\\AddOns\\OG-RaidHelper\\Tests\\test_hierarchical_checksums.lua")

local testResults = {}
local testCount = 0
local passCount = 0
local failCount = 0

-- Helper: Run a test
local function RunTest(name, testFunc)
    testCount = testCount + 1
    local success, result = pcall(testFunc)
    
    if success and result then
        passCount = passCount + 1
        table.insert(testResults, "|cff00ff00[PASS]|r " .. name)
    else
        failCount = failCount + 1
        local errMsg = result or "Test returned false"
        table.insert(testResults, "|cffff0000[FAIL]|r " .. name .. ": " .. errMsg)
    end
end

-- Helper: Assert
local function Assert(condition, message)
    if not condition then
        error(message or "Assertion failed")
    end
    return true
end

DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff=== Phase 6.1: Hierarchical Checksum Tests ===|r")

--[[
    Test Suite 6.1.1: Global-Level Checksums
]]

RunTest("6.1.1.1: ComputeGlobalComponentChecksum - tradeItems", function()
    local cs1 = OGRH.ComputeGlobalComponentChecksum("tradeItems")
    Assert(cs1 ~= nil, "Checksum should not be nil")
    Assert(type(cs1) == "string", "Checksum should be string")
    return true
end)

RunTest("6.1.1.2: ComputeGlobalComponentChecksum - consumes", function()
    local cs1 = OGRH.ComputeGlobalComponentChecksum("consumes")
    Assert(cs1 ~= nil, "Checksum should not be nil")
    Assert(type(cs1) == "string", "Checksum should be string")
    return true
end)

RunTest("6.1.1.3: ComputeGlobalComponentChecksum - rgo", function()
    local cs1 = OGRH.ComputeGlobalComponentChecksum("rgo")
    Assert(cs1 ~= nil, "Checksum should not be nil")
    Assert(type(cs1) == "string", "Checksum should be string")
    return true
end)

RunTest("6.1.1.4: ComputeGlobalComponentChecksum - unknown component", function()
    local cs1 = OGRH.ComputeGlobalComponentChecksum("invalidComponent")
    Assert(cs1 == "0", "Unknown component should return '0'")
    return true
end)

RunTest("6.1.1.5: GetGlobalComponentChecksums - returns all", function()
    local checksums = OGRH.GetGlobalComponentChecksums()
    Assert(type(checksums) == "table", "Should return table")
    Assert(checksums.tradeItems ~= nil, "Should include tradeItems")
    Assert(checksums.consumes ~= nil, "Should include consumes")
    Assert(checksums.rgo ~= nil, "Should include rgo")
    return true
end)

RunTest("6.1.1.6: Checksum stability - same data produces same checksum", function()
    local cs1 = OGRH.ComputeGlobalComponentChecksum("rgo")
    local cs2 = OGRH.ComputeGlobalComponentChecksum("rgo")
    Assert(cs1 == cs2, "Same data must produce same checksum: " .. cs1 .. " vs " .. cs2)
    return true
end)

RunTest("6.1.1.7: Checksum sensitivity - data change changes checksum", function()
    -- Save original
    OGRH.EnsureSV()
    local originalRgo = OGRH_SV.rgo
    local cs1 = OGRH.ComputeGlobalComponentChecksum("rgo")
    
    -- Modify data
    OGRH_SV.rgo = OGRH_SV.rgo or {}
    OGRH_SV.rgo.testField = "testValue"
    local cs2 = OGRH.ComputeGlobalComponentChecksum("rgo")
    
    -- Restore original
    OGRH_SV.rgo = originalRgo
    
    Assert(cs1 ~= cs2, "Data change must change checksum")
    return true
end)

--[[
    Test Suite 6.1.2: Raid-Level Checksums
]]

RunTest("6.1.2.1: ComputeRaidChecksum - valid raid", function()
    local cs1 = OGRH.ComputeRaidChecksum("BWL")
    Assert(cs1 ~= nil, "Checksum should not be nil")
    Assert(cs1 ~= "0", "Valid raid should not return '0'")
    return true
end)

RunTest("6.1.2.2: ComputeRaidChecksum - invalid raid", function()
    local cs1 = OGRH.ComputeRaidChecksum("InvalidRaid")
    Assert(cs1 == "0", "Invalid raid should return '0'")
    return true
end)

RunTest("6.1.2.3: GetRaidChecksums - returns all raids", function()
    local checksums = OGRH.GetRaidChecksums()
    Assert(type(checksums) == "table", "Should return table")
    -- Check if BWL exists (should be in defaults)
    local foundBWL = false
    for raidName, _ in pairs(checksums) do
        if raidName == "BWL" then
            foundBWL = true
        end
    end
    Assert(foundBWL, "Should include BWL raid")
    return true
end)

RunTest("6.1.2.4: Raid checksum stability", function()
    local cs1 = OGRH.ComputeRaidChecksum("BWL")
    local cs2 = OGRH.ComputeRaidChecksum("BWL")
    Assert(cs1 == cs2, "Same raid data must produce same checksum")
    return true
end)

RunTest("6.1.2.5: Raid checksum isolation - other raids unaffected", function()
    local bwlCs1 = OGRH.ComputeRaidChecksum("BWL")
    local mcCs1 = OGRH.ComputeRaidChecksum("MC")
    
    -- These should be different (different raid content)
    Assert(bwlCs1 ~= mcCs1, "Different raids should have different checksums")
    return true
end)

--[[
    Test Suite 6.1.3: Encounter-Level Checksums
]]

RunTest("6.1.3.1: ComputeEncounterChecksum - valid encounter", function()
    -- Note: Requires OGRH.FindEncounterByName to be loaded (from EncounterMgmt.lua)
    local cs1 = OGRH.ComputeEncounterChecksum("BWL", "Razorgore")
    Assert(cs1 ~= nil, "Checksum should not be nil")
    Assert(cs1 ~= "0", "Valid encounter should not return '0'")
    return true
end)

RunTest("6.1.3.2: ComputeEncounterChecksum - invalid encounter", function()
    local cs1 = OGRH.ComputeEncounterChecksum("BWL", "InvalidEncounter")
    Assert(cs1 == "0", "Invalid encounter should return '0'")
    return true
end)

RunTest("6.1.3.3: GetEncounterChecksums - returns all encounters", function()
    local checksums = OGRH.GetEncounterChecksums("BWL")
    Assert(type(checksums) == "table", "Should return table")
    -- Check if Razorgore exists
    local foundRazorgore = false
    for encName, _ in pairs(checksums) do
        if encName == "Razorgore" then
            foundRazorgore = true
        end
    end
    Assert(foundRazorgore, "Should include Razorgore encounter")
    return true
end)

RunTest("6.1.3.4: Encounter checksum stability", function()
    local cs1 = OGRH.ComputeEncounterChecksum("BWL", "Razorgore")
    local cs2 = OGRH.ComputeEncounterChecksum("BWL", "Razorgore")
    Assert(cs1 == cs2, "Same encounter data must produce same checksum")
    return true
end)

RunTest("6.1.3.5: Encounter checksum isolation", function()
    local razCs = OGRH.ComputeEncounterChecksum("BWL", "Razorgore")
    local vaeCs = OGRH.ComputeEncounterChecksum("BWL", "Vaelastrasz")
    
    -- Different encounters should have different checksums
    Assert(razCs ~= vaeCs, "Different encounters should have different checksums")
    return true
end)

--[[
    Test Suite 6.1.4: Component-Level Checksums
]]

RunTest("6.1.4.1: ComputeComponentChecksum - roles", function()
    local cs1 = OGRH.ComputeComponentChecksum("BWL", "Razorgore", "roles")
    Assert(cs1 ~= nil, "Checksum should not be nil")
    Assert(type(cs1) == "string", "Checksum should be string")
    return true
end)

RunTest("6.1.4.2: ComputeComponentChecksum - playerAssignments", function()
    local cs1 = OGRH.ComputeComponentChecksum("BWL", "Razorgore", "playerAssignments")
    Assert(cs1 ~= nil, "Checksum should not be nil")
    return true
end)

RunTest("6.1.4.3: ComputeComponentChecksum - raidMarks", function()
    local cs1 = OGRH.ComputeComponentChecksum("BWL", "Razorgore", "raidMarks")
    Assert(cs1 ~= nil, "Checksum should not be nil")
    return true
end)

RunTest("6.1.4.4: ComputeComponentChecksum - assignmentNumbers", function()
    local cs1 = OGRH.ComputeComponentChecksum("BWL", "Razorgore", "assignmentNumbers")
    Assert(cs1 ~= nil, "Checksum should not be nil")
    return true
end)

RunTest("6.1.4.5: ComputeComponentChecksum - announcements", function()
    local cs1 = OGRH.ComputeComponentChecksum("BWL", "Razorgore", "announcements")
    Assert(cs1 ~= nil, "Checksum should not be nil")
    return true
end)

RunTest("6.1.4.6: ComputeComponentChecksum - encounterMetadata", function()
    local cs1 = OGRH.ComputeComponentChecksum("BWL", "Razorgore", "encounterMetadata")
    Assert(cs1 ~= nil, "Checksum should not be nil")
    return true
end)

RunTest("6.1.4.7: ComputeComponentChecksum - invalid component", function()
    local cs1 = OGRH.ComputeComponentChecksum("BWL", "Razorgore", "invalidComponent")
    Assert(cs1 == "0", "Invalid component should return '0'")
    return true
end)

RunTest("6.1.4.8: GetComponentChecksums - returns all 6 components", function()
    local checksums = OGRH.GetComponentChecksums("BWL", "Razorgore")
    Assert(type(checksums) == "table", "Should return table")
    Assert(checksums.encounterMetadata ~= nil, "Should include encounterMetadata")
    Assert(checksums.roles ~= nil, "Should include roles")
    Assert(checksums.playerAssignments ~= nil, "Should include playerAssignments")
    Assert(checksums.raidMarks ~= nil, "Should include raidMarks")
    Assert(checksums.assignmentNumbers ~= nil, "Should include assignmentNumbers")
    Assert(checksums.announcements ~= nil, "Should include announcements")
    return true
end)

RunTest("6.1.4.9: Component checksum stability", function()
    local cs1 = OGRH.ComputeComponentChecksum("BWL", "Razorgore", "roles")
    local cs2 = OGRH.ComputeComponentChecksum("BWL", "Razorgore", "roles")
    Assert(cs1 == cs2, "Same component data must produce same checksum")
    return true
end)

RunTest("6.1.4.10: Component checksum isolation", function()
    -- Get checksums for roles and assignments
    local rolesCs1 = OGRH.ComputeComponentChecksum("BWL", "Razorgore", "roles")
    local assignCs1 = OGRH.ComputeComponentChecksum("BWL", "Razorgore", "playerAssignments")
    
    -- Modify assignments (simulate)
    OGRH.EnsureSV()
    OGRH_SV.encounterAssignments = OGRH_SV.encounterAssignments or {}
    OGRH_SV.encounterAssignments["BWL"] = OGRH_SV.encounterAssignments["BWL"] or {}
    OGRH_SV.encounterAssignments["BWL"]["Razorgore"] = OGRH_SV.encounterAssignments["BWL"]["Razorgore"] or {}
    local originalAssign = OGRH_SV.encounterAssignments["BWL"]["Razorgore"][1]
    OGRH_SV.encounterAssignments["BWL"]["Razorgore"][1] = "TestPlayer"
    
    -- Check roles unchanged
    local rolesCs2 = OGRH.ComputeComponentChecksum("BWL", "Razorgore", "roles")
    local assignCs2 = OGRH.ComputeComponentChecksum("BWL", "Razorgore", "playerAssignments")
    
    -- Restore
    OGRH_SV.encounterAssignments["BWL"]["Razorgore"][1] = originalAssign
    
    Assert(rolesCs1 == rolesCs2, "Roles checksum should be unchanged when assignments change")
    Assert(assignCs1 ~= assignCs2, "Assignments checksum should change")
    return true
end)

--[[
    Test Suite: Helper Functions
]]

RunTest("6.1.H.1: HashString - basic functionality", function()
    local hash1 = OGRH.HashString("test")
    Assert(hash1 ~= nil, "Hash should not be nil")
    Assert(type(hash1) == "string", "Hash should be string")
    return true
end)

RunTest("6.1.H.2: HashString - stability", function()
    local hash1 = OGRH.HashString("test")
    local hash2 = OGRH.HashString("test")
    Assert(hash1 == hash2, "Same input must produce same hash")
    return true
end)

RunTest("6.1.H.3: HashString - sensitivity", function()
    local hash1 = OGRH.HashString("test")
    local hash2 = OGRH.HashString("test2")
    Assert(hash1 ~= hash2, "Different input must produce different hash")
    return true
end)

RunTest("6.1.H.4: HashStringToNumber - returns number", function()
    local hash = OGRH.HashStringToNumber("test")
    Assert(hash ~= nil, "Hash should not be nil")
    Assert(type(hash) == "number", "Hash should be number")
    return true
end)

--[[
    Print Results
]]

DEFAULT_CHAT_FRAME:AddMessage("|cff00ccff=== Test Results ===|r")
for i = 1, table.getn(testResults) do
    DEFAULT_CHAT_FRAME:AddMessage(testResults[i])
end

DEFAULT_CHAT_FRAME:AddMessage(" ")
DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ccff=== Summary: %d/%d tests passed ===|r", passCount, testCount))

if failCount > 0 then
    DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff0000FAILED: %d tests failed|r", failCount))
else
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00ALL TESTS PASSED|r")
end
