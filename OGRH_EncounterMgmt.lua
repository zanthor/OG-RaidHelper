-- OGRH_EncounterMgmt.lua
-- Encounter Management Window for pre-planning encounter assignments
if not OGRH then
  DEFAULT_CHAT_FRAME:AddMessage("|cffff0000Error: OGRH_EncounterMgmt requires OGRH_Core to be loaded first!|r")
  return
end

-- Initialize namespace
OGRH.EncounterMgmt = OGRH.EncounterMgmt or {}

-- Storage for encounter assignments
local encounterData = {}

-- Auto-assign players from RollFor data
function OGRH.AutoAssignRollForPlayers(frame, rollForPlayers)
  if not frame or not rollForPlayers then return 0 end
  
  -- Get role configuration
  local roles = OGRH_SV.encounterMgmt.roles
  if not roles or not roles[frame.selectedRaid] or not roles[frame.selectedRaid][frame.selectedEncounter] then
    return 0
  end
  
  local encounterRoles = roles[frame.selectedRaid][frame.selectedEncounter]
  local column1 = encounterRoles.column1 or {}
  local column2 = encounterRoles.column2 or {}
  
  -- Build complete roles list
  local allRoles = {}
  for i = 1, table.getn(column1) do
    table.insert(allRoles, {role = column1[i], roleIndex = table.getn(allRoles) + 1})
  end
  for i = 1, table.getn(column2) do
    table.insert(allRoles, {role = column2[i], roleIndex = table.getn(allRoles) + 1})
  end
  
  -- Map RollFor role to OGRH role bucket (same as Invites module)
  local function MapRollForRole(rollForRole)
    if not rollForRole or rollForRole == "" then return nil end
    local roleMap = {
      DruidBear = "TANKS", PaladinProtection = "TANKS", ShamanTank = "TANKS", WarriorProtection = "TANKS",
      DruidRestoration = "HEALERS", PaladinHoly = "HEALERS", PriestHoly = "HEALERS", ShamanRestoration = "HEALERS",
      DruidFeral = "MELEE", HunterSurvival = "MELEE", PaladinRetribution = "MELEE", RogueDaggers = "MELEE",
      RogueSwords = "MELEE", ShamanEnhancement = "MELEE", WarriorArms = "MELEE", WarriorFury = "MELEE",
      DruidBalance = "RANGED", HunterMarksmanship = "RANGED", HunterBeastMastery = "RANGED", MageArcane = "RANGED",
      MageFire = "RANGED", MageFrost = "RANGED", PriestDiscipline = "RANGED", PriestShadow = "RANGED",
      WarlockAffliction = "RANGED", WarlockDemonology = "RANGED", WarlockDestruction = "RANGED", ShamanElemental = "RANGED"
    }
    return roleMap[rollForRole]
  end
  
  -- Track assignments
  local assignedPlayers = {}
  local assignmentCount = 0
  local processedRoles = {}
  
  -- Initialize assignments storage
  if not OGRH_SV.encounterAssignments then OGRH_SV.encounterAssignments = {} end
  if not OGRH_SV.encounterAssignments[frame.selectedRaid] then OGRH_SV.encounterAssignments[frame.selectedRaid] = {} end
  
  -- Clear existing assignments for this encounter
  OGRH_SV.encounterAssignments[frame.selectedRaid][frame.selectedEncounter] = {}
  
  local assignments = OGRH_SV.encounterAssignments[frame.selectedRaid][frame.selectedEncounter]
  
  -- Process each role
  for _, roleData in ipairs(allRoles) do
    local role = roleData.role
    local roleIndex = roleData.roleIndex
    
    -- Skip if already processed as part of a linked group
    if processedRoles[roleIndex] then
      -- Skip this role, already processed
    else
      -- Mark this role as processed
      processedRoles[roleIndex] = true
      
      -- Check if this role has linked roles
      local linkedRoleData = {}  -- Array of {roleIndex, role}
      if role.linkedRoles and table.getn(role.linkedRoles) > 0 then
        -- Build list of linked role data (including self)
        table.insert(linkedRoleData, {roleIndex = roleIndex, role = role})
        for _, linkedIdx in ipairs(role.linkedRoles) do
          if not processedRoles[linkedIdx] then
            -- Find the linked role in allRoles
            for _, rd in ipairs(allRoles) do
              if rd.roleIndex == linkedIdx then
                table.insert(linkedRoleData, {roleIndex = linkedIdx, role = rd.role})
                processedRoles[linkedIdx] = true
                break
              end
            end
          end
        end
      else
        -- No linked roles, just process this role
        table.insert(linkedRoleData, {roleIndex = roleIndex, role = role})
      end
      
      -- Initialize role assignments for all roles in the group
      for _, rd in ipairs(linkedRoleData) do
        if not assignments[rd.roleIndex] then
          assignments[rd.roleIndex] = {}
        end
      end
      
      -- Handle linked roles with alternating assignment
      if table.getn(linkedRoleData) > 1 then
        -- LINKED ROLES: Alternate between roles when filling slots
        local slotAssignmentQueue = {}
        
        -- Find the maximum number of slots among all linked roles
        local maxSlotsInGroup = 0
        for _, rd in ipairs(linkedRoleData) do
          local slots = rd.role.slots or 1
          if slots > maxSlotsInGroup then
            maxSlotsInGroup = slots
          end
        end
        
        -- Create alternating slot assignment order
        for slotNum = 1, maxSlotsInGroup do
          for _, rd in ipairs(linkedRoleData) do
            local maxSlots = rd.role.slots or 1
            if slotNum <= maxSlots then
              table.insert(slotAssignmentQueue, {roleIndex = rd.roleIndex, role = rd.role, slotIdx = slotNum})
            end
          end
        end
        
        -- Process slots in alternating order
        for _, slotData in ipairs(slotAssignmentQueue) do
          local currentRole = slotData.role
          local currentRoleIndex = slotData.roleIndex
          local slotIdx = slotData.slotIdx
          
          -- Skip if slot is already filled
          if not assignments[currentRoleIndex][slotIdx] then
            OGRH.AutoAssignRollForSlot(currentRole, currentRoleIndex, slotIdx, assignments, rollForPlayers, assignedPlayers, MapRollForRole)
            if assignments[currentRoleIndex][slotIdx] then
              assignmentCount = assignmentCount + 1
            end
          end
        end
      else
        -- SINGLE ROLE: Process each slot sequentially
        local slots = role.slots or 1
        for slotIdx = 1, slots do
          if not assignments[roleIndex][slotIdx] then
            OGRH.AutoAssignRollForSlot(role, roleIndex, slotIdx, assignments, rollForPlayers, assignedPlayers, MapRollForRole)
            if assignments[roleIndex][slotIdx] then
              assignmentCount = assignmentCount + 1
            end
          end
        end
      end
    end
  end
  
  -- Broadcast sync
  if OGRH.BroadcastFullSync then
    OGRH.BroadcastFullSync(frame.selectedRaid, frame.selectedEncounter)
  end
  
  -- Refresh display
  if frame.RefreshRoleContainers then
    frame.RefreshRoleContainers()
  end
  
  return assignmentCount
end

-- Helper function to assign a single slot from RollFor data
function OGRH.AutoAssignRollForSlot(role, roleIndex, slotIdx, assignments, rollForPlayers, assignedPlayers, MapRollForRole)
  local assigned = false
  
  -- PHASE 1: Try class priority first if configured
  if role.classPriority and role.classPriority[slotIdx] and table.getn(role.classPriority[slotIdx]) > 0 then
    local priorityList = role.classPriority[slotIdx]
    
    -- Try each class in priority order
    for _, className in ipairs(priorityList) do
      -- Build list of players with this class
      local classPlayers = {}
      for _, playerData in ipairs(rollForPlayers) do
        if not assignedPlayers[playerData.name] and playerData.class then
          local playerRoleBucket = MapRollForRole(playerData.role)
          
          if string.upper(playerData.class) == string.upper(className) and playerRoleBucket then
            local roleMatches = false
            
            -- Check if this slot/class has specific classPriorityRoles configured
            if role.classPriorityRoles and role.classPriorityRoles[slotIdx] and role.classPriorityRoles[slotIdx][className] then
              local allowedRoles = role.classPriorityRoles[slotIdx][className]
              
              -- Check if ANY checkbox is enabled
              local anyRoleEnabled = allowedRoles.Tanks or allowedRoles.Healers or allowedRoles.Melee or allowedRoles.Ranged
              
              if not anyRoleEnabled then
                -- No checkboxes enabled = accept from any role
                roleMatches = true
              elseif (playerRoleBucket == "TANKS" and allowedRoles.Tanks) or
                     (playerRoleBucket == "HEALERS" and allowedRoles.Healers) or
                     (playerRoleBucket == "MELEE" and allowedRoles.Melee) or
                     (playerRoleBucket == "RANGED" and allowedRoles.Ranged) then
                roleMatches = true
              end
            else
              -- No classPriorityRoles for this class, accept from any role in Phase 1
              roleMatches = true
            end
            
            if roleMatches then
              table.insert(classPlayers, playerData.name)
            end
          end
        end
      end
      
      -- Sort alphabetically for consistent results
      table.sort(classPlayers)
      
      -- Assign first available player
      if table.getn(classPlayers) > 0 then
        assignments[roleIndex][slotIdx] = classPlayers[1]
        assignedPlayers[classPlayers[1]] = true
        assigned = true
        
        -- Update class cache
        for _, playerData in ipairs(rollForPlayers) do
          if playerData.name == classPlayers[1] and playerData.class and OGRH.UpdatePlayerClass then
            OGRH.UpdatePlayerClass(playerData.name, playerData.class)
            break
          end
        end
        
        break -- Move to next slot
      end
    end
  end
  
  -- PHASE 2: If no class priority or class priority didn't assign anyone, try defaultRoles
  if not assigned and role.defaultRoles then
    for _, playerData in ipairs(rollForPlayers) do
      if not assignedPlayers[playerData.name] then
        local playerRoleBucket = MapRollForRole(playerData.role)
        
        -- Check if player matches role's defaultRoles
        local matches = false
        if playerRoleBucket then
          if (playerRoleBucket == "TANKS" and role.defaultRoles.tanks) or
             (playerRoleBucket == "HEALERS" and role.defaultRoles.healers) or
             (playerRoleBucket == "MELEE" and role.defaultRoles.melee) or
             (playerRoleBucket == "RANGED" and role.defaultRoles.ranged) then
            matches = true
          end
        end
        
        if matches then
          -- Assign player
          assignments[roleIndex][slotIdx] = playerData.name
          assignedPlayers[playerData.name] = true
          
          -- Update class cache if we have class data
          if playerData.class and OGRH.UpdatePlayerClass then
            OGRH.UpdatePlayerClass(playerData.name, playerData.class)
          end
          
          break
        end
      end
    end
  end
end

-- Get currently selected encounter for main UI (not planning window)
function OGRH.GetCurrentEncounter()
  -- Always use saved variables for main UI selection
  if OGRH_SV and OGRH_SV.ui then
    return OGRH_SV.ui.selectedRaid, OGRH_SV.ui.selectedEncounter
  end
  
  return nil, nil
end

-- Global ReplaceTags function for announcement processing
-- This is used by the A button and can work without the frame being created
function OGRH.ReplaceTags(text, roles, assignments, raidMarks, assignmentNumbers)
  if not text or text == "" then
    return ""
  end
  
  -- Use the frame's version if it exists (it's already been created and is authoritative)
  if OGRH_EncounterFrame and OGRH_EncounterFrame.ReplaceTags then
    return OGRH_EncounterFrame.ReplaceTags(text, roles, assignments, raidMarks, assignmentNumbers)
  end
  
  -- Otherwise, use simplified version that just returns the text as-is
  -- The full implementation is complex and duplicating it would be maintenance burden
  -- Users should open the Encounter Planning window at least once after login for full functionality
  return text
end

-- Migrate old roleDefaults to poolDefaults (one-time migration)
local function MigrateRoleDefaultsToPoolDefaults()
  if OGRH_SV.roleDefaults and not OGRH_SV.poolDefaults then
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OG-RaidHelper:|r Migrating Role Defaults to Pool Defaults...")
    OGRH_SV.poolDefaults = OGRH_SV.roleDefaults
    OGRH_SV.roleDefaults = nil
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OG-RaidHelper:|r Migration complete!")
  end
end

-- Initialize SavedVariables structure
local function InitializeSavedVars()
  -- Run migration first
  MigrateRoleDefaultsToPoolDefaults()
  
  if not OGRH_SV.encounterMgmt then
    OGRH_SV.encounterMgmt = {
      raids = {},
      encounters = {}
    }
  end
end

