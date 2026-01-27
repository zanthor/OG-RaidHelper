-- OGRH_EncounterSetup.lua
-- Encounter Setup Window and Role Editor
-- Extracted from OGRH_EncounterMgmt.lua for better modularity

-- Ensure OGRH namespace exists
if not OGRH then OGRH = {} end

-- Function to show Encounter Setup Window
function OGRH.ShowEncounterSetup(raidName, encounterName)
  -- Check if encounter data exists, if not show Share window
  OGRH.EnsureSV()
  local raids = OGRH.SVM.GetPath("encounterMgmt.raids")
  if not raids or table.getn(raids) == 0 then
    OGRH.Msg("|cffff6666[RH-Encounter]|r No encounter data found. Please import data from the Share window.")
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
    
    -- Planning button (to the left of Close button)
    local planningBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    planningBtn:SetWidth(70)
    planningBtn:SetHeight(24)
    planningBtn:SetPoint("RIGHT", closeBtn, "LEFT", -5, 0)
    planningBtn:SetText("Planning")
    OGRH.StyleButton(planningBtn)
    frame.planningBtn = planningBtn
    
    planningBtn:SetScript("OnEnter", function()
      GameTooltip:SetOwner(this, "ANCHOR_TOP")
      GameTooltip:SetText("Planning", 1, 1, 1)
      GameTooltip:AddLine("Open Encounter Planning to assign players to roles for the selected encounter.", 0.8, 0.8, 0.8, 1)
      GameTooltip:Show()
    end)
    planningBtn:SetScript("OnLeave", function()
      GameTooltip:Hide()
    end)
    
    planningBtn:SetScript("OnClick", function()
      local selectedRaid = frame.selectedRaid
      local selectedEncounter = frame.selectedEncounter
      
      if not selectedRaid or not selectedEncounter then
        OGRH.Msg("Select a raid and encounter first.")
        return
      end
      
      -- Close Encounter Setup window
      frame:Hide()
      
      -- Open Encounter Planning with the selected raid and encounter
      if OGRH.ShowEncounterPlanning then
        OGRH.ShowEncounterPlanning(selectedRaid, selectedEncounter)
      end
    end)
    
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
    OGRH.EnsureSV()
    
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
      
      -- Add existing raids (new structure only)
      local raids = OGRH.SVM.GetPath("encounterMgmt.raids") or {}
      for i = 1, table.getn(raids) do
        local raid = raids[i]
        local raidName = raid.name
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
        local raids = OGRH.SVM.GetPath("encounterMgmt.raids") or {}
        OGRH.AddListItemButtons(
          raidBtn,
          capturedIndex,
          table.getn(raids),
          function()
            -- Move up
            local currentRaids = OGRH.SVM.GetPath("encounterMgmt.raids") or {}
            local temp = currentRaids[capturedIndex - 1]
            currentRaids[capturedIndex - 1] = currentRaids[capturedIndex]
            currentRaids[capturedIndex] = temp
            
            OGRH.SVM.SetPath("encounterMgmt.raids", currentRaids, {
              syncLevel = "MANUAL",
              componentType = "structure"
            })
            
            RefreshRaidsList()
          end,
          function()
            -- Move down
            local currentRaids = OGRH.SVM.GetPath("encounterMgmt.raids") or {}
            local temp = currentRaids[capturedIndex + 1]
            currentRaids[capturedIndex + 1] = currentRaids[capturedIndex]
            currentRaids[capturedIndex] = temp
            
            OGRH.SVM.SetPath("encounterMgmt.raids", currentRaids, {
              syncLevel = "MANUAL",
              componentType = "structure"
            })
            
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
      
      -- Get encounters from raid object via SVM
      local raid = OGRH.FindRaidByName(frame.selectedRaid)
      if not raid or not raid.encounters then
        return
      end
      
      local yOffset = -5
      local selectedIndex = nil
      local contentWidth = scrollChild:GetWidth()
      
      -- Add existing encounters for selected raid
      local encounters = {}
      for i = 1, table.getn(raid.encounters) do
        table.insert(encounters, raid.encounters[i].name)
      end
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
          table.getn(encounters),
          function()
            -- Move up
            local raids = OGRH.SVM.GetPath("encounterMgmt.raids") or {}
            local raidObj = nil
            for i = 1, table.getn(raids) do
              if raids[i].name == capturedRaid then
                raidObj = raids[i]
                break
              end
            end
            
            if raidObj and raidObj.encounters then
              local temp = raidObj.encounters[capturedIndex - 1]
              raidObj.encounters[capturedIndex - 1] = raidObj.encounters[capturedIndex]
              raidObj.encounters[capturedIndex] = temp
              
              OGRH.SVM.SetPath("encounterMgmt.raids", raids, {
                syncLevel = "MANUAL",
                componentType = "structure"
              })
              
              RefreshEncountersList()
            end
          end,
          function()
            -- Move down
            local raids = OGRH.SVM.GetPath("encounterMgmt.raids") or {}
            local raidObj = nil
            for i = 1, table.getn(raids) do
              if raids[i].name == capturedRaid then
                raidObj = raids[i]
                break
              end
            end
            
            if raidObj and raidObj.encounters then
              local temp = raidObj.encounters[capturedIndex + 1]
              raidObj.encounters[capturedIndex + 1] = raidObj.encounters[capturedIndex]
              raidObj.encounters[capturedIndex] = temp
              
              OGRH.SVM.SetPath("encounterMgmt.raids", raids, {
                syncLevel = "MANUAL",
                componentType = "structure"
              })
              
              RefreshEncountersList()
            end
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
    
    -- Function to get next available role ID (v2: flat array)
    local function GetNextRoleId(roles)
      local maxId = 0
      for _, role in ipairs(roles or {}) do
        if role.roleId and role.roleId > maxId then
          maxId = role.roleId
        end
      end
      return maxId + 1
    end
    
    -- Helper: Write encounter roles via SVM (v2: write specific path, not entire raids array)
    function OGRH.WriteEncounterRoles(raidName, encounterName, roles, syncLevel)
      -- Find raid and encounter indices
      local raids = OGRH.SVM.GetPath("encounterMgmt.raids")
      if not raids then return end
      
      local raidIdx, encIdx
      for i = 1, table.getn(raids) do
        if raids[i].name == raidName then
          raidIdx = i
          if raids[i].encounters then
            for j = 1, table.getn(raids[i].encounters) do
              if raids[i].encounters[j].name == encounterName then
                encIdx = j
                break
              end
            end
          end
          break
        end
      end
      
      if not raidIdx or not encIdx then return end
      
      -- Write just the roles array at specific path
      local path = string.format("encounterMgmt.raids.%d.encounters.%d.roles", raidIdx, encIdx)
      OGRH.SVM.SetPath(path, roles, {
        syncLevel = syncLevel or "MANUAL",
        componentType = "settings",
        scope = {raid = raidName, encounter = encounterName}
      })
    end
    
    -- Function to refresh roles list (v2 schema)
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
      
      -- V2 schema: Get encounter object which contains roles array
      local raid = OGRH.FindRaidByName(frame.selectedRaid)
      if not raid then return end
      
      local encounter = OGRH.FindEncounterByName(raid, frame.selectedEncounter)
      if not encounter then return end
      
      -- Ensure roles array exists (v2: flat array with column field)
      if not encounter.roles then
        encounter.roles = {}
      end
      
      local allRoles = encounter.roles
      
      local allRoles = encounter.roles
      
      local yOffset1 = -5
      local yOffset2 = -5
      
      -- Helper function to create a role button (v2: roles have column field)
      local function CreateRoleButton(globalIndex, role, scrollChild, isColumn2)
        local roleBtn = OGRH.CreateStyledListItem(scrollChild, frame.rolesContentWidth, OGRH.LIST_ITEM_HEIGHT, "Button")
        
        local yOffset = isColumn2 and yOffset2 or yOffset1
        roleBtn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, yOffset)
        
        -- Make draggable
        roleBtn:RegisterForDrag("LeftButton")
        
        -- Role name text
        local nameText = roleBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        nameText:SetPoint("LEFT", roleBtn, "LEFT", 5, 0)
        local roleIdText = role.roleId and ("R" .. role.roleId .. " ") or ""
        nameText:SetText(roleIdText .. (role.name or "Unnamed"))
        nameText:SetWidth(70)
        nameText:SetJustifyH("LEFT")
        
        -- Store data on button for drag operations
        roleBtn.roleData = role
        roleBtn.globalIndex = globalIndex
        roleBtn.isColumn2 = isColumn2
        
        -- Click to edit role
        roleBtn:SetScript("OnClick", function()
          if not OGRH.CanEdit or not OGRH.CanEdit() then
            OGRH.Msg("Only the raid lead can edit roles.")
            return
          end
          
          OGRH.ShowEditRoleDialog(
            frame.selectedRaid,
            frame.selectedEncounter,
            role,
            allRoles,
            globalIndex,
            RefreshRolesList
          )
        end)
        
        -- Drag handlers (v2: change column field instead of moving between arrays)
        roleBtn:SetScript("OnDragStart", function()
          this.isDragging = true
          OGRH.SetListItemColor(roleBtn, 0.3, 0.5, 0.3, 0.8)
          
          if frame.dragCursor and frame.dragCursorText then
            frame.dragCursorText:SetText(role.name or "Unnamed")
            frame.dragCursor:Show()
          end
        end)
        
        roleBtn:SetScript("OnDragStop", function()
          this.isDragging = false
          OGRH.SetListItemSelected(roleBtn, false)
          
          if frame.dragCursor then
            frame.dragCursor:Hide()
          end
          
          -- Check if dropped on the other column's scroll frame
          local targetScrollFrame = this.isColumn2 and frame.rolesScrollFrame or frame.rolesScrollFrame2
          
          if MouseIsOver(targetScrollFrame) then
            -- V2: Change column field (1 <-> 2)
            role.column = this.isColumn2 and 1 or 2
            
            -- Write back via SVM (just the roles array, not entire raids)
            OGRH.WriteEncounterRoles(frame.selectedRaid, frame.selectedEncounter, allRoles, "MANUAL")
            
            RefreshRolesList()
          end
        end)
        
        -- Capture variables for button closures
        local capturedIdx = globalIndex
        
        -- Count roles in same column for up/down limits
        local sameColumnCount = 0
        local posInColumn = 0
        for i, r in ipairs(allRoles) do
          if (r.column or 1) == (role.column or 1) then
            sameColumnCount = sameColumnCount + 1
            if i <= capturedIdx then
              posInColumn = posInColumn + 1
            end
          end
        end
        
        -- Add up/down/delete buttons
        OGRH.AddListItemButtons(
          roleBtn,
          posInColumn,
          sameColumnCount,
          function()
            -- Move up (within same column)
            if posInColumn <= 1 then return end
            
            -- Find previous role in same column
            local prevIdx = nil
            local currentColumn = role.column or 1
            for i = capturedIdx - 1, 1, -1 do
              if (allRoles[i].column or 1) == currentColumn then
                prevIdx = i
                break
              end
            end
            
            if prevIdx then
              local temp = allRoles[prevIdx]
              allRoles[prevIdx] = allRoles[capturedIdx]
              allRoles[capturedIdx] = temp
              
              OGRH.WriteEncounterRoles(frame.selectedRaid, frame.selectedEncounter, allRoles, "MANUAL")
              
              RefreshRolesList()
            end
          end,
          function()
            -- Move down (within same column)
            if posInColumn >= sameColumnCount then return end
            
            -- Find next role in same column
            local nextIdx = nil
            local currentColumn = role.column or 1
            for i = capturedIdx + 1, table.getn(allRoles) do
              if (allRoles[i].column or 1) == currentColumn then
                nextIdx = i
                break
              end
            end
            
            if nextIdx then
              local temp = allRoles[nextIdx]
              allRoles[nextIdx] = allRoles[capturedIdx]
              allRoles[capturedIdx] = temp
              
              OGRH.WriteEncounterRoles(frame.selectedRaid, frame.selectedEncounter, allRoles, "MANUAL")
              
              RefreshRolesList()
            end
          end,
          function()
            -- Delete
            table.remove(allRoles, capturedIdx)
            
            OGRH.WriteEncounterRoles(frame.selectedRaid, frame.selectedEncounter, allRoles, "MANUAL")
            
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
      
      -- V2: Iterate flat array, filter by column field
      for i, role in ipairs(allRoles) do
        local column = role.column or 1  -- Default to column 1 if not set
        if column == 1 then
          CreateRoleButton(i, role, scrollChild1, false)
        elseif column == 2 then
          CreateRoleButton(i, role, scrollChild2, true)
        end
      end
      
      -- Add "Add Role" button to both columns at the bottom
      -- Left column Add Role button
      local addRoleBtn1 = OGRH.CreateStyledListItem(scrollChild1, frame.rolesContentWidth, OGRH.LIST_ITEM_HEIGHT, "Button")
      addRoleBtn1:SetPoint("TOPLEFT", scrollChild1, "TOPLEFT", 0, yOffset1)
      
      local addText1 = addRoleBtn1:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      addText1:SetPoint("CENTER", addRoleBtn1, "CENTER", 0, 0)
      addText1:SetText("|cff00ff00Add Role|r")
      
      addRoleBtn1:SetScript("OnClick", function()
        local newRoleId = GetNextRoleId(allRoles)
        local newRole = {
          name = "New Role", 
          slots = 1, 
          roleId = newRoleId,
          fillOrder = newRoleId,
          column = 1
        }
        table.insert(allRoles, newRole)
        
        OGRH.WriteEncounterRoles(frame.selectedRaid, frame.selectedEncounter, allRoles, "MANUAL")
        
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
        local newRoleId = GetNextRoleId(allRoles)
        local newRole = {
          name = "New Role", 
          slots = 1, 
          roleId = newRoleId,
          fillOrder = newRoleId,
          column = 2
        }
        table.insert(allRoles, newRole)
        
        OGRH.WriteEncounterRoles(frame.selectedRaid, frame.selectedEncounter, allRoles, "MANUAL")
        
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
    
    -- Create RefreshAll wrapper for external callers
    frame.RefreshAll = function()
      if frame.RefreshRaidsList then frame.RefreshRaidsList() end
      if frame.RefreshEncountersList then frame.RefreshEncountersList() end
      if frame.RefreshRolesList then frame.RefreshRolesList() end
    end
    
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
  
  -- Set specific raid and encounter if provided
  if raidName and encounterName then
    frame.selectedRaid = raidName
    frame.selectedEncounter = encounterName
    frame.RefreshRaidsList()
    frame.RefreshEncountersList()
    frame.RefreshRolesList()
  else
    frame:Show()
    frame.RefreshRaidsList()
  end
  
  frame:Show()
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
      OGRH.EnsureSV()
      -- Check if raid already exists
      local raids = OGRH.SVM.GetPath("encounterMgmt.raids") or {}
      local exists = false
      for i = 1, table.getn(raids) do
        local existing = raids[i]
        local existingName = type(existing) == "table" and existing.name or existing
        if existingName == raidName then
          exists = true
          break
        end
      end
      
      if not exists then
        table.insert(raids, {
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
        })
        
        OGRH.SVM.SetPath("encounterMgmt.raids", raids, {
          syncLevel = "MANUAL",
          componentType = "structure"
        })
        
        if OGRH_EncounterSetupFrame and OGRH_EncounterSetupFrame.RefreshRaidsList then
          OGRH_EncounterSetupFrame.RefreshRaidsList()
        end
        OGRH.Msg("|cffff6666[RH-Encounter]|r Raid '" .. raidName .. "' added")
      else
        OGRH.Msg("|cffff0000[RH-Error]|r Raid '" .. raidName .. "' already exists")
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
      local raids = OGRH.SVM.GetPath("encounterMgmt.raids") or {}
      for i = 1, table.getn(raids) do
        local raid = raids[i]
        local name = type(raid) == "table" and raid.name or raid
        if name == raidName then
          table.remove(raids, i)
          break
        end
      end
      
      OGRH.SVM.SetPath("encounterMgmt.raids", raids, {
        syncLevel = "MANUAL",
        componentType = "structure"
      })
      
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
      OGRH.Msg("|cffff6666[RH-Encounter]|r Raid '" .. raidName .. "' deleted")
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
      OGRH.EnsureSV()
      
      -- Find the raid in new structure
      local raidObj = nil
      local raids = OGRH.SVM.GetPath("encounterMgmt.raids") or {}
      for i = 1, table.getn(raids) do
        local raid = raids[i]
        if raid.name == raidName then
          raidObj = raid
          break
        end
      end
      
      if not raidObj then
        OGRH.Msg("|cffff0000[RH-Error]|r Raid not found")
        return
      end
      
      -- Ensure encounters array exists
      if not raidObj.encounters then
        raidObj.encounters = {}
      end
      
      -- Check if encounter already exists
      local exists = false
      for i = 1, table.getn(raidObj.encounters) do
        if raidObj.encounters[i].name == encounterName then
          exists = true
          break
        end
      end
      
      if not exists then
        -- Create new encounter with proper structure
        local newEncounter = {
          name = encounterName,
          advancedSettings = {
            bigwigs = {
              enabled = false,
              encounterId = "",
              autoAnnounce = false
            },
            consumeTracking = {
              enabled = nil,
              readyThreshold = nil,
              requiredFlaskRoles = {}
            }
          }
        }
        table.insert(raidObj.encounters, newEncounter)
        
        -- Write back via SVM
        OGRH.SVM.SetPath("encounterMgmt.raids", raids, {
          syncLevel = "MANUAL",
          componentType = "structure"
        })
        
        if OGRH_EncounterSetupFrame and OGRH_EncounterSetupFrame.RefreshEncountersList then
          OGRH_EncounterSetupFrame.RefreshEncountersList()
        end
        OGRH.Msg("|cffff6666[RH-Encounter]|r Encounter '" .. encounterName .. "' added to " .. raidName)
      else
        OGRH.Msg("|cffff0000[RH-Error]|r Encounter '" .. encounterName .. "' already exists in " .. raidName)
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
      -- Find the raid in new structure
      local raidObj = nil
      local raids = OGRH.SVM.GetPath("encounterMgmt.raids") or {}
      for i = 1, table.getn(raids) do
        local raid = raids[i]
        if raid.name == raidName then
          raidObj = raid
          break
        end
      end
      
      -- Remove encounter from raid's encounters array
      if raidObj and raidObj.encounters then
        for i = 1, table.getn(raidObj.encounters) do
          if raidObj.encounters[i].name == encounterName then
            table.remove(raidObj.encounters, i)
            break
          end
        end
      end
      
      -- Write back via SVM
      OGRH.SVM.SetPath("encounterMgmt.raids", raids, {
        syncLevel = "MANUAL",
        componentType = "structure"
      })
      
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
      OGRH.Msg("|cffff6666[RH-Encounter]|r Encounter '" .. encounterName .. "' deleted")
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
      OGRH.EnsureSV()
      
      -- Check if new name already exists
      local raids = OGRH.SVM.GetPath("encounterMgmt.raids") or {}
      local exists = false
      for i = 1, table.getn(raids) do
        local existing = raids[i]
        local name = type(existing) == "table" and existing.name or existing
        if name == newName then
          exists = true
          break
        end
      end
      
      if not exists then
        -- Update raid name in raids list
        for i = 1, table.getn(raids) do
          local raid = raids[i]
          local name = type(raid) == "table" and raid.name or raid
          if name == oldName then
            if type(raid) == "table" then
              raid.name = newName
            else
              raids[i] = newName
            end
            break
          end
        end
        
        -- Update roles data structure
        local roles = OGRH.SVM.GetPath("encounterMgmt.roles") or {}
        if roles[oldName] then
          roles[newName] = roles[oldName]
          roles[oldName] = nil
        end
        
        -- Write back via SVM
        OGRH.SVM.SetPath("encounterMgmt.raids", raids, {
          syncLevel = "MANUAL",
          componentType = "structure"
        })
        OGRH.SVM.SetPath("encounterMgmt.roles", roles, {
          syncLevel = "MANUAL",
          componentType = "structure"
        })
        
        -- Update assignments (read, modify, write back)
        local assignments = OGRH.SVM.GetPath("encounterAssignments") or {}
        if assignments[oldName] then
          assignments[newName] = assignments[oldName]
          assignments[oldName] = nil
          OGRH.SVM.SetPath("encounterAssignments", assignments, {
            syncLevel = "MANUAL",
            componentType = "structure"
          })
        end
        
        -- Update raid marks
        local marks = OGRH.SVM.GetPath("encounterRaidMarks") or {}
        if marks[oldName] then
          marks[newName] = marks[oldName]
          marks[oldName] = nil
          OGRH.SVM.SetPath("encounterRaidMarks", marks, {
            syncLevel = "MANUAL",
            componentType = "structure"
          })
        end
        
        -- Update assignment numbers
        local numbers = OGRH.SVM.GetPath("encounterAssignmentNumbers") or {}
        if numbers[oldName] then
          numbers[newName] = numbers[oldName]
          numbers[oldName] = nil
          OGRH.SVM.SetPath("encounterAssignmentNumbers", numbers, {
            syncLevel = "MANUAL",
            componentType = "structure"
          })
        end
        
        -- Update announcements
        local announcements = OGRH.SVM.GetPath("encounterAnnouncements") or {}
        if announcements[oldName] then
          announcements[newName] = announcements[oldName]
          announcements[oldName] = nil
          OGRH.SVM.SetPath("encounterAnnouncements", announcements, {
            syncLevel = "MANUAL",
            componentType = "structure"
          })
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
        
        OGRH.Msg("|cffff6666[RH-Encounter]|r Raid renamed from '" .. oldName .. "' to '" .. newName .. "'")
      else
        OGRH.Msg("|cffff0000[RH-Error]|r Raid '" .. newName .. "' already exists")
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
      OGRH.EnsureSV()
      
      -- Find the raid in new structure
      local raidObj = nil
      local raids = OGRH.SVM.GetPath("encounterMgmt.raids") or {}
      for i = 1, table.getn(raids) do
        local raid = raids[i]
        if raid.name == raidName then
          raidObj = raid
          break
        end
      end
      
      if not raidObj then
        OGRH.Msg("|cffff0000[RH-Error]|r Raid not found")
        return
      end
      
      -- Check if new name already exists in this raid
      local exists = false
      if raidObj.encounters then
        for i = 1, table.getn(raidObj.encounters) do
          if raidObj.encounters[i].name == newName then
            exists = true
            break
          end
        end
      end
      
      if not exists then
        -- Update encounter name in encounters array
        if raidObj.encounters then
          for i = 1, table.getn(raidObj.encounters) do
            if raidObj.encounters[i].name == oldName then
              raidObj.encounters[i].name = newName
              break
            end
          end
        end
        
        -- Write back raids via SVM
        OGRH.SVM.SetPath("encounterMgmt.raids", raids, {
          syncLevel = "MANUAL",
          componentType = "structure"
        })
        
        -- Update roles data structure
        local roles = OGRH.SVM.GetPath("encounterMgmt.roles") or {}
        if roles[raidName] and roles[raidName][oldName] then
          roles[raidName][newName] = roles[raidName][oldName]
          roles[raidName][oldName] = nil
          OGRH.SVM.SetPath("encounterMgmt.roles", roles, {
            syncLevel = "MANUAL",
            componentType = "structure"
          })
        end
        
        -- Update assignments
        local assignments = OGRH.SVM.GetPath("encounterAssignments") or {}
        if assignments[raidName] and assignments[raidName][oldName] then
          assignments[raidName][newName] = assignments[raidName][oldName]
          assignments[raidName][oldName] = nil
          OGRH.SVM.SetPath("encounterAssignments", assignments, {
            syncLevel = "MANUAL",
            componentType = "structure"
          })
        end
        
        -- Update raid marks
        local marks = OGRH.SVM.GetPath("encounterRaidMarks") or {}
        if marks[raidName] and marks[raidName][oldName] then
          marks[raidName][newName] = marks[raidName][oldName]
          marks[raidName][oldName] = nil
          OGRH.SVM.SetPath("encounterRaidMarks", marks, {
            syncLevel = "MANUAL",
            componentType = "structure"
          })
        end
        
        -- Update assignment numbers
        local numbers = OGRH.SVM.GetPath("encounterAssignmentNumbers") or {}
        if numbers[raidName] and numbers[raidName][oldName] then
          numbers[raidName][newName] = numbers[raidName][oldName]
          numbers[raidName][oldName] = nil
          OGRH.SVM.SetPath("encounterAssignmentNumbers", numbers, {
            syncLevel = "MANUAL",
            componentType = "structure"
          })
        end
        
        -- Update announcements
        local announcements = OGRH.SVM.GetPath("encounterAnnouncements") or {}
        if announcements[raidName] and announcements[raidName][oldName] then
          announcements[raidName][newName] = announcements[raidName][oldName]
          announcements[raidName][oldName] = nil
          OGRH.SVM.SetPath("encounterAnnouncements", announcements, {
            syncLevel = "MANUAL",
            componentType = "structure"
          })
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
        
        OGRH.Msg("|cffff6666[RH-Encounter]|r Encounter renamed from '" .. oldName .. "' to '" .. newName .. "'")
      else
        OGRH.Msg("|cffff0000[RH-Error]|r Encounter '" .. newName .. "' already exists in " .. raidName)
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
          OGRH.Msg("|cffff0000[RH-Error]|r Only one Consume Check role allowed per encounter.")
          return
        end
      end
    end
    
    if isCustomModule then
      for i, role in ipairs(currentColumnRoles) do
        if i ~= currentRoleIndex and role.isCustomModule then
          OGRH.Msg("|cffff0000[RH-Error]|r Only one Custom Module role allowed per encounter.")
          return
        end
      end
    end
    
    -- Update role data
    local oldName = roleData.name
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
    
    -- Write updated roles via SVM (v2: write specific encounter.roles path)
    OGRH.WriteEncounterRoles(
      OGRH_EncounterSetupFrame.selectedRaid,
      OGRH_EncounterSetupFrame.selectedEncounter,
      columnRoles,
      "MANUAL"
    )
    
    -- Refresh the roles list
    if refreshCallback then
      refreshCallback()
    end
    
    frame:Hide()
    OGRH.Msg("|cffff6666[RH-Encounter]|r Role updated")
  end)
  
  frame:Show()
end