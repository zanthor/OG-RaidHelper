-- OGRH_Core.lua  (Turtle-WoW 1.12)
OGRH = OGRH or {}
OGRH.ADDON = "OG-RaidHelper"
OGRH.CMD   = "ogrh"
OGRH.ADDON_PREFIX = "OGRH"
OGRH.VERSION = GetAddOnMetadata("OG-RaidHelper", "Version") or "Unknown"

-- Initialize Migration namespace (loaded later from SavedVariablesManager)
OGRH.Migration = OGRH.Migration or {}

-- RollFor version detection
OGRH.ROLLFOR_REQUIRED_VERSION = "4.8.1"
OGRH.ROLLFOR_AVAILABLE = false

-- Check if RollFor is installed and has the required version
function OGRH.CheckRollForVersion()
  local rollForVersion = GetAddOnMetadata("RollFor", "Version")
  if rollForVersion and rollForVersion == OGRH.ROLLFOR_REQUIRED_VERSION then
    OGRH.ROLLFOR_AVAILABLE = true
    return true
  end
  OGRH.ROLLFOR_AVAILABLE = false
  return false
end

-- Initialize RollFor check on load
OGRH.CheckRollForVersion()

-- Player class cache (persists across sessions)
OGRH.classCache = OGRH.classCache or {}

-- Standard announcement colors
OGRH.COLOR = {
  HEADER = "|cff00ff00",   -- Bright Green
  ROLE = "|cffffcc00",     -- Bright Yellow
  ANNOUNCE = "|cffff8800", -- Orange
  RESET = "|r",
  
  -- Class colors
  CLASS = {
    WARRIOR = "|cffC79C6E",
    PALADIN = "|cffF58CBA",
    HUNTER = "|cffABD473",
    ROGUE = "|cffFFF569",
    PRIEST = "|cffFFFFFF",
    SHAMAN = "|cff0070DE",
    MAGE = "|cff69CCF0",
    WARLOCK = "|cff9482C9",
    DRUID = "|cffFF7D0A"
  },
  
  -- Raid marker colors
  MARK = {
    [1] = "|cffFFFF00", -- Star - Yellow
    [2] = "|cffFF7F00", -- Circle - Orange
    [3] = "|cffFF00FF", -- Diamond - Purple/Magenta
    [4] = "|cff00FF00", -- Triangle - Green
    [5] = "|cffC0C0FF", -- Moon - Light Blue/Silver
    [6] = "|cff0080FF", -- Square - Blue
    [7] = "|cffFF0000", -- Cross - Red
    [8] = "|cffFFFFFF"  -- Skull - White
  }
}

function OGRH.EnsureSV()
  -- Initialize base OGRH_SV table if needed
  if not OGRH_SV then
    OGRH_SV = {}
  end
  
  -- Determine schema version (default to v2 for new installs)
  if not OGRH_SV.schemaVersion then
    -- Check if v1 data exists (upgrading from old version)
    local hasV1Data = OGRH_SV.roles or OGRH_SV.encounterMgmt or OGRH_SV.pollTime
    
    if hasV1Data then
      -- Legacy installation - keep using v1 (migration will happen later)
      OGRH_SV.schemaVersion = "v1"
    else
      -- New installation - use v2 from the start
      OGRH_SV.schemaVersion = "v2"
      OGRH_SV.v2 = {}
    end
  end
  
  -- ============================================
  -- AUTO-PURGE: Remove v1 data after 15 days
  -- ============================================
  if OGRH_SV.v2 and OGRH_SV.v2.migrationMeta and OGRH_SV.v2.migrationMeta.migrationDate then
    local migrationDate = OGRH_SV.v2.migrationMeta.migrationDate
    local currentTime = time()
    local daysSinceMigration = (currentTime - migrationDate) / 86400  -- 86400 seconds in a day
    
    if daysSinceMigration >= 15 then
      -- Check if v1 data still exists (anything except v2 and schemaVersion)
      local hasV1Data = false
      local purgedKeys = {}
      for key, _ in pairs(OGRH_SV) do
        if key ~= "v2" and key ~= "schemaVersion" then
          hasV1Data = true
          table.insert(purgedKeys, key)
        end
      end
      
      if hasV1Data then
OGRH.Msg("|cffffaa00[RH-Migration]|r v1 data is 15+ days old. Auto-purging...")
OGRH.Msg("|cff00ff00[RH-Migration]|r Purging keys: " .. table.concat(purgedKeys, ", "))
        -- Direct deletion (bypass PurgeV1Data checks)
        for i = 1, table.getn(purgedKeys) do
          OGRH_SV[purgedKeys[i]] = nil
        end
        -- Clean up deprecated v2 fields
        if OGRH_SV.v2.order then OGRH_SV.v2.order = nil end
        if OGRH_SV.v2.Permissions then OGRH_SV.v2.Permissions = nil end
        if OGRH_SV.v2.Versioning then OGRH_SV.v2.Versioning = nil end
        if OGRH.MainUI and OGRH.MainUI.State and OGRH.MainUI.State.debug then
          OGRH.Msg(string.format("|cff00ff00[RH-Migration]|r Auto-purged %d v1 keys", table.getn(purgedKeys)))
        end
      end
    end
  end
  
  -- Bootstrap schema-specific data based on active version
  if OGRH_SV.schemaVersion == "v2" then
    -- Initialize v2 schema
    if not OGRH_SV.v2 then OGRH_SV.v2 = {} end
    
    -- Core settings
    if OGRH_SV.v2.pollTime == nil then OGRH_SV.v2.pollTime = 5 end
    if OGRH_SV.v2.allowRemoteReadyCheck == nil then OGRH_SV.v2.allowRemoteReadyCheck = true end
    if OGRH_SV.v2.syncLocked == nil then OGRH_SV.v2.syncLocked = false end
    
    -- UI state
    if not OGRH_SV.v2.ui then OGRH_SV.v2.ui = {} end
    if OGRH_SV.v2.ui.minimized == nil then OGRH_SV.v2.ui.minimized = false end
    
    -- Data structures
    if not OGRH_SV.v2.tradeItems then OGRH_SV.v2.tradeItems = {} end
    if not OGRH_SV.v2.consumes then OGRH_SV.v2.consumes = {} end
    
  else
    -- Initialize v1 schema (legacy)
    if not OGRH_SV.roles then OGRH_SV.roles = {} end
    if OGRH_SV.pollTime == nil then OGRH_SV.pollTime = 5 end
    if not OGRH_SV.tankCategory then OGRH_SV.tankCategory = {} end
    if not OGRH_SV.healerBoss then OGRH_SV.healerBoss = {} end
    if not OGRH_SV.ui then OGRH_SV.ui = {} end
    if OGRH_SV.ui.minimized == nil then OGRH_SV.ui.minimized = false end
    if not OGRH_SV.tankIcon then OGRH_SV.tankIcon = {} end
    if not OGRH_SV.healerIcon then OGRH_SV.healerIcon = {} end
    if not OGRH_SV.rolesUI then OGRH_SV.rolesUI = {} end
    if not OGRH_SV.playerAssignments then OGRH_SV.playerAssignments = {} end
    if OGRH_SV.allowRemoteReadyCheck == nil then OGRH_SV.allowRemoteReadyCheck = true end
    if not OGRH_SV.tradeItems then OGRH_SV.tradeItems = {} end
    if OGRH_SV.syncLocked == nil then OGRH_SV.syncLocked = false end
    
    -- Migrate old healerTankAssigns to playerAssignments (as icons)
    if OGRH_SV.healerTankAssigns and not OGRH_SV._assignmentsMigrated then
      for name, iconId in pairs(OGRH_SV.healerTankAssigns) do
        if iconId and iconId >= 1 and iconId <= 8 then
          OGRH_SV.playerAssignments[name] = {type = "icon", value = iconId}
        end
      end
      OGRH_SV._assignmentsMigrated = true
    end
  end
end
local _svf = CreateFrame("Frame")
_svf:RegisterEvent("VARIABLES_LOADED")
_svf:RegisterEvent("PLAYER_ENTERING_WORLD")
_svf:RegisterEvent("RAID_ROSTER_UPDATE")
local hasPolledOnce = false

_svf:SetScript("OnEvent", function() 
  if event == "VARIABLES_LOADED" then 
  OGRH.EnsureSV()
  OGRH.MigrateRGOSettings()  -- Migrate and clean up deprecated RGO settings
  
  -- ============================================
  -- AUTO-MIGRATION: Check schema version
  -- ============================================
  if OGRH.Migration and OGRH.Migration.MigrateToV2 then
    -- Check if v2 exists and is active
    local needsSetup = false
    local isCleanInstall = false
    
    if not OGRH_SV.v2 then
      -- No v2 at all - check if clean install or migration needed
      needsSetup = true
      -- Check if this is a clean install (no v1 data)
      local hasV1Data = false
      for key, _ in pairs(OGRH_SV) do
        if key ~= "v2" and key ~= "schemaVersion" and key ~= "firstRun" then
          hasV1Data = true
          break
        end
      end
      isCleanInstall = not hasV1Data
    elseif not OGRH_SV.v2.encounterMgmt or OGRH_SV.v2.encounterMgmt.schemaVersion ~= 2 then
      -- v2 exists but not active - needs migration
      needsSetup = true
    end
    
    if needsSetup then
      -- CRITICAL: Set firstRun=false IMMEDIATELY to prevent LoadFactoryDefaults from running
      OGRH_SV.firstRun = false
      
      if isCleanInstall then
        -- Clean install: Initialize v2 from defaults, no migration
OGRH.Msg("|cffffaa00[RH-Migration]|r First-time setup detected. Initializing v2 from defaults...")
        OGRH_SV.v2 = {}
        OGRH_SV.schemaVersion = "v2"
        if OGRH.Sync and OGRH.Sync.LoadDefaults then
          OGRH.Sync.LoadDefaults()
        end
      else
        -- Has v1 data: Migrate v1 → v2, never touch defaults
OGRH.Msg("|cffffaa00[RH-Migration]|r Detected v1 schema. Auto-migrating to v2...")
        OGRH.Migration.MigrateToV2(false)
        
        -- Auto-cutover to v2
        if OGRH_SV.v2 and OGRH.Migration.CutoverToV2 then
OGRH.Msg("|cffffaa00[RH-Migration]|r Auto-activating v2 schema...")
          OGRH.Migration.CutoverToV2()
        end
      end
      
      -- Refresh ConsumesTracking cache after migration
      if OGRH.ConsumesTracking and OGRH.ConsumesTracking.trackOnPullEnabled ~= nil then
        OGRH.ConsumesTracking.trackOnPullEnabled = OGRH.SVM.GetPath("consumesTracking.trackOnPull") or false
      end
      
      -- Refresh Invites cache after migration
      if OGRH.Invites and OGRH.Invites.cachedCurrentSource then
        OGRH.Invites.cachedCurrentSource = OGRH.SVM.GetPath("invites.currentSource")
      end
    end
  end
  
  -- Upgrade encounter data structure if needed (must happen early before any UI access)
  if OGRH.UpgradeEncounterDataStructure then
    OGRH.UpgradeEncounterDataStructure()
  end
  
  -- Ensure Active Raid exists (Phase 1: Core Infrastructure)
  if OGRH_SV.schemaVersion == "v2" then
    OGRH.EnsureActiveRaid()
  end
  
  -- REMOVED: LoadFactoryDefaults - handled in migration block above
  -- firstRun flag is now set during migration/setup to prevent defaults from overwriting migrated data
  
  -- Initialize Phase 1 infrastructure systems
  if OGRH.Permissions and OGRH.Permissions.Initialize then
    OGRH.Permissions.Initialize()
  end
  
  if OGRH.Versioning and OGRH.Versioning.Initialize then
    OGRH.Versioning.Initialize()
  end
  
  if OGRH.MessageRouter and OGRH.MessageRouter.Initialize then
    OGRH.MessageRouter.Initialize()
  end
  
  -- Initialize Phase 2 sync system
  if OGRH.Sync and OGRH.Sync.Initialize then
    OGRH.Sync.Initialize()
  end
  
  -- Initialize sync systems
  if OGRH.SyncIntegrity and OGRH.SyncIntegrity.Initialize then
    OGRH.SyncIntegrity.Initialize()
  end
  
  if OGRH.SyncGranular and OGRH.SyncGranular.Initialize then
    OGRH.SyncGranular.Initialize()
  end
  
  elseif event == "PLAYER_ENTERING_WORLD" then
    -- Clean up v1 keys if we're in v2 mode (after all modules have loaded)
    -- Clean up deprecated v2 fields only (keep v1 data for rollback)
    if OGRH_SV.schemaVersion == "v2" and OGRH_SV.v2 then
      local deprecatedCount = 0
      if OGRH_SV.v2.order then OGRH_SV.v2.order = nil deprecatedCount = deprecatedCount + 1 end
      if OGRH_SV.v2.Permissions then OGRH_SV.v2.Permissions = nil deprecatedCount = deprecatedCount + 1 end
      if OGRH_SV.v2.Versioning then OGRH_SV.v2.Versioning = nil deprecatedCount = deprecatedCount + 1 end
      if deprecatedCount > 0 then
        OGRH.Msg("|cffffaa00[RH-Cleanup]|r Removed " .. deprecatedCount .. " deprecated v2 fields")
      end
    end
    
    -- Start integrity checks if we're the current admin (after login/reload)
    if OGRH.GetRaidAdmin and OGRH.StartIntegrityChecks then
      local currentAdmin = OGRH.GetRaidAdmin()
      if currentAdmin == UnitName("player") then
        OGRH.StartIntegrityChecks()
      end
    end
    
    -- Poll for admin when entering world (login, reload, zone)
    if UnitInRaid("player") and OGRH.PollForRaidAdmin then
      OGRH.PollForRaidAdmin()
      hasPolledOnce = true
    end
    
  elseif event == "RAID_ROSTER_UPDATE" then
    -- Poll for admin when joining a raid (only once per raid session)
    if UnitInRaid("player") and not hasPolledOnce and OGRH.PollForRaidAdmin then
      OGRH.PollForRaidAdmin()
      hasPolledOnce = true
    elseif not UnitInRaid("player") then
      hasPolledOnce = false  -- Reset flag when leaving raid
    end
  end
end)
OGRH.EnsureSV()

-- ========================================
-- CURRENT ENCOUNTER MANAGEMENT
-- ========================================

-- Get currently selected raid/encounter (read-only)
function OGRH.GetCurrentEncounter()
  -- v2 schema: Use indices instead of names
  local selectedRaidIndex = OGRH.SVM.Get("ui", "selectedRaidIndex")
  local selectedEncounterIndex = OGRH.SVM.Get("ui", "selectedEncounterIndex")
  
  return selectedRaidIndex, selectedEncounterIndex
end

-- Helper: Convert indices to names for backward compatibility
function OGRH.GetCurrentEncounterNames()
  local raidIdx, encIdx = OGRH.GetCurrentEncounter()
  if not raidIdx or not encIdx then
    return nil, nil
  end
  
  local raids = OGRH.SVM.GetPath("encounterMgmt.raids")
  if not raids or not raids[raidIdx] then
    return nil, nil
  end
  
  local raid = raids[raidIdx]
  local raidName = raid.name  -- Use name for lookups
  local encounterName = raid.encounters and raid.encounters[encIdx] and raid.encounters[encIdx].name
  
  return raidName, encounterName
end

-- Set currently selected raid/encounter (centralized write interface)
-- This is the ONLY function that should write selectedRaidIndex/selectedEncounterIndex
function OGRH.SetCurrentEncounter(raidIndex, encounterIndex)
  -- Check authorization first
  local isAdmin = OGRH.IsRaidAdmin and OGRH.IsRaidAdmin(UnitName("player"))
  local canNavigate = OGRH.CanNavigateEncounter and OGRH.CanNavigateEncounter()
  
  -- In raid: L/A only sends request, doesn't update local state
  if GetNumRaidMembers() > 0 and not isAdmin and canNavigate then
    -- Raid lead/assistant requests admin to change encounter
    local adminName = OGRH.GetRaidAdmin and OGRH.GetRaidAdmin()
    if adminName and adminName ~= UnitName("player") then
      OGRH.MessageRouter.SendTo(adminName, OGRH.MessageTypes.STATE.REQUEST_ENCOUNTER, {
        raidIndex = raidIndex,
        encounterIndex = encounterIndex,
        requester = UnitName("player")
      })
    end
    return  -- Don't update local state - wait for Admin broadcast
  end
  
  -- Admin or solo: update local state
  if raidIndex then
    OGRH.SVM.Set("ui", "selectedRaidIndex", raidIndex, {
      syncLevel = "REALTIME",
      componentType = "settings"
    })
  end
  
  if encounterIndex then
    OGRH.SVM.Set("ui", "selectedEncounterIndex", encounterIndex, {
      syncLevel = "REALTIME",
      componentType = "settings"
    })
  end
  
  -- Maintain backward compatibility: set selectedRaid and selectedEncounter for consume logging
  if raidIndex and encounterIndex then
    local raids = OGRH.SVM.GetPath("encounterMgmt.raids")
    if raids and raids[raidIndex] then
      local raid = raids[raidIndex]
      -- Use displayName for consume logging (e.g., "[AR] AQ40" not "[ACTIVE RAID]")
      local raidDisplayName = raid.displayName or raid.name
      OGRH.SVM.Set("ui", "selectedRaid", raidDisplayName)
      
      if raid.encounters and raid.encounters[encounterIndex] then
        local encounterName = raid.encounters[encounterIndex].name
        OGRH.SVM.Set("ui", "selectedEncounter", encounterName)
      end
    end
  end
  
  -- Admin broadcasts encounter change to all raid members
  if GetNumRaidMembers() > 0 and isAdmin and raidIndex and encounterIndex then
    OGRH.MessageRouter.Broadcast(OGRH.MessageTypes.STATE.CHANGE_ENCOUNTER, {
      raidIndex = raidIndex,
      encounterIndex = encounterIndex
    }, {
      priority = "HIGH"
    })
  end
end

-- ========================================
-- ACTIVE RAID MANAGEMENT (Phase 1: Core Infrastructure)
-- ========================================

-- Ensure Active Raid exists at raids[1] (automatically shifts existing raids if needed)
function OGRH.EnsureActiveRaid()
  local sv = OGRH.SVM and OGRH.SVM.GetActiveSchema() or OGRH_SV.v2
  if not sv then return false end
  
  -- Ensure encounterMgmt structure exists
  if not sv.encounterMgmt then sv.encounterMgmt = {} end
  if not sv.encounterMgmt.raids then sv.encounterMgmt.raids = {} end
  
  local raids = sv.encounterMgmt.raids
  
  -- Check if Active Raid already exists at correct position
  if table.getn(raids) > 0 and raids[1] and raids[1].id == "__active__" then
    return true  -- Active Raid already exists
  end
  
  -- Active Raid doesn't exist - need to create and shift existing raids
  local needsMigration = table.getn(raids) > 0
  
  -- Create Active Raid slot with default stub encounters
  local activeRaid = {
    id = "__active__",
    name = "[ACTIVE RAID]",
    displayName = "[AR] New Raid",
    sortOrder = 0,  -- Always first
    sourceRaidId = nil,  -- No source set yet
    encounters = {
      -- Default stub encounter for testing/initial state
      {
        id = 1,
        name = "Planning",
        displayName = "Raid Planning",
        sortOrder = 1,
        roles = {}  -- Empty roles array
      }
    }
  }
  
  -- Shift existing raids up by 1 index
  if needsMigration then
    OGRH.Msg("|cffffaa00[RH-ActiveRaid]|r Migrating existing raids to Active Raid structure...")
    for i = table.getn(raids), 1, -1 do
      raids[i + 1] = raids[i]
    end
    
    -- Update UI selectedRaid reference if it exists
    if sv.ui and sv.ui.selectedRaid then
      local oldRaidIdx = sv.ui.selectedRaid
      if type(oldRaidIdx) == "number" and oldRaidIdx > 0 then
        sv.ui.selectedRaid = oldRaidIdx + 1
      end
    end
    
    OGRH.Msg("|cff00ccff[RH-ActiveRaid]|r Shifted " .. table.getn(raids) .. " existing raids up by 1 index")
  end
  
  -- Insert Active Raid at index 1
  raids[1] = activeRaid
  
  OGRH.Msg("|cff00ccff[RH-ActiveRaid]|r Active Raid initialized at raids[1]")
  return true
end

-- Deep copy utility (declared before SetActiveRaid needs it)
local function DeepCopyForActiveRaid(obj, seen)
    if type(obj) ~= 'table' then return obj end
    if seen and seen[obj] then return seen[obj] end
    local s = seen or {}
    local res = setmetatable({}, getmetatable(obj))
    s[obj] = res
    for k, v in pairs(obj) do res[DeepCopyForActiveRaid(k, s)] = DeepCopyForActiveRaid(v, s) end
    return res
end

