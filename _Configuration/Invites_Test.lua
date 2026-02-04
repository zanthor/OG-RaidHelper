-- OGRH_Invites_Test.lua
-- Test script for Phase 1 implementation

-- Test JSON sample (real Raid-Helper data from raidgroups.json)
local testJSON = [[{
  "id": 96,
  "name": "Naxxramas",
  "players": [
    {
      "name": "Anamar",
      "class": "Paladin",
      "role": "Melee",
      "status": "signed",
      "group": 1,
      "bench": false,
      "absent": false
    },
    {
      "name": "Broomie",
      "class": "Druid",
      "role": "Healer",
      "status": "signed",
      "group": 2,
      "bench": false,
      "absent": false
    },
    {
      "name": "Davolution",
      "class": "Mage",
      "role": "Ranged",
      "status": "signed",
      "group": 3,
      "bench": false,
      "absent": false
    },
    {
      "name": "Melchiah",
      "class": "Paladin",
      "role": "Melee",
      "status": "signed",
      "bench": true,
      "absent": false
    },
    {
      "name": "Theldin",
      "class": "Warrior",
      "role": "Tank",
      "status": "signed",
      "bench": false,
      "absent": true
    }
  ]
}]]

-- Test function to be called from in-game
function OGRH.Invites.TestPhase1()
  DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00=== Phase 1 Test: Data Infrastructure ===|r")
  
  -- Test 1: JSON library loaded
  DEFAULT_CHAT_FRAME:AddMessage("Test 1: JSON library loaded = " .. tostring(json ~= nil))
  
  -- Test 2: Constants defined
  DEFAULT_CHAT_FRAME:AddMessage("Test 2: SOURCE_TYPE.ROLLFOR = " .. tostring(OGRH.Invites.SOURCE_TYPE.ROLLFOR))
  DEFAULT_CHAT_FRAME:AddMessage("Test 2: SOURCE_TYPE.RAIDHELPER = " .. tostring(OGRH.Invites.SOURCE_TYPE.RAIDHELPER))
  
  -- Test 3: Parse JSON
  local data, error = OGRH.Invites.ParseRaidHelperJSON(testJSON)
  if data then
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00Test 3: JSON parsing SUCCESS|r")
    DEFAULT_CHAT_FRAME:AddMessage("  Raid ID: " .. tostring(data.id))
    DEFAULT_CHAT_FRAME:AddMessage("  Raid Name: " .. tostring(data.name))
    DEFAULT_CHAT_FRAME:AddMessage("  Players: " .. tostring(table.getn(data.players)))
    
    -- Store in SavedVariables
    OGRH_SV.invites.raidhelperData = data
    OGRH_SV.invites.currentSource = OGRH.Invites.SOURCE_TYPE.RAIDHELPER
    
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00Data stored in SavedVariables|r")
  else
    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000Test 3: JSON parsing FAILED: " .. tostring(error) .. "|r")
  end
  
  -- Test 4: Get unified roster
  local players = OGRH.Invites.GetRosterPlayers()
  DEFAULT_CHAT_FRAME:AddMessage("Test 4: GetRosterPlayers returned " .. tostring(table.getn(players)) .. " players")
  
  for i = 1, table.getn(players) do
    local p = players[i]
    local flags = ""
    if p.bench then flags = flags .. " [BENCH]" end
    if p.absent then flags = flags .. " [ABSENT]" end
    
    DEFAULT_CHAT_FRAME:AddMessage("  " .. p.name .. " - " .. (p.class or "?") .. " - " .. (p.role or "?") .. flags)
  end
  
  -- Test 5: Role mapping
  DEFAULT_CHAT_FRAME:AddMessage("Test 5: Role mapping:")
  DEFAULT_CHAT_FRAME:AddMessage("  Tank -> " .. tostring(OGRH.Invites.MapRoleToOGRH("Tank", OGRH.Invites.SOURCE_TYPE.RAIDHELPER)))
  DEFAULT_CHAT_FRAME:AddMessage("  Healer -> " .. tostring(OGRH.Invites.MapRoleToOGRH("Healer", OGRH.Invites.SOURCE_TYPE.RAIDHELPER)))
  DEFAULT_CHAT_FRAME:AddMessage("  WarriorProtection -> " .. tostring(OGRH.Invites.MapRoleToOGRH("WarriorProtection", OGRH.Invites.SOURCE_TYPE.ROLLFOR)))
  
  DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00=== Phase 1 Test Complete ===|r")
  DEFAULT_CHAT_FRAME:AddMessage("Use '/run OGRH.Invites.ShowWindow()' to test UI integration")
end

-- Slash command for testing
SLASH_OGRHINVTEST1 = "/invtest"
SlashCmdList["OGRHINVTEST"] = function(msg)
  if msg == "p2" or msg == "phase2" then
    OGRH.Invites.TestPhase2()
  else
    OGRH.Invites.TestPhase1()
  end
end

