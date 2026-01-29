-- OGRH_ClassPriority.lua
-- Class Priority assignment dialog for role slots

-- Show class priority dialog for a specific role/slot
function OGRH.ShowClassPriorityDialog(raidName, encounterName, roleIndex, slotIndex, roleData, refreshCallback)
  -- Create or reuse frame
  if not OGRH_ClassPriorityFrame then
    local frame = CreateFrame("Frame", "OGRH_ClassPriorityFrame", UIParent)
    frame:SetWidth(500)
    frame:SetHeight(400)
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
    OGRH.MakeFrameCloseOnEscape(frame, "OGRH_ClassPriorityFrame")
    
    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", frame, "TOP", 0, -10)
    title:SetText("Class Priority")
    frame.title = title
    
    -- Subtitle (shows role and slot info)
    local subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    subtitle:SetPoint("TOP", title, "BOTTOM", 0, -5)
    subtitle:SetTextColor(0.7, 0.7, 0.7)
    frame.subtitle = subtitle
    
    -- Close button (top right)
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    closeBtn:SetWidth(60)
    closeBtn:SetHeight(24)
    closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -10)
    closeBtn:SetText("Close")
    OGRH.StyleButton(closeBtn)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)
    
    -- Instructions
    local instructions = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    instructions:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, -55)
    instructions:SetText("Set the order of class priority for this slot:")
    instructions:SetTextColor(0.8, 0.8, 0.8)
    
    -- Left column: Selected classes (priority order)
    local leftLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    leftLabel:SetPoint("TOPLEFT", instructions, "BOTTOMLEFT", 0, -10)
    leftLabel:SetText("Priority Order:")
    
    local leftListFrame, leftScrollFrame, leftScrollChild, leftScrollBar, leftContentWidth = 
      OGRH.CreateStyledScrollList(frame, 330, 240, true)
    leftListFrame:SetPoint("TOPLEFT", leftLabel, "BOTTOMLEFT", 0, -5)
    frame.leftListFrame = leftListFrame
    frame.leftScrollChild = leftScrollChild
    frame.leftContentWidth = leftContentWidth
    
    -- Right column: Available classes
    local rightLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    rightLabel:SetPoint("TOPLEFT", leftLabel, "TOPLEFT", 340, 0)
    rightLabel:SetText("Available Classes:")
    
    local rightListFrame, rightScrollFrame, rightScrollChild, rightScrollBar, rightContentWidth = 
      OGRH.CreateStyledScrollList(frame, 130, 240, true)
    rightListFrame:SetPoint("TOPLEFT", rightLabel, "BOTTOMLEFT", 0, -5)
    frame.rightListFrame = rightListFrame
    frame.rightScrollChild = rightScrollChild
    frame.rightContentWidth = rightContentWidth
    
    -- Save Button
    local saveBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    saveBtn:SetWidth(80)
    saveBtn:SetHeight(24)
    saveBtn:SetPoint("BOTTOMRIGHT", frame, "BOTTOM", -5, 15)
    saveBtn:SetText("Save")
    OGRH.StyleButton(saveBtn)
    frame.saveBtn = saveBtn
    
    -- Cancel Button
    local cancelBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    cancelBtn:SetWidth(80)
    cancelBtn:SetHeight(24)
    cancelBtn:SetPoint("BOTTOMLEFT", frame, "BOTTOM", 5, 15)
    cancelBtn:SetText("Cancel")
    OGRH.StyleButton(cancelBtn)
    cancelBtn:SetScript("OnClick", function() frame:Hide() end)
    
    OGRH_ClassPriorityFrame = frame
  end
  
  local frame = OGRH_ClassPriorityFrame
  
  -- Store context
  frame.raidName = raidName
  frame.encounterName = encounterName
  frame.roleIndex = roleIndex
  frame.slotIndex = slotIndex
  frame.roleData = roleData
  frame.refreshCallback = refreshCallback
  
  -- Update subtitle
  local roleName = roleData.name or "Role"
  frame.subtitle:SetText(roleName .. " - Slot " .. slotIndex)
  
  -- Initialize classPriority if it doesn't exist
  if not roleData.classPriority then
    roleData.classPriority = {}
  end
  if not roleData.classPriority[slotIndex] then
    roleData.classPriority[slotIndex] = {}
  end
  
  -- All available classes
  local allClasses = {"Druid", "Hunter", "Mage", "Paladin", "Priest", "Rogue", "Shaman", "Warlock", "Warrior"}
  
  -- Function to refresh the lists
  local function RefreshLists()
    -- Clear existing items
    if frame.leftItems then
      for _, item in ipairs(frame.leftItems) do
        item:Hide()
      end
    end
    if frame.rightItems then
      for _, item in ipairs(frame.rightItems) do
        item:Hide()
      end
    end
    frame.leftItems = {}
    frame.rightItems = {}
    
    -- Get current priority list
    local priorityList = roleData.classPriority[slotIndex] or {}
    
    -- Build available classes list (allow duplicates, so all classes are always available)
    local availableClasses = {}
    for _, className in ipairs(allClasses) do
      table.insert(availableClasses, className)
    end
    
    -- Render left list (selected classes with up/down/delete)
    local yOffset = 0
    for i, className in ipairs(priorityList) do
      local item = OGRH.CreateStyledListItem(frame.leftScrollChild, frame.leftContentWidth, OGRH.LIST_ITEM_HEIGHT, "Button")
      item:SetPoint("TOPLEFT", frame.leftScrollChild, "TOPLEFT", 0, yOffset)
      
      -- Class name text
      local nameText = item:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      nameText:SetPoint("LEFT", item, "LEFT", 5, 0)
      nameText:SetJustifyH("LEFT")
      
      -- Add up/down/delete buttons (capture index in closure)
      do
        local capturedIndex = i
        local deleteBtn, downBtn, upBtn = OGRH.AddListItemButtons(
          item,
          i,
          table.getn(priorityList),
          function()
            -- Move up
            if capturedIndex > 1 then
              local temp = priorityList[capturedIndex]
              priorityList[capturedIndex] = priorityList[capturedIndex - 1]
              priorityList[capturedIndex - 1] = temp
              
              -- Also swap role flags if they exist
              if roleData.classPriorityRoles and roleData.classPriorityRoles[slotIndex] then
                local tempRoles = roleData.classPriorityRoles[slotIndex][capturedIndex]
                roleData.classPriorityRoles[slotIndex][capturedIndex] = roleData.classPriorityRoles[slotIndex][capturedIndex - 1]
                roleData.classPriorityRoles[slotIndex][capturedIndex - 1] = tempRoles
              end
              
              RefreshLists()
            end
          end,
          function()
            -- Move down
            if capturedIndex < table.getn(priorityList) then
              local temp = priorityList[capturedIndex]
              priorityList[capturedIndex] = priorityList[capturedIndex + 1]
              priorityList[capturedIndex + 1] = temp
              
              -- Also swap role flags if they exist
              if roleData.classPriorityRoles and roleData.classPriorityRoles[slotIndex] then
                local tempRoles = roleData.classPriorityRoles[slotIndex][capturedIndex]
                roleData.classPriorityRoles[slotIndex][capturedIndex] = roleData.classPriorityRoles[slotIndex][capturedIndex + 1]
                roleData.classPriorityRoles[slotIndex][capturedIndex + 1] = tempRoles
              end
              
              RefreshLists()
            end
          end,
          function()
            -- Delete
            table.remove(priorityList, capturedIndex)
            
            -- Also remove role flags for deleted item and shift remaining ones
            if roleData.classPriorityRoles and roleData.classPriorityRoles[slotIndex] then
              table.remove(roleData.classPriorityRoles[slotIndex], capturedIndex)
            end
            
            RefreshLists()
          end
        )
        
        -- Position name text to not overlap buttons
        if upBtn then
          nameText:SetPoint("RIGHT", upBtn, "LEFT", -5, 0)
        else
          nameText:SetPoint("RIGHT", deleteBtn, "LEFT", -5, 0)
        end
      end
      
      -- Set class-colored text
      local classUpper = string.upper(className)
      local classColor = OGRH.COLOR.CLASS[classUpper] or ""
      nameText:SetText(classColor .. className .. OGRH.COLOR.RESET)
      
      -- Add role checkboxes based on class
      -- Determine which roles this class can fill
      local roles = {}
      if classUpper == "DRUID" or classUpper == "SHAMAN" then
        roles = {"Tanks", "Healers", "Melee", "Ranged"}
      elseif classUpper == "WARRIOR" then
        roles = {"Tanks", "Melee"}
      elseif classUpper == "PALADIN" then
        roles = {"Tanks", "Healers", "Melee"}
      elseif classUpper == "HUNTER" then
        roles = {"Melee", "Ranged"}
      elseif classUpper == "PRIEST" then
        roles = {"Healers", "Ranged"}
      elseif classUpper == "ROGUE" or classUpper == "MAGE" or classUpper == "WARLOCK" then
        roles = {}  -- No role checkboxes
      end
      
      if table.getn(roles) > 0 then
        -- Initialize role flags if not present
        if not roleData.classPriorityRoles then
          roleData.classPriorityRoles = {}
        end
        if not roleData.classPriorityRoles[slotIndex] then
          roleData.classPriorityRoles[slotIndex] = {}
        end
        -- Store role flags by position in priority list, not by class name
        if not roleData.classPriorityRoles[slotIndex][i] then
          roleData.classPriorityRoles[slotIndex][i] = {}
        end
        
        local roleFlags = roleData.classPriorityRoles[slotIndex][i]
        local xOffset = 42  -- Start position for checkboxes
        
        for _, role in ipairs(roles) do
          local checkBox = CreateFrame("CheckButton", nil, item)
          checkBox:SetWidth(16)
          checkBox:SetHeight(16)
          checkBox:SetPoint("LEFT", item, "LEFT", xOffset, 0)
          checkBox:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
          checkBox:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
          checkBox:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight")
          checkBox:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
          
          -- Set initial state
          if roleFlags[role] then
            checkBox:SetChecked(true)
          end
          
          -- Label
          local label = checkBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
          label:SetPoint("LEFT", checkBox, "RIGHT", 0, 0)
          label:SetText(role)
          
          -- Click handler (capture variables in closure)
          do
            local capturedRole = role
            local capturedIndex = i
            checkBox:SetScript("OnClick", function()
              roleFlags[capturedRole] = this:GetChecked() and true or nil
            end)
          end
          
          xOffset = xOffset + 50  -- Space between checkboxes
        end
      end
      
      table.insert(frame.leftItems, item)
      yOffset = yOffset - (OGRH.LIST_ITEM_HEIGHT + OGRH.LIST_ITEM_SPACING)
    end
    
    -- Update left scroll child height
    local leftHeight = table.getn(priorityList) * (OGRH.LIST_ITEM_HEIGHT + OGRH.LIST_ITEM_SPACING)
    if leftHeight < 1 then leftHeight = 1 end
    frame.leftScrollChild:SetHeight(leftHeight)
    
    -- Render right list (available classes - click to add)
    yOffset = 0
    for i, className in ipairs(availableClasses) do
      local item = OGRH.CreateStyledListItem(frame.rightScrollChild, frame.rightContentWidth, OGRH.LIST_ITEM_HEIGHT, "Button")
      item:SetPoint("TOPLEFT", frame.rightScrollChild, "TOPLEFT", 0, yOffset)
      
      -- Class name text
      local nameText = item:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      nameText:SetPoint("LEFT", item, "LEFT", 5, 0)
      nameText:SetPoint("RIGHT", item, "RIGHT", -5, 0)
      nameText:SetJustifyH("LEFT")
      
      -- Set class-colored text
      local classUpper = string.upper(className)
      local classColor = OGRH.COLOR.CLASS[classUpper] or ""
      nameText:SetText(classColor .. className .. OGRH.COLOR.RESET)
      
      table.insert(frame.rightItems, item)
      
      -- Click to add to priority list (use do-end block to capture className)
      do
        local capturedClass = className
        item:SetScript("OnClick", function()
          table.insert(priorityList, capturedClass)
          RefreshLists()
        end)
      end
      yOffset = yOffset - (OGRH.LIST_ITEM_HEIGHT + OGRH.LIST_ITEM_SPACING)
    end
    
    -- Update right scroll child height
    local rightHeight = table.getn(availableClasses) * (OGRH.LIST_ITEM_HEIGHT + OGRH.LIST_ITEM_SPACING)
    if rightHeight < 1 then rightHeight = 1 end
    frame.rightScrollChild:SetHeight(rightHeight)
  end
  
  -- Save button handler
  frame.saveBtn:SetScript("OnClick", function()
    -- Data is already saved in roleData.classPriority[slotIndex]
    
    frame:Hide()
    
    -- Refresh parent if callback provided
    if refreshCallback then
      refreshCallback()
    end
    
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OGRH:|r Class priority saved")
  end)
  
  -- Initial render
  RefreshLists()
  
  frame:Show()
end

-- DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[RaidHelper]|r Class Priority loaded")
