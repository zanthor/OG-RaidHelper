-- OGRH_RGO.lua
-- Raid Group Organization module for managing raid composition and slot assignments

if not OGRH then
  DEFAULT_CHAT_FRAME:AddMessage("|cffff0000Error: OGRH_RGO requires OGRH_Core to be loaded first!|r")
  return
end

-- Module registration
OGRH.RegisterModule({
  id = "rgo",
  name = "Raid Group Organization",
  description = "Manage raid composition and slot priority assignments"
})

-- ========================================
-- SAVED VARIABLES INITIALIZATION
-- ========================================

function OGRH.EnsureRGOSV()
  OGRH.EnsureSV()
  
  if not OGRH_SV.rgo then
    OGRH_SV.rgo = {
      currentRaidSize = "40",
      raidSizes = {
        ["10"] = {},
        ["20"] = {},
        ["40"] = {}
      }
    }
    
    -- Initialize priorities for each raid size
    for _, size in ipairs({"10", "20", "40"}) do
      OGRH_SV.rgo.raidSizes[size] = {}
      for i = 1, 8 do
        OGRH_SV.rgo.raidSizes[size][i] = {}
        for j = 1, 5 do
          OGRH_SV.rgo.raidSizes[size][i][j] = {class = nil, role = nil}
        end
      end
    end
  end
  
  -- Ensure raidSizes exists
  if not OGRH_SV.rgo.raidSizes then
    OGRH_SV.rgo.raidSizes = {
      ["10"] = {},
      ["20"] = {},
      ["40"] = {}
    }
  end
  
  -- Ensure all raid sizes are initialized
  for _, size in ipairs({"10", "20", "40"}) do
    if not OGRH_SV.rgo.raidSizes[size] then
      OGRH_SV.rgo.raidSizes[size] = {}
    end
    for i = 1, 8 do
      if not OGRH_SV.rgo.raidSizes[size][i] then
        OGRH_SV.rgo.raidSizes[size][i] = {}
      end
      for j = 1, 5 do
        if not OGRH_SV.rgo.raidSizes[size][i][j] then
          OGRH_SV.rgo.raidSizes[size][i][j] = {class = nil, role = nil}
        end
      end
    end
  end
  
  -- Migration: convert old format to new format
  if OGRH_SV.rgo.slotPriorities then
    OGRH_SV.rgo.raidSizes["40"] = OGRH_SV.rgo.slotPriorities
    OGRH_SV.rgo.slotPriorities = nil
    OGRH_SV.rgo.currentRaidSize = "40"
  end
  
  -- Ensure currentRaidSize exists
  if not OGRH_SV.rgo.currentRaidSize then
    OGRH_SV.rgo.currentRaidSize = "40"
  end
  
  -- Clean up invalid role flags (migration/validation)
  OGRH.CleanupInvalidRoleFlags()
end

-- Clean up any invalid role flags that don't match what the UI allows
function OGRH.CleanupInvalidRoleFlags()
  if not OGRH_SV.rgo or not OGRH_SV.rgo.raidSizes then
    return
  end
  
  -- Define valid roles for each class (must match UI)
  local validRoles = {
    DRUID = {Tanks = true, Healers = true, Melee = true, Ranged = true},
    SHAMAN = {Tanks = true, Healers = true, Melee = true, Ranged = true},
    WARRIOR = {Tanks = true, Melee = true},
    PALADIN = {Tanks = true, Healers = true, Melee = true},
    HUNTER = {Melee = true, Ranged = true},
    PRIEST = {Healers = true, Ranged = true},
    MAGE = {},
    WARLOCK = {},
    ROGUE = {}
  }
  
  local cleanupCount = 0
  
  for size, groups in pairs(OGRH_SV.rgo.raidSizes) do
    for groupNum = 1, 8 do
      if groups[groupNum] then
        for slotNum = 1, 5 do
          local slotData = groups[groupNum][slotNum]
          if slotData and slotData.priorityList and slotData.priorityRoles then
            -- Check each priority position
            for i, className in ipairs(slotData.priorityList) do
              if slotData.priorityRoles[i] then
                local classUpper = string.upper(className)
                local allowedRoles = validRoles[classUpper] or {}
                
                -- Remove any role flags that aren't valid for this class
                for roleName, roleValue in pairs(slotData.priorityRoles[i]) do
                  if roleValue and not allowedRoles[roleName] then
                    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[RGO Cleanup]|r Removing invalid role " .. roleName .. " from " .. className .. " in " .. size .. "man G" .. groupNum .. " S" .. slotNum .. " P" .. i)
                    slotData.priorityRoles[i][roleName] = nil
                    cleanupCount = cleanupCount + 1
                  end
                end
                
                -- If no valid roles remain, clear the entire role entry
                local hasAnyRole = false
                for roleName, roleValue in pairs(slotData.priorityRoles[i]) do
                  if roleValue then
                    hasAnyRole = true
                    break
                  end
                end
                if not hasAnyRole then
                  slotData.priorityRoles[i] = nil
                end
              end
            end
          end
        end
      end
    end
  end
  
  if cleanupCount > 0 then
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[RGO]|r Cleaned up " .. cleanupCount .. " invalid role flags")
  end
end

-- ========================================
-- LOCAL VARIABLES
-- ========================================

local RGOFrame = nil
local groupFrames = {} -- Store references to all group frames
local slotButtons = {} -- [groupNum][slotNum] = button

-- Class list for priority selection (alphabetically sorted)
local CLASSES = {
  "Druid", "Hunter", "Mage", "Paladin", "Priest",
  "Rogue", "Shaman", "Warlock", "Warrior"
}

-- Role list for priority selection
local ROLES = {
  "Tank", "Healer", "DPS", "Support", "Any"
}

-- Class colors (WoW standard)
local CLASS_COLORS = {
  ["Warrior"] = {r = 0.78, g = 0.61, b = 0.43},
  ["Paladin"] = {r = 0.96, g = 0.55, b = 0.73},
  ["Hunter"] = {r = 0.67, g = 0.83, b = 0.45},
  ["Rogue"] = {r = 1.00, g = 0.96, b = 0.41},
  ["Priest"] = {r = 1.00, g = 1.00, b = 1.00},
  ["Shaman"] = {r = 0.00, g = 0.44, b = 0.87},
  ["Mage"] = {r = 0.41, g = 0.80, b = 0.94},
  ["Warlock"] = {r = 0.58, g = 0.51, b = 0.79},
  ["Druid"] = {r = 1.00, g = 0.49, b = 0.04},
}

