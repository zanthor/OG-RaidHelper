-- OGRH_Invites.lua
-- Raid Invites Module - Manage invites for players from dual data sources (RollFor / Raid-Helper JSON)
if not OGRH then
  DEFAULT_CHAT_FRAME:AddMessage("|cffff0000Error: OGRH_Invites requires OGRH_Core to be loaded first!|r")
  return
end

-- Load JSON library
if not json then
  local jsonPath = "Interface\\AddOns\\OG-RaidHelper\\Libs\\json.lua"
  local loadFunc, errorMsg = loadfile(jsonPath)
  if loadFunc then
    json = loadFunc()
  else
    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000Error loading json.lua: " .. tostring(errorMsg) .. "|r")
  end
end

OGRH.Invites = OGRH.Invites or {
  playerStatuses = {}, -- Track invite status per player
  lastUpdate = 0,
  updateInterval = 2, -- Update every 2 seconds
  lastRollForHash = nil, -- For detecting RollFor data changes
  roleSyncQueue = {} -- Queue for retrying failed role syncs
}

-- Data source constants
OGRH.Invites.SOURCE_TYPE = {
  ROLLFOR = "rollfor",
  RAIDHELPER = "raidhelper"
}

-- Invite status constants
local STATUS = {
  NOT_IN_RAID = "not_in_raid",
  IN_RAID = "in_raid",
  INVITED = "invited",
  DECLINED = "declined",
  OFFLINE = "offline",
  IN_OTHER_GROUP = "in_other_group"
}

-- Helper function to normalize player names to title case (First letter uppercase, rest lowercase)
local function NormalizeName(name)
  if not name or name == "" then return name end
  local lower = string.lower(name)
  return string.upper(string.sub(lower, 1, 1)) .. string.sub(lower, 2)
end

-- Initialize saved variables for invite tracking
function OGRH.Invites.EnsureSV()
  OGRH.EnsureSV()
  if not OGRH_SV.invites then
    OGRH_SV.invites = {
      -- Legacy tracking
      declinedPlayers = {}, -- Track who declined invites this session
      history = {}, -- Track invite history with timestamps
      
      -- Data source
      currentSource = OGRH.Invites.SOURCE_TYPE.ROLLFOR, -- "rollfor" | "raidhelper"
      raidhelperData = nil, -- Parsed Raid-Helper Invites JSON (table)
      raidhelperGroupsData = nil, -- Parsed Raid-Helper Groups JSON (table)
      
      -- Invite Mode (new)
      inviteMode = {
        enabled = false,
        interval = 60,
        lastInviteTime = 0,
        totalPlayers = 0,
        invitedCount = 0
      },
      
      -- Invite Mode Panel position
      invitePanelPosition = {
        point = "BOTTOMRIGHT",
        x = -20,
        y = 200
      },
      
      -- RollFor change detection
      lastRollForHash = nil
    }
  end
  
  -- Ensure new fields exist (for migration from old versions)
  if not OGRH_SV.invites.currentSource then
    OGRH_SV.invites.currentSource = OGRH.Invites.SOURCE_TYPE.ROLLFOR
  end
  if not OGRH_SV.invites.raidhelperData then
    OGRH_SV.invites.raidhelperData = nil
  end
  if not OGRH_SV.invites.raidhelperGroupsData then
    OGRH_SV.invites.raidhelperGroupsData = nil
  end
  if not OGRH_SV.invites.inviteMode then
    OGRH_SV.invites.inviteMode = {
      enabled = false,
      interval = 60,
      lastInviteTime = 0,
      totalPlayers = 0,
      invitedCount = 0
    }
  end
  if not OGRH_SV.invites.invitePanelPosition then
    OGRH_SV.invites.invitePanelPosition = {
      point = "BOTTOMRIGHT",
      x = -20,
      y = 200
    }
  end
  if not OGRH_SV.invites.lastRollForHash then
    OGRH_SV.invites.lastRollForHash = nil
  end
end

-- Parse Raid-Helper JSON data
function OGRH.Invites.ParseRaidHelperJSON(jsonString)
  if not jsonString or jsonString == "" then
    return nil, "No JSON data provided"
  end
  
  if not json then
    return nil, "JSON library not loaded"
  end
  
  -- Parse JSON using json.lua library
  local success, data = pcall(json.decode, jsonString)
  if not success then
    -- data contains error message with line/column info
    return nil, "JSON Parse Error: " .. tostring(data)
  end
  
  -- Validate structure
  if type(data) ~= "table" then
    return nil, "Invalid JSON: Root must be an object"
  end
  
  -- Real Raid-Helper format uses "signUps" array, not "players"
  local signUps = data.signUps or data.players
  if not signUps or type(signUps) ~= "table" then
    return nil, "Invalid JSON: Missing 'signUps' or 'players' array"
  end
  
  -- Extract raid metadata
  local raidId = data.id
  local raidTitle = data.title or data.displayTitle or "Raid"
  
  -- Normalize player data
  local players = {}
  for i = 1, table.getn(signUps) do
    local signup = signUps[i]
    if signup and signup.name then
      local playerName = NormalizeName(signup.name)
      
      -- Determine actual class vs status
      -- Raid-Helper uses className for BOTH class and status (Absence/Bench/Tentative)
      local className = signup.className
      local actualClass = nil
      local isBench = false
      local isAbsent = false
      
      if className == "Absence" then
        isAbsent = true
        -- Will be looked up later from guild roster
        actualClass = nil
      elseif className == "Bench" then
        isBench = true
        actualClass = nil
      elseif className == "Tentative" then
        -- Tentative is active but uncertain - treat as active
        actualClass = nil
      elseif className then
        -- This is an actual class name
        actualClass = string.upper(className)
      end
      
      -- Map roleName to OGRH format
      local roleName = signup.roleName
      local role = nil
      if roleName == "Tanks" then
        role = "TANKS"
      elseif roleName == "Healers" then
        role = "HEALERS"
      elseif roleName == "Melee" then
        role = "MELEE"
      elseif roleName == "Ranged" then
        role = "RANGED"
      end
      
      -- Create normalized player object
      local player = {
        name = playerName,
        class = actualClass,
        role = role,
        status = signup.status or "signed",
        position = signup.position, -- Store position for sorting
        group = nil, -- Will be assigned by role during group organization
        bench = isBench,
        absent = isAbsent,
        source = OGRH.Invites.SOURCE_TYPE.RAIDHELPER
      }
      
      table.insert(players, player)
    end
  end
  
  -- Sort players by position to maintain signup order
  table.sort(players, function(a, b)
    local posA = a.position or 999
    local posB = b.position or 999
    return posA < posB
  end)
  
  -- Assign groups based on roles (fallback if no Groups JSON imported)
  -- Tanks: Group 1
  -- Healers: Group 2-3 (5 per group)
  -- Melee: Group 4-6 (5 per group)
  -- Ranged: Group 7-8 (5 per group)
  -- NOTE: This is overridden if Groups JSON is imported
  local groupCounters = {
    TANKS = 1,    -- Start at group 1
    HEALERS = 2,  -- Start at group 2
    MELEE = 4,    -- Start at group 4
    RANGED = 7    -- Start at group 7
  }
  local playersInGroup = {
    [1] = 0, [2] = 0, [3] = 0, [4] = 0,
    [5] = 0, [6] = 0, [7] = 0, [8] = 0
  }
  
  for _, player in ipairs(players) do
    if not player.bench and not player.absent and player.role then
      local role = player.role
      local currentGroup = groupCounters[role]
      
      if currentGroup then
        -- Assign to group
        player.group = currentGroup
        playersInGroup[currentGroup] = playersInGroup[currentGroup] + 1
        
        -- If group is full (5 players), move to next group
        if playersInGroup[currentGroup] >= 5 then
          if role == "TANKS" and currentGroup < 1 then
            currentGroup = 1 -- Tanks only use group 1
          elseif role == "HEALERS" and currentGroup < 3 then
            groupCounters[role] = currentGroup + 1
          elseif role == "MELEE" and currentGroup < 6 then
            groupCounters[role] = currentGroup + 1
          elseif role == "RANGED" and currentGroup < 8 then
            groupCounters[role] = currentGroup + 1
          end
        end
      end
    end
  end
  
  -- Create final normalized structure
  local result = {
    id = raidId,
    name = raidTitle,
    players = players
  }
  
  return result, nil
end

-- Parse Raid-Helper Groups JSON data (Composition Tool)
function OGRH.Invites.ParseRaidHelperGroupsJSON(jsonString)
  if not jsonString or jsonString == "" then
    return nil, "No JSON data provided"
  end
  
  if not json then
    return nil, "JSON library not loaded"
  end
  
  -- Parse JSON using json.lua library
  local success, data = pcall(json.decode, jsonString)
  if not success then
    return nil, "JSON Parse Error: " .. tostring(data)
  end
  
  -- Validate structure
  if type(data) ~= "table" then
    return nil, "Invalid JSON: Root must be an object"
  end
  
  -- Check for raidDrop array
  local raidDrop = data.raidDrop
  if not raidDrop or type(raidDrop) ~= "table" then
    return nil, "Invalid JSON: Missing 'raidDrop' array"
  end
  
  -- Extract full player roster
  local players = {}
  local groupAssignments = {} -- { [playerName] = groupNumber }
  
  for i = 1, table.getn(raidDrop) do
    local slot = raidDrop[i]
    if slot and slot.name then
      local playerName = NormalizeName(slot.name)
      local groupNum = tonumber(slot.partyId)
      local isBenched = (slot.class == "Bench")
      
      -- Map role_emote to OGRH role format
      local role = nil
      if slot.role_emote == "598989638098747403" then
        role = "TANKS"
      elseif slot.role_emote == "592438128057253898" then
        role = "HEALERS"
      elseif slot.role_emote == "734439523328720913" then
        role = "MELEE"
      elseif slot.role_emote == "592446395596931072" then
        role = "RANGED"
      end
      
      -- Get actual class from cache (for benched players and validation)
      local actualClass = nil
      if not isBenched and slot.class and slot.class ~= "Bench" then
        actualClass = string.upper(slot.class)
      end
      
      -- Try to get class from OGRH cache if not available
      if not actualClass then
        actualClass = OGRH.GetPlayerClass(playerName)
      end
      
      -- Create player object
      local player = {
        name = playerName,
        class = actualClass,
        role = role,
        group = groupNum,
        bench = isBenched,
        absent = false,
        status = "signed",
        source = OGRH.Invites.SOURCE_TYPE.RAIDHELPER
      }
      
      table.insert(players, player)
      
      -- Store group assignment for non-benched players
      if not isBenched and groupNum and groupNum >= 1 and groupNum <= 8 then
        groupAssignments[playerName] = groupNum
      end
    end
  end
  
  -- Create final normalized structure
  local result = {
    hash = data.hash,
    title = data.title or "Composition",
    players = players,
    groupAssignments = groupAssignments
  }
  
  return result, nil
end

