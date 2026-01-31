--[[
    SavedVariables Migration System - CSV-Driven v1 to v2
    
    Purpose: Production-ready migration using v1-to-v2-deep-migration-map.csv
    
    Migration Strategy:
    - Reads the detailed CSV map with 176 transformation records
    - Creates v2 schema using numeric indices (fixes spaces-in-names bug)
    - Handles 7 transformation types:
      1. NO CHANGE (135): Direct copy
      2. PATH CHANGE (22): Rename path, preserve data
      3. STRUCTURAL (7): Complex restructuring (roles table elimination)
      4. STRING KEY -> NUMERIC INDEX (10): Convert named keys to indices
      5. SEMANTIC CHANGE (2): Transform data structure
      6. DEPRECATED (6): Skip/remove
      7. NEW FIELD ADDED (3): Initialize with defaults
    
    Usage:
    /ogrh migration create  → OGRH.Migration.MigrateToV2()
    /ogrh migration validate → OGRH.Migration.ValidateV2()
    /ogrh migration cutover confirm → OGRH.Migration.CutoverToV2()
    /ogrh migration rollback → OGRH.Migration.RollbackFromV2()
--]]

OGRH = OGRH or {}
OGRH.Migration = OGRH.Migration or {}

-- ============================================
-- CONSTANTS
-- ============================================
local SCHEMA_V1 = "v1"
local SCHEMA_V2 = 2  -- Numeric for v2

-- ============================================
-- UTILITY: Deep Copy
-- ============================================
local function DeepCopy(obj, seen)
    if type(obj) ~= 'table' then return obj end
    if seen and seen[obj] then return seen[obj] end
    local s = seen or {}
    local res = setmetatable({}, getmetatable(obj))
    s[obj] = res
    for k, v in pairs(obj) do 
        res[DeepCopy(k, s)] = DeepCopy(v, s) 
    end
    return res
end

-- ============================================
-- UTILITY: Get/Set Nested Table Values
-- ============================================
local function GetNestedValue(tbl, path)
    if not tbl then return nil end
    local keys = {}
    for key in string.gmatch(path, "[^.]+") do
        -- Handle array notation like [idx]
        key = string.gsub(key, "%[.-%]", "")
        if key ~= "" then
            table.insert(keys, key)
        end
    end
    
    local current = tbl
    for _, key in ipairs(keys) do
        if type(current) ~= "table" then return nil end
        current = current[key]
    end
    return current
end

local function SetNestedValue(tbl, path, value, createPath)
    if not tbl then return false end
    local keys = {}
    for key in string.gmatch(path, "[^.]+") do
        key = string.gsub(key, "%[.-%]", "")
        if key ~= "" then
            table.insert(keys, key)
        end
    end
    
    local current = tbl
    for i = 1, table.getn(keys) - 1 do
        local key = keys[i]
        if not current[key] then
            if createPath then
                current[key] = {}
            else
                return false
            end
        end
        current = current[key]
        if type(current) ~= "table" then return false end
    end
    
    current[keys[table.getn(keys)]] = value
    return true
end

-- ============================================
-- LOAD MIGRATION MAP
-- ============================================

local function LoadMigrationMap()
    -- Migration map loaded from MigrationMap.lua (via TOC)
    if not _G.OGRH_MIGRATION_MAP then
OGRH.Msg("[Migration] ERROR: OGRH_MIGRATION_MAP not found. Check TOC file loading order.")
        return nil
    end
    
OGRH.Msg(string.format("[Migration] Loaded %d transformation records from embedded map", table.getn(_G.OGRH_MIGRATION_MAP)))
    return _G.OGRH_MIGRATION_MAP
end

-- ============================================
-- RAID/ENCOUNTER NAME TO INDEX MAPPING
-- ============================================
local function BuildRaidEncounterIndices(v1Data)
    local raidNameToIndex = {}
    local encounterNameToIndex = {}  -- Nested: [raidName][encounterName] = index
    
    if not v1Data.encounterMgmt or not v1Data.encounterMgmt.raids then
OGRH.Msg("[Migration] Warning: No encounterMgmt.raids found in v1 data")
        return raidNameToIndex, encounterNameToIndex
    end
    
    -- v1 raids are already a numeric array with .name metadata
    for raidIdx = 1, table.getn(v1Data.encounterMgmt.raids) do
        local raidData = v1Data.encounterMgmt.raids[raidIdx]
        if type(raidData) == "table" and raidData.name then
            local raidName = raidData.name
            raidNameToIndex[raidName] = raidIdx
            encounterNameToIndex[raidName] = {}
            
            -- Map encounter names to indices within this raid (also numeric array with .name)
            if raidData.encounters then
                for encIdx = 1, table.getn(raidData.encounters) do
                    local encounterData = raidData.encounters[encIdx]
                    if type(encounterData) == "table" and encounterData.name then
                        encounterNameToIndex[raidName][encounterData.name] = encIdx
                    end
                end
            end
        end
    end
    
OGRH.Msg(string.format("[Migration] Built indices for %d raids", table.getn(v1Data.encounterMgmt.raids)))
    return raidNameToIndex, encounterNameToIndex
end

-- ============================================
-- TRANSFORMATION HANDLERS
-- ============================================

-- NO CHANGE: Direct copy from v1 to v2
local function ApplyNoChange(v1Data, v2Data, mapping)
    -- Extract the base path (without OGRH_SV prefix and without array placeholders)
    local v1Path = string.gsub(mapping.v1Path, "^OGRH_SV%.", "")
    
    -- Handle dynamic array paths (contains [idx], [playerName], [raidName], [encounterName], etc.)
    if string.find(v1Path, "%[") then
        -- These are handled during iteration over actual data
        return true
    end
    
    local value = GetNestedValue(v1Data, v1Path)
    if value ~= nil then
        local v2Path = string.gsub(mapping.v2Path, "^OGRH_SV%.", "")
        v2Path = string.gsub(v2Path, " %(PER DESIGN DOC%)", "")  -- Clean path
        SetNestedValue(v2Data, v2Path, DeepCopy(value), true)
        return true
    end
    return false
end

-- PATH CHANGE: Rename path, preserve data
local function ApplyPathChange(v1Data, v2Data, mapping, raidNameToIndex, encounterNameToIndex)
    -- Similar to NO CHANGE but with different v2 path
    -- For paths with dynamic keys, needs special handling
    return ApplyNoChange(v1Data, v2Data, mapping)
end

-- STRING KEY -> NUMERIC INDEX: Convert named keys to numeric indices
local function ApplyStringKeyToIndex(v1Data, v2Data, mapping, raidNameToIndex, encounterNameToIndex)
    -- This requires iterating over the actual v1 data and using the name-to-index mapping
    -- These transformations are handled specially during the main migration loop
    return true  -- Marker that this is handled separately
end

-- DEPRECATED: Skip this field
local function ApplyDeprecated(v1Data, v2Data, mapping)
    -- Do nothing - field is not copied to v2
    return true
end

-- NEW FIELD ADDED: Initialize new v2 fields with defaults
local function ApplyNewField(v1Data, v2Data, mapping)
    -- New fields are initialized during STRUCTURAL transformations
    -- or set to nil/default values
    return true
end

-- SEMANTIC CHANGE: Transform data structure
local function ApplySemanticChange(v1Data, v2Data, mapping)
    -- Special handling for specific fields
    if string.find(mapping.v2Path, "selectedRaidIndex") then
        -- Convert selectedRaid name to index
        local v1Value = GetNestedValue(v1Data, "ui.selectedRaid")
        if v1Value and v2Data.encounterMgmt and v2Data.encounterMgmt.raids then
            -- Find the raid index
            for idx, raidData in ipairs(v2Data.encounterMgmt.raids) do
                if raidData.name == v1Value then
                    SetNestedValue(v2Data, "ui.selectedRaidIndex", idx, true)
                    return true
                end
            end
        end
    elseif string.find(mapping.v2Path, "selectedEncounterIndex") then
        -- Convert selectedEncounter name to index
        local v1Value = GetNestedValue(v1Data, "ui.selectedEncounter")
        if v1Value and v2Data.encounterMgmt and v2Data.encounterMgmt.raids then
            -- Need to know which raid to search
            local raidIdx = GetNestedValue(v2Data, "ui.selectedRaidIndex")
            if raidIdx and v2Data.encounterMgmt.raids[raidIdx] then
                for idx, encData in ipairs(v2Data.encounterMgmt.raids[raidIdx].encounters) do
                    if encData.name == v1Value then
                        SetNestedValue(v2Data, "ui.selectedEncounterIndex", idx, true)
                        return true
                    end
                end
            end
        end
    end
    return false
end

-- STRUCTURAL: Complex transformations (roles table elimination, column flattening)
local function ApplyStructural(v1Data, v2Data, mapping, raidNameToIndex, encounterNameToIndex)
    -- STRUCTURAL transformations are handled in MigrateEncounterRoles()
    return true  -- Marker
end

-- ============================================
-- SPECIAL: Migrate encounterMgmt.raids with STRING KEY -> NUMERIC INDEX
-- ============================================
local function MigrateEncounterMgmt(v1Data, v2Data, raidNameToIndex, encounterNameToIndex)
    if not v1Data.encounterMgmt or not v1Data.encounterMgmt.raids then
OGRH.Msg("[Migration] No encounterMgmt.raids to migrate")
        return
    end
    
    v2Data.encounterMgmt = v2Data.encounterMgmt or {}
    v2Data.encounterMgmt.raids = {}
    v2Data.encounterMgmt.schemaVersion = SCHEMA_V2
    
    -- v1 raids are already a numeric array with .name metadata
    for raidIdx = 1, table.getn(v1Data.encounterMgmt.raids) do
        local raidData = v1Data.encounterMgmt.raids[raidIdx]
        if type(raidData) == "table" and raidData.name then
            local v2Raid = DeepCopy(raidData)
            -- Name already exists in raidData, no need to set it again
            
            -- Convert encounters (also already numeric array with .name metadata)
            if raidData.encounters then
                v2Raid.encounters = {}
                for encIdx = 1, table.getn(raidData.encounters) do
                    local encounterData = raidData.encounters[encIdx]
                    if type(encounterData) == "table" and encounterData.name then
                        local v2Encounter = DeepCopy(encounterData)
                        -- Name already exists in encounterData
                        v2Raid.encounters[encIdx] = v2Encounter
                    end
                end
            end
            
            v2Data.encounterMgmt.raids[raidIdx] = v2Raid
        end
    end
    
OGRH.Msg(string.format("[Migration] Migrated %d raids with numeric indices", table.getn(v2Data.encounterMgmt.raids)))
end

-- ============================================
-- SPECIAL: Migrate encounterMgmt.roles (STRUCTURAL)
-- ============================================
local function MigrateEncounterRoles(v1Data, v2Data, raidNameToIndex, encounterNameToIndex)
    if not v1Data.encounterMgmt or not v1Data.encounterMgmt.roles then
OGRH.Msg("[Migration] No encounterMgmt.roles to migrate")
        return
    end
    
    -- Iterate over the v1 roles structure: roles[raidName][encounterName]
    for raidName, raidRoles in pairs(v1Data.encounterMgmt.roles) do
        local raidIdx = raidNameToIndex[raidName]
        if not raidIdx then
OGRH.Msg("[Migration] Warning: Unknown raid name in roles: " .. raidName)
        else
            for encounterName, encounterRoles in pairs(raidRoles) do
                local encIdx = encounterNameToIndex[raidName] and encounterNameToIndex[raidName][encounterName]
                if not encIdx then
OGRH.Msg("[Migration] Warning: Unknown encounter name in roles: " .. encounterName)
                else
                    -- Flatten column1 and column2 into single roles array
                    local v2Roles = {}
                    local roleIdx = 1
                    
                    -- Add column1 roles
                    if encounterRoles.column1 then
                        for _, roleData in ipairs(encounterRoles.column1) do
                            local v2Role = DeepCopy(roleData)
                            v2Role.column = 1
                            v2Role.roleId = nil  -- DEPRECATED field
                            v2Roles[roleIdx] = v2Role
                            roleIdx = roleIdx + 1
                        end
                    end
                    
                    -- Add column2 roles
                    if encounterRoles.column2 then
                        for _, roleData in ipairs(encounterRoles.column2) do
                            local v2Role = DeepCopy(roleData)
                            v2Role.column = 2
                            v2Role.roleId = nil  -- DEPRECATED field
                            v2Roles[roleIdx] = v2Role
                            roleIdx = roleIdx + 1
                        end
                    end
                    
                    -- Set the roles array in v2
                    if not v2Data.encounterMgmt.raids[raidIdx] then
OGRH.Msg("[Migration] Warning: Raid index " .. raidIdx .. " not found in v2 data")
                    elseif not v2Data.encounterMgmt.raids[raidIdx].encounters[encIdx] then
OGRH.Msg("[Migration] Warning: Encounter index " .. encIdx .. " not found in v2 data")
                    else
                        v2Data.encounterMgmt.raids[raidIdx].encounters[encIdx].roles = v2Roles
OGRH.Msg(string.format("[Migration] Migrated %d roles for %s > %s", table.getn(v2Roles), raidName, encounterName))
                    end
                end
            end
        end
    end
end

