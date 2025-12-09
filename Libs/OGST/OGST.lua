-- OGST.lua - OG Standard Templates Library
-- Reusable UI template functions for World of Warcraft 1.12.1 addons
-- Version 1.0.0
-- 
-- This library provides standardized UI components and helper functions
-- that can be used across multiple addons for consistent styling and behavior.

-- Create global namespace
if not OGST then
  OGST = {}
  OGST.version = "1.0.0"
end

-- ============================================
-- CONSTANTS
-- ============================================

-- Standard list item colors
OGST.LIST_COLORS = {
  SELECTED = {r = 0.2, g = 0.4, b = 0.2, a = 0.8},    -- Green highlight for selected items
  INACTIVE = {r = 0.2, g = 0.2, b = 0.2, a = 0.5},    -- Gray for normal/inactive items
  HOVER = {r = 0.2, g = 0.5, b = 0.2, a = 0.5}        -- Brighter green for mouseover
}

-- Standard list item dimensions
OGST.LIST_ITEM_HEIGHT = 20
OGST.LIST_ITEM_SPACING = 2

-- ============================================
-- WINDOW MANAGEMENT
-- ============================================

-- Window registry for managing "close all windows" behavior
OGST.WindowRegistry = OGST.WindowRegistry or {}

-- Legacy frame names registry (for backward compatibility with non-OGST windows)
OGST.LegacyFrameNames = OGST.LegacyFrameNames or {}

-- Close all registered windows except the specified one
-- @param exceptFrameName: Optional frame name to keep open
function OGST.CloseAllWindows(exceptFrameName)
  -- Close OGST-registered windows
  for windowName, windowFrame in pairs(OGST.WindowRegistry) do
    if windowName ~= exceptFrameName and windowFrame.closeOnNewWindow and windowFrame:IsShown() then
      windowFrame:Hide()
    end
  end
  
  -- Close legacy non-OGST windows
  for _, frameName in ipairs(OGST.LegacyFrameNames) do
    if frameName ~= exceptFrameName then
      local frame = getglobal(frameName)
      if frame and frame:IsVisible() then
        frame:Hide()
      end
    end
  end
end

-- Create a standardized window frame
-- @param config: Table with fields:
--   - name: Unique frame name (required)
--   - width: Window width (required)
--   - height: Window height (required)
--   - title: Window title text (required)
--   - closeButton: Boolean, add close button (default: true)
--   - escapeCloses: Boolean, ESC key closes window (default: true)
--   - closeOnNewWindow: Boolean, close when other windows open (default: false)
-- @return frame: Window frame with .contentFrame property for adding content
function OGST.CreateStandardWindow(config)
  if not config or not config.name or not config.width or not config.height or not config.title then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OGST:|r CreateStandardWindow requires name, width, height, and title")
    return nil
  end
  
  local frame = CreateFrame("Frame", config.name, UIParent)
  frame:SetWidth(config.width)
  frame:SetHeight(config.height)
  frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  frame:SetFrameStrata("DIALOG")
  frame:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 12,
    insets = {left = 4, right = 4, top = 4, bottom = 4}
  })
  frame:SetBackdropColor(0, 0, 0, 0.85)
  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function() frame:StartMoving() end)
  frame:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
  frame:Hide()
  
  -- Register for closeOnNewWindow behavior
  frame.closeOnNewWindow = config.closeOnNewWindow or false
  if frame.closeOnNewWindow then
    OGST.WindowRegistry[config.name] = frame
  end
  
  -- Close other windows when this one opens (only if this window has closeOnNewWindow = true)
  frame:SetScript("OnShow", function()
    if frame.closeOnNewWindow then
      OGST.CloseAllWindows(config.name)
    end
  end)
  
  -- Title
  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOP", 0, -15)
  title:SetText(config.title)
  frame.titleText = title
  
  -- Close button (default: true)
  local hasCloseButton = config.closeButton
  if hasCloseButton == nil then
    hasCloseButton = true
  end
  
  if hasCloseButton then
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    closeBtn:SetWidth(60)
    closeBtn:SetHeight(24)
    closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -10)
    closeBtn:SetText("Close")
    OGST.StyleButton(closeBtn)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)
    frame.closeButton = closeBtn
  end
  
  -- ESC key closes window (default: true)
  local escapeCloses = config.escapeCloses
  if escapeCloses == nil then
    escapeCloses = true
  end
  
  if escapeCloses then
    OGST.MakeFrameCloseOnEscape(frame, config.name)
  end
  
  -- Content frame (area for adding custom content)
  local contentFrame = CreateFrame("Frame", nil, frame)
  contentFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, -45)
  contentFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -15, 15)
  frame.contentFrame = contentFrame
  
  return frame
