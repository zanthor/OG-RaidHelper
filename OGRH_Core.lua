-- OGRH_Core.lua  (Turtle-WoW 1.12)  v1.14.0
OGRH = OGRH or {}
OGRH.ADDON = "OG-RaidHelper"
OGRH.CMD   = "ogrh"
OGRH.ADDON_PREFIX = "OGRH"

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
  if not OGRH_SV then OGRH_SV = { roles = {}, order = {}, pollTime = 5, tankCategory = {}, healerBoss = {}, ui = {}, tankIcon = {}, healerIcon = {}, rolesUI = {}, playerAssignments = {}, allowRemoteReadyCheck = true, tradeItems = {} } end
  if not OGRH_SV.roles then OGRH_SV.roles = {} end
  if not OGRH_SV.order then OGRH_SV.order = {} end
  if not OGRH_SV.order.TANKS then OGRH_SV.order.TANKS = {} end
  if not OGRH_SV.order.HEALERS then OGRH_SV.order.HEALERS = {} end
  if not OGRH_SV.order.MELEE then OGRH_SV.order.MELEE = {} end
  if not OGRH_SV.order.RANGED then OGRH_SV.order.RANGED = {} end
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
local _svf = CreateFrame("Frame"); _svf:RegisterEvent("VARIABLES_LOADED")
_svf:SetScript("OnEvent", function() OGRH.EnsureSV() end)
OGRH.EnsureSV()

function OGRH.Msg(s) if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cff66ccff[OGRH]|r "..tostring(s)) end end
function OGRH.Trim(s) return string.gsub(s or "", "^%s*(.-)%s*$", "%1") end
function OGRH.Mod1(n,t) return math.mod(n-1, t)+1 end
function OGRH.CanRW() if IsRaidLeader and IsRaidLeader()==1 then return true end if IsRaidOfficer and IsRaidOfficer()==1 then return true end return false end
function OGRH.SayRW(text) if OGRH.CanRW() then SendChatMessage(text, "RAID_WARNING") else SendChatMessage(text, "RAID") end end

-- Centralized window management - close all dialog windows except the specified one
function OGRH.CloseAllWindows(exceptFrame)
  local windows = {
    "OGRH_EncounterFrame",
    "OGRH_RolesFrame",
    "OGRH_ShareFrame",
    "OGRH_EncounterSetupFrame",
    "OGRH_InvitesFrame",
    "OGRH_SRValidationFrame",
    "OGRH_AddonAuditFrame",
    "OGRH_TradeSettingsFrame",
    "OGRH_TradeMenu",
    "OGRH_EncountersMenu",
    "OGRH_ConsumesFrame"
  }
  
  for _, frameName in ipairs(windows) do
    if frameName ~= exceptFrame then
      local frame = getglobal(frameName)
      if frame and frame:IsVisible() then
        frame:Hide()
      end
    end
  end
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
    -- Set flag to capture AFK messages
    OGRH.readyCheckInProgress = true
    DoReadyCheck()
  -- Check if player is raid assistant
  elseif IsRaidOfficer and IsRaidOfficer() == 1 then
    -- Send addon message to raid asking leader to start ready check
    SendAddonMessage(OGRH.ADDON_PREFIX, "READYCHECK_REQUEST", "RAID")
    OGRH.Msg("Ready check request sent to raid leader.")
  else
    OGRH.Msg("You must be raid leader or assistant to start a ready check.")
  end
end

-- Announcement storage and re-announce functionality
OGRH.storedAnnouncement = nil  -- Stores {lines = {...}, timestamp = time()}

-- Store announcement lines and broadcast to raid
function OGRH.StoreAndBroadcastAnnouncement(lines)
  if not lines or table.getn(lines) == 0 then return end
  
  -- Store locally (with single pipes for color codes)
  OGRH.storedAnnouncement = {
    lines = lines,
    timestamp = time()
  }
  
  -- Broadcast to other addon users in raid
  -- Use a different delimiter (semicolon) to avoid pipe confusion
  local message = "ANNOUNCE;" .. table.concat(lines, ";")
  SendAddonMessage(OGRH.ADDON_PREFIX, message, "RAID")
end

-- Helper function: Send announcement lines and store for re-announce
-- This is the recommended way to send announcements from any module
function OGRH.SendAnnouncement(lines, testMode)
  if not lines or table.getn(lines) == 0 then return end
  
  -- Store and broadcast for re-announce functionality
  OGRH.StoreAndBroadcastAnnouncement(lines)
  
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

-- Send addon message with prefix
function OGRH.SendAddonMessage(msgType, data)
  local message = msgType .. ";" .. data
  SendAddonMessage(OGRH.ADDON_PREFIX, message, "RAID")
end

-- Broadcast encounter selection to raid (does not sync settings, just UI state)
function OGRH.BroadcastEncounterSelection(raidName, encounterName)
  if GetNumRaidMembers() == 0 then
    return -- Not in a raid, don't broadcast
  end
  
  local message = "ENCOUNTER_SELECT;" .. raidName .. ";" .. encounterName
  SendAddonMessage(OGRH.ADDON_PREFIX, message, "RAID")
end

-- Calculate checksum of encounter assignments
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

-- Broadcast assignment update (minimal data)
function OGRH.BroadcastAssignmentUpdate(raid, encounter, roleIndex, slotIndex, playerName)
  if GetNumRaidMembers() == 0 then
    return
  end
  
  -- Only send if we're raid leader or assistant
  local canSend = false
  for i = 1, GetNumRaidMembers() do
    local name, rank = GetRaidRosterInfo(i)
    if name == UnitName("player") and (rank == 2 or rank == 1) then
      canSend = true
      break
    end
  end
  
  if not canSend then
    return
  end
  
  local checksum = OGRH.CalculateAssignmentChecksum(raid, encounter)
  local data = raid .. ";" .. encounter .. ";" .. roleIndex .. ";" .. slotIndex .. ";" .. (playerName or "") .. ";" .. checksum
  SendAddonMessage(OGRH.ADDON_PREFIX, "ASSIGNMENT_UPDATE;" .. data, "RAID")
end

-- Request full sync from sender
function OGRH.RequestFullSync(targetPlayer, raid, encounter)
  if GetNumRaidMembers() == 0 then
    return
  end
  
  local data = targetPlayer .. ";" .. raid .. ";" .. encounter
  SendAddonMessage(OGRH.ADDON_PREFIX, "REQUEST_FULL_SYNC;" .. data, "RAID")
end

-- Simple table serialization for addon messages
function OGRH.Serialize(tbl)
  if type(tbl) ~= "table" then return tostring(tbl) end
  
  -- Use AceSerializer if available, otherwise basic serialization
  if AceLibrary and AceLibrary:HasInstance("AceSerializer-1.0") then
    local serializer = AceLibrary("AceSerializer-1.0")
    return serializer:Serialize(tbl)
  end
  
  -- Basic serialization - convert to string
  local result = "{"
  for k, v in pairs(tbl) do
    if type(k) == "string" then
      result = result .. k .. "="
    end
    
    if type(v) == "table" then
      result = result .. OGRH.Serialize(v) .. ","
    elseif type(v) == "string" then
      result = result .. string.format("%q", v) .. ","
    elseif type(v) == "number" or type(v) == "boolean" then
      result = result .. tostring(v) .. ","
    end
  end
  result = result .. "}"
  return result
end

-- Simple table deserialization
function OGRH.Deserialize(str)
  if not str or str == "" then return nil end
  
  -- Use AceSerializer if available
  if AceLibrary and AceLibrary:HasInstance("AceSerializer-1.0") then
    local serializer = AceLibrary("AceSerializer-1.0")
    local success, data = serializer:Deserialize(str)
    if success then return data end
  end
  
  -- Basic deserialization - use loadstring
  local func = loadstring("return " .. str)
  if func then
    return func()
  end
  
  return nil