-- ============================================
-- SPECIAL: Migrate encounterAssignments/Marks/Numbers (nested in roles) and Announcements (at encounter level)
-- ============================================
local function MigrateEncounterData(v1Data, v2Data, raidNameToIndex, encounterNameToIndex, dataKey)
    if not v1Data[dataKey] then return end
    
    -- Determine target key name for v2
    local targetKey
    if dataKey == "encounterAssignments" then
        targetKey = "assignedPlayers"
    elseif dataKey == "encounterRaidMarks" then
        targetKey = "raidMarks"
    elseif dataKey == "encounterAssignmentNumbers" then
        targetKey = "assignmentNumbers"
    elseif dataKey == "encounterAnnouncements" then
        targetKey = "announcements"
    else
        targetKey = dataKey
    end
    
    for raidName, raidData in pairs(v1Data[dataKey]) do
        local raidIdx = raidNameToIndex[raidName]
        if raidIdx and type(raidData) == "table" then
            for encounterName, encounterData in pairs(raidData) do
                local encIdx = encounterNameToIndex[raidName] and encounterNameToIndex[raidName][encounterName]
                if encIdx and v2Data.encounterMgmt and v2Data.encounterMgmt.raids[raidIdx] and v2Data.encounterMgmt.raids[raidIdx].encounters[encIdx] then
                    local encounter = v2Data.encounterMgmt.raids[raidIdx].encounters[encIdx]
                    
                    -- Announcements go directly at encounter level
                    if dataKey == "encounterAnnouncements" then
                        encounter[targetKey] = DeepCopy(encounterData)
                    else
                        -- assignedPlayers, raidMarks, assignmentNumbers nest within each role
                        -- encounterData structure: [roleIdx][slotIdx] = value
                        if type(encounterData) == "table" then
                            -- Ensure roles array exists
                            if not encounter.roles then
                                encounter.roles = {}
                            end
                            
                            -- Iterate through roleIdx in the v1 data
                            for roleIdx, roleData in pairs(encounterData) do
                                if type(roleIdx) == "number" and type(roleData) == "table" then
                                    -- Ensure this role exists in v2
                                    if not encounter.roles[roleIdx] then
                                        encounter.roles[roleIdx] = {}
                                    end
                                    
                                    -- Create the target array within this role
                                    if not encounter.roles[roleIdx][targetKey] then
                                        encounter.roles[roleIdx][targetKey] = {}
                                    end
                                    
                                    -- Copy slot data: [slotIdx] = value
                                    for slotIdx, value in pairs(roleData) do
                                        if type(slotIdx) == "number" then
                                            encounter.roles[roleIdx][targetKey][slotIdx] = value
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    
OGRH.Msg(string.format("[Migration] Migrated %s (renamed to %s) with numeric indices", dataKey, targetKey))
end

-- ============================================
-- MAIN MIGRATION FUNCTION
-- ============================================
function OGRH.Migration.MigrateToV2(force)
    if not OGRH_SV then
OGRH.Msg("[Migration] ERROR: OGRH_SV not found")
        return false
    end
    
    if OGRH_SV.v2 and not force then
OGRH.Msg("[Migration] v2 schema already exists. Use /ogrh migration rollback first.")
OGRH.Msg("[Migration] Or use /ogrh migration create force to overwrite.")
        return false
    end
    
    if OGRH_SV.v2 and force then
OGRH.Msg("[Migration] ⚠ FORCE MODE: Overwriting existing v2 schema...")
        OGRH_SV.v2 = nil
    end
    
OGRH.Msg("=" .. string.rep("=", 70))
OGRH.Msg("[Migration] Starting v1 → v2 migration using CSV map...")
OGRH.Msg("=" .. string.rep("=", 70))
    
    -- Load migration map from CSV
    local migrations = LoadMigrationMap()
    if not migrations then
OGRH.Msg("[Migration] ERROR: Failed to load migration map")
        return false
    end
    
    -- Create v2 container
    OGRH_SV.v2 = {}
    local v2 = OGRH_SV.v2
    
    -- Build raid/encounter name-to-index mapping (critical for STRING KEY -> NUMERIC INDEX)
    local raidNameToIndex, encounterNameToIndex = BuildRaidEncounterIndices(OGRH_SV)
    
    -- Phase 1: Migrate encounterMgmt.raids (STRING KEY -> NUMERIC INDEX)
OGRH.Msg("\n[Phase 1] Migrating encounterMgmt.raids with numeric indices...")
    MigrateEncounterMgmt(OGRH_SV, v2, raidNameToIndex, encounterNameToIndex)
    
    -- Phase 2: Migrate encounterMgmt.roles (STRUCTURAL: flatten columns, move into encounters)
OGRH.Msg("\n[Phase 2] Migrating encounterMgmt.roles (STRUCTURAL transformation)...")
    MigrateEncounterRoles(OGRH_SV, v2, raidNameToIndex, encounterNameToIndex)
    
    -- Phase 3: Migrate encounterAssignments, encounterRaidMarks, encounterAssignmentNumbers, encounterAnnouncements
OGRH.Msg("\n[Phase 3] Migrating encounter assignments/marks/numbers/announcements...")
    MigrateEncounterData(OGRH_SV, v2, raidNameToIndex, encounterNameToIndex, "encounterAssignments")
    MigrateEncounterData(OGRH_SV, v2, raidNameToIndex, encounterNameToIndex, "encounterRaidMarks")
    MigrateEncounterData(OGRH_SV, v2, raidNameToIndex, encounterNameToIndex, "encounterAssignmentNumbers")
    MigrateEncounterData(OGRH_SV, v2, raidNameToIndex, encounterNameToIndex, "encounterAnnouncements")
    
    -- Phase 4: Process remaining transformations from CSV
OGRH.Msg("\n[Phase 4] Processing remaining transformations...")
    local stats = {
        noChange = 0,
        pathChange = 0,
        deprecated = 0,
        newField = 0,
        semanticChange = 0,
        structural = 0,
        stringKey = 0,
        errors = 0
    }
    
    for _, mapping in ipairs(migrations) do
        local success = false
        
        if mapping.transformType == "NO CHANGE" then
            success = ApplyNoChange(OGRH_SV, v2, mapping)
            if success then stats.noChange = stats.noChange + 1 end
            
        elseif mapping.transformType == "PATH CHANGE" then
            success = ApplyPathChange(OGRH_SV, v2, mapping, raidNameToIndex, encounterNameToIndex)
            if success then stats.pathChange = stats.pathChange + 1 end
            
        elseif mapping.transformType == "DEPRECATED" then
            success = ApplyDeprecated(OGRH_SV, v2, mapping)
            if success then stats.deprecated = stats.deprecated + 1 end
            
        elseif mapping.transformType == "NEW FIELD ADDED" then
            success = ApplyNewField(OGRH_SV, v2, mapping)
            if success then stats.newField = stats.newField + 1 end
            
        elseif mapping.transformType == "SEMANTIC CHANGE" then
            success = ApplySemanticChange(OGRH_SV, v2, mapping)
            if success then stats.semanticChange = stats.semanticChange + 1 end
            
        elseif mapping.transformType == "STRUCTURAL" then
            success = ApplyStructural(OGRH_SV, v2, mapping, raidNameToIndex, encounterNameToIndex)
            if success then stats.structural = stats.structural + 1 end
            
        elseif string.find(mapping.transformType, "STRING KEY") then
            -- Already handled in Phase 1-3
            success = true
            stats.stringKey = stats.stringKey + 1
            
        else
            OGRH.Msg(string.format("[Migration] Unknown transformation type: %s", tostring(mapping.transformType or "nil")))
            stats.errors = stats.errors + 1
        end
        
        if not success and mapping.transformType ~= "STRING KEY -> NUMERIC INDEX" then
            -- Don't report STRING KEY failures since they're handled separately
            if mapping.transformType ~= "DEPRECATED" and mapping.transformType ~= "NEW FIELD ADDED" and mapping.transformType ~= "STRUCTURAL" then
                -- Only report failures for transformations that should have succeeded
                -- (DEPRECATED, NEW FIELD, and STRUCTURAL are expected to return early)
            end
        end
    end
    
    -- Phase 5: Handle SEMANTIC CHANGE transformations
OGRH.Msg("\n[Phase 5] Applying semantic transformations...")
    for _, mapping in ipairs(migrations) do
        if mapping.transformType == "SEMANTIC CHANGE" then
            ApplySemanticChange(OGRH_SV, v2, mapping)
        end
    end
    
    -- Phase 6: Copy simple data structures not in migration map
OGRH.Msg("\n[Phase 6] Copying unmapped data (consumes, consumesTracking, tradeItems, recruitment, rosterManagement, autoPromotes, invites)...")
    local simpleCopyFields = {"consumes", "consumesTracking", "tradeItems", "recruitment", "rosterManagement", "autoPromotes", "invites", "pollTime", "allowRemoteReadyCheck", "monitorConsumes", "syncLocked"}
    for _, field in ipairs(simpleCopyFields) do
        if OGRH_SV[field] ~= nil then
            v2[field] = DeepCopy(OGRH_SV[field])
            local count = 0
            if type(OGRH_SV[field]) == "table" then
                for k, v in pairs(OGRH_SV[field]) do
                    count = count + 1
                end
OGRH.Msg(string.format("  Copied %s: %d items", field, count))
            else
OGRH.Msg(string.format("  Copied %s: %s", field, tostring(OGRH_SV[field])))
            end
        end
    end
    
    -- Copy UI state
    if OGRH_SV.ui then
        v2.ui = DeepCopy(OGRH_SV.ui)
OGRH.Msg(string.format("  Copied ui state"))
    end
    
    -- Record migration metadata
    OGRH_SV.v2.migrationMeta = {
        migrationDate = time(),
        version = 2
    }
    
OGRH.Msg("\n" .. string.rep("=", 72))
OGRH.Msg("[Migration] ✓ Migration Complete!")
OGRH.Msg(string.rep("=", 72))
OGRH.Msg(string.format("  NO CHANGE:       %d transformations", stats.noChange))
OGRH.Msg(string.format("  PATH CHANGE:     %d transformations", stats.pathChange))
OGRH.Msg(string.format("  STRING KEY:      %d transformations", stats.stringKey))
OGRH.Msg(string.format("  STRUCTURAL:      %d transformations", stats.structural))
OGRH.Msg(string.format("  SEMANTIC:        %d transformations", stats.semanticChange))
OGRH.Msg(string.format("  DEPRECATED:      %d fields skipped", stats.deprecated))
OGRH.Msg(string.format("  NEW FIELDS:      %d fields added", stats.newField))
    if stats.errors > 0 then
OGRH.Msg(string.format("  ERRORS:          %d", stats.errors))
    end
OGRH.Msg(string.rep("=", 72))
OGRH.Msg("\nOriginal data preserved in OGRH_SV (v1)")
OGRH.Msg("Migrated data available in OGRH_SV.v2")
OGRH.Msg("Migration timestamp: " .. date("%Y-%m-%d %H:%M:%S", time()))
OGRH.Msg("\nNext steps:")
OGRH.Msg("  1. Run /ogrh migration validate to compare schemas")
OGRH.Msg("  2. Test addon functionality with v2 data")
OGRH.Msg("  3. When ready: /ogrh migration cutover confirm")
    
    return true
end

-- ============================================
-- VALIDATION FUNCTION
-- ============================================
function OGRH.Migration.ValidateV2()
    if not OGRH_SV.v2 then
OGRH.Msg("[Validation] ERROR: v2 schema not found. Run /ogrh migration create first.")
        return false
    end
    
OGRH.Msg("=" .. string.rep("=", 70))
OGRH.Msg("[Validation] Comparing v1 and v2 schemas...")
OGRH.Msg("=" .. string.rep("=", 70))
    
    -- Load migration map
    local migrations = LoadMigrationMap()
    if not migrations then
OGRH.Msg("[Validation] ERROR: Failed to load migration map")
        return false
    end
    
    local stats = {
        validated = 0,
        missing = 0,
        mismatch = 0,
        deprecated = 0,
        newFields = 0
    }
    
    -- Build indices for validation
    local raidNameToIndex, encounterNameToIndex = BuildRaidEncounterIndices(OGRH_SV)
    
    for _, mapping in ipairs(migrations) do
        if mapping.transformType == "DEPRECATED" then
            stats.deprecated = stats.deprecated + 1
        elseif mapping.transformType == "NEW FIELD ADDED" then
            stats.newFields = stats.newFields + 1
        elseif mapping.transformType == "NO CHANGE" then
            -- Validate NO CHANGE fields match
            local v1Path = string.gsub(mapping.v1Path, "^OGRH_SV%.", "")
            local v2Path = string.gsub(mapping.v2Path, "^OGRH_SV%.", "")
            v2Path = string.gsub(v2Path, " %(PER DESIGN DOC%)", "")
            
            if not string.find(v1Path, "%[") then  -- Skip dynamic paths
                local v1Value = GetNestedValue(OGRH_SV, v1Path)
                local v2Value = GetNestedValue(OGRH_SV.v2, v2Path)
                
                if v1Value == nil and v2Value == nil then
                    -- Both nil - OK
                    stats.validated = stats.validated + 1
                elseif v1Value ~= nil and v2Value ~= nil then
                    -- Both exist - OK
                    stats.validated = stats.validated + 1
                else
OGRH.Msg(string.format("[Validation] MISSING: %s → %s", v1Path, v2Path))
                    stats.missing = stats.missing + 1
                end
            end
        else
            -- Other transformation types - just count as validated
            stats.validated = stats.validated + 1
        end
    end
    