-- Set Active Raid source (copy from another raid)
function OGRH.SetActiveRaid(sourceRaidIdx)
  if OGRH.MainUI and OGRH.MainUI.State and OGRH.MainUI.State.debug then
    OGRH.Msg("|cff00ccff[RH-ActiveRaid]|r SetActiveRaid called with index: " .. tostring(sourceRaidIdx))
  end
  
  local sv = OGRH.SVM and OGRH.SVM.GetActiveSchema() or OGRH_SV.v2
  if not sv or not sv.encounterMgmt or not sv.encounterMgmt.raids then
    OGRH.Msg("|cffff0000[RH-ActiveRaid]|r ERROR: encounterMgmt not initialized")
    return false
  end
  
  local raids = sv.encounterMgmt.raids
  
  -- Validate source raid
  if sourceRaidIdx < 2 or sourceRaidIdx > table.getn(raids) then
    OGRH.Msg("|cffff0000[RH-ActiveRaid]|r ERROR: Invalid source raid index: " .. tostring(sourceRaidIdx))
    return false
  end
  
  local sourceRaid = raids[sourceRaidIdx]
  if not sourceRaid then
    OGRH.Msg("|cffff0000[RH-ActiveRaid]|r ERROR: Source raid not found")
    return false
  end
  
  -- Deep copy source raid to Active Raid
  local activeRaid = raids[1]
  if not activeRaid then
    OGRH.EnsureActiveRaid()
    activeRaid = raids[1]
  end
  
  -- Copy encounters from source
  activeRaid.encounters = DeepCopyForActiveRaid(sourceRaid.encounters)
  activeRaid.sourceRaidId = sourceRaid.id
  activeRaid.displayName = "[AR] " .. (sourceRaid.name or sourceRaid.displayName or "Unknown")
  
  if OGRH.MainUI and OGRH.MainUI.State and OGRH.MainUI.State.debug then
    OGRH.Msg(string.format("|cff00ccff[RH-ActiveRaid]|r Set Active Raid to: %s", sourceRaid.name or sourceRaid.displayName))
  end
  
  -- Set the UI to select the Active Raid by INDEX (Active Raid is always raids[1])
  if OGRH.MainUI and OGRH.MainUI.State and OGRH.MainUI.State.debug then
    OGRH.Msg("|cff00ccff[RH-ActiveRaid]|r Setting selectedRaidIndex = 1")
  end
  OGRH.SVM.Set("ui", "selectedRaidIndex", 1, {
    syncLevel = "REALTIME",
    componentType = "settings"
  })
  
  -- Automatically select the first encounter in the new Active Raid by INDEX
  if activeRaid.encounters and table.getn(activeRaid.encounters) > 0 then
    if OGRH.MainUI and OGRH.MainUI.State and OGRH.MainUI.State.debug then
      OGRH.Msg("|cff00ccff[RH-ActiveRaid]|r Setting selectedEncounterIndex = 1")
    end
    OGRH.SVM.Set("ui", "selectedEncounterIndex", 1, {
      syncLevel = "REALTIME",
      componentType = "settings"
    })
    if OGRH.MainUI and OGRH.MainUI.State and OGRH.MainUI.State.debug then
      OGRH.Msg(string.format("|cff00ccff[RH-ActiveRaid]|r Auto-selected first encounter (index 1): %s", activeRaid.encounters[1].name))
    end
  end
  
  -- Verify the write
  if OGRH.MainUI and OGRH.MainUI.State and OGRH.MainUI.State.debug then
    local readBack1 = OGRH.SVM.Get("ui", "selectedRaidIndex")
    local readBack2 = OGRH.SVM.Get("ui", "selectedEncounterIndex")
    OGRH.Msg(string.format("|cff00ccff[RH-ActiveRaid]|r Verification: selectedRaidIndex=%s, selectedEncounterIndex=%s", tostring(readBack1), tostring(readBack2)))
  end
  
  -- Trigger UI refresh
  if OGRH.UpdateEncounterNavButton then
    OGRH.UpdateEncounterNavButton()
  end
  
  -- Refresh Encounter Planning window if it's open
  if OGRH_EncounterFrame and OGRH_EncounterFrame:IsVisible() then
    if OGRH_EncounterFrame.RefreshRoleContainers then
      OGRH_EncounterFrame.RefreshRoleContainers()
    end
    if OGRH_EncounterFrame.UpdateAnnouncementBuilder then
      OGRH_EncounterFrame.UpdateAnnouncementBuilder()
    end
  end
  
  if OGRH.MainUI and OGRH.MainUI.RefreshDisplay then
    OGRH.MainUI.RefreshDisplay()
  end
  
  -- Trigger checksum broadcast after change (SyncIntegrity will respect cooldown)
  if OGRH.SyncIntegrity and OGRH.SyncIntegrity.RecordAdminModification then
    OGRH.SyncIntegrity.RecordAdminModification()
  end
  if OGRH.SyncIntegrity and OGRH.SyncIntegrity.BroadcastChecksums then
    OGRH.ScheduleTimer(function()
      OGRH.SyncIntegrity.BroadcastChecksums()
    end, 2)  -- Broadcast 2 seconds after change
  end
  
  return true
end

-- Get Active Raid data
function OGRH.GetActiveRaid()
  local sv = OGRH.SVM and OGRH.SVM.GetActiveSchema() or OGRH_SV.v2
  if not sv or not sv.encounterMgmt or not sv.encounterMgmt.raids then
    return nil
  end
  
  return sv.encounterMgmt.raids[1]
end

-- ========================================
-- SYNC PRIORITY HELPERS (Phase 3)
-- ========================================

-- Determine if a raid index is the Active Raid
function OGRH.IsActiveRaid(raidIdx)
  return raidIdx == 1
end

-- Get appropriate sync level based on context
-- EncounterMgmt (Planning window): REALTIME for Active Raid, BATCH for saved raids
-- EncounterSetup (Configuration window): BATCH for Active Raid, MANUAL for saved raids
function OGRH.GetSyncLevel(raidIdx, context)
  local isActive = OGRH.IsActiveRaid(raidIdx)
  
  if context == "EncounterMgmt" then
    -- Planning window: REALTIME for active, BATCH for saved
    return isActive and "REALTIME" or "BATCH"
  elseif context == "EncounterSetup" then
    -- Configuration window: BATCH for active, MANUAL for saved
    return isActive and "BATCH" or "MANUAL"
  else
    -- Default: BATCH for active, MANUAL for saved
    return isActive and "BATCH" or "MANUAL"
  end
end

-- ========================================
-- RGO SETTINGS MIGRATION
-- ========================================
-- Migrate deprecated RGO settings to new locations and clean up
function OGRH.MigrateRGOSettings()
  if not OGRH_SV.rgo then return end  -- Already cleaned up
  
  -- Migrate autoSortEnabled to invites namespace
  if OGRH_SV.rgo.autoSortEnabled ~= nil then
    if not OGRH_SV.invites then OGRH_SV.invites = {} end
    if OGRH_SV.invites.autoSortEnabled == nil then
      OGRH_SV.invites.autoSortEnabled = OGRH_SV.rgo.autoSortEnabled
    end
  end
  
  -- Migrate sortSpeed to sorting namespace
  if OGRH_SV.rgo.sortSpeed then
    if not OGRH_SV.sorting then OGRH_SV.sorting = {} end
    if OGRH_SV.sorting.speed == nil then
      OGRH_SV.sorting.speed = OGRH_SV.rgo.sortSpeed
    end
  end
  
  -- Remove entire RGO saved variables
  OGRH_SV.rgo = nil
  
  OGRH.Msg("|cff00ff00[Migration]|r Cleaned up deprecated RGO settings")
end

-- ========================================
-- SAVEDVARIABLES V2 MIGRATION SYSTEM
-- ========================================
-- Schema version constants
local SCHEMA_V1 = "v1"
local SCHEMA_V2 = "v2"

-- Deep copy utility (for migration and dual-write)
local function DeepCopy(obj, seen)
    if type(obj) ~= 'table' then return obj end
    if seen and seen[obj] then return seen[obj] end
    local s = seen or {}
    local res = setmetatable({}, getmetatable(obj))
    s[obj] = res
    for k, v in pairs(obj) do res[DeepCopy(k, s)] = DeepCopy(v, s) end
    return res
end

-- NOTE: OGRH.Migration.MigrateToV2() is defined in Infrastructure/Migration.lua
-- The version below is NOT USED - it's overwritten when Migration.lua loads
-- Keeping it commented for reference only

--[[ DEPRECATED - Migration function moved to Infrastructure/Migration.lua
-- Main migration: Create v2 schema
function OGRH.Migration.MigrateToV2(force)
    if not OGRH_SV then
        OGRH.Msg("|cffFF0000[Migration]|r Error: OGRH_SV not found")
        return false
    end
    
    if OGRH_SV.v2 and not force then
        OGRH.Msg("|cffFFFF00[Migration]|r v2 schema already exists. Use /ogrh migration rollback to reset.")
        OGRH.Msg("|cffFFFF00[Migration]|r Or use /ogrh migration create force to overwrite.")
        return false
    end
    
    if force and OGRH_SV.v2 then
        OGRH.Msg("|cffFFFF00[Migration]|r Force mode: Clearing existing v2 schema...")
        OGRH_SV.v2 = nil
    end
    
    OGRH.Msg("|cff00ff00[Migration]|r Creating v2 schema alongside original data...")
    
    -- Initialize schema version if not set
    if not OGRH_SV.schemaVersion then
        OGRH_SV.schemaVersion = SCHEMA_V1
    end
    
    -- Create v2 structure
    OGRH_SV.v2 = {}
    
    -- Phase 1: Copy v1 data to v2, excluding empty tables
    OGRH.Msg("|cff00ff00[Migration]|r Phase 1: Copying data to v2 (excluding empty tables)...")
    
    local emptyTables = {
        tankIcon = true,
        healerIcon = true,
        tankCategory = true,
        healerBoss = true
    }
    
    local copiedKeys = 0
    for key, value in pairs(OGRH_SV) do
        if key ~= "v2" and key ~= "schemaVersion" and not emptyTables[key] then
            OGRH_SV.v2[key] = DeepCopy(value)
            copiedKeys = copiedKeys + 1
            
            -- Debug logging for critical data
            if key == "tradeItems" or key == "consumes" or key == "playerAssignments" then
                local count = 0
                if type(value) == "table" then
                    for k, v in pairs(value) do
                        count = count + 1
                    end
                end
                OGRH.Msg(string.format("|cff00ff00[Migration]|r   Copied %s: %d items", key, count))
            end
        end
    end
    
    OGRH.Msg(string.format("|cff00ff00[Migration]|r Copied %d keys to v2", copiedKeys))
    OGRH.Msg("|cff00ff00[Migration]|r Excluded: tankIcon, healerIcon, tankCategory, healerBoss (empty)")
    
    -- Phase 2: Apply data retention to v2
    OGRH.Msg("|cff00ff00[Migration]|r Phase 2: Applying data retention policies...")
    
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
        OGRH.Msg(string.format("|cff00ff00[Migration]|r Pruned %d old recruitment entries (>30 days)", recruitmentPruned))
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
        OGRH.Msg(string.format("|cff00ff00[Migration]|r Pruned %d old consume history entries (>90 days)", consumePruned))
    end
    
    OGRH.Msg("|cff00ff00[Migration]|r ✓ v2 schema created successfully")
    OGRH.Msg("|cff00ff00[Migration]|r Original data preserved in OGRH_SV (v1)")
    OGRH.Msg("|cff00ff00[Migration]|r New data available in OGRH_SV.v2")
    OGRH.Msg(" ")
    OGRH.Msg("|cff00ff00[Migration]|r Next steps:")
    OGRH.Msg("|cff00ff00[Migration]|r   1. Test addon functionality")
    OGRH.Msg("|cff00ff00[Migration]|r   2. Run /ogrh migration validate")
    OGRH.Msg("|cff00ff00[Migration]|r   3. When ready: /ogrh migration cutover confirm")
    
    return true
end
--]] -- END DEPRECATED Migration function

-- Validation: Compare v1 vs v2
function OGRH.Migration.ValidateV2()
    if not OGRH_SV.v2 then
        OGRH.Msg("|cffFF0000[Validation]|r Error: v2 schema not found. Run /ogrh migration create first.")
        return false
    end
    
    OGRH.Msg("|cff00ff00[Validation]|r Comparing v1 and v2 schemas...")
    
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
    
    OGRH.Msg(string.format("|cff00ff00[Validation]|r v1 keys: %d", v1Keys))
    OGRH.Msg(string.format("|cff00ff00[Validation]|r v2 keys: %d", v2Keys))
    OGRH.Msg(string.format("|cff00ff00[Validation]|r Difference: %d keys removed", v1Keys - v2Keys))
    OGRH.Msg(" ")
    OGRH.Msg("|cff00ff00[Validation]|r Removed tables: tankIcon, healerIcon, tankCategory, healerBoss")
    OGRH.Msg("|cff00ff00[Validation]|r Data retention: recruitment (30 days), consumeTracking (90 days)")
    OGRH.Msg(" ")
    OGRH.Msg("|cff00ff00[Validation]|r ✓ Review addon functionality before cutover")
    
    return true
end

-- Cutover: Switch to v2
function OGRH.Migration.CutoverToV2()
    if not OGRH_SV.v2 then
        OGRH.Msg("|cffFF0000[Cutover]|r Error: v2 schema not found")
        return false
    end
    
    OGRH.Msg("|cffFFFF00[Cutover]|r Switching to v2 schema...")
    
    -- Create backup of v1
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
    
    OGRH.Msg("|cff00ff00[Cutover]|r ✓ Complete! Now using v2 schema")
    OGRH.Msg("|cff00ff00[Cutover]|r v1 backup saved to OGRH_SV_BACKUP_V1")
    OGRH.Msg("|cff00ff00[Cutover]|r Use /ogrh migration rollback if issues found")
    OGRH.Msg("|cffFFFF00[Cutover]|r Please /reload to ensure clean state")
    
    return true
end

-- Rollback: Revert to v1
function OGRH.Migration.RollbackFromV2()
    -- Scenario 1: v2 exists but not active yet
    if OGRH_SV.v2 then
        OGRH_SV.v2 = nil
        OGRH_SV.schemaVersion = SCHEMA_V1
        OGRH.Msg("|cff00ff00[Rollback]|r v2 schema removed, back to v1")
        return true
    end
    
    -- Scenario 2: Already cut over to v2, restore from backup
    if OGRH_SV.schemaVersion == SCHEMA_V2 and OGRH_SV_BACKUP_V1 then
        OGRH.Msg("|cff00ff00[Rollback]|r Restoring v1 from backup...")
        
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
        
        OGRH.Msg("|cff00ff00[Rollback]|r ✓ Restored v1 from backup")
        OGRH.Msg("|cffFFFF00[Rollback]|r Please /reload to ensure clean state")
        return true
    end
    
    OGRH.Msg("|cffFF0000[Rollback]|r Error: Nothing to rollback")
    OGRH.Msg("|cffFF0000[Rollback]|r Current schema: " .. (OGRH_SV.schemaVersion or "unknown"))
    return false
end

-- ========================================
-- TIMER SYSTEM (for delayed execution)
-- ========================================
OGRH.timers = {}
local timerFrame = CreateFrame("Frame")

timerFrame:SetScript("OnUpdate", function()
  local now = GetTime()
  for id, timer in pairs(OGRH.timers) do
    if now >= timer.when then
      timer.callback()
      if timer.repeating then
        timer.when = now + timer.delay
      else
        OGRH.timers[id] = nil
      end
    end
  end
end)

function OGRH.ScheduleTimer(callback, delay, repeating)
  local id = GetTime() .. math.random()
  OGRH.timers[id] = {
    callback = callback,
    when = GetTime() + delay,
    delay = delay,
    repeating = repeating
  }
  return id
end

function OGRH.CancelTimer(id)
  if id and OGRH.timers[id] then
    OGRH.timers[id] = nil
  end
end

-- ========================================
-- MODULE SYSTEM
-- ========================================
OGRH.Modules = OGRH.Modules or {}
OGRH.LoadedModules = OGRH.LoadedModules or {}

-- Register a module (called by module files on load)
function OGRH.RegisterModule(module)
  if not module or not module.id or not module.name then
    return
  end
  
  OGRH.Modules[module.id] = module
end

-- Get list of all available modules
function OGRH.GetAvailableModules()
  local modules = {}
  for id, module in pairs(OGRH.Modules) do
    table.insert(modules, {
      id = id,
      name = module.name,
      description = module.description or ""
    })
  end
  
  -- Sort by name
  table.sort(modules, function(a, b) return a.name < b.name end)
  
  return modules
end

-- Load modules for a specific role (from saved module list)
function OGRH.LoadModulesForRole(moduleIds)
  -- Unload all currently loaded modules first
  OGRH.UnloadAllModules()
  
  if not moduleIds or table.getn(moduleIds) == 0 then
    return
  end
  
  -- Load each module in order
  for i, moduleId in ipairs(moduleIds) do
    local module = OGRH.Modules[moduleId]
    if module and module.OnLoad then
      module:OnLoad()
      table.insert(OGRH.LoadedModules, module)
    end
  end
end

-- Unload all currently loaded modules
function OGRH.UnloadAllModules()
  for i, module in ipairs(OGRH.LoadedModules) do
    if module.OnUnload then
      module:OnUnload()
    end
  end
  OGRH.LoadedModules = {}
end

-- Clean up all modules (called on addon unload)
function OGRH.CleanupModules()
  OGRH.UnloadAllModules()
  for id, module in pairs(OGRH.Modules) do
    if module.OnCleanup then
      module:OnCleanup()
    end
  end
end

function OGRH.Trim(s) return string.gsub(s or "", "^%s*(.-)%s*$", "%1") end
function OGRH.Mod1(n,t) return math.mod(n-1, t)+1 end
function OGRH.CanRW() if IsRaidLeader and IsRaidLeader()==1 then return true end if IsRaidOfficer and IsRaidOfficer()==1 then return true end return false end
function OGRH.SayRW(text) if OGRH.CanRW() then SendChatMessage(text, "RAID_WARNING") else SendChatMessage(text, "RAID") end end

-- Helper function to create an item link for chat messages
-- Takes a consumeData table with primaryId, secondaryId, allowAlternate
-- Optional escapeForProcessing parameter - if true, uses || instead of | for tag replacement processing
-- Returns a formatted string with clickable item links ready for chat
function OGRH.FormatConsumeItemLinks(consumeData, escapeForProcessing)
  if not consumeData then return "" end
  
  local items = {}
  
  -- Add primary item
  if consumeData.primaryId then
    table.insert(items, consumeData.primaryId)
  end
  
  -- Add secondary item if alternate allowed
  if consumeData.allowAlternate and consumeData.secondaryId then
    table.insert(items, consumeData.secondaryId)
  end
  
  -- Build line with item links
  if table.getn(items) > 0 then
    local lineText = ""
    for j = 1, table.getn(items) do
      local itemId = items[j]
      local itemName, itemLink, quality = GetItemInfo(itemId)
      
      if j > 1 then
        lineText = lineText .. " / "
      end
      
      -- Construct chat link - itemLink from GetItemInfo is in format "item:id:0:0:0"
      if itemLink and itemName then
        local _, _, _, color = GetItemQualityColor(quality)
        lineText = lineText .. color .. "|H" .. itemLink .. "|h[" .. itemName .. "]|h|r"
      elseif itemName then
        lineText = lineText .. itemName
      else
        lineText = lineText .. "Item " .. itemId
      end
    end
    return lineText
  end
  
  return ""
end

-- Centralized window management - close all dialog windows except the specified one
-- Register legacy frame names with OGST library
if OGST and OGST.LegacyFrameNames then
  OGST.LegacyFrameNames = {
    "OGRH_EncounterFrame",
    "OGRH_RolesFrame",
    "OGRH_EncounterSetupFrame",
    "OGRH_InvitesFrame",
    "OGRH_SRValidationFrame",
    "OGRH_AddonAuditFrame",
    "OGRH_TradeSettingsFrame",
    "OGRH_AutoPromoteFrame",
    "OGRH_TradeMenu",
    "OGRH_EncountersMenu",
    "OGRH_ConsumesFrame",
    "OGRH_DataManagementFrame",
    "OGRH_RaidLeadSelectionFrame",
    "OGRH_RecruitmentFrame"
  }
end

-- Wrapper for OGST.CloseAllWindows (backward compatibility)
function OGRH.CloseAllWindows(exceptFrame)
  if OGST and OGST.CloseAllWindows then
    OGST.CloseAllWindows(exceptFrame)
  end
end

-- Show Structure Sync Panel (similar to OGRH_Sync panel)
function OGRH.ShowStructureSyncPanel(isSender, encounterName)
  if OGRH_StructureSyncPanel then
    OGRH_StructureSyncPanel:Show()
    OGRH.UpdateStructureSyncPanel(isSender, encounterName)
    -- Manually trigger registration since OnShow might not fire
    if OGRH.RegisterAuxiliaryPanel then
      OGRH.RegisterAuxiliaryPanel(OGRH_StructureSyncPanel, 30)
    end
    if OGRH.RepositionAuxiliaryPanels then
      OGRH.RepositionAuxiliaryPanels()
    end
    return
  end
  
  local frame = CreateFrame("Frame", "OGRH_StructureSyncPanel", UIParent)
  frame:SetWidth(200)
  frame:SetHeight(90)
  frame:SetFrameStrata("MEDIUM")
  frame:EnableMouse(false)
  
  frame:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 12,
    insets = {left = 2, right = 2, top = 2, bottom = 2}
  })
  frame:SetBackdropColor(0, 0, 0, 0.85)
  
  -- Register with auxiliary panel system (priority 30 = after ready check)
  frame:SetScript("OnShow", function()
    if OGRH.RegisterAuxiliaryPanel then
      OGRH.RegisterAuxiliaryPanel(this, 30)
    end
  end)
  
  frame:SetScript("OnHide", function()
    if OGRH.UnregisterAuxiliaryPanel then
      OGRH.UnregisterAuxiliaryPanel(this)
    end
  end)
  
  -- Title
  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOP", 0, -10)
  title:SetText("Structure Sync")
  frame.title = title
  
  -- Status text
  local statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  statusText:SetPoint("TOP", title, "BOTTOM", 0, -8)
  statusText:SetWidth(180)
  statusText:SetJustifyH("CENTER")
  frame.statusText = statusText
  
  -- Assign to global BEFORE any operations
  OGRH_StructureSyncPanel = frame
  
  OGRH.UpdateStructureSyncPanel(isSender, encounterName)
  
  -- Manually register BEFORE showing (OnShow might not fire in time)
  if OGRH.RegisterAuxiliaryPanel then
    OGRH.RegisterAuxiliaryPanel(frame, 30)
  end
  
  frame:Show()
  
  -- Trigger immediate positioning
  if OGRH.RepositionAuxiliaryPanels then
    OGRH.RepositionAuxiliaryPanels()
  end
end

-- Update Structure Sync Panel content
function OGRH.UpdateStructureSyncPanel(isSender, encounterName)
  if not OGRH_StructureSyncPanel then return end
  
  local frame = OGRH_StructureSyncPanel
  local encounterText = encounterName and (" for " .. encounterName) or ""
  
  if isSender then
    frame.statusText:SetText("Sending data" .. encounterText .. "...")
  else
    frame.statusText:SetText("Receiving data" .. encounterText .. "...")
  end
end

