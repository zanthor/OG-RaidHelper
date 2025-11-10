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
function OGRH.ShowBWLEncounterWindow(encounterName)
  -- Create or show the window
  if not OGRH_BWLEncounterFrame then
    local frame = CreateFrame("Frame", "OGRH_BWLEncounterFrame", UIParent)
    frame:SetWidth(800)
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
    
    -- Title bar
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", frame, "TOP", 0, -10)
    title:SetText("Encounter Planning")
    frame.title = title
    
    -- Pool Defaults button (top left)
    local poolDefaultsBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    poolDefaultsBtn:SetWidth(100)
    poolDefaultsBtn:SetHeight(24)
    poolDefaultsBtn:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -10)
    poolDefaultsBtn:SetText("Pool Defaults")
    poolDefaultsBtn:SetScript("OnClick", function()
      OGRH.ShowPoolDefaultsWindow()
    end)
    
    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    closeBtn:SetWidth(60)
    closeBtn:SetHeight(24)
    closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -10)
    closeBtn:SetText("Close")
    closeBtn:SetScript("OnClick", function() frame:Hide() end)
    
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
    
    -- Raids list frame
    local raidsListFrame = CreateFrame("Frame", nil, leftPanel)
    raidsListFrame:SetPoint("TOPLEFT", raidsLabel, "BOTTOMLEFT", 0, -5)
    raidsListFrame:SetWidth(155)
    raidsListFrame:SetHeight(165)
    raidsListFrame:SetBackdrop({
      bgFile = "Interface/Tooltips/UI-Tooltip-Background",
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
      tile = true,
      tileSize = 16,
      edgeSize = 12,
      insets = {left = 3, right = 3, top = 3, bottom = 3}
    })
    raidsListFrame:SetBackdropColor(0.15, 0.15, 0.15, 0.9)
    
    -- Create scroll frame for raids
    local raidsScrollFrame = CreateFrame("ScrollFrame", nil, raidsListFrame)
    raidsScrollFrame:SetPoint("TOPLEFT", raidsListFrame, "TOPLEFT", 5, -5)
    raidsScrollFrame:SetPoint("BOTTOMRIGHT", raidsListFrame, "BOTTOMRIGHT", -5, 5)
    
    local raidsScrollChild = CreateFrame("Frame", nil, raidsScrollFrame)
    raidsScrollChild:SetWidth(145)
    raidsScrollChild:SetHeight(1)
    raidsScrollFrame:SetScrollChild(raidsScrollChild)
    frame.raidsScrollChild = raidsScrollChild
    frame.raidsScrollFrame = raidsScrollFrame
    
    -- Enable mouse wheel scrolling for raids list
    raidsScrollFrame:EnableMouseWheel(true)
    raidsScrollFrame:SetScript("OnMouseWheel", function()
      local delta = arg1
      local current = raidsScrollFrame:GetVerticalScroll()
      local maxScroll = raidsScrollChild:GetHeight() - raidsScrollFrame:GetHeight()
      if maxScroll < 0 then maxScroll = 0 end
      
      local newScroll = current - (delta * 20)
      if newScroll < 0 then
        newScroll = 0
      elseif newScroll > maxScroll then
        newScroll = maxScroll
      end
      raidsScrollFrame:SetVerticalScroll(newScroll)
    end)
    
    -- Encounters label
    local encountersLabel = leftPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    encountersLabel:SetPoint("TOPLEFT", raidsListFrame, "BOTTOMLEFT", 0, -10)
    encountersLabel:SetText("Encounters:")
    
    -- Encounters list frame
    local encountersListFrame = CreateFrame("Frame", nil, leftPanel)
    encountersListFrame:SetPoint("TOPLEFT", encountersLabel, "BOTTOMLEFT", 0, -5)
    encountersListFrame:SetWidth(155)
    encountersListFrame:SetHeight(165)
    encountersListFrame:SetBackdrop({
      bgFile = "Interface/Tooltips/UI-Tooltip-Background",
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
      tile = true,
      tileSize = 16,
      edgeSize = 12,
      insets = {left = 3, right = 3, top = 3, bottom = 3}
    })
    encountersListFrame:SetBackdropColor(0.15, 0.15, 0.15, 0.9)
    
    -- Create scroll frame for encounters
    local encountersScrollFrame = CreateFrame("ScrollFrame", nil, encountersListFrame)
    encountersScrollFrame:SetPoint("TOPLEFT", encountersListFrame, "TOPLEFT", 5, -5)
    encountersScrollFrame:SetPoint("BOTTOMRIGHT", encountersListFrame, "BOTTOMRIGHT", -5, 5)
    
    local encountersScrollChild = CreateFrame("Frame", nil, encountersScrollFrame)
    encountersScrollChild:SetWidth(145)
    encountersScrollChild:SetHeight(1)
    encountersScrollFrame:SetScrollChild(encountersScrollChild)
    frame.encountersScrollChild = encountersScrollChild
    frame.encountersScrollFrame = encountersScrollFrame
    
    -- Enable mouse wheel scrolling for encounters list
    encountersScrollFrame:EnableMouseWheel(true)
    encountersScrollFrame:SetScript("OnMouseWheel", function()
      local delta = arg1
      local current = encountersScrollFrame:GetVerticalScroll()
      local maxScroll = encountersScrollChild:GetHeight() - encountersScrollFrame:GetHeight()
      if maxScroll < 0 then maxScroll = 0 end
      
      local newScroll = current - (delta * 20)
      if newScroll < 0 then
        newScroll = 0
      elseif newScroll > maxScroll then
        newScroll = maxScroll
      end
      encountersScrollFrame:SetVerticalScroll(newScroll)
    end)
    
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
        local raidBtn = CreateFrame("Button", nil, scrollChild)
        raidBtn:SetWidth(145)
        raidBtn:SetHeight(20)
        raidBtn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, yOffset)
        
        -- Background
        local bg = raidBtn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetTexture("Interface\\Buttons\\WHITE8X8")
        if frame.selectedRaid == raidName then
          bg:SetVertexColor(0.2, 0.4, 0.2, 0.8)
        else
          bg:SetVertexColor(0.2, 0.2, 0.2, 0.5)
        end
        raidBtn.bg = bg
        
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
          RefreshRaidsList()
          if frame.RefreshEncountersList then
            frame.RefreshEncountersList()
          end
          if frame.RefreshRoleContainers then
            frame.RefreshRoleContainers()
          end
        end)
        
        table.insert(frame.raidButtons, raidBtn)
        yOffset = yOffset - 22
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
      
      for i, encounterName in ipairs(encounters) do
        local encounterBtn = CreateFrame("Button", nil, scrollChild)
        encounterBtn:SetWidth(145)
        encounterBtn:SetHeight(20)
        encounterBtn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, yOffset)
        
        -- Background
        local bg = encounterBtn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetTexture("Interface\\Buttons\\WHITE8X8")
        if frame.selectedEncounter == encounterName then
          bg:SetVertexColor(0.2, 0.4, 0.2, 0.8)
        else
          bg:SetVertexColor(0.2, 0.2, 0.2, 0.5)
        end
        encounterBtn.bg = bg
        
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
          RefreshEncountersList()
          if frame.RefreshRoleContainers then
            frame.RefreshRoleContainers()
          end
        end)
        
        table.insert(frame.encounterButtons, encounterBtn)
        yOffset = yOffset - 22
      end
      
      -- Update scroll child height
      local contentHeight = math.abs(yOffset) + 5
      scrollChild:SetHeight(contentHeight)
    end
    
    frame.RefreshEncountersList = RefreshEncountersList
    
    -- Top right panel: Role assignment area (60% of original height = 234px)
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
    
    -- Auto Assign button
    local autoAssignBtn = CreateFrame("Button", nil, bottomPanel, "UIPanelButtonTemplate")
    autoAssignBtn:SetWidth(120)
    autoAssignBtn:SetHeight(30)
    autoAssignBtn:SetPoint("TOPLEFT", bottomPanel, "TOPLEFT", 10, -10)
    autoAssignBtn:SetText("Auto Assign")
    frame.autoAssignBtn = autoAssignBtn
    
    -- Auto Assign functionality
    autoAssignBtn:SetScript("OnClick", function()
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
      
      -- Build ordered list of all roles (interleaved by row)
      local allRoles = {}
      local maxRoles = math.max(table.getn(column1), table.getn(column2))
      
      for i = 1, maxRoles do
        if column1[i] then
          table.insert(allRoles, {role = column1[i], roleIndex = table.getn(allRoles) + 1})
        end
        if column2[i] then
          table.insert(allRoles, {role = column2[i], roleIndex = table.getn(allRoles) + 1})
        end
      end
      
      -- Track assigned players
      local assignedPlayers = {}  -- playerName -> first roleIndex assigned
      local roleAssignments = {}  -- roleIndex -> {player1, player2, ...}
      local assignmentCount = 0
      
      -- Process each role in order
      for _, roleData in ipairs(allRoles) do
        local role = roleData.role
        local roleIndex = roleData.roleIndex
        local maxPlayers = role.slots or 1
        
        roleAssignments[roleIndex] = {}
        
        -- Get pool for this role
        if not OGRH_SV.encounterPools then
          OGRH_SV.encounterPools = {}
        end
        if not OGRH_SV.encounterPools[frame.selectedRaid] then
          OGRH_SV.encounterPools[frame.selectedRaid] = {}
        end
        if not OGRH_SV.encounterPools[frame.selectedRaid][frame.selectedEncounter] then
          OGRH_SV.encounterPools[frame.selectedRaid][frame.selectedEncounter] = {}
        end
        if not OGRH_SV.encounterPools[frame.selectedRaid][frame.selectedEncounter][roleIndex] then
          OGRH_SV.encounterPools[frame.selectedRaid][frame.selectedEncounter][roleIndex] = {}
        end
        
        local pool = OGRH_SV.encounterPools[frame.selectedRaid][frame.selectedEncounter][roleIndex]
        
        -- Try to assign players from the pool
        local slotsAssigned = 0
        for i = 1, table.getn(pool) do
          if slotsAssigned >= maxPlayers then
            break
          end
          
          local playerName = pool[i]
          
          -- Check if player is already assigned
          local canAssign = true
          if assignedPlayers[playerName] then
            -- Player is already assigned to at least one role
            -- They can only be reused if ALL roles they're assigned to have allowOtherRoles = true
            canAssign = false
            
            local allRolesAllowReuse = true
            -- Check all roles this player is currently assigned to
            for checkRoleIndex, players in pairs(roleAssignments) do
              for _, assignedPlayer in ipairs(players) do
                if assignedPlayer == playerName then
                  -- Found this player in a role, check if that role allows other roles
                  local roleAllowsReuse = false
                  for _, checkRoleData in ipairs(allRoles) do
                    if checkRoleData.roleIndex == checkRoleIndex then
                      if checkRoleData.role.allowOtherRoles then
                        roleAllowsReuse = true
                      end
                      break
                    end
                  end
                  
                  if not roleAllowsReuse then
                    -- This player is in a role that doesn't allow reuse
                    allRolesAllowReuse = false
                    break
                  end
                end
              end
              
              if not allRolesAllowReuse then
                break
              end
            end
            
            if allRolesAllowReuse then
              canAssign = true
            end
          end
          
          if canAssign then
            -- Check if player is in raid and online
            local inRaid = false
            local isOnline = false
            
            for j = 1, GetNumRaidMembers() do
              local name, _, _, _, _, _, _, online = GetRaidRosterInfo(j)
              if name == playerName then
                inRaid = true
                isOnline = online
                break
              end
            end
            
            if inRaid and isOnline then
              -- Assign this player to the role
              if not assignedPlayers[playerName] then
                assignedPlayers[playerName] = roleIndex
              end
              table.insert(roleAssignments[roleIndex], playerName)
              slotsAssigned = slotsAssigned + 1
              assignmentCount = assignmentCount + 1
            end
          end
        end
      end
      
      -- Store assignments (roleIndex -> {player1, player2, ...})
      if not OGRH_SV.encounterAssignments then
        OGRH_SV.encounterAssignments = {}
      end
      if not OGRH_SV.encounterAssignments[frame.selectedRaid] then
        OGRH_SV.encounterAssignments[frame.selectedRaid] = {}
      end
      
      OGRH_SV.encounterAssignments[frame.selectedRaid][frame.selectedEncounter] = roleAssignments
      
      -- Refresh the display
      if frame.RefreshRoleContainers then
        frame.RefreshRoleContainers()
      end
      
      DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OGRH:|r Auto-assigned " .. assignmentCount .. " players.")
    end)
    
    -- Announce button (below Auto Assign)
    local announceBtn = CreateFrame("Button", nil, bottomPanel, "UIPanelButtonTemplate")
    announceBtn:SetWidth(120)
    announceBtn:SetHeight(30)
    announceBtn:SetPoint("TOPLEFT", autoAssignBtn, "BOTTOMLEFT", 0, -10)
    announceBtn:SetText("Announce")
    frame.announceBtn = announceBtn
    
    -- Function to replace tags in announcement text with colored output
    local function ReplaceTags(text, roles, assignments, raidMarks, assignmentNumbers)
      if not text or text == "" then
        return ""
      end
      
      -- Helper function to get player class
      local function GetPlayerClass(playerName)
        for j = 1, GetNumRaidMembers() do
          local name, _, _, _, playerClass = GetRaidRosterInfo(j)
          if name == playerName then
            return playerClass
          end
        end
        return nil
      end
      
      -- Helper function to check if a tag is valid (has a value)
      local function IsTagValid(tagText, assignmentNumbers)
        -- Check [Rx.T] tags
        local roleNum = string.match(tagText, "^%[R(%d+)%.T%]$")
        if roleNum then
          local roleIndex = tonumber(roleNum)
          return roles and roles[roleIndex] ~= nil
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
              if string.find(content, "%[R%d+%.[TPMA]") then
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
            local tagStart, tagEnd = string.find(contentToCheck, "%[R%d+%.[TPMA][^%]]*%]", pos)
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
          [1] = "{Star}",
          [2] = "{Circle}",
          [3] = "{Diamond}",
          [4] = "{Triangle}",
          [5] = "{Moon}",
          [6] = "{Square}",
          [7] = "{Cross}",
          [8] = "{Skull}"
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
      
      -- Sort replacements by position (descending) so we can replace from end to start
      table.sort(replacements, function(a, b) return a.startPos > b.startPos end)
      
      -- Build result string by replacing tags from end to start
      for _, repl in ipairs(replacements) do
        local before = string.sub(result, 1, repl.startPos - 1)
        local after = string.sub(result, repl.endPos + 1)
        
        if repl.text == "" then
          -- Empty replacement - just remove the tag
          result = before .. after
        else
          -- Non-empty replacement - add with color codes
          result = before .. repl.color .. repl.text .. OGRH.COLOR.RESET .. after
        end
      end
      
      -- Color any plain text with ROLE color
      -- Split by color codes to identify plain text
      local finalResult = ""
      local lastPos = 1
      
      while true do
        -- Find next color code
        local colorStart = string.find(result, "|c%x%x%x%x%x%x%x%x", lastPos)
        
        if not colorStart then
          -- No more color codes, add remaining text
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
    
    -- Announce functionality
    announceBtn:SetScript("OnClick", function()
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
      
      -- Build ordered list of roles for tag replacement
      local orderedRoles = {}
      local maxRoles = math.max(table.getn(column1), table.getn(column2))
      
      for i = 1, maxRoles do
        if column1[i] then
          table.insert(orderedRoles, column1[i])
        end
        if column2[i] then
          table.insert(orderedRoles, column2[i])
        end
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
    
    -- Mark Players button (below Announce)
    local markPlayersBtn = CreateFrame("Button", nil, bottomPanel, "UIPanelButtonTemplate")
    markPlayersBtn:SetWidth(120)
    markPlayersBtn:SetHeight(30)
    markPlayersBtn:SetPoint("TOPLEFT", announceBtn, "BOTTOMLEFT", 0, -10)
    markPlayersBtn:SetText("Mark Players")
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
      
      -- Build ordered list of all roles (interleaved by row)
      local allRoles = {}
      local maxRoles = math.max(table.getn(column1), table.getn(column2))
      
      for i = 1, maxRoles do
        if column1[i] then
          table.insert(allRoles, {role = column1[i], roleIndex = table.getn(allRoles) + 1})
        end
        if column2[i] then
          table.insert(allRoles, {role = column2[i], roleIndex = table.getn(allRoles) + 1})
        end
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
            -- Only apply marks if role has markPlayer enabled
            if role.markPlayer then
              -- Find player in raid
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
    announcementScrollBar:SetPoint("TOPRIGHT", announcementScrollFrame, "TOPRIGHT", -5, -18)
    announcementScrollBar:SetPoint("BOTTOMRIGHT", announcementScrollFrame, "BOTTOMRIGHT", -5, 18)
    announcementScrollBar:SetWidth(16)
    announcementScrollBar:SetOrientation("VERTICAL")
    announcementScrollBar:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
    announcementScrollBar:SetBackdrop({
      bgFile = "Interface/Tooltips/UI-Tooltip-Background",
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
      tile = true,
      tileSize = 16,
      edgeSize = 8,
      insets = {left = 3, right = 3, top = 3, bottom = 3}
    })
    announcementScrollBar:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
    announcementScrollBar:SetMinMaxValues(0, 1)
    announcementScrollBar:SetValue(0)
    announcementScrollBar:SetValueStep(1)
    announcementScrollBar:SetScript("OnValueChanged", function()
      announcementScrollFrame:SetVerticalScroll(this:GetValue())
    end)
    
    -- Mouse wheel scroll support
    announcementScrollFrame:EnableMouseWheel(true)
    announcementScrollFrame:SetScript("OnMouseWheel", function()
      local currentScroll = announcementScrollBar:GetValue()
      local minScroll, maxScroll = announcementScrollBar:GetMinMaxValues()
      local delta = arg1
      
      if delta > 0 then
        -- Scroll up
        announcementScrollBar:SetValue(math.max(minScroll, currentScroll - 20))
      else
        -- Scroll down
        announcementScrollBar:SetValue(math.min(maxScroll, currentScroll + 20))
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
    
    -- Function to refresh role containers based on selected encounter
    local function RefreshRoleContainers()
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
        
        -- Pool button (top right)
        local poolBtn = CreateFrame("Button", nil, container, "UIPanelButtonTemplate")
        poolBtn:SetWidth(40)
        poolBtn:SetHeight(18)
        poolBtn:SetPoint("TOPRIGHT", container, "TOPRIGHT", -5, -5)
        poolBtn:SetText("Pool")
        
        local capturedRole = role
        local capturedRoleIndex = roleIndex
        poolBtn:SetScript("OnClick", function()
          OGRH.ShowEncounterPoolWindow(frame.selectedRaid, frame.selectedEncounter, capturedRole, capturedRoleIndex)
        end)
        
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
            nameText:SetPoint("RIGHT", slot, "RIGHT", -25, 0)
            
            local assignBtn = CreateFrame("Button", nil, slot)
            assignBtn:SetWidth(20)
            assignBtn:SetHeight(16)
            assignBtn:SetPoint("RIGHT", slot, "RIGHT", -3, 0)
            
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
            
            -- Tag marker for assignment (Ax) - positioned to the left of the button
            local assignTag = slot:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            assignTag:SetPoint("RIGHT", assignBtn, "LEFT", -4, 0)
            assignTag:SetText("|cff888888A" .. i .. "|r")
            assignTag:SetTextColor(0.5, 0.5, 0.5)
            slot.assignTag = assignTag
            
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
            nameText:SetPoint("RIGHT", slot, "RIGHT", -5, 0)
          end
          
          nameText:SetJustifyH("LEFT")
          slot.nameText = nameText
          
          -- Store slot info for assignment lookup
          slot.roleIndex = capturedRoleIndex
          slot.slotIndex = i
          
          -- Create a BUTTON for drag/drop (overlays the name area, RolesUI pattern)
          local dragBtn = CreateFrame("Button", nil, slot)
          dragBtn:SetPoint("LEFT", nameText, "LEFT", -5, 0)
          dragBtn:SetPoint("RIGHT", slot, "RIGHT", -5, 0)
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
            
            if not frame.draggedPlayer then return end
            
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
              else
                -- Just move: clear source position
                OGRH_SV.encounterAssignments[frame.selectedRaid][frame.selectedEncounter][frame.draggedFromRole][frame.draggedFromSlot] = nil
              end
            end
            
            -- Clear visual feedback
            this.parentSlot.bg:SetVertexColor(0.1, 0.1, 0.1, 0.8)
            
            -- Clear drag data
            frame.draggedPlayer = nil
            frame.draggedFromRole = nil
            frame.draggedFromSlot = nil
            
            -- Refresh display
            if frame.RefreshRoleContainers then
              frame.RefreshRoleContainers()
            end
          end)
          
          -- Click handler on button
          dragBtn:SetScript("OnClick", function()
            local button = arg1 or "LeftButton"
            local slotRoleIndex = this.roleIndex
            local slotSlotIndex = this.slotIndex
            
            if button == "RightButton" then
              -- Right click: Unassign player
              if OGRH_SV.encounterAssignments and
                 OGRH_SV.encounterAssignments[frame.selectedRaid] and
                 OGRH_SV.encounterAssignments[frame.selectedRaid][frame.selectedEncounter] and
                 OGRH_SV.encounterAssignments[frame.selectedRaid][frame.selectedEncounter][slotRoleIndex] then
                OGRH_SV.encounterAssignments[frame.selectedRaid][frame.selectedEncounter][slotRoleIndex][slotSlotIndex] = nil
                
                -- Refresh display
                if frame.RefreshRoleContainers then
                  frame.RefreshRoleContainers()
                end
              end
            else
              -- Left click: Show player selection dialog
              OGRH.ShowPlayerSelectionDialog(frame.selectedRaid, frame.selectedEncounter, slotRoleIndex, slotSlotIndex, frame)
            end
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
              -- Get player's class color
              local class = nil
              for j = 1, GetNumRaidMembers() do
                local name, _, _, _, playerClass = GetRaidRosterInfo(j)
                if name == playerName then
                  class = playerClass
                  break
                end
              end
              
              local colorCode = "|cffffffff"
              if class then
                local classColors = {
                  WARRIOR = "|cffC79C6E",
                  PALADIN = "|cffF58CBA",
                  HUNTER = "|cffABD473",
                  ROGUE = "|cffFFF569",
                  PRIEST = "|cffFFFFFF",
                  SHAMAN = "|cff0070DE",
                  MAGE = "|cff69CCF0",
                  WARLOCK = "|cff9482C9",
                  DRUID = "|cffFF7D0A"
                }
                colorCode = classColors[string.upper(class)] or "|cffffffff"
              end
              
              slot.nameText:SetText(colorCode .. playerName .. "|r")
            else
              slot.nameText:SetText("|cff888888[Empty]|r")
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
      
      -- Left column
      for i = 1, table.getn(column1) do
        local container = CreateRoleContainer(scrollChild, column1[i], roleIndex, 5, yOffsetLeft, columnWidth)
        table.insert(frame.roleContainers, container)
        roleIndex = roleIndex + 1
        
        -- Calculate offset for next role in left column
        local containerHeight = 40 + ((column1[i].slots or 1) * 22)
        yOffsetLeft = yOffsetLeft - containerHeight - 10
      end
      
      -- Right column
      for i = 1, table.getn(column2) do
        local container = CreateRoleContainer(scrollChild, column2[i], roleIndex, 287, yOffsetRight, columnWidth)
        table.insert(frame.roleContainers, container)
        roleIndex = roleIndex + 1
        
        -- Calculate offset for next role in right column
        local containerHeight = 40 + ((column2[i].slots or 1) * 22)
        yOffsetRight = yOffsetRight - containerHeight - 10
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
        scrollBar:SetMinMaxValues(0, contentHeight - scrollFrameHeight)
        scrollBar:SetValue(0)
        scrollFrame:SetVerticalScroll(0)
      else
        scrollBar:Hide()
        scrollFrame:SetVerticalScroll(0)
      end
    end
    
    frame.RefreshRoleContainers = RefreshRoleContainers
    
    -- Initialize lists
    RefreshRaidsList()
  end
  
  -- Close Roles window if it's open
  if OGRH.rolesFrame and OGRH.rolesFrame:IsVisible() then
    OGRH.rolesFrame:Hide()
  end
  
  -- Show the frame
  OGRH_BWLEncounterFrame:Show()
  
  -- Refresh the raids list (this will validate and clear selectedRaid/selectedEncounter if needed)
  OGRH_BWLEncounterFrame.RefreshRaidsList()
  
  -- Refresh the encounters list (this will validate and clear selectedEncounter if needed)
  if OGRH_BWLEncounterFrame.RefreshEncountersList then
    OGRH_BWLEncounterFrame.RefreshEncountersList()
  end
  
  -- Refresh role containers to set initial visibility state of buttons
  if OGRH_BWLEncounterFrame.RefreshRoleContainers then
    OGRH_BWLEncounterFrame.RefreshRoleContainers()
  end
  
  -- If an encounter is still selected after validation, refresh again
  -- to pick up any changes made in the Setup window
  if OGRH_BWLEncounterFrame.selectedRaid and OGRH_BWLEncounterFrame.selectedEncounter then
    if OGRH_BWLEncounterFrame.RefreshRoleContainers then
      OGRH_BWLEncounterFrame.RefreshRoleContainers()
    end
  end
end

-- Function to show Encounter Setup Window
function OGRH.ShowEncounterSetup()
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
    closeBtn:SetScript("OnClick", function() frame:Hide() end)
    
    -- Content area
    local contentFrame = CreateFrame("Frame", nil, frame)
    contentFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -50)
    contentFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 10)
    
    -- Raids section
    local raidsLabel = contentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    raidsLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -55)
    raidsLabel:SetText("Raids:")
    
    -- Raids list
    local raidsListFrame = CreateFrame("Frame", nil, contentFrame)
    raidsListFrame:SetPoint("TOPLEFT", raidsLabel, "BOTTOMLEFT", 0, -5)
    raidsListFrame:SetWidth(180)
    raidsListFrame:SetHeight(175)
    raidsListFrame:SetBackdrop({
      bgFile = "Interface/Tooltips/UI-Tooltip-Background",
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
      tile = true,
      tileSize = 16,
      edgeSize = 12,
      insets = {left = 3, right = 3, top = 3, bottom = 3}
    })
    raidsListFrame:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
    
    -- Create scroll frame for raids
    local raidsScrollFrame = CreateFrame("ScrollFrame", nil, raidsListFrame)
    raidsScrollFrame:SetPoint("TOPLEFT", raidsListFrame, "TOPLEFT", 5, -5)
    raidsScrollFrame:SetPoint("BOTTOMRIGHT", raidsListFrame, "BOTTOMRIGHT", -22, 5)
    
    local raidsScrollChild = CreateFrame("Frame", nil, raidsScrollFrame)
    raidsScrollChild:SetWidth(150)
    raidsScrollChild:SetHeight(1)
    raidsScrollFrame:SetScrollChild(raidsScrollChild)
    frame.raidsScrollChild = raidsScrollChild
    frame.raidsScrollFrame = raidsScrollFrame
    
    -- Create raids scrollbar
    local raidsScrollBar = CreateFrame("Slider", nil, raidsScrollFrame)
    raidsScrollBar:SetPoint("TOPRIGHT", raidsListFrame, "TOPRIGHT", -5, -16)
    raidsScrollBar:SetPoint("BOTTOMRIGHT", raidsListFrame, "BOTTOMRIGHT", -5, 16)
    raidsScrollBar:SetWidth(16)
    raidsScrollBar:SetBackdrop({
      bgFile = "Interface/Tooltips/UI-Tooltip-Background",
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 8,
      insets = {left = 3, right = 3, top = 3, bottom = 3}
    })
    raidsScrollBar:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
    raidsScrollBar:SetOrientation("VERTICAL")
    raidsScrollBar:SetMinMaxValues(0, 1)
    raidsScrollBar:SetValue(0)
    raidsScrollBar:SetValueStep(22)
    raidsScrollBar:Hide()
    frame.raidsScrollBar = raidsScrollBar
    
    raidsScrollBar:SetScript("OnValueChanged", function()
      raidsScrollFrame:SetVerticalScroll(this:GetValue())
    end)
    
    raidsScrollFrame:EnableMouseWheel(true)
    raidsScrollFrame:SetScript("OnMouseWheel", function()
      -- Only scroll if scrollbar is visible
      if not raidsScrollBar:IsShown() then
        return
      end
      
      local delta = arg1
      local current = raidsScrollBar:GetValue()
      local minVal, maxVal = raidsScrollBar:GetMinMaxValues()
      
      if delta > 0 then
        raidsScrollBar:SetValue(math.max(minVal, current - 22))
      else
        raidsScrollBar:SetValue(math.min(maxVal, current + 22))
      end
    end)
    
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
      
      -- Add existing raids
      for i, raidName in ipairs(OGRH_SV.encounterMgmt.raids) do
        local raidBtn = CreateFrame("Button", nil, scrollChild)
        raidBtn:SetWidth(150)
        raidBtn:SetHeight(20)
        raidBtn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, yOffset)
        
        -- Background
        local bg = raidBtn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetTexture("Interface\\Buttons\\WHITE8X8")
        if frame.selectedRaid == raidName then
          bg:SetVertexColor(0.2, 0.4, 0.2, 0.8)  -- Highlight if selected
        else
          bg:SetVertexColor(0.2, 0.2, 0.2, 0.5)
        end
        raidBtn.bg = bg
        
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
        
        -- Delete button (X mark - raid target icon 7)
        local deleteBtn = CreateFrame("Button", nil, raidBtn)
        deleteBtn:SetWidth(16)
        deleteBtn:SetHeight(16)
        deleteBtn:SetPoint("RIGHT", raidBtn, "RIGHT", -2, 0)
        
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
          StaticPopupDialogs["OGRH_CONFIRM_DELETE_RAID"].text_arg1 = capturedRaidName
          StaticPopup_Show("OGRH_CONFIRM_DELETE_RAID", capturedRaidName)
        end)
        
        -- Down button
        local downBtn = CreateFrame("Button", nil, raidBtn)
        downBtn:SetWidth(32)
        downBtn:SetHeight(32)
        downBtn:SetPoint("RIGHT", deleteBtn, "LEFT", 5, 0)
        downBtn:SetNormalTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up")
        downBtn:SetPushedTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Down")
        downBtn:SetHighlightTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Highlight")
        downBtn:SetScript("OnClick", function()
          if capturedIndex < table.getn(OGRH_SV.encounterMgmt.raids) then
            -- Swap with next
            local temp = OGRH_SV.encounterMgmt.raids[capturedIndex + 1]
            OGRH_SV.encounterMgmt.raids[capturedIndex + 1] = OGRH_SV.encounterMgmt.raids[capturedIndex]
            OGRH_SV.encounterMgmt.raids[capturedIndex] = temp
            RefreshRaidsList()
          end
        end)
        
        -- Up button
        local upBtn = CreateFrame("Button", nil, raidBtn)
        upBtn:SetWidth(32)
        upBtn:SetHeight(32)
        upBtn:SetPoint("RIGHT", downBtn, "LEFT", 13, 0)
        upBtn:SetNormalTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Up")
        upBtn:SetPushedTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Down")
        upBtn:SetHighlightTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Highlight")
        upBtn:SetScript("OnClick", function()
          if capturedIndex > 1 then
            -- Swap with previous
            local temp = OGRH_SV.encounterMgmt.raids[capturedIndex - 1]
            OGRH_SV.encounterMgmt.raids[capturedIndex - 1] = OGRH_SV.encounterMgmt.raids[capturedIndex]
            OGRH_SV.encounterMgmt.raids[capturedIndex] = temp
            RefreshRaidsList()
          end
        end)
        
        table.insert(frame.raidButtons, raidBtn)
        yOffset = yOffset - 22
      end
      
      -- Add "Add Raid" placeholder row at the bottom
      local addRaidBtn = CreateFrame("Button", nil, scrollChild)
      addRaidBtn:SetWidth(150)
      addRaidBtn:SetHeight(20)
      addRaidBtn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, yOffset)
      
      -- Background
      local bg = addRaidBtn:CreateTexture(nil, "BACKGROUND")
      bg:SetAllPoints()
      bg:SetTexture("Interface\\Buttons\\WHITE8X8")
      bg:SetVertexColor(0.1, 0.3, 0.1, 0.5)
      
      -- Highlight
      local highlight = addRaidBtn:CreateTexture(nil, "HIGHLIGHT")
      highlight:SetAllPoints()
      highlight:SetTexture("Interface\\Buttons\\WHITE8X8")
      highlight:SetVertexColor(0.2, 0.5, 0.2, 0.5)
      
      -- Text
      local addText = addRaidBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      addText:SetPoint("CENTER", addRaidBtn, "CENTER", 0, 0)
      addText:SetText("|cff00ff00Add Raid|r")
      
      addRaidBtn:SetScript("OnClick", function()
        StaticPopup_Show("OGRH_ADD_RAID")
      end)
      
      table.insert(frame.raidButtons, addRaidBtn)
      yOffset = yOffset - 22
      
      -- Update scroll child height
      local contentHeight = math.abs(yOffset) + 5
      scrollChild:SetHeight(contentHeight)
      
      -- Update scrollbar visibility
      local scrollFrame = frame.raidsScrollFrame
      local scrollBar = frame.raidsScrollBar
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
    
    frame.RefreshRaidsList = RefreshRaidsList
    
    -- Encounters section (below Raids)
    local encountersLabel = contentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    encountersLabel:SetPoint("TOPLEFT", raidsListFrame, "BOTTOMLEFT", 0, -15)
    encountersLabel:SetText("Encounters:")
    
    -- Encounters list
    local encountersListFrame = CreateFrame("Frame", nil, contentFrame)
    encountersListFrame:SetPoint("TOPLEFT", encountersLabel, "BOTTOMLEFT", 0, -5)
    encountersListFrame:SetWidth(180)
    encountersListFrame:SetHeight(175)
    encountersListFrame:SetBackdrop({
      bgFile = "Interface/Tooltips/UI-Tooltip-Background",
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
      tile = true,
      tileSize = 16,
      edgeSize = 12,
      insets = {left = 3, right = 3, top = 3, bottom = 3}
    })
    encountersListFrame:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
    
    -- Create scroll frame for encounters
    local encountersScrollFrame = CreateFrame("ScrollFrame", nil, encountersListFrame)
    encountersScrollFrame:SetPoint("TOPLEFT", encountersListFrame, "TOPLEFT", 5, -5)
    encountersScrollFrame:SetPoint("BOTTOMRIGHT", encountersListFrame, "BOTTOMRIGHT", -22, 5)
    
    local encountersScrollChild = CreateFrame("Frame", nil, encountersScrollFrame)
    encountersScrollChild:SetWidth(150)
    encountersScrollChild:SetHeight(1)
    encountersScrollFrame:SetScrollChild(encountersScrollChild)
    frame.encountersScrollChild = encountersScrollChild
    frame.encountersScrollFrame = encountersScrollFrame
    
    -- Create encounters scrollbar
    local encountersScrollBar = CreateFrame("Slider", nil, encountersScrollFrame)
    encountersScrollBar:SetPoint("TOPRIGHT", encountersListFrame, "TOPRIGHT", -5, -16)
    encountersScrollBar:SetPoint("BOTTOMRIGHT", encountersListFrame, "BOTTOMRIGHT", -5, 16)
    encountersScrollBar:SetWidth(16)
    encountersScrollBar:SetBackdrop({
      bgFile = "Interface/Tooltips/UI-Tooltip-Background",
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 8,
      insets = {left = 3, right = 3, top = 3, bottom = 3}
    })
    encountersScrollBar:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
    encountersScrollBar:SetOrientation("VERTICAL")
    encountersScrollBar:SetMinMaxValues(0, 1)
    encountersScrollBar:SetValue(0)
    encountersScrollBar:SetValueStep(22)
    encountersScrollBar:Hide()
    frame.encountersScrollBar = encountersScrollBar
    
    encountersScrollBar:SetScript("OnValueChanged", function()
      encountersScrollFrame:SetVerticalScroll(this:GetValue())
    end)
    
    encountersScrollFrame:EnableMouseWheel(true)
    encountersScrollFrame:SetScript("OnMouseWheel", function()
      -- Only scroll if scrollbar is visible
      if not encountersScrollBar:IsShown() then
        return
      end
      
      local delta = arg1
      local current = encountersScrollBar:GetValue()
      local minVal, maxVal = encountersScrollBar:GetMinMaxValues()
      
      if delta > 0 then
        encountersScrollBar:SetValue(math.max(minVal, current - 22))
      else
        encountersScrollBar:SetValue(math.min(maxVal, current + 22))
      end
    end)
    
    frame.encountersListFrame = encountersListFrame
    
    -- Track selected encounter
    frame.selectedEncounter = nil
    
    -- Function to refresh encounters list
    local function RefreshEncountersList()
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
      
      -- Add existing encounters for selected raid
      local encounters = OGRH_SV.encounterMgmt.encounters[frame.selectedRaid]
      for i, encounterName in ipairs(encounters) do
        local encounterBtn = CreateFrame("Button", nil, scrollChild)
        encounterBtn:SetWidth(150)
        encounterBtn:SetHeight(20)
        encounterBtn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, yOffset)
        
        -- Background
        local bg = encounterBtn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetTexture("Interface\\Buttons\\WHITE8X8")
        if frame.selectedEncounter == encounterName then
          bg:SetVertexColor(0.2, 0.4, 0.2, 0.8)  -- Highlight if selected
        else
          bg:SetVertexColor(0.2, 0.2, 0.2, 0.5)
        end
        encounterBtn.bg = bg
        
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
        
        -- Delete button (X mark)
        local deleteBtn = CreateFrame("Button", nil, encounterBtn)
        deleteBtn:SetWidth(16)
        deleteBtn:SetHeight(16)
        deleteBtn:SetPoint("RIGHT", encounterBtn, "RIGHT", -2, 0)
        
        local deleteIcon = deleteBtn:CreateTexture(nil, "ARTWORK")
        deleteIcon:SetWidth(16)
        deleteIcon:SetHeight(16)
        deleteIcon:SetAllPoints(deleteBtn)
        deleteIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
        deleteIcon:SetTexCoord(0.5, 0.75, 0.25, 0.5)
        
        local deleteHighlight = deleteBtn:CreateTexture(nil, "HIGHLIGHT")
        deleteHighlight:SetWidth(16)
        deleteHighlight:SetHeight(16)
        deleteHighlight:SetAllPoints(deleteBtn)
        deleteHighlight:SetTexture("Interface\\Buttons\\UI-Common-MouseHilight")
        deleteHighlight:SetBlendMode("ADD")
        
        deleteBtn:SetScript("OnClick", function()
          StaticPopupDialogs["OGRH_CONFIRM_DELETE_ENCOUNTER"].text_arg1 = capturedEncounterName
          StaticPopupDialogs["OGRH_CONFIRM_DELETE_ENCOUNTER"].text_arg2 = capturedRaid
          StaticPopup_Show("OGRH_CONFIRM_DELETE_ENCOUNTER", capturedEncounterName)
        end)
        
        -- Down button
        local downBtn = CreateFrame("Button", nil, encounterBtn)
        downBtn:SetWidth(32)
        downBtn:SetHeight(32)
        downBtn:SetPoint("RIGHT", deleteBtn, "LEFT", 5, 0)
        downBtn:SetNormalTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up")
        downBtn:SetPushedTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Down")
        downBtn:SetHighlightTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Highlight")
        downBtn:SetScript("OnClick", function()
          if capturedIndex < table.getn(OGRH_SV.encounterMgmt.encounters[capturedRaid]) then
            local temp = OGRH_SV.encounterMgmt.encounters[capturedRaid][capturedIndex + 1]
            OGRH_SV.encounterMgmt.encounters[capturedRaid][capturedIndex + 1] = OGRH_SV.encounterMgmt.encounters[capturedRaid][capturedIndex]
            OGRH_SV.encounterMgmt.encounters[capturedRaid][capturedIndex] = temp
            RefreshEncountersList()
          end
        end)
        
        -- Up button
        local upBtn = CreateFrame("Button", nil, encounterBtn)
        upBtn:SetWidth(32)
        upBtn:SetHeight(32)
        upBtn:SetPoint("RIGHT", downBtn, "LEFT", 13, 0)
        upBtn:SetNormalTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Up")
        upBtn:SetPushedTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Down")
        upBtn:SetHighlightTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Highlight")
        upBtn:SetScript("OnClick", function()
          if capturedIndex > 1 then
            local temp = OGRH_SV.encounterMgmt.encounters[capturedRaid][capturedIndex - 1]
            OGRH_SV.encounterMgmt.encounters[capturedRaid][capturedIndex - 1] = OGRH_SV.encounterMgmt.encounters[capturedRaid][capturedIndex]
            OGRH_SV.encounterMgmt.encounters[capturedRaid][capturedIndex] = temp
            RefreshEncountersList()
          end
        end)
        
        table.insert(frame.encounterButtons, encounterBtn)
        yOffset = yOffset - 22
      end
      
      -- Add "Add Encounter" placeholder row at the bottom
      local addEncounterBtn = CreateFrame("Button", nil, scrollChild)
      addEncounterBtn:SetWidth(150)
      addEncounterBtn:SetHeight(20)
      addEncounterBtn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, yOffset)
      
      local bg = addEncounterBtn:CreateTexture(nil, "BACKGROUND")
      bg:SetAllPoints()
      bg:SetTexture("Interface\\Buttons\\WHITE8X8")
      bg:SetVertexColor(0.1, 0.3, 0.1, 0.5)
      
      local highlight = addEncounterBtn:CreateTexture(nil, "HIGHLIGHT")
      highlight:SetAllPoints()
      highlight:SetTexture("Interface\\Buttons\\WHITE8X8")
      highlight:SetVertexColor(0.2, 0.5, 0.2, 0.5)
      
      local addText = addEncounterBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      addText:SetPoint("CENTER", addEncounterBtn, "CENTER", 0, 0)
      addText:SetText("|cff00ff00Add Encounter|r")
      
      local capturedRaid = frame.selectedRaid
      addEncounterBtn:SetScript("OnClick", function()
        StaticPopupDialogs["OGRH_ADD_ENCOUNTER"].text_arg1 = capturedRaid
        StaticPopup_Show("OGRH_ADD_ENCOUNTER")
      end)
      
      table.insert(frame.encounterButtons, addEncounterBtn)
      yOffset = yOffset - 22
      
      -- Update scroll child height
      local contentHeight = math.abs(yOffset) + 5
      scrollChild:SetHeight(contentHeight)
      
      -- Update scrollbar visibility
      local scrollFrame = frame.encountersScrollFrame
      local scrollBar = frame.encountersScrollBar
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
    
    -- Left column frame
    local rolesListFrame = CreateFrame("Frame", nil, designFrame)
    rolesListFrame:SetPoint("TOPLEFT", rolesLabel, "BOTTOMLEFT", 0, -5)
    rolesListFrame:SetWidth(165)
    rolesListFrame:SetHeight(340)
    rolesListFrame:SetBackdrop({
      bgFile = "Interface/Tooltips/UI-Tooltip-Background",
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
      tile = true,
      tileSize = 16,
      edgeSize = 12,
      insets = {left = 3, right = 3, top = 3, bottom = 3}
    })
    rolesListFrame:SetBackdropColor(0.15, 0.15, 0.15, 0.9)
    
    -- Create scroll frame for roles
    local rolesScrollFrame = CreateFrame("ScrollFrame", nil, rolesListFrame)
    rolesScrollFrame:SetPoint("TOPLEFT", rolesListFrame, "TOPLEFT", 5, -5)
    rolesScrollFrame:SetPoint("BOTTOMRIGHT", rolesListFrame, "BOTTOMRIGHT", -22, 5)
    
    local rolesScrollChild = CreateFrame("Frame", nil, rolesScrollFrame)
    rolesScrollChild:SetWidth(135)
    rolesScrollChild:SetHeight(1)
    rolesScrollFrame:SetScrollChild(rolesScrollChild)
    frame.rolesScrollChild = rolesScrollChild
    frame.rolesScrollFrame = rolesScrollFrame
    
    -- Create roles scrollbar
    local rolesScrollBar = CreateFrame("Slider", nil, rolesScrollFrame)
    rolesScrollBar:SetPoint("TOPRIGHT", rolesListFrame, "TOPRIGHT", -5, -16)
    rolesScrollBar:SetPoint("BOTTOMRIGHT", rolesListFrame, "BOTTOMRIGHT", -5, 16)
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
    
    rolesScrollFrame:EnableMouseWheel(true)
    rolesScrollFrame:SetScript("OnMouseWheel", function()
      -- Only scroll if scrollbar is visible
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
    
    -- Right column frame (no label, vertically aligned with left)
    local rolesListFrame2 = CreateFrame("Frame", nil, designFrame)
    rolesListFrame2:SetPoint("TOPLEFT", rolesListFrame, "TOPRIGHT", 15, 0)
    rolesListFrame2:SetWidth(165)
    rolesListFrame2:SetHeight(340)
    rolesListFrame2:SetBackdrop({
      bgFile = "Interface/Tooltips/UI-Tooltip-Background",
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
      tile = true,
      tileSize = 16,
      edgeSize = 12,
      insets = {left = 3, right = 3, top = 3, bottom = 3}
    })
    rolesListFrame2:SetBackdropColor(0.15, 0.15, 0.15, 0.9)
    
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
    
    -- Create scroll frame for roles column 2
    local rolesScrollFrame2 = CreateFrame("ScrollFrame", nil, rolesListFrame2)
    rolesScrollFrame2:SetPoint("TOPLEFT", rolesListFrame2, "TOPLEFT", 5, -5)
    rolesScrollFrame2:SetPoint("BOTTOMRIGHT", rolesListFrame2, "BOTTOMRIGHT", -22, 5)
    
    local rolesScrollChild2 = CreateFrame("Frame", nil, rolesScrollFrame2)
    rolesScrollChild2:SetWidth(135)
    rolesScrollChild2:SetHeight(1)
    rolesScrollFrame2:SetScrollChild(rolesScrollChild2)
    frame.rolesScrollChild2 = rolesScrollChild2
    frame.rolesScrollFrame2 = rolesScrollFrame2
    
    -- Create roles scrollbar 2
    local rolesScrollBar2 = CreateFrame("Slider", nil, rolesScrollFrame2)
    rolesScrollBar2:SetPoint("TOPRIGHT", rolesListFrame2, "TOPRIGHT", -5, -16)
    rolesScrollBar2:SetPoint("BOTTOMRIGHT", rolesListFrame2, "BOTTOMRIGHT", -5, 16)
    rolesScrollBar2:SetWidth(16)
    rolesScrollBar2:SetBackdrop({
      bgFile = "Interface/Tooltips/UI-Tooltip-Background",
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 8,
      insets = {left = 3, right = 3, top = 3, bottom = 3}
    })
    rolesScrollBar2:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
    rolesScrollBar2:SetOrientation("VERTICAL")
    rolesScrollBar2:SetMinMaxValues(0, 1)
    rolesScrollBar2:SetValue(0)
    rolesScrollBar2:SetValueStep(22)
    rolesScrollBar2:Hide()
    frame.rolesScrollBar2 = rolesScrollBar2
    
    rolesScrollBar2:SetScript("OnValueChanged", function()
      rolesScrollFrame2:SetVerticalScroll(this:GetValue())
    end)
    
    rolesScrollFrame2:EnableMouseWheel(true)
    rolesScrollFrame2:SetScript("OnMouseWheel", function()
      -- Only scroll if scrollbar is visible
      if not rolesScrollBar2:IsShown() then
        return
      end
      
      local delta = arg1
      local current = rolesScrollBar2:GetValue()
      local minVal, maxVal = rolesScrollBar2:GetMinMaxValues()
      
      if delta > 0 then
        rolesScrollBar2:SetValue(math.max(minVal, current - 22))
      else
        rolesScrollBar2:SetValue(math.min(maxVal, current + 22))
      end
    end)
    
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
        local roleBtn = CreateFrame("Button", nil, scrollChild)
        roleBtn:SetWidth(135)
        roleBtn:SetHeight(20)
        
        local yOffset = isColumn2 and yOffset2 or yOffset1
        roleBtn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, yOffset)
        
        -- Make draggable
        roleBtn:RegisterForDrag("LeftButton")
        
        -- Background
        local bg = roleBtn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetTexture("Interface\\Buttons\\WHITE8X8")
        bg:SetVertexColor(0.2, 0.2, 0.2, 0.5)
        
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
          bg:SetVertexColor(0.3, 0.5, 0.3, 0.8)
          
          -- Show drag cursor
          if frame.dragCursor and frame.dragCursorText then
            frame.dragCursorText:SetText(role.name or "Unnamed")
            frame.dragCursor:Show()
          end
        end)
        
        roleBtn:SetScript("OnDragStop", function()
          this.isDragging = false
          bg:SetVertexColor(0.2, 0.2, 0.2, 0.5)
          
          -- Hide drag cursor
          if frame.dragCursor then
            frame.dragCursor:Hide()
          end
          
          -- Check if dropped on the other column's scroll frame
          local targetScrollFrame = this.isColumn2 and frame.rolesScrollFrame or frame.rolesScrollFrame2
          local targetColumnRoles = this.isColumn2 and rolesData.column1 or rolesData.column2
          local sourceColumnRoles = this.columnRoles
          
          if MouseIsOver(targetScrollFrame) then
            -- Move role to other column
            local role = sourceColumnRoles[this.roleIndex]
            table.remove(sourceColumnRoles, this.roleIndex)
            table.insert(targetColumnRoles, role)
            RefreshRolesList()
          else
            -- Just refresh position
            RefreshRolesList()
          end
        end)
        
        -- Capture variables for button closures
        local capturedRoles = columnRoles
        local capturedIdx = roleIndex
        
        -- Delete button (rightmost)
        local deleteBtn = CreateFrame("Button", nil, roleBtn)
        deleteBtn:SetWidth(16)
        deleteBtn:SetHeight(16)
        deleteBtn:SetPoint("RIGHT", roleBtn, "RIGHT", -2, 0)
        
        local deleteIcon = deleteBtn:CreateTexture(nil, "ARTWORK")
        deleteIcon:SetWidth(16)
        deleteIcon:SetHeight(16)
        deleteIcon:SetAllPoints(deleteBtn)
        deleteIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
        deleteIcon:SetTexCoord(0.5, 0.75, 0.25, 0.5)
        
        local deleteHighlight = deleteBtn:CreateTexture(nil, "HIGHLIGHT")
        deleteHighlight:SetWidth(16)
        deleteHighlight:SetHeight(16)
        deleteHighlight:SetAllPoints(deleteBtn)
        deleteHighlight:SetTexture("Interface\\Buttons\\UI-Common-MouseHilight")
        deleteHighlight:SetBlendMode("ADD")
        
        deleteBtn:SetScript("OnClick", function()
          table.remove(capturedRoles, capturedIdx)
          RefreshRolesList()
        end)
        
        -- Down button (middle)
        local downBtn = CreateFrame("Button", nil, roleBtn)
        downBtn:SetWidth(32)
        downBtn:SetHeight(32)
        downBtn:SetPoint("RIGHT", deleteBtn, "LEFT", 5, 0)
        downBtn:SetNormalTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up")
        downBtn:SetPushedTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Down")
        downBtn:SetHighlightTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Highlight")
        downBtn:SetScript("OnClick", function()
          if capturedIdx < table.getn(capturedRoles) then
            local temp = capturedRoles[capturedIdx + 1]
            capturedRoles[capturedIdx + 1] = capturedRoles[capturedIdx]
            capturedRoles[capturedIdx] = temp
            RefreshRolesList()
          end
        end)
        
        -- Up button (leftmost of the three)
        local upBtn = CreateFrame("Button", nil, roleBtn)
        upBtn:SetWidth(32)
        upBtn:SetHeight(32)
        -- Position 2px left of down button: delete(16) + spacing(2) + down(32) + spacing(2) = 52 from right
        upBtn:SetPoint("RIGHT", downBtn, "LEFT", 13, 0)
        upBtn:SetNormalTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Up")
        upBtn:SetPushedTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Down")
        upBtn:SetHighlightTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Highlight")
        upBtn:SetScript("OnClick", function()
          if capturedIdx > 1 then
            local temp = capturedRoles[capturedIdx - 1]
            capturedRoles[capturedIdx - 1] = capturedRoles[capturedIdx]
            capturedRoles[capturedIdx] = temp
            RefreshRolesList()
          end
        end)
        
        table.insert(frame.roleButtons, roleBtn)
        
        if isColumn2 then
          yOffset2 = yOffset2 - 22
        else
          yOffset1 = yOffset1 - 22
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
      local addRoleBtn1 = CreateFrame("Button", nil, scrollChild1)
      addRoleBtn1:SetWidth(135)
      addRoleBtn1:SetHeight(20)
      addRoleBtn1:SetPoint("TOPLEFT", scrollChild1, "TOPLEFT", 0, yOffset1)
      
      local bg1 = addRoleBtn1:CreateTexture(nil, "BACKGROUND")
      bg1:SetAllPoints()
      bg1:SetTexture("Interface\\Buttons\\WHITE8X8")
      bg1:SetVertexColor(0.1, 0.3, 0.1, 0.5)
      
      local highlight1 = addRoleBtn1:CreateTexture(nil, "HIGHLIGHT")
      highlight1:SetAllPoints()
      highlight1:SetTexture("Interface\\Buttons\\WHITE8X8")
      highlight1:SetVertexColor(0.2, 0.5, 0.2, 0.5)
      
      local addText1 = addRoleBtn1:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      addText1:SetPoint("CENTER", addRoleBtn1, "CENTER", 0, 0)
      addText1:SetText("|cff00ff00Add Role|r")
      
      addRoleBtn1:SetScript("OnClick", function()
        local newIndex = table.getn(rolesData.column1) + 1
        table.insert(rolesData.column1, {name = "New Role " .. newIndex, slots = 1})
        RefreshRolesList()
      end)
      
      table.insert(frame.roleButtons, addRoleBtn1)
      yOffset1 = yOffset1 - 22
      
      -- Right column Add Role button
      local addRoleBtn2 = CreateFrame("Button", nil, scrollChild2)
      addRoleBtn2:SetWidth(135)
      addRoleBtn2:SetHeight(20)
      addRoleBtn2:SetPoint("TOPLEFT", scrollChild2, "TOPLEFT", 0, yOffset2)
      
      local bg2 = addRoleBtn2:CreateTexture(nil, "BACKGROUND")
      bg2:SetAllPoints()
      bg2:SetTexture("Interface\\Buttons\\WHITE8X8")
      bg2:SetVertexColor(0.1, 0.3, 0.1, 0.5)
      
      local highlight2 = addRoleBtn2:CreateTexture(nil, "HIGHLIGHT")
      highlight2:SetAllPoints()
      highlight2:SetTexture("Interface\\Buttons\\WHITE8X8")
      highlight2:SetVertexColor(0.2, 0.5, 0.2, 0.5)
      
      local addText2 = addRoleBtn2:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      addText2:SetPoint("CENTER", addRoleBtn2, "CENTER", 0, 0)
      addText2:SetText("|cff00ff00Add Role|r")
      
      addRoleBtn2:SetScript("OnClick", function()
        local newIndex = table.getn(rolesData.column2) + 1
        table.insert(rolesData.column2, {name = "New Role " .. newIndex, slots = 1})
        RefreshRolesList()
      end)
      
      table.insert(frame.roleButtons, addRoleBtn2)
      yOffset2 = yOffset2 - 22
      
      -- Update scroll child heights
      local contentHeight1 = math.abs(yOffset1) + 5
      scrollChild1:SetHeight(contentHeight1)
      
      local contentHeight2 = math.abs(yOffset2) + 5
      scrollChild2:SetHeight(contentHeight2)
      
      -- Update scrollbars for column 1
      local scrollFrame1 = frame.rolesScrollFrame
      local scrollBar1 = frame.rolesScrollBar
      local scrollFrameHeight1 = scrollFrame1:GetHeight()
      
      if contentHeight1 > scrollFrameHeight1 then
        scrollBar1:Show()
        scrollBar1:SetMinMaxValues(0, contentHeight1 - scrollFrameHeight1)
        scrollBar1:SetValue(0)
        scrollFrame1:SetVerticalScroll(0)
      else
        scrollBar1:Hide()
        scrollFrame1:SetVerticalScroll(0)
      end
      
      -- Update scrollbars for column 2
      local scrollFrame2 = frame.rolesScrollFrame2
      local scrollBar2 = frame.rolesScrollBar2
      local scrollFrameHeight2 = scrollFrame2:GetHeight()
      
      if contentHeight2 > scrollFrameHeight2 then
        scrollBar2:Show()
        scrollBar2:SetMinMaxValues(0, contentHeight2 - scrollFrameHeight2)
        scrollBar2:SetValue(0)
        scrollFrame2:SetVerticalScroll(0)
      else
        scrollBar2:Hide()
        scrollFrame2:SetVerticalScroll(0)
      end
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
        OGRH_EncounterSetupFrame.RefreshRaidsList()
        if OGRH_EncounterSetupFrame.RefreshEncountersList then
          OGRH_EncounterSetupFrame.RefreshEncountersList()
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
        
        -- Update player pools
        if OGRH_SV.encounterPools and OGRH_SV.encounterPools[oldName] then
          OGRH_SV.encounterPools[newName] = OGRH_SV.encounterPools[oldName]
          OGRH_SV.encounterPools[oldName] = nil
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
        if OGRH_BWLEncounterFrame and OGRH_BWLEncounterFrame.selectedRaid == oldName then
          OGRH_BWLEncounterFrame.selectedRaid = newName
        end
        
        -- Refresh windows
        if OGRH_EncounterSetupFrame and OGRH_EncounterSetupFrame.RefreshRaidsList then
          OGRH_EncounterSetupFrame.RefreshRaidsList()
          if OGRH_EncounterSetupFrame.RefreshEncountersList then
            OGRH_EncounterSetupFrame.RefreshEncountersList()
          end
        end
        if OGRH_BWLEncounterFrame and OGRH_BWLEncounterFrame.RefreshRaidsList then
          OGRH_BWLEncounterFrame.RefreshRaidsList()
          if OGRH_BWLEncounterFrame.RefreshEncountersList then
            OGRH_BWLEncounterFrame.RefreshEncountersList()
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
        
        -- Update player pools
        if OGRH_SV.encounterPools and OGRH_SV.encounterPools[raidName] and OGRH_SV.encounterPools[raidName][oldName] then
          OGRH_SV.encounterPools[raidName][newName] = OGRH_SV.encounterPools[raidName][oldName]
          OGRH_SV.encounterPools[raidName][oldName] = nil
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
        if OGRH_BWLEncounterFrame and OGRH_BWLEncounterFrame.selectedEncounter == oldName then
          OGRH_BWLEncounterFrame.selectedEncounter = newName
        end
        
        -- Refresh windows
        if OGRH_EncounterSetupFrame and OGRH_EncounterSetupFrame.RefreshEncountersList then
          OGRH_EncounterSetupFrame.RefreshEncountersList()
          if OGRH_EncounterSetupFrame.RefreshRolesList then
            OGRH_EncounterSetupFrame.RefreshRolesList()
          end
        end
        if OGRH_BWLEncounterFrame and OGRH_BWLEncounterFrame.RefreshEncountersList then
          OGRH_BWLEncounterFrame.RefreshEncountersList()
          if OGRH_BWLEncounterFrame.RefreshRoleContainers then
            OGRH_BWLEncounterFrame.RefreshRoleContainers()
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
    
    -- Raid Only checkbox
    local raidOnlyCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    raidOnlyCheck:SetWidth(24)
    raidOnlyCheck:SetHeight(24)
    raidOnlyCheck:SetPoint("TOP", roleFilterBtn, "BOTTOM", -35, -5)
    frame.raidOnlyCheck = raidOnlyCheck
    
    local raidOnlyLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    raidOnlyLabel:SetPoint("LEFT", raidOnlyCheck, "RIGHT", 5, 0)
    raidOnlyLabel:SetText("Raid Only")
    
    -- Initialize persistent setting
    if OGRH_SV.playerSelectionRaidOnly == nil then
      OGRH_SV.playerSelectionRaidOnly = true
    end
    raidOnlyCheck:SetChecked(OGRH_SV.playerSelectionRaidOnly)
    
    frame.raidOnlyCheck = raidOnlyCheck
    raidOnlyCheck:SetScript("OnClick", function()
      OGRH_SV.playerSelectionRaidOnly = raidOnlyCheck:GetChecked()
      if frame.RefreshPlayerList then
        frame.RefreshPlayerList()
      end
    end)
    
    -- Player list scroll frame
    local listFrame = CreateFrame("Frame", nil, frame)
    listFrame:SetWidth(320)
    listFrame:SetHeight(310)
    listFrame:SetPoint("TOP", raidOnlyCheck, "BOTTOM", 0, -10)
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
  
  -- Determine which role filter to use based on targetRoleIndex
  -- Get role configuration for this encounter
  local roleFilterToSet = "all"
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
    
    -- Use the defaultRoles setting to determine which pool to show
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
    frame.roleFilterBtn:SetText(roleFilterToSet == "all" and "All Players" or roleFilterToSet)
  end
  
  -- Get raid members from current raid
  local function GetRaidMembers()
    local members = {}
    local raidOnly = OGRH_SV.playerSelectionRaidOnly
    
    -- Helper function to check if player is in raid
    local function IsInRaid(playerName)
      if not raidOnly then
        return true -- If raid only is off, include everyone
      end
      
      local numRaidMembers = GetNumRaidMembers()
      if numRaidMembers > 0 then
        for i = 1, numRaidMembers do
          local name = GetRaidRosterInfo(i)
          if name == playerName then
            return true
          end
        end
      end
      return false
    end
    
    -- Map dropdown filter names to role constants (matching RolesUI exactly)
    local filterToRole = {
      ["all"] = nil,
      ["Tanks"] = "TANKS",
      ["Healers"] = "HEALERS",
      ["Melee"] = "MELEE",
      ["Ranged"] = "RANGED"
    }
    
    local selectedRoleConst = filterToRole[frame.selectedFilter]
    
    if frame.selectedFilter == "all" then
      if raidOnly then
        -- Show all raid members
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
      else
        -- Show all players from all roles in RolesUI
        if OGRH.GetRolePlayers then
          local allRoles = {"TANKS", "HEALERS", "MELEE", "RANGED"}
          for _, roleConst in ipairs(allRoles) do
            local rolePlayers = OGRH.GetRolePlayers(roleConst)
            if rolePlayers then
              for i = 1, table.getn(rolePlayers) do
                local name = rolePlayers[i]
                if not members[name] then -- Avoid duplicates
                  -- Try to get class from raid roster
                  local class = nil
                  for j = 1, GetNumRaidMembers() do
                    local raidName, _, _, _, raidClass = GetRaidRosterInfo(j)
                    if raidName == name then
                      class = raidClass
                      break
                    end
                  end
                  -- Use stored class if not in raid
                  if not class and OGRH.Roles and OGRH.Roles.nameClass then
                    class = OGRH.Roles.nameClass[name]
                  end
                  members[name] = {
                    name = name,
                    role = "All",
                    class = class
                  }
                end
              end
            end
          end
        end
      end
    elseif selectedRoleConst then
      -- Get pool for this encounter and role
      local poolPlayers = {}
      if OGRH_SV.encounterPools and OGRH_SV.encounterPools[raidName] and 
         OGRH_SV.encounterPools[raidName][encounterName] and
         OGRH_SV.encounterPools[raidName][encounterName][targetRoleIndex] then
        poolPlayers = OGRH_SV.encounterPools[raidName][encounterName][targetRoleIndex]
      end
      
      -- Add players from pool
      for i = 1, table.getn(poolPlayers) do
        local name = poolPlayers[i]
        if IsInRaid(name) then
          -- Get class info from raid roster or stored data
          local class = nil
          for j = 1, GetNumRaidMembers() do
            local raidName, _, _, _, raidClass = GetRaidRosterInfo(j)
            if raidName == name then
              class = raidClass
              break
            end
          end
          -- Use stored class if not in raid
          if not class and OGRH.Roles and OGRH.Roles.nameClass then
            class = OGRH.Roles.nameClass[name]
          end
          members[name] = {
            name = name,
            role = selectedRoleConst,
            class = class
          }
        end
      end
    end
    
    return members
  end
  
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
      
      local roles = {"all", "Tanks", "Healers", "Melee", "Ranged"}
      local yOffset = -5
      
      for _, roleName in ipairs(roles) do
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
        text:SetText(roleName == "all" and "All Players" or roleName)
        
        local capturedRole = roleName
        btn:SetScript("OnClick", function()
          frame.selectedFilter = capturedRole
          frame.roleFilterBtn:SetText(capturedRole == "all" and "All Players" or capturedRole)
          menu:Hide()
          RefreshPlayerList()
        end)
        
        btn:SetScript("OnEnter", function() bg:SetVertexColor(0.3, 0.3, 0.4, 0.8) end)
        btn:SetScript("OnLeave", function() bg:SetVertexColor(0.2, 0.2, 0.2, 0.5) end)
        
        yOffset = yOffset - 22
      end
    end
    
    if frame.roleMenu:IsShown() then
      frame.roleMenu:Hide()
    else
      frame.roleMenu:Show()
    end
  end)
  
  -- OK button handler
  frame.okBtn:SetScript("OnClick", function()
    -- Initialize assignments
    if not OGRH_SV.encounterAssignments then
      OGRH_SV.encounterAssignments = {}
    end
    if not OGRH_SV.encounterAssignments[raidName] then
      OGRH_SV.encounterAssignments[raidName] = {}
    end
    if not OGRH_SV.encounterAssignments[raidName][encounterName] then
      OGRH_SV.encounterAssignments[raidName][encounterName] = {}
    end
    if not OGRH_SV.encounterAssignments[raidName][encounterName][targetRoleIndex] then
      OGRH_SV.encounterAssignments[raidName][encounterName][targetRoleIndex] = {}
    end
    
    if not frame.selectedPlayer then
      -- No player selected: clear the assignment
      OGRH_SV.encounterAssignments[raidName][encounterName][targetRoleIndex][targetSlotIndex] = nil
      DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OGRH:|r Assignment cleared.")
    else
      -- Assign player
      OGRH_SV.encounterAssignments[raidName][encounterName][targetRoleIndex][targetSlotIndex] = frame.selectedPlayer
    end
    
    -- Refresh encounter frame
    if encounterFrame and encounterFrame.RefreshRoleContainers then
      encounterFrame.RefreshRoleContainers()
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
    frame:SetHeight(280)
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
    
    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", frame, "TOP", 0, -10)
    title:SetText("Edit Role")
    
    -- Role Name Label
    local nameLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, -40)
    nameLabel:SetText("Role Name:")
    
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
    
    -- Raid Icons Checkbox
    local raidIconsLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    raidIconsLabel:SetPoint("TOPLEFT", nameEditBox, "BOTTOMLEFT", -5, -15)
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
    
    -- Player Count Label
    local countLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    countLabel:SetPoint("TOPLEFT", showAssignmentLabel, "BOTTOMLEFT", 0, -15)
    countLabel:SetText("Player Count:")
    
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
    
    -- Default Player Roles Label
    local rolesLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    rolesLabel:SetPoint("TOPLEFT", countLabel, "BOTTOMLEFT", 0, -15)
    rolesLabel:SetText("Default Player Roles:")
    
    -- Role checkboxes
    local tankCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    tankCheck:SetPoint("TOPLEFT", rolesLabel, "BOTTOMLEFT", 10, -5)
    tankCheck:SetWidth(24)
    tankCheck:SetHeight(24)
    local tankLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    tankLabel:SetPoint("LEFT", tankCheck, "RIGHT", 5, 0)
    tankLabel:SetText("Tanks")
    frame.tankCheck = tankCheck
    
    local healerCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    healerCheck:SetPoint("TOPLEFT", tankCheck, "BOTTOMLEFT", 0, -5)
    healerCheck:SetWidth(24)
    healerCheck:SetHeight(24)
    local healerLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    healerLabel:SetPoint("LEFT", healerCheck, "RIGHT", 5, 0)
    healerLabel:SetText("Healers")
    frame.healerCheck = healerCheck
    
    local meleeCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    meleeCheck:SetPoint("LEFT", tankCheck, "LEFT", 120, 0)
    meleeCheck:SetWidth(24)
    meleeCheck:SetHeight(24)
    local meleeLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    meleeLabel:SetPoint("LEFT", meleeCheck, "RIGHT", 5, 0)
    meleeLabel:SetText("Melee")
    frame.meleeCheck = meleeCheck
    
    local rangedCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    rangedCheck:SetPoint("TOPLEFT", meleeCheck, "BOTTOMLEFT", 0, -5)
    rangedCheck:SetWidth(24)
    rangedCheck:SetHeight(24)
    local rangedLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    rangedLabel:SetPoint("LEFT", rangedCheck, "RIGHT", 5, 0)
    rangedLabel:SetText("Ranged")
    frame.rangedCheck = rangedCheck
    
    -- Make checkboxes act like radio buttons (only one can be selected)
    local roleChecks = {tankCheck, healerCheck, meleeCheck, rangedCheck}
    for _, check in ipairs(roleChecks) do
      check:SetScript("OnClick", function()
        if this:GetChecked() then
          -- Uncheck all others
          for _, otherCheck in ipairs(roleChecks) do
            if otherCheck ~= this then
              otherCheck:SetChecked(false)
            end
          end
        end
      end)
    end
    
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
  
  -- Populate fields with current role data
  frame.nameEditBox:SetText(roleData.name or "")
  frame.raidIconsCheckbox:SetChecked(roleData.showRaidIcons or false)
  frame.showAssignmentCheckbox:SetChecked(roleData.showAssignment or false)
  frame.markPlayerCheckbox:SetChecked(roleData.markPlayer or false)
  frame.allowOtherRolesCheckbox:SetChecked(roleData.allowOtherRoles or false)
  frame.countEditBox:SetText(tostring(roleData.slots or 1))
  
  -- Set default roles checkboxes (only one should be checked)
  local defaultRoles = roleData.defaultRoles or {}
  frame.tankCheck:SetChecked(defaultRoles.tanks or false)
  frame.healerCheck:SetChecked(defaultRoles.healers or false)
  frame.meleeCheck:SetChecked(defaultRoles.melee or false)
  frame.rangedCheck:SetChecked(defaultRoles.ranged or false)
  
  -- Save button handler
  frame.saveBtn:SetScript("OnClick", function()
    -- Update role data
    roleData.name = frame.nameEditBox:GetText()
    roleData.showRaidIcons = frame.raidIconsCheckbox:GetChecked()
    roleData.showAssignment = frame.showAssignmentCheckbox:GetChecked()
    roleData.markPlayer = frame.markPlayerCheckbox:GetChecked()
    roleData.allowOtherRoles = frame.allowOtherRolesCheckbox:GetChecked()
    roleData.slots = tonumber(frame.countEditBox:GetText()) or 1
    
    -- Update default roles (clear all, then set the checked one)
    if not roleData.defaultRoles then
      roleData.defaultRoles = {}
    end
    roleData.defaultRoles.tanks = frame.tankCheck:GetChecked()
    roleData.defaultRoles.healers = frame.healerCheck:GetChecked()
    roleData.defaultRoles.melee = frame.meleeCheck:GetChecked()
    roleData.defaultRoles.ranged = frame.rangedCheck:GetChecked()
    
    -- Refresh the roles list
    if refreshCallback then
      refreshCallback()
    end
    
    frame:Hide()
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OGRH:|r Role updated")
  end)
  
  frame:Show()