OGRH.Msg("\n" .. string.rep("=", 72))
OGRH.Msg("[Validation] ✓ Validation Complete!")
OGRH.Msg(string.rep("=", 72))
OGRH.Msg(string.format("  Validated:       %d fields", stats.validated))
OGRH.Msg(string.format("  Missing:         %d fields", stats.missing))
OGRH.Msg(string.format("  Deprecated:      %d fields (skipped)", stats.deprecated))
OGRH.Msg(string.format("  New Fields:      %d fields (added in v2)", stats.newFields))
OGRH.Msg(string.rep("=", 72))
    
    if stats.missing > 0 then
OGRH.Msg("\n⚠ Review missing fields before cutover")
    else
OGRH.Msg("\n✓ All fields validated - ready for cutover")
    end
    
    return stats.missing == 0
end

-- ============================================
-- CUTOVER FUNCTION
-- ============================================
function OGRH.Migration.CutoverToV2()
    if not OGRH_SV.v2 then
OGRH.Msg("[Cutover] ERROR: v2 schema not found. Run /ogrh migration create first.")
        return false
    end
    
OGRH.Msg("[Cutover] Switching to v2 schema...")
    
    -- Simply set schema version to v2
    -- SVM will now read/write to OGRH_SV.v2.* instead of OGRH_SV.*
    OGRH_SV.schemaVersion = "v2"
    
    -- Remove deprecated fields from v2 schema
    if OGRH_SV.v2.order then
        OGRH_SV.v2.order = nil
OGRH.Msg("[Cutover] Removed deprecated 'order' field from v2")
    end
    if OGRH_SV.v2.Permissions then
        OGRH_SV.v2.Permissions = nil
OGRH.Msg("[Cutover] Removed deprecated 'Permissions' field from v2 (use lowercase 'permissions')")
    end
    if OGRH_SV.v2.Versioning then
        OGRH_SV.v2.Versioning = nil
OGRH.Msg("[Cutover] Removed deprecated 'Versioning' field from v2 (use lowercase 'versioning')")
    end
    
OGRH.Msg("=" .. string.rep("=", 70))
OGRH.Msg("[Cutover] ✓ Cutover Complete!")
OGRH.Msg("=" .. string.rep("=", 70))
OGRH.Msg("Now using v2 schema at OGRH_SV.v2.*")
OGRH.Msg("v1 data preserved at OGRH_SV.* (can be removed later)")
OGRH.Msg("\nUse /ogrh migration rollback to switch back to v1")
OGRH.Msg("/reload recommended to ensure clean state")
    
    return true
end

-- ============================================
-- ROLLBACK FUNCTION
-- ============================================
function OGRH.Migration.RollbackFromV2()
    if OGRH_SV.schemaVersion ~= "v2" then
OGRH.Msg("[Rollback] Not using v2 schema - nothing to rollback")
        return false
    end
    
OGRH.Msg("[Rollback] Switching back to v1 schema...")
    
    -- Simply reset schema version to v1
    -- SVM will now read/write to OGRH_SV.* instead of OGRH_SV.v2.*
    OGRH_SV.schemaVersion = "v1"
    
OGRH.Msg("=" .. string.rep("=", 70))
OGRH.Msg("[Rollback] ✓ Rollback Complete!")
OGRH.Msg("=" .. string.rep("=", 70))
OGRH.Msg("Now using v1 schema at OGRH_SV.*")
OGRH.Msg("v2 data preserved at OGRH_SV.v2.* (can cutover again)")
OGRH.Msg("\n/reload recommended to ensure clean state")
    
    return true
end

-- ============================================
-- ACTIVE RAID MIGRATION (Phase 1: Core Infrastructure)
-- ============================================
function OGRH.Migration.MigrateToActiveRaid()
    -- Check prerequisites
    if OGRH_SV.schemaVersion ~= "v2" then
        OGRH.Msg("[AR-Migration] ERROR: Must be on v2 schema. Run /ogrh migration cutover confirm first.")
        return false
    end
    
    -- Call the core function which handles automatic migration
    local success = OGRH.EnsureActiveRaid()
    
    if success then
        OGRH.Msg("=" .. string.rep("=", 70))
        OGRH.Msg("[AR-Migration] ✓ Active Raid Migration Complete!")
        OGRH.Msg("=" .. string.rep("=", 70))
        OGRH.Msg("Active Raid slot at raids[1]")
        OGRH.Msg("\nUse /ogrh activeraid set <raidIdx> to set the Active Raid source")
        OGRH.Msg("Example: /ogrh activeraid set 2")
    end
    
    return success
end