end

-- ============================================
-- BUTTON STYLING
-- ============================================

-- Style a button with consistent dark teal theme
-- @param button: The button frame to style
function OGST.StyleButton(button)
  if not button then return end
  
  -- Hide the default textures
  local normalTexture = button:GetNormalTexture()
  if normalTexture then
    normalTexture:SetTexture(nil)
  end
  
  local highlightTexture = button:GetHighlightTexture()
  if highlightTexture then
    highlightTexture:SetTexture(nil)
  end
  
  local pushedTexture = button:GetPushedTexture()
  if pushedTexture then
    pushedTexture:SetTexture(nil)
  end
  
  -- Add custom backdrop with rounded corners and border
  button:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 12,
    insets = { left = 2, right = 2, top = 2, bottom = 2 }
  })
  
  -- Ensure button is fully opaque
  button:SetAlpha(1.0)
  
  -- Dark teal background color
  button:SetBackdropColor(0.25, 0.35, 0.35, 1)
  button:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
  
  -- Add hover effect
  button:SetScript("OnEnter", function()
    this:SetBackdropColor(0.3, 0.45, 0.45, 1)
    this:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
  end)
  
  button:SetScript("OnLeave", function()
    this:SetBackdropColor(0.25, 0.35, 0.35, 1)
    this:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
  end)
end

-- ============================================
-- MENU SYSTEM
-- ============================================

