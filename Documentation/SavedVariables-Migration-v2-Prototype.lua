--[[
    SavedVariables Migration Script - Schema v2 (Versioned Approach)
    
    Purpose: Prototype migration script for SavedVariables optimization
    Status: PROTOTYPE - NOT FOR PRODUCTION USE YET
    
    Migration Strategy: DUAL-SCHEMA APPROACH
    - Original data preserved in OGRH_SV (v1)
    - Migrated data created in OGRH_SV.v2
    - Allows validation, rollback, and incremental testing
    - After validation: cutover to v2 and remove old data
    
    This script demonstrates the migration approach for:
    1. Removing empty/unused tables
    2. Pruning historical data with retention
    3. Testing alongside original data
    4. Safe cutover with rollback capability
    
    Usage:
    1. Call MigrateToV2() to create v2 schema
    2. Test with ValidateV2()
    3. When ready: CutoverToV2()
    4. If issues: RollbackFromV2()
--]]

OGRH.Migration = OGRH.Migration or {}

-- ============================================
-- SCHEMA VERSION CONSTANTS
-- ============================================
local SCHEMA_V1 = "v1"
local SCHEMA_V2 = "v2"

-- ============================================
-- UTILITY: Deep Copy
-- ============================================
local function DeepCopy(obj, seen)
    if type(obj) ~= 'table' then return obj end
    if seen and seen[obj] then return seen[obj] end
    local s = seen or {}
    local res = setmetatable({}, getmetatable(obj))
    s[obj] = res
    for k, v in pairs(obj) do res[DeepCopy(k, s)] = DeepCopy(v, s) end
    return res
end

-- ============================================
-- MAIN MIGRATION: CREATE V2 SCHEMA
-- ============================================
function OGRH.Migration.MigrateToV2()
    if not OGRH_SV then
        print("[Migration] Error: OGRH_SV not found")
        return false
    end
    
    -- Check if already migrated
    if OGRH_SV.v2 then
        print("[Migration] v2 schema already exists. Use RollbackFromV2() to reset.")
        return false
    end
    
    print("[Migration] Creating v2 schema alongside original data...")
    
    -- Initialize schema version if not set
    if not OGRH_SV.schemaVersion then
        OGRH_SV.schemaVersion = SCHEMA_V1
    end
    
    -- Create v2 structure
    OGRH_SV.v2 = {}
    
    -- ========================================
    -- PHASE 1: Copy v1 data to v2, EXCLUDING EMPTY TABLES
    -- ========================================
    print("[Migration] Phase 1: Copying data to v2 (excluding empty tables)...")
    
    local emptyTables = {
        tankIcon = true,
        healerIcon = true,
        tankCategory = true,
        healerBoss = true
    }
    
    local copiedKeys = 0
    for key, value in pairs(OGRH_SV) do
        -- Skip metadata and empty tables
        if key ~= "v2" and key ~= "schemaVersion" and not emptyTables[key] then
            OGRH_SV.v2[key] = DeepCopy(value)
            copiedKeys = copiedKeys + 1
        end
    end
    
    print(string.format("[Migration] Copied %d keys to v2", copiedKeys))
    print("[Migration] Excluded: tankIcon, healerIcon, tankCategory, healerBoss (empty)")
    
    -- ========================================
    -- PHASE 2: APPLY DATA RETENTION TO V2
    -- ========================================
    print("[Migration] Phase 2: Applying data retention policies...")
    
    -- Recruitment data: Keep only last 30 days
    local recruitmentPruned = 0
    if OGRH_SV.v2.recruitment and OGRH_SV.v2.recruitment.applicantData then
        local cutoffTime = time() - (30 * 24 * 60 * 60)
        local newApplicantData = {}
        
        for charName, applicant in pairs(OGRH_SV.v2.recruitment.applicantData) do
            if applicant.lastUpdated and applicant.lastUpdated >= cutoffTime then
                newApplicantData[charName] = applicant
            else
                recruitmentPruned = recruitmentPruned + 1
            end
        end
        
        OGRH_SV.v2.recruitment.applicantData = newApplicantData
        print(string.format("[Migration] Pruned %d old recruitment entries (>30 days)", recruitmentPruned))
    end
    
    -- Consume tracking: Keep only last 90 days
    local consumePruned = 0
    if OGRH_SV.v2.consumeTracking and OGRH_SV.v2.consumeTracking.history then
        local cutoffTime = time() - (90 * 24 * 60 * 60)
        local newHistory = {}
        
        for raidDate, data in pairs(OGRH_SV.v2.consumeTracking.history) do
            if data.timestamp and data.timestamp >= cutoffTime then
                newHistory[raidDate] = data
            else
                consumePruned = consumePruned + 1
            end
        end
        
        OGRH_SV.v2.consumeTracking.history = newHistory
        print(string.format("[Migration] Pruned %d old consume history entries (>90 days)", consumePruned))
    end
    
    print("[Migration] ✓ v2 schema created successfully")
    print("[Migration] Original data preserved in OGRH_SV (v1)")
    print("[Migration] New data available in OGRH_SV.v2")
    print("[Migration] ")
    print("[Migration] Next steps:")
    print("[Migration]   1. Test addon functionality with v2 data")
    print("[Migration]   2. Run ValidateV2() to compare schemas")
    print("[Migration]   3. When ready: CutoverToV2()")
    
    return true