-- Apply group assignments from Groups JSON to Invites data
function OGRH.Invites.ApplyGroupAssignments()
  local groupsData = OGRH_SV.invites.raidhelperGroupsData
  local invitesData = OGRH_SV.invites.raidhelperData
  
  if not groupsData or not groupsData.groupAssignments then
    return
  end
  
  if not invitesData or not invitesData.players then
    return
  end
  
  -- Apply group assignments to players
  for _, player in ipairs(invitesData.players) do
    local assignedGroup = groupsData.groupAssignments[player.name]
    if assignedGroup then
      player.group = assignedGroup
    end
  end
end

-- Get player list from RollFor soft-res data
function OGRH.Invites.GetSoftResPlayers()
  local players = {}
  
  -- Check if RollFor is available
  if not OGRH.ROLLFOR_AVAILABLE then
    return players
  end
  
  -- Check if RollFor addon is loaded
  if not RollFor or not RollForCharDb then
    return players
  end
  
  -- Check if we have softres data
  if not RollForCharDb.softres then
    return players
  end
  
  -- The data is stored as an encoded string in RollForCharDb.softres.data
  -- We need to decode it using RollFor's decode function
  local encodedData = RollForCharDb.softres.data
  if not encodedData or type(encodedData) ~= "string" then
    return players
  end
  
  -- Use RollFor's SoftRes.decode function to decode the data
  if not RollFor.SoftRes or type(RollFor.SoftRes.decode) ~= "function" then
    return players
  end
  
  local decodedData = RollFor.SoftRes.decode(encodedData)
  if not decodedData or type(decodedData) ~= "table" then
    return players
  end
  
  -- Store the entire decoded structure for debugging
  OGRH.Invites.rawDecodedData = decodedData
  
  -- Extract metadata from nested table
  if decodedData.metadata and type(decodedData.metadata) == "table" then
    OGRH.Invites.softresMetadata = decodedData.metadata
  else
    OGRH.Invites.softresMetadata = {}
  end
  
  -- Now transform the data using SoftResDataTransformer
  if not RollFor.SoftResDataTransformer or type(RollFor.SoftResDataTransformer.transform) ~= "function" then
    return players
  end
  
  local softresData, hardresData = RollFor.SoftResDataTransformer.transform(decodedData)
  if not softresData or type(softresData) ~= "table" then
    return players
  end
  
  -- Build player map from soft-res data
  -- softresData structure: { [itemId] = { rollers = { {name, role, sr_plus, rolls} }, quality } }
  local playerMap = {}
  
  for itemId, itemData in pairs(softresData) do
    if type(itemData) == "table" and itemData.rollers then
      for _, roller in ipairs(itemData.rollers) do
        if roller and roller.name then
          local normalizedName = NormalizeName(roller.name)
          if not playerMap[normalizedName] then
            playerMap[normalizedName] = {
              name = normalizedName,
              role = roller.role or "Unknown",
              srPlus = roller.sr_plus or 0,
              itemCount = 0
            }
          end
          -- Increment item count
          playerMap[normalizedName].itemCount = playerMap[normalizedName].itemCount + (roller.rolls or 1)
        end
      end
    end
  end
  
  -- Convert map to array and add source marker
  for _, playerData in pairs(playerMap) do
    playerData.source = OGRH.Invites.SOURCE_TYPE.ROLLFOR
    playerData.bench = false
    playerData.absent = false
    table.insert(players, playerData)
  end
  
  -- Sort by name
  if table.getn(players) > 0 then
    table.sort(players, function(a, b) return a.name < b.name end)
  end
  
  return players
end

-- Get unified roster from current data source
function OGRH.Invites.GetRosterPlayers()
  OGRH.Invites.EnsureSV()
  
  local currentSource = OGRH_SV.invites.currentSource
  
  if currentSource == OGRH.Invites.SOURCE_TYPE.RAIDHELPER then
    -- Use Raid-Helper JSON data
    local raidhelperData = OGRH_SV.invites.raidhelperData
    if not raidhelperData or not raidhelperData.players then
      return {}
    end
    
    -- Return players in standardized format
    local players = {}
    for i = 1, table.getn(raidhelperData.players) do
      local player = raidhelperData.players[i]
      
      -- Convert to standardized format
      -- Note: role is already in OGRH format from parser (TANKS, HEALERS, MELEE, RANGED)
      local standardPlayer = {
        name = player.name,
        class = player.class,
        role = player.role,  -- Already mapped by parser
        group = player.group,
        bench = player.bench or false,
        absent = player.absent or false,
        status = STATUS.NOT_IN_RAID,
        online = false,
        source = OGRH.Invites.SOURCE_TYPE.RAIDHELPER
      }
      
      table.insert(players, standardPlayer)
    end
    
    return players
    
  else
    -- Use RollFor data (default)
    local rollforPlayers = OGRH.Invites.GetSoftResPlayers()
    
    -- Convert to standardized format
    local players = {}
    for i = 1, table.getn(rollforPlayers) do
      local player = rollforPlayers[i]
      
      local standardPlayer = {
        name = player.name,
        class = player.class,
        role = OGRH.Invites.MapRoleToOGRH(player.role, OGRH.Invites.SOURCE_TYPE.ROLLFOR),
        group = nil, -- RollFor doesn't have group assignments
        bench = false,
        absent = false,
        status = STATUS.NOT_IN_RAID,
        online = false,
        source = OGRH.Invites.SOURCE_TYPE.ROLLFOR,
        rawRole = player.role -- Keep original role string
      }
      
      table.insert(players, standardPlayer)
    end
    
    return players
  end
end

-- Map role to OGRH bucket based on source
function OGRH.Invites.MapRoleToOGRH(roleString, source)
  if not roleString or roleString == "" then
    return nil
  end
  
  if source == OGRH.Invites.SOURCE_TYPE.RAIDHELPER then
    -- Raid-Helper uses simplified roles: Tank, Healer, Melee, Ranged
    local roleMap = {
      Tank = "TANKS",
      Healer = "HEALERS",
      Healers = "HEALERS", -- Handle plural
      Melee = "MELEE",
      Ranged = "RANGED"
    }
    return roleMap[roleString]
  else
    -- RollFor uses ClassSpec format - use existing mapper
    return OGRH.Invites.MapRollForRoleToOGRH(roleString)
  end
end

-- Check if player is in current raid
function OGRH.Invites.IsPlayerInRaid(playerName)
  if not playerName then return false end
  playerName = NormalizeName(playerName)
  
  local numRaid = GetNumRaidMembers() or 0
  for i = 1, numRaid do
    local name = GetRaidRosterInfo(i)
    if name and NormalizeName(name) == playerName then
      return true
    end
  end
  
  return false
end

-- Get player online status and group status
function OGRH.Invites.GetPlayerStatus(playerName)
  OGRH.Invites.EnsureSV()
  
  -- Check if in our raid first
  if OGRH.Invites.IsPlayerInRaid(playerName) then
    return STATUS.IN_RAID, true, nil
  end
  
  -- Check if we've invited them this session
  if OGRH.Invites.playerStatuses[playerName] == STATUS.INVITED then
    return STATUS.INVITED, false, nil
  end
  
  -- Check if they declined
  if OGRH_SV.invites.declinedPlayers[playerName] then
    return STATUS.DECLINED, false, nil
  end
  
  -- Try to check if player is online via guild roster
  local numGuild = GetNumGuildMembers(true)
  for i = 1, numGuild do
    local name, _, _, _, _, _, _, _, online, _, class = GetGuildRosterInfo(i)
    if name and NormalizeName(name) == NormalizeName(playerName) then
      if not online then
        return STATUS.OFFLINE, false, class
      end
      -- Online but not in our raid
      return STATUS.NOT_IN_RAID, true, class
    end
  end
  
  -- Can't determine status (not in guild or we can't see them)
  return STATUS.NOT_IN_RAID, false, nil
end

-- Send invite to player
function OGRH.Invites.InvitePlayer(playerName)
  if not playerName or playerName == "" then return end
  playerName = NormalizeName(playerName)
  
  local numRaid = GetNumRaidMembers()
  local numParty = GetNumPartyMembers()
  
  -- Check if we're in a raid and have permission
  if numRaid > 0 then
    -- In a raid, check if we're leader or assistant
    if not IsRaidLeader() and not IsRaidOfficer() then
      OGRH.Msg("You must be raid leader or assistant to invite players.")
      return false
    end
  elseif numParty > 0 then
    -- In a party, check if we're leader
    if not IsPartyLeader() then
      OGRH.Msg("You must be party leader to invite players.")
      return false
    end
  end
  -- If solo, we can invite (will start a party)
  
  -- Send the invite
  InviteByName(playerName)
  
  -- Log the invite in history
  OGRH.Invites.EnsureSV()
  table.insert(OGRH_SV.invites.history, {
    player = playerName,
    timestamp = time(),
    action = "invited"
  })
  
  if numRaid > 0 then
    OGRH.Msg("Invited " .. playerName .. " to raid.")
  else
    OGRH.Msg("Invited " .. playerName .. " to party.")
  end
  return true
end

-- Send whisper to player
function OGRH.Invites.WhisperPlayer(playerName, message)
  if not playerName or playerName == "" then return end
  
  local msg = message
  if not msg then
    local meta = OGRH.Invites.GetMetadata()
    local raidName = "the raid"
    if meta.instance then
      raidName = OGRH.Invites.GetInstanceName(meta.instance)
    end
    msg = "Whisper me invite for " .. raidName .. " when ready."
  end
  SendChatMessage(msg, "WHISPER", nil, playerName)
  
  OGRH.Msg("Whispered " .. playerName .. ".")
end

-- Clear declined status for a player
function OGRH.Invites.ClearDeclined(playerName)
  OGRH.Invites.EnsureSV()
  OGRH_SV.invites.declinedPlayers[playerName] = nil
  OGRH.Invites.playerStatuses[playerName] = nil
end

-- Clear all invite tracking
function OGRH.Invites.ClearAllTracking()
  OGRH.Invites.EnsureSV()
  OGRH_SV.invites.declinedPlayers = {}
  OGRH.Invites.playerStatuses = {}
  OGRH.Msg("Cleared all invite tracking.")
end

-- Update player class from raid roster
function OGRH.Invites.UpdatePlayerClass(playerData)
  if not playerData or not playerData.name then return playerData end
  
  -- Use OGRH's existing class lookup system
  local class = OGRH.GetPlayerClass(playerData.name)
  if class then
    playerData.class = class
    return playerData
  end
  
  -- Fallback: Check raid roster for class
  local numRaid = GetNumRaidMembers() or 0
  for i = 1, numRaid do
    local name, _, _, _, raidClass = GetRaidRosterInfo(i)
    if name and NormalizeName(name) == NormalizeName(playerData.name) and raidClass then
      playerData.class = string.upper(raidClass)
      return playerData
    end
  end
  
  -- Check guild roster
  local numGuild = GetNumGuildMembers(true)
  for i = 1, numGuild do
    local name, _, _, _, _, _, _, _, _, _, guildClass = GetGuildRosterInfo(i)
    if name and NormalizeName(name) == NormalizeName(playerData.name) and guildClass then
      playerData.class = string.upper(guildClass)
      return playerData
    end
  end
  
  return playerData
end