-- Function to show Encounter Planning Window
function OGRH.ShowEncounterWindow(encounterName)
  OGRH.EnsureSV()
  
  -- Create or show the window
  if not OGRH_EncounterFrame then
    -- Check if encounter data exists before creating frame
    if not OGRH_SV.encounterMgmt or 
       not OGRH_SV.encounterMgmt.raids or 
       table.getn(OGRH_SV.encounterMgmt.raids) == 0 then
      DEFAULT_CHAT_FRAME:AddMessage("|cffff8800OGRH:|r No encounter data found. Please import data from the Share window.")
      if OGRH.ShowShareWindow then
        OGRH.ShowShareWindow()
      end
      return
    end
    
    -- Now create the frame
    local frame = CreateFrame("Frame", "OGRH_EncounterFrame", UIParent)
    frame:SetWidth(1010)
    frame:SetHeight(450)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetFrameStrata("HIGH")
    frame:SetBackdrop({
      bgFile = "Interface/Tooltips/UI-Tooltip-Background",
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
      tile = true,
      tileSize = 16,
      edgeSize = 16,
      insets = {left = 4, right = 4, top = 4, bottom = 4}
    })
    frame:SetBackdropColor(0, 0, 0, 0.9)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function() frame:StartMoving() end)
    frame:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
    
    -- Register ESC key handler
    OGRH.MakeFrameCloseOnEscape(frame, "OGRH_EncounterFrame")
    
    -- Title bar
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", frame, "TOP", 0, -10)
    title:SetText("Encounter Planning")
    frame.title = title
    
    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    closeBtn:SetWidth(60)
    closeBtn:SetHeight(24)
    closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -10)
    closeBtn:SetText("Close")
    OGRH.StyleButton(closeBtn)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)
    
    -- Encounter Sync button (to the left of Close button)
    local encounterSyncBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    encounterSyncBtn:SetWidth(100)
    encounterSyncBtn:SetHeight(24)
    encounterSyncBtn:SetPoint("RIGHT", closeBtn, "LEFT", -5, 0)
    encounterSyncBtn:SetText("Encounter Sync")
    OGRH.StyleButton(encounterSyncBtn)
    frame.encounterSyncBtn = encounterSyncBtn
    
    encounterSyncBtn:SetScript("OnEnter", function()
      GameTooltip:SetOwner(this, "ANCHOR_TOP")
      GameTooltip:SetText("Encounter Sync", 1, 1, 1)
      
      if OGRH.IsRaidLead and OGRH.IsRaidLead() then
        GameTooltip:AddLine("Broadcast player assignments for the selected encounter to all raid members.", 0.8, 0.8, 0.8, 1)
      else
        GameTooltip:AddLine("Request player assignments for the selected encounter from the raid lead.", 0.8, 0.8, 0.8, 1)
      end
      
      GameTooltip:Show()
    end)
    encounterSyncBtn:SetScript("OnLeave", function()
      GameTooltip:Hide()
    end)
    
    encounterSyncBtn:SetScript("OnClick", function()
      local selectedRaid = frame.selectedRaid
      local selectedEncounter = frame.selectedEncounter
      
      if not selectedRaid or not selectedEncounter then
        OGRH.Msg("Select an encounter first.")
        return
      end
      
      if OGRH.IsRaidLead and OGRH.IsRaidLead() then
        -- Broadcast encounter assignments
        OGRH.Msg("Broadcasting player assignments for " .. selectedEncounter .. "...")
        OGRH.BroadcastFullSync(selectedRaid, selectedEncounter)
      else
        -- Request encounter assignments
        OGRH.Msg("Requesting encounter sync from raid lead...")
        if OGRH.RequestCurrentEncounterSync then
          OGRH.RequestCurrentEncounterSync()
        end
      end
    end)
    
    -- Structure Sync button (to the left of Encounter Sync button)
    local structureSyncBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    structureSyncBtn:SetWidth(100)
    structureSyncBtn:SetHeight(24)
    structureSyncBtn:SetPoint("RIGHT", encounterSyncBtn, "LEFT", -5, 0)
    structureSyncBtn:SetText("Structure Sync")
    OGRH.StyleButton(structureSyncBtn)
    frame.structureSyncBtn = structureSyncBtn
    
    structureSyncBtn:SetScript("OnEnter", function()
      GameTooltip:SetOwner(this, "ANCHOR_TOP")
      GameTooltip:SetText("Structure Sync", 1, 1, 1)
      
      if OGRH.IsRaidLead and OGRH.IsRaidLead() then
        GameTooltip:AddLine("Broadcast the structure (roles, marks, numbers, announcements) for the selected encounter to all raid members.", 0.8, 0.8, 0.8, 1)
        GameTooltip:AddLine(" ", 1, 1, 1)
        GameTooltip:AddLine("This does NOT include player assignments.", 0.6, 0.6, 0.6, 1)
      else
        GameTooltip:AddLine("Request structure sync from the raid lead.", 0.8, 0.8, 0.8, 1)
      end
      
      GameTooltip:Show()
    end)
    structureSyncBtn:SetScript("OnLeave", function()
      GameTooltip:Hide()
    end)
    
    structureSyncBtn:SetScript("OnClick", function()
      local selectedRaid = frame.selectedRaid
      local selectedEncounter = frame.selectedEncounter
      
      if not selectedRaid or not selectedEncounter then
        OGRH.Msg("Select an encounter first.")
        return
      end
      
      if OGRH.IsRaidLead and OGRH.IsRaidLead() then
        -- Broadcast structure for selected encounter only
        OGRH.Msg("Broadcasting structure sync for " .. selectedEncounter .. "...")
        if OGRH.BroadcastEncounterStructureSync then
          OGRH.BroadcastEncounterStructureSync(selectedRaid, selectedEncounter)
        else
          OGRH.Msg("Structure sync function not available yet.")
        end
      else
        -- Non-raid-lead requests structure sync
        if GetNumRaidMembers() == 0 then
          OGRH.Msg("You must be in a raid.")
          return
        end
        
        OGRH.Msg("Requesting structure sync for " .. selectedEncounter .. " from raid lead...")
        local playerName = UnitName("player")
        local msg = "REQUEST_ENCOUNTER_STRUCTURE_SYNC;" .. selectedRaid .. ";" .. selectedEncounter .. ";" .. playerName
        SendAddonMessage(OGRH.ADDON_PREFIX, msg, "RAID")
      end
    end)
    
    -- Left panel: Raids and Encounters selection
    local leftPanel = CreateFrame("Frame", nil, frame)
    leftPanel:SetWidth(175)
    leftPanel:SetHeight(390)
    leftPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -50)
    leftPanel:SetBackdrop({
      bgFile = "Interface/Tooltips/UI-Tooltip-Background",
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
      tile = true,
      tileSize = 16,
      edgeSize = 12,
      insets = {left = 3, right = 3, top = 3, bottom = 3}
    })
    leftPanel:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
    frame.leftPanel = leftPanel
    
    -- Raids label
    local raidsLabel = leftPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    raidsLabel:SetPoint("TOPLEFT", leftPanel, "TOPLEFT", 10, -10)
    raidsLabel:SetText("Raids:")
    
    -- Raids list frame with standardized scroll list (no scrollbar)
    local raidsListFrame, raidsScrollFrame, raidsScrollChild, raidsScrollBar, raidsContentWidth = OGRH.CreateStyledScrollList(leftPanel, 155, 165, true)
    raidsListFrame:SetPoint("TOPLEFT", raidsLabel, "BOTTOMLEFT", 0, -5)
    frame.raidsScrollChild = raidsScrollChild
    frame.raidsScrollFrame = raidsScrollFrame
    
    -- Encounters label
    local encountersLabel = leftPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    encountersLabel:SetPoint("TOPLEFT", raidsListFrame, "BOTTOMLEFT", 0, -10)
    encountersLabel:SetText("Encounters:")
    
    -- Encounters list frame with standardized scroll list (no scrollbar)
    local encountersListFrame, encountersScrollFrame, encountersScrollChild, encountersScrollBar, encountersContentWidth = OGRH.CreateStyledScrollList(leftPanel, 155, 165, true)
    encountersListFrame:SetPoint("TOPLEFT", encountersLabel, "BOTTOMLEFT", 0, -5)
    frame.encountersScrollChild = encountersScrollChild
    frame.encountersScrollFrame = encountersScrollFrame
    
    -- Track selected raid and encounter
    frame.selectedRaid = nil
    frame.selectedEncounter = nil
    
    -- Function to refresh raids list
    local function RefreshRaidsList()
      -- Clear existing buttons
      if frame.raidButtons then
        for _, btn in ipairs(frame.raidButtons) do
          btn:Hide()
          btn:SetParent(nil)
        end
      end
      frame.raidButtons = {}
      
      -- Validate that the selected raid still exists
      if frame.selectedRaid then
        local raidExists = false
        for _, raidName in ipairs(OGRH_SV.encounterMgmt.raids) do
          if raidName == frame.selectedRaid then
            raidExists = true
            break
          end
        end
        if not raidExists then
          frame.selectedRaid = nil
          frame.selectedEncounter = nil
        end
      end
      
      local yOffset = -5
      local scrollChild = frame.raidsScrollChild
      
      -- Add existing raids
      for i, raidName in ipairs(OGRH_SV.encounterMgmt.raids) do
        local raidBtn = OGRH.CreateStyledListItem(scrollChild, raidsContentWidth, OGRH.LIST_ITEM_HEIGHT, "Button")
        raidBtn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, yOffset)
        
        -- Set selection state
        OGRH.SetListItemSelected(raidBtn, frame.selectedRaid == raidName)
        
        -- Raid name text
        local nameText = raidBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        nameText:SetPoint("LEFT", raidBtn, "LEFT", 5, 0)
        nameText:SetText(raidName)
        nameText:SetWidth(135)
        nameText:SetJustifyH("LEFT")
        
        -- Click to select raid
        local capturedRaidName = raidName
        raidBtn:SetScript("OnClick", function()
          -- Clear encounter selection when switching raids
          if frame.selectedRaid ~= capturedRaidName then
            frame.selectedEncounter = nil
          end
          frame.selectedRaid = capturedRaidName
          -- DO NOT update main UI state - planning window is independent
          
          -- Select first encounter if available
          local firstEncounter = nil
          if OGRH_SV.encounterMgmt.encounters and 
             OGRH_SV.encounterMgmt.encounters[capturedRaidName] and
             table.getn(OGRH_SV.encounterMgmt.encounters[capturedRaidName]) > 0 then
            firstEncounter = OGRH_SV.encounterMgmt.encounters[capturedRaidName][1]
            frame.selectedEncounter = firstEncounter
            -- DO NOT update main UI state - planning window is independent
          end
          
          RefreshRaidsList()
          if frame.RefreshEncountersList then
            frame.RefreshEncountersList()
          end
          if frame.RefreshRoleContainers then
            frame.RefreshRoleContainers()
          end
          if frame.RefreshPlayersList then
            frame.RefreshPlayersList()
          end
          -- DO NOT update main UI nav button - planning window is independent
          
          -- DO NOT broadcast encounter change - planning window is independent
        end)
        
        table.insert(frame.raidButtons, raidBtn)
        yOffset = yOffset - (OGRH.LIST_ITEM_HEIGHT + OGRH.LIST_ITEM_SPACING)
      end
      
      -- Update scroll child height
      local contentHeight = math.abs(yOffset) + 5
      scrollChild:SetHeight(contentHeight)
    end
    
    frame.RefreshRaidsList = RefreshRaidsList
    
    -- Function to refresh encounters list
    local function RefreshEncountersList()
      -- Clear existing buttons
      if frame.encounterButtons then
        for _, btn in ipairs(frame.encounterButtons) do
          if btn.placeholder then
            btn.placeholder:SetParent(nil)
            btn.placeholder = nil
          else
            btn:Hide()
            btn:SetParent(nil)
          end
        end
      end
      frame.encounterButtons = {}
      
      local scrollChild = frame.encountersScrollChild
      
      if not frame.selectedRaid then
        -- Show placeholder
        local placeholderText = encountersListFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        placeholderText:SetPoint("CENTER", encountersListFrame, "CENTER", 0, 0)
        placeholderText:SetText("|cff888888Select a raid|r")
        placeholderText:SetJustifyH("CENTER")
        table.insert(frame.encounterButtons, {placeholder = placeholderText})
        return
      end
      
      -- Ensure encounter storage exists
      if not OGRH_SV.encounterMgmt.encounters[frame.selectedRaid] then
        OGRH_SV.encounterMgmt.encounters[frame.selectedRaid] = {}
      end
      
      -- Validate that the selected encounter still exists
      if frame.selectedEncounter then
        local encounterExists = false
        local encounters = OGRH_SV.encounterMgmt.encounters[frame.selectedRaid]
        for _, encounterName in ipairs(encounters) do
          if encounterName == frame.selectedEncounter then
            encounterExists = true
            break
          end
        end
        if not encounterExists then
          frame.selectedEncounter = nil
        end
      end
      
      local yOffset = -5
      local encounters = OGRH_SV.encounterMgmt.encounters[frame.selectedRaid]
      local selectedIndex = nil
      
      for i, encounterName in ipairs(encounters) do
        if encounterName == frame.selectedEncounter then
          selectedIndex = i
        end
        local encounterBtn = OGRH.CreateStyledListItem(scrollChild, encountersContentWidth, OGRH.LIST_ITEM_HEIGHT, "Button")
        encounterBtn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, yOffset)
        
        -- Set selection state
        OGRH.SetListItemSelected(encounterBtn, frame.selectedEncounter == encounterName)
        
        -- Encounter name text
        local nameText = encounterBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        nameText:SetPoint("LEFT", encounterBtn, "LEFT", 5, 0)
        nameText:SetText(encounterName)
        nameText:SetWidth(135)
        nameText:SetJustifyH("LEFT")
        
        -- Click to select encounter
        local capturedEncounterName = encounterName
        encounterBtn:SetScript("OnClick", function()
          frame.selectedEncounter = capturedEncounterName
          -- DO NOT update main UI state - planning window is independent
          RefreshEncountersList()
          if frame.RefreshRoleContainers then
            frame.RefreshRoleContainers()
          end
          if frame.RefreshPlayersList then
            frame.RefreshPlayersList()
          end
          -- DO NOT update main UI nav button - planning window is independent
          
          -- DO NOT update consume monitor - it follows main UI, not planning window
          
          -- DO NOT broadcast encounter change - planning window is independent
        end)
        
        table.insert(frame.encounterButtons, encounterBtn)
        yOffset = yOffset - (OGRH.LIST_ITEM_HEIGHT + OGRH.LIST_ITEM_SPACING)
      end
      
      -- Update scroll child height
      local contentHeight = math.abs(yOffset) + 5
      scrollChild:SetHeight(contentHeight)
      
      -- Scroll to keep selected encounter visible
      local scrollFrame = frame.encountersScrollFrame
      if scrollFrame and selectedIndex then
        local buttonHeight = 22
        local visibleHeight = scrollFrame:GetHeight()
        local buttonTop = (selectedIndex - 1) * buttonHeight
        local buttonBottom = buttonTop + buttonHeight
        local currentScroll = scrollFrame:GetVerticalScroll()
        local scrollBottom = currentScroll + visibleHeight
        
        -- If selected button is above visible area, scroll up to it
        if buttonTop < currentScroll then
          scrollFrame:SetVerticalScroll(buttonTop)
        -- If selected button is below visible area, scroll down to it
        elseif buttonBottom > scrollBottom then
          scrollFrame:SetVerticalScroll(buttonBottom - visibleHeight)
        end
        -- Otherwise, don't change scroll position (button is already visible)
      end
    end
    
    frame.RefreshEncountersList = RefreshEncountersList
    
    -- Middle panel: Role assignment area
    local rightPanel = CreateFrame("Frame", nil, frame)
    rightPanel:SetWidth(595)
    rightPanel:SetHeight(234)
    rightPanel:SetPoint("TOPLEFT", leftPanel, "TOPRIGHT", 10, 0)
    rightPanel:SetBackdrop({
      bgFile = "Interface/Tooltips/UI-Tooltip-Background",
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
      tile = true,
      tileSize = 16,
      edgeSize = 12,
      insets = {left = 3, right = 3, top = 3, bottom = 3}
    })
    rightPanel:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
    frame.rightPanel = rightPanel
    
    -- Create scroll frame for role containers
    local rolesScrollFrame = CreateFrame("ScrollFrame", nil, rightPanel)
    rolesScrollFrame:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", 5, -5)
    rolesScrollFrame:SetPoint("BOTTOMRIGHT", rightPanel, "BOTTOMRIGHT", -22, 5)
    
    local rolesScrollChild = CreateFrame("Frame", nil, rolesScrollFrame)
    rolesScrollChild:SetWidth(565)
    rolesScrollChild:SetHeight(1)
    rolesScrollFrame:SetScrollChild(rolesScrollChild)
    frame.rolesScrollFrame = rolesScrollFrame
    frame.rolesScrollChild = rolesScrollChild
    
    -- Create scrollbar for roles
    local rolesScrollBar = CreateFrame("Slider", nil, rolesScrollFrame)
    rolesScrollBar:SetPoint("TOPRIGHT", rightPanel, "TOPRIGHT", -5, -16)
    rolesScrollBar:SetPoint("BOTTOMRIGHT", rightPanel, "BOTTOMRIGHT", -5, 16)
    rolesScrollBar:SetWidth(16)
    rolesScrollBar:SetBackdrop({
      bgFile = "Interface/Tooltips/UI-Tooltip-Background",
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 8,
      insets = {left = 3, right = 3, top = 3, bottom = 3}
    })
    rolesScrollBar:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
    rolesScrollBar:SetOrientation("VERTICAL")
    rolesScrollBar:SetMinMaxValues(0, 1)
    rolesScrollBar:SetValue(0)
    rolesScrollBar:SetValueStep(22)
    rolesScrollBar:Hide()
    frame.rolesScrollBar = rolesScrollBar
    
    rolesScrollBar:SetScript("OnValueChanged", function()
      rolesScrollFrame:SetVerticalScroll(this:GetValue())
    end)
    
    -- Enable mouse wheel scrolling
    rolesScrollFrame:EnableMouseWheel(true)
    rolesScrollFrame:SetScript("OnMouseWheel", function()
      if not rolesScrollBar:IsShown() then
        return
      end
      
      local delta = arg1
      local current = rolesScrollBar:GetValue()
      local minVal, maxVal = rolesScrollBar:GetMinMaxValues()
      
      if delta > 0 then
        rolesScrollBar:SetValue(math.max(minVal, current - 22))
      else
        rolesScrollBar:SetValue(math.min(maxVal, current + 22))
      end
    end)
    
    -- Placeholder text when no encounter selected
    local placeholderText = rightPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    placeholderText:SetPoint("CENTER", rightPanel, "CENTER", 0, 0)
    placeholderText:SetText("|cff888888Select a raid and encounter|r")
    frame.placeholderText = placeholderText
    
    -- Players panel: Shows available players for drag/drop assignment
    local playersPanel = CreateFrame("Frame", nil, frame)
    playersPanel:SetWidth(200)
    playersPanel:SetHeight(390)
    playersPanel:SetPoint("TOPLEFT", rightPanel, "TOPRIGHT", 10, 0)
    playersPanel:SetBackdrop({
      bgFile = "Interface/Tooltips/UI-Tooltip-Background",
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
      tile = true,
      tileSize = 16,
      edgeSize = 12,
      insets = {left = 3, right = 3, top = 3, bottom = 3}
    })
    playersPanel:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
    frame.playersPanel = playersPanel
    
    -- Players label
    local playersLabel = playersPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    playersLabel:SetPoint("TOP", playersPanel, "TOP", 0, -10)
    playersLabel:SetText("Players:")
    
    -- Role filter dropdown for players
    local playerRoleBtn = CreateFrame("Button", nil, playersPanel, "UIPanelButtonTemplate")
    playerRoleBtn:SetWidth(180)
    playerRoleBtn:SetHeight(24)
    playerRoleBtn:SetPoint("TOP", playersLabel, "BOTTOM", 0, -5)
    playerRoleBtn:SetText("All Roles")
    OGRH.StyleButton(playerRoleBtn)
    frame.playerRoleBtn = playerRoleBtn
    frame.selectedPlayerRole = "all"
    
    -- Create dropdown menu frame if it doesn't exist
    if not OGRH.playerRoleDropdown then
      OGRH.playerRoleDropdown = CreateFrame("Frame", "OGRH_PlayerRoleDropdown", UIParent, "UIDropDownMenuTemplate")
    end
    
    -- Role filter dropdown
    playerRoleBtn:SetScript("OnClick", function()
      -- Create menu items
      local menuItems = {
        {text = "All Roles", value = "all", label = "All Roles"},
        {text = "Tanks", value = "tanks", label = "Tanks"},
        {text = "Healers", value = "healers", label = "Healers"},
        {text = "Melee", value = "melee", label = "Melee"},
        {text = "Ranged", value = "ranged", label = "Ranged"},
        {text = "Signed Up", value = "signedup", label = "Signed Up"}
      }
      
      -- Show menu
      local menuFrame = CreateFrame("Frame", nil, UIParent)
      menuFrame:SetWidth(180)
      menuFrame:SetHeight(table.getn(menuItems) * 20 + 10)
      menuFrame:SetPoint("TOPLEFT", playerRoleBtn, "BOTTOMLEFT", 0, 0)
      menuFrame:SetFrameStrata("DIALOG")
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
      
      -- Close menu when clicking outside
      menuFrame:SetScript("OnHide", function()
        this:SetParent(nil)
      end)
      
      -- Create menu item buttons
      for i, item in ipairs(menuItems) do
        local btn = CreateFrame("Button", nil, menuFrame)
        btn:SetWidth(174)
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
        
        -- Capture variables for closure
        local capturedValue = item.value
        local capturedLabel = item.label
        
        btn:SetScript("OnEnter", function()
          bg:Show()
        end)
        
        btn:SetScript("OnLeave", function()
          bg:Hide()
        end)
        
        btn:SetScript("OnClick", function()
          frame.selectedPlayerRole = capturedValue
          playerRoleBtn:SetText(capturedLabel)
          if frame.RefreshPlayersList then
            frame.RefreshPlayersList()
          end
          menuFrame:Hide()
        end)
      end
      
      -- Auto-hide after short delay when mouse leaves
      menuFrame:SetScript("OnUpdate", function()
        if not MouseIsOver(menuFrame) and not MouseIsOver(playerRoleBtn) then
          menuFrame:Hide()
        end
      end)
      
      frame.currentRoleMenu = menuFrame
    end)
    
    -- Search box for text filtering
    local searchBox = CreateFrame("EditBox", nil, playersPanel)
    searchBox:SetWidth(180)
    searchBox:SetHeight(24)
    searchBox:SetPoint("TOP", playerRoleBtn, "BOTTOM", 0, -5)
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
      if frame.RefreshPlayersList then
        frame.RefreshPlayersList()
      end
    end)
    frame.playerSearchBox = searchBox
    
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
    
    -- Guild list frame with standardized scroll list
    local guildListFrame, guildScrollFrame, guildScrollChild, guildScrollBar, guildContentWidth = OGRH.CreateStyledScrollList(playersPanel, 180, 280)
    guildListFrame:SetPoint("TOP", searchBox, "BOTTOM", 0, -5)
    frame.guildScrollChild = guildScrollChild
    frame.guildScrollFrame = guildScrollFrame
    frame.guildScrollBar = guildScrollBar
    frame.guildContentWidth = guildContentWidth
    
    -- Bottom right panel: Additional info area (fills remaining space = 146px)
    local bottomPanel = CreateFrame("Frame", nil, frame)
    bottomPanel:SetWidth(595)
    bottomPanel:SetHeight(146)
    bottomPanel:SetPoint("TOPLEFT", rightPanel, "BOTTOMLEFT", 0, -10)
    bottomPanel:SetBackdrop({
      bgFile = "Interface/Tooltips/UI-Tooltip-Background",
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
      tile = true,
      tileSize = 16,
      edgeSize = 12,
      insets = {left = 3, right = 3, top = 3, bottom = 3}
    })
    bottomPanel:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
    frame.bottomPanel = bottomPanel
    
    -- Auto Assign button (reduced height to fit Edit button)
    local autoAssignBtn = CreateFrame("Button", nil, bottomPanel, "UIPanelButtonTemplate")
    autoAssignBtn:SetWidth(120)
    autoAssignBtn:SetHeight(24)
    autoAssignBtn:SetPoint("TOPLEFT", bottomPanel, "TOPLEFT", 10, -10)
    autoAssignBtn:SetText("Auto Assign")
    OGRH.StyleButton(autoAssignBtn)
    frame.autoAssignBtn = autoAssignBtn
    
    -- Enable right-click
    autoAssignBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    
    -- Tooltip
    autoAssignBtn:SetScript("OnEnter", function()
      GameTooltip:SetOwner(autoAssignBtn, "ANCHOR_TOP")
      GameTooltip:SetText("Auto Assign", 1, 1, 1)
      GameTooltip:AddLine("Left-click: Auto-assign from current raid members", 0.8, 0.8, 0.8, 1)
      GameTooltip:AddLine("Right-click: Auto-assign from RollFor soft-reserve data", 0.8, 0.8, 0.8, 1)
      GameTooltip:Show()
    end)
    autoAssignBtn:SetScript("OnLeave", function()
      GameTooltip:Hide()
    end)
    
    -- Auto Assign functionality
    autoAssignBtn:SetScript("OnClick", function()
      -- Check permission
      if not OGRH.CanEdit or not OGRH.CanEdit() then
        OGRH.Msg("Only the raid lead can modify assignments.")
        return
      end
      
      local button = arg1 or "LeftButton"
      
      -- Right-click: Auto-assign from RollFor data
      if button == "RightButton" then
        if not frame.selectedRaid or not frame.selectedEncounter then
          DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OGRH:|r Please select a raid and encounter first.")
          return
        end
        
        -- Check if RollFor is available
        if not RollFor or not RollForCharDb or not RollForCharDb.softres then
          DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OGRH:|r RollFor addon not found or no soft-res data loaded.")
          return
        end
        
        -- Get RollFor players
        local rollForPlayers = {}
        local encodedData = RollForCharDb.softres.data
        if encodedData and type(encodedData) == "string" and RollFor.SoftRes and RollFor.SoftRes.decode then
          local decodedData = RollFor.SoftRes.decode(encodedData)
          if decodedData and RollFor.SoftResDataTransformer and RollFor.SoftResDataTransformer.transform then
            local softresData = RollFor.SoftResDataTransformer.transform(decodedData)
            if softresData and type(softresData) == "table" then
              local playerMap = {}
              for itemId, itemData in pairs(softresData) do
                if type(itemData) == "table" and itemData.rollers then
                  for _, roller in ipairs(itemData.rollers) do
                    if roller and roller.name then
                      if not playerMap[roller.name] then
                        playerMap[roller.name] = {
                          name = roller.name,
                          role = roller.role or "Unknown",
                          class = nil
                        }
                      end
                    end
                  end
                end
              end
              for _, playerData in pairs(playerMap) do
                table.insert(rollForPlayers, playerData)
              end
            end
          end
        end
        
        if table.getn(rollForPlayers) == 0 then
          DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OGRH:|r No players found in RollFor data.")
          return
        end
        
        -- Update player classes from cache or guild roster
        for _, playerData in ipairs(rollForPlayers) do
          local class = OGRH.GetPlayerClass(playerData.name)
          if not class then
            local numGuild = GetNumGuildMembers(true)
            for i = 1, numGuild do
              local guildName, _, _, _, _, _, _, _, _, _, guildClass = GetGuildRosterInfo(i)
              if guildName == playerData.name and guildClass then
                class = string.upper(guildClass)
                break
              end
            end
          end
          playerData.class = class
        end
        
        -- Perform auto-assignment
        local assignmentCount = OGRH.AutoAssignRollForPlayers(frame, rollForPlayers)
        
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OGRH:|r Auto-assigned " .. assignmentCount .. " players from RollFor data.")
        return
      end
      
      -- Left-click: Auto Assign functionality
      if not frame.selectedRaid or not frame.selectedEncounter then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OGRH:|r Please select a raid and encounter first.")
        return
      end
      
      -- Get role configuration
      local roles = OGRH_SV.encounterMgmt.roles
      if not roles or not roles[frame.selectedRaid] or not roles[frame.selectedRaid][frame.selectedEncounter] then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OGRH:|r No roles configured for this encounter.")
        return
      end
      
      local encounterRoles = roles[frame.selectedRaid][frame.selectedEncounter]
      local column1 = encounterRoles.column1 or {}
      local column2 = encounterRoles.column2 or {}
      
      -- Build ordered list of all roles
      local allRoles = {}
      
      -- Add all roles from column1 first (top to bottom)
      for i = 1, table.getn(column1) do
        if not column1[i].isCustomModule then
          table.insert(allRoles, {role = column1[i], roleIndex = table.getn(allRoles) + 1})
        end
      end
      
      -- Then add all roles from column2 (top to bottom)
      for i = 1, table.getn(column2) do
        if not column2[i].isCustomModule then
          table.insert(allRoles, {role = column2[i], roleIndex = table.getn(allRoles) + 1})
        end
      end
      
      -- Track assigned players
      local assignedPlayers = {}  -- playerName -> true (already assigned)
      local roleAssignments = {}  -- roleIndex -> {slotIndex -> playerName}
      local assignmentCount = 0
      
      -- Helper function to get player's class
      local function GetPlayerClassInRaid(playerName)
        -- First try the global class cache/lookup function
        if OGRH.GetPlayerClass then
          local cachedClass = OGRH.GetPlayerClass(playerName)
          if cachedClass then
            return cachedClass
          end
        end
        
        -- Fallback: check raid roster directly
        local numRaidMembers = GetNumRaidMembers()
        if numRaidMembers > 0 then
          for i = 1, numRaidMembers do
            local name, _, _, _, class = GetRaidRosterInfo(i)
            if name == playerName and class then
              return string.upper(class)
            end
          end
        end
        return nil
      end
      
      -- Helper function to get player's role from RolesUI ROLE_COLUMNS
      local function GetPlayerRole(playerName)
        if not OGRH.rolesFrame or not OGRH.rolesFrame.ROLE_COLUMNS then
          return nil
        end
        
        local roleColumns = OGRH.rolesFrame.ROLE_COLUMNS
        -- roleColumns: 1=Tanks, 2=Healers, 3=Melee, 4=Ranged
        local roleNames = {"TANKS", "HEALERS", "MELEE", "RANGED"}
        
        for colIndex = 1, table.getn(roleColumns) do
          local players = roleColumns[colIndex].players
          if players then
            for _, name in ipairs(players) do
              if name == playerName then
                return roleNames[colIndex]
              end
            end
          end
        end
        
        return nil
      end
      
      -- Track which roles have been processed (for linked role groups)
      local processedRoles = {}
      
      -- Process each role in order
      for _, roleData in ipairs(allRoles) do
        local role = roleData.role
        local roleIndex = roleData.roleIndex
        
        -- Skip if already processed as part of a linked group
        if processedRoles[roleIndex] then
          -- Skip this role, already processed
        else
          -- Mark this role as processed
          processedRoles[roleIndex] = true
          
          -- Check if this role has linked roles
          local linkedRoleData = {}  -- Array of {roleIndex, role}
          if role.linkedRoles and table.getn(role.linkedRoles) > 0 then
            -- Build list of linked role data (including self)
            table.insert(linkedRoleData, {roleIndex = roleIndex, role = role})
            for _, linkedIdx in ipairs(role.linkedRoles) do
              if not processedRoles[linkedIdx] then
                -- Find the linked role in allRoles
                for _, rd in ipairs(allRoles) do
                  if rd.roleIndex == linkedIdx then
                    table.insert(linkedRoleData, {roleIndex = linkedIdx, role = rd.role})
                    processedRoles[linkedIdx] = true
                    break
                  end
                end
              end
            end
          else
            -- No linked roles, just process this role
            table.insert(linkedRoleData, {roleIndex = roleIndex, role = role})
          end
          
          -- Initialize role assignments for all roles in the group
          for _, rd in ipairs(linkedRoleData) do
            if not roleAssignments[rd.roleIndex] then
              roleAssignments[rd.roleIndex] = {}
            end
          end
          
          -- Build list of current raid members (includes offline)
          local raidMembers = {}
          local numRaidMembers = GetNumRaidMembers()
          if numRaidMembers > 0 then
            for i = 1, numRaidMembers do
              local name, rank, subgroup, level, class, fileName, zone, online, isDead = GetRaidRosterInfo(i)
              if name then
                raidMembers[name] = true
              end
            end
          end
        
          -- PHASE 1: Try to fill slots using class priority
          -- Handle linked roles with alternating assignment
          if table.getn(linkedRoleData) > 1 then
            -- LINKED ROLES: Alternate between roles when filling slots
            -- Build a combined slot list with role cycling
            local slotAssignmentQueue = {}
            
            -- Find the maximum number of slots among all linked roles
            local maxSlotsInGroup = 0
            for _, rd in ipairs(linkedRoleData) do
              local slots = rd.role.slots or 1
              if slots > maxSlotsInGroup then
                maxSlotsInGroup = slots
              end
            end
            
            -- Create alternating slot assignment order
            for slotNum = 1, maxSlotsInGroup do
              for _, rd in ipairs(linkedRoleData) do
                local maxSlots = rd.role.slots or 1
                if slotNum <= maxSlots then
                  table.insert(slotAssignmentQueue, {roleIndex = rd.roleIndex, role = rd.role, slotIdx = slotNum})
                end
              end
            end
            
            -- Process slots in alternating order
            for _, slotData in ipairs(slotAssignmentQueue) do
              local currentRole = slotData.role
              local currentRoleIndex = slotData.roleIndex
              local slotIdx = slotData.slotIdx
              
              -- Skip if slot is already filled
              if not roleAssignments[currentRoleIndex][slotIdx] then
                -- Try class priority first if configured
                local assignedViaClassPriority = false
                if currentRole.classPriority and currentRole.classPriority[slotIdx] and table.getn(currentRole.classPriority[slotIdx]) > 0 then
                  local priorityList = currentRole.classPriority[slotIdx]
                
                  -- Try each class in priority order
                  for _, className in ipairs(priorityList) do
                    local assigned = false
                  
                  -- Build sorted list of players with this class
                  local classPlayers = {}
                  -- Iterate through raid members and check their class/role
                  for playerName, _ in pairs(raidMembers) do
                    if not assignedPlayers[playerName] then
                      local playerClass = GetPlayerClassInRaid(playerName)
                      local playerRole = GetPlayerRole(playerName)
                      
                      if playerClass and playerRole and string.upper(playerClass) == string.upper(className) then
                        
                        local roleMatches = false
                        
                        -- Check if this slot/class has specific classPriorityRoles configured
                        if currentRole.classPriorityRoles and currentRole.classPriorityRoles[slotIdx] and currentRole.classPriorityRoles[slotIdx][className] then
                          -- Use classPriorityRoles (specific role checkboxes for this class)
                          local allowedRoles = currentRole.classPriorityRoles[slotIdx][className]
                          
                          -- Check if ANY checkbox is enabled
                          local anyRoleEnabled = allowedRoles.Tanks or allowedRoles.Healers or allowedRoles.Melee or allowedRoles.Ranged
                          
                          if not anyRoleEnabled then
                            -- No checkboxes enabled = accept from any role
                            roleMatches = true
                          elseif playerRole == "TANKS" and allowedRoles.Tanks then
                            roleMatches = true
                          elseif playerRole == "HEALERS" and allowedRoles.Healers then
                            roleMatches = true
                          elseif playerRole == "MELEE" and allowedRoles.Melee then
                            roleMatches = true
                          elseif playerRole == "RANGED" and allowedRoles.Ranged then
                            roleMatches = true
                          end
                        else
                          -- No classPriorityRoles for this class
                          -- In Phase 1 (class priority), if class is in priority list, accept from any role
                          roleMatches = true
                        end
                        
                        if roleMatches then
                          table.insert(classPlayers, playerName)
                        end
                      end
                    end
                  end
                  
                  -- Sort alphabetically for consistent results
                  table.sort(classPlayers)
                  
                    -- Assign first available player
                    if table.getn(classPlayers) > 0 then
                      local playerName = classPlayers[1]
                      roleAssignments[currentRoleIndex][slotIdx] = playerName
                      assignedPlayers[playerName] = true
                      assignmentCount = assignmentCount + 1
                      assigned = true
                      assignedViaClassPriority = true
                      break  -- Move to next slot
                    end
                  end
                end
                
                -- If no class priority or class priority didn't assign anyone, try defaultRoles fallback
                if not assignedViaClassPriority and currentRole.defaultRoles then
                  -- Build list of available players matching defaultRoles
                  local availablePlayers = {}
                  for playerName, _ in pairs(raidMembers) do
                    if not assignedPlayers[playerName] or currentRole.allowOtherRoles then
                      local playerRole = GetPlayerRole(playerName)
                      
                      if playerRole then
                        local matches = false
                        if playerRole == "TANKS" and currentRole.defaultRoles.tanks then
                          matches = true
                        elseif playerRole == "HEALERS" and currentRole.defaultRoles.healers then
                          matches = true
                        elseif playerRole == "MELEE" and currentRole.defaultRoles.melee then
                          matches = true
                        elseif playerRole == "RANGED" and currentRole.defaultRoles.ranged then
                          matches = true
                        end
                        
                        if matches then
                          table.insert(availablePlayers, playerName)
                        end
                      end
                    end
                  end
                  
                  -- Sort and assign first available
                  table.sort(availablePlayers)
                  if table.getn(availablePlayers) > 0 then
                    local playerName = availablePlayers[1]
                    local canAssign = true
                    if assignedPlayers[playerName] and not currentRole.allowOtherRoles then
                      canAssign = false
                    end
                    
                    if canAssign then
                      roleAssignments[currentRoleIndex][slotIdx] = playerName
                      assignedPlayers[playerName] = true
                      assignmentCount = assignmentCount + 1
                    end
                  end
                end
              end
            end
          else
            -- SINGLE ROLE (no linked roles): Process normally
            local maxSlots = role.slots or 1
            local startSlot, endSlot, step
            if role.invertFillOrder then
              -- Bottom-up: start from last slot and go to first
              startSlot = maxSlots
              endSlot = 1
              step = -1
            else
              -- Top-down: start from first slot and go to last
              startSlot = 1
              endSlot = maxSlots
              step = 1
            end
            
            if role.classPriority then
              -- Process slots in configured order
              for slotIdx = startSlot, endSlot, step do
                if role.classPriority[slotIdx] and table.getn(role.classPriority[slotIdx]) > 0 then
                  local priorityList = role.classPriority[slotIdx]
                  
                  -- Try each class in priority order
                  for _, className in ipairs(priorityList) do
                    local assigned = false
                    
                    -- Build sorted list of players with this class
                    local classPlayers = {}
                    -- Iterate through raid members and check their class/role
                    for playerName, _ in pairs(raidMembers) do
                      if not assignedPlayers[playerName] then
                        local playerClass = GetPlayerClassInRaid(playerName)
                        local playerRole = GetPlayerRole(playerName)
                        
                        if playerClass and playerRole and string.upper(playerClass) == string.upper(className) then
                          
                          local roleMatches = false
                          
                          -- Check if this slot/class has specific classPriorityRoles configured
                          if role.classPriorityRoles and role.classPriorityRoles[slotIdx] and role.classPriorityRoles[slotIdx][className] then
                            -- Use classPriorityRoles (specific role checkboxes for this class)
                            local allowedRoles = role.classPriorityRoles[slotIdx][className]
                            
                            -- Check if ANY checkbox is enabled
                            local anyRoleEnabled = allowedRoles.Tanks or allowedRoles.Healers or allowedRoles.Melee or allowedRoles.Ranged
                            
                            if not anyRoleEnabled then
                              -- No checkboxes enabled = accept from any role
                              roleMatches = true
                            elseif playerRole == "TANKS" and allowedRoles.Tanks then
                              roleMatches = true
                            elseif playerRole == "HEALERS" and allowedRoles.Healers then
                              roleMatches = true
                            elseif playerRole == "MELEE" and allowedRoles.Melee then
                              roleMatches = true
                            elseif playerRole == "RANGED" and allowedRoles.Ranged then
                              roleMatches = true
                            end
                          else
                            -- No classPriorityRoles for this class
                            -- In Phase 1 (class priority), if class is in priority list, accept from any role
                            roleMatches = true
                          end
                          
                          if roleMatches then
                            table.insert(classPlayers, playerName)
                          end
                        end
                      end
                    end
                    
                    -- Sort alphabetically for consistent results
                    table.sort(classPlayers)
                    
                    -- Assign first available player
                    if table.getn(classPlayers) > 0 then
                      local playerName = classPlayers[1]
                      roleAssignments[roleIndex][slotIdx] = playerName
                      assignedPlayers[playerName] = true
                      assignmentCount = assignmentCount + 1
                      assigned = true
                      break  -- Move to next slot
                    end
                  end
                  
                  -- If we assigned someone, break the slot loop to move to next slot
                  if assigned then
                    -- Continue to next slot (loop handles this)
                  end
                end
              end
            end
          end
          
          -- PHASE 2: Fill remaining empty slots using defaultRoles (fallback)
          -- Process each role in the linked group
          for _, rd in ipairs(linkedRoleData) do
            local currentRole = rd.role
            local currentRoleIndex = rd.roleIndex
            
            if currentRole.defaultRoles then
              local availablePlayers = {}
              
              -- Iterate through raid members and check their roles
              for playerName, _ in pairs(raidMembers) do
                -- Check if player is not already assigned (or allowOtherRoles is true)
                if not assignedPlayers[playerName] or currentRole.allowOtherRoles then
                  local playerRole = GetPlayerRole(playerName)
                  
                  if playerRole then
                    -- Check if player's role matches any enabled defaultRole
                    local matches = false
                    
                    if playerRole == "TANKS" and currentRole.defaultRoles.tanks then
                      matches = true
                    elseif playerRole == "HEALERS" and currentRole.defaultRoles.healers then
                      matches = true
                    elseif playerRole == "MELEE" and currentRole.defaultRoles.melee then
                      matches = true
                    elseif playerRole == "RANGED" and currentRole.defaultRoles.ranged then
                      matches = true
                    end
                    
                    if matches then
                      table.insert(availablePlayers, playerName)
                    end
                  end
                end
              end
              
              -- Sort alphabetically for consistent results
              table.sort(availablePlayers)
              
              -- Fill remaining empty slots
              local maxSlots = currentRole.slots or 1
              local playerIdx = 1
              for slotIdx = 1, maxSlots do
                if not roleAssignments[currentRoleIndex][slotIdx] and playerIdx <= table.getn(availablePlayers) then
                  local playerName = availablePlayers[playerIdx]
                  
                  -- Check if we can assign this player
                  local canAssign = true
                  if assignedPlayers[playerName] and not currentRole.allowOtherRoles then
                    canAssign = false
                  end
                  
                  if canAssign then
                    roleAssignments[currentRoleIndex][slotIdx] = playerName
                    assignedPlayers[playerName] = true
                    assignmentCount = assignmentCount + 1
                  end
                  
                  playerIdx = playerIdx + 1
                end
              end
            end
          end
        end
      end
      
      -- Store assignments
      if not OGRH_SV.encounterAssignments then
        OGRH_SV.encounterAssignments = {}
      end
      if not OGRH_SV.encounterAssignments[frame.selectedRaid] then
        OGRH_SV.encounterAssignments[frame.selectedRaid] = {}
      end
      
      OGRH_SV.encounterAssignments[frame.selectedRaid][frame.selectedEncounter] = roleAssignments
      
      -- Broadcast full sync
      if OGRH.BroadcastFullSync then
        OGRH.BroadcastFullSync(frame.selectedRaid, frame.selectedEncounter)
      end
      
      -- Refresh the display
      if frame.RefreshRoleContainers then
        frame.RefreshRoleContainers()
      end
      
      DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OGRH:|r Auto-assigned " .. assignmentCount .. " players.")
    end)
    
    -- Announce button (below Auto Assign, reduced height)
    local announceBtn = CreateFrame("Button", nil, bottomPanel, "UIPanelButtonTemplate")
    announceBtn:SetWidth(120)
    announceBtn:SetHeight(24)
    announceBtn:SetPoint("TOPLEFT", autoAssignBtn, "BOTTOMLEFT", 0, -6)
    announceBtn:SetText("Announce")
    OGRH.StyleButton(announceBtn)
    frame.announceBtn = announceBtn
    
    -- Function to replace tags in announcement text with colored output
    local function ReplaceTags(text, roles, assignments, raidMarks, assignmentNumbers)
      if not text or text == "" then
        return ""
      end
      
      -- Use the cached class lookup system instead of only checking raid roster
      local function GetPlayerClass(playerName)
        return OGRH.GetPlayerClass(playerName)
      end
      
      -- Helper function to check if a tag is valid (has a value)
      local function IsTagValid(tagText, assignmentNumbers)
        -- Check [Rx.T] tags
        local roleNum = string.match(tagText, "^%[R(%d+)%.T%]$")
        if roleNum then
          local roleIndex = tonumber(roleNum)
          return roles and roles[roleIndex] ~= nil
        end
        
        -- Check [Rx.P] tags (all players in role)
        roleNum = string.match(tagText, "^%[R(%d+)%.P%]$")
        if roleNum then
          local roleIndex = tonumber(roleNum)
          -- Valid if role exists and has at least one assigned player
          if assignments and assignments[roleIndex] then
            for _, playerName in pairs(assignments[roleIndex]) do
              if playerName then
                return true
              end
            end
          end
          return false
        end
        
        -- Check [Rx.PA] tags (all players with assignments)
        roleNum = string.match(tagText, "^%[R(%d+)%.PA%]$")
        if roleNum then
          local roleIndex = tonumber(roleNum)
          -- Valid if role exists and has at least one assigned player
          if assignments and assignments[roleIndex] then
            for _, playerName in pairs(assignments[roleIndex]) do
              if playerName then
                return true
              end
            end
          end
          return false
        end
        
        -- Check [Rx.Py] tags
        local roleNum, playerNum = string.match(tagText, "^%[R(%d+)%.P(%d+)%]$")
        if roleNum and playerNum then
          local roleIndex = tonumber(roleNum)
          local playerIndex = tonumber(playerNum)
          return assignments and assignments[roleIndex] and assignments[roleIndex][playerIndex] ~= nil
        end
        
        -- Check [Rx.My] tags
        roleNum, playerNum = string.match(tagText, "^%[R(%d+)%.M(%d+)%]$")
        if roleNum and playerNum then
          local roleIndex = tonumber(roleNum)
          local playerIndex = tonumber(playerNum)
          if not raidMarks or not raidMarks[roleIndex] or not raidMarks[roleIndex][playerIndex] then
            return false
          end
          local markIndex = raidMarks[roleIndex][playerIndex]
          return markIndex ~= 0
        end
        
        -- Check [Rx.Ay] tags
        roleNum, playerNum = string.match(tagText, "^%[R(%d+)%.A(%d+)%]$")
        if roleNum and playerNum then
          local roleIndex = tonumber(roleNum)
          local playerIndex = tonumber(playerNum)
          if not assignmentNumbers or not assignmentNumbers[roleIndex] or not assignmentNumbers[roleIndex][playerIndex] then
            return false
          end
          local assignIndex = assignmentNumbers[roleIndex][playerIndex]
          return assignIndex ~= 0
        end
        
        -- Check [Rx.A=y] tags (all players with assignment y in role x)
        local roleNum, assignNum = string.match(tagText, "^%[R(%d+)%.A=(%d+)%]$")
        if roleNum and assignNum then
          local roleIndex = tonumber(roleNum)
          local targetAssign = tonumber(assignNum)
          
          -- Check if any player in this role has this assignment
          if assignmentNumbers and assignmentNumbers[roleIndex] and assignments and assignments[roleIndex] then
            for slotIndex, playerName in pairs(assignments[roleIndex]) do
              if playerName and assignmentNumbers[roleIndex][slotIndex] == targetAssign then
                return true -- At least one player has this assignment
              end
            end
          end
          
          return false -- No players with this assignment
        end
        
        -- Check [Rx.Cy] tags (Consume items)
        roleNum, consumeNum = string.match(tagText, "^%[R(%d+)%.C(%d+)%]$")
        if roleNum and consumeNum then
          local roleIndex = tonumber(roleNum)
          local consumeIndex = tonumber(consumeNum)
          
          -- Check if role is a consume check role and has consume data
          if roles and roles[roleIndex] and roles[roleIndex].isConsumeCheck then
            if roles[roleIndex].consumes and roles[roleIndex].consumes[consumeIndex] then
              local consumeData = roles[roleIndex].consumes[consumeIndex]
              -- Valid if primary name is set
              return consumeData.primaryName ~= nil and consumeData.primaryName ~= ""
            end
          end
          
          return false -- Invalid consume reference
        end
        
        return true -- Not a tag, consider it valid
      end
      
      -- Process conditional blocks: [text with [tags]]
      -- Default is OR: show block if ANY tag is valid, hide if ALL are invalid
      -- If first char after [ is &, it's AND: show block only if ALL tags are valid
      local function ProcessConditionals(inputText)
        local result = inputText
        local maxIterations = 100 -- Prevent infinite loops
        local iterations = 0
        
        while iterations < maxIterations do
          iterations = iterations + 1
          local foundBlock = false
          
          -- Find innermost conditional blocks
          -- Look for patterns like [text [Rx.T] more text] where there's at least one tag
          local searchPos = 1
          local bestStart, bestEnd, bestContent = nil, nil, nil
          
          while searchPos <= string.len(result) do
            -- Find opening bracket
            local openBracket = string.find(result, "%[", searchPos)
            if not openBracket then break end
            
            -- Find matching closing bracket (innermost one)
            local closeBracket = openBracket + 1
            local nestLevel = 0
            local foundClose = false
            
            while closeBracket <= string.len(result) do
              local char = string.sub(result, closeBracket, closeBracket)
              if char == "[" then
                nestLevel = nestLevel + 1
              elseif char == "]" then
                if nestLevel == 0 then
                  foundClose = true
                  break
                else
                  nestLevel = nestLevel - 1
                end
              end
              closeBracket = closeBracket + 1
            end
            
            if foundClose then
              local content = string.sub(result, openBracket + 1, closeBracket - 1)
              
              -- Check if this block contains at least one tag
              if string.find(content, "%[R%d+%.[TPMAC]") then
                -- This is a conditional block
                bestStart = openBracket
                bestEnd = closeBracket
                bestContent = content
                foundBlock = true
                break
              end
            end
            
            searchPos = openBracket + 1
          end
          
          if not foundBlock then
            break
          end
          
          -- Process this conditional block
          local isAndBlock = false
          local contentToCheck = bestContent
          
          if string.sub(bestContent, 1, 1) == "&" then
            isAndBlock = true
            contentToCheck = string.sub(bestContent, 2) -- Remove the & prefix
          end
          
          -- Collect all tags and their validity
          local tags = {}
          local pos = 1
          
          while true do
            local tagStart, tagEnd = string.find(contentToCheck, "%[R%d+%.[TPMAC][^%]]*%]", pos)
            if not tagStart then break end
            
            local tagText = string.sub(contentToCheck, tagStart, tagEnd)
            local valid = IsTagValid(tagText, assignmentNumbers)
            
            table.insert(tags, {
              text = tagText,
              valid = valid,
              startPos = tagStart,
              endPos = tagEnd
            })
            
            pos = tagEnd + 1
          end
          
          -- Determine if block should be shown
          local showBlock = false
          
          if isAndBlock then
            -- AND logic: show only if ALL tags are valid
            showBlock = true
            for _, tag in ipairs(tags) do
              if not tag.valid then
                showBlock = false
                break
              end
            end
          else
            -- OR logic: show if ANY tag is valid
            showBlock = false
            for _, tag in ipairs(tags) do
              if tag.valid then
                showBlock = true
                break
              end
            end
          end
          
          -- Replace the conditional block
          local before = string.sub(result, 1, bestStart - 1)
          local after = string.sub(result, bestEnd + 1)
          
          if showBlock then
            -- For OR blocks, remove invalid tags from the content
            if not isAndBlock then
              -- Build cleaned content by removing invalid tags
              local cleanedContent = ""
              local lastPos = 1
              
              -- Sort tags by start position
              table.sort(tags, function(a, b) return a.startPos < b.startPos end)
              
              for _, tag in ipairs(tags) do
                if tag.valid then
                  -- Keep everything up to and including this valid tag
                  cleanedContent = cleanedContent .. string.sub(contentToCheck, lastPos, tag.endPos)
                  lastPos = tag.endPos + 1
                else
                  -- Keep text before the invalid tag, skip the tag itself
                  cleanedContent = cleanedContent .. string.sub(contentToCheck, lastPos, tag.startPos - 1)
                  lastPos = tag.endPos + 1
                end
              end
              
              -- Add any remaining text after the last tag
              if lastPos <= string.len(contentToCheck) then
                cleanedContent = cleanedContent .. string.sub(contentToCheck, lastPos)
              end
              
              result = before .. cleanedContent .. after
            else
              -- For AND blocks, keep all content as-is (all tags are valid)
              result = before .. contentToCheck .. after
            end
          else
            -- Remove the entire block
            result = before .. after
          end
        end
        
        return result
      end
      
      -- First, process conditional blocks
      local result = ProcessConditionals(text)
      
      -- Build a table of tag replacements with their positions
      local replacements = {}
      
      -- Helper to add a replacement
      local function AddReplacement(startPos, endPos, replacement, color, isValid)
        table.insert(replacements, {
          startPos = startPos,
          endPos = endPos,
          text = replacement,
          color = color,
          isValid = isValid
        })
      end
      
      -- Find [Rx.T] tags (Role Title)
      local pos = 1
      while true do
        local tagStart, tagEnd, roleNum = string.find(result, "%[R(%d+)%.T%]", pos)
        if not tagStart then break end
        
        local roleIndex = tonumber(roleNum)
        
        if roles and roles[roleIndex] then
          local replacement = roles[roleIndex].name or "Unknown"
          local color = OGRH.COLOR.HEADER
          AddReplacement(tagStart, tagEnd, replacement, color, true)
        else
          -- Invalid tag - replace with empty string
          AddReplacement(tagStart, tagEnd, "", "", false)
        end
        
        pos = tagEnd + 1
      end
      
      -- Find [Rx.P] tags (All Players in Role) - Must come before [Rx.Py]
      pos = 1
      while true do
        local tagStart, tagEnd, roleNum = string.find(result, "%[R(%d+)%.P%]", pos)
        if not tagStart then break end
        
        local roleIndex = tonumber(roleNum)
        
        -- Build list of all players in this role with class colors
        local allPlayers = {}
        
        if assignments and assignments[roleIndex] then
          -- Iterate through all slots in this role
          for slotIndex, playerName in pairs(assignments[roleIndex]) do
            if playerName then
              -- Get player's class for coloring
              local playerClass = GetPlayerClass(playerName)
              local color = OGRH.COLOR.ROLE
              
              if playerClass and OGRH.COLOR.CLASS[string.upper(playerClass)] then
                color = OGRH.COLOR.CLASS[string.upper(playerClass)]
              end
              
              -- Add player with color code prefix only (no reset)
              table.insert(allPlayers, {index = slotIndex, name = color .. playerName})
            end
          end
        end
        
        if table.getn(allPlayers) > 0 then
          -- Sort by slot index to maintain assignment order
          table.sort(allPlayers, function(a, b) return a.index < b.index end)
          
          -- Extract just the names
          local playerNames = {}
          for _, player in ipairs(allPlayers) do
            table.insert(playerNames, player.name)
          end
          
          -- Join with space and reset code between each player
          local playerList = table.concat(playerNames, OGRH.COLOR.RESET .. " ")
          -- Pass empty color and use the embedded colors
          AddReplacement(tagStart, tagEnd, playerList, "", false)
        else
          -- No players - replace with empty string
          AddReplacement(tagStart, tagEnd, "", "", false)
        end
        
        pos = tagEnd + 1
      end
      
      -- Find [Rx.PA] tags (All Players with Assignment Numbers)
      pos = 1
      while true do
        local tagStart, tagEnd, roleNum = string.find(result, "%[R(%d+)%.PA%]", pos)
        if not tagStart then break end
        
        local roleIndex = tonumber(roleNum)
        
        -- Build list of all players in this role with their assignment numbers
        local allPlayers = {}
        
        if assignments and assignments[roleIndex] then
          -- Iterate through all slots in this role
          for slotIndex, playerName in pairs(assignments[roleIndex]) do
            if playerName then
              -- Get player's class for coloring
              local playerClass = GetPlayerClass(playerName)
              local color = OGRH.COLOR.ROLE
              
              if playerClass and OGRH.COLOR.CLASS[string.upper(playerClass)] then
                color = OGRH.COLOR.CLASS[string.upper(playerClass)]
              end
              
              -- Get assignment number for this player
              local assignNum = ""
              if assignmentNumbers and assignmentNumbers[roleIndex] and assignmentNumbers[roleIndex][slotIndex] then
                local assignIndex = assignmentNumbers[roleIndex][slotIndex]
                if assignIndex and assignIndex ~= 0 then
                  assignNum = " (" .. assignIndex .. ")"
                end
              end
              
              -- Add player with color code and assignment number
              table.insert(allPlayers, {index = slotIndex, text = color .. playerName .. assignNum})
            end
          end
        end
        
        if table.getn(allPlayers) > 0 then
          -- Sort by slot index to maintain assignment order
          table.sort(allPlayers, function(a, b) return a.index < b.index end)
          
          -- Extract just the text
          local playerTexts = {}
          for _, player in ipairs(allPlayers) do
            table.insert(playerTexts, player.text)
          end
          
          -- Join with space and reset code between each player
          local playerList = table.concat(playerTexts, OGRH.COLOR.RESET .. " ")
          -- Pass empty color and use the embedded colors
          AddReplacement(tagStart, tagEnd, playerList, "", false)
        else
          -- No players - replace with empty string
          AddReplacement(tagStart, tagEnd, "", "", false)
        end
        
        pos = tagEnd + 1
      end
      
      -- Find [Rx.Py] tags (Player Name)
      pos = 1
      while true do
        local tagStart, tagEnd, roleNum, playerNum = string.find(result, "%[R(%d+)%.P(%d+)%]", pos)
        if not tagStart then break end
        
        local roleIndex = tonumber(roleNum)
        local playerIndex = tonumber(playerNum)
        
        if assignments and assignments[roleIndex] and assignments[roleIndex][playerIndex] then
          local playerName = assignments[roleIndex][playerIndex]
          local playerClass = GetPlayerClass(playerName)
          local color = OGRH.COLOR.ROLE
          
          if playerClass and OGRH.COLOR.CLASS[string.upper(playerClass)] then
            color = OGRH.COLOR.CLASS[string.upper(playerClass)]
          end
          
          AddReplacement(tagStart, tagEnd, playerName, color, true)
        else
          -- Invalid tag - replace with empty string
          AddReplacement(tagStart, tagEnd, "", "", false)
        end
        
        pos = tagEnd + 1
      end
      
      -- Find [Rx.My] tags (Raid Mark)
      pos = 1
      while true do
        local tagStart, tagEnd, roleNum, playerNum = string.find(result, "%[R(%d+)%.M(%d+)%]", pos)
        if not tagStart then break end
        
        local roleIndex = tonumber(roleNum)
        local playerIndex = tonumber(playerNum)
        
        -- Raid mark names
        local markNames = {
          [1] = "(Star)",
          [2] = "(Circle)",
          [3] = "(Diamond)",
          [4] = "(Triangle)",
          [5] = "(Moon)",
          [6] = "(Square)",
          [7] = "(Cross)",
          [8] = "(Skull)"
        }
        
        if raidMarks and raidMarks[roleIndex] and raidMarks[roleIndex][playerIndex] then
          local markIndex = raidMarks[roleIndex][playerIndex]
          if markIndex ~= 0 and markNames[markIndex] then
            local color = OGRH.COLOR.MARK[markIndex] or OGRH.COLOR.ROLE
            AddReplacement(tagStart, tagEnd, markNames[markIndex], color, true)
          else
            -- Mark is 0 (none) - replace with empty string
            AddReplacement(tagStart, tagEnd, "", "", false)
          end
        else
          -- Invalid tag - replace with empty string
          AddReplacement(tagStart, tagEnd, "", "", false)
        end
        
        pos = tagEnd + 1
      end
      
      -- Find [Rx.Ay] tags (Assignment Number)
      pos = 1
      while true do
        local tagStart, tagEnd, roleNum, playerNum = string.find(result, "%[R(%d+)%.A(%d+)%]", pos)
        if not tagStart then break end
        
        local roleIndex = tonumber(roleNum)
        local playerIndex = tonumber(playerNum)
        
        if assignmentNumbers and assignmentNumbers[roleIndex] and assignmentNumbers[roleIndex][playerIndex] then
          local assignIndex = assignmentNumbers[roleIndex][playerIndex]
          if assignIndex ~= 0 then
            local color = OGRH.COLOR.ROLE
            AddReplacement(tagStart, tagEnd, tostring(assignIndex), color, true)
          else
            -- Assignment is 0 (none) - replace with empty string
            AddReplacement(tagStart, tagEnd, "", "", false)
          end
        else
          -- Invalid tag - replace with empty string
          AddReplacement(tagStart, tagEnd, "", "", false)
        end
        
        pos = tagEnd + 1
      end
      
      -- Find [Rx.A=y] tags (All players with assignment number y in role x)
      pos = 1
      while true do
        local tagStart, tagEnd, roleNum, assignNum = string.find(result, "%[R(%d+)%.A=(%d+)%]", pos)
        if not tagStart then break end
        
        local roleIndex = tonumber(roleNum)
        local targetAssign = tonumber(assignNum)
        
        -- Build list of players with this assignment number with class colors
        local matchingPlayers = {}
        
        if assignmentNumbers and assignmentNumbers[roleIndex] and assignments and assignments[roleIndex] then
          -- Iterate through all slots in this role
          for slotIndex, playerName in pairs(assignments[roleIndex]) do
            if playerName and assignmentNumbers[roleIndex][slotIndex] == targetAssign then
              -- Get player's class for coloring
              local playerClass = GetPlayerClass(playerName)
              local color = OGRH.COLOR.ROLE
              
              if playerClass and OGRH.COLOR.CLASS[string.upper(playerClass)] then
                color = OGRH.COLOR.CLASS[string.upper(playerClass)]
              end
              
              -- Add player with color code prefix only (no reset)
              table.insert(matchingPlayers, color .. playerName)
            end
          end
        end
        
        if table.getn(matchingPlayers) > 0 then
          -- Join with space and reset code between each player
          local playerList = table.concat(matchingPlayers, OGRH.COLOR.RESET .. " ")
          -- Pass empty color and use the embedded colors
          AddReplacement(tagStart, tagEnd, playerList, "", false)
        else
          -- No matching players - replace with empty string
          AddReplacement(tagStart, tagEnd, "", "", false)
        end
        
        pos = tagEnd + 1
      end
      
      -- Find [Rx.Cy] tags (Consume items from Consume Check role)
      pos = 1
      while true do
        local tagStart, tagEnd, roleNum, consumeNum = string.find(result, "%[R(%d+)%.C(%d+)%]", pos)
        if not tagStart then break end
        
        local roleIndex = tonumber(roleNum)
        local consumeIndex = tonumber(consumeNum)
        
        -- Check if this role is a consume check role
        if roles and roles[roleIndex] and roles[roleIndex].isConsumeCheck then
          local consumeRole = roles[roleIndex]
          
          -- Check if consume data exists for this index
          if consumeRole.consumes and consumeRole.consumes[consumeIndex] then
            local consumeData = consumeRole.consumes[consumeIndex]
            
            -- Use the helper function to format item links (no escaping needed)
            local consumeText = ""
            if OGRH.FormatConsumeItemLinks then
              consumeText = OGRH.FormatConsumeItemLinks(consumeData, false)
            end
            
            if consumeText ~= "" then
              -- Item links have their own color codes and must be inserted exactly as-is
              -- Use special marker to indicate this replacement should not be wrapped
              AddReplacement(tagStart, tagEnd, consumeText, "__NOCOLOR__", false)
            else
              -- No consume configured - replace with empty string
              AddReplacement(tagStart, tagEnd, "", "", false)
            end
          else
            -- Invalid consume index - replace with empty string
            AddReplacement(tagStart, tagEnd, "", "", false)
          end
        else
          -- Not a consume check role - replace with empty string
          AddReplacement(tagStart, tagEnd, "", "", false)
        end
        
        pos = tagEnd + 1
      end
      
      -- Sort replacements by position (descending) so we can replace from end to start
      table.sort(replacements, function(a, b) return a.startPos > b.startPos end)
      
      -- Build result string by replacing tags from end to start
      for _, repl in ipairs(replacements) do
        local before = string.sub(result, 1, repl.startPos - 1)
        local after = string.sub(result, repl.endPos + 1)
        
        if repl.text == "" then
          -- Empty replacement - just remove the tag
          result = before .. after
        elseif repl.color == "__NOCOLOR__" then
          -- Special case: Item links that must be inserted exactly as-is
          result = before .. repl.text .. after
        else
          -- Non-empty replacement - add with color codes
          result = before .. repl.color .. repl.text .. OGRH.COLOR.RESET .. after
        end
      end
      
      -- Color any plain text with ROLE color
      -- BUT: If the result contains item links (|H), skip this processing entirely
      -- Item links are fragile and must be sent exactly as-is
      if string.find(result, "|H", 1, true) then
        return result
      end
      
      -- Split by color codes to identify plain text
      local finalResult = ""
      local lastPos = 1
      
      while true do
        -- Find next color code
        local colorStart = string.find(result, "|c%x%x%x%x%x%x%x%x", lastPos)
        local hyperlinkStart = nil  -- Not needed since we skip if |H exists
        
        if not colorStart then
          -- No more color codes or hyperlinks, add remaining text
          local remaining = string.sub(result, lastPos)
          if remaining ~= "" then
            finalResult = finalResult .. OGRH.COLOR.ROLE .. remaining .. OGRH.COLOR.RESET
          end
          break
        end
        
        -- Add plain text before color code
        if colorStart > lastPos then
          local plainText = string.sub(result, lastPos, colorStart - 1)
          finalResult = finalResult .. OGRH.COLOR.ROLE .. plainText .. OGRH.COLOR.RESET
        end
        
        -- Find the end of this colored section (next |r or end of string)
        local resetPos = string.find(result, "|r", colorStart)
        if not resetPos then
          -- Add rest of string as-is
          finalResult = finalResult .. string.sub(result, colorStart)
          break
        end
        
        -- Add colored section
        finalResult = finalResult .. string.sub(result, colorStart, resetPos + 1)
        lastPos = resetPos + 2
      end
      
      return finalResult
    end
    
    -- Store ReplaceTags on frame for external access (e.g., tooltip generation)
    frame.ReplaceTags = ReplaceTags
    
    -- Enable right-click on announce button
    announceBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    
    -- Announce functionality
    announceBtn:SetScript("OnClick", function()
      local button = arg1 or "LeftButton"
      
      if not frame.selectedRaid or not frame.selectedEncounter then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OGRH:|r Please select a raid and encounter first.")
        return
      end
      
      -- Right-click: Announce consumes
      if button == "RightButton" then
        -- Get role configuration
        local roles = OGRH_SV.encounterMgmt.roles
        if not roles or not roles[frame.selectedRaid] or not roles[frame.selectedRaid][frame.selectedEncounter] then
          return -- Silently do nothing if no roles configured
        end
        
        local encounterRoles = roles[frame.selectedRaid][frame.selectedEncounter]
        local column1 = encounterRoles.column1 or {}
        local column2 = encounterRoles.column2 or {}
        
        -- Find consume check role
        local consumeRole = nil
        for i = 1, table.getn(column1) do
          if column1[i].isConsumeCheck then
            consumeRole = column1[i]
            break
          end
        end
        if not consumeRole then
          for i = 1, table.getn(column2) do
            if column2[i].isConsumeCheck then
              consumeRole = column2[i]
              break
            end
          end
        end
        
        -- If no consume role found, do nothing
        if not consumeRole or not consumeRole.consumes then
          return
        end
        
        -- Check if in raid
        if GetNumRaidMembers() == 0 then
          DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OGRH:|r You must be in a raid to announce.")
          return
        end
        
        -- Build consume announcement lines
        local announceLines = {}
        local titleColor = OGRH.COLOR.HEADER or "|cFFFFD100"
        table.insert(announceLines, titleColor .. "Consumes for " .. frame.selectedEncounter .. OGRH.COLOR.RESET)
        
        for i = 1, (consumeRole.slots or 1) do
          if consumeRole.consumes[i] then
            local consumeData = consumeRole.consumes[i]
            local items = {}
            
            -- Add primary item
            if consumeData.primaryId then
              table.insert(items, consumeData.primaryId)
            end
            
            -- Add secondary item if alternate allowed
            if consumeData.allowAlternate and consumeData.secondaryId then
              table.insert(items, consumeData.secondaryId)
            end
            
            -- Build line with item links
            if table.getn(items) > 0 then
              local lineText = ""
              for j = 1, table.getn(items) do
                local itemId = items[j]
                local itemName, itemLink, quality = GetItemInfo(itemId)
                
                if j > 1 then
                  lineText = lineText .. " / "
                end
                
                -- Construct chat link using AtlasLoot method
                if itemLink and itemName then
                  local _, _, _, color = GetItemQualityColor(quality)
                  lineText = lineText .. color .. "|H" .. itemLink .. "|h[" .. itemName .. "]|h|r"
                elseif itemName then
                  lineText = lineText .. itemName
                else
                  lineText = lineText .. "Item " .. itemId
                end
              end
              table.insert(announceLines, lineText)
            end
          end
        end
        
        -- Send to raid warning
        for _, line in ipairs(announceLines) do
          SendChatMessage(line, "RAID_WARNING")
        end
        
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OGRH:|r Consumes announced to raid warning.")
        return
      end
      
      -- Left-click: Normal announcement
      
      -- Get role configuration
      local roles = OGRH_SV.encounterMgmt.roles
      if not roles or not roles[frame.selectedRaid] or not roles[frame.selectedRaid][frame.selectedEncounter] then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OGRH:|r No roles configured for this encounter.")
        return
      end
      
      local encounterRoles = roles[frame.selectedRaid][frame.selectedEncounter]
      local column1 = encounterRoles.column1 or {}
      local column2 = encounterRoles.column2 or {}
      
      -- Build ordered list of roles for tag replacement
      local orderedRoles = {}
      
      -- Add all roles from column1 first (top to bottom)
      for i = 1, table.getn(column1) do
        table.insert(orderedRoles, column1[i])
      end
      
      -- Then add all roles from column2 (top to bottom)
      for i = 1, table.getn(column2) do
        table.insert(orderedRoles, column2[i])
      end
      
      -- Get assignments
      local assignments = {}
      if OGRH_SV.encounterAssignments and 
         OGRH_SV.encounterAssignments[frame.selectedRaid] and
         OGRH_SV.encounterAssignments[frame.selectedRaid][frame.selectedEncounter] then
        assignments = OGRH_SV.encounterAssignments[frame.selectedRaid][frame.selectedEncounter]
      end
      
      -- Get raid marks
      local raidMarks = {}
      if OGRH_SV.encounterRaidMarks and
         OGRH_SV.encounterRaidMarks[frame.selectedRaid] and
         OGRH_SV.encounterRaidMarks[frame.selectedRaid][frame.selectedEncounter] then
        raidMarks = OGRH_SV.encounterRaidMarks[frame.selectedRaid][frame.selectedEncounter]
      end
      
      -- Get assignment numbers
      local assignmentNumbers = {}
      if OGRH_SV.encounterAssignmentNumbers and
         OGRH_SV.encounterAssignmentNumbers[frame.selectedRaid] and
         OGRH_SV.encounterAssignmentNumbers[frame.selectedRaid][frame.selectedEncounter] then
        assignmentNumbers = OGRH_SV.encounterAssignmentNumbers[frame.selectedRaid][frame.selectedEncounter]
      end
      
      -- Get announcement text and replace tags
      local announcementLines = {}
      if frame.announcementLines then
        for i = 1, table.getn(frame.announcementLines) do
          local lineText = frame.announcementLines[i]:GetText()
          if lineText and lineText ~= "" then
            local processedText = ReplaceTags(lineText, orderedRoles, assignments, raidMarks, assignmentNumbers)
            table.insert(announcementLines, processedText)
          end
        end
      end
      
      -- Send announcements to raid chat
      if table.getn(announcementLines) == 0 then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OGRH:|r No announcement text to send.")
        return
      end
      
      -- Check if in raid
      if GetNumRaidMembers() == 0 then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OGRH:|r You must be in a raid to announce.")
        return
      end
      
      -- Send announcement and store for re-announce
      if OGRH.SendAnnouncement then
        OGRH.SendAnnouncement(announcementLines)
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OGRH:|r Announcement sent to raid chat and stored for RA button.")
      else
        -- Fallback if SendAnnouncement not loaded
        for _, line in ipairs(announcementLines) do
          SendChatMessage(line, "RAID")
        end
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OGRH:|r Announcement sent to raid chat.")
      end
    end)
    
    -- Mark Players button (below Announce, reduced height)
    local markPlayersBtn = CreateFrame("Button", nil, bottomPanel, "UIPanelButtonTemplate")
    markPlayersBtn:SetWidth(120)
    markPlayersBtn:SetHeight(24)
    markPlayersBtn:SetPoint("TOPLEFT", announceBtn, "BOTTOMLEFT", 0, -6)
    markPlayersBtn:SetText("Mark Players")
    OGRH.StyleButton(markPlayersBtn)
    frame.markPlayersBtn = markPlayersBtn
    
    -- Mark Players functionality
    markPlayersBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    markPlayersBtn:SetScript("OnClick", function()
      local button = arg1 or "LeftButton"
      
      -- Check if in raid
      if GetNumRaidMembers() == 0 then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OGRH:|r You must be in a raid to mark players.")
        return
      end
      
      -- Clear all raid marks first
      local clearedCount = 0
      for j = 1, GetNumRaidMembers() do
        SetRaidTarget("raid"..j, 0)
        clearedCount = clearedCount + 1
      end
      
      -- Right click: just clear marks and exit
      if button == "RightButton" then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OGRH:|r Cleared marks on " .. clearedCount .. " raid members.")
        return
      end
      
      -- Left click: clear then apply marks
      if not frame.selectedRaid or not frame.selectedEncounter then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OGRH:|r Please select a raid and encounter first.")
        return
      end
      
      -- Get role configuration
      local roles = OGRH_SV.encounterMgmt.roles
      if not roles or not roles[frame.selectedRaid] or not roles[frame.selectedRaid][frame.selectedEncounter] then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OGRH:|r No roles configured for this encounter.")
        return
      end
      
      local encounterRoles = roles[frame.selectedRaid][frame.selectedEncounter]
      local column1 = encounterRoles.column1 or {}
      local column2 = encounterRoles.column2 or {}
      
      -- Build ordered list of all roles (column1 first, then column2)
      local allRoles = {}
      
      for i = 1, table.getn(column1) do
        table.insert(allRoles, {role = column1[i], roleIndex = table.getn(allRoles) + 1})
      end
      for i = 1, table.getn(column2) do
        table.insert(allRoles, {role = column2[i], roleIndex = table.getn(allRoles) + 1})
      end
      
      -- Get assignments
      local assignments = {}
      if OGRH_SV.encounterAssignments and 
         OGRH_SV.encounterAssignments[frame.selectedRaid] and
         OGRH_SV.encounterAssignments[frame.selectedRaid][frame.selectedEncounter] then
        assignments = OGRH_SV.encounterAssignments[frame.selectedRaid][frame.selectedEncounter]
      end
      
      -- Get raid marks
      local raidMarks = {}
      if OGRH_SV.encounterRaidMarks and
         OGRH_SV.encounterRaidMarks[frame.selectedRaid] and
         OGRH_SV.encounterRaidMarks[frame.selectedRaid][frame.selectedEncounter] then
        raidMarks = OGRH_SV.encounterRaidMarks[frame.selectedRaid][frame.selectedEncounter]
      end
      
      -- Iterate through roles and apply marks
      local markedCount = 0
      
      for _, roleData in ipairs(allRoles) do
        local role = roleData.role
        local roleIndex = roleData.roleIndex
        
        -- Get assigned players for this role
        local assignedPlayers = assignments[roleIndex] or {}
        local roleMarks = raidMarks[roleIndex] or {}
        
        -- Iterate through slots
        for slotIndex = 1, table.getn(assignedPlayers) do
          local playerName = assignedPlayers[slotIndex]
          local markIndex = roleMarks[slotIndex]
          
          if playerName and markIndex and markIndex ~= 0 then
            -- Find player in raid and apply mark
            for j = 1, GetNumRaidMembers() do
              local name = GetRaidRosterInfo(j)
              if name == playerName then
                -- Set raid target icon (1-8)
                SetRaidTarget("raid"..j, markIndex)
                markedCount = markedCount + 1
                break
              end
            end
          end
        end
      end
      
      DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OGRH:|r Marked " .. markedCount .. " players.")
    end)
    
    -- Edit toggle button (below Mark Players)
    local editToggleBtn = CreateFrame("Button", nil, bottomPanel, "UIPanelButtonTemplate")
    editToggleBtn:SetWidth(120)
    editToggleBtn:SetHeight(24)
    editToggleBtn:SetPoint("TOPLEFT", markPlayersBtn, "BOTTOMLEFT", 0, -6)
    editToggleBtn:SetText("|cffff0000Edit: Locked|r")
    OGRH.StyleButton(editToggleBtn)
    frame.editToggleBtn = editToggleBtn
    frame.editMode = false  -- Start in locked mode
    
    -- Function to toggle edit mode
    local function SetEditMode(enabled)
      -- Check if player has permission to edit
      local canEdit = OGRH.CanEdit and OGRH.CanEdit()
      
      -- If trying to enable but no permission, disable and show message
      if enabled and not canEdit then
        enabled = false
        frame.editMode = false
        editToggleBtn:SetText("|cffff0000Edit: Locked|r")
        return
      end
      
      frame.editMode = enabled
      
      if enabled then
        editToggleBtn:SetText("|cff00ff00Edit: Unlocked|r")
      else
        editToggleBtn:SetText("|cffff0000Edit: Locked|r")
      end
      
      -- Enable/disable announcement EditBoxes (only if have permission)
      if frame.announcementLines then
        for i = 1, table.getn(frame.announcementLines) do
          frame.announcementLines[i]:EnableKeyboard(enabled and canEdit)
          frame.announcementLines[i]:EnableMouse(enabled and canEdit)
          if not enabled or not canEdit then
            frame.announcementLines[i]:ClearFocus()
          end
        end
      end
      
      -- Enable/disable all raid mark and assignment buttons in role containers
      -- We'll need to track these when they're created
      if frame.roleContainers then
        for _, container in ipairs(frame.roleContainers) do
          if container.slots then
            for _, slot in ipairs(container.slots) do
              -- Disable/enable raid mark icon buttons
              if slot.iconBtn then
                slot.iconBtn:EnableMouse(enabled)
              end
              -- Disable/enable assignment buttons
              if slot.assignBtn then
                slot.assignBtn:EnableMouse(enabled)
              end
              -- Disable/enable edit buttons
              if slot.editBtn then
                slot.editBtn:EnableMouse(enabled)
              end
            end
          end
        end
      end
    end
    
    frame.SetEditMode = SetEditMode
    
    -- Toggle edit mode on click
    editToggleBtn:SetScript("OnClick", function()
      -- Check permission
      if not frame.editMode and (not OGRH.CanEdit or not OGRH.CanEdit()) then
        OGRH.Msg("Only the raid lead can unlock editing.")
        return
      end
      
      SetEditMode(not frame.editMode)
    end)
    
    -- Announcement Builder label
    local announcementLabel = bottomPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    announcementLabel:SetPoint("TOPLEFT", bottomPanel, "TOPLEFT", 145, -10)
    announcementLabel:SetText("Announcement Builder:")
    
    -- Announcement Builder scroll frame
    local announcementScrollFrame = CreateFrame("ScrollFrame", nil, bottomPanel)
    announcementScrollFrame:SetWidth(430)
    announcementScrollFrame:SetHeight(106)
    announcementScrollFrame:SetPoint("TOPLEFT", announcementLabel, "BOTTOMLEFT", 0, -5)
    announcementScrollFrame:SetBackdrop({
      bgFile = "Interface/Tooltips/UI-Tooltip-Background",
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
      tile = true,
      tileSize = 16,
      edgeSize = 12,
      insets = {left = 3, right = 3, top = 3, bottom = 3}
    })
    announcementScrollFrame:SetBackdropColor(0.05, 0.05, 0.05, 0.9)
    
    -- Scroll child frame
    local announcementFrame = CreateFrame("Frame", nil, announcementScrollFrame)
    announcementFrame:SetWidth(410)
    announcementScrollFrame:SetScrollChild(announcementFrame)
    
    -- Scrollbar
    local announcementScrollBar = CreateFrame("Slider", nil, announcementScrollFrame)
    announcementScrollBar:SetPoint("TOPRIGHT", announcementScrollFrame, "TOPRIGHT", -5, -16)
    announcementScrollBar:SetPoint("BOTTOMRIGHT", announcementScrollFrame, "BOTTOMRIGHT", -5, 16)
    announcementScrollBar:SetWidth(16)
    announcementScrollBar:SetBackdrop({
      bgFile = "Interface/Tooltips/UI-Tooltip-Background",
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 8,
      insets = {left = 3, right = 3, top = 3, bottom = 3}
    })
    announcementScrollBar:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
    announcementScrollBar:SetOrientation("VERTICAL")
    announcementScrollBar:SetMinMaxValues(0, 1)
    announcementScrollBar:SetValue(0)
    announcementScrollBar:SetValueStep(22)
    announcementScrollBar:SetScript("OnValueChanged", function()
      announcementScrollFrame:SetVerticalScroll(this:GetValue())
    end)
    
    -- Mouse wheel scroll support
    announcementScrollFrame:EnableMouseWheel(true)
    announcementScrollFrame:SetScript("OnMouseWheel", function()
      local delta = arg1
      local current = announcementScrollBar:GetValue()
      local minVal, maxVal = announcementScrollBar:GetMinMaxValues()
      
      if delta > 0 then
        announcementScrollBar:SetValue(math.max(minVal, current - 22))
      else
        announcementScrollBar:SetValue(math.min(maxVal, current + 22))
      end
    end)
    
    frame.announcementScrollFrame = announcementScrollFrame
    frame.announcementScrollBar = announcementScrollBar
    
    -- Create individual edit boxes for each line (8 lines)
    frame.announcementLines = {}
    local numLines = 8
    local lineHeight = 18
    local lineSpacing = 2
    
    for i = 1, numLines do
      local lineFrame = CreateFrame("Frame", nil, announcementFrame)
      lineFrame:SetWidth(390)
      lineFrame:SetHeight(lineHeight)
      lineFrame:SetPoint("TOPLEFT", announcementFrame, "TOPLEFT", 5, -5 - ((i - 1) * (lineHeight + lineSpacing)))
      lineFrame:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = false,
        tileSize = 0,
        edgeSize = 8,
        insets = {left = 2, right = 2, top = 2, bottom = 2}
      })
      lineFrame:SetBackdropColor(0.0, 0.0, 0.0, 0.8)
      lineFrame:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)
      
      local editBox = CreateFrame("EditBox", nil, lineFrame)
      editBox:SetWidth(375)
      editBox:SetHeight(lineHeight - 4)
      editBox:SetPoint("LEFT", lineFrame, "LEFT", 5, 0)
      editBox:SetFontObject(GameFontHighlight)
      editBox:SetAutoFocus(false)
      editBox:SetMaxLetters(255)
      
      -- Start in read-only mode
      editBox:EnableKeyboard(false)
      editBox:EnableMouse(false)
      
      editBox:SetScript("OnEscapePressed", function()
        this:ClearFocus()
      end)
      
      editBox:SetScript("OnEnterPressed", function()
        this:ClearFocus()
        -- Move to next line if not the last one
        if i < numLines then
          frame.announcementLines[i + 1]:SetFocus()
        end
      end)
      
      editBox:SetScript("OnTabPressed", function()
        -- Move to next line
        if i < numLines then
          frame.announcementLines[i + 1]:SetFocus()
        else
          frame.announcementLines[1]:SetFocus()
        end
      end)
      
      -- Arrow key navigation
      local capturedLineIndex = i
      editBox:SetScript("OnKeyDown", function()
        local key = arg1
        if key == "UP" then
          -- Move to previous line
          if capturedLineIndex > 1 then
            frame.announcementLines[capturedLineIndex - 1]:SetFocus()
          end
        elseif key == "DOWN" then
          -- Move to next line
          if capturedLineIndex < numLines then
            frame.announcementLines[capturedLineIndex + 1]:SetFocus()
          end
        end
      end)
      
      -- Save text changes to SavedVariables
      local capturedIndex = i
      editBox:SetScript("OnTextChanged", function()
        if frame.selectedRaid and frame.selectedEncounter then
          if not OGRH_SV.encounterAnnouncements then
            OGRH_SV.encounterAnnouncements = {}
          end
          if not OGRH_SV.encounterAnnouncements[frame.selectedRaid] then
            OGRH_SV.encounterAnnouncements[frame.selectedRaid] = {}
          end
          if not OGRH_SV.encounterAnnouncements[frame.selectedRaid][frame.selectedEncounter] then
            OGRH_SV.encounterAnnouncements[frame.selectedRaid][frame.selectedEncounter] = {}
          end
          
          OGRH_SV.encounterAnnouncements[frame.selectedRaid][frame.selectedEncounter][capturedIndex] = this:GetText()
        end
      end)
      
      frame.announcementLines[i] = editBox
    end
    
    -- Set the scroll child height based on content
    local contentHeight = (numLines * (lineHeight + lineSpacing)) + 10
    announcementFrame:SetHeight(contentHeight)
    
    -- Update scrollbar
    local scrollFrameHeight = announcementScrollFrame:GetHeight()
    if contentHeight > scrollFrameHeight then
      announcementScrollBar:Show()
      announcementScrollBar:SetMinMaxValues(0, contentHeight - scrollFrameHeight)
      announcementScrollBar:SetValue(0)
    else
      announcementScrollBar:Hide()
    end
    
    -- Store role containers (will be created dynamically)
    frame.roleContainers = {}
    
    -- Function to refresh players list based on role filter
    frame.RefreshPlayersList = function()
      -- Clear existing player buttons
      local scrollChild = frame.guildScrollChild
      local children = {scrollChild:GetChildren()}
      for _, child in ipairs(children) do
        child:Hide()
        child:SetParent(nil)
      end
      
      -- Get search text
      local searchText = ""
      if frame.playerSearchBox then
        searchText = string.lower(frame.playerSearchBox:GetText() or "")
      end
      
      -- Class filters for each role (both uppercase and mixed case for compatibility)
      local classFilters = {
        tanks = {WARRIOR = true, Warrior = true, PALADIN = true, Paladin = true, DRUID = true, Druid = true, SHAMAN = true, Shaman = true},
        healers = {DRUID = true, Druid = true, PRIEST = true, Priest = true, SHAMAN = true, Shaman = true, PALADIN = true, Paladin = true},
        melee = {WARRIOR = true, Warrior = true, ROGUE = true, Rogue = true, HUNTER = true, Hunter = true, SHAMAN = true, Shaman = true, DRUID = true, Druid = true, PALADIN = true, Paladin = true},
        ranged = {MAGE = true, Mage = true, WARLOCK = true, Warlock = true, HUNTER = true, Hunter = true, DRUID = true, Druid = true, PRIEST = true, Priest = true}
      }
      
      -- Build player list: raid members, online 60s, offline 60s, or signed up players
      local raidPlayers = {}  -- {name=..., class=..., section="raid"}
      local onlinePlayers = {}  -- {name=..., class=..., section="online"}
      local offlinePlayers = {}  -- {name=..., class=..., section="offline"}
      local signedUpPlayers = {}  -- {name=..., class=..., section="tanks"|"healers"|"melee"|"ranged"}
      
      -- Check if we're showing Signed Up filter
      if frame.selectedPlayerRole == "signedup" then
        -- Get RollFor sign-up data
        if RollForCharDb and RollForCharDb.softres and RollForCharDb.softres.data then
          local encodedData = RollForCharDb.softres.data
          if encodedData and type(encodedData) == "string" and RollFor and RollFor.SoftRes and RollFor.SoftRes.decode then
            local decodedData = RollFor.SoftRes.decode(encodedData)
            if decodedData and RollFor.SoftResDataTransformer and RollFor.SoftResDataTransformer.transform then
              local softresData = RollFor.SoftResDataTransformer.transform(decodedData)
              if softresData and type(softresData) == "table" then
                -- Map RollFor role to OGRH role bucket
                local roleMap = {
                  DruidBear = "TANKS", PaladinProtection = "TANKS", ShamanTank = "TANKS", WarriorProtection = "TANKS",
                  DruidRestoration = "HEALERS", PaladinHoly = "HEALERS", PriestHoly = "HEALERS", ShamanRestoration = "HEALERS",
                  DruidFeral = "MELEE", HunterSurvival = "MELEE", PaladinRetribution = "MELEE", RogueDaggers = "MELEE",
                  RogueSwords = "MELEE", ShamanEnhancement = "MELEE", WarriorArms = "MELEE", WarriorFury = "MELEE",
                  DruidBalance = "RANGED", HunterMarksmanship = "RANGED", HunterBeastMastery = "RANGED", MageArcane = "RANGED",
                  MageFire = "RANGED", MageFrost = "RANGED", PriestDiscipline = "RANGED", PriestShadow = "RANGED",
                  ShamanElemental = "RANGED", WarlockAffliction = "RANGED", WarlockDemonology = "RANGED", WarlockDestruction = "RANGED"
                }
                
                local playerMap = {}
                for itemId, itemData in pairs(softresData) do
                  if type(itemData) == "table" and itemData.rollers then
                    for _, roller in ipairs(itemData.rollers) do
                      if roller and roller.name then
                        if not playerMap[roller.name] then
                          local roleBucket = roleMap[roller.role] or "RANGED"
                          local class = OGRH.GetPlayerClass(roller.name)
                          if not class then
                            -- Try to get from guild roster
                            local numGuild = GetNumGuildMembers(true)
                            for i = 1, numGuild do
                              local guildName, _, _, _, guildClass = GetGuildRosterInfo(i)
                              if guildName == roller.name and guildClass then
                                class = string.upper(guildClass)
                                OGRH.classCache[roller.name] = class
                                break
                              end
                            end
                          end
                          
                          playerMap[roller.name] = {
                            name = roller.name,
                            class = class or "UNKNOWN",
                            section = string.lower(roleBucket)  -- tanks, healers, melee, ranged
                          }
                        end
                      end
                    end
                  end
                end
                
                -- Convert to array and apply search filter
                for _, playerData in pairs(playerMap) do
                  if searchText == "" or string.find(string.lower(playerData.name), searchText, 1, true) then
                    table.insert(signedUpPlayers, playerData)
                  end
                end
              end
            end
          end
        end
      else
        -- Get raid members first (from RolesUI data)
        local numRaid = GetNumRaidMembers()
        if numRaid > 0 then
        -- Build role assignments from RolesUI
        local roleAssignments = {}  -- playerName -> {tanks=true, healers=true, etc}
        
        local tankPlayers = OGRH.GetRolePlayers("TANKS") or {}
        local healerPlayers = OGRH.GetRolePlayers("HEALERS") or {}
        local meleePlayers = OGRH.GetRolePlayers("MELEE") or {}
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
              -- Apply role filter - check RolesUI assignments for raid members
              local include = false
              if frame.selectedPlayerRole == "all" then
                include = true
              else
                -- For raid members, check their actual role assignment
                local assignments = roleAssignments[name]
                if assignments and assignments[frame.selectedPlayerRole] then
                  include = true
                end
              end
              
              if include then
                table.insert(raidPlayers, {name = name, class = string.upper(class), section = "raid"})
              end
            end
          end
        end
      end
      
      -- Build a set of raid member names for deduplication
      local raidNames = {}
      for _, p in ipairs(raidPlayers) do
        raidNames[p.name] = true
      end
      
      -- Get guild members (level 60 only)
      local numGuildMembers = GetNumGuildMembers(true)
      for i = 1, numGuildMembers do
        local name, _, _, level, class, _, _, _, online = GetGuildRosterInfo(i)
        if name and level == 60 and not raidNames[name] and class then
          -- Cache the class
          OGRH.classCache[name] = string.upper(class)
          
          -- Apply search filter
          if searchText == "" or string.find(string.lower(name), searchText, 1, true) then
            -- Apply role filter
            local include = false
            if frame.selectedPlayerRole == "all" then
              include = true
            else
              local filter = classFilters[frame.selectedPlayerRole]
              if filter and (filter[class] or filter[string.upper(class)]) then
                include = true
              end
            end
            
            if include then
              if online then
                table.insert(onlinePlayers, {name = name, class = string.upper(class), section = "online"})
              else
                table.insert(offlinePlayers, {name = name, class = string.upper(class), section = "offline"})
              end
            end
          end
        end
      end
      end  -- end of signedup filter check
      
      -- Sort each section alphabetically
      table.sort(raidPlayers, function(a, b) return a.name < b.name end)
      table.sort(onlinePlayers, function(a, b) return a.name < b.name end)
      table.sort(offlinePlayers, function(a, b) return a.name < b.name end)
      table.sort(signedUpPlayers, function(a, b)
        if a.section ~= b.section then
          local order = {tanks = 1, healers = 2, melee = 3, ranged = 4}
          return (order[a.section] or 5) < (order[b.section] or 5)
        end
        return a.name < b.name
      end)
      
      -- Combine all sections
      local players = {}
      if frame.selectedPlayerRole == "signedup" then
        -- Only show signed up players
        for _, p in ipairs(signedUpPlayers) do
          table.insert(players, p)
        end
      else
        -- Show raid/guild roster
        for _, p in ipairs(raidPlayers) do
          table.insert(players, p)
        end
        for _, p in ipairs(onlinePlayers) do
          table.insert(players, p)
        end
        for _, p in ipairs(offlinePlayers) do
          table.insert(players, p)
        end
      end
      
      -- Create section headers and draggable buttons for each player
      local yOffset = 0
      local lastSection = nil
      
      for i, playerData in ipairs(players) do
        -- Add section header if section changed
        if playerData.section ~= lastSection then
          local sectionLabel = ""
          if playerData.section == "raid" then
            sectionLabel = "In Raid"
          elseif playerData.section == "online" then
            sectionLabel = "Online"
          elseif playerData.section == "offline" then
            sectionLabel = "Offline"
          elseif playerData.section == "tanks" then
            sectionLabel = "Tanks"
          elseif playerData.section == "healers" then
            sectionLabel = "Healers"
          elseif playerData.section == "melee" then
            sectionLabel = "Melee"
          elseif playerData.section == "ranged" then
            sectionLabel = "Ranged"
          end
          
          if sectionLabel ~= "" then
            -- Create header as a frame so it gets cleaned up properly
            local headerFrame = CreateFrame("Frame", nil, scrollChild)
            headerFrame:SetWidth(170)
            headerFrame:SetHeight(16)
            headerFrame:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 2, -yOffset)
            
            local headerText = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            headerText:SetPoint("LEFT", headerFrame, "LEFT", 0, 0)
            headerText:SetText("|cffaaaaaa" .. sectionLabel .. "|r")
            
            yOffset = yOffset + 18
          end
          
          lastSection = playerData.section
        end
        
        local playerName = playerData.name
        local playerClass = playerData.class
        
        local playerBtn = OGRH.CreateStyledListItem(scrollChild, frame.guildContentWidth, OGRH.LIST_ITEM_HEIGHT, "Button")
        playerBtn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 2, -yOffset)
        
        -- Player name with class color
        local classColor = RAID_CLASS_COLORS[playerClass] or {r=1, g=1, b=1}
        
        local nameText = playerBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        nameText:SetPoint("LEFT", playerBtn, "LEFT", 5, 0)
        nameText:SetText(playerName)
        nameText:SetTextColor(classColor.r, classColor.g, classColor.b)
        
        -- Make draggable
        playerBtn.playerName = playerName
        playerBtn:RegisterForDrag("LeftButton")
        playerBtn:SetScript("OnDragStart", function()
          -- Check permission
          if not OGRH.CanEdit or not OGRH.CanEdit() then
            return
          end
          
          -- Create drag frame
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
          dragText:SetText(playerName)
          dragText:SetTextColor(classColor.r, classColor.g, classColor.b)
          
          dragFrame:SetScript("OnUpdate", function()
            local x, y = GetCursorPosition()
            local scale = UIParent:GetEffectiveScale()
            dragFrame:ClearAllPoints()
            dragFrame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
          end)
          
          frame.currentDragFrame = dragFrame
          frame.draggedPlayerName = playerName
        end)
        
        playerBtn:SetScript("OnDragStop", function()
          if frame.currentDragFrame then
            frame.currentDragFrame:Hide()
            frame.currentDragFrame:SetParent(nil)
            frame.currentDragFrame = nil
          end
          
          -- Check if we're over a role slot
          if frame.draggedPlayerName then
            local x, y = GetCursorPosition()
            local scale = UIParent:GetEffectiveScale()
            x = x/scale
            y = y/scale
            
            -- Find which slot we're over
            local foundTarget = false
            local targetRoleIndex = nil
            local targetSlotIndex = nil
            
            if frame.roleContainers then
              for _, container in ipairs(frame.roleContainers) do
                if container.slots then
                  for slotIdx, testSlot in ipairs(container.slots) do
                    if testSlot then
                      local left = testSlot:GetLeft()
                      local right = testSlot:GetRight()
                      local bottom = testSlot:GetBottom()
                      local top = testSlot:GetTop()
                      
                      if left and right and bottom and top and
                         x >= left and x <= right and y >= bottom and y <= top then
                        targetRoleIndex = testSlot.roleIndex
                        targetSlotIndex = testSlot.slotIndex
                        foundTarget = true
                        break
                      end
                    end
                  end
                end
                if foundTarget then break end
              end
            end
            
            -- Assign player to slot if we found a target
            if foundTarget and targetRoleIndex and targetSlotIndex then
              if not OGRH_SV.encounterAssignments then
                OGRH_SV.encounterAssignments = {}
              end
              if not OGRH_SV.encounterAssignments[frame.selectedRaid] then
                OGRH_SV.encounterAssignments[frame.selectedRaid] = {}
              end
              if not OGRH_SV.encounterAssignments[frame.selectedRaid][frame.selectedEncounter] then
                OGRH_SV.encounterAssignments[frame.selectedRaid][frame.selectedEncounter] = {}
              end
              if not OGRH_SV.encounterAssignments[frame.selectedRaid][frame.selectedEncounter][targetRoleIndex] then
                OGRH_SV.encounterAssignments[frame.selectedRaid][frame.selectedEncounter][targetRoleIndex] = {}
              end
              
              OGRH_SV.encounterAssignments[frame.selectedRaid][frame.selectedEncounter][targetRoleIndex][targetSlotIndex] = frame.draggedPlayerName
              
              -- Broadcast assignment update (minimal sync)
              if OGRH.BroadcastAssignmentUpdate then
                OGRH.BroadcastAssignmentUpdate(
                  frame.selectedRaid,
                  frame.selectedEncounter,
                  targetRoleIndex,
                  targetSlotIndex,
                  frame.draggedPlayerName
                )
              end
              
              -- Refresh display
              if frame.RefreshRoleContainers then
                frame.RefreshRoleContainers()
              end
            end
          end
          
          frame.draggedPlayerName = nil
        end)
        
        yOffset = yOffset + (OGRH.LIST_ITEM_HEIGHT + OGRH.LIST_ITEM_SPACING)
      end
      
      -- Update scroll child height
      scrollChild:SetHeight(math.max(yOffset, 1))
      
      -- Update scrollbar visibility and range
      local scrollBar = frame.guildScrollBar
      local scrollFrame = frame.guildScrollFrame
      if scrollBar and scrollFrame then
        local contentHeight = scrollChild:GetHeight()
        local scrollFrameHeight = scrollFrame:GetHeight()
        
        if contentHeight > scrollFrameHeight then
          scrollBar:Show()
          scrollBar:SetMinMaxValues(0, contentHeight - scrollFrameHeight)
          scrollBar:SetValue(0)
        else
          scrollBar:Hide()
        end
        scrollFrame:SetVerticalScroll(0)
      end
    end
    
    -- Function to refresh role containers based on selected encounter
    local function RefreshRoleContainers()
      -- Save current scroll position
      local savedScrollPosition = 0
      if frame.rolesScrollBar and frame.rolesScrollBar:IsShown() then
        savedScrollPosition = frame.rolesScrollBar:GetValue()
      end
      
      -- Clear existing role containers
      for _, container in pairs(frame.roleContainers) do
        container:Hide()
        container:SetParent(nil)
      end
      frame.roleContainers = {}
      
      -- Show/hide placeholder and bottom panel controls
      if not frame.selectedRaid or not frame.selectedEncounter then
        placeholderText:Show()
        
        -- Hide bottom panel controls when no encounter is selected
        frame.autoAssignBtn:Hide()
        frame.announceBtn:Hide()
        frame.markPlayersBtn:Hide()
        frame.editToggleBtn:Hide()
        announcementLabel:Hide()
        announcementScrollFrame:Hide()
        
        -- Clear announcement lines when no encounter is selected
        if frame.announcementLines then
          for i = 1, table.getn(frame.announcementLines) do
            frame.announcementLines[i]:SetText("")
            frame.announcementLines[i]:ClearFocus()
          end
        end
        
        return
      end
      
      placeholderText:Hide()
      
      -- Show bottom panel controls when encounter is selected
      frame.autoAssignBtn:Show()
      frame.announceBtn:Show()
      frame.markPlayersBtn:Show()
      frame.editToggleBtn:Show()
      announcementLabel:Show()
      announcementScrollFrame:Show()
      
      -- Load saved announcement text for this encounter
      if not OGRH_SV.encounterAnnouncements then
        OGRH_SV.encounterAnnouncements = {}
      end
      if not OGRH_SV.encounterAnnouncements[frame.selectedRaid] then
        OGRH_SV.encounterAnnouncements[frame.selectedRaid] = {}
      end
      if not OGRH_SV.encounterAnnouncements[frame.selectedRaid][frame.selectedEncounter] then
        OGRH_SV.encounterAnnouncements[frame.selectedRaid][frame.selectedEncounter] = {}
      end
      
      local savedAnnouncements = OGRH_SV.encounterAnnouncements[frame.selectedRaid][frame.selectedEncounter]
      if frame.announcementLines then
        for i = 1, table.getn(frame.announcementLines) do
          local savedText = savedAnnouncements[i] or ""
          frame.announcementLines[i]:SetText(savedText)
        end
      end
      
      -- Get role configuration for this encounter
      local roles = OGRH_SV.encounterMgmt.roles
      if not roles or not roles[frame.selectedRaid] or not roles[frame.selectedRaid][frame.selectedEncounter] then
        -- No roles configured yet
        local noRolesText = rightPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        noRolesText:SetPoint("CENTER", rightPanel, "CENTER", 0, 0)
        noRolesText:SetText("|cffff8888No roles configured for this encounter|r\n|cff888888Configure roles in Encounter Setup|r")
        frame.roleContainers.noRolesText = noRolesText
        return
      end
      
      local encounterRoles = roles[frame.selectedRaid][frame.selectedEncounter]
      local column1 = encounterRoles.column1 or {}
      local column2 = encounterRoles.column2 or {}
      
      -- Helper function to create role container
      local function CreateRoleContainer(parent, role, roleIndex, xPos, yPos, width)
        -- Consume Check role UI
        if role.isConsumeCheck then
          local maxConsumes = role.slots or 1
          local container = CreateFrame("Frame", nil, parent)
          container:SetWidth(width)
          container:SetHeight(40 + (maxConsumes * 22))
          container:SetPoint("TOPLEFT", parent, "TOPLEFT", xPos, yPos)
          container:SetBackdrop({
            bgFile = "Interface/Tooltips/UI-Tooltip-Background",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 8,
            insets = {left = 2, right = 2, top = 2, bottom = 2}
          })
          container:SetBackdropColor(0.15, 0.15, 0.15, 0.9)
          
          -- Role index label (top left)
          local indexLabel = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
          indexLabel:SetPoint("TOPLEFT", container, "TOPLEFT", 5, -5)
          indexLabel:SetText("R" .. roleIndex)
          indexLabel:SetTextColor(0.7, 0.7, 0.7)
          
          -- Role name (centered)
          local titleText = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
          titleText:SetPoint("TOP", container, "TOP", 5, -10)
          titleText:SetText(role.name or "Consumes")
          
          -- Tag marker for title (T) - positioned to the left of title
          local titleTag = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
          titleTag:SetPoint("RIGHT", titleText, "LEFT", -3, 0)
          titleTag:SetText("|cff888888T|r")
          titleTag:SetTextColor(0.5, 0.5, 0.5)
          
          -- Capture roleIndex for closures
          local capturedRoleIndex = roleIndex
          
          -- Consume slots
          container.slots = {}
          for i = 1, maxConsumes do
            local slot = CreateFrame("Frame", nil, container)
            slot:SetWidth(width - 20)
            slot:SetHeight(20)
            slot:SetPoint("TOP", container, "TOP", 0, -30 - ((i-1) * 22))
            
            -- Background
            local bg = slot:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetTexture("Interface\\Buttons\\WHITE8X8")
            bg:SetVertexColor(0.1, 0.1, 0.1, 0.8)
            slot.bg = bg
            
            -- Tag marker for consume (Cx)
            local consumeTag = slot:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            consumeTag:SetPoint("LEFT", slot, "LEFT", 2, 0)
            consumeTag:SetText("|cff888888C" .. i .. "|r")
            consumeTag:SetTextColor(0.5, 0.5, 0.5)
            slot.consumeTag = consumeTag
            
            -- Consume selection button
            local consumeBtn = CreateFrame("Button", nil, slot)
            consumeBtn:SetWidth(width - 30)
            consumeBtn:SetHeight(20)
            consumeBtn:SetPoint("LEFT", consumeTag, "RIGHT", 2, 0)
            
            local consumeText = consumeBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            consumeText:SetPoint("LEFT", consumeBtn, "LEFT", 2, 0)
            consumeText:SetWidth(width - 56)
            consumeText:SetJustifyH("LEFT")
            consumeBtn.consumeText = consumeText
            
            -- Combat icon (skull from raid markers)
            local combatIcon = consumeBtn:CreateTexture(nil, "OVERLAY")
            combatIcon:SetWidth(16)
            combatIcon:SetHeight(16)
            combatIcon:SetPoint("RIGHT", consumeBtn, "RIGHT", -2, 0)
            combatIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
            combatIcon:SetTexCoord(0.75, 1, 0.25, 0.5)  -- Skull icon coordinates
            consumeBtn.combatIcon = combatIcon
            
            -- Update text and icon based on role consume data
            if role.consumes and role.consumes[i] then
              local consumeData = role.consumes[i]
              local displayText = ""
              if consumeData.allowAlternate and consumeData.secondaryName and consumeData.secondaryName ~= "" then
                displayText = consumeData.primaryName .. " / " .. consumeData.secondaryName
              elseif consumeData.primaryName then
                displayText = consumeData.primaryName
              else
                displayText = "|cff888888Click to select consume|r"
              end
              
              -- Truncate text if too long
              consumeText:SetText(displayText)
              if consumeText:GetStringWidth() > (width - 56) then
                while consumeText:GetStringWidth() > (width - 62) and string.len(displayText) > 3 do
                  displayText = string.sub(displayText, 1, string.len(displayText) - 1)
                  consumeText:SetText(displayText .. "...")
                end
              end
              
              -- Show/hide combat icon
              if consumeData.checkDuringCombat then
                combatIcon:Show()
              else
                combatIcon:Hide()
              end
            else
              consumeText:SetText("|cff888888Click to select consume|r")
              combatIcon:Hide()
            end
            
            -- Click to select consume
            local capturedSlotIndex = i
            consumeBtn:SetScript("OnClick", function()
              OGRH.ShowConsumeSelectionDialog(frame.selectedRaid, frame.selectedEncounter, capturedRoleIndex, capturedSlotIndex)
            end)
            
            table.insert(container.slots, slot)
          end
          
          return container
        end
        
        local maxPlayers = role.slots or 1
        local container = CreateFrame("Frame", nil, parent)
        container:SetWidth(width)
        container:SetHeight(40 + (maxPlayers * 22))
        container:SetPoint("TOPLEFT", parent, "TOPLEFT", xPos, yPos)
        container:SetBackdrop({
          bgFile = "Interface/Tooltips/UI-Tooltip-Background",
          edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
          tile = true,
          tileSize = 16,
          edgeSize = 8,
          insets = {left = 2, right = 2, top = 2, bottom = 2}
        })
        container:SetBackdropColor(0.15, 0.15, 0.15, 0.9)
        
        -- Role index label (top left)
        local indexLabel = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        indexLabel:SetPoint("TOPLEFT", container, "TOPLEFT", 5, -5)
        indexLabel:SetText("R" .. roleIndex)
        indexLabel:SetTextColor(0.7, 0.7, 0.7)
        
        -- Role name (centered)
        local titleText = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        titleText:SetPoint("TOP", container, "TOP", 5, -10)
        titleText:SetText(role.name or "Unknown Role")
        
        -- Tag marker for title (T) - positioned to the left of title
        local titleTag = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        titleTag:SetPoint("RIGHT", titleText, "LEFT", -3, 0)
        titleTag:SetText("|cff888888T|r")
        titleTag:SetTextColor(0.5, 0.5, 0.5)
        
        -- Link Role button (top right) - only show if linkRole is enabled
        if role.linkRole then
          local linkRoleBtn = CreateFrame("Button", nil, container, "UIPanelButtonTemplate")
          linkRoleBtn:SetWidth(50)
          linkRoleBtn:SetHeight(18)
          linkRoleBtn:SetPoint("TOPRIGHT", container, "TOPRIGHT", -5, -5)
          linkRoleBtn:SetText("Link")
          OGRH.StyleButton(linkRoleBtn)
          
          local capturedRoleIndex = roleIndex
          local capturedRole = role
          linkRoleBtn:SetScript("OnClick", function()
            if not OGRH.ShowLinkRoleDialog then
              OGRH.Msg("Link Role dialog not loaded. Please /reload")
              return
            end
            
            -- Get all roles from both columns
            local allRoles = {}
            if OGRH_SV.encounterMgmt and OGRH_SV.encounterMgmt.roles and
               OGRH_SV.encounterMgmt.roles[frame.selectedRaid] and
               OGRH_SV.encounterMgmt.roles[frame.selectedRaid][frame.selectedEncounter] then
              local rolesData = OGRH_SV.encounterMgmt.roles[frame.selectedRaid][frame.selectedEncounter]
              if rolesData.column1 then
                for _, r in ipairs(rolesData.column1) do
                  table.insert(allRoles, r)
                end
              end
              if rolesData.column2 then
                for _, r in ipairs(rolesData.column2) do
                  table.insert(allRoles, r)
                end
              end
            end
            
            OGRH.ShowLinkRoleDialog(
              frame.selectedRaid,
              frame.selectedEncounter,
              capturedRoleIndex,
              capturedRole,
              allRoles,
              function()
                -- Refresh callback
                if frame.RefreshRoleContainers then
                  frame.RefreshRoleContainers()
                end
              end
            )
          end)
        end
        
        -- Capture roleIndex for closures
        local capturedRoleIndex = roleIndex
        
        -- Player slots
        container.slots = {}
        for i = 1, maxPlayers do
          local slot = CreateFrame("Frame", nil, container)
          slot:SetWidth(width - 20)
          slot:SetHeight(20)
          slot:SetPoint("TOP", container, "TOP", 0, -30 - ((i-1) * 22))
          
          -- Store slot reference for drag/drop lookup
          slot.bg = slot.bg -- Will be set below
          frame["slot_"..capturedRoleIndex.."_"..i] = slot
          
          -- Background
          local bg = slot:CreateTexture(nil, "BACKGROUND")
          bg:SetAllPoints()
          bg:SetTexture("Interface\\Buttons\\WHITE8X8")
          bg:SetVertexColor(0.1, 0.1, 0.1, 0.8)
          slot.bg = bg
          
          -- Raid icon dropdown button - only if showRaidIcons is true
          if role.showRaidIcons then
            -- Tag marker for raid mark (Mx) - positioned before the icon button
            local markTag = slot:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            markTag:SetPoint("LEFT", slot, "LEFT", 2, 0)
            markTag:SetText("|cff888888M" .. i .. "|r")
            markTag:SetTextColor(0.5, 0.5, 0.5)
            slot.markTag = markTag
            
            local iconBtn = CreateFrame("Button", nil, slot)
            iconBtn:SetWidth(16)
            iconBtn:SetHeight(16)
            iconBtn:SetPoint("LEFT", markTag, "RIGHT", 2, 0)
            
            -- Background for icon button
            local iconBg = iconBtn:CreateTexture(nil, "BACKGROUND")
            iconBg:SetAllPoints()
            iconBg:SetTexture("Interface\\Buttons\\WHITE8X8")
            iconBg:SetVertexColor(0.3, 0.3, 0.3, 0.8)
            
            -- Icon texture (will show selected raid icon)
            local iconTex = iconBtn:CreateTexture(nil, "OVERLAY")
            iconTex:SetWidth(12)
            iconTex:SetHeight(12)
            iconTex:SetPoint("CENTER", iconBtn, "CENTER")
            iconTex:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
            iconTex:Hide()  -- Hidden until icon is selected
            iconBtn.iconTex = iconTex
            
            -- Current icon index (0 = none)
            iconBtn.iconIndex = 0
            
            -- Store reference for loading
            slot.iconBtn = iconBtn
            
            -- Start with mouse disabled (read-only mode)
            iconBtn:EnableMouse(false)
            
            -- Click to cycle through raid icons
            local capturedSlotIndex = i
            iconBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            iconBtn:SetScript("OnClick", function()
              local button = arg1 or "LeftButton"
              local currentIndex = iconBtn.iconIndex
              
              if button == "LeftButton" then
                -- Cycle forward: none -> 8 -> 7 -> ... -> 1 -> none
                if currentIndex == 0 then
                  currentIndex = 8
                elseif currentIndex == 1 then
                  currentIndex = 0
                else
                  currentIndex = currentIndex - 1
                end
              else
                -- Right click: Cycle backward: none -> 1 -> 2 -> ... -> 8 -> none
                if currentIndex == 0 then
                  currentIndex = 1
                elseif currentIndex == 8 then
                  currentIndex = 0
                else
                  currentIndex = currentIndex + 1
                end
              end
              
              iconBtn.iconIndex = currentIndex
              
              -- Save the raid mark assignment
              if frame.selectedRaid and frame.selectedEncounter then
                if not OGRH_SV.encounterRaidMarks then
                  OGRH_SV.encounterRaidMarks = {}
                end
                if not OGRH_SV.encounterRaidMarks[frame.selectedRaid] then
                  OGRH_SV.encounterRaidMarks[frame.selectedRaid] = {}
                end
                if not OGRH_SV.encounterRaidMarks[frame.selectedRaid][frame.selectedEncounter] then
                  OGRH_SV.encounterRaidMarks[frame.selectedRaid][frame.selectedEncounter] = {}
                end
                if not OGRH_SV.encounterRaidMarks[frame.selectedRaid][frame.selectedEncounter][capturedRoleIndex] then
                  OGRH_SV.encounterRaidMarks[frame.selectedRaid][frame.selectedEncounter][capturedRoleIndex] = {}
                end
                
                OGRH_SV.encounterRaidMarks[frame.selectedRaid][frame.selectedEncounter][capturedRoleIndex][capturedSlotIndex] = currentIndex
              end
              
              if currentIndex == 0 then
                iconTex:Hide()
              else
                -- Set texture coordinates for the selected icon
                -- Texture coordinates from RolesUI
                local coords = {
                  [1] = {0, 0.25, 0, 0.25},       -- Star
                  [2] = {0.25, 0.5, 0, 0.25},     -- Circle
                  [3] = {0.5, 0.75, 0, 0.25},     -- Diamond
                  [4] = {0.75, 1, 0, 0.25},       -- Triangle
                  [5] = {0, 0.25, 0.25, 0.5},     -- Moon
                  [6] = {0.25, 0.5, 0.25, 0.5},   -- Square
                  [7] = {0.5, 0.75, 0.25, 0.5},   -- Cross
                  [8] = {0.75, 1, 0.25, 0.5},     -- Skull
                }
                local c = coords[currentIndex]
                iconTex:SetTexCoord(c[1], c[2], c[3], c[4])
                iconTex:Show()
              end
            end)
          end
          
          -- Edit button for class priority (create first so we can position other elements relative to it)
          local editBtn = CreateFrame("Button", nil, slot)
          editBtn:SetWidth(16)
          editBtn:SetHeight(16)
          editBtn:SetPoint("RIGHT", slot, "RIGHT", -3, 0)
          editBtn:SetNormalTexture("Interface\\Buttons\\UI-GuildButton-PublicNote-Up")
          editBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
          editBtn:SetPushedTexture("Interface\\Buttons\\UI-GuildButton-PublicNote-Down")
          editBtn.roleIndex = capturedRoleIndex
          editBtn.slotIndex = i
          editBtn:EnableMouse(false)
          slot.editBtn = editBtn
          
          -- Player name text
          local nameText = slot:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
          
          -- Tag marker for player (Px) - positioned to the left of player name
          local playerTag = slot:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
          playerTag:SetText("|cff888888P" .. i .. "|r")
          playerTag:SetTextColor(0.5, 0.5, 0.5)
          slot.playerTag = playerTag
          
          if role.showRaidIcons then
            playerTag:SetPoint("LEFT", slot.iconBtn, "RIGHT", 5, 0)
            nameText:SetPoint("LEFT", playerTag, "RIGHT", 3, 0)
          else
            playerTag:SetPoint("LEFT", slot, "LEFT", 5, 0)
            nameText:SetPoint("LEFT", playerTag, "RIGHT", 3, 0)
          end
          
          -- Assignment button - only if showAssignment is true
          if role.showAssignment then
            
            local assignBtn = CreateFrame("Button", nil, slot)
            assignBtn:SetWidth(20)
            assignBtn:SetHeight(16)
            assignBtn:SetPoint("RIGHT", editBtn, "LEFT", -4, 0)
            
            -- Background for assignment button
            local assignBg = assignBtn:CreateTexture(nil, "BACKGROUND")
            assignBg:SetAllPoints()
            assignBg:SetTexture("Interface\\Buttons\\WHITE8X8")
            assignBg:SetVertexColor(0.3, 0.3, 0.3, 0.8)
            
            -- Assignment text (shows 1-9, 0, or empty)
            local assignText = assignBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            assignText:SetPoint("CENTER", assignBtn, "CENTER")
            assignText:SetText("")
            assignBtn.assignText = assignText
            
            -- Current assignment index (0 = none/empty)
            assignBtn.assignIndex = 0
            
            -- Store reference for loading
            slot.assignBtn = assignBtn
            
            -- Start with mouse disabled (read-only mode)
            assignBtn:EnableMouse(false)
            
            -- Tag marker for assignment (Ax) - positioned to the left of the button
            local assignTag = slot:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            assignTag:SetPoint("RIGHT", assignBtn, "LEFT", -2, 0)
            assignTag:SetText("|cff888888A" .. i .. "|r")
            assignTag:SetTextColor(0.5, 0.5, 0.5)
            slot.assignTag = assignTag
            
            -- Position nameText to end before assignment tag
            nameText:SetPoint("RIGHT", assignTag, "LEFT", -5, 0)
            
            -- Click to cycle through assignments
            local capturedSlotIndex = i
            assignBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            assignBtn:SetScript("OnClick", function()
              local button = arg1 or "LeftButton"
              local currentIndex = assignBtn.assignIndex
              
              if button == "LeftButton" then
                -- Cycle forward: 0 -> 1 -> 2 -> ... -> 9 -> 0
                currentIndex = currentIndex + 1
                if currentIndex > 9 then
                  currentIndex = 0
                end
              else
                -- Right click: Cycle backward: 0 -> 9 -> 8 -> ... -> 1 -> 0
                currentIndex = currentIndex - 1
                if currentIndex < 0 then
                  currentIndex = 9
                end
              end
              
              assignBtn.assignIndex = currentIndex
              
              -- Save the assignment
              if frame.selectedRaid and frame.selectedEncounter then
                if not OGRH_SV.encounterAssignmentNumbers then
                  OGRH_SV.encounterAssignmentNumbers = {}
                end
                if not OGRH_SV.encounterAssignmentNumbers[frame.selectedRaid] then
                  OGRH_SV.encounterAssignmentNumbers[frame.selectedRaid] = {}
                end
                if not OGRH_SV.encounterAssignmentNumbers[frame.selectedRaid][frame.selectedEncounter] then
                  OGRH_SV.encounterAssignmentNumbers[frame.selectedRaid][frame.selectedEncounter] = {}
                end
                if not OGRH_SV.encounterAssignmentNumbers[frame.selectedRaid][frame.selectedEncounter][capturedRoleIndex] then
                  OGRH_SV.encounterAssignmentNumbers[frame.selectedRaid][frame.selectedEncounter][capturedRoleIndex] = {}
                end
                
                OGRH_SV.encounterAssignmentNumbers[frame.selectedRaid][frame.selectedEncounter][capturedRoleIndex][capturedSlotIndex] = currentIndex
              end
              
              -- Update display
              if currentIndex == 0 then
                assignText:SetText("")
              else
                assignText:SetText(tostring(currentIndex))
              end
            end)
          else
            -- No assignment button, nameText ends before edit button
            nameText:SetPoint("RIGHT", editBtn, "LEFT", -5, 0)
          end
          
          -- Click handler for edit button
          local capturedSlotIndex = i
          local capturedRoleData = role
          editBtn:SetScript("OnClick", function()
            if not OGRH.ShowClassPriorityDialog then
              OGRH.Msg("Class Priority dialog not loaded. Please /reload")
              return
            end
            OGRH.ShowClassPriorityDialog(
              frame.selectedRaid,
              frame.selectedEncounter,
              capturedRoleIndex,
              capturedSlotIndex,
              capturedRoleData,
              function()
                -- Refresh callback
                if frame.RefreshRoleContainers then
                  frame.RefreshRoleContainers()
                end
              end
            )
          end)
          
          nameText:SetJustifyH("LEFT")
          slot.nameText = nameText
          
          -- Store slot info for assignment lookup
          slot.roleIndex = capturedRoleIndex
          slot.slotIndex = i
          
          -- Create a BUTTON for drag/drop (overlays the name area, RolesUI pattern)
          local dragBtn = CreateFrame("Button", nil, slot)
          dragBtn:SetPoint("LEFT", nameText, "LEFT", -5, 0)
          -- Stop before the assignment tag/button area (or edit button if no assignment)
          if role.showAssignment then
            dragBtn:SetPoint("RIGHT", slot.assignTag, "LEFT", -2, 0)
          else
            dragBtn:SetPoint("RIGHT", editBtn, "LEFT", -2, 0)
          end
          dragBtn:SetHeight(20)
          dragBtn:EnableMouse(true)
          dragBtn:SetMovable(true)
          dragBtn:RegisterForDrag("LeftButton")
          dragBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
          
          -- Store references on button
          dragBtn.roleIndex = capturedRoleIndex
          dragBtn.slotIndex = i
          dragBtn.parentSlot = slot
          -- Store references on button
          dragBtn.roleIndex = capturedRoleIndex
          dragBtn.slotIndex = i
          dragBtn.parentSlot = slot
          
          -- Create a drag frame that follows cursor
          local dragFrame = CreateFrame("Frame", nil, UIParent)
          dragFrame:SetWidth(100)
          dragFrame:SetHeight(20)
          dragFrame:SetFrameStrata("TOOLTIP")
          dragFrame:Hide()
          
          local dragText = dragFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
          dragText:SetPoint("CENTER", dragFrame, "CENTER", 0, 0)
          
          dragBtn.dragFrame = dragFrame
          dragBtn.dragText = dragText
          
          -- Drag start
          dragBtn:SetScript("OnDragStart", function()
            -- Mark that a drag actually started
            this.isDragging = true
            
            -- Check permission
            if not OGRH.CanEdit or not OGRH.CanEdit() then
              return
            end
            
            local slotRoleIndex = this.roleIndex
            local slotSlotIndex = this.slotIndex
            
            -- Get current player assignment
            if not OGRH_SV.encounterAssignments or
               not OGRH_SV.encounterAssignments[frame.selectedRaid] or
               not OGRH_SV.encounterAssignments[frame.selectedRaid][frame.selectedEncounter] or
               not OGRH_SV.encounterAssignments[frame.selectedRaid][frame.selectedEncounter][slotRoleIndex] or
               not OGRH_SV.encounterAssignments[frame.selectedRaid][frame.selectedEncounter][slotRoleIndex][slotSlotIndex] then
              return -- No player to drag
            end
            
            local playerName = OGRH_SV.encounterAssignments[frame.selectedRaid][frame.selectedEncounter][slotRoleIndex][slotSlotIndex]
            
            -- Store drag info on frame
            frame.draggedPlayer = playerName
            frame.draggedFromRole = slotRoleIndex
            frame.draggedFromSlot = slotSlotIndex
            
            -- Show drag frame with player name
            this.dragText:SetText(playerName)
            this.dragFrame:Show()
            this.dragFrame:SetScript("OnUpdate", function()
              local x, y = GetCursorPosition()
              local scale = UIParent:GetEffectiveScale()
              this:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x/scale, y/scale)
            end)
            
            -- Visual feedback on parent slot
            this.parentSlot.bg:SetVertexColor(0.3, 0.3, 0.5, 0.8)
          end)
          
          -- Drag stop - check cursor position to find target (RolesUI pattern)
          dragBtn:SetScript("OnDragStop", function()
            this.dragFrame:Hide()
            this.dragFrame:SetScript("OnUpdate", nil)
            
            -- Check if dragging from players list or from another slot
            local isDraggingFromPlayerList = (frame.draggedPlayerName ~= nil)
            
            if not frame.draggedPlayer and not isDraggingFromPlayerList then return end
            
            -- Get cursor position
            local x, y = GetCursorPosition()
            local scale = UIParent:GetEffectiveScale()
            x = x/scale
            y = y/scale
            
            -- Find which slot we're over by checking all stored slot frames
            local foundTarget = false
            local targetRoleIndex = nil
            local targetSlotIndex = nil
            
            -- Check all role containers
            if frame.roleContainers then
              for _, container in ipairs(frame.roleContainers) do
                if container.slots then
                  for slotIdx, testSlot in ipairs(container.slots) do
                    if testSlot then
                      local left = testSlot:GetLeft()
                      local right = testSlot:GetRight()
                      local bottom = testSlot:GetBottom()
                      local top = testSlot:GetTop()
                      
                      if left and right and bottom and top and
                         x >= left and x <= right and y >= bottom and y <= top then
                        -- Found target slot - get its roleIndex from stored property
                        targetRoleIndex = testSlot.roleIndex
                        targetSlotIndex = testSlot.slotIndex
                        foundTarget = true
                        break
                      end
                    end
                  end
                end
                if foundTarget then break end
              end
            end
            
            -- Perform the swap/move if we found a target
            if foundTarget and targetRoleIndex and targetSlotIndex then
              -- Initialize assignments table
              if not OGRH_SV.encounterAssignments then
                OGRH_SV.encounterAssignments = {}
              end
              if not OGRH_SV.encounterAssignments[frame.selectedRaid] then
                OGRH_SV.encounterAssignments[frame.selectedRaid] = {}
              end
              if not OGRH_SV.encounterAssignments[frame.selectedRaid][frame.selectedEncounter] then
                OGRH_SV.encounterAssignments[frame.selectedRaid][frame.selectedEncounter] = {}
              end
              if not OGRH_SV.encounterAssignments[frame.selectedRaid][frame.selectedEncounter][targetRoleIndex] then
                OGRH_SV.encounterAssignments[frame.selectedRaid][frame.selectedEncounter][targetRoleIndex] = {}
              end
              
              if isDraggingFromPlayerList then
                -- Dragging from players list - just assign
                OGRH_SV.encounterAssignments[frame.selectedRaid][frame.selectedEncounter][targetRoleIndex][targetSlotIndex] = frame.draggedPlayerName
              else
                -- Dragging from another slot - swap or move
                if not OGRH_SV.encounterAssignments[frame.selectedRaid][frame.selectedEncounter][frame.draggedFromRole] then
                  OGRH_SV.encounterAssignments[frame.selectedRaid][frame.selectedEncounter][frame.draggedFromRole] = {}
                end
                
                -- Get current player at target position (if any)
                local targetPlayer = OGRH_SV.encounterAssignments[frame.selectedRaid][frame.selectedEncounter][targetRoleIndex][targetSlotIndex]
                
                -- Perform swap or move
                OGRH_SV.encounterAssignments[frame.selectedRaid][frame.selectedEncounter][targetRoleIndex][targetSlotIndex] = frame.draggedPlayer
                
                if targetPlayer then
                  -- Swap: put target player in source position
                  OGRH_SV.encounterAssignments[frame.selectedRaid][frame.selectedEncounter][frame.draggedFromRole][frame.draggedFromSlot] = targetPlayer
                  
                  -- Broadcast swap: update both positions
                  if OGRH.BroadcastAssignmentUpdate then
                    OGRH.BroadcastAssignmentUpdate(
                      frame.selectedRaid,
                      frame.selectedEncounter,
                      targetRoleIndex,
                      targetSlotIndex,
                      frame.draggedPlayer
                    )
                    OGRH.BroadcastAssignmentUpdate(
                      frame.selectedRaid,
                      frame.selectedEncounter,
                      frame.draggedFromRole,
                      frame.draggedFromSlot,
                      targetPlayer
                    )
                  end
                else
                  -- Just move: clear source position
                  OGRH_SV.encounterAssignments[frame.selectedRaid][frame.selectedEncounter][frame.draggedFromRole][frame.draggedFromSlot] = nil
                  
                  -- Broadcast move: update target and clear source
                  if OGRH.BroadcastAssignmentUpdate then
                    OGRH.BroadcastAssignmentUpdate(
                      frame.selectedRaid,
                      frame.selectedEncounter,
                      targetRoleIndex,
                      targetSlotIndex,
                      frame.draggedPlayer
                    )
                    OGRH.BroadcastAssignmentUpdate(
                      frame.selectedRaid,
                      frame.selectedEncounter,
                      frame.draggedFromRole,
                      frame.draggedFromSlot,
                      nil
                    )
                  end
                end
              end
            end
            
            -- Clear visual feedback
            this.parentSlot.bg:SetVertexColor(0.1, 0.1, 0.1, 0.8)
            
            -- Clear drag data
            frame.draggedPlayer = nil
            frame.draggedFromRole = nil
            frame.draggedFromSlot = nil
            frame.draggedPlayerName = nil
            
            -- Keep isDragging flag set so OnClick knows to ignore it
            -- It will be cleared in OnClick handler
            
            -- Refresh display
            if frame.RefreshRoleContainers then
              frame.RefreshRoleContainers()
            end
          end)
          
          -- Click handler on button
          dragBtn:SetScript("OnClick", function()
            -- If a drag occurred, ignore the click
            if this.isDragging then
              this.isDragging = false
              return
            end
            
            local button = arg1 or "LeftButton"
            local slotRoleIndex = this.roleIndex
            local slotSlotIndex = this.slotIndex
            
            if button == "RightButton" then
              -- Check permission
              if not OGRH.CanEdit or not OGRH.CanEdit() then
                OGRH.Msg("Only the raid lead can modify assignments.")
                return
              end
              
              -- Right click: Unassign player
              if OGRH_SV.encounterAssignments and
                 OGRH_SV.encounterAssignments[frame.selectedRaid] and
                 OGRH_SV.encounterAssignments[frame.selectedRaid][frame.selectedEncounter] and
                 OGRH_SV.encounterAssignments[frame.selectedRaid][frame.selectedEncounter][slotRoleIndex] then
                OGRH_SV.encounterAssignments[frame.selectedRaid][frame.selectedEncounter][slotRoleIndex][slotSlotIndex] = nil
                
                -- Broadcast removal
                if OGRH.BroadcastAssignmentUpdate then
                  OGRH.BroadcastAssignmentUpdate(
                    frame.selectedRaid,
                    frame.selectedEncounter,
                    slotRoleIndex,
                    slotSlotIndex,
                    nil
                  )
                end
                
                -- Refresh display
                if frame.RefreshRoleContainers then
                  frame.RefreshRoleContainers()
                end
              end
            end
            -- Left click: Do nothing (edit button handles class priority)
          end)
          
          table.insert(container.slots, slot)
        end
        
        -- Update slot assignments after creating all slots
        local function UpdateSlotAssignments()
          -- Get assignments for this encounter
          local assignedPlayers = {}
          if OGRH_SV.encounterAssignments and 
             OGRH_SV.encounterAssignments[frame.selectedRaid] and
             OGRH_SV.encounterAssignments[frame.selectedRaid][frame.selectedEncounter] and
             OGRH_SV.encounterAssignments[frame.selectedRaid][frame.selectedEncounter][capturedRoleIndex] then
            assignedPlayers = OGRH_SV.encounterAssignments[frame.selectedRaid][frame.selectedEncounter][capturedRoleIndex]
          end
          
          -- Update slot displays
          for slotIdx, slot in ipairs(container.slots) do
            local playerName = assignedPlayers[slotIdx]
            
            -- Load saved raid mark for this slot
            if slot.iconBtn then
              local savedMark = 0
              if OGRH_SV.encounterRaidMarks and
                 OGRH_SV.encounterRaidMarks[frame.selectedRaid] and
                 OGRH_SV.encounterRaidMarks[frame.selectedRaid][frame.selectedEncounter] and
                 OGRH_SV.encounterRaidMarks[frame.selectedRaid][frame.selectedEncounter][capturedRoleIndex] then
                savedMark = OGRH_SV.encounterRaidMarks[frame.selectedRaid][frame.selectedEncounter][capturedRoleIndex][slotIdx] or 0
              end
              
              slot.iconBtn.iconIndex = savedMark
              
              if savedMark == 0 then
                slot.iconBtn.iconTex:Hide()
              else
                local coords = {
                  [1] = {0, 0.25, 0, 0.25},
                  [2] = {0.25, 0.5, 0, 0.25},
                  [3] = {0.5, 0.75, 0, 0.25},
                  [4] = {0.75, 1, 0, 0.25},
                  [5] = {0, 0.25, 0.25, 0.5},
                  [6] = {0.25, 0.5, 0.25, 0.5},
                  [7] = {0.5, 0.75, 0.25, 0.5},
                  [8] = {0.75, 1, 0.25, 0.5},
                }
                local c = coords[savedMark]
                slot.iconBtn.iconTex:SetTexCoord(c[1], c[2], c[3], c[4])
                slot.iconBtn.iconTex:Show()
              end
            end
            
            -- Load saved assignment number for this slot
            if slot.assignBtn then
              local savedAssign = 0
              if OGRH_SV.encounterAssignmentNumbers and
                 OGRH_SV.encounterAssignmentNumbers[frame.selectedRaid] and
                 OGRH_SV.encounterAssignmentNumbers[frame.selectedRaid][frame.selectedEncounter] and
                 OGRH_SV.encounterAssignmentNumbers[frame.selectedRaid][frame.selectedEncounter][capturedRoleIndex] then
                savedAssign = OGRH_SV.encounterAssignmentNumbers[frame.selectedRaid][frame.selectedEncounter][capturedRoleIndex][slotIdx] or 0
              end
              
              slot.assignBtn.assignIndex = savedAssign
              
              if savedAssign == 0 then
                slot.assignBtn.assignText:SetText("")
              else
                slot.assignBtn.assignText:SetText(tostring(savedAssign))
              end
            end
            
            if playerName then
              -- Get player's class from cache or lookup
              local class = OGRH.GetPlayerClass(playerName)
              
              -- Apply class color
              if class and RAID_CLASS_COLORS[class] then
                local color = RAID_CLASS_COLORS[class]
                slot.nameText:SetText(playerName)
                slot.nameText:SetTextColor(color.r, color.g, color.b)
              else
                slot.nameText:SetText(playerName)
                slot.nameText:SetTextColor(1, 1, 1)
              end
            else
              -- Build placeholder text from class priority and default roles
              local placeholderText = "[Empty]"
              
              -- Get highest priority class if configured
              local priorityClass = nil
              if role.classPriority and role.classPriority[slotIdx] and table.getn(role.classPriority[slotIdx]) > 0 then
                priorityClass = role.classPriority[slotIdx][1]
              end
              
              -- Get default role text
              local defaultRoleText = nil
              if role.defaultRoles then
                local roleNames = {}
                if role.defaultRoles.tanks then table.insert(roleNames, "Tanks") end
                if role.defaultRoles.healers then table.insert(roleNames, "Healers") end
                if role.defaultRoles.melee then table.insert(roleNames, "Melee") end
                if role.defaultRoles.ranged then table.insert(roleNames, "Ranged") end
                
                if table.getn(roleNames) > 0 then
                  defaultRoleText = table.concat(roleNames, "/")
                end
              end
              
              -- Build final text
              if priorityClass and defaultRoleText then
                placeholderText = "[" .. priorityClass .. "/" .. defaultRoleText .. "]"
              elseif priorityClass then
                placeholderText = "[" .. priorityClass .. "]"
              elseif defaultRoleText then
                placeholderText = "[" .. defaultRoleText .. "]"
              end
              
              slot.nameText:SetText(placeholderText)
              slot.nameText:SetTextColor(0.53, 0.53, 0.53)
            end
          end
        end
        
        UpdateSlotAssignments()
        container.UpdateSlotAssignments = UpdateSlotAssignments
        
        return container
      end
      
      -- Create role containers from both columns
      local scrollChild = frame.rolesScrollChild
      local yOffsetLeft = -5
      local yOffsetRight = -5
      local columnWidth = 272
      
      -- Create each column independently to avoid unwanted whitespace
      local roleIndex = 1
      
      -- Left column (skip Custom Module roles - they don't render in planning UI)
      for i = 1, table.getn(column1) do
        if not column1[i].isCustomModule then
          local container = CreateRoleContainer(scrollChild, column1[i], roleIndex, 5, yOffsetLeft, columnWidth)
          table.insert(frame.roleContainers, container)
          
          -- Calculate offset for next role in left column
          local containerHeight = 40 + ((column1[i].slots or 1) * 22)
          yOffsetLeft = yOffsetLeft - containerHeight - 10
        end
        roleIndex = roleIndex + 1
      end
      
      -- Right column (skip Custom Module roles - they don't render in planning UI)
      for i = 1, table.getn(column2) do
        if not column2[i].isCustomModule then
          local container = CreateRoleContainer(scrollChild, column2[i], roleIndex, 287, yOffsetRight, columnWidth)
          table.insert(frame.roleContainers, container)
          
          -- Calculate offset for next role in right column
          local containerHeight = 40 + ((column2[i].slots or 1) * 22)
          yOffsetRight = yOffsetRight - containerHeight - 10
        end
        roleIndex = roleIndex + 1
      end
      
      -- Update scroll child height (based on the taller column)
      local contentHeight = math.max(math.abs(yOffsetLeft), math.abs(yOffsetRight)) + 5
      scrollChild:SetHeight(math.max(1, contentHeight))
      
      -- Update scrollbar visibility
      local scrollFrame = frame.rolesScrollFrame
      local scrollBar = frame.rolesScrollBar
      local scrollFrameHeight = scrollFrame:GetHeight()
      
      if contentHeight > scrollFrameHeight then
        scrollBar:Show()
        local maxScroll = contentHeight - scrollFrameHeight
        scrollBar:SetMinMaxValues(0, maxScroll)
        
        -- Restore scroll position, but clamp to new max
        local newScrollPos = math.min(savedScrollPosition, maxScroll)
        scrollBar:SetValue(newScrollPos)
        scrollFrame:SetVerticalScroll(newScrollPos)
      else
        scrollBar:Hide()
        scrollFrame:SetVerticalScroll(0)
      end
      
      -- Apply current edit mode to newly created containers
      if frame.SetEditMode then
        frame.SetEditMode(frame.editMode or false)
      end
    end
    
    frame.RefreshRoleContainers = RefreshRoleContainers
    
    -- Initialize lists
    RefreshRaidsList()
    
    -- Restore saved raid and encounter selection
    if OGRH_SV.ui.selectedRaid then
      frame.selectedRaid = OGRH_SV.ui.selectedRaid
      if OGRH_SV.ui.selectedEncounter then
        frame.selectedEncounter = OGRH_SV.ui.selectedEncounter
      end
    end
  end
  
  -- Close Roles window if it's open
  if OGRH.rolesFrame and OGRH.rolesFrame:IsVisible() then
    OGRH.rolesFrame:Hide()
  end
  
  -- Close SR+ Validation window if it's open
  if OGRH_SRValidationFrame and OGRH_SRValidationFrame:IsVisible() then
    OGRH_SRValidationFrame:Hide()
  end
  
  -- Close Share window if it's open
  if OGRH_ShareFrame and OGRH_ShareFrame:IsVisible() then
    OGRH_ShareFrame:Hide()
  end
  
  -- Show the frame
  OGRH_EncounterFrame:Show()
  
  -- Refresh the raids list (this will validate and clear selectedRaid/selectedEncounter if needed)
  OGRH_EncounterFrame.RefreshRaidsList()
  
  -- Refresh the encounters list (this will validate and clear selectedEncounter if needed)
  if OGRH_EncounterFrame.RefreshEncountersList then
    OGRH_EncounterFrame.RefreshEncountersList()
  end
  
  -- Refresh role containers to set initial visibility state of buttons
  if OGRH_EncounterFrame.RefreshRoleContainers then
    OGRH_EncounterFrame.RefreshRoleContainers()
  end
  
  -- If an encounter is still selected after validation, refresh again
  -- to pick up any changes made in the Setup window
  if OGRH_EncounterFrame.selectedRaid and OGRH_EncounterFrame.selectedEncounter then
    if OGRH_EncounterFrame.RefreshRoleContainers then
      OGRH_EncounterFrame.RefreshRoleContainers()
    end
    
    -- Ensure scroll position is correct after frame is shown (delayed to next frame)
    -- This handles the case where the frame is shown for the first time with a saved encounter
    local delayFrame = CreateFrame("Frame")
    delayFrame:SetScript("OnUpdate", function()
      if OGRH_EncounterFrame and OGRH_EncounterFrame.RefreshEncountersList then
        OGRH_EncounterFrame.RefreshEncountersList()
      end
      this:SetScript("OnUpdate", nil)
    end)
  end
end

-- Function to show Encounter Setup Window
function OGRH.ShowEncounterSetup()
  -- Check if encounter data exists, if not show Share window
  OGRH.EnsureSV()
  if not OGRH_SV.encounterMgmt or 
     not OGRH_SV.encounterMgmt.raids or 
     table.getn(OGRH_SV.encounterMgmt.raids) == 0 then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff8800OGRH:|r No encounter data found. Please import data from the Share window.")
    if OGRH.ShowShareWindow then
      OGRH.ShowShareWindow()
    end
    return
  end
  
  -- Create or show the setup window
  if not OGRH_EncounterSetupFrame then
    local frame = CreateFrame("Frame", "OGRH_EncounterSetupFrame", UIParent)
    frame:SetWidth(600)
    frame:SetHeight(500)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetFrameStrata("HIGH")
    frame:SetBackdrop({
      bgFile = "Interface/Tooltips/UI-Tooltip-Background",
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
      tile = true,
      tileSize = 16,
      edgeSize = 16,
      insets = {left = 4, right = 4, top = 4, bottom = 4}
    })
    frame:SetBackdropColor(0, 0, 0, 0.9)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function() frame:StartMoving() end)
    frame:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
    
    -- Register ESC key handler
    OGRH.MakeFrameCloseOnEscape(frame, "OGRH_EncounterSetupFrame")
    
    -- Title bar
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", frame, "TOP", 0, -10)
    title:SetText("Encounter Setup")
    
    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    closeBtn:SetWidth(60)
    closeBtn:SetHeight(24)
    closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -10)
    closeBtn:SetText("Close")
    OGRH.StyleButton(closeBtn)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)
    
    -- Content area
    local contentFrame = CreateFrame("Frame", nil, frame)
    contentFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -50)
    contentFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 10)
    
    -- Raids section
    local raidsLabel = contentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    raidsLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -55)
    raidsLabel:SetText("Raids:")
    
    -- Raids list using template
    local raidsListWidth = 180
    local raidsListHeight = 175
    local raidsListFrame, raidsScrollFrame, raidsScrollChild, raidsScrollBar, raidsContentWidth = OGRH.CreateStyledScrollList(contentFrame, raidsListWidth, raidsListHeight, true)
    raidsListFrame:SetPoint("TOPLEFT", raidsLabel, "BOTTOMLEFT", 0, -5)
    frame.raidsScrollChild = raidsScrollChild
    frame.raidsScrollFrame = raidsScrollFrame
    frame.raidsScrollBar = raidsScrollBar
    frame.raidsListFrame = raidsListFrame
    
    -- Storage for raid data (use SavedVariables)
    InitializeSavedVars()
    
    -- Track selected raid
    frame.selectedRaid = nil
    
    -- Function to refresh raids list
    local function RefreshRaidsList()
      -- Clear existing buttons
      if frame.raidButtons then
        for _, btn in ipairs(frame.raidButtons) do
          btn:Hide()
          btn:SetParent(nil)
        end
      end
      frame.raidButtons = {}
      
      local yOffset = -5
      local scrollChild = frame.raidsScrollChild
      local contentWidth = scrollChild:GetWidth()
      
      -- Add existing raids
      for i, raidName in ipairs(OGRH_SV.encounterMgmt.raids) do
        local raidBtn = OGRH.CreateStyledListItem(scrollChild, contentWidth, OGRH.LIST_ITEM_HEIGHT, "Button")
        raidBtn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, yOffset)
        
        -- Set selection state
        if frame.selectedRaid == raidName then
          OGRH.SetListItemSelected(raidBtn, true)
        end
        
        -- Raid name text
        local nameText = raidBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        nameText:SetPoint("LEFT", raidBtn, "LEFT", 5, 0)
        nameText:SetText(raidName)
        nameText:SetWidth(80)
        nameText:SetJustifyH("LEFT")
        
        -- Click to select raid, right-click to rename
        local capturedRaidName = raidName
        local capturedIndex = i
        raidBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        raidBtn:SetScript("OnClick", function()
          local button = arg1 or "LeftButton"
          if button == "RightButton" then
            -- Right-click: Rename
            StaticPopupDialogs["OGRH_RENAME_RAID"].text_arg1 = capturedRaidName
            StaticPopup_Show("OGRH_RENAME_RAID", capturedRaidName)
          else
            -- Left-click: Select
            frame.selectedRaid = capturedRaidName
            RefreshRaidsList()
            if frame.RefreshEncountersList then
              frame.RefreshEncountersList()
            end
          end
        end)
        
        -- Add up/down/delete buttons using template
        OGRH.AddListItemButtons(
          raidBtn,
          capturedIndex,
          table.getn(OGRH_SV.encounterMgmt.raids),
          function()
            -- Move up
            local temp = OGRH_SV.encounterMgmt.raids[capturedIndex - 1]
            OGRH_SV.encounterMgmt.raids[capturedIndex - 1] = OGRH_SV.encounterMgmt.raids[capturedIndex]
            OGRH_SV.encounterMgmt.raids[capturedIndex] = temp
            RefreshRaidsList()
          end,
          function()
            -- Move down
            local temp = OGRH_SV.encounterMgmt.raids[capturedIndex + 1]
            OGRH_SV.encounterMgmt.raids[capturedIndex + 1] = OGRH_SV.encounterMgmt.raids[capturedIndex]
            OGRH_SV.encounterMgmt.raids[capturedIndex] = temp
            RefreshRaidsList()
          end,
          function()
            -- Delete
            StaticPopupDialogs["OGRH_CONFIRM_DELETE_RAID"].text_arg1 = capturedRaidName
            StaticPopup_Show("OGRH_CONFIRM_DELETE_RAID", capturedRaidName)
          end
        )
        
        table.insert(frame.raidButtons, raidBtn)
        yOffset = yOffset - OGRH.LIST_ITEM_HEIGHT - OGRH.LIST_ITEM_SPACING
      end
      
      -- Add "Add Raid" placeholder row at the bottom
      local addRaidBtn = OGRH.CreateStyledListItem(scrollChild, contentWidth, OGRH.LIST_ITEM_HEIGHT, "Button")
      addRaidBtn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, yOffset)
      
      -- Text
      local addText = addRaidBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      addText:SetPoint("CENTER", addRaidBtn, "CENTER", 0, 0)
      addText:SetText("|cff00ff00Add Raid|r")
      
      addRaidBtn:SetScript("OnClick", function()
        StaticPopup_Show("OGRH_ADD_RAID")
      end)
      
      table.insert(frame.raidButtons, addRaidBtn)
      yOffset = yOffset - OGRH.LIST_ITEM_HEIGHT
      
      -- Update scroll child height
      local contentHeight = math.abs(yOffset) + 5
      scrollChild:SetHeight(math.max(contentHeight, 1))
      
      -- Update scroll (scrollbar always hidden)
      local scrollFrame = frame.raidsScrollFrame
      scrollFrame:SetVerticalScroll(0)
    end
    
    frame.RefreshRaidsList = RefreshRaidsList
    
    -- Encounters section (below Raids)
    local encountersLabel = contentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    encountersLabel:SetPoint("TOPLEFT", raidsListFrame, "BOTTOMLEFT", 0, -15)
    encountersLabel:SetText("Encounters:")
    
    -- Encounters list using template
    local encountersListWidth = 180
    local encountersListHeight = 175
    local encountersListFrame, encountersScrollFrame, encountersScrollChild, encountersScrollBar, encountersContentWidth = OGRH.CreateStyledScrollList(contentFrame, encountersListWidth, encountersListHeight, true)
    encountersListFrame:SetPoint("TOPLEFT", encountersLabel, "BOTTOMLEFT", 0, -5)
    frame.encountersScrollChild = encountersScrollChild
    frame.encountersScrollFrame = encountersScrollFrame
    frame.encountersScrollBar = encountersScrollBar
    frame.encountersListFrame = encountersListFrame
    
    -- Track selected encounter
    frame.selectedEncounter = nil
    
    -- Function to refresh encounters list
    local function RefreshEncountersList()
      -- Save current scroll position
      local scrollFrame = frame.encountersScrollFrame
      local savedScroll = scrollFrame and scrollFrame:GetVerticalScroll() or 0
      
      -- Clear existing buttons
      if frame.encounterButtons then
        for _, btn in ipairs(frame.encounterButtons) do
          if btn.placeholder then
            -- It's a placeholder text, just set parent to nil
            btn.placeholder:SetParent(nil)
            btn.placeholder = nil
          else
            -- It's a regular button
            btn:Hide()
            btn:SetParent(nil)
          end
        end
      end
      frame.encounterButtons = {}
      
      local scrollChild = frame.encountersScrollChild
      
      if not frame.selectedRaid then
        -- Show placeholder if no raid selected
        local placeholderText = encountersListFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        placeholderText:SetPoint("CENTER", encountersListFrame, "CENTER", 0, 0)
        placeholderText:SetText("|cff888888Select a raid\nto view encounters|r")
        placeholderText:SetJustifyH("CENTER")
        table.insert(frame.encounterButtons, {placeholder = placeholderText})
        
        -- Hide scrollbar when showing placeholder
        frame.encountersScrollBar:Hide()
        return
      end
      
      -- Ensure encounter storage exists for this raid
      if not OGRH_SV.encounterMgmt.encounters[frame.selectedRaid] then
        OGRH_SV.encounterMgmt.encounters[frame.selectedRaid] = {}
      end
      
      local yOffset = -5
      local selectedIndex = nil
      local contentWidth = scrollChild:GetWidth()
      
      -- Add existing encounters for selected raid
      local encounters = OGRH_SV.encounterMgmt.encounters[frame.selectedRaid]
      for i, encounterName in ipairs(encounters) do
        if encounterName == frame.selectedEncounter then
          selectedIndex = i
        end
        local encounterBtn = OGRH.CreateStyledListItem(scrollChild, contentWidth, OGRH.LIST_ITEM_HEIGHT, "Button")
        encounterBtn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, yOffset)
        
        -- Set selection state
        if frame.selectedEncounter == encounterName then
          OGRH.SetListItemSelected(encounterBtn, true)
        end
        
        -- Encounter name text
        local nameText = encounterBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        nameText:SetPoint("LEFT", encounterBtn, "LEFT", 5, 0)
        nameText:SetText(encounterName)
        nameText:SetWidth(80)
        nameText:SetJustifyH("LEFT")
        
        -- Click to select encounter, right-click to rename
        local capturedEncounterName = encounterName
        local capturedIndex = i
        local capturedRaid = frame.selectedRaid
        encounterBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        encounterBtn:SetScript("OnClick", function()
          local button = arg1 or "LeftButton"
          if button == "RightButton" then
            -- Right-click: Rename
            StaticPopupDialogs["OGRH_RENAME_ENCOUNTER"].text_arg1 = capturedEncounterName
            StaticPopupDialogs["OGRH_RENAME_ENCOUNTER"].text_arg2 = capturedRaid
            StaticPopup_Show("OGRH_RENAME_ENCOUNTER", capturedEncounterName)
          else
            -- Left-click: Select
            frame.selectedEncounter = capturedEncounterName
            RefreshEncountersList()
            if frame.RefreshRolesList then
              frame.RefreshRolesList()
            end
          end
        end)
        
        -- Add up/down/delete buttons using template
        OGRH.AddListItemButtons(
          encounterBtn,
          capturedIndex,
          table.getn(OGRH_SV.encounterMgmt.encounters[capturedRaid]),
          function()
            -- Move up
            local temp = OGRH_SV.encounterMgmt.encounters[capturedRaid][capturedIndex - 1]
            OGRH_SV.encounterMgmt.encounters[capturedRaid][capturedIndex - 1] = OGRH_SV.encounterMgmt.encounters[capturedRaid][capturedIndex]
            OGRH_SV.encounterMgmt.encounters[capturedRaid][capturedIndex] = temp
            RefreshEncountersList()
          end,
          function()
            -- Move down
            local temp = OGRH_SV.encounterMgmt.encounters[capturedRaid][capturedIndex + 1]
            OGRH_SV.encounterMgmt.encounters[capturedRaid][capturedIndex + 1] = OGRH_SV.encounterMgmt.encounters[capturedRaid][capturedIndex]
            OGRH_SV.encounterMgmt.encounters[capturedRaid][capturedIndex] = temp
            RefreshEncountersList()
          end,
          function()
            -- Delete
            StaticPopupDialogs["OGRH_CONFIRM_DELETE_ENCOUNTER"].text_arg1 = capturedEncounterName
            StaticPopupDialogs["OGRH_CONFIRM_DELETE_ENCOUNTER"].text_arg2 = capturedRaid
            StaticPopup_Show("OGRH_CONFIRM_DELETE_ENCOUNTER", capturedEncounterName)
          end
        )
        
        table.insert(frame.encounterButtons, encounterBtn)
        yOffset = yOffset - OGRH.LIST_ITEM_HEIGHT - OGRH.LIST_ITEM_SPACING
      end
      
      -- Add "Add Encounter" placeholder row at the bottom
      local addEncounterBtn = OGRH.CreateStyledListItem(scrollChild, contentWidth, OGRH.LIST_ITEM_HEIGHT, "Button")
      addEncounterBtn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, yOffset)
      
      local addText = addEncounterBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      addText:SetPoint("CENTER", addEncounterBtn, "CENTER", 0, 0)
      addText:SetText("|cff00ff00Add Encounter|r")
      
      local capturedRaid = frame.selectedRaid
      addEncounterBtn:SetScript("OnClick", function()
        StaticPopupDialogs["OGRH_ADD_ENCOUNTER"].text_arg1 = capturedRaid
        StaticPopup_Show("OGRH_ADD_ENCOUNTER")
      end)
      
      table.insert(frame.encounterButtons, addEncounterBtn)
      yOffset = yOffset - OGRH.LIST_ITEM_HEIGHT
      
      -- Update scroll child height
      local contentHeight = math.abs(yOffset) + 5
      scrollChild:SetHeight(math.max(contentHeight, 1))
      
      -- Update scrollbar visibility
      local scrollFrame = frame.encountersScrollFrame
      local scrollFrameHeight = scrollFrame:GetHeight()
      
      if contentHeight > scrollFrameHeight then
        -- Restore or adjust scroll position to keep selected item visible (scrollbar always hidden)
        if selectedIndex then
          local buttonHeight = 22
          local visibleHeight = scrollFrameHeight
          local buttonTop = (selectedIndex - 1) * buttonHeight
          local buttonBottom = buttonTop + buttonHeight
          local scrollBottom = savedScroll + visibleHeight
          
          -- If selected button is above visible area, scroll up to it
          if buttonTop < savedScroll then
            scrollFrame:SetVerticalScroll(buttonTop)
          -- If selected button is below visible area, scroll down to it
          elseif buttonBottom > scrollBottom then
            local newScroll = buttonBottom - visibleHeight
            scrollFrame:SetVerticalScroll(newScroll)
          else
            -- Selected item is visible, restore saved scroll position
            scrollFrame:SetVerticalScroll(savedScroll)
          end
        else
          -- No selected item, restore saved scroll position
          scrollFrame:SetVerticalScroll(savedScroll)
        end
      else
        scrollFrame:SetVerticalScroll(0)
      end
    end
    
    frame.RefreshEncountersList = RefreshEncountersList
    
    -- Design section (fills right 2/3 of window)
    local designLabel = contentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    designLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 220, -55)
    designLabel:SetText("Design:")
    
    -- Design frame
    local designFrame = CreateFrame("Frame", nil, contentFrame)
    designFrame:SetPoint("TOPLEFT", designLabel, "BOTTOMLEFT", 0, -5)
    designFrame:SetWidth(360)
    designFrame:SetHeight(382)
    designFrame:SetBackdrop({
      bgFile = "Interface/Tooltips/UI-Tooltip-Background",
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
      tile = true,
      tileSize = 16,
      edgeSize = 12,
      insets = {left = 3, right = 3, top = 3, bottom = 3}
    })
    designFrame:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
    
    designFrame:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
    frame.designFrame = designFrame
    
    -- Left column label (Roles)
    local rolesLabel = designFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    rolesLabel:SetPoint("TOPLEFT", designFrame, "TOPLEFT", 10, -10)
    rolesLabel:SetText("Roles:")
    
    -- Left column frame with standardized scroll list (no scrollbar)
    local rolesListFrame, rolesScrollFrame, rolesScrollChild, rolesScrollBar, rolesContentWidth = OGRH.CreateStyledScrollList(designFrame, 165, 340, true)
    rolesListFrame:SetPoint("TOPLEFT", rolesLabel, "BOTTOMLEFT", 0, -5)
    frame.rolesScrollChild = rolesScrollChild
    frame.rolesScrollFrame = rolesScrollFrame
    frame.rolesScrollBar = rolesScrollBar
    frame.rolesContentWidth = rolesContentWidth
    
    -- Right column frame (no label, vertically aligned with left)
    local rolesListFrame2, rolesScrollFrame2, rolesScrollChild2, rolesScrollBar2, rolesContentWidth2 = OGRH.CreateStyledScrollList(designFrame, 165, 340, true)
    rolesListFrame2:SetPoint("TOPLEFT", rolesListFrame, "TOPRIGHT", 15, 0)
    frame.rolesScrollChild2 = rolesScrollChild2
    frame.rolesScrollFrame2 = rolesScrollFrame2
    frame.rolesScrollBar2 = rolesScrollBar2
    
    -- Create drag cursor frame (follows mouse during drag operations)
    local dragCursor = CreateFrame("Frame", nil, UIParent)
    dragCursor:SetWidth(135)
    dragCursor:SetHeight(20)
    dragCursor:SetFrameStrata("TOOLTIP")
    dragCursor:Hide()
    
    local dragCursorBg = dragCursor:CreateTexture(nil, "BACKGROUND")
    dragCursorBg:SetAllPoints()
    dragCursorBg:SetTexture("Interface\\Buttons\\WHITE8X8")
    dragCursorBg:SetVertexColor(0.3, 0.5, 0.3, 0.9)
    
    local dragCursorText = dragCursor:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    dragCursorText:SetPoint("LEFT", dragCursor, "LEFT", 5, 0)
    dragCursorText:SetWidth(125)
    dragCursorText:SetJustifyH("LEFT")
    
    frame.dragCursor = dragCursor
    frame.dragCursorText = dragCursorText
    
    -- Update drag cursor position on frame update
    dragCursor:SetScript("OnUpdate", function()
      if dragCursor:IsShown() then
        local scale = UIParent:GetEffectiveScale()
        local x, y = GetCursorPosition()
        dragCursor:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
      end
    end)
    
    -- Function to update announcement tags when roles are reordered/deleted
    local function UpdateAnnouncementTagsForRoleChanges(raidName, encounterName, oldRoles, newRoles)
      if not OGRH_SV.encounterAnnouncements or not OGRH_SV.encounterAnnouncements[raidName] or 
         not OGRH_SV.encounterAnnouncements[raidName][encounterName] then
        return
      end
      
      -- Build a mapping from old role indices to new role indices by matching role objects
      local roleMapping = {} -- roleMapping[oldIndex] = newIndex
      
      for oldIdx, oldRole in ipairs(oldRoles) do
        for newIdx, newRole in ipairs(newRoles) do
          if oldRole == newRole then -- Same table reference
            roleMapping[oldIdx] = newIdx
            break
          end
        end
        -- If not found in new roles, it was deleted (no mapping)
      end
      
      -- Update all announcement lines
      local announcements = OGRH_SV.encounterAnnouncements[raidName][encounterName]
      for lineIdx, line in ipairs(announcements) do
        if line and line ~= "" then
          -- Replace all [Rx.xxx] tags with updated role indices
          local updatedLine = line
          
          -- Find all role references and update them
          -- Match patterns like [R1.T], [R2.P3], [R1.M1], [R1.A=2], etc.
          updatedLine = string.gsub(updatedLine, "%[R(%d+)%.([^%]]+)%]", function(roleNum, tagSuffix)
            local oldRoleIdx = tonumber(roleNum)
            local newRoleIdx = roleMapping[oldRoleIdx]
            
            if newRoleIdx then
              -- Role still exists, update to new index
              return "[R" .. newRoleIdx .. "." .. tagSuffix .. "]"
            else
              -- Role was deleted, remove the tag
              return ""
            end
          end)
          
          -- Clean up extra spaces left by removed tags
          updatedLine = string.gsub(updatedLine, "  +", " ")
          updatedLine = string.gsub(updatedLine, "^ +", "")
          updatedLine = string.gsub(updatedLine, " +$", "")
          
          announcements[lineIdx] = updatedLine
        end
      end
    end
    
    -- Function to refresh roles list
    local function RefreshRolesList()
      -- Clear existing buttons from both columns
      if frame.roleButtons then
        for _, btn in ipairs(frame.roleButtons) do
          if btn.placeholder then
            btn.placeholder:SetParent(nil)
            btn.placeholder = nil
          else
            btn:Hide()
            btn:SetParent(nil)
          end
        end
      end
      frame.roleButtons = {}
      
      local scrollChild1 = frame.rolesScrollChild
      local scrollChild2 = frame.rolesScrollChild2
      
      if not frame.selectedRaid or not frame.selectedEncounter then
        -- Show placeholder
        local placeholderText = designFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        placeholderText:SetPoint("CENTER", designFrame, "CENTER", 0, 0)
        placeholderText:SetText("|cff888888Select an encounter\nto design roles|r")
        placeholderText:SetJustifyH("CENTER")
        table.insert(frame.roleButtons, {placeholder = placeholderText})
        frame.rolesScrollBar:Hide()
        frame.rolesScrollBar2:Hide()
        return
      end
      
      -- Ensure roles storage exists with column structure
      if not OGRH_SV.encounterMgmt.roles then
        OGRH_SV.encounterMgmt.roles = {}
      end
      if not OGRH_SV.encounterMgmt.roles[frame.selectedRaid] then
        OGRH_SV.encounterMgmt.roles[frame.selectedRaid] = {}
      end
      if not OGRH_SV.encounterMgmt.roles[frame.selectedRaid][frame.selectedEncounter] then
        OGRH_SV.encounterMgmt.roles[frame.selectedRaid][frame.selectedEncounter] = {
          column1 = {},
          column2 = {}
        }
      end
      
      local rolesData = OGRH_SV.encounterMgmt.roles[frame.selectedRaid][frame.selectedEncounter]
      
      -- Handle legacy format (flat array) - migrate to column structure
      if rolesData[1] and not rolesData.column1 then
        local legacyRoles = {}
        for i, role in ipairs(rolesData) do
          table.insert(legacyRoles, role)
        end
        rolesData.column1 = {}
        rolesData.column2 = {}
        for i, role in ipairs(legacyRoles) do
          if math.mod(i, 2) == 1 then
            table.insert(rolesData.column1, role)
          else
            table.insert(rolesData.column2, role)
          end
          rolesData[i] = nil
        end
      end
      
      -- Ensure columns exist
      if not rolesData.column1 then rolesData.column1 = {} end
      if not rolesData.column2 then rolesData.column2 = {} end
      
      -- Ensure columns exist
      if not rolesData.column1 then rolesData.column1 = {} end
      if not rolesData.column2 then rolesData.column2 = {} end
      
      local yOffset1 = -5
      local yOffset2 = -5
      
      -- Helper function to create a role button
      local function CreateRoleButton(roleIndex, role, columnRoles, scrollChild, isColumn2)
        local roleBtn = OGRH.CreateStyledListItem(scrollChild, frame.rolesContentWidth, OGRH.LIST_ITEM_HEIGHT, "Button")
        
        local yOffset = isColumn2 and yOffset2 or yOffset1
        roleBtn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, yOffset)
        
        -- Make draggable
        roleBtn:RegisterForDrag("LeftButton")
        
        -- Role name text
        local nameText = roleBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        nameText:SetPoint("LEFT", roleBtn, "LEFT", 5, 0)
        nameText:SetText(role.name or "Unnamed")
        nameText:SetWidth(70)
        nameText:SetJustifyH("LEFT")
        
        -- Store data on button for drag operations
        roleBtn.roleData = role
        roleBtn.roleIndex = roleIndex
        roleBtn.columnRoles = columnRoles
        roleBtn.isColumn2 = isColumn2
        
        -- Click to edit role
        roleBtn:SetScript("OnClick", function()
          -- Check permission
          if not OGRH.CanEdit or not OGRH.CanEdit() then
            OGRH.Msg("Only the raid lead can edit roles.")
            return
          end
          
          OGRH.ShowEditRoleDialog(
            frame.selectedRaid,
            frame.selectedEncounter,
            role,
            columnRoles,
            roleIndex,
            RefreshRolesList
          )
        end)
        
        -- Drag handlers
        roleBtn:SetScript("OnDragStart", function()
          this.isDragging = true
          -- Visual feedback on original button
          OGRH.SetListItemColor(roleBtn, 0.3, 0.5, 0.3, 0.8)
          
          -- Show drag cursor
          if frame.dragCursor and frame.dragCursorText then
            frame.dragCursorText:SetText(role.name or "Unnamed")
            frame.dragCursor:Show()
          end
        end)
        
        roleBtn:SetScript("OnDragStop", function()
          this.isDragging = false
          OGRH.SetListItemSelected(roleBtn, false)
          
          -- Hide drag cursor
          if frame.dragCursor then
            frame.dragCursor:Hide()
          end
          
          -- Check if dropped on the other column's scroll frame
          local targetScrollFrame = this.isColumn2 and frame.rolesScrollFrame or frame.rolesScrollFrame2
          local targetColumnRoles = this.isColumn2 and rolesData.column1 or rolesData.column2
          local sourceColumnRoles = this.columnRoles
          
          if MouseIsOver(targetScrollFrame) then
            local selectedRaid = frame.selectedRaid
            local selectedEncounter = frame.selectedEncounter
            local rolesData = OGRH_SV.encounterMgmt.roles[selectedRaid][selectedEncounter]
            
            -- Save old roles state before moving (column1 then column2)
            local oldRoles = {}
            for _, role in ipairs(rolesData.column1) do table.insert(oldRoles, role) end
            for _, role in ipairs(rolesData.column2) do table.insert(oldRoles, role) end
            
            -- Move role to other column
            local role = sourceColumnRoles[this.roleIndex]
            table.remove(sourceColumnRoles, this.roleIndex)
            table.insert(targetColumnRoles, role)
            
            -- Build new roles state after moving
            local newRoles = {}
            for _, role in ipairs(rolesData.column1) do table.insert(newRoles, role) end
            for _, role in ipairs(rolesData.column2) do table.insert(newRoles, role) end
            
            -- Update announcement tags
            UpdateAnnouncementTagsForRoleChanges(selectedRaid, selectedEncounter, oldRoles, newRoles)
            
            RefreshRolesList()
          else
            -- Just refresh position
            RefreshRolesList()
          end
        end)
        
        -- Capture variables for button closures
        local capturedRoles = columnRoles
        local capturedIdx = roleIndex
        
        -- Add up/down/delete buttons using template
        OGRH.AddListItemButtons(
          roleBtn,
          capturedIdx,
          table.getn(capturedRoles),
          function()
            -- Move up
            local selectedRaid = frame.selectedRaid
            local selectedEncounter = frame.selectedEncounter
            local rolesData = OGRH_SV.encounterMgmt.roles[selectedRaid][selectedEncounter]
            
            -- Save old roles state before reordering (column1 then column2)
            local oldRoles = {}
            for _, role in ipairs(rolesData.column1) do table.insert(oldRoles, role) end
            for _, role in ipairs(rolesData.column2) do table.insert(oldRoles, role) end
            
            -- Swap roles
            local temp = capturedRoles[capturedIdx - 1]
            capturedRoles[capturedIdx - 1] = capturedRoles[capturedIdx]
            capturedRoles[capturedIdx] = temp
            
            -- Build new roles state after reordering
            local newRoles = {}
            for _, role in ipairs(rolesData.column1) do table.insert(newRoles, role) end
            for _, role in ipairs(rolesData.column2) do table.insert(newRoles, role) end
            
            -- Update announcement tags
            UpdateAnnouncementTagsForRoleChanges(selectedRaid, selectedEncounter, oldRoles, newRoles)
            
            RefreshRolesList()
          end,
          function()
            -- Move down
            local selectedRaid = frame.selectedRaid
            local selectedEncounter = frame.selectedEncounter
            local rolesData = OGRH_SV.encounterMgmt.roles[selectedRaid][selectedEncounter]
            
            -- Save old roles state before reordering (column1 then column2)
            local oldRoles = {}
            for _, role in ipairs(rolesData.column1) do table.insert(oldRoles, role) end
            for _, role in ipairs(rolesData.column2) do table.insert(oldRoles, role) end
            
            -- Swap roles
            local temp = capturedRoles[capturedIdx + 1]
            capturedRoles[capturedIdx + 1] = capturedRoles[capturedIdx]
            capturedRoles[capturedIdx] = temp
            
            -- Build new roles state after reordering
            local newRoles = {}
            for _, role in ipairs(rolesData.column1) do table.insert(newRoles, role) end
            for _, role in ipairs(rolesData.column2) do table.insert(newRoles, role) end
            
            -- Update announcement tags
            UpdateAnnouncementTagsForRoleChanges(selectedRaid, selectedEncounter, oldRoles, newRoles)
            
            RefreshRolesList()
          end,
          function()
            -- Delete
            local selectedRaid = frame.selectedRaid
            local selectedEncounter = frame.selectedEncounter
            local rolesData = OGRH_SV.encounterMgmt.roles[selectedRaid][selectedEncounter]
            
            -- Save old roles state before deletion (column1 then column2)
            local oldRoles = {}
            for _, role in ipairs(rolesData.column1) do table.insert(oldRoles, role) end
            for _, role in ipairs(rolesData.column2) do table.insert(oldRoles, role) end
            
            -- Remove the role
            table.remove(capturedRoles, capturedIdx)
            
            -- Build new roles state after deletion
            local newRoles = {}
            for _, role in ipairs(rolesData.column1) do table.insert(newRoles, role) end
            for _, role in ipairs(rolesData.column2) do table.insert(newRoles, role) end
            
            -- Update announcement tags
            UpdateAnnouncementTagsForRoleChanges(selectedRaid, selectedEncounter, oldRoles, newRoles)
            
            RefreshRolesList()
          end
        )
        
        table.insert(frame.roleButtons, roleBtn)
        
        if isColumn2 then
          yOffset2 = yOffset2 - (OGRH.LIST_ITEM_HEIGHT + OGRH.LIST_ITEM_SPACING)
        else
          yOffset1 = yOffset1 - (OGRH.LIST_ITEM_HEIGHT + OGRH.LIST_ITEM_SPACING)
        end
      end  -- End of CreateRoleButton function
      
      -- Add roles from column 1
      for i, role in ipairs(rolesData.column1) do
        CreateRoleButton(i, role, rolesData.column1, scrollChild1, false)
      end
      
      -- Add roles from column 2
      for i, role in ipairs(rolesData.column2) do
        CreateRoleButton(i, role, rolesData.column2, scrollChild2, true)
      end
      
      -- Add "Add Role" button to both columns at the bottom
      -- Left column Add Role button
      local addRoleBtn1 = OGRH.CreateStyledListItem(scrollChild1, frame.rolesContentWidth, OGRH.LIST_ITEM_HEIGHT, "Button")
      addRoleBtn1:SetPoint("TOPLEFT", scrollChild1, "TOPLEFT", 0, yOffset1)
      
      local addText1 = addRoleBtn1:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      addText1:SetPoint("CENTER", addRoleBtn1, "CENTER", 0, 0)
      addText1:SetText("|cff00ff00Add Role|r")
      
      addRoleBtn1:SetScript("OnClick", function()
        local newIndex = table.getn(rolesData.column1) + 1
        table.insert(rolesData.column1, {name = "New Role " .. newIndex, slots = 1})
        RefreshRolesList()
      end)
      
      table.insert(frame.roleButtons, addRoleBtn1)
      yOffset1 = yOffset1 - (OGRH.LIST_ITEM_HEIGHT + OGRH.LIST_ITEM_SPACING)
      
      -- Right column Add Role button
      local addRoleBtn2 = OGRH.CreateStyledListItem(scrollChild2, frame.rolesContentWidth, OGRH.LIST_ITEM_HEIGHT, "Button")
      addRoleBtn2:SetPoint("TOPLEFT", scrollChild2, "TOPLEFT", 0, yOffset2)
      
      local addText2 = addRoleBtn2:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      addText2:SetPoint("CENTER", addRoleBtn2, "CENTER", 0, 0)
      addText2:SetText("|cff00ff00Add Role|r")
      
      addRoleBtn2:SetScript("OnClick", function()
        local newIndex = table.getn(rolesData.column2) + 1
        table.insert(rolesData.column2, {name = "New Role " .. newIndex, slots = 1})
        RefreshRolesList()
      end)
      
      table.insert(frame.roleButtons, addRoleBtn2)
      yOffset2 = yOffset2 - (OGRH.LIST_ITEM_HEIGHT + OGRH.LIST_ITEM_SPACING)
      
      -- Update scroll child heights
      local contentHeight1 = math.abs(yOffset1) + 5
      scrollChild1:SetHeight(contentHeight1)
      
      local contentHeight2 = math.abs(yOffset2) + 5
      scrollChild2:SetHeight(contentHeight2)
      
      -- Update scroll for column 1 (scrollbar always hidden)
      local scrollFrame1 = frame.rolesScrollFrame
      scrollFrame1:SetVerticalScroll(0)
      
      -- Update scroll for column 2 (scrollbar always hidden)
      local scrollFrame2 = frame.rolesScrollFrame2
      scrollFrame2:SetVerticalScroll(0)
    end
    
    frame.RefreshRolesList = RefreshRolesList
    
    -- Initialize lists
    RefreshRaidsList()
    RefreshEncountersList()
    RefreshRolesList()
  end
  
  -- Close Roles window if it's open
  if OGRH.rolesFrame and OGRH.rolesFrame:IsVisible() then
    OGRH.rolesFrame:Hide()
  end
  
  local frame = OGRH_EncounterSetupFrame
  frame:Show()
  frame.RefreshRaidsList()
