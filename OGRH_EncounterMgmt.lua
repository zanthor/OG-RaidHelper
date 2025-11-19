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

-- Get currently selected encounter (for sync from MainUI)
function OGRH.GetCurrentEncounter()
  -- Check frame first
  if OGRH_EncounterFrame and OGRH_EncounterFrame.selectedRaid and OGRH_EncounterFrame.selectedEncounter then
    return OGRH_EncounterFrame.selectedRaid, OGRH_EncounterFrame.selectedEncounter
  end
  
  -- Fall back to saved variables
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
          OGRH_SV.ui.selectedRaid = capturedRaidName
          
          -- Select first encounter if available
          local firstEncounter = nil
          if OGRH_SV.encounterMgmt.encounters and 
             OGRH_SV.encounterMgmt.encounters[capturedRaidName] and
             table.getn(OGRH_SV.encounterMgmt.encounters[capturedRaidName]) > 0 then
            firstEncounter = OGRH_SV.encounterMgmt.encounters[capturedRaidName][1]
            frame.selectedEncounter = firstEncounter
            OGRH_SV.ui.selectedEncounter = firstEncounter
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
          if OGRH.UpdateEncounterNavButton then
            OGRH.UpdateEncounterNavButton()
          end
          
          -- Broadcast encounter change
          if firstEncounter and OGRH.BroadcastEncounterSelection then
            OGRH.BroadcastEncounterSelection(capturedRaidName, firstEncounter)
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
      local selectedIndex = nil
      
      for i, encounterName in ipairs(encounters) do
        if encounterName == frame.selectedEncounter then
          selectedIndex = i
        end
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
          OGRH_SV.ui.selectedEncounter = capturedEncounterName
          RefreshEncountersList()
          if frame.RefreshRoleContainers then
            frame.RefreshRoleContainers()
          end
          if frame.RefreshPlayersList then
            frame.RefreshPlayersList()
          end
          if OGRH.UpdateEncounterNavButton then
            OGRH.UpdateEncounterNavButton()
          end
          
          -- Update consume monitor if enabled
          if OGRH.ShowConsumeMonitor then
            OGRH.ShowConsumeMonitor()
          end
          
          -- Broadcast encounter change
          if frame.selectedRaid and OGRH.BroadcastEncounterSelection then
            OGRH.BroadcastEncounterSelection(frame.selectedRaid, capturedEncounterName)
          end
        end)
        
        table.insert(frame.encounterButtons, encounterBtn)
        yOffset = yOffset - 22
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
        {text = "Ranged", value = "ranged", label = "Ranged"}
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
    
    -- Guild list frame
    local guildListFrame = CreateFrame("Frame", nil, playersPanel)
    guildListFrame:SetPoint("TOP", searchBox, "BOTTOM", 0, -5)
    guildListFrame:SetWidth(180)
    guildListFrame:SetHeight(280)
    guildListFrame:SetBackdrop({
      bgFile = "Interface/Tooltips/UI-Tooltip-Background",
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
      tile = true,
      tileSize = 16,
      edgeSize = 12,
      insets = {left = 3, right = 3, top = 3, bottom = 3}
    })
    guildListFrame:SetBackdropColor(0.15, 0.15, 0.15, 0.9)
    
    -- Create scroll frame for guild list
    local guildScrollFrame = CreateFrame("ScrollFrame", nil, guildListFrame)
    guildScrollFrame:SetPoint("TOPLEFT", guildListFrame, "TOPLEFT", 5, -5)
    guildScrollFrame:SetPoint("BOTTOMRIGHT", guildListFrame, "BOTTOMRIGHT", -25, 5)
    
    local guildScrollChild = CreateFrame("Frame", nil, guildScrollFrame)
    guildScrollChild:SetWidth(155)
    guildScrollChild:SetHeight(1)
    guildScrollFrame:SetScrollChild(guildScrollChild)
    frame.guildScrollChild = guildScrollChild
    frame.guildScrollFrame = guildScrollFrame
    
    -- Create scrollbar for player list
    local guildScrollBar = CreateFrame("Slider", nil, guildListFrame)
    guildScrollBar:SetPoint("TOPRIGHT", guildListFrame, "TOPRIGHT", -5, -16)
    guildScrollBar:SetPoint("BOTTOMRIGHT", guildListFrame, "BOTTOMRIGHT", -5, 16)
    guildScrollBar:SetWidth(16)
    guildScrollBar:SetBackdrop({
      bgFile = "Interface/Tooltips/UI-Tooltip-Background",
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 8,
      insets = {left = 3, right = 3, top = 3, bottom = 3}
    })
    guildScrollBar:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
    guildScrollBar:SetOrientation("VERTICAL")
    guildScrollBar:SetMinMaxValues(0, 1)
    guildScrollBar:SetValue(0)
    guildScrollBar:SetValueStep(22)
    frame.guildScrollBar = guildScrollBar
    
    guildScrollBar:SetScript("OnValueChanged", function()
      guildScrollFrame:SetVerticalScroll(this:GetValue())
    end)
    
    -- Enable mouse wheel scrolling for guild list
    guildScrollFrame:EnableMouseWheel(true)
    guildScrollFrame:SetScript("OnMouseWheel", function()
      local delta = arg1
      local current = guildScrollBar:GetValue()
      local minVal, maxVal = guildScrollBar:GetMinMaxValues()
      
      if delta > 0 then
        guildScrollBar:SetValue(math.max(minVal, current - 22))
      else
        guildScrollBar:SetValue(math.min(maxVal, current + 22))
      end
    end)
    
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
    
    -- Auto Assign functionality
    autoAssignBtn:SetScript("OnClick", function()
      local button = arg1 or "LeftButton"
      
      -- Right-click: Clear all encounter data
      if button == "RightButton" then
        if not frame.selectedRaid or not frame.selectedEncounter then
          DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OGRH:|r Please select a raid and encounter first.")
          return
        end
        
        -- Create confirmation dialog
        StaticPopupDialogs["OGRH_CLEAR_ENCOUNTER"] = {
          text = "Clear all assignments, marks, and announcement text for this encounter?",
          button1 = "OK",
          button2 = "Cancel",
          OnAccept = function()
            -- Clear assignments
            if OGRH_SV.encounterAssignments and OGRH_SV.encounterAssignments[frame.selectedRaid] then
              OGRH_SV.encounterAssignments[frame.selectedRaid][frame.selectedEncounter] = {}
            end
            
            -- Clear raid marks
            if OGRH_SV.encounterRaidMarks and OGRH_SV.encounterRaidMarks[frame.selectedRaid] then
              OGRH_SV.encounterRaidMarks[frame.selectedRaid][frame.selectedEncounter] = {}
            end
            
            -- Clear assignment numbers
            if OGRH_SV.encounterAssignmentNumbers and OGRH_SV.encounterAssignmentNumbers[frame.selectedRaid] then
              OGRH_SV.encounterAssignmentNumbers[frame.selectedRaid][frame.selectedEncounter] = {}
            end
            
            -- Broadcast full sync to update other clients
            if OGRH.BroadcastFullSync then
              OGRH.BroadcastFullSync(frame.selectedRaid, frame.selectedEncounter)
            end
            
            -- Refresh display
            if frame.RefreshRoleContainers then
              frame.RefreshRoleContainers()
            end
            
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OGRH:|r Encounter data cleared.")
          end,
          timeout = 0,
          whileDead = true,
          hideOnEscape = true,
        }
        StaticPopup_Show("OGRH_CLEAR_ENCOUNTER")
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
        table.insert(allRoles, {role = column1[i], roleIndex = table.getn(allRoles) + 1})
      end
      
      -- Then add all roles from column2 (top to bottom)
      for i = 1, table.getn(column2) do
        table.insert(allRoles, {role = column2[i], roleIndex = table.getn(allRoles) + 1})
      end
      
      -- Track assigned players
      local assignedPlayers = {}  -- playerName -> true (already assigned)
      local roleAssignments = {}  -- roleIndex -> {slotIndex -> playerName}
      local assignmentCount = 0
      
      -- Process each role in order
      for _, roleData in ipairs(allRoles) do
        local role = roleData.role
        local roleIndex = roleData.roleIndex
        local maxSlots = role.slots or 1
        
        if not roleAssignments[roleIndex] then
          roleAssignments[roleIndex] = {}
        end
        
        -- Get available players for this role based on defaultRoles
        local availablePlayers = {}
        
        -- Build list of current raid members
        local raidMembers = {}
        local numRaidMembers = GetNumRaidMembers()
        if numRaidMembers > 0 then
          for i = 1, numRaidMembers do
            local name = GetRaidRosterInfo(i)
            if name then
              raidMembers[name] = true
            end
          end
        end
        
        if role.defaultRoles then
          -- Get all players from RolesUI who match the defaultRoles
          if OGRH_SV.roles then
            for playerName, playerRole in pairs(OGRH_SV.roles) do
              -- Check if player is in the raid
              if raidMembers[playerName] then
                -- Check if player's role matches any enabled defaultRole
                local matches = false
                
                if playerRole == "TANKS" and role.defaultRoles.tanks then
                  matches = true
                elseif playerRole == "HEALERS" and role.defaultRoles.healers then
                  matches = true
                elseif playerRole == "MELEE" and role.defaultRoles.melee then
                  matches = true
                elseif playerRole == "RANGED" and role.defaultRoles.ranged then
                  matches = true
                end
                
                if matches then
                  -- Check if player is already assigned (unless allowOtherRoles is true)
                  if not assignedPlayers[playerName] or role.allowOtherRoles then
                    table.insert(availablePlayers, playerName)
                  end
                end
              end
            end
          end
        end
        
        -- Assign players to slots
        local slotIndex = 1
        for i = 1, table.getn(availablePlayers) do
          if slotIndex > maxSlots then
            break
          end
          
          local playerName = availablePlayers[i]
          
          -- Check if we can assign this player
          local canAssign = true
          if assignedPlayers[playerName] and not role.allowOtherRoles then
            canAssign = false
          end
          
          if canAssign then
            roleAssignments[roleIndex][slotIndex] = playerName
            assignedPlayers[playerName] = true
            assignmentCount = assignmentCount + 1
            slotIndex = slotIndex + 1
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
      frame.editMode = enabled
      
      if enabled then
        editToggleBtn:SetText("|cff00ff00Edit: Unlocked|r")
      else
        editToggleBtn:SetText("|cffff0000Edit: Locked|r")
      end
      
      -- Enable/disable announcement EditBoxes
      if frame.announcementLines then
        for i = 1, table.getn(frame.announcementLines) do
          frame.announcementLines[i]:EnableKeyboard(enabled)
          frame.announcementLines[i]:EnableMouse(enabled)
          if not enabled then
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
            end
          end
        end
      end
    end
    
    frame.SetEditMode = SetEditMode
    
    -- Toggle edit mode on click
    editToggleBtn:SetScript("OnClick", function()
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
      
      -- Build player list: raid members, online 60s, offline 60s
      local raidPlayers = {}  -- {name=..., class=..., section="raid"}
      local onlinePlayers = {}  -- {name=..., class=..., section="online"}
      local offlinePlayers = {}  -- {name=..., class=..., section="offline"}
      
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
      
      -- Sort each section alphabetically
      table.sort(raidPlayers, function(a, b) return a.name < b.name end)
      table.sort(onlinePlayers, function(a, b) return a.name < b.name end)
      table.sort(offlinePlayers, function(a, b) return a.name < b.name end)
      
      -- Combine all sections
      local players = {}
      for _, p in ipairs(raidPlayers) do
        table.insert(players, p)
      end
      for _, p in ipairs(onlinePlayers) do
        table.insert(players, p)
      end
      for _, p in ipairs(offlinePlayers) do
        table.insert(players, p)
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
        
        local playerBtn = CreateFrame("Button", nil, scrollChild)
        playerBtn:SetWidth(170)
        playerBtn:SetHeight(20)
        playerBtn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 2, -yOffset)
        
        -- Background
        local bg = playerBtn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetTexture("Interface\\Buttons\\WHITE8X8")
        bg:SetVertexColor(0.2, 0.2, 0.2, 0.8)
        playerBtn.bg = bg
        
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
        
        -- Highlight on hover
        playerBtn:SetScript("OnEnter", function()
          bg:SetVertexColor(0.3, 0.3, 0.4, 0.9)
        end)
        
        playerBtn:SetScript("OnLeave", function()
          bg:SetVertexColor(0.2, 0.2, 0.2, 0.8)
        end)
        
        yOffset = yOffset + 22
      end
      
      -- Update scroll child height
      scrollChild:SetHeight(math.max(yOffset, 1))
      
      -- Update scrollbar range
      local scrollBar = frame.guildScrollBar
      if scrollBar then
        local maxScroll = scrollChild:GetHeight() - frame.guildScrollFrame:GetHeight()
        if maxScroll < 0 then maxScroll = 0 end
        scrollBar:SetMinMaxValues(0, maxScroll)
        scrollBar:SetValue(0)
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
            
            -- Start with mouse disabled (read-only mode)
            assignBtn:EnableMouse(false)
            
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
          -- If assignment button exists, stop before it; otherwise cover full width
          if role.showAssignment then
            dragBtn:SetPoint("RIGHT", slot.assignTag, "LEFT", -2, 0)
          else
            dragBtn:SetPoint("RIGHT", slot, "RIGHT", -5, 0)
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
            -- Left click: Do nothing (removed player selection dialog)
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
              slot.nameText:SetText("[Empty]")
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
      
      -- Add existing encounters for selected raid
      local encounters = OGRH_SV.encounterMgmt.encounters[frame.selectedRaid]
      for i, encounterName in ipairs(encounters) do
        if encounterName == frame.selectedEncounter then
          selectedIndex = i
        end
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
      local scrollBar = frame.encountersScrollBar
      local scrollFrameHeight = scrollFrame:GetHeight()
      
      if contentHeight > scrollFrameHeight then
        scrollBar:Show()
        scrollBar:SetMinMaxValues(0, contentHeight - scrollFrameHeight)
        
        -- Restore or adjust scroll position to keep selected item visible
        if selectedIndex then
          local buttonHeight = 22
          local visibleHeight = scrollFrameHeight
          local buttonTop = (selectedIndex - 1) * buttonHeight
          local buttonBottom = buttonTop + buttonHeight
          local scrollBottom = savedScroll + visibleHeight
          
          -- If selected button is above visible area, scroll up to it
          if buttonTop < savedScroll then
            scrollBar:SetValue(buttonTop)
            scrollFrame:SetVerticalScroll(buttonTop)
          -- If selected button is below visible area, scroll down to it
          elseif buttonBottom > scrollBottom then
            local newScroll = buttonBottom - visibleHeight
            scrollBar:SetValue(newScroll)
            scrollFrame:SetVerticalScroll(newScroll)
          else
            -- Selected item is visible, restore saved scroll position
            scrollBar:SetValue(savedScroll)
            scrollFrame:SetVerticalScroll(savedScroll)
          end
        else
          -- No selected item, restore saved scroll position
          scrollBar:SetValue(savedScroll)
          scrollFrame:SetVerticalScroll(savedScroll)
        end
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
    
    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", frame, "TOP", 0, -10)
    title:SetText("Edit Role")
    
    -- Consume Check Checkbox
    local consumeCheckLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    consumeCheckLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, -40)
    consumeCheckLabel:SetText("Consume Check:")
    frame.consumeCheckLabel = consumeCheckLabel
    
    local consumeCheckbox = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    consumeCheckbox:SetPoint("LEFT", consumeCheckLabel, "RIGHT", 5, 0)
    consumeCheckbox:SetWidth(24)
    consumeCheckbox:SetHeight(24)
    frame.consumeCheckbox = consumeCheckbox
    
    -- Role Name Label
    local nameLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameLabel:SetPoint("TOPLEFT", consumeCheckLabel, "BOTTOMLEFT", 0, -10)
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
    
    local healersCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    healersCheck:SetPoint("TOPLEFT", tanksCheck, "BOTTOMLEFT", 0, -5)
    healersCheck:SetWidth(24)
    healersCheck:SetHeight(24)
    local healersLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    healersLabel:SetPoint("LEFT", healersCheck, "RIGHT", 5, 0)
    healersLabel:SetText("Healers")
    frame.healersCheck = healersCheck
    
    local meleeCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    meleeCheck:SetPoint("TOPLEFT", healersCheck, "BOTTOMLEFT", 0, -5)
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
    
    frame.defaultRoleChecks = {tanksCheck, healersCheck, meleeCheck, rangedCheck}
    
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
  
  -- Function to update visibility based on consume check
  local function UpdateConsumeCheckVisibility()
    local isConsumeCheck = frame.consumeCheckbox:GetChecked()
    
    -- Hide/show elements based on consume check
    if isConsumeCheck then
      -- Set name to "Consumes" and hide name controls
      frame.nameEditBox:SetText("Consumes")
      frame.nameLabel:Hide()
      frame.nameEditBox:Hide()
      
      -- Hide standard role options
      frame.raidIconsLabel:Hide()
      frame.raidIconsCheckbox:Hide()
      frame.showAssignmentLabel:Hide()
      frame.showAssignmentCheckbox:Hide()
      frame.markPlayerLabel:Hide()
      frame.markPlayerCheckbox:Hide()
      frame.allowOtherRolesLabel:Hide()
      frame.allowOtherRolesCheckbox:Hide()
      
      -- Reanchor count label to consume checkbox (since other labels are hidden)
      frame.countLabel:ClearAllPoints()
      frame.countLabel:SetPoint("TOPLEFT", frame.consumeCheckLabel, "BOTTOMLEFT", 0, -15)
      frame.countLabel:SetText("Consume Count:")
      
      -- Change label to Classes and show class checkboxes
      frame.rolesLabel:SetText("Classes:")
      for _, check in ipairs(frame.defaultRoleChecks) do
        check:Hide()
      end
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
      
      -- Resize dialog to fit (smaller height)
      frame:SetHeight(280)
    else
      -- Show name controls
      frame.nameLabel:Show()
      frame.nameEditBox:Show()
      
      -- Show standard role options
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
      
      -- Change label to Default Role and show default role checkboxes
      frame.rolesLabel:SetText("Default Role:")
      for _, check in ipairs(frame.defaultRoleChecks) do
        check:Show()
      end
      frame.allCheck:Hide()
      frame.allLabel:Hide()
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
      
      -- Resize dialog back to full height
      frame:SetHeight(380)
    end
  end
  
  -- Set consume checkbox click handler
  frame.consumeCheckbox:SetScript("OnClick", function()
    UpdateConsumeCheckVisibility()
  end)
  
  -- Check if another role is already a consume check (only allow one)
  local hasConsumeCheck = false
  for i, role in ipairs(columnRoles) do
    if i ~= roleIndex and role.isConsumeCheck then
      hasConsumeCheck = true
      break
    end
  end
  
  -- Populate fields with current role data
  frame.consumeCheckbox:SetChecked(roleData.isConsumeCheck or false)
  
  -- Hide consume check option entirely if another consume check already exists
  if hasConsumeCheck and not roleData.isConsumeCheck then
    frame.consumeCheckLabel:Hide()
    frame.consumeCheckbox:Hide()
  else
    frame.consumeCheckLabel:Show()
    frame.consumeCheckbox:Show()
    frame.consumeCheckbox:Enable()
  end
  
  frame.nameEditBox:SetText(roleData.name or "")
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
  
  -- Trigger initial visibility update (this will show/hide appropriate checkboxes)
  UpdateConsumeCheckVisibility()
  
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
    local isConsumeCheck = frame.consumeCheckbox:GetChecked()
    if isConsumeCheck then
      for i, role in ipairs(columnRoles) do
        if i ~= roleIndex and role.isConsumeCheck then
          DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OGRH:|r Only one Consume Check role allowed per encounter.")
          return
        end
      end
    end
    
    -- Update role data
    roleData.name = frame.nameEditBox:GetText()
    roleData.isConsumeCheck = isConsumeCheck
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
  
  -- Get raid and encounter from frame if it exists, otherwise from saved variables
  local raidName, encounterName
  if OGRH_EncounterFrame then
    raidName = OGRH_EncounterFrame.selectedRaid
    encounterName = OGRH_EncounterFrame.selectedEncounter
  elseif OGRH_SV and OGRH_SV.ui then
    raidName = OGRH_SV.ui.selectedRaid
    encounterName = OGRH_SV.ui.selectedEncounter
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
  -- Get current encounter from frame or saved variables
  local raidName, currentEncounter = OGRH.GetCurrentEncounter()
  
  if not raidName or not currentEncounter then
    return
  end
  
  if OGRH_SV.encounterMgmt and OGRH_SV.encounterMgmt.encounters and 
     OGRH_SV.encounterMgmt.encounters[raidName] then
    local encounters = OGRH_SV.encounterMgmt.encounters[raidName]
    
    for i = 1, table.getn(encounters) do
      if encounters[i] == currentEncounter and i > 1 then
        -- Update saved variables
        OGRH_SV.ui.selectedEncounter = encounters[i - 1]
        
        -- Update frame if it exists
        if OGRH_EncounterFrame then
          OGRH_EncounterFrame.selectedEncounter = encounters[i - 1]
          if OGRH_EncounterFrame.RefreshEncountersList then
            OGRH_EncounterFrame.RefreshEncountersList()
          end
          if OGRH_EncounterFrame.RefreshRoleContainers then
            OGRH_EncounterFrame.RefreshRoleContainers()
          end
        end
        
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
  -- Get current encounter from frame or saved variables
  local raidName, currentEncounter = OGRH.GetCurrentEncounter()
  
  if not raidName or not currentEncounter then
    return
  end
  
  if OGRH_SV.encounterMgmt and OGRH_SV.encounterMgmt.encounters and 
     OGRH_SV.encounterMgmt.encounters[raidName] then
    local encounters = OGRH_SV.encounterMgmt.encounters[raidName]
    
    for i = 1, table.getn(encounters) do
      if encounters[i] == currentEncounter and i < table.getn(encounters) then
        -- Update saved variables
        OGRH_SV.ui.selectedEncounter = encounters[i + 1]
        
        -- Update frame if it exists
        if OGRH_EncounterFrame then
          OGRH_EncounterFrame.selectedEncounter = encounters[i + 1]
          if OGRH_EncounterFrame.RefreshEncountersList then
            OGRH_EncounterFrame.RefreshEncountersList()
          end
          if OGRH_EncounterFrame.RefreshRoleContainers then
            OGRH_EncounterFrame.RefreshRoleContainers()
          end
        end
        
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
  
  if not OGRH_EncounterFrame then
    OGRH.ShowEncounterWindow()
    return
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
          
          -- Check if window is currently open
          local wasOpen = OGRH_EncounterFrame and OGRH_EncounterFrame:IsVisible()
          
          -- Only create/show window if it was already open
          if wasOpen then
            -- Select this raid
            OGRH_EncounterFrame.selectedRaid = capturedRaid
            
            -- Select first encounter if available
            local firstEncounter = nil
            if OGRH_SV.encounterMgmt.encounters and 
               OGRH_SV.encounterMgmt.encounters[capturedRaid] and
               table.getn(OGRH_SV.encounterMgmt.encounters[capturedRaid]) > 0 then
              firstEncounter = OGRH_SV.encounterMgmt.encounters[capturedRaid][1]
              OGRH_EncounterFrame.selectedEncounter = firstEncounter
            end
            
            -- Refresh the window
            if OGRH_EncounterFrame.RefreshRaidsList then
              OGRH_EncounterFrame.RefreshRaidsList()
            end
            if OGRH_EncounterFrame.RefreshEncountersList then
              OGRH_EncounterFrame.RefreshEncountersList()
            end
            if OGRH_EncounterFrame.RefreshRoleContainers then
              OGRH_EncounterFrame.RefreshRoleContainers()
            end
            
            -- Broadcast encounter change
            if firstEncounter then
              OGRH.BroadcastEncounterSelection(capturedRaid, firstEncounter)
            end
          else
            -- Window not open, create frame but keep it hidden
            if not OGRH_EncounterFrame then
              OGRH.ShowEncounterWindow()
              OGRH_EncounterFrame:Hide()
            end
            
            -- Select this raid
            OGRH_EncounterFrame.selectedRaid = capturedRaid
            
            -- Select first encounter if available
            local firstEncounter = nil
            if OGRH_SV.encounterMgmt.encounters and 
               OGRH_SV.encounterMgmt.encounters[capturedRaid] and
               table.getn(OGRH_SV.encounterMgmt.encounters[capturedRaid]) > 0 then
              firstEncounter = OGRH_SV.encounterMgmt.encounters[capturedRaid][1]
              OGRH_EncounterFrame.selectedEncounter = firstEncounter
            end
            
            -- Update saved variables for next time
            OGRH.EnsureSV()
            OGRH_SV.lastSelectedRaid = capturedRaid
            if firstEncounter then
              OGRH_SV.lastSelectedEncounter = firstEncounter
            end
            
            -- Broadcast encounter change
            if firstEncounter then
              OGRH.BroadcastEncounterSelection(capturedRaid, firstEncounter)
            end
          end
          
          OGRH.UpdateEncounterNavButton()
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