-- Get soft-res metadata (instance, date, time)
function OGRH.Invites.GetMetadata()
  -- Force a refresh to capture metadata
  OGRH.Invites.GetSoftResPlayers()
  return OGRH.Invites.softresMetadata or {}
end

-- Map instance ID to name
function OGRH.Invites.GetInstanceName(instanceId)
  local instances = {
    [100] = "Zul'Gurub", -- wd
    [98] = "Ruins of Ahn'Qiraj", -- wd
    [101] = "Lower Karazhan Halls", -- wd
    [95] = "Molten Core", -- wd
    [94] = "Blackwing Lair", -- wd
    [99] = "Temple of Ahn'Qiraj", --wd
    [96] = "Naxxramas", --wd
    [109] = "Karazhan", -- wd
    [97] = "Onyxia's Lair", -- wd
    [102] = "Emerald Sanctum", -- wd 
  }
  return instances[tonumber(instanceId)] or "Unknown Raid (ID: " .. tostring(instanceId) .. ")"
end

-- Debug function to show available metadata
function OGRH.Invites.ShowMetadata()
  local meta = OGRH.Invites.GetMetadata()
  DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00=== RollFor Soft-Res Metadata ===|r")
  for key, value in pairs(meta) do
    if key == "instance" then
      DEFAULT_CHAT_FRAME:AddMessage("|cffffcc00" .. key .. "|r: " .. tostring(value) .. " (" .. OGRH.Invites.GetInstanceName(value) .. ")")
    else
      DEFAULT_CHAT_FRAME:AddMessage("|cffffcc00" .. key .. "|r: " .. tostring(value))
    end
  end
  if not next(meta) then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000No metadata found|r")
  end
end

-- Debug function to show raw decoded structure
function OGRH.Invites.ShowRawData()
  OGRH.Invites.GetSoftResPlayers() -- Force refresh
  
  if not OGRH.Invites.rawDecodedData then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000No raw data available|r")
    return
  end
  
  DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00=== Raw Decoded Data Structure ===|r")
  local count = 0
  for key, value in pairs(OGRH.Invites.rawDecodedData) do
    count = count + 1
    if count <= 20 then
      DEFAULT_CHAT_FRAME:AddMessage("|cffffcc00" .. tostring(key) .. "|r: " .. type(value) .. 
        (type(value) ~= "table" and " = " .. tostring(value) or ""))
    end
  end
  DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00Total keys: " .. count .. "|r")
end

-- Map RollFor role to OGRH RolesUI bucket
function OGRH.Invites.MapRollForRoleToOGRH(rollForRole)
  -- RollFor format: "ClassSpec" (e.g., "DruidBalance", "HunterMarksmanship")
  -- Map to OGRH buckets: TANKS, HEALERS, MELEE, RANGED
  
  if not rollForRole or rollForRole == "" then
    return nil
  end
  
  local roleMap = {
    -- Tanks
    DruidBear = "TANKS",
    PaladinProtection = "TANKS",
    ShamanTank = "TANKS",
    WarriorProtection = "TANKS",
    
    -- Healers
    DruidRestoration = "HEALERS",
    PaladinHoly = "HEALERS",
    PriestHoly = "HEALERS",
    ShamanRestoration = "HEALERS",
    
    -- Melee
    DruidFeral = "MELEE",
    HunterSurvival = "MELEE",
    PaladinRetribution = "MELEE",
    RogueDaggers = "MELEE",
    RogueSwords = "MELEE",
    ShamanEnhancement = "MELEE",
    WarriorArms = "MELEE",
    WarriorFury = "MELEE",
    
    -- Ranged
    DruidBalance = "RANGED",
    HunterMarksmanship = "RANGED",
    HunterBeastMastery = "RANGED",
    MageArcane = "RANGED",
    MageFire = "RANGED",
    MageFrost = "RANGED",
    PriestDiscipline = "RANGED",
    PriestShadow = "RANGED",
    WarlockAffliction = "RANGED",
    WarlockDemonology = "RANGED",
    WarlockDestruction = "RANGED",
    ShamanElemental = "RANGED"
  }
  
  return roleMap[rollForRole]
end

-- Sync RollFor data to OGRH RolesUI
function OGRH.Invites.SyncToRolesUI()
  local players = OGRH.Invites.GetSoftResPlayers()
  
  if table.getn(players) == 0 then
    OGRH.Msg("No soft-res players to sync.")
    return
  end
  
  local syncCount = 0
  
  for _, playerData in ipairs(players) do
    local ogrh_role = OGRH.Invites.MapRollForRoleToOGRH(playerData.role)
    
    if ogrh_role and playerData.name then
      -- Use OGRH's AddTo function to assign role
      OGRH.AddTo(ogrh_role, playerData.name)
      syncCount = syncCount + 1
    end
  end
  
  OGRH.Msg("Synced " .. syncCount .. " players from RollFor to Roles.")
  
  -- Refresh RolesUI if it's open
  if OGRH_RolesFrame and OGRH_RolesFrame:IsVisible() and OGRH.RenderRoles then
    OGRH.RenderRoles()
  end
end

-- Show Invites Window
function OGRH.Invites.ShowWindow()
  -- Check if RollFor is available
  if not OGRH.ROLLFOR_AVAILABLE then
    OGRH.Msg("Invites requires RollFor version " .. OGRH.ROLLFOR_REQUIRED_VERSION .. ".")
    return
  end
  
  -- Close other windows
  OGRH.CloseAllWindows("OGRH_InvitesFrame")
  
  if OGRH_InvitesFrame then
    OGRH_InvitesFrame:Show()
    OGRH.Invites.RefreshPlayerList()
    return
  end
  
  -- Create main frame
  local frame = CreateFrame("Frame", "OGRH_InvitesFrame", UIParent)
  frame:SetWidth(520)
  frame:SetHeight(540)
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
  
  -- Import Roster menu button (top left)
  local importMenuBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  importMenuBtn:SetWidth(110)
  importMenuBtn:SetHeight(24)
  importMenuBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -10)
  importMenuBtn:SetText("Import Roster")
  if OGRH and OGRH.StyleButton then
    OGRH.StyleButton(importMenuBtn)
  end
  
  -- Create dropdown menu for import options
  importMenuBtn:SetScript("OnClick", function()
    local menu = OGRH.CreateStandardMenu({
      name = "OGRH_ImportRosterMenu",
      width = 140
    })
    
    -- RollFor Import option
    menu:AddItem({
      text = "RollFor Soft-Res",
      onClick = function()
        if RollFor and RollFor.key_bindings and RollFor.key_bindings.softres_toggle then
          RollFor.key_bindings.softres_toggle()
          OGRH_SV.invites.currentSource = OGRH.Invites.SOURCE_TYPE.ROLLFOR
          if OGRH_InvitesFrame and OGRH_InvitesFrame.UpdateOrganizeButton then
            OGRH_InvitesFrame.UpdateOrganizeButton()
          end
        else
          OGRH.Msg("RollFor addon not found or not loaded.")
        end
      end
    })
    
    -- Raid-Helper Invites JSON Import option
    menu:AddItem({
      text = "Raid-Helper (Invites)",
      onClick = function()
        OGRH.Invites.ShowJSONImportDialog("invites")
      end
    })
    
    -- Raid-Helper Groups JSON Import option
    menu:AddItem({
      text = "Raid-Helper (Groups)",
      onClick = function()
        OGRH.Invites.ShowJSONImportDialog("groups")
      end
    })
    
    menu:Finalize()
    menu:SetPoint("TOPLEFT", this, "BOTTOMLEFT", 0, 0)
    menu:Show()
  end)
  
  -- Title
  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOP", 0, -15)
  
  -- Set title with raid name and ID from metadata
  local meta = OGRH.Invites.GetMetadata()
  local titleText = "Raid Invites"
  if meta.instance then
    local raidName = OGRH.Invites.GetInstanceName(meta.instance)
    titleText = "Raid Invites - " .. raidName .. " (" .. tostring(meta.instance) .. ")"
  end
  title:SetText(titleText)
  frame.titleText = title
  
  -- Close button
  local closeBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  closeBtn:SetWidth(60)
  closeBtn:SetHeight(24)
  closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -10)
  closeBtn:SetText("Close")
  OGRH.StyleButton(closeBtn)
  closeBtn:SetScript("OnClick", function() frame:Hide() end)
  
  -- Info text
  local infoText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  infoText:SetPoint("TOPLEFT", 20, -45)
  infoText:SetPoint("TOPRIGHT", -20, -45)
  infoText:SetJustifyH("LEFT")
  infoText:SetText("Players from RollFor soft-res data not currently in the raid:")
  frame.infoText = infoText
  
  -- Column headers
  local headerFrame = CreateFrame("Frame", nil, frame)
  headerFrame:SetPoint("TOPLEFT", 20, -70)
  headerFrame:SetPoint("TOPRIGHT", -20, -70)
  headerFrame:SetHeight(20)
  
  local nameHeader = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  nameHeader:SetPoint("LEFT", 5, 0)
  nameHeader:SetText("Name")
  
  local roleHeader = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  roleHeader:SetPoint("LEFT", 140, 0)
  roleHeader:SetText("Role")
  
  local statusHeader = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  statusHeader:SetPoint("LEFT", 230, 0)
  statusHeader:SetText("Status")
  
  local actionsHeader = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  actionsHeader:SetPoint("LEFT", 320, 0)
  actionsHeader:SetText("Actions")
  
  -- Create a container frame for the player list that fills available space
  local listContainer = CreateFrame("Frame", nil, frame)
  listContainer:SetPoint("TOPLEFT", 17, -95)
  local containerWidth = frame:GetWidth() - 34
  local containerHeight = frame:GetHeight() - 185  -- 95 top + 115 bottom (Refresh+Clear Status rows)
  listContainer:SetWidth(containerWidth)
  listContainer:SetHeight(containerHeight)
  
  -- Create styled scroll list using standardized function
  local listFrame, scrollFrame, scrollChild, scrollBar, contentWidth = OGRH.CreateStyledScrollList(listContainer, containerWidth, containerHeight)
  listFrame:SetAllPoints(listContainer)
  
  frame.scrollChild = scrollChild
  frame.scrollFrame = scrollFrame
  frame.scrollBar = scrollBar
  frame.contentWidth = contentWidth
  
  -- Bottom action buttons (using OGST components)
  
  -- Row 1 (y=15): Invite Mode controls
  local inviteModeBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  inviteModeBtn:SetWidth(130)
  inviteModeBtn:SetHeight(28)
  inviteModeBtn:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 20, 15)
  inviteModeBtn:SetText(OGRH_SV.invites.inviteMode.enabled and "Stop Invite Mode" or "Start Invite Mode")
  if OGRH.StyleButton then
    OGRH.StyleButton(inviteModeBtn)
  end
  inviteModeBtn:SetScript("OnClick", function()
    OGRH.Invites.ToggleInviteMode()
  end)
  frame.inviteModeBtn = inviteModeBtn
  
  local function UpdateInviteModeButton()
    inviteModeBtn:SetText(OGRH_SV.invites.inviteMode.enabled and "Stop Invite Mode" or "Start Invite Mode")
  end
  
  -- Interval input with label using OGST
  local intervalContainer, intervalBackdrop, intervalInput, intervalLabel = OGST.CreateSingleLineTextBox(frame, 40, 28, {
    label = "Invite every",
    labelAnchor = "LEFT",
    labelWidth = 80,
    labelAlign = "RIGHT",
    textBoxWidth = 40,
    gap = 5,
    numeric = true,
    maxLetters = 3,
    align = "CENTER",
    onChange = function(text)
      local value = tonumber(text) or 10
      if value < 10 then value = 10 end
      if value > 300 then value = 300 end
      OGRH_SV.invites.inviteMode.interval = value
      if intervalInput and intervalInput.SetText then
        intervalInput:SetText(tostring(value))
      end
    end
  })
  OGST.AnchorElement(intervalContainer, inviteModeBtn, {position = "right", align = "center"})
  if intervalInput and intervalInput.SetText then
    intervalInput:SetText(tostring(OGRH_SV.invites.inviteMode.interval))
  end
  frame.intervalInput = intervalInput
  
  -- Seconds label
  local secondsLabel = OGST.CreateStaticText(frame, {
    text = "seconds",
    font = "GameFontNormal"
  })
  OGST.AnchorElement(secondsLabel, intervalContainer, {position = "right", align = "center"})
  
  -- Row 2 (y=50): Action buttons
  local inviteAllBtn = OGST.CreateButton(frame, {
    text = "Invite All Active",
    width = 130,
    height = 28,
    onClick = function()
      OGRH.Invites.InviteAllOnline()
    end
  })
  inviteAllBtn:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 20, 50)
  
  -- Stats text (row 2, center)
  local statsText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  statsText:SetPoint("LEFT", inviteAllBtn, "RIGHT", 20, 0)
  statsText:SetJustifyH("LEFT")
  statsText:SetText("0 players not in raid")
  frame.statsText = statsText
  
  UpdateInviteModeButton()
  
  -- Initialize auto-sort state (default off)
  if not OGRH_SV.rgo then
    OGRH_SV.rgo = {}
  end
  if OGRH_SV.rgo.autoSortEnabled == nil then
    OGRH_SV.rgo.autoSortEnabled = false
  end
  
  -- Refresh button (row 2, right side)
  local refreshBtn = OGST.CreateButton(frame, {
    text = "Refresh",
    width = 80,
    height = 28,
    onClick = function()
      OGRH.Invites.RefreshPlayerList()
      OGRH.Msg("Refreshed player list.")
    end
  })
  refreshBtn:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -20, 50)
  
  -- Clear Status button (below Refresh)
  local clearBtn = OGST.CreateButton(frame, {
    text = "Clear Status",
    width = 100,
    height = 28,
    onClick = function()
      OGRH.Invites.ClearAllTracking()
      OGRH.Invites.RefreshPlayerList()
    end
  })
  OGST.AnchorElement(clearBtn, refreshBtn, {position = "below", align = "right"})
  
  -- AutoGroup button (to the left of Clear Status, only for Raid-Helper source)
  local organizeBtn = OGST.CreateButton(frame, {
    text = "AutoGroup",
    width = 80,
    height = 28,
    onClick = function()
      OGRH.Invites.OrganizeRaidGroups()
    end
  })
  OGST.AnchorElement(organizeBtn, clearBtn, {position = "left", align = "center"})
  
  -- Show/hide organize button based on data source
  local function UpdateOrganizeButton()
    if OGRH_SV.invites.currentSource == OGRH.Invites.SOURCE_TYPE.RAIDHELPER then
      organizeBtn:Show()
    else
      organizeBtn:Hide()
    end
  end
  UpdateOrganizeButton()
  frame.UpdateOrganizeButton = UpdateOrganizeButton
  
  -- Register window with OGST for design mode updates
  if OGST.RegisterWindow then
    OGST.RegisterWindow(frame)
  end
  
  -- Auto-update timer
  frame:SetScript("OnUpdate", function()
    if not frame:IsVisible() then return end
    
    local now = GetTime()
    if now - OGRH.Invites.lastUpdate >= OGRH.Invites.updateInterval then
      OGRH.Invites.lastUpdate = now
      OGRH.Invites.RefreshPlayerList()
    end
  end)
  
  -- Register for whisper events
  frame:RegisterEvent("CHAT_MSG_WHISPER")
  frame:SetScript("OnEvent", function()
    if event == "CHAT_MSG_WHISPER" then
      local msg, sender = arg1, arg2
      OGRH.Invites.HandleWhisperAutoResponse(sender, msg)
    end
  end)
  
  -- Register events for party/raid changes
  frame:RegisterEvent("PARTY_MEMBERS_CHANGED")
  frame:RegisterEvent("RAID_ROSTER_UPDATE")
  
  frame:SetScript("OnEvent", function()
    if event == "PARTY_MEMBERS_CHANGED" or event == "RAID_ROSTER_UPDATE" then
      local numRaid = GetNumRaidMembers()
      local numParty = GetNumPartyMembers()
      
      -- Only auto-convert if we're within the invite window (60 seconds after clicking Invite All)
      local currentTime = GetTime()
      if OGRH.Invites.autoConvertExpiry and currentTime < OGRH.Invites.autoConvertExpiry then
        -- If someone joined the party and we're not in a raid yet, convert to raid
        if numRaid == 0 and numParty > 0 then
          ConvertToRaid()
          OGRH.Msg("Party detected - converting to raid...")
          -- Wait a moment then invite rest
          OGRH.Invites.scheduleRestOfInvites = true
        end
        
        -- If we just converted to raid and have pending invites, send them
        if numRaid > 0 and OGRH.Invites.scheduleRestOfInvites then
          OGRH.Invites.scheduleRestOfInvites = false
          OGRH.Msg("Raid formed - inviting remaining online players...")
          OGRH.Invites.InviteAllOnline()
        end
      end
      
      -- Always refresh the list to update statuses
      OGRH.Invites.RefreshPlayerList()
    end
  end)
  
  -- Enable ESC key to close
  OGRH.MakeFrameCloseOnEscape(frame, "OGRH_InvitesFrame")
  
  frame:Show()
  OGRH.Invites.RefreshPlayerList()