-- ========================================
-- CLASS PRIORITY DIALOG
-- ========================================

function OGRH.ShowRGOClassPriorityDialog(groupNum, slotNum)
  local currentSize = OGRH_SV.rgo.currentRaidSize
  local slotData = OGRH_SV.rgo.raidSizes[currentSize][groupNum][slotNum]
  
  -- Initialize priority list if it doesn't exist
  if not slotData.priorityList then
    slotData.priorityList = {}
  end
  
  -- Create or reuse frame
  if not OGRH_RGOClassPriorityFrame then
    local frame = OGST.CreateStandardWindow({
      name = "OGRH_RGOClassPriorityFrame",
      width = 500,
      height = 400,
      title = "Class Priority",
      closeButton = true,
      escapeCloses = true,
      closeOnNewWindow = false
    })
    
    -- Set higher strata to appear above RGO window
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    
    local content = frame.contentFrame
    
    -- Subtitle (shows group and slot info)
    local subtitle = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    subtitle:SetPoint("TOP", content, "TOP", 0, -5)
    subtitle:SetTextColor(0.7, 0.7, 0.7)
    frame.subtitle = subtitle
    
    -- Instructions
    local instructions = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    instructions:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -30)
    instructions:SetText("Set the order of class priority (duplicates allowed):")
    instructions:SetTextColor(0.8, 0.8, 0.8)
    
    -- Left column: Selected classes (priority order)
    local leftLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    leftLabel:SetPoint("TOPLEFT", instructions, "BOTTOMLEFT", 0, -10)
    leftLabel:SetText("Priority Order:")
    
    local leftListFrame, leftScrollFrame, leftScrollChild, leftScrollBar, leftContentWidth = 
      OGRH.CreateStyledScrollList(content, 330, 220, true)
    leftListFrame:SetPoint("TOPLEFT", leftLabel, "BOTTOMLEFT", 0, -5)
    frame.leftListFrame = leftListFrame
    frame.leftScrollChild = leftScrollChild
    frame.leftContentWidth = leftContentWidth
    
    -- Right column: Available classes
    local rightLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    rightLabel:SetPoint("TOPLEFT", leftLabel, "TOPLEFT", 340, 0)
    rightLabel:SetText("Available Classes:")
    
    local rightListFrame, rightScrollFrame, rightScrollChild, rightScrollBar, rightContentWidth = 
      OGRH.CreateStyledScrollList(content, 130, 220, true)
    rightListFrame:SetPoint("TOPLEFT", rightLabel, "BOTTOMLEFT", 0, -5)
    frame.rightListFrame = rightListFrame
    frame.rightScrollChild = rightScrollChild
    frame.rightContentWidth = rightContentWidth
    
    -- Save Button
    local saveBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    saveBtn:SetWidth(80)
    saveBtn:SetHeight(24)
    saveBtn:SetPoint("BOTTOMRIGHT", content, "BOTTOM", -5, 5)
    saveBtn:SetText("Save")
    OGRH.StyleButton(saveBtn)
    frame.saveBtn = saveBtn
    
    -- Cancel Button
    local cancelBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    cancelBtn:SetWidth(80)
    cancelBtn:SetHeight(24)
    cancelBtn:SetPoint("BOTTOMLEFT", content, "BOTTOM", 5, 5)
    cancelBtn:SetText("Cancel")
    OGRH.StyleButton(cancelBtn)
    cancelBtn:SetScript("OnClick", function() frame:Hide() end)
    
    OGRH_RGOClassPriorityFrame = frame
  end
  
  local frame = OGRH_RGOClassPriorityFrame
  
  -- Store context
  frame.groupNum = groupNum
  frame.slotNum = slotNum
  frame.slotData = slotData
  
  -- Update subtitle
  frame.subtitle:SetText("Group " .. groupNum .. " - Slot " .. slotNum)
  
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
    
    local priorityList = slotData.priorityList
    
    -- Render left list (selected classes with up/down/delete) - ALLOWS DUPLICATES
    local yOffset = 0
    for i, className in ipairs(priorityList) do
      local item = OGRH.CreateStyledListItem(frame.leftScrollChild, frame.leftContentWidth, OGRH.LIST_ITEM_HEIGHT, "Button")
      item:SetPoint("TOPLEFT", frame.leftScrollChild, "TOPLEFT", 0, -yOffset)
      
      -- Class name text
      local nameText = item:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      nameText:SetPoint("LEFT", item, "LEFT", 5, 0)
      nameText:SetJustifyH("LEFT")
      
      -- Add up/down/delete buttons
      do
        local capturedIndex = i
        local deleteBtn, downBtn, upBtn = OGRH.AddListItemButtons(
          item,
          i,
          table.getn(priorityList),
          function() -- Move up
            if capturedIndex > 1 then
              -- Swap class names
              local temp = priorityList[capturedIndex]
              priorityList[capturedIndex] = priorityList[capturedIndex - 1]
              priorityList[capturedIndex - 1] = temp
              
              -- Swap role flags
              if slotData.priorityRoles then
                local tempRoles = slotData.priorityRoles[capturedIndex]
                slotData.priorityRoles[capturedIndex] = slotData.priorityRoles[capturedIndex - 1]
                slotData.priorityRoles[capturedIndex - 1] = tempRoles
              end
              
              RefreshLists()
            end
          end,
          function() -- Move down
            if capturedIndex < table.getn(priorityList) then
              -- Swap class names
              local temp = priorityList[capturedIndex]
              priorityList[capturedIndex] = priorityList[capturedIndex + 1]
              priorityList[capturedIndex + 1] = temp
              
              -- Swap role flags
              if slotData.priorityRoles then
                local tempRoles = slotData.priorityRoles[capturedIndex]
                slotData.priorityRoles[capturedIndex] = slotData.priorityRoles[capturedIndex + 1]
                slotData.priorityRoles[capturedIndex + 1] = tempRoles
              end
              
              RefreshLists()
            end
          end,
          function() -- Delete
            table.remove(priorityList, capturedIndex)
            if slotData.priorityRoles then
              table.remove(slotData.priorityRoles, capturedIndex)
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
      local classColor = CLASS_COLORS[className] or {r = 1, g = 1, b = 1}
      nameText:SetTextColor(classColor.r, classColor.g, classColor.b)
      nameText:SetText(className)
      
      -- Add role checkboxes for classes that can fill multiple roles
      local classUpper = string.upper(className)
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
      end
      
      if table.getn(roles) > 0 then
        -- Initialize role flags if not present
        if not slotData.priorityRoles then
          slotData.priorityRoles = {}
        end
        if not slotData.priorityRoles[i] then
          slotData.priorityRoles[i] = {}
        end
        
        local roleFlags = slotData.priorityRoles[i]
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
              if not slotData.priorityRoles[capturedIndex] then
                slotData.priorityRoles[capturedIndex] = {}
              end
              slotData.priorityRoles[capturedIndex][capturedRole] = this:GetChecked() and true or nil
            end)
          end
          
          xOffset = xOffset + 50  -- Space between checkboxes
        end
      end
      
      table.insert(frame.leftItems, item)
      yOffset = yOffset + (OGRH.LIST_ITEM_HEIGHT + OGRH.LIST_ITEM_SPACING)
    end
    
    -- Update left scroll child height
    local leftHeight = table.getn(priorityList) * (OGRH.LIST_ITEM_HEIGHT + OGRH.LIST_ITEM_SPACING)
    if leftHeight < 1 then leftHeight = 1 end
    frame.leftScrollChild:SetHeight(leftHeight)
    
    -- Render right list (all classes always available - click to add, ALLOWS DUPLICATES)
    yOffset = 0
    for i, className in ipairs(CLASSES) do
      local item = OGRH.CreateStyledListItem(frame.rightScrollChild, frame.rightContentWidth, OGRH.LIST_ITEM_HEIGHT, "Button")
      item:SetPoint("TOPLEFT", frame.rightScrollChild, "TOPLEFT", 0, -yOffset)
      
      -- Class name text
      local nameText = item:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      nameText:SetPoint("LEFT", item, "LEFT", 5, 0)
      nameText:SetPoint("RIGHT", item, "RIGHT", -5, 0)
      nameText:SetJustifyH("LEFT")
      
      -- Set class-colored text
      local classColor = CLASS_COLORS[className] or {r = 1, g = 1, b = 1}
      nameText:SetTextColor(classColor.r, classColor.g, classColor.b)
      nameText:SetText(className)
      
      table.insert(frame.rightItems, item)
      
      -- Click to add to priority list (capture className)
      do
        local capturedClass = className
        item:SetScript("OnClick", function()
          table.insert(priorityList, capturedClass)
          RefreshLists()
        end)
      end
      yOffset = yOffset + (OGRH.LIST_ITEM_HEIGHT + OGRH.LIST_ITEM_SPACING)
    end
    
    -- Update right scroll child height
    local rightHeight = table.getn(CLASSES) * (OGRH.LIST_ITEM_HEIGHT + OGRH.LIST_ITEM_SPACING)
    if rightHeight < 1 then rightHeight = 1 end
    frame.rightScrollChild:SetHeight(rightHeight)
  end
  
  -- Save button handler
  frame.saveBtn:SetScript("OnClick", function()
    frame:Hide()
    OGRH.UpdateRGOSlotDisplay(groupNum, slotNum)
  end)
  
  -- Initial render
  RefreshLists()
  
  frame:Show()