end

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

-- Handle incoming addon messages and game events
local addonFrame = CreateFrame("Frame")
addonFrame:RegisterEvent("CHAT_MSG_ADDON")
addonFrame:RegisterEvent("CHAT_MSG_SYSTEM")
addonFrame:SetScript("OnEvent", function()
  if event == "CHAT_MSG_ADDON" then
    local prefix, message, distribution, sender = arg1, arg2, arg3, arg4
    
    if prefix == OGRH.ADDON_PREFIX then
      -- Handle ready check request from assistant
      if message == "READYCHECK_REQUEST" then
        -- Only process if we are the raid leader
        if IsRaidLeader and IsRaidLeader() == 1 then
          -- Check if remote ready checks are allowed
          OGRH.EnsureSV()
          if OGRH_SV.allowRemoteReadyCheck then
            -- Set flag to capture AFK messages
            OGRH.readyCheckInProgress = true
            DoReadyCheck()
          end
        end
      -- Handle announcement broadcast
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
      -- Handle encounter sync
      elseif string.sub(message, 1, 15) == "ENCOUNTER_SYNC;" then
        -- Block sync from self
        local playerName = UnitName("player")
        if sender == playerName then
          return
        end
        
        -- Check if sync is locked (send only mode)
        OGRH.EnsureSV()
        if OGRH_SV.syncLocked then
          DEFAULT_CHAT_FRAME:AddMessage("|cffff8800OGRH:|r Ignored encounter sync from " .. sender .. " (sync is locked)")
          return
        end
        
        -- Check if sender is raid leader or assistant
        local isAuthorized = false
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
          if not OGRH_SV.encounterMgmt then OGRH_SV.encounterMgmt = {raids = {}, encounters = {}} end
          if not OGRH_SV.encounterMgmt.raids then OGRH_SV.encounterMgmt.raids = {} end
          if not OGRH_SV.encounterMgmt.encounters then OGRH_SV.encounterMgmt.encounters = {} end
          if not OGRH_SV.encounterMgmt.roles then OGRH_SV.encounterMgmt.roles = {} end
          if not OGRH_SV.encounterAssignments then OGRH_SV.encounterAssignments = {} end
          if not OGRH_SV.encounterRaidMarks then OGRH_SV.encounterRaidMarks = {} end
          if not OGRH_SV.encounterAssignmentNumbers then OGRH_SV.encounterAssignmentNumbers = {} end
          if not OGRH_SV.encounterAnnouncements then OGRH_SV.encounterAnnouncements = {} end
          
          -- Add raid to raids list if it doesn't exist
          local raidExists = false
          for i = 1, table.getn(OGRH_SV.encounterMgmt.raids) do
            if OGRH_SV.encounterMgmt.raids[i] == syncData.raid then
              raidExists = true
              break
            end
          end
          if not raidExists then
            table.insert(OGRH_SV.encounterMgmt.raids, syncData.raid)
          end
          
          -- Initialize encounter list for this raid if needed
          if not OGRH_SV.encounterMgmt.encounters[syncData.raid] then
            OGRH_SV.encounterMgmt.encounters[syncData.raid] = {}
          end
          
          -- Add encounter to raid's encounter list if it doesn't exist
          local encounterExists = false
          for i = 1, table.getn(OGRH_SV.encounterMgmt.encounters[syncData.raid]) do
            if OGRH_SV.encounterMgmt.encounters[syncData.raid][i] == syncData.encounter then
              encounterExists = true
              break
            end
          end
          if not encounterExists then
            table.insert(OGRH_SV.encounterMgmt.encounters[syncData.raid], syncData.encounter)
          end
          
          -- Replace/create raid structure
          if not OGRH_SV.encounterMgmt.roles[syncData.raid] then
            OGRH_SV.encounterMgmt.roles[syncData.raid] = {}
          end
          if not OGRH_SV.encounterAssignments[syncData.raid] then
            OGRH_SV.encounterAssignments[syncData.raid] = {}
          end
          if not OGRH_SV.encounterRaidMarks[syncData.raid] then
            OGRH_SV.encounterRaidMarks[syncData.raid] = {}
          end
          if not OGRH_SV.encounterAssignmentNumbers[syncData.raid] then
            OGRH_SV.encounterAssignmentNumbers[syncData.raid] = {}
          end
          if not OGRH_SV.encounterAnnouncements[syncData.raid] then
            OGRH_SV.encounterAnnouncements[syncData.raid] = {}
          end
          
          -- Replace encounter data
          if syncData.roles then
            OGRH_SV.encounterMgmt.roles[syncData.raid][syncData.encounter] = syncData.roles
          end
          if syncData.assignments then
            OGRH_SV.encounterAssignments[syncData.raid][syncData.encounter] = syncData.assignments
          end
          if syncData.raidMarks then
            OGRH_SV.encounterRaidMarks[syncData.raid][syncData.encounter] = syncData.raidMarks
          end
          if syncData.assignmentNumbers then
            OGRH_SV.encounterAssignmentNumbers[syncData.raid][syncData.encounter] = syncData.assignmentNumbers
          end
          if syncData.announcements then
            OGRH_SV.encounterAnnouncements[syncData.raid][syncData.encounter] = syncData.announcements
          end
          
          DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OGRH:|r Received encounter sync from " .. sender .. ": " .. syncData.raid .. " - " .. syncData.encounter)
          
          -- Refresh raid/encounter lists in open windows
          if OGRH_EncounterFrame and OGRH_EncounterFrame.RefreshRaidsList then
            OGRH_EncounterFrame.RefreshRaidsList()
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
          
          -- Check if sender is raid leader or assistant
          local isAuthorized = false
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
            -- Silently ignore - not from leader/assistant
            return
          end
          
          -- Verify raid and encounter exist locally
          if OGRH_SV.encounterMgmt and OGRH_SV.encounterMgmt.encounters and
             OGRH_SV.encounterMgmt.encounters[raidName] then
            
            -- Check if encounter exists in this raid
            local encounters = OGRH_SV.encounterMgmt.encounters[raidName]
            local encounterExists = false
            for _, enc in ipairs(encounters) do
              if enc == encounterName then
                encounterExists = true
                break
              end
            end
            
            if encounterExists then
              -- Create frame if it doesn't exist (but don't show it)
              if not OGRH_EncounterFrame then
                OGRH.ShowEncounterWindow()
                OGRH_EncounterFrame:Hide()
              end
              
              -- Update selection
              OGRH_EncounterFrame.selectedRaid = raidName
              OGRH_EncounterFrame.selectedEncounter = encounterName
              
              -- Refresh UI if window is open
              if OGRH_EncounterFrame:IsVisible() then
                if OGRH_EncounterFrame.RefreshRaidsList then
                  OGRH_EncounterFrame.RefreshRaidsList()
                end
                if OGRH_EncounterFrame.RefreshEncountersList then
                  OGRH_EncounterFrame.RefreshEncountersList()
                end
                if OGRH_EncounterFrame.RefreshRoleContainers then
                  OGRH_EncounterFrame.RefreshRoleContainers()
                end
              end
              
              -- Always update the main UI encounter button
              if OGRH.UpdateEncounterNavButton then
                OGRH.UpdateEncounterNavButton()
              end
            end
          end
        end
      -- Handle assignment update
      elseif string.sub(message, 1, 18) == "ASSIGNMENT_UPDATE;" then
        -- Block from self
        local playerName = UnitName("player")
        if sender == playerName then
          return
        end
        
        -- Check if sync is locked (receive only if unlocked)
        OGRH.EnsureSV()
        if OGRH_SV.syncLocked then
          return
        end
        
        -- Check if sender is raid leader or assistant
        local isAuthorized = false
        local numRaidMembers = GetNumRaidMembers()
        
        if numRaidMembers > 0 then
          for i = 1, numRaidMembers do
            local name, rank = GetRaidRosterInfo(i)
            if name == sender and (rank == 2 or rank == 1) then
              isAuthorized = true
              break
            end
          end
        end
        
        if not isAuthorized then
          return
        end
        
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
          local senderChecksum = parts[6]
          
          -- Calculate our checksum before update
          local ourChecksum = OGRH.CalculateAssignmentChecksum(raid, encounter)
          
          -- Apply update
          if not OGRH_SV.encounterAssignments then OGRH_SV.encounterAssignments = {} end
          if not OGRH_SV.encounterAssignments[raid] then OGRH_SV.encounterAssignments[raid] = {} end
          if not OGRH_SV.encounterAssignments[raid][encounter] then OGRH_SV.encounterAssignments[raid][encounter] = {} end
          if not OGRH_SV.encounterAssignments[raid][encounter][roleIndex] then OGRH_SV.encounterAssignments[raid][encounter][roleIndex] = {} end
          
          OGRH_SV.encounterAssignments[raid][encounter][roleIndex][slotIndex] = newPlayerName
          
          -- Calculate new checksum after update
          local newChecksum = OGRH.CalculateAssignmentChecksum(raid, encounter)
          
          -- If checksums don't match, request full sync
          if newChecksum ~= senderChecksum then
            OGRH.RequestFullSync(sender, raid, encounter)
          end
          
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
      elseif string.sub(message, 1, 18) == "REQUEST_FULL_SYNC;" then
        -- Block from self
        local playerName = UnitName("player")
        if sender == playerName then
          return
        end
        
        -- Parse: targetPlayer;raid;encounter
        local content = string.sub(message, 19)
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
          local targetPlayer = parts[1]
          local raid = parts[2]
          local encounter = parts[3]
          
          -- Only respond if we're the target
          if targetPlayer ~= playerName then
            return
          end
          
          -- Send full sync data back via whisper
          local syncData = {
            raid = raid,
            encounter = encounter,
            roles = {},
            assignments = {},
            marks = {},
            numbers = {},
            announcements = ""
          }
          
          OGRH.EnsureSV()
          
          if OGRH_SV.encounterMgmt and OGRH_SV.encounterMgmt.roles and 
             OGRH_SV.encounterMgmt.roles[raid] and 
             OGRH_SV.encounterMgmt.roles[raid][encounter] then
            syncData.roles = OGRH_SV.encounterMgmt.roles[raid][encounter]
          end
          
          if OGRH_SV.encounterAssignments and OGRH_SV.encounterAssignments[raid] and 
             OGRH_SV.encounterAssignments[raid][encounter] then
            syncData.assignments = OGRH_SV.encounterAssignments[raid][encounter]
          end
          
          if OGRH_SV.encounterRaidMarks and OGRH_SV.encounterRaidMarks[raid] and 
             OGRH_SV.encounterRaidMarks[raid][encounter] then
            syncData.marks = OGRH_SV.encounterRaidMarks[raid][encounter]
          end
          
          if OGRH_SV.encounterAssignmentNumbers and OGRH_SV.encounterAssignmentNumbers[raid] and 
             OGRH_SV.encounterAssignmentNumbers[raid][encounter] then
            syncData.numbers = OGRH_SV.encounterAssignmentNumbers[raid][encounter]
          end
          
          if OGRH_SV.encounterAnnouncements and OGRH_SV.encounterAnnouncements[raid] and 
             OGRH_SV.encounterAnnouncements[raid][encounter] then
            syncData.announcements = OGRH_SV.encounterAnnouncements[raid][encounter]
          end
          
          local serialized = OGRH.Serialize(syncData)
          SendAddonMessage(OGRH.ADDON_PREFIX, "FULL_SYNC_RESPONSE;" .. sender .. ";" .. serialized, "RAID")
        end
      -- Handle full sync response
      elseif string.sub(message, 1, 19) == "FULL_SYNC_RESPONSE;" then
        -- Parse: requesterName;serializedData
        local content = string.sub(message, 20)
        local semicolonPos = string.find(content, ";", 1, true)
        
        if semicolonPos then
          local requesterName = string.sub(content, 1, semicolonPos - 1)
          local playerName = UnitName("player")
          
          -- Only process if we're the requester
          if requesterName ~= playerName then
            return
          end
          
          local serialized = string.sub(content, semicolonPos + 1)
          local syncData = OGRH.Deserialize(serialized)
          
          if syncData and syncData.raid and syncData.encounter then
            -- Apply the full sync data (same as ENCOUNTER_SYNC handler)
            OGRH.EnsureSV()
            if not OGRH_SV.encounterMgmt then OGRH_SV.encounterMgmt = {raids = {}, encounters = {}} end
            if not OGRH_SV.encounterMgmt.roles then OGRH_SV.encounterMgmt.roles = {} end
            if not OGRH_SV.encounterAssignments then OGRH_SV.encounterAssignments = {} end
            if not OGRH_SV.encounterRaidMarks then OGRH_SV.encounterRaidMarks = {} end
            if not OGRH_SV.encounterAssignmentNumbers then OGRH_SV.encounterAssignmentNumbers = {} end
            if not OGRH_SV.encounterAnnouncements then OGRH_SV.encounterAnnouncements = {} end
            
            if not OGRH_SV.encounterMgmt.roles[syncData.raid] then
              OGRH_SV.encounterMgmt.roles[syncData.raid] = {}
            end
            if not OGRH_SV.encounterAssignments[syncData.raid] then
              OGRH_SV.encounterAssignments[syncData.raid] = {}
            end
            if not OGRH_SV.encounterRaidMarks[syncData.raid] then
              OGRH_SV.encounterRaidMarks[syncData.raid] = {}
            end
            if not OGRH_SV.encounterAssignmentNumbers[syncData.raid] then
              OGRH_SV.encounterAssignmentNumbers[syncData.raid] = {}
            end
            if not OGRH_SV.encounterAnnouncements[syncData.raid] then
              OGRH_SV.encounterAnnouncements[syncData.raid] = {}
            end
            
            if syncData.roles then
              OGRH_SV.encounterMgmt.roles[syncData.raid][syncData.encounter] = syncData.roles
            end
            if syncData.assignments then
              OGRH_SV.encounterAssignments[syncData.raid][syncData.encounter] = syncData.assignments
            end
            if syncData.raidMarks then
              OGRH_SV.encounterRaidMarks[syncData.raid][syncData.encounter] = syncData.raidMarks
            end
            if syncData.assignmentNumbers then
              OGRH_SV.encounterAssignmentNumbers[syncData.raid][syncData.encounter] = syncData.assignmentNumbers
            end
            if syncData.announcements then
              OGRH_SV.encounterAnnouncements[syncData.raid][syncData.encounter] = syncData.announcements
            end
            
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OGRH:|r Received full sync from " .. sender .. ": " .. syncData.raid .. " - " .. syncData.encounter)
            
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
        end
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
      end
    end
  elseif event == "CHAT_MSG_SYSTEM" then
    -- Capture ready check AFK messages
    if OGRH.readyCheckInProgress and IsRaidLeader() == 1 then
      local msg = arg1
      
      -- Check for "No players are AFK" or "The following players are AFK:"
      if msg and string.find(msg, "No players are AFK") then
        -- Echo "No players are AFK" with header color
        OGRH.SayRW(OGRH.Header("No players are AFK"))
        OGRH.readyCheckInProgress = false
      elseif msg and string.find(msg, "The following players are AFK:") then
        -- Parse the player names from the message
        local playersPart = string.gsub(msg, "The following players are AFK: ", "")
        local players = {}
        
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
            table.insert(players, playerName)
          end
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
        
        -- Build colored message
        local coloredPlayers = {}
        for i = 1, table.getn(players) do
          local playerName = players[i]
          local info = raidInfo[playerName]
          local coloredName
          
          if info and info.class then
            -- Use the class from raid roster to color the name
            local classUpper = string.upper(info.class)
            local classColorHex = OGRH.ClassColorHex(classUpper)
            coloredName = classColorHex .. playerName .. "|r"
          else
            -- Fallback to white if class not found
            coloredName = playerName
          end
          
          -- Add asterisk if offline
          if info and not info.online then
            coloredName = coloredName .. OGRH.COLOR.ROLE .. "*" .. OGRH.COLOR.RESET
          end
          
          table.insert(coloredPlayers, coloredName)
        end
        
        -- Build the final message
        local coloredMsg = OGRH.Header("The following players are AFK:") .. " " .. table.concat(coloredPlayers, ", ")
        OGRH.SayRW(coloredMsg)
        OGRH.readyCheckInProgress = false
      end
    end
  end