-- Create a standardized dropdown menu with optional title and submenus
-- @param config: Table with optional fields:
--   - name: Frame name for ESC key handling
--   - width: Menu width (default 160)
--   - title: Optional title text
--   - titleColor: RGB table for title {r, g, b} (default white)
--   - itemColor: RGB table for items {r, g, b} (default white)
-- @return menu: Frame with AddItem() and Finalize() methods
function OGST.CreateStandardMenu(config)
  config = config or {}
  local menuName = config.name or "OGST_GenericMenu"
  local menuWidth = config.width or 160
  local menuTitle = config.title
  local titleColor = config.titleColor or config.textColor or {1, 1, 1}
  local itemColor = config.itemColor or {1, 1, 1}
  
  local menu = CreateFrame("Frame", menuName, UIParent)
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
  menu:SetWidth(menuWidth)
  menu:SetHeight(100)
  menu:Hide()
  menu:EnableMouse(true)
  
  -- Register ESC key handler if name provided
  if menuName then
    OGST.MakeFrameCloseOnEscape(menu, menuName)
  end
  
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
    -- Hide any open submenus
    if menu.activeSubmenu then
      menu.activeSubmenu:Hide()
      menu.activeSubmenu = nil
    end
  end)
  
  -- Title text (optional)
  local yOffset = -8
  if menuTitle then
    local titleText = menu:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetPoint("TOP", menu, "TOP", 0, yOffset)
    titleText:SetText(menuTitle)
    titleText:SetTextColor(titleColor[1], titleColor[2], titleColor[3])
    menu.titleText = titleText
    yOffset = yOffset - 20
  end
  
  menu.items = {}
  menu.yOffset = yOffset
  menu.itemHeight = 16
  menu.itemSpacing = 2
  menu.itemColor = itemColor
  
  -- Helper to create menu item
  function menu:AddItem(itemConfig)
    local text = itemConfig.text or "Menu Item"
    local onClick = itemConfig.onClick
    local hasSubmenu = itemConfig.submenu ~= nil
    local submenuItems = itemConfig.submenu
    
    local item = CreateFrame("Button", nil, menu)
    item:SetWidth(menuWidth - 10)
    item:SetHeight(self.itemHeight)
    item:SetPoint("TOP", menu, "TOP", 0, self.yOffset)
    
    -- Background highlight
    local bg = item:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    bg:SetVertexColor(0.2, 0.2, 0.2, 0)
    item.bg = bg
    
    -- Text (left-aligned)
    local fs = item:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("LEFT", item, "LEFT", 8, 0)
    fs:SetText(text)
    fs:SetTextColor(self.itemColor[1], self.itemColor[2], self.itemColor[3])
    item.fs = fs
    
    -- Add arrow if has submenu
    if hasSubmenu then
      local arrow = item:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      arrow:SetPoint("RIGHT", item, "RIGHT", -5, 0)
      arrow:SetText(">")
      arrow:SetTextColor(self.itemColor[1] * 0.7, self.itemColor[2] * 0.7, self.itemColor[3] * 0.7)
      item.arrow = arrow
    end
    
    -- Highlight on hover
    item:SetScript("OnEnter", function()
      bg:SetVertexColor(0.3, 0.3, 0.3, 0.5)
      
      if hasSubmenu then
        -- Create and show submenu
        if not item.submenu then
          item.submenu = menu:CreateSubmenu(submenuItems, item)
        end
        
        -- Hide any previously open submenu
        if menu.activeSubmenu and menu.activeSubmenu ~= item.submenu then
          menu.activeSubmenu:Hide()
        end
        
        item.submenu:ClearAllPoints()
        item.submenu:SetPoint("TOPLEFT", item, "TOPRIGHT", 2, 0)
        item.submenu:Show()
        menu.activeSubmenu = item.submenu
      end
    end)
    
    item:SetScript("OnLeave", function()
      bg:SetVertexColor(0.2, 0.2, 0.2, 0)
    end)
    
    if not hasSubmenu and onClick then
      item:SetScript("OnClick", function()
        onClick()
        menu:Hide()
      end)
    end
    
    table.insert(self.items, item)
    self.yOffset = self.yOffset - (self.itemHeight + self.itemSpacing)
    
    return item
  end
  
  -- Helper to create submenu
  function menu:CreateSubmenu(submenuItems, parentItem)
    local submenu = CreateFrame("Frame", nil, UIParent)
    submenu:SetFrameStrata("FULLSCREEN_DIALOG")
    submenu:SetFrameLevel(menu:GetFrameLevel() + 1)
    submenu:SetBackdrop({
      bgFile = "Interface/Tooltips/UI-Tooltip-Background",
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
      tile = true,
      tileSize = 16,
      edgeSize = 16,
      insets = {left = 4, right = 4, top = 4, bottom = 4}
    })
    submenu:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
    submenu:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    submenu:SetWidth(180)
    submenu:Hide()
    submenu:EnableMouse(true)
    
    local subYOffset = -5
    
    for i, subItemConfig in ipairs(submenuItems) do
      local subText = subItemConfig.text or "Submenu Item"
      local subOnClick = subItemConfig.onClick
      
      local subItem = CreateFrame("Button", nil, submenu)
      subItem:SetWidth(170)
      subItem:SetHeight(menu.itemHeight)
      subItem:SetPoint("TOPLEFT", submenu, "TOPLEFT", 5, subYOffset)
      
      -- Background highlight
      local subBg = subItem:CreateTexture(nil, "BACKGROUND")
      subBg:SetAllPoints()
      subBg:SetTexture("Interface\\Buttons\\WHITE8X8")
      subBg:SetVertexColor(0.2, 0.2, 0.2, 0)
      subItem.bg = subBg
      
      -- Text (left-aligned)
      local subFs = subItem:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      subFs:SetPoint("LEFT", subItem, "LEFT", 8, 0)
      subFs:SetText(subText)
      subFs:SetTextColor(menu.itemColor[1], menu.itemColor[2], menu.itemColor[3])
      subItem.fs = subFs
      
      -- Highlight on hover
      subItem:SetScript("OnEnter", function()
        subBg:SetVertexColor(0.3, 0.3, 0.3, 0.5)
      end)
      
      subItem:SetScript("OnLeave", function()
        subBg:SetVertexColor(0.2, 0.2, 0.2, 0)
      end)
      
      if subOnClick then
        subItem:SetScript("OnClick", function()
          subOnClick()
          submenu:Hide()
          menu:Hide()
        end)
      end
      
      subYOffset = subYOffset - (menu.itemHeight + menu.itemSpacing)
    end
    
    submenu:SetHeight(math.max(30, math.abs(subYOffset) + 10))
    
    return submenu
  end
  
  -- Method to finalize menu (set final height)
  function menu:Finalize()
    self:SetHeight(math.max(50, math.abs(self.yOffset) + 15))
  end
  
  return menu