end

-- Function to show Pool Defaults management window
function OGRH.ShowPoolDefaultsWindow()
  -- Create window if it doesn't exist
  if not OGRH_PoolDefaultsFrame then
    local frame = CreateFrame("Frame", "OGRH_PoolDefaultsFrame", UIParent)
    frame:SetWidth(500)
    frame:SetHeight(450)
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
    frame:SetBackdropColor(0, 0, 0, 0.95)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function() frame:StartMoving() end)
    frame:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
    
    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", frame, "TOP", 0, -15)
    title:SetText("Role Defaults")
    
    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    closeBtn:SetWidth(60)
    closeBtn:SetHeight(24)
    closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -10)
    closeBtn:SetText("Close")
    closeBtn:SetScript("OnClick", function() frame:Hide() end)
    
    -- Role selection dropdown
    local roleDropdown = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    roleDropdown:SetWidth(150)
    roleDropdown:SetHeight(24)
    roleDropdown:SetPoint("TOP", title, "BOTTOM", 0, -10)
    roleDropdown:SetText("Tanks")
    frame.roleDropdown = roleDropdown
    frame.selectedRole = 1
    frame.selectedRoleName = "Tanks"
    
    roleDropdown:SetScript("OnClick", function()
      if not frame.roleMenu then
        local menu = CreateFrame("Frame", nil, frame)
        menu:SetWidth(150)
        menu:SetHeight(100)
        menu:SetFrameStrata("FULLSCREEN_DIALOG")
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
        
        local roleNames = {"Tanks", "Healers", "Melee", "Ranged"}
        local yOffset = -5
        
        for i, roleName in ipairs(roleNames) do
          local btn = CreateFrame("Button", nil, menu, "UIPanelButtonTemplate")
          btn:SetWidth(140)
          btn:SetHeight(20)
          btn:SetPoint("TOP", menu, "TOP", 0, yOffset)
          btn:SetText(roleName)
          
          local capturedIndex = i
          local capturedName = roleName
          btn:SetScript("OnClick", function()
            frame.selectedRole = capturedIndex
            frame.selectedRoleName = capturedName
            roleDropdown:SetText(capturedName)
            menu:Hide()
            -- Refresh the lists based on selected role
            if frame.RefreshGuildList and frame.RefreshAssignedList then
              frame.RefreshGuildList()
              frame.RefreshAssignedList()
            end
          end)
          
          yOffset = yOffset - 22
        end
      end
      
      if frame.roleMenu:IsVisible() then
        frame.roleMenu:Hide()
      else
        frame.roleMenu:ClearAllPoints()
        frame.roleMenu:SetPoint("TOP", roleDropdown, "BOTTOM", 0, -2)
        frame.roleMenu:Show()
      end
    end)
    
    -- Left panel: Guild members
    local leftPanel = CreateFrame("Frame", nil, frame)
    leftPanel:SetWidth(225)
    leftPanel:SetHeight(340)
    leftPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -80)
    leftPanel:SetBackdrop({
      bgFile = "Interface/Tooltips/UI-Tooltip-Background",
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
      tile = true,
      tileSize = 16,
      edgeSize = 12,
      insets = {left = 3, right = 3, top = 3, bottom = 3}
    })
    leftPanel:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
    
    -- Guild label
    local guildLabel = leftPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    guildLabel:SetPoint("TOP", leftPanel, "TOP", 0, -8)
    guildLabel:SetText("Guild")
    
    -- Search/Filter text box
    local searchBox = CreateFrame("EditBox", nil, leftPanel)
    searchBox:SetWidth(200)
    searchBox:SetHeight(20)
    searchBox:SetPoint("TOP", guildLabel, "BOTTOM", 0, -5)
    searchBox:SetAutoFocus(false)
    searchBox:SetFontObject(GameFontHighlight)
    searchBox:SetTextInsets(5, 5, 0, 0)
    
    -- Search box background
    local searchBg = searchBox:CreateTexture(nil, "BACKGROUND")
    searchBg:SetAllPoints(searchBox)
    searchBg:SetTexture("Interface\\Buttons\\WHITE8X8")
    searchBg:SetVertexColor(0.1, 0.1, 0.1, 0.9)
    
    -- Search box border
    local searchBorder = CreateFrame("Frame", nil, leftPanel)
    searchBorder:SetWidth(210)
    searchBorder:SetHeight(24)
    searchBorder:SetPoint("CENTER", searchBox, "CENTER", 0, 0)
    searchBorder:SetBackdrop({
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
      edgeSize = 12,
      insets = {left = 2, right = 2, top = 2, bottom = 2}
    })
    
    frame.searchBox = searchBox
    frame.searchFilter = ""
    
    -- Update filter when text changes
    searchBox:SetScript("OnTextChanged", function()
      frame.searchFilter = string.lower(searchBox:GetText() or "")
      if frame.RefreshGuildList then
        frame.RefreshGuildList()
      end
    end)
    
    searchBox:SetScript("OnEscapePressed", function()
      searchBox:ClearFocus()
    end)
    
    searchBox:SetScript("OnEnterPressed", function()
      searchBox:ClearFocus()
    end)
    
    -- Guild scroll frame
    local guildScrollFrame = CreateFrame("ScrollFrame", nil, leftPanel)
    guildScrollFrame:SetPoint("TOPLEFT", leftPanel, "TOPLEFT", 5, -60)
    guildScrollFrame:SetPoint("BOTTOMRIGHT", leftPanel, "BOTTOMRIGHT", -20, 5)
    
    local guildScrollChild = CreateFrame("Frame", nil, guildScrollFrame)
    guildScrollChild:SetWidth(195)
    guildScrollChild:SetHeight(1)
    guildScrollFrame:SetScrollChild(guildScrollChild)
    frame.guildScrollChild = guildScrollChild
    
    -- Guild scroll bar
    local guildScrollBar = CreateFrame("Slider", nil, leftPanel)
    guildScrollBar:SetOrientation("VERTICAL")
    guildScrollBar:SetPoint("TOPRIGHT", leftPanel, "TOPRIGHT", -5, -60)
    guildScrollBar:SetPoint("BOTTOMRIGHT", leftPanel, "BOTTOMRIGHT", -5, 5)
    guildScrollBar:SetWidth(16)
    guildScrollBar:SetBackdrop({
      bgFile = "Interface/Buttons/WHITE8X8",
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
      tile = true,
      tileSize = 8,
      edgeSize = 8,
      insets = {left = 3, right = 3, top = 3, bottom = 3}
    })
    guildScrollBar:SetBackdropColor(0.1, 0.1, 0.1, 0.5)
    guildScrollBar:SetMinMaxValues(0, 100)
    guildScrollBar:SetValue(0)
    guildScrollBar:SetValueStep(1)
    
    local guildThumb = guildScrollBar:CreateTexture(nil, "OVERLAY")
    guildThumb:SetTexture("Interface/Buttons/UI-ScrollBar-Knob")
    guildThumb:SetWidth(16)
    guildThumb:SetHeight(24)
    guildScrollBar:SetThumbTexture(guildThumb)
    
    guildScrollBar:SetScript("OnValueChanged", function()
      local value = guildScrollBar:GetValue()
      guildScrollFrame:SetVerticalScroll(value)
    end)
    
    -- Enable mouse wheel scrolling for guild
    guildScrollFrame:EnableMouseWheel(true)
    guildScrollFrame:SetScript("OnMouseWheel", function()
      local delta = arg1
      local current = guildScrollFrame:GetVerticalScroll()
      local maxScroll = guildScrollChild:GetHeight() - guildScrollFrame:GetHeight()
      if maxScroll < 0 then maxScroll = 0 end
      
      local newScroll = current - (delta * 20)
      if newScroll < 0 then
        newScroll = 0
      elseif newScroll > maxScroll then
        newScroll = maxScroll
      end
      guildScrollFrame:SetVerticalScroll(newScroll)
      guildScrollBar:SetValue(newScroll)
    end)
    
    frame.guildScrollBar = guildScrollBar
    
    -- Right panel: Assigned members
    local rightPanel = CreateFrame("Frame", nil, frame)
    rightPanel:SetWidth(225)
    rightPanel:SetHeight(340)
    rightPanel:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -80)
    rightPanel:SetBackdrop({
      bgFile = "Interface/Tooltips/UI-Tooltip-Background",
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
      tile = true,
      tileSize = 16,
      edgeSize = 12,
      insets = {left = 3, right = 3, top = 3, bottom = 3}
    })
    rightPanel:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
    
    -- Assigned label
    local assignedLabel = rightPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    assignedLabel:SetPoint("TOP", rightPanel, "TOP", 0, -8)
    assignedLabel:SetText("Assigned")
    
    -- Assigned scroll frame
    local assignedScrollFrame = CreateFrame("ScrollFrame", nil, rightPanel)
    assignedScrollFrame:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", 5, -30)
    assignedScrollFrame:SetPoint("BOTTOMRIGHT", rightPanel, "BOTTOMRIGHT", -20, 5)
    
    local assignedScrollChild = CreateFrame("Frame", nil, assignedScrollFrame)
    assignedScrollChild:SetWidth(195)
    assignedScrollChild:SetHeight(1)
    assignedScrollFrame:SetScrollChild(assignedScrollChild)
    frame.assignedScrollChild = assignedScrollChild
    
    -- Assigned scroll bar
    local assignedScrollBar = CreateFrame("Slider", nil, rightPanel)
    assignedScrollBar:SetOrientation("VERTICAL")
    assignedScrollBar:SetPoint("TOPRIGHT", rightPanel, "TOPRIGHT", -5, -30)
    assignedScrollBar:SetPoint("BOTTOMRIGHT", rightPanel, "BOTTOMRIGHT", -5, 5)
    assignedScrollBar:SetWidth(16)
    assignedScrollBar:SetBackdrop({
      bgFile = "Interface/Buttons/WHITE8X8",
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
      tile = true,
      tileSize = 8,
      edgeSize = 8,
      insets = {left = 3, right = 3, top = 3, bottom = 3}
    })
    assignedScrollBar:SetBackdropColor(0.1, 0.1, 0.1, 0.5)
    assignedScrollBar:SetMinMaxValues(0, 100)
    assignedScrollBar:SetValue(0)
    assignedScrollBar:SetValueStep(1)
    
    local assignedThumb = assignedScrollBar:CreateTexture(nil, "OVERLAY")
    assignedThumb:SetTexture("Interface/Buttons/UI-ScrollBar-Knob")
    assignedThumb:SetWidth(16)
    assignedThumb:SetHeight(24)
    assignedScrollBar:SetThumbTexture(assignedThumb)
    
    assignedScrollBar:SetScript("OnValueChanged", function()
      local value = assignedScrollBar:GetValue()
      assignedScrollFrame:SetVerticalScroll(value)
    end)
    
    -- Enable mouse wheel scrolling for assigned
    assignedScrollFrame:EnableMouseWheel(true)
    assignedScrollFrame:SetScript("OnMouseWheel", function()
      local delta = arg1
      local current = assignedScrollFrame:GetVerticalScroll()
      local maxScroll = assignedScrollChild:GetHeight() - assignedScrollFrame:GetHeight()
      if maxScroll < 0 then maxScroll = 0 end
      
      local newScroll = current - (delta * 20)
      if newScroll < 0 then
        newScroll = 0
      elseif newScroll > maxScroll then
        newScroll = maxScroll
      end
      assignedScrollFrame:SetVerticalScroll(newScroll)
      assignedScrollBar:SetValue(newScroll)
    end)
    
    frame.assignedScrollBar = assignedScrollBar
    
    -- Function to update guild scroll bar range
    frame.updateGuildScrollBar = function()
      local maxScroll = guildScrollChild:GetHeight() - guildScrollFrame:GetHeight()
      if maxScroll < 0 then maxScroll = 0 end
      guildScrollBar:SetMinMaxValues(0, maxScroll)
    end
    
    -- Function to update assigned scroll bar range
    frame.updateAssignedScrollBar = function()
      local maxScroll = assignedScrollChild:GetHeight() - assignedScrollFrame:GetHeight()
      if maxScroll < 0 then maxScroll = 0 end
      assignedScrollBar:SetMinMaxValues(0, maxScroll)
    end
    
    -- Function to refresh guild members list
    frame.RefreshGuildList = function()
      -- Clear existing buttons
      local children = {guildScrollChild:GetChildren()}
      for i = 1, table.getn(children) do
        if children[i] then
          children[i]:Hide()
          children[i]:SetParent(nil)
        end
      end
      
      -- Define class filters for each role
      local roleClasses = {
        {name = "Tanks", classes = {"WARRIOR", "DRUID", "PALADIN", "SHAMAN"}},
        {name = "Healers", classes = {"PALADIN", "PRIEST", "DRUID", "SHAMAN"}},
        {name = "Melee", classes = {"ROGUE", "WARRIOR", "PALADIN", "DRUID", "HUNTER", "SHAMAN"}},
        {name = "Ranged", classes = {"DRUID", "HUNTER", "SHAMAN", "MAGE", "WARLOCK", "PRIEST"}}
      }
      
      local currentRoleData = roleClasses[frame.selectedRole]
      if not currentRoleData then return end
      
      -- Get guild roster
      local numGuildMembers = GetNumGuildMembers()
      local onlinePlayers = {}
      local offlinePlayers = {}
      local fourteenDaysInSeconds = 14 * 24 * 60 * 60
      
      -- Get assigned players for this role from SavedVariables
      if not OGRH_SV.poolDefaults then
        OGRH_SV.poolDefaults = {}
      end
      if not OGRH_SV.poolDefaults[frame.selectedRole] then
        OGRH_SV.poolDefaults[frame.selectedRole] = {}
      end
      local assignedPlayers = OGRH_SV.poolDefaults[frame.selectedRole]
      
      -- Build assigned lookup table
      local assignedLookup = {}
      for i = 1, table.getn(assignedPlayers) do
        assignedLookup[assignedPlayers[i]] = true
      end
      
      for i = 1, numGuildMembers do
        local name, _, _, level, class, _, _, _, online, _, _, _, _, _, _, _, lastOnline = GetGuildRosterInfo(i)
        
        if name and level == 60 then
          -- Check if class is in the allowed list for this role
          local classAllowed = false
          for j = 1, table.getn(currentRoleData.classes) do
            if string.upper(class) == currentRoleData.classes[j] then
              classAllowed = true
              break
            end
          end
          
          if classAllowed then
            -- Store class info for color coding
            local upperClass = string.upper(class)
            if not OGRH.Roles then OGRH.Roles = {} end
            if not OGRH.Roles.nameClass then OGRH.Roles.nameClass = {} end
            OGRH.Roles.nameClass[name] = upperClass
            
            -- Check if player has been online in the past 14 days
            local includePlayer = true
            if not online then
              if lastOnline and lastOnline > fourteenDaysInSeconds then
                includePlayer = false
              end
            end
            
            -- Only include if not already assigned and meets activity requirement
            if includePlayer and not assignedLookup[name] then
              -- Apply search filter
              local nameMatch = true
              if frame.searchFilter and frame.searchFilter ~= "" then
                nameMatch = string.find(string.lower(name), frame.searchFilter, 1, true) ~= nil
              end
              
              if nameMatch then
                if online then
                  table.insert(onlinePlayers, {name = name, class = upperClass})
                else
                  table.insert(offlinePlayers, {name = name, class = upperClass})
                end
              end
            end
          end
        end
      end
      
      -- Sort alphabetically
      local function sortByName(a, b)
        return a.name < b.name
      end
      
      table.sort(onlinePlayers, sortByName)
      table.sort(offlinePlayers, sortByName)
      
      -- Combine: online first, then offline
      local allPlayers = {}
      for i = 1, table.getn(onlinePlayers) do
        table.insert(allPlayers, {name = onlinePlayers[i].name, online = true})
      end
      for i = 1, table.getn(offlinePlayers) do
        table.insert(allPlayers, {name = offlinePlayers[i].name, online = false})
      end
      
      -- Create player buttons
      local yOffset = 0
      for i, playerData in ipairs(allPlayers) do
        local btn = CreateFrame("Button", nil, guildScrollChild)
        btn:SetWidth(200)
        btn:SetHeight(18)
        btn:SetPoint("TOPLEFT", guildScrollChild, "TOPLEFT", 0, -yOffset)
        
        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetTexture("Interface\\Buttons\\WHITE8X8")
        bg:SetVertexColor(0.2, 0.2, 0.2, 0.5)
        
        local text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        text:SetPoint("LEFT", btn, "LEFT", 5, 0)
        
        -- Apply class color
        local displayName = playerData.name
        if OGRH.ClassColorHex and OGRH.Roles.nameClass[playerData.name] then
          local class = OGRH.Roles.nameClass[playerData.name]
          displayName = OGRH.ClassColorHex(class) .. playerData.name .. "|r"
        end
        
        if not playerData.online then
          displayName = displayName .. " |cFF888888(Offline)|r"
        end
        text:SetText(displayName)
        
        -- Click to assign
        local capturedName = playerData.name
        btn:SetScript("OnClick", function()
          table.insert(OGRH_SV.poolDefaults[frame.selectedRole], capturedName)
          frame.RefreshGuildList()
          frame.RefreshAssignedList()
        end)
        
        yOffset = yOffset + 20
      end
      
      guildScrollChild:SetHeight(math.max(1, yOffset))
      frame.updateGuildScrollBar()
    end
    
    -- Function to refresh assigned members list
    frame.RefreshAssignedList = function()
      -- Clear existing buttons
      local children = {assignedScrollChild:GetChildren()}
      for i = 1, table.getn(children) do
        if children[i] then
          children[i]:Hide()
          children[i]:SetParent(nil)
        end
      end
      
      -- Get assigned players for this role
      if not OGRH_SV.poolDefaults then
        OGRH_SV.poolDefaults = {}
      end
      if not OGRH_SV.poolDefaults[frame.selectedRole] then
        OGRH_SV.poolDefaults[frame.selectedRole] = {}
      end
      local assignedPlayers = OGRH_SV.poolDefaults[frame.selectedRole]
      
      -- Sort alphabetically
      table.sort(assignedPlayers, function(a, b)
        return a < b
      end)
      
      -- Create player buttons
      local yOffset = 0
      for i, playerName in ipairs(assignedPlayers) do
        local playerFrame = CreateFrame("Frame", nil, assignedScrollChild)
        playerFrame:SetWidth(220)
        playerFrame:SetHeight(20)
        playerFrame:SetPoint("TOPLEFT", assignedScrollChild, "TOPLEFT", 0, -yOffset)
        
        local bg = playerFrame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetTexture("Interface\\Buttons\\WHITE8X8")
        bg:SetVertexColor(0.15, 0.15, 0.15, 0.8)
        
        -- Remove button
        local removeBtn = CreateFrame("Button", nil, playerFrame, "UIPanelButtonTemplate")
        removeBtn:SetWidth(16)
        removeBtn:SetHeight(16)
        removeBtn:SetPoint("LEFT", playerFrame, "LEFT", 2, 0)
        removeBtn:SetText("X")
        
        local currentIndex = i
        removeBtn:SetScript("OnClick", function()
          table.remove(OGRH_SV.poolDefaults[frame.selectedRole], currentIndex)
          frame.RefreshGuildList()
          frame.RefreshAssignedList()
        end)
        
        -- Player name with class color
        local nameText = playerFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        nameText:SetPoint("LEFT", removeBtn, "RIGHT", 5, 0)
        
        if OGRH.ClassColorHex and OGRH.Roles and OGRH.Roles.nameClass then
          local class = OGRH.Roles.nameClass[playerName]
          if class then
            nameText:SetText(OGRH.ClassColorHex(class) .. playerName .. "|r")
          else
            nameText:SetText(playerName)
          end
        else
          nameText:SetText(playerName)
        end
        
        yOffset = yOffset + 22
      end
      
      assignedScrollChild:SetHeight(math.max(1, yOffset))
      frame.updateAssignedScrollBar()
    end
    
    OGRH_PoolDefaultsFrame = frame
  end
  
  -- Refresh guild roster to update class colors
  GuildRoster()
  
  -- Show the window and refresh lists
  OGRH_PoolDefaultsFrame:Show()
  OGRH_PoolDefaultsFrame.RefreshGuildList()
  OGRH_PoolDefaultsFrame.RefreshAssignedList()
  
  DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00OGRH:|r Role Defaults window opened")