end

-- Show JSON Import Dialog
function OGRH.Invites.ShowJSONImportDialog(importType)
  -- importType: "invites" or "groups"
  importType = importType or "invites"
  
  -- Create or show existing dialog
  if OGRH_JSONImportDialog then
    -- Update dialog for current type
    local dialog = OGRH_JSONImportDialog
    dialog.importType = importType
    
    if importType == "groups" then
      dialog.titleText:SetText("Import Raid-Helper Groups")
      dialog.labelText:SetText("Paste Composition Tool JSON data below:")
      if dialog.raidNameInput then
        dialog.raidNameInput:SetText("")
        dialog.raidNameInput:Show()
      end
    else
      dialog.titleText:SetText("Import Raid-Helper Invites")
      dialog.labelText:SetText("Raid-Helper signup JSON data below:")
      if dialog.raidNameInput then
        dialog.raidNameInput:Hide()
      end
    end
    
    dialog.editBox:SetText("")
    dialog.statusText:SetText(" ")
    dialog:Show()
    return
  end
  
  -- Create dialog frame
  local dialog = CreateFrame("Frame", "OGRH_JSONImportDialog", UIParent)
  dialog:SetWidth(450)
  dialog:SetHeight(400)
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
  
  dialog.importType = importType
  
  -- Title
  local title = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOP", 0, -15)
  title:SetText(importType == "groups" and "Import Raid-Helper Groups" or "Import Raid-Helper Invites")
  dialog.titleText = title
  
  -- Instruction label
  local label = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  label:SetPoint("TOPLEFT", 15, -45)
  label:SetText(importType == "groups" and "Paste Composition Tool JSON data below:" or "Raid-Helper signup JSON data below:")
  dialog.labelText = label
  
  -- Raid Name input (only for Groups import)
  local raidNameInput
  if importType == "groups" then
    local raidNameLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    raidNameLabel:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -8)
    raidNameLabel:SetText("Raid Name:")
    
    local raidNameBox = CreateFrame("EditBox", nil, dialog)
    raidNameBox:SetPoint("LEFT", raidNameLabel, "RIGHT", 5, 0)
    raidNameBox:SetWidth(280)
    raidNameBox:SetHeight(20)
    raidNameBox:SetAutoFocus(false)
    raidNameBox:SetFontObject(ChatFontNormal)
    raidNameBox:SetBackdrop({
      bgFile = "Interface/Tooltips/UI-Tooltip-Background",
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
      edgeSize = 12,
      insets = {left = 4, right = 4, top = 4, bottom = 4}
    })
    raidNameBox:SetBackdropColor(0, 0, 0, 0.8)
    raidNameBox:SetTextInsets(5, 5, 0, 0)
    raidNameBox:SetScript("OnEscapePressed", function() raidNameBox:ClearFocus() end)
    raidNameInput = raidNameBox
    dialog.raidNameInput = raidNameInput
  end
  
  -- JSON input area using ScrollFrame
  local inputBackdrop = CreateFrame("Frame", nil, dialog)
  if importType == "groups" then
    inputBackdrop:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -36)
    inputBackdrop:SetHeight(222)
  else
    inputBackdrop:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -8)
    inputBackdrop:SetHeight(250)
  end
  inputBackdrop:SetWidth(420)
  inputBackdrop:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/DialogFrame/UI-DialogBox-Border",
    edgeSize = 16,
    insets = {left = 5, right = 5, top = 5, bottom = 5}
  })
  inputBackdrop:SetBackdropColor(0, 0, 0, 1)
  inputBackdrop:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
  
  -- ScrollFrame for text input
  local scrollFrame = CreateFrame("ScrollFrame", nil, inputBackdrop)
  scrollFrame:SetPoint("TOPLEFT", 8, -8)
  scrollFrame:SetPoint("BOTTOMRIGHT", -8, 8)
  
  -- Scroll child
  local scrollChild = CreateFrame("Frame", nil, scrollFrame)
  scrollFrame:SetScrollChild(scrollChild)
  scrollChild:SetWidth(400)
  scrollChild:SetHeight(500)
  
  -- EditBox for JSON input
  local editBox = CreateFrame("EditBox", nil, scrollChild)
  editBox:SetPoint("TOPLEFT", 0, 0)
  editBox:SetWidth(400)
  editBox:SetHeight(500)
  editBox:SetMultiLine(true)
  editBox:SetAutoFocus(false)
  editBox:SetMaxLetters(0)  -- No limit
  editBox:SetFontObject(GameFontHighlightSmall)
  editBox:SetTextInsets(5, 5, 3, 3)
  editBox:SetScript("OnEscapePressed", function() editBox:ClearFocus() end)
  dialog.editBox = editBox
  
  -- Status text
  local statusText = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  statusText:SetPoint("TOPLEFT", inputBackdrop, "BOTTOMLEFT", 0, -8)
  statusText:SetPoint("TOPRIGHT", inputBackdrop, "BOTTOMRIGHT", 0, -8)
  statusText:SetJustifyH("LEFT")
  statusText:SetText(" ")
  dialog.statusText = statusText
  
  -- Import button
  local importBtn = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
  importBtn:SetWidth(80)
  importBtn:SetHeight(24)
  importBtn:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -90, 15)
  importBtn:SetText("Import")
  if OGRH and OGRH.StyleButton then
    OGRH.StyleButton(importBtn)
  end
  
  importBtn:SetScript("OnClick", function()
    local jsonText = editBox:GetText()
    
    if not jsonText or jsonText == "" then
      statusText:SetText("|cffff0000Error: No JSON data provided|r")
      return
    end
    
    local parsedData, errorMsg
    
    if dialog.importType == "groups" then
      -- Parse Groups JSON
      parsedData, errorMsg = OGRH.Invites.ParseRaidHelperGroupsJSON(jsonText)
      
      if errorMsg then
        statusText:SetText("|cffff0000Error: " .. errorMsg .. "|r")
        return
      end
      
      -- Get custom raid name from input
      local customRaidName = "Raid"
      if dialog.raidNameInput then
        local inputName = dialog.raidNameInput:GetText()
        if inputName and inputName ~= "" then
          customRaidName = inputName
        end
      end
      
      -- Replace invites roster data with Groups data
      OGRH_SV.invites.raidhelperData = {
        id = parsedData.hash,
        name = customRaidName,
        players = parsedData.players
      }
      OGRH_SV.invites.raidhelperGroupsData = parsedData
      OGRH_SV.invites.currentSource = OGRH.Invites.SOURCE_TYPE.RAIDHELPER
      
      statusText:SetText("|cff00ff00Successfully imported " .. table.getn(parsedData.players) .. " players from Groups|r")
    else
      -- Parse Invites JSON
      parsedData, errorMsg = OGRH.Invites.ParseRaidHelperJSON(jsonText)
      
      if errorMsg then
        statusText:SetText("|cffff0000Error: " .. errorMsg .. "|r")
        return
      end
      
      -- Store data and set source
      OGRH_SV.invites.raidhelperData = parsedData
      OGRH_SV.invites.currentSource = OGRH.Invites.SOURCE_TYPE.RAIDHELPER
      
      -- Apply group assignments if groups data exists
      if OGRH_SV.invites.raidhelperGroupsData then
        OGRH.Invites.ApplyGroupAssignments()
      end
      
      statusText:SetText("|cff00ff00Successfully imported " .. table.getn(parsedData.players) .. " players from " .. (parsedData.name or "Raid-Helper") .. "|r")
    end
    
    -- Refresh main window if open
    if OGRH_InvitesFrame and OGRH_InvitesFrame:IsVisible() then
      OGRH.Invites.RefreshPlayerList()
      if OGRH_InvitesFrame.UpdateOrganizeButton then
        OGRH_InvitesFrame.UpdateOrganizeButton()
      end
    end
    
    -- Close dialog after 1.5 seconds
    OGRH.ScheduleTimer(function()
      dialog:Hide()
    end, 1.5, false)
  end)
  
  -- Cancel button
  local cancelBtn = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
  cancelBtn:SetWidth(80)
  cancelBtn:SetHeight(24)
  cancelBtn:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -10, 15)
  cancelBtn:SetText("Cancel")
  if OGRH and OGRH.StyleButton then
    OGRH.StyleButton(cancelBtn)
  end
  cancelBtn:SetScript("OnClick", function() dialog:Hide() end)
  
  -- Enable ESC to close
  OGRH.MakeFrameCloseOnEscape(dialog, "OGRH_JSONImportDialog")
  
  dialog:Show()
  editBox:SetFocus()