end

-- ============================================
-- SCROLL LIST
-- ============================================

-- Create a standardized scrolling list with frame
-- @param parent: Parent frame
-- @param width: List width
-- @param height: List height
-- @param hideScrollBar: Optional boolean, true to hide scrollbar
-- @return outerFrame, scrollFrame, scrollChild, scrollBar, contentWidth
function OGST.CreateStyledScrollList(parent, width, height, hideScrollBar)
  if not parent then return nil end
  
  -- Outer container frame with backdrop
  local outerFrame = CreateFrame("Frame", nil, parent)
  outerFrame:SetWidth(width)
  outerFrame:SetHeight(height)
  outerFrame:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 12,
    insets = {left = 3, right = 3, top = 3, bottom = 3}
  })
  outerFrame:SetBackdropColor(0.15, 0.15, 0.15, 0.9)
  
  -- Adjust content width based on whether scrollbar will be shown
  local scrollBarSpace = hideScrollBar and 0 or 20
  
  -- Scroll frame inside the outer frame
  local scrollFrame = CreateFrame("ScrollFrame", nil, outerFrame)
  scrollFrame:SetPoint("TOPLEFT", outerFrame, "TOPLEFT", 5, -5)
  scrollFrame:SetPoint("BOTTOMRIGHT", outerFrame, "BOTTOMRIGHT", -(5 + scrollBarSpace), 5)
  
  -- Scroll child
  local scrollChild = CreateFrame("Frame", nil, scrollFrame)
  local contentWidth = width - 10 - scrollBarSpace
  scrollChild:SetWidth(contentWidth)
  scrollChild:SetHeight(1)
  scrollFrame:SetScrollChild(scrollChild)
  
  -- Scrollbar
  local scrollBar = CreateFrame("Slider", nil, outerFrame)
  scrollBar:SetPoint("TOPRIGHT", outerFrame, "TOPRIGHT", -5, -16)
  scrollBar:SetPoint("BOTTOMRIGHT", outerFrame, "BOTTOMRIGHT", -5, 16)
  scrollBar:SetWidth(16)
  scrollBar:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 8,
    insets = {left = 3, right = 3, top = 3, bottom = 3}
  })
  scrollBar:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
  scrollBar:SetOrientation("VERTICAL")
  scrollBar:SetMinMaxValues(0, 1)
  scrollBar:SetValue(0)
  scrollBar:SetValueStep(22)
  scrollBar:Hide()
  
  scrollBar:SetScript("OnValueChanged", function()
    scrollFrame:SetVerticalScroll(this:GetValue())
  end)
  
  -- Enable mouse wheel scrolling
  scrollFrame:EnableMouseWheel(true)
  scrollFrame:SetScript("OnMouseWheel", function()
    local delta = arg1
    local current, minVal, maxVal
    
    if hideScrollBar then
      -- When scrollbar is hidden, directly manipulate scroll position
      current = scrollFrame:GetVerticalScroll()
      maxVal = scrollChild:GetHeight() - scrollFrame:GetHeight()
      if maxVal < 0 then maxVal = 0 end
      minVal = 0
      
      local newScroll = current - (delta * 20)
      if newScroll < minVal then
        newScroll = minVal
      elseif newScroll > maxVal then
        newScroll = maxVal
      end
      scrollFrame:SetVerticalScroll(newScroll)
    else
      -- When scrollbar is visible, use it for scrolling
      if not scrollBar:IsShown() then return end
      current = scrollBar:GetValue()
      minVal, maxVal = scrollBar:GetMinMaxValues()
      if delta > 0 then
        scrollBar:SetValue(math.max(minVal, current - 22))
      else
        scrollBar:SetValue(math.min(maxVal, current + 22))
      end
    end
  end)
  
  return outerFrame, scrollFrame, scrollChild, scrollBar, contentWidth
