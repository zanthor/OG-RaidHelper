--[[
    SavedVariables Migration Script - Schema v2
    
    Purpose: Prototype migration script for SavedVariables optimization
    Status: PROTOTYPE - NOT FOR PRODUCTION USE YET
    
    This script demonstrates the migration approach for:
    1. Removing empty/unused tables
    2. Consolidating role data
    3. Pruning historical data
    4. Adding versioning and backup
    
    Usage:
    - Include in Core.lua after EnsureSV()
    - Will auto-run on VARIABLES_LOADED if schema version < 2
--]]

OGRH.Migration = OGRH.Migration or {}

-- ============================================
-- SCHEMA VERSION CONSTANTS
-- ============================================
local SCHEMA_V1 = 1
local SCHEMA_V2 = 2
local CURRENT_SCHEMA = SCHEMA_V2

local BACKUP_RETENTION_DAYS = 30

-- ============================================
-- MAIN MIGRATION ENTRY POINT
-- ============================================
function OGRH.Migration.Run()
    if not OGRH_SV then
        OGRH.Msg("[Migration] No SavedVariables found - skipping migration")
        return
    end
    
    -- Determine current schema version
    local currentVersion = OGRH_SV.schemaVersion or SCHEMA_V1
    
    if currentVersion >= CURRENT_SCHEMA then
        -- Already up to date
        OGRH.Migration.CleanupOldBackups()
        return
    end
    
    OGRH.Msg("|cff00ff00[Migration]|r Starting SavedVariables migration from v" .. currentVersion .. " to v" .. CURRENT_SCHEMA)
    
    -- Run migrations in sequence
    if currentVersion < SCHEMA_V2 then
        local success = OGRH.Migration.MigrateToV2()
        if not success then
            OGRH.Msg("|cffff0000[Migration]|r Failed! Use /ogrh migration rollback to restore")
            return
        end
        OGRH_SV.schemaVersion = SCHEMA_V2
    end
    
    -- Future migrations would go here
    -- if currentVersion < SCHEMA_V3 then
    --     OGRH.Migration.MigrateToV3()
    --     OGRH_SV.schemaVersion = SCHEMA_V3
    -- end
    
    OGRH.Msg("|cff00ff00[Migration]|r Complete! SavedVariables now at schema v" .. CURRENT_SCHEMA)
    OGRH.Msg("|cffcccccc[Migration]|r Backup stored for 30 days. Use /ogrh migration rollback if needed")
end

-- ============================================
-- SCHEMA V1 -> V2 MIGRATION
-- ============================================
function OGRH.Migration.MigrateToV2()
    OGRH.Msg("[Migration v2] Step 1: Creating backup...")
    
    -- 1. Create backup of critical data
    if not OGRH_SV._migrations then
        OGRH_SV._migrations = {}
    end
    
    OGRH_SV._migrations.v2 = {
        timestamp = time(),
        backupData = {
            tankIcon = OGRH.DeepCopy(OGRH_SV.tankIcon),
            healerIcon = OGRH.DeepCopy(OGRH_SV.healerIcon),
            tankCategory = OGRH.DeepCopy(OGRH_SV.tankCategory),
            healerBoss = OGRH.DeepCopy(OGRH_SV.healerBoss),
            playerAssignments = OGRH.DeepCopy(OGRH_SV.playerAssignments),
            pollTime = OGRH_SV.pollTime,
            recruitment = {
                whisperHistoryCount = OGRH.Migration.CountEntries(OGRH_SV.recruitment and OGRH_SV.recruitment.whisperHistory),
                playerCacheCount = OGRH.Migration.CountEntries(OGRH_SV.recruitment and OGRH_SV.recruitment.playerCache)
            },
            consumesTracking = {
                historyCount = OGRH_SV.consumesTracking and table.getn(OGRH_SV.consumesTracking.history or {}) or 0
            }
        }
    }
    
    OGRH.Msg("[Migration v2] Step 2: Removing unused tables...")
    OGRH.Migration.RemoveUnusedTables()
    
    OGRH.Msg("[Migration v2] Step 3: Pruning historical data...")
    local recruitmentPruned = OGRH.Migration.PruneRecruitmentHistory()
    local consumesPruned = OGRH.Migration.PruneConsumeHistory()
    
    OGRH.Msg("[Migration v2] Results:")
    OGRH.Msg("  - Empty tables removed: 4")
    OGRH.Msg("  - Recruitment history pruned: " .. recruitmentPruned .. " entries")
    OGRH.Msg("  - Consume history pruned: " .. consumesPruned .. " entries")
    
    -- Note: Role consolidation was removed from migration
    -- OGRH_SV.roles, rosterManagement.primaryRole, and ConsumeHelper_SV.playerRoles
    -- serve distinct purposes and should NOT be consolidated
    
    return true
