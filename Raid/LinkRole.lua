-- OGRH_LinkRole.lua
-- Link Role dialog for connecting roles together

-- Show link role dialog for a specific role
function OGRH.ShowLinkRoleDialog(raidName, encounterName, roleIndex, roleData, allRoles, refreshCallback)
  -- Create or reuse frame
  if not OGRH_LinkRoleFrame then
    local frame = CreateFrame("Frame", "OGRH_LinkRoleFrame", UIParent)
    frame:SetWidth(450)
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
    OGRH.MakeFrameCloseOnEscape(frame, "OGRH_LinkRoleFrame")
    
    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", frame, "TOP", 0, -10)
    title:SetText("Link Roles")
    frame.title = title
    
    -- Subtitle (shows role info)
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
    instructions:SetText("Select roles to link with this role:")
    instructions:SetTextColor(0.8, 0.8, 0.8)
    
    -- Left column: Linked roles
    local leftLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    leftLabel:SetPoint("TOPLEFT", instructions, "BOTTOMLEFT", 0, -10)
    leftLabel:SetText("Linked Roles:")
    
    local leftListFrame, leftScrollFrame, leftScrollChild, leftScrollBar, leftContentWidth = 
      OGRH.CreateStyledScrollList(frame, 280, 240, true)
    leftListFrame:SetPoint("TOPLEFT", leftLabel, "BOTTOMLEFT", 0, -5)
    frame.leftListFrame = leftListFrame
    frame.leftScrollChild = leftScrollChild
    frame.leftContentWidth = leftContentWidth
    
    -- Right column: Available roles
    local rightLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    rightLabel:SetPoint("TOPLEFT", leftLabel, "TOPLEFT", 290, 0)
    rightLabel:SetText("Available Roles:")
    
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
    
    OGRH_LinkRoleFrame = frame
  end
  
  local frame = OGRH_LinkRoleFrame
  
  -- Update subtitle
  frame.subtitle:SetText("Role: " .. (roleData.name or "Unknown"))
  
  -- Store context
  frame.raidName = raidName
  frame.encounterName = encounterName
  frame.roleIndex = roleIndex
  frame.roleData = roleData
  frame.allRoles = allRoles
  frame.refreshCallback = refreshCallback
  
  -- Initialize linkedRoles if not exists
  if not roleData.linkedRoles then
    roleData.linkedRoles = {}
  end
  
  -- Create a copy of linked roles for editing
  frame.linkedRolesCopy = {}
  for _, linkedRoleIndex in ipairs(roleData.linkedRoles) do
    table.insert(frame.linkedRolesCopy, linkedRoleIndex)
  end
  
  -- Function to refresh both lists
  local function RefreshLists()
    -- Clear left list (linked roles)
    for _, child in pairs({frame.leftScrollChild:GetChildren()}) do
      child:Hide()
      child:SetParent(nil)
    end
    
    -- Clear right list (available roles)
    for _, child in pairs({frame.rightScrollChild:GetChildren()}) do
      child:Hide()
      child:SetParent(nil)
    end
    
    -- Build set of linked role indices for quick lookup
    local linkedSet = {}
    for _, linkedRoleIndex in ipairs(frame.linkedRolesCopy) do
      linkedSet[linkedRoleIndex] = true
    end
    
    -- Populate left list (linked roles)
    local yOffset = 0
    for _, linkedRoleIndex in ipairs(frame.linkedRolesCopy) do
      -- Find the role data
      local linkedRole = nil
      for i, r in ipairs(allRoles) do
        if i == linkedRoleIndex then
          linkedRole = r
          break
        end
      end
      
      if linkedRole then
        local item = OGRH.CreateStyledListItem(frame.leftScrollChild, frame.leftContentWidth, OGRH.LIST_ITEM_HEIGHT, "Button")
        item:SetPoint("TOPLEFT", frame.leftScrollChild, "TOPLEFT", 0, yOffset)
        
        -- Role name
        local nameText = item:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        nameText:SetPoint("LEFT", item, "LEFT", 5, 0)
        nameText:SetText(linkedRole.name or "Unknown")
        nameText:SetWidth(frame.leftContentWidth - 40)
        nameText:SetJustifyH("LEFT")
        
        -- Add delete button using helper function (hideUpDown = true for delete only)
        local capturedRoleIndex = linkedRoleIndex
        OGRH.AddListItemButtons(
          item,
          0, -- index (not used for delete-only)
          0, -- listLength (not used for delete-only)
          nil, -- onMoveUp (not used)
          nil, -- onMoveDown (not used)
          function() -- onDelete
            -- Remove from linked list
            for i, idx in ipairs(frame.linkedRolesCopy) do
              if idx == capturedRoleIndex then
                table.remove(frame.linkedRolesCopy, i)
                break
              end
            end
            RefreshLists()
          end,
          true -- hideUpDown = true (only show delete button)
        )
        
        yOffset = yOffset - OGRH.LIST_ITEM_HEIGHT
      end
    end
    
    -- Populate right list (available roles that have linkRole enabled and are not already linked)
    yOffset = 0
    for i, availableRole in ipairs(allRoles) do
      -- Skip self
      if i ~= roleIndex then
        -- Only show roles with linkRole enabled
        if availableRole.linkRole and not linkedSet[i] then
          local item = OGRH.CreateStyledListItem(frame.rightScrollChild, frame.rightContentWidth, OGRH.LIST_ITEM_HEIGHT, "Button")
          item:SetPoint("TOPLEFT", frame.rightScrollChild, "TOPLEFT", 0, yOffset)
          
          -- Role name
          local nameText = item:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
          nameText:SetPoint("CENTER", item, "CENTER")
          nameText:SetText(availableRole.name or "Unknown")
          nameText:SetWidth(frame.rightContentWidth - 10)
          nameText:SetJustifyH("CENTER")
          
          -- Click to add to linked list
          local capturedRoleIndex = i
          item:SetScript("OnClick", function()
            table.insert(frame.linkedRolesCopy, capturedRoleIndex)
            RefreshLists()
          end)
          
          yOffset = yOffset - OGRH.LIST_ITEM_HEIGHT
        end
      end
    end
  end
  
  -- Save button handler
  frame.saveBtn:SetScript("OnClick", function()
    -- Get old linked roles for comparison
    local oldLinkedRoles = {}
    if roleData.linkedRoles then
      for _, idx in ipairs(roleData.linkedRoles) do
        oldLinkedRoles[idx] = true
      end
    end
    
    -- Update role data
    roleData.linkedRoles = {}
    for _, linkedRoleIndex in ipairs(frame.linkedRolesCopy) do
      table.insert(roleData.linkedRoles, linkedRoleIndex)
    end
    
    -- Build complete set of all roles that should be linked together
    local allLinkedRoles = {roleIndex} -- Start with current role
    for _, linkedRoleIndex in ipairs(frame.linkedRolesCopy) do
      table.insert(allLinkedRoles, linkedRoleIndex)
    end
    
    -- Create fully bidirectional links: Every role in the group links to every other role
    for _, sourceRoleIndex in ipairs(allLinkedRoles) do
      local sourceRole = allRoles[sourceRoleIndex]
      if sourceRole then
        -- Initialize linkedRoles if not exists
        if not sourceRole.linkedRoles then
          sourceRole.linkedRoles = {}
        end
        
        -- Clear existing links and rebuild with full group
        sourceRole.linkedRoles = {}
        
        -- Add all other roles in the group
        for _, targetRoleIndex in ipairs(allLinkedRoles) do
          if targetRoleIndex ~= sourceRoleIndex then
            table.insert(sourceRole.linkedRoles, targetRoleIndex)
          end
        end
      end
    end
    
    -- Remove bidirectional links for roles that were unlinked
    for oldIdx, _ in pairs(oldLinkedRoles) do
      local stillLinked = false
      for _, newIdx in ipairs(frame.linkedRolesCopy) do
        if newIdx == oldIdx then
          stillLinked = true
          break
        end
      end
      
      -- If this role was unlinked, remove current role from its linkedRoles
      if not stillLinked then
        local unlinkedRole = allRoles[oldIdx]
        if unlinkedRole and unlinkedRole.linkedRoles then
          for i = table.getn(unlinkedRole.linkedRoles), 1, -1 do
            if unlinkedRole.linkedRoles[i] == roleIndex then
              table.remove(unlinkedRole.linkedRoles, i)
            end
          end
        end
      end
    end
    
    -- Refresh the parent display
    if refreshCallback then
      refreshCallback()
    end
    
    frame:Hide()
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OGRH:|r Linked roles updated")
  end)
  
  -- Initial refresh
  RefreshLists()
  
  frame:Show()
end
