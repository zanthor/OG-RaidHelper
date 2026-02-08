-- OGRH_Roster.lua - Roster Management System
-- Provides interface to manage raid roster with role assignments and rankings

OGRH = OGRH or {}
OGRH.RosterMgmt = OGRH.RosterMgmt or {}

-- Local references
local RosterMgmt = OGRH.RosterMgmt

-- Temporary cache for removed role scores (not saved between sessions)
local roleScoreCache = {}

-- Constants
local ROLES = {"TANKS", "HEALERS", "MELEE", "RANGED"}
local ROLE_DISPLAY = {
  TANKS = "Tanks",
  HEALERS = "Healers",
  MELEE = "Melee",
  RANGED = "Ranged"
}

-- Role icons (WoW 1.12 textures)
local ROLE_ICONS = {
  TANKS = "Interface\\Icons\\Ability_Defend",  -- Shield
  HEALERS = "Interface\\Icons\\Spell_Holy_FlashHeal",  -- Heal spell
  MELEE = "Interface\\Icons\\INV_Sword_27",  -- Melee weapon
  RANGED = "Interface\\Icons\\Spell_Fire_FireBolt"  -- Ranged spell
}

local CLASSES = {"WARRIOR", "PRIEST", "PALADIN", "DRUID", "SHAMAN", "ROGUE", "HUNTER", "MAGE", "WARLOCK"}

-- Class-role constraints (matches class priority system)
local VALID_CLASS_ROLES = {
  DRUID = {TANKS = true, HEALERS = true, MELEE = true, RANGED = true},
  SHAMAN = {TANKS = true, HEALERS = true, MELEE = true, RANGED = true},
  WARRIOR = {TANKS = true, MELEE = true},
  PALADIN = {TANKS = true, HEALERS = true, MELEE = true},
  HUNTER = {MELEE = true, RANGED = true},
  PRIEST = {HEALERS = true, RANGED = true},
  ROGUE = {MELEE = true},
  MAGE = {RANGED = true},
  WARLOCK = {RANGED = true}
}

-- Get valid roles for a class
function RosterMgmt.GetValidRolesForClass(class)
  if not class then return {} end
  return VALID_CLASS_ROLES[string.upper(class)] or {}
end

-- Check if a class can have a specific role
function RosterMgmt.IsValidClassRole(class, role)
  if not class or class == "" or not role then return false end
  local upperClass = string.upper(class)
  local validRoles = VALID_CLASS_ROLES[upperClass]
  if not validRoles then return false end
  return validRoles[role] or false
end

-- Get default primary role for a class (matching RolesUI logic)
function RosterMgmt.GetDefaultRoleForClass(class)
  if not class or class == "" then
    return "RANGED"  -- Default fallback when class is unknown
  end
  
  class = string.upper(class)
  
  -- Match the default role assignments from OGRH_RolesUI.lua
  if class == "WARRIOR" then
    return "TANKS"
  elseif class == "PRIEST" or class == "PALADIN" or class == "DRUID" then
    return "HEALERS"
  elseif class == "ROGUE" then
    return "MELEE"
  else
    return "RANGED"  -- HUNTER, MAGE, WARLOCK, SHAMAN, and unknown classes
  end
end

-- Initialize saved variables
function RosterMgmt.EnsureSV()
  -- Validate SVM is available
  if not OGRH.SVM then
    OGRH.Msg("|cffff0000[RH-Roster]|r Error: SavedVariablesManager (SVM) not loaded. Cannot initialize.")
    return false
  end
  
  local rosterManagement = OGRH.SVM.GetPath("rosterManagement")
  
  if not rosterManagement then
    -- Initialize with default structure
    OGRH.SVM.SetPath("rosterManagement", {
      players = {},
      rankingHistory = {},
      config = {
        historySize = 10,
        autoRankingEnabled = {
          TANKS = false,
          HEALERS = true,
          MELEE = true,
          RANGED = true
        },
        rankingSource = "DPSMate",
        useEffectiveHealing = true,
        eloSettings = {
          startingRating = 1000,
          kFactor = 32,
          manualAdjustment = 25
        }
      },
      syncMeta = {
        version = 1,
        lastSync = 0,
        syncChecksum = ""
      }
    }, {
      syncLevel = "MANUAL",
      componentType = "settings"
    })
    -- Debug message removed - roster initialized silently
  end
  
  return true
end

-- Get class color
local function GetClassColor(class)
  local colors = RAID_CLASS_COLORS[class]
  if colors then
    return colors.r, colors.g, colors.b
  end
  return 1, 1, 1
end

-- Get player class (detect from roster or online)
local function GetPlayerClass(playerName)
  -- Check if player is in roster
  local allPlayers = OGRH.SVM.GetPath("rosterManagement.players") or {}
  if allPlayers[playerName] then
    return allPlayers[playerName].class
  end
  
  -- Try to detect from raid
  for i = 1, GetNumRaidMembers() do
    local name, _, _, _, class = GetRaidRosterInfo(i)
    if name == playerName then
      return class
    end
  end
  
  -- Try to detect from party
  for i = 1, GetNumPartyMembers() do
    local unit = "party" .. i
    if UnitName(unit) == playerName then
      local _, class = UnitClass(unit)
      return class
    end
  end
  
  return nil
end

-- Add or update player
function RosterMgmt.AddPlayer(playerName, class)
  if not RosterMgmt.EnsureSV() then
    return false
  end
  
  if not playerName or playerName == "" then
    return false
  end
  
  if not class then
    class = GetPlayerClass(playerName)
  end
  
  if not class then
    return false
  end
  
  local config = OGRH.SVM.GetPath("rosterManagement.config") or {}
  local startingRating = (config.eloSettings and config.eloSettings.startingRating) or 1000
  
  -- Determine default primary role based on class
  local defaultPrimaryRole = "MELEE"  -- Safe default for all classes
  local validRoles = RosterMgmt.GetValidRolesForClass(class)
  
  -- Prefer roles in this order: TANKS -> HEALERS -> MELEE -> RANGED
  if validRoles.TANKS then
    defaultPrimaryRole = "TANKS"
  elseif validRoles.HEALERS then
    defaultPrimaryRole = "HEALERS"
  elseif validRoles.MELEE then
    defaultPrimaryRole = "MELEE"
  elseif validRoles.RANGED then
    defaultPrimaryRole = "RANGED"
  end
  
  local allPlayers = OGRH.SVM.GetPath("rosterManagement.players") or {}
  allPlayers[playerName] = {
    class = class,
    primaryRole = defaultPrimaryRole,
    secondaryRoles = {},
    rankings = {
      TANKS = startingRating,
      HEALERS = startingRating,
      MELEE = startingRating,
      RANGED = startingRating
    },
    notes = "",
    lastUpdated = time()
  }
  
  OGRH.SVM.SetPath("rosterManagement.players", allPlayers, {
    syncLevel = "MANUAL",
    componentType = "roster",
    source = "Roster"
  })
  
  return true
end

-- Remove player
function RosterMgmt.RemovePlayer(playerName)
  if not RosterMgmt.EnsureSV() then
    return false
  end
  
  local allPlayers = OGRH.SVM.GetPath("rosterManagement.players") or {}
  if not allPlayers[playerName] then
    return false
  end
  
  allPlayers[playerName] = nil
  OGRH.SVM.SetPath("rosterManagement.players", allPlayers, {
    syncLevel = "MANUAL",
    componentType = "roster",
    source = "Roster"
  })
  
  local allHistory = OGRH.SVM.GetPath("rosterManagement.rankingHistory") or {}
  allHistory[playerName] = nil
  OGRH.SVM.SetPath("rosterManagement.rankingHistory", allHistory, {
    syncLevel = "MANUAL",
    componentType = "roster",
    source = "Roster"
  })
  
  return true
end

-- Adjust ELO ranking
function RosterMgmt.AdjustElo(playerName, role, adjustment)
  if not RosterMgmt.EnsureSV() then
    return false
  end
  
  local allPlayers = OGRH.SVM.GetPath("rosterManagement.players") or {}
  local player = allPlayers[playerName]
  if not player then
    return false
  end
  
  player.rankings[role] = player.rankings[role] + adjustment
  player.lastUpdated = time()
  
  OGRH.SVM.SetPath("rosterManagement.players." .. playerName, player, {
    syncLevel = "MANUAL",
    componentType = "roster",
    source = "Roster"
  })
  
  return true
end

-- Set ELO ranking
function RosterMgmt.SetElo(playerName, role, newValue)
  if not RosterMgmt.EnsureSV() then
    return false
  end
  
  local allPlayers = OGRH.SVM.GetPath("rosterManagement.players") or {}
  local player = allPlayers[playerName]
  if not player then
    return false
  end
  
  player.rankings[role] = newValue
  player.lastUpdated = time()
  
  OGRH.SVM.SetPath("rosterManagement.players." .. playerName, player, {
    syncLevel = "MANUAL",
    componentType = "roster",
    source = "Roster"
  })
  
  return true
end

-- Get players for role (sorted by ranking)
function RosterMgmt.GetPlayersForRole(role)
  if not RosterMgmt.EnsureSV() then
    return {}
  end
  
  local players = {}
  local allPlayers = OGRH.SVM.GetPath("rosterManagement.players") or {}
  
  for name, data in pairs(allPlayers) do
    -- Include if primary or secondary role matches
    local isInRole = (data.primaryRole == role)
    if not isInRole and data.secondaryRoles then
      for _, secRole in ipairs(data.secondaryRoles) do
        if secRole == role then
          isInRole = true
          break
        end
      end
    end
    
    if isInRole then
      local ranking = 1000  -- Default
      if data.rankings and data.rankings[role] then
        ranking = data.rankings[role]
      end
      
      table.insert(players, {
        name = name,
        class = data.class,
        ranking = ranking,
        isPrimary = (data.primaryRole == role)
      })
    end
  end
  
  -- Sort by ranking (descending)
  table.sort(players, function(a, b)
    return a.ranking > b.ranking
  end)
  
  return players
end

-- Get all players
function RosterMgmt.GetAllPlayers()
  if not RosterMgmt.EnsureSV() then
    return {}
  end
  
  local players = {}
  local allPlayers = OGRH.SVM.GetPath("rosterManagement.players") or {}
  
  for name, data in pairs(allPlayers) do
    table.insert(players, {
      name = name,
      class = data.class,
      primaryRole = data.primaryRole
    })
  end
  
  -- Sort by class, then name
  table.sort(players, function(a, b)
    if a.class ~= b.class then
      return a.class < b.class
    end
    return a.name < b.name
  end)
  
  return players
end

-- Show main roster window
function RosterMgmt.ShowWindow()
  RosterMgmt.EnsureSV()
  
  -- Recreate window if design mode state has changed
  if RosterMgmt.window and RosterMgmt.window.designModeState ~= OGST.DESIGN_MODE then
    RosterMgmt.window:Hide()
    RosterMgmt.window = nil
  end
  
  -- Create window if it doesn't exist
  if not RosterMgmt.window then
    RosterMgmt.CreateWindow()
    if RosterMgmt.window then
      RosterMgmt.window.designModeState = OGST.DESIGN_MODE
    end
  end
  
  RosterMgmt.window:Show()
  RosterMgmt.RefreshUI()
end