-- Phase 2 Test: UI Foundation
function OGRH.Invites.TestPhase2()
  DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00=== Phase 2 Test: UI Foundation ===|r")
  
  -- Test 1: Verify JSON dialog function exists
  DEFAULT_CHAT_FRAME:AddMessage("Test 1: ShowJSONImportDialog exists = " .. tostring(OGRH.Invites.ShowJSONImportDialog ~= nil))
  
  -- Test 2: Verify section header function exists
  DEFAULT_CHAT_FRAME:AddMessage("Test 2: CreateSectionHeader exists = " .. tostring(OGRH.Invites.CreateSectionHeader ~= nil))
  
  -- Test 3: Load test JSON with bench/absent flags
  local data, error = OGRH.Invites.ParseRaidHelperJSON(testJSON)
  if data then
    OGRH_SV.invites.raidhelperData = data
    OGRH_SV.invites.currentSource = OGRH.Invites.SOURCE_TYPE.RAIDHELPER
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00Test 3: Test data loaded with bench/absent flags|r")
  else
    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000Test 3: Failed to load test data|r")
    return
  end
  
  -- Test 4: Verify section separation
  local players = OGRH.Invites.GetRosterPlayers()
  local activeCount, benchCount, absentCount = 0, 0, 0
  
  for i = 1, table.getn(players) do
    if players[i].absent then
      absentCount = absentCount + 1
    elseif players[i].bench then
      benchCount = benchCount + 1
    else
      activeCount = activeCount + 1
    end
  end
  
  DEFAULT_CHAT_FRAME:AddMessage("Test 4: Section counts:")
  DEFAULT_CHAT_FRAME:AddMessage("  Active: " .. activeCount .. " (expected 3)")
  DEFAULT_CHAT_FRAME:AddMessage("  Benched: " .. benchCount .. " (expected 1)")
  DEFAULT_CHAT_FRAME:AddMessage("  Absent: " .. absentCount .. " (expected 1)")
  
  -- Test 5: Open main window to verify UI rendering
  DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00Test 5: Opening Invites window to verify sections...|r")
  OGRH.Invites.ShowWindow()
  
  DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00=== Phase 2 Test Complete ===|r")
  DEFAULT_CHAT_FRAME:AddMessage("Click 'Import Roster' button to test menu dropdown")
  DEFAULT_CHAT_FRAME:AddMessage("Select 'Raid-Helper JSON' to test JSON import dialog")
end

-- Test Phase 3: Invite Mode Core
function TestPhase3()
  DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00=== Starting Phase 3 Test: Invite Mode ===|r")
  
  -- Setup: Import test roster first
  OGRH_SV.invites.currentSource = "raidhelper"
  OGRH_SV.invites.raidhelperData = testRaidHelperData
  
  -- Test 1: Verify Invite Mode controls exist
  DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00Test 1: Opening window to check Invite Mode controls...|r")
  OGRH.Invites.ShowWindow()
  
  local frame = OGRH_InvitesFrame
  if frame.inviteModeBtn then
    DEFAULT_CHAT_FRAME:AddMessage("  ✓ Invite Mode button exists: " .. frame.inviteModeBtn:GetText())
  else
    DEFAULT_CHAT_FRAME:AddMessage("  ✗ Invite Mode button NOT FOUND")
  end
  
  if frame.intervalInput then
    DEFAULT_CHAT_FRAME:AddMessage("  ✓ Interval input exists, value: " .. frame.intervalInput:GetText())
  else
    DEFAULT_CHAT_FRAME:AddMessage("  ✗ Interval input NOT FOUND")
  end
  
  -- Test 2: Verify SavedVariables structure
  DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00Test 2: Checking SavedVariables structure...|r")
  local im = OGRH_SV.invites.inviteMode
  DEFAULT_CHAT_FRAME:AddMessage("  enabled: " .. tostring(im.enabled))
  DEFAULT_CHAT_FRAME:AddMessage("  interval: " .. tostring(im.interval))
  DEFAULT_CHAT_FRAME:AddMessage("  lastInviteTime: " .. tostring(im.lastInviteTime))
  DEFAULT_CHAT_FRAME:AddMessage("  totalPlayers: " .. tostring(im.totalPlayers))
  DEFAULT_CHAT_FRAME:AddMessage("  invitedCount: " .. tostring(im.invitedCount))
  
  -- Test 3: Test toggle (start Invite Mode)
  DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00Test 3: Starting Invite Mode...|r")
  OGRH.Invites.ToggleInviteMode()
  
  OGRH.ScheduleTimer(function()
    DEFAULT_CHAT_FRAME:AddMessage("  enabled: " .. tostring(OGRH_SV.invites.inviteMode.enabled))
    DEFAULT_CHAT_FRAME:AddMessage("  totalPlayers: " .. tostring(OGRH_SV.invites.inviteMode.totalPlayers))
    
    if OGRH_InviteModePanel and OGRH_InviteModePanel:IsVisible() then
      DEFAULT_CHAT_FRAME:AddMessage("  ✓ Invite Mode panel is visible")
    else
      DEFAULT_CHAT_FRAME:AddMessage("  ✗ Invite Mode panel NOT visible")
    end
    
    -- Test 4: Stop Invite Mode after 3 seconds
    OGRH.ScheduleTimer(function()
      DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00Test 4: Stopping Invite Mode...|r")
      OGRH.Invites.ToggleInviteMode()
      
      OGRH.ScheduleTimer(function()
        if OGRH_InviteModePanel and not OGRH_InviteModePanel:IsVisible() then
          DEFAULT_CHAT_FRAME:AddMessage("  ✓ Invite Mode panel hidden after stop")
        else
          DEFAULT_CHAT_FRAME:AddMessage("  ✗ Invite Mode panel still visible")
        end
        
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00=== Phase 3 Test Complete ===|r")
        DEFAULT_CHAT_FRAME:AddMessage("Manual test: Click 'Start Invite Mode' button to test live")
      end, 0.5)
    end, 3)
  end, 0.5)
end

-- Slash command handler
SLASH_INVTEST1 = "/invtest"
SlashCmdList["INVTEST"] = function(msg)
  msg = string.lower(msg or "")
  
  if msg == "phase2" then
    TestPhase2()
  elseif msg == "phase3" then
    TestPhase3()
  else
    -- Default to Phase 2
    TestPhase2()
  end
end

DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OGRH Invites Test loaded. Type /invtest phase2 or /invtest phase3 to run tests.|r")