end)

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

function OGRH.EnsureOrderContiguous(role, present)
  OGRH.EnsureSV()
  local o = OGRH_SV.order[role] or {}
  local k
  for k,_ in pairs(o) do if not present[k] then o[k] = nil end end
  local max = 0
  local _,v; for _,v in pairs(o) do if v>max then max=v end end
  local nm; for nm,_ in pairs(present) do if not o[nm] then max=max+1; o[nm]=max end end
  local arr = {}; for name,idx in pairs(o) do arr[idx]=name end
  local newIndex, j = {}, 1
  local i; for i=1,table.getn(arr) do if arr[i] then newIndex[arr[i]]=j; j=j+1 end end
  OGRH_SV.order[role]=newIndex
end

function OGRH.AddTo(role, name)
  OGRH.EnsureSV()
  if not name or name=="" or not OGRH.Roles.buckets[role] then return end
  if not OGRH.Roles.testing and not OGRH.Roles.raidNames[name] then OGRH.Msg("Cannot assign "..name.." (not in raid)."); return end
  local k,_; for k,_ in pairs(OGRH.Roles.buckets) do OGRH.Roles.buckets[k][name]=nil; if OGRH_SV.order[k] then OGRH_SV.order[k][name]=nil end end
  OGRH.Roles.buckets[role][name]=true
  OGRH_SV.roles[name]=role
  OGRH_SV.tankCategory[name]=nil; OGRH_SV.healerBoss[name]=nil
  local present = {}; local nm; for nm,_ in pairs(OGRH.Roles.buckets[role]) do if OGRH.Roles.testing or OGRH.Roles.raidNames[nm] then present[nm]=true end end
  OGRH.EnsureOrderContiguous(role, present)
  local o = OGRH_SV.order[role] or {}; local max = 0; local _,v; for _,v in pairs(o) do if v>max then max=v end end
  if not o[name] then o[name]=max+1 end; OGRH_SV.order[role]=o
