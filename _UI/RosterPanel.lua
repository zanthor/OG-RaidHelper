-- _UI/RosterPanel.lua
-- Shared roster panel component used by EncounterMgmt and BuffManager.
-- Provides a player list with source toggle (Raid/Roster), role filter,
-- search box, section headers, class-colored names, and drag-and-drop.
--
-- Usage:
--   local panel = OGRH.CreateRosterPanel(parentFrame, {
--     anchor = {"TOPLEFT", sibling, "TOPRIGHT", 10, 0},
--     ...
--   })
--   panel:Refresh()
--
-- See Documentation/2.1/BuffManager.md "Shared Roster Panel" for full API docs.

OGRH = OGRH or {}

--------------------------------------------------------------------------------
-- Helper: Create a simple dropdown menu anchored below a button
--------------------------------------------------------------------------------
local function CreateDropdownMenu(anchorBtn, menuItems, onSelect)
  local menuFrame = CreateFrame("Frame", nil, UIParent)
  menuFrame:SetWidth(85)
  menuFrame:SetHeight(table.getn(menuItems) * 20 + 10)
  menuFrame:SetPoint("TOPLEFT", anchorBtn, "BOTTOMLEFT", 0, 0)
  menuFrame:SetFrameStrata("FULLSCREEN_DIALOG")
  menuFrame:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 12,
    insets = {left = 3, right = 3, top = 3, bottom = 3}
  })
  menuFrame:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
  menuFrame:EnableMouse(true)

  menuFrame:SetScript("OnHide", function()
    this:SetParent(nil)
  end)

  for i, item in ipairs(menuItems) do
    local btn = CreateFrame("Button", nil, menuFrame)
    btn:SetWidth(79)
    btn:SetHeight(18)
    btn:SetPoint("TOPLEFT", menuFrame, "TOPLEFT", 3, -3 - ((i-1) * 20))

    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    bg:SetVertexColor(0.2, 0.2, 0.2, 0.5)
    bg:Hide()

    local text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("LEFT", btn, "LEFT", 5, 0)
    text:SetText(item.text)

    local capturedValue = item.value
    local capturedLabel = item.label or item.text

    btn:SetScript("OnEnter", function() bg:Show() end)
    btn:SetScript("OnLeave", function() bg:Hide() end)
    btn:SetScript("OnClick", function()
      onSelect(capturedValue, capturedLabel)
      menuFrame:Hide()
    end)
  end

  -- Auto-hide when mouse leaves both menu and anchor button
  menuFrame:SetScript("OnUpdate", function()
    if not MouseIsOver(menuFrame) and not MouseIsOver(anchorBtn) then
      menuFrame:Hide()
    end
  end)

  return menuFrame
end