-- Show Structure Sync progress
function OGRH.ShowStructureSyncProgress(isSender, progress, complete, encounterName)
  if not OGRH_StructureSyncPanel then
    OGRH.ShowStructureSyncPanel(isSender, encounterName)
  end
  
  local frame = OGRH_StructureSyncPanel
  
  -- Ensure frame is registered and positioned
  if frame and OGRH.RegisterAuxiliaryPanel then
    OGRH.RegisterAuxiliaryPanel(frame, 30)
    if OGRH.RepositionAuxiliaryPanels then
      OGRH.RepositionAuxiliaryPanels()
    end
  end
  
  -- Create or update progress bar
  if not frame.progressBar then
    local bar = CreateFrame("StatusBar", nil, frame)
    bar:SetWidth(160)
    bar:SetHeight(16)
    bar:SetPoint("TOP", frame.statusText, "BOTTOM", 0, -10)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetStatusBarColor(0.2, 0.8, 0.2)
    bar:SetMinMaxValues(0, 100)
    
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(bar)
    bg:SetTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bg:SetVertexColor(0.2, 0.2, 0.2, 0.5)
    
    local text = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("CENTER", bar, "CENTER")
    bar.text = text
    
    frame.progressBar = bar
  end
  
  local bar = frame.progressBar
  bar:SetValue(progress)
  bar.text:SetText(string.format("%d%%", progress))
  
  if complete then
    bar:SetStatusBarColor(0.2, 1, 0.2)
    local encounterText = encounterName and (" for " .. encounterName) or ""
    frame.statusText:SetText((isSender and "Sync Complete!" or "Data Received!") .. encounterText)
    
    -- Hide panel after 3 seconds
    OGRH.ScheduleFunc(function()
      if OGRH_StructureSyncPanel then
        OGRH_StructureSyncPanel:Hide()
      end
    end, 3)
  else
    bar:SetStatusBarColor(0.2, 0.8, 0.2)
  end
  
  bar:Show()
  frame:Show()
end

-- Custom button styling with backdrop and rounded corners
function OGRH.StyleButton(button)
  if not button then return end
  
  -- Hide the default textures
  local normalTexture = button:GetNormalTexture()
  if normalTexture then
    normalTexture:SetTexture(nil)
  end
  
  local highlightTexture = button:GetHighlightTexture()
  if highlightTexture then
    highlightTexture:SetTexture(nil)
  end
  
  local pushedTexture = button:GetPushedTexture()
  if pushedTexture then
    pushedTexture:SetTexture(nil)
  end
  
  -- Add custom backdrop with rounded corners and border
  button:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 12,
    insets = { left = 2, right = 2, top = 2, bottom = 2 }
  })
  
  -- Ensure button is fully opaque
  button:SetAlpha(1.0)
  
  -- Dark teal background color
  button:SetBackdropColor(0.25, 0.35, 0.35, 1)
  button:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
  
  -- Add hover effect
  button:SetScript("OnEnter", function()
    this:SetBackdropColor(0.3, 0.45, 0.45, 1)
    this:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
  end)
  
  button:SetScript("OnLeave", function()
    this:SetBackdropColor(0.25, 0.35, 0.35, 1)
    this:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
  end)
end

-- ========================================
-- OGST LIBRARY WRAPPERS
-- ========================================
-- Wrapper functions maintain backward compatibility with existing code
-- while using the OGST library under the hood

-- Wrap OGST.CreateStandardWindow for backward compatibility
OGRH.CreateStandardWindow = function(config)
  if OGST and OGST.CreateStandardWindow then
    return OGST.CreateStandardWindow(config)
  end
  return nil
end

-- Wrap OGST.StyleButton for backward compatibility
OGRH.StyleButton = function(button)
  if OGST and OGST.StyleButton then
    OGST.StyleButton(button)
  end
end

-- Wrap OGST.CreateStandardMenu for backward compatibility
OGRH.CreateStandardMenu = function(config)
  if OGST and OGST.CreateStandardMenu then
    return OGST.CreateStandardMenu(config)
  end
  return nil
end

-- Wrap OGST.CreateStyledScrollList for backward compatibility
OGRH.CreateStyledScrollList = function(parent, width, height, hideScrollBar)
  if OGST and OGST.CreateStyledScrollList then
    return OGST.CreateStyledScrollList(parent, width, height, hideScrollBar)
  end
  return nil
end

-- Wrap OGST.CreateStyledListItem for backward compatibility
OGRH.CreateStyledListItem = function(parent, width, height, frameType)
  if OGST and OGST.CreateStyledListItem then
    return OGST.CreateStyledListItem(parent, width, height, frameType)
  end
  return nil
end

-- Wrap OGST.AddListItemButtons for backward compatibility
OGRH.AddListItemButtons = function(listItem, index, listLength, onMoveUp, onMoveDown, onDelete, hideUpDown)
  if OGST and OGST.AddListItemButtons then
    return OGST.AddListItemButtons(listItem, index, listLength, onMoveUp, onMoveDown, onDelete, hideUpDown)
  end
  return nil, nil, nil
end

-- Wrap OGST.SetListItemSelected for backward compatibility
OGRH.SetListItemSelected = function(item, isSelected)
  if OGST and OGST.SetListItemSelected then
    OGST.SetListItemSelected(item, isSelected)
  end
end

-- Wrap OGST.SetListItemColor for backward compatibility
OGRH.SetListItemColor = function(item, r, g, b, a)
  if OGST and OGST.SetListItemColor then
    OGST.SetListItemColor(item, r, g, b, a)
  end
end

-- Wrap OGST.CreateScrollingTextBox for backward compatibility
OGRH.CreateScrollingTextBox = function(parent, width, height)
  if OGST and OGST.CreateScrollingTextBox then
    return OGST.CreateScrollingTextBox(parent, width, height)
  end
  return nil
end

-- Wrap OGST.MakeFrameCloseOnEscape for backward compatibility
OGRH.MakeFrameCloseOnEscape = function(frame, frameName, closeCallback)
  if OGST and OGST.MakeFrameCloseOnEscape then
    OGST.MakeFrameCloseOnEscape(frame, frameName, closeCallback)
  end
end

-- Expose OGST constants through OGRH namespace
OGRH.LIST_COLORS = OGST and OGST.LIST_COLORS or {
  SELECTED = {r = 0.2, g = 0.4, b = 0.2, a = 0.8},
  INACTIVE = {r = 0.2, g = 0.2, b = 0.2, a = 0.5},
  HOVER = {r = 0.2, g = 0.5, b = 0.2, a = 0.5}
}

OGRH.LIST_ITEM_HEIGHT = OGST and OGST.LIST_ITEM_HEIGHT or 20
OGRH.LIST_ITEM_SPACING = OGST and OGST.LIST_ITEM_SPACING or 2

-- ========================================
-- AUXILIARY PANEL POSITIONING SYSTEM
-- ========================================
-- Centralized system for managing stacked panels below/above main UI
OGRH.AuxiliaryPanels = OGRH.AuxiliaryPanels or {
  panels = {}, -- Registered panels in display order
  updateFrame = nil
}

-- Register an auxiliary panel for automatic positioning
-- priority: lower numbers appear closer to main UI (1 = closest)
function OGRH.RegisterAuxiliaryPanel(frame, priority)
  if not frame then return end
  
  priority = priority or 100
  
  -- Check if already registered
  for i, panel in ipairs(OGRH.AuxiliaryPanels.panels) do
    if panel.frame == frame then
      panel.priority = priority
      OGRH.RepositionAuxiliaryPanels()
      return
    end
  end
  
  -- Add new panel
  table.insert(OGRH.AuxiliaryPanels.panels, {
    frame = frame,
    priority = priority
  })
  
  -- Sort by priority
  table.sort(OGRH.AuxiliaryPanels.panels, function(a, b)
    return a.priority < b.priority
  end)
  
  OGRH.RepositionAuxiliaryPanels()
end

-- Unregister an auxiliary panel
function OGRH.UnregisterAuxiliaryPanel(frame)
  if not frame then return end
  
  for i, panel in ipairs(OGRH.AuxiliaryPanels.panels) do
    if panel.frame == frame then
      table.remove(OGRH.AuxiliaryPanels.panels, i)
      OGRH.RepositionAuxiliaryPanels()
      return
    end
  end
end

-- Reposition all registered auxiliary panels
function OGRH.RepositionAuxiliaryPanels()
  if not OGRH_Main or not OGRH_Main:IsVisible() then return end
  
  local screenHeight = UIParent:GetHeight()
  local mainBottom = OGRH_Main:GetBottom()
  local mainTop = OGRH_Main:GetTop()
  
  if not mainBottom or not mainTop then return end
  
  -- Separate panels into visible below and above
  local visibleBelow = {}
  local visibleAbove = {}
  
  for _, panel in ipairs(OGRH.AuxiliaryPanels.panels) do
    if panel.frame:IsVisible() then
      local frameHeight = panel.frame:GetHeight() or 0
      table.insert(visibleBelow, {frame = panel.frame, height = frameHeight})
    end
  end
  
  -- Calculate total height of panels
  local totalBelowHeight = 0
  for _, panel in ipairs(visibleBelow) do
    totalBelowHeight = totalBelowHeight + panel.height
  end
  
  -- Position panels below or above based on available space
  local gap = -2  -- Negative gap to stack panels with small spacing
  
  if (mainBottom - totalBelowHeight) > 0 then
    -- Stack below main UI
    local currentAnchor = OGRH_Main
    local currentPoint = "BOTTOM"
    
    for _, panel in ipairs(visibleBelow) do
      panel.frame:ClearAllPoints()
      panel.frame:SetPoint("TOP", currentAnchor, currentPoint, 0, gap)
      currentAnchor = panel.frame
      currentPoint = "BOTTOM"
    end
  elseif (mainTop + totalBelowHeight) < screenHeight then
    -- Stack above main UI (reverse order)
    local currentAnchor = OGRH_Main
    local currentPoint = "TOP"
    
    for i = table.getn(visibleBelow), 1, -1 do
      local panel = visibleBelow[i]
      panel.frame:ClearAllPoints()
      panel.frame:SetPoint("BOTTOM", currentAnchor, currentPoint, 0, -gap)
      currentAnchor = panel.frame
      currentPoint = "TOP"
    end
  else
    -- Not enough space either way, fallback to individual positioning
    for _, panel in ipairs(visibleBelow) do
      panel.frame:ClearAllPoints()
      panel.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
  end
end

-- Initialize automatic repositioning on main UI movement or panel visibility changes
if not OGRH.AuxiliaryPanels.updateFrame then
  local updateFrame = CreateFrame("Frame")
  updateFrame.lastMainPos = nil
  updateFrame.lastPanelStates = {}
  
  updateFrame:SetScript("OnUpdate", function()
    if not OGRH_Main or not OGRH_Main:IsVisible() then return end
    
    -- Check for main UI movement
    local currentPos = OGRH_Main:GetLeft()
    if currentPos and currentPos ~= this.lastMainPos then
      this.lastMainPos = currentPos
      OGRH.RepositionAuxiliaryPanels()
    end
    
    -- Check for panel visibility changes
    local needsUpdate = false
    for i, panel in ipairs(OGRH.AuxiliaryPanels.panels) do
      local isVisible = panel.frame:IsVisible()
      if this.lastPanelStates[i] ~= isVisible then
        this.lastPanelStates[i] = isVisible
        needsUpdate = true
      end
    end
    
    if needsUpdate then
      OGRH.RepositionAuxiliaryPanels()
    end
  end)
  
  OGRH.AuxiliaryPanels.updateFrame = updateFrame
end

-- ========================================
-- GENERIC MENU BUILDER (Uses OGST Library)
-- ========================================
-- Creates a standardized menu/submenu system using OGST
-- Returns a menu object with methods: Show(), Hide(), AddItem(), etc.
function OGRH.CreateStandardMenu(config)
  return OGST.CreateStandardMenu(config)
end

-- Create a standardized scrolling list with frame
-- Returns: outerFrame, scrollFrame, scrollChild, scrollBar, contentWidth
function OGRH.CreateStyledScrollList(parent, width, height, hideScrollBar)
  if not parent then return nil end
  
  -- Outer container frame with backdrop
  local outerFrame = CreateFrame("Frame", nil, parent)
  outerFrame:SetWidth(width)
  outerFrame:SetHeight(height)
  outerFrame:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 12,
    insets = {left = 3, right = 3, top = 3, bottom = 3}
  })
  outerFrame:SetBackdropColor(0.15, 0.15, 0.15, 0.9)
  
  -- Adjust content width based on whether scrollbar will be shown
  local scrollBarSpace = hideScrollBar and 0 or 20
  
  -- Scroll frame inside the outer frame
  local scrollFrame = CreateFrame("ScrollFrame", nil, outerFrame)
  scrollFrame:SetPoint("TOPLEFT", outerFrame, "TOPLEFT", 5, -5)
  scrollFrame:SetPoint("BOTTOMRIGHT", outerFrame, "BOTTOMRIGHT", -(5 + scrollBarSpace), 5)
  
  -- Scroll child
  local scrollChild = CreateFrame("Frame", nil, scrollFrame)
  local contentWidth = width - 10 - scrollBarSpace  -- width - margins - scrollbar area
  scrollChild:SetWidth(contentWidth)
  scrollChild:SetHeight(1)
  scrollFrame:SetScrollChild(scrollChild)
  
  -- Scrollbar
  local scrollBar = CreateFrame("Slider", nil, outerFrame)
  scrollBar:SetPoint("TOPRIGHT", outerFrame, "TOPRIGHT", -5, -16)
  scrollBar:SetPoint("BOTTOMRIGHT", outerFrame, "BOTTOMRIGHT", -5, 16)
  scrollBar:SetWidth(16)
  scrollBar:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 8,
    insets = {left = 3, right = 3, top = 3, bottom = 3}
  })
  scrollBar:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
  scrollBar:SetOrientation("VERTICAL")
  scrollBar:SetMinMaxValues(0, 1)
  scrollBar:SetValue(0)
  scrollBar:SetValueStep(22)
  scrollBar:Hide()
  
  scrollBar:SetScript("OnValueChanged", function()
    scrollFrame:SetVerticalScroll(this:GetValue())
  end)
  
  -- Enable mouse wheel scrolling
  scrollFrame:EnableMouseWheel(true)
  scrollFrame:SetScript("OnMouseWheel", function()
    local delta = arg1
    local current, minVal, maxVal
    
    if hideScrollBar then
      -- When scrollbar is hidden, directly manipulate scroll position
      current = scrollFrame:GetVerticalScroll()
      maxVal = scrollChild:GetHeight() - scrollFrame:GetHeight()
      if maxVal < 0 then maxVal = 0 end
      minVal = 0
      
      local newScroll = current - (delta * 20)
      if newScroll < minVal then
        newScroll = minVal
      elseif newScroll > maxVal then
        newScroll = maxVal
      end
      scrollFrame:SetVerticalScroll(newScroll)
    else
      -- When scrollbar is visible, use it for scrolling
      if not scrollBar:IsShown() then return end
      current = scrollBar:GetValue()
      minVal, maxVal = scrollBar:GetMinMaxValues()
      if delta > 0 then
        scrollBar:SetValue(math.max(minVal, current - 22))
      else
        scrollBar:SetValue(math.min(maxVal, current + 22))
      end
    end
  end)
  
  return outerFrame, scrollFrame, scrollChild, scrollBar, contentWidth
end

-- Standard list item colors
OGRH.LIST_COLORS = {
  SELECTED = {r = 0.2, g = 0.4, b = 0.2, a = 0.8},    -- Green highlight for selected items
  INACTIVE = {r = 0.2, g = 0.2, b = 0.2, a = 0.5},    -- Gray for normal/inactive items
  HOVER = {r = 0.2, g = 0.5, b = 0.2, a = 0.5}        -- Brighter green for mouseover
  --HOVER = { r = 1.0, g = 0.0, b = 0.0, a = 0.5 }        -- Brighter green for mouseover
}

-- Standard list item dimensions
OGRH.LIST_ITEM_HEIGHT = 20
OGRH.LIST_ITEM_SPACING = 2

-- Add standardized up/down/delete buttons to a list item
-- Parameters:
--   listItem: The parent frame (list item) to attach buttons to
--   index: Current index in the list (1-based)
--   listLength: Total number of items in the list
--   onMoveUp: Callback function when up button clicked
--   onMoveDown: Callback function when down button clicked
--   onDelete: Callback function when delete button clicked
--   hideUpDown: Optional boolean, if true only shows delete button
-- Returns: deleteButton, downButton, upButton (for manual positioning if needed)
function OGRH.AddListItemButtons(listItem, index, listLength, onMoveUp, onMoveDown, onDelete, hideUpDown)
  if not listItem then return nil, nil, nil end
  
  local buttonSize = 32
  local buttonSpacing = -10
  
  -- Delete button (X mark)
  local deleteBtn = CreateFrame("Button", nil, listItem)
  deleteBtn:SetWidth(buttonSize)
  deleteBtn:SetHeight(buttonSize)
  deleteBtn:SetPoint("RIGHT", listItem, "RIGHT", -2, 0)
  deleteBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
  deleteBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight", "ADD")
  deleteBtn:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
  
  if onDelete then
    deleteBtn:SetScript("OnClick", onDelete)
  end
  
  -- If hideUpDown is true, only return delete button
  if hideUpDown then
    return deleteBtn, nil, nil
  end
  
  -- Down button (scroll down arrow)
  local downBtn = CreateFrame("Button", nil, listItem)
  downBtn:SetWidth(buttonSize)
  downBtn:SetHeight(buttonSize)
  downBtn:SetPoint("RIGHT", deleteBtn, "LEFT", -buttonSpacing, 0)
  downBtn:SetNormalTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up")
  downBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
  downBtn:SetPushedTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Down")
  downBtn:SetDisabledTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Disabled")
  
  -- Disable down button if this is the last item
  if index >= listLength then
    downBtn:Disable()
  elseif onMoveDown then
    downBtn:SetScript("OnClick", onMoveDown)
  end
  
  -- Up button (scroll up arrow)
  local upBtn = CreateFrame("Button", nil, listItem)
  upBtn:SetWidth(buttonSize)
  upBtn:SetHeight(buttonSize)
  upBtn:SetPoint("RIGHT", downBtn, "LEFT", -buttonSpacing, 0)
  upBtn:SetNormalTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Up")
  upBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
  upBtn:SetPushedTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Down")
  upBtn:SetDisabledTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Disabled")
  
  -- Disable up button if this is the first item
  if index <= 1 then
    upBtn:Disable()
  elseif onMoveUp then
    upBtn:SetScript("OnClick", onMoveUp)
  end
  
  return deleteBtn, downBtn, upBtn
end

-- Create a standardized list item with background and hover effects
-- Returns: itemFrame with .bg property for runtime color changes
function OGRH.CreateStyledListItem(parent, width, height, frameType)
  if not parent then return nil end
  
  height = height or OGRH.LIST_ITEM_HEIGHT  -- Use default if not specified
  frameType = frameType or "Button"  -- Default to Button for clickable items
  
  local item = CreateFrame(frameType, nil, parent)
  item:SetWidth(width)
  item:SetHeight(height)
  
  -- For Frame types, use backdrop instead of texture
  if frameType == "Frame" then
    item:SetBackdrop({
      bgFile = "Interface/Tooltips/UI-Tooltip-Background",
      tile = false,
      insets = {left = 0, right = 0, top = 0, bottom = 0}
    })
    item:SetBackdropColor(
      OGRH.LIST_COLORS.INACTIVE.r,
      OGRH.LIST_COLORS.INACTIVE.g,
      OGRH.LIST_COLORS.INACTIVE.b,
      OGRH.LIST_COLORS.INACTIVE.a
    )
    -- For consistency with Button types, store a reference to the item for color changes
    item.bg = item  -- Reference to self for SetBackdropColor
  else
    -- For Button types, use texture approach
    local bg = item:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    bg:SetVertexColor(
      OGRH.LIST_COLORS.INACTIVE.r,
      OGRH.LIST_COLORS.INACTIVE.g,
      OGRH.LIST_COLORS.INACTIVE.b,
      OGRH.LIST_COLORS.INACTIVE.a
    )
    bg:Show()  -- Explicitly show the texture
    item.bg = bg
  end
  
  item:Show()  -- Explicitly show the item frame
  
  -- Add hover and selection effects only for Button frames
  if frameType == "Button" then
    item:SetScript("OnEnter", function()
      -- Don't change color on hover if item is selected
      if not this.isSelected then
        this.bg:SetVertexColor(
          OGRH.LIST_COLORS.HOVER.r,
          OGRH.LIST_COLORS.HOVER.g,
          OGRH.LIST_COLORS.HOVER.b,
          OGRH.LIST_COLORS.HOVER.a
        )
      end
    end)
    
    item:SetScript("OnLeave", function()
      -- Restore color based on selection state
      if this.isSelected then
        this.bg:SetVertexColor(
          OGRH.LIST_COLORS.SELECTED.r,
          OGRH.LIST_COLORS.SELECTED.g,
          OGRH.LIST_COLORS.SELECTED.b,
          OGRH.LIST_COLORS.SELECTED.a
        )
      else
        this.bg:SetVertexColor(
          OGRH.LIST_COLORS.INACTIVE.r,
          OGRH.LIST_COLORS.INACTIVE.g,
          OGRH.LIST_COLORS.INACTIVE.b,
          OGRH.LIST_COLORS.INACTIVE.a
        )
      end
    end)
  end
  -- Frame type: no dynamic styling, just uses default INACTIVE color via backdrop
  
  return item
end