end

-- ============================================
-- LIST ITEMS
-- ============================================

-- Create a standardized list item with background and hover effects
-- @param parent: Parent frame
-- @param width: Item width
-- @param height: Item height (default: OGST.LIST_ITEM_HEIGHT)
-- @param frameType: "Button" or "Frame" (default: "Button")
-- @return itemFrame: Frame with .bg property for runtime color changes
function OGST.CreateStyledListItem(parent, width, height, frameType)
  if not parent then return nil end
  
  height = height or OGST.LIST_ITEM_HEIGHT
  frameType = frameType or "Button"
  
  local item = CreateFrame(frameType, nil, parent)
  item:SetWidth(width)
  item:SetHeight(height)
  
  -- For Frame types, use backdrop instead of texture
  if frameType == "Frame" then
    item:SetBackdrop({
      bgFile = "Interface/Tooltips/UI-Tooltip-Background",
      tile = false,
      insets = {left = 0, right = 0, top = 0, bottom = 0}
    })
    item:SetBackdropColor(
      OGST.LIST_COLORS.INACTIVE.r,
      OGST.LIST_COLORS.INACTIVE.g,
      OGST.LIST_COLORS.INACTIVE.b,
      OGST.LIST_COLORS.INACTIVE.a
    )
    item.bg = item  -- Reference to self for SetBackdropColor
  else
    -- For Button types, use texture approach
    local bg = item:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    bg:SetVertexColor(
      OGST.LIST_COLORS.INACTIVE.r,
      OGST.LIST_COLORS.INACTIVE.g,
      OGST.LIST_COLORS.INACTIVE.b,
      OGST.LIST_COLORS.INACTIVE.a
    )
    bg:Show()
    item.bg = bg
  end
  
  item:Show()
  
  -- Add hover and selection effects only for Button frames
  if frameType == "Button" then
    item:SetScript("OnEnter", function()
      if not this.isSelected then
        this.bg:SetVertexColor(
          OGST.LIST_COLORS.HOVER.r,
          OGST.LIST_COLORS.HOVER.g,
          OGST.LIST_COLORS.HOVER.b,
          OGST.LIST_COLORS.HOVER.a
        )
      end
    end)
    
    item:SetScript("OnLeave", function()
      if this.isSelected then
        this.bg:SetVertexColor(
          OGST.LIST_COLORS.SELECTED.r,
          OGST.LIST_COLORS.SELECTED.g,
          OGST.LIST_COLORS.SELECTED.b,
          OGST.LIST_COLORS.SELECTED.a
        )
      else
        this.bg:SetVertexColor(
          OGST.LIST_COLORS.INACTIVE.r,
          OGST.LIST_COLORS.INACTIVE.g,
          OGST.LIST_COLORS.INACTIVE.b,
          OGST.LIST_COLORS.INACTIVE.a
        )
      end
    end)
  end
  
  return item
end

