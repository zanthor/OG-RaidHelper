-- OGRH_BigWigs.lua
-- BigWigs encounter detection integration

OGRH.BigWigs = OGRH.BigWigs or {}
OGRH.BigWigs.State = OGRH.BigWigs.State or {
  debug = false
}

-- Track last detected encounter to avoid duplicate switches
local lastDetectedEncounter = nil

-- Track last announcement to avoid spam
local lastAnnouncement = {
  raidName = nil,
  encounterName = nil,
  time = 0
}

-- Track last consume tracking time to avoid spam
local lastConsumeTrackingTime = 0

-- Function to check if BigWigs module name matches any configured encounter
local function FindMatchingEncounter(bigwigsModuleName)
  local encounterMgmt = OGRH.SVM.GetPath('encounterMgmt')
  if not encounterMgmt or not encounterMgmt.raids then
    return nil, nil
  end
  
  -- Only check the active raid (index 1)
  local raid = encounterMgmt.raids[1]
  if not raid or not raid.encounters then
    return nil, nil
  end
  
  -- Iterate through all encounters in the active raid
  for j = 1, table.getn(raid.encounters) do
    local encounter = raid.encounters[j]
    
    -- Ensure encounter has advanced settings with BigWigs config
    if encounter.advancedSettings and 
       encounter.advancedSettings.bigwigs and 
       encounter.advancedSettings.bigwigs.enabled then
      
      -- Get the array of configured BigWigs encounters for this OGRH encounter
      local encounterIds = encounter.advancedSettings.bigwigs.encounterIds
      
      -- Check if BigWigs module name is in the configured list
      if encounterIds and table.getn(encounterIds) > 0 then
        for k = 1, table.getn(encounterIds) do
          if encounterIds[k] == bigwigsModuleName then
            -- Found a match!
            return raid.name, encounter.name
          end
        end
      end
    end
  end
  
  return nil, nil
end

-- Function to auto-select raid/encounter when BigWigs detects it
function OGRH.BigWigs.OnEncounterDetected(moduleName)
  if not moduleName or moduleName == "" then return end
  
  if OGRH.BigWigs.State.debug then
    OGRH.Msg("|cff00ff00[RH-BigWigs DEBUG]|r OnEncounterDetected called with: " .. tostring(moduleName))
  end
  
  -- Avoid duplicate processing
  if lastDetectedEncounter == moduleName then
    if OGRH.BigWigs.State.debug then
      OGRH.Msg("|cff00ff00[RH-BigWigs DEBUG]|r Skipping duplicate detection")
    end
    return
  end
  
  -- Check if player is raid admin (not just leader/assist)
  if GetNumRaidMembers() > 0 then
    if not OGRH.IsRaidAdmin or not OGRH.IsRaidAdmin(UnitName("player")) then
      if OGRH.BigWigs.State.debug then
        OGRH.Msg("|cff00ff00[RH-BigWigs DEBUG]|r Not raid admin, skipping")
      end
      return
    end
  end
  
  -- Find matching OGRH encounter
  local raidName, encounterName = FindMatchingEncounter(moduleName)
  
  if OGRH.BigWigs.State.debug then
    OGRH.Msg("|cff00ff00[RH-BigWigs DEBUG]|r FindMatchingEncounter returned: raidName=" .. tostring(raidName) .. ", encounterName=" .. tostring(encounterName))
  end
  
  if raidName and encounterName then
    -- Update last detected to avoid spam
    lastDetectedEncounter = moduleName
    
    -- Set the main UI selection (not planning window)
    OGRH.EnsureSV()
    
    -- Convert names to indices for v2 schema
    local raidIdx, encIdx = OGRH.FindRaidAndEncounterIndices(raidName, encounterName)
    
    -- Use centralized API to set current encounter (handles sync automatically)
    if OGRH.SetCurrentEncounter and raidIdx and encIdx then
      OGRH.SetCurrentEncounter(raidIdx, encIdx)
    end
    
    -- Refresh main UI if it exists
    if OGRH.UpdateEncounterNavButton then
      OGRH.UpdateEncounterNavButton()
    end
    
    -- Notify user
    OGRH.Msg("|cffff6666[RH-BigWigs]|r Auto-selected: " .. encounterName .. " (" .. raidName .. ")")
    
    -- Auto-mark players if encounter has marks configured
    if OGRH.MarkPlayersFromMainUI and GetNumRaidMembers() > 0 then
      -- Check if this encounter has any marks configured
      local hasMarks = false
      
      -- Find raid and encounter indices
      local raidIdx, encIdx = OGRH.FindRaidAndEncounterIndices(raidName, encounterName)
      if raidIdx and encIdx then
        local encounterMgmt = OGRH.SVM.GetPath('encounterMgmt')
        if encounterMgmt and encounterMgmt.raids[raidIdx] and 
           encounterMgmt.raids[raidIdx].encounters[encIdx] then
          
          local encounter = encounterMgmt.raids[raidIdx].encounters[encIdx]
          
          -- Check if any role has markPlayer enabled (v2: roles is flat array)
          if encounter.roles then
            for i = 1, table.getn(encounter.roles) do
              if encounter.roles[i].markPlayer then
                hasMarks = true
                break
              end
            end
          end
        end
      end
      
      if hasMarks then
        OGRH.MarkPlayersFromMainUI()
        OGRH.Msg("|cffff6666[RH-BigWigs]|r Auto-marked players")
      end
    end
    
    -- Check if auto-announce is enabled for this encounter
    local raid = OGRH.FindRaidByName(raidName)
    if raid then
      local encounter = OGRH.FindEncounterByName(raid, encounterName)
      if encounter and encounter.advancedSettings and 
         encounter.advancedSettings.bigwigs and 
         encounter.advancedSettings.bigwigs.autoAnnounce then
        
        -- Check if this is a back-to-back repeat
        local now = GetTime()
        if lastAnnouncement.raidName ~= raidName or 
           lastAnnouncement.encounterName ~= encounterName or 
           (now - lastAnnouncement.time) > 30 then -- 30 second cooldown
          
          -- Update last announcement tracker
          lastAnnouncement.raidName = raidName
          lastAnnouncement.encounterName = encounterName
          lastAnnouncement.time = now
          
          -- Auto-announce the encounter
          if OGRH.Announcements and OGRH.Announcements.SendEncounterAnnouncement then
            OGRH.Announcements.SendEncounterAnnouncement(raidName, encounterName)
            OGRH.Msg("|cffff6666[RH-BigWigs]|r Auto-announcing encounter")
          end
        end
      end
    end
  end