end

-- ========================================
-- HELPER FUNCTIONS
-- ========================================

-- Determine if a group should be enabled for the current raid size
local function IsGroupEnabled(groupNum)
  local raidSize = tonumber(OGRH_SV.rgo.currentRaidSize) or 40
  
  if raidSize == 10 then
    return groupNum <= 2
  elseif raidSize == 20 then
    return groupNum <= 4
  else  -- 40
    return true
  end
end

-- ========================================
-- SLOT DISPLAY UPDATE
-- ========================================

function OGRH.UpdateRGOSlotDisplay(groupNum, slotNum)
  local button = slotButtons[groupNum] and slotButtons[groupNum][slotNum]
  if not button then return end
  
  -- Check if group is enabled for current raid size
  local groupEnabled = IsGroupEnabled(groupNum)
  
  if not groupEnabled then
    -- Disabled slot - show as unavailable
    button.text:SetText("Slot " .. slotNum)
    button.text:SetTextColor(0.3, 0.3, 0.3)
    return
  end
  
  local currentSize = OGRH_SV.rgo.currentRaidSize
  local slotData = OGRH_SV.rgo.raidSizes[currentSize][groupNum][slotNum]
  
  if slotData.priorityList and table.getn(slotData.priorityList) > 0 then
    -- Display first class in priority list with count if more than 1
    local firstClass = slotData.priorityList[1]
    local count = table.getn(slotData.priorityList)
    local classColor = CLASS_COLORS[firstClass] or {r = 1, g = 1, b = 1}
    
    local displayText = firstClass
    if count > 1 then
      displayText = firstClass .. " (+" .. (count - 1) .. ")"
    end
    
    button.text:SetText(displayText)
    button.text:SetTextColor(classColor.r, classColor.g, classColor.b)
  else
    -- Empty slot
    button.text:SetText("Slot " .. slotNum)
    button.text:SetTextColor(0.6, 0.6, 0.6)
  end
end

-- ========================================
-- LIST POPULATION
-- ========================================

local SLOT_HEIGHT = 15

