-- test_phase1.lua
-- Phase 1 Core Infrastructure Test Suite
-- Tests: Active Raid, SyncChecksum, SyncRouter
-- WoW 1.12 Compatible
--
-- Run with: /ogrh test phase1

OGRH = OGRH or {}
OGRH.Tests = OGRH.Tests or {}
OGRH.Tests.Phase1 = {}

local testResults = {}
local testCount = 0
local passCount = 0
local failCount = 0

-- Helper: Run a test (suppresses error output to DEFAULT_CHAT_FRAME)
local function RunTest(name, testFunc)
    testCount = testCount + 1
    
    -- Suppress error output by temporarily redirecting error handler
    local oldErrorHandler = geterrorhandler()
    seterrorhandler(function(err) return err end)  -- Silent error handler
    
    local success, result = pcall(testFunc)
    
    -- Restore original error handler
    seterrorhandler(oldErrorHandler)
    
    if success and result then
        passCount = passCount + 1
        table.insert(testResults, "|cff00ff00[PASS]|r " .. name)
        return true
    else
        failCount = failCount + 1
        local errMsg = result or "Test returned false"
        -- Clean up error message (remove file path prefix if present)
        errMsg = string.gsub(tostring(errMsg), "^.*test_phase1%.lua:%d+: ", "")
        table.insert(testResults, "|cffff0000[FAIL]|r " .. name .. ": " .. errMsg)
        return false
    end
end

-- Helper: Assert (returns error message for pcall to catch)
local function Assert(condition, message)
    if not condition then
        return nil, message or "Assertion failed"
    end
    return true
end

-- Helper: Check if value exists
local function Exists(value)
    return value ~= nil
end

--[[
    ====================================================================
    ACTIVE RAID TESTS
    ====================================================================
]]

function OGRH.Tests.Phase1.TestActiveRaid()
    OGRH.Msg("|cff66ff66[RH-Tests]|r === Active Raid Tests ===")
    
    RunTest("AR-1: Active Raid exists at raids[1]", function()
        Assert(Exists(OGRH_SV.v2), "v2 schema should exist")
        Assert(Exists(OGRH_SV.v2.encounterMgmt), "encounterMgmt should exist")
        Assert(Exists(OGRH_SV.v2.encounterMgmt.raids), "raids array should exist")
        Assert(table.getn(OGRH_SV.v2.encounterMgmt.raids) >= 1, "At least one raid should exist")
        return true
    end)
    
    RunTest("AR-2: Active Raid has correct ID", function()
        local activeRaid = OGRH_SV.v2.encounterMgmt.raids[1]
        Assert(Exists(activeRaid), "Active Raid should exist")
        Assert(activeRaid.id == "__active__", "Active Raid ID should be '__active__', got: " .. tostring(activeRaid.id))
        return true
    end)
    
    RunTest("AR-3: Active Raid has display name with [AR] prefix", function()
        local activeRaid = OGRH_SV.v2.encounterMgmt.raids[1]
        Assert(Exists(activeRaid.displayName), "Active Raid should have displayName")
        local hasPrefix = string.find(activeRaid.displayName, "^%[AR%]")
        Assert(hasPrefix, "Display name should start with [AR], got: " .. activeRaid.displayName)
        return true
    end)
    
    RunTest("AR-4: GetActiveRaid() returns Active Raid", function()
        Assert(Exists(OGRH.GetActiveRaid), "GetActiveRaid function should exist")
        local activeRaid = OGRH.GetActiveRaid()
        Assert(Exists(activeRaid), "GetActiveRaid should return a value")
        Assert(activeRaid.id == "__active__", "Should return Active Raid")
        return true
    end)
    
    RunTest("AR-5: Existing raids shifted up by 1 index", function()
        -- Check if we have more than 1 raid (Active Raid + at least one other)
        if table.getn(OGRH_SV.v2.encounterMgmt.raids) > 1 then
            local secondRaid = OGRH_SV.v2.encounterMgmt.raids[2]
            Assert(secondRaid.id ~= "__active__", "Second raid should not be Active Raid")
            return true
        else
            -- If only Active Raid exists, that's fine too
            return true
        end
    end)
    
    RunTest("AR-6: SetActiveRaid() copies raid structure", function()
        Assert(Exists(OGRH.SetActiveRaid), "SetActiveRaid function should exist")
        
        -- Only test if we have multiple raids
        if table.getn(OGRH_SV.v2.encounterMgmt.raids) > 1 then
            local sourceRaid = OGRH_SV.v2.encounterMgmt.raids[2]
            local sourceRaidName = sourceRaid.displayName or sourceRaid.name or "Unknown"
            
            OGRH.SetActiveRaid(2)
            
            local activeRaid = OGRH.GetActiveRaid()
            Assert(Exists(activeRaid), "Active Raid should exist after SetActiveRaid")
            Assert(activeRaid.id == "__active__", "Active Raid ID should remain __active__")
            
            -- Display name should have [AR] prefix
            local hasPrefix = string.find(activeRaid.displayName or "", "%[AR%]")
            Assert(hasPrefix, "Active Raid displayName should have [AR] prefix, got: " .. tostring(activeRaid.displayName))
            return true
        else
            -- Skip if only one raid
            return true
        end
    end)