-- Create main window
function RosterMgmt.CreateWindow()
  local window = OGST.CreateStandardWindow({
    name = "OGRH_RosterMgmtWindow",
    width = 700,
    height = 420,
    title = "Roster Management",
    closeButton = true,
    escapeCloses = true,
    closeOnNewWindow = false,
    resizable = false
  })
  
  window:SetPoint("CENTER", UIParent, "CENTER")
  
  -- Add OnUpdate handler for auto-save timer
  window:SetScript("OnUpdate", function()
    if RosterMgmt.notesSaveTimer and GetTime() >= RosterMgmt.notesSaveTimer then
      RosterMgmt.notesSaveTimer = nil
      RosterMgmt.SavePlayerDetails()
    end
  end)
  
  -- Create role list (left) - anchor directly to contentFrame
  RosterMgmt.CreateRoleList(window.contentFrame)
  
  -- Create player list (middle) - anchor to role list
  RosterMgmt.CreatePlayerList(window.contentFrame)
  
  -- Create details panel (right) - content panel, anchored to player list
  local detailsPanel = OGST.CreateContentPanel(window.contentFrame, {
    width = 240,
    height = 100
  })
  
  if not detailsPanel then
    return nil
  end
  
  -- Anchor to right side of contentFrame
  detailsPanel:SetPoint("TOPRIGHT", window.contentFrame, "TOPRIGHT", -5, -5)
  detailsPanel:SetPoint("BOTTOM", window.contentFrame, "BOTTOM", 0, 40)  -- Leave 40px for toolbar
  detailsPanel:SetPoint("LEFT", window.contentFrame.playerList, "RIGHT", 5, 0)
  
  window.contentFrame.detailsPanel = detailsPanel
  
  -- Create details panel content
  RosterMgmt.CreateDetailsPanel(detailsPanel)
  
  -- Create bottom toolbar
  RosterMgmt.CreateToolbar(window)
  
  RosterMgmt.window = window
end

-- Create role list (left panel)
function RosterMgmt.CreateRoleList(parent)
  -- Create scrollable list for roles (anchored directly to contentFrame)
  local scrollList = OGST.CreateStyledScrollList(parent, 160, 500, true)
  scrollList:SetPoint("TOPLEFT", parent, "TOPLEFT", 5, -5)
  scrollList:SetPoint("BOTTOM", parent, "BOTTOM", 0, 40)  -- Leave 40px for toolbar
  
  -- Store role items for selection management
  scrollList.roleItems = {}
  
  -- Add role items
  for _, role in ipairs(ROLES) do
    local roleKey = role  -- Localize for closure
    local item = scrollList:AddItem({
      text = ROLE_DISPLAY[roleKey],
      onClick = function()
        RosterMgmt.SelectRole(roleKey)
      end
    })
    
    scrollList.roleItems[roleKey] = item
    
    -- Select TANKS by default
    if roleKey == "TANKS" then
      OGST.SetListItemSelected(item, true)
    end
  end
  
  -- Add All Players item
  local allPlayersItem = scrollList:AddItem({
    text = "All Players",
    onClick = function()
      RosterMgmt.SelectRole("ALL")
    end
  })
  
  scrollList.roleItems["ALL"] = allPlayersItem
  
  parent.roleList = scrollList
  RosterMgmt.selectedRole = "TANKS"
end

-- Select role
function RosterMgmt.SelectRole(role)
  -- Deselect all role items first
  if RosterMgmt.window and RosterMgmt.window.contentFrame and RosterMgmt.window.contentFrame.roleList then
    local roleList = RosterMgmt.window.contentFrame.roleList
    if roleList.roleItems then
      for _, item in pairs(roleList.roleItems) do
        OGST.SetListItemSelected(item, false)
      end
      
      -- Select the new role
      if roleList.roleItems[role] then
        OGST.SetListItemSelected(roleList.roleItems[role], true)
      end
    end
  end
  
  RosterMgmt.selectedRole = role
  RosterMgmt.RefreshPlayerList()
end

-- Create player list (center panel)
function RosterMgmt.CreatePlayerList(parent)
  -- Create scrollable list (anchored to role list)
  local scrollList = OGST.CreateStyledScrollList(parent, 300, 500, false)
  scrollList:SetPoint("TOPLEFT", parent.roleList, "TOPRIGHT", 5, 0)
  scrollList:SetPoint("BOTTOM", parent, "BOTTOM", 0, 40)  -- Leave 40px for toolbar
  
  parent.playerList = scrollList
end

-- Refresh player list
function RosterMgmt.RefreshPlayerList()
  if not RosterMgmt.window then return end
  
  local scrollList = RosterMgmt.window.contentFrame.playerList
  
  if not scrollList then return end
  
  -- Save current scroll position
  local savedScrollPosition = 0
  if scrollList.scrollFrame then
    savedScrollPosition = scrollList.scrollFrame:GetVerticalScroll()
  end
  
  -- Clear existing items
  scrollList:Clear()
  
  local players
  if RosterMgmt.selectedRole == "ALL" then
    players = RosterMgmt.GetAllPlayers()
  else
    players = RosterMgmt.GetPlayersForRole(RosterMgmt.selectedRole)
  end
  
  
  -- Add players to list
  for i, playerData in ipairs(players) do
    -- Skip if player data is invalid
    if not playerData or not playerData.name then
      break
    end
    
    local r, g, b = GetClassColor(playerData.class)
    
    -- Format text based on selected role
    local displayText
    if RosterMgmt.selectedRole ~= "ALL" then
      -- Show name with ELO rating
      local rankingText = playerData.ranking and tostring(playerData.ranking) or "N/A"
      displayText = playerData.name .. " - " .. rankingText
    else
      -- Show name only (role icons will be shown)
      displayText = playerData.name
    end
    
    -- Localize for closure
    local clickPlayerName = playerData.name
    
    local item = scrollList:AddItem({
      text = displayText,
      textColor = {r = r, g = g, b = b, a = 1},
      onClick = function()
        if RosterMgmt and RosterMgmt.SelectPlayer and clickPlayerName then
          RosterMgmt.SelectPlayer(clickPlayerName)
        end
      end,
      onMoveUp = (RosterMgmt.selectedRole ~= "ALL") and function()
        RosterMgmt.AdjustPlayerRank(clickPlayerName, 25)
      end or nil,
      onMoveDown = (RosterMgmt.selectedRole ~= "ALL") and function()
        RosterMgmt.AdjustPlayerRank(clickPlayerName, -25)
      end or nil,
      alwaysEnableButtons = true,
      onDelete = (RosterMgmt.selectedRole == "ALL") and function()
        if RosterMgmt.RemovePlayer then
          RosterMgmt.RemovePlayer(clickPlayerName)
          RosterMgmt.selectedPlayer = nil
          RosterMgmt.RefreshUI()
        end
      end or nil
    })
    
    -- Add role checkboxes when in "All Players" view
    if RosterMgmt.selectedRole == "ALL" then
      local checkSize = 16
      local iconSize = 16
      local spacing = 2
      local roleWidth = checkSize + spacing + iconSize
      
      -- Get player's full data for role checking
      local fullPlayerData = nil
      if OGRH.SVM then
        local allPlayers = OGRH.SVM.GetPath("rosterManagement.players") or {}
        fullPlayerData = allPlayers[playerData.name]
      end
      
      if fullPlayerData then
        -- Position checkboxes/icons after the player name text (around 85px from left)
        local xOffset = 85
        
        -- Create checkboxes for each role (left to right)
        for roleIndex = 1, table.getn(ROLES) do
          local role = ROLES[roleIndex]
          
          -- Check if this role is valid for this class
          local isValidRole = RosterMgmt.IsValidClassRole(fullPlayerData.class, role)
          
          -- Skip invalid roles entirely
          if isValidRole then
            local isPrimary = (fullPlayerData.primaryRole == role)
            local isSecondary = false
            
            if fullPlayerData.secondaryRoles then
              for _, secRole in ipairs(fullPlayerData.secondaryRoles) do
                if secRole == role then
                  isSecondary = true
                  break
                end
              end
            end
            
            -- Create checkbox first (on the left)
            local checkbox = CreateFrame("CheckButton", nil, item)
            checkbox:SetWidth(checkSize)
            checkbox:SetHeight(checkSize)
            checkbox:SetPoint("LEFT", item, "LEFT", xOffset, 0)
            checkbox:SetFrameLevel(item:GetFrameLevel() + 1)  -- Ensure checkbox is clickable but below buttons
            
            -- Checkbox textures
            checkbox:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
            checkbox:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
            checkbox:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
            checkbox:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
            checkbox:SetDisabledCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check-Disabled")
            
            -- Set checked state
            if isPrimary or isSecondary then
              checkbox:SetChecked(true)
            else
              checkbox:SetChecked(false)
            end
            
            -- Disable if primary role
            if isPrimary then
              checkbox:Disable()
            end
            
            -- Click handler to toggle role (localize vars for closure)
            local playerName = playerData.name
            local clickRole = role
            checkbox:SetScript("OnClick", function()
              RosterMgmt.TogglePlayerRole(playerName, clickRole)
            end)
            
            -- Tooltip
            checkbox:SetScript("OnEnter", function()
              GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
              GameTooltip:SetText(ROLE_DISPLAY[clickRole])
              if isPrimary then
                GameTooltip:AddLine("Primary Role (cannot uncheck)", 1, 0.82, 0)
              elseif isSecondary then
                GameTooltip:AddLine("Secondary Role", 0.5, 0.5, 0.5)
              else
                GameTooltip:AddLine("Click to assign", 0.5, 0.5, 0.5)
              end
              GameTooltip:Show()
            end)
            
            checkbox:SetScript("OnLeave", function()
              GameTooltip:Hide()
            end)
            
            -- Create role icon to the right of checkbox
            local roleIcon = item:CreateTexture(nil, "OVERLAY")
            roleIcon:SetWidth(iconSize)
            roleIcon:SetHeight(iconSize)
            roleIcon:SetPoint("LEFT", item, "LEFT", xOffset + checkSize + spacing, 0)
            roleIcon:SetTexture(ROLE_ICONS[role])
            roleIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            
            xOffset = xOffset + roleWidth + spacing
          end  -- end if isValidRole
        end  -- end for roleIndex
      end
    end
    
    -- Store player data on item for reference
    item.playerName = playerData.name
    item.playerData = playerData
  end
  
  -- Restore scroll position after populating list
  if scrollList.scrollFrame and savedScrollPosition > 0 then
    -- Need to call UpdateScrollBar first to ensure proper scrollbar state
    if scrollList.UpdateScrollBar then
      scrollList.UpdateScrollBar()
    end
    -- Restore the saved scroll position
    scrollList.scrollFrame:SetVerticalScroll(savedScrollPosition)
    -- Update scrollbar to match
    if scrollList.scrollBar and scrollList.scrollBar:IsShown() then
      scrollList.scrollBar:SetValue(savedScrollPosition)
    end
  end
end

-- Adjust player ranking (increase/decrease ELO)
function RosterMgmt.AdjustPlayerRank(playerName, adjustment)
  local allPlayers = OGRH.SVM.GetPath("rosterManagement.players") or {}
  local playerData = allPlayers[playerName]
  if not playerData then return end
  
  -- Determine which role to adjust
  local roleToAdjust = RosterMgmt.selectedRole
  if roleToAdjust == "ALL" then
    -- In All Players view, adjust the primary role
    roleToAdjust = playerData.primaryRole
  end
  
  if not roleToAdjust then return end
  
  -- Initialize rankings table if it doesn't exist
  if not playerData.rankings then
    playerData.rankings = { TANKS = 1000, HEALERS = 1000, MELEE = 1000, RANGED = 1000 }
  end
  
  -- Adjust ELO for the current role
  local currentRanking = playerData.rankings[roleToAdjust] or 1000
  playerData.rankings[roleToAdjust] = currentRanking + adjustment
  
  -- Update timestamp
  playerData.lastUpdated = time()
  
  -- Write back via SVM
  OGRH.SVM.SetPath("rosterManagement.players." .. playerName, playerData, {
    syncLevel = "MANUAL",
    componentType = "roster",
    source = "Roster"
  })
  
  -- Refresh the list (will resort by ELO)
  RosterMgmt.RefreshUI()
end