local function PopulateList(parent, contentWidth, groupNumbers)
  local yOffset = 0
  
  for _, groupNum in ipairs(groupNumbers) do
    -- Add group header (not clickable)
    local headerItem = OGRH.CreateStyledListItem(parent, contentWidth, SLOT_HEIGHT, "Frame")
    headerItem:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -yOffset)
    headerItem.text = headerItem:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    headerItem.text:SetPoint("LEFT", headerItem, "LEFT", 5, 0)
    headerItem.text:SetText("Group " .. groupNum)
    headerItem.text:SetTextColor(1, 0.82, 0)
    
    -- Different background color for headers
    OGRH.SetListItemColor(headerItem, 0.2, 0.25, 0.25, 0.8)
    
    yOffset = yOffset + SLOT_HEIGHT + OGRH.LIST_ITEM_SPACING
    
    -- Determine if this group should be enabled
    local groupEnabled = IsGroupEnabled(groupNum)
    
    -- Add 5 slot items (clickable)
    for slotNum = 1, 5 do
      local slotItem = OGRH.CreateStyledListItem(parent, contentWidth, SLOT_HEIGHT, "Button")
      slotItem:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -yOffset)
      slotItem.text = slotItem:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      slotItem.text:SetPoint("LEFT", slotItem, "LEFT", 15, 0)
      slotItem.text:SetText("  Slot " .. slotNum)
      
      -- Store reference data
      slotItem.groupNum = groupNum
      slotItem.slotNum = slotNum
      
      -- Store in slotButtons for updates
      if not slotButtons[groupNum] then
        slotButtons[groupNum] = {}
      end
      slotButtons[groupNum][slotNum] = slotItem
      
      -- Apply enabled/disabled state
      if groupEnabled then
        slotItem:Enable()
        slotItem.text:SetTextColor(0.6, 0.6, 0.6)
        OGRH.SetListItemColor(slotItem, 0.2, 0.2, 0.2, 0.5)
        
        -- Click handler (OGST CreateStyledListItem already handles hover effects)
        slotItem:SetScript("OnClick", function()
          OGRH.ShowRGOClassPriorityDialog(this.groupNum, this.slotNum)
        end)
        
        -- Register for drag and drop (both left and right buttons)
        slotItem:RegisterForDrag("LeftButton", "RightButton")
        
        -- OnDragStart
        slotItem:SetScript("OnDragStart", function()
          if not OGRH_SV.rgo.dragSource then
            local button = arg1 -- "LeftButton" or "RightButton"
            local isCopy = (button == "RightButton")
            
            OGRH_SV.rgo.dragSource = {
              groupNum = this.groupNum,
              slotNum = this.slotNum,
              isCopy = isCopy
            }
            
            if isCopy then
              OGRH.SetListItemColor(this, 0.0, 0.4, 0.4, 0.8) -- Cyan highlight for copy
            else
              OGRH.SetListItemColor(this, 0.4, 0.4, 0.0, 0.8) -- Yellow highlight for swap
            end
            
            -- Show drag cursor
            if RGOFrame and RGOFrame.dragCursor and RGOFrame.dragCursorText then
              local label = isCopy and "[COPY] " or "[SWAP] "
              RGOFrame.dragCursorText:SetText(label .. "G" .. this.groupNum .. " S" .. this.slotNum)
              RGOFrame.dragCursor:Show()
            end
          end
        end)
        
        -- OnDragStop
        slotItem:SetScript("OnDragStop", function()
          -- Hide drag cursor
          if RGOFrame and RGOFrame.dragCursor then
            RGOFrame.dragCursor:Hide()
          end
          
          if OGRH_SV.rgo.dragSource then
            -- Check if we're over a valid drop target
            local mouseX, mouseY = GetCursorPosition()
            local scale = UIParent:GetEffectiveScale()
            mouseX = mouseX / scale
            mouseY = mouseY / scale
            
            local dropTarget = nil
            for gNum, slots in pairs(slotButtons) do
              for sNum, btn in pairs(slots) do
                if btn:IsVisible() and btn:IsEnabled() then
                  local left, bottom, width, height = btn:GetLeft(), btn:GetBottom(), btn:GetWidth(), btn:GetHeight()
                  if left and bottom and mouseX >= left and mouseX <= (left + width) and 
                     mouseY >= bottom and mouseY <= (bottom + height) then
                    dropTarget = {groupNum = gNum, slotNum = sNum}
                    break
                  end
                end
              end
              if dropTarget then break end
            end
            
            if dropTarget and (dropTarget.groupNum ~= OGRH_SV.rgo.dragSource.groupNum or 
                              dropTarget.slotNum ~= OGRH_SV.rgo.dragSource.slotNum) then
              local currentSize = OGRH_SV.rgo.currentRaidSize
              local sourceData = OGRH_SV.rgo.raidSizes[currentSize][OGRH_SV.rgo.dragSource.groupNum][OGRH_SV.rgo.dragSource.slotNum]
              local destData = OGRH_SV.rgo.raidSizes[currentSize][dropTarget.groupNum][dropTarget.slotNum]
              
              if OGRH_SV.rgo.dragSource.isCopy then
                -- Copy source to destination (destination loses its data)
                destData.priorityList = {}
                destData.priorityRoles = {}
                
                -- Deep copy the source data
                if sourceData.priorityList then
                  for i, className in ipairs(sourceData.priorityList) do
                    destData.priorityList[i] = className
                  end
                end
                
                if sourceData.priorityRoles then
                  for i, roles in pairs(sourceData.priorityRoles) do
                    destData.priorityRoles[i] = {}
                    for roleName, roleValue in pairs(roles) do
                      destData.priorityRoles[i][roleName] = roleValue
                    end
                  end
                end
                
                -- Update destination display only
                OGRH.UpdateRGOSlotDisplay(dropTarget.groupNum, dropTarget.slotNum)
              else
                -- Swap the priorities
                local tempList = sourceData.priorityList
                local tempRoles = sourceData.priorityRoles
                sourceData.priorityList = destData.priorityList
                sourceData.priorityRoles = destData.priorityRoles
                destData.priorityList = tempList
                destData.priorityRoles = tempRoles
                
                -- Update both displays
                OGRH.UpdateRGOSlotDisplay(OGRH_SV.rgo.dragSource.groupNum, OGRH_SV.rgo.dragSource.slotNum)
                OGRH.UpdateRGOSlotDisplay(dropTarget.groupNum, dropTarget.slotNum)
              end
            end
            
            -- Clear drag state and restore color
            OGRH.SetListItemColor(this, 0.2, 0.2, 0.2, 0.5)
            OGRH_SV.rgo.dragSource = nil
          end
        end)
      else
        slotItem:Disable()
        slotItem.text:SetTextColor(0.3, 0.3, 0.3)
        OGRH.SetListItemColor(slotItem, 0.15, 0.15, 0.15, 0.3)
        slotItem:SetScript("OnClick", nil)
      end
      
      yOffset = yOffset + SLOT_HEIGHT + OGRH.LIST_ITEM_SPACING
      
      -- Update display from saved data
      OGRH.UpdateRGOSlotDisplay(groupNum, slotNum)
    end
  end
end

-- ========================================
-- MAIN WINDOW CREATION
-- ========================================