-- Create a scrolling multi-line text box with backdrop and scrollbar
-- Returns: backdrop, editBox, scrollFrame, scrollBar
function OGRH.CreateScrollingTextBox(parent, width, height)
  if not parent then return nil end
  
  -- Backdrop frame
  local backdrop = CreateFrame("Frame", nil, parent)
  backdrop:SetWidth(width)
  backdrop:SetHeight(height)
  backdrop:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 16,
    insets = {left = 3, right = 3, top = 3, bottom = 3}
  })
  backdrop:SetBackdropColor(0, 0, 0, 1)
  backdrop:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
  
  -- Scroll frame
  local scrollFrame = CreateFrame("ScrollFrame", nil, backdrop)
  scrollFrame:SetPoint("TOPLEFT", 5, -6)
  scrollFrame:SetPoint("BOTTOMRIGHT", -28, 6)
  
  -- Calculate actual content width: width - margins - scrollbar
  local contentWidth = width - 5 - 28 - 5
  
  -- Scroll child
  local scrollChild = CreateFrame("Frame", nil, scrollFrame)
  scrollFrame:SetScrollChild(scrollChild)
  scrollChild:SetWidth(contentWidth)
  scrollChild:SetHeight(400)
  
  -- Edit box
  local editBox = CreateFrame("EditBox", nil, scrollChild)
  editBox:SetPoint("TOPLEFT", 0, 0)
  editBox:SetWidth(contentWidth)
  editBox:SetHeight(400)
  editBox:SetMultiLine(true)
  editBox:SetAutoFocus(false)
  editBox:SetFontObject(ChatFontNormal)
  editBox:SetTextInsets(5, 5, 3, 3)
  editBox:SetScript("OnEscapePressed", function() this:ClearFocus() end)
  
  -- Scrollbar
  local scrollBar = CreateFrame("Slider", nil, backdrop)
  scrollBar:SetPoint("TOPRIGHT", backdrop, "TOPRIGHT", -5, -16)
  scrollBar:SetPoint("BOTTOMRIGHT", backdrop, "BOTTOMRIGHT", -5, 16)
  scrollBar:SetWidth(16)
  scrollBar:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 8,
    insets = {left = 3, right = 3, top = 3, bottom = 3}
  })
  scrollBar:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
  scrollBar:SetOrientation("VERTICAL")
  scrollBar:SetMinMaxValues(0, 1)
  scrollBar:SetValue(0)
  scrollBar:SetValueStep(22)
  scrollBar:SetScript("OnValueChanged", function()
    scrollFrame:SetVerticalScroll(this:GetValue())
  end)
  
  -- Update scroll range when text changes
  editBox:SetScript("OnTextChanged", function()
    local maxScroll = scrollChild:GetHeight() - scrollFrame:GetHeight()
    if maxScroll > 0 then
      scrollBar:SetMinMaxValues(0, maxScroll)
      scrollBar:Show()
    else
      scrollBar:Hide()
    end
  end)
  
  -- Mouse wheel scrolling
  scrollFrame:EnableMouseWheel(true)
  scrollFrame:SetScript("OnMouseWheel", function()
    local current = scrollBar:GetValue()
    local maxScroll = scrollChild:GetHeight() - scrollFrame:GetHeight()
    if maxScroll > 0 then
      if arg1 > 0 then
        scrollBar:SetValue(math.max(0, current - 22))
      else
        scrollBar:SetValue(math.min(maxScroll, current + 22))
      end
    end
  end)
  
  -- Make the backdrop clickable to focus the editbox
  backdrop:EnableMouse(true)
  backdrop:SetScript("OnMouseDown", function()
    editBox:SetFocus()
  end)
  
  return backdrop, editBox, scrollFrame, scrollBar
end

-- Helper function to set list item state (selected/inactive)
function OGRH.SetListItemSelected(item, isSelected)
  if not item or not item.bg then return end
  
  item.isSelected = isSelected
  
  local color = isSelected and OGRH.LIST_COLORS.SELECTED or OGRH.LIST_COLORS.INACTIVE
  
  -- Check if bg is a texture or the frame itself (backdrop)
  if item.bg.SetVertexColor then
    -- Texture-based (Button)
    item.bg:SetVertexColor(color.r, color.g, color.b, color.a)
  elseif item.bg.SetBackdropColor then
    -- Backdrop-based (Frame)
    item.bg:SetBackdropColor(color.r, color.g, color.b, color.a)
  end
end

