-- OGRH_BigWigs.lua
-- BigWigs encounter detection integration

OGRH.BigWigs = OGRH.BigWigs or {}

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
  if not OGRH_SV or not OGRH_SV.encounterMgmt or not OGRH_SV.encounterMgmt.raids then
    return nil, nil
  end
  
  -- Iterate through all raids
  for i = 1, table.getn(OGRH_SV.encounterMgmt.raids) do
    local raid = OGRH_SV.encounterMgmt.raids[i]
    
    -- Ensure raid has encounters
    if raid.encounters then
      -- Iterate through all encounters in this raid
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
    end
  end
  
  return nil, nil
end

-- Function to auto-select raid/encounter when BigWigs detects it
function OGRH.BigWigs.OnEncounterDetected(moduleName)
  if not moduleName or moduleName == "" then return end
  
  -- Avoid duplicate processing
  if lastDetectedEncounter == moduleName then
    return
  end
  
  -- Check if player is raid admin (not just leader/assist)
  if GetNumRaidMembers() > 0 then
    if not OGRH.IsRaidAdmin or not OGRH.IsRaidAdmin() then
      return
    end
  end
  
  -- Find matching OGRH encounter
  local raidName, encounterName = FindMatchingEncounter(moduleName)
  
  if raidName and encounterName then
    -- Update last detected to avoid spam
    lastDetectedEncounter = moduleName
    
    -- Set the main UI selection (not planning window)
    OGRH.EnsureSV()
    if not OGRH_SV.ui then
      OGRH_SV.ui = {}
    end
    
    OGRH_SV.ui.selectedRaid = raidName
    OGRH_SV.ui.selectedEncounter = encounterName
    
    -- Refresh main UI if it exists
    if OGRH.UpdateEncounterNavButton then
      OGRH.UpdateEncounterNavButton()
    end
    
    -- Broadcast encounter selection to raid (so everyone switches)
    if GetNumRaidMembers() > 0 and OGRH.MessageRouter then
      OGRH.MessageRouter.Broadcast(OGRH.MessageTypes.STATE.CHANGE_ENCOUNTER, {
        raidName = raidName,
        encounterName = encounterName
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
          raidName = raidName,
          encounterName = encounterName
        }, {
          priority = "NORMAL"
        })
      end
    end
    
    -- Notify user
    OGRH.Msg("|cffff6666[RH-BigWigs]|r Auto-selected: " .. encounterName .. " (" .. raidName .. ")")
    
    -- Auto-mark players if encounter has marks configured
    if OGRH.MarkPlayersFromMainUI and GetNumRaidMembers() > 0 then
      -- Check if this encounter has any marks configured
      local hasMarks = false
      if OGRH_SV.encounterMgmt and OGRH_SV.encounterMgmt.roles and
         OGRH_SV.encounterMgmt.roles[raidName] and
         OGRH_SV.encounterMgmt.roles[raidName][encounterName] then
        
        local encounterRoles = OGRH_SV.encounterMgmt.roles[raidName][encounterName]
        local column1 = encounterRoles.column1 or {}
        local column2 = encounterRoles.column2 or {}
        
        -- Check if any role has markPlayer enabled
        for i = 1, table.getn(column1) do
          if column1[i].markPlayer then
            hasMarks = true
            break
          end
        end
        
        if not hasMarks then
          for i = 1, table.getn(column2) do
            if column2[i].markPlayer then
              hasMarks = true
              break
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

-- Hook into BigWigs module enable
local function HookBigWigs()
  if not BigWigs then
    -- BigWigs not loaded yet, try again later
    OGRH.ScheduleTimer(HookBigWigs, 1)
    return
  end
  
  -- Hook each module's OnEnable function for detection
  if BigWigs.modules then
    local count = 0
    for name, module in pairs(BigWigs.modules) do
      if module.OnEnable then
        local originalOnEnable = module.OnEnable
        module.OnEnable = function(self)
          -- Call original
          originalOnEnable(self)
          
          -- Detect encounter
          if self.translatedName then
            OGRH.BigWigs.OnEncounterDetected(self.translatedName)
          end
        end
        count = count + 1
      end
      
      -- Hook Engage function for consume tracking trigger
      if module.Engage then
        local originalEngage = module.Engage
        module.Engage = function(self)
          -- Call original
          originalEngage(self)
          
          -- Trigger consume tracking (like /pull does at 2 seconds)
          if self.translatedName then
            local now = GetTime()
            -- Only trigger if it's been more than 10 seconds since last consume tracking
            if (now - lastConsumeTrackingTime) > 10 then
              lastConsumeTrackingTime = now
              
              -- Schedule consume tracking after 2 seconds (like /pull)
              OGRH.ScheduleTimer(function()
                if OGRH.StartConsumeCountdown then
                  OGRH.StartConsumeCountdown()
                end
              end, 2)
            end
          end
        end
      end
    end
    
    OGRH.Msg("|cff00ff00[RH-BigWigs]|r Integration active (hooked " .. count .. " modules)")
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