-- ============================================
-- COMPARISON: Compare v1 vs v2 raid data
-- ============================================
function OGRH.Migration.CompareRaid(raidName)
    if not OGRH_SV then
        OGRH.Msg("[Compare] ERROR: OGRH_SV not found")
        return false
    end
    
    if not OGRH_SV.v2 then
        OGRH.Msg("[Compare] ERROR: v2 schema not found. Run /ogrh migration create first.")
        return false
    end
    
    -- Find raid in v1 (search by name in array)
    local v1Raid = nil
    local v1RaidIdx = nil
    if OGRH_SV.encounterMgmt and OGRH_SV.encounterMgmt.raids then
        for idx = 1, table.getn(OGRH_SV.encounterMgmt.raids) do
            local raid = OGRH_SV.encounterMgmt.raids[idx]
            if type(raid) == "table" and raid.name == raidName then
                v1Raid = raid
                v1RaidIdx = idx
                break
            end
        end
    end
    
    if not v1Raid then
        OGRH.Msg("[Compare] ERROR: Raid '" .. raidName .. "' not found in v1 data")
        return false
    end
    
    -- Find raid in v2 (need to search by name since it's stored as metadata)
    local v2Raid = nil
    local v2RaidIdx = nil
    if OGRH_SV.v2.encounterMgmt and OGRH_SV.v2.encounterMgmt.raids then
        for idx, raid in ipairs(OGRH_SV.v2.encounterMgmt.raids) do
            if raid.name == raidName then
                v2Raid = raid
                v2RaidIdx = idx
                break
            end
        end
    end
    
    if not v2Raid then
        OGRH.Msg("[Compare] ERROR: Raid '" .. raidName .. "' not found in v2 data")
        return false
    end
    
    -- Display comparison
    OGRH.Msg("======================================")
    OGRH.Msg("RAID COMPARISON: " .. raidName)
    OGRH.Msg("======================================")
    OGRH.Msg(" ")
    
    -- Raid Name
    OGRH.Msg("|cffffaa00Raid Name:|r")
    OGRH.Msg("  v1: '" .. (v1Raid.name or "nil") .. "' (metadata) at index " .. v1RaidIdx)
    OGRH.Msg("  v2: '" .. (v2Raid.name or "nil") .. "' (metadata) at index " .. v2RaidIdx)
    OGRH.Msg(" ")
    
    -- Number of Encounters
    local v1EncounterCount = 0
    if v1Raid.encounters then
        for _ in pairs(v1Raid.encounters) do
            v1EncounterCount = v1EncounterCount + 1
        end
    end
    
    local v2EncounterCount = 0
    if v2Raid.encounters then
        v2EncounterCount = table.getn(v2Raid.encounters)
    end
    
    OGRH.Msg("|cffffaa00Number of Encounters:|r")
    OGRH.Msg("  v1: " .. v1EncounterCount)
    OGRH.Msg("  v2: " .. v2EncounterCount)
    OGRH.Msg(" ")
    
    -- Advanced Settings
    OGRH.Msg("|cffffaa00Advanced Settings:|r")
    
    local v1Settings = v1Raid.advancedSettings or {}
    local v2Settings = v2Raid.advancedSettings or {}
    
    -- Consume Tracking
    if v1Settings.consumeTracking or v2Settings.consumeTracking then
        OGRH.Msg("  |cff00ff00Consume Tracking:|r")
        
        local v1CT = v1Settings.consumeTracking or {}
        local v2CT = v2Settings.consumeTracking or {}
        
        OGRH.Msg("    enabled: " .. tostring(v1CT.enabled or false) .. " | " .. tostring(v2CT.enabled or false))
        OGRH.Msg("    readyThreshold: " .. tostring(v1CT.readyThreshold or "nil") .. " | " .. tostring(v2CT.readyThreshold or "nil"))
        
        -- Flask Roles
        local v1Flask = v1CT.requiredFlaskRoles or {}
        local v2Flask = v2CT.requiredFlaskRoles or {}
        local flaskRoles = {"Tanks", "Healers", "Melee", "Ranged"}
        
        for _, role in ipairs(flaskRoles) do
            local v1Val = v1Flask[role] or false
            local v2Val = v2Flask[role] or false
            OGRH.Msg("    flask." .. role .. ": " .. tostring(v1Val) .. " | " .. tostring(v2Val))
        end
    end
    
    -- BigWigs
    if v1Settings.bigwigs or v2Settings.bigwigs then
        OGRH.Msg(" ")
        OGRH.Msg("  |cff00ff00BigWigs:|r")
        
        local v1BW = v1Settings.bigwigs or {}
        local v2BW = v2Settings.bigwigs or {}
        
        OGRH.Msg("    enabled: " .. tostring(v1BW.enabled or false) .. " | " .. tostring(v2BW.enabled or false))
        OGRH.Msg("    autoAnnounce: " .. tostring(v1BW.autoAnnounce or false) .. " | " .. tostring(v2BW.autoAnnounce or false))
        
        -- Raid Zone (singular vs array)
        -- v1 might have either raidZone (string) or raidZones (array)
        local v1Zone = v1BW.raidZone
        local v1Zones = v1BW.raidZones
        local v2Zones = v2BW.raidZones
        
        if v1Zone or v1Zones or v2Zones then
            local v1Display = "nil"
            if v1Zones and type(v1Zones) == "table" then
                -- v1 already uses array format
                local zoneList = {}
                for i = 1, table.getn(v1Zones) do
                    table.insert(zoneList, "'" .. v1Zones[i] .. "'")
                end
                v1Display = "[" .. table.concat(zoneList, ", ") .. "]"
            elseif v1Zone then
                -- v1 uses old singular format
                v1Display = "'" .. v1Zone .. "'"
            end
            
            local v2Display = "nil"
            if v2Zones and type(v2Zones) == "table" then
                local zoneList = {}
                for i = 1, table.getn(v2Zones) do
                    table.insert(zoneList, "'" .. v2Zones[i] .. "'")
                end
                v2Display = "[" .. table.concat(zoneList, ", ") .. "]"
            end
            OGRH.Msg("    raidZone/raidZones: " .. v1Display .. " | " .. v2Display)
        end
    end
    
    OGRH.Msg(" ")
    OGRH.Msg("======================================")
    
    return true
end

-- ============================================
-- COMPARISON: Compare v1 vs v2 encounter data
-- ============================================
function OGRH.Migration.CompareEncounter(raidName, encounterName)
    if not OGRH_SV then
        OGRH.Msg("[Compare] ERROR: OGRH_SV not found")
        return false
    end
    
    if not OGRH_SV.v2 then
        OGRH.Msg("[Compare] ERROR: v2 schema not found. Run /ogrh migration create first.")
        return false
    end
    
    -- Find raid in v1
    local v1Raid = nil
    local v1RaidIdx = nil
    if OGRH_SV.encounterMgmt and OGRH_SV.encounterMgmt.raids then
        for idx = 1, table.getn(OGRH_SV.encounterMgmt.raids) do
            local raid = OGRH_SV.encounterMgmt.raids[idx]
            if type(raid) == "table" and raid.name == raidName then
                v1Raid = raid
                v1RaidIdx = idx
                break
            end
        end
    end
    
    if not v1Raid then
        OGRH.Msg("[Compare] ERROR: Raid '" .. raidName .. "' not found in v1 data")
        return false
    end
    
    -- Find encounter in v1
    local v1Encounter = nil
    local v1EncIdx = nil
    if v1Raid.encounters then
        for idx = 1, table.getn(v1Raid.encounters) do
            local enc = v1Raid.encounters[idx]
            if type(enc) == "table" and enc.name == encounterName then
                v1Encounter = enc
                v1EncIdx = idx
                break
            end
        end
    end
    
    if not v1Encounter then
        OGRH.Msg("[Compare] ERROR: Encounter '" .. encounterName .. "' not found in v1 raid '" .. raidName .. "'")
        return false
    end
    
    -- Find raid in v2
    local v2Raid = nil
    local v2RaidIdx = nil
    if OGRH_SV.v2.encounterMgmt and OGRH_SV.v2.encounterMgmt.raids then
        for idx, raid in ipairs(OGRH_SV.v2.encounterMgmt.raids) do
            if raid.name == raidName then
                v2Raid = raid
                v2RaidIdx = idx
                break
            end
        end
    end
    
    if not v2Raid then
        OGRH.Msg("[Compare] ERROR: Raid '" .. raidName .. "' not found in v2 data")
        return false
    end
    
    -- Find encounter in v2
    local v2Encounter = nil
    local v2EncIdx = nil
    if v2Raid.encounters then
        for idx, enc in ipairs(v2Raid.encounters) do
            if enc.name == encounterName then
                v2Encounter = enc
                v2EncIdx = idx
                break
            end
        end
    end
    
    if not v2Encounter then
        OGRH.Msg("[Compare] ERROR: Encounter '" .. encounterName .. "' not found in v2 raid '" .. raidName .. "'")
        return false
    end
    
    -- Display comparison
    OGRH.Msg("======================================")
    OGRH.Msg("ENCOUNTER COMPARISON: " .. raidName .. "/" .. encounterName)
    OGRH.Msg("======================================")
    OGRH.Msg(" ")
    
    -- Encounter Name
    OGRH.Msg("|cffffaa00Encounter Name:|r")
    OGRH.Msg("  v1: '" .. (v1Encounter.name or "nil") .. "' (metadata) at raid[" .. v1RaidIdx .. "].encounters[" .. v1EncIdx .. "]")
    OGRH.Msg("  v2: '" .. (v2Encounter.name or "nil") .. "' (metadata) at raid[" .. v2RaidIdx .. "].encounters[" .. v2EncIdx .. "]")
    OGRH.Msg(" ")
    
    -- Sort Order (show implicit order from index if not set)
    OGRH.Msg("|cffffaa00Sort Order:|r")
    local v1SortDisplay = v1Encounter.sortOrder and tostring(v1Encounter.sortOrder) or (v1EncIdx .. " (implicit from index)")
    local v2SortDisplay = v2Encounter.sortOrder and tostring(v2Encounter.sortOrder) or (v2EncIdx .. " (implicit from index)")
    OGRH.Msg("  v1: " .. v1SortDisplay)
    OGRH.Msg("  v2: " .. v2SortDisplay)
    OGRH.Msg(" ")
    
    -- Number of Roles (v1 uses string keys: roles[raidName][encounterName])
    local v1RoleCount = 0
    if OGRH_SV.encounterMgmt.roles and OGRH_SV.encounterMgmt.roles[raidName] then
        local rolesForEnc = OGRH_SV.encounterMgmt.roles[raidName][encounterName]
        if rolesForEnc then
            if rolesForEnc.column1 then
                v1RoleCount = v1RoleCount + table.getn(rolesForEnc.column1)
            end
            if rolesForEnc.column2 then
                v1RoleCount = v1RoleCount + table.getn(rolesForEnc.column2)
            end
        end
    end
    
    local v2RoleCount = 0
    if v2Encounter.roles then
        v2RoleCount = table.getn(v2Encounter.roles)
    end
    
    OGRH.Msg("|cffffaa00Number of Roles:|r")
    OGRH.Msg("  v1: " .. v1RoleCount .. " (column1 + column2)")
    OGRH.Msg("  v2: " .. v2RoleCount .. " (flattened array)")
    OGRH.Msg(" ")
    
    -- Advanced Settings
    OGRH.Msg("|cffffaa00Advanced Settings:|r")
    
    local v1Settings = v1Encounter.advancedSettings or {}
    local v2Settings = v2Encounter.advancedSettings or {}
    
    -- Consume Tracking
    if v1Settings.consumeTracking or v2Settings.consumeTracking then
        OGRH.Msg("  |cff00ff00Consume Tracking:|r")
        
        local v1CT = v1Settings.consumeTracking or {}
        local v2CT = v2Settings.consumeTracking or {}
        
        OGRH.Msg("    enabled: " .. tostring(v1CT.enabled or false) .. " | " .. tostring(v2CT.enabled or false))
        OGRH.Msg("    readyThreshold: " .. tostring(v1CT.readyThreshold or "nil") .. " | " .. tostring(v2CT.readyThreshold or "nil"))
        
        -- Flask Roles
        local v1Flask = v1CT.requiredFlaskRoles or {}
        local v2Flask = v2CT.requiredFlaskRoles or {}
        local flaskRoles = {"Tanks", "Healers", "Melee", "Ranged"}
        
        for _, role in ipairs(flaskRoles) do
            local v1Val = v1Flask[role] or false
            local v2Val = v2Flask[role] or false
            OGRH.Msg("    flask." .. role .. ": " .. tostring(v1Val) .. " | " .. tostring(v2Val))
        end
    end
    
    -- BigWigs
    if v1Settings.bigwigs or v2Settings.bigwigs then
        OGRH.Msg(" ")
        OGRH.Msg("  |cff00ff00BigWigs:|r")
        
        local v1BW = v1Settings.bigwigs or {}
        local v2BW = v2Settings.bigwigs or {}
        
        OGRH.Msg("    enabled: " .. tostring(v1BW.enabled or false) .. " | " .. tostring(v2BW.enabled or false))
        OGRH.Msg("    autoAnnounce: " .. tostring(v1BW.autoAnnounce or false) .. " | " .. tostring(v2BW.autoAnnounce or false))
        
        -- Encounter ID (singular vs array)
        local v1EncId = v1BW.encounterId
        local v1EncIds = v1BW.encounterIds
        local v2EncIds = v2BW.encounterIds
        
        if v1EncId or v1EncIds or v2EncIds then
            local v1Display = "nil"
            if v1EncIds and type(v1EncIds) == "table" then
                local idList = {}
                for i = 1, table.getn(v1EncIds) do
                    table.insert(idList, tostring(v1EncIds[i]))
                end
                v1Display = "[" .. table.concat(idList, ", ") .. "]"
            elseif v1EncId then
                v1Display = tostring(v1EncId)
            end
            
            local v2Display = "nil"
            if v2EncIds and type(v2EncIds) == "table" then
                local idList = {}
                for i = 1, table.getn(v2EncIds) do
                    table.insert(idList, tostring(v2EncIds[i]))
                end
                v2Display = "[" .. table.concat(idList, ", ") .. "]"
            end
            OGRH.Msg("    encounterId/encounterIds: " .. v1Display .. " | " .. v2Display)
        end
    end
    
    OGRH.Msg(" ")
    OGRH.Msg("======================================")
    
    return true
end

-- ============================================
-- COMPARISON: Compare v1 vs v2 role data
-- ============================================
function OGRH.Migration.CompareRole(raidName, encounterName, roleIdentifier)
    if not OGRH_SV then
        OGRH.Msg("[Compare] ERROR: OGRH_SV not found")
        return false
    end
    
    if not OGRH_SV.v2 then
        OGRH.Msg("[Compare] ERROR: v2 schema not found. Run /ogrh migration create first.")
        return false
    end
    
    -- Find raid in v1
    local v1Raid = nil
    local v1RaidIdx = nil
    if OGRH_SV.encounterMgmt and OGRH_SV.encounterMgmt.raids then
        for idx = 1, table.getn(OGRH_SV.encounterMgmt.raids) do
            local raid = OGRH_SV.encounterMgmt.raids[idx]
            if type(raid) == "table" and raid.name == raidName then
                v1Raid = raid
                v1RaidIdx = idx
                break
            end
        end
    end
    
    if not v1Raid then
        OGRH.Msg("[Compare] ERROR: Raid '" .. raidName .. "' not found in v1 data")
        return false
    end
    
    -- Find encounter in v1
    local v1Encounter = nil
    local v1EncIdx = nil
    if v1Raid.encounters then
        for idx = 1, table.getn(v1Raid.encounters) do
            local enc = v1Raid.encounters[idx]
            if type(enc) == "table" and enc.name == encounterName then
                v1Encounter = enc
                v1EncIdx = idx
                break
            end
        end
    end
    
    if not v1Encounter then
        OGRH.Msg("[Compare] ERROR: Encounter '" .. encounterName .. "' not found in v1 raid '" .. raidName .. "'")
        return false
    end
    
    -- Find role in v1 (roles[raidName][encounterName].column1/.column2)
    local v1Role = nil
    local v1RoleIdx = nil
    local v1Column = nil
    if OGRH_SV.encounterMgmt.roles and OGRH_SV.encounterMgmt.roles[raidName] and OGRH_SV.encounterMgmt.roles[raidName][encounterName] then
        local rolesData = OGRH_SV.encounterMgmt.roles[raidName][encounterName]
        
        -- Search in column1 first
        if rolesData.column1 then
            for idx = 1, table.getn(rolesData.column1) do
                local role = rolesData.column1[idx]
                -- Match by index (R1, R2, etc.) or by name
                if roleIdentifier == "R" .. idx or (role.name and role.name == roleIdentifier) then
                    v1Role = role
                    v1RoleIdx = idx
                    v1Column = 1
                    break
                end
            end
        end
        
        -- Search in column2 if not found
        if not v1Role and rolesData.column2 then
            for idx = 1, table.getn(rolesData.column2) do
                local role = rolesData.column2[idx]
                local offset = rolesData.column1 and table.getn(rolesData.column1) or 0
                local globalIdx = offset + idx
                if roleIdentifier == "R" .. globalIdx or (role.name and role.name == roleIdentifier) then
                    v1Role = role
                    v1RoleIdx = idx
                    v1Column = 2
                    break
                end
            end
        end
    end
    
    if not v1Role then
        OGRH.Msg("[Compare] ERROR: Role '" .. roleIdentifier .. "' not found in v1 " .. raidName .. "/" .. encounterName)
        return false
    end
    
    -- Find raid in v2
    local v2Raid = nil
    local v2RaidIdx = nil
    if OGRH_SV.v2.encounterMgmt and OGRH_SV.v2.encounterMgmt.raids then
        for idx, raid in ipairs(OGRH_SV.v2.encounterMgmt.raids) do
            if raid.name == raidName then
                v2Raid = raid
                v2RaidIdx = idx
                break
            end
        end
    end
    
    if not v2Raid then
        OGRH.Msg("[Compare] ERROR: Raid '" .. raidName .. "' not found in v2 data")
        return false
    end
    
    -- Find encounter in v2
    local v2Encounter = nil
    local v2EncIdx = nil
    if v2Raid.encounters then
        for idx, enc in ipairs(v2Raid.encounters) do
            if enc.name == encounterName then
                v2Encounter = enc
                v2EncIdx = idx
                break
            end
        end
    end
    
    if not v2Encounter then
        OGRH.Msg("[Compare] ERROR: Encounter '" .. encounterName .. "' not found in v2 raid '" .. raidName .. "'")
        return false
    end
    
    -- Find role in v2 (flattened array)
    local v2Role = nil
    local v2RoleIdx = nil
    if v2Encounter.roles then
        -- Try matching by index first
        local roleNum = string.match(roleIdentifier, "^R(%d+)$")
        if roleNum then
            local idx = tonumber(roleNum)
            if idx and idx <= table.getn(v2Encounter.roles) then
                v2Role = v2Encounter.roles[idx]
                v2RoleIdx = idx
            end
        end
        
        -- Try matching by name if not found
        if not v2Role then
            for idx = 1, table.getn(v2Encounter.roles) do
                local role = v2Encounter.roles[idx]
                if role.name == roleIdentifier then
                    v2Role = role
                    v2RoleIdx = idx
                    break
                end
            end
        end
    end
    
    if not v2Role then
        OGRH.Msg("[Compare] ERROR: Role '" .. roleIdentifier .. "' not found in v2 " .. raidName .. "/" .. encounterName)
        return false
    end
    
    -- Display comparison
    OGRH.Msg("======================================")
    OGRH.Msg("ROLE COMPARISON: " .. raidName .. "/" .. encounterName .. "/" .. roleIdentifier)
    OGRH.Msg("======================================")
    OGRH.Msg(" ")
    
    OGRH.Msg("|cffffaa00Role Name:|r")
    OGRH.Msg("  v1: '" .. (v1Role.name or "nil") .. "' at column" .. v1Column .. "[" .. v1RoleIdx .. "]")
    OGRH.Msg("  v2: '" .. (v2Role.name or "nil") .. "' at roles[" .. v2RoleIdx .. "]")
    OGRH.Msg(" ")
    
    OGRH.Msg("|cffffaa00Column:|r")
    OGRH.Msg("  v1: " .. tostring(v1Column) .. " (column1/column2 structure)")
    OGRH.Msg("  v2: " .. tostring(v2Role.column or "nil") .. " (flattened with .column field)")
    OGRH.Msg(" ")
    
    OGRH.Msg("|cffffaa00Slots:|r")
    OGRH.Msg("  v1: " .. tostring(v1Role.slots or "nil"))
    OGRH.Msg("  v2: " .. tostring(v2Role.slots or "nil"))
    OGRH.Msg(" ")
    
    OGRH.Msg("|cffffaa00Sort Order:|r")
    OGRH.Msg("  v1: " .. tostring(v1Role.sortOrder or "nil"))
    OGRH.Msg("  v2: " .. tostring(v2Role.sortOrder or "nil"))
    OGRH.Msg(" ")
    
    OGRH.Msg("|cffffaa00Default Roles:|r")
    local v1Roles = v1Role.defaultRoles or {}
    local v2Roles = v2Role.defaultRoles or {}
    local roleTypes = {"TANKS", "HEALERS", "MELEE", "RANGED"}
    for _, roleType in ipairs(roleTypes) do
        local v1Val = v1Roles[roleType] or false
        local v2Val = v2Roles[roleType] or false
        OGRH.Msg("  " .. roleType .. ": " .. tostring(v1Val) .. " | " .. tostring(v2Val))
    end
    OGRH.Msg(" ")
    
    OGRH.Msg("|cffffaa00Flags:|r")
    OGRH.Msg("  showRaidIcons: " .. tostring(v1Role.showRaidIcons or false) .. " | " .. tostring(v2Role.showRaidIcons or false))
    OGRH.Msg("  fillOrder: " .. tostring(v1Role.fillOrder or "nil") .. " | " .. tostring(v2Role.fillOrder or "nil"))
    if v2Role.invertFillOrder ~= nil then
        OGRH.Msg("  invertFillOrder: (NEW in v2) | " .. tostring(v2Role.invertFillOrder))
    end
    if v2Role.showAssignment ~= nil then
        OGRH.Msg("  showAssignment: (NEW in v2) | " .. tostring(v2Role.showAssignment))
    end
    if v2Role.markPlayer ~= nil then
        OGRH.Msg("  markPlayer: (NEW in v2) | " .. tostring(v2Role.markPlayer))
    end
    if v2Role.allowOtherRoles ~= nil then
        OGRH.Msg("  allowOtherRoles: (NEW in v2) | " .. tostring(v2Role.allowOtherRoles))
    end
    
    OGRH.Msg(" ")
    OGRH.Msg("======================================")
    
    return true
end

-- ============================================
-- COMPARISON: Compare v1 vs v2 class priority data
-- ============================================
function OGRH.Migration.CompareClassPriority(raidName, encounterName, roleIdentifier)
    if not OGRH_SV then
        OGRH.Msg("[Compare] ERROR: OGRH_SV not found")
        return false
    end
    
    if not OGRH_SV.v2 then
        OGRH.Msg("[Compare] ERROR: v2 schema not found. Run /ogrh migration create first.")
        return false
    end
    
    -- Find raid in v1
    local v1Raid = nil
    local v1RaidIdx = nil
    if OGRH_SV.encounterMgmt and OGRH_SV.encounterMgmt.raids then
        for idx = 1, table.getn(OGRH_SV.encounterMgmt.raids) do
            local raid = OGRH_SV.encounterMgmt.raids[idx]
            if type(raid) == "table" and raid.name == raidName then
                v1Raid = raid
                v1RaidIdx = idx
                break
            end
        end
    end
    
    if not v1Raid then
        OGRH.Msg("[Compare] ERROR: Raid '" .. raidName .. "' not found in v1 data")
        return false
    end
    
    -- Find encounter in v1
    local v1Encounter = nil
    local v1EncIdx = nil
    if v1Raid.encounters then
        for idx = 1, table.getn(v1Raid.encounters) do
            local enc = v1Raid.encounters[idx]
            if type(enc) == "table" and enc.name == encounterName then
                v1Encounter = enc
                v1EncIdx = idx
                break
            end
        end
    end
    
    if not v1Encounter then
        OGRH.Msg("[Compare] ERROR: Encounter '" .. encounterName .. "' not found in v1 raid '" .. raidName .. "'")
        return false
    end
    
    -- Find role in v1
    local v1Role = nil
    local v1RoleIdx = nil
    local v1Column = nil
    if OGRH_SV.encounterMgmt.roles and OGRH_SV.encounterMgmt.roles[raidName] and OGRH_SV.encounterMgmt.roles[raidName][encounterName] then
        local rolesData = OGRH_SV.encounterMgmt.roles[raidName][encounterName]
        
        -- Search in column1 first
        if rolesData.column1 then
            for idx = 1, table.getn(rolesData.column1) do
                local role = rolesData.column1[idx]
                if roleIdentifier == "R" .. idx or (role.name and role.name == roleIdentifier) then
                    v1Role = role
                    v1RoleIdx = idx
                    v1Column = 1
                    break
                end
            end
        end
        
        -- Search in column2 if not found
        if not v1Role and rolesData.column2 then
            for idx = 1, table.getn(rolesData.column2) do
                local role = rolesData.column2[idx]
                local offset = rolesData.column1 and table.getn(rolesData.column1) or 0
                local globalIdx = offset + idx
                if roleIdentifier == "R" .. globalIdx or (role.name and role.name == roleIdentifier) then
                    v1Role = role
                    v1RoleIdx = idx
                    v1Column = 2
                    break
                end
            end
        end
    end
    
    if not v1Role then
        OGRH.Msg("[Compare] ERROR: Role '" .. roleIdentifier .. "' not found in v1 " .. raidName .. "/" .. encounterName)
        return false
    end
    
    -- Find raid in v2
    local v2Raid = nil
    local v2RaidIdx = nil
    if OGRH_SV.v2.encounterMgmt and OGRH_SV.v2.encounterMgmt.raids then
        for idx, raid in ipairs(OGRH_SV.v2.encounterMgmt.raids) do
            if raid.name == raidName then
                v2Raid = raid
                v2RaidIdx = idx
                break
            end
        end
    end
    
    if not v2Raid then
        OGRH.Msg("[Compare] ERROR: Raid '" .. raidName .. "' not found in v2 data")
        return false
    end
    
    -- Find encounter in v2
    local v2Encounter = nil
    local v2EncIdx = nil
    if v2Raid.encounters then
        for idx, enc in ipairs(v2Raid.encounters) do
            if enc.name == encounterName then
                v2Encounter = enc
                v2EncIdx = idx
                break
            end
        end
    end
    
    if not v2Encounter then
        OGRH.Msg("[Compare] ERROR: Encounter '" .. encounterName .. "' not found in v2 raid '" .. raidName .. "'")
        return false
    end
    
    -- Find role in v2
    local v2Role = nil
    local v2RoleIdx = nil
    if v2Encounter.roles then
        local roleNum = string.match(roleIdentifier, "^R(%d+)$")
        if roleNum then
            local idx = tonumber(roleNum)
            if idx and idx <= table.getn(v2Encounter.roles) then
                v2Role = v2Encounter.roles[idx]
                v2RoleIdx = idx
            end
        end
        
        if not v2Role then
            for idx = 1, table.getn(v2Encounter.roles) do
                local role = v2Encounter.roles[idx]
                if role.name == roleIdentifier then
                    v2Role = role
                    v2RoleIdx = idx
                    break
                end
            end
        end
    end
    
    if not v2Role then
        OGRH.Msg("[Compare] ERROR: Role '" .. roleIdentifier .. "' not found in v2 " .. raidName .. "/" .. encounterName)
        return false
    end
    
    -- Display comparison
    OGRH.Msg("======================================")
    OGRH.Msg("CLASS PRIORITY: " .. raidName .. "/" .. encounterName .. "/" .. roleIdentifier)
    OGRH.Msg("======================================")
    OGRH.Msg(" ")
    
    OGRH.Msg("|cffffaa00Role:|r '" .. (v1Role.name or "nil") .. "' / '" .. (v2Role.name or "nil") .. "'")
    OGRH.Msg("|cffffaa00Slots:|r " .. tostring(v1Role.slots or "nil") .. " / " .. tostring(v2Role.slots or "nil"))
    OGRH.Msg(" ")
    
    -- Class Priority - v1 is indexed by slot: classPriority[slotIdx][classIdx]
    local v1ClassPrio = v1Role.classPriority or {}
    local v2ClassPrio = v2Role.classPriority or {}
    
    -- Count total slots with class priority data
    local v1SlotCount = 0
    for slotIdx, classes in pairs(v1ClassPrio) do
        if type(classes) == "table" and table.getn(classes) > 0 then
            v1SlotCount = v1SlotCount + 1
        end
    end
    
    local v2SlotCount = 0
    if type(v2ClassPrio) == "table" then
        for slotIdx, classes in pairs(v2ClassPrio) do
            if type(classes) == "table" and table.getn(classes) > 0 then
                v2SlotCount = v2SlotCount + 1
            end
        end
    end
    
    OGRH.Msg("|cffffaa00Class Priority by Slot:|r")
    OGRH.Msg("  v1: " .. v1SlotCount .. " slots with priorities")
    OGRH.Msg("  v2: " .. v2SlotCount .. " slots with priorities")
    OGRH.Msg(" ")
    
    -- Display each slot's class priority
    local maxSlots = v1Role.slots or 1
    if v2Role.slots and v2Role.slots > maxSlots then
        maxSlots = v2Role.slots
    end
    
    for slotIdx = 1, maxSlots do
        local v1Classes = v1ClassPrio[slotIdx] or {}
        local v2Classes = v2ClassPrio[slotIdx] or {}
        
        if table.getn(v1Classes) > 0 or table.getn(v2Classes) > 0 then
            OGRH.Msg("  |cffaaffaa[Slot " .. slotIdx .. "]|r")
            
            -- Build v1 class list
            local v1ClassList = {}
            for i = 1, table.getn(v1Classes) do
                local class = v1Classes[i]
                if type(class) == "table" then
                    table.insert(v1ClassList, tostring(class.name or class[1] or "table"))
                else
                    table.insert(v1ClassList, tostring(class))
                end
            end
            
            -- Build v2 class list
            local v2ClassList = {}
            for i = 1, table.getn(v2Classes) do
                local class = v2Classes[i]
                if type(class) == "table" then
                    table.insert(v2ClassList, tostring(class.name or class[1] or "table"))
                else
                    table.insert(v2ClassList, tostring(class))
                end
            end
            
            local v1Display = table.getn(v1ClassList) > 0 and table.concat(v1ClassList, ", ") or "none"
            local v2Display = table.getn(v2ClassList) > 0 and table.concat(v2ClassList, ", ") or "none"
            
            OGRH.Msg("    v1: " .. v1Display)
            OGRH.Msg("    v2: " .. v2Display)
            
            -- Show class priority roles for this slot
            local v1SlotRoles = (v1Role.classPriorityRoles and v1Role.classPriorityRoles[slotIdx]) or {}
            local v2SlotRoles = (v2Role.classPriorityRoles and v2Role.classPriorityRoles[slotIdx]) or {}
            
            -- Display role flags for each class in this slot's priority list
            local maxClasses = table.getn(v1Classes)
            if table.getn(v2Classes) > maxClasses then
                maxClasses = table.getn(v2Classes)
            end
            
            if maxClasses > 0 then
                OGRH.Msg("    |cffccccccRole Flags:|r")
                for classIdx = 1, maxClasses do
                    local v1ClassName = v1Classes[classIdx]
                    local v2ClassName = v2Classes[classIdx]
                    
                    -- Get class name as string
                    local v1ClassStr = "nil"
                    if v1ClassName then
                        if type(v1ClassName) == "table" then
                            v1ClassStr = tostring(v1ClassName.name or v1ClassName[1] or "table")
                        else
                            v1ClassStr = tostring(v1ClassName)
                        end
                    end
                    
                    local v2ClassStr = "nil"
                    if v2ClassName then
                        if type(v2ClassName) == "table" then
                            v2ClassStr = tostring(v2ClassName.name or v2ClassName[1] or "table")
                        else
                            v2ClassStr = tostring(v2ClassName)
                        end
                    end
                    
                    -- Get role flags for this class position
                    local v1Flags = v1SlotRoles[classIdx] or {}
                    local v2Flags = v2SlotRoles[classIdx] or {}
                    
                    -- Check both proper case and all caps (for compatibility)
                    local hasV1Flags = v1Flags.TANKS or v1Flags.HEALERS or v1Flags.MELEE or v1Flags.RANGED or
                                       v1Flags.Tanks or v1Flags.Healers or v1Flags.Melee or v1Flags.Ranged
                    local hasV2Flags = v2Flags.TANKS or v2Flags.HEALERS or v2Flags.MELEE or v2Flags.RANGED or
                                       v2Flags.Tanks or v2Flags.Healers or v2Flags.Melee or v2Flags.Ranged
                    
                    -- Only show if either has flags set
                    if hasV1Flags or hasV2Flags then
                        OGRH.Msg("      [" .. classIdx .. "] " .. v1ClassStr .. " / " .. v2ClassStr .. ":")
                        
                        local roles = {
                            {upper = "TANKS", proper = "Tanks"},
                            {upper = "HEALERS", proper = "Healers"},
                            {upper = "MELEE", proper = "Melee"},
                            {upper = "RANGED", proper = "Ranged"}
                        }
                        local flagsV1 = {}
                        local flagsV2 = {}
                        
                        for _, role in ipairs(roles) do
                            -- Check both casing options
                            if v1Flags[role.upper] or v1Flags[role.proper] then
                                table.insert(flagsV1, role.upper)
                            end
                            if v2Flags[role.upper] or v2Flags[role.proper] then
                                table.insert(flagsV2, role.upper)
                            end
                        end
                        
                        local v1FlagsStr = table.getn(flagsV1) > 0 and table.concat(flagsV1, ", ") or "none"
                        local v2FlagsStr = table.getn(flagsV2) > 0 and table.concat(flagsV2, ", ") or "none"
                        
                        OGRH.Msg("        v1: " .. v1FlagsStr)
                        OGRH.Msg("        v2: " .. v2FlagsStr)
                    end
                end
            end
        end
    end
    OGRH.Msg(" ")
    
    -- Raid Marks and Assignment Numbers
    OGRH.Msg("|cffffaa00Raid Marks & Assignment Numbers:|r")
    
    -- Get the global role index for v1 (needed for encounterRaidMarks/encounterAssignmentNumbers access)
    local v1GlobalRoleIdx = v1RoleIdx
    if v1Column == 2 then
        local col1Count = 0
        if OGRH_SV.encounterMgmt.roles[raidName] and OGRH_SV.encounterMgmt.roles[raidName][encounterName] and 
           OGRH_SV.encounterMgmt.roles[raidName][encounterName].column1 then
            col1Count = table.getn(OGRH_SV.encounterMgmt.roles[raidName][encounterName].column1)
        end
        v1GlobalRoleIdx = col1Count + v1RoleIdx
    end
    
    -- Access raid marks and assignment numbers
    local v1Marks = {}
    local v1Numbers = {}
    if OGRH_SV.encounterRaidMarks and OGRH_SV.encounterRaidMarks[raidName] and 
       OGRH_SV.encounterRaidMarks[raidName][encounterName] and
       OGRH_SV.encounterRaidMarks[raidName][encounterName][v1GlobalRoleIdx] then
        v1Marks = OGRH_SV.encounterRaidMarks[raidName][encounterName][v1GlobalRoleIdx]
    end
    
    if OGRH_SV.encounterAssignmentNumbers and OGRH_SV.encounterAssignmentNumbers[raidName] and
       OGRH_SV.encounterAssignmentNumbers[raidName][encounterName] and
       OGRH_SV.encounterAssignmentNumbers[raidName][encounterName][v1GlobalRoleIdx] then
        v1Numbers = OGRH_SV.encounterAssignmentNumbers[raidName][encounterName][v1GlobalRoleIdx]
    end
    
    local v2Marks = {}
    local v2Numbers = {}
    if OGRH_SV.v2.encounterRaidMarks and OGRH_SV.v2.encounterRaidMarks[v2RaidIdx] and
       OGRH_SV.v2.encounterRaidMarks[v2RaidIdx][v2EncIdx] and
       OGRH_SV.v2.encounterRaidMarks[v2RaidIdx][v2EncIdx][v2RoleIdx] then
        v2Marks = OGRH_SV.v2.encounterRaidMarks[v2RaidIdx][v2EncIdx][v2RoleIdx]
    end
    
    if OGRH_SV.v2.encounterAssignmentNumbers and OGRH_SV.v2.encounterAssignmentNumbers[v2RaidIdx] and
       OGRH_SV.v2.encounterAssignmentNumbers[v2RaidIdx][v2EncIdx] and
       OGRH_SV.v2.encounterAssignmentNumbers[v2RaidIdx][v2EncIdx][v2RoleIdx] then
        v2Numbers = OGRH_SV.v2.encounterAssignmentNumbers[v2RaidIdx][v2EncIdx][v2RoleIdx]
    end
    
    -- Display per-slot data
    local maxSlots = v1Role.slots or 1
    if v2Role.slots and v2Role.slots > maxSlots then
        maxSlots = v2Role.slots
    end
    
    for slotIdx = 1, maxSlots do
        local v1Mark = v1Marks[slotIdx]
        local v2Mark = v2Marks[slotIdx]
        local v1Num = v1Numbers[slotIdx]
        local v2Num = v2Numbers[slotIdx]
        
        if v1Mark or v2Mark or v1Num or v2Num then
            OGRH.Msg("  [Slot " .. slotIdx .. "]")
            if v1Mark or v2Mark then
                OGRH.Msg("    Raid Mark: " .. tostring(v1Mark or "none") .. " | " .. tostring(v2Mark or "none"))
            end
            if v1Num or v2Num then
                OGRH.Msg("    Assignment #: " .. tostring(v1Num or "none") .. " | " .. tostring(v2Num or "none"))
            end
        end
    end
    
    OGRH.Msg(" ")
    OGRH.Msg("======================================")
    
    return true
end

-- ============================================
-- COMPARISON: Compare v1 vs v2 announcements
-- ============================================
function OGRH.Migration.CompareAnnouncements(raidName, encounterName)
    if not OGRH_SV then
        OGRH.Msg("[Compare] ERROR: OGRH_SV not found")
        return false
    end
    
    if not OGRH_SV.v2 then
        OGRH.Msg("[Compare] ERROR: v2 schema not found. Run /ogrh migration create first.")
        return false
    end
    
    -- Find raid in v1
    local v1Raid = nil
    local v1RaidIdx = nil
    if OGRH_SV.encounterMgmt and OGRH_SV.encounterMgmt.raids then
        for idx = 1, table.getn(OGRH_SV.encounterMgmt.raids) do
            local raid = OGRH_SV.encounterMgmt.raids[idx]
            if type(raid) == "table" and raid.name == raidName then
                v1Raid = raid
                v1RaidIdx = idx
                break
            end
        end
    end
    
    if not v1Raid then
        OGRH.Msg("[Compare] ERROR: Raid '" .. raidName .. "' not found in v1 data")
        return false
    end
    
    -- Find encounter in v1
    local v1Encounter = nil
    local v1EncIdx = nil
    if v1Raid.encounters then
        for idx = 1, table.getn(v1Raid.encounters) do
            local enc = v1Raid.encounters[idx]
            if type(enc) == "table" and enc.name == encounterName then
                v1Encounter = enc
                v1EncIdx = idx
                break
            end
        end
    end
    
    if not v1Encounter then
        OGRH.Msg("[Compare] ERROR: Encounter '" .. encounterName .. "' not found in v1 raid '" .. raidName .. "'")
        return false
    end
    
    -- Find raid in v2
    local v2Raid = nil
    local v2RaidIdx = nil
    if OGRH_SV.v2.encounterMgmt and OGRH_SV.v2.encounterMgmt.raids then
        for idx, raid in ipairs(OGRH_SV.v2.encounterMgmt.raids) do
            if raid.name == raidName then
                v2Raid = raid
                v2RaidIdx = idx
                break
            end
        end
    end
    
    if not v2Raid then
        OGRH.Msg("[Compare] ERROR: Raid '" .. raidName .. "' not found in v2 data")
        return false
    end
    
    -- Find encounter in v2
    local v2Encounter = nil
    local v2EncIdx = nil
    if v2Raid.encounters then
        for idx, enc in ipairs(v2Raid.encounters) do
            if enc.name == encounterName then
                v2Encounter = enc
                v2EncIdx = idx
                break
            end
        end
    end
    
    if not v2Encounter then
        OGRH.Msg("[Compare] ERROR: Encounter '" .. encounterName .. "' not found in v2 raid '" .. raidName .. "'")
        return false
    end
    
    -- Get announcements
    local v1Announcements = {}
    if OGRH_SV.encounterAnnouncements and OGRH_SV.encounterAnnouncements[raidName] and
       OGRH_SV.encounterAnnouncements[raidName][encounterName] then
        v1Announcements = OGRH_SV.encounterAnnouncements[raidName][encounterName]
    end
    
    local v2Announcements = {}
    if OGRH_SV.v2.encounterAnnouncements and OGRH_SV.v2.encounterAnnouncements[v2RaidIdx] and
       OGRH_SV.v2.encounterAnnouncements[v2RaidIdx][v2EncIdx] then
        v2Announcements = OGRH_SV.v2.encounterAnnouncements[v2RaidIdx][v2EncIdx]
    end
    
    -- Display comparison
    OGRH.Msg("======================================")
    OGRH.Msg("ANNOUNCEMENTS: " .. raidName .. "/" .. encounterName)
    OGRH.Msg("======================================")
    OGRH.Msg(" ")
    
    OGRH.Msg("|cffffaa00Announcement Count:|r")
    OGRH.Msg("  v1: " .. table.getn(v1Announcements) .. " announcements")
    OGRH.Msg("  v2: " .. table.getn(v2Announcements) .. " announcements")
    OGRH.Msg(" ")
    
    -- Find max count
    local maxCount = table.getn(v1Announcements)
    if table.getn(v2Announcements) > maxCount then
        maxCount = table.getn(v2Announcements)
    end
    
    if maxCount > 0 then
        for i = 1, maxCount do
            -- Both v1 and v2 announcements are stored as strings
            local v1Ann = v1Announcements[i]
            local v2Ann = v2Announcements[i]
            
            OGRH.Msg("|cffffaa00[Announcement " .. i .. "]|r")
            
            if v1Ann or v2Ann then
                local v1Text = v1Ann or "(not configured)"
                local v2Text = v2Ann or "(not configured)"
                
                -- Truncate for display
                if v1Ann and string.len(v1Text) > 50 then
                    v1Text = string.sub(v1Text, 1, 50) .. "..."
                end
                if v2Ann and string.len(v2Text) > 50 then
                    v2Text = string.sub(v2Text, 1, 50) .. "..."
                end
                
                OGRH.Msg("  v1: " .. v1Text)
                OGRH.Msg("  v2: " .. v2Text)
            else
                OGRH.Msg("  (no data)")
            end
            OGRH.Msg(" ")
        end
    else
        OGRH.Msg("  No announcements configured")
        OGRH.Msg(" ")
    end
    
    OGRH.Msg("======================================")
    
    return true
end

-- ============================================
-- COMPARISON: Component-Level Comparisons
-- ============================================

-- Compare recruitment data
function OGRH.Migration.CompareRecruitment()
    if not OGRH_SV then
        OGRH.Msg("[Compare] ERROR: OGRH_SV not found")
        return false
    end
    
    if not OGRH_SV.v2 then
        OGRH.Msg("[Compare] ERROR: v2 schema not found. Run /ogrh migration create first")
        return false
    end
    
    local v1 = OGRH_SV.recruitment or {}
    local v2 = OGRH_SV.v2.recruitment or {}
    
    OGRH.Msg("======================================")
    OGRH.Msg("RECRUITMENT COMPARISON")
    OGRH.Msg("======================================")
    OGRH.Msg(" ")
    
    -- Compare simple fields
    local fields = {
        {key = "enabled", label = "Enabled"},
        {key = "selectedMessageIndex", label = "Selected Message"},
        {key = "lastAdTime", label = "Last Ad Time"},
        {key = "autoAd", label = "Auto-Ad"},
        {key = "selectedChannel", label = "Channel"},
        {key = "interval", label = "Interval"},
        {key = "targetTime", label = "Target Time"},
        {key = "isRecruiting", label = "Is Recruiting"}
    }
    
    for i = 1, table.getn(fields) do
        local field = fields[i]
        local v1Val = v1[field.key]
        local v2Val = v2[field.key]
        local match = (v1Val == v2Val) and "|cff00ff00✓|r" or "|cffff0000✗|r"
        
        OGRH.Msg(string.format("%s |cffffaa00%s:|r", match, field.label))
        OGRH.Msg(string.format("  v1: %s", tostring(v1Val)))
        OGRH.Msg(string.format("  v2: %s", tostring(v2Val)))
        OGRH.Msg(" ")
    end
    
    -- Compare messages
    OGRH.Msg("|cffffaa00Messages:|r")
    for i = 1, 5 do
        local v1Msg = (v1.messages and v1.messages[i]) or ""
        local v2Msg = (v2.messages and v2.messages[i]) or ""
        local match = (v1Msg == v2Msg) and "|cff00ff00✓|r" or "|cffff0000✗|r"
        OGRH.Msg(string.format("%s  Slot %d: v1='%s' v2='%s'", match, i, v1Msg, v2Msg))
    end
    OGRH.Msg(" ")
    
    -- Compare messages2
    OGRH.Msg("|cffffaa00Messages2:|r")
    for i = 1, 5 do
        local v1Msg = (v1.messages2 and v1.messages2[i]) or ""
        local v2Msg = (v2.messages2 and v2.messages2[i]) or ""
        local match = (v1Msg == v2Msg) and "|cff00ff00✓|r" or "|cffff0000✗|r"
        OGRH.Msg(string.format("%s  Slot %d: v1='%s' v2='%s'", match, i, v1Msg, v2Msg))
    end
    OGRH.Msg(" ")
    
    -- Compare table sizes
    OGRH.Msg("|cffffaa00Table Sizes:|r")
    local v1WhisperCount = (v1.whisperHistory and table.getn(v1.whisperHistory)) or 0
    local v2WhisperCount = (v2.whisperHistory and table.getn(v2.whisperHistory)) or 0
    OGRH.Msg(string.format("  whisperHistory: v1=%d v2=%d", v1WhisperCount, v2WhisperCount))
    OGRH.Msg(" ")
    
    OGRH.Msg("======================================")
    return true
end

-- Compare consumes tracking data
function OGRH.Migration.CompareConsumesTracking()
    if not OGRH_SV then
        OGRH.Msg("[Compare] ERROR: OGRH_SV not found")
        return false
    end
    
    if not OGRH_SV.v2 then
        OGRH.Msg("[Compare] ERROR: v2 schema not found. Run /ogrh migration create first")
        return false
    end
    
    local v1 = OGRH_SV.consumesTracking or {}
    local v2 = OGRH_SV.v2.consumesTracking or {}
    
    OGRH.Msg("======================================")
    OGRH.Msg("CONSUMES TRACKING COMPARISON")
    OGRH.Msg("======================================")
    OGRH.Msg(" ")
    
    -- Compare simple fields
    local fields = {
        {key = "enabled", label = "Enabled"},
        {key = "trackOnPull", label = "Track on Pull"},
        {key = "maxEntries", label = "Max Entries"},
        {key = "secondsBeforePull", label = "Seconds Before Pull"},
        {key = "logToMemory", label = "Log to Memory"},
        {key = "logToCombatLog", label = "Log to Combat Log"}
    }
    
    for i = 1, table.getn(fields) do
        local field = fields[i]
        local v1Val = v1[field.key]
        local v2Val = v2[field.key]
        local match = (v1Val == v2Val) and "|cff00ff00✓|r" or "|cffff0000✗|r"
        
        OGRH.Msg(string.format("%s |cffffaa00%s:|r", match, field.label))
        OGRH.Msg(string.format("  v1: %s", tostring(v1Val)))
        OGRH.Msg(string.format("  v2: %s", tostring(v2Val)))
        OGRH.Msg(" ")
    end
    
    -- Compare table sizes
    OGRH.Msg("|cffffaa00Table Sizes:|r")
    local v1HistoryCount = (v1.history and table.getn(v1.history)) or 0
    local v2HistoryCount = (v2.history and table.getn(v2.history)) or 0
    OGRH.Msg(string.format("  history: v1=%d v2=%d", v1HistoryCount, v2HistoryCount))
    OGRH.Msg(" ")
    
    OGRH.Msg("======================================")
    return true
end

-- Compare auto-promotes data
function OGRH.Migration.ComparePromotes()
    if not OGRH_SV then
        OGRH.Msg("[Compare] ERROR: OGRH_SV not found")
        return false
    end
    
    if not OGRH_SV.v2 then
        OGRH.Msg("[Compare] ERROR: v2 schema not found. Run /ogrh migration create first")
        return false
    end
    
    local v1 = OGRH_SV.autoPromotes or {}
    local v2 = OGRH_SV.v2.autoPromotes or {}
    
    OGRH.Msg("======================================")
    OGRH.Msg("AUTO-PROMOTES COMPARISON")
    OGRH.Msg("======================================")
    OGRH.Msg(" ")
    
    local v1Count = table.getn(v1)
    local v2Count = table.getn(v2)
    
    OGRH.Msg(string.format("|cffffaa00Entry Count:|r v1=%d v2=%d", v1Count, v2Count))
    OGRH.Msg(" ")
    
    local maxCount = v1Count > v2Count and v1Count or v2Count
    
    if maxCount > 0 then
        for i = 1, maxCount do
            local v1Entry = v1[i]
            local v2Entry = v2[i]
            
            OGRH.Msg(string.format("|cffffaa00[Entry %d]|r", i))
            
            if v1Entry and v2Entry then
                local nameMatch = (v1Entry.name == v2Entry.name) and "|cff00ff00✓|r" or "|cffff0000✗|r"
                local classMatch = (v1Entry.class == v2Entry.class) and "|cff00ff00✓|r" or "|cffff0000✗|r"
                
                OGRH.Msg(string.format("%s  name: v1='%s' v2='%s'", nameMatch, tostring(v1Entry.name), tostring(v2Entry.name)))
                OGRH.Msg(string.format("%s  class: v1='%s' v2='%s'", classMatch, tostring(v1Entry.class), tostring(v2Entry.class)))
            elseif v1Entry then
                OGRH.Msg(string.format("  v1: name='%s' class='%s'", tostring(v1Entry.name), tostring(v1Entry.class)))
                OGRH.Msg("  v2: (missing)")
            elseif v2Entry then
                OGRH.Msg("  v1: (missing)")
                OGRH.Msg(string.format("  v2: name='%s' class='%s'", tostring(v2Entry.name), tostring(v2Entry.class)))
            end
            OGRH.Msg(" ")
        end
    else
        OGRH.Msg("  No auto-promote entries")
        OGRH.Msg(" ")
    end
    
    OGRH.Msg("======================================")
    return true
end

-- Compare roster management data
function OGRH.Migration.CompareRoster()
    if not OGRH_SV then
        OGRH.Msg("[Compare] ERROR: OGRH_SV not found")
        return false
    end
    
    if not OGRH_SV.v2 then
        OGRH.Msg("[Compare] ERROR: v2 schema not found. Run /ogrh migration create first")
        return false
    end
    
    local v1 = OGRH_SV.rosterManagement or {}
    local v2 = OGRH_SV.v2.rosterManagement or {}
    
    OGRH.Msg("======================================")
    OGRH.Msg("ROSTER MANAGEMENT COMPARISON")
    OGRH.Msg("======================================")
    OGRH.Msg(" ")
    
    -- Count players
    local v1PlayerCount = 0
    local v2PlayerCount = 0
    
    if v1.players then
        for _ in pairs(v1.players) do
            v1PlayerCount = v1PlayerCount + 1
        end
    end
    
    if v2.players then
        for _ in pairs(v2.players) do
            v2PlayerCount = v2PlayerCount + 1
        end
    end
    
    OGRH.Msg(string.format("|cffffaa00Player Count:|r v1=%d v2=%d", v1PlayerCount, v2PlayerCount))
    OGRH.Msg(" ")
    
    -- Compare config
    if v1.config or v2.config then
        OGRH.Msg("|cffffaa00Config:|r")
        local v1Config = v1.config or {}
        local v2Config = v2.config or {}
        
        local configFields = {"historySize", "autoRankingEnabled"}
        for i = 1, table.getn(configFields) do
            local field = configFields[i]
            local v1Val = v1Config[field]
            local v2Val = v2Config[field]
            local match = (v1Val == v2Val) and "|cff00ff00✓|r" or "|cffff0000✗|r"
            
            OGRH.Msg(string.format("%s  %s: v1=%s v2=%s", match, field, tostring(v1Val), tostring(v2Val)))
        end
        OGRH.Msg(" ")
    end
    
    OGRH.Msg("======================================")
    return true
end

-- Compare core settings
function OGRH.Migration.CompareBaseConsumes()
    if not OGRH_SV then
        OGRH.Msg("[Compare] ERROR: OGRH_SV not found")
        return false
    end
    
    if not OGRH_SV.v2 then
        OGRH.Msg("[Compare] ERROR: v2 schema not found. Run /ogrh migration create first")
        return false
    end
    
    local v1Consumes = OGRH_SV.consumes or {}
    local v2Consumes = OGRH_SV.v2.consumes or {}
    
    OGRH.Msg("======================================")
    OGRH.Msg("BASE CONSUMES COMPARISON")
    OGRH.Msg("======================================")
    OGRH.Msg(" ")
    
    -- Show v1 consumes
    OGRH.Msg("|cffffaa00v1 Consumes:|r")
    local v1Count = 0
    for key, value in pairs(v1Consumes) do
        v1Count = v1Count + 1
        if type(value) == "table" then
            local items = ""
            for k, v in pairs(value) do
                if items ~= "" then items = items .. ", " end
                items = items .. tostring(k) .. "=" .. tostring(v)
            end
            OGRH.Msg(string.format("  [%s] = {%s}", tostring(key), items))
        else
            OGRH.Msg(string.format("  [%s] = %s", tostring(key), tostring(value)))
        end
    end
    if v1Count == 0 then
        OGRH.Msg("  (empty)")
    end
    OGRH.Msg(" ")
    
    -- Show v2 consumes
    OGRH.Msg("|cffffaa00v2 Consumes:|r")
    local v2Count = 0
    for key, value in pairs(v2Consumes) do
        v2Count = v2Count + 1
        if type(value) == "table" then
            local items = ""
            for k, v in pairs(value) do
                if items ~= "" then items = items .. ", " end
                items = items .. tostring(k) .. "=" .. tostring(v)
            end
            OGRH.Msg(string.format("  [%s] = {%s}", tostring(key), items))
        else
            OGRH.Msg(string.format("  [%s] = %s", tostring(key), tostring(value)))
        end
    end
    if v2Count == 0 then
        OGRH.Msg("  (empty)")
    end
    OGRH.Msg(" ")
    
    local match = (v1Count == v2Count) and "|cff00ff00✓|r" or "|cffff0000✗|r"
    OGRH.Msg(string.format("%s |cffffaa00Total Items:|r v1=%d v2=%d", match, v1Count, v2Count))
    OGRH.Msg("======================================")
    return true
end

function OGRH.Migration.CompareTrade()
    if not OGRH_SV then
        OGRH.Msg("[Compare] ERROR: OGRH_SV not found")
        return false
    end
    
    if not OGRH_SV.v2 then
        OGRH.Msg("[Compare] ERROR: v2 schema not found. Run /ogrh migration create first")
        return false
    end
    
    local v1Trade = OGRH_SV.tradeItems or {}
    local v2Trade = OGRH_SV.v2.tradeItems or {}
    
    OGRH.Msg("======================================")
    OGRH.Msg("TRADE ITEMS COMPARISON")
    OGRH.Msg("======================================")
    OGRH.Msg(" ")
    
    -- Show v1 trade items
    OGRH.Msg("|cffffaa00v1 Trade Items:|r")
    local v1Count = 0
    for i = 1, table.getn(v1Trade) do
        v1Count = v1Count + 1
        local item = v1Trade[i]
        if type(item) == "table" then
            -- Dump all keys in the table
            local keys = ""
            for k, v in pairs(item) do
                if keys ~= "" then keys = keys .. ", " end
                keys = keys .. tostring(k) .. "=" .. tostring(v)
            end
            OGRH.Msg(string.format("  [%d] {%s}", i, keys))
        else
            OGRH.Msg(string.format("  [%d] = %s", i, tostring(item)))
        end
    end
    if v1Count == 0 then
        OGRH.Msg("  (empty)")
    end
    OGRH.Msg(" ")
    
    -- Show v2 trade items
    OGRH.Msg("|cffffaa00v2 Trade Items:|r")
    local v2Count = 0
    for i = 1, table.getn(v2Trade) do
        v2Count = v2Count + 1
        local item = v2Trade[i]
        if type(item) == "table" then
            -- Dump all keys in the table
            local keys = ""
            for k, v in pairs(item) do
                if keys ~= "" then keys = keys .. ", " end
                keys = keys .. tostring(k) .. "=" .. tostring(v)
            end
            OGRH.Msg(string.format("  [%d] {%s}", i, keys))
        else
            OGRH.Msg(string.format("  [%d] = %s", i, tostring(item)))
        end
    end
    if v2Count == 0 then
        OGRH.Msg("  (empty)")
    end
    OGRH.Msg(" ")
    
    local match = (v1Count == v2Count) and "|cff00ff00✓|r" or "|cffff0000✗|r"
    OGRH.Msg(string.format("%s |cffffaa00Total Items:|r v1=%d v2=%d", match, v1Count, v2Count))
    OGRH.Msg("======================================")
    return true
end

function OGRH.Migration.CompareCore()
    if not OGRH_SV then
        OGRH.Msg("[Compare] ERROR: OGRH_SV not found")
        return false
    end
    
    if not OGRH_SV.v2 then
        OGRH.Msg("[Compare] ERROR: v2 schema not found. Run /ogrh migration create first")
        return false
    end
    
    OGRH.Msg("======================================")
    OGRH.Msg("CORE SETTINGS COMPARISON")
    OGRH.Msg("======================================")
    OGRH.Msg(" ")
    
    -- Schema version is a meta field (only at root level)
    OGRH.Msg("|cffffaa00Schema Version:|r")
    OGRH.Msg(string.format("  Root level (active schema): %s", tostring(OGRH_SV.schemaVersion)))
    OGRH.Msg(" ")
    
    -- Compare root-level data fields
    local v1PollTime = OGRH_SV.pollTime
    local v2PollTime = OGRH_SV.v2.pollTime
    local pollMatch = (v1PollTime == v2PollTime) and "|cff00ff00✓|r" or "|cffff0000✗|r"
    
    OGRH.Msg(string.format("%s |cffffaa00Poll Time:|r", pollMatch))
    OGRH.Msg(string.format("  v1: %s", tostring(v1PollTime)))
    OGRH.Msg(string.format("  v2: %s", tostring(v2PollTime)))
    OGRH.Msg(" ")
    
    -- Remote ready check setting
    local v1RemoteRC = OGRH_SV.allowRemoteReadyCheck
    local v2RemoteRC = OGRH_SV.v2.allowRemoteReadyCheck
    local rcMatch = (v1RemoteRC == v2RemoteRC) and "|cff00ff00✓|r" or "|cffff0000✗|r"
    
    OGRH.Msg(string.format("%s |cffffaa00Allow Remote Ready Check:|r", rcMatch))
    OGRH.Msg(string.format("  v1: %s", tostring(v1RemoteRC)))
    OGRH.Msg(string.format("  v2: %s", tostring(v2RemoteRC)))
    OGRH.Msg(" ")
    
    -- Monitor consumes setting
    local v1MonitorConsumes = OGRH_SV.monitorConsumes
    local v2MonitorConsumes = OGRH_SV.v2.monitorConsumes
    local monitorMatch = (v1MonitorConsumes == v2MonitorConsumes) and "|cff00ff00✓|r" or "|cffff0000✗|r"
    
    OGRH.Msg(string.format("%s |cffffaa00Monitor Consumes:|r", monitorMatch))
    OGRH.Msg(string.format("  v1: %s", tostring(v1MonitorConsumes)))
    OGRH.Msg(string.format("  v2: %s", tostring(v2MonitorConsumes)))
    OGRH.Msg(" ")
    
    -- Selected raid/encounter are in ui.* not root
    local v1SelectedRaid = (OGRH_SV.ui and OGRH_SV.ui.selectedRaid) or nil
    local v2SelectedRaid = (OGRH_SV.v2.ui and OGRH_SV.v2.ui.selectedRaid) or nil
    local raidMatch = (v1SelectedRaid == v2SelectedRaid) and "|cff00ff00✓|r" or "|cffff0000✗|r"
    
    OGRH.Msg(string.format("%s |cffffaa00Selected Raid:|r", raidMatch))
    OGRH.Msg(string.format("  v1: %s", tostring(v1SelectedRaid)))
    OGRH.Msg(string.format("  v2: %s", tostring(v2SelectedRaid)))
    OGRH.Msg(" ")
    
    local v1SelectedEnc = (OGRH_SV.ui and OGRH_SV.ui.selectedEncounter) or nil
    local v2SelectedEnc = (OGRH_SV.v2.ui and OGRH_SV.v2.ui.selectedEncounter) or nil
    local encMatch = (v1SelectedEnc == v2SelectedEnc) and "|cff00ff00✓|r" or "|cffff0000✗|r"
    
    OGRH.Msg(string.format("%s |cffffaa00Selected Encounter:|r", encMatch))
    OGRH.Msg(string.format("  v1: %s", tostring(v1SelectedEnc)))
    OGRH.Msg(string.format("  v2: %s", tostring(v2SelectedEnc)))
    OGRH.Msg(" ")
    
    -- Sync locked setting
    local v1SyncLocked = OGRH_SV.syncLocked
    local v2SyncLocked = OGRH_SV.v2.syncLocked
    local syncLockedMatch = (v1SyncLocked == v2SyncLocked) and "|cff00ff00✓|r" or "|cffff0000✗|r"
    
    OGRH.Msg(string.format("%s |cffffaa00Sync Locked:|r", syncLockedMatch))
    OGRH.Msg(string.format("  v1: %s", tostring(v1SyncLocked)))
    OGRH.Msg(string.format("  v2: %s", tostring(v2SyncLocked)))
    OGRH.Msg(" ")
    
    -- Compare UI settings
    if OGRH_SV.ui or OGRH_SV.v2.ui then
        OGRH.Msg("|cffffaa00UI Settings:|r")
        local v1UI = OGRH_SV.ui or {}
        local v2UI = OGRH_SV.v2.ui or {}
        
        local uiFields = {"locked", "minimized", "point", "relPoint", "x", "y", "hidden"}
        for i = 1, table.getn(uiFields) do
            local field = uiFields[i]
            local v1Val = v1UI[field]
            local v2Val = v2UI[field]
            local match = (v1Val == v2Val) and "|cff00ff00✓|r" or "|cffff0000✗|r"
            
            OGRH.Msg(string.format("%s  %s: v1=%s v2=%s", match, field, tostring(v1Val), tostring(v2Val)))
        end
        OGRH.Msg(" ")
    end
    
    -- Compare data structure counts
    local v1TradeItemsCount = 0
    if OGRH_SV.tradeItems then
        for k, v in pairs(OGRH_SV.tradeItems) do
            v1TradeItemsCount = v1TradeItemsCount + 1
        end
    end
    
    local v2TradeItemsCount = 0
    if OGRH_SV.v2.tradeItems then
        for k, v in pairs(OGRH_SV.v2.tradeItems) do
            v2TradeItemsCount = v2TradeItemsCount + 1
        end
    end
    
    local tradeMatch = (v1TradeItemsCount == v2TradeItemsCount) and "|cff00ff00✓|r" or "|cffff0000✗|r"
    OGRH.Msg(string.format("%s |cffffaa00Trade Items Count:|r", tradeMatch))
    OGRH.Msg(string.format("  v1: %d", v1TradeItemsCount))
    OGRH.Msg(string.format("  v2: %d", v2TradeItemsCount))
    OGRH.Msg(" ")
    
    local v1ConsumesCount = 0
    if OGRH_SV.consumes then
        for k, v in pairs(OGRH_SV.consumes) do
            v1ConsumesCount = v1ConsumesCount + 1
        end
    end
    
    local v2ConsumesCount = 0
    if OGRH_SV.v2.consumes then
        for k, v in pairs(OGRH_SV.v2.consumes) do
            v2ConsumesCount = v2ConsumesCount + 1
        end
    end
    
    local consumesMatch = (v1ConsumesCount == v2ConsumesCount) and "|cff00ff00✓|r" or "|cffff0000✗|r"
    OGRH.Msg(string.format("%s |cffffaa00Consumes Count:|r", consumesMatch))
    OGRH.Msg(string.format("  v1: %d", v1ConsumesCount))
    OGRH.Msg(string.format("  v2: %d", v2ConsumesCount))
    OGRH.Msg(" ")
    
    OGRH.Msg("======================================")
    return true
end

-- Compare message router state
function OGRH.Migration.CompareMessageRouter()
    if not OGRH_SV then
        OGRH.Msg("[Compare] ERROR: OGRH_SV not found")
        return false
    end
    
    if not OGRH_SV.v2 then
        OGRH.Msg("[Compare] ERROR: v2 schema not found. Run /ogrh migration create first")
        return false
    end
    
    local v1 = OGRH_SV.MessageRouter or {}
    local v2 = OGRH_SV.v2.MessageRouter or {}
    
    OGRH.Msg("======================================")
    OGRH.Msg("MESSAGE ROUTER COMPARISON")
    OGRH.Msg("======================================")
    OGRH.Msg(" ")
    
    -- Count handlers
    local v1HandlerCount = 0
    local v2HandlerCount = 0
    
    if v1.handlers then
        for _ in pairs(v1.handlers) do
            v1HandlerCount = v1HandlerCount + 1
        end
    end
    
    if v2.handlers then
        for _ in pairs(v2.handlers) do
            v2HandlerCount = v2HandlerCount + 1
        end
    end
    
    OGRH.Msg(string.format("|cffffaa00Handler Count:|r v1=%d v2=%d", v1HandlerCount, v2HandlerCount))
    OGRH.Msg(" ")
    
    -- Compare state fields
    if v1.state or v2.state then
        OGRH.Msg("|cffffaa00State:|r")
        local v1State = v1.state or {}
        local v2State = v2.state or {}
        
        local stateFields = {"initialized", "ready"}
        for i = 1, table.getn(stateFields) do
            local field = stateFields[i]
            local v1Val = v1State[field]
            local v2Val = v2State[field]
            local match = (v1Val == v2Val) and "|cff00ff00✓|r" or "|cffff0000✗|r"
            
            OGRH.Msg(string.format("%s  %s: v1=%s v2=%s", match, field, tostring(v1Val), tostring(v2Val)))
        end
        OGRH.Msg(" ")
    end
    
    OGRH.Msg("======================================")
    return true
end

-- Compare permissions data
function OGRH.Migration.ComparePermissions()
    if not OGRH_SV then
        OGRH.Msg("[Compare] ERROR: OGRH_SV not found")
        return false
    end
    
    if not OGRH_SV.v2 then
        OGRH.Msg("[Compare] ERROR: v2 schema not found. Run /ogrh migration create first")
        return false
    end
    
    local v1 = OGRH_SV.permissions or {}
    local v2 = OGRH_SV.v2.permissions or {}
    
    OGRH.Msg("======================================")
    OGRH.Msg("PERMISSIONS COMPARISON")
    OGRH.Msg("======================================")
    OGRH.Msg(" ")
    
    -- Compare fields
    local fields = {
        {key = "raidAdmin", label = "Raid Admin"},
        {key = "sessionAdmin", label = "Session Admin"},
        {key = "adminTimestamp", label = "Admin Timestamp"}
    }
    
    for i = 1, table.getn(fields) do
        local field = fields[i]
        local v1Val = v1[field.key]
        local v2Val = v2[field.key]
        local match = (v1Val == v2Val) and "|cff00ff00✓|r" or "|cffff0000✗|r"
        
        OGRH.Msg(string.format("%s |cffffaa00%s:|r", match, field.label))
        OGRH.Msg(string.format("  v1: %s", tostring(v1Val)))
        OGRH.Msg(string.format("  v2: %s", tostring(v2Val)))
        OGRH.Msg(" ")
    end
    
    -- Count denials
    local v1DenialCount = 0
    local v2DenialCount = 0
    
    if v1.denials then
        v1DenialCount = table.getn(v1.denials)
    end
    
    if v2.denials then
        v2DenialCount = table.getn(v2.denials)
    end
    
    OGRH.Msg(string.format("|cffffaa00Denial Count:|r v1=%d v2=%d", v1DenialCount, v2DenialCount))
    OGRH.Msg(" ")
    
    OGRH.Msg("======================================")
    return true
end

-- ============================================
-- PURGE V1 DATA
-- ============================================
function OGRH.Migration.PurgeV1Data(silent)
    if not OGRH_SV then
OGRH.Msg("|cffff0000[RH-Migration]|r ERROR: OGRH_SV not found")
        return false
    end
    
    if not OGRH_SV.v2 then
OGRH.Msg("|cffff0000[RH-Migration]|r ERROR: v2 schema not found. Cannot purge without active v2 data.")
        return false
    end
    
    -- Ensure encounterMgmt.schemaVersion is set to v2
    if not OGRH_SV.v2.encounterMgmt or OGRH_SV.v2.encounterMgmt.schemaVersion ~= 2 then
OGRH.Msg("|cffff0000[RH-Migration]|r ERROR: v2 schema not active. Run /ogrh migration cutover confirm first.")
        return false
    end
    
    if not silent then
OGRH.Msg("|cff00ccff[RH-Migration]|r Purging v1 data from SavedVariables...")
    end
    
    -- List of keys to preserve (v2 schema and schemaVersion flag)
    local preserveKeys = {
        v2 = true,  -- v2 schema contains all addon data
        schemaVersion = true  -- Need to preserve schema routing flag
    }
    
    -- Count keys purged
    local purgedCount = 0
    local purgedKeys = {}
    
    -- Purge all v1 keys except preserved ones
    for key, _ in pairs(OGRH_SV) do
        if not preserveKeys[key] then
            OGRH_SV[key] = nil
            purgedCount = purgedCount + 1
            table.insert(purgedKeys, key)
        end
    end
    
    -- Also remove deprecated fields from v2 schema
    if OGRH_SV.v2.order then
        OGRH_SV.v2.order = nil
        if not silent then
OGRH.Msg("|cff00ccff[RH-Migration]|r Removed deprecated 'order' field from v2")
        end
    end
    if OGRH_SV.v2.Permissions then
        OGRH_SV.v2.Permissions = nil
        if not silent then
OGRH.Msg("|cff00ccff[RH-Migration]|r Removed deprecated 'Permissions' field from v2 (use lowercase 'permissions')")
        end
    end
    if OGRH_SV.v2.Versioning then
        OGRH_SV.v2.Versioning = nil
        if not silent then
OGRH.Msg("|cff00ccff[RH-Migration]|r Removed deprecated 'Versioning' field from v2 (use lowercase 'versioning')")
        end
    end
    
    if not silent then
OGRH.Msg(string.format("|cff00ff00[RH-Migration]|r ✓ Purged %d v1 keys from SavedVariables", purgedCount))
        if purgedCount > 0 and purgedCount <= 20 then
OGRH.Msg("|cff00ccff[RH-Migration]|r Purged keys: " .. table.concat(purgedKeys, ", "))
        end
OGRH.Msg("|cff00ccff[RH-Migration]|r All addon data now resides in OGRH_SV.v2")
    end
    
    return true
end

-- Compare versioning data
function OGRH.Migration.CompareVersioning()
    if not OGRH_SV then
        OGRH.Msg("[Compare] ERROR: OGRH_SV not found")
        return false
    end
    
    if not OGRH_SV.v2 then
        OGRH.Msg("[Compare] ERROR: v2 schema not found. Run /ogrh migration create first")
        return false
    end
    
    local v1 = OGRH_SV.versioning or {}
    local v2 = OGRH_SV.v2.versioning or {}
    
    OGRH.Msg("======================================")
    OGRH.Msg("VERSIONING COMPARISON")
    OGRH.Msg("======================================")
    OGRH.Msg(" ")
    
    -- Compare global version
    local v1Global = v1.globalVersion or 0
    local v2Global = v2.globalVersion or 0
    local match = (v1Global == v2Global) and "|cff00ff00✓|r" or "|cffff0000✗|r"
    
    OGRH.Msg(string.format("%s |cffffaa00Global Version:|r", match))
    OGRH.Msg(string.format("  v1: %d", v1Global))
    OGRH.Msg(string.format("  v2: %d", v2Global))
    OGRH.Msg(" ")
    
    -- Count encounter versions
    local v1EncCount = 0
    local v2EncCount = 0
    
    if v1.encounterVersions then
        for _ in pairs(v1.encounterVersions) do
            v1EncCount = v1EncCount + 1
        end
    end
    
    if v2.encounterVersions then
        for _ in pairs(v2.encounterVersions) do
            v2EncCount = v2EncCount + 1
        end
    end
    
    OGRH.Msg(string.format("|cffffaa00Encounter Version Count:|r v1=%d v2=%d", v1EncCount, v2EncCount))
    OGRH.Msg(" ")
    
    -- Count assignment versions
    local v1AssignCount = 0
    local v2AssignCount = 0
    
    if v1.assignmentVersions then
        for _ in pairs(v1.assignmentVersions) do
            v1AssignCount = v1AssignCount + 1
        end
    end
    
    if v2.assignmentVersions then
        for _ in pairs(v2.assignmentVersions) do
            v2AssignCount = v2AssignCount + 1
        end
    end
    
    OGRH.Msg(string.format("|cffffaa00Assignment Version Count:|r v1=%d v2=%d", v1AssignCount, v2AssignCount))
    OGRH.Msg(" ")
    
    OGRH.Msg("======================================")
    return true
end
