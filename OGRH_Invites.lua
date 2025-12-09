-- OGRH_Invites.lua
-- Raid Invites Module - Manage invites for players from RollFor soft-res data
if not OGRH then
  DEFAULT_CHAT_FRAME:AddMessage("|cffff0000Error: OGRH_Invites requires OGRH_Core to be loaded first!|r")
  return
end

OGRH.Invites = OGRH.Invites or {
  playerStatuses = {}, -- Track invite status per player
  lastUpdate = 0,
  updateInterval = 2 -- Update every 2 seconds
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
      declinedPlayers = {}, -- Track who declined invites this session
      history = {} -- Track invite history with timestamps
    }
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
  
  -- Convert map to array
  for _, playerData in pairs(playerMap) do
    table.insert(players, playerData)
  end
  
  -- Sort by name
  if table.getn(players) > 0 then
    table.sort(players, function(a, b) return a.name < b.name end)
  end
  
  return players
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
  frame:SetHeight(500)
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
  
  -- RollFor import button (top left)
  local rollForBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  rollForBtn:SetWidth(110)
  rollForBtn:SetHeight(24)
  rollForBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -10)
  rollForBtn:SetText("RollFor Import")
  if OGRH and OGRH.StyleButton then
    OGRH.StyleButton(rollForBtn)
  end
  
  -- Tooltip
  rollForBtn:SetScript("OnEnter", function()
    GameTooltip:SetOwner(rollForBtn, "ANCHOR_RIGHT")
    GameTooltip:SetText("RollFor SR Import", 1, 1, 1)
    GameTooltip:AddLine("Click to open soft reserve import window", 0.8, 0.8, 0.8, 1)
    GameTooltip:Show()
  end)
  rollForBtn:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)
  
  -- Click handler
  rollForBtn:SetScript("OnClick", function()
    if RollFor and RollFor.key_bindings and RollFor.key_bindings.softres_toggle then
      RollFor.key_bindings.softres_toggle()
    else
      OGRH.Msg("RollFor addon not found or not loaded.")
    end
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
  local containerHeight = frame:GetHeight() - 145  -- Available vertical space
  listContainer:SetWidth(containerWidth)
  listContainer:SetHeight(containerHeight)
  
  -- Create styled scroll list using standardized function
  local listFrame, scrollFrame, scrollChild, scrollBar, contentWidth = OGRH.CreateStyledScrollList(listContainer, containerWidth, containerHeight)
  listFrame:SetAllPoints(listContainer)
  
  frame.scrollChild = scrollChild
  frame.scrollFrame = scrollFrame
  frame.scrollBar = scrollBar
  frame.contentWidth = contentWidth
  
  -- Bottom action buttons
  local inviteAllBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  inviteAllBtn:SetWidth(70)
  inviteAllBtn:SetHeight(28)
  inviteAllBtn:SetPoint("BOTTOMLEFT", 20, 15)
  inviteAllBtn:SetText("Invite")
  OGRH.StyleButton(inviteAllBtn)
  inviteAllBtn:SetScript("OnClick", function()
    OGRH.Invites.InviteAllOnline()
  end)
  
  -- Initialize auto-sort state (default off)
  if not OGRH_SV.rgo then
    OGRH_SV.rgo = {}
  end
  if OGRH_SV.rgo.autoSortEnabled == nil then
    OGRH_SV.rgo.autoSortEnabled = false
  end
  
  -- Refresh button (bottom right)
  local refreshBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  refreshBtn:SetWidth(70)
  refreshBtn:SetHeight(28)
  refreshBtn:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -20, 15)
  refreshBtn:SetText("Refresh")
  OGRH.StyleButton(refreshBtn)
  refreshBtn:SetScript("OnClick", function()
    OGRH.Invites.RefreshPlayerList()
    OGRH.Msg("Refreshed player list.")
  end)
  
  -- Clear Status button (bottom right, left of Refresh)
  local clearBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  clearBtn:SetWidth(100)
  clearBtn:SetHeight(28)
  clearBtn:SetPoint("RIGHT", refreshBtn, "LEFT", -5, 0)
  clearBtn:SetText("Clear Status")
  OGRH.StyleButton(clearBtn)
  clearBtn:SetScript("OnClick", function()
    OGRH.Invites.ClearAllTracking()
    OGRH.Invites.RefreshPlayerList()
  end)
  
  local statsText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  statsText:SetPoint("BOTTOM", 0, 25)
  statsText:SetJustifyH("CENTER")
  statsText:SetText("0 players not in raid")
  frame.statsText = statsText
  
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
      sender = NormalizeName(sender)
      -- Check if sender is already in the raid
      if OGRH.Invites.IsPlayerInRaid(sender) then
        return
      end
      -- Check if sender is in our soft-res list
      local players = OGRH.Invites.GetSoftResPlayers()
      for _, playerData in ipairs(players) do
        if NormalizeName(playerData.name) == sender then
          -- Auto-invite them
          OGRH.Invites.InvitePlayer(sender)
          OGRH.Msg("Auto-inviting " .. sender .. " (whispered for invite)")
          break
        end
      end
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
  
  -- Get soft-res players
  local allPlayers = OGRH.Invites.GetSoftResPlayers()
  
  -- Filter to only those not in raid
  local playersNotInRaid = {}
  for _, playerData in ipairs(allPlayers) do
    if not OGRH.Invites.IsPlayerInRaid(playerData.name) then
      -- Update class information first
      playerData = OGRH.Invites.UpdatePlayerClass(playerData)
      
      -- Get current status (note: GetPlayerStatus returns class as 3rd param but we already looked it up above)
      playerData.status, playerData.online = OGRH.Invites.GetPlayerStatus(playerData.name)
      
      table.insert(playersNotInRaid, playerData)
    end
  end
  
  -- Update stats text
  local totalCount = table.getn(allPlayers)
  local notInRaidCount = table.getn(playersNotInRaid)
  local inRaidCount = totalCount - notInRaidCount
  
  -- Check if RollFor is loaded but not initialized yet
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
    notInRaidCount .. " players not in raid\n(" .. inRaidCount .. " already in raid)"
  )
  
  if notInRaidCount == 0 then
    OGRH_InvitesFrame.infoText:SetText("All soft-res players are in the raid!")
    scrollChild:SetHeight(1)
    OGRH_InvitesFrame.scrollBar:Hide()
    return
  else
    OGRH_InvitesFrame.infoText:SetText("Players from RollFor soft-res data not currently in the raid:")
  end
  
  -- Create rows
  local yOffset = -5
  local rowHeight = OGRH.LIST_ITEM_HEIGHT
  local rowSpacing = OGRH.LIST_ITEM_SPACING
  
  for i, playerData in ipairs(playersNotInRaid) do
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
    local ogrh_role = OGRH.Invites.MapRollForRoleToOGRH(playerData.role)
    local displayRole = ogrh_role or playerData.role or "Unknown"
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
    roleText:SetText(displayRole)
    
    -- Status
    local statusText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusText:SetPoint("LEFT", row, "LEFT", 225, 0)
    statusText:SetWidth(90)
    statusText:SetJustifyH("LEFT")
    if playerData.status == STATUS.OFFLINE then
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
    -- Disable if offline
    if playerData.status == STATUS.OFFLINE then
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
    -- Disable if offline
    if playerData.status == STATUS.OFFLINE then
      whisperBtn:Disable()
    end
    
    table.insert(scrollChild.rows, row)
    yOffset = yOffset - rowHeight - rowSpacing
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

-- Handle party invite declined event
local inviteEventFrame = CreateFrame("Frame")
inviteEventFrame:RegisterEvent("PARTY_INVITE_REQUEST")
inviteEventFrame:RegisterEvent("RAID_ROSTER_UPDATE")
inviteEventFrame:SetScript("OnEvent", function()
  if event == "PARTY_INVITE_REQUEST" then
    -- Track declined invites
    -- Note: WoW 1.12 doesn't have a specific "declined" event
    -- We'll track this indirectly
  elseif event == "RAID_ROSTER_UPDATE" then
    -- Refresh the window if it's open
    if OGRH_InvitesFrame and OGRH_InvitesFrame:IsVisible() then
      OGRH.Invites.RefreshPlayerList()
    end
  end
end)

-- Initialize
OGRH.Invites.EnsureSV()

-- DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[RaidHelper]|r Invites loaded")