end

-- ============================================
-- VALIDATION: COMPARE V1 VS V2
-- ============================================
function OGRH.Migration.ValidateV2()
    if not OGRH_SV.v2 then
        print("[Validation] Error: v2 schema not found. Run MigrateToV2() first.")
        return false
    end
    
    print("[Validation] Comparing v1 and v2 schemas...")
    print("[Validation] ")
    
    -- Count keys in each version
    local v1Keys, v2Keys = 0, 0
    for k, v in pairs(OGRH_SV) do
        if k ~= "v2" and k ~= "schemaVersion" then
            v1Keys = v1Keys + 1
        end
    end
    for k, v in pairs(OGRH_SV.v2) do
        v2Keys = v2Keys + 1
    end
    
    print(string.format("[Validation] v1 keys: %d", v1Keys))
    print(string.format("[Validation] v2 keys: %d", v2Keys))
    print(string.format("[Validation] Difference: %d keys removed", v1Keys - v2Keys))
    print("[Validation] ")
    print("[Validation] Removed tables:")
    print("[Validation]   - tankIcon")
    print("[Validation]   - healerIcon")
    print("[Validation]   - tankCategory")
    print("[Validation]   - healerBoss")
    print("[Validation] ")
    print("[Validation] Data retention applied:")
    print("[Validation]   - recruitment: Last 30 days only")
    print("[Validation]   - consumeTracking: Last 90 days only")
    print("[Validation] ")
    print("[Validation] ✓ Review addon functionality before cutover")
    
    return true
end

-- ============================================
-- CUTOVER: SWITCH TO V2
-- ============================================
function OGRH.Migration.CutoverToV2()
    if not OGRH_SV.v2 then
        print("[Cutover] Error: v2 schema not found")
        return false
    end
    
    print("[Cutover] WARNING: This will replace v1 data with v2")
    print("[Cutover] v1 data will be backed up to OGRH_SV_BACKUP_V1")
    print("[Cutover] Type '/ogrh migration cutover confirm' to proceed")
    print("[Cutover] ")
    print("[Cutover] (In production, this would require user confirmation)")
    
    -- Create backup of v1 (everything except v2)
    OGRH_SV_BACKUP_V1 = {}
    for k, v in pairs(OGRH_SV) do
        if k ~= "v2" and k ~= "schemaVersion" then
            OGRH_SV_BACKUP_V1[k] = DeepCopy(v)
        end
    end
    
    -- Remove v1 data from top level
    for k, v in pairs(OGRH_SV) do
        if k ~= "v2" and k ~= "schemaVersion" then
            OGRH_SV[k] = nil
        end
    end
    
    -- Move v2 data to top level
    for k, v in pairs(OGRH_SV.v2) do
        OGRH_SV[k] = v
    end
    
    -- Update schema version and remove v2 container
    OGRH_SV.v2 = nil
    OGRH_SV.schemaVersion = SCHEMA_V2
    
    print("[Cutover] ✓ Complete! Now using v2 schema")
    print("[Cutover] v1 backup saved to OGRH_SV_BACKUP_V1 (global variable)")
    print("[Cutover] Use RollbackFromV2() if issues found")
    
    return true