end

-- StaticPopup dialogs for raid management
StaticPopupDialogs["OGRH_ADD_RAID"] = {
  text = "Enter raid name:",
  button1 = "Add",
  button2 = "Cancel",
  hasEditBox = 1,
  maxLetters = 32,
  OnAccept = function()
    local raidName = getglobal(this:GetParent():GetName().."EditBox"):GetText()
    if raidName and raidName ~= "" then
      InitializeSavedVars()
      -- Check if raid already exists
      local exists = false
      for _, name in ipairs(OGRH_SV.encounterMgmt.raids) do
        if name == raidName then
          exists = true
          break
        end
      end
      
      if not exists then
        table.insert(OGRH_SV.encounterMgmt.raids, raidName)
        if OGRH_EncounterSetupFrame and OGRH_EncounterSetupFrame.RefreshRaidsList then
          OGRH_EncounterSetupFrame.RefreshRaidsList()
        end
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OGRH:|r Raid '" .. raidName .. "' added")
      else
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OGRH:|r Raid '" .. raidName .. "' already exists")
      end
    end
  end,
  OnShow = function()
    getglobal(this:GetName().."EditBox"):SetFocus()
  end,
  OnHide = function()
    getglobal(this:GetName().."EditBox"):SetText("")
  end,
  EditBoxOnEnterPressed = function()
    local parent = this:GetParent()
    StaticPopup_OnClick(parent, 1)
  end,
  EditBoxOnEscapePressed = function()
    this:GetParent():Hide()
  end,
  timeout = 0,
  whileDead = 1,
  hideOnEscape = 1
}