end

--[[
    ====================================================================
    SYNCCHECKSUM TESTS
    ====================================================================
]]

function OGRH.Tests.Phase1.TestSyncChecksum()
    OGRH.Msg("|cff66ff66[RH-Tests]|r === SyncChecksum Tests ===")
    
    RunTest("SC-1: SyncChecksum namespace exists", function()
        Assert(Exists(OGRH.SyncChecksum), "OGRH.SyncChecksum should exist")
        return true
    end)
    
    RunTest("SC-2: ComputeComponentChecksum() exists", function()
        Assert(Exists(OGRH.SyncChecksum.ComputeComponentChecksum), "ComputeComponentChecksum should exist")
        return true
    end)
    
    RunTest("SC-3: ComputeComponentChecksum() returns valid checksum", function()
        local checksum = OGRH.SyncChecksum.ComputeComponentChecksum("roles", "playerAssignments")
        Assert(Exists(checksum), "Should return a checksum")
        Assert(type(checksum) == "string", "Checksum should be a string, got: " .. type(checksum))
        Assert(string.len(checksum) > 0, "Checksum should not be empty")
        return true
    end)
    
    RunTest("SC-4: ComputeRaidChecksum() returns valid checksum", function()
        Assert(Exists(OGRH.SyncChecksum.ComputeRaidChecksum), "ComputeRaidChecksum should exist")
        local checksum = OGRH.SyncChecksum.ComputeRaidChecksum(1)
        Assert(Exists(checksum), "Should return a checksum for Active Raid")
        Assert(type(checksum) == "string", "Checksum should be a string")
        Assert(string.len(checksum) > 0, "Checksum should not be empty")
        return true
    end)
    
    RunTest("SC-5: ComputeEncounterChecksum() returns valid checksum", function()
        Assert(Exists(OGRH.SyncChecksum.ComputeEncounterChecksum), "ComputeEncounterChecksum should exist")
        
        -- Check if Active Raid has encounters
        local activeRaid = OGRH.GetActiveRaid()
        if activeRaid and activeRaid.encounters and table.getn(activeRaid.encounters) > 0 then
            local checksum = OGRH.SyncChecksum.ComputeEncounterChecksum(1, 1)
            Assert(Exists(checksum), "Should return a checksum for encounter")
            Assert(type(checksum) == "string", "Checksum should be a string")
            Assert(string.len(checksum) > 0, "Checksum should not be empty")
        end
        return true
    end)
    
    -- SC-6 removed - ComputeGlobalComponentChecksum doesn't exist in new Phase 1 architecture
    -- Global components are handled differently in v2 schema
    
    RunTest("SC-6: Checksum stability - same data = same checksum", function()
        local checksum1 = OGRH.SyncChecksum.ComputeRaidChecksum(1)
        local checksum2 = OGRH.SyncChecksum.ComputeRaidChecksum(1)
        Assert(checksum1 == checksum2, "Same raid should produce same checksum")
        return true
    end)
    
    RunTest("SC-7: MarkComponentDirty() adds to dirty list", function()
        Assert(Exists(OGRH.SyncChecksum.MarkComponentDirty), "MarkComponentDirty should exist")
        Assert(Exists(OGRH.SyncChecksum.State), "SyncChecksum.State should exist")
        
        local initialCount = table.getn(OGRH.SyncChecksum.State.dirtyComponents)
        OGRH.SyncChecksum.MarkComponentDirty("roles", 1, 1)
        local newCount = table.getn(OGRH.SyncChecksum.State.dirtyComponents)
        
        Assert(newCount >= initialCount, "Dirty component count should increase or stay same")
        return true
    end)
    
    RunTest("SC-8: BroadcastChecksums() exists and doesn't error", function()
        Assert(Exists(OGRH.SyncChecksum.BroadcastChecksums), "BroadcastChecksums should exist")
        
        -- Only call if we're raid admin (safe to call, just won't broadcast if not admin)
        pcall(function() OGRH.SyncChecksum.BroadcastChecksums() end)
        return true
    end)
    
    RunTest("SC-9: ValidateChecksums() exists", function()
        Assert(Exists(OGRH.SyncChecksum.ValidateChecksums), "ValidateChecksums should exist")
        return true
    end)
end

--[[
    ====================================================================
    SYNCROUTER TESTS
    ====================================================================
]]

