-- OGRH_SyncRouter.lua (Turtle-WoW 1.12)
-- Context-aware sync level routing
-- Phase 1: Core Infrastructure

OGRH = OGRH or {}
OGRH.SyncRouter = {}

--[[
    Sync Router State
    
    Determines appropriate sync level based on:
    - Active Raid context (active vs non-active)
    - UI context (EncounterSetup vs EncounterMgmt)
    - Change type (structure, assignments, settings)
]]

OGRH.SyncRouter.State = {
    currentContext = "unknown",  -- "active_mgmt", "active_setup", "nonactive_setup"
    activeRaidIdx = 1,           -- Always 1 (Active Raid at raids[1])
}

--[[
    Context Detection
]]

-- Determine current context based on active raid and UI
function OGRH.SyncRouter.DetectContext(raidIdx)
    -- Active Raid is always at index 1
    local isActiveRaid = (raidIdx == 1)
    
    -- Check which UI is open
    local isSetupOpen = OGRH.EncounterSetup and OGRH.EncounterSetup.IsOpen and OGRH.EncounterSetup.IsOpen()
    local isMgmtOpen = OGRH.EncounterMgmt and OGRH.EncounterMgmt.IsOpen and OGRH.EncounterMgmt.IsOpen()
    
    if isActiveRaid then
        if isMgmtOpen then
            return "active_mgmt"    -- REALTIME sync
        else
            return "active_setup"   -- BATCH sync
        end
    else
        return "nonactive_setup"    -- BATCH sync (or MANUAL for structure)
    end
end

--[[
    Sync Level Decision Logic
]]

-- Determine sync level for a change
function OGRH.SyncRouter.DetermineSyncLevel(raidIdx, componentType, changeType)
    local context = OGRH.SyncRouter.DetectContext(raidIdx)
    
    -- Structure changes (raid/encounter CRUD)
    if componentType == "structure" then
        -- Structure changes are MANUAL (admin must explicitly push)
        return "MANUAL"
    end
    
    -- Active Raid - EncounterMgmt (Live Execution)
    if context == "active_mgmt" then
        -- Assignment changes during live execution
        if componentType == "roles" or componentType == "assignments" or componentType == "marks" or componentType == "numbers" then
            return "REALTIME"  -- Instant sync for combat-critical data
        end
        -- Settings changes during execution
        if componentType == "settings" or componentType == "metadata" then
            return "BATCH"     -- Batch non-critical changes
        end
    end
    
    -- Active Raid - EncounterSetup (Pre-Planning)
    if context == "active_setup" then
        -- All changes are batched during setup
        return "BATCH"
    end
    
    -- Non-Active Raid - Setup Only
    if context == "nonactive_setup" then
        -- All changes are batched for saved raids
        return "BATCH"
    end
    
    -- Default to BATCH
    return "BATCH"
end

--[[
    Scope Detection
]]

-- Extract scope from change metadata
function OGRH.SyncRouter.ExtractScope(raidIdx, encounterIdx, componentType)
    local sv = OGRH.SVM and OGRH.SVM.GetActiveSchema() or OGRH_SV.v2
    if not sv or not sv.encounterMgmt or not sv.encounterMgmt.raids then
        return {type = "unknown"}
    end
    
    local raid = sv.encounterMgmt.raids[raidIdx]
    if not raid then
        return {type = "unknown"}
    end
    
    local raidName = raid.name or raid.displayName or "Unknown"
    
    if encounterIdx then
        local encounter = raid.encounters and raid.encounters[encounterIdx]
        local encounterName = encounter and (encounter.name or encounter.displayName or "Unknown")
        
        return {
            type = "encounter",
            raid = raidName,
            raidIdx = raidIdx,
            encounter = encounterName,
            encounterIdx = encounterIdx,
            component = componentType
        }
    else
        return {
            type = "raid",
            raid = raidName,
            raidIdx = raidIdx,
            component = componentType
        }
    end
end

--[[
    Public API: Route Sync Decision
]]

-- Main routing function called by SVM
function OGRH.SyncRouter.Route(path, value, changeType)
    -- Parse path to extract raid/encounter indices
    local raidIdx, encounterIdx, componentType = OGRH.SyncRouter.ParsePath(path)
    
    -- Determine sync level
    local syncLevel = OGRH.SyncRouter.DetermineSyncLevel(raidIdx, componentType, changeType)
    
    -- Extract scope
    local scope = OGRH.SyncRouter.ExtractScope(raidIdx, encounterIdx, componentType)
    
    -- Build sync metadata
    local syncMetadata = {
        syncLevel = syncLevel,
        componentType = componentType,
        scope = scope,
        changeType = changeType
    }
    
    return syncMetadata
end

--[[
    Path Parsing
]]

-- Parse path to extract raid/encounter indices and component type
function OGRH.SyncRouter.ParsePath(path)
    -- Example paths:
    -- "encounterMgmt.raids.1.encounters.2.roles"
    -- "encounterMgmt.raids.1.name"
    -- "roles.PlayerName"
    -- "permissions.currentAdmin"
    
    local raidIdx = nil
    local encounterIdx = nil
    local componentType = "unknown"
    
    -- Check if path is for encounterMgmt
    if string.find(path, "^encounterMgmt%.") then
        -- Extract raid index
        local raidIdxStr = string.match(path, "raids%.(%d+)")
        if raidIdxStr then
            raidIdx = tonumber(raidIdxStr)
        end
        
        -- Extract encounter index
        local encounterIdxStr = string.match(path, "encounters%.(%d+)")
        if encounterIdxStr then
            encounterIdx = tonumber(encounterIdxStr)
        end
        
        -- Extract component type
        if string.find(path, "%.roles") then
            componentType = "roles"
        elseif string.find(path, "%.advancedSettings") then
            componentType = "settings"
        elseif string.find(path, "%.name") or string.find(path, "%.displayName") then
            componentType = "metadata"
        end
    else
        -- Global components
        if string.find(path, "^roles%.") then
            componentType = "roles"
        elseif string.find(path, "^permissions%.") then
            componentType = "permissions"
        elseif string.find(path, "^versioning%.") then
            componentType = "versioning"
        elseif string.find(path, "^invites%.") then
            componentType = "invites"
        elseif string.find(path, "^consumes") then
            componentType = "consumes"
        elseif string.find(path, "^tradeItems") then
            componentType = "tradeItems"
        end
    end
    
    return raidIdx, encounterIdx, componentType
end

--[[
    Helper: Check if Raid is Active
]]

-- Check if given raid index is the Active Raid
function OGRH.SyncRouter.IsActiveRaid(raidIdx)
    return raidIdx == 1
end

--[[
    Initialization
]]

function OGRH.SyncRouter.Initialize()
    -- Module initialized
end

-- Auto-initialize on load
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:SetScript("OnEvent", function()
    if event == "ADDON_LOADED" and arg1 == "OG-RaidHelper" then
        OGRH.ScheduleTimer(function()
            OGRH.SyncRouter.Initialize()
        end, 0.5)
    end
end)