StaticPopupDialogs["OGRH_CONFIRM_DELETE_RAID"] = {
  text = "Delete raid '%s'?\n\nThis will remove the raid and all its encounters.\n\n|cffff0000This cannot be undone!|r",
  button1 = "Delete",
  button2 = "Cancel",
  OnAccept = function()
    local raidName = StaticPopupDialogs["OGRH_CONFIRM_DELETE_RAID"].text_arg1
    if raidName then
      -- Remove raid from list
      for i, name in ipairs(OGRH_SV.encounterMgmt.raids) do
        if name == raidName then
          table.remove(OGRH_SV.encounterMgmt.raids, i)
          break
        end
      end
      
      -- Remove all encounter data associated with this raid
      OGRH_SV.encounterMgmt.encounters[raidName] = nil
      
      if OGRH_EncounterSetupFrame and OGRH_EncounterSetupFrame.RefreshRaidsList then
        OGRH_EncounterSetupFrame.selectedRaid = nil
        OGRH_EncounterSetupFrame.selectedEncounter = nil
        OGRH_EncounterSetupFrame.RefreshRaidsList()
        if OGRH_EncounterSetupFrame.RefreshEncountersList then
          OGRH_EncounterSetupFrame.RefreshEncountersList()
        end
        if OGRH_EncounterSetupFrame.RefreshRolesList then
          OGRH_EncounterSetupFrame.RefreshRolesList()
        end
      end
      DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OGRH:|r Raid '" .. raidName .. "' deleted")
    end
  end,
  timeout = 0,
  whileDead = 1,
  hideOnEscape = 1
}