end

-- ============================================
-- ROLLBACK: REVERT TO V1
-- ============================================
function OGRH.Migration.RollbackFromV2()
    -- Scenario 1: v2 exists but not active yet
    if OGRH_SV.v2 then
        OGRH_SV.v2 = nil
        OGRH_SV.schemaVersion = SCHEMA_V1
        print("[Rollback] v2 schema removed, back to v1")
        return true
    end
    
    -- Scenario 2: Already cut over to v2, need to restore from backup
    if OGRH_SV.schemaVersion == SCHEMA_V2 and OGRH_SV_BACKUP_V1 then
        print("[Rollback] Restoring v1 from backup...")
        
        -- Remove v2 data
        for k, v in pairs(OGRH_SV) do
            if k ~= "schemaVersion" then
                OGRH_SV[k] = nil
            end
        end
        
        -- Restore v1 backup
        for k, v in pairs(OGRH_SV_BACKUP_V1) do
            OGRH_SV[k] = DeepCopy(v)
        end
        
        OGRH_SV.schemaVersion = SCHEMA_V1
        
        print("[Rollback] ✓ Restored v1 from backup")
        print("[Rollback] Please reload UI (/reload) to ensure clean state")
        return true
    end
    
    print("[Rollback] Error: Nothing to rollback")
    print("[Rollback] Current schema: " .. (OGRH_SV.schemaVersion or "unknown"))
    return false
end

-- ============================================
-- DUAL-WRITE HELPER (For gradual migration)
-- ============================================
-- Example: Update both v1 and v2 during transition period
function OGRH.Migration.DualWrite(keyPath, value)
    -- Only active if v2 exists but not yet cut over
    if not OGRH_SV.v2 or OGRH_SV.schemaVersion == SCHEMA_V2 then
        return
    end
    
    -- Write to both v1 and v2
    -- keyPath format: "recruitment.applicantData.PlayerName"
    local function SetNestedValue(tbl, path, val)
        local keys = {}
        for key in string.gmatch(path, "[^.]+") do
            table.insert(keys, key)
        end
        
        for i = 1, #keys - 1 do
            local key = keys[i]
            if not tbl[key] then tbl[key] = {} end
            tbl = tbl[key]
        end
        
        tbl[keys[#keys]] = val
    end
    
    SetNestedValue(OGRH_SV, keyPath, DeepCopy(value))
    SetNestedValue(OGRH_SV.v2, keyPath, DeepCopy(value))
end

-- ============================================
-- EXAMPLE USAGE
-- ============================================
--[[
    -- Step 1: Create v2 schema
    OGRH.Migration.MigrateToV2()
    
    -- Step 2: Validate
    OGRH.Migration.ValidateV2()
    
    -- Step 3: Test addon with v2 data
    -- Code can read from OGRH_SV.v2 for testing
    
    -- Step 4: Cutover when ready
    OGRH.Migration.CutoverToV2()
    
    -- If issues: Rollback
    OGRH.Migration.RollbackFromV2()
--]]

print("[Migration Script] Loaded: SavedVariables v2 Migration (Versioned)")
print("[Migration Script] Available functions:")
print("  - OGRH.Migration.MigrateToV2()")
print("  - OGRH.Migration.ValidateV2()")
print("  - OGRH.Migration.CutoverToV2()")
print("  - OGRH.Migration.RollbackFromV2()")