end

-- Create section header
function OGRH.Invites.CreateSectionHeader(parent, width, yOffset, sectionName, playerCount, color)
  local header = CreateFrame("Frame", nil, parent)
  header:SetWidth(width)
  header:SetHeight(25)
  header:SetPoint("TOPLEFT", 0, yOffset)
  
  -- Background
  header:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = nil,
    tile = false,
    insets = {left = 0, right = 0, top = 0, bottom = 0}
  })
  header:SetBackdropColor(color.r * 0.3, color.g * 0.3, color.b * 0.3, 0.5)
  
  -- Section title text
  local text = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  text:SetPoint("LEFT", 10, 0)
  text:SetText(sectionName)
  text:SetTextColor(color.r, color.g, color.b)
  
  -- Count text
  local countText = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  countText:SetPoint("RIGHT", -10, 0)
  countText:SetText("(" .. playerCount .. ")")
  countText:SetTextColor(color.r * 0.8, color.g * 0.8, color.b * 0.8)
  
  return header
end

-- Refresh the player list
function OGRH.Invites.RefreshPlayerList()
  if not OGRH_InvitesFrame then return end
  
  local scrollChild = OGRH_InvitesFrame.scrollChild
  
  -- Clear existing rows
  if scrollChild.rows then
    for _, row in ipairs(scrollChild.rows) do
      row:Hide()
      row:SetParent(nil)
    end
  end
  scrollChild.rows = {}
  
  -- Get roster players based on current source
  local allPlayers = OGRH.Invites.GetRosterPlayers()
  
  -- Separate into sections: Active, Benched, Absent
  local activePlayers = {}
  local benchedPlayers = {}
  local absentPlayers = {}
  
  for _, playerData in ipairs(allPlayers) do
    -- Update class and status info
    playerData = OGRH.Invites.UpdatePlayerClass(playerData)
    playerData.status, playerData.online = OGRH.Invites.GetPlayerStatus(playerData.name)
    
    -- Categorize player
    if playerData.absent then
      table.insert(absentPlayers, playerData)
    elseif playerData.bench then
      table.insert(benchedPlayers, playerData)
    else
      table.insert(activePlayers, playerData)
    end
  end
  
  -- Sort each section alphabetically
  table.sort(activePlayers, function(a, b) return a.name < b.name end)
  table.sort(benchedPlayers, function(a, b) return a.name < b.name end)
  table.sort(absentPlayers, function(a, b) return a.name < b.name end)
  
  -- Filter active players to only those not in raid
  local playersNotInRaid = {}
  for _, playerData in ipairs(activePlayers) do
    if not OGRH.Invites.IsPlayerInRaid(playerData.name) then
      table.insert(playersNotInRaid, playerData)
    end
  end
  
  -- Update stats text
  local totalCount = table.getn(activePlayers) + table.getn(benchedPlayers) + table.getn(absentPlayers)
  local notInRaidCount = table.getn(playersNotInRaid)
  local inRaidCount = table.getn(activePlayers) - notInRaidCount
  local benchCount = table.getn(benchedPlayers)
  local absentCount = table.getn(absentPlayers)
  
  -- Update title and info text based on current source
  local currentSource = OGRH_SV.invites.currentSource
  local sourceName = "Unknown"
  local sourceColor = "|cffffffff"
  
  if currentSource == OGRH.Invites.SOURCE_TYPE.ROLLFOR then
    sourceName = "RollFor Soft-Res"
    sourceColor = "|cff00ff00"
    
    -- Update title with raid metadata
    local meta = OGRH.Invites.GetMetadata()
    if meta.instance and OGRH_InvitesFrame.titleText then
      local raidName = OGRH.Invites.GetInstanceName(meta.instance)
      OGRH_InvitesFrame.titleText:SetText("Raid Invites - " .. raidName .. " (" .. tostring(meta.instance) .. ")")
    end
  elseif currentSource == OGRH.Invites.SOURCE_TYPE.RAIDHELPER then
    sourceName = "Raid-Helper"
    sourceColor = "|cff00ccff"
    
    -- Show if groups data is imported
    if OGRH_SV.invites.raidhelperGroupsData then
      sourceName = sourceName .. " (Groups)"
    end
    
    -- Update title with raid-helper data
    if OGRH_SV.invites.raidhelperData and OGRH_SV.invites.raidhelperData.name and OGRH_InvitesFrame.titleText then
      OGRH_InvitesFrame.titleText:SetText("Raid Invites - " .. OGRH_SV.invites.raidhelperData.name)
    end
  end
  
  if OGRH_InvitesFrame.infoText then
    local infoStr = "Source: " .. sourceColor .. sourceName .. "|r | "
    infoStr = infoStr .. "Active: |cff00ff00" .. table.getn(activePlayers) .. "|r"
    if benchCount > 0 then
      infoStr = infoStr .. " | Benched: |cffffff00" .. benchCount .. "|r"
    end
    if absentCount > 0 then
      infoStr = infoStr .. " | Absent: |cffff0000" .. absentCount .. "|r"
    end
    OGRH_InvitesFrame.infoText:SetText(infoStr)
  end
  
  -- Check if no data loaded
  if totalCount == 0 then
    if not RollFor then
      OGRH_InvitesFrame.infoText:SetText("RollFor addon not detected. Please install and load RollFor.")
    elseif not RollFor.unfiltered_softres and not RollFor.softres then
      OGRH_InvitesFrame.infoText:SetText("RollFor is loading... please wait a moment and refresh.")
    else
      OGRH_InvitesFrame.infoText:SetText("No soft-res data found. Import soft-res in RollFor first (/sr).")
    end
    OGRH_InvitesFrame.statsText:SetText("0 players")
    scrollChild:SetHeight(1)
    OGRH_InvitesFrame.scrollBar:Hide()
    return
  end
  
  OGRH_InvitesFrame.statsText:SetText(
    notInRaidCount .. " players not in raid\n(" .. inRaidCount .. " already in raid, " .. benchCount .. " benched, " .. absentCount .. " absent)"
  )
  
  if totalCount == 0 then
    scrollChild:SetHeight(1)
    OGRH_InvitesFrame.scrollBar:Hide()
    return
  end
  
  -- Create rows with section headers
  local yOffset = -5
  local rowHeight = OGRH.LIST_ITEM_HEIGHT
  local rowSpacing = OGRH.LIST_ITEM_SPACING
  
  -- Helper function to render a player row
  local function RenderPlayerRow(playerData, isDisabled)
    isDisabled = isDisabled or false
    
    -- Create styled list item
    local row = OGRH.CreateStyledListItem(scrollChild, OGRH_InvitesFrame.contentWidth, rowHeight, "Button")
    row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, yOffset)
    
    -- Set background color based on status
    if playerData.status == STATUS.IN_RAID then
      OGRH.SetListItemColor(row, 0.1, 0.3, 0.1, 0.5)
    elseif playerData.status == STATUS.DECLINED then
      OGRH.SetListItemColor(row, 0.3, 0.1, 0.1, 0.5)
    elseif playerData.status == STATUS.INVITED then
      OGRH.SetListItemColor(row, 0.2, 0.2, 0.3, 0.5)
    elseif playerData.bench then
      OGRH.SetListItemColor(row, 0.3, 0.25, 0.1, 0.4)  -- Yellow/orange tint for benched
    elseif playerData.absent then
      OGRH.SetListItemColor(row, 0.3, 0.1, 0.1, 0.4)  -- Red tint for absent
    end
    -- For OFFLINE and default: use the standard INACTIVE color from template
    
    -- Player name with class color
    local classColor = playerData.class and RAID_CLASS_COLORS[playerData.class] or {r=1, g=1, b=1}
    local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameText:SetPoint("LEFT", row, "LEFT", 5, 0)
    nameText:SetWidth(130)
    nameText:SetJustifyH("LEFT")
    nameText:SetTextColor(classColor.r, classColor.g, classColor.b)
    nameText:SetText(playerData.name)
    
    -- Role (show OGRH bucket instead of RollFor spec)
    local roleText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    roleText:SetPoint("LEFT", row, "LEFT", 140, 0)
    roleText:SetWidth(80)
    roleText:SetJustifyH("LEFT")
    local displayRole = playerData.role or "Unknown"
    -- Format for display: TANKS -> Tank, HEALERS -> Healer, MELEE -> Melee, RANGED -> Ranged
    if displayRole == "TANKS" then
      displayRole = "Tank"
    elseif displayRole == "HEALERS" then
      displayRole = "Healer"
    elseif displayRole == "MELEE" then
      displayRole = "Melee"
    elseif displayRole == "RANGED" then
      displayRole = "Ranged"
    end
    -- Append group number if available
    if playerData.group and playerData.group >= 1 and playerData.group <= 8 then
      displayRole = displayRole .. " (" .. playerData.group .. ")"
    end
    roleText:SetText(displayRole)
    
    -- Status
    local statusText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusText:SetPoint("LEFT", row, "LEFT", 225, 0)
    statusText:SetWidth(90)
    statusText:SetJustifyH("LEFT")
    if playerData.bench then
      statusText:SetText("|cffffff00Benched|r")
    elseif playerData.absent then
      statusText:SetText("|cffff0000Absent|r")
    elseif playerData.status == STATUS.OFFLINE then
      statusText:SetText("|cff888888Offline|r")
    elseif playerData.status == STATUS.INVITED then
      statusText:SetText("|cff8888ffInvited|r")
    elseif playerData.status == STATUS.DECLINED then
      statusText:SetText("|cffff8888Declined|r")
    elseif playerData.online then
      statusText:SetText("|cff88ff88Online|r")
    else
      statusText:SetText("|cffccccccUnknown|r")
    end
    
    -- Invite button
    local inviteBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    inviteBtn:SetWidth(50)
    inviteBtn:SetHeight(20)
    inviteBtn:SetPoint("LEFT", row, "LEFT", 320, 0)
    inviteBtn:SetText("Invite")
    OGRH.StyleButton(inviteBtn)
    local playerName = playerData.name
    inviteBtn:SetScript("OnClick", function()
      OGRH.Invites.InvitePlayer(playerName)
    end)
    -- Disable if offline, benched, or absent
    if playerData.status == STATUS.OFFLINE or isDisabled then
      inviteBtn:Disable()
    end
    
    -- Whisper button
    local whisperBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    whisperBtn:SetWidth(50)
    whisperBtn:SetHeight(20)
    whisperBtn:SetPoint("LEFT", inviteBtn, "RIGHT", 2, 0)
    whisperBtn:SetText("Msg")
    OGRH.StyleButton(whisperBtn)
    whisperBtn:SetScript("OnClick", function()
      OGRH.Invites.WhisperPlayer(playerName)
    end)
    -- Disable if offline, benched, or absent
    if playerData.status == STATUS.OFFLINE or isDisabled then
      whisperBtn:Disable()
    end
    
    table.insert(scrollChild.rows, row)
    yOffset = yOffset - rowHeight - rowSpacing
  end
  
  -- Render ACTIVE ROSTER section
  if notInRaidCount > 0 then
    local header = OGRH.Invites.CreateSectionHeader(scrollChild, OGRH_InvitesFrame.contentWidth, yOffset, "ACTIVE ROSTER", notInRaidCount, {r=0.4, g=1.0, b=0.4})
    table.insert(scrollChild.rows, header)
    yOffset = yOffset - 30
    
    for _, playerData in ipairs(playersNotInRaid) do
      RenderPlayerRow(playerData, false)
    end
  end
  
  -- Render BENCHED section
  if benchCount > 0 then
    yOffset = yOffset - 10  -- Extra gap before section
    local header = OGRH.Invites.CreateSectionHeader(scrollChild, OGRH_InvitesFrame.contentWidth, yOffset, "BENCHED PLAYERS", benchCount, {r=1.0, g=0.8, b=0.2})
    table.insert(scrollChild.rows, header)
    yOffset = yOffset - 30
    
    for _, playerData in ipairs(benchedPlayers) do
      RenderPlayerRow(playerData, true)
    end
  end
  
  -- Render ABSENT section
  if absentCount > 0 then
    yOffset = yOffset - 10  -- Extra gap before section
    local header = OGRH.Invites.CreateSectionHeader(scrollChild, OGRH_InvitesFrame.contentWidth, yOffset, "ABSENT PLAYERS", absentCount, {r=1.0, g=0.3, b=0.3})
    table.insert(scrollChild.rows, header)
    yOffset = yOffset - 30
    
    for _, playerData in ipairs(absentPlayers) do
      RenderPlayerRow(playerData, true)
    end
  end
  
  -- Update scroll child height
  local contentHeight = math.abs(yOffset) + 5
  scrollChild:SetHeight(contentHeight)
  
  -- Update scrollbar
  local scrollFrame = OGRH_InvitesFrame.scrollFrame
  local scrollBar = OGRH_InvitesFrame.scrollBar
  local scrollFrameHeight = scrollFrame:GetHeight()
  
  if contentHeight > scrollFrameHeight then
    scrollBar:Show()
    scrollBar:SetMinMaxValues(0, contentHeight - scrollFrameHeight)
  else
    scrollBar:Hide()
    scrollFrame:SetVerticalScroll(0)
  end
