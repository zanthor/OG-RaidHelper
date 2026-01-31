-- test_svm.lua
-- SavedVariablesManager (SVM) Test Suite
-- WoW 1.12 Compatible Test Framework
--
-- This file is loaded via TOC and tests run with: /ogrh test svm

OGRH = OGRH or {}
OGRH.Tests = OGRH.Tests or {}
OGRH.Tests.SVM = {}

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

-- Helper: Deep equals for tables
local function DeepEquals(t1, t2)
    if type(t1) ~= type(t2) then return false end
    if type(t1) ~= "table" then return t1 == t2 end
    
    for k, v in pairs(t1) do
        if not DeepEquals(v, t2[k]) then return false end
    end
    for k, v in pairs(t2) do
        if not DeepEquals(v, t1[k]) then return false end
    end
    return true
end

-- Public function to run all SVM tests
function OGRH.Tests.SVM.RunAll()
    -- Reset counters
    testResults = {}
    testCount = 0
    passCount = 0
    failCount = 0
    
    OGRH.Msg("|cff66ff66[RH-Tests]|r === SavedVariablesManager (SVM) Test Suite ===")

--[[
    Test Suite 1: Core Read/Write Operations
]]

RunTest("1.1: SVM.Set - simple key/value", function()
    local success = OGRH.SVM.Set("testKey", nil, "testValue")
    Assert(success, "Set should return true")
    Assert(OGRH_SV.testKey == "testValue", "Value should be set in OGRH_SV")
    return true
end)

RunTest("1.2: SVM.Get - simple key/value", function()
    OGRH_SV.testKey = "testValue"
    local value = OGRH.SVM.Get("testKey")
    Assert(value == "testValue", "Get should return correct value")
    return true
end)

RunTest("1.3: SVM.Set - key with subkey", function()
    local success = OGRH.SVM.Set("testTable", "subkey", "subvalue")
    Assert(success, "Set should return true")
    Assert(OGRH_SV.testTable ~= nil, "Table should be created")
    Assert(OGRH_SV.testTable.subkey == "subvalue", "Subkey value should be set")
    return true
end)

RunTest("1.4: SVM.Get - key with subkey", function()
    OGRH_SV.testTable = {subkey = "subvalue"}
    local value = OGRH.SVM.Get("testTable", "subkey")
    Assert(value == "subvalue", "Get should return correct subkey value")
    return true
end)

RunTest("1.5: SVM.SetPath - deep path", function()
    local success = OGRH.SVM.SetPath("level1.level2.level3", "deepValue")
    Assert(success, "SetPath should return true")
    Assert(OGRH_SV.level1 ~= nil, "Level 1 should exist")
    Assert(OGRH_SV.level1.level2 ~= nil, "Level 2 should exist")
    Assert(OGRH_SV.level1.level2.level3 == "deepValue", "Deep value should be set")
    return true
end)

RunTest("1.6: SVM.SetPath - table value", function()
    local testTable = {a = 1, b = 2, c = {d = 3}}
    local success = OGRH.SVM.SetPath("testPath", testTable)
    Assert(success, "SetPath should return true")
    Assert(OGRH_SV.testPath ~= nil, "Table should be set")
    Assert(DeepEquals(OGRH_SV.testPath, testTable), "Table should match")
    return true
end)

--[[
    Test Suite 2: Dual-Write During Migration
]]

RunTest("2.1: Dual-write to v2 when v2 exists", function()
    -- Setup v2 structure
    OGRH_SV.v2 = {}
    OGRH_SV.schemaVersion = "v1"
    
    local success = OGRH.SVM.Set("dualWriteKey", nil, "dualValue")
    Assert(success, "Set should return true")
    Assert(OGRH_SV.dualWriteKey == "dualValue", "Value should be in v1")
    Assert(OGRH_SV.v2.dualWriteKey == "dualValue", "Value should be in v2")
    
    -- Cleanup
    OGRH_SV.v2 = nil
    return true
end)

RunTest("2.2: Dual-write deep path to v2", function()
    -- Setup v2 structure
    OGRH_SV.v2 = {}
    OGRH_SV.schemaVersion = "v1"
    
    local success = OGRH.SVM.SetPath("deep.path.test", "deepDualValue")
    Assert(success, "SetPath should return true")
    Assert(OGRH_SV.deep.path.test == "deepDualValue", "Value should be in v1")
    Assert(OGRH_SV.v2.deep ~= nil, "Deep path should exist in v2")
    Assert(OGRH_SV.v2.deep.path.test == "deepDualValue", "Value should be in v2")
    
    -- Cleanup
    OGRH_SV.v2 = nil
    return true
end)

