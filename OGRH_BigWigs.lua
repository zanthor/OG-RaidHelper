-- OGRH_BigWigs.lua
-- BigWigs encounter detection integration

OGRH.BigWigs = OGRH.BigWigs or {}

-- Track last detected encounter to avoid duplicate switches
local lastDetectedEncounter = nil

-- Function to check if BigWigs module name matches any configured encounter
local function FindMatchingEncounter(bigwigsModuleName)
  DEFAULT_CHAT_FRAME:AddMessage("|cffff8800OGRH Debug:|r Searching for BigWigs module: " .. tostring(bigwigsModuleName))
  
  if not OGRH_SV or not OGRH_SV.encounterMgmt or not OGRH_SV.encounterMgmt.raids then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OGRH Debug:|r No raid data found")
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
          
          DEFAULT_CHAT_FRAME:AddMessage("|cffff8800OGRH Debug:|r Checking encounter: " .. encounter.name)
          
          -- Get the array of configured BigWigs encounters for this OGRH encounter
          local encounterIds = encounter.advancedSettings.bigwigs.encounterIds
          
          -- Check if BigWigs module name is in the configured list
          if encounterIds and table.getn(encounterIds) > 0 then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff8800OGRH Debug:|r   Has " .. table.getn(encounterIds) .. " configured BigWigs encounters")
            for k = 1, table.getn(encounterIds) do
              DEFAULT_CHAT_FRAME:AddMessage("|cffff8800OGRH Debug:|r   Checking: " .. tostring(encounterIds[k]))
              if encounterIds[k] == bigwigsModuleName then
                -- Found a match!
                DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OGRH Debug:|r MATCH FOUND!")
                return raid.name, encounter.name
              end
            end
          else
            DEFAULT_CHAT_FRAME:AddMessage("|cffff8800OGRH Debug:|r   No encounterIds configured")
          end
        end
      end
    end
  end
  
  DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OGRH Debug:|r No match found for: " .. tostring(bigwigsModuleName))
  return nil, nil
end

-- Function to auto-select raid/encounter when BigWigs detects it
function OGRH.BigWigs.OnEncounterDetected(moduleName)
  if not moduleName or moduleName == "" then return end
  
  -- Avoid duplicate processing
  if lastDetectedEncounter == moduleName then
    return
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
    
    -- Notify user
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OG-RaidHelper:|r Auto-selected: " .. encounterName .. " (" .. raidName .. ")", 0, 1, 0)
  end
end

-- Hook into BigWigs module enable
local function HookBigWigs()
  if not BigWigs then
    -- BigWigs not loaded yet, try again later
    OGRH.ScheduleTimer(HookBigWigs, 1)
    return
  end
  
  -- Hook each module's OnEnable function
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
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OGRH Debug:|r BigWigs enabled: " .. self.translatedName)
            OGRH.BigWigs.OnEncounterDetected(self.translatedName)
          end
        end
        count = count + 1
      end
    end
    
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OG-RaidHelper:|r BigWigs integration active (hooked " .. count .. " modules)")
  else
    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OG-RaidHelper:|r BigWigs.modules not found")
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