end

OGRH.CLASS_RGB = OGRH.CLASS_RGB
OGRH.ICON_NAMES = {"Star","Circle","Diamond","Triangle","Moon","Square","Cross","Skull"}

Roles = OGRH.Roles
ensureSV = OGRH.EnsureSV
colorName = OGRH.ColorName
sayRW = OGRH.SayRW
msg = OGRH.Msg


-- Return an array of names in a role, sorted by saved order, filtering to current raid unless testing
function OGRH.SortedRoleNamesRaw(role)
  OGRH.EnsureSV()
  local out = {}
  local bucket = OGRH.Roles.buckets[role] or {}
  local name,_
  for name,_ in pairs(bucket) do
    if OGRH.Roles.testing or OGRH.Roles.raidNames[name] then
      table.insert(out, name)
    end
  end
  local ord = OGRH_SV.order[role] or {}
  table.sort(out, function(a,b)
    local ia = ord[a] or 9999
    local ib = ord[b] or 9999
    if ia ~= ib then return ia < ib else return a < b end
  end)
  return out
end


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

-- === Share Window for Import/Export ===
function OGRH.ShowShareWindow()
  -- Create window if it doesn't exist
  if not OGRH_ShareFrame then
    local frame = CreateFrame("Frame", "OGRH_ShareFrame", UIParent)
    frame:SetWidth(600)
    frame:SetHeight(400)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetFrameStrata("DIALOG")
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function() frame:StartMoving() end)
    frame:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
    
    -- Backdrop
    frame:SetBackdrop({
      bgFile = "Interface/Tooltips/UI-Tooltip-Background",
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
      edgeSize = 12,
      insets = {left = 4, right = 4, top = 4, bottom = 4}
    })
    frame:SetBackdropColor(0, 0, 0, 0.85)
    
    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -15)
    title:SetText("Share Raid Data")
    
    -- Instructions
    local instructions = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    instructions:SetPoint("TOPLEFT", 20, -45)
    instructions:SetText("Export: Click 'Export' to generate data. Copy from box below.")
    
    local instructions2 = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    instructions2:SetPoint("TOPLEFT", 20, -60)
    instructions2:SetText("Import: Paste data in box below and click 'Import'.")
    
    -- Scroll frame backdrop
    local scrollBackdrop = CreateFrame("Frame", nil, frame)
    scrollBackdrop:SetPoint("TOPLEFT", 17, -80)
    scrollBackdrop:SetPoint("BOTTOMRIGHT", -17, 50)
    scrollBackdrop:SetBackdrop({
      bgFile = "Interface/Tooltips/UI-Tooltip-Background",
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
      tile = true,
      tileSize = 16,
      edgeSize = 16,
      insets = {left = 3, right = 3, top = 3, bottom = 3}
    })
    scrollBackdrop:SetBackdropColor(0, 0, 0, 1)
    scrollBackdrop:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    
    -- Scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", "OGRH_ShareScrollFrame", scrollBackdrop, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 5, -6)
    scrollFrame:SetPoint("BOTTOMRIGHT", -28, 6)
    
    -- Scroll child
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollFrame:SetScrollChild(scrollChild)
    scrollChild:SetWidth(scrollFrame:GetWidth())
    scrollChild:SetHeight(400)
    
    -- Edit box
    local editBox = CreateFrame("EditBox", nil, scrollChild)
    editBox:SetPoint("TOPLEFT", 0, 0)
    editBox:SetWidth(scrollChild:GetWidth())
    editBox:SetHeight(400)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetTextInsets(5, 5, 3, 3)
    editBox:SetScript("OnEscapePressed", function() editBox:ClearFocus() end)
    frame.editBox = editBox
    
    -- Update scroll child size when scroll frame resizes
    scrollFrame:SetScript("OnSizeChanged", function()
      scrollChild:SetWidth(scrollFrame:GetWidth())
      editBox:SetWidth(scrollFrame:GetWidth())
    end)
    
    -- Update scroll range when text changes
    editBox:SetScript("OnTextChanged", function()
      scrollFrame:UpdateScrollChildRect()
    end)
    
    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    closeBtn:SetWidth(80)
    closeBtn:SetHeight(25)
    closeBtn:SetPoint("BOTTOMRIGHT", -20, 15)
    closeBtn:SetText("Close")
    OGRH.StyleButton(closeBtn)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)
    
    -- Clear button
    local clearBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    clearBtn:SetWidth(80)
    clearBtn:SetHeight(25)
    clearBtn:SetPoint("RIGHT", closeBtn, "LEFT", -10, 0)
    clearBtn:SetText("Clear")
    OGRH.StyleButton(clearBtn)
    clearBtn:SetScript("OnClick", function()
      editBox:SetText("")
      editBox:SetFocus()
    end)
    
    -- Export button
    local exportBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    exportBtn:SetWidth(100)
    exportBtn:SetHeight(25)
    exportBtn:SetPoint("BOTTOMLEFT", 20, 15)
    exportBtn:SetText("Export")
    OGRH.StyleButton(exportBtn)
    exportBtn:SetScript("OnClick", function()
      if OGRH.ExportShareData then
        local data = OGRH.ExportShareData()
        editBox:SetText(data)
        editBox:HighlightText()
        editBox:SetFocus()
      end
    end)
    
    -- Import button (moved next to Export)
    local importBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    importBtn:SetWidth(100)
    importBtn:SetHeight(25)
    importBtn:SetPoint("LEFT", exportBtn, "RIGHT", 10, 0)
    importBtn:SetText("Import")
    OGRH.StyleButton(importBtn)
    importBtn:SetScript("OnClick", function()
      local text = editBox:GetText()
      if text and text ~= "" then
        if OGRH.ImportShareData then
          OGRH.ImportShareData(text)
        end
      else
        OGRH.Msg("No data to import.")
      end
    end)
    
    -- Pull from Raid button (in Import's old location)
    local pullBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    pullBtn:SetWidth(120)
    pullBtn:SetHeight(25)
    pullBtn:SetPoint("RIGHT", clearBtn, "LEFT", -10, 0)
    pullBtn:SetText("Pull from Raid")
    OGRH.StyleButton(pullBtn)
    pullBtn:SetScript("OnClick", function()
      if OGRH.RequestRaidData then
        OGRH.RequestRaidData()
      end
    end)
    
    OGRH_ShareFrame = frame
  end
  
  OGRH_ShareFrame:Show()
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

-- Export data to string
function OGRH.ExportShareData()
  OGRH.EnsureSV()
  
  -- Collect all encounter management data
  local exportData = {
    version = "1.0",
    encounterMgmt = OGRH_SV.encounterMgmt or { raids = {}, encounters = {} },
    poolDefaults = OGRH_SV.poolDefaults or {},
    encounterPools = OGRH_SV.encounterPools or {},
    encounterAssignments = OGRH_SV.encounterAssignments or {},
    encounterRaidMarks = OGRH_SV.encounterRaidMarks or {},
    encounterAssignmentNumbers = OGRH_SV.encounterAssignmentNumbers or {},
    encounterAnnouncements = OGRH_SV.encounterAnnouncements or {},
    tradeItems = OGRH_SV.tradeItems or {},
    consumes = OGRH_SV.consumes or {}
  }
  
  -- Serialize to string (using a simple format)
  local serialized = OGRH.Serialize(exportData)
  return serialized
end

-- Import data from string
function OGRH.ImportShareData(dataString)
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
  
  -- Import all encounter management data
  if importData.encounterMgmt then
    OGRH_SV.encounterMgmt = importData.encounterMgmt
  end
  if importData.poolDefaults then
    OGRH_SV.poolDefaults = importData.poolDefaults
  end
  if importData.encounterPools then
    OGRH_SV.encounterPools = importData.encounterPools
  end
  if importData.encounterAssignments then
    OGRH_SV.encounterAssignments = importData.encounterAssignments
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
    OGRH_SV.consumes = importData.consumes
  end
  
  OGRH.Msg("|cff00ff00Success:|r Encounter data imported.")
  
  -- Debug: Check what was imported
  if OGRH_SV.encounterMgmt and OGRH_SV.encounterMgmt.raids then
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OGRH:|r Imported " .. table.getn(OGRH_SV.encounterMgmt.raids) .. " raids")
  else
    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OGRH:|r encounterMgmt.raids is nil after import!")
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
end

-- Simple serialization (converts table to string)
function OGRH.Serialize(tbl)
  local function serializeValue(v)
    local t = type(v)
    if t == "string" then
      return string.format("%q", v)
    elseif t == "number" or t == "boolean" then
      return tostring(v)
    elseif t == "table" then
      return OGRH.SerializeTable(v)
    else
      return "nil"
    end
  end
  
  local function serializeTable(tbl)
    local parts = {}
    table.insert(parts, "{")
    
    for k, v in pairs(tbl) do
      local keyStr
      if type(k) == "string" then
        keyStr = string.format("[%q]", k)
      else
        keyStr = "[" .. tostring(k) .. "]"
      end
      table.insert(parts, keyStr .. "=" .. serializeValue(v) .. ",")
    end
    
    table.insert(parts, "}")
    return table.concat(parts, "")
  end
  
  OGRH.SerializeTable = serializeTable
  return serializeTable(tbl)
end

-- Simple deserialization (converts string back to table)
function OGRH.Deserialize(str)
  if not str or str == "" then return nil end
  
  -- Use loadstring to evaluate the table string
  local func = loadstring("return " .. str)
  if not func then return nil end
  
  return func()
end

-- Trade Settings Window
function OGRH.ShowTradeSettings()
  OGRH.EnsureSV()
  OGRH.CloseAllWindows("OGRH_TradeSettingsFrame")
  
  if OGRH_TradeSettingsFrame then
    OGRH_TradeSettingsFrame:Show()
    OGRH.RefreshTradeSettings()
    return
  end
  
  local frame = CreateFrame("Frame", "OGRH_TradeSettingsFrame", UIParent)
  frame:SetWidth(300)
  frame:SetHeight(450)
  frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  frame:SetFrameStrata("DIALOG")
  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function() frame:StartMoving() end)
  frame:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
  
  -- Backdrop
  frame:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 12,
    insets = {left = 4, right = 4, top = 4, bottom = 4}
  })
  frame:SetBackdropColor(0, 0, 0, 0.85)
  
  -- Title
  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOP", 0, -15)
  title:SetText("Trade Settings")
  
  -- Close button
  local closeBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  closeBtn:SetWidth(60)
  closeBtn:SetHeight(24)
  closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -10)
  closeBtn:SetText("Close")
  closeBtn:SetScript("OnClick", function() frame:Hide() end)
  
  -- Instructions
  local instructions = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  instructions:SetPoint("TOPLEFT", 20, -45)
  instructions:SetText("Configure trade items and quantities:")
  
  -- List backdrop
  local listBackdrop = CreateFrame("Frame", nil, frame)
  listBackdrop:SetPoint("TOPLEFT", 17, -75)
  listBackdrop:SetPoint("BOTTOMRIGHT", -17, 10)
  listBackdrop:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 12,
    insets = {left = 3, right = 3, top = 3, bottom = 3}
  })
  listBackdrop:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
  
  -- Scroll frame
  local scrollFrame = CreateFrame("ScrollFrame", nil, listBackdrop)
  scrollFrame:SetPoint("TOPLEFT", listBackdrop, "TOPLEFT", 5, -5)
  scrollFrame:SetPoint("BOTTOMRIGHT", listBackdrop, "BOTTOMRIGHT", -22, 5)
  
  -- Scroll child
  local scrollChild = CreateFrame("Frame", nil, scrollFrame)
  scrollChild:SetWidth(235)
  scrollChild:SetHeight(1)
  scrollFrame:SetScrollChild(scrollChild)
  frame.scrollChild = scrollChild
  frame.scrollFrame = scrollFrame
  
  -- Create scrollbar
  local scrollBar = CreateFrame("Slider", nil, scrollFrame)
  scrollBar:SetPoint("TOPRIGHT", listBackdrop, "TOPRIGHT", -5, -16)
  scrollBar:SetPoint("BOTTOMRIGHT", listBackdrop, "BOTTOMRIGHT", -5, 16)
  scrollBar:SetWidth(16)
  scrollBar:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 8,
    insets = {left = 3, right = 3, top = 3, bottom = 3}
  })
  scrollBar:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
  scrollBar:SetOrientation("VERTICAL")
  scrollBar:SetMinMaxValues(0, 1)
  scrollBar:SetValue(0)
  scrollBar:SetValueStep(22)
  scrollBar:Hide()
  frame.scrollBar = scrollBar
  
  scrollBar:SetScript("OnValueChanged", function()
    scrollFrame:SetVerticalScroll(this:GetValue())
  end)
  
  scrollFrame:EnableMouseWheel(true)
  scrollFrame:SetScript("OnMouseWheel", function()
    if not scrollBar:IsShown() then
      return
    end
    
    local delta = arg1
    local current = scrollBar:GetValue()
    local minVal, maxVal = scrollBar:GetMinMaxValues()
    
    if delta > 0 then
      scrollBar:SetValue(math.max(minVal, current - 22))
    else
      scrollBar:SetValue(math.min(maxVal, current + 22))
    end
  end)
  
  frame:Show()
  OGRH.RefreshTradeSettings()
