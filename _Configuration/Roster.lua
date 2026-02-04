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
  local columnWidth = math.floor(availableWidth / 5)
  
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
  
  -- Flag to track if Rank ELO has been used on current import
  local hasRankedElo = false
  
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
  
  -- Rank ELO button
  local rankEloBtn = CreateFrame("Button", nil, window.contentFrame)
  rankEloBtn:SetHeight(24)
  rankEloBtn:SetWidth(75)
  rankEloBtn:SetPoint("LEFT", importCsvBtn, "RIGHT", 5, 0)
  
  local rankEloText = rankEloBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  rankEloText:SetPoint("CENTER", rankEloBtn, "CENTER", 0, 0)
  rankEloText:SetText("Rank ELO")
  rankEloText:SetTextColor(1, 0.82, 0, 1)
  
  OGST.StyleButton(rankEloBtn)
  
  -- Update ELO button - saves current ELO rankings
  local updateEloBtn = CreateFrame("Button", nil, window.contentFrame)
  updateEloBtn:SetHeight(24)
  updateEloBtn:SetWidth(85)
  updateEloBtn:SetPoint("LEFT", rankEloBtn, "RIGHT", 5, 0)
  
  local updateEloText = updateEloBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  updateEloText:SetPoint("CENTER", updateEloBtn, "CENTER", 0, 0)
  updateEloText:SetText("Update ELO")
  updateEloText:SetTextColor(1, 0.82, 0, 1)
  
  OGST.StyleButton(updateEloBtn)
  
  -- Declare CSV controls first (needed by ParseAndPopulate function)
  local csvBackdrop, csvEditBox
  
  -- Refresh display from current parsedPlayers data (without re-parsing CSV)
  local function RefreshDisplay()
    -- Clear role lists
    for role, list in pairs(roleLists) do
      list:Clear()
    end
    
    -- Populate role lists from parsedPlayers
    for _, role in ipairs(ROLES) do
      if roleLists[role] and parsedPlayers[role] then
        -- Sort by DPS descending
        table.sort(parsedPlayers[role], function(a, b)
          return a.dps > b.dps
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
          roleLists[role]:AddItem({
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
              RefreshDisplay()  -- Refresh without re-parsing CSV
            end
          })
        end
      end
    end
  end
  
  -- Parse CSV and populate role lists
  local function ParseAndPopulate()
    -- Clear existing data
    for role in pairs(parsedPlayers) do
      parsedPlayers[role] = {}
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
    
    -- Parse each line
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
        table.insert(parsedPlayers[role], {
          name = name,
          class = class,
          dps = tonumber(dps) or 0,
          elo = currentElo,
          adjustment = adjustment
        })
      end
    end
    
    -- Refresh display
    RefreshDisplay()
  end
  
  importCsvBtn:SetScript("OnClick", function()
    ParseAndPopulate()
    -- Reset Rank ELO state for new import
    hasRankedElo = false
    rankEloBtn:Enable()
    rankEloText:SetTextColor(1, 0.82, 0, 1)
  end)
  
  -- Rank ELO button - Process ELO rankings using sequential comparison
  -- TODO: Add aura tracking and ELO modifiers
  -- Track if the winner has specific raid buffs/auras (Boomkin aura, Windfury totem, 
  -- Atiesh, etc.) and apply modifiers to ELO adjustments. Players with these buffs 
  -- gain artificial DPS advantage, so their ELO gains should be reduced and their 
  -- opponents' losses should be minimized to reflect true skill differences.
  rankEloBtn:SetScript("OnClick", function()
    -- Calculate ELO adjustments for included roles
    local kFactor = 32  -- ELO adjustment sensitivity
    
    for _, role in ipairs(ROLES) do
      if includeCheckboxes[role] then
        local isChecked = includeCheckboxes[role]:GetChecked()
        if isChecked then
          local players = parsedPlayers[role]
          
          if players and table.getn(players) > 1 then
            -- Sort by DPS (already done, but ensure order)
            table.sort(players, function(a, b)
              return a.dps > b.dps
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
              
              -- Update adjustments for display
              playerA.adjustment = (playerA.adjustment or 0) + changeA
              playerB.adjustment = (playerB.adjustment or 0) + changeB
            end
          end
        end
      end
    end
    
    -- Refresh all displays with updated ELO values
    RefreshDisplay()
    
    -- Disable Rank ELO button after first use
    hasRankedElo = true
    rankEloBtn:Disable()
    rankEloText:SetTextColor(0.5, 0.5, 0.5, 1)
    
    OGRH.Msg("|cffffaa00[RH-Roster]|r ELO rankings calculated. Use 'Update ELO' to save these rankings.")
  end)
  
  -- Update ELO button - saves current rankings to player records
  updateEloBtn:SetScript("OnClick", function()
    if not RosterMgmt.EnsureSV() then
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
    
    -- Create scrollable list for this role - fill space between label and checkbox
    local listFrame = OGST.CreateStyledScrollList(window.contentFrame, columnWidth, 0, true)
    OGST.AnchorElement(listFrame, roleLabel, {
      position = "fillBetween",
      bottomElement = checkboxContainer
    })
    
    roleLists[role] = listFrame
  end
  
  -- Track selected import source
  window.importSource = "DPSMate"
  
  -- Forward declare controls for use in menu onClick handlers
  local csvBackdrop, csvEditBox
  local dpsMeterList
  local sourceMenuContainer, sourceMenuBtn
  
  -- Function to update UI based on selected source
  local function UpdateSourceUI(source)
    window.importSource = source
    sourceMenuBtn:SetText(source)
    
    if source == "CSV" then
      csvBackdrop:Show()
      dpsMeterList:Hide()
    else
      csvBackdrop:Hide()
      dpsMeterList:Show()
    end
  end
  
  -- Import source menu button - create first so it can be referenced
  sourceMenuContainer, sourceMenuBtn = OGST.CreateMenuButton(window.contentFrame, {
    label = "Source:",
    labelAnchor = "LEFT",
    buttonText = "DPSMate",
    menuItems = {
      {
        text = "DPSMate",
        selected = true,
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
  csvBackdrop, csvEditBox = OGST.CreateScrollingTextBox(window.contentFrame, 0, 0)
  OGST.AnchorElement(csvBackdrop, sourceMenuContainer, {
    position = "fillBetween",
    bottomElement = importCsvBtn,
    offsetYTop = 8,
    offsetYBottom = 5
  })
  
  -- DPS Meter list - fill same space as CSV text box
  dpsMeterList = OGST.CreateStyledScrollList(window.contentFrame, 0, 0, true)
  OGST.AnchorElement(dpsMeterList, sourceMenuContainer, {
    position = "fillBetween",
    bottomElement = importCsvBtn,
    offsetYTop = 8,
    offsetYBottom = 5
  })
  
  -- Initialize UI to show DPS meter list
  UpdateSourceUI("DPSMate")
  
  window:Show()
end

-- Refresh entire UI
function RosterMgmt.RefreshUI()
  RosterMgmt.RefreshPlayerList()
  RosterMgmt.RefreshDetailsPanel()
end