end

-- Function to handle boss engagement (combat start)
function OGRH.BigWigs.OnBossEngage(moduleName)
  if not moduleName or moduleName == "" then return end
  
  if OGRH.BigWigs.State.debug then
    OGRH.Msg("|cff00ff00[RH-BigWigs DEBUG]|r OnBossEngage called with: " .. tostring(moduleName))
  end
  
  -- Trigger consume tracking if enabled (don't change encounter)
  if OGRH.ConsumesTracking and OGRH.ConsumesTracking.CaptureConsumesSnapshot then
    local trackOnPull = OGRH.SVM.GetPath("consumesTracking.trackOnPull")
    if trackOnPull then
      -- Check if this is a back-to-back repeat
      local now = GetTime()
      if (now - lastConsumeTrackingTime) > 30 then -- 30 second cooldown
        lastConsumeTrackingTime = now
        
        -- Capture consumes snapshot for currently selected encounter
        OGRH.ConsumesTracking.CaptureConsumesSnapshot()
        OGRH.Msg("|cffff6666[RH-BigWigs]|r Captured consume snapshot on boss engage")
      end
    end
  end
end

-- Hook into BigWigs module enable and engage events
local function HookBigWigs()
  if not BigWigs then
    -- BigWigs not loaded yet, try again later
    OGRH.ScheduleTimer(HookBigWigs, 1)
    return
  end
  
  -- Hook each module's OnEnable and Engage functions
  if BigWigs.modules then
    local count = 0
    for name, module in pairs(BigWigs.modules) do
      -- Hook OnEnable for encounter selection
      if module.OnEnable then
        local originalOnEnable = module.OnEnable
        module.OnEnable = function(self)
          -- Call original
          originalOnEnable(self)
          
          -- DEBUG: Log what properties are available
          if OGRH.BigWigs.State.debug then
            OGRH.Msg("|cff00ff00[RH-BigWigs DEBUG]|r Module enabled:")
            OGRH.Msg("  name: " .. tostring(name))
            OGRH.Msg("  self.name: " .. tostring(self.name))
            OGRH.Msg("  self.translatedName: " .. tostring(self.translatedName))
            OGRH.Msg("  self.displayName: " .. tostring(self.displayName))
          end
          
          -- Try different properties to find the right one
          local moduleName = self.translatedName or self.name or name
          if moduleName then
            if OGRH.BigWigs.State.debug then
              OGRH.Msg("  Using: " .. tostring(moduleName))
            end
            OGRH.BigWigs.OnEncounterDetected(moduleName)
          end
        end
        count = count + 1
      end
      
      -- Hook Engage for consume tracking
      if module.Engage then
        local originalEngage = module.Engage
        module.Engage = function(self)
          -- Call original
          originalEngage(self)
          
          if OGRH.BigWigs.State.debug then
            OGRH.Msg("|cff00ff00[RH-BigWigs DEBUG]|r Boss engage detected")
          end
          
          -- Try different properties to find the right one
          local moduleName = self.translatedName or self.name or name
          if moduleName then
            OGRH.BigWigs.OnBossEngage(moduleName)
          end
        end
      end
    end
    
    -- BigWigs integration active silently - no user-facing message
  else
    OGRH.Msg("|cffff0000[RH-BigWigs]|r Error: BigWigs.modules not found")
  end
end

-- Initialize on VARIABLES_LOADED
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("VARIABLES_LOADED")
initFrame:SetScript("OnEvent", function()
  if event == "VARIABLES_LOADED" then
    -- Wait a bit for BigWigs to fully load
    OGRH.ScheduleTimer(HookBigWigs, 2)
  end
end)

-- ============================================================================
-- Test Functions
-- ============================================================================

-- Test function to simulate BigWigs encounter detection
-- Usage: /script OGRH.BigWigs.TestEncounterDetection("Baron Geddon")
function OGRH.BigWigs.TestEncounterDetection(moduleName)
  if not moduleName then
    OGRH.Msg("|cffff0000[RH-BigWigs Test]|r Usage: OGRH.BigWigs.TestEncounterDetection(\"Baron Geddon\")")
    return
  end
  
  OGRH.Msg("|cff00ff00[RH-BigWigs Test]|r Simulating encounter detection for: " .. moduleName)
  OGRH.BigWigs.OnEncounterDetected(moduleName)
end

-- Test function to simulate BigWigs boss engagement
-- Usage: /script OGRH.BigWigs.TestBossEngage("Baron Geddon")
function OGRH.BigWigs.TestBossEngage(moduleName)
  if not moduleName then
    OGRH.Msg("|cffff0000[RH-BigWigs Test]|r Usage: OGRH.BigWigs.TestBossEngage(\"Baron Geddon\")")
    return
  end
  
  OGRH.Msg("|cff00ff00[RH-BigWigs Test]|r Simulating boss engage for: " .. moduleName)
  OGRH.BigWigs.OnBossEngage(moduleName)
end