function OGRH.ShowRGOWindow()
  OGRH.EnsureRGOSV()
  
  if RGOFrame then
    RGOFrame:Show()
    return
  end
  
  -- Calculate window dimensions
  local columnWidth = 200
  local listHeight = 417
  local windowWidth = 440
  local windowHeight = 482
  
  -- Create standard window
  RGOFrame = OGRH.CreateStandardWindow({
    name = "OGRH_RGO_Window",
    width = windowWidth,
    height = windowHeight,
    title = "Raid Group Organization",
    closeButton = true,
    escapeCloses = true,
    closeOnNewWindow = true
  })
  
  local content = RGOFrame.contentFrame
  
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
  
  RGOFrame.dragCursor = dragCursor
  RGOFrame.dragCursorText = dragCursorText
  
  -- Track last cursor position to avoid unnecessary updates
  dragCursor.lastX = 0
  dragCursor.lastY = 0
  
  -- Update drag cursor position on frame update
  dragCursor:SetScript("OnUpdate", function()
    if dragCursor:IsShown() then
      local scale = UIParent:GetEffectiveScale()
      local x, y = GetCursorPosition()
      x = x / scale
      y = y / scale
      
      -- Only update if position changed (avoid spamming SetPoint)
      if x ~= dragCursor.lastX or y ~= dragCursor.lastY then
        dragCursor:ClearAllPoints()
        dragCursor:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
        dragCursor.lastX = x
        dragCursor.lastY = y
      end
    end
  end)
  
  -- Raid size selector button
  local sizeButton = CreateFrame("Button", nil, RGOFrame)
  sizeButton:SetWidth(80)
  sizeButton:SetHeight(24)
  sizeButton:SetPoint("TOPLEFT", RGOFrame, "TOPLEFT", 10, -8)
  OGRH.StyleButton(sizeButton)
  
  sizeButton.text = sizeButton:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  sizeButton.text:SetPoint("CENTER", sizeButton, "CENTER", 0, 0)
  sizeButton.text:SetText(OGRH_SV.rgo.currentRaidSize .. " Man")
  
  sizeButton:SetScript("OnClick", function()
    local menu = OGRH.CreateStandardMenu({
      name = "OGRH_RGO_SizeMenu",
      width = 100
    })
    
    for _, size in ipairs({"10", "20", "40"}) do
      local currentSize = size  -- Create local copy for closure
      menu:AddItem({
        text = currentSize .. " Man",
        onClick = function()
          OGRH_SV.rgo.currentRaidSize = currentSize
          sizeButton.text:SetText(currentSize .. " Man")
          
          -- Refresh all slots (display and enabled state)
          for groupNum = 1, 8 do
            local groupEnabled = IsGroupEnabled(groupNum)
            for slotNum = 1, 5 do
              local slotItem = slotButtons[groupNum] and slotButtons[groupNum][slotNum]
              if slotItem then
                -- Update enabled/disabled state
                if groupEnabled then
                  slotItem:Enable()
                  slotItem.text:SetTextColor(0.6, 0.6, 0.6)
                  OGRH.SetListItemColor(slotItem, 0.2, 0.2, 0.2, 0.5)
                  slotItem:SetScript("OnClick", function()
                    OGRH.ShowRGOClassPriorityDialog(this.groupNum, this.slotNum)
                  end)
                else
                  slotItem:Disable()
                  slotItem.text:SetTextColor(0.3, 0.3, 0.3)
                  OGRH.SetListItemColor(slotItem, 0.15, 0.15, 0.15, 0.3)
                  slotItem:SetScript("OnClick", nil)
                end
                
                -- Update display
                OGRH.UpdateRGOSlotDisplay(groupNum, slotNum)
              end
            end
          end
        end
      })
    end
    
    menu:Finalize()
    menu:SetPoint("TOPLEFT", this, "BOTTOMLEFT", 0, 0)
    menu:Show()
  end)
  
  -- Create left column using OGST scroll list (Groups 1, 3, 5, 7)
  local leftOuter, leftScroll, leftChild, leftBar, leftWidth = OGRH.CreateStyledScrollList(content, columnWidth, listHeight, true)
  leftOuter:SetPoint("TOPLEFT", content, "TOPLEFT", 5, -5)
  
  -- Create right column using OGST scroll list (Groups 2, 4, 6, 8)
  local rightOuter, rightScroll, rightChild, rightBar, rightWidth = OGRH.CreateStyledScrollList(content, columnWidth, listHeight, true)
  rightOuter:SetPoint("TOPRIGHT", content, "TOPRIGHT", -5, -5)
  
  -- Populate lists
  PopulateList(leftChild, leftWidth, {1, 3, 5, 7})
  PopulateList(rightChild, rightWidth, {2, 4, 6, 8})
  
  RGOFrame:Show()
end

-- ========================================
-- AUTO-SORT FUNCTIONALITY
-- ========================================

-- Timer for auto-sort
local autoSortTimer = 0
local AUTO_SORT_INTERVAL = 1 -- seconds

-- Get current raid size based on number of players
local function GetCurrentRaidSize()
  local numRaid = GetNumRaidMembers()
  if numRaid == 0 then
    return nil
  elseif numRaid <= 10 then
    return "10"
  elseif numRaid <= 20 then
    return "20"
  else
    return "40"
  end
end

-- Get all current raid members with their info
local function GetRaidRoster()
  local roster = {}
  local numRaid = GetNumRaidMembers()
  
  if numRaid == 0 then
    return roster
  end
  
  for i = 1, numRaid do
    local name, rank, subgroup, level, class, fileName, zone, online, isDead = GetRaidRosterInfo(i)
    if name then
      -- Get player's role from RolesUI
      local playerRole = nil
      if OGRH_SV and OGRH_SV.roles and OGRH_SV.roles[name] then
        playerRole = OGRH_SV.roles[name] -- "TANKS", "HEALERS", "MELEE", or "RANGED"
      end
      
      table.insert(roster, {
        index = i,
        name = name,
        class = fileName, -- English class name
        subgroup = subgroup,
        online = online,
        isDead = isDead,
        role = playerRole
      })
    end
  end
  
  return roster
end

-- Get priority configuration for a specific group and raid size
local function GetGroupPriorities(raidSize, groupNum)
  if not OGRH_SV.rgo or not OGRH_SV.rgo.raidSizes then
    return {}
  end
  
  local sizeConfig = OGRH_SV.rgo.raidSizes[raidSize]
  if not sizeConfig or not sizeConfig[groupNum] then
    return {}
  end
  
  local priorities = {}
  for slot = 1, 5 do
    local slotConfig = sizeConfig[groupNum][slot]
    if slotConfig and slotConfig.priorityList then
      priorities[slot] = {
        priorityList = slotConfig.priorityList,
        priorityRoles = slotConfig.priorityRoles or {}
      }
    end
  end
  
  return priorities