end

-- Invite all online players
function OGRH.Invites.InviteAllOnline()
  local players = OGRH.Invites.GetSoftResPlayers()
  local inviteCount = 0
  local numRaid = GetNumRaidMembers()
  local numParty = GetNumPartyMembers()
  local wasSolo = (numRaid == 0 and numParty == 0)
  
  -- Enable auto-convert for 60 seconds
  OGRH.Invites.autoConvertExpiry = GetTime() + 60
  
  for _, playerData in ipairs(players) do
    if not OGRH.Invites.IsPlayerInRaid(playerData.name) then
      local status, online = OGRH.Invites.GetPlayerStatus(playerData.name)
      if online and status ~= STATUS.INVITED and status ~= STATUS.DECLINED then
        -- If we started solo, only send 4 invites initially
        if wasSolo and inviteCount >= 4 then
          break
        end
        
        OGRH.Invites.InvitePlayer(playerData.name)
        inviteCount = inviteCount + 1
      end
    end
  end
  
  if inviteCount > 0 then
    if wasSolo and inviteCount >= 4 then
      OGRH.Msg("Sent " .. inviteCount .. " invites. Will auto-convert to raid and invite rest when someone joins (60s window).")
    else
      OGRH.Msg("Sent invites to " .. inviteCount .. " online players.")
    end
    OGRH.Invites.RefreshPlayerList()
  else
    OGRH.Msg("No online players to invite.")
  end
end

-- Show whisper dialog
function OGRH.Invites.ShowWhisperDialog(playerName)
  if OGRH_WhisperDialog then
    OGRH_WhisperDialog.targetPlayer = playerName
    OGRH_WhisperDialog.titleText:SetText("Whisper " .. playerName)
    OGRH_WhisperDialog.messageInput:SetText("")
    OGRH_WhisperDialog:Show()
    OGRH_WhisperDialog.messageInput:SetFocus()
    return
  end
  
  -- Create dialog
  local dialog = CreateFrame("Frame", "OGRH_WhisperDialog", UIParent)
  dialog:SetWidth(400)
  dialog:SetHeight(200)
  dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  dialog:SetFrameStrata("FULLSCREEN_DIALOG")
  dialog:EnableMouse(true)
  dialog:SetMovable(true)
  dialog:RegisterForDrag("LeftButton")
  dialog:SetScript("OnDragStart", function() dialog:StartMoving() end)
  dialog:SetScript("OnDragStop", function() dialog:StopMovingOrSizing() end)
  
  dialog.targetPlayer = playerName
  
  -- Backdrop
  dialog:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 12,
    insets = {left = 4, right = 4, top = 4, bottom = 4}
  })
  dialog:SetBackdropColor(0, 0, 0, 0.9)
  
  -- Title
  local titleText = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  titleText:SetPoint("TOP", 0, -15)
  titleText:SetText("Whisper " .. playerName)
  dialog.titleText = titleText
  
  -- Message label
  local msgLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  msgLabel:SetPoint("TOPLEFT", 20, -50)
  msgLabel:SetText("Message:")
  
  -- Message input (multiline)
  local msgBackdrop = CreateFrame("Frame", nil, dialog)
  msgBackdrop:SetPoint("TOPLEFT", 20, -75)
  msgBackdrop:SetPoint("TOPRIGHT", -20, -75)
  msgBackdrop:SetHeight(80)
  msgBackdrop:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 12,
    insets = {left = 4, right = 4, top = 4, bottom = 4}
  })
  msgBackdrop:SetBackdropColor(0, 0, 0, 0.8)
  
  local messageInput = CreateFrame("EditBox", nil, msgBackdrop)
  messageInput:SetPoint("TOPLEFT", 8, -8)
  messageInput:SetPoint("BOTTOMRIGHT", -8, 8)
  messageInput:SetMultiLine(true)
  messageInput:SetAutoFocus(true)
  messageInput:SetFontObject(ChatFontNormal)
  messageInput:SetText("Hey! We have a raid spot for you. Are you available?")
  messageInput:SetScript("OnEscapePressed", function()
    dialog:Hide()
  end)
  dialog.messageInput = messageInput
  
  -- Send button
  local sendBtn = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
  sendBtn:SetWidth(80)
  sendBtn:SetHeight(24)
  sendBtn:SetPoint("BOTTOMRIGHT", -20, 15)
  sendBtn:SetText("Send")
  OGRH.StyleButton(sendBtn)
  sendBtn:SetScript("OnClick", function()
    local msg = messageInput:GetText()
    if msg and msg ~= "" then
      OGRH.Invites.WhisperPlayer(dialog.targetPlayer, msg)
      dialog:Hide()
    end
  end)
  
  -- Cancel button
  local cancelBtn = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
  cancelBtn:SetWidth(80)
  cancelBtn:SetHeight(24)
  cancelBtn:SetPoint("RIGHT", sendBtn, "LEFT", -5, 0)
  cancelBtn:SetText("Cancel")
  OGRH.StyleButton(cancelBtn)
  cancelBtn:SetScript("OnClick", function()
    dialog:Hide()
  end)
  
  -- Enable ESC key to close
  OGRH.MakeFrameCloseOnEscape(dialog, "OGRH_WhisperDialog")
  
  dialog:Show()
  messageInput:SetFocus()
end

-- ============================================================================
-- INVITE MODE: Timer-based automated invites
-- ============================================================================