StaticPopupDialogs["OGRH_ADD_ENCOUNTER"] = {
  text = "Enter encounter name:",
  button1 = "Add",
  button2 = "Cancel",
  hasEditBox = 1,
  maxLetters = 32,
  OnAccept = function()
    local encounterName = getglobal(this:GetParent():GetName().."EditBox"):GetText()
    local raidName = StaticPopupDialogs["OGRH_ADD_ENCOUNTER"].text_arg1
    if encounterName and encounterName ~= "" and raidName then
      InitializeSavedVars()
      -- Ensure raid encounters table exists
      if not OGRH_SV.encounterMgmt.encounters[raidName] then
        OGRH_SV.encounterMgmt.encounters[raidName] = {}
      end
      
      -- Check if encounter already exists
      local exists = false
      for _, name in ipairs(OGRH_SV.encounterMgmt.encounters[raidName]) do
        if name == encounterName then
          exists = true
          break
        end
      end
      
      if not exists then
        table.insert(OGRH_SV.encounterMgmt.encounters[raidName], encounterName)
        if OGRH_EncounterSetupFrame and OGRH_EncounterSetupFrame.RefreshEncountersList then
          OGRH_EncounterSetupFrame.RefreshEncountersList()
        end
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OGRH:|r Encounter '" .. encounterName .. "' added to " .. raidName)
      else
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OGRH:|r Encounter '" .. encounterName .. "' already exists in " .. raidName)
      end
    end
  end,
  OnShow = function()
    getglobal(this:GetName().."EditBox"):SetFocus()
  end,
  OnHide = function()
    getglobal(this:GetName().."EditBox"):SetText("")
  end,
  EditBoxOnEnterPressed = function()
    local parent = this:GetParent()
    StaticPopup_OnClick(parent, 1)
  end,
  EditBoxOnEscapePressed = function()
    this:GetParent():Hide()
  end,
  timeout = 0,
  whileDead = 1,
  hideOnEscape = 1
}