end

-- Calculate a score for how well a player fits a slot's priorities
local function CalculateFitScore(player, slotPriority)
  if not slotPriority or not slotPriority.priorityList then
    return 0
  end
  
  -- Check all positions in priority list to find best match (including duplicate classes with different roles)
  for i, className in ipairs(slotPriority.priorityList) do
    -- Compare uppercase versions for case-insensitive matching
    if string.upper(player.class) == string.upper(className) then
      -- Found class in priority list
      -- Now check if player's role matches the allowed roles for this class position
      local priorityRoles = (slotPriority.priorityRoles and slotPriority.priorityRoles[i]) or {}
      
      -- If no roles are specified for this class position, accept any role
      local hasAnyRole = priorityRoles.Tanks or priorityRoles.Healers or priorityRoles.Melee or priorityRoles.Ranged or priorityRoles.DPS or priorityRoles.Support or priorityRoles.Any
      
      if not hasAnyRole then
        -- No role restrictions, class match is enough
        return 110 - (i * 10)
      end
      
      -- Check if player's role matches allowed roles
      if player.role then
        local roleMatches = false
        if player.role == "TANKS" and priorityRoles.Tanks then
          roleMatches = true
        elseif player.role == "HEALERS" and priorityRoles.Healers then
          roleMatches = true
        elseif player.role == "MELEE" and (priorityRoles.Melee or priorityRoles.DPS) then
          roleMatches = true
        elseif player.role == "RANGED" and (priorityRoles.Ranged or priorityRoles.DPS) then
          roleMatches = true
        end
        
        if priorityRoles.Any then
          roleMatches = true
        end
        
        if roleMatches then
          -- Class and role both match - return this score
          return 110 - (i * 10)
        end
        -- Class matches but role doesn't - continue checking other positions
      end
      -- Player has no assigned role but slot has role requirements - continue checking
    end
  end
  
  return 0 -- Not in priority list or no matching role found
end

-- Find best slot for a player in a group
local function FindBestSlotForPlayer(player, groupPriorities, currentPlayers)
  local bestSlot = nil
  local bestScore = -1
  
  for slot = 1, 5 do
    local slotPriority = groupPriorities[slot]
    if slotPriority then
      local score = CalculateFitScore(player, slotPriority)
      
      -- Check if slot is already filled by someone
      local slotFilled = false
      for _, p in ipairs(currentPlayers) do
        if p.assignedSlot == slot then
          slotFilled = true
          break
        end
      end
      
      if not slotFilled and score > bestScore then
        bestScore = score
        bestSlot = slot
      end
    end
  end
  
  return bestSlot, bestScore
end

-- Get players currently in a group
local function GetGroupPlayers(roster, groupNum)
  local players = {}
  for _, player in ipairs(roster) do
    if player.subgroup == groupNum then
      table.insert(players, player)
    end
  end
  return players
end

-- Evaluate how well a group matches its priorities
local function EvaluateGroupFit(roster, raidSize, groupNum)
  local priorities = GetGroupPriorities(raidSize, groupNum)
  local players = GetGroupPlayers(roster, groupNum)
  
  -- Check if this group has ANY priorities configured
  local hasPriorities = false
  for slot = 1, 5 do
    if priorities[slot] and priorities[slot].priorityList and table.getn(priorities[slot].priorityList) > 0 then
      hasPriorities = true
      break
    end
  end
  
  local totalScore = 0
  local mismatches = {}
  
  -- If group has no priorities configured, all players are mismatches
  if not hasPriorities then
    for _, player in ipairs(players) do
      table.insert(mismatches, player)
    end
    return 0, mismatches
  end
  
  -- For each player in the group, see how well they fit any slot
  for _, player in ipairs(players) do
    local bestScore = 0
    for slot = 1, 5 do
      local slotPriority = priorities[slot]
      if slotPriority then
        local score = CalculateFitScore(player, slotPriority)
        if score > bestScore then
          bestScore = score
        end
      end
    end
    
    totalScore = totalScore + bestScore
    
    if bestScore == 0 then
      -- This player doesn't fit any priority in this group
      table.insert(mismatches, player)
    end
  end
  
  return totalScore, mismatches
end

-- Find best group for a player (including full groups for potential swaps)
local function FindBestGroupForPlayer(player, roster, raidSize, maxGroupNum)
  local bestGroup = player.subgroup
  local bestScore = -1
  
  for groupNum = 1, maxGroupNum do
    -- Skip completed groups when searching for best placement
    if not OGRH_SV.rgo.completedGroups or not OGRH_SV.rgo.completedGroups[groupNum] then
      local priorities = GetGroupPriorities(raidSize, groupNum)
      local groupPlayers = GetGroupPlayers(roster, groupNum)
      
      -- Check if this group has ANY priorities configured
      local hasPriorities = false
      for slot = 1, 5 do
        if priorities[slot] and priorities[slot].priorityList and table.getn(priorities[slot].priorityList) > 0 then
          hasPriorities = true
          break
        end
      end
      
      -- Skip groups with no priorities configured
      if hasPriorities then
        -- Calculate how well this player fits this group
        for slot = 1, 5 do
          local slotPriority = priorities[slot]
          if slotPriority then
            local score = CalculateFitScore(player, slotPriority)
            if score > bestScore then
              bestScore = score
              bestGroup = groupNum
            end
          end
        end
      end
    end
  end
  
  return bestGroup, bestScore
end

-- Debug window for auto-sort output
local debugWindow = nil
local debugText = ""

local function DebugLog(msg)
  -- Debug output disabled
end