function OGRH.Invites.ToggleInviteMode()
  local inviteMode = OGRH_SV.invites.inviteMode
  inviteMode.enabled = not inviteMode.enabled
  
  if inviteMode.enabled then
    inviteMode.lastInviteTime = 0  -- Force immediate first invite
    inviteMode.invitedCount = 0
    inviteMode.totalPlayers = 0
    
    -- Count total players (excluding benched/absent)
    local players = OGRH.Invites.GetRosterPlayers()
    for _, player in ipairs(players) do
      if not player.bench and not player.absent then
        inviteMode.totalPlayers = inviteMode.totalPlayers + 1
      end
    end
    
    -- Get raid name for announcement
    local raidName = "Raid"
    local currentSource = OGRH_SV.invites.currentSource
    if currentSource == OGRH.Invites.SOURCE_TYPE.RAIDHELPER then
      if OGRH_SV.invites.raidhelperData and OGRH_SV.invites.raidhelperData.name then
        raidName = OGRH_SV.invites.raidhelperData.name
      end
    elseif currentSource == OGRH.Invites.SOURCE_TYPE.ROLLFOR then
      local meta = OGRH.Invites.GetMetadata()
      if meta.instance then
        raidName = OGRH.Invites.GetInstanceName(meta.instance)
      end
    end
    
    -- Announce to guild chat
    SendChatMessage("Starting invites for " .. raidName .. ". Whisper me if you're signed up and need an invite!", "GUILD")
    
    -- Show auxiliary panel
    OGRH.Invites.ShowInviteModePanel()
    
    -- Do first batch invite immediately
    OGRH.Invites.DoInviteCycle()
  else
    -- Hide auxiliary panel
    if OGRH_InviteModePanel then
      OGRH_InviteModePanel:Hide()
    end
  end
  
  -- Update button text
  if OGRH_InvitesFrame and OGRH_InvitesFrame.inviteModeBtn then
    OGRH_InvitesFrame.inviteModeBtn:SetText(inviteMode.enabled and "Stop Invite Mode" or "Start Invite Mode")
  end
end

function OGRH.Invites.DoInviteCycle()
  local inviteMode = OGRH_SV.invites.inviteMode
  local players = OGRH.Invites.GetRosterPlayers()
  local invitedThisCycle = 0
  
  -- Check current group status
  local inRaid = (GetNumRaidMembers() > 0)
  local inParty = (GetNumPartyMembers() > 0)
  local isSolo = not inRaid and not inParty
  
  -- If we're in a party (not raid), convert to raid first
  if inParty and not inRaid then
    ConvertToRaid()
    return -- Let conversion complete, we'll invite next cycle
  end
  
  -- Invite players who aren't in raid, aren't benched/absent, and are online
  for _, player in ipairs(players) do
    if not player.bench and not player.absent and not OGRH.Invites.IsPlayerInRaid(player.name) then
      -- Check if player is online
      local status, online = OGRH.Invites.GetPlayerStatus(player.name)
      if online then
        InviteByName(player.name)
        invitedThisCycle = invitedThisCycle + 1
        
        -- If solo, only invite 4 to form party first
        if isSolo and invitedThisCycle >= 4 then
          break
        end
      end
    end
  end
  
  inviteMode.lastInviteTime = GetTime()
  
  -- Update panel if visible
  if OGRH_InviteModePanel and OGRH_InviteModePanel:IsVisible() then
    OGRH.Invites.UpdateInviteModePanel()
  end
end

function OGRH.Invites.ShowInviteModePanel()
  local panel = OGRH_InviteModePanel
  if not panel then
    -- Create auxiliary panel (similar to OGRH_RecruitingPanel)
    panel = CreateFrame("Frame", "OGRH_InviteModePanel", UIParent)
    local mainWidth = OGRH_Main and OGRH_Main:GetWidth() or 240
    panel:SetWidth(mainWidth)
    panel:SetHeight(65)  -- Taller than recruiting panel to fit two progress bars
    panel:SetFrameStrata("MEDIUM")
    panel:SetBackdrop({
      bgFile = "Interface/Tooltips/UI-Tooltip-Background",
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
      tile = true,
      tileSize = 16,
      edgeSize = 16,
      insets = {left = 4, right = 4, top = 4, bottom = 4}
    })
    panel:SetBackdropColor(0, 0, 0, 0.85)
    panel:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    
    -- Title and Stop button on same line
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -8)
    title:SetText("Invite Mode")
    
    -- Stop button
    local stopBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    stopBtn:SetWidth(50)
    stopBtn:SetHeight(18)
    stopBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -6)
    stopBtn:SetText("Stop")
    if OGRH and OGRH.StyleButton then
      OGRH.StyleButton(stopBtn)
    end
    stopBtn:SetScript("OnClick", function()
      OGRH.Invites.ToggleInviteMode()
    end)
    
    -- Next invite countdown bar
    local timerBar = CreateFrame("StatusBar", nil, panel)
    timerBar:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    timerBar:SetPoint("RIGHT", panel, "RIGHT", -8, 0)
    timerBar:SetHeight(10)
    timerBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    timerBar:SetStatusBarColor(0.2, 0.8, 0.2, 1)
    timerBar:SetMinMaxValues(0, 1)
    timerBar:SetValue(0)
    panel.timerBar = timerBar
    
    -- Timer text (centered on bar)
    local timerText = timerBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    timerText:SetPoint("CENTER", timerBar, "CENTER", 0, 0)
    timerText:SetText("0:00")
    panel.timerText = timerText
    
    -- Progress bar (players invited)
    local progressBar = CreateFrame("StatusBar", nil, panel)
    progressBar:SetPoint("TOPLEFT", timerBar, "BOTTOMLEFT", 0, -4)
    progressBar:SetPoint("RIGHT", panel, "RIGHT", -8, 0)
    progressBar:SetHeight(10)
    progressBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    progressBar:SetStatusBarColor(0.2, 0.6, 1.0, 1)
    progressBar:SetMinMaxValues(0, 100)
    progressBar:SetValue(0)
    panel.progressBar = progressBar
    
    -- Progress text (centered on bar)
    local progressText = progressBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    progressText:SetPoint("CENTER", progressBar, "CENTER", 0, 0)
    progressText:SetText("0 / 0")
    panel.progressText = progressText
    
    -- Update script
    panel:SetScript("OnUpdate", function()
      if not OGRH_SV.invites.inviteMode.enabled then
        panel:Hide()
        return
      end
      
      local inviteMode = OGRH_SV.invites.inviteMode
      local now = GetTime()
      local elapsed = now - inviteMode.lastInviteTime
      
      -- Use 10-second interval until raid is formed, then use configured interval
      local currentInterval
      if GetNumRaidMembers() > 0 then
        currentInterval = inviteMode.interval
      else
        currentInterval = 10 -- Fast invites until raid forms
      end
      
      local remaining = currentInterval - elapsed
      
      if remaining <= 0 then
        -- Time to invite
        OGRH.Invites.DoInviteCycle()
        -- Note: DoInviteCycle updates lastInviteTime
      end
      
      -- Recalculate after potential DoInviteCycle call
      elapsed = now - inviteMode.lastInviteTime
      
      -- Recalculate current interval in case raid status changed
      if GetNumRaidMembers() > 0 then
        currentInterval = inviteMode.interval
      else
        currentInterval = 10
      end
      
      remaining = currentInterval - elapsed
      
      -- Update countdown bar and text
      local progress = elapsed / currentInterval
      panel.timerBar:SetValue(progress)
      
      local minutes = math.floor(remaining / 60)
      local seconds = math.floor(mod(remaining, 60))
      local secondsStr = tostring(seconds)
      if seconds < 10 then
        secondsStr = "0" .. secondsStr
      end
      panel.timerText:SetText(tostring(minutes) .. ":" .. secondsStr)
      
      -- Update progress display (only every 30 frames to reduce spam)
      if not panel.updateCounter then panel.updateCounter = 0 end
      panel.updateCounter = panel.updateCounter + 1
      if panel.updateCounter >= 30 then
        panel.updateCounter = 0
        OGRH.Invites.UpdateInviteModePanel()
      end
    end)
    
    -- Register with auxiliary panel system (priority 16 - after recruiting at 15)
    panel:SetScript("OnShow", function()
      if OGRH.RegisterAuxiliaryPanel then
        OGRH.RegisterAuxiliaryPanel(this, 16)
      end
    end)
    
    panel:SetScript("OnHide", function()
      if OGRH.UnregisterAuxiliaryPanel then
        OGRH.UnregisterAuxiliaryPanel(this)
      end
    end)
    
    OGRH_InviteModePanel = panel
  end
  
  panel:Show()
  
  -- Manually trigger registration and positioning
  if OGRH.RegisterAuxiliaryPanel then
    OGRH.RegisterAuxiliaryPanel(panel, 16)
  end
  if OGRH.RepositionAuxiliaryPanels then
    OGRH.RepositionAuxiliaryPanels()
  end
end

function OGRH.Invites.UpdateInviteModePanel()
  local panel = OGRH_InviteModePanel
  if not panel or not panel:IsVisible() then return end
  
  local inviteMode = OGRH_SV.invites.inviteMode
  
  -- Count how many roster players are now in raid
  local inRaidCount = 0
  local notInRaidCount = 0
  local players = OGRH.Invites.GetRosterPlayers()
  for _, player in ipairs(players) do
    if not player.bench and not player.absent then
      if OGRH.Invites.IsPlayerInRaid(player.name) then
        inRaidCount = inRaidCount + 1
      else
        notInRaidCount = notInRaidCount + 1
      end
    end
  end
  
  inviteMode.invitedCount = inRaidCount
  
  -- Update progress bar
  if inviteMode.totalPlayers > 0 then
    panel.progressBar:SetMinMaxValues(0, inviteMode.totalPlayers)
    panel.progressBar:SetValue(inviteMode.invitedCount)
  end
  
  panel.progressText:SetText(string.format("%d / %d", inviteMode.invitedCount, inviteMode.totalPlayers))
  
  -- Auto-stop only when everyone is actually in the raid
  if notInRaidCount == 0 and inviteMode.totalPlayers > 0 then
    OGRH.Invites.ToggleInviteMode()
  end
end

-- Handle party invite declined event and whispers
local inviteEventFrame = CreateFrame("Frame")
inviteEventFrame:RegisterEvent("PARTY_INVITE_REQUEST")
inviteEventFrame:RegisterEvent("RAID_ROSTER_UPDATE")
inviteEventFrame:RegisterEvent("CHAT_MSG_WHISPER")
inviteEventFrame:SetScript("OnEvent", function()
  if event == "PARTY_INVITE_REQUEST" then
    -- Track declined invites
    -- Note: WoW 1.12 doesn't have a specific "declined" event
    -- We'll track this indirectly
  elseif event == "RAID_ROSTER_UPDATE" then
    -- Detect new members and sync their roles during invite mode
    if OGRH_SV.invites.inviteMode.enabled then
      -- Track who was in raid before
      if not OGRH.Invites.previousRaidMembers then
        OGRH.Invites.previousRaidMembers = {}
      end
      
      local currentMembers = {}
      local numRaid = GetNumRaidMembers()
      for i = 1, numRaid do
        local name = GetRaidRosterInfo(i)
        if name then
          name = NormalizeName(name)
          currentMembers[name] = true
          
          -- If this player wasn't in raid before, sync their role
          if not OGRH.Invites.previousRaidMembers[name] then
            OGRH.Invites.SyncPlayerRole(name)
          end
        end
      end
      
      OGRH.Invites.previousRaidMembers = currentMembers
      
      -- Auto-organize players when they join the raid (only for Raid-Helper source)
      if OGRH_SV.invites.currentSource == OGRH.Invites.SOURCE_TYPE.RAIDHELPER then
        OGRH.Invites.AutoOrganizeNewMembers()
      end
    end
    
    -- Refresh the window if it's open
    if OGRH_InvitesFrame and OGRH_InvitesFrame:IsVisible() then
      OGRH.Invites.RefreshPlayerList()
    end
  elseif event == "CHAT_MSG_WHISPER" then
    -- Auto-respond to whispers for benched/absent players
    local message = arg1
    local sender = arg2
    OGRH.Invites.HandleWhisperAutoResponse(sender, message)
  end
end)