--------------------------------------------------------------------------------
-- OGRH.CreateRosterPanel(parent, config) → panel
--------------------------------------------------------------------------------
--
-- Config keys:
--   width              number   Panel width (default 200)
--   height             number   Panel height (default 390)
--   anchor             table    SetPoint args, e.g. {"TOPLEFT", ref, "TOPRIGHT", 10, 0}
--   showUnassignedFilter  bool  Include "Unassigned" in role filter (default false)
--   showGuildMembers      bool  Show guild members in Raid mode (default false)
--   defaultSource         string "Raid" or "Roster" (default "Raid")
--   canDrag            function(panel) → bool  Permission check before drag
--   onDragStart        function(panel, playerName, playerClass, classColor)
--   onDragStop         function(panel, playerName, playerClass)  Consumer handles drop
--   onRightClick       function(panel, btn, playerName, section)
--   getAssignedPlayers function() → table|nil  Set of assigned names for "unassigned" filter
--   getEncounterContext function() → raidIdx, encounterIdx  For unassigned filter SVM lookup
--
-- Returned panel fields:
--   panel (Frame)                  The outer container
--   panel.selectedUnitSource       "Raid" or "Roster"
--   panel.selectedPlayerRole       "all", "tanks", "healers", "melee", "ranged", "unassigned"
--   panel.unitSourceBtn            The source toggle button
--   panel.playerRoleBtn            The role filter button
--   panel.searchBox                The EditBox
--   panel.scrollChild              Scroll child frame
--   panel.scrollFrame              Scroll frame
--   panel.scrollBar                Scroll bar
--   panel.contentWidth             Width available for list items
--   panel.currentDragFrame         Currently active drag frame (or nil)
--   panel.draggedPlayerName        Name of player currently being dragged (or nil)
--   panel:Refresh()                Rebuild the player list
--
function OGRH.CreateRosterPanel(parent, config)
  config = config or {}
  local width = config.width or 200
  local height = config.height or 390
  local showUnassignedFilter = config.showUnassignedFilter or false
  local showGuildMembers = config.showGuildMembers or false

  ---------------------------------------------------------------------------
  -- Panel frame
  ---------------------------------------------------------------------------
  local panel = CreateFrame("Frame", nil, parent)
  panel:SetWidth(width)
  panel:SetHeight(height)
  if config.anchor then
    panel:SetPoint(unpack(config.anchor))
  end
  panel:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 12,
    insets = {left = 3, right = 3, top = 3, bottom = 3}
  })
  panel:SetBackdropColor(0.1, 0.1, 0.1, 0.8)

  -- State
  panel.selectedUnitSource = config.defaultSource or "Raid"
  panel.selectedPlayerRole = "all"
  panel.currentDragFrame = nil
  panel.draggedPlayerName = nil

  ---------------------------------------------------------------------------
  -- "Players:" label
  ---------------------------------------------------------------------------
  local playersLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  playersLabel:SetPoint("TOP", panel, "TOP", 0, -10)
  playersLabel:SetText("Players:")

  ---------------------------------------------------------------------------
  -- Unit source button (Raid / Roster)
  ---------------------------------------------------------------------------
  local unitSourceBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  unitSourceBtn:SetWidth(85)
  unitSourceBtn:SetHeight(24)
  unitSourceBtn:SetPoint("TOP", playersLabel, "BOTTOM", -47, -5)
  unitSourceBtn:SetText(panel.selectedUnitSource)
  OGRH.StyleButton(unitSourceBtn)
  panel.unitSourceBtn = unitSourceBtn

  unitSourceBtn:SetScript("OnClick", function()
    CreateDropdownMenu(unitSourceBtn, {
      {text = "Raid", value = "Raid"},
      {text = "Roster", value = "Roster"}
    }, function(value, label)
      panel.selectedUnitSource = value
      unitSourceBtn:SetText(value)
      panel:Refresh()
    end)
  end)

  ---------------------------------------------------------------------------
  -- Role filter button
  ---------------------------------------------------------------------------
  local playerRoleBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  playerRoleBtn:SetWidth(85)
  playerRoleBtn:SetHeight(24)
  playerRoleBtn:SetPoint("LEFT", unitSourceBtn, "RIGHT", 5, 0)
  playerRoleBtn:SetText("All Roles")
  OGRH.StyleButton(playerRoleBtn)
  panel.playerRoleBtn = playerRoleBtn

  local roleMenuItems = {
    {text = "All Roles", value = "all", label = "All Roles"},
    {text = "Tanks",     value = "tanks", label = "Tanks"},
    {text = "Healers",   value = "healers", label = "Healers"},
    {text = "Melee",     value = "melee", label = "Melee"},
    {text = "Ranged",    value = "ranged", label = "Ranged"},
  }
  if showUnassignedFilter then
    table.insert(roleMenuItems, {text = "Unassigned", value = "unassigned", label = "Unassigned"})
  end

  playerRoleBtn:SetScript("OnClick", function()
    CreateDropdownMenu(playerRoleBtn, roleMenuItems, function(value, label)
      panel.selectedPlayerRole = value
      playerRoleBtn:SetText(label)
      panel:Refresh()
    end)
  end)

  ---------------------------------------------------------------------------
  -- Search box
  ---------------------------------------------------------------------------
  local searchBox = CreateFrame("EditBox", nil, panel)
  searchBox:SetWidth(width - 20)
  searchBox:SetHeight(24)
  searchBox:SetPoint("TOP", unitSourceBtn, "BOTTOM", 47, -5)
  searchBox:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 12,
    insets = {left = 3, right = 3, top = 3, bottom = 3}
  })
  searchBox:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
  searchBox:SetFontObject(GameFontNormal)
  searchBox:SetAutoFocus(false)
  searchBox:SetText("")
  searchBox:SetScript("OnEscapePressed", function() this:ClearFocus() end)
  searchBox:SetScript("OnEnterPressed", function() this:ClearFocus() end)
  searchBox:SetScript("OnTextChanged", function()
    panel:Refresh()
  end)
  panel.searchBox = searchBox

  -- Search placeholder text
  local searchPlaceholder = searchBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  searchPlaceholder:SetPoint("LEFT", searchBox, "LEFT", 5, 0)
  searchPlaceholder:SetText("|cff888888Search...|r")
  searchPlaceholder:SetTextColor(0.5, 0.5, 0.5)

  searchBox:SetScript("OnEditFocusGained", function()
    searchPlaceholder:Hide()
  end)

  searchBox:SetScript("OnEditFocusLost", function()
    if searchBox:GetText() == "" then
      searchPlaceholder:Show()
    end
  end)

  ---------------------------------------------------------------------------
  -- Scroll list
  ---------------------------------------------------------------------------
  local listHeight = height - 105  -- room for label + buttons + search + padding
  local listFrame, scrollFrame, scrollChild, scrollBar, contentWidth =
    OGRH.CreateStyledScrollList(panel, width - 20, listHeight)
  listFrame:SetPoint("TOP", searchBox, "BOTTOM", 0, -5)
  panel.scrollChild = scrollChild
  panel.scrollFrame = scrollFrame
  panel.scrollBar = scrollBar
  panel.contentWidth = contentWidth

  ---------------------------------------------------------------------------
  -- Refresh: rebuild the player list
  ---------------------------------------------------------------------------
  function panel:Refresh()
    -- Clear existing items
    local children = {self.scrollChild:GetChildren()}
    for _, child in ipairs(children) do
      child:Hide()
      child:SetParent(nil)
    end

    -- Get search text
    local searchText = ""
    if self.searchBox then
      searchText = string.lower(self.searchBox:GetText() or "")
    end

    -- Build assigned-players set for "Unassigned" filter
    local assignedInEncounter = {}
    if self.selectedPlayerRole == "unassigned" and config.getAssignedPlayers then
      assignedInEncounter = config.getAssignedPlayers() or {}
    end

    -- Class filters for each role (mixed case for compatibility)
    local classFilters = {
      tanks   = {WARRIOR = true, Warrior = true, PALADIN = true, Paladin = true, DRUID = true, Druid = true, SHAMAN = true, Shaman = true},
      healers = {DRUID = true, Druid = true, PRIEST = true, Priest = true, SHAMAN = true, Shaman = true, PALADIN = true, Paladin = true},
      melee   = {WARRIOR = true, Warrior = true, ROGUE = true, Rogue = true, HUNTER = true, Hunter = true, SHAMAN = true, Shaman = true, DRUID = true, Druid = true, PALADIN = true, Paladin = true},
      ranged  = {MAGE = true, Mage = true, WARLOCK = true, Warlock = true, HUNTER = true, Hunter = true, DRUID = true, Druid = true, PRIEST = true, Priest = true}
    }

    local raidPlayers   = {}
    local onlinePlayers = {}
    local offlinePlayers = {}
    local rosterPlayers = {}

    local unitSource = self.selectedUnitSource or "Raid"

    if unitSource == "Roster" then
      -- Get planning roster from Invites module
      local planningRoster = OGRH.Invites and OGRH.Invites.GetPlanningRoster and OGRH.Invites.GetPlanningRoster()
      if planningRoster and type(planningRoster) == "table" then
        for role, players in pairs(planningRoster) do
          if type(players) == "table" then
            for _, playerData in ipairs(players) do
              if type(playerData) == "table" and playerData.name then
                local playerName = playerData.name
                local playerClass = playerData.class or OGRH.GetPlayerClass(playerName) or "WARRIOR"

                -- Apply search filter
                if searchText == "" or string.find(string.lower(playerName), searchText, 1, true) then
                  local includePlayer = false
                  local playerSection = "roster"

                  if self.selectedPlayerRole == "all" then
                    includePlayer = true
                    if role == "TANKS" then playerSection = "tanks"
                    elseif role == "HEALERS" then playerSection = "healers"
                    elseif role == "MELEE" then playerSection = "melee"
                    elseif role == "RANGED" then playerSection = "ranged"
                    end
                  elseif self.selectedPlayerRole == "unassigned" then
                    if not assignedInEncounter[playerName] then
                      includePlayer = true
                      if role == "TANKS" then playerSection = "tanks"
                      elseif role == "HEALERS" then playerSection = "healers"
                      elseif role == "MELEE" then playerSection = "melee"
                      elseif role == "RANGED" then playerSection = "ranged"
                      end
                    end
                  else
                    local roleFilter = self.selectedPlayerRole
                    if roleFilter == "tanks" and role == "TANKS" then includePlayer = true
                    elseif roleFilter == "healers" and role == "HEALERS" then includePlayer = true
                    elseif roleFilter == "melee" and role == "MELEE" then includePlayer = true
                    elseif roleFilter == "ranged" and role == "RANGED" then includePlayer = true
                    end
                    playerSection = "roster"
                  end

                  if includePlayer then
                    table.insert(rosterPlayers, {
                      name = playerName,
                      class = playerClass,
                      section = playerSection
                    })
                  end
                end
              end
            end
          end
        end
      end
    else
      -- Raid mode
      local numRaid = GetNumRaidMembers()
      if numRaid > 0 then
        -- Build role assignments from RolesUI
        local roleAssignments = {}
        local tankPlayers   = OGRH.GetRolePlayers("TANKS") or {}
        local healerPlayers = OGRH.GetRolePlayers("HEALERS") or {}
        local meleePlayers  = OGRH.GetRolePlayers("MELEE") or {}
        local rangedPlayers = OGRH.GetRolePlayers("RANGED") or {}

        for _, name in ipairs(tankPlayers) do
          if not roleAssignments[name] then roleAssignments[name] = {} end
          roleAssignments[name].tanks = true
        end
        for _, name in ipairs(healerPlayers) do
          if not roleAssignments[name] then roleAssignments[name] = {} end
          roleAssignments[name].healers = true
        end
        for _, name in ipairs(meleePlayers) do
          if not roleAssignments[name] then roleAssignments[name] = {} end
          roleAssignments[name].melee = true
        end
        for _, name in ipairs(rangedPlayers) do
          if not roleAssignments[name] then roleAssignments[name] = {} end
          roleAssignments[name].ranged = true
        end

        for i = 1, numRaid do
          local name, _, _, _, class, _, _, online = GetRaidRosterInfo(i)
          if name and class then
            -- Cache the class
            OGRH.classCache[name] = string.upper(class)

            -- Apply search filter
            if searchText == "" or string.find(string.lower(name), searchText, 1, true) then
              local include = false
              local playerSection = "raid"

              if self.selectedPlayerRole == "all" then
                include = true
                local assignments = roleAssignments[name]
                if assignments then
                  if assignments.tanks then playerSection = "tanks"
                  elseif assignments.healers then playerSection = "healers"
                  elseif assignments.melee then playerSection = "melee"
                  elseif assignments.ranged then playerSection = "ranged"
                  end
                end
              elseif self.selectedPlayerRole == "unassigned" then
                if not assignedInEncounter[name] then
                  include = true
                  local rAssign = roleAssignments[name]
                  if rAssign then
                    if rAssign.tanks then playerSection = "tanks"
                    elseif rAssign.healers then playerSection = "healers"
                    elseif rAssign.melee then playerSection = "melee"
                    elseif rAssign.ranged then playerSection = "ranged"
                    end
                  end
                end
              else
                local assignments = roleAssignments[name]
                if assignments and assignments[self.selectedPlayerRole] then
                  include = true
                  playerSection = "raid"
                end
              end

              if include then
                table.insert(raidPlayers, {name = name, class = string.upper(class), section = playerSection})
              end
            end
          end
        end
      end

      -- Build raid name set for deduplication
      local raidNames = {}
      for _, p in ipairs(raidPlayers) do
        raidNames[p.name] = true
      end

      -- Optionally show guild members (level 60, not in raid)
      if showGuildMembers and self.selectedPlayerRole == "all" then
        local numGuildMembers = GetNumGuildMembers(true)
        for i = 1, numGuildMembers do
          local name, _, _, level, class, _, _, _, online = GetGuildRosterInfo(i)
          if name and level == 60 and not raidNames[name] and class then
            OGRH.classCache[name] = string.upper(class)
            if searchText == "" or string.find(string.lower(name), searchText, 1, true) then
              if online then
                table.insert(onlinePlayers, {name = name, class = string.upper(class), section = "online"})
              else
                table.insert(offlinePlayers, {name = name, class = string.upper(class), section = "offline"})
              end
            end
          end
        end
      end
    end  -- end unitSource check

    -- Sort each section
    table.sort(raidPlayers, function(a, b)
      if a.section ~= b.section then
        local order = {tanks = 1, healers = 2, melee = 3, ranged = 4, raid = 5}
        return (order[a.section] or 6) < (order[b.section] or 6)
      end
      return a.name < b.name
    end)
    table.sort(rosterPlayers, function(a, b)
      if a.section ~= b.section then
        local order = {tanks = 1, healers = 2, melee = 3, ranged = 4, roster = 5}
        return (order[a.section] or 6) < (order[b.section] or 6)
      end
      return a.name < b.name
    end)
    table.sort(onlinePlayers, function(a, b) return a.name < b.name end)
    table.sort(offlinePlayers, function(a, b) return a.name < b.name end)

    -- Combine all sections
    local allPlayers = {}
    if unitSource == "Roster" then
      for _, p in ipairs(rosterPlayers) do table.insert(allPlayers, p) end
    else
      for _, p in ipairs(raidPlayers) do table.insert(allPlayers, p) end
      for _, p in ipairs(onlinePlayers) do table.insert(allPlayers, p) end
      for _, p in ipairs(offlinePlayers) do table.insert(allPlayers, p) end
    end

    -- Render section headers and player items
    local yOffset = 0
    local lastSection = nil
    local sc = self.scrollChild

    for _, playerData in ipairs(allPlayers) do
      -- Section header when section changes
      if playerData.section ~= lastSection then
        local sectionLabel = ""
        if playerData.section == "raid" then sectionLabel = "In Raid"
        elseif playerData.section == "roster" then sectionLabel = "Planning Roster"
        elseif playerData.section == "tanks" then sectionLabel = "Tanks"
        elseif playerData.section == "healers" then sectionLabel = "Healers"
        elseif playerData.section == "melee" then sectionLabel = "Melee"
        elseif playerData.section == "ranged" then sectionLabel = "Ranged"
        elseif playerData.section == "online" then sectionLabel = "Online"
        elseif playerData.section == "offline" then sectionLabel = "Offline"
        end

        if sectionLabel ~= "" then
          local headerFrame = CreateFrame("Frame", nil, sc)
          headerFrame:SetWidth(170)
          headerFrame:SetHeight(16)
          headerFrame:SetPoint("TOPLEFT", sc, "TOPLEFT", 2, -yOffset)

          local headerText = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
          headerText:SetPoint("LEFT", headerFrame, "LEFT", 0, 0)
          headerText:SetText("|cffaaaaaa" .. sectionLabel .. "|r")

          yOffset = yOffset + 18
        end

        lastSection = playerData.section
      end

      local playerName = playerData.name
      local playerClass = playerData.class

      local playerBtn = OGRH.CreateStyledListItem(sc, self.contentWidth, OGRH.LIST_ITEM_HEIGHT, "Button")
      playerBtn:SetPoint("TOPLEFT", sc, "TOPLEFT", 2, -yOffset)

      -- Class color
      local class = OGRH.GetPlayerClass(playerName)
      local nameText = playerBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      nameText:SetPoint("LEFT", playerBtn, "LEFT", 5, 0)
      nameText:SetText(playerName)

      local classColor
      if class and RAID_CLASS_COLORS[class] then
        classColor = RAID_CLASS_COLORS[class]
        nameText:SetTextColor(classColor.r, classColor.g, classColor.b)
      else
        classColor = {r = 1, g = 1, b = 1}
        nameText:SetTextColor(1, 1, 1)
      end

      -- Store metadata on the button
      playerBtn.playerName = playerName
      playerBtn.playerSection = playerData.section
      playerBtn:RegisterForDrag("LeftButton")
      playerBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

      -- Drag start
      local capturedName = playerName
      local capturedClass = playerClass
      local capturedColor = classColor
      local capturedSection = playerData.section

      playerBtn:SetScript("OnDragStart", function()
        -- Permission check
        if config.canDrag and not config.canDrag(panel) then
          return
        end

        -- Create visual drag frame
        local dragFrame = CreateFrame("Frame", nil, UIParent)
        dragFrame:SetWidth(150)
        dragFrame:SetHeight(20)
        dragFrame:SetFrameStrata("TOOLTIP")
        dragFrame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", 0, 0)

        local dragBg = dragFrame:CreateTexture(nil, "BACKGROUND")
        dragBg:SetAllPoints()
        dragBg:SetTexture("Interface\\Buttons\\WHITE8X8")
        dragBg:SetVertexColor(0.3, 0.3, 0.3, 0.9)

        local dragText = dragFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        dragText:SetPoint("CENTER", dragFrame, "CENTER", 0, 0)
        dragText:SetText(capturedName)
        dragText:SetTextColor(capturedColor.r, capturedColor.g, capturedColor.b)

        dragFrame:SetScript("OnUpdate", function()
          local x, y = GetCursorPosition()
          local scale = UIParent:GetEffectiveScale()
          dragFrame:ClearAllPoints()
          dragFrame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
        end)

        panel.currentDragFrame = dragFrame
        panel.draggedPlayerName = capturedName

        -- Notify consumer
        if config.onDragStart then
          config.onDragStart(panel, capturedName, capturedClass, capturedColor)
        end
      end)

      -- Right-click
      playerBtn:SetScript("OnClick", function()
        if arg1 == "RightButton" and config.onRightClick then
          config.onRightClick(panel, this, capturedName, capturedSection)
        end
      end)

      -- Drag stop
      playerBtn:SetScript("OnDragStop", function()
        if panel.currentDragFrame then
          panel.currentDragFrame:Hide()
          panel.currentDragFrame:SetParent(nil)
          panel.currentDragFrame = nil
        end

        local draggedName = panel.draggedPlayerName

        -- Notify consumer to handle the drop
        if draggedName and config.onDragStop then
          config.onDragStop(panel, draggedName, capturedClass)
        end

        panel.draggedPlayerName = nil
      end)

      yOffset = yOffset + (OGRH.LIST_ITEM_HEIGHT + OGRH.LIST_ITEM_SPACING)
    end

    -- Update scroll child height
    sc:SetHeight(math.max(yOffset, 1))

    -- Update scrollbar visibility and range
    if self.scrollBar and self.scrollFrame then
      local contentHeight = sc:GetHeight()
      local scrollFrameHeight = self.scrollFrame:GetHeight()

      if contentHeight > scrollFrameHeight then
        self.scrollBar:Show()
        self.scrollBar:SetMinMaxValues(0, contentHeight - scrollFrameHeight)
        self.scrollBar:SetValue(0)
      else
        self.scrollBar:Hide()
      end
      self.scrollFrame:SetVerticalScroll(0)
    end
  end  -- end Refresh()

  return panel
end