-- Toggle player role assignment
function RosterMgmt.TogglePlayerRole(playerName, role)
  if not RosterMgmt.EnsureSV() then
    return
  end
  
  local allPlayers = OGRH.SVM.GetPath("rosterManagement.players") or {}
  local player = allPlayers[playerName]
  if not player then return end
  
  -- Check if this role is valid for the player's class
  if not RosterMgmt.IsValidClassRole(player.class, role) then
    return
  end
  
  -- Check if this is the primary role
  if player.primaryRole == role then
    -- Can't remove primary role
    return
  end
  
  -- Check if it's a secondary role
  local isSecondary = false
  local secondaryIndex = nil
  if player.secondaryRoles then
    for i, secRole in ipairs(player.secondaryRoles) do
      if secRole == role then
        isSecondary = true
        secondaryIndex = i
        break
      end
    end
  else
    player.secondaryRoles = {}
  end
  
  if isSecondary then
    -- Remove from secondary roles
    table.remove(player.secondaryRoles, secondaryIndex)
    
    -- Cache the current score before removing it
    if not roleScoreCache[playerName] then
      roleScoreCache[playerName] = {}
    end
    if player.rankings and player.rankings[role] then
      roleScoreCache[playerName][role] = player.rankings[role]
      player.rankings[role] = nil
    end
  else
    -- Add as secondary role
    table.insert(player.secondaryRoles, role)
    
    -- Initialize rankings if needed
    if not player.rankings then
      player.rankings = { TANKS = 1000, HEALERS = 1000, MELEE = 1000, RANGED = 1000 }
    end
    
    -- Try to restore from cache, otherwise use default
    if roleScoreCache[playerName] and roleScoreCache[playerName][role] then
      player.rankings[role] = roleScoreCache[playerName][role]
      roleScoreCache[playerName][role] = nil
    elseif not player.rankings[role] then
      player.rankings[role] = 1000
    end
  end
  
  player.lastUpdated = time()
  
  -- Write back via SVM
  OGRH.SVM.SetPath("rosterManagement.players." .. playerName, player, {
    syncLevel = "MANUAL",
    componentType = "roster",
    source = "Roster"
  })
  
  -- Refresh the list and details panel to update role icons and rankings display
  RosterMgmt.RefreshUI()
end

-- Select player
function RosterMgmt.SelectPlayer(playerName)
  RosterMgmt.selectedPlayer = playerName
  RosterMgmt.RefreshDetailsPanel()
end

-- Create details panel (right panel)
function RosterMgmt.CreateDetailsPanel(parent)
  -- Player name display container
  local nameContainer = CreateFrame("Frame", nil, parent)
  nameContainer:SetHeight(30)
  nameContainer:SetPoint("TOPLEFT", parent, "TOPLEFT", 5, -5)
  nameContainer:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -5, -5)
  
  -- Player name static text
  parent.nameText = OGST.CreateStaticText(nameContainer, {
    text = "Select a player",
    font = "GameFontNormalLarge",
    color = {r = 1, g = 0.82, b = 0, a = 1},
    align = "CENTER"
  })
  OGST.AnchorElement(parent.nameText, nameContainer, { position = "top", align = "center" })
  
  parent.nameContainer = nameContainer
  
  -- Primary Role menu button with built-in label
  -- Note: menuItems populated with ALL roles initially, will be filtered dynamically
  local roleMenuItems = {}
  for _, role in ipairs(ROLES) do
    -- Capture role in local variable for closure
    local capturedRole = role
    table.insert(roleMenuItems, {
      text = ROLE_DISPLAY[role],
      value = role,
      onClick = function()
        if RosterMgmt.editingPlayer then
          -- Get player class, use empty string if unknown
          local playerClass = RosterMgmt.editingPlayer.class or ""
          local upperClass = playerClass ~= "" and string.upper(playerClass) or ""
          
          -- Check if role is valid for this class
          if upperClass == "" or RosterMgmt.IsValidClassRole(upperClass, capturedRole) then
            -- Valid role for this class (or class unknown) - assign it
            RosterMgmt.editingPlayer.primaryRole = capturedRole
            RosterMgmt.SavePlayerDetails()  -- Auto-save, will refresh UI
          end
        end
      end
    })
  end
  
  local roleContainer, roleButton, roleMenu, roleLabel = OGST.CreateMenuButton(parent, {
    label = "Primary Role:",
    labelAnchor = "LEFT",
    labelWidth = 100,
    buttonText = "Tanks",
    buttonWidth = 130,
    singleSelect = true,
    menuItems = roleMenuItems
  })
  
  parent.primaryRoleContainer = roleContainer
  parent.primaryRoleButton = roleButton
  parent.primaryRoleMenu = roleMenu
  
  -- Hide initially until player selected
  if roleContainer then
    roleContainer:Hide()
  end
  
  -- Store original menu items (all roles) for filtering later
  if roleContainer and roleContainer.config then
    roleContainer.config.originalMenuItems = {}
    for _, item in ipairs(roleContainer.config.menuItems) do
      table.insert(roleContainer.config.originalMenuItems, item)
    end
  end
  
  -- Override button click to filter menu based on current player's class
  if roleButton and roleMenu and roleContainer then
    roleButton:SetScript("OnClick", function()
      -- Filter menu based on currently selected player's class
      if RosterMgmt.selectedPlayer then
        local allPlayers = OGRH.SVM.GetPath("rosterManagement.players") or {}
        local playerData = allPlayers[RosterMgmt.selectedPlayer]
        if playerData and playerData.class then
          local validRoles = RosterMgmt.GetValidRolesForClass(playerData.class)
          
          -- Build filtered menuItems
          local filteredMenuItems = {}
          if roleContainer.config and roleContainer.config.originalMenuItems then
            for _, role in ipairs(ROLES) do
              if validRoles[role] then
                for _, menuItem in ipairs(roleContainer.config.originalMenuItems) do
                  if menuItem.value == role then
                    table.insert(filteredMenuItems, menuItem)
                    break
                  end
                end
              end
            end
            
            -- Update config and rebuild
            roleContainer.config.menuItems = filteredMenuItems
            OGST.RebuildMenuButton(roleContainer, roleButton, roleMenu, roleContainer.config)
          end
        end
      end
      
      -- Show the menu
      if roleMenu:IsShown() then
        roleMenu:Hide()
      else
        roleMenu:ClearAllPoints()
        roleMenu:SetPoint("TOPLEFT", roleButton, "BOTTOMLEFT", 0, -2)
        roleMenu:Show()
      end
    end)
  end
  
  if roleContainer then
    OGST.AnchorElement(roleContainer, nameContainer, {position = "below", fill = true})
  end
  
  -- Notes label
  local notesLabel = OGST.CreateStaticText(parent, {
    text = "Notes:",
    font = "GameFontNormal",
    color = {r = 1, g = 1, b = 1, a = 1},
    align = "LEFT"
  })
  notesLabel:Hide()  -- Hide initially
  parent.notesLabel = notesLabel
  
  if roleContainer then
    OGST.AnchorElement(notesLabel, roleContainer, {position = "below", fill = true})
  end
  
  -- Notes text box
  parent.notesTextBox = OGST.CreateScrollingTextBox(parent, 220, 80)
  if parent.notesTextBox then
    parent.notesTextBox:Hide()  -- Hide initially
    OGST.AnchorElement(parent.notesTextBox, notesLabel, {position = "below", fill = true})
    -- Add OnTextChanged handler for auto-save
    if parent.notesTextBox.editBox then
      parent.notesTextBox.editBox:SetScript("OnTextChanged", function()
        if RosterMgmt.editingPlayer and this:GetText() ~= (RosterMgmt.editingPlayer.notes or "") then
          -- Delay save to avoid saving on every keystroke
          if not RosterMgmt.notesSaveTimer then
            RosterMgmt.notesSaveTimer = 0
          end
          RosterMgmt.notesSaveTimer = GetTime() + 1  -- Save 1 second after last keystroke
        end
      end)
    end
  end
  
  -- Rankings summary label
  local rankingsLabel = OGST.CreateStaticText(parent, {
    text = "Rankings:",
    font = "GameFontNormal",
    color = {r = 1, g = 1, b = 1, a = 1},
    align = "LEFT"
  })
  rankingsLabel:Hide()  -- Hide initially
  parent.rankingsLabel = rankingsLabel
  
  if parent.notesTextBox then
    OGST.AnchorElement(rankingsLabel, parent.notesTextBox, {position = "below", fill = true, gap = 10})
  end
  
  -- Create editable textboxes for each role ranking
  parent.rankingTextBoxes = {}
  
  local previousElement = rankingsLabel
  for _, role in ipairs(ROLES) do
    -- Localize role for closure
    local currentRole = role
    
    -- Create textbox using CreateSingleLineTextBox with label
    local container, backdrop, editBox, label = OGST.CreateSingleLineTextBox(parent, 165, 24, {
      textBoxWidth = 80,
      maxLetters = 5,
      align = "LEFT",
      label = ROLE_DISPLAY[currentRole] .. ":",
      labelAnchor = "LEFT",
      labelWidth = 70
    })
    
    -- Don't hide initially - let the RefreshDetailsPanel handle visibility
    -- container:Hide()  -- Removed - causes backdrop to not render properly
    
    -- Store reference to container with editBox access
    parent.rankingTextBoxes[currentRole] = container
    container.editBox = editBox
    
    -- Position below previous element
    if previousElement then
      OGST.AnchorElement(container, previousElement, {position = "below", fill = false})
    end
    
    -- Add validation and update handler
    if editBox then
      editBox:SetScript("OnEnterPressed", function()
        local value = tonumber(editBox:GetText())
        if value and RosterMgmt.editingPlayer then
          -- Update the ranking
          local playerName = RosterMgmt.editingPlayer.name
          local allPlayers = OGRH.SVM.GetPath("rosterManagement.players") or {}
          local playerData = allPlayers[playerName]
          if playerData then
            -- Initialize rankings table if it doesn't exist
            if not playerData.rankings then
              playerData.rankings = { TANKS = 1000, HEALERS = 1000, MELEE = 1000, RANGED = 1000 }
            end
            playerData.rankings[currentRole] = value
            playerData.lastUpdated = time()
            
            OGRH.SVM.SetPath("rosterManagement.players." .. playerName, playerData, {
              syncLevel = "MANUAL",
              componentType = "roster",
              source = "Roster"
            })
            
            -- Refresh UI to resort the list
            RosterMgmt.RefreshUI()
          end
        end
        this:ClearFocus()
      end)
      
      editBox:SetScript("OnEscapePressed", function()
        this:ClearFocus()
        -- Restore original value
        if RosterMgmt.editingPlayer then
          local playerName = RosterMgmt.editingPlayer.name
          local allPlayers = OGRH.SVM.GetPath("rosterManagement.players") or {}
          local playerData = allPlayers[playerName]
          if playerData and playerData.rankings then
            editBox:SetText(tostring(playerData.rankings[currentRole] or 1000))
          end
        end
      end)
      
      -- Only allow numbers
      editBox:SetScript("OnChar", function()
        local text = this:GetText()
        if text and text ~= "" then
          -- Remove any non-numeric characters
          local numericText = string.gsub(text, "[^0-9]", "")
          if numericText ~= text then
            this:SetText(numericText)
          end
        end
      end)
    end
    
    previousElement = container
  end
end

