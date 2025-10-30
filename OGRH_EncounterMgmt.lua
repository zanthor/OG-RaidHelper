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
          frame.selectedRaid = capturedRaidName
          RefreshRaidsList()
          if frame.RefreshEncountersList then
            frame.RefreshEncountersList()
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
    
    -- Right panel: Role assignment area
    local rightPanel = CreateFrame("Frame", nil, frame)
    rightPanel:SetWidth(595)
    rightPanel:SetHeight(390)
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
    
    -- Placeholder text when no encounter selected
    local placeholderText = rightPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    placeholderText:SetPoint("CENTER", rightPanel, "CENTER", 0, 0)
    placeholderText:SetText("|cff888888Select a raid and encounter|r")
    frame.placeholderText = placeholderText
    
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
      
      -- Show/hide placeholder
      if not frame.selectedRaid or not frame.selectedEncounter then
        placeholderText:Show()
        return
      end
      
      placeholderText:Hide()
      
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
        titleText:SetPoint("TOP", container, "TOP", 0, -10)
        titleText:SetText(role.name or "Unknown Role")
        
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
          
          -- Background
          local bg = slot:CreateTexture(nil, "BACKGROUND")
          bg:SetAllPoints()
          bg:SetTexture("Interface\\Buttons\\WHITE8X8")
          bg:SetVertexColor(0.1, 0.1, 0.1, 0.8)
          
          -- Raid icon dropdown button - only if showRaidIcons is true
          if role.showRaidIcons then
            local iconBtn = CreateFrame("Button", nil, slot)
            iconBtn:SetWidth(16)
            iconBtn:SetHeight(16)
            iconBtn:SetPoint("LEFT", slot, "LEFT", 5, 0)
            
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
            
            -- Click to cycle through raid icons
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
            
            slot.iconBtn = iconBtn
          end
          
          -- Player name text
          local nameText = slot:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
          if role.showRaidIcons then
            nameText:SetPoint("LEFT", slot.iconBtn, "RIGHT", 5, 0)
          else
            nameText:SetPoint("LEFT", slot, "LEFT", 5, 0)
          end
          nameText:SetText("|cff888888[Empty]|r")
          slot.nameText = nameText
          
          table.insert(container.slots, slot)
        end
        
        return container
      end
      
      -- Create role containers from both columns
      local yOffset = -10
      local columnWidth = 282
      
      -- Interleave columns in 2-column layout
      local maxRoles = math.max(table.getn(column1), table.getn(column2))
      local roleIndex = 1
      
      for i = 1, maxRoles do
        -- Left column role
        if column1[i] then
          local container = CreateRoleContainer(rightPanel, column1[i], roleIndex, 10, yOffset, columnWidth)
          table.insert(frame.roleContainers, container)
          roleIndex = roleIndex + 1
        end
        
        -- Right column role
        if column2[i] then
          local container = CreateRoleContainer(rightPanel, column2[i], roleIndex, 302, yOffset, columnWidth)
          table.insert(frame.roleContainers, container)
          roleIndex = roleIndex + 1
        end
        
        -- Calculate offset for next row based on tallest container in this row
        local leftHeight = column1[i] and (40 + ((column1[i].slots or 1) * 22)) or 0
        local rightHeight = column2[i] and (40 + ((column2[i].slots or 1) * 22)) or 0
        yOffset = yOffset - math.max(leftHeight, rightHeight) - 10
      end
    end
    
    frame.RefreshRoleContainers = RefreshRoleContainers
    
    -- Initialize lists
    RefreshRaidsList()
  end
  
  -- Show the frame
  OGRH_BWLEncounterFrame:Show()
  
  -- Refresh the raids list (this will validate and clear selectedRaid/selectedEncounter if needed)
  OGRH_BWLEncounterFrame.RefreshRaidsList()
  
  -- Refresh the encounters list (this will validate and clear selectedEncounter if needed)
  if OGRH_BWLEncounterFrame.RefreshEncountersList then
    OGRH_BWLEncounterFrame.RefreshEncountersList()
  end
  
  -- If an encounter is still selected after validation, refresh the role containers
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
        
        -- Click to select raid
        local capturedRaidName = raidName
        local capturedIndex = i
        raidBtn:SetScript("OnClick", function()
          frame.selectedRaid = capturedRaidName
          RefreshRaidsList()
          if frame.RefreshEncountersList then
            frame.RefreshEncountersList()
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
        
        -- Click to select encounter
        local capturedEncounterName = encounterName
        local capturedIndex = i
        local capturedRaid = frame.selectedRaid
        encounterBtn:SetScript("OnClick", function()
          frame.selectedEncounter = capturedEncounterName
          RefreshEncountersList()
          if frame.RefreshRolesList then
            frame.RefreshRolesList()
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
    
    -- Player Count Label
    local countLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    countLabel:SetPoint("TOPLEFT", raidIconsLabel, "BOTTOMLEFT", 0, -15)
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
    
    local rangedCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    rangedCheck:SetPoint("LEFT", tankCheck, "LEFT", 120, 0)
    rangedCheck:SetWidth(24)
    rangedCheck:SetHeight(24)
    local rangedLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    rangedLabel:SetPoint("LEFT", rangedCheck, "RIGHT", 5, 0)
    rangedLabel:SetText("Ranged")
    frame.rangedCheck = rangedCheck
    
    local dpsCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    dpsCheck:SetPoint("TOPLEFT", rangedCheck, "BOTTOMLEFT", 0, -5)
    dpsCheck:SetWidth(24)
    dpsCheck:SetHeight(24)
    local dpsLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dpsLabel:SetPoint("LEFT", dpsCheck, "RIGHT", 5, 0)
    dpsLabel:SetText("DPS")
    frame.dpsCheck = dpsCheck
    
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
  frame.countEditBox:SetText(tostring(roleData.slots or 1))
  
  -- Set default roles checkboxes
  local defaultRoles = roleData.defaultRoles or {}
  frame.tankCheck:SetChecked(defaultRoles.tanks or false)
  frame.healerCheck:SetChecked(defaultRoles.healers or false)
  frame.rangedCheck:SetChecked(defaultRoles.ranged or false)
  frame.dpsCheck:SetChecked(defaultRoles.dps or false)
  
  -- Save button handler
  frame.saveBtn:SetScript("OnClick", function()
    -- Update role data
    roleData.name = frame.nameEditBox:GetText()
    roleData.showRaidIcons = frame.raidIconsCheckbox:GetChecked()
    roleData.slots = tonumber(frame.countEditBox:GetText()) or 1
    
    -- Update default roles
    if not roleData.defaultRoles then
      roleData.defaultRoles = {}
    end
    roleData.defaultRoles.tanks = frame.tankCheck:GetChecked()
    roleData.defaultRoles.healers = frame.healerCheck:GetChecked()
    roleData.defaultRoles.ranged = frame.rangedCheck:GetChecked()
    roleData.defaultRoles.dps = frame.dpsCheck:GetChecked()
    
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
    
    -- Guild scroll frame
    local guildScrollFrame = CreateFrame("ScrollFrame", nil, leftPanel)
    guildScrollFrame:SetPoint("TOPLEFT", leftPanel, "TOPLEFT", 5, -30)
    guildScrollFrame:SetPoint("BOTTOMRIGHT", leftPanel, "BOTTOMRIGHT", -20, 5)
    
    local guildScrollChild = CreateFrame("Frame", nil, guildScrollFrame)
    guildScrollChild:SetWidth(195)
    guildScrollChild:SetHeight(1)
    guildScrollFrame:SetScrollChild(guildScrollChild)
    frame.guildScrollChild = guildScrollChild
    
    -- Guild scroll bar
    local guildScrollBar = CreateFrame("Slider", nil, leftPanel)
    guildScrollBar:SetOrientation("VERTICAL")
    guildScrollBar:SetPoint("TOPRIGHT", leftPanel, "TOPRIGHT", -5, -30)
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
        {name = "Ranged", classes = {"DRUID", "HUNTER", "SHAMAN", "MAGE", "WARLOCK"}}
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
              if online then
                table.insert(onlinePlayers, {name = name, class = upperClass})
              else
                table.insert(offlinePlayers, {name = name, class = upperClass})
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
    sourceDropdown:SetText("Current Raid")
    frame.sourceDropdown = sourceDropdown
    frame.selectedSource = "raid"
    
    sourceDropdown:SetScript("OnClick", function()
      if not frame.sourceMenu then
        local menu = CreateFrame("Frame", nil, frame)
        menu:SetWidth(180)
        menu:SetHeight(150)
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
          {text = "Current Raid", value = "raid"},
          {text = "Default: Tanks", value = "default_tanks"},
          {text = "Default: Healers", value = "default_healers"},
          {text = "Default: Melee", value = "default_melee"},
          {text = "Default: Ranged", value = "default_ranged"}
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
      
      if frame.selectedSource == "raid" then
        -- Get players from current raid
        if OGRH.GetRolePlayers and frame.currentRole.defaultRoles then
          local allPlayers = {}
          
          if frame.currentRole.defaultRoles.tanks then
            local tanks = OGRH.GetRolePlayers("TANKS")
            for i = 1, table.getn(tanks) do
              table.insert(allPlayers, tanks[i])
            end
          end
          
          if frame.currentRole.defaultRoles.healers then
            local healers = OGRH.GetRolePlayers("HEALERS")
            for i = 1, table.getn(healers) do
              table.insert(allPlayers, healers[i])
            end
          end
          
          if frame.currentRole.defaultRoles.ranged then
            local ranged = OGRH.GetRolePlayers("RANGED")
            for i = 1, table.getn(ranged) do
              table.insert(allPlayers, ranged[i])
            end
          end
          
          if frame.currentRole.defaultRoles.dps then
            local melee = OGRH.GetRolePlayers("MELEE")
            for i = 1, table.getn(melee) do
              table.insert(allPlayers, melee[i])
            end
          end
          
          -- Remove duplicates
          local seen = {}
          for i = 1, table.getn(allPlayers) do
            if not seen[allPlayers[i]] and not poolLookup[allPlayers[i]] then
              seen[allPlayers[i]] = true
              table.insert(availablePlayers, allPlayers[i])
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
  
  -- Reset to default source (current raid)
  frame.selectedSource = "raid"
  frame.sourceDropdown:SetText("Current Raid")
  
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