-- Helper function to set custom list item color (if standard colors don't fit)
function OGRH.SetListItemColor(item, r, g, b, a)
  if not item or not item.bg then return end
  
  -- Check if bg is a texture or the frame itself (backdrop)
  if item.bg.SetVertexColor then
    -- Texture-based (Button)
    item.bg:SetVertexColor(r, g, b, a)
  elseif item.bg.SetBackdropColor then
    -- Backdrop-based (Frame)
    item.bg:SetBackdropColor(r, g, b, a)
  end
end

-- Helper function to make a frame close on ESC key
function OGRH.MakeFrameCloseOnEscape(frame, frameName, closeCallback)
  if not frame or not frameName then return end
  
  -- Check if already registered to avoid duplicates
  local alreadyRegistered = false
  for i = 1, table.getn(UISpecialFrames) do
    if UISpecialFrames[i] == frameName then
      alreadyRegistered = true
      break
    end
  end
  
  -- Register with Blizzard's UI panel system for ESC key handling
  -- This is the standard WoW method used by pfQuest and other addons
  if not alreadyRegistered then
    table.insert(UISpecialFrames, frameName)
  end
  
  -- If a custom close callback is provided, hook it to the frame's OnHide
  if closeCallback and type(closeCallback) == "function" then
    local originalOnHide = frame:GetScript("OnHide")
    frame:SetScript("OnHide", function()
      if originalOnHide then originalOnHide() end
      closeCallback()
    end)
  end
end

-- Ready Check Timer Frame
function OGRH.ShowReadyCheckTimer()
  -- Create frame if it doesn't exist
  if not OGRH_ReadyCheckTimerFrame then
    local frame = CreateFrame("Frame", "OGRH_ReadyCheckTimerFrame", UIParent)
    frame:SetWidth(180)
    frame:SetHeight(32)
    frame:SetFrameStrata("HIGH")
    frame:SetBackdrop({
      bgFile = "Interface/Tooltips/UI-Tooltip-Background",
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
      edgeSize = 12,
      insets = {left = 4, right = 4, top = 4, bottom = 4}
    })
    frame:SetBackdropColor(0, 0, 0, 0.85)
    frame:Hide()
    
    -- Text label
    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOP", frame, "TOP", 0, -6)
    label:SetText("Ready Check")
    frame.label = label
    
    -- Status bar
    local statusBar = CreateFrame("StatusBar", nil, frame)
    statusBar:SetPoint("LEFT", frame, "LEFT", 8, -8)
    statusBar:SetPoint("RIGHT", frame, "RIGHT", -8, -8)
    statusBar:SetHeight(10)
    statusBar:SetStatusBarTexture("Interface/TargetingFrame/UI-StatusBar")
    statusBar:SetStatusBarColor(0.2, 0.8, 0.2, 1)
    statusBar:SetMinMaxValues(0, 30)
    statusBar:SetValue(30)
    frame.statusBar = statusBar
    
    -- Timer text
    local timerText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    timerText:SetPoint("CENTER", statusBar, "CENTER", 0, 0)
    timerText:SetText("30s")
    frame.timerText = timerText
    
    -- OnUpdate script for countdown
    frame:SetScript("OnUpdate", function()
      if not frame.startTime or not frame:IsVisible() then return end
      
      local elapsed = GetTime() - frame.startTime
      local remaining = 30 - elapsed
      
      if remaining <= 0 then
        frame:Hide()
        return
      end
      
      -- Update bar and text
      frame.statusBar:SetValue(remaining)
      frame.timerText:SetText(string.format("%.1fs", remaining))
      
      -- Change color as time runs out
      if remaining <= 10 then
        frame.statusBar:SetStatusBarColor(0.8, 0.2, 0.2, 1)
      elseif remaining <= 20 then
        frame.statusBar:SetStatusBarColor(0.8, 0.8, 0.2, 1)
      end
    end)
    
    -- Register with auxiliary panel system (priority 20 = after consume monitor)
    frame:SetScript("OnShow", function()
      if OGRH.RegisterAuxiliaryPanel then
        OGRH.RegisterAuxiliaryPanel(this, 20)
      end
    end)
    
    frame:SetScript("OnHide", function()
      if OGRH.UnregisterAuxiliaryPanel then
        OGRH.UnregisterAuxiliaryPanel(this)
      end
    end)
    
    OGRH_ReadyCheckTimerFrame = frame
  end
  
  local frame = OGRH_ReadyCheckTimerFrame
  
  -- Reset and show
  frame.startTime = GetTime()
  frame.statusBar:SetValue(30)
  frame.statusBar:SetStatusBarColor(0.2, 0.8, 0.2, 1)
  frame.timerText:SetText("30s")
  frame:Show()
  
  -- Manually trigger registration and positioning (in case OnShow doesn't fire)
  if OGRH.RegisterAuxiliaryPanel then
    OGRH.RegisterAuxiliaryPanel(frame, 20)
  end
  if OGRH.RepositionAuxiliaryPanels then
    OGRH.RepositionAuxiliaryPanels()
  end
end

function OGRH.HideReadyCheckTimer()
  if OGRH_ReadyCheckTimerFrame then
    OGRH_ReadyCheckTimerFrame:Hide()
  end
end

-- Ready Check functionality
function OGRH.DoReadyCheck()
  -- Check if in a raid
  local numRaid = GetNumRaidMembers() or 0
  if numRaid == 0 then
    OGRH.Msg("You are not in a raid.")
    return
  end
  
  -- Check if player is raid leader
  if IsRaidLeader and IsRaidLeader() == 1 then
    -- Set flag to capture ready check responses
    OGRH.readyCheckInProgress = true
    OGRH.readyCheckResponses = {
      notReady = {},
      afk = {}
    }
    -- Show timer
    OGRH.ShowReadyCheckTimer()
    DoReadyCheck()
  -- Check if player is raid assistant
  elseif IsRaidOfficer and IsRaidOfficer() == 1 then
    -- Send addon message to raid asking leader to start ready check
    OGRH.MessageRouter.Broadcast(OGRH.MessageTypes.ADMIN.READY_REQUEST, "", {
      priority = "HIGH"
    })
    OGRH.Msg("Ready check request sent to raid leader.")
  else
    OGRH.Msg("You must be raid leader or assistant to start a ready check.")
  end
end

-- Helper function: Send announcement lines to raid chat
-- This is the recommended way to send announcements from any module
function OGRH.SendAnnouncement(lines, testMode)
  if not lines or table.getn(lines) == 0 then return end
  
  -- Send each line to chat
  local canRW = OGRH.CanRW()
  for _, line in ipairs(lines) do
    if testMode then
      -- In test mode, display to local chat frame
      DEFAULT_CHAT_FRAME:AddMessage(OGRH.Announce("OGRH: ") .. line)
    else
      -- Send to raid warning or raid chat
      if canRW then
        SendChatMessage(line, "RAID_WARNING")
      else
        SendChatMessage(line, "RAID")
      end
    end
  end
end
--[[
-- Send addon message with prefix (DEPRECATED - Use OGRH.MessageRouter instead)
function OGRH.SendAddonMessage(msgType, data)
  -- This function is deprecated and should not be used
  -- All code should use OGRH.MessageRouter.Broadcast() or OGRH.MessageRouter.SendTo()
  DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[RH-DEPRECATED]|r OGRH.SendAddonMessage() called with msgType: " .. tostring(msgType))
  DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[RH-DEPRECATED]|r This function is disabled. Please update caller to use MessageRouter.")
  -- SendAddonMessage call deliberately removed - do not re-add
end

-- Broadcast encounter selection to raid (DEPRECATED - Use MessageRouter directly)
function OGRH.BroadcastEncounterSelection(raidName, encounterName)
  -- This function is deprecated and should not be used
  -- All code should use MessageRouter with OGRH.MessageTypes.STATE.CHANGE_ENCOUNTER
  DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[RH-DEPRECATED]|r OGRH.BroadcastEncounterSelection() called")
  DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[RH-DEPRECATED]|r This function is disabled. Please update caller to use MessageRouter.")
  -- SendAddonMessage calls deliberately removed - do not re-add
end
]]--
--[[
  NOTE: Checksum and serialization functions have been consolidated into
  _Infrastructure/SyncChecksum.lua. All calls now delegate to that module.
  
  Removed functions:
  - OGRH.HashRole()
  - OGRH.CalculateStructureChecksum()
  - OGRH.CalculateAllStructureChecksum()
  - OGRH.CalculateRolesUIChecksum()
  - OGRH.Serialize()
  - OGRH.Deserialize()
  
  These functions are accessible via backward compatibility wrappers at OGRH.*
  which delegate to OGRH.SyncChecksum.*
]]
--[[
function OGRH.CalculateAssignmentChecksum(raid, encounter)
  OGRH.EnsureSV()
  if not OGRH_SV.encounterAssignments or 
     not OGRH_SV.encounterAssignments[raid] or 
     not OGRH_SV.encounterAssignments[raid][encounter] then
    return "0"
  end
  
  local assignments = OGRH_SV.encounterAssignments[raid][encounter]
  local checksum = 0
  
  for roleIdx, roleAssignments in pairs(assignments) do
    for slotIdx, playerName in pairs(roleAssignments) do
      if type(playerName) == "string" then
        -- Simple hash: sum of byte values
        for i = 1, string.len(playerName) do
          checksum = checksum + string.byte(playerName, i) * (roleIdx * 100 + slotIdx)
        end
      end
    end
  end
  
  return tostring(checksum)
end

-- Broadcast full encounter assignment sync (assignments only, no structure)
function OGRH.BroadcastFullEncounterSync()
  
  if GetNumRaidMembers() == 0 then
    OGRH.Msg("You must be in a raid to sync.")
    return
  end
  
  -- Get current encounter
  if not OGRH.GetCurrentEncounter then
    return
  end
  
  local currentRaid, currentEncounter = OGRH.GetCurrentEncounter()
  
  if not currentRaid or not currentEncounter then
    OGRH.Msg("No encounter selected to sync.")
    return
  end
  
  -- Calculate structure checksum
  local structureChecksum = OGRH.CalculateStructureChecksum(currentRaid, currentEncounter)
  
  -- Build sync data package (assignments only, no structure elements like marks/numbers)
  OGRH.EnsureSV()
  local syncData = {
    raid = currentRaid,
    encounter = currentEncounter,
    structureChecksum = structureChecksum,
    assignments = {}
  }
  
  -- Get player assignments
  if OGRH_SV.encounterAssignments and OGRH_SV.encounterAssignments[currentRaid] and 
     OGRH_SV.encounterAssignments[currentRaid][currentEncounter] then
    syncData.assignments = OGRH_SV.encounterAssignments[currentRaid][currentEncounter]
  end
  
  -- Use OGRH.Sync.SendChunked to handle automatic chunking
  if OGRH.Sync and OGRH.Sync.SendChunked then
    local success = OGRH.Sync.SendChunked(syncData, OGRH.Sync.MessageType.ENCOUNTER_ASSIGNMENTS, "RAID")
    if not success then
      OGRH.Msg("Failed to send encounter sync.")
    end
  else
    OGRH.Msg("ERROR: Sync module not loaded - cannot send encounter sync.")
  end
end

-- Wrapper for legacy code that passes raid/encounter parameters
-- Sets current encounter then calls BroadcastFullEncounterSync()
function OGRH.BroadcastFullSync(raid, encounter)
  DEFAULT_CHAT_FRAME:AddMessage(string.format("[DEBUG] BroadcastFullSync called: %s / %s", raid or "nil", encounter or "nil"))
  
  -- Set the specified encounter as current
  if OGRH.SetCurrentEncounter then
    OGRH.SetCurrentEncounter(raid, encounter)
    DEFAULT_CHAT_FRAME:AddMessage("[DEBUG] SetCurrentEncounter called")
  end
  
  -- Call the new sync system (Phase 2 - no fallback)
  DEFAULT_CHAT_FRAME:AddMessage("[DEBUG] Calling OGRH.Sync.BroadcastFullSync")
  OGRH.Sync.BroadcastFullSync()
end

-- Handler for receiving encounter assignment syncs (used by OGRH.Sync.RouteMessage)
function OGRH.HandleAssignmentSync(sender, syncData)
  -- Block sync from self
  local playerName = UnitName("player")
  if sender == playerName then
    return
  end
  
  -- Check if sync is locked (send only mode) - but allow from designated raid lead
  OGRH.EnsureSV()
  local currentAdmin = OGRH.GetRaidAdmin and OGRH.GetRaidAdmin()
  local isFromRaidLead = (currentAdmin and sender == currentAdmin)
  
  if OGRH_SV.syncLocked and not isFromRaidLead then
    return
  end
  
  -- Check if sender is raid leader or assistant (or designated raid lead)
  local isAuthorized = isFromRaidLead
  
  local numRaidMembers = GetNumRaidMembers()
  
  if numRaidMembers > 0 then
    for i = 1, numRaidMembers do
      local name, rank = GetRaidRosterInfo(i)
      if name == sender and (rank == 2 or rank == 1) then
        -- rank 2 = leader, rank 1 = assistant
        isAuthorized = true
        break
      end
    end
  end
  
  if not isAuthorized then
    return
  end
  
  if not syncData or not syncData.raid or not syncData.encounter then
    return
  end
  
  -- Initialize structures
  OGRH.EnsureSV()
  if not OGRH_SV.encounterMgmt then OGRH_SV.encounterMgmt = {raids = {}} end
  if not OGRH_SV.encounterMgmt.raids then OGRH_SV.encounterMgmt.raids = {} end
  if not OGRH_SV.encounterAssignments then OGRH_SV.encounterAssignments = {} end
  
  -- Add raid to raids list if it doesn't exist (new structure only)
  local raidExists = false
  for i = 1, table.getn(OGRH_SV.encounterMgmt.raids) do
    local raid = OGRH_SV.encounterMgmt.raids[i]
    if raid.name == syncData.raid then
      raidExists = true
      break
    end
  end
  if not raidExists then
    table.insert(OGRH_SV.encounterMgmt.raids, {
      name = syncData.raid,
      encounters = {},
      advancedSettings = {
        consumeTracking = {
          enabled = false,
          readyThreshold = 85,
          requiredFlaskRoles = {
            ["Tanks"] = false,
            ["Healers"] = false,
            ["Melee"] = false,
            ["Ranged"] = false,
          }
        }
      }
    })
  end
  
  -- Find the raid object and add encounter if it doesn't exist
  local raidObj = OGRH.FindRaidByName(syncData.raid)
  if not raidObj or not raidObj.encounters then
    return
  end
  
  -- Add encounter to raid's encounter list if it doesn't exist
  local encounterExists = false
  for i = 1, table.getn(raidObj.encounters) do
    if raidObj.encounters[i].name == syncData.encounter then
      encounterExists = true
      break
    end
  end
  if not encounterExists then
    table.insert(raidObj.encounters, {
      name = syncData.encounter,
      advancedSettings = {
        bigwigs = {
          enabled = false,
          encounterId = ""
        },
        consumeTracking = {
          enabled = nil,
          readyThreshold = nil,
          requiredFlaskRoles = {}
        }
      }
    })
  end
  
  -- Initialize assignment storage
  if not OGRH_SV.encounterAssignments[syncData.raid] then
    OGRH_SV.encounterAssignments[syncData.raid] = {}
  end
  
  -- Validate structure checksum (required - assignments only)
  if not syncData.structureChecksum then
    -- No structure checksum - reject (old format no longer supported)
    OGRH.Msg("Received sync without structure validation - ignored.")
    OGRH.Msg("Raid lead needs to update their addon.")
    return
  end
  
  local localChecksum = OGRH.CalculateStructureChecksum(syncData.raid, syncData.encounter)
  
  if localChecksum ~= syncData.structureChecksum then
    OGRH.Msg("Assignment sync error: Structure mismatch!")
    OGRH.Msg("Local checksum: " .. tostring(localChecksum) .. " | Leader checksum: " .. tostring(syncData.structureChecksum))
    OGRH.Msg("Your encounter structure is out of date.")
    OGRH.Msg("Use Import/Export > Sync to update from raid lead.")
    
    -- Mark sync button as error (set red)
    OGRH.syncError = true
    if OGRH.syncButton then
      OGRH.syncButton:SetText("|cffff0000Sync|r")
    end
    return
  end
  
  -- Clear any previous error
  OGRH.syncError = false
  if OGRH.syncButton then
    OGRH.syncButton:SetText("Sync")
  end
  
  -- Apply assignments only (NO ROLES, NO MARKS, NO NUMBERS - use Import/Export > Sync for structure)
  if syncData.assignments then
    OGRH_SV.encounterAssignments[syncData.raid][syncData.encounter] = syncData.assignments
  end
  
  -- Refresh raid/encounter lists in open windows
  if OGRH_EncounterFrame then
    if OGRH_EncounterFrame.RefreshRaidsList then
      OGRH_EncounterFrame.RefreshRaidsList()
    end
    if OGRH_EncounterFrame.RefreshEncountersList then
      OGRH_EncounterFrame.RefreshEncountersList()
    end
  end
  if OGRH_EncounterSetupFrame and OGRH_EncounterSetupFrame.RefreshRaidsList then
    OGRH_EncounterSetupFrame.RefreshRaidsList()
  end
  
  -- Refresh UI if it's open and showing this encounter
  if OGRH_EncounterFrame and OGRH_EncounterFrame:IsVisible() then
    if OGRH_EncounterFrame.selectedRaid == syncData.raid and
       OGRH_EncounterFrame.selectedEncounter == syncData.encounter then
      if OGRH_EncounterFrame.RefreshRoleContainers then
        OGRH_EncounterFrame.RefreshRoleContainers()
      end
    end
  end
end

-- Handler for receiving encounter structure syncs (used by OGRH.Sync.RouteMessage)
function OGRH.HandleEncounterSync(sender, syncData)
  -- Block sync from self
  local playerName = UnitName("player")
  if sender == playerName then
    return
  end
  
  if not syncData then
    return
  end
  
  -- Handle structure sync
  if syncData.type == "STRUCTURE_SYNC" and syncData.data then
    if OGRH.ImportShareData then
      OGRH.ImportShareData(syncData.data, sender)
    end
  elseif syncData.type == "ENCOUNTER_STRUCTURE_SYNC" and syncData.data then
    -- Handle encounter-specific structure sync
    if OGRH.ImportShareData then
      -- Check if we're the requester (if specified)
      if syncData.requester == "" or syncData.requester == playerName then
        OGRH.ImportShareData(syncData.data, sender)
      end
    end
  end
end

-------------------------------------------------------------------------------
-- RolesUI Auto-Sync System
-------------------------------------------------------------------------------

-- RolesUI sync functions removed - now handled by OGRH_SyncIntegrity.lua
-- See unified checksum polling system for RolesUI integrity checks

-- Handler for receiving RolesUI sync (used by OGRH.Sync.RouteMessage and direct messages)
function OGRH.HandleRolesUISync(sender, syncData)
  -- Block sync from self
  local playerName = UnitName("player")
  if sender == playerName then
    return
  end
  
  if not syncData or not syncData.roles then
    return
  end
  
  -- Apply roles data
  OGRH.EnsureSV()
  OGRH_SV.roles = syncData.roles
  
  -- Refresh RolesUI if it exists (regardless of visibility check, as it may be inaccurate)
  if OGRH.rolesFrame and OGRH.rolesFrame.UpdatePlayerLists then
    OGRH.rolesFrame.UpdatePlayerLists(false)
  elseif OGRH.RenderRoles then
    OGRH.RenderRoles()
  end
end

-- ReadHelper sync support removed - addon deprecated

-- Re-announce stored announcement
function OGRH.ReAnnounce()
  if not OGRH.storedAnnouncement then
    OGRH.Msg("No announcement to repeat.")
    return
  end
  
  -- Check if we can send raid warnings
  local canRW = OGRH.CanRW()
  
  -- Send each line (no escaping needed for SendChatMessage)
  for _, line in ipairs(OGRH.storedAnnouncement.lines) do
    if canRW then
      SendChatMessage(line, "RAID_WARNING")
    else
      SendChatMessage(line, "RAID")
    end
  end
  
  OGRH.Msg("Re-announced " .. table.getn(OGRH.storedAnnouncement.lines) .. " line(s).")
end
]]--

-- Handle incoming addon messages and game events
local addonFrame = CreateFrame("Frame")
addonFrame:RegisterEvent("CHAT_MSG_ADDON")
addonFrame:RegisterEvent("CHAT_MSG_SYSTEM")
addonFrame:RegisterEvent("READY_CHECK")
addonFrame:RegisterEvent("RAID_ROSTER_UPDATE")
addonFrame:RegisterEvent("PLAYER_LOGOUT")
addonFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
addonFrame:SetScript("OnEvent", function()
  if event == "PLAYER_ENTERING_WORLD" then
    -- Restore consume monitor if encounter is selected
    local selectedRaid = OGRH.SVM.Get("ui", "selectedRaid")
    local selectedEncounter = OGRH.SVM.Get("ui", "selectedEncounter")
    if OGRH_SV and selectedRaid and selectedEncounter then
      if OGRH.ShowConsumeMonitor then
        OGRH.ShowConsumeMonitor()
      end
    end
  elseif event == "PLAYER_LOGOUT" then
    -- Save Phase 1 infrastructure state
    if OGRH.Permissions and OGRH.Permissions.Save then
      OGRH.Permissions.Save()
    end
    
    if OGRH.Versioning and OGRH.Versioning.Save then
      OGRH.Versioning.Save()
    end
    
    -- Save Phase 2 sync state
    if OGRH.Sync and OGRH.Sync.SaveState then
      OGRH.Sync.SaveState()
    end
    
    -- Clean up modules on logout
    if OGRH.CleanupModules then
      OGRH.CleanupModules()
    end
  elseif event == "READY_CHECK" then
    -- Show timer for all players when ready check starts
    OGRH.ShowReadyCheckTimer()
  elseif event == "CHAT_MSG_ADDON" then
    local prefix, message, distribution, sender = arg1, arg2, arg3, arg4
    
    if prefix == OGRH.ADDON_PREFIX then
      -- Handle ready check complete broadcast (MIGRATED TO MessageRouter)
      -- Legacy handler kept for backward compatibility during migration
      if message == "READYCHECK_COMPLETE" then
        -- Hide timer when raid leader reports results
        OGRH.HideReadyCheckTimer()
      -- Handle ready check request from assistant (MIGRATED TO MessageRouter)
      -- AUTOPROMOTE_REQUEST migrated to MessageRouter (ADMIN.PROMOTE_REQUEST)
      -- ADDON_POLL and ADDON_POLL_RESPONSE migrated to MessageRouter (Item 10)
      -- Handle role change broadcast
      elseif string.sub(message, 1, 12) == "ROLE_CHANGE;" then
        -- Parse: ROLE_CHANGE;playerName;newRole
        local content = string.sub(message, 13)
        local semicolon = string.find(content, ";")
        if semicolon then
          local playerName = string.sub(content, 1, semicolon - 1)
          local newRole = string.sub(content, semicolon + 1)
          
          -- Apply role change locally
          if not OGRH_SV then OGRH_SV = {} end
          if not OGRH_SV.roles then OGRH_SV.roles = {} end
          OGRH_SV.roles[playerName] = newRole
          
          -- Refresh Roles UI if open
          if OGRH.rolesFrame and OGRH.rolesFrame:IsVisible() and OGRH.rolesFrame.UpdatePlayerLists then
            OGRH.rolesFrame.UpdatePlayerLists(false)
          end
        end
      -- Handle RollFor sync broadcast
      elseif message == "ROLLFOR_SYNC" then
        -- Only update roles for players who are in RollFor data
        -- Leave everyone else where they are
        if OGRH.Invites and OGRH.Invites.GetSoftResPlayers then
          local softResPlayers = OGRH.Invites.GetSoftResPlayers()
          
          for _, playerData in ipairs(softResPlayers) do
            local playerName = playerData.name
            local rollForRole = OGRH.Invites.MapRollForRoleToOGRH(playerData.role)
            
            if rollForRole then
              -- Save the RollFor role
              if not OGRH_SV then OGRH_SV = {} end
              if not OGRH_SV.roles then OGRH_SV.roles = {} end
              OGRH_SV.roles[playerName] = rollForRole
            end
          end
          
          -- Refresh Roles UI if open
          if OGRH.rolesFrame and OGRH.rolesFrame:IsVisible() and OGRH.rolesFrame.UpdatePlayerLists then
            OGRH.rolesFrame.UpdatePlayerLists(false)
          end
          
          OGRH.Msg("Roles synced from RollFor by " .. sender)
        end
      -- Handle encounter structure sync request (for single encounter)
      elseif string.sub(message, 1, 33) == "REQUEST_ENCOUNTER_STRUCTURE_SYNC;" then
        -- Parse: raid;encounter;requester
        local content = string.sub(message, 34)
        local parts = {}
        local lastPos = 1
        for i = 1, 3 do
          local pos = string.find(content, ";", lastPos, true)
          if pos then
            table.insert(parts, string.sub(content, lastPos, pos - 1))
            lastPos = pos + 1
          else
            table.insert(parts, string.sub(content, lastPos))
            break
          end
        end
        
        if table.getn(parts) >= 3 then
          local raidName = parts[1]
          local encounterName = parts[2]
          local requester = parts[3]
          
          -- Only respond if we're the raid admin
          local isRaidAdmin = false
          if OGRH.IsRaidAdmin then
            isRaidAdmin = OGRH.IsRaidAdmin(UnitName("player"))
          end
          
          if isRaidAdmin then
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OGRH:|r Structure sync requested by " .. requester .. " for " .. encounterName)
            if OGRH.BroadcastEncounterStructureSync then
              OGRH.BroadcastEncounterStructureSync(raidName, encounterName, requester)
            end
          end
        end
      -- Handle sync request from non-lead
      elseif message == "SYNC_REQUEST" then
        -- Only respond if we're the raid admin
        if OGRH.IsRaidAdmin and OGRH.IsRaidAdmin(UnitName("player")) then
          -- Send current encounter sync
          if OGRH.GetCurrentEncounter then
            local currentRaid, currentEncounter = OGRH.GetCurrentEncounter()
            if currentRaid and currentEncounter and OGRH.BroadcastFullEncounterSync then
              OGRH.BroadcastFullEncounterSync()
            end
          end
        end
      -- RolesUI checksum check removed - now handled by OGRH_SyncIntegrity.lua unified polling
      -- Handle announcement broadcast
      -- DISABLED: Announcement receive handler
      -- This feature is no longer used since we're not staging announcements
      --[[
      elseif string.sub(message, 1, 9) == "ANNOUNCE;" then
        -- Parse the announcement lines (semicolon delimited)
        local content = string.sub(message, 10)
        local lines = {}
        local lastPos = 1
        local pos = 1
        
        -- Split by semicolon delimiter
        while pos <= string.len(content) do
          local found = string.find(content, ";", pos, true)
          if found then
            table.insert(lines, string.sub(content, lastPos, found - 1))
            lastPos = found + 1
            pos = found + 1
          else
            -- Last segment
            table.insert(lines, string.sub(content, lastPos))
            break
          end
        end
        
        -- Store the announcement
        if table.getn(lines) > 0 then
          OGRH.storedAnnouncement = {
            lines = lines,
            timestamp = time()
          }
        end
      --]]
      -- Handle encounter sync
      elseif string.sub(message, 1, 15) == "ENCOUNTER_SYNC;" then
        -- Block sync from self
        local playerName = UnitName("player")
        if sender == playerName then
          return
        end
        
        -- Check if sync is locked (send only mode) - but allow from designated raid lead
        OGRH.EnsureSV()
        local currentAdmin = OGRH.GetRaidAdmin and OGRH.GetRaidAdmin()
        local isFromRaidLead = (currentAdmin and sender == currentAdmin)
        
        if OGRH_SV.syncLocked and not isFromRaidLead then
          DEFAULT_CHAT_FRAME:AddMessage("|cffff8800OGRH:|r Ignored encounter sync from " .. sender .. " (sync is locked)")
          return
        end
        
        -- Check if sender is raid leader or assistant (or designated raid lead)
        local isAuthorized = isFromRaidLead
        local numRaidMembers = GetNumRaidMembers()
        
        if numRaidMembers > 0 then
          for i = 1, numRaidMembers do
            local name, rank = GetRaidRosterInfo(i)
            if name == sender and (rank == 2 or rank == 1) then
              -- rank 2 = leader, rank 1 = assistant
              isAuthorized = true
              break
            end
          end
        end
        
        if not isAuthorized then
          DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OGRH:|r Ignored encounter sync from " .. sender .. " (not raid leader or assistant)")
          return
        end
        
        local serialized = string.sub(message, 16)
        local syncData = OGRH.Deserialize(serialized)
        
        if syncData and syncData.raid and syncData.encounter then
          -- Initialize structures
          OGRH.EnsureSV()
          if not OGRH_SV.encounterMgmt then OGRH_SV.encounterMgmt = {raids = {}} end
          if not OGRH_SV.encounterMgmt.raids then OGRH_SV.encounterMgmt.raids = {} end
          if not OGRH_SV.encounterAssignments then OGRH_SV.encounterAssignments = {} end
          
          -- Add raid to raids list if it doesn't exist (new structure only)
          local raidExists = false
          for i = 1, table.getn(OGRH_SV.encounterMgmt.raids) do
            local raid = OGRH_SV.encounterMgmt.raids[i]
            if raid.name == syncData.raid then
              raidExists = true
              break
            end
          end
          if not raidExists then
            table.insert(OGRH_SV.encounterMgmt.raids, {
              name = syncData.raid,
              encounters = {},
              advancedSettings = {
                consumeTracking = {
                  enabled = false,
                  readyThreshold = 85,
                  requiredFlaskRoles = {
                    ["Tanks"] = false,
                    ["Healers"] = false,
                    ["Melee"] = false,
                    ["Ranged"] = false,
                  }
                }
              }
            })
          end
          
          -- Find the raid object and add encounter if it doesn't exist
          local raidObj = OGRH.FindRaidByName(syncData.raid)
          if not raidObj or not raidObj.encounters then
            return
          end
          
          -- Add encounter to raid's encounter list if it doesn't exist
          local encounterExists = false
          for i = 1, table.getn(raidObj.encounters) do
            if raidObj.encounters[i].name == syncData.encounter then
              encounterExists = true
              break
            end
          end
          if not encounterExists then
            table.insert(raidObj.encounters, {
              name = syncData.encounter,
              advancedSettings = {
                bigwigs = {
                  enabled = false,
                  encounterId = ""
                },
                consumeTracking = {
                  enabled = nil,
                  readyThreshold = nil,
                  requiredFlaskRoles = {}
                }
              }
            })
          end
          
          -- Initialize assignment storage
          if not OGRH_SV.encounterAssignments[syncData.raid] then
            OGRH_SV.encounterAssignments[syncData.raid] = {}
          end
          
          -- Validate structure checksum (required - assignments only)
          if not syncData.structureChecksum then
            -- No structure checksum - reject (old format no longer supported)
            OGRH.Msg("Received sync without structure validation - ignored.")
            OGRH.Msg("Raid lead needs to update their addon.")
            return
          end
          
          local localChecksum = OGRH.CalculateStructureChecksum(syncData.raid, syncData.encounter)
          
          if localChecksum ~= syncData.structureChecksum then
            OGRH.Msg("Assignment sync error: Structure mismatch!")
            OGRH.Msg("Local checksum: " .. tostring(localChecksum) .. " | Leader checksum: " .. tostring(syncData.structureChecksum))
            OGRH.Msg("Your encounter structure is out of date.")
            OGRH.Msg("Use Import/Export > Sync to update from raid lead.")
            
            -- Mark sync button as error (set red)
            OGRH.syncError = true
            if OGRH.syncButton then
              OGRH.syncButton:SetText("|cffff0000Sync|r")
            end
            return
          end
          
          -- Clear any previous error
          OGRH.syncError = false
          if OGRH.syncButton then
            OGRH.syncButton:SetText("Sync")
          end
          
          -- Apply assignments only (NO ROLES, NO MARKS, NO NUMBERS - use Import/Export > Sync for structure)
          if syncData.assignments then
            OGRH_SV.encounterAssignments[syncData.raid][syncData.encounter] = syncData.assignments
          end
          
          -- Refresh raid/encounter lists in open windows
          if OGRH_EncounterFrame then
            if OGRH_EncounterFrame.RefreshRaidsList then
              OGRH_EncounterFrame.RefreshRaidsList()
            end
            if OGRH_EncounterFrame.RefreshEncountersList then
              OGRH_EncounterFrame.RefreshEncountersList()
            end
          end
          if OGRH_EncounterSetupFrame and OGRH_EncounterSetupFrame.RefreshRaidsList then
            OGRH_EncounterSetupFrame.RefreshRaidsList()
          end
          
          -- Refresh UI if it's open and showing this encounter
          if OGRH_EncounterFrame and OGRH_EncounterFrame:IsVisible() then
            if OGRH_EncounterFrame.selectedRaid == syncData.raid and
               OGRH_EncounterFrame.selectedEncounter == syncData.encounter then
              if OGRH_EncounterFrame.RefreshRoleContainers then
                OGRH_EncounterFrame.RefreshRoleContainers()
              end
            end
          end
        end
      -- Handle encounter sync chunk
      elseif string.sub(message, 1, 21) == "ENCOUNTER_SYNC_CHUNK;" then
        -- Block from self
        local playerName = UnitName("player")
        if sender == playerName then
          return
        end
        
        -- Parse: chunkIndex;totalChunks;data
        local content = string.sub(message, 22)
        local semicolon1 = string.find(content, ";", 1, true)
        if not semicolon1 then return end
        
        local chunkIndex = tonumber(string.sub(content, 1, semicolon1 - 1))
        local remainder = string.sub(content, semicolon1 + 1)
        
        local semicolon2 = string.find(remainder, ";", 1, true)
        if not semicolon2 then return end
        
        local totalChunks = tonumber(string.sub(remainder, 1, semicolon2 - 1))
        local chunkData = string.sub(remainder, semicolon2 + 1)
        
        -- Initialize storage
        if not OGRH.encounterSyncChunks then
          OGRH.encounterSyncChunks = {}
        end
        
        if not OGRH.encounterSyncChunks[sender] then
          OGRH.encounterSyncChunks[sender] = {
            chunks = {},
            total = totalChunks,
            received = 0,
            complete = false,
            data = ""
          }
        end
        
        local senderData = OGRH.encounterSyncChunks[sender]
        
        -- Store chunk if not already received
        if not senderData.chunks[chunkIndex] then
          senderData.chunks[chunkIndex] = chunkData
          senderData.received = senderData.received + 1
          
          -- Progress notification every 10 chunks (reduce spam)
          if math.mod(senderData.received, 10) == 0 and senderData.received < senderData.total then
            OGRH.Msg("Receiving encounter sync: " .. senderData.received .. "/" .. senderData.total .. " chunks...")
          end
          
          -- Check if complete
          if senderData.received == senderData.total then
            -- Reassemble data
            local fullData = ""
            for i = 1, totalChunks do
              if senderData.chunks[i] then
                fullData = fullData .. senderData.chunks[i]
              end
            end
            senderData.data = fullData
            senderData.complete = true
            
            -- Process the sync data
            local syncData = OGRH.Deserialize(fullData)
            if syncData and syncData.raid and syncData.encounter then
              -- Validate structure checksum
              if syncData.structureChecksum then
                local localChecksum = OGRH.CalculateStructureChecksum(syncData.raid, syncData.encounter)
                if localChecksum ~= syncData.structureChecksum then
                  OGRH.Msg("Assignment sync error: Structure mismatch!")
                  OGRH.Msg("Local checksum: " .. localChecksum .. " | Leader checksum: " .. syncData.structureChecksum)
                  OGRH.Msg("Your encounter structure is out of date.")
                  OGRH.Msg("Use Import/Export > Sync to update from raid lead.")
                  
                  -- Mark sync button as error
                  OGRH.syncError = true
                  if OGRH.syncButton then
                    OGRH.syncButton:SetText("|cffff0000Sync|r")
                  end
                  
                  OGRH.encounterSyncChunks = {}
                  return
                end
              end
              
              -- Clear any previous error
              OGRH.syncError = false
              if OGRH.syncButton then
                OGRH.syncButton:SetText("Sync")
              end
              
              -- Apply assignments
              OGRH.EnsureSV()
              if not OGRH_SV.encounterAssignments then OGRH_SV.encounterAssignments = {} end
              
              if not OGRH_SV.encounterAssignments[syncData.raid] then
                OGRH_SV.encounterAssignments[syncData.raid] = {}
              end
              
              -- Apply assignments only (NO MARKS, NO NUMBERS - structure elements)
              if syncData.assignments then
                OGRH_SV.encounterAssignments[syncData.raid][syncData.encounter] = syncData.assignments
              end
              
              -- Refresh raid/encounter lists
              if OGRH_EncounterFrame then
                if OGRH_EncounterFrame.RefreshRaidsList then
                  OGRH_EncounterFrame.RefreshRaidsList()
                end
                if OGRH_EncounterFrame.RefreshEncountersList then
                  OGRH_EncounterFrame.RefreshEncountersList()
                end
              end
              if OGRH_EncounterSetupFrame and OGRH_EncounterSetupFrame.RefreshRaidsList then
                OGRH_EncounterSetupFrame.RefreshRaidsList()
              end
              
              -- Refresh UI if showing this encounter
              if OGRH_EncounterFrame and OGRH_EncounterFrame:IsVisible() then
                if OGRH_EncounterFrame.selectedRaid == syncData.raid and
                   OGRH_EncounterFrame.selectedEncounter == syncData.encounter then
                  if OGRH_EncounterFrame.RefreshRoleContainers then
                    OGRH_EncounterFrame.RefreshRoleContainers()
                  end
                end
              end
            end
            
            -- Clean up
            OGRH.encounterSyncChunks = {}
          end
        end
      -- Handle encounter selection broadcast
      elseif string.sub(message, 1, 17) == "ENCOUNTER_SELECT;" then
        -- Block selection from self
        local playerName = UnitName("player")
        if sender == playerName then
          return
        end
        
        -- Parse raid and encounter names
        local content = string.sub(message, 18)
        local semicolonPos = string.find(content, ";", 1, true)
        
        if semicolonPos then
          local raidName = string.sub(content, 1, semicolonPos - 1)
          local encounterName = string.sub(content, semicolonPos + 1)
          
          -- Check if sender is raid leader, assistant, or designated raid admin
          local isAuthorized = false
          local numRaidMembers = GetNumRaidMembers()
          
          -- Check if sender is the designated raid admin
          local currentAdmin = OGRH.GetRaidAdmin and OGRH.GetRaidAdmin()
          if currentAdmin == sender then
            isAuthorized = true
          end
          
          -- Check if sender is raid leader or assistant
          if not isAuthorized and numRaidMembers > 0 then
            for i = 1, numRaidMembers do
              local name, rank = GetRaidRosterInfo(i)
              if name == sender and (rank == 2 or rank == 1) then
                -- rank 2 = leader, rank 1 = assistant
                isAuthorized = true
                break
              end
            end
          end
          
          if not isAuthorized then
            -- Silently ignore - not from leader/assistant/raid admin
            return
          end
          
          -- Verify raid and encounter exist locally
          local raidFound = false
          local encounterFound = false
          
          if OGRH_SV.encounterMgmt and OGRH_SV.encounterMgmt.raids then
            -- Loop through raids array to find matching raid name
            for i = 1, table.getn(OGRH_SV.encounterMgmt.raids) do
              local raid = OGRH_SV.encounterMgmt.raids[i]
              if raid.name == raidName then
                raidFound = true
                -- Check if encounter exists in this raid - encounters is also an array
                if raid.encounters then
                  for j = 1, table.getn(raid.encounters) do
                    local enc = raid.encounters[j]
                    if enc.name == encounterName then
                      encounterFound = true
                      break
                    end
                  end
                end
                break
              end
            end
          end
          
          if raidFound and encounterFound then
            -- Update main UI selection using indices (SetCurrentEncounter handles backward compat)
            OGRH.SetCurrentEncounter(raidIdx, encIdx)
            
            -- Do NOT update planning window frame
            -- Planning window maintains its own independent selection
            
            -- Always update the main UI encounter button (this loads modules)
            if OGRH.UpdateEncounterNavButton then
              OGRH.UpdateEncounterNavButton()
            end
            
            -- Update consume monitor
            if OGRH.ShowConsumeMonitor then
              OGRH.ShowConsumeMonitor()
            end
          end
        end
      -- Handle request for encounter sync (MIGRATED TO MessageRouter - SYNC.REQUEST_PARTIAL)
      -- Handle assignment update
      elseif string.sub(message, 1, 18) == "ASSIGNMENT_UPDATE;" then
        -- Block from self
        local playerName = UnitName("player")
        if sender == playerName then
          return
        end
        
        -- Check if sender is the designated raid lead
        local isAuthorized = false
        local currentAdmin = OGRH.GetRaidAdmin and OGRH.GetRaidAdmin()
        if currentAdmin then
          if sender == currentAdmin then
            isAuthorized = true
          end
        end
        
        if not isAuthorized then
          return
        end
        
        -- Allow updates from raid lead even if sync is locked
        -- (syncLocked only prevents manual editing, not receiving from lead)
        
        -- Parse: raid;encounter;roleIndex;slotIndex;playerName;checksum
        local content = string.sub(message, 19)
        local parts = {}
        local lastPos = 1
        for i = 1, 6 do
          local pos = string.find(content, ";", lastPos, true)
          if pos then
            table.insert(parts, string.sub(content, lastPos, pos - 1))
            lastPos = pos + 1
          else
            table.insert(parts, string.sub(content, lastPos))
            break
          end
        end
        
        if table.getn(parts) >= 6 then
          local raid = parts[1]
          local encounter = parts[2]
          local roleIndex = tonumber(parts[3])
          local slotIndex = tonumber(parts[4])
          local newPlayerName = parts[5]
          if newPlayerName == "" then newPlayerName = nil end
          local senderStructureChecksum = parts[6]
          
          -- Validate structure checksum
          local localStructureChecksum = OGRH.CalculateStructureChecksum(raid, encounter)
          
          if localStructureChecksum ~= senderStructureChecksum then
            OGRH.Msg("Assignment update error: Structure mismatch!")
            OGRH.Msg("Local checksum: " .. tostring(localStructureChecksum) .. " | Leader checksum: " .. tostring(senderStructureChecksum))
            OGRH.Msg("Your encounter structure is out of date.")
            OGRH.Msg("Use Import/Export > Sync to update from raid lead.")
            
            -- Mark sync button as error (set red)
            OGRH.syncError = true
            if OGRH.syncButton then
              OGRH.syncButton:SetText("|cffff0000Sync|r")
            end
            return
          end
          
          -- Clear any previous error
          OGRH.syncError = false
          if OGRH.syncButton then
            OGRH.syncButton:SetText("Sync")
          end
          
          -- Apply update
          if not OGRH_SV.encounterAssignments then OGRH_SV.encounterAssignments = {} end
          if not OGRH_SV.encounterAssignments[raid] then OGRH_SV.encounterAssignments[raid] = {} end
          if not OGRH_SV.encounterAssignments[raid][encounter] then OGRH_SV.encounterAssignments[raid][encounter] = {} end
          if not OGRH_SV.encounterAssignments[raid][encounter][roleIndex] then OGRH_SV.encounterAssignments[raid][encounter][roleIndex] = {} end
          
          OGRH_SV.encounterAssignments[raid][encounter][roleIndex][slotIndex] = newPlayerName
          
          -- Refresh UI if showing this encounter
          if OGRH_EncounterFrame and OGRH_EncounterFrame:IsVisible() then
            if OGRH_EncounterFrame.selectedRaid == raid and
               OGRH_EncounterFrame.selectedEncounter == encounter then
              if OGRH_EncounterFrame.RefreshRoleContainers then
                OGRH_EncounterFrame.RefreshRoleContainers()
              end
            end
          end
        end
      -- Handle full sync request
      -- Handle raid data request
      elseif message == "REQUEST_RAID_DATA" then
        -- Block from self
        local playerName = UnitName("player")
        if sender == playerName then
          return
        end
        
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OGRH:|r Received raid data request from " .. sender)
        
        -- Only respond if sync is locked (send only mode)
        OGRH.EnsureSV()
        if not OGRH_SV.syncLocked then
          DEFAULT_CHAT_FRAME:AddMessage("|cffff8800OGRH:|r Sync not locked - not responding (sync must be locked to send-only mode)")
          return
        end
        
        -- Check if we have data to share
        if not OGRH_SV.encounterMgmt or 
           not OGRH_SV.encounterMgmt.raids or 
           table.getn(OGRH_SV.encounterMgmt.raids) == 0 then
          DEFAULT_CHAT_FRAME:AddMessage("|cffff8800OGRH:|r No encounter data to share")
          return -- No data to share
        end
        
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OGRH:|r Will respond with encounter data (sync locked to send-only)")
        
        -- Add random delay (0.5 to 2 seconds) to avoid flooding
        local delay = 0.5 + (math.random() * 1.5)
        
        if not OGRH.raidDataResponseTimer then
          OGRH.raidDataResponseTimer = CreateFrame("Frame")
        end
        
        local elapsed = 0
        OGRH.raidDataResponseTimer:SetScript("OnUpdate", function()
          elapsed = elapsed + arg1
          if elapsed >= delay then
            OGRH.raidDataResponseTimer:SetScript("OnUpdate", nil)
            
            -- Export and send data in chunks
            if OGRH.ExportShareData then
              local data = OGRH.ExportShareData()
              local chunkSize = 200 -- Safe chunk size
              local totalChunks = math.ceil(string.len(data) / chunkSize)
              
              DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OGRH:|r Sending raid data in " .. totalChunks .. " chunks")
              
              -- Send chunks with delay between them
              local chunkIndex = 0
              local chunkTimer = CreateFrame("Frame")
              local chunkElapsed = 0
              
              chunkTimer:SetScript("OnUpdate", function()
                chunkElapsed = chunkElapsed + arg1
                if chunkElapsed >= 0.5 then -- 500ms between chunks (safer for chat throttling)
                  chunkElapsed = 0
                  chunkIndex = chunkIndex + 1
                  
                  if chunkIndex <= totalChunks then
                    local startPos = (chunkIndex - 1) * chunkSize + 1
                    local endPos = math.min(chunkIndex * chunkSize, string.len(data))
                    local chunk = string.sub(data, startPos, endPos)
                    
                    local msg = "RAID_DATA_CHUNK;" .. chunkIndex .. ";" .. totalChunks .. ";" .. chunk
                    SendAddonMessage(OGRH.ADDON_PREFIX, msg, "RAID")
                  else
                    chunkTimer:SetScript("OnUpdate", nil)
                    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OGRH:|r All chunks sent")
                  end
                end
              end)
            end
          end
        end)
      -- Handle raid data chunk
      elseif string.sub(message, 1, 16) == "RAID_DATA_CHUNK;" then
        -- Block from self
        local playerName = UnitName("player")
        if sender == playerName then
          return
        end
        
        -- Only collect if we're waiting for responses
        if not OGRH.waitingForRaidData then
          return
        end
        
        -- Parse: chunkIndex;totalChunks;data
        local content = string.sub(message, 17)
        local semicolon1 = string.find(content, ";", 1, true)
        if not semicolon1 then return end
        
        local chunkIndex = tonumber(string.sub(content, 1, semicolon1 - 1))
        local remainder = string.sub(content, semicolon1 + 1)
        
        local semicolon2 = string.find(remainder, ";", 1, true)
        if not semicolon2 then return end
        
        local totalChunks = tonumber(string.sub(remainder, 1, semicolon2 - 1))
        local chunkData = string.sub(remainder, semicolon2 + 1)
        
        -- Initialize storage for this sender
        if not OGRH.raidDataChunks[sender] then
          OGRH.raidDataChunks[sender] = {
            chunks = {},
            total = totalChunks,
            received = 0,
            complete = false,
            data = ""
          }
        end
        
        local senderData = OGRH.raidDataChunks[sender]
        
        -- Store chunk if not already received
        if not senderData.chunks[chunkIndex] then
          senderData.chunks[chunkIndex] = chunkData
          senderData.received = senderData.received + 1
          
          DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OGRH:|r Received chunk " .. chunkIndex .. "/" .. totalChunks .. " from " .. sender)
          
          -- Check if complete
          if senderData.received == senderData.total then
            -- Reassemble data
            local fullData = ""
            for i = 1, totalChunks do
              if senderData.chunks[i] then
                fullData = fullData .. senderData.chunks[i]
              end
            end
            senderData.data = fullData
            senderData.complete = true
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OGRH:|r Complete data received from " .. sender)
          end
        end
      -- Handle current encounter sync request
      elseif message == "REQUEST_CURRENT_ENCOUNTER" then
        -- Block from self
        local playerName = UnitName("player")
        if sender == playerName then
          return
        end
        
        -- Only respond if we're the raid lead
        local isRaidLead = false
        local currentAdmin = OGRH.GetRaidAdmin and OGRH.GetRaidAdmin()
        if currentAdmin then
          if currentAdmin == playerName then
            isRaidLead = true
          end
        end
        
        if isRaidLead then
          -- Get current encounter from Main UI
          local currentRaid, currentEncounter = OGRH.GetCurrentEncounter()
          if currentRaid and currentEncounter then
            -- Broadcast encounter selection using MessageRouter
            if GetNumRaidMembers() > 0 then
              OGRH.MessageRouter.Broadcast(OGRH.MessageTypes.STATE.CHANGE_ENCOUNTER, {
                raidName = currentRaid,
                encounterName = currentEncounter
              }, {
                priority = "NORMAL"
              })
              
              -- Broadcast full sync if admin, request sync if not
              if OGRH.IsRaidAdmin and OGRH.IsRaidAdmin() then
                if OGRH.BroadcastFullEncounterSync then
                  OGRH.BroadcastFullEncounterSync()
                end
              else
                OGRH.MessageRouter.Broadcast(OGRH.MessageTypes.SYNC.REQUEST_PARTIAL, {
                  raidName = currentRaid,
                  encounterName = currentEncounter
                }, {
                  priority = "NORMAL"
                })
              end
            end
          end
        end
      -- Handle structure sync request
      elseif message == "REQUEST_STRUCTURE_SYNC" then
        -- Block from self
        local playerName = UnitName("player")
        if sender == playerName then
          return
        end
        
        -- Only respond if we're the raid lead
        local isRaidLead = false
        local currentAdmin = OGRH.GetRaidAdmin and OGRH.GetRaidAdmin()
        if currentAdmin then
          if currentAdmin == playerName then
            isRaidLead = true
          end
        end
        
        if isRaidLead then
          DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OGRH:|r Structure sync requested by " .. sender)
          OGRH.BroadcastStructureSync()
        end
      -- Handle structure sync chunk
      elseif string.sub(message, 1, 21) == "STRUCTURE_SYNC_CHUNK;" then
        -- Block from self
        local playerName = UnitName("player")
        if sender == playerName then
          return
        end
        
        -- Only collect if we're waiting for structure sync
        if not OGRH.waitingForStructureSync then
          return
        end
        
        -- Parse: chunkIndex;totalChunks;data
        local content = string.sub(message, 22)
        local semicolon1 = string.find(content, ";", 1, true)
        if not semicolon1 then return end
        
        local chunkIndex = tonumber(string.sub(content, 1, semicolon1 - 1))
        local remainder = string.sub(content, semicolon1 + 1)
        
        local semicolon2 = string.find(remainder, ";", 1, true)
        if not semicolon2 then return end
        
        local totalChunks = tonumber(string.sub(remainder, 1, semicolon2 - 1))
        local chunkData = string.sub(remainder, semicolon2 + 1)
        
        -- Initialize storage
        if not OGRH.structureSyncChunks then
          OGRH.structureSyncChunks = {}
        end
        
        if not OGRH.structureSyncChunks[sender] then
          OGRH.structureSyncChunks[sender] = {
            chunks = {},
            total = totalChunks,
            received = 0,
            complete = false,
            data = ""
          }
        end
        
        local senderData = OGRH.structureSyncChunks[sender]
        
        -- Store chunk if not already received
        if not senderData.chunks[chunkIndex] then
          senderData.chunks[chunkIndex] = chunkData
          senderData.received = senderData.received + 1
          
          -- Reset timeout timer since we're actively receiving chunks
          if OGRH.structureSyncTimer then
            OGRH.structureSyncTimer:SetScript("OnUpdate", nil)
            local elapsed = 0
            OGRH.structureSyncTimer:SetScript("OnUpdate", function()
              elapsed = elapsed + arg1
              if elapsed >= 90 then
                OGRH.structureSyncTimer:SetScript("OnUpdate", nil)
                if OGRH.waitingForStructureSync then
                  OGRH.waitingForStructureSync = false
                  if OGRH_StructureSyncPanel then
                    OGRH_StructureSyncPanel:Hide()
                  end
                end
              end
            end)
          end
          
          -- Update progress bar
          local progress = math.floor((senderData.received / senderData.total) * 100)
          OGRH.ShowStructureSyncProgress(false, progress, false, nil)
          
          -- Check if complete
          if senderData.received == senderData.total then
            -- Reassemble data
            local fullData = ""
            for i = 1, totalChunks do
              if senderData.chunks[i] then
                fullData = fullData .. senderData.chunks[i]
              end
            end
            senderData.data = fullData
            senderData.complete = true
            
            -- Import the data
            if OGRH.ImportShareData then
              OGRH.ImportShareData(fullData)
              OGRH.ShowStructureSyncProgress(false, 100, true, nil)
            end
            
            -- Refresh role containers if Encounter Planning window is open
            if OGRH_EncounterFrame and OGRH_EncounterFrame:IsShown() and OGRH_EncounterFrame.RefreshRoleContainers then
              OGRH_EncounterFrame.RefreshRoleContainers()
            end
            
            -- Clean up
            OGRH.waitingForStructureSync = false
            OGRH.structureSyncChunks = {}
            if OGRH.structureSyncTimer then
              OGRH.structureSyncTimer:SetScript("OnUpdate", nil)
            end
          end
        end
      -- Handle encounter structure sync chunk (single encounter)
      elseif string.sub(message, 1, 31) == "ENCOUNTER_STRUCTURE_SYNC_CHUNK;" then
        -- Block from self
        local playerName = UnitName("player")
        if sender == playerName then
          return
        end
        
        -- Parse: requester;chunkIndex;totalChunks;data
        local content = string.sub(message, 32)
        local semicolon1 = string.find(content, ";", 1, true)
        if not semicolon1 then return end
        
        local requester = string.sub(content, 1, semicolon1 - 1)
        local remainder = string.sub(content, semicolon1 + 1)
        
        -- Only process if: no requester (broadcast to all) OR we are the requester
        if requester ~= "" and requester ~= playerName then
          return
        end
        
        local semicolon2 = string.find(remainder, ";", 1, true)
        if not semicolon2 then return end
        
        local chunkIndex = tonumber(string.sub(remainder, 1, semicolon2 - 1))
        local remainder2 = string.sub(remainder, semicolon2 + 1)
        
        local semicolon3 = string.find(remainder2, ";", 1, true)
        if not semicolon3 then return end
        
        local totalChunks = tonumber(string.sub(remainder2, 1, semicolon3 - 1))
        local chunkData = string.sub(remainder2, semicolon3 + 1)
        
        -- Initialize storage
        if not OGRH.encounterStructureSyncChunks then
          OGRH.encounterStructureSyncChunks = {}
        end
        
        if not OGRH.encounterStructureSyncChunks[sender] then
          OGRH.encounterStructureSyncChunks[sender] = {
            chunks = {},
            total = totalChunks,
            received = 0,
            complete = false,
            data = ""
          }
        end
        
        local senderData = OGRH.encounterStructureSyncChunks[sender]
        
        -- Store chunk if not already received
        if not senderData.chunks[chunkIndex] then
          senderData.chunks[chunkIndex] = chunkData
          senderData.received = senderData.received + 1
          
          -- Extract encounter name from first chunk if available
          local encounterName = nil
          if chunkIndex == 1 then
            -- Try to parse encounter name from data structure
            local raidStart = string.find(chunkData, '"raids"')
            if raidStart then
              local encounterStart = string.find(chunkData, '"encounter":', raidStart)
              if encounterStart then
                local nameStart = string.find(chunkData, '"', encounterStart + 12)
                if nameStart then
                  local nameEnd = string.find(chunkData, '"', nameStart + 1)
                  if nameEnd then
                    encounterName = string.sub(chunkData, nameStart + 1, nameEnd - 1)
                  end
                end
              end
            end
          end
          
          -- Update progress bar
          local progress = math.floor((senderData.received / senderData.total) * 100)
          OGRH.ShowStructureSyncProgress(false, progress, false, encounterName)
          
          -- Check if complete
          if senderData.received == senderData.total then
            -- Reassemble data
            local fullData = ""
            for i = 1, totalChunks do
              if senderData.chunks[i] then
                fullData = fullData .. senderData.chunks[i]
              end
            end
            senderData.data = fullData
            senderData.complete = true
            
            -- Import the data (single encounter mode)
            if OGRH.ImportShareData then
              OGRH.ImportShareData(fullData, true)
              OGRH.ShowStructureSyncProgress(false, 100, true, encounterName)
            end
            
            -- Refresh role containers if Encounter Planning window is open
            if OGRH_EncounterFrame and OGRH_EncounterFrame:IsShown() and OGRH_EncounterFrame.RefreshRoleContainers then
              OGRH_EncounterFrame.RefreshRoleContainers()
            end
            
            -- Clean up
            OGRH.encounterStructureSyncChunks = {}
          end
        end
      end
    end
  elseif event == "CHAT_MSG_SYSTEM" then
    -- Capture ready check responses
    if OGRH.readyCheckInProgress and IsRaidLeader() == 1 then
      local msg = arg1
      
      -- Initialize tracking if not already done
      if not OGRH.readyCheckResponses then
        OGRH.readyCheckResponses = {
          notReady = {},
          afk = {}
        }
      end
      
      -- Capture "not ready" responses
      -- Note: In vanilla WoW, "ready" responses don't generate system messages
      -- Format: "PlayerName is not ready."
      local isNotReadyMsg = msg and string.find(msg, " is not ready")
      
      if isNotReadyMsg then
        local playerName = string.gsub(msg, " is not ready.*", "")
        playerName = string.gsub(playerName, "^%s*(.-)%s*$", "%1")
        if playerName ~= "" then
          table.insert(OGRH.readyCheckResponses.notReady, playerName)
        end
        -- Don't continue to summary check
      -- Check for final AFK summary messages
      elseif msg and string.find(msg, "No players are AFK") then
        -- Report all responses
        OGRH.ReportReadyCheckResults()
        OGRH.readyCheckInProgress = false
        OGRH.readyCheckResponses = nil
      elseif msg and string.find(msg, "The following players are AFK:") then
        -- Parse the player names from the message
        local playersPart = string.gsub(msg, "The following players are AFK: ", "")
        
        -- Split by comma and space
        local pos = 1
        while pos <= string.len(playersPart) do
          local commaPos = string.find(playersPart, ", ", pos, true)
          local playerName
          if commaPos then
            playerName = string.sub(playersPart, pos, commaPos - 1)
            pos = commaPos + 2
          else
            playerName = string.sub(playersPart, pos)
            pos = string.len(playersPart) + 1
          end
          
          -- Trim whitespace
          playerName = string.gsub(playerName, "^%s*(.-)%s*$", "%1")
          if playerName ~= "" then
            table.insert(OGRH.readyCheckResponses.afk, playerName)
          end
        end
        
        -- Report all responses
        OGRH.ReportReadyCheckResults()
        OGRH.readyCheckInProgress = false
        OGRH.readyCheckResponses = nil
      end
    end
  elseif event == "RAID_ROSTER_UPDATE" then
    -- When joining a raid, request assignment sync for current encounter
    local numRaidMembers = GetNumRaidMembers()
    
    -- Store previous raid size to detect joining vs already in raid
    if not OGRH.previousRaidSize then
      OGRH.previousRaidSize = 0
    end
    
    -- Only request sync when transitioning from no raid to in raid
    if OGRH.previousRaidSize == 0 and numRaidMembers > 0 then
      -- Delay the request slightly to allow raid roster to stabilize
      local delayFrame = CreateFrame("Frame")
      local elapsed = 0
      delayFrame:SetScript("OnUpdate", function()
        elapsed = elapsed + arg1
        if elapsed >= 2 then
          delayFrame:SetScript("OnUpdate", nil)
          
          -- Request current encounter assignment sync
          if OGRH.RequestCurrentEncounterSync then
            OGRH.RequestCurrentEncounterSync()
          end
        end
      end)
    end
    
    OGRH.previousRaidSize = numRaidMembers
  end
end)

-- Report ready check results
function OGRH.ReportReadyCheckResults()
  if not OGRH.readyCheckResponses then return end
  
  -- Hide the timer
  OGRH.HideReadyCheckTimer()
  
  -- Broadcast to other addon users to hide their timers
  if OGRH.MessageRouter and OGRH.MessageTypes then
    OGRH.MessageRouter.Broadcast(
      OGRH.MessageTypes.ADMIN.READY_COMPLETE,
      "",
      {priority = "HIGH"}
    )
  end
  
  -- Build lookup table of raid members with class and online status
  local raidInfo = {}
  local numRaid = GetNumRaidMembers() or 0
  for j = 1, numRaid do
    local name, _, _, _, class, _, _, online = GetRaidRosterInfo(j)
    if name then
      raidInfo[name] = {class = class, online = online}
    end
  end
  
  -- Helper function to color player names
  local function ColorPlayerName(playerName, isOffline)
    local info = raidInfo[playerName]
    local coloredName
    
    if info and info.class then
      local classUpper = string.upper(info.class)
      local classColorHex = OGRH.ClassColorHex(classUpper)
      coloredName = classColorHex .. playerName .. "|r"
    else
      coloredName = playerName
    end
    
    -- Add asterisk if offline
    if isOffline or (info and not info.online) then
      coloredName = coloredName .. OGRH.COLOR.ROLE .. "*" .. OGRH.COLOR.RESET
    end
    
    return coloredName
  end
  
  local messages = {}
  local prefix = OGRH.Announce("OGRH: ")
  
  -- Report not ready players (most important)
  if table.getn(OGRH.readyCheckResponses.notReady) > 0 then
    local coloredPlayers = {}
    for _, playerName in ipairs(OGRH.readyCheckResponses.notReady) do
      table.insert(coloredPlayers, ColorPlayerName(playerName))
    end
    table.insert(messages, prefix .. OGRH.Header("Not Ready:") .. " " .. table.concat(coloredPlayers, ", "))
  end
  
  -- Report AFK players
  if table.getn(OGRH.readyCheckResponses.afk) > 0 then
    local coloredPlayers = {}
    for _, playerName in ipairs(OGRH.readyCheckResponses.afk) do
      table.insert(coloredPlayers, ColorPlayerName(playerName))
    end
    table.insert(messages, prefix .. OGRH.Header("AFK:") .. " " .. table.concat(coloredPlayers, ", "))
  end
  
  -- Calculate ready count
  -- Note: In vanilla WoW, "ready" responses don't generate system messages
  -- Only "not ready" and AFK generate messages, so we calculate ready by subtraction
  local notReadyCount = table.getn(OGRH.readyCheckResponses.notReady or {})
  local afkCount = table.getn(OGRH.readyCheckResponses.afk or {})
  local readyCount = numRaid - notReadyCount - afkCount
  
  if table.getn(messages) == 0 then
    -- Everyone is ready
    table.insert(messages, prefix .. OGRH.Header("All players are ready!") .. " (" .. readyCount .. "/" .. numRaid .. ")")
  else
    -- Add summary
    table.insert(messages, prefix .. OGRH.Header("Ready:") .. " " .. readyCount .. "/" .. numRaid)
  end
  
  -- Send all messages
  for _, msg in ipairs(messages) do
    OGRH.SayRW(msg)
  end
end

-- Helper functions for colored text
function OGRH.Header(text) return OGRH.COLOR.HEADER .. text .. OGRH.COLOR.RESET end
function OGRH.Role(text) return OGRH.COLOR.ROLE .. text .. OGRH.COLOR.RESET end
function OGRH.Announce(text) return OGRH.COLOR.ANNOUNCE .. text .. OGRH.COLOR.RESET end

OGRH.CLASS_RGB = {
  DRUID={1,0.49,0.04}, HUNTER={0.67,0.83,0.45}, MAGE={0.25,0.78,0.92}, PALADIN={0.96,0.55,0.73},
  PRIEST={1,1,1}, ROGUE={1,0.96,0.41}, SHAMAN={0,0.44,0.87}, WARLOCK={0.53,0.53,0.93}, WARRIOR={0.78,0.61,0.43}
}
function OGRH.ClassColorHex(class)
  if not class then return "|cffffffff" end
  local r,g,b = 1,1,1
  if RAID_CLASS_COLORS and RAID_CLASS_COLORS[class] then r,g,b = RAID_CLASS_COLORS[class].r, RAID_CLASS_COLORS[class].g, RAID_CLASS_COLORS[class].b
  elseif OGRH.CLASS_RGB[class] then r,g,b = OGRH.CLASS_RGB[class][1], OGRH.CLASS_RGB[class][2], OGRH.CLASS_RGB[class][3] end
  return string.format("|cff%02x%02x%02x", r*255, g*255, b*255)
end

-- Get player class from multiple sources with caching
function OGRH.GetPlayerClass(playerName)
  if not playerName then return nil end
  
  -- Check cache first
  if OGRH.classCache[playerName] then
    return OGRH.classCache[playerName]
  end
  
  -- Check raid roster (most reliable for current raid members)
  if OGRH.Roles.nameClass[playerName] then
    OGRH.classCache[playerName] = OGRH.Roles.nameClass[playerName]
    return OGRH.Roles.nameClass[playerName]
  end
  
  -- Check current raid roster directly
  local numRaid = GetNumRaidMembers()
  if numRaid > 0 then
    for i = 1, numRaid do
      local name, _, _, _, class = GetRaidRosterInfo(i)
      if name == playerName and class then
        local upperClass = string.upper(class)
        OGRH.classCache[playerName] = upperClass
        return upperClass
      end
    end
  end
  
  -- Check guild roster
  local numGuild = GetNumGuildMembers(true)
  if numGuild > 0 then
    for i = 1, numGuild do
      local name, _, _, _, class = GetGuildRosterInfo(i)
      if name == playerName and class then
        local upperClass = string.upper(class)
        OGRH.classCache[playerName] = upperClass
        return upperClass
      end
    end
  end
  
  -- Try UnitClass if player is targetable/in party
  -- Wrap in pcall to handle "Unknown unit name" errors gracefully
  local existsSuccess, unitExists = pcall(UnitExists, playerName)
  if existsSuccess and unitExists then
    local success, _, class = pcall(UnitClass, playerName)
    if success and class then
      local upperClass = string.upper(class)
      OGRH.classCache[playerName] = upperClass
      return upperClass
    end
  end
  
  return nil
end

OGRH.Roles = OGRH.Roles or {
  active=false, phaseIndex=0, silence=0, silenceGate=5, lastPlus=0, nextAdvanceTime=0,
  tankHeaders=false, healerHeaders=false, healRank={},
  buckets={ TANKS={}, HEALERS={}, MELEE={}, RANGED={} },
  nameClass={}, raidNames={}, raidParty={}, testing=false,
  iconHeaders = {}
}

function OGRH.ColorName(name)
  if not name or name=="" then return "" end
  local c = OGRH.Roles.nameClass[name]
  return (OGRH.ClassColorHex(c or "PRIEST"))..name.."|r"
end

function OGRH.RefreshRoster()
  if OGRH.Roles.testing then return end
  OGRH.Roles.raidNames = {}
  OGRH.Roles.nameClass = {}
  OGRH.Roles.raidParty = {}
  local n = GetNumRaidMembers() or 0
  local i
  for i=1,n do
    local name,_,subgroup,_,class = GetRaidRosterInfo(i)
    if name then
      OGRH.Roles.raidNames[name] = true
      if class then OGRH.Roles.nameClass[name] = string.upper(class) end
      if subgroup then OGRH.Roles.raidParty[name] = subgroup end
    end
  end
end

function OGRH.PruneBucketsToRaid()
  if OGRH.Roles.testing then return end
  local r, nm
  for r,_ in pairs(OGRH.Roles.buckets) do
    for nm,_ in pairs(OGRH.Roles.buckets[r]) do
      if not OGRH.Roles.raidNames[nm] then OGRH.Roles.buckets[r][nm] = nil end
    end
  end
end

function OGRH.InAnyBucket(nm)
  local r,_
  for r,_ in pairs(OGRH.Roles.buckets) do if OGRH.Roles.buckets[r][nm] then return true end end
end
function OGRH.AddTo(role, name)
  OGRH.EnsureSV()
  if not name or name=="" or not OGRH.Roles.buckets[role] then return end
  if not OGRH.Roles.testing and not OGRH.Roles.raidNames[name] then OGRH.Msg("Cannot assign "..name.." (not in raid)."); return end
  local k,_; for k,_ in pairs(OGRH.Roles.buckets) do OGRH.Roles.buckets[k][name]=nil end
  OGRH.Roles.buckets[role][name]=true
  OGRH_SV.roles[name]=role
  OGRH_SV.tankCategory[name]=nil; OGRH_SV.healerBoss[name]=nil
end

OGRH.CLASS_RGB = OGRH.CLASS_RGB
OGRH.ICON_NAMES = {"Star","Circle","Diamond","Triangle","Moon","Square","Cross","Skull"}

Roles = OGRH.Roles
ensureSV = OGRH.EnsureSV
colorName = OGRH.ColorName
sayRW = OGRH.SayRW
msg = OGRH.Msg

-- === MIGRATION: icon index mapping old->blizzard (run once) ===
function OGRH.MigrateIconOrder()
  if OGRH_SV and not OGRH_SV._icons_migrated then
    local function remap(v) if type(v)=="number" and v>=1 and v<=8 then return 9 - v end return v end
    if OGRH_SV.tankIcon then for k,v in pairs(OGRH_SV.tankIcon) do OGRH_SV.tankIcon[k]=remap(v) end end
    if OGRH_SV.healerIcon then for k,v in pairs(OGRH_SV.healerIcon) do OGRH_SV.healerIcon[k]=remap(v) end end
    OGRH_SV._icons_migrated = true
  end
end

-- === Player Assignment Functions (raid icons 1-8 or numbers 0-9) ===
-- Assignments are stored as tables: {type="icon", value=8} or {type="number", value=5}
-- Get player assignment: returns table {type="icon"|"number", value=0-9} or nil if unassigned
function OGRH.GetPlayerAssignment(playerName)
  OGRH.EnsureSV()
  return OGRH_SV.playerAssignments[playerName]
end

-- Set player assignment: assignData should be {type="icon"|"number", value=number} or nil to clear
function OGRH.SetPlayerAssignment(playerName, assignData)
  OGRH.EnsureSV()
  if assignData == nil then
    OGRH_SV.playerAssignments[playerName] = nil
  elseif type(assignData) == "table" and assignData.type and assignData.value then
    if (assignData.type == "icon" and assignData.value >= 1 and assignData.value <= 8) or
       (assignData.type == "number" and assignData.value >= 0 and assignData.value <= 9) then
      OGRH_SV.playerAssignments[playerName] = {type = assignData.type, value = assignData.value}
    end
  end
end

-- Clear all player assignments
function OGRH.ClearAllAssignments()
  OGRH.EnsureSV()
  OGRH_SV.playerAssignments = {}
end

-- Request raid data from raid members
function OGRH.RequestRaidData()
  if GetNumRaidMembers() == 0 then
    OGRH.Msg("You must be in a raid to request data.")
    return
  end
  
  -- Send request to raid
  SendAddonMessage(OGRH.ADDON_PREFIX, "REQUEST_RAID_DATA", "RAID")
  OGRH.Msg("Requesting encounter data from raid members...")
  
  -- Store that we're waiting for responses
  OGRH.waitingForRaidData = true
  OGRH.raidDataChunks = {} -- Store chunks by sender
  
  -- Set timeout to collect responses (90 seconds for chunked data)
  if not OGRH.raidDataTimer then
    OGRH.raidDataTimer = CreateFrame("Frame")
  end
  
  OGRH.raidDataTimer:SetScript("OnUpdate", nil)
  local elapsed = 0
  OGRH.raidDataTimer:SetScript("OnUpdate", function()
    elapsed = elapsed + arg1
    if elapsed >= 90 then
      OGRH.raidDataTimer:SetScript("OnUpdate", nil)
      OGRH.ProcessRaidDataResponses()
    end
  end)
end

-- Process collected raid data responses
function OGRH.ProcessRaidDataResponses()
  if not OGRH.waitingForRaidData then
    return
  end
  
  OGRH.waitingForRaidData = false
  
  if not OGRH.raidDataChunks then
    OGRH.Msg("No raid data received. Make sure other raid members have the addon installed.")
    return
  end
  
  -- Find first sender with complete data
  local completeData = nil
  local completeSender = nil
  
  for sender, chunks in pairs(OGRH.raidDataChunks) do
    if chunks.complete then
      completeData = chunks.data
      completeSender = sender
      break
    end
  end
  
  if not completeData then
    OGRH.Msg("No complete raid data received. Try again.")
    OGRH.raidDataChunks = {}
    return
  end
  
  -- Import the data
  if OGRH.ImportShareData then
    OGRH.ImportShareData(completeData)
    OGRH.Msg("Received encounter data from " .. completeSender .. ".")
  end
  
  OGRH.raidDataChunks = {}
end

-- Request current encounter assignment sync from raid lead
function OGRH.RequestCurrentEncounterSync()
  if GetNumRaidMembers() == 0 then
    return
  end
  
  -- Send request to raid
  SendAddonMessage(OGRH.ADDON_PREFIX, "REQUEST_CURRENT_ENCOUNTER", "RAID")
end

-- Request structure sync from raid lead (or broadcast if you are the lead)
function OGRH.RequestStructureSync()
  if GetNumRaidMembers() == 0 then
    OGRH.Msg("You must be in a raid.")
    return
  end
  
  -- Check if we're the raid lead
  local isRaidLead = false
  local currentAdmin = OGRH.GetRaidAdmin and OGRH.GetRaidAdmin()
  local playerName = UnitName("player")
  if currentAdmin then
    if currentAdmin == playerName then
      isRaidLead = true
    end
  end
  
  if isRaidLead then
    -- We're the raid lead, broadcast structure sync
    OGRH.BroadcastStructureSync()
  else
    -- Request structure sync from raid lead
    SendAddonMessage(OGRH.ADDON_PREFIX, "REQUEST_STRUCTURE_SYNC", "RAID")
    OGRH.Msg("Requesting structure sync from raid lead...")
    
    -- Store that we're waiting for structure sync
    OGRH.waitingForStructureSync = true
    OGRH.structureSyncChunks = {}
    
    -- Set timeout (90 seconds)
    if not OGRH.structureSyncTimer then
      OGRH.structureSyncTimer = CreateFrame("Frame")
    end
    
    OGRH.structureSyncTimer:SetScript("OnUpdate", nil)
    local elapsed = 0
    OGRH.structureSyncTimer:SetScript("OnUpdate", function()
      elapsed = elapsed + arg1
      if elapsed >= 90 then
        OGRH.structureSyncTimer:SetScript("OnUpdate", nil)
        if OGRH.waitingForStructureSync then
          OGRH.waitingForStructureSync = false
          OGRH.Msg("Structure sync timed out.")
        end
      end
    end)
  end
end

-- Broadcast structure sync (raid lead only)
function OGRH.BroadcastStructureSync()
  if GetNumRaidMembers() == 0 then
    OGRH.Msg("You must be in a raid.")
    return
  end
  
  -- Export data
  if not OGRH.ExportShareData then
    OGRH.Msg("Export function not available.")
    return
  end
  
  local exportedData = OGRH.ExportShareData()
  
  -- Show sync panel
  OGRH.ShowStructureSyncPanel(true, nil)
  
  -- Use OGRH.Sync.SendChunked to handle automatic chunking
  if OGRH.Sync and OGRH.Sync.SendChunked then
    -- For structure sync, we need to send the raw string data, so we wrap it
    local syncData = {
      type = "STRUCTURE_SYNC",
      data = exportedData
    }
    local success = OGRH.Sync.SendChunked(syncData, OGRH.Sync.MessageType.ENCOUNTER_STRUCTURE, "RAID")
    if success then
      OGRH.ShowStructureSyncProgress(true, 100, true, nil)
    else
      OGRH.Msg("Failed to send structure sync.")
    end
  else
    -- Fallback to old method if Sync module not loaded
    local chunkSize = 200
    local totalChunks = math.ceil(string.len(exportedData) / chunkSize)
    
    -- Send chunks with delay between them
    local chunkIndex = 0
    local chunkTimer = CreateFrame("Frame")
    local chunkElapsed = 0
    
    chunkTimer:SetScript("OnUpdate", function()
      chunkElapsed = chunkElapsed + arg1
      if chunkElapsed >= 0.5 then
        chunkElapsed = 0
        chunkIndex = chunkIndex + 1
        
        if chunkIndex <= totalChunks then
          local startPos = (chunkIndex - 1) * chunkSize + 1
          local endPos = math.min(chunkIndex * chunkSize, string.len(exportedData))
          local chunk = string.sub(exportedData, startPos, endPos)
          
          local msg = "STRUCTURE_SYNC_CHUNK;" .. chunkIndex .. ";" .. totalChunks .. ";" .. chunk
          SendAddonMessage(OGRH.ADDON_PREFIX, msg, "RAID")
          
          -- Update progress bar
          local progress = math.floor((chunkIndex / totalChunks) * 100)
          OGRH.ShowStructureSyncProgress(true, progress, false, nil)
        else
          chunkTimer:SetScript("OnUpdate", nil)
          OGRH.ShowStructureSyncProgress(true, 100, true, nil)
        end
      end
    end)
  end
end

-- Broadcast structure sync for a single encounter (raid lead only)
function OGRH.BroadcastEncounterStructureSync(raidName, encounterName, requester)
  if GetNumRaidMembers() == 0 then
    OGRH.Msg("You must be in a raid.")
    return
  end
  
  if not raidName or not encounterName then
    OGRH.Msg("No encounter specified.")
    return
  end
  
  -- Export only the selected encounter's structure
  if not OGRH.ExportEncounterShareData then
    OGRH.Msg("Export function not available.")
    return
  end
  
  local exportedData = OGRH.ExportEncounterShareData(raidName, encounterName)
  local requesterName = requester or ""  -- Track who requested this
  
  -- Show sync panel
  OGRH.ShowStructureSyncPanel(true, encounterName)
  
  -- Use OGRH.Sync.SendChunked to handle automatic chunking
  if OGRH.Sync and OGRH.Sync.SendChunked then
    -- For encounter structure sync, we need to send the raw string data
    local syncData = {
      type = "ENCOUNTER_STRUCTURE_SYNC",
      requester = requesterName,
      data = exportedData
    }
    local success = OGRH.Sync.SendChunked(syncData, OGRH.Sync.MessageType.ENCOUNTER_STRUCTURE, "RAID")
    if success then
      OGRH.ShowStructureSyncProgress(true, 100, true, encounterName)
    else
      OGRH.Msg("Failed to send encounter structure sync.")
    end
  else
    -- Fallback to old method if Sync module not loaded
    local chunkSize = 200
    local totalChunks = math.ceil(string.len(exportedData) / chunkSize)
    
    -- Send chunks with delay between them
    local chunkIndex = 0
    local chunkTimer = CreateFrame("Frame")
    local chunkElapsed = 0
    
    chunkTimer:SetScript("OnUpdate", function()
      chunkElapsed = chunkElapsed + arg1
      if chunkElapsed >= 0.5 then
        chunkElapsed = 0
        chunkIndex = chunkIndex + 1
        
        if chunkIndex <= totalChunks then
          local startPos = (chunkIndex - 1) * chunkSize + 1
          local endPos = math.min(chunkIndex * chunkSize, string.len(exportedData))
          local chunk = string.sub(exportedData, startPos, endPos)
          
          -- Include requester name so others can filter
          local msg = "ENCOUNTER_STRUCTURE_SYNC_CHUNK;" .. requesterName .. ";" .. chunkIndex .. ";" .. totalChunks .. ";" .. chunk
          SendAddonMessage(OGRH.ADDON_PREFIX, msg, "RAID")
          
          -- Update progress bar
          local progress = math.floor((chunkIndex / totalChunks) * 100)
          OGRH.ShowStructureSyncProgress(true, progress, false, encounterName)
        else
          chunkTimer:SetScript("OnUpdate", nil)
          OGRH.ShowStructureSyncProgress(true, 100, true, encounterName)
        end
      end
    end)
  end
end

-- Export data to string
function OGRH.ExportShareData()
  OGRH.EnsureSV()
  
  -- Collect all encounter management data (excluding player data)
  local encounterMgmt = {}
  if OGRH_SV.encounterMgmt then
    encounterMgmt.raids = OGRH_SV.encounterMgmt.raids
    encounterMgmt.roles = OGRH_SV.encounterMgmt.roles
    -- Explicitly exclude playerPools, encounterPools, encounterAssignments, poolDefaults
  end
  
  local exportData = {
    version = "1.0",
    encounterMgmt = encounterMgmt,
    encounterRaidMarks = OGRH_SV.encounterRaidMarks or {},
    encounterAssignmentNumbers = OGRH_SV.encounterAssignmentNumbers or {},
    encounterAnnouncements = OGRH_SV.encounterAnnouncements or {},
    tradeItems = OGRH_SV.tradeItems or {},
    consumes = OGRH.SVM.Get("consumes") or {},
    rgo = OGRH_SV.rgo or {}
  }
  
  -- Serialize to string (using a simple format)
  local serialized = OGRH.Serialize(exportData)
  return serialized
end

-- Export single encounter structure data to string
function OGRH.ExportEncounterShareData(raidName, encounterName)
  OGRH.EnsureSV()
  
  -- Collect only the specified encounter's structure data (new structure only)
  local encounterMgmt = {}
  if OGRH_SV.encounterMgmt then
    -- Find the specified raid
    local sourceRaid = OGRH.FindRaidByName(raidName)
    if sourceRaid then
      -- Include only this raid in the export
      encounterMgmt.raids = {}
      
      -- Find the specific encounter within the raid
      local sourceEncounter = OGRH.FindEncounterByName(sourceRaid, encounterName)
      if sourceEncounter then
        -- Create a copy of the raid with only this encounter
        local exportRaid = {
          name = raidName,
          encounters = {sourceEncounter},
          advancedSettings = sourceRaid.advancedSettings
        }
        table.insert(encounterMgmt.raids, exportRaid)
      end
    end
    
    -- Include only roles for the specified encounter
    encounterMgmt.roles = {}
    if OGRH_SV.encounterMgmt.roles and OGRH_SV.encounterMgmt.roles[raidName] and OGRH_SV.encounterMgmt.roles[raidName][encounterName] then
      encounterMgmt.roles[raidName] = {}
      encounterMgmt.roles[raidName][encounterName] = OGRH_SV.encounterMgmt.roles[raidName][encounterName]
    end
  end
  
  -- Filter marks, numbers, and announcements for only this encounter
  local encounterRaidMarks = {}
  if OGRH_SV.encounterRaidMarks and OGRH_SV.encounterRaidMarks[raidName] and OGRH_SV.encounterRaidMarks[raidName][encounterName] then
    encounterRaidMarks[raidName] = {}
    encounterRaidMarks[raidName][encounterName] = OGRH_SV.encounterRaidMarks[raidName][encounterName]
  end
  
  local encounterAssignmentNumbers = {}
  if OGRH_SV.encounterAssignmentNumbers and OGRH_SV.encounterAssignmentNumbers[raidName] and OGRH_SV.encounterAssignmentNumbers[raidName][encounterName] then
    encounterAssignmentNumbers[raidName] = {}
    encounterAssignmentNumbers[raidName][encounterName] = OGRH_SV.encounterAssignmentNumbers[raidName][encounterName]
  end
  
  local encounterAnnouncements = {}
  if OGRH_SV.encounterAnnouncements and OGRH_SV.encounterAnnouncements[raidName] and OGRH_SV.encounterAnnouncements[raidName][encounterName] then
    encounterAnnouncements[raidName] = {}
    encounterAnnouncements[raidName][encounterName] = OGRH_SV.encounterAnnouncements[raidName][encounterName]
  end
  
  local exportData = {
    version = "1.0",
    encounterMgmt = encounterMgmt,
    encounterRaidMarks = encounterRaidMarks,
    encounterAssignmentNumbers = encounterAssignmentNumbers,
    encounterAnnouncements = encounterAnnouncements,
    tradeItems = {},  -- Don't sync trade items for single encounter
    consumes = {}     -- Don't sync consumes for single encounter
  }
  
  -- Serialize to string
  local serialized = OGRH.Serialize(exportData)
  return serialized
end

-- Import data from string
function OGRH.ImportShareData(dataString, isSingleEncounter)
  if not dataString or dataString == "" then
    OGRH.Msg("No data to import.")
    return
  end
  
  -- Deserialize
  local success, importData = pcall(OGRH.Deserialize, dataString)
  
  if not success or not importData then
    OGRH.Msg("|cffff0000Error:|r Failed to parse import data.")
    return
  end
  
  -- Validate version
  if not importData.version then
    OGRH.Msg("|cffff0000Error:|r Invalid data format.")
    return
  end
  
  OGRH.EnsureSV()
  
  if isSingleEncounter then
    -- Merge single encounter data (don't overwrite existing data)
    if importData.encounterMgmt then
      if not OGRH_SV.encounterMgmt then OGRH_SV.encounterMgmt = {} end
      if not OGRH_SV.encounterMgmt.raids then OGRH_SV.encounterMgmt.raids = {} end
      
      -- Merge raids and encounters using new array-based structure
      if importData.encounterMgmt.raids then
        for i = 1, table.getn(importData.encounterMgmt.raids) do
          local importRaid = importData.encounterMgmt.raids[i]
          local importRaidName = importRaid.name
          
          -- Find or create raid in local data
          local localRaid = nil
          for j = 1, table.getn(OGRH_SV.encounterMgmt.raids) do
            if OGRH_SV.encounterMgmt.raids[j].name == importRaidName then
              localRaid = OGRH_SV.encounterMgmt.raids[j]
              break
            end
          end
          
          -- If raid doesn't exist, create it
          if not localRaid then
            localRaid = {
              name = importRaidName,
              encounters = {},
              advancedSettings = importRaid.advancedSettings or {
                consumeTracking = {
                  enabled = false,
                  readyThreshold = 85,
                  requiredFlaskRoles = {}
                },
                bigwigs = {
                  enabled = false,
                  raidZones = {},
                  autoAnnounce = false
                }
              }
            }
            table.insert(OGRH_SV.encounterMgmt.raids, localRaid)
          end
          
          -- Ensure local raid has encounters array
          if not localRaid.encounters then
            localRaid.encounters = {}
          end
          
          -- Merge encounters from import
          if importRaid.encounters then
            for k = 1, table.getn(importRaid.encounters) do
              local importEncounter = importRaid.encounters[k]
              local encounterExists = false
              
              -- Check if encounter already exists
              for m = 1, table.getn(localRaid.encounters) do
                if localRaid.encounters[m].name == importEncounter.name then
                  -- Update existing encounter (overwrite with imported data for single encounter sync)
                  localRaid.encounters[m] = importEncounter
                  encounterExists = true
                  break
                end
              end
              
              -- Add encounter if it doesn't exist
              if not encounterExists then
                table.insert(localRaid.encounters, importEncounter)
              end
            end
          end
        end
      end
      
      -- Merge roles for this encounter only
      if importData.encounterMgmt.roles then
        if not OGRH_SV.encounterMgmt.roles then OGRH_SV.encounterMgmt.roles = {} end
        for raidName, raidRoles in pairs(importData.encounterMgmt.roles) do
          if not OGRH_SV.encounterMgmt.roles[raidName] then OGRH_SV.encounterMgmt.roles[raidName] = {} end
          for encounterName, roles in pairs(raidRoles) do
            OGRH_SV.encounterMgmt.roles[raidName][encounterName] = roles
          end
        end
      end
    end
    
    -- Merge marks for this encounter only
    if importData.encounterRaidMarks then
      if not OGRH_SV.encounterRaidMarks then OGRH_SV.encounterRaidMarks = {} end
      for raidName, raidMarks in pairs(importData.encounterRaidMarks) do
        if not OGRH_SV.encounterRaidMarks[raidName] then OGRH_SV.encounterRaidMarks[raidName] = {} end
        for encounterName, marks in pairs(raidMarks) do
          OGRH_SV.encounterRaidMarks[raidName][encounterName] = marks
        end
      end
    end
    
    -- Merge numbers for this encounter only
    if importData.encounterAssignmentNumbers then
      if not OGRH_SV.encounterAssignmentNumbers then OGRH_SV.encounterAssignmentNumbers = {} end
      for raidName, raidNumbers in pairs(importData.encounterAssignmentNumbers) do
        if not OGRH_SV.encounterAssignmentNumbers[raidName] then OGRH_SV.encounterAssignmentNumbers[raidName] = {} end
        for encounterName, numbers in pairs(raidNumbers) do
          OGRH_SV.encounterAssignmentNumbers[raidName][encounterName] = numbers
        end
      end
    end
    
    -- Merge announcements for this encounter only
    if importData.encounterAnnouncements then
      if not OGRH_SV.encounterAnnouncements then OGRH_SV.encounterAnnouncements = {} end
      for raidName, raidAnnouncements in pairs(importData.encounterAnnouncements) do
        if not OGRH_SV.encounterAnnouncements[raidName] then OGRH_SV.encounterAnnouncements[raidName] = {} end
        for encounterName, announcements in pairs(raidAnnouncements) do
          OGRH_SV.encounterAnnouncements[raidName][encounterName] = announcements
        end
      end
    end
    
    OGRH.Msg("|cff00ff00Success:|r Encounter structure imported.")
  else
    -- Full import - overwrite everything
    if importData.encounterMgmt then
      OGRH_SV.encounterMgmt = importData.encounterMgmt
      
      -- Ensure advancedSettings exist for all raids and encounters (migration safety)
      if OGRH_SV.encounterMgmt.raids then
        for i = 1, table.getn(OGRH_SV.encounterMgmt.raids) do
          local raid = OGRH_SV.encounterMgmt.raids[i]
          if OGRH.EnsureRaidAdvancedSettings then
            OGRH.EnsureRaidAdvancedSettings(raid)
          end
          if raid.encounters then
            for j = 1, table.getn(raid.encounters) do
              local encounter = raid.encounters[j]
              if OGRH.EnsureEncounterAdvancedSettings then
                OGRH.EnsureEncounterAdvancedSettings(raid, encounter)
              end
            end
          end
        end
      end
    end
    if importData.encounterRaidMarks then
      OGRH_SV.encounterRaidMarks = importData.encounterRaidMarks
    end
    if importData.encounterAssignmentNumbers then
      OGRH_SV.encounterAssignmentNumbers = importData.encounterAssignmentNumbers
    end
    if importData.encounterAnnouncements then
      OGRH_SV.encounterAnnouncements = importData.encounterAnnouncements
    end
    if importData.tradeItems then
      OGRH_SV.tradeItems = importData.tradeItems
    end
    if importData.consumes then
      OGRH.SVM.Set("consumes", nil, importData.consumes)
    end
    if importData.rgo then
      OGRH_SV.rgo = importData.rgo
    end
    
    OGRH.Msg("|cff00ff00Success:|r Encounter data imported.")
    
    -- Debug: Check what was imported
    if OGRH_SV.encounterMgmt and OGRH_SV.encounterMgmt.raids then
      DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OGRH:|r Imported " .. table.getn(OGRH_SV.encounterMgmt.raids) .. " raids")
    else
      DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OGRH:|r encounterMgmt.raids is nil after import!")
    end
  end
  
  -- Refresh any open windows
  if OGRH_EncounterSetupFrame and OGRH_EncounterSetupFrame.RefreshAll then
    OGRH_EncounterSetupFrame.RefreshAll()
  end
  if OGRH_TradeSettingsFrame and OGRH_TradeSettingsFrame.RefreshList then
    OGRH_TradeSettingsFrame.RefreshList()
  end
  if OGRH_EncounterFrame and OGRH_EncounterFrame.RefreshRaidsList then
    OGRH_EncounterFrame.RefreshRaidsList()
  end
  if OGRH_ConsumesFrame and OGRH_ConsumesFrame.RefreshConsumesList then
    OGRH_ConsumesFrame.RefreshConsumesList()
  end
  -- Refresh RGO window (even if not visible, so it's ready when opened)
  if RGOFrame then
    for groupNum = 1, 8 do
      for slotNum = 1, 5 do
        OGRH.UpdateRGOSlotDisplay(groupNum, slotNum)
      end
    end
  end
end

-- Load factory defaults from OGRH_Defaults.lua
function OGRH.LoadFactoryDefaults()
  if not OGRH.FactoryDefaults or type(OGRH.FactoryDefaults) ~= "table" then
    OGRH.Msg("|cffff0000Error:|r No factory defaults configured in OGRH_Defaults.lua")
    OGRH.Msg("Edit OGRH_Defaults.lua and paste your export string after the = sign.")
    return
  end
  
  -- Check if it has the version field (basic validation)
  if not OGRH.FactoryDefaults.version then
    OGRH.Msg("|cffff0000Error:|r Invalid factory defaults format in OGRH_Defaults.lua")
    return
  end
  
  OGRH.EnsureSV()
  
  -- Import all encounter management data directly from the table
  if OGRH.FactoryDefaults.encounterMgmt then
    OGRH_SV.encounterMgmt = OGRH.FactoryDefaults.encounterMgmt
  end
  if OGRH.FactoryDefaults.encounterRaidMarks then
    OGRH_SV.encounterRaidMarks = OGRH.FactoryDefaults.encounterRaidMarks
  end
  if OGRH.FactoryDefaults.encounterAssignmentNumbers then
    OGRH_SV.encounterAssignmentNumbers = OGRH.FactoryDefaults.encounterAssignmentNumbers
  end
  if OGRH.FactoryDefaults.encounterAnnouncements then
    OGRH_SV.encounterAnnouncements = OGRH.FactoryDefaults.encounterAnnouncements
  end
  if OGRH.FactoryDefaults.tradeItems then
    OGRH_SV.tradeItems = OGRH.FactoryDefaults.tradeItems
  end
  if OGRH.FactoryDefaults.consumes then
    OGRH.SVM.Set("consumes", nil, OGRH.FactoryDefaults.consumes)
  end
  if OGRH.FactoryDefaults.rgo then
    OGRH_SV.rgo = OGRH.FactoryDefaults.rgo
  end
  
  -- Factory defaults loaded silently - no user-facing message needed
  
  -- Refresh any open windows
  if OGRH_EncounterSetupFrame and OGRH_EncounterSetupFrame.RefreshAll then
    OGRH_EncounterSetupFrame.RefreshAll()
  end
  if OGRH_TradeSettingsFrame and OGRH_TradeSettingsFrame.RefreshList then
    OGRH_TradeSettingsFrame.RefreshList()
  end
  if OGRH_EncounterFrame and OGRH_EncounterFrame.RefreshRaidsList then
    OGRH_EncounterFrame.RefreshRaidsList()
  end
  if OGRH_ConsumesFrame and OGRH_ConsumesFrame.RefreshConsumesList then
    OGRH_ConsumesFrame.RefreshConsumesList()
  end
  -- Refresh RGO window (even if not visible, so it's ready when opened)
  if RGOFrame then
    for groupNum = 1, 8 do
      for slotNum = 1, 5 do
        OGRH.UpdateRGOSlotDisplay(groupNum, slotNum)
      end
    end
  end
end

-- Trade Settings Window
-- Trade settings UI moved to Raid/Trade.lua

-- Create minimap button
local function CreateMinimapButton()
  local button = CreateFrame("Button", "OGRHMinimapButton", Minimap)
  button:SetWidth(32)
  button:SetHeight(32)
  button:SetFrameStrata("MEDIUM")
  button:SetFrameLevel(8)
  button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  
  -- Background texture
  local background = button:CreateTexture(nil, "BACKGROUND")
  background:SetWidth(20)
  background:SetHeight(20)
  background:SetPoint("CENTER", 0, 1)
  background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  
  -- Border
  local border = button:CreateTexture(nil, "OVERLAY")
  border:SetWidth(52)
  border:SetHeight(52)
  border:SetPoint("TOPLEFT", 0, 0)
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  
  -- Text label (RH)
  local text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  text:SetPoint("CENTER", 0, 1)
  text:SetText("RH")
  text:SetTextColor(1, 1, 0)
  
  -- Position
  OGRH.EnsureSV()
  local minimap = OGRH.SVM.GetPath("minimap")
  if not minimap then
    OGRH.SVM.SetPath("minimap", {angle = 200})
  end
  
  local function UpdatePosition()
    local minimap = OGRH.SVM.GetPath("minimap")
    local angle = minimap and minimap.angle or 200
    local x = 80 * math.cos(angle)
    local y = 80 * math.sin(angle)
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
  end
  
  UpdatePosition()
  
  -- Create right-click menu
  local function ShowMinimapMenu(sourceButton)
    if not OGRH_MinimapMenu then
      -- Create menu using the standard menu builder
      local menu = OGRH.CreateStandardMenu({
        name = "OGRH_MinimapMenu",
        width = 160,
        title = "OG-RaidHelper",
        titleColor = {1, 0.82, 0}, -- Gold title color
        itemColor = {1, 1, 1} -- White menu items
      })
      
      OGRH_MinimapMenu = menu
      
      -- Invites (direct click, no submenu)
      local invitesItem = menu:AddItem({
        text = "Invites",
        onClick = function()
          if not OGRH.ROLLFOR_AVAILABLE then
            OGRH.Msg("Invites requires RollFor version " .. OGRH.ROLLFOR_REQUIRED_VERSION .. ".")
            return
          end
          
          OGRH.CloseAllWindows("OGRH_InvitesFrame")
          
          if OGRH.Invites and OGRH.Invites.ShowWindow then
            OGRH.Invites.ShowWindow()
          else
            OGRH.Msg("Invites module not loaded.")
          end
        end
      })
      
      -- Gray out if RollFor not available
      if not OGRH.ROLLFOR_AVAILABLE then
        invitesItem.fs:SetTextColor(0.5, 0.5, 0.5)
      end
      
      -- Guild Recruitment
      menu:AddItem({
        text = "Guild Recruitment",
        onClick = function()
          if OGRH.ShowRecruitmentWindow then
            OGRH.ShowRecruitmentWindow()
          else
            OGRH.Msg("Recruitment module not loaded.")
          end
        end
      })
      
      -- SR Validation
      local srValidationItem = menu:AddItem({
        text = "SR Validation",
        onClick = function()
          if not OGRH.ROLLFOR_AVAILABLE then
            OGRH.Msg("SR Validation requires RollFor version " .. OGRH.ROLLFOR_REQUIRED_VERSION .. ".")
            return
          end
          
          OGRH.CloseAllWindows("OGRH_SRValidationFrame")
          
          if OGRH.SRValidation and OGRH.SRValidation.ShowWindow then
            OGRH.SRValidation.ShowWindow()
          else
            OGRH.Msg("SR Validation module not loaded.")
          end
        end
      })
      
      -- Gray out if RollFor not available
      if not OGRH.ROLLFOR_AVAILABLE then
        srValidationItem.fs:SetTextColor(0.5, 0.5, 0.5)
      end
      
      -- Settings submenu (moved here, will be added to menu after Hide)
      local settingsItems = {
          {
            text = "Encounters",
            onClick = function()
              OGRH.CloseAllWindows("OGRH_EncounterSetupFrame")
              if OGRH.ShowEncounterSetup then
                OGRH.ShowEncounterSetup()
              end
            end
          },
          {
            text = "Trade",
            onClick = function()
              if OGRH.ShowTradeSettings then
                OGRH.ShowTradeSettings()
              else
                OGRH.Msg("Trade Settings module not loaded.")
              end
            end
          },
          {
            text = "Consumes",
            onClick = function()
              if OGRH.ShowConsumesSettings then
                OGRH.ShowConsumesSettings()
              else
                OGRH.Msg("Consumes module not loaded.")
              end
            end
          },
          {
            text = "Monitor Consumes",
            onClick = function()
              OGRH.EnsureSV()
              local currentValue = OGRH.SVM.Get("monitorConsumes")
              OGRH.SVM.Set("monitorConsumes", nil, not currentValue)
              
              if OGRH.SVM.Get("monitorConsumes") then
                if OGRH.ShowConsumeMonitor then
                  OGRH.ShowConsumeMonitor()
                end
                OGRH.Msg("Consume monitoring |cff00ff00enabled|r.")
              else
                if OGRH.HideConsumeMonitor then
                  OGRH.HideConsumeMonitor()
                end
                OGRH.Msg("Consume monitoring |cffff0000disabled|r.")
              end
            end
          },
          {
            text = "Track Consumes",
            onClick = function()
              OGRH.CloseAllWindows("OGRH_TrackConsumesFrame")
              if OGRH.ShowTrackConsumes then
                OGRH.ShowTrackConsumes()
              else
                OGRH.Msg("Track Consumes module not loaded.")
              end
            end
          },
          {
            text = "Auto Promote",
            onClick = function()
              if OGRH.ShowAutoPromote then
                OGRH.ShowAutoPromote()
              else
                OGRH.Msg("Auto Promote module not loaded.")
              end
            end
          },
          -- DEPRECATED: RGO feature has been removed. Use Roster Management instead.
          -- {
          --   text = "Raid Group Organization",
          --   onClick = function()
          --     if OGRH.ShowRGOWindow then
          --       OGRH.ShowRGOWindow()
          --     else
          --       OGRH.Msg("Raid Group Organization module not loaded.")
          --     end
          --   end
          -- },
          {
            text = "Roster Management",
            onClick = function()
              if OGRH.RosterMgmt and OGRH.RosterMgmt.ShowWindow then
                OGRH.RosterMgmt.ShowWindow()
              else
                OGRH.Msg("Roster Management module not loaded.")
              end
            end
          },
          {
            text = "Data Management",
            onClick = function()
              OGRH.CloseAllWindows("OGRH_DataManagementFrame")
              if OGRH.DataManagement and OGRH.DataManagement.ShowWindow then
                OGRH.DataManagement.ShowWindow()
              else
                OGRH.Msg("Data Management module not loaded.")
              end
            end
          }
      }
      
      -- Modules submenu
      menu:AddItem({
        text = "Modules",
        submenu = {
          {
            text = "Consume Helper",
            onClick = function()
              if OGRH.ShowManageConsumes then
                OGRH.ShowManageConsumes()
              else
                OGRH.Msg("Consume Helper module not loaded.")
              end
            end
          }
        }
      })
      
      -- Hide/Show toggle
      menu.toggleItem = menu:AddItem({
        text = "Hide",
        onClick = function()
          if OGRH_Main then
            if OGRH_Main:IsVisible() then
              OGRH_Main:Hide()
              OGRH.SVM.Set("ui", "hidden", true)
            else
              OGRH_Main:Show()
              OGRH.SVM.Set("ui", "hidden", false)
            end
          end
        end
      })
      
      -- Settings submenu (at bottom)
      local settingsMenuItem = menu:AddItem({
        text = "Settings",
        submenu = settingsItems
      })
      
      -- Hook into Settings menu item OnEnter to update Monitor Consumes text before submenu shows
      local originalOnEnter = settingsMenuItem:GetScript("OnEnter")
      settingsMenuItem:SetScript("OnEnter", function()
        -- Clear cached submenu to force recreation with updated text
        settingsMenuItem.submenu = nil
        
        -- Update Monitor Consumes text (4th item in settings) before submenu is created
        OGRH.EnsureSV()
        if OGRH.SVM.Get("monitorConsumes") then
          settingsItems[4].text = "|cff00ff00Monitor Consumes|r"
        else
          settingsItems[4].text = "Monitor Consumes"
        end
        
        -- Call original OnEnter to show submenu
        if originalOnEnter then
          originalOnEnter()
        end
      end)
      
      -- Helper function to update toggle text
      menu.UpdateToggleText = function()
        if OGRH_Main and OGRH_Main:IsVisible() then
          menu.toggleItem.fs:SetText("Hide")
        else
          menu.toggleItem.fs:SetText("Show")
        end
      end
      
      -- Finalize menu height
      menu:Finalize()
    end
    
    local menu = OGRH_MinimapMenu
    
    -- Toggle menu visibility
    if menu:IsVisible() then
      menu:Hide()
      return
    end
    
    -- Update toggle button text
    menu.UpdateToggleText()
    
    -- Position menu near source button with boundary checking
    menu:ClearAllPoints()
    
    -- Use provided button or fall back to minimap button
    local targetButton = sourceButton or button
    
    -- Get screen dimensions
    local screenWidth = UIParent:GetWidth()
    local screenHeight = UIParent:GetHeight()
    
    -- Get button position
    local btnX, btnY = targetButton:GetCenter()
    local menuWidth = menu:GetWidth()
    local menuHeight = menu:GetHeight()
    
    -- Default position: below and left-aligned
    local anchorPoint = "TOPLEFT"
    local relativePoint = "BOTTOMLEFT"
    local xOffset = 0
    local yOffset = -5
    
    -- Check if menu would go off right edge
    if btnX + menuWidth > screenWidth then
      -- Align right edge of menu with button
      anchorPoint = "TOPRIGHT"
      relativePoint = "BOTTOMRIGHT"
    end
    
    -- Check if menu would go off bottom edge
    if btnY - menuHeight < 0 then
      -- Position above button instead
      if anchorPoint == "TOPLEFT" then
        anchorPoint = "BOTTOMLEFT"
        relativePoint = "TOPLEFT"
      else
        anchorPoint = "BOTTOMRIGHT"
        relativePoint = "TOPRIGHT"
      end
      yOffset = 5
    end
    
    menu:SetPoint(anchorPoint, targetButton, relativePoint, xOffset, yOffset)
    menu:Show()
  end
  
  -- Click handler (left-click toggles, right-click shows menu)
  button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  button:SetScript("OnClick", function()
    if arg1 == "RightButton" then
      ShowMinimapMenu()
    else
      -- Left-click: toggle window
      if OGRH_Main then
        if OGRH_Main:IsVisible() then
          OGRH_Main:Hide()
          OGRH_SV.ui.hidden = true
        else
          OGRH_Main:Show()
          OGRH_SV.ui.hidden = false
        end
      end
    end
  end)
  
  -- Drag to reposition
  button:RegisterForDrag("LeftButton")
  button:SetScript("OnDragStart", function()
    button:SetScript("OnUpdate", function()
      local mx, my = Minimap:GetCenter()
      local px, py = GetCursorPosition()
      local scale = Minimap:GetEffectiveScale()
      px, py = px / scale, py / scale
      
      local angle = math.atan2(py - my, px - mx)
      OGRH_SV.minimap.angle = angle
      UpdatePosition()
    end)
  end)
  
  button:SetScript("OnDragStop", function()
    button:SetScript("OnUpdate", nil)
  end)
  
  -- Tooltip
  button:SetScript("OnEnter", function()
    GameTooltip:SetOwner(button, "ANCHOR_LEFT")
    GameTooltip:SetText("|cff66ccffOG-RaidHelper|r")
    GameTooltip:AddLine("Left-click to toggle main window", 1, 1, 1)
    GameTooltip:AddLine("Right-click for menu", 1, 1, 1)
    GameTooltip:AddLine("Drag to move", 0.8, 0.8, 0.8)
    GameTooltip:Show()
  end)
  
  button:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)
  
  OGRH.minimapButton = button
  
  -- Expose menu function globally for RH button
  OGRH.ShowMinimapMenu = ShowMinimapMenu
end

-- Create minimap button on load
local minimapLoader = CreateFrame("Frame")
minimapLoader:RegisterEvent("PLAYER_LOGIN")
minimapLoader:SetScript("OnEvent", function()
  CreateMinimapButton()
end)

-- ============================================================================
-- Helper Functions - Consumables Tracking Integration
-- ============================================================================

-- Get currently selected raid and encounter from main UI
-- Used by consumables tracking module to capture historical records
-- @return string, string: raid name, encounter name (or nil, nil if not selected)
function OGRH.GetSelectedRaidAndEncounter()
  -- Get indices
  local raidIdx, encIdx = OGRH.GetCurrentEncounter()
  if not raidIdx or not encIdx then
    return nil, nil
  end
  
  -- Get raid/encounter objects
  local raids = OGRH.SVM.GetPath("encounterMgmt.raids")
  if not raids or not raids[raidIdx] then
    return nil, nil
  end
  
  local raid = raids[raidIdx]
  local encounter = raid.encounters and raid.encounters[encIdx]
  if not encounter then
    return nil, nil
  end
  
  -- Use displayName for raid (e.g., "[AR] AQ40") and strip [AR] prefix if present
  local raidName = raid.displayName or raid.name
  if raidName then
    -- Strip "[AR] " prefix from Active Raid
    raidName = string.gsub(raidName, "^%[AR%]%s*", "")
  end
  
  local encounterName = encounter.name
  
  return raidName, encounterName
end