-- Refresh details panel
function RosterMgmt.RefreshDetailsPanel()
  if not RosterMgmt.window then return end
  
  local parent = RosterMgmt.window.contentFrame.detailsPanel
  
  if not parent or not parent.nameText then return end
  
  if not RosterMgmt.selectedPlayer then
    -- No player selected - hide all controls
    parent.nameText:SetText("Select a player")
    parent.nameText:SetTextColor(1, 0.82, 0, 1)  -- Gold
    
    if parent.primaryRoleContainer then parent.primaryRoleContainer:Hide() end
    if parent.notesLabel then parent.notesLabel:Hide() end
    if parent.notesTextBox then parent.notesTextBox:Hide() end
    if parent.rankingsLabel then parent.rankingsLabel:Hide() end
    if parent.rankingTextBoxes then
      for _, textBox in pairs(parent.rankingTextBoxes) do
        textBox:Hide()
      end
    end
    
    return
  end
  
  local allPlayers = OGRH.SVM.GetPath("rosterManagement.players") or {}
  local playerData = allPlayers[RosterMgmt.selectedPlayer]
  if not playerData then
    -- Player not found - hide all controls
    parent.nameText:SetText("Player not found")
    parent.nameText:SetTextColor(1, 0.82, 0, 1)  -- Gold
    
    if parent.primaryRoleContainer then parent.primaryRoleContainer:Hide() end
    if parent.notesLabel then parent.notesLabel:Hide() end
    if parent.notesTextBox then parent.notesTextBox:Hide() end
    if parent.rankingsLabel then parent.rankingsLabel:Hide() end
    if parent.rankingTextBoxes then
      for _, textBox in pairs(parent.rankingTextBoxes) do
        textBox:Hide()
      end
    end
    
    return
  end
  
  -- Valid player - show all controls
  if parent.primaryRoleContainer then parent.primaryRoleContainer:Show() end
  if parent.notesLabel then parent.notesLabel:Show() end
  if parent.notesTextBox then parent.notesTextBox:Show() end
  if parent.rankingsLabel then parent.rankingsLabel:Show() end
  
  -- Show/hide ranking textboxes based on player's configured roles
  -- Also re-anchor them dynamically so visible ones move up to fill gaps
  if parent.rankingTextBoxes then
    local previousVisibleElement = parent.rankingsLabel
    
    for _, role in ipairs(ROLES) do
      local textBox = parent.rankingTextBoxes[role]
      if textBox then
        -- Check if this role is the player's primary role
        local isPlayerRole = (playerData.primaryRole == role)
        
        -- Check if this role is one of the player's secondary roles
        if not isPlayerRole and playerData.secondaryRoles then
          for _, secRole in ipairs(playerData.secondaryRoles) do
            if secRole == role then
              isPlayerRole = true
              break
            end
          end
        end
        
        -- Only show textbox if this role is configured for the player
        if isPlayerRole then
          -- Clear all anchor points and re-anchor to previous visible element
          textBox:ClearAllPoints()
          OGST.AnchorElement(textBox, previousVisibleElement, {position = "below", fill = false})
          textBox:Show()
          previousVisibleElement = textBox
        else
          textBox:Hide()
        end
      end
    end
  end
  
  -- Update name with class color
  parent.nameText:SetText(RosterMgmt.selectedPlayer)
  if playerData.class then
    local r, g, b = GetClassColor(playerData.class)
    parent.nameText:SetTextColor(r, g, b, 1)
  else
    parent.nameText:SetTextColor(1, 0.82, 0, 1)  -- Gold fallback
  end
  
  -- Update primary role button text
  if parent.primaryRoleButton and playerData.primaryRole then
    parent.primaryRoleButton:SetText(ROLE_DISPLAY[playerData.primaryRole] or "Unknown")
  end
  
  -- Update notes
  if parent.notesTextBox and parent.notesTextBox.editBox then
    parent.notesTextBox.editBox:SetText(playerData.notes or "")
  end
  
  -- Update ranking textboxes
  if parent.rankingTextBoxes and playerData.rankings then
    for _, role in ipairs(ROLES) do
      local textBox = parent.rankingTextBoxes[role]
      if textBox and textBox.editBox then
        textBox.editBox:SetText(tostring(playerData.rankings[role] or 1000))
      end
    end
  end
  
  -- Store current player being edited
  -- Ensure player has a primary role - if missing, assign default based on class
  local primaryRole = playerData.primaryRole
  if not primaryRole or primaryRole == "" then
    primaryRole = RosterMgmt.GetDefaultRoleForClass(playerData.class)
    -- Save the default role to the player data
    playerData.primaryRole = primaryRole
  end
  
  RosterMgmt.editingPlayer = {
    name = RosterMgmt.selectedPlayer,
    class = playerData.class,
    primaryRole = primaryRole,
    secondaryRoles = playerData.secondaryRoles,
    notes = playerData.notes,
    rankings = playerData.rankings
  }
end

-- Save player details
function RosterMgmt.SavePlayerDetails()
  if not RosterMgmt.editingPlayer then return end
  
  local playerName = RosterMgmt.editingPlayer.name
  local allPlayers = OGRH.SVM.GetPath("rosterManagement.players") or {}
  local playerData = allPlayers[playerName]
  
  if not playerData then return end
  
  -- Update player data
  playerData.primaryRole = RosterMgmt.editingPlayer.primaryRole
  
  -- Get notes from text box
  local parent = RosterMgmt.window.contentFrame.detailsPanel
  if parent.notesTextBox and parent.notesTextBox.editBox then
    playerData.notes = parent.notesTextBox.editBox:GetText()
  end
  
  playerData.lastUpdated = time()
  
  OGRH.SVM.SetPath("rosterManagement.players." .. playerName, playerData, {
    syncLevel = "MANUAL",
    componentType = "roster",
    source = "Roster"
  })
  
  RosterMgmt.RefreshUI()
end

-- Cancel player edit
function RosterMgmt.CancelPlayerEdit()
  RosterMgmt.RefreshDetailsPanel()
end

-- Create bottom toolbar
function RosterMgmt.CreateToolbar(window)
  local toolbar = CreateFrame("Frame", nil, window.contentFrame)
  toolbar:SetHeight(30)
  toolbar:SetPoint("BOTTOMLEFT", window.contentFrame, "BOTTOMLEFT", 5, 5)
  toolbar:SetPoint("BOTTOMRIGHT", window.contentFrame, "BOTTOMRIGHT", -5, 5)
  
  -- Import button
  local manualImportBtn = CreateFrame("Button", nil, toolbar)
  manualImportBtn:SetWidth(100)
  manualImportBtn:SetHeight(24)
  manualImportBtn:SetPoint("LEFT", toolbar, "LEFT", 5, 0)
  
  local manualImportText = manualImportBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  manualImportText:SetPoint("CENTER", manualImportBtn, "CENTER", 0, 0)
  manualImportText:SetText("Import")
  manualImportText:SetTextColor(1, 0.82, 0, 1)
  
  OGST.StyleButton(manualImportBtn)
  
  manualImportBtn:SetScript("OnClick", function()
    RosterMgmt.ShowManualImportDialog()
  end)
  
  window.toolbar = toolbar
end

-- Show add player dialog
function RosterMgmt.ShowAddPlayerDialog()
  local dialogData  -- Forward declare for closure
  local playerNameInput  -- Forward declare for closure
  
  dialogData = OGST.CreateDialog({
    title = "Add Player to Roster",
    width = 400,
    height = 200,
    content = "Enter player name. Class will be detected automatically if player is online or in your raid.",
    buttons = {
      {text = "Add", onClick = function()
        -- Get input from textbox
        if playerNameInput then
          local playerName = playerNameInput:GetText()
          if playerName and playerName ~= "" then
            -- Capitalize first letter
            playerName = string.upper(string.sub(playerName, 1, 1)) .. string.lower(string.sub(playerName, 2))
            
            -- Check if player already exists
            if not RosterMgmt.EnsureSV() then
              return
            end
            local allPlayers = OGRH.SVM.GetPath("rosterManagement.players") or {}
            if allPlayers[playerName] then
              return
            end
            
            -- Try to detect class using existing OGRH cache
            local class = OGRH.GetPlayerClass(playerName)
            
            if not class then
              return
            end
            
            -- Add player with detected class
            RosterMgmt.AddPlayer(playerName, class)
            RosterMgmt.RefreshUI()
          end
        end
      end},
      {text = "Cancel", onClick = function()
        -- Close dialog
      end}
    }
  })
  
  -- Create EditBox for player name input
  local inputBox = CreateFrame("EditBox", nil, dialogData.contentFrame)
  inputBox:SetHeight(24)
  inputBox:SetWidth(350)
  inputBox:SetPoint("TOP", dialogData.contentFrame, "TOP", 0, -30)
  inputBox:SetAutoFocus(true)
  inputBox:SetFontObject(GameFontHighlight)
  inputBox:SetMaxLetters(12) -- WoW character name limit
  
  -- EditBox background
  inputBox:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 }
  })
  inputBox:SetBackdropColor(0, 0, 0, 0.9)
  inputBox:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
  
  -- Add padding
  inputBox:SetTextInsets(8, 8, 0, 0)
  
  -- Handle Enter key to trigger Add button
  inputBox:SetScript("OnEnterPressed", function()
    if dialogData.buttons and dialogData.buttons[1] then
      dialogData.buttons[1]:Click()
    end
  end)
  
  -- Handle Escape key to close dialog
  inputBox:SetScript("OnEscapePressed", function()
    dialogData.backdrop:Hide()
  end)
  
  -- Store reference
  playerNameInput = inputBox
  
  dialogData.backdrop:Show()
end

-- Show remove player dialog
function RosterMgmt.ShowRemovePlayerDialog()
  if not RosterMgmt.selectedPlayer then return end
  
  local dialogData = OGST.CreateDialog({
    title = "Remove Player",
    width = 400,
    height = 180,
    content = "Are you sure you want to remove " .. RosterMgmt.selectedPlayer .. " from the roster?\n\nAll ranking data will be lost.",
    buttons = {
      {text = "Remove", onClick = function()
        RosterMgmt.RemovePlayer(RosterMgmt.selectedPlayer)
        RosterMgmt.selectedPlayer = nil
        RosterMgmt.RefreshUI()
        dialogData.backdrop:Hide()
      end},
      {text = "Cancel", onClick = function()
        dialogData.backdrop:Hide()
      end}
    }
  })
  
  dialogData.backdrop:Show()
end