-- Sync player role to RolesUI when they join raid during invite mode
function OGRH.Invites.SyncPlayerRole(playerName)
  if not OGRH_SV.invites.inviteMode.enabled then
    return -- Only sync during invite mode
  end
  
  -- Get player's role from roster data
  local players = OGRH.Invites.GetRosterPlayers()
  for _, player in ipairs(players) do
    if NormalizeName(player.name) == NormalizeName(playerName) then
      if player.role and OGRH.RolesUI and OGRH.RolesUI.SetPlayerRole then
        OGRH.RolesUI.SetPlayerRole(playerName, player.role)
      end
      return
    end
  end
end

-- Whisper auto-response for benched/absent players, auto-invite for active roster members
function OGRH.Invites.HandleWhisperAutoResponse(sender, message)
  if not sender or not message then 
    return 
  end
  
  -- Get roster players
  local players = OGRH.Invites.GetRosterPlayers()
  local senderNormalized = NormalizeName(sender)
  
  -- Check if sender is in roster
  for _, player in ipairs(players) do
    if NormalizeName(player.name) == senderNormalized then
      if player.bench then
        SendChatMessage("You are currently on the bench for this raid. Please check with the raid leader if you want to participate.", "WHISPER", nil, sender)
        return
      elseif player.absent then
        SendChatMessage("You are marked as absent for this raid. If you can attend, please update your status and whisper the raid leader.", "WHISPER", nil, sender)
        return
      end
      
      -- Player is on active roster - check if invite mode is active
      if OGRH_SV.invites.inviteMode.enabled then
        local inRaid = OGRH.Invites.IsPlayerInRaid(senderNormalized)
        
        -- Only auto-invite if they're not already in raid
        if not inRaid then
          OGRH.Invites.InvitePlayer(senderNormalized)
        end
      end
      return
    end
  end
end

-- Helper function to check if player is in combat
local function IsPlayerInCombat(raidIndex)
  if not raidIndex or raidIndex < 1 or raidIndex > 40 then
    return false
  end
  local unitId = "raid" .. raidIndex
  return UnitAffectingCombat(unitId)
end

-- Helper function to count players in a group
local function GetGroupPlayerCount(groupNum)
  local count = 0
  local numRaid = GetNumRaidMembers()
  for i = 1, numRaid do
    local _, _, currentGroup = GetRaidRosterInfo(i)
    if currentGroup == groupNum then
      count = count + 1
    end
  end
  return count
end

-- Helper function to find a fallback group (tries 8, then 7, then 6, etc.)
local function FindAvailableGroup()
  for groupNum = 8, 1, -1 do
    if GetGroupPlayerCount(groupNum) < 5 then
      return groupNum
    end
  end
  return nil -- All groups full
end

-- Helper function to find someone in a group who doesn't belong there
local function FindMisplacedPlayerInGroup(groupNum, raidhelperData)
  local numRaid = GetNumRaidMembers()
  for i = 1, numRaid do
    local name, _, currentGroup = GetRaidRosterInfo(i)
    if currentGroup == groupNum and not IsPlayerInCombat(i) then
      -- Check if this player has a different group assignment
      local shouldBeHere = false
      local playerTargetGroup = nil
      
      for _, player in ipairs(raidhelperData.players) do
        if NormalizeName(player.name) == NormalizeName(name) then
          if player.group and tonumber(player.group) == groupNum then
            shouldBeHere = true
          elseif player.group then
            playerTargetGroup = tonumber(player.group)
          end
          break
        end
      end
      
      if not shouldBeHere then
        return i, name, playerTargetGroup
      end
    end
  end
  return nil, nil, nil
end

-- Organize raid groups based on Raid-Helper assignments
-- Auto-organize new raid members (silent version)
function OGRH.Invites.AutoOrganizeNewMembers()
  if OGRH_SV.invites.currentSource ~= OGRH.Invites.SOURCE_TYPE.RAIDHELPER then
    return
  end
  
  local raidhelperData = OGRH_SV.invites.raidhelperData
  if not raidhelperData or not raidhelperData.players then
    return
  end
  
  -- Check if we're raid leader or assistant
  if not IsRaidLeader() and not IsRaidOfficer() then
    return
  end
  
  -- Organize players by their assigned group
  for _, player in ipairs(raidhelperData.players) do
    if player.group and not player.bench and not player.absent then
      local targetGroup = tonumber(player.group)
      if targetGroup and targetGroup >= 1 and targetGroup <= 8 then
        -- Find player in raid
        local numRaid = GetNumRaidMembers()
        for i = 1, numRaid do
          local name, _, currentGroup = GetRaidRosterInfo(i)
          if name and NormalizeName(name) == NormalizeName(player.name) then
            -- Skip if already in correct group
            if currentGroup == targetGroup then
              break
            end
            
            -- Skip if player is in combat
            if IsPlayerInCombat(i) then
              break
            end
            
            -- Check if target group has room
            if GetGroupPlayerCount(targetGroup) < 5 then
              -- Group has room, just move
              SetRaidSubgroup(i, targetGroup)
            else
              -- Group is full, find someone to swap
              local swapIndex, swapName, swapTargetGroup = FindMisplacedPlayerInGroup(targetGroup, raidhelperData)
              
              if swapIndex then
                -- Move the misplaced player first
                if swapTargetGroup and swapTargetGroup >= 1 and swapTargetGroup <= 8 and GetGroupPlayerCount(swapTargetGroup) < 5 then
                  -- Move to their correct group
                  SetRaidSubgroup(swapIndex, swapTargetGroup)
                else
                  -- Move to fallback group
                  local fallbackGroup = FindAvailableGroup()
                  if fallbackGroup then
                    SetRaidSubgroup(swapIndex, fallbackGroup)
                  end
                end
                
                -- Now move our player to the target group
                SetRaidSubgroup(i, targetGroup)
              end
            end
            break
          end
        end
      end
    end
  end
end

-- Manual organize command (with feedback)
function OGRH.Invites.OrganizeRaidGroups()
  if OGRH_SV.invites.currentSource ~= OGRH.Invites.SOURCE_TYPE.RAIDHELPER then
    return
  end
  
  local raidhelperData = OGRH_SV.invites.raidhelperData
  if not raidhelperData or not raidhelperData.players then
    return
  end
  
  -- Check if we're raid leader or assistant
  if not IsRaidLeader() and not IsRaidOfficer() then
    return
  end
  
  local movedCount = 0
  local skippedCombat = 0
  
  -- Organize players by their assigned group
  for _, player in ipairs(raidhelperData.players) do
    if player.group and not player.bench and not player.absent then
      local targetGroup = tonumber(player.group)
      if targetGroup and targetGroup >= 1 and targetGroup <= 8 then
        -- Find player in raid
        local numRaid = GetNumRaidMembers()
        for i = 1, numRaid do
          local name, _, currentGroup = GetRaidRosterInfo(i)
          if name and NormalizeName(name) == NormalizeName(player.name) then
            -- Skip if already in correct group
            if currentGroup == targetGroup then
              break
            end
            
            -- Skip if player is in combat
            if IsPlayerInCombat(i) then
              skippedCombat = skippedCombat + 1
              break
            end
            
            -- Check if target group has room
            if GetGroupPlayerCount(targetGroup) < 5 then
              -- Group has room, just move
              SetRaidSubgroup(i, targetGroup)
              movedCount = movedCount + 1
            else
              -- Group is full, find someone to swap
              local swapIndex, swapName, swapTargetGroup = FindMisplacedPlayerInGroup(targetGroup, raidhelperData)
              
              if swapIndex then
                -- Move the misplaced player first
                if swapTargetGroup and swapTargetGroup >= 1 and swapTargetGroup <= 8 and GetGroupPlayerCount(swapTargetGroup) < 5 then
                  -- Move to their correct group
                  SetRaidSubgroup(swapIndex, swapTargetGroup)
                  ChatFrame4:AddMessage("[OGRH] Moving " .. swapName .. " to group " .. swapTargetGroup, 0, 1, 1)
                else
                  -- Move to fallback group
                  local fallbackGroup = FindAvailableGroup()
                  if fallbackGroup then
                    SetRaidSubgroup(swapIndex, fallbackGroup)
                    ChatFrame4:AddMessage("[OGRH] Moving " .. swapName .. " to group " .. fallbackGroup .. " (fallback)", 1, 1, 0)
                  else
                    ChatFrame4:AddMessage("[OGRH] Cannot move " .. name .. " - all groups full", 1, 0, 0)
                    break
                  end
                end
                
                -- Now move our player to the target group
                SetRaidSubgroup(i, targetGroup)
                movedCount = movedCount + 1
              end
            end
            break
          end
        end
      end
    end
  end
end

-- RollFor auto-refresh (check every 5 seconds for changes)
local rollForCheckFrame = CreateFrame("Frame")
local rollForLastHash = nil
local rollForCheckInterval = 5
local rollForTimeSinceCheck = 0

local function GetRollForDataHash()
  if not RollForCharDb or not RollForCharDb.softres or not RollForCharDb.softres.data then
    return nil
  end
  return RollForCharDb.softres.data
end

rollForCheckFrame:SetScript("OnUpdate", function()
  rollForTimeSinceCheck = rollForTimeSinceCheck + arg1
  
  if rollForTimeSinceCheck >= rollForCheckInterval then
    rollForTimeSinceCheck = 0
    
    -- Only check if RollFor is the current source and window is open
    if OGRH_SV.invites.currentSource == OGRH.Invites.SOURCE_TYPE.ROLLFOR and OGRH_InvitesFrame and OGRH_InvitesFrame:IsVisible() then
      local currentHash = GetRollForDataHash()
      
      if currentHash and currentHash ~= rollForLastHash then
        rollForLastHash = currentHash
        
        -- Refresh the player list
        if OGRH.Invites.RefreshPlayerList then
          OGRH.Invites.RefreshPlayerList()
          ChatFrame4:AddMessage("[OGRH] RollFor data updated - refreshing player list.", 0, 1, 1)
        end
      end
    end
  end
end)

-- Initialize
OGRH.Invites.EnsureSV()

-- Reset invite mode on reload/login
if OGRH_SV.invites.inviteMode then
  OGRH_SV.invites.inviteMode.enabled = false
end

-- Initialize RollFor hash
rollForLastHash = GetRollForDataHash()

-- DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[RaidHelper]|r Invites loaded")