end

-- Refresh the trade settings list
function OGRH.RefreshTradeSettings()
  if not OGRH_TradeSettingsFrame then return end
  
  local scrollChild = OGRH_TradeSettingsFrame.scrollChild
  
  -- Clear existing rows
  if scrollChild.rows then
    for _, row in ipairs(scrollChild.rows) do
      row:Hide()
      row:SetParent(nil)
    end
  end
  scrollChild.rows = {}
  
  OGRH.EnsureSV()
  local items = OGRH_SV.tradeItems
  
  local yOffset = -5
  local rowHeight = 22
  local rowSpacing = 2
  
  for i, itemData in ipairs(items) do
    local row = CreateFrame("Button", nil, scrollChild)
    row:SetWidth(235)
    row:SetHeight(rowHeight)
    row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, yOffset)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    
    -- Background
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    bg:SetVertexColor(0.2, 0.2, 0.2, 0.5)
    row.bg = bg
    
    local idx = i
    
    -- Right-click to edit
    row:SetScript("OnClick", function()
      if arg1 == "RightButton" then
        OGRH.ShowEditTradeItemDialog(idx)
      end
    end)
    
    -- Delete button (X mark - raid target icon 7)
    local deleteBtn = CreateFrame("Button", nil, row)
    deleteBtn:SetWidth(16)
    deleteBtn:SetHeight(16)
    deleteBtn:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    
    local deleteIcon = deleteBtn:CreateTexture(nil, "ARTWORK")
    deleteIcon:SetWidth(16)
    deleteIcon:SetHeight(16)
    deleteIcon:SetAllPoints(deleteBtn)
    deleteIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    deleteIcon:SetTexCoord(0.5, 0.75, 0.25, 0.5)  -- Cross/X icon (raid mark 7)
    
    local deleteHighlight = deleteBtn:CreateTexture(nil, "HIGHLIGHT")
    deleteHighlight:SetWidth(16)
    deleteHighlight:SetHeight(16)
    deleteHighlight:SetAllPoints(deleteBtn)
    deleteHighlight:SetTexture("Interface\\Buttons\\UI-Common-MouseHilight")
    deleteHighlight:SetBlendMode("ADD")
    
    deleteBtn:SetScript("OnClick", function()
      table.remove(OGRH_SV.tradeItems, idx)
      OGRH.RefreshTradeSettings()
    end)
    
    -- Down button
    local downBtn = CreateFrame("Button", nil, row)
    downBtn:SetWidth(32)
    downBtn:SetHeight(32)
    downBtn:SetPoint("RIGHT", deleteBtn, "LEFT", 5, 0)
    downBtn:SetNormalTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up")
    downBtn:SetPushedTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Down")
    downBtn:SetHighlightTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Highlight")
    downBtn:SetScript("OnClick", function()
      if idx < table.getn(OGRH_SV.tradeItems) then
        local temp = OGRH_SV.tradeItems[idx + 1]
        OGRH_SV.tradeItems[idx + 1] = OGRH_SV.tradeItems[idx]
        OGRH_SV.tradeItems[idx] = temp
        OGRH.RefreshTradeSettings()
      end
    end)
    
    -- Up button
    local upBtn = CreateFrame("Button", nil, row)
    upBtn:SetWidth(32)
    upBtn:SetHeight(32)
    upBtn:SetPoint("RIGHT", downBtn, "LEFT", 13, 0)
    upBtn:SetNormalTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Up")
    upBtn:SetPushedTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Down")
    upBtn:SetHighlightTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Highlight")
    upBtn:SetScript("OnClick", function()
      if idx > 1 then
        local temp = OGRH_SV.tradeItems[idx - 1]
        OGRH_SV.tradeItems[idx - 1] = OGRH_SV.tradeItems[idx]
        OGRH_SV.tradeItems[idx] = temp
        OGRH.RefreshTradeSettings()
      end
    end)
    
    -- Quantity (positioned 10px from up arrow)
    local qtyText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    qtyText:SetPoint("RIGHT", upBtn, "LEFT", -10, 0)
    qtyText:SetText("x" .. (itemData.quantity or 1))
    
    -- Item name (fill remaining space)
    local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    nameText:SetPoint("LEFT", row, "LEFT", 5, 0)
    nameText:SetPoint("RIGHT", qtyText, "LEFT", -5, 0)
    nameText:SetJustifyH("LEFT")
    nameText:SetText(itemData.name or ("Item " .. itemData.itemId))
    upBtn:SetHighlightTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Highlight")
    upBtn:SetScript("OnClick", function()
      if idx > 1 then
        local temp = OGRH_SV.tradeItems[idx - 1]
        OGRH_SV.tradeItems[idx - 1] = OGRH_SV.tradeItems[idx]
        OGRH_SV.tradeItems[idx] = temp
        OGRH.RefreshTradeSettings()
      end
    end)
    
    table.insert(scrollChild.rows, row)
    yOffset = yOffset - rowHeight - rowSpacing
  end
  
  -- Add "Add Item" placeholder row at the bottom
  local addItemBtn = CreateFrame("Button", nil, scrollChild)
  addItemBtn:SetWidth(235)
  addItemBtn:SetHeight(rowHeight)
  addItemBtn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, yOffset)
  
  -- Background
  local bg = addItemBtn:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetTexture("Interface\\Buttons\\WHITE8X8")
  bg:SetVertexColor(0.1, 0.3, 0.1, 0.5)
  
  -- Highlight
  local highlight = addItemBtn:CreateTexture(nil, "HIGHLIGHT")
  highlight:SetAllPoints()
  highlight:SetTexture("Interface\\Buttons\\WHITE8X8")
  highlight:SetVertexColor(0.2, 0.5, 0.2, 0.5)
  
  -- Text
  local addText = addItemBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  addText:SetPoint("CENTER", addItemBtn, "CENTER", 0, 0)
  addText:SetText("|cff00ff00Add Item|r")
  
  addItemBtn:SetScript("OnClick", function()
    OGRH.ShowAddTradeItemDialog()
  end)
  
  table.insert(scrollChild.rows, addItemBtn)
  yOffset = yOffset - rowHeight
  
  -- Update scroll child height
  local contentHeight = math.abs(yOffset) + 5
  scrollChild:SetHeight(contentHeight)
  
  -- Update scrollbar visibility
  local scrollFrame = OGRH_TradeSettingsFrame.scrollFrame
  local scrollBar = OGRH_TradeSettingsFrame.scrollBar
  local scrollFrameHeight = scrollFrame:GetHeight()
  
  if contentHeight > scrollFrameHeight then
    scrollBar:Show()
    scrollBar:SetMinMaxValues(0, contentHeight - scrollFrameHeight)
    scrollBar:SetValue(0)
    scrollFrame:SetVerticalScroll(0)
  else
    scrollBar:Hide()
    scrollFrame:SetVerticalScroll(0)
  end