local function CreateDebugWindow()
  if debugWindow then
    -- Window exists, just show it and update text
    if debugWindow.textBox then
      debugWindow.textBox:SetText(debugText)
    end
    debugWindow:Show()
    return
  end
  
  debugWindow = OGRH.CreateStandardWindow({
    name = "OGRH_RGO_DebugWindow",
    width = 600,
    height = 500,
    title = "RGO Auto-Sort Debug Log",
    closeButton = true,
    escapeCloses = true,
    closeOnNewWindow = false
  })
  
  -- CreateScrollingTextBox returns: backdrop, editBox, scrollFrame, scrollBar
  local textBoxFrame, editBox, scrollFrame, scrollBar = OGRH.CreateScrollingTextBox(debugWindow.contentFrame, 580, 450)
  if textBoxFrame then
    textBoxFrame:SetPoint("TOPLEFT", debugWindow.contentFrame, "TOPLEFT", 5, -5)
  end
  
  debugWindow.textBox = editBox
  debugWindow.scrollFrame = scrollFrame
  debugWindow.scrollBar = scrollBar
  
  -- Set initial text if we have any
  if editBox and debugText and debugText ~= "" then
    editBox:SetText(debugText)
  end
  
  debugWindow:Show()
end

-- Perform one iteration of auto-sort
function OGRH.PerformAutoSort()
  local raidSize = GetCurrentRaidSize()
  if not raidSize then
    return -- Not in a raid
  end
  
  -- Check if we're the designated raid admin (not just any leader/assistant)
  if not OGRH.IsRaidAdmin() then
    return -- Only raid admin can run auto-sort
  end
  
  -- Disable auto-sort IMMEDIATELY to prevent re-runs during execution
  OGRH_SV.rgo.autoSortEnabled = false
  
  -- Build the roster
  if not OGRH_SV.roles then OGRH_SV.roles = {} end
  local roster = GetRaidRoster()
  if table.getn(roster) == 0 then
    return
  end
  
  -- Determine max groups based on raid size
  local maxGroups = 2
  if raidSize == "20" then
    maxGroups = 4
  elseif raidSize == "40" then
    maxGroups = 8
  end
  
  -- Skip debug output
  
  -- PHASE 1: Plan ALL group assignments (build target state)
  local targetState = {} -- targetState[groupNum][slotNum] = playerName
  local assignedPlayers = {} -- assignedPlayers[playerName] = {group, slot}
  
  for groupNum = 1, maxGroups do
    targetState[groupNum] = {}
    local priorities = GetGroupPriorities(raidSize, groupNum)
    
    -- Check if this group has priorities
    local hasPriorities = false
    for slot = 1, 5 do
      if priorities[slot] and priorities[slot].priorityList and table.getn(priorities[slot].priorityList) > 0 then
        hasPriorities = true
        break
      end
    end
    
    if hasPriorities then
      DebugLog("Planning group " .. groupNum)
      
      -- Debug: show what priorities we have
      local priorityCount = 0
      for slot = 1, 5 do
        if priorities[slot] then
          priorityCount = priorityCount + 1
        end
      end
      DebugLog("  Found " .. priorityCount .. " configured slots")
      
      -- For each slot, find the best available player
      for slot = 1, 5 do
        local slotPriority = priorities[slot]
        if slotPriority and slotPriority.priorityList and table.getn(slotPriority.priorityList) > 0 then
          DebugLog("  Slot " .. slot .. " has " .. table.getn(slotPriority.priorityList) .. " priorities")
          
          -- Debug: show what's in the priority list and roles
          for pIdx = 1, table.getn(slotPriority.priorityList) do
            local pClass = slotPriority.priorityList[pIdx]
            local pRoles = slotPriority.priorityRoles and slotPriority.priorityRoles[pIdx]
            if pRoles then
              local roleStr = ""
              for rName, rVal in pairs(pRoles) do
                if rVal then
                  roleStr = roleStr .. rName .. " "
                end
              end
              DebugLog("    " .. pIdx .. ": " .. pClass .. " [" .. roleStr .. "]")
            else
              DebugLog("    " .. pIdx .. ": " .. pClass .. " [no roles]")
            end
          end
          
          local bestPlayer = nil
          local bestScore = -1
          
          -- Search entire raid for best fit
          for _, player in ipairs(roster) do
            if not assignedPlayers[player.name] then
              local enableDebug = (groupNum == 5 and slot == 2) -- Debug G5 S2
              local score = CalculateFitScore(player, slotPriority, enableDebug)
              
              -- Extra debug for Group 5 Slot 2 - show ALL healers being evaluated
              if groupNum == 5 and slot == 2 and player.role == "HEALERS" then
                DebugLog("    Evaluating " .. player.name .. " (" .. player.class .. "/" .. (player.role or "NO ROLE") .. ") = score " .. score)
              end
              
              if score > bestScore then
                bestScore = score
                bestPlayer = player
              end
            end
          end
          
          if bestPlayer and bestScore > 0 then
            targetState[groupNum][slot] = bestPlayer.name
            assignedPlayers[bestPlayer.name] = {group = groupNum, slot = slot, player = bestPlayer}
            DebugLog("  G" .. groupNum .. " S" .. slot .. ": " .. bestPlayer.name .. " (score " .. bestScore .. ")")
          else
            DebugLog("  G" .. groupNum .. " S" .. slot .. ": No suitable player found")
          end
        else
          if slotPriority then
            DebugLog("  Slot " .. slot .. " has empty priority list")
          else
            DebugLog("  Slot " .. slot .. " not configured")
          end
        end
      end
    end
  end
  
  -- PHASE 2: Build move queue to achieve target state
  DebugLog("")
  DebugLog("Building move queue...")
  local moveQueue = {}
  
  -- First pass: identify all players that need to move
  for playerName, assignment in pairs(assignedPlayers) do
    local player = assignment.player
    if player.subgroup ~= assignment.group then
      table.insert(moveQueue, {
        playerName = playerName,
        playerIndex = player.index,
        fromGroup = player.subgroup,
        toGroup = assignment.group,
        slot = assignment.slot
      })
      DebugLog("  " .. playerName .. ": G" .. player.subgroup .. " -> G" .. assignment.group)
    else
      DebugLog("  " .. playerName .. " already in G" .. assignment.group)
    end
  end
  
  if table.getn(moveQueue) == 0 then
    DebugLog("")
    DebugLog("Raid composition is already optimal!")
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[RGO]|r Raid composition is already optimal!")
    return
  end
  
  DebugLog("")
  DebugLog("Executing " .. table.getn(moveQueue) .. " moves...")
  DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[RGO]|r Executing " .. table.getn(moveQueue) .. " moves - see debug window for details")
  
  -- PHASE 3: Execute the queue with delays
  local moveDelay = ((OGRH_SV.rgo and OGRH_SV.rgo.sortSpeed) or 250) / 1000 -- Default 250ms, configurable via /ogrh sortspeed
  local moveIndex = 1
  local moveFrame = CreateFrame("Frame")
  moveFrame.timer = 0
  moveFrame.queue = moveQueue
  
  moveFrame:SetScript("OnUpdate", function()
    this.timer = this.timer + arg1
    if this.timer >= moveDelay then
      this.timer = 0
      
      if moveIndex <= table.getn(this.queue) then
        local move = this.queue[moveIndex]
        
        -- Find someone in the target group to swap with, or just move if there's room
        local targetGroupPlayers = GetGroupPlayers(GetRaidRoster(), move.toGroup)
        
        if table.getn(targetGroupPlayers) < 5 then
          -- Group has room, just move
          DebugLog("Move " .. moveIndex .. ": " .. move.playerName .. " -> Group " .. move.toGroup)
          SetRaidSubgroup(move.playerIndex, move.toGroup)
        else
          -- Group is full, need to swap with someone
          -- Priority 1: Find a player who doesn't belong in this group AND has no assignment anywhere
          -- Priority 2: Find a player who doesn't belong in this group but has an assignment elsewhere (will be moved later)
          local swapTarget = nil
          local swapTargetHasAssignment = false
          
          for _, player in ipairs(targetGroupPlayers) do
            local shouldBeHere = false
            for slot, name in pairs(targetState[move.toGroup]) do
              if name == player.name then
                shouldBeHere = true
                break
              end
            end
            
            if not shouldBeHere then
              -- Check if this player has an assignment in ANY other group
              local hasOtherAssignment = false
              for gNum, groupSlots in pairs(targetState) do
                if gNum ~= move.toGroup then
                  for slot, name in pairs(groupSlots) do
                    if name == player.name then
                      hasOtherAssignment = true
                      break
                    end
                  end
                  if hasOtherAssignment then break end
                end
              end
              
              -- Prefer swapping with someone who has no assignment (true "extra")
              if not hasOtherAssignment then
                swapTarget = player
                swapTargetHasAssignment = false
                break -- This is ideal, use it
              elseif not swapTarget then
                -- Fallback: someone who will be moved later
                swapTarget = player
                swapTargetHasAssignment = true
              end
            end
          end
          
          if swapTarget then
            local assignmentNote = swapTargetHasAssignment and " (will be moved later)" or " (no assignment)"
            DebugLog("Swap " .. moveIndex .. ": " .. move.playerName .. " <-> " .. swapTarget.name .. assignmentNote)
            SwapRaidSubgroup(move.playerIndex, swapTarget.index)
          else
            -- All players in target group are supposed to be there - this shouldn't happen
            DebugLog("ERROR: Can't swap " .. move.playerName .. " - all players in G" .. move.toGroup .. " are assigned there!")
          end
        end
        
        moveIndex = moveIndex + 1
      else
        -- All moves complete
        DebugLog("")
        DebugLog("=== AUTO-SORT COMPLETE ===")
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[RGO]|r Auto-sort completed! Raid composition optimized.")
        this:SetScript("OnUpdate", nil)
      end
    end
  end)