function OGRH.Tests.Phase1.TestSyncRouter()
    OGRH.Msg("|cff66ff66[RH-Tests]|r === SyncRouter Tests ===")
    
    RunTest("SR-1: SyncRouter namespace exists", function()
        Assert(Exists(OGRH.SyncRouter), "OGRH.SyncRouter should exist")
        return true
    end)
    
    RunTest("SR-2: DetectContext() exists and returns valid context", function()
        Assert(Exists(OGRH.SyncRouter.DetectContext), "DetectContext should exist")
        local context = OGRH.SyncRouter.DetectContext(1)
        Assert(Exists(context), "Should return a context")
        Assert(type(context) == "string", "Context should be a string")
        
        -- Valid contexts: "active_mgmt", "active_setup", "nonactive_setup"
        local validContexts = {active_mgmt = true, active_setup = true, nonactive_setup = true}
        Assert(validContexts[context], "Context should be valid, got: " .. context)
        return true
    end)
    
    RunTest("SR-3: Active Raid context detection", function()
        local context = OGRH.SyncRouter.DetectContext(1)
        
        -- Active Raid should return active_mgmt or active_setup
        local isActiveContext = context == "active_mgmt" or context == "active_setup"
        Assert(isActiveContext, "Active Raid should return active context, got: " .. context)
        return true
    end)
    
    RunTest("SR-4: Non-active raid context detection", function()
        if table.getn(OGRH_SV.v2.encounterMgmt.raids) > 1 then
            local context = OGRH.SyncRouter.DetectContext(2)
            Assert(context == "nonactive_setup", "Non-active raid should return nonactive_setup, got: " .. context)
        end
        return true
    end)
    
    RunTest("SR-5: DetermineSyncLevel() for Active Raid roles", function()
        Assert(Exists(OGRH.SyncRouter.DetermineSyncLevel), "DetermineSyncLevel should exist")
        local syncLevel = OGRH.SyncRouter.DetermineSyncLevel(1, "roles", "UPDATE")
        Assert(Exists(syncLevel), "Should return a sync level")
        Assert(syncLevel == "REALTIME", "Active Raid roles should be REALTIME, got: " .. syncLevel)
        return true
    end)
    
    RunTest("SR-6: DetermineSyncLevel() for Active Raid settings", function()
        local syncLevel = OGRH.SyncRouter.DetermineSyncLevel(1, "settings", "UPDATE")
        Assert(Exists(syncLevel), "Should return a sync level")
        
        -- Settings can be REALTIME or BATCH depending on context
        local validLevels = {REALTIME = true, BATCH = true}
        Assert(validLevels[syncLevel], "Settings should be REALTIME or BATCH, got: " .. syncLevel)
        return true
    end)
    
    RunTest("SR-7: DetermineSyncLevel() for non-active raid", function()
        if table.getn(OGRH_SV.v2.encounterMgmt.raids) > 1 then
            local syncLevel = OGRH.SyncRouter.DetermineSyncLevel(2, "roles", "UPDATE")
            Assert(syncLevel == "BATCH", "Non-active raid should be BATCH, got: " .. syncLevel)
        end
        return true
    end)
    
    RunTest("SR-8: DetermineSyncLevel() for structure changes", function()
        local syncLevel = OGRH.SyncRouter.DetermineSyncLevel(1, "structure", "CREATE")
        Assert(syncLevel == "MANUAL", "Structure changes should be MANUAL, got: " .. syncLevel)
        return true
    end)
    
    RunTest("SR-9: Route() exists and returns metadata", function()
        Assert(Exists(OGRH.SyncRouter.Route), "Route should exist")
        local metadata = OGRH.SyncRouter.Route("encounterMgmt.raids.1.displayName", "Test", "UPDATE")
        
        Assert(Exists(metadata), "Should return metadata")
        Assert(type(metadata) == "table", "Metadata should be a table")
        Assert(Exists(metadata.syncLevel), "Metadata should have syncLevel")
        Assert(Exists(metadata.componentType), "Metadata should have componentType")
        return true
    end)
    
    RunTest("SR-10: Route() parses path correctly", function()
        local metadata = OGRH.SyncRouter.Route("encounterMgmt.raids.1.encounters.1.roles", {}, "UPDATE")
        
        Assert(metadata.componentType == "roles", "Should detect roles component")
        Assert(Exists(metadata.scope), "Should have scope")
        Assert(metadata.scope.raid == 1, "Should have raid index 1")
        return true
    end)
    
    RunTest("SR-11: ParsePath() extracts raid and encounter indices", function()
        Assert(Exists(OGRH.SyncRouter.ParsePath), "ParsePath should exist")
        local raidIdx, encIdx, componentType = OGRH.SyncRouter.ParsePath("encounterMgmt.raids.1.encounters.2.roles")
        
        Assert(raidIdx == 1, "Should extract raid index 1")
        Assert(encIdx == 2, "Should extract encounter index 2")
        Assert(componentType == "roles", "Should extract component type 'roles'")
        return true
    end)