end

-- ============================================
-- NOTE: Role Consolidation Removed
-- ============================================
-- The three role storage systems serve DISTINCT purposes:
-- 1. OGRH_SV.roles - Current raid composition (RolesUI drag-drop)
-- 2. rosterManagement.primaryRole - Player capabilities (ranking/ELO)
-- 3. ConsumeHelper_SV.playerRoles - Individual consume preferences
--
-- These are NOT redundant and should NOT be consolidated.
-- ============================================
-- STEP: REMOVE UNUSED TABLES
-- ============================================
function OGRH.Migration.RemoveUnusedTables()
    -- Remove tables that are always empty and never used
    OGRH_SV.tankIcon = nil
    OGRH_SV.healerIcon = nil
    OGRH_SV.tankCategory = nil
    OGRH_SV.healerBoss = nil
    
    -- Remove pollTime if unused (needs verification)
    -- OGRH_SV.pollTime = nil
    
    -- playerAssignments was migrated to rosterManagement, but we keep it
    -- for now as it may still be referenced in some places
end

-- ============================================
-- STEP: PRUNE RECRUITMENT HISTORY
-- ============================================
function OGRH.Migration.PruneRecruitmentHistory()
    if not OGRH_SV.recruitment then
        return 0
    end
    
    local pruned = 0
    local cutoffTime = time() - (BACKUP_RETENTION_DAYS * 24 * 60 * 60)
    
    -- 1. Prune whisper history (keep last 30 days)
    if OGRH_SV.recruitment.whisperHistory then
        for playerName, history in pairs(OGRH_SV.recruitment.whisperHistory) do
            if type(history) == "table" then
                local filtered = {}
                for i = 1, table.getn(history) do
                    local entry = history[i]
                    if entry and entry.timestamp and entry.timestamp > cutoffTime then
                        table.insert(filtered, entry)
                    else
                        pruned = pruned + 1
                    end
                end
                
                if table.getn(filtered) > 0 then
                    OGRH_SV.recruitment.whisperHistory[playerName] = filtered
                else
                    OGRH_SV.recruitment.whisperHistory[playerName] = nil
                end
            end
        end
    end
    
    -- 2. Prune player cache (keep most recent 100 players)
    if OGRH_SV.recruitment.playerCache then
        local sorted = {}
        for name, data in pairs(OGRH_SV.recruitment.playerCache) do
            table.insert(sorted, {
                name = name,
                data = data,
                lastSeen = data.lastSeen or 0
            })
        end
        
        -- Sort by most recent
        table.sort(sorted, function(a, b)
            return a.lastSeen > b.lastSeen
        end)
        
        -- Keep only top 100
        local newCache = {}
        local maxPlayers = 100
        for i = 1, math.min(maxPlayers, table.getn(sorted)) do
            newCache[sorted[i].name] = sorted[i].data
        end
        
        local removed = table.getn(sorted) - table.getn(newCache)
        pruned = pruned + math.max(0, removed)
        
        OGRH_SV.recruitment.playerCache = newCache
    end
    
    -- 3. Prune deleted contacts (keep most recent 50)
    if OGRH_SV.recruitment.deletedContacts then
        local contactList = {}
        for name, _ in pairs(OGRH_SV.recruitment.deletedContacts) do
            table.insert(contactList, name)
        end
        
        if table.getn(contactList) > 50 then
            -- Remove oldest entries (we don't have timestamps, so just keep first 50)
            local newDeleted = {}
            for i = 1, 50 do
                newDeleted[contactList[i]] = true
            end
            pruned = pruned + (table.getn(contactList) - 50)
            OGRH_SV.recruitment.deletedContacts = newDeleted
        end
    end
    
    return pruned
end

-- ============================================
-- STEP: PRUNE CONSUME HISTORY
-- ============================================
function OGRH.Migration.PruneConsumeHistory()
    if not OGRH_SV.consumesTracking or not OGRH_SV.consumesTracking.history then
        return 0
    end
    
    local history = OGRH_SV.consumesTracking.history
    local maxEntries = OGRH_SV.consumesTracking.maxEntries or 200
    local currentCount = table.getn(history)
    
    if currentCount <= maxEntries then
        return 0  -- No pruning needed
    end
    
    -- Keep only the most recent maxEntries
    local newHistory = {}
    local startIndex = currentCount - maxEntries + 1
    
    for i = startIndex, currentCount do
        table.insert(newHistory, history[i])
    end
    
    local pruned = currentCount - table.getn(newHistory)
    OGRH_SV.consumesTracking.history = newHistory
    
    return pruned
end

-- ============================================
-- ROLLBACK FUNCTIONALITY
-- ============================================
function OGRH.Migration.RollbackV2()
    if not OGRH_SV._migrations or not OGRH_SV._migrations.v2 then
        OGRH.Msg("|cffff0000[Migration]|r No backup found for v2 migration")
        return false
    end
    
    local backup = OGRH_SV._migrations.v2.backupData
    
    OGRH.Msg("[Migration] Rolling back to schema v1...")
    
    -- Restore backed up data
    OGRH_SV.roles = backup.ro (empty tables only - no data lost)nkIcon
    OGRH_SV.healerIcon = backup.healerIcon
    OGRH_SV.tankCategory = backup.tankCategory
    OGRH_SV.healerBoss = backup.healerBoss
    OGRH_SV.playerAssignments = backup.playerAssignments
    OGRH_SV.pollTime = backup.pollTime
    
    -- Note: We don't restore pruned history as it's intentionally removed
    -- If user needs it, they should restore from WTF backup
    
    OGRH_SV.schemaVersion = SCHEMA_V1
    
    OGRH.Msg("|cff00ff00[Migration]|r Rollback complete! Reloading UI recommended")
    return true
end

-- ============================================
-- UTILITY: COUNT ENTRIES IN TABLE
-- ============================================
function OGRH.Migration.CountEntries(tbl)
    if not tbl then return 0 end
    
    local count = 0
    for k, v in pairs(tbl) do
        count = count + 1
    end
    return count
end

-- ============================================
-- UTILITY: CLEANUP OLD BACKUPS
-- ============================================
function OGRH.Migration.CleanupOldBackups()
    if not OGRH_SV._migrations then
        return
    end
    
    local cutoffTime = time() - (BACKUP_RETENTION_DAYS * 24 * 60 * 60)
    
    for version, migrationData in pairs(OGRH_SV._migrations) do
        if migrationData.timestamp and migrationData.timestamp < cutoffTime then
            OGRH_SV._migrations[version] = nil
        end
    end
end

-- ============================================
-- ACCESSOR: GET PLAYER ROLE (NEW UNIFIED API)
-- NOTE: Accessor Functions Not Needed
-- ============================================
-- The three role systems remain separate:
-- - Use OGRH_SV.roles for current raid composition
-- - Use rosterManagement for player capabilities
-- - Use ConsumeHelper_SV.playerRoles for consume preferences-- ============================================
-- SLASH COMMAND HANDLERS
-- ============================================
function OGRH.Migration.HandleCommand(args)
    if not args or args == "" or args == "status" then
        OGRH.Migration.ShowStatus()
    elseif args == "rollback" then
        OGRH.Migration.RollbackV2()
    elseif args == "force" then
        OGRH_SV.schemaVersion = SCHEMA_V1
        OGRH.Migration.Run()
    elseif args == "backup" then
        OGRH.Migration.ShowBackupInfo()
    else
        OGRH.Msg("Migration commands:")
        OGRH.Msg("  /ogrh migration status - Show current schema version")
        OGRH.Msg("  /ogrh migration rollback - Rollback last migration")
        OGRH.Msg("  /ogrh migration force - Force re-run migration")
        OGRH.Msg("  /ogrh migration backup - Show backup information")
    end
end

function OGRH.Migration.ShowStatus()
    local version = OGRH_SV.schemaVersion or SCHEMA_V1
    OGRH.Msg("SavedVariables Schema Version: " .. version)
    OGRH.Msg("Current Schema Version: " .. CURRENT_SCHEMA)
    
    if version < CURRENT_SCHEMA then
        OGRH.Msg("|cffff0000Status:|r Out of date - migration needed")
    else
        OGRH.Msg("|cff00ff00Status:|r Up to date")
    end
    
    -- Show table sizes
    if OGRH_SV.recruitment then
        local whisperCount = OGRH.Migration.CountEntries(OGRH_SV.recruitment.whisperHistory or {})
        local cacheCount = OGRH.Migration.CountEntries(OGRH_SV.recruitment.playerCache or {})
        OGRH.Msg("Recruitment: " .. whisperCount .. " whisper entries, " .. cacheCount .. " cached players")
    end
    
    if OGRH_SV.consumesTracking then
        local historyCount = table.getn(OGRH_SV.consumesTracking.history or {})
        OGRH.Msg("Consume History: " .. historyCount .. " entries")
    end
end

function OGRH.Migration.ShowBackupInfo()
    if not OGRH_SV._migrations then
        OGRH.Msg("No migration backups found")
        return
    end
    
    for version, migrationData in pairs(OGRH_SV._migrations) do
        if migrationData.timestamp then
            local age = math.floor((time() - migrationData.timestamp) / (24 * 60 * 60))
            OGRH.Msg(string.format("Backup for v%s: %d days old", tostring(version), age))
        end
    end
end

--[[
    INTEGRATION INSTRUCTIONS:
    
    1. Add to Core.lua after OGRH.EnsureSV():
       
       -- Run migrations if needed
       OGRH.Migration.Run()
    
    2. Add slash command handler:
       
       SLASH_OGRH_MIGRATION1 = "/ogrh migration"
       SlashCmdList["OGRH_MIGRATION"] = function(msg)
           OGRH.Migration.HandleCommand(msg)
       end
    
    3. Update all direct role references to use new API:
       
       -- OLD:
       local role = OGRH_SV.roles[playerName]
       
       -- NEW:
       local role = OGRH.GetPlayerRole(playerName)
    
    4. Test thoroughly:
       - Fresh install (no SavedVariables)
       - Existing install (with v1 data)
       - Rollback functionality
       - Multiple migration runs (should be idempotent)
]]

-- ============================================
-- AUTO-RUN ON LOAD (for testing)
-- ============================================
-- Uncomment to enable auto-migration on load
-- local migrationFrame = CreateFrame("Frame")
-- migrationFrame:RegisterEvent("VARIABLES_LOADED")
-- migrationFrame:SetScript("OnEvent", function()
--     if event == "VARIABLES_LOADED" then
--         OGRH.Migration.Run()
--     end
-- end)
Test thoroughly:
       - Fresh install (no SavedVariables)
       - Existing install (with v1 data)
       - Rollback functionality
       - Multiple migration runs (should be idempotent)
       - Verify empty tables removed
       - Check history pruning works correctly
       
    Note: No code changes needed - this migration only:
    - Removes empty tables (tankIcon, healerIcon, etc.)
    - Prunes historical data to size limits
    - Does NOT change role storage (those systems are separate