end

-- Show add trade item dialog
function OGRH.ShowAddTradeItemDialog()
  if OGRH_AddTradeItemDialog then
    OGRH_AddTradeItemDialog:Show()
    return
  end
  
  local dialog = CreateFrame("Frame", "OGRH_AddTradeItemDialog", UIParent)
  dialog:SetWidth(250)
  dialog:SetHeight(160)
  dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  dialog:SetFrameStrata("FULLSCREEN_DIALOG")
  dialog:EnableMouse(true)
  dialog:SetMovable(true)
  dialog:RegisterForDrag("LeftButton")
  dialog:SetScript("OnDragStart", function() dialog:StartMoving() end)
  dialog:SetScript("OnDragStop", function() dialog:StopMovingOrSizing() end)
  
  -- Backdrop
  dialog:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 12,
    insets = {left = 4, right = 4, top = 4, bottom = 4}
  })
  dialog:SetBackdropColor(0, 0, 0, 0.9)
  
  -- Title
  local title = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOP", 0, -15)
  title:SetText("Add Trade Item")
  
  -- Item ID label
  local itemIdLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  itemIdLabel:SetPoint("TOPLEFT", 20, -50)
  itemIdLabel:SetText("Item ID:")
  
  -- Item ID input
  local itemIdInput = CreateFrame("EditBox", nil, dialog)
  itemIdInput:SetPoint("LEFT", itemIdLabel, "RIGHT", 10, 0)
  itemIdInput:SetWidth(120)
  itemIdInput:SetHeight(25)
  itemIdInput:SetAutoFocus(false)
  itemIdInput:SetFontObject(ChatFontNormal)
  itemIdInput:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 12,
    insets = {left = 4, right = 4, top = 4, bottom = 4}
  })
  itemIdInput:SetBackdropColor(0, 0, 0, 0.8)
  itemIdInput:SetTextInsets(8, 8, 0, 0)
  itemIdInput:SetScript("OnEscapePressed", function() itemIdInput:ClearFocus() end)
  dialog.itemIdInput = itemIdInput
  
  -- Quantity label
  local qtyLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  qtyLabel:SetPoint("TOPLEFT", 20, -90)
  qtyLabel:SetText("Quantity:")
  
  -- Quantity input
  local qtyInput = CreateFrame("EditBox", nil, dialog)
  qtyInput:SetPoint("LEFT", qtyLabel, "RIGHT", 10, 0)
  qtyInput:SetWidth(120)
  qtyInput:SetHeight(25)
  qtyInput:SetAutoFocus(false)
  qtyInput:SetFontObject(ChatFontNormal)
  qtyInput:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 12,
    insets = {left = 4, right = 4, top = 4, bottom = 4}
  })
  qtyInput:SetBackdropColor(0, 0, 0, 0.8)
  qtyInput:SetTextInsets(8, 8, 0, 0)
  qtyInput:SetText("1")
  qtyInput:SetScript("OnEscapePressed", function() qtyInput:ClearFocus() end)
  dialog.qtyInput = qtyInput
  
  -- Cancel button
  local cancelBtn = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
  cancelBtn:SetWidth(80)
  cancelBtn:SetHeight(25)
  cancelBtn:SetPoint("BOTTOMRIGHT", -20, 15)
  cancelBtn:SetText("Cancel")
  cancelBtn:SetScript("OnClick", function()
    dialog:Hide()
  end)
  
  -- Add button
  local addBtn = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
  addBtn:SetWidth(80)
  addBtn:SetHeight(25)
  addBtn:SetPoint("RIGHT", cancelBtn, "LEFT", -10, 0)
  addBtn:SetText("Add")
  addBtn:SetScript("OnClick", function()
    local itemIdText = itemIdInput:GetText()
    local qtyText = qtyInput:GetText()
    
    local itemId = tonumber(itemIdText)
    local quantity = tonumber(qtyText)
    
    if not itemId or itemId <= 0 then
      OGRH.Msg("Invalid Item ID. Please enter a valid number.")
      return
    end
    
    if not quantity or quantity <= 0 then
      OGRH.Msg("Invalid Quantity. Please enter a valid number.")
      return
    end
    
    -- Get item name from game
    local itemName, itemLink = GetItemInfo(itemId)
    
    -- Add to list
    OGRH.EnsureSV()
    table.insert(OGRH_SV.tradeItems, {
      itemId = itemId,
      name = itemName or ("Item " .. itemId),
      quantity = quantity
    })
    
    -- Clear inputs
    itemIdInput:SetText("")
    qtyInput:SetText("1")
    
    -- Refresh settings window
    OGRH.RefreshTradeSettings()
    
    dialog:Hide()
    OGRH.Msg("Added trade item: " .. (itemName or ("Item " .. itemId)))
  end)
  
  dialog:Show()
