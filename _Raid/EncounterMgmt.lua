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

-- Upgrade old data structure to new nested structure
function OGRH.UpgradeEncounterDataStructure()
  OGRH.EnsureSV()
  local encounterMgmt = OGRH.SVM.Get("encounterMgmt")
  if not encounterMgmt or not encounterMgmt.raids then
    return false
  end
  
  local raids = encounterMgmt.raids
  if table.getn(raids) == 0 then
    return false
  end
  
  -- Check if already using new structure
  local firstRaid = raids[1]
  if type(firstRaid) == "table" and firstRaid.name then
    return false -- Already upgraded
  end
  
  -- Upgrade from old structure (array of raid name strings) to new structure (array of raid objects)
  local newRaids = {}
  
  for i = 1, table.getn(raids) do
    local raidName = raids[i]
    local raidObj = {
      name = raidName,
      encounters = {},
      advancedSettings = {
        consumeTracking = {
          enabled = false,
          readyThreshold = 85,
          requiredFlaskRoles = {
            ["Tanks"] = false,
            ["Healers"] = false,
            ["Melee"] = false,
            ["Ranged"] = false,
          }
        }
      }
    }
    
    -- Migrate encounters for this raid
    local encounters = encounterMgmt.encounters
    if encounters and encounters[raidName] then
      local encounterNames = encounters[raidName]
      for j = 1, table.getn(encounterNames) do
        local encounterName = encounterNames[j]
        local encounterObj = {
          name = encounterName,
          advancedSettings = {
            bigwigs = {
              enabled = false,
              encounterId = ""
            },
            consumeTracking = {
              enabled = nil,
              readyThreshold = nil,
              requiredFlaskRoles = {}
            }
          }
        }
        table.insert(raidObj.encounters, encounterObj)
      end
    end
    
    table.insert(newRaids, raidObj)
  end
  
  -- Replace old structure with new
  OGRH.SVM.SetPath("encounterMgmt.raids", newRaids, {
    syncLevel = "MANUAL",
    componentType = "structure"
  })
  OGRH.SVM.SetPath("encounterMgmt.encounters", nil, {
    syncLevel = "MANUAL",
    componentType = "structure"
  })
  
  OGRH.Msg("Encounter data structure upgraded successfully!")
  return true
end

-- Auto-assign players from RollFor data
function OGRH.AutoAssignRollForPlayers(frame, rollForPlayers)
  if not frame or not rollForPlayers then return 0 end
  
  -- Get role configuration from v2 schema (roles nested in encounters)
  if not frame.selectedRaidIdx or not frame.selectedEncounterIdx then
    return 0
  end
  
  local allRaids = OGRH.SVM.GetPath('encounterMgmt.raids')
  if not allRaids or 
     not allRaids[frame.selectedRaidIdx] or 
     not allRaids[frame.selectedRaidIdx].encounters or
     not allRaids[frame.selectedRaidIdx].encounters[frame.selectedEncounterIdx] then
    return 0
  end
  
  local encounter = allRaids[frame.selectedRaidIdx].encounters[frame.selectedEncounterIdx]
  if not encounter.roles then
    return 0
  end
  
  -- Build column1 and column2 from roles array
  local column1 = {}
  local column2 = {}
  for i = 1, table.getn(encounter.roles) do
    local role = encounter.roles[i]
    if role.column == 1 then
      table.insert(column1, role)
    elseif role.column == 2 then
      table.insert(column2, role)
    end
  end
  
  -- Build complete roles list using stable roleId
  local allRoles = {}
  for i = 1, table.getn(column1) do
    table.insert(allRoles, {role = column1[i], roleIndex = column1[i].roleId or (table.getn(allRoles) + 1)})
  end
  for i = 1, table.getn(column2) do
    table.insert(allRoles, {role = column2[i], roleIndex = column2[i].roleId or (table.getn(allRoles) + 1)})
  end
  
  -- Map RollFor role to OGRH role bucket (same as Invites module)
  local function MapRollForRole(rollForRole)
    if not rollForRole or rollForRole == "" then return nil end
    
    -- If already in correct format (TANKS/HEALERS/MELEE/RANGED), return as-is
    if rollForRole == "TANKS" or rollForRole == "HEALERS" or rollForRole == "MELEE" or rollForRole == "RANGED" then
      return rollForRole
    end
    
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
  local assignedPlayers = {}  -- Players who can NEVER be reused (from roles without allowOtherRoles)
  local tempAssignedPlayers = {}  -- Players temporarily blocked in passes 1-2, can be reused in pass 3
  local assignmentCount = 0
  local processedRoles = {}
  
  -- Save old assignments for delta sync (to detect clears) - v2 schema: nested in roles
  local oldAssignments = {}
  if encounter.roles then
    for roleIdx = 1, table.getn(encounter.roles) do
      local role = encounter.roles[roleIdx]
      if role.assignedPlayers then
        oldAssignments[roleIdx] = {}
        for slotIdx = 1, table.getn(role.assignedPlayers) do
          if role.assignedPlayers[slotIdx] then
            oldAssignments[roleIdx][slotIdx] = role.assignedPlayers[slotIdx]
          end
        end
      end
    end
  end
  
  -- Clear existing assignments for this encounter - v2 schema: clear within each role
  if encounter.roles then
    for roleIdx = 1, table.getn(encounter.roles) do
      encounter.roles[roleIdx].assignedPlayers = {}
    end
  end
  
  -- Write back cleared assignments
  OGRH.SVM.SetPath('encounterMgmt.raids', allRaids)
  
  -- Build assignments table for tracking (maps roleIdx -> slotIdx -> playerName)
  local assignments = {}
  
  -- Check if any role has both invertFillOrder AND allowOtherRoles
  local needsThreePass = false
  for _, roleData in ipairs(allRoles) do
    if roleData.role.invertFillOrder and roleData.role.allowOtherRoles then
      needsThreePass = true
      break
    end
  end
  
  -- MULTI-PASS ASSIGNMENT:
  -- Standard 2-pass: Pass 1 = class priority, Pass 2 = default roles
  -- Special 3-pass (when any role has invertFillOrder AND allowOtherRoles):
  --   Pass 1 = default roles top-down (no duplicates)
  --   Pass 2 = class priority bottom-up (no duplicates) 
  --   Pass 3 = default roles top-down (allow duplicates to fill remaining)
  
  local maxPasses = needsThreePass and 3 or 2
  for passNum = 1, maxPasses do
    -- Determine pass type
    local classPriorityOnly = false
    local defaultRolesOnly = false
    local allowDuplicates = false
    
    if needsThreePass then
      if passNum == 1 then
        defaultRolesOnly = true  -- Pass 1: default roles only, no duplicates
      elseif passNum == 2 then
        classPriorityOnly = true  -- Pass 2: class priority only, no duplicates
      else
        -- Pass 3: Same as pass 1 (default roles only) but allow duplicates
        defaultRolesOnly = true
        allowDuplicates = true
      end
    else
      classPriorityOnly = (passNum == 1)  -- Standard: Pass 1 = class priority, Pass 2 = default
    end
    processedRoles = {}  -- Reset for each pass
    
    -- Process each role
    for _, roleData in ipairs(allRoles) do
      local role = roleData.role
      local roleIndex = roleData.roleIndex
      
      -- Skip if already processed as part of a linked group in this pass
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
        
        -- Initialize role assignments for all roles in the group (only in pass 1)
        if passNum == 1 then
          for _, rd in ipairs(linkedRoleData) do
            if not assignments[rd.roleIndex] then
              assignments[rd.roleIndex] = {}
            end
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
              OGRH.AutoAssignRollForSlot(currentRole, currentRoleIndex, slotIdx, assignments, rollForPlayers, assignedPlayers, MapRollForRole, classPriorityOnly, defaultRolesOnly, allowDuplicates, passNum, tempAssignedPlayers)
              if assignments[currentRoleIndex][slotIdx] then
                assignmentCount = assignmentCount + 1
              end
            end
          end
        else
          -- SINGLE ROLE: Process each slot sequentially
          local slots = role.slots or 1
          
          -- Determine slot processing order
          local slotOrder = {}
          if role.invertFillOrder and role.allowOtherRoles and classPriorityOnly then
            -- 3-pass mode: Pass 2 (class priority) is bottom-up
            for slotIdx = slots, 1, -1 do
              table.insert(slotOrder, slotIdx)
            end
          else
            -- All other cases: Process slots top-down
            for slotIdx = 1, slots do
              table.insert(slotOrder, slotIdx)
            end
          end
          
          -- Process slots in the determined order
          for _, slotIdx in ipairs(slotOrder) do
            if not assignments[roleIndex][slotIdx] then
              OGRH.AutoAssignRollForSlot(role, roleIndex, slotIdx, assignments, rollForPlayers, assignedPlayers, MapRollForRole, classPriorityOnly, defaultRolesOnly, allowDuplicates, passNum, tempAssignedPlayers, needsThreePass)
              if assignments[roleIndex][slotIdx] then
                assignmentCount = assignmentCount + 1
              end
            end
          end
        end
      end
    end
  end
  
  -- Note: Change tracking now handled automatically by SVM sync levels
  
  -- Write assignments back to v2 schema (nested in roles)
  for roleIdx, roleAssignments in pairs(assignments) do
    if encounter.roles[roleIdx] then
      if not encounter.roles[roleIdx].assignedPlayers then
        encounter.roles[roleIdx].assignedPlayers = {}
      end
      for slotIdx, playerName in pairs(roleAssignments) do
        encounter.roles[roleIdx].assignedPlayers[slotIdx] = playerName
      end
    end
  end
  
  -- Write back to saved variables
  OGRH.SVM.SetPath('encounterMgmt.raids', allRaids)
  
  -- Refresh display
  if frame.RefreshRoleContainers then
    frame.RefreshRoleContainers()
  end
  
  return assignmentCount
end