-- Add standardized up/down/delete buttons to a list item
-- @param listItem: The parent frame to attach buttons to
-- @param index: Current index in the list (1-based)
-- @param listLength: Total number of items in the list
-- @param onMoveUp: Callback function when up button clicked
-- @param onMoveDown: Callback function when down button clicked
-- @param onDelete: Callback function when delete button clicked
-- @param hideUpDown: Optional boolean, if true only shows delete button
-- @return deleteButton, downButton, upButton
function OGST.AddListItemButtons(listItem, index, listLength, onMoveUp, onMoveDown, onDelete, hideUpDown)
  if not listItem then return nil, nil, nil end
  
  local buttonSize = 32
  local buttonSpacing = -10
  
  -- Delete button (X mark)
  local deleteBtn = CreateFrame("Button", nil, listItem)
  deleteBtn:SetWidth(buttonSize)
  deleteBtn:SetHeight(buttonSize)
  deleteBtn:SetPoint("RIGHT", listItem, "RIGHT", -2, 0)
  deleteBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
  deleteBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight", "ADD")
  deleteBtn:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
  
  if onDelete then
    deleteBtn:SetScript("OnClick", onDelete)
  end
  
  if hideUpDown then
    return deleteBtn, nil, nil
  end
  
  -- Down button
  local downBtn = CreateFrame("Button", nil, listItem)
  downBtn:SetWidth(buttonSize)
  downBtn:SetHeight(buttonSize)
  downBtn:SetPoint("RIGHT", deleteBtn, "LEFT", -buttonSpacing, 0)
  downBtn:SetNormalTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up")
  downBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
  downBtn:SetPushedTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Down")
  downBtn:SetDisabledTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Disabled")
  
  if index >= listLength then
    downBtn:Disable()
  elseif onMoveDown then
    downBtn:SetScript("OnClick", onMoveDown)
  end
  
  -- Up button
  local upBtn = CreateFrame("Button", nil, listItem)
  upBtn:SetWidth(buttonSize)
  upBtn:SetHeight(buttonSize)
  upBtn:SetPoint("RIGHT", downBtn, "LEFT", -buttonSpacing, 0)
  upBtn:SetNormalTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Up")
  upBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
  upBtn:SetPushedTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Down")
  upBtn:SetDisabledTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Disabled")
  
  if index <= 1 then
    upBtn:Disable()
  elseif onMoveUp then
    upBtn:SetScript("OnClick", onMoveUp)
  end
  
  return deleteBtn, downBtn, upBtn
end

-- Set list item selected state
-- @param item: List item frame
-- @param isSelected: Boolean for selection state
function OGST.SetListItemSelected(item, isSelected)
  if not item or not item.bg then return end
  
  item.isSelected = isSelected
  
  local color = isSelected and OGST.LIST_COLORS.SELECTED or OGST.LIST_COLORS.INACTIVE
  
  if item.bg.SetVertexColor then
    item.bg:SetVertexColor(color.r, color.g, color.b, color.a)
  elseif item.bg.SetBackdropColor then
    item.bg:SetBackdropColor(color.r, color.g, color.b, color.a)
  end
end

-- Set custom list item color
-- @param item: List item frame
-- @param r, g, b, a: Color components (0-1)
function OGST.SetListItemColor(item, r, g, b, a)
  if not item or not item.bg then return end
  
  if item.bg.SetVertexColor then
    item.bg:SetVertexColor(r, g, b, a)
  elseif item.bg.SetBackdropColor then
    item.bg:SetBackdropColor(r, g, b, a)
  end
end

-- ============================================
-- TEXT BOX
-- ============================================

