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

-- Initialize SavedVariables structure
local function InitializeSavedVars()
  if not OGRH_SV.encounterMgmt then
    OGRH_SV.encounterMgmt = {
      raids = {},
      encounters = {}
    }
  end
end

-- Function to show BWL Encounter Management Window
function OGRH.ShowBWLEncounterWindow(encounterName)
  -- Create or show the window
  if not OGRH_BWLEncounterFrame then
    local frame = CreateFrame("Frame", "OGRH_BWLEncounterFrame", UIParent)
    frame:SetWidth(800)
    frame:SetHeight(450)  -- Adjusted to fit player selection panel (380) + title/close (50) + bottom margin (20)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
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
    title:SetText("BWL - Razorgore")
    frame.title = title
    
    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    closeBtn:SetWidth(60)
    closeBtn:SetHeight(24)
    closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -10)
    closeBtn:SetText("Close")
    closeBtn:SetScript("OnClick", function() frame:Hide() end)
    
    -- Left panel: Player selector
    local leftPanel = CreateFrame("Frame", nil, frame)
    leftPanel:SetWidth(175)  -- 50% of original 350
    leftPanel:SetHeight(380)  -- Height for selector button + 15 players (24 + 10 + 15*22 + margins)
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
    
    -- Role selector dropdown button
    local selectedRole = "Tanks"
    
    local roleSelectorBtn = CreateFrame("Button", nil, leftPanel, "UIPanelButtonTemplate")
    roleSelectorBtn:SetWidth(155)  -- 50% of original 330, adjusted for panel width
    roleSelectorBtn:SetHeight(24)
    roleSelectorBtn:SetPoint("TOP", leftPanel, "TOP", 0, -10)
    roleSelectorBtn:SetText("Select Role: " .. selectedRole)
    
    -- Create role menu
    local roleMenu = CreateFrame("Frame", nil, UIParent)
    roleMenu:SetWidth(155)  -- Match button width
    roleMenu:SetHeight(100)
    roleMenu:SetFrameStrata("FULLSCREEN_DIALOG")
    roleMenu:SetBackdrop({
      bgFile = "Interface/Tooltips/UI-Tooltip-Background",
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
      edgeSize = 12,
      insets = {left = 4, right = 4, top = 4, bottom = 4}
    })
    roleMenu:SetBackdropColor(0, 0, 0, 0.95)
    roleMenu:Hide()
    
    local roleMenuButtons = {}
    local roleNames = {"Tanks", "Healers", "Melee", "Ranged"}
    
    local function UpdateRoleSelection(role)
      selectedRole = role
      roleSelectorBtn:SetText("Select Role: " .. role)
      roleMenu:Hide()
      -- Refresh player list
      if frame.RefreshPlayerList then
        frame.RefreshPlayerList()
      end
    end
    
    for i, roleName in ipairs(roleNames) do
      local btn = CreateFrame("Button", nil, roleMenu, "UIPanelButtonTemplate")
      btn:SetWidth(145)  -- Adjusted for new menu width
      btn:SetHeight(20)
      if i == 1 then
        btn:SetPoint("TOPLEFT", roleMenu, "TOPLEFT", 5, -5)
      else
        btn:SetPoint("TOP", roleMenuButtons[i-1], "BOTTOM", 0, -2)
      end
      btn:SetText(roleName)
      local capturedRole = roleName
      btn:SetScript("OnClick", function()
        UpdateRoleSelection(capturedRole)
      end)
      table.insert(roleMenuButtons, btn)
    end
    
    roleMenu:SetHeight(15 + (table.getn(roleMenuButtons) * 20) + ((table.getn(roleMenuButtons) - 1) * 2) + 5)
    
    roleSelectorBtn:SetScript("OnClick", function()
      if roleMenu:IsVisible() then
        roleMenu:Hide()
      else
        roleMenu:ClearAllPoints()
        roleMenu:SetPoint("TOPLEFT", roleSelectorBtn, "BOTTOMLEFT", 0, -2)
        roleMenu:Show()
      end
    end)
    
    -- Player list scroll area
    local playerListScrollFrame = CreateFrame("ScrollFrame", nil, leftPanel)
    playerListScrollFrame:SetPoint("TOPLEFT", roleSelectorBtn, "BOTTOMLEFT", 0, -10)
    playerListScrollFrame:SetPoint("BOTTOMRIGHT", leftPanel, "BOTTOMRIGHT", -10, 10)
    
    -- Create scroll child frame
    local playerListFrame = CreateFrame("Frame", nil, playerListScrollFrame)
    playerListFrame:SetWidth(145)
    playerListFrame:SetHeight(1)  -- Will be adjusted based on content
    playerListScrollFrame:SetScrollChild(playerListFrame)
    frame.playerListFrame = playerListFrame
    frame.playerListScrollFrame = playerListScrollFrame
    
    -- Create scroll bar
    local scrollBar = CreateFrame("Slider", nil, playerListScrollFrame)
    scrollBar:SetPoint("TOPRIGHT", playerListScrollFrame, "TOPRIGHT", 0, -16)
    scrollBar:SetPoint("BOTTOMRIGHT", playerListScrollFrame, "BOTTOMRIGHT", 0, 16)
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
    scrollBar:SetValueStep(22)
    scrollBar:Hide()  -- Hidden by default
    frame.playerScrollBar = scrollBar
    
    scrollBar:SetScript("OnValueChanged", function()
      playerListScrollFrame:SetVerticalScroll(this:GetValue())
    end)
    
    -- Enable mouse wheel scrolling
    playerListScrollFrame:EnableMouseWheel(true)
    playerListScrollFrame:SetScript("OnMouseWheel", function()
      local delta = arg1
      local current = scrollBar:GetValue()
      local minVal, maxVal = scrollBar:GetMinMaxValues()
      
      if delta > 0 then
        scrollBar:SetValue(math.max(minVal, current - 22))
      else
        scrollBar:SetValue(math.min(maxVal, current + 22))
      end
    end)
    
    -- Function to refresh player list based on selected role
    function frame.RefreshPlayerList()
      -- Clear existing player buttons
      if frame.playerButtons then
        for _, btn in ipairs(frame.playerButtons) do
          btn:Hide()
          btn:SetParent(nil)
        end
      end
      frame.playerButtons = {}
      
      -- Get players from selected role
      local players = {}
      if OGRH.Roles and OGRH.Roles.columns then
        local roleIndex = 1
        if selectedRole == "Healers" then roleIndex = 2
        elseif selectedRole == "Melee" then roleIndex = 3
        elseif selectedRole == "Ranged" then roleIndex = 4
        end
        
        if OGRH.Roles.columns[roleIndex] then
          for _, playerName in ipairs(OGRH.Roles.columns[roleIndex].players) do
            table.insert(players, playerName)
          end
        end
      end
      
      -- Create player buttons
      local yOffset = -5
      for _, playerName in ipairs(players) do
        local playerBtn = CreateFrame("Button", nil, playerListFrame)
        playerBtn:SetWidth(145)  -- Adjusted for new panel width
        playerBtn:SetHeight(20)
        playerBtn:SetPoint("TOPLEFT", playerListFrame, "TOPLEFT", 5, yOffset)
        
        -- Background
        local bg = playerBtn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetTexture("Interface\\Buttons\\WHITE8X8")
        bg:SetVertexColor(0.2, 0.2, 0.2, 0.5)
        
        -- Player name text
        local nameText = playerBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        nameText:SetPoint("LEFT", playerBtn, "LEFT", 5, 0)
        local class = OGRH.Roles.nameClass and OGRH.Roles.nameClass[playerName]
        if class and OGRH.ClassColorHex then
          nameText:SetText(OGRH.ClassColorHex(class) .. playerName .. "|r")
        else
          nameText:SetText(playerName)
        end
        
        -- TODO: Add drag functionality
        
        table.insert(frame.playerButtons, playerBtn)
        yOffset = yOffset - 22
      end
      
      -- Update scroll frame height
      local contentHeight = math.abs(yOffset) + 5
      playerListFrame:SetHeight(contentHeight)
      
      -- Update scrollbar
      local scrollFrame = frame.playerListScrollFrame
      local scrollBar = frame.playerScrollBar
      local scrollFrameHeight = scrollFrame:GetHeight()
      
      if contentHeight > scrollFrameHeight then
        -- Show scrollbar and adjust scroll range
        scrollBar:Show()
        scrollBar:SetMinMaxValues(0, contentHeight - scrollFrameHeight)
        scrollBar:SetValue(0)
        scrollFrame:SetVerticalScroll(0)
      else
        -- Hide scrollbar
        scrollBar:Hide()
        scrollFrame:SetVerticalScroll(0)
      end
    end
    
    -- Right panel: Role containers
    local rightPanel = CreateFrame("Frame", nil, frame)
    rightPanel:SetWidth(595)  -- Increased to use more horizontal space
    rightPanel:SetHeight(380)  -- Match left panel height
    rightPanel:SetPoint("TOPLEFT", leftPanel, "TOPRIGHT", 10, 0)  -- Position relative to left panel
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
    
    -- Create role containers
    local roleContainers = {}
    
    local function CreateRoleContainer(parent, title, maxPlayers, xPos, yPos, width)
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
      
      -- Title
      local titleText = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      titleText:SetPoint("TOP", container, "TOP", 0, -10)
      titleText:SetText(title)
      
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
        
        -- Mark button (raid target icon)
        local markBtn = CreateFrame("Button", nil, slot)
        markBtn:SetWidth(16)
        markBtn:SetHeight(16)
        markBtn:SetPoint("LEFT", slot, "LEFT", 5, 0)
        local markBg = markBtn:CreateTexture(nil, "BACKGROUND")
        markBg:SetAllPoints()
        markBg:SetTexture("Interface\\Buttons\\WHITE8X8")
        markBg:SetVertexColor(0.2, 0.2, 0.2, 0.5)
        slot.markBtn = markBtn
        
        -- Player name text
        local nameText = slot:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        nameText:SetPoint("LEFT", markBtn, "RIGHT", 5, 0)
        nameText:SetText("|cff888888[Empty]|r")
        slot.nameText = nameText
        
        -- Only show up/down buttons if maxPlayers > 1
        if maxPlayers > 1 then
          -- Up button
          local upBtn = CreateFrame("Button", nil, slot)
          upBtn:SetWidth(20)
          upBtn:SetHeight(20)
          upBtn:SetPoint("RIGHT", slot, "RIGHT", -25, 0)
          upBtn:SetNormalTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Up")
          upBtn:SetPushedTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Down")
          upBtn:SetHighlightTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Highlight")
          slot.upBtn = upBtn
          
          -- Down button
          local downBtn = CreateFrame("Button", nil, slot)
          downBtn:SetWidth(20)
          downBtn:SetHeight(20)
          downBtn:SetPoint("RIGHT", slot, "RIGHT", -5, 0)
          downBtn:SetNormalTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up")
          downBtn:SetPushedTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Down")
          downBtn:SetHighlightTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Highlight")
          slot.downBtn = downBtn
        end
        
        table.insert(container.slots, slot)
      end
      
      return container
    end
    
    -- Create the four role containers in 2x2 layout
    -- Top row: Main Tank (left) and Orb Control (right)
    roleContainers.mainTank = CreateRoleContainer(rightPanel, "Main Tank", 1, 10, -10, 282)
    roleContainers.orbControl = CreateRoleContainer(rightPanel, "Orb Control", 1, 302, -10, 282)
    
    -- Bottom row: Near Side (left) and Far Side (right)
    roleContainers.nearSide = CreateRoleContainer(rightPanel, "Near Side", 5, 10, -80, 282)
    roleContainers.farSide = CreateRoleContainer(rightPanel, "Far Side", 5, 302, -80, 282)
    
    frame.roleContainers = roleContainers
    
    -- Initialize with selected role
    UpdateRoleSelection("Tanks")
  end
  
  frame:Show()
  frame.RefreshPlayerList()
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

-- Initialize SavedVariables when addon loads
InitializeSavedVars()

DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OGRH:|r Encounter Management loaded")