StaticPopupDialogs["OGRH_CONFIRM_DELETE_ENCOUNTER"] = {
  text = "Delete encounter '%s'?\n\n|cffff0000This cannot be undone!|r",
  button1 = "Delete",
  button2 = "Cancel",
  OnAccept = function()
    local encounterName = StaticPopupDialogs["OGRH_CONFIRM_DELETE_ENCOUNTER"].text_arg1
    local raidName = StaticPopupDialogs["OGRH_CONFIRM_DELETE_ENCOUNTER"].text_arg2
    if encounterName and raidName then
      -- Remove encounter from list
      if OGRH_SV.encounterMgmt.encounters[raidName] then
        for i, name in ipairs(OGRH_SV.encounterMgmt.encounters[raidName]) do
          if name == encounterName then
            table.remove(OGRH_SV.encounterMgmt.encounters[raidName], i)
            break
          end
        end
      end
      
      -- TODO: Remove encounter design data
      
      if OGRH_EncounterSetupFrame then
        OGRH_EncounterSetupFrame.selectedEncounter = nil
        if OGRH_EncounterSetupFrame.RefreshEncountersList then
          OGRH_EncounterSetupFrame.RefreshEncountersList()
        end
        if OGRH_EncounterSetupFrame.RefreshRolesList then
          OGRH_EncounterSetupFrame.RefreshRolesList()
        end
      end
      DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OGRH:|r Encounter '" .. encounterName .. "' deleted")
    end
  end,
  timeout = 0,
  whileDead = 1,
  hideOnEscape = 1
}

StaticPopupDialogs["OGRH_RENAME_RAID"] = {
  text = "Rename raid '%s':",
  button1 = "Rename",
  button2 = "Cancel",
  hasEditBox = 1,
  maxLetters = 32,
  OnAccept = function()
    local newName = getglobal(this:GetParent():GetName().."EditBox"):GetText()
    local oldName = StaticPopupDialogs["OGRH_RENAME_RAID"].text_arg1
    
    if newName and newName ~= "" and oldName and newName ~= oldName then
      InitializeSavedVars()
      
      -- Check if new name already exists
      local exists = false
      for _, name in ipairs(OGRH_SV.encounterMgmt.raids) do
        if name == newName then
          exists = true
          break
        end
      end
      
      if not exists then
        -- Update raid name in raids list
        for i, name in ipairs(OGRH_SV.encounterMgmt.raids) do
          if name == oldName then
            OGRH_SV.encounterMgmt.raids[i] = newName
            break
          end
        end
        
        -- Update encounters data structure
        if OGRH_SV.encounterMgmt.encounters[oldName] then
          OGRH_SV.encounterMgmt.encounters[newName] = OGRH_SV.encounterMgmt.encounters[oldName]
          OGRH_SV.encounterMgmt.encounters[oldName] = nil
        end
        
        -- Update roles data structure
        if OGRH_SV.encounterMgmt.roles and OGRH_SV.encounterMgmt.roles[oldName] then
          OGRH_SV.encounterMgmt.roles[newName] = OGRH_SV.encounterMgmt.roles[oldName]
          OGRH_SV.encounterMgmt.roles[oldName] = nil
        end
        
        -- Update assignments
        if OGRH_SV.encounterAssignments and OGRH_SV.encounterAssignments[oldName] then
          OGRH_SV.encounterAssignments[newName] = OGRH_SV.encounterAssignments[oldName]
          OGRH_SV.encounterAssignments[oldName] = nil
        end
        
        -- Update raid marks
        if OGRH_SV.encounterRaidMarks and OGRH_SV.encounterRaidMarks[oldName] then
          OGRH_SV.encounterRaidMarks[newName] = OGRH_SV.encounterRaidMarks[oldName]
          OGRH_SV.encounterRaidMarks[oldName] = nil
        end
        
        -- Update assignment numbers
        if OGRH_SV.encounterAssignmentNumbers and OGRH_SV.encounterAssignmentNumbers[oldName] then
          OGRH_SV.encounterAssignmentNumbers[newName] = OGRH_SV.encounterAssignmentNumbers[oldName]
          OGRH_SV.encounterAssignmentNumbers[oldName] = nil
        end
        
        -- Update announcements
        if OGRH_SV.encounterAnnouncements and OGRH_SV.encounterAnnouncements[oldName] then
          OGRH_SV.encounterAnnouncements[newName] = OGRH_SV.encounterAnnouncements[oldName]
          OGRH_SV.encounterAnnouncements[oldName] = nil
        end
        
        -- Update selected raid in both windows
        if OGRH_EncounterSetupFrame and OGRH_EncounterSetupFrame.selectedRaid == oldName then
          OGRH_EncounterSetupFrame.selectedRaid = newName
        end
        if OGRH_EncounterFrame and OGRH_EncounterFrame.selectedRaid == oldName then
          OGRH_EncounterFrame.selectedRaid = newName
        end
        
        -- Refresh windows
        if OGRH_EncounterSetupFrame and OGRH_EncounterSetupFrame.RefreshRaidsList then
          OGRH_EncounterSetupFrame.RefreshRaidsList()
          if OGRH_EncounterSetupFrame.RefreshEncountersList then
            OGRH_EncounterSetupFrame.RefreshEncountersList()
          end
        end
        if OGRH_EncounterFrame and OGRH_EncounterFrame.RefreshRaidsList then
          OGRH_EncounterFrame.RefreshRaidsList()
          if OGRH_EncounterFrame.RefreshEncountersList then
            OGRH_EncounterFrame.RefreshEncountersList()
          end
        end
        
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OGRH:|r Raid renamed from '" .. oldName .. "' to '" .. newName .. "'")
      else
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OGRH:|r Raid '" .. newName .. "' already exists")
      end
    end
  end,
  OnShow = function()
    local editBox = getglobal(this:GetName().."EditBox")
    local oldName = StaticPopupDialogs["OGRH_RENAME_RAID"].text_arg1
    editBox:SetText(oldName or "")
    editBox:HighlightText()
    editBox:SetFocus()
  end,
  OnHide = function()
    getglobal(this:GetName().."EditBox"):SetText("")
  end,
  EditBoxOnEnterPressed = function()
    local parent = this:GetParent()
    StaticPopup_OnClick(parent, 1)
  end,
  EditBoxOnEscapePressed = function()
    this:GetParent():Hide()
  end,
  timeout = 0,
  whileDead = 1,
  hideOnEscape = 1
}

StaticPopupDialogs["OGRH_RENAME_ENCOUNTER"] = {
  text = "Rename encounter '%s':",
  button1 = "Rename",
  button2 = "Cancel",
  hasEditBox = 1,
  maxLetters = 32,
  OnAccept = function()
    local newName = getglobal(this:GetParent():GetName().."EditBox"):GetText()
    local oldName = StaticPopupDialogs["OGRH_RENAME_ENCOUNTER"].text_arg1
    local raidName = StaticPopupDialogs["OGRH_RENAME_ENCOUNTER"].text_arg2
    
    if newName and newName ~= "" and oldName and raidName and newName ~= oldName then
      InitializeSavedVars()
      
      -- Check if new name already exists in this raid
      local exists = false
      if OGRH_SV.encounterMgmt.encounters[raidName] then
        for _, name in ipairs(OGRH_SV.encounterMgmt.encounters[raidName]) do
          if name == newName then
            exists = true
            break
          end
        end
      end
      
      if not exists then
        -- Update encounter name in encounters list
        if OGRH_SV.encounterMgmt.encounters[raidName] then
          for i, name in ipairs(OGRH_SV.encounterMgmt.encounters[raidName]) do
            if name == oldName then
              OGRH_SV.encounterMgmt.encounters[raidName][i] = newName
              break
            end
          end
        end
        
        -- Update roles data structure
        if OGRH_SV.encounterMgmt.roles and OGRH_SV.encounterMgmt.roles[raidName] and OGRH_SV.encounterMgmt.roles[raidName][oldName] then
          OGRH_SV.encounterMgmt.roles[raidName][newName] = OGRH_SV.encounterMgmt.roles[raidName][oldName]
          OGRH_SV.encounterMgmt.roles[raidName][oldName] = nil
        end
        
        -- Update assignments
        if OGRH_SV.encounterAssignments and OGRH_SV.encounterAssignments[raidName] and OGRH_SV.encounterAssignments[raidName][oldName] then
          OGRH_SV.encounterAssignments[raidName][newName] = OGRH_SV.encounterAssignments[raidName][oldName]
          OGRH_SV.encounterAssignments[raidName][oldName] = nil
        end
        
        -- Update raid marks
        if OGRH_SV.encounterRaidMarks and OGRH_SV.encounterRaidMarks[raidName] and OGRH_SV.encounterRaidMarks[raidName][oldName] then
          OGRH_SV.encounterRaidMarks[raidName][newName] = OGRH_SV.encounterRaidMarks[raidName][oldName]
          OGRH_SV.encounterRaidMarks[raidName][oldName] = nil
        end
        
        -- Update assignment numbers
        if OGRH_SV.encounterAssignmentNumbers and OGRH_SV.encounterAssignmentNumbers[raidName] and OGRH_SV.encounterAssignmentNumbers[raidName][oldName] then
          OGRH_SV.encounterAssignmentNumbers[raidName][newName] = OGRH_SV.encounterAssignmentNumbers[raidName][oldName]
          OGRH_SV.encounterAssignmentNumbers[raidName][oldName] = nil
        end
        
        -- Update announcements
        if OGRH_SV.encounterAnnouncements and OGRH_SV.encounterAnnouncements[raidName] and OGRH_SV.encounterAnnouncements[raidName][oldName] then
          OGRH_SV.encounterAnnouncements[raidName][newName] = OGRH_SV.encounterAnnouncements[raidName][oldName]
          OGRH_SV.encounterAnnouncements[raidName][oldName] = nil
        end
        
        -- Update selected encounter in both windows
        if OGRH_EncounterSetupFrame and OGRH_EncounterSetupFrame.selectedEncounter == oldName then
          OGRH_EncounterSetupFrame.selectedEncounter = newName
        end
        if OGRH_EncounterFrame and OGRH_EncounterFrame.selectedEncounter == oldName then
          OGRH_EncounterFrame.selectedEncounter = newName
        end
        
        -- Refresh windows
        if OGRH_EncounterSetupFrame and OGRH_EncounterSetupFrame.RefreshEncountersList then
          OGRH_EncounterSetupFrame.RefreshEncountersList()
          if OGRH_EncounterSetupFrame.RefreshRolesList then
            OGRH_EncounterSetupFrame.RefreshRolesList()
          end
        end
        if OGRH_EncounterFrame and OGRH_EncounterFrame.RefreshEncountersList then
          OGRH_EncounterFrame.RefreshEncountersList()
          if OGRH_EncounterFrame.RefreshRoleContainers then
            OGRH_EncounterFrame.RefreshRoleContainers()
          end
        end
        
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OGRH:|r Encounter renamed from '" .. oldName .. "' to '" .. newName .. "'")
      else
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OGRH:|r Encounter '" .. newName .. "' already exists in " .. raidName)
      end
    end
  end,
  OnShow = function()
    local editBox = getglobal(this:GetName().."EditBox")
    local oldName = StaticPopupDialogs["OGRH_RENAME_ENCOUNTER"].text_arg1
    editBox:SetText(oldName or "")
    editBox:HighlightText()
    editBox:SetFocus()
  end,
  OnHide = function()
    getglobal(this:GetName().."EditBox"):SetText("")
  end,
  EditBoxOnEnterPressed = function()
    local parent = this:GetParent()
    StaticPopup_OnClick(parent, 1)
  end,
  EditBoxOnEscapePressed = function()
    this:GetParent():Hide()
  end,
  timeout = 0,
  whileDead = 1,
  hideOnEscape = 1
}

-- Function to show player selection dialog
function OGRH.ShowPlayerSelectionDialog(raidName, encounterName, targetRoleIndex, targetSlotIndex, encounterFrame)
  -- Create or reuse frame
  if not OGRH_PlayerSelectionFrame then
    local frame = CreateFrame("Frame", "OGRH_PlayerSelectionFrame", UIParent)
    frame:SetWidth(350)
    frame:SetHeight(450)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetBackdrop({
      bgFile = "Interface/Tooltips/UI-Tooltip-Background",
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
      tile = true,
      tileSize = 16,
      edgeSize = 16,
      insets = {left = 4, right = 4, top = 4, bottom = 4}
    })
    frame:SetBackdropColor(0, 0, 0, 0.95)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function() frame:StartMoving() end)
    frame:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
    
    -- Register ESC key handler
    OGRH.MakeFrameCloseOnEscape(frame, "OGRH_PlayerSelectionFrame")
    
    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", frame, "TOP", 0, -10)
    title:SetText("Select Player")
    frame.title = title
    
    -- Role filter dropdown
    local roleFilterBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    roleFilterBtn:SetWidth(200)
    roleFilterBtn:SetHeight(24)
    roleFilterBtn:SetPoint("TOP", title, "BOTTOM", 0, -10)
    roleFilterBtn:SetText("All Players")
    frame.roleFilterBtn = roleFilterBtn
    frame.selectedFilter = "all"
    
    -- Player list scroll frame
    local listFrame = CreateFrame("Frame", nil, frame)
    listFrame:SetWidth(320)
    listFrame:SetHeight(340)
    listFrame:SetPoint("TOP", roleFilterBtn, "BOTTOM", 0, -10)
    listFrame:SetPoint("LEFT", frame, "LEFT", 15, 0)
    listFrame:SetPoint("RIGHT", frame, "RIGHT", -15, 0)
    listFrame:SetBackdrop({
      bgFile = "Interface/Tooltips/UI-Tooltip-Background",
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
      tile = true,
      tileSize = 16,
      edgeSize = 12,
      insets = {left = 3, right = 3, top = 3, bottom = 3}
    })
    listFrame:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
    
    local scrollFrame = CreateFrame("ScrollFrame", nil, listFrame)
    scrollFrame:SetPoint("TOPLEFT", listFrame, "TOPLEFT", 5, -5)
    scrollFrame:SetPoint("BOTTOMRIGHT", listFrame, "BOTTOMRIGHT", -5, 5)
    
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(310)
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)
    frame.scrollChild = scrollChild
    
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function()
      local delta = arg1
      local current = scrollFrame:GetVerticalScroll()
      local maxScroll = scrollChild:GetHeight() - scrollFrame:GetHeight()
      if maxScroll < 0 then maxScroll = 0 end
      
      local newScroll = current - (delta * 20)
      if newScroll < 0 then newScroll = 0 elseif newScroll > maxScroll then newScroll = maxScroll end
      scrollFrame:SetVerticalScroll(newScroll)
    end)
    
    -- OK button
    local okBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    okBtn:SetWidth(80)
    okBtn:SetHeight(24)
    okBtn:SetPoint("BOTTOM", frame, "BOTTOM", -45, 15)
    okBtn:SetText("OK")
    frame.okBtn = okBtn
    
    -- Cancel button
    local cancelBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    cancelBtn:SetWidth(80)
    cancelBtn:SetHeight(24)
    cancelBtn:SetPoint("BOTTOM", frame, "BOTTOM", 45, 15)
    cancelBtn:SetText("Cancel")
    cancelBtn:SetScript("OnClick", function() frame:Hide() end)
    
    OGRH_PlayerSelectionFrame = frame
  end
  
  local frame = OGRH_PlayerSelectionFrame
  frame.selectedPlayer = nil
  
  -- Store dialog parameters on frame so GetRaidMembers can access them
  frame.currentRaidName = raidName
  frame.currentEncounterName = encounterName
  frame.currentTargetRoleIndex = targetRoleIndex
  frame.currentTargetSlotIndex = targetSlotIndex
  frame.currentEncounterFrame = encounterFrame
  
  -- Determine which role filter to use based on targetRoleIndex and defaultRoles setting
  local roleFilterToSet = "pool" -- Default to pool
  local targetRole = nil
  if OGRH_SV.encounterMgmt and OGRH_SV.encounterMgmt.roles and
     OGRH_SV.encounterMgmt.roles[raidName] and
     OGRH_SV.encounterMgmt.roles[raidName][encounterName] then
    local encounterRoles = OGRH_SV.encounterMgmt.roles[raidName][encounterName]
    local column1 = encounterRoles.column1 or {}
    local column2 = encounterRoles.column2 or {}
    
    -- targetRoleIndex is 1-based across both columns
    if targetRoleIndex <= table.getn(column1) then
      targetRole = column1[targetRoleIndex]
    else
      targetRole = column2[targetRoleIndex - table.getn(column1)]
    end
    
    -- Use the defaultRoles setting to determine which filter to show
    if targetRole and targetRole.defaultRoles then
      if targetRole.defaultRoles.tanks then
        roleFilterToSet = "Tanks"
      elseif targetRole.defaultRoles.healers then
        roleFilterToSet = "Healers"
      elseif targetRole.defaultRoles.melee then
        roleFilterToSet = "Melee"
      elseif targetRole.defaultRoles.ranged then
        roleFilterToSet = "Ranged"
      end
    end
  end
  
  frame.selectedFilter = roleFilterToSet
  if frame.roleFilterBtn then
    frame.roleFilterBtn:SetText(roleFilterToSet)
  end
  
  -- Get raid members from current raid
  -- Store as frame method so it always uses current frame values
  if not frame.GetRaidMembers then
    frame.GetRaidMembers = function()
      local members = {}
      
      if frame.selectedFilter == "all" then
        -- All Players: Show everyone currently in raid
        for j = 1, GetNumRaidMembers() do
          local name, _, _, _, class = GetRaidRosterInfo(j)
          if name then
            members[name] = {
              name = name,
              role = "All",
              class = class
            }
          end
        end
      elseif frame.selectedFilter == "Tanks" or frame.selectedFilter == "Healers" or 
           frame.selectedFilter == "Melee" or frame.selectedFilter == "Ranged" then
      -- Role-specific: Show players in raid assigned to this role in RolesUI
      local roleConst = nil
      if frame.selectedFilter == "Tanks" then roleConst = "TANKS"
      elseif frame.selectedFilter == "Healers" then roleConst = "HEALERS"
      elseif frame.selectedFilter == "Melee" then roleConst = "MELEE"
      elseif frame.selectedFilter == "Ranged" then roleConst = "RANGED"
      end
      
      if roleConst and OGRH.GetRolePlayers then
        local rolePlayers = OGRH.GetRolePlayers(roleConst)
        if rolePlayers then
          for i = 1, table.getn(rolePlayers) do
            local name = rolePlayers[i]
            -- Get class from raid roster (only show if in raid)
            local class = nil
            for j = 1, GetNumRaidMembers() do
              local raidName, _, _, _, raidClass = GetRaidRosterInfo(j)
              if raidName == name then
                class = raidClass
                members[name] = {
                  name = name,
                  role = frame.selectedFilter,
                  class = class
                }
                break
              end
            end
          end
        end
      end
    end
    
    return members
  end
  end
  local GetRaidMembers = frame.GetRaidMembers
  
  -- Refresh player list
  local function RefreshPlayerList()
    -- Clear existing buttons
    if frame.playerButtons then
      for _, btn in ipairs(frame.playerButtons) do
        btn:Hide()
        btn:SetParent(nil)
      end
    end
    frame.playerButtons = {}
    
    local members = GetRaidMembers()
    local yOffset = -5
    
    -- Build sorted list (no additional filtering needed, GetRaidMembers already filtered)
    local sortedMembers = {}
    for playerName, data in pairs(members) do
      table.insert(sortedMembers, data)
    end
    table.sort(sortedMembers, function(a, b) return a.name < b.name end)
    
    -- Create buttons
    for _, data in ipairs(sortedMembers) do
      local btn = CreateFrame("Button", nil, frame.scrollChild)
      btn:SetWidth(300)
      btn:SetHeight(20)
      btn:SetPoint("TOPLEFT", frame.scrollChild, "TOPLEFT", 0, yOffset)
      
      local bg = btn:CreateTexture(nil, "BACKGROUND")
      bg:SetAllPoints()
      bg:SetTexture("Interface\\Buttons\\WHITE8X8")
      bg:SetVertexColor(0.2, 0.2, 0.2, 0.5)
      btn.bg = bg
      
      local nameText = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      nameText:SetPoint("LEFT", btn, "LEFT", 5, 0)
      
      -- Color by class
      local colorCode = "|cffffffff"
      if data.class and OGRH.COLOR.CLASS[string.upper(data.class)] then
        colorCode = OGRH.COLOR.CLASS[string.upper(data.class)]
      end
      nameText:SetText(colorCode .. data.name .. "|r")
      
      local capturedName = data.name
      btn:SetScript("OnClick", function()
        frame.selectedPlayer = capturedName
        
        -- Update visual selection
        for _, otherBtn in ipairs(frame.playerButtons) do
          otherBtn.bg:SetVertexColor(0.2, 0.2, 0.2, 0.5)
        end
        this.bg:SetVertexColor(0.2, 0.4, 0.2, 0.8)
      end)
      
      table.insert(frame.playerButtons, btn)
      yOffset = yOffset - 22
    end
    
    frame.scrollChild:SetHeight(math.max(1, math.abs(yOffset) + 5))
  end
  
  -- Store RefreshPlayerList as frame method
  frame.RefreshPlayerList = RefreshPlayerList
  
  -- Role filter dropdown functionality
  frame.roleFilterBtn:SetScript("OnClick", function()
    if not frame.roleMenu then
      local menu = CreateFrame("Frame", nil, frame)
      menu:SetWidth(200)
      menu:SetHeight(150)
      menu:SetPoint("TOP", frame.roleFilterBtn, "BOTTOM", 0, -5)
      menu:SetFrameStrata("TOOLTIP")
      menu:SetFrameLevel(frame:GetFrameLevel() + 10)
      menu:EnableMouse(true)
      menu:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = {left = 3, right = 3, top = 3, bottom = 3}
      })
      menu:SetBackdropColor(0, 0, 0, 0.95)
      menu:Hide()
      frame.roleMenu = menu
      
      local roles = {
        {filter = "all", label = "All Players"},
        {filter = "Tanks", label = "Tanks"},
        {filter = "Healers", label = "Healers"},
        {filter = "Melee", label = "Melee"},
        {filter = "Ranged", label = "Ranged"}
      }
      local yOffset = -5
      
      for _, roleData in ipairs(roles) do
        local btn = CreateFrame("Button", nil, menu)
        btn:SetWidth(190)
        btn:SetHeight(20)
        btn:SetPoint("TOPLEFT", menu, "TOPLEFT", 5, yOffset)
        
        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetTexture("Interface\\Buttons\\WHITE8X8")
        bg:SetVertexColor(0.2, 0.2, 0.2, 0.5)
        
        local text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        text:SetPoint("LEFT", btn, "LEFT", 5, 0)
        text:SetText(roleData.label)
        
        local capturedFilter = roleData.filter
        local capturedLabel = roleData.label
        btn:SetScript("OnClick", function()
          frame.selectedFilter = capturedFilter
          frame.roleFilterBtn:SetText(capturedLabel)
          menu:Hide()
          RefreshPlayerList()
        end)
        
        btn:SetScript("OnEnter", function() bg:SetVertexColor(0.3, 0.3, 0.4, 0.8) end)
        btn:SetScript("OnLeave", function() bg:SetVertexColor(0.2, 0.2, 0.2, 0.5) end)
        
        yOffset = yOffset - 22
      end
      
      -- Update menu height to fit all options
      menu:SetHeight(math.abs(yOffset) + 10)
    end
    
    if frame.roleMenu:IsShown() then
      frame.roleMenu:Hide()
    else
      frame.roleMenu:Show()
    end
  end)
  
  -- OK button handler
  frame.okBtn:SetScript("OnClick", function()
    local currentRaid = frame.currentRaidName
    local currentEnc = frame.currentEncounterName
    local currentRoleIdx = frame.currentTargetRoleIndex
    local currentSlotIdx = frame.currentTargetSlotIndex
    local currentEncFrame = frame.currentEncounterFrame
    
    -- Initialize assignments
    if not OGRH_SV.encounterAssignments then
      OGRH_SV.encounterAssignments = {}
    end
    if not OGRH_SV.encounterAssignments[currentRaid] then
      OGRH_SV.encounterAssignments[currentRaid] = {}
    end
    if not OGRH_SV.encounterAssignments[currentRaid][currentEnc] then
      OGRH_SV.encounterAssignments[currentRaid][currentEnc] = {}
    end
    if not OGRH_SV.encounterAssignments[currentRaid][currentEnc][currentRoleIdx] then
      OGRH_SV.encounterAssignments[currentRaid][currentEnc][currentRoleIdx] = {}
    end
    
    if not frame.selectedPlayer then
      -- No player selected: clear the assignment
      OGRH_SV.encounterAssignments[currentRaid][currentEnc][currentRoleIdx][currentSlotIdx] = nil
      DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OGRH:|r Assignment cleared.")
    else
      -- Assign player
      OGRH_SV.encounterAssignments[currentRaid][currentEnc][currentRoleIdx][currentSlotIdx] = frame.selectedPlayer
    end
    
    -- Refresh encounter frame
    if currentEncFrame and currentEncFrame.RefreshRoleContainers then
      currentEncFrame.RefreshRoleContainers()
    end
    
    frame:Hide()
  end)
  
  RefreshPlayerList()
  frame:Show()
end