-- Create a scrolling multi-line text box with backdrop and scrollbar
-- @param parent: Parent frame
-- @param width: Text box width
-- @param height: Text box height
-- @return backdrop, editBox, scrollFrame, scrollBar
function OGST.CreateScrollingTextBox(parent, width, height)
  if not parent then return nil end
  
  -- Backdrop frame
  local backdrop = CreateFrame("Frame", nil, parent)
  backdrop:SetWidth(width)
  backdrop:SetHeight(height)
  backdrop:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 16,
    insets = {left = 3, right = 3, top = 3, bottom = 3}
  })
  backdrop:SetBackdropColor(0, 0, 0, 1)
  backdrop:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
  
  -- Scroll frame
  local scrollFrame = CreateFrame("ScrollFrame", nil, backdrop)
  scrollFrame:SetPoint("TOPLEFT", 5, -6)
  scrollFrame:SetPoint("BOTTOMRIGHT", -28, 6)
  
  local contentWidth = width - 5 - 28 - 5
  
  -- Scroll child
  local scrollChild = CreateFrame("Frame", nil, scrollFrame)
  scrollFrame:SetScrollChild(scrollChild)
  scrollChild:SetWidth(contentWidth)
  scrollChild:SetHeight(400)
  
  -- Edit box
  local editBox = CreateFrame("EditBox", nil, scrollChild)
  editBox:SetPoint("TOPLEFT", 0, 0)
  editBox:SetWidth(contentWidth)
  editBox:SetHeight(400)
  editBox:SetMultiLine(true)
  editBox:SetAutoFocus(false)
  editBox:SetFontObject(ChatFontNormal)
  editBox:SetTextInsets(5, 5, 3, 3)
  editBox:SetScript("OnEscapePressed", function() this:ClearFocus() end)
  
  -- Scrollbar
  local scrollBar = CreateFrame("Slider", nil, backdrop)
  scrollBar:SetPoint("TOPRIGHT", backdrop, "TOPRIGHT", -5, -16)
  scrollBar:SetPoint("BOTTOMRIGHT", backdrop, "BOTTOMRIGHT", -5, 16)
  scrollBar:SetWidth(16)
  scrollBar:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 8,
    insets = {left = 3, right = 3, top = 3, bottom = 3}
  })
  scrollBar:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
  scrollBar:SetOrientation("VERTICAL")
  scrollBar:SetMinMaxValues(0, 1)
  scrollBar:SetValue(0)
  scrollBar:SetValueStep(22)
  scrollBar:SetScript("OnValueChanged", function()
    scrollFrame:SetVerticalScroll(this:GetValue())
  end)
  
  -- Update scroll range when text changes
  editBox:SetScript("OnTextChanged", function()
    local maxScroll = scrollChild:GetHeight() - scrollFrame:GetHeight()
    if maxScroll > 0 then
      scrollBar:SetMinMaxValues(0, maxScroll)
      scrollBar:Show()
    else
      scrollBar:Hide()
    end
  end)
  
  -- Mouse wheel scrolling
  scrollFrame:EnableMouseWheel(true)
  scrollFrame:SetScript("OnMouseWheel", function()
    local current = scrollBar:GetValue()
    local maxScroll = scrollChild:GetHeight() - scrollFrame:GetHeight()
    if maxScroll > 0 then
      if arg1 > 0 then
        scrollBar:SetValue(math.max(0, current - 22))
      else
        scrollBar:SetValue(math.min(maxScroll, current + 22))
      end
    end
  end)
  
  -- Make the backdrop clickable to focus the editbox
  backdrop:EnableMouse(true)
  backdrop:SetScript("OnMouseDown", function()
    editBox:SetFocus()
  end)
  
  return backdrop, editBox, scrollFrame, scrollBar
end

-- ============================================
-- FRAME UTILITIES
-- ============================================

-- Make a frame close on ESC key
-- @param frame: The frame to register
-- @param frameName: Unique name for the frame
-- @param closeCallback: Optional callback function when frame closes
function OGST.MakeFrameCloseOnEscape(frame, frameName, closeCallback)
  if not frame or not frameName then return end
  
  -- Check if already registered to avoid duplicates
  local alreadyRegistered = false
  for i = 1, table.getn(UISpecialFrames) do
    if UISpecialFrames[i] == frameName then
      alreadyRegistered = true
      break
    end
  end
  
  -- Register with Blizzard's UI panel system for ESC key handling
  if not alreadyRegistered then
    table.insert(UISpecialFrames, frameName)
  end
  
  -- If a custom close callback is provided, hook it to the frame's OnHide
  if closeCallback and type(closeCallback) == "function" then
    local originalOnHide = frame:GetScript("OnHide")
    frame:SetScript("OnHide", function()
      if originalOnHide then originalOnHide() end
      closeCallback()
    end)
  end
end

-- Library loaded message
DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OGST:|r Standard Templates Library v" .. OGST.version .. " loaded")