-- Show manual import dialog
function RosterMgmt.ShowManualImportDialog()
  -- Window dimensions
  local windowWidth = 910
  local windowHeight = 419
  
  -- Calculate column dimensions
  -- Available width = windowWidth - left padding (5) - right padding (5) - gaps between 5 columns (4 * 5 = 20)
  local availableWidth = windowWidth - 10 - 20
  local columnWidth = math.floor(availableWidth / 5) - 15
  
  -- Calculate text box height
  -- Available height = windowHeight - header (40) - bottom padding (5) - label (~15) - gap (0) - autorank gap (5) - autorank button (24)
  local textBoxHeight = windowHeight - 40 - 5 - 15 - 0 - 5 - 24
  
  -- Create import window
  local window = OGST.CreateStandardWindow({
    name = "OGRH_ManualImportWindow",
    width = windowWidth,
    height = windowHeight,
    title = "Import Ranking Data",
    closeButton = true,
    escapeCloses = true,
    closeOnNewWindow = false
  })
  
  if not window then return end
  
  -- Set proper frame strata to ensure it appears on top
  window:SetFrameStrata("FULLSCREEN")
  
  -- Center the window
  window:ClearAllPoints()
  window:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  
  -- Storage for parsed player data
  local parsedPlayers = {
    TANKS = {},
    HEALERS = {},
    MELEE = {},
    RANGED = {}
  }
  
  -- Storage for original player data (before ELO calculations)
  local parsedPlayersOriginal = {
    TANKS = {},
    HEALERS = {},
    MELEE = {},
    RANGED = {}
  }
  
  -- Session-based tracking of segments used for Update ELO (resets when window closes)
  window.importedSegments = {}
  
  -- Storage for include checkboxes
  local includeCheckboxes = {}
  
  -- Storage for list frames
  local roleLists = {}
  
  -- Storage for role labels
  local roleLabels = {}
  
  -- Import CSV button - anchor to bottom left of content frame
  local importCsvBtn = CreateFrame("Button", nil, window.contentFrame)
  importCsvBtn:SetHeight(24)
  importCsvBtn:SetWidth(85)
  importCsvBtn:SetPoint("BOTTOMLEFT", window.contentFrame, "BOTTOMLEFT", 0, 0)
  
  local importCsvText = importCsvBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  importCsvText:SetPoint("CENTER", importCsvBtn, "CENTER", 0, 0)
  importCsvText:SetText("Import CSV")
  importCsvText:SetTextColor(1, 0.82, 0, 1)
  
  OGST.StyleButton(importCsvBtn)
  
  -- Update ELO button - saves current ELO rankings
  local updateEloBtn = CreateFrame("Button", nil, window.contentFrame)
  updateEloBtn:SetHeight(24)
  updateEloBtn:SetWidth(85)
  updateEloBtn:SetPoint("LEFT", importCsvBtn, "RIGHT", 5, 0)
  
  local updateEloText = updateEloBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  updateEloText:SetPoint("CENTER", updateEloBtn, "CENTER", 0, 0)
  updateEloText:SetText("Update ELO")
  updateEloText:SetTextColor(1, 0.82, 0, 1)
  
  OGST.StyleButton(updateEloBtn)
  
  -- Declare CSV controls first (needed by ParseAndPopulate function)
  local csvBackdrop, csvEditBox
  
  -- Function to reset all players to original ELO values (before any adjustments)
  local function ResetToOriginalELO()
    for _, role in ipairs(ROLES) do
      if parsedPlayers[role] then
        for i = 1, table.getn(parsedPlayers[role]) do
          local player = parsedPlayers[role][i]
          -- Find original data across all roles (player may have been dragged)
          for _, origRole in ipairs(ROLES) do
            if parsedPlayersOriginal[origRole] then
              for j = 1, table.getn(parsedPlayersOriginal[origRole]) do
                if parsedPlayersOriginal[origRole][j].name == player.name then
                  player.elo = parsedPlayersOriginal[origRole][j].elo
                  player.adjustment = 0
                  break
                end
              end
            end
          end
        end
      end
    end
  end
  
  -- Function to calculate ELO rankings for all included roles
  local function RankELO()
    local kFactor = 32  -- ELO adjustment sensitivity
    
    -- Reset all players to original ELO before recalculating
    ResetToOriginalELO()
    
    for _, role in ipairs(ROLES) do
      if includeCheckboxes[role] and includeCheckboxes[role]:GetChecked() then
        local players = parsedPlayers[role]
        
        if players and table.getn(players) > 1 then
          -- Sort by value (damage or healing) descending
          table.sort(players, function(a, b)
            return a.value > b.value
          end)
          
          -- Sequential comparison: compare each player with the one below them
          for i = 1, table.getn(players) - 1 do
            local playerA = players[i]  -- Higher DPS
            local playerB = players[i + 1]  -- Lower DPS
            
            -- Calculate expected scores using ELO formula
            local expectedA = 1 / (1 + 10 ^ ((playerB.elo - playerA.elo) / 400))
            local expectedB = 1 / (1 + 10 ^ ((playerA.elo - playerB.elo) / 400))
            
            -- Actual scores: winner gets 1, loser gets 0
            local actualA = 1  -- PlayerA has higher DPS
            local actualB = 0  -- PlayerB has lower DPS
            
            -- Calculate ELO changes
            local changeA = math.floor(kFactor * (actualA - expectedA) + 0.5)
            local changeB = math.floor(kFactor * (actualB - expectedB) + 0.5)
            
            -- Update ELO values
            playerA.elo = playerA.elo + changeA
            playerB.elo = playerB.elo + changeB
            
            -- Update adjustments for display (set directly, not accumulate)
            playerA.adjustment = playerA.adjustment + changeA
            playerB.adjustment = playerB.adjustment + changeB
          end
        end
      end
    end
  end
  
  -- Refresh display from current parsedPlayers data (without re-parsing CSV)
  local function RefreshDisplay()
    -- Clear role lists
    for role, list in pairs(roleLists) do
      list:Clear()
    end
    
    -- Populate role lists from parsedPlayers
    for _, role in ipairs(ROLES) do
      if roleLists[role] and parsedPlayers[role] then
        -- Sort by value (damage or healing) descending
        table.sort(parsedPlayers[role], function(a, b)
          return a.value > b.value
        end)
        
        -- Add to list
        for j = 1, table.getn(parsedPlayers[role]) do
          local player = parsedPlayers[role][j]
          local r, g, b = GetClassColor(player.class)
          
          local displayText = string.format("%s %d [%s%d]", 
            player.name, 
            player.elo,
            (player.adjustment >= 0 and "+" or ""),
            player.adjustment
          )
          
          -- Capture role in closure
          local playerRole = role
          local playerData = player
          
          local item = roleLists[role]:AddItem({
            text = displayText,
            textColor = {r = r, g = g, b = b, a = 1},
            onDelete = function()
              -- Remove from parsed data
              if parsedPlayers[playerRole] then
                for k = 1, table.getn(parsedPlayers[playerRole]) do
                  if parsedPlayers[playerRole][k].name == player.name then
                    table.remove(parsedPlayers[playerRole], k)
                    break
                  end
                end
              end
              
              -- Also remove from original data
              if parsedPlayersOriginal[playerRole] then
                for k = 1, table.getn(parsedPlayersOriginal[playerRole]) do
                  if parsedPlayersOriginal[playerRole][k].name == player.name then
                    table.remove(parsedPlayersOriginal[playerRole], k)
                    break
                  end
                end
              end
              
              -- Recalculate ELO for remaining players
              RankELO()
              RefreshDisplay()
            end
          })
          
          -- Enable drag on the item (similar to RolesUI.lua pattern)
          if item then
            item:RegisterForDrag("LeftButton")
            item:SetMovable(true)
            
            -- Create a drag frame that follows the cursor
            local dragFrame = CreateFrame("Frame", nil, UIParent)
            dragFrame:SetWidth(150)
            dragFrame:SetHeight(20)
            dragFrame:SetFrameStrata("TOOLTIP")
            dragFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            dragFrame:Hide()
            
            -- Add background to make it visible
            local dragBg = dragFrame:CreateTexture(nil, "BACKGROUND")
            dragBg:SetAllPoints()
            dragBg:SetTexture("Interface\\Buttons\\WHITE8X8")
            dragBg:SetVertexColor(0.3, 0.3, 0.3, 0.9)
            
            local dragText = dragFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            dragText:SetPoint("CENTER", dragFrame, "CENTER", 0, 0)
            dragText:SetText(displayText)
            dragText:SetTextColor(r, g, b, 1)
            
            item:SetScript("OnDragStart", function()
              dragFrame:Show()
              dragFrame:SetScript("OnUpdate", function()
                local x, y = GetCursorPosition()
                local scale = UIParent:GetEffectiveScale()
                dragFrame:ClearAllPoints()
                dragFrame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x/scale, y/scale)
              end)
            end)
            
            item:SetScript("OnDragStop", function()
              dragFrame:Hide()
              dragFrame:SetScript("OnUpdate", nil)
              
              -- Find which role list we're over
              local x, y = GetCursorPosition()
              local scale = UIParent:GetEffectiveScale()
              x = x/scale
              y = y/scale
              
              local targetRole = nil
              for checkRole, checkList in pairs(roleLists) do
                local left, right, bottom, top = checkList:GetLeft(), checkList:GetRight(), checkList:GetBottom(), checkList:GetTop()
                if left and right and bottom and top and x >= left and x <= right and y >= bottom and y <= top then
                  targetRole = checkRole
                  break
                end
              end
              
              -- Only move if we're dropping into a different role
              if targetRole and targetRole ~= playerRole then
                -- Remove from source role
                if parsedPlayers[playerRole] then
                  for k = 1, table.getn(parsedPlayers[playerRole]) do
                    if parsedPlayers[playerRole][k].name == playerData.name then
                      table.remove(parsedPlayers[playerRole], k)
                      break
                    end
                  end
                end
                
                -- Look up the proper damage/healing value for the target role from segment data
                local targetValue = 0
                local foundData = false
                
                if window.selectedSegment and window.selectedSegment.type == "pending" then
                  local pendingSegments = OGRH.SVM.GetPath("rosterManagement.pendingSegments") or {}
                  local segment = pendingSegments[window.selectedSegment.index]
                  
                  if segment then
                    if targetRole == "HEALERS" then
                      -- Look for effective healing data (use value, fallback to total)
                      if segment.effectiveHealingData and segment.effectiveHealingData[playerData.name] then
                        local healingData = segment.effectiveHealingData[playerData.name]
                        if type(healingData) == "table" then
                          targetValue = healingData.value or healingData.total or 0
                        else
                          targetValue = healingData or 0
                        end
                        foundData = true
                      end
                    else
                      -- Look for damage data (use value, fallback to total)
                      if segment.damageData and segment.damageData[playerData.name] then
                        local damageData = segment.damageData[playerData.name]
                        if type(damageData) == "table" then
                          targetValue = damageData.value or damageData.total or 0
                        else
                          targetValue = damageData or 0
                        end
                        foundData = true
                      end
                    end
                  end
                end
                
                -- Fallback: look in parsedPlayersOriginal if no segment data found
                if not foundData then
                  for _, origRole in ipairs(ROLES) do
                    if parsedPlayersOriginal[origRole] then
                      for j = 1, table.getn(parsedPlayersOriginal[origRole]) do
                        if parsedPlayersOriginal[origRole][j].name == playerData.name then
                          targetValue = parsedPlayersOriginal[origRole][j].value
                          break
                        end
                      end
                    end
                  end
                end
                
                -- Look up the player's ELO for the TARGET role from their profile
                local targetELO = 1000  -- Default
                local allPlayers = OGRH.SVM.GetPath("rosterManagement.players") or {}
                if allPlayers[playerData.name] and 
                   allPlayers[playerData.name].rankings and
                   allPlayers[playerData.name].rankings[targetRole] then
                  targetELO = allPlayers[playerData.name].rankings[targetRole]
                end
                
                -- Add to target role with correct value and target role's ELO
                table.insert(parsedPlayers[targetRole], {
                  name = playerData.name,
                  class = playerData.class,
                  value = targetValue,
                  elo = targetELO,
                  adjustment = 0  -- Reset adjustment since we'll recalculate
                })
                
                -- Also update parsedPlayersOriginal for this player in the target role
                -- First remove from original role if exists
                for _, origRole in ipairs(ROLES) do
                  if parsedPlayersOriginal[origRole] then
                    for k = 1, table.getn(parsedPlayersOriginal[origRole]) do
                      if parsedPlayersOriginal[origRole][k].name == playerData.name then
                        table.remove(parsedPlayersOriginal[origRole], k)
                        break
                      end
                    end
                  end
                end
                -- Then add to target role in original data
                table.insert(parsedPlayersOriginal[targetRole], {
                  name = playerData.name,
                  class = playerData.class,
                  value = targetValue,
                  elo = targetELO,
                  adjustment = 0
                })
                
                -- Recalculate ELO and refresh
                RankELO()
                RefreshDisplay()
              end
            end)
          end
        end
      end
    end
  end
  
  -- Parse CSV and populate role lists (supports both legacy CSV and segment recovery format)
  local function ParseAndPopulate()
    -- Clear existing data
    for role in pairs(parsedPlayers) do
      parsedPlayers[role] = {}
    end
    
    for role in pairs(parsedPlayersOriginal) do
      parsedPlayersOriginal[role] = {}
    end
    
    -- Clear role lists
    for role, list in pairs(roleLists) do
      list:Clear()
    end
    
    local csvText = csvEditBox:GetText()
    if not csvText or csvText == "" then return end
    
    -- Remove leading/trailing quotes if present
    csvText = string.gsub(csvText, "^\"", "")
    csvText = string.gsub(csvText, "\"$", "")
    
    -- Split by newlines
    local lines = {}
    for line in string.gfind(csvText, "[^\n]+") do
      table.insert(lines, line)
    end
    
    if table.getn(lines) == 0 then return end
    
    -- Detect format: check first line for segment recovery format
    local firstLine = lines[1]
    local isSegmentFormat = string.match(firstLine, "^SEGMENT_META%|")
    
    if isSegmentFormat then
      -- SEGMENT RECOVERY FORMAT
      -- Parse metadata from first line
      local metaParts = {}
      for part in string.gfind(firstLine, "[^|]+") do
        table.insert(metaParts, part)
      end
      
      if table.getn(metaParts) < 8 or metaParts[1] ~= "SEGMENT_META" then
        OGRH.Msg("|cffff0000[RH-Roster]|r Invalid segment format")
        return
      end
      
      local segmentName = metaParts[2]
      local createdAt = metaParts[3]
      local raidName = metaParts[4]
      local raidIndex = tonumber(metaParts[5]) or 0
      local encounterName = metaParts[6]
      local encounterIndex = tonumber(metaParts[7]) or 0
      local combatTime = tonumber(metaParts[8]) or 0
      
      -- Build segment data structures
      local damageData = {}
      local effectiveHealingData = {}
      local totalHealingData = {}
      local playerRoles = {}
      local playerCount = 0
      
      -- Parse player lines (format: Name|Class|Role|Damage|EffHealing|TotalHealing)
      for i = 2, table.getn(lines) do
        local line = lines[i]
        local parts = {}
        for part in string.gfind(line, "[^|]+") do
          table.insert(parts, part)
        end
        
        if table.getn(parts) >= 6 then
          local playerName = parts[1]
          local class = parts[2]
          local role = parts[3]
          local damage = tonumber(parts[4]) or 0
          local effectiveHealing = tonumber(parts[5]) or 0
          local totalHealing = tonumber(parts[6]) or 0
          
          playerCount = playerCount + 1
          playerRoles[playerName] = role
          
          if damage > 0 then
            damageData[playerName] = {total = damage, value = damage}
          end
          
          if effectiveHealing > 0 then
            effectiveHealingData[playerName] = {total = effectiveHealing, value = effectiveHealing}
          end
          
          if totalHealing > 0 then
            totalHealingData[playerName] = {total = totalHealing, value = totalHealing}
          end
          
          -- Get player's ELO for their assigned role
          local currentElo = 1000
          local allPlayers = OGRH.SVM.GetPath("rosterManagement.players") or {}
          if allPlayers[playerName] and 
             allPlayers[playerName].rankings and
             allPlayers[playerName].rankings[role] then
            currentElo = allPlayers[playerName].rankings[role]
          end
          
          -- Add to appropriate role list based on their assigned role
          local playerData = {
            name = playerName,
            class = class,
            value = (role == "HEALERS") and effectiveHealing or damage,
            elo = currentElo,
            adjustment = 0
          }
          
          table.insert(parsedPlayers[role], playerData)
          table.insert(parsedPlayersOriginal[role], {
            name = playerName,
            class = class,
            value = playerData.value,
            elo = currentElo,
            adjustment = 0
          })
        end
      end
      
      -- Create a pending segment entry from recovered data
      local timestamp = time()
      local segmentId = "recovered_" .. timestamp .. "_" .. string.gsub(string.lower(segmentName), "%s", "_")
      
      local segment = {
        segmentId = segmentId,
        name = segmentName .. " [RECOVERED]",
        timestamp = timestamp,
        createdAt = createdAt,
        
        raidName = raidName,
        raidIndex = raidIndex,
        encounterName = encounterName ~= "" and encounterName or nil,
        encounterIndex = encounterIndex,
        
        combatTime = combatTime,
        effectiveCombatTime = {},  -- Not recoverable from combat log
        
        damageData = damageData,
        totalHealingData = totalHealingData,
        effectiveHealingData = effectiveHealingData,
        playerRoles = playerRoles,
        
        imported = false,
        importedAt = nil,
        importedBy = nil,
        
        expiresAt = timestamp + (2 * 86400),  -- 2 days
        
        playerCount = playerCount,
      }
      
      -- Add to pending segments
      local pendingSegments = OGRH.SVM.GetPath("rosterManagement.pendingSegments") or {}
      table.insert(pendingSegments, 1, segment)  -- Insert at front (newest first)
      
      OGRH.SVM.SetPath("rosterManagement.pendingSegments", pendingSegments, {
        source = "Roster",
        action = "recover",
        sync = false,
      })
      
      -- Store segment reference so we can import it
      window.selectedSegment = {type = "pending", index = 1}
      
      OGRH.Msg("|cff00ff00[RH-Roster]|r Recovered segment: " .. segmentName)
      OGRH.Msg("|cffaaaaaa[RH-Roster]|r " .. playerCount .. " players, " .. string.format("%.1f", combatTime) .. "s combat")
      
      -- Refresh pending segments list if it exists
      if window.PopulatePendingSegmentsList then
        window.PopulatePendingSegmentsList()
      end
      
    else
      -- LEGACY CSV FORMAT (Name,Damage,DPS)
      for i = 1, table.getn(lines) do
        local line = lines[i]
        -- Parse CSV: PlayerName,Damage,DPS
        local name, damage, dps = string.match(line, "([^,]+),([^,]+),([^,]+)")
        
        if name and dps then
          -- Trim whitespace
          name = string.gsub(name, "^%s*(.-)%s*$", "%1")
          dps = string.gsub(dps, "^%s*(.-)%s*$", "%1")
          
          -- Get player class from OGRH cache
          local class = OGRH.GetPlayerClass(name)
          if not class then
            class = "UNKNOWN"
          end
          
          -- Determine role: check roster data first, then RolesUI saved data, then default
          local role = "RANGED"  -- Default fallback
          local allPlayers = OGRH.SVM.GetPath("rosterManagement.players") or {}
          if allPlayers[name] then
            -- Player exists in roster management
            role = allPlayers[name].primaryRole
          elseif OGRH_GetPlayerRole and OGRH_GetPlayerRole(name) then
            -- Player has saved role from RolesUI (via SVM)
            role = OGRH_GetPlayerRole(name)
          else
            -- Use default role for class
            role = RosterMgmt.GetDefaultRoleForClass(class)
          end
          
          -- Get current ELO or default
          local currentElo = 1000
          if allPlayers[name] and 
             allPlayers[name].rankings and
             allPlayers[name].rankings[role] then
            currentElo = allPlayers[name].rankings[role]
          end
          
          -- TODO: Calculate adjustment (placeholder)
          local adjustment = 0
          
          -- Store player data
          local playerData = {
            name = name,
            class = class,
            value = tonumber(dps) or 0,  -- Still parsing DPS from CSV for backwards compatibility
            elo = currentElo,
            adjustment = adjustment
          }
          table.insert(parsedPlayers[role], playerData)
          
          -- Backup original data (before ELO)
          table.insert(parsedPlayersOriginal[role], {
            name = name,
            class = class,
            value = tonumber(dps) or 0,
            elo = currentElo,
            adjustment = 0
          })
        end
      end
    end
    
    -- Automatically rank ELO after parsing
    RankELO()
    
    -- Refresh display
    RefreshDisplay()
  end
  
  importCsvBtn:SetScript("OnClick", function()
    ParseAndPopulate()
  end)
  
  -- Update ELO button - saves current rankings to player records
  updateEloBtn:SetScript("OnClick", function()
    if not RosterMgmt.EnsureSV() then
      return
    end
    
    -- Check if this segment has already been used for Update ELO
    local segmentKey
    if window.selectedSegment then
      if window.selectedSegment.type == "current" then
        segmentKey = "current"
      elseif window.selectedSegment.type == "total" then
        segmentKey = "total"
      elseif window.selectedSegment.type == "segment" then
        segmentKey = "segment_" .. tostring(window.selectedSegment.index)
      elseif window.selectedSegment.type == "pending" then
        local pendingSegments = OGRH.SVM.GetPath("rosterManagement.pendingSegments") or {}
        local segment = pendingSegments[window.selectedSegment.index]
        if segment then
          segmentKey = "pending_" .. tostring(segment.segmentId or window.selectedSegment.index)
        end
      end
    end
    
    if segmentKey and window.importedSegments[segmentKey] then
      OGRH.Msg("|cffff8800[RH-Roster]|r This segment has already been used for Update ELO. Select a different segment.")
      return
    end
    
    local updateCount = 0
    local addCount = 0
    local allPlayers = OGRH.SVM.GetPath("rosterManagement.players") or {}
    
    for _, role in ipairs(ROLES) do
      -- Only process roles that have their Include checkbox checked
      if includeCheckboxes[role] and includeCheckboxes[role]:GetChecked() and parsedPlayers[role] then
        for i = 1, table.getn(parsedPlayers[role]) do
          local player = parsedPlayers[role][i]
          local playerName = player.name
          
          -- Check if player exists in database
          if allPlayers[playerName] then
            -- Update existing player's ranking for this role
            allPlayers[playerName].rankings[role] = player.elo
            allPlayers[playerName].lastUpdated = time()
            updateCount = updateCount + 1
          else
            -- Add new player with this role as primary
            if RosterMgmt.AddPlayer(playerName, player.class) then
              -- Reload allPlayers after adding
              allPlayers = OGRH.SVM.GetPath("rosterManagement.players") or {}
              -- Set this role as primary and update its ranking
              allPlayers[playerName].primaryRole = role
              allPlayers[playerName].rankings[role] = player.elo
              addCount = addCount + 1
            end
          end
        end
      end
    end
    
    -- Write back all changes
    OGRH.SVM.SetPath("rosterManagement.players", allPlayers, {
      syncLevel = "MANUAL",
      componentType = "roster",
      source = "Roster"
    })
    
    if addCount > 0 then
      OGRH.Msg(string.format("|cff00ff00[RH-Roster]|r Added %d new players, updated %d players", addCount, updateCount))
    else
      OGRH.Msg(string.format("|cff00ff00[RH-Roster]|r Updated ELO ratings for %d players", updateCount))
    end
    
    -- Mark this segment as used
    if segmentKey then
      window.importedSegments[segmentKey] = true
    end
    
    -- If pending segment, mark it as imported in SavedVariables
    if window.selectedSegment and window.selectedSegment.type == "pending" then
      local pendingSegments = OGRH.SVM.GetPath("rosterManagement.pendingSegments") or {}
      local segment = pendingSegments[window.selectedSegment.index]
      if segment then
        segment.imported = true
        segment.importedAt = time()
        segment.importedBy = UnitName("player")
        OGRH.SVM.SetPath("rosterManagement.pendingSegments", pendingSegments, {
          source = "RosterMgmt",
          action = "import_segment",
          sync = false,
        })
      end
    end
    
    -- Disable the Update ELO button
    updateEloBtn:Disable()
    updateEloText:SetTextColor(0.5, 0.5, 0.5, 1)
    
    -- Refresh the DPS Meter segment list to remove the used segment
    if window.PopulateDPSMateList and window.importSource == "DPSMate" then
      window.PopulateDPSMateList()
    elseif window.PopulatePendingSegmentsList and window.importSource == "Pending Segments" then
      window.PopulatePendingSegmentsList()
    end
    
    -- Refresh the main roster display if it's open
    if OGRH_RosterWindow and OGRH_RosterWindow:IsVisible() then
      RosterMgmt.RefreshPlayerList()
    end
  end)
  
  -- Create 4 role columns from right to left (Ranged, Melee, Healers, Tanks)
  -- Reverse ROLES to anchor from right to left
  local reversedRoles = {"RANGED", "MELEE", "HEALERS", "TANKS"}
  
  for i, role in ipairs(reversedRoles) do
    -- Role label
    local roleLabel = OGST.CreateStaticText(window.contentFrame, {
      text = ROLE_DISPLAY[role] .. ":",
      font = "GameFontNormal",
      align = "LEFT",
      width = columnWidth
    })
    
    -- Position first column (Ranged) at top-right, others relative to previous label moving left
    if i == 1 then
      OGST.AnchorElement(roleLabel, window.contentFrame, {position = "top", align = "right"})
    else
      OGST.AnchorElement(roleLabel, roleLabels[reversedRoles[i-1]], {position = "left"})
    end
    
    roleLabels[role] = roleLabel
    
    -- Include checkbox - anchor to bottom aligned with role label (right-aligned)
    local checkboxContainer, checkButton = OGST.CreateCheckbox(window.contentFrame, {
      width = columnWidth,
      label = "Include",
      checked = (role ~= "TANKS"),
      labelPosition = "RIGHT"
    })
    OGST.AnchorElement(checkboxContainer, roleLabel, {
      position = "alignBottom",
      parent = window.contentFrame,
      align = "right"
    })
    
    includeCheckboxes[role] = checkButton
    
    -- Add onChange handler to recalculate or restore ELO when checkbox changes
    local capturedRole = role
    checkButton:SetScript("OnClick", function()
      -- Always reset all players to original ELO first
      ResetToOriginalELO()
      
      -- Then recalculate ELO for all currently checked roles
      RankELO()
      
      -- Refresh display to show updated values
      RefreshDisplay()
    end)
    
    -- Create scrollable list for this role - fill space between label and checkbox
    local listFrame = OGST.CreateStyledScrollList(window.contentFrame, columnWidth, 0, true)
    OGST.AnchorElement(listFrame, roleLabel, {
      position = "fillBetween",
      bottomElement = checkboxContainer
    })
    
    roleLists[role] = listFrame
  end
  
  -- Track selected import source
  window.importSource = "Pending Segments"
  
  -- Forward declare controls for use in menu onClick handlers
  local csvBackdrop, csvEditBox
  local dpsMeterList
  local sourceMenuContainer, sourceMenuBtn
  
  -- Forward declare import function
  local ImportFromDPSMate
  local PopulateDPSMateList
  local PopulatePendingSegmentsList
  local ImportFromPendingSegment
  
  -- Function to populate DPSMate segment list
  PopulateDPSMateList = function()
    dpsMeterList:Clear()
    
    if not DPSMateHistory or not DPSMateHistory.names then
      dpsMeterList:AddItem({
        text = "DPSMate not loaded or no data available",
        textAlign = "LEFT",
        onClick = function() end
      })
      return
    end
    
    -- Add "Current Fight" option
    local isCurrentUsed = window.importedSegments["current"]
    dpsMeterList:AddItem({
      text = isCurrentUsed and "Current Fight [IMPORTED]" or "Current Fight",
      textAlign = "LEFT",
      textColor = isCurrentUsed and {r = 0.5, g = 0.5, b = 0.5, a = 1} or nil,
      onClick = function()
        if isCurrentUsed then
          OGRH.Msg("|cffff8800[RH-Roster]|r This segment has already been imported.")
          return
        end
        window.selectedSegment = {type = "current"}
        ImportFromDPSMate("current")
      end
    })
    
    -- Add "Total" option
    local isTotalUsed = window.importedSegments["total"]
    dpsMeterList:AddItem({
      text = isTotalUsed and "Total [IMPORTED]" or "Total",
      textAlign = "LEFT",
      textColor = isTotalUsed and {r = 0.5, g = 0.5, b = 0.5, a = 1} or nil,
      onClick = function()
        if isTotalUsed then
          OGRH.Msg("|cffff8800[RH-Roster]|r This segment has already been imported.")
          return
        end
        window.selectedSegment = {type = "total"}
        ImportFromDPSMate("total")
      end
    })
    
    -- Add each segment (only if it has data)
    local segmentCount = table.getn(DPSMateHistory.names)
    for i = 1, segmentCount do
      local segmentName = DPSMateHistory.names[i]
      if segmentName then
        local segmentKey = "segment_" .. i
        
        -- Check if segment has any data
        local hasDamageData = DPSMateHistory.DMGDone and DPSMateHistory.DMGDone[i] and next(DPSMateHistory.DMGDone[i]) ~= nil
        local hasHealingData = DPSMateHistory.EHealing and DPSMateHistory.EHealing[i] and next(DPSMateHistory.EHealing[i]) ~= nil
        
        if hasDamageData or hasHealingData then
          local capturedIndex = i  -- Capture in closure
          local isSegmentUsed = window.importedSegments[segmentKey]
          
          dpsMeterList:AddItem({
            text = isSegmentUsed and (segmentName .. " [IMPORTED]") or segmentName,
            textAlign = "LEFT",
            textColor = isSegmentUsed and {r = 0.5, g = 0.5, b = 0.5, a = 1} or nil,
            onClick = function()
              if window.importedSegments["segment_" .. capturedIndex] then
                OGRH.Msg("|cffff8800[RH-Roster]|r This segment has already been imported.")
                return
              end
              window.selectedSegment = {type = "segment", index = capturedIndex}
              ImportFromDPSMate("segment", capturedIndex)
            end
          })
        end
      end
    end
  end
  
  -- Store on window for use by Update ELO button
  window.PopulateDPSMateList = PopulateDPSMateList
  
  -- Function to populate ShaguDPS segment list (placeholder for now)
  local function PopulateShaguDPSList()
    dpsMeterList:Clear()
    
    dpsMeterList:AddItem({
      text = "ShaguDPS integration coming soon",
      textAlign = "LEFT",
      onClick = function()
        window.selectedSegment = {type = "none"}
      end
    })
  end
  
  -- Function to populate Pending Segments list
  PopulatePendingSegmentsList = function()
    dpsMeterList:Clear()
    
    local pendingSegments = OGRH.SVM.GetPath("rosterManagement.pendingSegments") or {}
    
    if table.getn(pendingSegments) == 0 then
      dpsMeterList:AddItem({
        text = "No pending segments captured yet",
        textAlign = "LEFT",
        onClick = function() end
      })
      return
    end
    
    -- Display segments (newest first)
    for i = 1, table.getn(pendingSegments) do
      local segment = pendingSegments[i]
      local segmentKey = "pending_" .. tostring(segment.segmentId or i)
      local isSegmentUsed = window.importedSegments[segmentKey] or segment.imported
      
      -- Format: "Magmadar [11] - 260206 19:44"
      local displayName = segment.name or "Unknown"
      if segment.playerCount then
        displayName = displayName .. " [" .. segment.playerCount .. "]"
      end
      
      -- Add timestamp in format YYMMDD HH:MM
      if segment.timestamp then
        local timeStr = date("%y%m%d %H:%M", segment.timestamp)
        displayName = displayName .. " - " .. timeStr
      end
      
      if isSegmentUsed then
        displayName = displayName .. " [IMPORTED]"
      end
      
      local capturedIndex = i  -- Capture in closure
      
      dpsMeterList:AddItem({
        text = displayName,
        textAlign = "LEFT",
        textColor = isSegmentUsed and {r = 0.5, g = 0.5, b = 0.5, a = 1} or nil,
        onClick = function()
          if window.importedSegments["pending_" .. tostring(pendingSegments[capturedIndex].segmentId or capturedIndex)] or pendingSegments[capturedIndex].imported then
            OGRH.Msg("|cffff8800[RH-Roster]|r This segment has already been imported.")
            return
          end
          window.selectedSegment = {type = "pending", index = capturedIndex}
          ImportFromPendingSegment(capturedIndex)
        end
      })
    end
  end
  
  -- Store on window for use by Update ELO button
  window.PopulatePendingSegmentsList = PopulatePendingSegmentsList
  
  -- Define import function (forward declared above)
  ImportFromDPSMate = function(segmentType, segmentIndex)
    -- Clear existing data
    for role in pairs(parsedPlayers) do
      parsedPlayers[role] = {}
      parsedPlayersOriginal[role] = {}
    end
    
    -- Re-enable Update ELO button for new segment
    updateEloBtn:Enable()
    updateEloText:SetTextColor(1, 0.82, 0, 1)
    
    -- Determine which data set to use
    local damageData, healingData
    if segmentType == "current" then
      damageData = DPSMateDamageDone and DPSMateDamageDone[2]
      healingData = DPSMateEHealing and DPSMateEHealing[2]
    elseif segmentType == "total" then
      damageData = DPSMateDamageDone and DPSMateDamageDone[1]
      healingData = DPSMateEHealing and DPSMateEHealing[1]
    elseif segmentType == "segment" and segmentIndex then
      damageData = DPSMateHistory and DPSMateHistory.DMGDone and DPSMateHistory.DMGDone[segmentIndex]
      healingData = DPSMateHistory and DPSMateHistory.EHealing and DPSMateHistory.EHealing[segmentIndex]
    end
    
    if not damageData and not healingData then
      OGRH.Msg("|cffff0000[RH-Roster]|r No data available for selected segment")
      -- Clear the lists
      for role in pairs(parsedPlayers) do
        parsedPlayers[role] = {}
      end
      RefreshDisplay()
      return
    end
    
    local allPlayers = OGRH.SVM.GetPath("rosterManagement.players") or {}
    
    -- Track which players have been added to prevent duplicates
    local addedPlayers = {}
    
    -- Build reverse lookup: playerID -> playerName
    local playerIdToName = {}
    if DPSMateUser then
      for playerName, playerInfo in pairs(DPSMateUser) do
        local playerId = playerInfo[1]
        if playerId then
          playerIdToName[tostring(playerId)] = playerName
        end
      end
    end
    
    -- Process healers FIRST (before damage dealers) so they get healing values
    if healingData then
      for playerId, playerData in pairs(healingData) do
        local playerName = playerIdToName[tostring(playerId)]
        
        if playerName and DPSMateUser and DPSMateUser[playerName] and not addedPlayers[playerName] then
          local class = DPSMateUser[playerName][2] or "UNKNOWN"
          
          -- Handle different data structures
          local healing = 0
          if type(playerData) == "number" then
            healing = playerData
          elseif type(playerData) == "table" then
            if playerData.i then
              if type(playerData.i) == "number" then
                healing = playerData.i
              elseif type(playerData.i) == "table" then
                healing = playerData.i[1] or 0
              end
            elseif playerData[1] then
              healing = playerData[1]
            end
          end
          
          OGRH.Msg("|cff00ff00[RH-Roster]|r Healer: " .. playerName .. " = " .. healing .. " healing")
          
          -- Determine if player should be in HEALERS based on role assignment
          local shouldBeHealer = false
          
          -- 1. Check RolesUI
          if OGRH_GetPlayerRole then
            local rolesUIRole = OGRH_GetPlayerRole(playerName)
            if rolesUIRole == "HEALERS" then
              shouldBeHealer = true
            elseif rolesUIRole then
              -- Player has a different role assigned in RolesUI, skip them
              shouldBeHealer = false
            end
          end
          
          -- 2. Check rosterManagement primaryRole (only if RolesUI didn't have them)
          if shouldBeHealer == false and not OGRH_GetPlayerRole or not OGRH_GetPlayerRole(playerName) then
            if allPlayers[playerName] and allPlayers[playerName].primaryRole then
              if allPlayers[playerName].primaryRole == "HEALERS" then
                shouldBeHealer = true
              else
                -- Player has a different role in rosterManagement, skip them
                shouldBeHealer = false
              end
            end
          end
          
          -- 3. If no role assigned anywhere, check if they're a healing class with >2k healing
          if shouldBeHealer == false and not OGRH_GetPlayerRole or not OGRH_GetPlayerRole(playerName) then
            if not allPlayers[playerName] or not allPlayers[playerName].primaryRole then
              local upperClass = string.upper(class)
              local isHealingClass = (upperClass == "PRIEST" or upperClass == "PALADIN" or upperClass == "DRUID" or upperClass == "SHAMAN")
              if healing > 2000 and isHealingClass then
                shouldBeHealer = true
              end
            end
          end
          
          if shouldBeHealer then
            local currentElo = 1000
            if allPlayers[playerName] and allPlayers[playerName].rankings and allPlayers[playerName].rankings["HEALERS"] then
              currentElo = allPlayers[playerName].rankings["HEALERS"]
            end
            
            local playerData = {
              name = playerName,
              class = string.upper(class),
              dps = healing,
              elo = currentElo,
              adjustment = 0
            }
            table.insert(parsedPlayers["HEALERS"], playerData)
            
            -- Backup original data
            table.insert(parsedPlayersOriginal["HEALERS"], {
              name = playerName,
              class = string.upper(class),
              dps = healing,
              elo = currentElo,
              adjustment = 0
            })
            
            addedPlayers[playerName] = true
          end
        end
      end
    end
    
    -- Process damage dealers AFTER healers
    if damageData then
      local damageCount = 0
      for playerId, playerData in pairs(damageData) do
        damageCount = damageCount + 1
        
        local playerName = playerIdToName[tostring(playerId)]
        
        if playerName and DPSMateUser and DPSMateUser[playerName] and not addedPlayers[playerName] then
          local class = DPSMateUser[playerName][2] or "UNKNOWN"
          
          -- Handle different data structures
          local damage = 0
          if type(playerData) == "number" then
            damage = playerData
          elseif type(playerData) == "table" then
            if playerData.i then
              if type(playerData.i) == "number" then
                damage = playerData.i
              elseif type(playerData.i) == "table" then
                damage = playerData.i[1] or 0
              end
            elseif playerData[1] then
              damage = playerData[1]
            end
          end
          
          -- Determine role with priority: RolesUI > rosterManagement primaryRole > class-based
          local role
          
          -- 1. Check RolesUI - accept any role (TANKS, HEALERS, MELEE, RANGED)
          if OGRH_GetPlayerRole then
            local rolesUIRole = OGRH_GetPlayerRole(playerName)
            if rolesUIRole then
              role = rolesUIRole
            end
          end
          
          -- 2. Check rosterManagement primaryRole - accept any role
          if not role then
            if allPlayers[playerName] and allPlayers[playerName].primaryRole then
              role = allPlayers[playerName].primaryRole
            end
          end
          
          -- 3. Assign based on class
          if not role then
            local upperClass = string.upper(class)
            if upperClass == "MAGE" or upperClass == "WARLOCK" or upperClass == "PRIEST" or upperClass == "HUNTER" then
              role = "RANGED"
            else
              role = "MELEE"  -- WARRIOR, ROGUE, PALADIN, DRUID, SHAMAN
            end
          end
          
          local currentElo = 1000
          if allPlayers[playerName] and allPlayers[playerName].rankings and allPlayers[playerName].rankings[role] then
            currentElo = allPlayers[playerName].rankings[role]
          end
          
          local playerData = {
            name = playerName,
            class = string.upper(class),
            dps = damage,
            elo = currentElo,
            adjustment = 0
          }
          table.insert(parsedPlayers[role], playerData)
          
          -- Backup original data
          table.insert(parsedPlayersOriginal[role], {
            name = playerName,
            class = string.upper(class),
            dps = damage,
            elo = currentElo,
            adjustment = 0
          })
          
          addedPlayers[playerName] = true
        end
      end
    end
    
    -- Automatically rank ELO after import
    RankELO()
    
    -- Refresh display
    RefreshDisplay()
  end
  
  -- Function to import from Pending Segment
  ImportFromPendingSegment = function(segmentIndex)
    -- Clear existing data
    for role in pairs(parsedPlayers) do
      parsedPlayers[role] = {}
      parsedPlayersOriginal[role] = {}
    end
    
    -- Re-enable Update ELO button for new segment
    updateEloBtn:Enable()
    updateEloText:SetTextColor(1, 0.82, 0, 1)
    
    local pendingSegments = OGRH.SVM.GetPath("rosterManagement.pendingSegments") or {}
    local segment = pendingSegments[segmentIndex]
    
    if not segment then
      OGRH.Msg("|cffff0000[RH-Roster]|r Segment not found")
      RefreshDisplay()
      return
    end
    
    local allPlayers = OGRH.SVM.GetPath("rosterManagement.players") or {}
    local addedPlayers = {}
    
    -- Process healers FIRST
    if segment.effectiveHealingData then
      for playerName, healingData in pairs(segment.effectiveHealingData) do
        if not addedPlayers[playerName] then
          local class = OGRH.GetPlayerClass(playerName) or "UNKNOWN"
          
          -- Extract numeric healing value (use value field, fallback to total)
          local healing = 0
          if type(healingData) == "number" then
            healing = healingData
          elseif type(healingData) == "table" then
            healing = healingData.value or healingData.total or 0
          end
          
          -- Check if player should be in HEALERS using stored role
          local shouldBeHealer = false
          if segment.playerRoles and segment.playerRoles[playerName] == "HEALERS" then
            shouldBeHealer = true
          else
            -- Fallback to old logic if no stored role
            -- Check RolesUI
            if OGRH_GetPlayerRole then
              local rolesUIRole = OGRH_GetPlayerRole(playerName)
              if rolesUIRole == "HEALERS" then
                shouldBeHealer = true
              elseif rolesUIRole then
                shouldBeHealer = false
              end
            end
            
            -- Check rosterManagement primaryRole
            if shouldBeHealer == false and (not OGRH_GetPlayerRole or not OGRH_GetPlayerRole(playerName)) then
              if allPlayers[playerName] and allPlayers[playerName].primaryRole then
                if allPlayers[playerName].primaryRole == "HEALERS" then
                  shouldBeHealer = true
                else
                  shouldBeHealer = false
                end
              end
            end
            
            -- If no role assigned, check if healing class with >2k healing
            if shouldBeHealer == false and (not OGRH_GetPlayerRole or not OGRH_GetPlayerRole(playerName)) then
              if not allPlayers[playerName] or not allPlayers[playerName].primaryRole then
                local upperClass = string.upper(class)
                local isHealingClass = (upperClass == "PRIEST" or upperClass == "PALADIN" or upperClass == "DRUID" or upperClass == "SHAMAN")
                if healing > 2000 and isHealingClass then
                  shouldBeHealer = true
                end
              end
            end
          end
          
          if shouldBeHealer then
            local currentElo = 1000
            if allPlayers[playerName] and allPlayers[playerName].rankings and allPlayers[playerName].rankings["HEALERS"] then
              currentElo = allPlayers[playerName].rankings["HEALERS"]
            end
            
            table.insert(parsedPlayers["HEALERS"], {
              name = playerName,
              class = string.upper(class),
              value = healing,
              elo = currentElo,
              adjustment = 0
            })
            
            table.insert(parsedPlayersOriginal["HEALERS"], {
              name = playerName,
              class = string.upper(class),
              value = healing,
              elo = currentElo,
              adjustment = 0
            })
            
            addedPlayers[playerName] = true
          end
        end
      end
    end
    
    -- Process damage dealers AFTER healers
    if segment.damageData then
      for playerName, damageData in pairs(segment.damageData) do
        if not addedPlayers[playerName] then
          local class = OGRH.GetPlayerClass(playerName) or "UNKNOWN"
          local upperClass = string.upper(class)
          
          -- Extract numeric damage value (use value field, fallback to total)
          local damage = 0
          if type(damageData) == "number" then
            damage = damageData
          elseif type(damageData) == "table" then
            damage = damageData.value or damageData.total or 0
          end
          
          -- Determine role using stored playerRoles first
          local role = "RANGED"
          if segment.playerRoles and segment.playerRoles[playerName] then
            role = segment.playerRoles[playerName]
          else
            -- Fallback to old logic if no stored role
            -- Check RolesUI first
            if OGRH_GetPlayerRole then
              local rolesUIRole = OGRH_GetPlayerRole(playerName)
              if rolesUIRole and rolesUIRole ~= "HEALERS" then
                role = rolesUIRole
              end
            end
            
            -- Check rosterManagement primaryRole
            if (not OGRH_GetPlayerRole or not OGRH_GetPlayerRole(playerName)) and allPlayers[playerName] and allPlayers[playerName].primaryRole then
              if allPlayers[playerName].primaryRole ~= "HEALERS" then
                role = allPlayers[playerName].primaryRole
              end
            end
            
            -- Use default role for class if no role assigned
            if (not OGRH_GetPlayerRole or not OGRH_GetPlayerRole(playerName)) and (not allPlayers[playerName] or not allPlayers[playerName].primaryRole) then
              role = RosterMgmt.GetDefaultRoleForClass(upperClass)
            end
          end
          
          -- Skip if they ended up as HEALERS
          if role ~= "HEALERS" then
            local currentElo = 1000
            if allPlayers[playerName] and allPlayers[playerName].rankings and allPlayers[playerName].rankings[role] then
              currentElo = allPlayers[playerName].rankings[role]
            end
            
            table.insert(parsedPlayers[role], {
              name = playerName,
              class = upperClass,
              value = damage,
              elo = currentElo,
              adjustment = 0
            })
            
            table.insert(parsedPlayersOriginal[role], {
              name = playerName,
              class = upperClass,
              value = damage,
              elo = currentElo,
              adjustment = 0
            })
            
            addedPlayers[playerName] = true
          end
        end
      end
    end
    
    -- Automatically rank ELO after import
    RankELO()
    
    -- Refresh display
    RefreshDisplay()
  end
  
  -- Function to update UI based on selected source
  local function UpdateSourceUI(source)
    window.importSource = source
    
    -- Count pending segments for display
    local pendingCount = 0
    if OGRH.SVM and OGRH.SVM.GetPath then
      local pendingSegments = OGRH.SVM.GetPath("rosterManagement.pendingSegments") or {}
      for i = 1, table.getn(pendingSegments) do
        if not pendingSegments[i].imported then
          pendingCount = pendingCount + 1
        end
      end
    end
    
    local displayText = source
    if source == "Pending Segments" then
      displayText = "Pending Segments (" .. pendingCount .. ")"
    end
    sourceMenuBtn:SetText(displayText)
    
    if source == "CSV" then
      csvBackdrop:Show()
      dpsMeterList:Hide()
      importCsvBtn:Enable()
      importCsvText:SetTextColor(1, 0.82, 0, 1)
    elseif source == "DPSMate" then
      csvBackdrop:Hide()
      dpsMeterList:Show()
      PopulateDPSMateList()
      importCsvBtn:Disable()
      importCsvText:SetTextColor(0.5, 0.5, 0.5, 1)
    elseif source == "ShaguDPS" then
      csvBackdrop:Hide()
      dpsMeterList:Show()
      PopulateShaguDPSList()
      importCsvBtn:Disable()
      importCsvText:SetTextColor(0.5, 0.5, 0.5, 1)
    elseif source == "Pending Segments" then
      csvBackdrop:Hide()
      dpsMeterList:Show()
      PopulatePendingSegmentsList()
      importCsvBtn:Disable()
      importCsvText:SetTextColor(0.5, 0.5, 0.5, 1)
    end
  end
  
  -- Import source menu button - create first so it can be referenced
  -- Calculate pending segment count for default display
  local initialPendingCount = 0
  if OGRH.SVM and OGRH.SVM.GetPath then
    local pendingSegs = OGRH.SVM.GetPath("rosterManagement.pendingSegments") or {}
    for i = 1, table.getn(pendingSegs) do
      if not pendingSegs[i].imported then
        initialPendingCount = initialPendingCount + 1
      end
    end
  end
  
  sourceMenuContainer, sourceMenuBtn = OGST.CreateMenuButton(window.contentFrame, {
    label = "Source:",
    labelAnchor = "LEFT",
    buttonText = "Pending Segments (" .. initialPendingCount .. ")",
    menuItems = {
      {
        text = "Pending Segments",
        selected = true,
        onClick = function()
          UpdateSourceUI("Pending Segments")
        end
      },
      {
        text = "DPSMate",
        onClick = function()
          UpdateSourceUI("DPSMate")
        end
      },
      {
        text = "ShaguDPS",
        onClick = function()
          UpdateSourceUI("ShaguDPS")
        end
      },
      {
        text = "CSV",
        onClick = function()
          UpdateSourceUI("CSV")
        end
      }
    },
    singleSelect = true
  })
  
  OGST.AnchorElement(sourceMenuContainer, window.contentFrame, {
    position = "spanHorizontal",
    rightElement = roleLabels["TANKS"],
    verticalAlign = "top"
  })
  
  -- CSV text box - fill space between source menu button and Import CSV button
  csvBackdrop, csvEditBox = OGST.CreateScrollingTextBox(window.contentFrame, columnWidth + 96, textBoxHeight - 8)
  OGST.AnchorElement(csvBackdrop, sourceMenuContainer, {
    position = "below",
    offsetY = 6
  })
  
  -- DPS Meter list - fill same space as CSV text box
  dpsMeterList = OGST.CreateStyledScrollList(window.contentFrame, columnWidth + 96, textBoxHeight - 8, false)
  window.dpsMeterList = dpsMeterList  -- Store reference on window for Update ELO button access
  OGST.AnchorElement(dpsMeterList, sourceMenuContainer, {
    position = "below",
    offsetY = 6
  })
  
  -- Initialize UI to show Pending Segments list
  UpdateSourceUI("Pending Segments")
  
  window:Show()
end

-- Refresh entire UI
function RosterMgmt.RefreshUI()
  RosterMgmt.RefreshPlayerList()
  RosterMgmt.RefreshDetailsPanel()
end