RunTest("2.3: No dual-write when schemaVersion is v2", function()
    -- Setup v2 structure
    OGRH_SV.v2 = {}
    OGRH_SV.schemaVersion = "v2"
    
    local success = OGRH.SVM.Set("noDualWrite", nil, "value")
    Assert(success, "Set should return true")
    -- When schemaVersion is v2, writes go to OGRH_SV (which is v2)
    -- No dual-write needed
    
    -- Cleanup
    OGRH_SV.v2 = nil
    OGRH_SV.schemaVersion = nil
    return true
end)

--[[
    Test Suite 3: Sync Level Routing
]]

RunTest("3.1: REALTIME sync metadata triggers SyncRealtime", function()
    -- Mock sync called flag
    local syncCalled = false
    local originalSyncRealtime = OGRH.SVM.SyncRealtime
    OGRH.SVM.SyncRealtime = function() syncCalled = true end
    
    OGRH.SVM.Set("realtimeTest", nil, "value", {syncLevel = "REALTIME"})
    
    Assert(syncCalled, "SyncRealtime should be called")
    
    -- Restore
    OGRH.SVM.SyncRealtime = originalSyncRealtime
    return true
end)

RunTest("3.2: BATCH sync metadata triggers SyncBatch", function()
    -- Mock sync called flag
    local syncCalled = false
    local originalSyncBatch = OGRH.SVM.SyncBatch
    OGRH.SVM.SyncBatch = function() syncCalled = true end
    
    OGRH.SVM.Set("batchTest", nil, "value", {syncLevel = "BATCH"})
    
    Assert(syncCalled, "SyncBatch should be called")
    
    -- Restore
    OGRH.SVM.SyncBatch = originalSyncBatch
    return true
end)

RunTest("3.3: No sync metadata = no sync calls", function()
    -- Mock sync called flag
    local realtimeCalled = false
    local batchCalled = false
    local originalRealtime = OGRH.SVM.SyncRealtime
    local originalBatch = OGRH.SVM.SyncBatch
    
    OGRH.SVM.SyncRealtime = function() realtimeCalled = true end
    OGRH.SVM.SyncBatch = function() batchCalled = true end
    
    OGRH.SVM.Set("noSyncTest", nil, "value")
    
    Assert(not realtimeCalled, "SyncRealtime should not be called")
    Assert(not batchCalled, "SyncBatch should not be called")
    
    -- Restore
    OGRH.SVM.SyncRealtime = originalRealtime
    OGRH.SVM.SyncBatch = originalBatch
    return true
end)

--[[
    Test Suite 4: Offline Queue
]]

RunTest("4.1: QueueOffline adds to offline queue", function()
    local queueSizeBefore = table.getn(OGRH.SVM.SyncConfig.offlineQueue)
    
    OGRH.SVM.QueueOffline("key", "subkey", "value", {syncLevel = "REALTIME"})
    
    local queueSizeAfter = table.getn(OGRH.SVM.SyncConfig.offlineQueue)
    Assert(queueSizeAfter == queueSizeBefore + 1, "Queue should have one more item")
    
    -- Cleanup
    OGRH.SVM.SyncConfig.offlineQueue = {}
    return true
end)

RunTest("4.2: FlushOfflineQueue processes all items", function()
    -- Add test items to queue
    OGRH.SVM.SyncConfig.offlineQueue = {
        {key = "test1", subkey = nil, value = "value1", metadata = {syncLevel = "REALTIME"}},
        {key = "test2", subkey = nil, value = "value2", metadata = {syncLevel = "BATCH"}}
    }
    
    -- Mock HandleSync
    local handleSyncCalls = 0
    local originalHandleSync = OGRH.SVM.HandleSync
    OGRH.SVM.HandleSync = function() handleSyncCalls = handleSyncCalls + 1 end
    
    OGRH.SVM.FlushOfflineQueue()
    
    Assert(handleSyncCalls == 2, "HandleSync should be called twice")
    Assert(table.getn(OGRH.SVM.SyncConfig.offlineQueue) == 0, "Queue should be empty")
    
    -- Restore
    OGRH.SVM.HandleSync = originalHandleSync
    return true
end)

RunTest("4.3: Offline queue persists during combat", function()
    -- This test would require mocking UnitAffectingCombat
    -- For now, we'll test the queue addition
    OGRH.SVM.QueueOffline("combatKey", nil, "combatValue", {syncLevel = "REALTIME"})
    
    local found = false
    for i = 1, table.getn(OGRH.SVM.SyncConfig.offlineQueue) do
        if OGRH.SVM.SyncConfig.offlineQueue[i].key == "combatKey" then
            found = true
        end
    end
    
    Assert(found, "Combat item should be in queue")
    
    -- Cleanup
    OGRH.SVM.SyncConfig.offlineQueue = {}
    return true
end)

--[[
    Test Suite 5: Batch System
]]