end

-- Show edit trade item dialog
function OGRH.ShowEditTradeItemDialog(itemIndex)
  OGRH.EnsureSV()
  local itemData = OGRH_SV.tradeItems[itemIndex]
  if not itemData then return end
  
  if OGRH_EditTradeItemDialog then
    OGRH_EditTradeItemDialog.itemIndex = itemIndex
    OGRH_EditTradeItemDialog.itemIdInput:SetText(tostring(itemData.itemId))
    OGRH_EditTradeItemDialog.qtyInput:SetText(tostring(itemData.quantity or 1))
    OGRH_EditTradeItemDialog:Show()
    return
  end
  
  local dialog = CreateFrame("Frame", "OGRH_EditTradeItemDialog", UIParent)
  dialog:SetWidth(250)
  dialog:SetHeight(160)
  dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  dialog:SetFrameStrata("FULLSCREEN_DIALOG")
  dialog:EnableMouse(true)
  dialog:SetMovable(true)
  dialog:RegisterForDrag("LeftButton")
  dialog:SetScript("OnDragStart", function() dialog:StartMoving() end)
  dialog:SetScript("OnDragStop", function() dialog:StopMovingOrSizing() end)
  dialog.itemIndex = itemIndex
  
  -- Backdrop
  dialog:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 12,
    insets = {left = 4, right = 4, top = 4, bottom = 4}
  })
  dialog:SetBackdropColor(0, 0, 0, 0.9)
  
  -- Title
  local title = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOP", 0, -15)
  title:SetText("Edit Trade Item")
  
  -- Item ID label
  local itemIdLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  itemIdLabel:SetPoint("TOPLEFT", 20, -50)
  itemIdLabel:SetText("Item ID:")
  
  -- Item ID input
  local itemIdInput = CreateFrame("EditBox", nil, dialog)
  itemIdInput:SetPoint("LEFT", itemIdLabel, "RIGHT", 10, 0)
  itemIdInput:SetWidth(120)
  itemIdInput:SetHeight(25)
  itemIdInput:SetAutoFocus(false)
  itemIdInput:SetFontObject(ChatFontNormal)
  itemIdInput:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 12,
    insets = {left = 4, right = 4, top = 4, bottom = 4}
  })
  itemIdInput:SetBackdropColor(0, 0, 0, 0.8)
  itemIdInput:SetTextInsets(8, 8, 0, 0)
  itemIdInput:SetText(tostring(itemData.itemId))
  itemIdInput:SetScript("OnEscapePressed", function() itemIdInput:ClearFocus() end)
  dialog.itemIdInput = itemIdInput
  
  -- Quantity label
  local qtyLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  qtyLabel:SetPoint("TOPLEFT", 20, -90)
  qtyLabel:SetText("Quantity:")
  
  -- Quantity input
  local qtyInput = CreateFrame("EditBox", nil, dialog)
  qtyInput:SetPoint("LEFT", qtyLabel, "RIGHT", 10, 0)
  qtyInput:SetWidth(120)
  qtyInput:SetHeight(25)
  qtyInput:SetAutoFocus(false)
  qtyInput:SetFontObject(ChatFontNormal)
  qtyInput:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 12,
    insets = {left = 4, right = 4, top = 4, bottom = 4}
  })
  qtyInput:SetBackdropColor(0, 0, 0, 0.8)
  qtyInput:SetTextInsets(8, 8, 0, 0)
  qtyInput:SetText(tostring(itemData.quantity or 1))
  qtyInput:SetScript("OnEscapePressed", function() qtyInput:ClearFocus() end)
  dialog.qtyInput = qtyInput
  
  -- Cancel button
  local cancelBtn = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
  cancelBtn:SetWidth(80)
  cancelBtn:SetHeight(25)
  cancelBtn:SetPoint("BOTTOMRIGHT", -20, 15)
  cancelBtn:SetText("Cancel")
  cancelBtn:SetScript("OnClick", function()
    dialog:Hide()
  end)
  
  -- Save button
  local saveBtn = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
  saveBtn:SetWidth(80)
  saveBtn:SetHeight(25)
  saveBtn:SetPoint("RIGHT", cancelBtn, "LEFT", -10, 0)
  saveBtn:SetText("Save")
  saveBtn:SetScript("OnClick", function()
    local itemIdText = itemIdInput:GetText()
    local qtyText = qtyInput:GetText()
    
    local itemId = tonumber(itemIdText)
    local quantity = tonumber(qtyText)
    
    if not itemId or itemId <= 0 then
      OGRH.Msg("Invalid Item ID. Please enter a valid number.")
      return
    end
    
    if not quantity or quantity <= 0 then
      OGRH.Msg("Invalid Quantity. Please enter a valid number.")
      return
    end
    
    -- Get item name from game
    local itemName, itemLink = GetItemInfo(itemId)
    
    -- Update item
    OGRH_SV.tradeItems[dialog.itemIndex] = {
      itemId = itemId,
      name = itemName or ("Item " .. itemId),
      quantity = quantity
    }
    
    -- Refresh settings window
    OGRH.RefreshTradeSettings()
    
    dialog:Hide()
    OGRH.Msg("Updated trade item: " .. (itemName or ("Item " .. itemId)))
  end)
  
  dialog:Show()