end

-- Function to show Encounter Pool management window
function OGRH.ShowEncounterPoolWindow(raidName, encounterName, role, roleIndex)
  -- Create window if it doesn't exist
  if not OGRH_EncounterPoolFrame then
    local frame = CreateFrame("Frame", "OGRH_EncounterPoolFrame", UIParent)
    frame:SetWidth(500)
    frame:SetHeight(450)
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
    frame:SetBackdropColor(0, 0, 0, 0.95)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function() frame:StartMoving() end)
    frame:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
    
    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", frame, "TOP", 0, -15)
    frame.title = title
    
    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    closeBtn:SetWidth(60)
    closeBtn:SetHeight(24)
    closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -10)
    closeBtn:SetText("Close")
    closeBtn:SetScript("OnClick", function() frame:Hide() end)
    
    -- Source selection dropdown
    local sourceDropdown = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    sourceDropdown:SetWidth(180)
    sourceDropdown:SetHeight(24)
    sourceDropdown:SetPoint("TOP", title, "BOTTOM", 0, -10)
    sourceDropdown:SetText("Tanks")
    frame.sourceDropdown = sourceDropdown
    frame.selectedSource = "role_tanks"
    
    sourceDropdown:SetScript("OnClick", function()
      if not frame.sourceMenu then
        local menu = CreateFrame("Frame", nil, frame)
        menu:SetWidth(180)
        menu:SetHeight(230)
        menu:SetFrameStrata("FULLSCREEN_DIALOG")
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
        frame.sourceMenu = menu
        
        local sourceOptions = {
          {text = "Raid: Tanks", value = "role_tanks"},
          {text = "Raid: Healers", value = "role_healers"},
          {text = "Raid: Melee", value = "role_melee"},
          {text = "Raid: Ranged", value = "role_ranged"},
          {text = "Guild: Tanks", value = "default_tanks"},
          {text = "Guild: Healers", value = "default_healers"},
          {text = "Guild: Melee", value = "default_melee"},
          {text = "Guild: Ranged", value = "default_ranged"}
        }
        local yOffset = -5
        
        for i, option in ipairs(sourceOptions) do
          local btn = CreateFrame("Button", nil, menu, "UIPanelButtonTemplate")
          btn:SetWidth(170)
          btn:SetHeight(24)
          btn:SetPoint("TOP", menu, "TOP", 0, yOffset)
          btn:SetText(option.text)
          
          local capturedValue = option.value
          local capturedText = option.text
          btn:SetScript("OnClick", function()
            frame.selectedSource = capturedValue
            sourceDropdown:SetText(capturedText)
            menu:Hide()
            -- Refresh the available players list
            if frame.RefreshAvailableList then
              frame.RefreshAvailableList()
            end
          end)
          
          yOffset = yOffset - 28
        end
      end
      
      if frame.sourceMenu:IsVisible() then
        frame.sourceMenu:Hide()
      else
        frame.sourceMenu:ClearAllPoints()
        frame.sourceMenu:SetPoint("TOP", sourceDropdown, "BOTTOM", 0, -2)
        frame.sourceMenu:Show()
      end
    end)
    
    -- Left panel: Available players
    local leftPanel = CreateFrame("Frame", nil, frame)
    leftPanel:SetWidth(225)
    leftPanel:SetHeight(340)
    leftPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -80)
    leftPanel:SetBackdrop({
      bgFile = "Interface/Tooltips/UI-Tooltip-Background",
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
      tile = true,
      tileSize = 16,
      edgeSize = 12,
      insets = {left = 3, right = 3, top = 3, bottom = 3}
    })
    leftPanel:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
    
    -- Available label
    local availableLabel = leftPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    availableLabel:SetPoint("TOP", leftPanel, "TOP", 0, -8)
    availableLabel:SetText("Available")
    
    -- Available scroll frame
    local availScrollFrame = CreateFrame("ScrollFrame", nil, leftPanel)
    availScrollFrame:SetPoint("TOPLEFT", leftPanel, "TOPLEFT", 5, -30)
    availScrollFrame:SetPoint("BOTTOMRIGHT", leftPanel, "BOTTOMRIGHT", -20, 5)
    
    local availScrollChild = CreateFrame("Frame", nil, availScrollFrame)
    availScrollChild:SetWidth(195)
    availScrollChild:SetHeight(1)
    availScrollFrame:SetScrollChild(availScrollChild)
    frame.availScrollChild = availScrollChild
    
    -- Available scroll bar
    local availScrollBar = CreateFrame("Slider", nil, leftPanel)
    availScrollBar:SetOrientation("VERTICAL")
    availScrollBar:SetPoint("TOPRIGHT", leftPanel, "TOPRIGHT", -5, -30)
    availScrollBar:SetPoint("BOTTOMRIGHT", leftPanel, "BOTTOMRIGHT", -5, 5)
    availScrollBar:SetWidth(16)
    availScrollBar:SetBackdrop({
      bgFile = "Interface/Buttons/WHITE8X8",
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
      tile = true,
      tileSize = 8,
      edgeSize = 8,
      insets = {left = 3, right = 3, top = 3, bottom = 3}
    })
    availScrollBar:SetBackdropColor(0.1, 0.1, 0.1, 0.5)
    availScrollBar:SetMinMaxValues(0, 100)
    availScrollBar:SetValue(0)
    availScrollBar:SetValueStep(1)
    
    local availThumb = availScrollBar:CreateTexture(nil, "OVERLAY")
    availThumb:SetTexture("Interface/Buttons/UI-ScrollBar-Knob")
    availThumb:SetWidth(16)
    availThumb:SetHeight(24)
    availScrollBar:SetThumbTexture(availThumb)
    
    availScrollBar:SetScript("OnValueChanged", function()
      local value = availScrollBar:GetValue()
      availScrollFrame:SetVerticalScroll(value)
    end)
    
    -- Enable mouse wheel scrolling for available
    availScrollFrame:EnableMouseWheel(true)
    availScrollFrame:SetScript("OnMouseWheel", function()
      local delta = arg1
      local current = availScrollFrame:GetVerticalScroll()
      local maxScroll = availScrollChild:GetHeight() - availScrollFrame:GetHeight()
      if maxScroll < 0 then maxScroll = 0 end
      
      local newScroll = current - (delta * 20)
      if newScroll < 0 then
        newScroll = 0
      elseif newScroll > maxScroll then
        newScroll = maxScroll
      end
      availScrollFrame:SetVerticalScroll(newScroll)
      availScrollBar:SetValue(newScroll)
    end)
    
    frame.availScrollBar = availScrollBar
    
    -- Right panel: Pool members
    local rightPanel = CreateFrame("Frame", nil, frame)
    rightPanel:SetWidth(225)
    rightPanel:SetHeight(340)
    rightPanel:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -80)
    rightPanel:SetBackdrop({
      bgFile = "Interface/Tooltips/UI-Tooltip-Background",
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
      tile = true,
      tileSize = 16,
      edgeSize = 12,
      insets = {left = 3, right = 3, top = 3, bottom = 3}
    })
    rightPanel:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
    
    -- Pool label
    local poolLabel = rightPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    poolLabel:SetPoint("TOP", rightPanel, "TOP", 0, -8)
    poolLabel:SetText("Pool")
    
    -- Pool scroll frame
    local poolScrollFrame = CreateFrame("ScrollFrame", nil, rightPanel)
    poolScrollFrame:SetPoint("TOPLEFT", rightPanel, "TOPLEFT", 5, -30)
    poolScrollFrame:SetPoint("BOTTOMRIGHT", rightPanel, "BOTTOMRIGHT", -20, 5)
    
    local poolScrollChild = CreateFrame("Frame", nil, poolScrollFrame)
    poolScrollChild:SetWidth(195)
    poolScrollChild:SetHeight(1)
    poolScrollFrame:SetScrollChild(poolScrollChild)
    frame.poolScrollChild = poolScrollChild
    
    -- Pool scroll bar
    local poolScrollBar = CreateFrame("Slider", nil, rightPanel)
    poolScrollBar:SetOrientation("VERTICAL")
    poolScrollBar:SetPoint("TOPRIGHT", rightPanel, "TOPRIGHT", -5, -30)
    poolScrollBar:SetPoint("BOTTOMRIGHT", rightPanel, "BOTTOMRIGHT", -5, 5)
    poolScrollBar:SetWidth(16)
    poolScrollBar:SetBackdrop({
      bgFile = "Interface/Buttons/WHITE8X8",
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
      tile = true,
      tileSize = 8,
      edgeSize = 8,
      insets = {left = 3, right = 3, top = 3, bottom = 3}
    })
    poolScrollBar:SetBackdropColor(0.1, 0.1, 0.1, 0.5)
    poolScrollBar:SetMinMaxValues(0, 100)
    poolScrollBar:SetValue(0)
    poolScrollBar:SetValueStep(1)
    
    local poolThumb = poolScrollBar:CreateTexture(nil, "OVERLAY")
    poolThumb:SetTexture("Interface/Buttons/UI-ScrollBar-Knob")
    poolThumb:SetWidth(16)
    poolThumb:SetHeight(24)
    poolScrollBar:SetThumbTexture(poolThumb)
    
    poolScrollBar:SetScript("OnValueChanged", function()
      local value = poolScrollBar:GetValue()
      poolScrollFrame:SetVerticalScroll(value)
    end)
    
    -- Enable mouse wheel scrolling for pool
    poolScrollFrame:EnableMouseWheel(true)
    poolScrollFrame:SetScript("OnMouseWheel", function()
      local delta = arg1
      local current = poolScrollFrame:GetVerticalScroll()
      local maxScroll = poolScrollChild:GetHeight() - poolScrollFrame:GetHeight()
      if maxScroll < 0 then maxScroll = 0 end
      
      local newScroll = current - (delta * 20)
      if newScroll < 0 then
        newScroll = 0
      elseif newScroll > maxScroll then
        newScroll = maxScroll
      end
      poolScrollFrame:SetVerticalScroll(newScroll)
      poolScrollBar:SetValue(newScroll)
    end)
    
    frame.poolScrollBar = poolScrollBar
    
    -- Function to update scroll bar ranges
    frame.updateAvailScrollBar = function()
      local maxScroll = availScrollChild:GetHeight() - availScrollFrame:GetHeight()
      if maxScroll < 0 then maxScroll = 0 end
      availScrollBar:SetMinMaxValues(0, maxScroll)
    end
    
    frame.updatePoolScrollBar = function()
      local maxScroll = poolScrollChild:GetHeight() - poolScrollFrame:GetHeight()
      if maxScroll < 0 then maxScroll = 0 end
      poolScrollBar:SetMinMaxValues(0, maxScroll)
    end
    
    -- Function to refresh available players list
    frame.RefreshAvailableList = function()
      -- Clear existing buttons
      local children = {availScrollChild:GetChildren()}
      for i = 1, table.getn(children) do
        if children[i] then
          children[i]:Hide()
          children[i]:SetParent(nil)
        end
      end
      
      -- Get pool data
      if not OGRH_SV.encounterPools then
        OGRH_SV.encounterPools = {}
      end
      if not OGRH_SV.encounterPools[frame.currentRaid] then
        OGRH_SV.encounterPools[frame.currentRaid] = {}
      end
      if not OGRH_SV.encounterPools[frame.currentRaid][frame.currentEncounter] then
        OGRH_SV.encounterPools[frame.currentRaid][frame.currentEncounter] = {}
      end
      if not OGRH_SV.encounterPools[frame.currentRaid][frame.currentEncounter][frame.currentRoleIndex] then
        OGRH_SV.encounterPools[frame.currentRaid][frame.currentEncounter][frame.currentRoleIndex] = {}
      end
      
      local pool = OGRH_SV.encounterPools[frame.currentRaid][frame.currentEncounter][frame.currentRoleIndex]
      
      -- Build pool lookup table
      local poolLookup = {}
      for i = 1, table.getn(pool) do
        poolLookup[pool[i]] = true
      end
      
      -- Get available players based on selected source
      local availablePlayers = {}
      
      if frame.selectedSource == "role_tanks" then
        -- Get players from Tanks role in RolesUI
        if OGRH.GetRolePlayers then
          local tanks = OGRH.GetRolePlayers("TANKS")
          for i = 1, table.getn(tanks) do
            if not poolLookup[tanks[i]] then
              table.insert(availablePlayers, tanks[i])
            end
          end
        end
      elseif frame.selectedSource == "role_healers" then
        -- Get players from Healers role in RolesUI
        if OGRH.GetRolePlayers then
          local healers = OGRH.GetRolePlayers("HEALERS")
          for i = 1, table.getn(healers) do
            if not poolLookup[healers[i]] then
              table.insert(availablePlayers, healers[i])
            end
          end
        end
      elseif frame.selectedSource == "role_melee" then
        -- Get players from Melee role in RolesUI
        if OGRH.GetRolePlayers then
          local melee = OGRH.GetRolePlayers("MELEE")
          for i = 1, table.getn(melee) do
            if not poolLookup[melee[i]] then
              table.insert(availablePlayers, melee[i])
            end
          end
        end
      elseif frame.selectedSource == "role_ranged" then
        -- Get players from Ranged role in RolesUI
        if OGRH.GetRolePlayers then
          local ranged = OGRH.GetRolePlayers("RANGED")
          for i = 1, table.getn(ranged) do
            if not poolLookup[ranged[i]] then
              table.insert(availablePlayers, ranged[i])
            end
          end
        end
      elseif frame.selectedSource == "default_tanks" and OGRH_SV.poolDefaults and OGRH_SV.poolDefaults[1] then
        for i = 1, table.getn(OGRH_SV.poolDefaults[1]) do
          if not poolLookup[OGRH_SV.poolDefaults[1][i]] then
            table.insert(availablePlayers, OGRH_SV.poolDefaults[1][i])
          end
        end
      elseif frame.selectedSource == "default_healers" and OGRH_SV.poolDefaults and OGRH_SV.poolDefaults[2] then
        for i = 1, table.getn(OGRH_SV.poolDefaults[2]) do
          if not poolLookup[OGRH_SV.poolDefaults[2][i]] then
            table.insert(availablePlayers, OGRH_SV.poolDefaults[2][i])
          end
        end
      elseif frame.selectedSource == "default_melee" and OGRH_SV.poolDefaults and OGRH_SV.poolDefaults[3] then
        for i = 1, table.getn(OGRH_SV.poolDefaults[3]) do
          if not poolLookup[OGRH_SV.poolDefaults[3][i]] then
            table.insert(availablePlayers, OGRH_SV.poolDefaults[3][i])
          end
        end
      elseif frame.selectedSource == "default_ranged" and OGRH_SV.poolDefaults and OGRH_SV.poolDefaults[4] then
        for i = 1, table.getn(OGRH_SV.poolDefaults[4]) do
          if not poolLookup[OGRH_SV.poolDefaults[4][i]] then
            table.insert(availablePlayers, OGRH_SV.poolDefaults[4][i])
          end
        end
      end
      
      -- Sort alphabetically
      table.sort(availablePlayers)
      
      -- Create player buttons
      local yOffset = 0
      for i, playerName in ipairs(availablePlayers) do
        local btn = CreateFrame("Button", nil, availScrollChild)
        btn:SetWidth(200)
        btn:SetHeight(18)
        btn:SetPoint("TOPLEFT", availScrollChild, "TOPLEFT", 0, -yOffset)
        
        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetTexture("Interface\\Buttons\\WHITE8X8")
        bg:SetVertexColor(0.2, 0.2, 0.2, 0.5)
        
        local text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        text:SetPoint("LEFT", btn, "LEFT", 5, 0)
        
        -- Apply class color
        local displayName = playerName
        if OGRH.ClassColorHex and OGRH.Roles and OGRH.Roles.nameClass and OGRH.Roles.nameClass[playerName] then
          local class = OGRH.Roles.nameClass[playerName]
          displayName = OGRH.ClassColorHex(class) .. playerName .. "|r"
        end
        text:SetText(displayName)
        
        -- Click to add to pool
        local capturedName = playerName
        btn:SetScript("OnClick", function()
          table.insert(pool, capturedName)
          frame.RefreshAvailableList()
          frame.RefreshPoolList()
        end)
        
        yOffset = yOffset + 20
      end
      
      availScrollChild:SetHeight(math.max(1, yOffset))
      frame.updateAvailScrollBar()
    end
    
    -- Function to refresh pool list
    frame.RefreshPoolList = function()
      -- Clear existing buttons
      local children = {poolScrollChild:GetChildren()}
      for i = 1, table.getn(children) do
        if children[i] then
          children[i]:Hide()
          children[i]:SetParent(nil)
        end
      end
      
      -- Get pool data
      if not OGRH_SV.encounterPools then
        OGRH_SV.encounterPools = {}
      end
      if not OGRH_SV.encounterPools[frame.currentRaid] then
        OGRH_SV.encounterPools[frame.currentRaid] = {}
      end
      if not OGRH_SV.encounterPools[frame.currentRaid][frame.currentEncounter] then
        OGRH_SV.encounterPools[frame.currentRaid][frame.currentEncounter] = {}
      end
      if not OGRH_SV.encounterPools[frame.currentRaid][frame.currentEncounter][frame.currentRoleIndex] then
        OGRH_SV.encounterPools[frame.currentRaid][frame.currentEncounter][frame.currentRoleIndex] = {}
      end
      
      local pool = OGRH_SV.encounterPools[frame.currentRaid][frame.currentEncounter][frame.currentRoleIndex]
      
      -- Don't sort - maintain manual order for priority
      
      -- Create player buttons
      local yOffset = 0
      for i, playerName in ipairs(pool) do
        local playerFrame = CreateFrame("Frame", nil, poolScrollChild)
        playerFrame:SetWidth(220)
        playerFrame:SetHeight(20)
        playerFrame:SetPoint("TOPLEFT", poolScrollChild, "TOPLEFT", 0, -yOffset)
        
        local bg = playerFrame:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetTexture("Interface\\Buttons\\WHITE8X8")
        bg:SetVertexColor(0.15, 0.15, 0.15, 0.8)
        
        -- Up button
        local upBtn = CreateFrame("Button", nil, playerFrame)
        upBtn:SetWidth(16)
        upBtn:SetHeight(16)
        upBtn:SetPoint("LEFT", playerFrame, "LEFT", 2, 0)
        upBtn:SetNormalTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Up")
        upBtn:SetPushedTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Down")
        upBtn:SetHighlightTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Highlight")
        
        local currentIndex = i
        upBtn:SetScript("OnClick", function()
          if currentIndex > 1 then
            local temp = pool[currentIndex]
            pool[currentIndex] = pool[currentIndex - 1]
            pool[currentIndex - 1] = temp
            frame.RefreshPoolList()
          end
        end)
        
        -- Down button
        local downBtn = CreateFrame("Button", nil, playerFrame)
        downBtn:SetWidth(16)
        downBtn:SetHeight(16)
        downBtn:SetPoint("LEFT", upBtn, "RIGHT", 0, 0)
        downBtn:SetNormalTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up")
        downBtn:SetPushedTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Down")
        downBtn:SetHighlightTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Highlight")
        
        downBtn:SetScript("OnClick", function()
          if currentIndex < table.getn(pool) then
            local temp = pool[currentIndex]
            pool[currentIndex] = pool[currentIndex + 1]
            pool[currentIndex + 1] = temp
            frame.RefreshPoolList()
          end
        end)
        
        -- Remove button
        local removeBtn = CreateFrame("Button", nil, playerFrame, "UIPanelButtonTemplate")
        removeBtn:SetWidth(16)
        removeBtn:SetHeight(16)
        removeBtn:SetPoint("LEFT", downBtn, "RIGHT", 2, 0)
        removeBtn:SetText("X")
        
        removeBtn:SetScript("OnClick", function()
          table.remove(pool, currentIndex)
          frame.RefreshAvailableList()
          frame.RefreshPoolList()
        end)
        
        -- Player name with class color
        local nameText = playerFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        nameText:SetPoint("LEFT", removeBtn, "RIGHT", 5, 0)
        
        if OGRH.ClassColorHex and OGRH.Roles and OGRH.Roles.nameClass then
          local class = OGRH.Roles.nameClass[playerName]
          if class then
            nameText:SetText(OGRH.ClassColorHex(class) .. playerName .. "|r")
          else
            nameText:SetText(playerName)
          end
        else
          nameText:SetText(playerName)
        end
        
        yOffset = yOffset + 22
      end
      
      poolScrollChild:SetHeight(math.max(1, yOffset))
      frame.updatePoolScrollBar()
    end
    
    OGRH_EncounterPoolFrame = frame
  end
  
  local frame = OGRH_EncounterPoolFrame
  
  -- Store current context
  frame.currentRaid = raidName
  frame.currentEncounter = encounterName
  frame.currentRole = role
  frame.currentRoleIndex = roleIndex
  
  -- Update title
  frame.title:SetText("Player Pool - " .. (role.name or "Unknown"))
  
  -- Reset to default source (Tanks role)
  frame.selectedSource = "role_tanks"
  frame.sourceDropdown:SetText("Tanks")
  
  -- Refresh guild roster to update class colors
  GuildRoster()
  
  -- Show the window and refresh lists
  frame:Show()
  frame.RefreshAvailableList()
  frame.RefreshPoolList()
  
  DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00OGRH:|r Encounter pool window opened")
end

-- Initialize SavedVariables when addon loads
InitializeSavedVars()

DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OGRH:|r Encounter Management loaded")