-- Helper function to assign a single slot from RollFor data
function OGRH.AutoAssignRollForSlot(role, roleIndex, slotIdx, assignments, rollForPlayers, assignedPlayers, MapRollForRole, classPriorityOnly, defaultRolesOnly, allowDuplicates, passNum, tempAssignedPlayers, isThreePassMode)
  local assigned = false
  passNum = passNum or 0  -- Default to 0 if not provided
  tempAssignedPlayers = tempAssignedPlayers or {}  -- Default to empty table if not provided
  isThreePassMode = isThreePassMode or false  -- Default to false if not provided
  
  -- Helper function to count how many times a player has been assigned
  local function GetAssignmentCount(playerName)
    local count = 0
    for _, roleAssignments in pairs(assignments) do
      for _, assignedName in pairs(roleAssignments) do
        if assignedName == playerName then
          count = count + 1
        end
      end
    end
    return count
  end
  
  -- PHASE 1: Try class priority first if configured (skip if defaultRolesOnly)
  if not defaultRolesOnly and role.classPriority and role.classPriority[slotIdx] and table.getn(role.classPriority[slotIdx]) > 0 then
    local priorityList = role.classPriority[slotIdx]
    
    -- Try each class in priority order
    for priorityIndex, className in ipairs(priorityList) do
      -- Build list of players with this class
      local classPlayers = {}
      for _, playerData in ipairs(rollForPlayers) do
        -- Check if player is available
        -- assignedPlayers = permanently blocked (role didn't have allowOtherRoles)
        -- tempAssignedPlayers = temporarily blocked in passes 1-2
        local canUsePlayer = not assignedPlayers[playerData.name]
        if canUsePlayer and not allowDuplicates then
          -- In passes 1-2, also check temporary assignments
          canUsePlayer = not tempAssignedPlayers[playerData.name]
        end
        -- In pass 3, only reuse players who already have assignments
        if canUsePlayer and allowDuplicates then
          canUsePlayer = (GetAssignmentCount(playerData.name) > 0)
        end
        
        if playerData.class and canUsePlayer then
          if string.upper(playerData.class) == string.upper(className) then
            local roleMatches = false
            
            -- Check if this slot/class has specific classPriorityRoles configured (by position index)
            if role.classPriorityRoles and role.classPriorityRoles[slotIdx] and role.classPriorityRoles[slotIdx][priorityIndex] then
              local allowedRoles = role.classPriorityRoles[slotIdx][priorityIndex]
              
              -- Check if ANY checkbox is enabled
              local anyRoleEnabled = allowedRoles.Tanks or allowedRoles.Healers or allowedRoles.Melee or allowedRoles.Ranged
              
              if not anyRoleEnabled then
                -- No checkboxes enabled = accept from any role
                roleMatches = true
              else
                -- Checkboxes enabled - need to match role
                local playerRoleBucket = MapRollForRole(playerData.role)
                if playerRoleBucket and (
                   (playerRoleBucket == "TANKS" and allowedRoles.Tanks) or
                   (playerRoleBucket == "HEALERS" and allowedRoles.Healers) or
                   (playerRoleBucket == "MELEE" and allowedRoles.Melee) or
                   (playerRoleBucket == "RANGED" and allowedRoles.Ranged)) then
                  roleMatches = true
                end
              end
            else
              -- No classPriorityRoles configured for this position = accept any player of this class
              roleMatches = true
            end
            
            if roleMatches then
              table.insert(classPlayers, playerData.name)
            end
          end
        end
      end
      
      -- Sort players to prefer those with fewer assignments (distribute load evenly)
      table.sort(classPlayers, function(a, b)
        local countA = GetAssignmentCount(a)
        local countB = GetAssignmentCount(b)
        if countA ~= countB then
          return countA < countB  -- Prefer players with fewer assignments
        end
        return a < b  -- Alphabetical for consistent results when counts are equal
      end)
      
      -- Assign first available player
      if table.getn(classPlayers) > 0 then
        assignments[roleIndex][slotIdx] = classPlayers[1]
        -- Permanent block: role doesn't allow other roles
        if not role.allowOtherRoles then
          assignedPlayers[classPlayers[1]] = true
        end
        -- Temporary block: we're in pass 1 or 2 (no duplicates allowed yet)
        -- In 3-pass mode: always block in passes 1-2, allow in pass 3
        -- In 2-pass mode: only block if role doesn't allow other roles
        if not allowDuplicates then
          if isThreePassMode or not role.allowOtherRoles then
            tempAssignedPlayers[classPlayers[1]] = true
          end
        end
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
  
  -- PHASE 2: Try defaultRoles if appropriate
  -- Skip if: already assigned, or this is class priority only pass, or no defaultRoles configured
  if not assigned and not classPriorityOnly and role.defaultRoles then
    -- Build list of matching players
    local matchingPlayers = {}
    for _, playerData in ipairs(rollForPlayers) do
      -- Check if player is available
      -- assignedPlayers = permanently blocked (role didn't have allowOtherRoles)
      -- tempAssignedPlayers = temporarily blocked in passes 1-2
      local canUsePlayer = not assignedPlayers[playerData.name]
      if canUsePlayer and not allowDuplicates then
        -- In passes 1-2, also check temporary assignments
        canUsePlayer = not tempAssignedPlayers[playerData.name]
      end
      -- In pass 3, only reuse players who already have assignments
      if canUsePlayer and allowDuplicates then
        canUsePlayer = (GetAssignmentCount(playerData.name) > 0)
      end
      
      if canUsePlayer then
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
          table.insert(matchingPlayers, playerData)
        end
      end
    end
    
    -- Sort players to prefer those with fewer assignments (distribute load evenly)
    table.sort(matchingPlayers, function(a, b)
      local countA = GetAssignmentCount(a.name)
      local countB = GetAssignmentCount(b.name)
      if countA ~= countB then
        return countA < countB  -- Prefer players with fewer assignments
      end
      return a.name < b.name  -- Alphabetical for consistent results when counts are equal
    end)
    
    -- Assign first available player
    if table.getn(matchingPlayers) > 0 then
      local selectedPlayer = matchingPlayers[1]
      assignments[roleIndex][slotIdx] = selectedPlayer.name
      -- Permanent block: role doesn't allow other roles
      if not role.allowOtherRoles then
        assignedPlayers[selectedPlayer.name] = true
      end
      -- Temporary block: we're in pass 1 or 2 (no duplicates allowed yet)
      -- In 3-pass mode: always block in passes 1-2, allow in pass 3
      -- In 2-pass mode: only block if role doesn't allow other roles
      if not allowDuplicates then
        if isThreePassMode or not role.allowOtherRoles then
          tempAssignedPlayers[selectedPlayer.name] = true
        end
      end
      
      -- Update class cache if we have class data
      if selectedPlayer.class and OGRH.UpdatePlayerClass then
        OGRH.UpdatePlayerClass(selectedPlayer.name, selectedPlayer.class)
      end
    end
  end
end

-- Get currently selected encounter for main UI (not planning window)
-- DEPRECATED: Use OGRH.GetCurrentEncounter() in Core.lua instead
function OGRH.GetCurrentEncounter()
  return OGRH.SVM.Get("ui", "selectedRaid"), OGRH.SVM.Get("ui", "selectedEncounter")
end

-- Global ReplaceTags function for announcement processing
-- Migrate old roleDefaults to poolDefaults (one-time migration)
local function MigrateRoleDefaultsToPoolDefaults()
  local roleDefaults = OGRH.SVM.Get("roleDefaults")
  local poolDefaults = OGRH.SVM.Get("poolDefaults")
  if roleDefaults and not poolDefaults then
    OGRH.Msg("|cffff6666[RH-EncounterMgmt]|r Migrating Role Defaults to Pool Defaults...")
    OGRH.SVM.Set("poolDefaults", nil, roleDefaults)
    OGRH.SVM.Set("roleDefaults", nil, nil)
    OGRH.Msg("|cff00ff00[RH-EncounterMgmt]|r Migration complete!")
  end
end

-- Migrate roles to stable IDs (one-time migration)
function OGRH.MigrateRolesToStableIDs()
  local encounterMgmt = OGRH.SVM.Get("encounterMgmt")
  if not encounterMgmt or not encounterMgmt.roles then
    return
  end
  
  local needsMigration = false
  
  -- Check if any roles lack IDs
  for raidName, raidRoles in pairs(encounterMgmt.roles) do
    for encounterName, encounterRoles in pairs(raidRoles) do
      local column1 = encounterRoles.column1 or {}
      local column2 = encounterRoles.column2 or {}
      
      for _, role in ipairs(column1) do
        if not role.roleId then
          needsMigration = true
          break
        end
      end
      for _, role in ipairs(column2) do
        if not role.roleId then
          needsMigration = true
          break
        end
      end
      
      if needsMigration then break end
    end
    if needsMigration then break end
  end
  
  if not needsMigration then return end
  
  OGRH.Msg("|cffff6666[RH-EncounterMgmt]|r Migrating roles to stable IDs...")
  
  -- Assign stable IDs based on current position
  for raidName, raidRoles in pairs(encounterMgmt.roles) do
    for encounterName, encounterRoles in pairs(raidRoles) do
      local column1 = encounterRoles.column1 or {}
      local column2 = encounterRoles.column2 or {}
      
      local roleIdCounter = 1
      
      -- Assign IDs to column1 roles
      for _, role in ipairs(column1) do
        if not role.roleId then
          role.roleId = roleIdCounter
          role.fillOrder = roleIdCounter
        end
        roleIdCounter = roleIdCounter + 1
      end
      
      -- Assign IDs to column2 roles
      for _, role in ipairs(column2) do
        if not role.roleId then
          role.roleId = roleIdCounter
          role.fillOrder = roleIdCounter
        end
        roleIdCounter = roleIdCounter + 1
      end
    end
  end
  
  OGRH.Msg("|cff00ff00[RH-EncounterMgmt]|r Role ID migration complete!")
end

-- Initialize SavedVariables structure
local function InitializeSavedVars()
  -- Run migrations
  MigrateRoleDefaultsToPoolDefaults()
  OGRH.MigrateRolesToStableIDs()
  
  -- Initialize encounterMgmt if missing
  local encounterMgmt = OGRH.SVM.Get("encounterMgmt")
  if not encounterMgmt then
    OGRH.SVM.Set("encounterMgmt", nil, {
      raids = {}
      -- Note: No encounters table - new structure has encounters nested in raids
    })
    encounterMgmt = OGRH.SVM.Get("encounterMgmt")
  end
  
  -- Ensure raids array exists
  if not encounterMgmt.raids then
    OGRH.SVM.SetPath("encounterMgmt.raids", {})
    encounterMgmt = OGRH.SVM.Get("encounterMgmt")
  end
  
  -- Upgrade old structure if found
  if table.getn(encounterMgmt.raids) > 0 then
    local firstRaid = encounterMgmt.raids[1]
    -- Check if using old structure (string) or incomplete new structure (table without 'name' field)
    if type(firstRaid) == "string" or (type(firstRaid) == "table" and not firstRaid.name) then
      OGRH.UpgradeEncounterDataStructure()
    end
  elseif encounterMgmt.encounters then
    -- Has old encounters table but no raids - upgrade
    OGRH.UpgradeEncounterDataStructure()
  end
end

-- Function to show Encounter Planning Window
function OGRH.ShowEncounterPlanning(encounterName)
  OGRH.EnsureSV()
  
  -- Create or show the window
  if not OGRH_EncounterFrame then
    -- Check if encounter data exists before creating frame
    local encounterMgmt = OGRH.SVM.Get("encounterMgmt")
    if not encounterMgmt or 
       not encounterMgmt.raids or 
       table.getn(encounterMgmt.raids) == 0 then
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
    frame:Hide()  -- Start hidden by default
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
    
    -- Export Raid button (top left)
    local exportRaidBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    exportRaidBtn:SetWidth(90)
    exportRaidBtn:SetHeight(24)
    exportRaidBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -10)
    exportRaidBtn:SetText("Export Raid")
    OGRH.StyleButton(exportRaidBtn)
    exportRaidBtn:SetScript("OnClick", function()
      if frame.selectedRaid then
        OGRH.ShowExportRaidWindow(frame.selectedRaid)
      else
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OGRH:|r Please select a raid first.")
      end
    end)
    frame.exportRaidBtn = exportRaidBtn
    
    -- Status label (anchored to top left corner, hidden by default)
    local statusLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    statusLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, -12)
    statusLabel:SetTextColor(0, 1, 0)  -- Green color
    statusLabel:SetText("")
    statusLabel:Hide()
    frame.statusLabel = statusLabel
    
    -- Function to show status message temporarily
    frame.ShowStatus = function(message, duration)
      duration = duration or 10
      statusLabel:SetText(message)
      statusLabel:Show()
      
      -- Cancel any existing timer
      if frame.statusTimer then
        frame.statusTimer = nil
      end
      
      -- Set up timer to hide after duration
      frame.statusTimer = duration
      frame:SetScript("OnUpdate", function()
        if frame.statusTimer then
          frame.statusTimer = frame.statusTimer - arg1
          if frame.statusTimer <= 0 then
            statusLabel:Hide()
            statusLabel:SetText("")
            frame.statusTimer = nil
            frame:SetScript("OnUpdate", nil)
          end
        end
      end)
    end
    
    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    closeBtn:SetWidth(60)
    closeBtn:SetHeight(24)
    closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -10)
    closeBtn:SetText("Close")
    OGRH.StyleButton(closeBtn)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)
    
    -- Edit Structure button (to the left of Close button)
    local editStructureBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    editStructureBtn:SetWidth(95)
    editStructureBtn:SetHeight(24)
    editStructureBtn:SetPoint("RIGHT", closeBtn, "LEFT", -5, 0)
    editStructureBtn:SetText("Edit Structure")
    OGRH.StyleButton(editStructureBtn)
    frame.editStructureBtn = editStructureBtn
    
    editStructureBtn:SetScript("OnEnter", function()
      GameTooltip:SetOwner(this, "ANCHOR_TOP")
      GameTooltip:SetText("Edit Structure", 1, 1, 1)
      GameTooltip:AddLine("Open Encounter Setup to edit roles, marks, and announcements for the selected encounter.", 0.8, 0.8, 0.8, 1)
      GameTooltip:Show()
    end)
    editStructureBtn:SetScript("OnLeave", function()
      GameTooltip:Hide()
    end)
    
    editStructureBtn:SetScript("OnClick", function()
      local selectedRaid = frame.selectedRaid
      local selectedEncounter = frame.selectedEncounter
      
      if not selectedRaid or not selectedEncounter then
        OGRH.Msg("Select an encounter first.")
        return
      end
      
      -- Close Encounter Planning window
      frame:Hide()
      
      -- Open Encounter Setup with the selected raid and encounter
      if OGRH.ShowEncounterSetup then
        OGRH.ShowEncounterSetup(selectedRaid, selectedEncounter)
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
        local raids = OGRH.SVM.GetPath("encounterMgmt.raids")
        for i = 1, table.getn(raids) do
          local raid = raids[i]
          if raid.name == frame.selectedRaid then
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
      
      -- Add existing raids (new structure only)
      local raids = OGRH.SVM.GetPath("encounterMgmt.raids")
      for i = 1, table.getn(raids) do
        local raid = raids[i]
        local raidName = raid.name
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
        
        -- Settings button (notepad icon, right side)
        local settingsBtn = CreateFrame("Button", nil, raidBtn)
        settingsBtn:SetWidth(16)
        settingsBtn:SetHeight(16)
        settingsBtn:SetPoint("RIGHT", raidBtn, "RIGHT", -5, 0)
        settingsBtn:SetNormalTexture("Interface\\Buttons\\UI-GuildButton-PublicNote-Up")
        settingsBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
        settingsBtn:SetPushedTexture("Interface\\Buttons\\UI-GuildButton-PublicNote-Down")
        
        local capturedRaidName = raidName
        local capturedRaidIdx = i
        settingsBtn:SetScript("OnEnter", function()
          GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
          GameTooltip:SetText("Raid-Wide Settings")
          GameTooltip:AddLine("Configure default settings for all encounters", 1, 1, 1, 1)
          GameTooltip:Show()
        end)
        
        settingsBtn:SetScript("OnLeave", function()
          GameTooltip:Hide()
        end)
        
        settingsBtn:SetScript("OnClick", function()
          -- Set this raid as selected first
          frame.selectedRaid = capturedRaidName
          frame.selectedRaidIdx = capturedRaidIdx
          RefreshRaidsList()
          if frame.RefreshEncountersList then
            frame.RefreshEncountersList()
          end
          
          -- Show raid-wide settings dialog
          if OGRH.ShowRaidSettingsDialog then
            OGRH.ShowRaidSettingsDialog()
          end
        end)
        
        -- Store reference for potential updates
        raidBtn.settingsBtn = settingsBtn
        
        -- Click to select raid
        raidBtn:SetScript("OnClick", function()
          -- Clear encounter selection when switching raids
          if frame.selectedRaid ~= capturedRaidName then
            frame.selectedEncounter = nil
            frame.selectedEncounterIdx = nil
          end
          frame.selectedRaid = capturedRaidName
          frame.selectedRaidIdx = capturedRaidIdx
          -- DO NOT update main UI state - planning window is independent
          
          -- Select first encounter if available (new structure only)
          local firstEncounter = nil
          local raid = OGRH.FindRaidByName(capturedRaidName)
          if raid and raid.encounters and table.getn(raid.encounters) > 0 then
            firstEncounter = raid.encounters[1].name
            frame.selectedEncounter = firstEncounter
            frame.selectedEncounterIdx = 1
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
      
      -- Get encounters for selected raid (new structure only)
      local raid = OGRH.FindRaidByName(frame.selectedRaid)
      if not raid or not raid.encounters then
        return
      end
      
      -- Validate that the selected encounter still exists
      if frame.selectedEncounter then
        local encounterExists = false
        for i = 1, table.getn(raid.encounters) do
          if raid.encounters[i].name == frame.selectedEncounter then
            encounterExists = true
            break
          end
        end
        if not encounterExists then
          frame.selectedEncounter = nil
          frame.selectedEncounterIdx = nil
        end
      end
      
      local yOffset = -5
      local selectedIndex = nil
      
      for i = 1, table.getn(raid.encounters) do
        local encounterName = raid.encounters[i].name
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
        
        -- Settings button (notepad icon, right side)
        local settingsBtn = CreateFrame("Button", nil, encounterBtn)
        settingsBtn:SetWidth(16)
        settingsBtn:SetHeight(16)
        settingsBtn:SetPoint("RIGHT", encounterBtn, "RIGHT", -5, 0)
        settingsBtn:SetNormalTexture("Interface\\Buttons\\UI-GuildButton-PublicNote-Up")
        settingsBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
        settingsBtn:SetPushedTexture("Interface\\Buttons\\UI-GuildButton-PublicNote-Down")
        
        local capturedEncounterName = encounterName
        local capturedEncounterIdx = i
        settingsBtn:SetScript("OnEnter", function()
          GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
          GameTooltip:SetText("Encounter Settings")
          GameTooltip:AddLine("Configure BigWigs detection and consume requirements", 1, 1, 1, 1)
          GameTooltip:Show()
        end)
        
        settingsBtn:SetScript("OnLeave", function()
          GameTooltip:Hide()
        end)
        
        settingsBtn:SetScript("OnClick", function()
          -- Set this encounter as selected first
          frame.selectedEncounter = capturedEncounterName
          frame.selectedEncounterIdx = capturedEncounterIdx
          -- Ensure raid is also selected (should already be, but make sure)
          if not frame.selectedRaid then
            frame.selectedRaid = frame.selectedRaid
          end
          RefreshEncountersList()
          if frame.RefreshRoleContainers then
            frame.RefreshRoleContainers()
          end
          
          -- Show encounter settings dialog
          if OGRH.ShowAdvancedSettingsDialog then
            OGRH.ShowAdvancedSettingsDialog()
          end
        end)
        
        -- Store reference for potential updates
        encounterBtn.settingsBtn = settingsBtn
        
        -- Click to select encounter
        encounterBtn:SetScript("OnClick", function()
          frame.selectedEncounter = capturedEncounterName
          frame.selectedEncounterIdx = capturedEncounterIdx
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
      if OGRH.ROLLFOR_AVAILABLE then
        GameTooltip:AddLine("Right-click: Auto-assign from RollFor soft-reserve data", 0.8, 0.8, 0.8, 1)
      else
        GameTooltip:AddLine("Right-click: Auto-assign from RollFor (requires RollFor " .. OGRH.ROLLFOR_REQUIRED_VERSION .. ")", 0.5, 0.5, 0.5, 1)
      end
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
        -- Check if RollFor is available
        if not OGRH.ROLLFOR_AVAILABLE then
          DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OGRH:|r Auto-assign from RollFor requires RollFor version " .. OGRH.ROLLFOR_REQUIRED_VERSION .. ".")
          return
        end
        
        if not frame.selectedRaid or not frame.selectedEncounter then
          DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OGRH:|r Please select a raid and encounter first.")
          return
        end
        
        -- Check if RollFor data is loaded
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
        
        -- Show status in label instead of chat
        if frame.ShowStatus then
          frame.ShowStatus("Auto-assigned " .. assignmentCount .. " players from RollFor data.", 10)
        end
        return
      end
      
      -- Left-click: Auto Assign from current raid members
      -- Now uses same two-pass logic as RollFor path
      if not frame.selectedRaid or not frame.selectedEncounter then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OGRH:|r Please select a raid and encounter first.")
        return
      end
      
      if GetNumRaidMembers() == 0 then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OGRH:|r You must be in a raid to auto-assign.")
        return
      end
      
      -- Build player data in same format as RollFor
      local raidPlayers = {}
      
      -- Helper to get player's role from RolesUI
      local function GetPlayerRole(playerName)
        if not OGRH.rolesFrame or not OGRH.rolesFrame.ROLE_COLUMNS then
          return nil
        end
        
        local roleColumns = OGRH.rolesFrame.ROLE_COLUMNS
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
      
      -- Build player list from current raid
      for i = 1, GetNumRaidMembers() do
        local name, _, _, _, class = GetRaidRosterInfo(i)
        if name and class then
          local playerRole = GetPlayerRole(name)
          if playerRole then
            table.insert(raidPlayers, {
              name = name,
              role = playerRole,  -- Already in TANKS/HEALERS/MELEE/RANGED format
              class = string.upper(class)
            })
          end
        end
      end
      
      if table.getn(raidPlayers) == 0 then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OGRH:|r No raid members found with assigned roles.")
        return
      end
      
      -- Map function that just returns the role as-is (already in correct format)
      local function MapRaidRole(roleBucket)
        return roleBucket
      end
      
      -- Use same auto-assign logic as RollFor
      local assignmentCount = OGRH.AutoAssignRollForPlayers(frame, raidPlayers)
      
      -- Show status in label instead of chat
      if frame.ShowStatus then
        frame.ShowStatus("Auto-assigned " .. assignmentCount .. " players from raid.", 10)
      end
    end)
    
    -- Announce button (below Auto Assign, reduced height)
    local announceBtn = CreateFrame("Button", nil, bottomPanel, "UIPanelButtonTemplate")
    announceBtn:SetWidth(120)
    announceBtn:SetHeight(24)
    announceBtn:SetPoint("TOPLEFT", autoAssignBtn, "BOTTOMLEFT", 0, -6)
    announceBtn:SetText("Announce")
    OGRH.StyleButton(announceBtn)
    frame.announceBtn = announceBtn

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
        -- Get role configuration from v2 via SVM
        local raids = OGRH.SVM.GetPath('encounterMgmt.raids')
        if not raids then
          return -- Silently do nothing if no raids configured
        end
        
        -- Use stored indices to access encounter directly
        if not frame.selectedRaidIdx or not frame.selectedEncounterIdx then
          return
        end
        
        if not raids[frame.selectedRaidIdx] or not raids[frame.selectedRaidIdx].encounters then
          return
        end
        
        local encounter = raids[frame.selectedRaidIdx].encounters[frame.selectedEncounterIdx]
        
        if not encounter or not encounter.roles then
          return
        end
        
        -- Build column1/column2 structure from roles array
        local column1 = {}
        local column2 = {}
        for i = 1, table.getn(encounter.roles) do
          local role = encounter.roles[i]
          if role.column == 1 then
            table.insert(column1, role)
          elseif role.column == 2 then
            table.insert(column2, role)
          end
        end
        
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
        
        -- Build consume announcement using helper function
        local announceLines = OGRH.Announcements.BuildConsumeAnnouncement(frame.selectedEncounter, consumeRole)
        
        -- Send to raid warning
        for _, line in ipairs(announceLines) do
          SendChatMessage(line, "RAID_WARNING")
        end
        
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OGRH:|r Consumes announced to raid warning.")
        return
      end
      
      -- Left-click: Normal announcement
      
      -- Use unified announcement function
      if OGRH.Announcements and OGRH.Announcements.SendEncounterAnnouncement then
        OGRH.Announcements.SendEncounterAnnouncement(frame.selectedRaid, frame.selectedEncounter)
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
      
      -- Get role configuration from v2 via SVM
      local raids = OGRH.SVM.GetPath('encounterMgmt.raids')
      if not raids then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OGRH:|r No roles configured for this encounter.")
        return
      end
      
      -- Find the raid by name
      local raid = nil
      -- Use stored indices to access encounter directly
      if not frame.selectedRaidIdx or not frame.selectedEncounterIdx then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OGRH:|r No encounter selected.")
        return
      end
      
      if not raids[frame.selectedRaidIdx] or not raids[frame.selectedRaidIdx].encounters then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OGRH:|r No roles configured for this encounter.")
        return
      end
      
      local encounter = raids[frame.selectedRaidIdx].encounters[frame.selectedEncounterIdx]
      
      if not encounter or not encounter.roles then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OGRH:|r No roles configured for this encounter.")
        return
      end
      
      -- Build column1/column2 structure from roles array
      local column1 = {}
      local column2 = {}
      for i = 1, table.getn(encounter.roles) do
        local role = encounter.roles[i]
        if role.column == 1 then
          table.insert(column1, role)
        elseif role.column == 2 then
          table.insert(column2, role)
        end
      end
      
      -- Build ordered list of all roles using stable roleId
      local allRoles = {}
      
      for i = 1, table.getn(column1) do
        table.insert(allRoles, {role = column1[i], roleIndex = column1[i].roleId or (table.getn(allRoles) + 1)})
      end
      for i = 1, table.getn(column2) do
        table.insert(allRoles, {role = column2[i], roleIndex = column2[i].roleId or (table.getn(allRoles) + 1)})
      end
      
      -- Get assignments and raid marks from nested role objects
      local allRaids = OGRH.SVM.GetPath('encounterMgmt.raids')
      local encounter = nil
      
      -- Use stored indices to access encounter data directly
      if frame.selectedRaidIdx and frame.selectedEncounterIdx then
        if allRaids and
           allRaids[frame.selectedRaidIdx] and
           allRaids[frame.selectedRaidIdx].encounters and
           allRaids[frame.selectedRaidIdx].encounters[frame.selectedEncounterIdx] then
          encounter = allRaids[frame.selectedRaidIdx].encounters[frame.selectedEncounterIdx]
        end
      end
      
      -- Iterate through roles and apply marks
      local markedCount = 0
      
      for _, roleData in ipairs(allRoles) do
        local role = roleData.role
        local roleIndex = roleData.roleIndex
        
        -- Get assigned players for this role from nested role object
        local assignedPlayers = {}
        local roleMarks = {}
        if encounter and encounter.roles and encounter.roles[roleIndex] then
          assignedPlayers = encounter.roles[roleIndex].assignedPlayers or {}
          roleMarks = encounter.roles[roleIndex].raidMarks or {}
        end
        
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
        if frame.ShowStatus then
          frame.ShowStatus("Only the raid lead can unlock editing.", 10)
        end
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
      
      -- Save text changes to SavedVariables on focus lost (not every keystroke)
      local capturedIndex = i
      editBox:SetScript("OnEditFocusLost", function()
        if frame.selectedRaidIdx and frame.selectedEncounterIdx then
          -- Use stored indices to access encounter directly
          local raids = OGRH.SVM.GetPath('encounterMgmt.raids')
          if not raids or
             not raids[frame.selectedRaidIdx] or
             not raids[frame.selectedRaidIdx].encounters or
             not raids[frame.selectedRaidIdx].encounters[frame.selectedEncounterIdx] then
            return
          end
          
          local encounter = raids[frame.selectedRaidIdx].encounters[frame.selectedEncounterIdx]
          
          -- Ensure announcements array exists
          if not encounter.announcements then
            encounter.announcements = {}
          end
          
          local oldText = encounter.announcements[capturedIndex] or ""
          local newText = this:GetText()
          encounter.announcements[capturedIndex] = newText
          
          -- Write back the entire raids structure via SVM (change tracking handled automatically)
          OGRH.SVM.SetPath('encounterMgmt.raids', raids)
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
              -- Use stored indices to access encounter directly
              if frame.selectedRaidIdx and frame.selectedEncounterIdx then
                local raids = OGRH.SVM.GetPath('encounterMgmt.raids')
                if raids and
                   raids[frame.selectedRaidIdx] and
                   raids[frame.selectedRaidIdx].encounters and
                   raids[frame.selectedRaidIdx].encounters[frame.selectedEncounterIdx] then
                  local encounter = raids[frame.selectedRaidIdx].encounters[frame.selectedEncounterIdx]
                  
                  -- Ensure roles structure exists
                  if not encounter.roles or not encounter.roles[targetRoleIndex] then
                    OGRH.Msg("Cannot assign player - role does not exist")
                    return
                  end
                  
                  -- Ensure assignedPlayers array exists within role
                  if not encounter.roles[targetRoleIndex].assignedPlayers then
                    encounter.roles[targetRoleIndex].assignedPlayers = {}
                  end
                  
                  -- Assign player
                  encounter.roles[targetRoleIndex].assignedPlayers[targetSlotIndex] = frame.draggedPlayerName
                  
                  -- Write back the entire raids structure
                  OGRH.SVM.SetPath('encounterMgmt.raids', raids)
                end
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
      
      -- Load saved announcement text for this encounter via SVM
      -- Use stored indices to access encounter directly
      local encounter = nil
      
      if frame.selectedRaidIdx and frame.selectedEncounterIdx then
        local raids = OGRH.SVM.GetPath('encounterMgmt.raids')
        if raids and
           raids[frame.selectedRaidIdx] and
           raids[frame.selectedRaidIdx].encounters and
           raids[frame.selectedRaidIdx].encounters[frame.selectedEncounterIdx] then
          encounter = raids[frame.selectedRaidIdx].encounters[frame.selectedEncounterIdx]
        end
      end
      
      local savedAnnouncements = {}
      if encounter and encounter.announcements then
        savedAnnouncements = encounter.announcements
      end
      if frame.announcementLines then
        for i = 1, table.getn(frame.announcementLines) do
          local savedText = savedAnnouncements[i] or ""
          frame.announcementLines[i]:SetText(savedText)
        end
      end
      
      -- Get role configuration for this encounter from v2 via SVM
      local raids = OGRH.SVM.GetPath('encounterMgmt.raids')
      if not raids then
        -- No roles configured yet
        local noRolesText = rightPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        noRolesText:SetPoint("CENTER", rightPanel, "CENTER", 0, 0)
        noRolesText:SetText("|cffff8888No roles configured for this encounter|r\n|cff888888Configure roles in Encounter Setup|r")
        frame.roleContainers.noRolesText = noRolesText
        return
      end
      
      -- Use stored indices to access encounter directly
      if not frame.selectedRaidIdx or not frame.selectedEncounterIdx then
        local noRolesText = rightPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        noRolesText:SetPoint("CENTER", rightPanel, "CENTER", 0, 0)
        noRolesText:SetText("|cffff8888No encounter selected|r")
        frame.roleContainers.noRolesText = noRolesText
        return
      end
      
      if not raids[frame.selectedRaidIdx] or not raids[frame.selectedRaidIdx].encounters then
        local noRolesText = rightPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        noRolesText:SetPoint("CENTER", rightPanel, "CENTER", 0, 0)
        noRolesText:SetText("|cffff8888No roles configured for this encounter|r\n|cff888888Configure roles in Encounter Setup|r")
        frame.roleContainers.noRolesText = noRolesText
        return
      end
      
      local encounter = raids[frame.selectedRaidIdx].encounters[frame.selectedEncounterIdx]
      
      if not encounter or not encounter.roles then
        -- No roles configured yet
        local noRolesText = rightPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        noRolesText:SetPoint("CENTER", rightPanel, "CENTER", 0, 0)
        noRolesText:SetText("|cffff8888No roles configured for this encounter|r\n|cff888888Configure roles in Encounter Setup|r")
        frame.roleContainers.noRolesText = noRolesText
        return
      end
      
      -- Build column1/column2 structure from roles array
      local column1 = {}
      local column2 = {}
      for i = 1, table.getn(encounter.roles) do
        local role = encounter.roles[i]
        if role.column == 1 then
          table.insert(column1, role)
        elseif role.column == 2 then
          table.insert(column2, role)
        end
      end
      
      -- DATA CLEANUP: Remove obsolete stored data that doesn't match current role configuration
      -- This prevents issues like raid marks on slots that no longer have showRaidIcons enabled
      local function CleanupObsoleteData()
        -- Build a map of valid roleIds and their configuration
        local validRoles = {}
        for _, role in ipairs(column1) do
          if role.roleId then
            validRoles[role.roleId] = role
          end
        end
        for _, role in ipairs(column2) do
          if role.roleId then
            validRoles[role.roleId] = role
          end
        end
        
        -- Cleanup raidMarks - v2 schema has roles as array, each role has raidMarks array
        if frame.selectedRaidIdx and frame.selectedEncounterIdx then
          local allRaids = OGRH.SVM.GetPath('encounterMgmt.raids')
          if allRaids and 
             allRaids[frame.selectedRaidIdx] and 
             allRaids[frame.selectedRaidIdx].encounters and
             allRaids[frame.selectedRaidIdx].encounters[frame.selectedEncounterIdx] then
            local encounter = allRaids[frame.selectedRaidIdx].encounters[frame.selectedEncounterIdx]
          if encounter.roles then
            -- Iterate through roles array (v2 schema)
            for roleIdx = 1, table.getn(encounter.roles) do
              local roleData = encounter.roles[roleIdx]
              local role = validRoles[roleData.roleId]
              
              if not role then
                -- Role ID no longer exists in configuration, clear marks
                roleData.raidMarks = nil
                roleData.assignedPlayers = nil
                roleData.assignmentNumbers = nil
              elseif not role.showRaidIcons then
                -- Role exists but showRaidIcons is false/nil, remove all marks
                roleData.raidMarks = nil
              elseif roleData.raidMarks then
                -- Role exists and has showRaidIcons, check slot counts
                local maxSlots = role.slots or 1
                -- Clean up marks beyond slot count
                for slotIdx = maxSlots + 1, table.getn(roleData.raidMarks or {}) do
                  roleData.raidMarks[slotIdx] = nil
                end
              end
            end
            
            -- Write back cleaned raids structure via SVM
            OGRH.SVM.SetPath('encounterMgmt.raids', allRaids)
            end
          end
        end
        
        -- Cleanup assignedPlayers and assignmentNumbers - v2 schema has these nested in roles
        if frame.selectedRaidIdx and frame.selectedEncounterIdx then
          local allRaids = OGRH.SVM.GetPath('encounterMgmt.raids')
          if allRaids and 
             allRaids[frame.selectedRaidIdx] and 
             allRaids[frame.selectedRaidIdx].encounters and
             allRaids[frame.selectedRaidIdx].encounters[frame.selectedEncounterIdx] then
            local encounter = allRaids[frame.selectedRaidIdx].encounters[frame.selectedEncounterIdx]
          if encounter.roles then
            -- Iterate through roles array (v2 schema)
            for roleIdx = 1, table.getn(encounter.roles) do
              local roleData = encounter.roles[roleIdx]
              local role = validRoles[roleData.roleId]
              
              if not role then
                -- Role ID no longer exists, already cleared above
              elseif roleData.assignedPlayers then
                -- Role exists, check slot counts
                local maxSlots = role.slots or 1
                -- Clean up assignments beyond slot count
                for slotIdx = maxSlots + 1, table.getn(roleData.assignedPlayers or {}) do
                  roleData.assignedPlayers[slotIdx] = nil
                  if roleData.assignmentNumbers then
                    roleData.assignmentNumbers[slotIdx] = nil
                  end
                end
              end
            end
            
            -- Write back cleaned raids structure via SVM
            OGRH.SVM.SetPath('encounterMgmt.raids', allRaids)
            end
          end
        end
      end
      
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
            
            -- Get all roles from v2 via SVM
            local allRoles = {}
            local raids = OGRH.SVM.GetPath('encounterMgmt.raids')
            if raids and frame.selectedRaidIdx and frame.selectedEncounterIdx then
              if raids[frame.selectedRaidIdx] and
                 raids[frame.selectedRaidIdx].encounters and
                 raids[frame.selectedRaidIdx].encounters[frame.selectedEncounterIdx] then
                local encounter = raids[frame.selectedRaidIdx].encounters[frame.selectedEncounterIdx]
                
                if encounter and encounter.roles then
                  -- Add all roles from the encounter
                  for i = 1, table.getn(encounter.roles) do
                    table.insert(allRoles, encounter.roles[i])
                  end
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
                -- Write modified roles back to SVM
                local raids = OGRH.SVM.GetPath('encounterMgmt.raids')
                if raids and frame.selectedRaidIdx and frame.selectedEncounterIdx then
                  if raids[frame.selectedRaidIdx] and
                     raids[frame.selectedRaidIdx].encounters and
                     raids[frame.selectedRaidIdx].encounters[frame.selectedEncounterIdx] then
                    -- Update with modified roles
                    raids[frame.selectedRaidIdx].encounters[frame.selectedEncounterIdx].roles = allRoles
                    
                    OGRH.SVM.SetPath('encounterMgmt.raids', raids, {
                      syncLevel = "MANUAL",
                      componentType = "settings",
                      scope = {raid = frame.selectedRaid, encounter = frame.selectedEncounter}
                    })
                  end
                end
                
                -- Refresh UI
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
              
              -- Save the raid mark assignment via SVM - write to nested role.raidMarks
              if frame.selectedRaidIdx and frame.selectedEncounterIdx then
                local allRaids = OGRH.SVM.GetPath('encounterMgmt.raids') or {}
                
                -- Ensure structure exists
                if not allRaids[frame.selectedRaidIdx] then return end
                if not allRaids[frame.selectedRaidIdx].encounters then return end
                if not allRaids[frame.selectedRaidIdx].encounters[frame.selectedEncounterIdx] then return end
                
                local encounter = allRaids[frame.selectedRaidIdx].encounters[frame.selectedEncounterIdx]
                
                -- Don't initialize empty roles - they should already exist from setup
                if not encounter.roles or not encounter.roles[capturedRoleIndex] then 
                  OGRH.Msg("Cannot set raid mark - role does not exist. Configure roles in Encounter Setup first.")
                  return
                end
                
                if not encounter.roles[capturedRoleIndex].raidMarks then
                  encounter.roles[capturedRoleIndex].raidMarks = {}
                end
                
                local oldMark = encounter.roles[capturedRoleIndex].raidMarks[capturedSlotIndex] or 0
                encounter.roles[capturedRoleIndex].raidMarks[capturedSlotIndex] = currentIndex
                
                -- Write back via SVM (change tracking handled automatically)
                OGRH.SVM.SetPath('encounterMgmt.raids', allRaids)
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
              
              -- Save the assignment number via SVM - write to nested encounter.assignmentNumbers
              if frame.selectedRaidIdx and frame.selectedEncounterIdx then
                local allRaids = OGRH.SVM.GetPath('encounterMgmt.raids') or {}
                
                -- Ensure structure exists
                if not allRaids[frame.selectedRaidIdx] then return end
                if not allRaids[frame.selectedRaidIdx].encounters then return end
                if not allRaids[frame.selectedRaidIdx].encounters[frame.selectedEncounterIdx] then return end
                
                local encounter = allRaids[frame.selectedRaidIdx].encounters[frame.selectedEncounterIdx]
                
                -- Don't initialize empty roles - they should already exist from setup
                if not encounter.roles or not encounter.roles[capturedRoleIndex] then
                  OGRH.Msg("Cannot set assignment number - role does not exist. Configure roles in Encounter Setup first.")
                  return
                end
                
                if not encounter.roles[capturedRoleIndex].assignmentNumbers then
                  encounter.roles[capturedRoleIndex].assignmentNumbers = {}
                end
                
                local oldNumber = encounter.roles[capturedRoleIndex].assignmentNumbers[capturedSlotIndex] or 0
                encounter.roles[capturedRoleIndex].assignmentNumbers[capturedSlotIndex] = currentIndex
                
                -- Write back via SVM (change tracking handled automatically)
                OGRH.SVM.SetPath('encounterMgmt.raids', allRaids)
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
            
            -- Get current player assignment from nested encounter.assignedPlayers
            local playerName = nil
            if frame.selectedRaidIdx and frame.selectedEncounterIdx then
              local allRaids = OGRH.SVM.GetPath('encounterMgmt.raids')
              if allRaids and
                 allRaids[frame.selectedRaidIdx] and
                 allRaids[frame.selectedRaidIdx].encounters and
                 allRaids[frame.selectedRaidIdx].encounters[frame.selectedEncounterIdx] then
                local encounter = allRaids[frame.selectedRaidIdx].encounters[frame.selectedEncounterIdx]
                if encounter.roles and
                   encounter.roles[slotRoleIndex] and
                   encounter.roles[slotRoleIndex].assignedPlayers and
                   encounter.roles[slotRoleIndex].assignedPlayers[slotSlotIndex] then
                  playerName = encounter.roles[slotRoleIndex].assignedPlayers[slotSlotIndex]
                end
              end
            end
            
            if not playerName then
              return -- No player to drag
            end
            
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
              if not frame.selectedRaidIdx or not frame.selectedEncounterIdx then return end
              
              -- Get the entire raids structure to modify
              local allRaids = OGRH.SVM.GetPath('encounterMgmt.raids') or {}
              
              -- Ensure structure exists
              if not allRaids[frame.selectedRaidIdx] then return end
              if not allRaids[frame.selectedRaidIdx].encounters then return end
              if not allRaids[frame.selectedRaidIdx].encounters[frame.selectedEncounterIdx] then return end
              
              local encounter = allRaids[frame.selectedRaidIdx].encounters[frame.selectedEncounterIdx]
              
              -- Ensure roles exist
              if not encounter.roles then
                OGRH.Msg("Cannot assign - encounter has no roles configured")
                return
              end
              
              if isDraggingFromPlayerList then
                -- Dragging from players list - just assign
                if not encounter.roles[targetRoleIndex] then
                  OGRH.Msg("Cannot assign - target role does not exist")
                  return
                end
                if not encounter.roles[targetRoleIndex].assignedPlayers then
                  encounter.roles[targetRoleIndex].assignedPlayers = {}
                end
                encounter.roles[targetRoleIndex].assignedPlayers[targetSlotIndex] = frame.draggedPlayerName
                
                -- Write back via SVM
                OGRH.SVM.SetPath('encounterMgmt.raids', allRaids)
              else
                -- Dragging from another slot - swap or move
                -- Get current player at target position (if any)
                local targetPlayer = nil
                if encounter.roles[targetRoleIndex] and 
                   encounter.roles[targetRoleIndex].assignedPlayers then
                  targetPlayer = encounter.roles[targetRoleIndex].assignedPlayers[targetSlotIndex]
                end
                
                -- Ensure target and source roles exist
                if not encounter.roles[targetRoleIndex] then
                  OGRH.Msg("Cannot assign - target role does not exist")
                  return
                end
                if not encounter.roles[frame.draggedFromRole] then
                  OGRH.Msg("Cannot move - source role does not exist")
                  return
                end
                if not encounter.roles[targetRoleIndex].assignedPlayers then
                  encounter.roles[targetRoleIndex].assignedPlayers = {}
                end
                if not encounter.roles[frame.draggedFromRole].assignedPlayers then
                  encounter.roles[frame.draggedFromRole].assignedPlayers = {}
                end
                if not encounter.roles[frame.draggedFromRole].assignedPlayers then
                  encounter.roles[frame.draggedFromRole].assignedPlayers = {}
                end
                
                -- Move player to target
                encounter.roles[targetRoleIndex].assignedPlayers[targetSlotIndex] = frame.draggedPlayer
                
                if targetPlayer then
                  -- Swap: put target player in source position
                  encounter.roles[frame.draggedFromRole].assignedPlayers[frame.draggedFromSlot] = targetPlayer
                else
                  -- Just move: clear source position
                  encounter.roles[frame.draggedFromRole].assignedPlayers[frame.draggedFromSlot] = nil
                end
                
                -- Write back via SVM
                OGRH.SVM.SetPath('encounterMgmt.raids', allRaids)
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
              
              -- Right click: Unassign player using SVM - clear from nested encounter.assignedPlayers
              if not frame.selectedRaidIdx or not frame.selectedEncounterIdx then return end
              
              local allRaids = OGRH.SVM.GetPath('encounterMgmt.raids')
              if allRaids and
                 allRaids[frame.selectedRaidIdx] and
                 allRaids[frame.selectedRaidIdx].encounters and
                 allRaids[frame.selectedRaidIdx].encounters[frame.selectedEncounterIdx] then
                local encounter = allRaids[frame.selectedRaidIdx].encounters[frame.selectedEncounterIdx]
                if encounter.roles and
                   encounter.roles[slotRoleIndex] and
                   encounter.roles[slotRoleIndex].assignedPlayers then
                  
                  encounter.roles[slotRoleIndex].assignedPlayers[slotSlotIndex] = nil
                  
                  -- Write back via SVM
                  OGRH.SVM.SetPath('encounterMgmt.raids', allRaids)
                  
                  -- Refresh display
                  if frame.RefreshRoleContainers then
                    frame.RefreshRoleContainers()
                  end
                end
              end
            end
            -- Left click: Do nothing (edit button handles class priority)
          end)
          
          table.insert(container.slots, slot)
        end
        
        -- Update slot assignments after creating all slots
        local function UpdateSlotAssignments()
          -- Get assignments for this encounter from nested encounter.assignedPlayers
          local assignedPlayers = {}
          local raidMarks = {}
          local assignmentNumbers = {}
          
          -- Use stored indices to access encounter data directly
          if frame.selectedRaidIdx and frame.selectedEncounterIdx then
            local allRaids = OGRH.SVM.GetPath('encounterMgmt.raids')
            if allRaids and
               allRaids[frame.selectedRaidIdx] and
               allRaids[frame.selectedRaidIdx].encounters and
               allRaids[frame.selectedRaidIdx].encounters[frame.selectedEncounterIdx] then
              local encounter = allRaids[frame.selectedRaidIdx].encounters[frame.selectedEncounterIdx]
              if encounter.roles and encounter.roles[capturedRoleIndex] then
                if encounter.roles[capturedRoleIndex].assignedPlayers then
                  assignedPlayers = encounter.roles[capturedRoleIndex].assignedPlayers
                end
                if encounter.roles[capturedRoleIndex].raidMarks then
                  raidMarks = encounter.roles[capturedRoleIndex].raidMarks
                end
                if encounter.roles[capturedRoleIndex].assignmentNumbers then
                  assignmentNumbers = encounter.roles[capturedRoleIndex].assignmentNumbers
                end
              end
            end
          end
          
          -- Update slot displays
          for slotIdx, slot in ipairs(container.slots) do
            local playerName = assignedPlayers[slotIdx]
            
            -- Load saved raid mark for this slot
            if slot.iconBtn then
              local savedMark = raidMarks[slotIdx] or 0
              
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
              local savedAssign = assignmentNumbers[slotIdx] or 0
              
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
      
      -- Left column (skip Custom Module roles - they don't render in planning UI)
      for i = 1, table.getn(column1) do
        if not column1[i].isCustomModule then
          -- Use stable roleId for labeling and data storage
          local roleIndex = column1[i].roleId or i
          local container = CreateRoleContainer(scrollChild, column1[i], roleIndex, 5, yOffsetLeft, columnWidth)
          table.insert(frame.roleContainers, container)
          
          -- Calculate offset for next role in left column
          local containerHeight = 40 + ((column1[i].slots or 1) * 22)
          yOffsetLeft = yOffsetLeft - containerHeight - 10
        end
      end
      
      -- Right column (skip Custom Module roles - they don't render in planning UI)
      for i = 1, table.getn(column2) do
        if not column2[i].isCustomModule then
          -- Use stable roleId for labeling and data storage
          local roleIndex = column2[i].roleId or (table.getn(column1) + i)
          local container = CreateRoleContainer(scrollChild, column2[i], roleIndex, 287, yOffsetRight, columnWidth)
          table.insert(frame.roleContainers, container)
          
          -- Calculate offset for next role in right column
          local containerHeight = 40 + ((column2[i].slots or 1) * 22)
          yOffsetRight = yOffsetRight - containerHeight - 10
        end
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
      
      -- Find the raid index by name
      local raids = OGRH.SVM.GetPath('encounterMgmt.raids')
      if raids then
        for i = 1, table.getn(raids) do
          if raids[i].name == OGRH_SV.ui.selectedRaid then
            frame.selectedRaidIdx = i
            
            -- If there's a saved encounter, find its index too
            if OGRH_SV.ui.selectedEncounter and raids[i].encounters then
              frame.selectedEncounter = OGRH_SV.ui.selectedEncounter
              for j = 1, table.getn(raids[i].encounters) do
                if raids[i].encounters[j].name == OGRH_SV.ui.selectedEncounter then
                  frame.selectedEncounterIdx = j
                  break
                end
              end
            end
            break
          end
        end
      end
      
      -- Refresh the UI to display the restored selection
      if frame.RefreshEncountersList then
        frame.RefreshEncountersList()
      end
      if frame.RefreshRoleContainers then
        frame.RefreshRoleContainers()
      end
      if frame.RefreshPlayersList then
        frame.RefreshPlayersList()
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
  
  -- Update button states based on raid lead status
  if OGRH.UpdateRaidLeadUI then
    OGRH.UpdateRaidLeadUI()
  end
  
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
  
  -- Load existing consume data for this slot from v2 schema
  local existingConsumeData = nil
  local allRaids = OGRH.SVM.GetPath('encounterMgmt.raids')
  if allRaids then
    for i = 1, table.getn(allRaids) do
      if allRaids[i].name == raidName and allRaids[i].encounters then
        for j = 1, table.getn(allRaids[i].encounters) do
          if allRaids[i].encounters[j].name == encounterName then
            local encounter = allRaids[i].encounters[j]
            if encounter.roles and encounter.roles[roleIndex] then
              local role = encounter.roles[roleIndex]
              if role.consumes and role.consumes[slotIndex] then
                existingConsumeData = role.consumes[slotIndex]
                dialog.selectedConsume = existingConsumeData
              end
            end
            break
          end
        end
        break
      end
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
    -- Find encounter and role in v2 schema
    local allRaids = OGRH.SVM.GetPath('encounterMgmt.raids')
    local encounter = nil
    local role = nil
    
    if allRaids then
      for i = 1, table.getn(allRaids) do
        if allRaids[i].name == dialog.raidName and allRaids[i].encounters then
          for j = 1, table.getn(allRaids[i].encounters) do
            if allRaids[i].encounters[j].name == dialog.encounterName then
              encounter = allRaids[i].encounters[j]
              if encounter.roles and encounter.roles[dialog.roleIndex] then
                role = encounter.roles[dialog.roleIndex]
              end
              break
            end
          end
          break
        end
      end
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
    
    -- Save old consume data for delta sync
    local oldConsume = role.consumes[dialog.slotIndex]
    
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
    
    -- Delta sync for consume selection change
    if OGRH.SyncDelta and OGRH.SyncDelta.RecordAssignmentChange then
      local consumeData = {
        raid = dialog.raidName,
        encounter = dialog.encounterName,
        roleIndex = dialog.roleIndex,
        slotIndex = dialog.slotIndex
      }
      OGRH.SyncDelta.RecordAssignmentChange(
        nil,  -- playerName (not applicable for consume selection)
        "CONSUME_SELECTION",
        {consume = role.consumes[dialog.slotIndex], consumeData = consumeData},
        {consume = oldConsume, consumeData = consumeData}
      )
    end
    
    -- Write back to saved variables
    OGRH.SVM.SetPath('encounterMgmt.raids', allRaids)
    
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
function OGRH.ShowAnnouncementTooltip(anchorFrame)
  -- Get the current encounter from main UI (not from Encounter Planning window)
  local selectedRaid, selectedEncounter = OGRH.GetCurrentEncounter()
  
  if not selectedRaid or not selectedEncounter then
    return
  end
  
  -- Check if announcement system is loaded
  if not OGRH.Announcements or not OGRH.Announcements.ReplaceTags then
    return
  end
  
  -- announcements will be checked below when we read from nested structure
  
  -- Get role data for tag processing from v2 schema
  local orderedRoles = {}
  
  -- Find encounter in v2 schema
  local allRaids = OGRH.SVM.GetPath('encounterMgmt.raids')
  local encounter = nil
  if allRaids then
    for i = 1, table.getn(allRaids) do
      if allRaids[i].name == selectedRaid and allRaids[i].encounters then
        for j = 1, table.getn(allRaids[i].encounters) do
          if allRaids[i].encounters[j].name == selectedEncounter then
            encounter = allRaids[i].encounters[j]
            break
          end
        end
        break
      end
    end
  end
  
  if encounter and encounter.roles then
    -- Build roles array indexed by roleId from v2 schema
    for i = 1, table.getn(encounter.roles) do
      local role = encounter.roles[i]
      local roleId = role.roleId or i
      orderedRoles[roleId] = role
    end
  end
  
  -- Get encounter data from nested structure via SVM
  local assignments = {}
  local raidMarks = {}
  local assignmentNumbers = {}
  
  -- Find raid and encounter by name (v2 schema uses numeric indices but stores names)
  local allRaids = OGRH.SVM.GetPath('encounterMgmt.raids')
  local encounter = nil
  if allRaids then
    for raidIdx = 1, table.getn(allRaids) do
      if allRaids[raidIdx].name == selectedRaid and allRaids[raidIdx].encounters then
        for encIdx = 1, table.getn(allRaids[raidIdx].encounters) do
          if allRaids[raidIdx].encounters[encIdx].name == selectedEncounter then
            encounter = allRaids[raidIdx].encounters[encIdx]
            break
          end
        end
        if encounter then break end
      end
    end
  end
  
  -- Collect data from roles within encounter
  if encounter and encounter.roles then
    for roleIdx = 1, table.getn(encounter.roles) do
      local role = encounter.roles[roleIdx]
      if role then
        if role.assignedPlayers then
          assignments[roleIdx] = role.assignedPlayers
        end
        if role.raidMarks then
          raidMarks[roleIdx] = role.raidMarks
        end
        if role.assignmentNumbers then
          assignmentNumbers[roleIdx] = role.assignmentNumbers
        end
      end
    end
  end
  
  local announcementData = nil
  if encounter then
    announcementData = encounter.announcements
  end
  
  if not announcementData then
    return
  end
  
  -- Process announcement lines exactly as they would be sent to chat
  GameTooltip:SetOwner(anchorFrame, "ANCHOR_RIGHT")
  GameTooltip:ClearLines()
  
  local hasLines = false
  for i = 1, 20 do
    local lineText = announcementData[i]
    if lineText and lineText ~= "" then
      local processedText = OGRH.Announcements.ReplaceTags(lineText, orderedRoles, assignments, raidMarks, assignmentNumbers)
      
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
    OGRH.ShowEncounterPlanning()
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
    -- Create menu using the standard menu builder
    local menu = OGRH.CreateStandardMenu({
      name = "OGRH_EncounterRaidMenu",
      width = 160,
      itemColor = {1, 1, 1} -- White menu items to match main menu
    })
    
    OGRH_EncounterRaidMenu = menu
    
    menu.Rebuild = function()
      -- Clear existing items
      for _, item in ipairs(menu.items) do
        item:Hide()
        item:SetParent(nil)
      end
      menu.items = {}
      
      -- Reset yOffset for rebuilding
      menu.yOffset = -5
      
      if not OGRH_SV.encounterMgmt or not OGRH_SV.encounterMgmt.raids then
        menu:Finalize()
        return
      end
      
      local raids = OGRH_SV.encounterMgmt.raids
      
      for i = 1, table.getn(raids) do
        local raid = raids[i]
        local raidName = raid.name
        
        -- Get encounters for this raid (new structure only)
        local encounters = {}
        if raid.encounters then
          for j = 1, table.getn(raid.encounters) do
            table.insert(encounters, raid.encounters[j].name)
          end
        end
        
        -- Build submenu items for encounters
        local submenuItems = {}
        for j = 1, table.getn(encounters) do
          local encounterName = encounters[j]
          local capturedRaid = raidName
          local capturedEncounter = encounterName
          
          table.insert(submenuItems, {
            text = encounterName,
            onClick = function()
              -- Check authorization
              if not OGRH.CanNavigateEncounter or not OGRH.CanNavigateEncounter() then
                OGRH.Msg("Only the Raid Leader, Assistants, or Raid Admin can change the selected encounter.")
                return
              end
              
              -- Update encounter using centralized setter (triggers REALTIME sync)
              OGRH.SetCurrentEncounter(capturedRaid, capturedEncounter)
              
              -- Update UI
              OGRH.UpdateEncounterNavButton()
              if OGRH.ShowConsumeMonitor then
                OGRH.ShowConsumeMonitor()
              end
            end
          })
        end
        
        -- Add raid item with encounter submenu
        menu:AddItem({
          text = raidName,
          submenu = submenuItems
        })
      end
      
      menu:Finalize()
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
  
  -- Get role configuration from v2 schema
  local allRaids = OGRH.SVM.GetPath('encounterMgmt.raids')
  local encounter = nil
  if allRaids then
    for i = 1, table.getn(allRaids) do
      if allRaids[i].name == selectedRaid and allRaids[i].encounters then
        for j = 1, table.getn(allRaids[i].encounters) do
          if allRaids[i].encounters[j].name == selectedEncounter then
            encounter = allRaids[i].encounters[j]
            break
          end
        end
        break
      end
    end
  end
  
  if not encounter or not encounter.roles then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OGRH:|r No roles configured for this encounter.")
    return
  end
  
  -- Build column1 and column2 from roles array
  local column1 = {}
  local column2 = {}
  for i = 1, table.getn(encounter.roles) do
    local role = encounter.roles[i]
    if role.column == 1 then
      table.insert(column1, role)
    elseif role.column == 2 then
      table.insert(column2, role)
    end
  end
  
  -- Build ordered list of all roles using stable roleId
  local allRoles = {}
  
  for i = 1, table.getn(column1) do
    table.insert(allRoles, {role = column1[i], roleIndex = column1[i].roleId or (table.getn(allRoles) + 1)})
  end
  for i = 1, table.getn(column2) do
    table.insert(allRoles, {role = column2[i], roleIndex = column2[i].roleId or (table.getn(allRoles) + 1)})
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
  
  -- Get assignments and raidMarks from nested role objects
  local assignments = {}
  local raidMarks = {}
  
  -- Find raid and encounter by name (v2 schema)
  local allRaids = OGRH.SVM.GetPath('encounterMgmt.raids')
  local encounter = nil
  if allRaids then
    for raidIdx = 1, table.getn(allRaids) do
      if allRaids[raidIdx].name == selectedRaid and allRaids[raidIdx].encounters then
        for encIdx = 1, table.getn(allRaids[raidIdx].encounters) do
          if allRaids[raidIdx].encounters[encIdx].name == selectedEncounter then
            encounter = allRaids[raidIdx].encounters[encIdx]
            break
          end
        end
        if encounter then break end
      end
    end
  end
  
  -- Collect data from roles within encounter
  if encounter and encounter.roles then
    for roleIdx = 1, table.getn(encounter.roles) do
      local role = encounter.roles[roleIdx]
      if role then
        if role.assignedPlayers then
          assignments[roleIdx] = role.assignedPlayers
        end
        if role.raidMarks then
          raidMarks[roleIdx] = role.raidMarks
        end
      end
    end
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

-- ========================================
-- EXPORT RAID WINDOW
-- ========================================

-- Helper function to strip WoW color codes
local function StripColorCodes(text)
  if not text then return "" end
  -- Remove |cFFxxxxxx and |r tags
  local stripped = string.gsub(text, "|c[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]", "")
  stripped = string.gsub(stripped, "|r", "")
  -- Remove raid icons {rt1} etc
  stripped = string.gsub(stripped, "{rt%d}", "")
  return stripped
end

-- Helper function to convert WoW color codes to RGB hex for HTML
local function ConvertColorToHex(colorCode)
  if not colorCode then return "000000" end
  -- Extract RRGGBB from |cFFRRGGBB or |cAARRGGBB
  local hex = string.match(colorCode, "|c[0-9a-fA-F][0-9a-fA-F]([0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F])")
  return hex or "FFFFFF"
end

-- Helper function to escape CSV fields
local function EscapeCSV(text)
  if not text then return "" end
  -- Strip color codes first
  text = StripColorCodes(text)
  -- If contains comma, quote, or newline, wrap in quotes and escape quotes
  if string.find(text, '[,"\n]') then
    text = string.gsub(text, '"', '""')
    return '"' .. text .. '"'
  end
  return text
end

function OGRH.ShowExportRaidWindow(raidName)
  if not raidName then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OGRH:|r No raid selected.")
    return
  end
  
  -- Build export data structure
  local exportData = {}
  exportData.raidName = raidName
  exportData.encounters = {}
  
  -- Get encounters for this raid (new structure only)
  local raid = OGRH.FindRaidByName(raidName)
  if not raid or not raid.encounters then
    OGRH.Msg("No encounters found for " .. raidName)
    return
  end
  
  local encounters = {}
  for i = 1, table.getn(raid.encounters) do
    table.insert(encounters, raid.encounters[i].name)
  end
  
  -- Process each encounter
  for i = 1, table.getn(encounters) do
    local encounterName = encounters[i]
    local encounterData = {
      name = encounterName, 
      announcements = {},
      roles = {},
      assignments = {},
      raidMarks = {},
      assignmentNumbers = {}
    }
    
    -- Get announcement data from nested encounter structure via SVM
    local allRaids = OGRH.SVM.GetPath('encounterMgmt.raids')
    local announcementData = nil
    if allRaids then
      -- Find raid index by name
      for raidIdx = 1, table.getn(allRaids) do
        if allRaids[raidIdx].name == raidName then
          -- Find encounter index by name
          if allRaids[raidIdx].encounters then
            for encIdx = 1, table.getn(allRaids[raidIdx].encounters) do
              if allRaids[raidIdx].encounters[encIdx].name == encounterName then
                local encounter = allRaids[raidIdx].encounters[encIdx]
                announcementData = encounter.announcements
                -- Collect data from roles within encounter
                if encounter.roles then
                  for roleIdx = 1, table.getn(encounter.roles) do
                    local role = encounter.roles[roleIdx]
                    if role then
                      if role.assignedPlayers then
                        encounterData.assignments[roleIdx] = role.assignedPlayers
                      end
                      if role.raidMarks then
                        encounterData.raidMarks[roleIdx] = role.raidMarks
                      end
                      if role.assignmentNumbers then
                        encounterData.assignmentNumbers[roleIdx] = role.assignmentNumbers
                      end
                    end
                  end
                end
                break
              end
            end
          end
          break
        end
      end
    end
    
    if announcementData then
      
      -- Get role configuration from v2 schema (already have encounter from above)
      local orderedRoles = {}
      if encounter.roles then
        for j = 1, table.getn(encounter.roles) do
          table.insert(orderedRoles, encounter.roles[j])
        end
      end
      encounterData.roles = orderedRoles
      
      -- Note: assignments, raidMarks, assignmentNumbers already populated above from nested encounter structure
      
      -- Process announcement lines
      for j = 1, table.getn(announcementData) do
        local lineText = announcementData[j]
        if lineText and lineText ~= "" then
          local processedText = OGRH.Announcements.ReplaceTags(lineText, orderedRoles, encounterData.assignments, encounterData.raidMarks, encounterData.assignmentNumbers)
          if processedText and processedText ~= "" then
            table.insert(encounterData.announcements, processedText)
          end
        end
      end
    end
    
    table.insert(exportData.encounters, encounterData)
  end
  
  -- Function to generate plain text format
  local function GeneratePlainText(data)
    local lines = {}
    table.insert(lines, "=== " .. data.raidName .. " ===")
    table.insert(lines, "")
    
    for i = 1, table.getn(data.encounters) do
      local encounter = data.encounters[i]
      table.insert(lines, "--- " .. encounter.name .. " ---")
      for j = 1, table.getn(encounter.announcements) do
        table.insert(lines, StripColorCodes(encounter.announcements[j]))
      end
      table.insert(lines, "")
    end
    
    return table.concat(lines, "\n")
  end
  
  -- Function to generate CSV format (for Google Sheets)
  local function GenerateCSV(data)
    local lines = {}
    table.insert(lines, "Raid,Encounter,R.T,R.M,R.P,R.A")
    
    for i = 1, table.getn(data.encounters) do
      local encounter = data.encounters[i]
      local roles = encounter.roles
      local assignments = encounter.assignments
      local raidMarks = encounter.raidMarks
      local assignmentNumbers = encounter.assignmentNumbers
      
      -- Iterate through each role
      for roleIndex = 1, table.getn(roles) do
        local role = roles[roleIndex]
        if assignments[roleIndex] then
          -- Get all assigned players for this role
          local roleAssignments = assignments[roleIndex]
          
          for slotIndex = 1, table.getn(roleAssignments) do
            local playerName = roleAssignments[slotIndex]
            if playerName and playerName ~= "" then
              -- Get role title
              local roleTitle = role.title or ""
              
              -- Get mark index
              local markIndex = 0
              if raidMarks[roleIndex] and raidMarks[roleIndex][slotIndex] then
                markIndex = raidMarks[roleIndex][slotIndex]
              end
              
              -- Get assignment number
              local assignmentNum = 0
              if assignmentNumbers[roleIndex] and assignmentNumbers[roleIndex][slotIndex] then
                assignmentNum = assignmentNumbers[roleIndex][slotIndex]
              end
              
              -- Build role tags
              local roleTag = "R" .. roleIndex .. ".T"
              local markTag = "R" .. roleIndex .. ".M" .. slotIndex
              local playerTag = "R" .. roleIndex .. ".P" .. slotIndex
              local assignTag = "R" .. roleIndex .. ".A" .. slotIndex
              
              -- Build CSV line with actual values
              local line = EscapeCSV(data.raidName) .. "," ..
                           EscapeCSV(encounter.name) .. "," ..
                           EscapeCSV(roleTitle) .. "," ..
                           (markIndex > 0 and tostring(markIndex) or "") .. "," ..
                           EscapeCSV(playerName) .. "," ..
                           (assignmentNum > 0 and tostring(assignmentNum) or "")
              table.insert(lines, line)
            end
          end
        end
      end
    end
    
    return table.concat(lines, "\n")
  end
  
  -- Function to generate HTML format (preserves colors)
  local function GenerateHTML(data)
    local lines = {}
    table.insert(lines, "<html><head><style>")
    table.insert(lines, "body { font-family: Arial, sans-serif; background: #000; color: #fff; }")
    table.insert(lines, "h1 { color: #FFD100; }")
    table.insert(lines, "h2 { color: #00FF00; margin-top: 20px; }")
    table.insert(lines, ".announcement { margin: 5px 0; }")
    table.insert(lines, "</style></head><body>")
    table.insert(lines, "<h1>" .. data.raidName .. "</h1>")
    
    for i = 1, table.getn(data.encounters) do
      local encounter = data.encounters[i]
      table.insert(lines, "<h2>" .. encounter.name .. "</h2>")
      
      for j = 1, table.getn(encounter.announcements) do
        local text = encounter.announcements[j]
        local htmlText = ""
        local pos = 1
        local inColor = false
        local currentColor = "FFFFFF"
        
        while pos <= string.len(text) do
          -- Check for color code
          local colorStart, colorEnd, colorCode = string.find(text, "(|c[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F])", pos)
          local resetStart = string.find(text, "|r", pos)
          
          if colorStart == pos then
            if inColor then
              htmlText = htmlText .. "</span>"
            end
            currentColor = ConvertColorToHex(colorCode)
            htmlText = htmlText .. '<span style="color:#' .. currentColor .. ';">'
            inColor = true
            pos = colorEnd + 1
          elseif resetStart == pos then
            if inColor then
              htmlText = htmlText .. "</span>"
              inColor = false
            end
            pos = resetStart + 2
          else
            -- Regular character
            local char = string.sub(text, pos, pos)
            if char == "<" then
              htmlText = htmlText .. "&lt;"
            elseif char == ">" then
              htmlText = htmlText .. "&gt;"
            elseif char == "&" then
              htmlText = htmlText .. "&amp;"
            else
              htmlText = htmlText .. char
            end
            pos = pos + 1
          end
        end
        
        if inColor then
          htmlText = htmlText .. "</span>"
        end
        
        -- Remove raid icon tags
        htmlText = string.gsub(htmlText, "{rt%d}", "")
        
        table.insert(lines, '<div class="announcement">' .. htmlText .. '</div>')
      end
    end
    
    table.insert(lines, "</body></html>")
    return table.concat(lines, "\n")
  end
  
  -- Default to plain text
  local currentFormat = "plain"
  local exportText = GeneratePlainText(exportData)
  
  -- Create or show export window
  local exportFrame = CreateFrame("Frame", "OGRH_ExportRaidFrame", UIParent)
  exportFrame:SetWidth(600)
  exportFrame:SetHeight(400)
  exportFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  exportFrame:SetFrameStrata("FULLSCREEN_DIALOG")
  exportFrame:EnableMouse(true)
  exportFrame:SetMovable(true)
  exportFrame:RegisterForDrag("LeftButton")
  exportFrame:SetScript("OnDragStart", function() exportFrame:StartMoving() end)
  exportFrame:SetScript("OnDragStop", function() exportFrame:StopMovingOrSizing() end)
  
  exportFrame:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 16,
    insets = {left = 4, right = 4, top = 4, bottom = 4}
  })
  exportFrame:SetBackdropColor(0, 0, 0, 0.9)
  
  -- Title
  local title = exportFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOP", exportFrame, "TOP", 0, -15)
  title:SetText("Export Raid: " .. raidName)
  
  -- Close button
  local closeBtn = CreateFrame("Button", nil, exportFrame, "UIPanelButtonTemplate")
  closeBtn:SetWidth(60)
  closeBtn:SetHeight(24)
  closeBtn:SetPoint("TOPRIGHT", exportFrame, "TOPRIGHT", -10, -10)
  closeBtn:SetText("Close")
  OGRH.StyleButton(closeBtn)
  closeBtn:SetScript("OnClick", function() 
    exportFrame:Hide()
    exportFrame:SetParent(nil)
  end)
  
  -- Instructions
  local instructions = exportFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  instructions:SetPoint("TOPLEFT", exportFrame, "TOPLEFT", 15, -45)
  instructions:SetText("Select format:")
  
  -- Format buttons
  local plainTextBtn = CreateFrame("Button", nil, exportFrame, "UIPanelButtonTemplate")
  plainTextBtn:SetWidth(90)
  plainTextBtn:SetHeight(22)
  plainTextBtn:SetPoint("TOPLEFT", instructions, "BOTTOMLEFT", 0, -4)
  plainTextBtn:SetText("Plain Text")
  OGRH.StyleButton(plainTextBtn)
  
  local csvBtn = CreateFrame("Button", nil, exportFrame, "UIPanelButtonTemplate")
  csvBtn:SetWidth(130)
  csvBtn:SetHeight(22)
  csvBtn:SetPoint("LEFT", plainTextBtn, "RIGHT", 5, 0)
  csvBtn:SetText("CSV (Spreadsheet)")
  OGRH.StyleButton(csvBtn)
  
  local htmlBtn = CreateFrame("Button", nil, exportFrame, "UIPanelButtonTemplate")
  htmlBtn:SetWidth(120)
  htmlBtn:SetHeight(22)
  htmlBtn:SetPoint("LEFT", csvBtn, "RIGHT", 5, 0)
  htmlBtn:SetText("HTML (Colors)")
  OGRH.StyleButton(htmlBtn)
  
  -- Copy instructions
  local copyInstructions = exportFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  copyInstructions:SetPoint("TOPLEFT", plainTextBtn, "BOTTOMLEFT", 0, -8)
  copyInstructions:SetText("Copy: Ctrl+A to select all, Ctrl+C to copy")
  copyInstructions:SetTextColor(0.7, 0.7, 0.7)
  
  -- Text box using standard scrolling text box
  local textBackdrop, textBox, scrollFrame, scrollBar = OGRH.CreateScrollingTextBox(exportFrame, 570, 240)
  textBackdrop:SetPoint("TOPLEFT", copyInstructions, "BOTTOMLEFT", 0, -8)
  
  textBox:SetText(exportText)
  textBox:SetScript("OnEscapePressed", function() textBox:ClearFocus() end)
  
  -- Format button handlers
  plainTextBtn:SetScript("OnClick", function()
    currentFormat = "plain"
    textBox:SetText(GeneratePlainText(exportData))
    textBox:HighlightText()
    textBox:SetFocus()
  end)
  
  csvBtn:SetScript("OnClick", function()
    currentFormat = "csv"
    textBox:SetText(GenerateCSV(exportData))
    textBox:HighlightText()
    textBox:SetFocus()
  end)
  
  htmlBtn:SetScript("OnClick", function()
    currentFormat = "html"
    textBox:SetText(GenerateHTML(exportData))
    textBox:HighlightText()
    textBox:SetFocus()
  end)
  
  -- Highlight text on show
  textBox:HighlightText()
  textBox:SetFocus()
  
  exportFrame:Show()
  
  -- Register ESC key handler after showing to ensure it's closed first
  OGRH.MakeFrameCloseOnEscape(exportFrame, "OGRH_ExportRaidFrame")
end

-- ========================================
-- ADVANCED SETTINGS DATA LAYER (Phase 2)
-- ========================================

-- Helper function to find raid by name (supports new nested structure)
function OGRH.FindRaidByName(raidName)
  OGRH.EnsureSV()
  
  -- Use SVM to get raids from active schema (v1 or v2)
  local raids = OGRH.SVM.GetPath("encounterMgmt.raids")
  if not raids then
    return nil
  end
  
  -- Search array for raid with matching name
  for i = 1, table.getn(raids) do
    local raid = raids[i]
    if raid.name == raidName then
      return raid
    end
  end
  
  return nil
end

-- Helper function to find encounter by name within a raid (new structure only)
function OGRH.FindEncounterByName(raid, encounterName)
  if not raid or not encounterName then
    return nil
  end
  
  -- New structure only: raid has encounters array
  if raid.encounters and type(raid.encounters) == "table" then
    for i = 1, table.getn(raid.encounters) do
      local encounter = raid.encounters[i]
      if type(encounter) == "table" and encounter.name == encounterName then
        return encounter
      end
    end
  end
  
  return nil
end

-- Ensure raid has advanced settings structure
function OGRH.EnsureRaidAdvancedSettings(raid)
  if not raid then
    return
  end
  
  if not raid.advancedSettings then
    raid.advancedSettings = {
      bigwigs = {
        enabled = false,
        raidZone = ""
      },
      consumeTracking = {
        enabled = false,
        readyThreshold = 85,
        requiredFlaskRoles = {
          ["Tanks"] = false,
          ["Healers"] = false,
          ["Melee"] = false,
          ["Ranged"] = false,
        }
      }
    }
  end
  
  -- Ensure sub-tables exist (for upgrades)
  if not raid.advancedSettings.bigwigs then
    raid.advancedSettings.bigwigs = {
      enabled = false,
      raidZone = ""
    }
  end
  
  if not raid.advancedSettings.consumeTracking then
    raid.advancedSettings.consumeTracking = {
      enabled = false,
      readyThreshold = 85,
      requiredFlaskRoles = {
        ["Tanks"] = false,
        ["Healers"] = false,
        ["Melee"] = false,
        ["Ranged"] = false,
      }
    }
  end
  
  -- Ensure requiredFlaskRoles exists
  if not raid.advancedSettings.consumeTracking.requiredFlaskRoles then
    raid.advancedSettings.consumeTracking.requiredFlaskRoles = {
      ["Tanks"] = false,
      ["Healers"] = false,
      ["Melee"] = false,
      ["Ranged"] = false,
    }
  end
end

-- Ensure encounter has advanced settings structure
function OGRH.EnsureEncounterAdvancedSettings(raid, encounter)
  if not encounter then
    return
  end
  
  if not encounter.advancedSettings then
    encounter.advancedSettings = {
      bigwigs = {
        enabled = false,
        encounterId = ""
      },
      consumeTracking = {
        enabled = nil,  -- nil = inherit from raid
        readyThreshold = nil,  -- nil = inherit from raid
        requiredFlaskRoles = {}
      }
    }
  end
  
  -- Ensure sub-tables exist (for upgrades)
  if not encounter.advancedSettings.bigwigs then
    encounter.advancedSettings.bigwigs = {
      enabled = false,
      encounterId = ""
    }
  end
  
  if not encounter.advancedSettings.consumeTracking then
    encounter.advancedSettings.consumeTracking = {
      enabled = nil,
      readyThreshold = nil,
      requiredFlaskRoles = {}
    }
  end
end

-- Get advanced settings for currently selected raid
function OGRH.GetCurrentRaidAdvancedSettings()
  local frame = OGRH_EncounterFrame
  if not frame or not frame.selectedRaid then
    DEFAULT_CHAT_FRAME:AddMessage("[OGRH Debug] Load failed: no frame or selectedRaid")
    return nil
  end
  
  local raid = OGRH.FindRaidByName(frame.selectedRaid)
  if not raid then
    DEFAULT_CHAT_FRAME:AddMessage("[OGRH Debug] Load failed: raid not found")
    return nil
  end
  
  OGRH.EnsureRaidAdvancedSettings(raid)
  
  return raid.advancedSettings
end

-- Save advanced settings for currently selected raid
function OGRH.SaveCurrentRaidAdvancedSettings(settings)
  local frame = OGRH_EncounterFrame
  if not frame or not frame.selectedRaid then
    DEFAULT_CHAT_FRAME:AddMessage("[OGRH Debug] Save failed: no frame or selectedRaid")
    return false
  end
  
  local raid = OGRH.FindRaidByName(frame.selectedRaid)
  if not raid then
    DEFAULT_CHAT_FRAME:AddMessage("[OGRH Debug] Save failed: raid not found")
    return false
  end
  
  raid.advancedSettings = settings
  return true
end

-- Get advanced settings for currently selected encounter
function OGRH.GetCurrentEncounterAdvancedSettings()
  local frame = OGRH_EncounterFrame
  if not frame or not frame.selectedRaid or not frame.selectedEncounter then
    return nil
  end
  
  local raid = OGRH.FindRaidByName(frame.selectedRaid)
  if not raid then return nil end
  
  local encounter = OGRH.FindEncounterByName(raid, frame.selectedEncounter)
  if not encounter then
    return nil
  end
  
  OGRH.EnsureEncounterAdvancedSettings(raid, encounter)
  return encounter.advancedSettings
end

-- Save advanced settings for currently selected encounter
function OGRH.SaveCurrentEncounterAdvancedSettings(settings)
  local frame = OGRH_EncounterFrame
  if not frame or not frame.selectedRaid or not frame.selectedEncounter then
    return false
  end
  
  local raid = OGRH.FindRaidByName(frame.selectedRaid)
  if not raid then return false end
  
  local encounter = OGRH.FindEncounterByName(raid, frame.selectedEncounter)
  if not encounter then
    return false
  end
  
  encounter.advancedSettings = settings
  return true
end

-- Note: Encounter frame is created on-demand when first accessed, not on load

-- DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[RaidHelper]|r Encounter Management loaded")