end

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
  if not OGRH_SV.minimap then
    OGRH_SV.minimap = {angle = 200}
  end
  
  local function UpdatePosition()
    local angle = OGRH_SV.minimap.angle
    local x = 80 * math.cos(angle)
    local y = 80 * math.sin(angle)
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
  end
  
  UpdatePosition()
  
  -- Create right-click menu
  local function ShowMinimapMenu(sourceButton)
    if not OGRH_MinimapMenu then
      local menu = CreateFrame("Frame", "OGRH_MinimapMenu", UIParent)
      menu:SetFrameStrata("FULLSCREEN_DIALOG")
      menu:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = {left = 4, right = 4, top = 4, bottom = 4}
      })
      menu:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
      menu:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
      menu:SetWidth(160)
      menu:SetHeight(189)
      menu:Hide()
      
      -- Close menu when clicking outside
      menu:SetScript("OnShow", function()
        -- Create invisible backdrop to capture clicks
        if not menu.backdrop then
          local backdrop = CreateFrame("Frame", nil, UIParent)
          backdrop:SetFrameStrata("FULLSCREEN")
          backdrop:SetAllPoints()
          backdrop:EnableMouse(true)
          backdrop:SetScript("OnMouseDown", function()
            menu:Hide()
          end)
          menu.backdrop = backdrop
        end
        menu.backdrop:Show()
      end)
      
      menu:SetScript("OnHide", function()
        if menu.backdrop then
          menu.backdrop:Hide()
        end
      end)
      
      -- Title text
      local titleText = menu:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      titleText:SetPoint("TOP", menu, "TOP", 0, -8)
      titleText:SetText("OG-RaidHelper")
      titleText:SetTextColor(1, 0.82, 0)
      
      local yOffset = -28
      local itemHeight = 16
      local itemSpacing = 2
      
      -- Helper to create menu items
      local function CreateMenuItem(text, onClick, parent, yPos)
        local item = CreateFrame("Button", nil, menu)
        item:SetWidth(150)
        item:SetHeight(itemHeight)
        item:SetPoint("TOP", menu, "TOP", 0, yPos)
        
        -- Background highlight
        local bg = item:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetTexture("Interface\\Buttons\\WHITE8X8")
        bg:SetVertexColor(0.2, 0.2, 0.2, 0)
        item.bg = bg
        
        -- Text
        local fs = item:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", item, "LEFT", 8, 0)
        fs:SetText(text)
        fs:SetTextColor(1, 1, 1)
        item.fs = fs
        
        -- Highlight on hover
        item:SetScript("OnEnter", function()
          bg:SetVertexColor(0.3, 0.3, 0.3, 0.5)
        end)
        
        item:SetScript("OnLeave", function()
          bg:SetVertexColor(0.2, 0.2, 0.2, 0)
        end)
        
        item:SetScript("OnClick", function()
          onClick()
          menu:Hide()
        end)
        
        return item
      end
      
      -- Show/Hide item
      local toggleItem = CreateMenuItem("Show", function()
        if OGRH_Main then
          if OGRH_Main:IsVisible() then
            OGRH_Main:Hide()
            OGRH_SV.ui.hidden = true
          else
            OGRH_Main:Show()
            OGRH_SV.ui.hidden = false
          end
        end
      end, menu, yOffset)
      
      yOffset = yOffset - itemHeight - itemSpacing
      
      -- Share item
      local shareItem = CreateMenuItem("Share", function()
        OGRH.CloseAllWindows("OGRH_ShareFrame")
        
        if OGRH.ShowShareWindow then
          OGRH.ShowShareWindow()
        end
      end, menu, yOffset)
      
      yOffset = yOffset - itemHeight - itemSpacing
      
      -- Setup item
      local setupItem = CreateMenuItem("Setup", function()
        OGRH.CloseAllWindows("OGRH_EncounterSetupFrame")
        
        if OGRH.ShowEncounterSetup then
          OGRH.ShowEncounterSetup()
        end
      end, menu, yOffset)
      
      yOffset = yOffset - itemHeight - itemSpacing
      
      -- Invites item
      local invitesItem = CreateMenuItem("Invites", function()
        OGRH.CloseAllWindows("OGRH_InvitesFrame")
        
        if OGRH.Invites and OGRH.Invites.ShowWindow then
          OGRH.Invites.ShowWindow()
        else
          OGRH.Msg("Invites module not loaded.")
        end
      end, menu, yOffset)
      
      yOffset = yOffset - itemHeight - itemSpacing
      
      -- SR Validation item
      local srValidationItem = CreateMenuItem("SR Validation", function()
        OGRH.CloseAllWindows("OGRH_SRValidationFrame")
        
        if OGRH.SRValidation and OGRH.SRValidation.ShowWindow then
          OGRH.SRValidation.ShowWindow()
        else
          OGRH.Msg("SR Validation module not loaded.")
        end
      end, menu, yOffset)
      
      yOffset = yOffset - itemHeight - itemSpacing
      
      -- Addon Audit item
      local addonAuditItem = CreateMenuItem("Audit Addons", function()
        if OGRH.ShowAddonAudit then
          OGRH.ShowAddonAudit()
        else
          OGRH.Msg("Addon Audit module not loaded.")
        end
      end, menu, yOffset)
      
      yOffset = yOffset - itemHeight - itemSpacing
      
      -- Trade Settings item
      local tradeSettingsItem = CreateMenuItem("Trade Settings", function()
        if OGRH.ShowTradeSettings then
          OGRH.ShowTradeSettings()
        else
          OGRH.Msg("Trade Settings module not loaded.")
        end
      end, menu, yOffset)
      
      yOffset = yOffset - itemHeight - itemSpacing
      
      -- Consumes item
      local consumesItem = CreateMenuItem("Consumes", function()
        if OGRH.ShowConsumesSettings then
          OGRH.ShowConsumesSettings()
        else
          OGRH.Msg("Consumes module not loaded.")
        end
      end, menu, yOffset)
      
      menu.toggleItem = toggleItem
      
      -- Update toggle item text based on window state
      menu.UpdateToggleText = function()
        if OGRH_Main and OGRH_Main:IsVisible() then
          toggleItem.fs:SetText("Hide")
        else
          toggleItem.fs:SetText("Show")
        end
      end
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