-- Function to show edit role dialog
function OGRH.ShowEditRoleDialog(raidName, encounterName, roleData, columnRoles, roleIndex, refreshCallback)
  -- Create or reuse frame
  if not OGRH_EditRoleFrame then
    local frame = CreateFrame("Frame", "OGRH_EditRoleFrame", UIParent)
    frame:SetWidth(350)
    frame:SetHeight(380)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetFrameStrata("DIALOG")
    frame:SetBackdrop({
      bgFile = "Interface/Tooltips/UI-Tooltip-Background",
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
      tile = true,
      tileSize = 16,
      edgeSize = 16,
      insets = {left = 4, right = 4, top = 4, bottom = 4}
    })
    frame:SetBackdropColor(0, 0, 0, 0.9)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function() frame:StartMoving() end)
    frame:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
    
    -- Register ESC key handler
    OGRH.MakeFrameCloseOnEscape(frame, "OGRH_EditRoleFrame")
    
    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", frame, "TOP", 0, -10)
    title:SetText("Edit Role")
    
    -- Role Type Dropdown
    local roleTypeLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    roleTypeLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, -40)
    roleTypeLabel:SetText("Role Type:")
    frame.roleTypeLabel = roleTypeLabel
    
    local roleTypeBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    roleTypeBtn:SetWidth(150)
    roleTypeBtn:SetHeight(24)
    roleTypeBtn:SetPoint("LEFT", roleTypeLabel, "RIGHT", 10, 0)
    roleTypeBtn:SetText("Raider Roles")
    OGRH.StyleButton(roleTypeBtn)
    frame.roleTypeBtn = roleTypeBtn
    frame.selectedRoleType = "raider"  -- Default value
    
    -- Role Type dropdown click handler
    roleTypeBtn:SetScript("OnClick", function()
      -- Recalculate which role types already exist in this encounter
      local hasConsumeCheck = false
      local hasCustomModule = false
      local currentColumnRoles = frame.currentColumnRoles
      local currentRoleIndex = frame.currentRoleIndex
      
      if currentColumnRoles then
        for i, role in ipairs(currentColumnRoles) do
          if i ~= currentRoleIndex then
            if role.isConsumeCheck then
              hasConsumeCheck = true
            end
            if role.isCustomModule then
              hasCustomModule = true
            end
          end
        end
      end
      
      -- Create menu items (filter based on existing roles)
      local menuItems = {
        {text = "Raider Roles", value = "raider", label = "Raider Roles"}
      }
      
      -- Only show Consume Check if one doesn't already exist (or this is the consume check)
      if not hasConsumeCheck or frame.selectedRoleType == "consume" then
        table.insert(menuItems, {text = "Consume Check", value = "consume", label = "Consume Check"})
      end
      
      -- Only show Custom Module if one doesn't already exist (or this is the custom module)
      if not hasCustomModule or frame.selectedRoleType == "custom" then
        table.insert(menuItems, {text = "Custom Module", value = "custom", label = "Custom Module"})
      end
      
      -- Show menu
      local menuFrame = CreateFrame("Frame", nil, UIParent)
      menuFrame:SetWidth(150)
      menuFrame:SetHeight(table.getn(menuItems) * 20 + 10)
      menuFrame:SetPoint("TOPLEFT", roleTypeBtn, "BOTTOMLEFT", 0, 0)
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
      
      -- Close menu when clicking outside
      menuFrame:SetScript("OnHide", function()
        this:SetParent(nil)
      end)
      
      -- Create menu item buttons
      for i, item in ipairs(menuItems) do
        local btn = CreateFrame("Button", nil, menuFrame)
        btn:SetWidth(144)
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
        
        -- Capture variables for closure
        local capturedValue = item.value
        local capturedLabel = item.label
        
        btn:SetScript("OnEnter", function()
          bg:Show()
        end)
        
        btn:SetScript("OnLeave", function()
          bg:Hide()
        end)
        
        btn:SetScript("OnClick", function()
          frame.selectedRoleType = capturedValue
          roleTypeBtn:SetText(capturedLabel)
          if frame.UpdateRoleTypeVisibility then
            frame.UpdateRoleTypeVisibility()
          end
          menuFrame:Hide()
        end)
      end
      
      -- Auto-hide after short delay when mouse leaves
      menuFrame:SetScript("OnUpdate", function()
        if not MouseIsOver(menuFrame) and not MouseIsOver(roleTypeBtn) then
          menuFrame:Hide()
        end
      end)
      
      frame.currentRoleTypeMenu = menuFrame
    end)
    
    -- Role Name Label
    local nameLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameLabel:SetPoint("TOPLEFT", roleTypeLabel, "BOTTOMLEFT", 0, -10)
    nameLabel:SetText("Role Name:")
    frame.nameLabel = nameLabel
    
    -- Role Name EditBox
    local nameEditBox = CreateFrame("EditBox", nil, frame)
    nameEditBox:SetWidth(250)
    nameEditBox:SetHeight(20)
    nameEditBox:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 5, -5)
    nameEditBox:SetBackdrop({
      bgFile = "Interface/Tooltips/UI-Tooltip-Background",
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
      tile = true,
      tileSize = 16,
      edgeSize = 8,
      insets = {left = 2, right = 2, top = 2, bottom = 2}
    })
    nameEditBox:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
    nameEditBox:SetFontObject("GameFontHighlight")
    nameEditBox:SetAutoFocus(false)
    nameEditBox:SetMaxLetters(50)
    nameEditBox:SetScript("OnEscapePressed", function() this:ClearFocus() end)
    frame.nameEditBox = nameEditBox
    
    -- Link Role Checkbox
    local linkRoleLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    linkRoleLabel:SetPoint("TOPLEFT", nameEditBox, "BOTTOMLEFT", -5, -15)
    linkRoleLabel:SetText("Link Role:")
    frame.linkRoleLabel = linkRoleLabel
    
    local linkRoleCheckbox = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    linkRoleCheckbox:SetPoint("LEFT", linkRoleLabel, "RIGHT", 5, 0)
    linkRoleCheckbox:SetWidth(24)
    linkRoleCheckbox:SetHeight(24)
    frame.linkRoleCheckbox = linkRoleCheckbox
    
    -- Invert Fill Order Checkbox (next to Link Role)
    local invertFillOrderLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    invertFillOrderLabel:SetPoint("LEFT", linkRoleCheckbox, "RIGHT", 10, 0)
    invertFillOrderLabel:SetText("Invert Fill Order:")
    frame.invertFillOrderLabel = invertFillOrderLabel
    
    local invertFillOrderCheckbox = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    invertFillOrderCheckbox:SetPoint("LEFT", invertFillOrderLabel, "RIGHT", 5, 0)
    invertFillOrderCheckbox:SetWidth(24)
    invertFillOrderCheckbox:SetHeight(24)
    frame.invertFillOrderCheckbox = invertFillOrderCheckbox
    
    -- Raid Icons Checkbox
    local raidIconsLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    raidIconsLabel:SetPoint("TOPLEFT", linkRoleLabel, "BOTTOMLEFT", 0, -10)
    raidIconsLabel:SetText("Show Raid Icons:")
    
    local raidIconsCheckbox = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    raidIconsCheckbox:SetPoint("LEFT", raidIconsLabel, "RIGHT", 5, 0)
    raidIconsCheckbox:SetWidth(24)
    raidIconsCheckbox:SetHeight(24)
    frame.raidIconsCheckbox = raidIconsCheckbox
    
    -- Show Assignment Checkbox
    local showAssignmentLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    showAssignmentLabel:SetPoint("TOPLEFT", raidIconsLabel, "BOTTOMLEFT", 0, -10)
    showAssignmentLabel:SetText("Show Assignment:")
    
    local showAssignmentCheckbox = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    showAssignmentCheckbox:SetPoint("LEFT", showAssignmentLabel, "RIGHT", 5, 0)
    showAssignmentCheckbox:SetWidth(24)
    showAssignmentCheckbox:SetHeight(24)
    frame.showAssignmentCheckbox = showAssignmentCheckbox
    
    -- Mark Player Checkbox
    local markPlayerLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    markPlayerLabel:SetPoint("LEFT", showAssignmentCheckbox, "RIGHT", 10, 0)
    markPlayerLabel:SetText("Mark Player:")
    
    local markPlayerCheckbox = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    markPlayerCheckbox:SetPoint("LEFT", markPlayerLabel, "RIGHT", 5, 0)
    markPlayerCheckbox:SetWidth(24)
    markPlayerCheckbox:SetHeight(24)
    frame.markPlayerCheckbox = markPlayerCheckbox
    
    -- Allow Other Roles Checkbox
    local allowOtherRolesLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    allowOtherRolesLabel:SetPoint("LEFT", raidIconsCheckbox, "RIGHT", 10, 0)
    allowOtherRolesLabel:SetText("Allow Other Roles:")
    
    local allowOtherRolesCheckbox = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    allowOtherRolesCheckbox:SetPoint("LEFT", allowOtherRolesLabel, "RIGHT", 5, 0)
    allowOtherRolesCheckbox:SetWidth(24)
    allowOtherRolesCheckbox:SetHeight(24)
    frame.allowOtherRolesCheckbox = allowOtherRolesCheckbox
    
    -- Player/Consume Count Label
    local countLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    countLabel:SetPoint("TOPLEFT", showAssignmentLabel, "BOTTOMLEFT", 0, -15)
    countLabel:SetText("Player Count:")
    frame.countLabel = countLabel
    frame.raidIconsLabel = raidIconsLabel
    frame.showAssignmentLabel = showAssignmentLabel
    frame.markPlayerLabel = markPlayerLabel
    frame.allowOtherRolesLabel = allowOtherRolesLabel
    
    -- Player Count EditBox
    local countEditBox = CreateFrame("EditBox", nil, frame)
    countEditBox:SetWidth(60)
    countEditBox:SetHeight(20)
    countEditBox:SetPoint("LEFT", countLabel, "RIGHT", 10, 0)
    countEditBox:SetBackdrop({
      bgFile = "Interface/Tooltips/UI-Tooltip-Background",
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
      tile = true,
      tileSize = 16,
      edgeSize = 8,
      insets = {left = 2, right = 2, top = 2, bottom = 2}
    })
    countEditBox:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
    countEditBox:SetFontObject("GameFontHighlight")
    countEditBox:SetAutoFocus(false)
    countEditBox:SetMaxLetters(2)
    countEditBox:SetNumeric(true)
    countEditBox:SetScript("OnEscapePressed", function() this:ClearFocus() end)
    frame.countEditBox = countEditBox
    
    -- Role/Classes Label (text changes based on consume check)
    local rolesLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    rolesLabel:SetPoint("TOPLEFT", countLabel, "BOTTOMLEFT", 0, -15)
    rolesLabel:SetText("Default Role:")
    frame.rolesLabel = rolesLabel
    
    -- Default Role checkboxes (Tank/Healers/Melee/Ranged)
    local tanksCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    tanksCheck:SetPoint("TOPLEFT", rolesLabel, "BOTTOMLEFT", 10, -5)
    tanksCheck:SetWidth(24)
    tanksCheck:SetHeight(24)
    local tanksLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    tanksLabel:SetPoint("LEFT", tanksCheck, "RIGHT", 5, 0)
    tanksLabel:SetText("Tanks")
    frame.tanksCheck = tanksCheck
    frame.tanksLabel = tanksLabel
    
    local healersCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    healersCheck:SetPoint("TOPLEFT", tanksCheck, "BOTTOMLEFT", 0, -5)
    healersCheck:SetWidth(24)
    healersCheck:SetHeight(24)
    local healersLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    healersLabel:SetPoint("LEFT", healersCheck, "RIGHT", 5, 0)
    healersLabel:SetText("Healers")
    frame.healersCheck = healersCheck
    frame.healersLabel = healersLabel
    
    local meleeCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    meleeCheck:SetPoint("TOPLEFT", healersCheck, "BOTTOMLEFT", 0, -5)
    meleeCheck:SetWidth(24)
    meleeCheck:SetHeight(24)
    local meleeLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    meleeLabel:SetPoint("LEFT", meleeCheck, "RIGHT", 5, 0)
    meleeLabel:SetText("Melee")
    frame.meleeCheck = meleeCheck
    frame.meleeLabel = meleeLabel
    
    local rangedCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    rangedCheck:SetPoint("TOPLEFT", meleeCheck, "BOTTOMLEFT", 0, -5)
    rangedCheck:SetWidth(24)
    rangedCheck:SetHeight(24)
    local rangedLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    rangedLabel:SetPoint("LEFT", rangedCheck, "RIGHT", 5, 0)
    rangedLabel:SetText("Ranged")
    frame.rangedCheck = rangedCheck
    frame.rangedLabel = rangedLabel
    
    frame.defaultRoleChecks = {tanksCheck, healersCheck, meleeCheck, rangedCheck}
    frame.defaultRoleLabels = {tanksLabel, healersLabel, meleeLabel, rangedLabel}
    
    -- Make default role checkboxes behave like radio buttons (only one can be selected)
    local function SetupRoleRadioButton(checkButton, otherChecks)
      checkButton:SetScript("OnClick", function()
        if this:GetChecked() then
          -- Uncheck all other role checkboxes
          for _, otherCheck in ipairs(otherChecks) do
            if otherCheck ~= this then
              otherCheck:SetChecked(false)
            end
          end
        end
      end)
    end
    
    SetupRoleRadioButton(tanksCheck, frame.defaultRoleChecks)
    SetupRoleRadioButton(healersCheck, frame.defaultRoleChecks)
    SetupRoleRadioButton(meleeCheck, frame.defaultRoleChecks)
    SetupRoleRadioButton(rangedCheck, frame.defaultRoleChecks)
    
    -- All checkbox
    local allCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    allCheck:SetPoint("TOPLEFT", rolesLabel, "BOTTOMLEFT", 10, -5)
    allCheck:SetWidth(24)
    allCheck:SetHeight(24)
    local allLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    allLabel:SetPoint("LEFT", allCheck, "RIGHT", 5, 0)
    allLabel:SetText("All")
    frame.allCheck = allCheck
    frame.allLabel = allLabel
    
    -- Class checkboxes - Column 1
    local warriorCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    warriorCheck:SetPoint("TOPLEFT", allCheck, "BOTTOMLEFT", 0, -5)
    warriorCheck:SetWidth(24)
    warriorCheck:SetHeight(24)
    local warriorLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    warriorLabel:SetPoint("LEFT", warriorCheck, "RIGHT", 5, 0)
    warriorLabel:SetText("Warrior")
    frame.warriorCheck = warriorCheck
    frame.warriorLabel = warriorLabel
    
    local rogueCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    rogueCheck:SetPoint("TOPLEFT", warriorCheck, "BOTTOMLEFT", 0, -5)
    rogueCheck:SetWidth(24)
    rogueCheck:SetHeight(24)
    local rogueLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    rogueLabel:SetPoint("LEFT", rogueCheck, "RIGHT", 5, 0)
    rogueLabel:SetText("Rogue")
    frame.rogueCheck = rogueCheck
    frame.rogueLabel = rogueLabel
    
    local hunterCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    hunterCheck:SetPoint("TOPLEFT", rogueCheck, "BOTTOMLEFT", 0, -5)
    hunterCheck:SetWidth(24)
    hunterCheck:SetHeight(24)
    local hunterLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hunterLabel:SetPoint("LEFT", hunterCheck, "RIGHT", 5, 0)
    hunterLabel:SetText("Hunter")
    frame.hunterCheck = hunterCheck
    frame.hunterLabel = hunterLabel
    
    -- Class checkboxes - Column 2
    local paladinCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    paladinCheck:SetPoint("LEFT", allCheck, "LEFT", 100, 0)
    paladinCheck:SetWidth(24)
    paladinCheck:SetHeight(24)
    local paladinLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    paladinLabel:SetPoint("LEFT", paladinCheck, "RIGHT", 5, 0)
    paladinLabel:SetText("Paladin")
    frame.paladinCheck = paladinCheck
    frame.paladinLabel = paladinLabel
    
    local priestCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    priestCheck:SetPoint("TOPLEFT", paladinCheck, "BOTTOMLEFT", 0, -5)
    priestCheck:SetWidth(24)
    priestCheck:SetHeight(24)
    local priestLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    priestLabel:SetPoint("LEFT", priestCheck, "RIGHT", 5, 0)
    priestLabel:SetText("Priest")
    frame.priestCheck = priestCheck
    frame.priestLabel = priestLabel
    
    local shamanCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    shamanCheck:SetPoint("TOPLEFT", priestCheck, "BOTTOMLEFT", 0, -5)
    shamanCheck:SetWidth(24)
    shamanCheck:SetHeight(24)
    local shamanLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    shamanLabel:SetPoint("LEFT", shamanCheck, "RIGHT", 5, 0)
    shamanLabel:SetText("Shaman")
    frame.shamanCheck = shamanCheck
    frame.shamanLabel = shamanLabel
    
    local druidCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    druidCheck:SetPoint("TOPLEFT", shamanCheck, "BOTTOMLEFT", 0, -5)
    druidCheck:SetWidth(24)
    druidCheck:SetHeight(24)
    local druidLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    druidLabel:SetPoint("LEFT", druidCheck, "RIGHT", 5, 0)
    druidLabel:SetText("Druid")
    frame.druidCheck = druidCheck
    frame.druidLabel = druidLabel
    
    -- Class checkboxes - Column 3
    local mageCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    mageCheck:SetPoint("LEFT", paladinCheck, "LEFT", 100, 0)
    mageCheck:SetWidth(24)
    mageCheck:SetHeight(24)
    local mageLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    mageLabel:SetPoint("LEFT", mageCheck, "RIGHT", 5, 0)
    mageLabel:SetText("Mage")
    frame.mageCheck = mageCheck
    frame.mageLabel = mageLabel
    
    local warlockCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    warlockCheck:SetPoint("TOPLEFT", mageCheck, "BOTTOMLEFT", 0, -5)
    warlockCheck:SetWidth(24)
    warlockCheck:SetHeight(24)
    local warlockLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    warlockLabel:SetPoint("LEFT", warlockCheck, "RIGHT", 5, 0)
    warlockLabel:SetText("Warlock")
    frame.warlockCheck = warlockCheck
    frame.warlockLabel = warlockLabel
    
    -- Store all class checks for easy iteration
    frame.classChecks = {
      allCheck, warriorCheck, rogueCheck, hunterCheck,
      paladinCheck, priestCheck, shamanCheck, druidCheck,
      mageCheck, warlockCheck
    }
    
    -- Store class labels for visibility toggling
    frame.classLabels = {
      frame.allLabel, frame.warriorLabel, frame.rogueLabel, frame.hunterLabel,
      frame.paladinLabel, frame.priestLabel, frame.shamanLabel, frame.druidLabel,
      frame.mageLabel, frame.warlockLabel
    }
    
    -- Initially hide class checkboxes and labels (show default roles by default)
    allCheck:Hide()
    frame.allLabel:Hide()
    for _, check in ipairs(frame.classChecks) do
      if check ~= allCheck then
        check:Hide()
      end
    end
    for _, label in ipairs(frame.classLabels) do
      if label ~= frame.allLabel then
        label:Hide()
      end
    end
    
    -- All checkbox behavior: uncheck all others when checked
    allCheck:SetScript("OnClick", function()
      if this:GetChecked() then
        for _, check in ipairs(frame.classChecks) do
          if check ~= allCheck then
            check:SetChecked(false)
            check:Disable()
          end
        end
      else
        for _, check in ipairs(frame.classChecks) do
          if check ~= allCheck then
            check:Enable()
          end
        end
      end
    end)
    
    -- Individual class checkboxes: uncheck All when any is checked
    local classOnlyChecks = {
      warriorCheck, rogueCheck, hunterCheck,
      paladinCheck, priestCheck, shamanCheck, druidCheck,
      mageCheck, warlockCheck
    }
    for _, check in ipairs(classOnlyChecks) do
      check:SetScript("OnClick", function()
        if this:GetChecked() then
          allCheck:SetChecked(false)
          for _, otherCheck in ipairs(frame.classChecks) do
            if otherCheck ~= allCheck then
              otherCheck:Enable()
            end
          end
        end
      end)
    end
    
    -- Custom Module UI - Two list boxes side by side
    local customModuleContainer = CreateFrame("Frame", nil, frame)
    customModuleContainer:SetPoint("TOPLEFT", roleTypeLabel, "BOTTOMLEFT", 0, -10)
    customModuleContainer:SetWidth(320)
    customModuleContainer:SetHeight(220)
    frame.customModuleContainer = customModuleContainer
    
    -- Left list box (Selected Items)
    local leftListLabel = customModuleContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    leftListLabel:SetPoint("TOPLEFT", customModuleContainer, "TOPLEFT", 0, 0)
    leftListLabel:SetText("Selected:")
    frame.leftListLabel = leftListLabel
    
    local leftListOuter, leftListScroll, leftListChild, leftListBar, leftListWidth = OGRH.CreateStyledScrollList(customModuleContainer, 155, 190)
    leftListOuter:SetPoint("TOPLEFT", leftListLabel, "BOTTOMLEFT", 0, -5)
    frame.leftListOuter = leftListOuter
    frame.leftListScroll = leftListScroll
    frame.leftListChild = leftListChild
    frame.leftListBar = leftListBar
    
    -- Right list box (Available Items)
    local rightListLabel = customModuleContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    rightListLabel:SetPoint("TOPLEFT", customModuleContainer, "TOPLEFT", 165, 0)
    rightListLabel:SetText("Available:")
    frame.rightListLabel = rightListLabel
    
    local rightListOuter, rightListScroll, rightListChild, rightListBar, rightListWidth = OGRH.CreateStyledScrollList(customModuleContainer, 155, 190)
    rightListOuter:SetPoint("TOPLEFT", rightListLabel, "BOTTOMLEFT", 0, -5)
    frame.rightListOuter = rightListOuter
    frame.rightListScroll = rightListScroll
    frame.rightListChild = rightListChild
    frame.rightListBar = rightListBar
    
    -- Store selected modules list
    frame.selectedModules = {}
    
    -- Function to populate the module lists
    local function PopulateModuleLists()
      -- Clear existing items
      local child = frame.leftListChild
      local children = { child:GetChildren() }
      for _, c in ipairs(children) do
        c:Hide()
        c:SetParent(nil)
      end
      
      child = frame.rightListChild
      children = { child:GetChildren() }
      for _, c in ipairs(children) do
        c:Hide()
        c:SetParent(nil)
      end
      
      -- Get all available modules
      local allModules = OGRH.GetAvailableModules and OGRH.GetAvailableModules() or {}
      
      -- Build available list (modules not in selected)
      local availableModules = {}
      for _, module in ipairs(allModules) do
        local isSelected = false
        for _, selectedId in ipairs(frame.selectedModules) do
          if selectedId == module.id then
            isSelected = true
            break
          end
        end
        if not isSelected then
          table.insert(availableModules, module)
        end
      end
      
      -- Populate Selected list (left) - use Button type with standard action buttons
      local yOffset = 0
      local leftContentWidth = 135
      for i, moduleId in ipairs(frame.selectedModules) do
        -- Find module info
        local moduleInfo = nil
        for _, m in ipairs(allModules) do
          if m.id == moduleId then
            moduleInfo = m
            break
          end
        end
        
        if moduleInfo then
          local itemBtn = OGRH.CreateStyledListItem(frame.leftListChild, leftContentWidth, OGRH.LIST_ITEM_HEIGHT, "Button")
          itemBtn:SetPoint("TOPLEFT", frame.leftListChild, "TOPLEFT", 0, -yOffset)
          
          local text = itemBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
          text:SetPoint("LEFT", itemBtn, "LEFT", 5, 0)
          text:SetText(moduleInfo.name)
          text:SetJustifyH("LEFT")
          text:SetWidth(30)
          
          -- Capture variables for closures
          local capturedIdx = i
          local capturedModuleId = moduleId
          
          -- Add standard action buttons (delete, down, up)
          OGRH.AddListItemButtons(
            itemBtn,
            capturedIdx,
            table.getn(frame.selectedModules),
            function()
              -- Move up
              local temp = frame.selectedModules[capturedIdx - 1]
              frame.selectedModules[capturedIdx - 1] = frame.selectedModules[capturedIdx]
              frame.selectedModules[capturedIdx] = temp
              PopulateModuleLists()
            end,
            function()
              -- Move down
              local temp = frame.selectedModules[capturedIdx + 1]
              frame.selectedModules[capturedIdx + 1] = frame.selectedModules[capturedIdx]
              frame.selectedModules[capturedIdx] = temp
              PopulateModuleLists()
            end,
            function()
              -- Delete
              for j, id in ipairs(frame.selectedModules) do
                if id == capturedModuleId then
                  table.remove(frame.selectedModules, j)
                  break
                end
              end
              PopulateModuleLists()
            end
          )
          
          yOffset = yOffset + (OGRH.LIST_ITEM_HEIGHT + OGRH.LIST_ITEM_SPACING)
        end
      end
      
      -- Update left scroll child height
      frame.leftListChild:SetHeight(math.max(yOffset, 190))
      
      -- Populate Available list (right) - use Button type for clickability
      yOffset = 0
      local rightContentWidth = 145
      for _, module in ipairs(availableModules) do
        local itemBtn = OGRH.CreateStyledListItem(frame.rightListChild, rightContentWidth, OGRH.LIST_ITEM_HEIGHT, "Button")
        itemBtn:SetPoint("TOPLEFT", frame.rightListChild, "TOPLEFT", 0, -yOffset)
        
        local text = itemBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetPoint("CENTER", itemBtn, "CENTER", 0, 0)
        text:SetText(module.name)
        
        -- Click to add to selected
        local capturedId = module.id
        local capturedModule = module
        itemBtn:SetScript("OnClick", function()
          table.insert(frame.selectedModules, capturedId)
          PopulateModuleLists()
        end)
        
        -- Show tooltip with description on hover
        local originalOnEnter = itemBtn:GetScript("OnEnter")
        itemBtn:SetScript("OnEnter", function()
          if originalOnEnter then originalOnEnter() end
          if capturedModule.description and capturedModule.description ~= "" then
            GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
            GameTooltip:SetText(capturedModule.description)
            GameTooltip:Show()
          end
        end)
        
        local originalOnLeave = itemBtn:GetScript("OnLeave")
        itemBtn:SetScript("OnLeave", function()
          if originalOnLeave then originalOnLeave() end
          GameTooltip:Hide()
        end)
        
        yOffset = yOffset + (OGRH.LIST_ITEM_HEIGHT + OGRH.LIST_ITEM_SPACING)
      end
      
      -- Update right scroll child height
      frame.rightListChild:SetHeight(math.max(yOffset, 190))
    end
    
    frame.PopulateModuleLists = PopulateModuleLists
    
    -- Initially hide custom module UI
    customModuleContainer:Hide()
    
    -- Save Button
    local saveBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    saveBtn:SetWidth(80)
    saveBtn:SetHeight(24)
    saveBtn:SetPoint("BOTTOMRIGHT", frame, "BOTTOM", -5, 15)
    saveBtn:SetText("Save")
    frame.saveBtn = saveBtn
    
    -- Cancel Button
    local cancelBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    cancelBtn:SetWidth(80)
    cancelBtn:SetHeight(24)
    cancelBtn:SetPoint("BOTTOMLEFT", frame, "BOTTOM", 5, 15)
    cancelBtn:SetText("Cancel")
    cancelBtn:SetScript("OnClick", function()
      frame:Hide()
    end)
    
    OGRH_EditRoleFrame = frame
  end
  
  local frame = OGRH_EditRoleFrame
  
  -- Function to update visibility based on role type
  local function UpdateRoleTypeVisibility()
    local roleType = frame.selectedRoleType or "raider"
    local isConsumeCheck = (roleType == "consume")
    local isCustomModule = (roleType == "custom")
    
    -- Hide/show elements based on consume check
    if isConsumeCheck then
      -- Set name to "Consumes" and hide name controls
      frame.nameEditBox:SetText("Consumes")
      frame.nameLabel:Hide()
      frame.nameEditBox:Hide()
      
      -- Hide standard role options
      frame.invertFillOrderLabel:Hide()
      frame.invertFillOrderCheckbox:Hide()
      frame.linkRoleLabel:Hide()
      frame.linkRoleCheckbox:Hide()
      frame.raidIconsLabel:Hide()
      frame.raidIconsCheckbox:Hide()
      frame.showAssignmentLabel:Hide()
      frame.showAssignmentCheckbox:Hide()
      frame.markPlayerLabel:Hide()
      frame.markPlayerCheckbox:Hide()
      frame.allowOtherRolesLabel:Hide()
      frame.allowOtherRolesCheckbox:Hide()
      
      -- Reanchor count label to role type label (since other labels are hidden)
      frame.countLabel:ClearAllPoints()
      frame.countLabel:SetPoint("TOPLEFT", frame.roleTypeLabel, "BOTTOMLEFT", 0, -40)
      frame.countLabel:SetText("Consume Count:")
      
      -- Hide role label and show class checkboxes
      frame.rolesLabel:Hide()
      for _, check in ipairs(frame.defaultRoleChecks) do
        check:Hide()
      end
      for _, label in ipairs(frame.defaultRoleLabels) do
        label:Hide()
      end
      
      -- Reanchor All checkbox to count label instead of rolesLabel
      frame.allCheck:ClearAllPoints()
      frame.allCheck:SetPoint("TOPLEFT", frame.countLabel, "BOTTOMLEFT", 10, -15)
      frame.allCheck:Show()
      frame.allLabel:Show()
      
      for _, check in ipairs(frame.classChecks) do
        if check ~= frame.allCheck then
          check:Show()
        end
      end
      for _, label in ipairs(frame.classLabels) do
        if label ~= frame.allLabel then
          label:Show()
        end
      end
      
      -- Hide custom module UI
      frame.customModuleContainer:Hide()
      
      -- Resize dialog to fit (smaller height)
      frame:SetHeight(280)
    elseif isCustomModule then
      -- Custom Module mode
      -- Set fixed name and hide name controls
      frame.nameEditBox:SetText("Custom Module")
      frame.nameLabel:Hide()
      frame.nameEditBox:Hide()
      
      -- Hide standard role options
      frame.invertFillOrderLabel:Hide()
      frame.invertFillOrderCheckbox:Hide()
      frame.linkRoleLabel:Hide()
      frame.linkRoleCheckbox:Hide()
      frame.raidIconsLabel:Hide()
      frame.raidIconsCheckbox:Hide()
      frame.showAssignmentLabel:Hide()
      frame.showAssignmentCheckbox:Hide()
      frame.markPlayerLabel:Hide()
      frame.markPlayerCheckbox:Hide()
      frame.allowOtherRolesLabel:Hide()
      frame.allowOtherRolesCheckbox:Hide()
      frame.countLabel:Hide()
      frame.countEditBox:Hide()
      frame.rolesLabel:Hide()
      
      -- Hide default role checkboxes
      for _, check in ipairs(frame.defaultRoleChecks) do
        check:Hide()
      end
      for _, label in ipairs(frame.defaultRoleLabels) do
        label:Hide()
      end
      
      -- Hide class checkboxes
      frame.allCheck:Hide()
      frame.allLabel:Hide()
      for _, check in ipairs(frame.classChecks) do
        check:Hide()
      end
      for _, label in ipairs(frame.classLabels) do
        label:Hide()
      end
      
      -- Show custom module UI
      frame.customModuleContainer:Show()
      
      -- Populate module lists
      if frame.PopulateModuleLists then
        frame.PopulateModuleLists()
      end
      
      -- Resize dialog for custom module
      frame:SetHeight(330)
    else
      -- Raider Roles mode (default)
      -- Show name controls
      frame.nameLabel:Show()
      frame.nameEditBox:Show()
      
      -- Show standard role options
      frame.invertFillOrderLabel:Show()
      frame.invertFillOrderCheckbox:Show()
      frame.linkRoleLabel:Show()
      frame.linkRoleCheckbox:Show()
      frame.raidIconsLabel:Show()
      frame.raidIconsCheckbox:Show()
      frame.showAssignmentLabel:Show()
      frame.showAssignmentCheckbox:Show()
      frame.markPlayerLabel:Show()
      frame.markPlayerCheckbox:Show()
      frame.allowOtherRolesLabel:Show()
      frame.allowOtherRolesCheckbox:Show()
      
      -- Reanchor count label back to showAssignmentLabel
      frame.countLabel:ClearAllPoints()
      frame.countLabel:SetPoint("TOPLEFT", frame.showAssignmentLabel, "BOTTOMLEFT", 0, -15)
      frame.countLabel:SetText("Player Count:")
      frame.countLabel:Show()
      frame.countEditBox:Show()
      
      -- Show role label and default role checkboxes
      frame.rolesLabel:SetText("Default Role:")
      frame.rolesLabel:Show()
      
      -- Hide All checkbox (restore anchor for consistency but keep hidden)
      frame.allCheck:ClearAllPoints()
      frame.allCheck:SetPoint("TOPLEFT", frame.rolesLabel, "BOTTOMLEFT", 10, -5)
      frame.allCheck:Hide()
      frame.allLabel:Hide()
      
      for _, check in ipairs(frame.defaultRoleChecks) do
        check:Show()
      end
      for _, label in ipairs(frame.defaultRoleLabels) do
        label:Show()
      end
      for _, check in ipairs(frame.classChecks) do
        if check ~= frame.allCheck then
          check:Hide()
        end
      end
      for _, label in ipairs(frame.classLabels) do
        if label ~= frame.allLabel then
          label:Hide()
        end
      end
      
      -- Hide custom module UI
      frame.customModuleContainer:Hide()
      
      -- Resize dialog back to full height
      frame:SetHeight(380)
    end
  end
  
  -- Store function for external access
  frame.UpdateRoleTypeVisibility = UpdateRoleTypeVisibility
  
  -- Store current context for validation
  frame.currentColumnRoles = columnRoles
  frame.currentRoleIndex = roleIndex
  
  -- Set role type based on role data
  if roleData.isConsumeCheck then
    frame.selectedRoleType = "consume"
    frame.roleTypeBtn:SetText("Consume Check")
  elseif roleData.roleType == "custom" then
    frame.selectedRoleType = "custom"
    frame.roleTypeBtn:SetText("Custom Module")
  else
    frame.selectedRoleType = "raider"
    frame.roleTypeBtn:SetText("Raider Roles")
  end
  
  frame.nameEditBox:SetText(roleData.name or "")
  frame.invertFillOrderCheckbox:SetChecked(roleData.invertFillOrder or false)
  frame.linkRoleCheckbox:SetChecked(roleData.linkRole or false)
  frame.raidIconsCheckbox:SetChecked(roleData.showRaidIcons or false)
  frame.showAssignmentCheckbox:SetChecked(roleData.showAssignment or false)
  frame.markPlayerCheckbox:SetChecked(roleData.markPlayer or false)
  frame.allowOtherRolesCheckbox:SetChecked(roleData.allowOtherRoles or false)
  frame.countEditBox:SetText(tostring(roleData.slots or 1))
  
  -- Set default role checkboxes
  local defaultRoles = roleData.defaultRoles or {}
  frame.tanksCheck:SetChecked(defaultRoles.tanks or false)
  frame.healersCheck:SetChecked(defaultRoles.healers or false)
  frame.meleeCheck:SetChecked(defaultRoles.melee or false)
  frame.rangedCheck:SetChecked(defaultRoles.ranged or false)
  
  -- Set class checkboxes
  local classes = roleData.classes or {}
  frame.allCheck:SetChecked(classes.all or false)
  frame.warriorCheck:SetChecked(classes.warrior or false)
  frame.rogueCheck:SetChecked(classes.rogue or false)
  frame.hunterCheck:SetChecked(classes.hunter or false)
  frame.paladinCheck:SetChecked(classes.paladin or false)
  frame.priestCheck:SetChecked(classes.priest or false)
  frame.shamanCheck:SetChecked(classes.shaman or false)
  frame.druidCheck:SetChecked(classes.druid or false)
  frame.mageCheck:SetChecked(classes.mage or false)
  frame.warlockCheck:SetChecked(classes.warlock or false)
  
  -- Load selected modules (for custom module type)
  frame.selectedModules = {}
  if roleData.modules then
    for i, moduleId in ipairs(roleData.modules) do
      table.insert(frame.selectedModules, moduleId)
    end
  end
  
  -- Trigger initial visibility update (this will show/hide appropriate checkboxes and populate module lists)
  UpdateRoleTypeVisibility()
  
  -- If "All" is checked, disable other class checkboxes
  if classes.all and roleData.isConsumeCheck then
    for _, check in ipairs(frame.classChecks) do
      if check ~= frame.allCheck then
        check:Disable()
      end
    end
  else
    -- Re-enable class checkboxes if "All" is not checked
    for _, check in ipairs(frame.classChecks) do
      if check ~= frame.allCheck then
        check:Enable()
      end
    end
  end
  
  -- Save button handler
  frame.saveBtn:SetScript("OnClick", function()
    -- Validate consume check limit
    local roleType = frame.selectedRoleType or "raider"
    local isConsumeCheck = (roleType == "consume")
    local isCustomModule = (roleType == "custom")
    
    -- Use the stored current values, not the closure values
    local currentColumnRoles = frame.currentColumnRoles
    local currentRoleIndex = frame.currentRoleIndex
    
    if isConsumeCheck then
      for i, role in ipairs(currentColumnRoles) do
        if i ~= currentRoleIndex and role.isConsumeCheck then
          DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OGRH:|r Only one Consume Check role allowed per encounter.")
          return
        end
      end
    end
    
    if isCustomModule then
      for i, role in ipairs(currentColumnRoles) do
        if i ~= currentRoleIndex and role.isCustomModule then
          DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OGRH:|r Only one Custom Module role allowed per encounter.")
          return
        end
      end
    end
    
    -- Update role data
    roleData.name = frame.nameEditBox:GetText()
    roleData.isConsumeCheck = isConsumeCheck
    roleData.isCustomModule = isCustomModule
    roleData.roleType = isCustomModule and "custom" or nil
    roleData.invertFillOrder = frame.invertFillOrderCheckbox:GetChecked()
    roleData.linkRole = frame.linkRoleCheckbox:GetChecked()
    roleData.showRaidIcons = frame.raidIconsCheckbox:GetChecked()
    roleData.showAssignment = frame.showAssignmentCheckbox:GetChecked()
    roleData.markPlayer = frame.markPlayerCheckbox:GetChecked()
    roleData.allowOtherRoles = frame.allowOtherRolesCheckbox:GetChecked()
    roleData.slots = tonumber(frame.countEditBox:GetText()) or 1
    
    -- Update default roles (for standard roles)
    if not isConsumeCheck then
      if not roleData.defaultRoles then
        roleData.defaultRoles = {}
      end
      roleData.defaultRoles.tanks = frame.tanksCheck:GetChecked()
      roleData.defaultRoles.healers = frame.healersCheck:GetChecked()
      roleData.defaultRoles.melee = frame.meleeCheck:GetChecked()
      roleData.defaultRoles.ranged = frame.rangedCheck:GetChecked()
      
      -- Clear classes for standard roles
      roleData.classes = nil
    end
    
    -- Update classes (for consume checks)
    if isConsumeCheck then
      if not roleData.classes then
        roleData.classes = {}
      end
      roleData.classes.all = frame.allCheck:GetChecked()
      roleData.classes.warrior = frame.warriorCheck:GetChecked()
      roleData.classes.rogue = frame.rogueCheck:GetChecked()
      roleData.classes.hunter = frame.hunterCheck:GetChecked()
      roleData.classes.paladin = frame.paladinCheck:GetChecked()
      roleData.classes.priest = frame.priestCheck:GetChecked()
      roleData.classes.shaman = frame.shamanCheck:GetChecked()
      roleData.classes.druid = frame.druidCheck:GetChecked()
      roleData.classes.mage = frame.mageCheck:GetChecked()
      roleData.classes.warlock = frame.warlockCheck:GetChecked()
      
      -- Clear defaultRoles for consume checks
      roleData.defaultRoles = nil
    end
    
    -- Update modules (for custom module type)
    if isCustomModule then
      roleData.modules = {}
      for i, moduleId in ipairs(frame.selectedModules) do
        table.insert(roleData.modules, moduleId)
      end
      
      -- Clear defaultRoles and classes for custom modules
      roleData.defaultRoles = nil
      roleData.classes = nil
    end
    
    -- Refresh the roles list
    if refreshCallback then
      refreshCallback()
    end
    
    frame:Hide()
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OGRH:|r Role updated")
  end)
  
  frame:Show()
end