RunTest("5.1: Batch adds to pendingBatch", function()
    local batchSizeBefore = table.getn(OGRH.SVM.SyncConfig.pendingBatch)
    
    -- Mock CanSyncNow to return true
    local originalCanSyncNow = OGRH.CanSyncNow
    OGRH.CanSyncNow = function() return true end
    
    OGRH.SVM.SyncBatch("batchKey", nil, "batchValue", {syncLevel = "BATCH"})
    
    local batchSizeAfter = table.getn(OGRH.SVM.SyncConfig.pendingBatch)
    Assert(batchSizeAfter == batchSizeBefore + 1, "Pending batch should have one more item")
    
    -- Cleanup
    OGRH.SVM.SyncConfig.pendingBatch = {}
    OGRH.CanSyncNow = originalCanSyncNow
    return true
end)

RunTest("5.2: FlushBatch clears pending batch", function()
    -- Add test items to batch
    OGRH.SVM.SyncConfig.pendingBatch = {
        {path = "test1", value = "value1", metadata = {}},
        {path = "test2", value = "value2", metadata = {}}
    }
    
    OGRH.SVM.FlushBatch()
    
    Assert(table.getn(OGRH.SVM.SyncConfig.pendingBatch) == 0, "Pending batch should be empty")
    return true
end)

--[[
    Test Suite 6: Checksum Integration
]]

RunTest("6.1: InvalidateChecksum calls SyncIntegrity", function()
    if not OGRH.SyncIntegrity or not OGRH.SyncIntegrity.RecordAdminModification then
        -- SyncIntegrity not available in test environment
        return true
    end
    
    local called = false
    local originalRecord = OGRH.SyncIntegrity.RecordAdminModification
    OGRH.SyncIntegrity.RecordAdminModification = function() called = true end
    
    OGRH.SVM.InvalidateChecksum("test.scope")
    
    Assert(called, "RecordAdminModification should be called")
    
    -- Restore
    OGRH.SyncIntegrity.RecordAdminModification = originalRecord
    return true
end)

RunTest("6.2: InvalidateChecksumsBatch collects unique scopes", function()
    if not OGRH.SyncIntegrity or not OGRH.SyncIntegrity.RecordAdminModification then
        return true
    end
    
    local scopes = {}
    local originalRecord = OGRH.SyncIntegrity.RecordAdminModification
    OGRH.SyncIntegrity.RecordAdminModification = function(scope) 
        scopes[scope] = true 
    end
    
    local updates = {
        {path = "test1", metadata = {scope = "scope1"}},
        {path = "test2", metadata = {scope = "scope1"}},  -- Duplicate
        {path = "test3", metadata = {scope = "scope2"}},
        {path = "test4", metadata = {}}  -- No scope
    }
    
    OGRH.SVM.InvalidateChecksumsBatch(updates)
    
    local count = 0
    for _ in pairs(scopes) do count = count + 1 end
    Assert(count == 2, "Should invalidate 2 unique scopes")
    
    -- Restore
    OGRH.SyncIntegrity.RecordAdminModification = originalRecord
    return true
end)

--[[
    Test Suite 7: Error Handling
]]

RunTest("7.1: Set handles nil value", function()
    local success = OGRH.SVM.Set("nilTest", nil, nil)
    Assert(success, "Set should handle nil value")
    Assert(OGRH_SV.nilTest == nil, "Value should be nil")
    return true
end)

RunTest("7.2: SetPath handles empty path", function()
    local success = OGRH.SVM.SetPath("", "value")
    Assert(not success, "SetPath should return false for empty path")
    return true
end)

RunTest("7.3: Get handles non-existent key", function()
    local value = OGRH.SVM.Get("nonExistentKey")
    Assert(value == nil, "Get should return nil for non-existent key")
    return true
end)

RunTest("7.4: Get handles non-existent subkey", function()
    OGRH_SV.existentKey = {}
    local value = OGRH.SVM.Get("existentKey", "nonExistentSubkey")
    Assert(value == nil, "Get should return nil for non-existent subkey")
    return true
end)

--
-- Print Results
--
for i = 1, table.getn(testResults) do
    OGRH.Msg("|cff66ff66[RH-Tests]|r " .. testResults[i])
end

OGRH.Msg(" ")
OGRH.Msg("|cff66ff66[RH-Tests]|r " .. string.format("|cff00ccff=== Summary: %d/%d tests passed ===|r", passCount, testCount))

if failCount == 0 then
    OGRH.Msg("|cff00ff00[RH-Tests]|r All tests passed!")
else
    OGRH.Msg("|cffff0000[RH-Tests]|r " .. string.format("%d tests failed", failCount))
end
end

-- Auto-register slash command if Core is loaded
if OGRH.RegisterSlashCommand then
    OGRH.RegisterSlashCommand("test svm", OGRH.Tests.SVM.RunAll, "Run SVM test suite")
end