end

-- Create hidden frame for OnUpdate timer
local autoSortFrame = CreateFrame("Frame")
-- DISABLED: Timer causing endless loop
-- autoSortFrame:SetScript("OnUpdate", function()
--   if not OGRH_SV.rgo or not OGRH_SV.rgo.autoSortEnabled then
--     return
--   end
--   
--   if not this.timer then
--     this.timer = 0
--     DEFAULT_CHAT_FRAME:AddMessage("|cffff00ff[RGO]|r AutoSort timer initialized")
--   end
--   
--   this.timer = this.timer + arg1
--   if this.timer >= AUTO_SORT_INTERVAL then
--     this.timer = 0
--     DEFAULT_CHAT_FRAME:AddMessage("|cffff00ff[RGO]|r Timer triggered, calling PerformAutoSort")
--     OGRH.PerformAutoSort()
--   end
-- end)

-- ========================================
-- SHUFFLE RAID (TESTING)
-- ========================================

function OGRH.ShuffleRaid(delayMs)
  local numRaid = GetNumRaidMembers()
  if numRaid == 0 then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[RGO]|r You must be in a raid to shuffle.")
    return
  end
  
  -- Check if we're raid leader/assistant
  if not OGRH.IsRaidAdmin() then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[RGO]|r You must be raid leader or assistant to shuffle.")
    return
  end
  
  local maxSwaps = 20
  local swapDelay = (delayMs or 500) / 1000 -- convert ms to seconds, default 500ms
  local totalTime = maxSwaps * swapDelay
  DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[RGO]|r Shuffling raid - " .. maxSwaps .. " random swaps at " .. (swapDelay * 1000) .. "ms intervals (total: " .. totalTime .. "s)...")
  
  local swapCount = 0
  local shuffleTimer = 0
  
  local shuffleFrame = CreateFrame("Frame")
  shuffleFrame:SetScript("OnUpdate", function()
    shuffleTimer = shuffleTimer + arg1
    
    if shuffleTimer >= swapDelay then
      shuffleTimer = 0
      swapCount = swapCount + 1
      
      if swapCount > maxSwaps then
        -- Done shuffling
        this:SetScript("OnUpdate", nil)
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[RGO]|r Shuffle complete!")
        return
      end
      
      -- Pick two random players
      local player1Index = math.random(1, numRaid)
      local player2Index = math.random(1, numRaid)
      
      -- Make sure they're different players and in different groups
      local attempts = 0
      while (player1Index == player2Index or GetRaidRosterInfo(player1Index) == GetRaidRosterInfo(player2Index)) and attempts < 50 do
        player2Index = math.random(1, numRaid)
        attempts = attempts + 1
      end
      
      if attempts >= 50 then
        -- Couldn't find valid swap, skip this one
        return
      end
      
      local name1, _, subgroup1 = GetRaidRosterInfo(player1Index)
      local name2, _, subgroup2 = GetRaidRosterInfo(player2Index)
      
      if name1 and name2 and subgroup1 ~= subgroup2 then
        -- Perform the swap
        SwapRaidSubgroup(player1Index, player2Index)
      end
    end
  end)
end

-- ========================================
-- SLASH COMMAND
-- ========================================

SLASH_OGRHRGO1 = "/rgo"
SlashCmdList["OGRHRGO"] = function(msg)
  OGRH.ShowRGOWindow()
end