-- Function to show consume selection dialog
function OGRH.ShowConsumeSelectionDialog(raidName, encounterName, roleIndex, slotIndex)
  -- Create or reuse dialog
  if not OGRH_ConsumeSelectionDialog then
    local dialog = CreateFrame("Frame", "OGRH_ConsumeSelectionDialog", UIParent)
    dialog:SetWidth(350)
    dialog:SetHeight(300)
    dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    dialog:SetFrameStrata("FULLSCREEN_DIALOG")
    dialog:SetBackdrop({
      bgFile = "Interface/Tooltips/UI-Tooltip-Background",
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
      tile = true,
      tileSize = 16,
      edgeSize = 16,
      insets = {left = 4, right = 4, top = 4, bottom = 4}
    })
    dialog:SetBackdropColor(0, 0, 0, 0.95)
    dialog:EnableMouse(true)
    dialog:SetMovable(true)
    dialog:RegisterForDrag("LeftButton")
    dialog:SetScript("OnDragStart", function() dialog:StartMoving() end)
    dialog:SetScript("OnDragStop", function() dialog:StopMovingOrSizing() end)
    
    -- Register ESC key handler
    OGRH.MakeFrameCloseOnEscape(dialog, "OGRH_ConsumeSelectionDialog")
    
    -- Title
    local title = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", dialog, "TOP", 0, -10)
    title:SetText("Select Consume")
    
    -- Allow alternate consume checkbox
    local allowAltLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    allowAltLabel:SetPoint("TOPLEFT", dialog, "TOPLEFT", 15, -40)
    allowAltLabel:SetText("Allow alternate consume:")
    
    local allowAltCheckbox = CreateFrame("CheckButton", nil, dialog, "UICheckButtonTemplate")
    allowAltCheckbox:SetPoint("LEFT", allowAltLabel, "RIGHT", 5, 0)
    allowAltCheckbox:SetWidth(24)
    allowAltCheckbox:SetHeight(24)
    dialog.allowAltCheckbox = allowAltCheckbox
    
    -- Check during Combat checkbox
    local combatCheckLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    combatCheckLabel:SetPoint("TOPLEFT", allowAltLabel, "BOTTOMLEFT", 0, -8)
    combatCheckLabel:SetText("Check during Combat:")
    
    local combatCheckbox = CreateFrame("CheckButton", nil, dialog, "UICheckButtonTemplate")
    combatCheckbox:SetPoint("LEFT", combatCheckLabel, "RIGHT", 5, 0)
    combatCheckbox:SetWidth(24)
    combatCheckbox:SetHeight(24)
    dialog.combatCheckbox = combatCheckbox
    
    -- Scroll frame for consume list
    local scrollFrame = CreateFrame("ScrollFrame", nil, dialog)
    scrollFrame:SetPoint("TOPLEFT", combatCheckLabel, "BOTTOMLEFT", 0, -10)
    scrollFrame:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -30, 45)
    
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(300)
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)
    dialog.scrollChild = scrollChild
    
    -- Scrollbar
    local scrollBar = CreateFrame("Slider", nil, scrollFrame)
    scrollBar:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", -10, -115)
    scrollBar:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -10, 55)
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
    scrollBar:SetScript("OnValueChanged", function()
      scrollFrame:SetVerticalScroll(this:GetValue())
    end)
    dialog.scrollBar = scrollBar
    
    -- Mouse wheel scrolling
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function()
      local delta = arg1
      local current = scrollBar:GetValue()
      local minVal, maxVal = scrollBar:GetMinMaxValues()
      if delta > 0 then
        scrollBar:SetValue(math.max(minVal, current - 20))
      else
        scrollBar:SetValue(math.min(maxVal, current + 20))
      end
    end)
    
    -- OK button
    local okBtn = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    okBtn:SetWidth(80)
    okBtn:SetHeight(24)
    okBtn:SetPoint("BOTTOM", dialog, "BOTTOM", -45, 15)
    okBtn:SetText("OK")
    dialog.okBtn = okBtn
    
    -- Cancel button
    local cancelBtn = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    cancelBtn:SetWidth(80)
    cancelBtn:SetHeight(24)
    cancelBtn:SetPoint("LEFT", okBtn, "RIGHT", 10, 0)
    cancelBtn:SetText("Cancel")
    cancelBtn:SetScript("OnClick", function()
      dialog:Hide()
    end)
    
    OGRH_ConsumeSelectionDialog = dialog
  end
  
  local dialog = OGRH_ConsumeSelectionDialog
  
  -- Store parameters for OK button
  dialog.raidName = raidName
  dialog.encounterName = encounterName
  dialog.roleIndex = roleIndex
  dialog.slotIndex = slotIndex
  dialog.selectedConsume = nil
  
  -- Load existing consume data for this slot
  local existingConsumeData = nil
  if OGRH_SV.encounterMgmt and OGRH_SV.encounterMgmt.roles and
     OGRH_SV.encounterMgmt.roles[raidName] and
     OGRH_SV.encounterMgmt.roles[raidName][encounterName] then
    local encounterRoles = OGRH_SV.encounterMgmt.roles[raidName][encounterName]
    local column1 = encounterRoles.column1 or {}
    local column2 = encounterRoles.column2 or {}
    
    local role = nil
    if roleIndex <= table.getn(column1) then
      role = column1[roleIndex]
    else
      role = column2[roleIndex - table.getn(column1)]
    end
    
    if role and role.consumes and role.consumes[slotIndex] then
      existingConsumeData = role.consumes[slotIndex]
      dialog.selectedConsume = existingConsumeData
    end
  end
  
  -- Set checkbox state from existing data
  if existingConsumeData and existingConsumeData.allowAlternate then
    dialog.allowAltCheckbox:SetChecked(true)
  else
    dialog.allowAltCheckbox:SetChecked(false)
  end
  
  if existingConsumeData and existingConsumeData.checkDuringCombat then
    dialog.combatCheckbox:SetChecked(true)
  else
    dialog.combatCheckbox:SetChecked(false)
  end
  
  -- Setup OK button handler
  dialog.okBtn:SetScript("OnClick", function()
    if not dialog.selectedConsume then
      DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OGRH:|r Please select a consume first.")
      return
    end
    
    -- Get the encounter data (stored in encounterMgmt.roles)
    OGRH.EnsureSV()
    if not OGRH_SV.encounterMgmt then
      OGRH_SV.encounterMgmt = {raids = {}, encounters = {}, roles = {}}
    end
    if not OGRH_SV.encounterMgmt.roles then
      OGRH_SV.encounterMgmt.roles = {}
    end
    if not OGRH_SV.encounterMgmt.roles[dialog.raidName] then
      OGRH_SV.encounterMgmt.roles[dialog.raidName] = {}
    end
    if not OGRH_SV.encounterMgmt.roles[dialog.raidName][dialog.encounterName] then
      OGRH_SV.encounterMgmt.roles[dialog.raidName][dialog.encounterName] = {column1 = {}, column2 = {}}
    end
    
    local encounterRoles = OGRH_SV.encounterMgmt.roles[dialog.raidName][dialog.encounterName]
    local column1 = encounterRoles.column1 or {}
    local column2 = encounterRoles.column2 or {}
    
    -- Find the role based on roleIndex (1-based across both columns)
    local role = nil
    if dialog.roleIndex <= table.getn(column1) then
      role = column1[dialog.roleIndex]
    else
      role = column2[dialog.roleIndex - table.getn(column1)]
    end
    
    if not role then
      DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OGRH:|r Role not found.")
      dialog:Hide()
      return
    end
    
    -- Initialize consumes array if needed
    if not role.consumes then
      role.consumes = {}
    end
    
    -- Save consume selection
    local allowAlt = dialog.allowAltCheckbox:GetChecked()
    local checkCombat = dialog.combatCheckbox:GetChecked()
    role.consumes[dialog.slotIndex] = {
      primaryId = dialog.selectedConsume.primaryId,
      primaryName = dialog.selectedConsume.primaryName,
      secondaryId = dialog.selectedConsume.secondaryId,
      secondaryName = dialog.selectedConsume.secondaryName,
      allowAlternate = allowAlt,
      checkDuringCombat = checkCombat
    }
    
    -- Refresh the Encounter Planning UI
    if OGRH_EncounterFrame and OGRH_EncounterFrame.RefreshRoleContainers then
      OGRH_EncounterFrame.RefreshRoleContainers()
    end
    
    dialog:Hide()
  end)
  
  -- Clear existing buttons
  if dialog.consumeButtons then
    for _, btn in ipairs(dialog.consumeButtons) do
      btn:Hide()
      btn:SetParent(nil)
    end
  end
  dialog.consumeButtons = {}
  
  -- Load consumes from saved variables
  OGRH.EnsureSV()
  if not OGRH_SV.consumes or table.getn(OGRH_SV.consumes) == 0 then
    local noConsumesText = dialog.scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    noConsumesText:SetPoint("CENTER", dialog.scrollChild, "CENTER", 0, 0)
    noConsumesText:SetText("|cff888888No consumes configured\nConfigure in Consumes menu|r")
    noConsumesText:SetJustifyH("CENTER")
    table.insert(dialog.consumeButtons, {placeholder = noConsumesText})
    dialog:Show()
    return
  end
  
  local yOffset = -5
  for i, consumeData in ipairs(OGRH_SV.consumes) do
    local consumeBtn = CreateFrame("Button", nil, dialog.scrollChild)
    consumeBtn:SetWidth(290)
    consumeBtn:SetHeight(20)
    consumeBtn:SetPoint("TOPLEFT", dialog.scrollChild, "TOPLEFT", 5, yOffset)
    
    local bg = consumeBtn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    bg:SetVertexColor(0.2, 0.2, 0.2, 0.5)
    consumeBtn.bg = bg
    
    local highlight = consumeBtn:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetTexture("Interface\\Buttons\\WHITE8X8")
    highlight:SetVertexColor(0.3, 0.3, 0.3, 0.5)
    
    local consumeText = consumeBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    consumeText:SetPoint("LEFT", consumeBtn, "LEFT", 5, 0)
    consumeText:SetText(consumeData.primaryName or "Unknown Item")
    consumeText:SetWidth(280)
    consumeText:SetJustifyH("LEFT")
    
    local capturedConsumeData = consumeData
    local capturedBg = bg
    consumeBtn:SetScript("OnClick", function()
      -- Store selected consume (don't close dialog yet)
      dialog.selectedConsume = capturedConsumeData
      
      -- Update visual feedback on all buttons
      for _, otherBtn in ipairs(dialog.consumeButtons) do
        if otherBtn.bg then
          otherBtn.bg:SetVertexColor(0.2, 0.2, 0.2, 0.5)
        end
      end
      capturedBg:SetVertexColor(0.3, 0.5, 0.3, 0.7)
    end)
    
    -- Highlight if this is the currently selected consume
    if dialog.selectedConsume and 
       dialog.selectedConsume.primaryId == consumeData.primaryId and
       dialog.selectedConsume.primaryName == consumeData.primaryName then
      bg:SetVertexColor(0.3, 0.5, 0.3, 0.7)
    end
    
    table.insert(dialog.consumeButtons, consumeBtn)
    yOffset = yOffset - 22
  end
  
  -- Update scroll child height
  local contentHeight = math.abs(yOffset) + 5
  dialog.scrollChild:SetHeight(contentHeight)
  
  -- Update scrollbar
  local scrollFrameHeight = dialog.scrollChild:GetParent():GetHeight()
  if contentHeight > scrollFrameHeight then
    dialog.scrollBar:Show()
    dialog.scrollBar:SetMinMaxValues(0, contentHeight - scrollFrameHeight)
    dialog.scrollBar:SetValue(0)
  else
    dialog.scrollBar:Hide()
  end
  
  dialog:Show()
end

-- Initialize SavedVariables when addon loads
InitializeSavedVars()

-- Functions for MainUI encounter navigation
function OGRH.UpdateEncounterNavButton()
  if not OGRH.encounterNav then return end
  
  local btn = OGRH.encounterNav.encounterBtn
  local prevBtn = OGRH.encounterNav.prevEncBtn
  local nextBtn = OGRH.encounterNav.nextEncBtn
  
  -- Always get raid and encounter from main UI saved variables only
  local raidName, encounterName
  if OGRH_SV and OGRH_SV.ui then
    raidName = OGRH_SV.ui.selectedRaid
    encounterName = OGRH_SV.ui.selectedEncounter
  end
  
  -- Load modules for the selected encounter (main UI only)
  if OGRH.LoadModulesForRole and OGRH.UnloadAllModules and raidName and encounterName then
    -- Get roles for this encounter
    if OGRH_SV.encounterMgmt and OGRH_SV.encounterMgmt.roles and 
       OGRH_SV.encounterMgmt.roles[raidName] and 
       OGRH_SV.encounterMgmt.roles[raidName][encounterName] then
      local rolesData = OGRH_SV.encounterMgmt.roles[raidName][encounterName]
      
      -- Collect all modules from custom module roles
      local allModules = {}
      if rolesData.column1 then
        for _, role in ipairs(rolesData.column1) do
          if role.isCustomModule and role.modules then
            for _, moduleId in ipairs(role.modules) do
              table.insert(allModules, moduleId)
            end
          end
        end
      end
      if rolesData.column2 then
        for _, role in ipairs(rolesData.column2) do
          if role.isCustomModule and role.modules then
            for _, moduleId in ipairs(role.modules) do
              table.insert(allModules, moduleId)
            end
          end
        end
      end
      
      -- Load the modules
      if table.getn(allModules) > 0 then
        OGRH.LoadModulesForRole(allModules)
      else
        OGRH.UnloadAllModules()
      end
    else
      OGRH.UnloadAllModules()
    end
  end
  
  if not raidName then
    btn:SetText("Select Raid")
    prevBtn:Disable()
    nextBtn:Disable()
    return
  end
  
  if encounterName then
    -- Truncate encounter name if needed to fit
    local displayName = encounterName
    if string.len(displayName) > 15 then
      displayName = string.sub(displayName, 1, 12) .. "..."
    end
    btn:SetText(displayName)
  else
    btn:SetText("No Encounter")
  end
  
  -- Enable/disable prev/next buttons
  if OGRH_SV.encounterMgmt and OGRH_SV.encounterMgmt.encounters and 
     OGRH_SV.encounterMgmt.encounters[raidName] then
    local encounters = OGRH_SV.encounterMgmt.encounters[raidName]
    local currentIndex = nil
    
    for i = 1, table.getn(encounters) do
      if encounters[i] == encounterName then
        currentIndex = i
        break
      end
    end
    
    if currentIndex then
      if currentIndex > 1 then
        prevBtn:Enable()
      else
        prevBtn:Disable()
      end
      
      if currentIndex < table.getn(encounters) then
        nextBtn:Enable()
      else
        nextBtn:Disable()
      end
    else
      prevBtn:Disable()
      nextBtn:Disable()
    end
  else
    prevBtn:Disable()
    nextBtn:Disable()
  end
end

function OGRH.NavigateToPreviousEncounter()
  -- Check authorization - must be raid lead, assistant, or designated raid admin
  if not OGRH.CanNavigateEncounter or not OGRH.CanNavigateEncounter() then
    OGRH.Msg("Only the Raid Leader, Assistants, or Raid Admin can change the selected encounter.")
    return
  end
  
  -- Get current encounter from main UI selection
  local raidName, currentEncounter = OGRH.GetCurrentEncounter()
  
  if not raidName or not currentEncounter then
    return
  end
  
  if OGRH_SV.encounterMgmt and OGRH_SV.encounterMgmt.encounters and 
     OGRH_SV.encounterMgmt.encounters[raidName] then
    local encounters = OGRH_SV.encounterMgmt.encounters[raidName]
    
    for i = 1, table.getn(encounters) do
      if encounters[i] == currentEncounter and i > 1 then
        -- Update main UI saved variables only
        OGRH_SV.ui.selectedEncounter = encounters[i - 1]
        
        -- Do NOT update planning window frame
        -- Planning window maintains its own independent selection
        
        OGRH.UpdateEncounterNavButton()
        
        -- Update consume monitor if enabled
        if OGRH.ShowConsumeMonitor then
          OGRH.ShowConsumeMonitor()
        end
        
        -- Broadcast encounter change
        OGRH.BroadcastEncounterSelection(raidName, encounters[i - 1])
        break
      end
    end
  end
end

function OGRH.NavigateToNextEncounter()
  -- Check authorization - must be raid lead, assistant, or designated raid admin
  if not OGRH.CanNavigateEncounter or not OGRH.CanNavigateEncounter() then
    OGRH.Msg("Only the Raid Leader, Assistants, or Raid Admin can change the selected encounter.")
    return
  end
  
  -- Get current encounter from main UI selection
  local raidName, currentEncounter = OGRH.GetCurrentEncounter()
  
  if not raidName or not currentEncounter then
    return
  end
  
  if OGRH_SV.encounterMgmt and OGRH_SV.encounterMgmt.encounters and 
     OGRH_SV.encounterMgmt.encounters[raidName] then
    local encounters = OGRH_SV.encounterMgmt.encounters[raidName]
    
    for i = 1, table.getn(encounters) do
      if encounters[i] == currentEncounter and i < table.getn(encounters) then
        -- Update main UI saved variables only
        OGRH_SV.ui.selectedEncounter = encounters[i + 1]
        
        -- Do NOT update planning window frame
        -- Planning window maintains its own independent selection
        
        OGRH.UpdateEncounterNavButton()
        
        -- Update consume monitor if enabled
        if OGRH.ShowConsumeMonitor then
          OGRH.ShowConsumeMonitor()
        end
        
        -- Broadcast encounter change
        OGRH.BroadcastEncounterSelection(raidName, encounters[i + 1])
        break
      end
    end
  end
end

function OGRH.ShowAnnouncementTooltip(anchorFrame)
  if not OGRH_EncounterFrame or not OGRH_EncounterFrame.selectedRaid or 
     not OGRH_EncounterFrame.selectedEncounter then
    return
  end
  
  -- Check if there's a ReplaceTags function stored on the frame
  if not OGRH_EncounterFrame.ReplaceTags then
    return
  end
  
  -- Get announcement text lines
  if not OGRH_SV.encounterAnnouncements or 
     not OGRH_SV.encounterAnnouncements[OGRH_EncounterFrame.selectedRaid] or
     not OGRH_SV.encounterAnnouncements[OGRH_EncounterFrame.selectedRaid][OGRH_EncounterFrame.selectedEncounter] then
    return "No announcement configured"
  end
  
  -- Get role data
  local orderedRoles = {}
  if OGRH_SV.encounterRoles and 
     OGRH_SV.encounterRoles[OGRH_EncounterFrame.selectedRaid] and 
     OGRH_SV.encounterRoles[OGRH_EncounterFrame.selectedRaid][OGRH_EncounterFrame.selectedEncounter] then
    orderedRoles = OGRH_SV.encounterRoles[OGRH_EncounterFrame.selectedRaid][OGRH_EncounterFrame.selectedEncounter]
  end
  
  local assignments = {}
  if OGRH_SV.encounterAssignments and
     OGRH_SV.encounterAssignments[OGRH_EncounterFrame.selectedRaid] and
     OGRH_SV.encounterAssignments[OGRH_EncounterFrame.selectedRaid][OGRH_EncounterFrame.selectedEncounter] then
    assignments = OGRH_SV.encounterAssignments[OGRH_EncounterFrame.selectedRaid][OGRH_EncounterFrame.selectedEncounter]
  end
  
  local raidMarks = {}
  if OGRH_SV.encounterRaidMarks and
     OGRH_SV.encounterRaidMarks[OGRH_EncounterFrame.selectedRaid] and
     OGRH_SV.encounterRaidMarks[OGRH_EncounterFrame.selectedRaid][OGRH_EncounterFrame.selectedEncounter] then
    raidMarks = OGRH_SV.encounterRaidMarks[OGRH_EncounterFrame.selectedRaid][OGRH_EncounterFrame.selectedEncounter]
  end
  
  local assignmentNumbers = {}
  if OGRH_SV.encounterAssignmentNumbers and
     OGRH_SV.encounterAssignmentNumbers[OGRH_EncounterFrame.selectedRaid] and
     OGRH_SV.encounterAssignmentNumbers[OGRH_EncounterFrame.selectedRaid][OGRH_EncounterFrame.selectedEncounter] then
    assignmentNumbers = OGRH_SV.encounterAssignmentNumbers[OGRH_EncounterFrame.selectedRaid][OGRH_EncounterFrame.selectedEncounter]
  end
  
  -- Get announcement text
  if not OGRH_SV.encounterAnnouncements or 
     not OGRH_SV.encounterAnnouncements[OGRH_EncounterFrame.selectedRaid] or
     not OGRH_SV.encounterAnnouncements[OGRH_EncounterFrame.selectedRaid][OGRH_EncounterFrame.selectedEncounter] then
    return
  end
  
  -- Get role data for tag processing (must match announce button logic)
  local orderedRoles = {}
  local roles = OGRH_SV.encounterMgmt.roles
  if roles and roles[OGRH_EncounterFrame.selectedRaid] and 
     roles[OGRH_EncounterFrame.selectedRaid][OGRH_EncounterFrame.selectedEncounter] then
    local encounterRoles = roles[OGRH_EncounterFrame.selectedRaid][OGRH_EncounterFrame.selectedEncounter]
    local column1 = encounterRoles.column1 or {}
    local column2 = encounterRoles.column2 or {}
    
    -- Build ordered list of roles
    for i = 1, table.getn(column1) do
      table.insert(orderedRoles, column1[i])
    end
    for i = 1, table.getn(column2) do
      table.insert(orderedRoles, column2[i])
    end
  end
  
  local assignments = {}
  if OGRH_SV.encounterAssignments and
     OGRH_SV.encounterAssignments[OGRH_EncounterFrame.selectedRaid] and
     OGRH_SV.encounterAssignments[OGRH_EncounterFrame.selectedRaid][OGRH_EncounterFrame.selectedEncounter] then
    assignments = OGRH_SV.encounterAssignments[OGRH_EncounterFrame.selectedRaid][OGRH_EncounterFrame.selectedEncounter]
  end
  
  -- Note: This is a duplicate of raidMarks loading above and can be removed
  local raidMarks = {}
  if OGRH_SV.encounterRaidMarks and
     OGRH_SV.encounterRaidMarks[OGRH_EncounterFrame.selectedRaid] and
     OGRH_SV.encounterRaidMarks[OGRH_EncounterFrame.selectedRaid][OGRH_EncounterFrame.selectedEncounter] then
    raidMarks = OGRH_SV.encounterRaidMarks[OGRH_EncounterFrame.selectedRaid][OGRH_EncounterFrame.selectedEncounter]
  end
  
  local assignmentNumbers = {}
  if OGRH_SV.encounterAssignmentNumbers and
     OGRH_SV.encounterAssignmentNumbers[OGRH_EncounterFrame.selectedRaid] and
     OGRH_SV.encounterAssignmentNumbers[OGRH_EncounterFrame.selectedRaid][OGRH_EncounterFrame.selectedEncounter] then
    assignmentNumbers = OGRH_SV.encounterAssignmentNumbers[OGRH_EncounterFrame.selectedRaid][OGRH_EncounterFrame.selectedEncounter]
  end
  
  local announcementData = OGRH_SV.encounterAnnouncements[OGRH_EncounterFrame.selectedRaid][OGRH_EncounterFrame.selectedEncounter]
  
  -- Process announcement lines exactly as they would be sent to chat
  GameTooltip:SetOwner(anchorFrame, "ANCHOR_RIGHT")
  GameTooltip:ClearLines()
  
  local hasLines = false
  for i = 1, 20 do
    local lineText = announcementData[i]
    if lineText and lineText ~= "" then
      local processedText = OGRH_EncounterFrame.ReplaceTags(lineText, orderedRoles, assignments, raidMarks, assignmentNumbers)
      
      if processedText and processedText ~= "" then
        if not hasLines then
          GameTooltip:AddLine(processedText, 1, 1, 1, 1)
          hasLines = true
        else
          GameTooltip:AddLine(processedText, 1, 1, 1, 1)
        end
      end
    end
  end
  
  if hasLines then
    GameTooltip:Show()
  end
end

function OGRH.PrepareEncounterAnnouncement()
  -- Get current encounter from frame or saved variables
  local selectedRaid, selectedEncounter = OGRH.GetCurrentEncounter()
  
  if not selectedRaid or not selectedEncounter then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OGRH:|r No encounter selected")
    return
  end
  
  -- Check if in raid
  if GetNumRaidMembers() == 0 then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OGRH:|r You must be in a raid to announce.")
    return
  end
  
  -- Broadcast sync to ReadHelper users
  if OGRH.SendReadHelperSyncData then
    OGRH.SendReadHelperSyncData(nil)
  end
  
  -- Get announcement text from saved variables
  if not OGRH_SV.encounterAnnouncements or 
     not OGRH_SV.encounterAnnouncements[selectedRaid] or
     not OGRH_SV.encounterAnnouncements[selectedRaid][selectedEncounter] then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OGRH:|r No announcement text configured for this encounter.")
    return
  end
  
  local announcementData = OGRH_SV.encounterAnnouncements[selectedRaid][selectedEncounter]
  
  -- Get role configuration
  local roles = OGRH_SV.encounterMgmt.roles
  if not roles or not roles[selectedRaid] or not roles[selectedRaid][selectedEncounter] then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OGRH:|r No roles configured for this encounter.")
    return
  end
  
  local encounterRoles = roles[selectedRaid][selectedEncounter]
  local column1 = encounterRoles.column1 or {}
  local column2 = encounterRoles.column2 or {}
  
  -- Build ordered list of roles for tag replacement
  local orderedRoles = {}
  for i = 1, table.getn(column1) do
    table.insert(orderedRoles, column1[i])
  end
  for i = 1, table.getn(column2) do
    table.insert(orderedRoles, column2[i])
  end
  
  -- Get assignments
  local assignments = {}
  if OGRH_SV.encounterAssignments and 
     OGRH_SV.encounterAssignments[selectedRaid] and
     OGRH_SV.encounterAssignments[selectedRaid][selectedEncounter] then
    assignments = OGRH_SV.encounterAssignments[selectedRaid][selectedEncounter]
  end
  
  -- Get raid marks
  local raidMarks = {}
  if OGRH_SV.encounterRaidMarks and
     OGRH_SV.encounterRaidMarks[selectedRaid] and
     OGRH_SV.encounterRaidMarks[selectedRaid][selectedEncounter] then
    raidMarks = OGRH_SV.encounterRaidMarks[selectedRaid][selectedEncounter]
  end
  
  -- Get assignment numbers
  local assignmentNumbers = {}
  if OGRH_SV.encounterAssignmentNumbers and
     OGRH_SV.encounterAssignmentNumbers[selectedRaid] and
     OGRH_SV.encounterAssignmentNumbers[selectedRaid][selectedEncounter] then
    assignmentNumbers = OGRH_SV.encounterAssignmentNumbers[selectedRaid][selectedEncounter]
  end
  
  -- Process announcement lines using global ReplaceTags function
  local announcementLines = {}
  for i = 1, table.getn(announcementData) do
    local lineText = announcementData[i]
    if lineText and lineText ~= "" then
      local processedText = OGRH.ReplaceTags(lineText, orderedRoles, assignments, raidMarks, assignmentNumbers)
      table.insert(announcementLines, processedText)
    end
  end
  
  -- Send announcements to raid chat
  if table.getn(announcementLines) == 0 then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OGRH:|r No announcement text to send.")
    return
  end
  
  -- Send announcement using SendAnnouncement (which checks for raid warning permission)
  if OGRH.SendAnnouncement then
    OGRH.SendAnnouncement(announcementLines)
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OGRH:|r Announcement sent to raid chat (" .. table.getn(announcementLines) .. " lines).")
  else
    -- Fallback if SendAnnouncement not loaded
    for _, line in ipairs(announcementLines) do
      SendChatMessage(line, "RAID")
    end
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OGRH:|r Announcement sent to raid chat (" .. table.getn(announcementLines) .. " lines).")
  end
end

function OGRH.OpenEncounterPlanning()
  -- Close SR+ Validation window if it's open
  if OGRH_SRValidationFrame and OGRH_SRValidationFrame:IsVisible() then
    OGRH_SRValidationFrame:Hide()
  end
  
  -- Close Share window if it's open
  if OGRH_ShareFrame and OGRH_ShareFrame:IsVisible() then
    OGRH_ShareFrame:Hide()
  end
  
  -- Get current raid/encounter from Main UI
  local currentRaid, currentEncounter = OGRH.GetCurrentEncounter()
  
  if not OGRH_EncounterFrame then
    OGRH.ShowEncounterWindow()
    -- After frame creation, set to current Main UI selection if available
    if OGRH_EncounterFrame and currentRaid and currentEncounter then
      OGRH_EncounterFrame.selectedRaid = currentRaid
      OGRH_EncounterFrame.selectedEncounter = currentEncounter
      -- Refresh to show the correct selection
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
    return
  end
  
  -- Frame already exists - update to current Main UI selection
  if currentRaid and currentEncounter then
    OGRH_EncounterFrame.selectedRaid = currentRaid
    OGRH_EncounterFrame.selectedEncounter = currentEncounter
    -- Refresh to show the correct selection
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
  
  OGRH_EncounterFrame:Show()
end

function OGRH.ShowEncounterRaidMenu(anchorBtn)
  if not OGRH_EncounterRaidMenu then
    local menu = CreateFrame("Frame", "OGRH_EncounterRaidMenu", UIParent)
    menu:SetWidth(140)
    menu:SetHeight(100)
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
    menu:Hide()
    
    -- Close menu when clicking outside
    menu:SetScript("OnShow", function()
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
    
    menu.buttons = {}
    
    menu.Rebuild = function()
      -- Clear existing buttons
      for _, btn in ipairs(menu.buttons) do
        btn:Hide()
        btn:SetParent(nil)
      end
      menu.buttons = {}
      
      if not OGRH_SV.encounterMgmt or not OGRH_SV.encounterMgmt.raids then
        return
      end
      
      local raids = OGRH_SV.encounterMgmt.raids
      local yOffset = -5
      local itemHeight = 18
      local itemSpacing = 2
      
      for i = 1, table.getn(raids) do
        local raidName = raids[i]
        local btn = CreateFrame("Button", nil, menu)
        btn:SetWidth(130)
        btn:SetHeight(itemHeight)
        btn:SetPoint("TOPLEFT", menu, "TOPLEFT", 5, yOffset)
        
        -- Background highlight
        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetTexture("Interface\\Buttons\\WHITE8X8")
        bg:SetVertexColor(0.2, 0.2, 0.2, 0)
        btn.bg = bg
        
        -- Text
        local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("CENTER", btn, "CENTER", 0, 0)
        fs:SetText(raidName)
        fs:SetTextColor(1, 1, 1)
        btn.fs = fs
        
        -- Highlight on hover
        btn:SetScript("OnEnter", function()
          bg:SetVertexColor(0.3, 0.3, 0.3, 0.5)
        end)
        
        btn:SetScript("OnLeave", function()
          bg:SetVertexColor(0.2, 0.2, 0.2, 0)
        end)
        
        local capturedRaid = raidName
        btn:SetScript("OnClick", function()
          menu:Hide()
          
          -- Check authorization - must be raid lead, assistant, or designated raid admin
          if not OGRH.CanNavigateEncounter or not OGRH.CanNavigateEncounter() then
            OGRH.Msg("Only the Raid Leader, Assistants, or Raid Admin can change the selected encounter.")
            return
          end
          
          -- Select first encounter if available
          local firstEncounter = nil
          if OGRH_SV.encounterMgmt.encounters and 
             OGRH_SV.encounterMgmt.encounters[capturedRaid] and
             table.getn(OGRH_SV.encounterMgmt.encounters[capturedRaid]) > 0 then
            firstEncounter = OGRH_SV.encounterMgmt.encounters[capturedRaid][1]
          end
          
          -- Update Main UI state
          OGRH.EnsureSV()
          OGRH_SV.ui.selectedRaid = capturedRaid
          OGRH_SV.ui.selectedEncounter = firstEncounter
          
          -- Broadcast encounter change to raid
          if firstEncounter then
            OGRH.BroadcastEncounterSelection(capturedRaid, firstEncounter)
          end
          
          -- Update navigation button and consume monitor
          OGRH.UpdateEncounterNavButton()
          if OGRH.ShowConsumeMonitor then
            OGRH.ShowConsumeMonitor()
          end
        end)
        
        table.insert(menu.buttons, btn)
        yOffset = yOffset - (itemHeight + itemSpacing)
      end
      
      menu:SetHeight(math.max(50, math.abs(yOffset) + 10))
    end
  end
  
  local menu = OGRH_EncounterRaidMenu
  
  if menu:IsVisible() then
    menu:Hide()
  else
    menu.Rebuild()
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", anchorBtn, "BOTTOMLEFT", 0, -2)
    menu:Show()
  end
end

-- Mark Players from MainUI
function OGRH.MarkPlayersFromMainUI()
  -- Check if in raid
  if GetNumRaidMembers() == 0 then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OGRH:|r You must be in a raid to mark players.")
    return
  end
  
  -- Get selected raid and encounter from frame or saved variables
  local selectedRaid, selectedEncounter = OGRH.GetCurrentEncounter()
  
  if not selectedRaid or not selectedEncounter then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OGRH:|r Please select a raid and encounter first.")
    return
  end
  
  -- Get role configuration
  local roles = OGRH_SV.encounterMgmt.roles
  if not roles or not roles[selectedRaid] or not roles[selectedRaid][selectedEncounter] then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OGRH:|r No roles configured for this encounter.")
    return
  end
  
  local encounterRoles = roles[selectedRaid][selectedEncounter]
  local column1 = encounterRoles.column1 or {}
  local column2 = encounterRoles.column2 or {}
  
  -- Build ordered list of all roles (column1 first, then column2)
  local allRoles = {}
  
  for i = 1, table.getn(column1) do
    table.insert(allRoles, {role = column1[i], roleIndex = table.getn(allRoles) + 1})
  end
  for i = 1, table.getn(column2) do
    table.insert(allRoles, {role = column2[i], roleIndex = table.getn(allRoles) + 1})
  end
  
  -- Check if any role has markPlayer enabled
  local hasMarkPlayerEnabled = false
  for _, roleData in ipairs(allRoles) do
    if roleData.role.markPlayer then
      hasMarkPlayerEnabled = true
      break
    end
  end
  
  -- If no roles have markPlayer enabled, try AutoMarker
  if not hasMarkPlayerEnabled then
    local amHandler = SlashCmdList["AUTOMARKER"]
    if type(amHandler) ~= "function" then
      DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OGRH:|r No roles configured to mark players and AutoMarker addon not found.")
      return
    end
    
    -- Call AutoMarker with /am mark command
    amHandler("mark")
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OGRH:|r AutoMarker invoked.")
    return
  end
  
  -- Get assignments
  local assignments = {}
  if OGRH_SV.encounterAssignments and 
     OGRH_SV.encounterAssignments[selectedRaid] and
     OGRH_SV.encounterAssignments[selectedRaid][selectedEncounter] then
    assignments = OGRH_SV.encounterAssignments[selectedRaid][selectedEncounter]
  end
  
  -- Get raid marks
  local raidMarks = {}
  if OGRH_SV.encounterRaidMarks and
     OGRH_SV.encounterRaidMarks[selectedRaid] and
     OGRH_SV.encounterRaidMarks[selectedRaid][selectedEncounter] then
    raidMarks = OGRH_SV.encounterRaidMarks[selectedRaid][selectedEncounter]
  end
  
  -- Clear all raid marks first
  for j = 1, GetNumRaidMembers() do
    SetRaidTarget("raid"..j, 0)
  end
  
  -- Iterate through roles and apply marks
  local markedCount = 0
  
  for _, roleData in ipairs(allRoles) do
    local role = roleData.role
    local roleIndex = roleData.roleIndex
    
    -- Only process roles with markPlayer enabled
    if role.markPlayer then
      -- Get assigned players for this role
      local assignedPlayers = assignments[roleIndex] or {}
      local roleMarks = raidMarks[roleIndex] or {}
      
      -- Iterate through slots
      for slotIndex = 1, table.getn(assignedPlayers) do
        local playerName = assignedPlayers[slotIndex]
        local markIndex = roleMarks[slotIndex]
        
        if playerName and markIndex and markIndex ~= 0 then
          -- Find player in raid and apply mark
          for j = 1, GetNumRaidMembers() do
            local name = GetRaidRosterInfo(j)
            if name == playerName then
              -- Set raid target icon (1-8)
              SetRaidTarget("raid"..j, markIndex)
              markedCount = markedCount + 1
              break
            end
          end
        end
      end
    end
  end
  
  DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OGRH:|r Marked " .. markedCount .. " players.")
end

-- Initialize encounter frame on VARIABLES_LOADED to ensure ReplaceTags is available
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("VARIABLES_LOADED")
initFrame:SetScript("OnEvent", function()
  -- Create the frame if it doesn't exist and we have encounter data
  if not OGRH_EncounterFrame and OGRH_SV and OGRH_SV.encounterMgmt and 
     OGRH_SV.encounterMgmt.raids and table.getn(OGRH_SV.encounterMgmt.raids) > 0 then
    -- Create frame hidden so ReplaceTags function is available
    OGRH.ShowEncounterWindow()
    if OGRH_EncounterFrame then
      OGRH_EncounterFrame:Hide()
    end
  end
end)

DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OGRH:|r Encounter Management loaded")