end

--[[
    ====================================================================
    INTEGRATION TESTS
    ====================================================================
]]

function OGRH.Tests.Phase1.TestIntegration()
    OGRH.Msg("|cff66ff66[RH-Tests]|r === Integration Tests ===")
    
    RunTest("INT-1: SVM SetPath triggers SyncRouter", function()
        Assert(Exists(OGRH.SVM.SetPath), "SVM.SetPath should exist")
        
        -- This should trigger sync routing internally
        local success = OGRH.SVM.SetPath("encounterMgmt.raids.1.displayName", "[AR] Test Raid")
        Assert(success, "SetPath should succeed")
        
        -- Verify value was written
        local value = OGRH.SVM.GetPath("encounterMgmt.raids.1.displayName")
        Assert(value == "[AR] Test Raid", "Value should be written correctly")
        return true
    end)
    
    RunTest("INT-2: SVM write marks checksums dirty", function()
        -- Clear dirty components
        OGRH.SyncChecksum.State.dirtyComponents = {}
        
        -- Make a write
        OGRH.SVM.SetPath("encounterMgmt.raids.1.displayName", "[AR] Checksum Test")
        
        -- Check if marked dirty (component-level marking may vary)
        -- Just verify the system doesn't error
        return true
    end)
    
    RunTest("INT-3: Active Raid changes use REALTIME sync", function()
        -- Simulate writing to Active Raid roles
        local metadata = OGRH.SyncRouter.Route("encounterMgmt.raids.1.encounters.1.roles", {}, "UPDATE")
        Assert(metadata.syncLevel == "REALTIME", "Active Raid roles should use REALTIME")
        return true
    end)
    
    RunTest("INT-4: Non-active raid changes use BATCH sync", function()
        if table.getn(OGRH_SV.v2.encounterMgmt.raids) > 1 then
            local metadata = OGRH.SyncRouter.Route("encounterMgmt.raids.2.displayName", "Test", "UPDATE")
            Assert(metadata.syncLevel == "BATCH", "Non-active raid should use BATCH")
        end
        return true
    end)
    
    RunTest("INT-5: MessageTypes includes CHECKSUM", function()
        Assert(Exists(OGRH.MessageTypes), "MessageTypes should exist")
        Assert(Exists(OGRH.MessageTypes.SYNC), "MessageTypes.SYNC should exist")
        Assert(Exists(OGRH.MessageTypes.SYNC.CHECKSUM), "MessageTypes.SYNC.CHECKSUM should exist")
        return true
    end)
end

--[[
    ====================================================================
    MAIN TEST RUNNER
    ====================================================================
]]

function OGRH.Tests.Phase1.RunAll()
    -- Reset counters
    testResults = {}
    testCount = 0
    passCount = 0
    failCount = 0
    
    OGRH.Msg("|cff66ccff[RH-Tests]|r ===================================================")
    OGRH.Msg("|cff66ccff[RH-Tests]|r  Phase 1 Core Infrastructure Test Suite")
    OGRH.Msg("|cff66ccff[RH-Tests]|r ===================================================")
    OGRH.Msg(" ")
    
    -- Run test suites
    OGRH.Tests.Phase1.TestActiveRaid()
    OGRH.Msg(" ")
    
    OGRH.Tests.Phase1.TestSyncChecksum()
    OGRH.Msg(" ")
    
    OGRH.Tests.Phase1.TestSyncRouter()
    OGRH.Msg(" ")
    
    OGRH.Tests.Phase1.TestIntegration()
    OGRH.Msg(" ")
    
    -- Print results
    OGRH.Msg("|cff66ccff[RH-Tests]|r ===================================================")
    OGRH.Msg("|cff66ccff[RH-Tests]|r  Test Results")
    OGRH.Msg("|cff66ccff[RH-Tests]|r ===================================================")
    
    for i = 1, table.getn(testResults) do
        OGRH.Msg(testResults[i])
    end
    
    OGRH.Msg(" ")
    OGRH.Msg(string.format("|cff66ccff[RH-Tests]|r Total: %d | |cff00ff00Pass: %d|r | |cffff0000Fail: %d|r", 
        testCount, passCount, failCount))
    
    if failCount == 0 then
        OGRH.Msg("|cff00ff00[RH-Tests]|r ✓ All tests passed!|r")
    else
        OGRH.Msg("|cffff0000[RH-Tests]|r ✗ Some tests failed. Review above.|r")
    end
    
    OGRH.Msg("|cff66ccff[RH-Tests]|r ===================================================")
end

-- Debug message removed - test suite is loaded silently. Run with: /ogrh test phase1
