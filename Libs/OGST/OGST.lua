-- OGST.lua - OG Standard Templates Library
-- Reusable UI template functions for World of Warcraft 1.12.1 addons
-- Version 1.1.0
-- 
-- This library provides standardized UI components and helper functions
-- that can be used across multiple addons for consistent styling and behavior.

-- Version checking and load management
-- This allows OGST to be loaded either as a standalone addon (_OGST)
-- or embedded within other addons. The newest version takes priority.

local OGST_NEW_VERSION = "1.1.0"
local OGST_LOAD_SOURCE = nil  -- Will be set to "standalone" or addon name

-- Determine where we're being loaded from
do
  local loadedFrom = debugstack()
  if string.find(loadedFrom, "Interface\\AddOns\\_OGST\\") then
    OGST_LOAD_SOURCE = "standalone"
  elseif string.find(loadedFrom, "Interface\\AddOns\\OG%-RaidHelper\\Libs\\OGST\\") then
    OGST_LOAD_SOURCE = "OG-RaidHelper"
  elseif string.find(loadedFrom, "Interface\\AddOns\\") then
    -- Extract addon name from path
    local _, _, addonName = string.find(loadedFrom, "Interface\\AddOns\\([^\\]+)\\")
    OGST_LOAD_SOURCE = addonName or "unknown"
  else
    OGST_LOAD_SOURCE = "unknown"
  end
end

-- Compare semantic versions (format: "major.minor.patch")
-- Returns: 1 if v1 > v2, -1 if v1 < v2, 0 if equal
local function CompareVersions(v1, v2)
  local function parseVersion(v)
    local major, minor, patch = string.match(v, "(%d+)%.(%d+)%.(%d+)")
    return {
      tonumber(major) or 0,
      tonumber(minor) or 0,
      tonumber(patch) or 0
    }
  end
  
  local v1Parts = parseVersion(v1)
  local v2Parts = parseVersion(v2)
  
  for i = 1, 3 do
    if v1Parts[i] > v2Parts[i] then
      return 1
    elseif v1Parts[i] < v2Parts[i] then
      return -1
    end
  end
  
  return 0
end

-- Create global namespace with version checking
if not OGST then
  OGST = {}
  OGST.version = OGST_NEW_VERSION
  OGST.loadSource = OGST_LOAD_SOURCE
  DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OGST:|r Initialized v" .. OGST_NEW_VERSION .. " from " .. OGST_LOAD_SOURCE)
elseif OGST.version then
  -- OGST already exists - check version
  local comparison = CompareVersions(OGST_NEW_VERSION, OGST.version)
  
  if comparison > 0 then
    -- New version is newer - we'll initialize below
    DEFAULT_CHAT_FRAME:AddMessage("|cffffff00OGST:|r Upgrading from v" .. OGST.version .. " (" .. (OGST.loadSource or "unknown") .. ") to v" .. OGST_NEW_VERSION .. " (" .. OGST_LOAD_SOURCE .. ")")
    OGST.version = OGST_NEW_VERSION
    OGST.previousLoadSource = OGST.loadSource
    OGST.loadSource = OGST_LOAD_SOURCE
  elseif comparison == 0 then
    -- Same version - skip initialization
    DEFAULT_CHAT_FRAME:AddMessage("|cff888888OGST:|r v" .. OGST.version .. " already loaded from " .. (OGST.loadSource or "unknown") .. ", skipping duplicate load from " .. OGST_LOAD_SOURCE)
    return  -- Exit early, don't reinitialize
  else
    -- Old version - skip initialization
    DEFAULT_CHAT_FRAME:AddMessage("|cffff8800OGST:|r v" .. OGST.version .. " (" .. (OGST.loadSource or "unknown") .. ") is newer than v" .. OGST_NEW_VERSION .. " (" .. OGST_LOAD_SOURCE .. "), keeping existing version")
    return  -- Exit early, don't reinitialize
  end
else
  -- OGST exists but has no version (legacy)
  DEFAULT_CHAT_FRAME:AddMessage("|cffffff00OGST:|r Upgrading legacy version to v" .. OGST_NEW_VERSION .. " (" .. OGST_LOAD_SOURCE .. ")")
  OGST.version = OGST_NEW_VERSION
  OGST.loadSource = OGST_LOAD_SOURCE
end

OGST.DESIGN_MODE = OGST.DESIGN_MODE or false

-- Helper function to add design mode tooltips
function OGST.AddDesignTooltip(frame, name, frameType)
  frame:SetScript("OnEnter", function()
    if not OGST.DESIGN_MODE then return end
    GameTooltip:SetOwner(this, "ANCHOR_CURSOR")
    GameTooltip:AddLine(name or "Unknown", 1, 1, 1)
    GameTooltip:AddLine("Type: " .. (frameType or frame:GetObjectType()), 0.8, 0.8, 0.8)
    local w, h = frame:GetWidth(), frame:GetHeight()
    GameTooltip:AddLine(string.format("Size: %.0fx%.0f", w, h), 0.6, 0.6, 1)
    GameTooltip:Show()
  end)
  
  frame:SetScript("OnLeave", function()
    if not OGST.DESIGN_MODE then return end
    GameTooltip:Hide()
  end)
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
-- HELPER FUNCTIONS
-- ============================================

-- Get the correct path for OGST resources based on where it's loaded from
-- Returns the base path to the OGST folder
function OGST.GetResourcePath()
  if not OGST._resourcePath then
    -- Determine path based on where OGST was loaded from
    
    if OGST.loadSource == "standalone" then
      OGST._resourcePath = "Interface\\AddOns\\_OGST\\"
    elseif OGST.loadSource == "OG-RaidHelper" then
      OGST._resourcePath = "Interface\\AddOns\\OG-RaidHelper\\Libs\\OGST\\"
    else
      -- Generic embedded version - construct path from load source
      OGST._resourcePath = "Interface\\AddOns\\" .. (OGST.loadSource or "OG-RaidHelper") .. "\\Libs\\OGST\\"
    end
  end
  
  return OGST._resourcePath
end

-- Helper to get table size
function OGST.GetTableSize(t)
  local count = 0
  for _ in pairs(t) do count = count + 1 end
  return count
end

-- Toggle design mode and update all windows
function OGST.ToggleDesignMode()
  OGST.DESIGN_MODE = not OGST.DESIGN_MODE
  
  if OGST.DESIGN_MODE then
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OGST:|r Design mode |cff00ff00ENABLED|r")
  else
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OGST:|r Design mode |cffff0000DISABLED|r")
  end
  
  -- Function to recursively update all child frames
  local function UpdateFrameBorders(frame)
    if not frame then return end
    
    -- Check if this frame has a design mode border marker
    if frame.hasDesignBorder then
      if OGST.DESIGN_MODE then
        if not frame:GetBackdrop() or not frame:GetBackdrop().edgeFile then
          frame:SetBackdrop({
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 16,
            insets = { left = 0, right = 0, top = 0, bottom = 0 }
          })
        end
        frame:SetBackdropBorderColor(frame.designBorderColor.r, frame.designBorderColor.g, frame.designBorderColor.b, 1)
      else
        -- Only remove border if frame doesn't need backdrop for other reasons
        if frame.removeBackdropWhenNotDesigning then
          frame:SetBackdrop(nil)
        else
          -- Just reset border to normal color
          if frame.normalBorderColor then
            frame:SetBackdropBorderColor(frame.normalBorderColor.r, frame.normalBorderColor.g, frame.normalBorderColor.b, frame.normalBorderColor.a or 1)
          end
        end
      end
    end
    
    -- Recursively update children
    local children = { frame:GetChildren() }
    for _, child in ipairs(children) do
      UpdateFrameBorders(child)
    end
  end
  
  -- Update all registered windows
  for windowName, windowFrame in pairs(OGST.WindowRegistry) do
    if windowFrame then
      UpdateFrameBorders(windowFrame)
    end
  end
end

-- ============================================
-- WINDOW MANAGEMENT
-- ============================================

-- Window registry for managing "close all windows" behavior
OGST.WindowRegistry = OGST.WindowRegistry or {}

-- ============================================
-- MENU MANAGEMENT
-- ============================================

-- Menu registry for managing globally accessible menus
OGST.MenuRegistry = OGST.MenuRegistry or {}

-- Get a registered menu by name
-- @param name: Menu name
-- @return menu: Menu frame or nil
function OGST.GetMenu(name)
  return OGST.MenuRegistry[name]
end

-- Add an item to an existing menu
-- @param menuName: Name of the registered menu
-- @param itemConfig: Item configuration (same as menu:AddItem)
-- @return success: Boolean
function OGST.AddMenuItem(menuName, itemConfig)
  local menu = OGST.MenuRegistry[menuName]
  if not menu then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OGST:|r Menu '" .. menuName .. "' not found")
    return false
  end
  
  if not menu.finalized then
    menu:AddItem(itemConfig)
    return true
  else
    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OGST:|r Cannot add items to finalized menu '" .. menuName .. "'")
    return false
  end
end

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
  
  -- Register window in registry for design mode updates
  OGST.WindowRegistry[config.name] = frame
  
  -- Store closeOnNewWindow flag
  frame.closeOnNewWindow = config.closeOnNewWindow or false
  
  -- Close other windows when this one opens (only if this window has closeOnNewWindow = true)
  frame:SetScript("OnShow", function()
    if frame.closeOnNewWindow then
      OGST.CloseAllWindows(config.name)
    end
  end)
  
  -- Header frame (5px padding, 35px height)
  local headerFrame = CreateFrame("Frame", nil, frame)
  headerFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 5, -5)
  headerFrame:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -5, -5)
  headerFrame:SetHeight(35)
  headerFrame:EnableMouse(true)
  headerFrame:RegisterForDrag("LeftButton")
  headerFrame:SetScript("OnDragStart", function()
    frame:StartMoving()
  end)
  headerFrame:SetScript("OnDragStop", function()
    frame:StopMovingOrSizing()
  end)
  
  -- Mark for design mode system
  headerFrame.hasDesignBorder = true
  headerFrame.designBorderColor = {r = 1, g = 0, b = 0}  -- Red
  headerFrame.removeBackdropWhenNotDesigning = true
  
  -- Design mode border for header
  if OGST.DESIGN_MODE then
    headerFrame:SetBackdrop({
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      edgeSize = 16,
      insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    headerFrame:SetBackdropBorderColor(1, 0, 0, 1)  -- Red for header
  end
  OGST.AddDesignTooltip(headerFrame, "Header Frame", "Frame")
  
  frame.headerFrame = headerFrame
  
  -- Title (centered in header)
  local title = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("CENTER", headerFrame, "CENTER", 0, 0)
  title:SetText(config.title)
  frame.titleText = title
  
  -- Close button (default: true)
  local hasCloseButton = config.closeButton
  if hasCloseButton == nil then
    hasCloseButton = true
  end
  
  if hasCloseButton then
    local closeBtn = CreateFrame("Button", nil, headerFrame, "UIPanelButtonTemplate")
    closeBtn:SetWidth(60)
    closeBtn:SetHeight(24)
    closeBtn:SetPoint("RIGHT", headerFrame, "RIGHT", -5, 0)
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
  
  -- Resize handle (default: false) - create before contentFrame so we can adjust padding
  local hasResize = config.resizable or false
  local resizeBtn = nil
  if hasResize then
    frame:SetResizable(true)
    
    -- Set min/max sizes with configurable parameters
    local minWidth = config.minWidth or 200
    local minHeight = config.minHeight or 150
    local maxWidth = config.maxWidth or UIParent:GetWidth()
    local maxHeight = config.maxHeight or UIParent:GetHeight()
    
    frame:SetMinResize(minWidth, minHeight)
    frame:SetMaxResize(maxWidth, maxHeight)
    
    -- Create resize button in bottom right
    local resizeBtn = CreateFrame("Button", nil, frame)
    resizeBtn:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -5, 5)
    resizeBtn:SetWidth(16)
    resizeBtn:SetHeight(16)
    resizeBtn:SetFrameStrata("FULLSCREEN")
    resizeBtn:SetFrameLevel(frame:GetFrameLevel() + 10)
    resizeBtn:EnableMouse(true)
    resizeBtn:RegisterForDrag("LeftButton")
    
    -- Use resize grip texture from OGST img folder
    local resizeTex = resizeBtn:CreateTexture(nil, "OVERLAY")
    resizeTex:SetWidth(16)
    resizeTex:SetHeight(16)
    resizeTex:SetPoint("BOTTOMRIGHT", resizeBtn, "BOTTOMRIGHT")
    resizeTex:SetTexture(OGST.GetResourcePath() .. "img\\UI-ChatIM-SizeGrabber-Up")
    
    local resizeTexHighlight = resizeBtn:CreateTexture(nil, "HIGHLIGHT")
    resizeTexHighlight:SetWidth(16)
    resizeTexHighlight:SetHeight(16)
    resizeTexHighlight:SetPoint("BOTTOMRIGHT", resizeBtn, "BOTTOMRIGHT")
    resizeTexHighlight:SetTexture(OGST.GetResourcePath() .. "img\\UI-ChatIM-SizeGrabber-Highlight")
    
    -- Resize drag behavior
    resizeBtn:SetScript("OnDragStart", function()
      frame:StartSizing("BOTTOMRIGHT")
    end)
    
    resizeBtn:SetScript("OnDragStop", function()
      frame:StopMovingOrSizing()
    end)
    
    frame.resizeButton = resizeBtn
  end
  
  -- Content frame (area for adding custom content) - created after resize button
  local contentPadding = config.contentPadding or 5
  local contentFrame = CreateFrame("Frame", nil, frame)
  contentFrame:EnableMouse(false)  -- Don't block mouse events
  
  -- Calculate top offset: below header if it exists, otherwise just padding
  local topOffset = -contentPadding
  if config.title and config.title ~= "" then
    topOffset = -35  -- Below header (35px header height + 5px header padding + -5px gap)
  end
  
  contentFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", contentPadding, topOffset)
  contentFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -contentPadding, contentPadding)
  
  -- Mark for design mode system
  contentFrame.hasDesignBorder = true
  contentFrame.designBorderColor = {r = 0, g = 1, b = 0}  -- Green
  contentFrame.removeBackdropWhenNotDesigning = true
  
  -- Design mode border
  if OGST.DESIGN_MODE then
    contentFrame:SetBackdrop({
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      edgeSize = 16,
      insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    contentFrame:SetBackdropBorderColor(0, 1, 0, 1)  -- Green for content
  end
  OGST.AddDesignTooltip(contentFrame, "Content Frame", "Frame")
  
  frame.contentFrame = contentFrame
  
  return frame
end

-- ============================================
-- BUTTON STYLING
-- ============================================

-- Create a styled button with consistent theming
-- @param parent: Parent frame
-- @param config: Configuration table
--   - width: Button width (required)
--   - height: Button height (default: 24)
--   - text: Button text (required)
--   - onClick: Click handler function
-- @return button: Styled button frame
function OGST.CreateButton(parent, config)
  if not parent or not config or not config.text then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OGST:|r CreateButton requires parent and config.text")
    return nil
  end
  
  local width = config.width or 100
  local height = config.height or 24
  
  local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  button:SetWidth(width)
  button:SetHeight(height)
  
  local buttonText = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  buttonText:SetPoint("CENTER", button, "CENTER", 0, 0)
  buttonText:SetText(config.text)
  buttonText:SetTextColor(1, 0.82, 0, 1)
  
  OGST.StyleButton(button)
  
  -- Mark for design mode system
  button.hasDesignBorder = true
  button.designBorderColor = {r = 0, g = 1, b = 0}  -- Green
  button.normalBorderColor = {r = 0.4, g = 0.4, b = 0.4, a = 1}
  button.removeBackdropWhenNotDesigning = false  -- Keep backdrop always
  
  -- Override border color in design mode
  if OGST.DESIGN_MODE then
    button:SetBackdropBorderColor(0, 1, 0, 1)  -- Green border for design mode
  end
  
  if config.onClick then
    button:SetScript("OnClick", config.onClick)
  end
  
  -- Design mode tooltip
  OGST.AddDesignTooltip(button, config.text .. " Button", "Button")
  
  return button
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
--   - name: Frame name for ESC key handling and registry
--   - width: Menu width (default 160)
--   - title: Optional title text
--   - titleColor: RGB table for title {r, g, b} (default white)
--   - itemColor: RGB table for items {r, g, b} (default white)
--   - register: Register menu globally (default: true if name provided)
-- @return menu: Frame with AddItem() and Finalize() methods
function OGST.CreateStandardMenu(config)
  config = config or {}
  local menuName = config.name or "OGST_GenericMenu"
  local menuWidth = config.width or 160
  local menuTitle = config.title
  local titleColor = config.titleColor or config.textColor or {1, 1, 1}
  local itemColor = config.itemColor or {1, 1, 1}
  local shouldRegister = config.register
  if shouldRegister == nil and menuName then
    shouldRegister = true
  end
  
  local menu = CreateFrame("Frame", menuName, UIParent)
  menu:SetFrameStrata("FULLSCREEN_DIALOG")
  menu.finalized = false
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
    submenu.activeSubmenu = nil
    
    local subYOffset = -5
    
    for i, subItemConfig in ipairs(submenuItems) do
      local subText = subItemConfig.text or "Submenu Item"
      local subOnClick = subItemConfig.onClick
      local hasNestedSubmenu = subItemConfig.submenu ~= nil
      local nestedSubmenuItems = subItemConfig.submenu
      
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
      
      -- Add arrow if has nested submenu
      if hasNestedSubmenu then
        local arrow = subItem:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        arrow:SetPoint("RIGHT", subItem, "RIGHT", -5, 0)
        arrow:SetText(">")
        arrow:SetTextColor(menu.itemColor[1] * 0.7, menu.itemColor[2] * 0.7, menu.itemColor[3] * 0.7)
        subItem.arrow = arrow
      end
      
      -- Highlight on hover
      subItem:SetScript("OnEnter", function()
        subBg:SetVertexColor(0.3, 0.3, 0.3, 0.5)
        
        if hasNestedSubmenu then
          -- Create and show nested submenu
          if not subItem.submenu then
            subItem.submenu = menu:CreateSubmenu(nestedSubmenuItems, subItem)
          end
          
          -- Hide any previously open nested submenu
          if submenu.activeSubmenu and submenu.activeSubmenu ~= subItem.submenu then
            submenu.activeSubmenu:Hide()
          end
          
          subItem.submenu:ClearAllPoints()
          subItem.submenu:SetPoint("TOPLEFT", subItem, "TOPRIGHT", 2, 0)
          subItem.submenu:Show()
          submenu.activeSubmenu = subItem.submenu
        end
      end)
      
      subItem:SetScript("OnLeave", function()
        subBg:SetVertexColor(0.2, 0.2, 0.2, 0)
      end)
      
      if not hasNestedSubmenu and subOnClick then
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
    self.finalized = true
  end
  
  -- Register menu if requested
  if shouldRegister then
    OGST.MenuRegistry[menuName] = menu
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
-- TODO: Fix scrollChild width calculation when outerFrame is sized via fillBelow anchoring
-- The scrollChild needs to properly fill the scrollFrame width when the list is dynamically sized
-- Current workaround: Use static width/height instead of relying on anchor-based sizing
function OGST.CreateStyledScrollList(parent, width, height, hideScrollBar)
  if not parent then return nil end
  
  -- Outer container frame with backdrop
  local outerFrame = CreateFrame("Frame", nil, parent)
  -- Only set explicit size if non-zero (allow anchor system to handle sizing)
  if width and width > 0 then
    outerFrame:SetWidth(width)
  end
  if height and height > 0 then
    outerFrame:SetHeight(height)
  end
  outerFrame:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 12,
    insets = {left = 3, right = 3, top = 3, bottom = 3}
  })
  outerFrame:SetBackdropColor(0.15, 0.15, 0.15, 0.9)
  
  -- Mark for design mode system
  outerFrame.hasDesignBorder = true
  outerFrame.designBorderColor = {r = 1, g = 0, b = 0}  -- Red
  outerFrame.normalBorderColor = {r = 0.4, g = 0.4, b = 0.4, a = 1}
  outerFrame.removeBackdropWhenNotDesigning = false  -- Keep backdrop always
  
  -- Design mode border
  if OGST.DESIGN_MODE then
    outerFrame:SetBackdropBorderColor(1, 0, 0, 1)
  end
  OGST.AddDesignTooltip(outerFrame, "Scroll List Container", "Frame")
  
  -- Adjust content width based on whether scrollbar will be shown
  -- If width is 0 or not set, use default of 175 for calculations
  local effectiveWidth = (width and width > 0) and width or 175
  local scrollBarWidth = 20
  local baseContentWidth = effectiveWidth - 10
  local contentWidthWithScroll = baseContentWidth - scrollBarWidth
  local contentWidthNoScroll = baseContentWidth
  
  -- Scroll frame inside the outer frame
  local scrollFrame = CreateFrame("ScrollFrame", nil, outerFrame)
  scrollFrame:SetPoint("TOPLEFT", outerFrame, "TOPLEFT", 5, -5)
  -- Initial right edge - will be adjusted by UpdateScrollBar
  if hideScrollBar then
    scrollFrame:SetPoint("BOTTOMRIGHT", outerFrame, "BOTTOMRIGHT", -5, 5)
  else
    scrollFrame:SetPoint("BOTTOMRIGHT", outerFrame, "BOTTOMRIGHT", -(5 + scrollBarWidth), 5)
  end
  
  -- Mark for design mode system
  scrollFrame.hasDesignBorder = true
  scrollFrame.designBorderColor = {r = 0, g = 1, b = 0}  -- Green
  scrollFrame.removeBackdropWhenNotDesigning = true
  
  -- Design mode border
  if OGST.DESIGN_MODE then
    scrollFrame:SetBackdrop({
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      edgeSize = 16,
      insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    scrollFrame:SetBackdropBorderColor(0, 1, 0, 1)
  end
  OGST.AddDesignTooltip(scrollFrame, "Scroll Frame", "ScrollFrame")
  
  -- Scroll child
  local scrollChild = CreateFrame("Frame", nil, scrollFrame)
  -- Start with width that accounts for scrollbar
  scrollChild:SetWidth(hideScrollBar and contentWidthNoScroll or contentWidthWithScroll)
  scrollChild:SetHeight(1)
  scrollFrame:SetScrollChild(scrollChild)
  
  -- Mark for design mode system
  scrollChild.hasDesignBorder = true
  scrollChild.designBorderColor = {r = 0, g = 0, b = 1}  -- Blue
  scrollChild.removeBackdropWhenNotDesigning = true
  
  -- Design mode border
  if OGST.DESIGN_MODE then
    scrollChild:SetBackdrop({
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      edgeSize = 16,
      insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    scrollChild:SetBackdropBorderColor(0, 0, 1, 1)
  end
  OGST.AddDesignTooltip(scrollChild, "Scroll Child (Content)", "Frame")
  
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
  
  -- Function to update scrollbar when content changes
  local function UpdateScrollBar()
    local maxScroll = scrollChild:GetHeight() - scrollFrame:GetHeight()
    if maxScroll > 0 and not hideScrollBar then
      -- Need scrollbar - adjust scrollFrame to make room and show scrollbar
      scrollFrame:ClearAllPoints()
      scrollFrame:SetPoint("TOPLEFT", outerFrame, "TOPLEFT", 5, -5)
      scrollFrame:SetPoint("BOTTOMRIGHT", outerFrame, "BOTTOMRIGHT", -(5 + scrollBarWidth), 5)
      scrollChild:SetWidth(contentWidthWithScroll)
      scrollBar:SetMinMaxValues(0, maxScroll)
      scrollBar:Show()
    else
      -- No scrollbar needed - expand scrollFrame and hide scrollbar
      scrollFrame:ClearAllPoints()
      scrollFrame:SetPoint("TOPLEFT", outerFrame, "TOPLEFT", 5, -5)
      scrollFrame:SetPoint("BOTTOMRIGHT", outerFrame, "BOTTOMRIGHT", -5, 5)
      scrollChild:SetWidth(contentWidthNoScroll)
      scrollBar:Hide()
      scrollFrame:SetVerticalScroll(0)
    end
  end
  
  -- Store update function on frames for external use
  scrollFrame.UpdateScrollBar = UpdateScrollBar
  scrollChild.UpdateScrollBar = UpdateScrollBar
  outerFrame.UpdateScrollBar = UpdateScrollBar
  
  -- Function to recalculate content width based on current outerFrame size
  local function RecalculateContentWidth()
    -- Get outerFrame width (this is reliable even with anchors if explicitly set)
    local currentOuterWidth = outerFrame:GetWidth()
    
    if currentOuterWidth and currentOuterWidth > 0 then
      -- scrollFrame is inset by 5px on left, and 5px + scrollBarWidth on right
      -- So scrollChild should be: outerFrame width - 10 (left/right padding) - scrollBarWidth (if shown)
      local scrollFrameWidth = currentOuterWidth - 10  -- Left 5px + right 5px padding
      if not hideScrollBar and scrollBar:IsShown() then
        scrollFrameWidth = scrollFrameWidth - scrollBarWidth
      end
      
      -- Set scrollChild width
      scrollChild:SetWidth(scrollFrameWidth)
      
      -- Update stored contentWidth
      outerFrame.contentWidth = scrollFrameWidth
      scrollChild.contentWidth = scrollFrameWidth
      
      -- Update all existing items to match new width
      for _, item in ipairs(outerFrame.items) do
        item:SetWidth(scrollFrameWidth)
      end
    end
  end
  
  outerFrame.RecalculateContentWidth = RecalculateContentWidth
  
  -- Add OnSizeChanged handler to update scrollChild width when outer frame is resized
  outerFrame:SetScript("OnSizeChanged", function()
    this:RecalculateContentWidth()
  end)
  
  -- Add OnShow handler to recalculate width and update items when frame is first shown
  -- This is needed because fillBelow anchoring sets frame size asynchronously
  outerFrame:SetScript("OnShow", function()
    -- Delay slightly to allow anchor system to calculate sizes
    this:SetScript("OnUpdate", function()
      this:SetScript("OnUpdate", nil)
      this:RecalculateContentWidth()
    end)
  end)
  
  -- Store scrollChild, scrollFrame, scrollBar and contentWidth for external access
  outerFrame.scrollChild = scrollChild
  outerFrame.scrollFrame = scrollFrame
  outerFrame.scrollBar = scrollBar
  outerFrame.contentWidth = scrollChild:GetWidth()
  scrollChild.contentWidth = scrollChild:GetWidth()  -- Also store on scrollChild for CreateStyledListItem
  
  -- Add list management methods
  outerFrame.items = {}
  
  function outerFrame:Clear()
    for _, item in ipairs(self.items) do
      item:Hide()
      item:SetParent(nil)
    end
    self.items = {}
    scrollChild:SetHeight(1)
  end
  
  function outerFrame:AddItem(itemOrConfig)
    local item
    local config
    
    -- Check if parameter is a table config or an existing frame
    if type(itemOrConfig) == "table" and not itemOrConfig.GetObjectType then
      -- It's a config table, create the item
      config = itemOrConfig
      item = OGST.CreateStyledListItem(outerFrame, config.width, config.height, config.frameType or "Button", config)
      
      -- Store reference to parent list for selection management
      item.parentList = outerFrame
      
      -- Wrap click handler to manage selection state
      local userOnClick = config.onClick
      item:SetScript("OnClick", function()
        -- Deselect all items in this list
        for _, listItem in ipairs(outerFrame.items) do
          OGST.SetListItemSelected(listItem, false)
        end
        
        -- Select this item
        OGST.SetListItemSelected(this, true)
        
        -- Call user's onClick if provided
        if userOnClick then
          userOnClick()
        end
      end)
    else
      -- It's an existing frame
      item = itemOrConfig
      config = {}
    end
    
    table.insert(self.items, item)
    item:SetParent(scrollChild)
    
    -- Recalculate content width in case outer frame was resized after creation
    self:RecalculateContentWidth()
    
    -- Update item width to match current contentWidth
    item:SetWidth(self.contentWidth)
    
    -- Add up/down/delete buttons if callbacks provided
    if config.onMoveUp or config.onMoveDown or config.onDelete then
      local hideUpDown = not config.onMoveUp and not config.onMoveDown
      local currentIndex = table.getn(self.items)
      local listLength = currentIndex  -- Will be updated on re-render
      
      OGST.AddListItemButtons(
        item, 
        currentIndex, 
        listLength,
        config.onMoveUp,
        config.onMoveDown,
        config.onDelete,
        hideUpDown,
        config.alwaysEnableButtons
      )
    end
    
    local yOffset = 0
    for i, listItem in ipairs(self.items) do
      listItem:ClearAllPoints()
      listItem:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yOffset)
      listItem:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, -yOffset)
      listItem:Show()
      yOffset = yOffset + (listItem:GetHeight() or 24) + OGST.LIST_ITEM_SPACING
    end
    
    scrollChild:SetHeight(math.max(yOffset, scrollFrame:GetHeight()))
    UpdateScrollBar()
    
    return item
  end
  
  -- Initial update
  UpdateScrollBar()
  
  -- Store scrollChild reference for debugging
  outerFrame.scrollChild = scrollChild
  
  return outerFrame, scrollFrame, scrollChild, scrollBar, scrollChild:GetWidth()
end

-- ============================================
-- LIST ITEMS
-- ============================================

-- CRITICAL: LUA 5.0 CLOSURE SCOPING FOR EVENT HANDLERS
-- =====================================================
-- When creating list items in loops and attaching event handlers (OnClick, OnEnter, etc.),
-- you MUST NOT capture loop variables directly in closures. In Lua 5.0, closures capture
-- REFERENCES to variables, not their VALUES. This causes handlers to use the FINAL iteration
-- value, not the current iteration value.
--
-- WRONG PATTERN (causes nil index errors):
--   for i, action in ipairs(actions) do
--     local item = OGST.CreateStyledListItem(parent, width, height)
--     item:SetScript("OnClick", function()
--       DoSomething(action.name)  -- 'action' refers to the LAST loop iteration!
--     end)
--   end
--
-- CORRECT PATTERN (store data on frame, use 'this' keyword):
--   for i, action in ipairs(actions) do
--     local item = OGST.CreateStyledListItem(parent, width, height)
--     item.actionName = action.name  -- Store data as frame property
--     item.bg = bg  -- Store references to child elements
--     item:SetScript("OnClick", function()
--       DoSomething(this.actionName)  -- Use 'this' to reference the frame
--       this.bg:SetVertexColor(...)   -- Access stored references via 'this'
--     end)
--   end
--
-- KEY RULES:
-- 1. Store any loop data you need as properties on the frame itself (item.myData = loopVar)
-- 2. Use 'this' inside event handlers to reference the frame receiving the event
-- 3. Access stored data via this.myData, not via closure-captured variables
-- 4. This applies to ALL event handlers: OnClick, OnEnter, OnLeave, OnShow, etc.
-- 5. WoW 1.12 uses 'this' (not 'self') - it's automatically set when events fire
--
-- This pattern is MANDATORY for WoW 1.12 / Lua 5.0 compatibility.
-- =====================================================

-- Create a standardized list item with background and hover effects
-- @param parent: Parent frame (if it's a scroll list, automatically uses scrollChild)
-- @param width: Item width (default: parent's contentWidth or 160)
-- @param height: Item height (default: OGST.LIST_ITEM_HEIGHT)
-- @param frameType: "Button" or "Frame" (default: "Button")
-- @return itemFrame: Frame with .bg property for runtime color changes
function OGST.CreateStyledListItem(parent, width, height, frameType, config)
  if not parent then return nil end
  
  config = config or {}
  height = height or OGST.LIST_ITEM_HEIGHT
  frameType = frameType or "Button"
  
  -- If parent has scrollChild, use that as actual parent (for scroll lists)
  local actualParent = parent.scrollChild or parent
  
  -- If parent has contentWidth, use that; otherwise default to 160
  width = width or parent.contentWidth or 160
  
  local item = CreateFrame(frameType, nil, actualParent)
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
  
  -- Add default text if provided
  if config.text then
    item.text = item:CreateFontString(nil, "OVERLAY", config.font or "GameFontHighlight")
    local align = config.textAlign or "LEFT"
    local xOffset = (align == "LEFT" and 5) or (align == "RIGHT" and -5) or 0
    item.text:SetPoint(align, item, align, xOffset, 0)
    item.text:SetText(config.text)
    
    if config.textColor then
      item.text:SetTextColor(config.textColor.r or 1, config.textColor.g or 1, config.textColor.b or 1, config.textColor.a or 1)
    else
      item.text:SetTextColor(1, 1, 1, 1)  -- Default white (GameFontHighlight color)
    end
    
    -- Set text width to prevent overflow
    if align == "LEFT" or align == "RIGHT" then
      item.text:SetWidth(width - 10)  -- 5px padding on each side
      item.text:SetJustifyH(align)
    end
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
-- @param alwaysEnableButtons: Optional boolean, if true buttons are never disabled based on position
-- @return deleteButton, downButton, upButton
function OGST.AddListItemButtons(listItem, index, listLength, onMoveUp, onMoveDown, onDelete, hideUpDown, alwaysEnableButtons)
  if not listItem then return nil, nil, nil end
  
  local buttonSize = 32
  local buttonSpacing = -10
  
  -- Delete button (X mark)
  local deleteBtn = CreateFrame("Button", nil, listItem)
  deleteBtn:SetWidth(buttonSize)
  deleteBtn:SetHeight(buttonSize)
  deleteBtn:SetPoint("RIGHT", listItem, "RIGHT", -2, 0)
  deleteBtn:SetFrameLevel(listItem:GetFrameLevel() + 2)  -- Ensure button is above other elements
  deleteBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
  deleteBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight", "ADD")
  deleteBtn:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
  
  if onDelete then
    deleteBtn:SetScript("OnClick", onDelete)
  else
    deleteBtn:Hide()  -- Hide button if no callback
  end
  
  if hideUpDown then
    return deleteBtn, nil, nil
  end
  
  -- Determine anchor point for up/down buttons
  local anchorFrame = listItem
  local anchorPoint = "RIGHT"
  local anchorOffset = -2
  
  -- If delete button is visible, anchor to it instead
  if onDelete then
    anchorFrame = deleteBtn
    anchorPoint = "LEFT"
    anchorOffset = -buttonSpacing
  end
  
  -- Down button
  local downBtn = CreateFrame("Button", nil, listItem)
  downBtn:SetWidth(buttonSize)
  downBtn:SetHeight(buttonSize)
  downBtn:SetPoint("RIGHT", anchorFrame, anchorPoint, anchorOffset, 0)
  downBtn:SetNormalTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up")
  downBtn:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
  downBtn:SetPushedTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Down")
  downBtn:SetDisabledTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Disabled")
  
  if not alwaysEnableButtons and index >= listLength then
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
  
  if not alwaysEnableButtons and index <= 1 then
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

-- Create a single-line text input box with backdrop and optional label
-- @param parent: Parent frame
-- @param width: Text box width
-- @param height: Text box height (default: 24)
-- @param config: Optional configuration table
--   - align: "LEFT", "CENTER", or "RIGHT" (default: "LEFT")
--   - maxLetters: Maximum number of characters (default: 0 = unlimited)
--   - numeric: Only allow numeric input (default: false)
--   - font: Font object (default: ChatFontNormal)
--   - onChange: Callback function(text) when text changes
--   - onEnter: Callback function(text) when Enter is pressed
--   - onEscape: Callback function() when Escape is pressed
--   - autoFocus: Auto-focus on creation (default: false)
--   - label: Label text (optional)
--   - labelAnchor: "TOP-LEFT", "TOP-RIGHT", "BOTTOM-LEFT", "BOTTOM-RIGHT", "LEFT", "RIGHT" (default: "LEFT")
--   - labelFont: Font object for label (default: GameFontNormalSmall)
--   - labelColor: RGB table {r, g, b} (default: {r=1, g=1, b=1})
-- @return backdrop, editBox, labelText
function OGST.CreateSingleLineTextBox(parent, width, height, config)
  if not parent then return nil end
  
  height = height or 24
  config = config or {}
  
  -- Container frame (wraps label and textbox with padding)
  local container = CreateFrame("Frame", nil, parent)
  local labelWidth = config.labelWidth or 0
  local textBoxWidth = config.textBoxWidth or width
  local gap = config.gap or 5
  local padding = config.padding or 5
  local fillWidth = textBoxWidth == "Fill"
  
  -- Store anchor gap as property for use with AnchorElement
  container.anchorGap = config.anchorGap or -12
  
  -- Calculate container width based on layout
  if fillWidth then
    -- Fill width - will be anchored to parent edges
    container:SetPoint("LEFT", parent, "LEFT", padding, 0)
    container:SetPoint("RIGHT", parent, "RIGHT", -padding, 0)
  else
    local totalWidth = textBoxWidth
    if config.label then
      if config.labelAnchor == "LEFT" or config.labelAnchor == "RIGHT" then
        totalWidth = labelWidth + gap + textBoxWidth
      else
        totalWidth = math.max(labelWidth, textBoxWidth)
      end
    end
    container:SetWidth(totalWidth + (padding * 2))
  end
  
  container:SetHeight(height + (padding * 2))
  container:EnableMouse(true)
  
  -- Design mode border for container
  if OGST.DESIGN_MODE then
    container:SetBackdrop({
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      edgeSize = 16,
      insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    container:SetBackdropBorderColor(1, 1, 0, 1)  -- Yellow for textbox container
  end
  -- Mark for dynamic design mode updates
  container.hasDesignBorder = true
  container.designBorderColor = {r = 1, g = 1, b = 0}  -- Yellow
  container.removeBackdropWhenNotDesigning = true  -- Container doesn't need backdrop normally
  
  local tooltipName = config.label or "TextBox Container"
  OGST.AddDesignTooltip(container, tooltipName, "Frame")
  
  -- Backdrop frame (textbox background)
  local backdrop = CreateFrame("Frame", nil, container)
  if not fillWidth then
    backdrop:SetWidth(textBoxWidth)
  end
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
  
  -- Edit box
  local editBox = CreateFrame("EditBox", nil, backdrop)
  editBox:SetPoint("TOPLEFT", 6, -4)
  editBox:SetPoint("BOTTOMRIGHT", -6, 4)
  editBox:SetMultiLine(false)
  editBox:SetAutoFocus(config.autoFocus or false)
  editBox:SetFontObject(config.font or ChatFontNormal)
  
  -- Set alignment
  local align = config.align or "LEFT"
  if align == "CENTER" then
    editBox:SetJustifyH("CENTER")
    editBox:SetTextInsets(5, 5, 0, 0)
  elseif align == "RIGHT" then
    editBox:SetJustifyH("RIGHT")
    editBox:SetTextInsets(5, 5, 0, 0)
  else
    editBox:SetJustifyH("LEFT")
    editBox:SetTextInsets(5, 5, 0, 0)
  end
  
  -- Set max letters
  if config.maxLetters and config.maxLetters > 0 then
    editBox:SetMaxLetters(config.maxLetters)
  end
  
  -- Numeric only validation
  if config.numeric then
    editBox:SetScript("OnTextChanged", function()
      local text = editBox:GetText()
      -- Allow empty, numbers, minus sign, and decimal point
      if text and text ~= "" then
        local filtered = string.gsub(text, "[^0-9%.%-]", "")
        if filtered ~= text then
          editBox:SetText(filtered)
        end
      end
      if config.onChange then
        config.onChange(editBox:GetText())
      end
    end)
  elseif config.onChange then
    editBox:SetScript("OnTextChanged", function()
      config.onChange(editBox:GetText())
    end)
  end
  
  -- Enter key handler
  editBox:SetScript("OnEnterPressed", function()
    if config.onEnter then
      config.onEnter(editBox:GetText())
    end
    editBox:ClearFocus()
  end)
  
  -- Escape key handler
  editBox:SetScript("OnEscapePressed", function()
    if config.onEscape then
      config.onEscape()
    end
    editBox:ClearFocus()
  end)
  
  -- Make the backdrop clickable to focus the editbox
  backdrop:EnableMouse(true)
  backdrop:SetScript("OnMouseDown", function()
    editBox:SetFocus()
  end)
  
  -- Add label if specified
  local labelText = nil
  if config.label then
    labelText = container:CreateFontString(nil, "OVERLAY", config.labelFont or "GameFontNormalSmall")
    labelText:SetText(config.label)
    labelText:SetWidth(labelWidth)
    local labelColor = config.labelColor or {r=1, g=1, b=1}
    labelText:SetTextColor(labelColor.r, labelColor.g, labelColor.b)
    
    -- Label alignment
    local labelAlign = config.labelAlign or "LEFT"
    if labelAlign == "CENTER" then
      labelText:SetJustifyH("CENTER")
    elseif labelAlign == "RIGHT" then
      labelText:SetJustifyH("RIGHT")
    else
      labelText:SetJustifyH("LEFT")
    end
    
    -- Label positioning relative to textbox (with padding offset)
    local anchor = config.labelAnchor or "LEFT"
    if anchor == "TOP-LEFT" then
      labelText:SetPoint("BOTTOMLEFT", backdrop, "TOPLEFT", 2, 2)
      backdrop:SetPoint("TOPLEFT", container, "TOPLEFT", padding, -padding)
    elseif anchor == "TOP-RIGHT" then
      labelText:SetPoint("BOTTOMRIGHT", backdrop, "TOPRIGHT", -2, 2)
      backdrop:SetPoint("TOPRIGHT", container, "TOPRIGHT", -padding, -padding)
    elseif anchor == "BOTTOM-LEFT" then
      labelText:SetPoint("TOPLEFT", backdrop, "BOTTOMLEFT", 2, -2)
      backdrop:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", padding, padding)
    elseif anchor == "BOTTOM-RIGHT" then
      labelText:SetPoint("TOPRIGHT", backdrop, "BOTTOMRIGHT", -2, -2)
      backdrop:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -padding, padding)
    elseif anchor == "LEFT" then
      labelText:SetPoint("LEFT", container, "LEFT", padding, 0)
      if fillWidth then
        backdrop:SetPoint("LEFT", labelText, "RIGHT", gap, 0)
        backdrop:SetPoint("RIGHT", container, "RIGHT", -padding, 0)
      else
        backdrop:SetPoint("LEFT", labelText, "RIGHT", gap, 0)
      end
    elseif anchor == "RIGHT" then
      labelText:SetPoint("RIGHT", container, "RIGHT", -padding, 0)
      if fillWidth then
        backdrop:SetPoint("LEFT", container, "LEFT", padding, 0)
        backdrop:SetPoint("RIGHT", labelText, "LEFT", -gap, 0)
      else
        backdrop:SetPoint("RIGHT", labelText, "LEFT", -gap, 0)
      end
    end
  else
    -- No label, position backdrop to fill container with padding
    if fillWidth then
      backdrop:SetPoint("TOPLEFT", container, "TOPLEFT", padding, -padding)
      backdrop:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -padding, padding)
    else
      backdrop:SetPoint("TOPLEFT", container, "TOPLEFT", padding, -padding)
    end
  end
  
  return container, backdrop, editBox, labelText
end

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
  
  -- Mark for design mode system
  backdrop.hasDesignBorder = true
  backdrop.designBorderColor = {r = 0, g = 1, b = 0}  -- Green
  backdrop.normalBorderColor = {r = 0.4, g = 0.4, b = 0.4, a = 1}
  backdrop.removeBackdropWhenNotDesigning = false  -- Keep backdrop always
  
  -- Design mode border override
  if OGST.DESIGN_MODE then
    backdrop:SetBackdropBorderColor(0, 1, 0, 1)  -- Green for text box
  else
    backdrop:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
  end
  
  OGST.AddDesignTooltip(backdrop, "Scrolling Text Box", "Frame")
  
  -- Store dynamic sizing flags
  backdrop.dynamicWidth = (width == 0)
  backdrop.dynamicHeight = (height == 0)
  
  -- Scroll frame
  local scrollFrame = CreateFrame("ScrollFrame", nil, backdrop)
  scrollFrame:SetPoint("TOPLEFT", 5, -6)
  scrollFrame:SetPoint("BOTTOMRIGHT", -28, 6)
  
  -- Scroll child
  local scrollChild = CreateFrame("Frame", nil, scrollFrame)
  scrollFrame:SetScrollChild(scrollChild)
  
  local contentWidth
  if width > 0 then
    contentWidth = width - 5 - 28 - 5
    scrollChild:SetWidth(contentWidth)
  else
    -- Dynamic width - will be calculated on show
    contentWidth = 1
    scrollChild:SetWidth(contentWidth)
  end
  scrollChild:SetHeight(800)
  
  -- Edit box
  local editBox = CreateFrame("EditBox", nil, scrollChild)
  editBox:SetPoint("TOPLEFT", 0, 0)
  editBox:SetWidth(contentWidth)
  editBox:SetHeight(800)
  editBox:SetMultiLine(true)
  editBox:SetAutoFocus(false)
  editBox:SetFontObject(ChatFontNormal)
  editBox:SetTextColor(1, 1, 1, 1)
  editBox:SetTextInsets(5, 5, 3, 3)
  editBox:SetScript("OnEscapePressed", function() this:ClearFocus() end)
  
  -- For dynamic sizing, update dimensions when shown or size changes
  if width == 0 or height == 0 then
    backdrop:SetScript("OnShow", function()
      local backdropWidth = this:GetWidth()
      local backdropHeight = this:GetHeight()
      
      if backdropWidth and backdropWidth > 0 and this.dynamicWidth then
        -- scrollFrame takes up: backdrop - 5 (left) - 28 (right/scrollbar)
        local scrollFrameWidth = backdropWidth - 33
        scrollChild:SetWidth(scrollFrameWidth)
        -- Add 40px to the width to work around EditBox wrap width issue
        editBox:SetWidth(scrollFrameWidth + 40)
      end
      
      -- Height doesn't need special handling - scrollChild and editBox handle text height dynamically
    end)
    
    -- Also trigger on size update
    backdrop:SetScript("OnSizeChanged", function()
      local backdropWidth = this:GetWidth()
      local backdropHeight = this:GetHeight()
      
      if backdropWidth and backdropWidth > 0 and this.dynamicWidth then
        local scrollFrameWidth = backdropWidth - 33
        scrollChild:SetWidth(scrollFrameWidth)
        editBox:SetWidth(scrollFrameWidth + 40)
      end
    end)
  end
  
  
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
    -- Update heights based on text content
    local text = editBox:GetText()
    if text and text ~= "" then
      -- Count lines
      local lines = 1
      local _, count = string.gsub(text, "\n", "\n")
      lines = lines + count
      
      -- Estimate height (each line ~14px with ChatFontNormal)
      local textHeight = math.max(lines * 14 + 20, 800)
      editBox:SetHeight(textHeight)
      scrollChild:SetHeight(textHeight)
    end
    
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
-- CHECKBOX
-- ============================================

-- Create a checkbox with optional label
-- @param parent: Parent frame
-- @param config: Optional configuration table
--   - label: Label text (optional)
--   - labelAnchor: "LEFT" or "RIGHT" (default: "RIGHT")
--   - labelFont: Font object for label (default: GameFontNormalSmall)
--   - labelColor: RGB table {r, g, b} (default: {r=1, g=1, b=1})
--   - labelWidth: Width for label (default: auto-size based on text)
--   - gap: Distance between checkbox and label (default: 5)
--   - padding: Container padding (default: 5)
--   - checked: Initial checked state (default: false)
--   - onChange: Callback function(isChecked) when state changes
--   - disabled: Initial disabled state (default: false)
--   - anchorGap: Gap for use with AnchorElement (default: -12)
-- @return container, checkButton, labelText
function OGST.CreateCheckbox(parent, config)
  if not parent then return nil end
  
  config = config or {}
  
  local gap = config.gap or 5
  local padding = config.padding or 5
  local labelWidth = config.labelWidth or 0
  local checkSize = 24  -- Standard checkbox size
  
  -- Container frame
  local container = CreateFrame("Frame", nil, parent)
  container:EnableMouse(true)
  
  -- Store anchor gap as property for use with AnchorElement
  container.anchorGap = config.anchorGap or -12
  
  -- Calculate container dimensions
  local containerWidth = checkSize
  local containerHeight = checkSize
  
  if config.label then
    if config.labelAnchor == "LEFT" then
      containerWidth = labelWidth + gap + checkSize
    else  -- RIGHT (default)
      containerWidth = checkSize + gap + labelWidth
    end
  end
  
  container:SetWidth(containerWidth + (padding * 2))
  container:SetHeight(containerHeight + (padding * 2))
  
  -- Mark for design mode system
  container.hasDesignBorder = true
  container.designBorderColor = {r = 1, g = 0.5, b = 0}  -- Orange
  container.removeBackdropWhenNotDesigning = true  -- Checkboxes don't need backdrop normally
  
  -- Design mode border for container
  if OGST.DESIGN_MODE then
    container:SetBackdrop({
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      edgeSize = 16,
      insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    container:SetBackdropBorderColor(1, 0.5, 0, 1)  -- Orange for checkbox container
  end
  local tooltipName = config.label or "Checkbox Container"
  OGST.AddDesignTooltip(container, tooltipName, "Frame")
  
  -- Create checkbox button
  local checkButton = CreateFrame("CheckButton", nil, container)
  checkButton:SetWidth(checkSize)
  checkButton:SetHeight(checkSize)
  
  -- Set textures for checkbox
  checkButton:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
  checkButton:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
  checkButton:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight")
  checkButton:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
  checkButton:SetDisabledCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check-Disabled")
  
  -- Set initial state
  checkButton:SetChecked(config.checked or false)
  if config.disabled then
    checkButton:Disable()
  end
  
  -- Add label if specified
  local labelText = nil
  if config.label then
    labelText = container:CreateFontString(nil, "OVERLAY", config.labelFont or "GameFontNormalSmall")
    labelText:SetText(config.label)
    
    -- Auto-size label width if not specified
    if labelWidth == 0 then
      labelWidth = labelText:GetStringWidth() + 5
      labelText:SetWidth(labelWidth)
      
      -- Recalculate container width with actual label width
      if config.labelAnchor == "LEFT" then
        containerWidth = labelWidth + gap + checkSize
      else
        containerWidth = checkSize + gap + labelWidth
      end
      container:SetWidth(containerWidth + (padding * 2))
    else
      labelText:SetWidth(labelWidth)
    end
    
    local labelColor = config.labelColor or {r=1, g=1, b=1}
    labelText:SetTextColor(labelColor.r, labelColor.g, labelColor.b)
    labelText:SetJustifyH("LEFT")
    
    -- Position label and checkbox based on labelAnchor
    local anchor = config.labelAnchor or "RIGHT"
    if anchor == "LEFT" then
      -- Label on left, checkbox on right
      labelText:SetPoint("LEFT", container, "LEFT", padding, 0)
      checkButton:SetPoint("LEFT", labelText, "RIGHT", gap, 0)
    else
      -- Checkbox on left, label on right (default)
      checkButton:SetPoint("LEFT", container, "LEFT", padding, 0)
      labelText:SetPoint("LEFT", checkButton, "RIGHT", gap, 0)
    end
    
    -- Make container clickable to toggle checkbox
    container:SetScript("OnMouseDown", function()
      if not checkButton:IsEnabled() then return end
      checkButton:Click()
    end)
  else
    -- No label, center checkbox in container
    checkButton:SetPoint("CENTER", container, "CENTER", 0, 0)
  end
  
  -- OnClick handler
  checkButton:SetScript("OnClick", function()
    if config.onChange then
      config.onChange(this:GetChecked() == 1)
    end
  end)
  
  return container, checkButton, labelText
end

-- ============================================
-- MENU BUTTON
-- ============================================

-- Create a menu button that combines a styled button with a dropdown menu
-- @param parent: Parent frame
-- @param config: Configuration table
--   - label: Label text (optional)
--   - labelAnchor: "LEFT" or "RIGHT" (default: "LEFT")
--   - labelFont: Font object for label (default: GameFontNormalSmall)
--   - labelColor: RGB table {r, g, b} (default: {r=1, g=1, b=1})
--   - labelWidth: Width for label (default: auto-size based on text)
--   - buttonText: Text displayed on button (required)
--   - buttonWidth: Button width (default: 100)
--   - buttonHeight: Button height (default: 24)
--   - gap: Distance between label and button (default: 5)
--   - padding: Container padding (default: 5)
--   - menuItems: Array of menu item configs (required)
--     Each item: {text, onClick, selected}
--   - anchorGap: Gap for use with AnchorElement (default: -12)
-- @return container, button, menu, labelText
function OGST.CreateMenuButton(parent, config)
  if not parent then return nil end
  
  config = config or {}
  
  if not config.buttonText or not config.menuItems then
    DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OGST:|r CreateMenuButton requires buttonText and menuItems")
    return nil
  end
  
  local gap = config.gap or 5
  local padding = config.padding or 5
  local labelWidth = config.labelWidth or 0
  local buttonWidth = config.buttonWidth or 100
  local buttonHeight = config.buttonHeight or 24
  local fillWidth = config.fillWidth or false
  local singleSelect = config.singleSelect or false
  
  -- Container frame
  local container = CreateFrame("Frame", nil, parent)
  container:EnableMouse(true)
  
  -- Store anchor gap as property for use with AnchorElement
  container.anchorGap = config.anchorGap or -12
  
  -- CreateMenuButton has internal padding, so default anchor offsets should be 0
  container._anchorOffset = 0
  
  -- Calculate container dimensions
  local containerWidth = buttonWidth
  local containerHeight = buttonHeight
  
  if fillWidth then
    -- Fill parent width with padding
    container:SetPoint("LEFT", parent, "LEFT", padding, 0)
    container:SetPoint("RIGHT", parent, "RIGHT", -padding, 0)
    container:SetHeight(containerHeight + (padding * 2))
  else
    -- Fixed width mode (original behavior)
    if config.label then
      if config.labelAnchor == "RIGHT" then
        containerWidth = buttonWidth + gap + labelWidth
      else  -- LEFT (default)
        containerWidth = labelWidth + gap + buttonWidth
      end
    end
    
    container:SetWidth(containerWidth + (padding * 2))
    container:SetHeight(containerHeight + (padding * 2))
  end
  
  -- Design mode border for container
  container.hasDesignBorder = true
  container.designBorderColor = {r = 0, g = 1, b = 1}  -- Cyan
  container.removeBackdropWhenNotDesigning = true
  
  if OGST.DESIGN_MODE then
    container:SetBackdrop({
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      edgeSize = 16,
      insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    container:SetBackdropBorderColor(0, 1, 1, 1)  -- Cyan for menu button container
  end
  local tooltipName = config.label or "MenuButton Container"
  OGST.AddDesignTooltip(container, tooltipName, "Frame")
  
  -- Create button
  local button = CreateFrame("Button", nil, container, "UIPanelButtonTemplate")
  
  if not fillWidth then
    -- Fixed width mode: set explicit width
    button:SetWidth(buttonWidth)
  end
  
  button:SetHeight(buttonHeight)
  button:SetText(config.buttonText)
  OGST.StyleButton(button)
  
  -- Create menu
  local menuName = "OGST_MenuButton_" .. tostring(container)
  local menu = OGST.CreateStandardMenu({
    name = menuName,
    width = buttonWidth,
    register = false
  })
  
  -- Track selected items (supports multiple selections)
  container.selectedItems = {}
  
  -- Add menu items
  for _, itemConfig in ipairs(config.menuItems) do
    -- Capture itemConfig in a local scope for the closure
    local capturedConfig = itemConfig
    
    -- Create and store the click handler for this item
    capturedConfig._internalOnClick = function()
      -- Ensure container and selectedItems exist
      if not container or not container.selectedItems then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OGST MenuButton Error:|r Container or selectedItems is nil")
        return
      end
      
      -- Handle single-select mode: clear all selections first
      if singleSelect then
        container.selectedItems = {}
      end
      
      -- Toggle selected state for this item
      local isCurrentlySelected = false
      for i, selected in ipairs(container.selectedItems) do
        if selected == capturedConfig then
          isCurrentlySelected = true
          table.remove(container.selectedItems, i)
          break
        end
      end
      
      if not isCurrentlySelected then
        table.insert(container.selectedItems, capturedConfig)
      end
      
      -- Rebuild menu to update colors
      OGST.RebuildMenuButton(container, button, menu, config)
      
      -- Call user callback
      if capturedConfig.onClick then
        capturedConfig.onClick()
      end
    end
    
    local item = menu:AddItem({
      text = capturedConfig.text,
      onClick = capturedConfig._internalOnClick
    })
    
    -- Mark initially selected items
    if itemConfig.selected then
      table.insert(container.selectedItems, itemConfig)
    end
  end
  
  menu:Finalize()
  
  -- Button opens menu
  button:SetScript("OnClick", function()
    if menu:IsShown() then
      menu:Hide()
    else
      menu:ClearAllPoints()
      menu:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -2)
      menu:Show()
    end
  end)
  
  -- Add label if specified
  local labelText = nil
  if config.label then
    labelText = container:CreateFontString(nil, "OVERLAY", config.labelFont or "GameFontNormalSmall")
    labelText:SetText(config.label)
    
    -- Auto-size label width if not specified
    if labelWidth == 0 then
      labelWidth = labelText:GetStringWidth() + 5
      labelText:SetWidth(labelWidth)
      
      -- Recalculate container width with actual label width
      if config.labelAnchor == "RIGHT" then
        containerWidth = buttonWidth + gap + labelWidth
      else
        containerWidth = labelWidth + gap + buttonWidth
      end
      container:SetWidth(containerWidth + (padding * 2))
    else
      labelText:SetWidth(labelWidth)
    end
    
    local labelColor = config.labelColor or {r=1, g=1, b=1}
    labelText:SetTextColor(labelColor.r, labelColor.g, labelColor.b)
    labelText:SetJustifyH("LEFT")
    labelText:SetJustifyV("MIDDLE")
    
    -- Position label and button based on labelAnchor
    local anchor = config.labelAnchor or "LEFT"
    if anchor == "RIGHT" then
      -- Button on left, label on right
      button:ClearAllPoints()
      button:SetPoint("LEFT", container, "LEFT", padding, 0)
      labelText:SetPoint("LEFT", button, "RIGHT", gap, 0)
      
      if fillWidth then
        button:SetPoint("RIGHT", labelText, "LEFT", -gap, 0)
      else
        -- Constrain button to container
        button:SetPoint("RIGHT", container, "RIGHT", -padding, 0)
      end
    else
      -- Label on left, button on right (default)
      labelText:SetPoint("LEFT", container, "LEFT", padding, 0)
      button:ClearAllPoints()
      button:SetPoint("LEFT", labelText, "RIGHT", gap, 0)
      
      if fillWidth then
        button:SetPoint("RIGHT", container, "RIGHT", -padding, 0)
      else
        -- Constrain button to container
        button:SetPoint("RIGHT", container, "RIGHT", -padding, 0)
      end
    end
  else
    -- No label, position button
    button:ClearAllPoints()
    button:SetPoint("LEFT", container, "LEFT", padding, 0)
    
    if fillWidth then
      button:SetPoint("RIGHT", container, "RIGHT", -padding, 0)
    else
      -- Constrain button to container
      button:SetPoint("RIGHT", container, "RIGHT", -padding, 0)
    end
  end
  
  -- Store references
  container.button = button
  container.menu = menu
  container.config = config
  
  -- Apply selected state coloring
  OGST.RebuildMenuButton(container, button, menu, config)
  
  return container, button, menu, labelText
end

-- Rebuild menu button items with updated selection state
-- @param container: Container frame
-- @param button: Button frame
-- @param menu: Menu frame
-- @param config: Original config
function OGST.RebuildMenuButton(container, button, menu, config)
  if not container or not menu or not config then return end
  
  -- Ensure selectedItems is initialized
  if not container.selectedItems then
    container.selectedItems = {}
  end
  
  -- Clear existing items
  if menu.items then
    for _, item in ipairs(menu.items) do
      if item then
        item:Hide()
        item:SetParent(nil)
      end
    end
  end
  menu.items = {}
  menu.yOffset = config.title and -28 or -8
  
  -- Re-add items with updated colors
  for _, itemConfig in ipairs(config.menuItems) do
    -- Check if this item is selected
    local isSelected = false
    if container.selectedItems then
      for _, selected in ipairs(container.selectedItems) do
        if selected == itemConfig then
          isSelected = true
          break
        end
      end
    end
    
    -- Store the click handler that was created at initialization
    local storedOnClick = itemConfig._internalOnClick
    
    local item = menu:AddItem({
      text = itemConfig.text,
      onClick = storedOnClick
    })
    
    -- Set green color for selected items (only if item was successfully created)
    if item and isSelected and item.fs then
      item.fs:SetTextColor(0.2, 1, 0.2)  -- Green for selected
    end
  end
  
  if menu and menu.Finalize then
    menu:Finalize()
  end
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

-- ============================================
-- DIALOG
-- ============================================

-- Create a modal dialog with backdrop, title, content frame, and configurable buttons
-- @param config: Configuration table
--   - title: Dialog title text (default: "Dialog")
--   - width: Dialog width in pixels (default: 400)
--   - height: Dialog height in pixels (default: 200)
--   - content: Optional string for simple text content (creates FontString)
--   - buttons: Array of button configs {text="OK", onClick=function}
--              Default: single OK button that closes dialog
--   - onClose: Optional callback when dialog closes
--   - escapeCloses: Whether ESC key closes dialog (default: true)
-- @return Table with: dialog (main frame), backdrop, contentFrame, buttons (array of button frames)
function OGST.CreateDialog(config)
  if not config then config = {} end
  
  local title = config.title or "Dialog"
  local width = config.width or 400
  local height = config.height or 200
  local buttons = config.buttons
  local onClose = config.onClose
  local escapeCloses = config.escapeCloses
  if escapeCloses == nil then escapeCloses = true end
  
  -- Default to single OK button if no buttons specified
  if not buttons or table.getn(buttons) == 0 then
    buttons = {{text = "OK", onClick = nil}}
  end
  
  -- Create backdrop (modal overlay) with unique name for ESC handling
  local uniqueName = "OGST_Dialog_" .. date("%Y%m%d%H%M%S") .. math.random(1000, 9999)
  local backdrop = CreateFrame("Frame", uniqueName, UIParent)
  backdrop:SetFrameStrata("FULLSCREEN_DIALOG")
  backdrop:SetAllPoints(UIParent)
  backdrop:EnableMouse(true) -- Blocks clicks to frames below
  backdrop:SetScript("OnMouseDown", function() end) -- Eat clicks
  
  -- Dim effect
  local backdropTex = backdrop:CreateTexture(nil, "BACKGROUND")
  backdropTex:SetAllPoints(backdrop)
  backdropTex:SetTexture(0, 0, 0, 0.7)
  
  -- Create dialog frame
  local dialog = CreateFrame("Frame", nil, backdrop)
  dialog:SetFrameStrata("FULLSCREEN_DIALOG")
  dialog:SetFrameLevel(backdrop:GetFrameLevel() + 1)
  dialog:SetWidth(width)
  dialog:SetHeight(height)
  dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  dialog:EnableMouse(true)
  
  -- Dialog background with rounded corners (OGST standard)
  dialog:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 }
  })
  dialog:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
  dialog:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
  
  -- Title bar
  local titleBar = CreateFrame("Frame", nil, dialog)
  titleBar:SetHeight(32)
  titleBar:SetPoint("TOPLEFT", dialog, "TOPLEFT", 4, -4)
  titleBar:SetPoint("TOPRIGHT", dialog, "TOPRIGHT", -4, -4)
  
  -- Title bar background with rounded top corners
  titleBar:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    tile = true,
    tileSize = 16
  })
  titleBar:SetBackdropColor(0.2, 0.2, 0.2, 1)
  
  local titleText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  titleText:SetPoint("LEFT", titleBar, "LEFT", 10, 0)
  titleText:SetText(title)
  titleText:SetTextColor(1, 0.82, 0, 1)
  
  -- Content frame (where custom UI or text goes)
  local contentFrame = CreateFrame("Frame", nil, dialog)
  contentFrame:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 10, -10)
  contentFrame:SetPoint("BOTTOMRIGHT", dialog, "BOTTOMRIGHT", -10, 45) -- Leave space for buttons
  
  -- If simple text content provided, create FontString
  if config.content and type(config.content) == "string" then
    local contentText = contentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    contentText:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, 0)
    contentText:SetPoint("TOPRIGHT", contentFrame, "TOPRIGHT", 0, 0)
    contentText:SetJustifyH("LEFT")
    contentText:SetJustifyV("TOP")
    contentText:SetText(config.content)
    contentText:SetTextColor(1, 1, 1, 1)
  end
  
  -- Button row at bottom
  local buttonCount = table.getn(buttons)
  local buttonWidth = 100
  local buttonHeight = 24
  local buttonSpacing = 10
  local totalButtonWidth = (buttonCount * buttonWidth) + ((buttonCount - 1) * buttonSpacing)
  local startX = (width - totalButtonWidth) / 2
  
  local buttonFrames = {}
  for i = 1, buttonCount do
    local btnConfig = buttons[i]
    local btn = CreateFrame("Button", nil, dialog)
    btn:SetWidth(buttonWidth)
    btn:SetHeight(buttonHeight)
    
    local xOffset = startX + ((i - 1) * (buttonWidth + buttonSpacing))
    btn:SetPoint("BOTTOMLEFT", dialog, "BOTTOMLEFT", xOffset, 10)
    
    -- Style button
    OGST.StyleButton(btn)
    
    -- Set button text with gold color (default OGST style)
    local btnText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btnText:SetPoint("CENTER", btn, "CENTER", 0, 0)
    btnText:SetText(btnConfig.text or "Button")
    btnText:SetTextColor(1, 0.82, 0, 1)
    btn.text = btnText
    
    -- Button click handler
    btn:SetScript("OnClick", function()
      if btnConfig.onClick and type(btnConfig.onClick) == "function" then
        btnConfig.onClick()
      end
      -- Close dialog after button click
      backdrop:Hide()
    end)
    
    table.insert(buttonFrames, btn)
  end
  
  -- Close function
  local function CloseDialog()
    if onClose and type(onClose) == "function" then
      onClose()
    end
    backdrop:Hide()
  end
  
  -- ESC key handling - use custom key handler instead of UISpecialFrames
  if escapeCloses then
    backdrop:EnableKeyboard(true)
    backdrop:SetScript("OnKeyDown", function()
      if arg1 == "ESCAPE" then
        CloseDialog()
      end
    end)
    
    -- Hook OnHide to call onClose callback
    if onClose and type(onClose) == "function" then
      backdrop:SetScript("OnHide", onClose)
    end
  end
  
  -- Store references
  dialog.backdrop = backdrop
  dialog.contentFrame = contentFrame
  dialog.buttons = buttonFrames
  dialog.Close = CloseDialog
  
  -- Return full structure
  return {
    dialog = dialog,
    backdrop = backdrop,
    contentFrame = contentFrame,
    buttons = buttonFrames,
    Close = CloseDialog
  }
end

-- ============================================
-- STATIC TEXT
-- ============================================

-- Create a static text display (FontString wrapper)
-- @param parent: Parent frame
-- @param config: Configuration table
--   - text: Text to display (default: "")
--   - font: Font template (default: "GameFontNormal")
--   - color: RGBA table {r, g, b, a} (default: white {1, 1, 1, 1})
--   - align: Horizontal justification "LEFT", "CENTER", "RIGHT" (default: "LEFT")
--   - valign: Vertical justification "TOP", "MIDDLE", "BOTTOM" (default: "TOP")
--   - multiline: Enable word wrap for multiple lines (default: false)
--   - width: Width in pixels (required for multiline)
--   - height: Height in pixels (optional)
--   - padding: Internal padding from parent edges (default: 5)
--   - paddingLeft: Left padding (overrides padding, default: 5)
--   - paddingRight: Right padding (overrides padding, default: 5)
--   - paddingTop: Top padding (overrides padding, default: 4)
--   - paddingBottom: Bottom padding (overrides padding, default: 4)
-- @return FontString
function OGST.CreateStaticText(parent, config)
  if not parent or not config then return nil end
  
  local text = config.text or ""
  local font = config.font or "GameFontNormal"
  local color = config.color or {r = 1, g = 0.82, b = 0, a = 1}
  local align = config.align or "LEFT"
  local valign = config.valign or "TOP"
  local multiline = config.multiline or false
  local width = config.width
  local height = config.height
  local padding = config.padding or 5
  local paddingLeft = config.paddingLeft or padding
  local paddingRight = config.paddingRight or padding
  local paddingTop = config.paddingTop or padding
  local paddingBottom = config.paddingBottom or padding
  
  -- Create container frame for design mode border
  local container = CreateFrame("Frame", nil, parent)
  container:EnableMouse(false)
  
  -- Mark for design mode system
  container.hasDesignBorder = true
  container.isStaticText = true  -- Identify as static text for default gap=0 in AnchorElement
  container.designBorderColor = {r = 0, g = 1, b = 0}  -- Green
  container.removeBackdropWhenNotDesigning = true
  
  -- Design mode border for container
  if OGST.DESIGN_MODE then
    container:SetBackdrop({
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      edgeSize = 16,
      insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    container:SetBackdropBorderColor(0, 1, 0, 1)  -- Green for static text
  end
  OGST.AddDesignTooltip(container, (text ~= "" and text) or "Static Text", "Frame")
  
  -- Create FontString
  local fontString = container:CreateFontString(nil, "OVERLAY", font)
  fontString:SetText(text)
  fontString:SetTextColor(color.r, color.g, color.b, color.a or 1)
  fontString:SetJustifyH(align)
  fontString:SetJustifyV(valign)
  
  -- Position fontString within container with padding
  if align == "CENTER" then
    fontString:SetPoint("TOP", container, "TOP", 0, -paddingTop)
    if width then
      fontString:SetWidth(width - paddingLeft - paddingRight)
    end
  elseif align == "RIGHT" then
    fontString:SetPoint("TOPRIGHT", container, "TOPRIGHT", -paddingRight, -paddingTop)
    if width then
      fontString:SetWidth(width - paddingLeft - paddingRight)
    end
  else  -- LEFT or default
    fontString:SetPoint("TOPLEFT", container, "TOPLEFT", paddingLeft, -paddingTop)
    if not width then
      -- Fill horizontally with padding if no width specified
      fontString:SetPoint("TOPRIGHT", container, "TOPRIGHT", -paddingRight, -paddingTop)
    else
      fontString:SetWidth(width - paddingLeft - paddingRight)
    end
  end
  
  -- Set height if specified
  if height then
    fontString:SetHeight(height)
  end
  
  -- Enable word wrap for multiline
  if multiline then
    fontString:SetNonSpaceWrap(true)
  end
  
  -- Size container based on content or make it responsive for multiline
  if multiline and not width then
    -- Multiline without fixed width: container should fill available space, fontString fills container
    -- Don't set fixed width - let caller anchor it with fill=true for responsive behavior
    container:SetHeight(100)  -- Initial height, will grow as text wraps
    
    -- Add OnSizeChanged handler to update fontString width when container resizes
    container:SetScript("OnSizeChanged", function()
      local containerWidth = this:GetWidth()
      if containerWidth > 0 then
        local textWidth = containerWidth - paddingLeft - paddingRight
        if textWidth > 0 then
          fontString:SetWidth(textWidth)
        end
      end
    end)
  else
    -- Single line or fixed width: size container to content
    if width then
      -- If width is specified, container should be exactly that width
      container:SetWidth(width)
      
      -- For multiline with fixed width, fontString already set to width - padding above
      if multiline then
        fontString:SetWidth(width - paddingLeft - paddingRight)
      end
      
      local fsHeight = height or fontString:GetHeight()
      if fsHeight == 0 then
        fsHeight = 20  -- Default fallback height
      end
      
      container:SetHeight(fsHeight + paddingTop + paddingBottom)
    else
      -- No width specified, size to content
      local fsWidth = fontString:GetWidth()
      
      -- Fallback if fontString hasn't been rendered yet
      if fsWidth == 0 then
        fsWidth = 100  -- Default fallback width
      end
      
      local fsHeight = height or fontString:GetHeight()
      if fsHeight == 0 then
        fsHeight = 20  -- Default fallback height
      end
      
      container:SetWidth(fsWidth + paddingLeft + paddingRight)
      container:SetHeight(fsHeight + paddingTop + paddingBottom)
    end
  end
  
  -- Store fontString reference for callers
  container.fontString = fontString
  
  -- Add transparent wrapper methods so container can be used like a FontString
  function container:SetText(newText)
    fontString:SetText(newText)
    -- Container is anchored, no resize needed
  end
  
  function container:GetText()
    return fontString:GetText()
  end
  
  function container:SetTextColor(r, g, b, a)
    fontString:SetTextColor(r, g, b, a or 1)
  end
  
  return container
end

-- ============================================
-- TEXTURE & PANEL UTILITIES
-- ============================================

-- ============================================
-- COLORED PANELS
-- ============================================

-- Create a colored panel with border and background
-- @param parent: Parent frame
-- @param width: Panel width
-- @param height: Panel height
-- @param borderColor: RGB table {r, g, b} for border (optional, default white)
-- @param bgColor: RGBA table {r, g, b, a} for background (optional, default black 0.8)
-- @return Panel frame with .border and .bg texture properties
function OGST.CreateColoredPanel(parent, width, height, borderColor, bgColor)
  local panel = CreateFrame("Frame", nil, parent)
  panel:SetWidth(width)
  panel:SetHeight(height)
  
  borderColor = borderColor or {r = 1, g = 1, b = 1}
  bgColor = bgColor or {r = 0, g = 0, b = 0, a = 0.8}
  
  -- Border texture
  local border = panel:CreateTexture(nil, "BORDER")
  border:SetAllPoints(panel)
  border:SetTexture(borderColor.r, borderColor.g, borderColor.b, 1)
  border:SetVertexColor(borderColor.r, borderColor.g, borderColor.b, 1)
  panel.border = border
  
  -- Background texture (inset for border visibility)
  local bg = panel:CreateTexture(nil, "BACKGROUND")
  bg:SetTexture(bgColor.r, bgColor.g, bgColor.b, bgColor.a)
  bg:SetPoint("TOPLEFT", panel, "TOPLEFT", 2, -2)
  bg:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -2, 2)
  panel.bg = bg
  
  return panel
end

-- Add a centered label to a frame
-- @param frame: Parent frame
-- @param text: Text to display
-- @param font: Font object (optional, default GameFontNormalSmall)
-- @return FontString
function OGST.AddCenteredLabel(frame, text, font)
  font = font or "GameFontNormalSmall"
  local label = frame:CreateFontString(nil, "OVERLAY", font)
  label:SetPoint("CENTER", frame, "CENTER")
  label:SetText(text)
  label:SetTextColor(1, 1, 1)
  return label
end

-- Create a highlight border frame for layout segregation
-- @param parent: Parent frame
-- @param config: Configuration table
--   - width: Width in pixels or "Fill" (default: "Fill")
--   - height: Height in pixels or "Fill" (default: "Fill")
--   - color: RGB table {r, g, b} (default: green {r=0, g=1, b=0})
--   - alpha: Border opacity 0-1 (default: 1)
--   - thickness: Border thickness in pixels (default: 2)
--   - fillPadding: Padding when using "Fill" mode (default: 25)
--   - anchorTo: Another highlight border frame to anchor to (optional)
--   - anchorPoint: Anchor point like "TOPLEFT", "BOTTOMLEFT" etc (default: "TOPLEFT")
--   - anchorToPoint: Point on anchorTo frame (default: same as anchorPoint)
--   - offset: Distance from anchorTo (default: 10)
--   - offsetX: Horizontal offset (overrides offset)
--   - offsetY: Vertical offset (overrides offset)
-- @return Highlight border frame
function OGST.CreateHighlightBorder(parent, config)
  if not parent then return nil end
  
  config = config or {}
  local width = config.width or "Fill"
  local height = config.height or "Fill"
  local color = config.color or {r=0, g=1, b=0}
  local alpha = config.alpha or 1
  local thickness = config.thickness or 2
  local fillPadding = config.fillPadding or 25
  
  -- Create container frame
  local border = CreateFrame("Frame", nil, parent)
  
  -- Handle anchoring first if specified
  local hasAnchor = config.anchorTo ~= nil
  local anchorPoint = config.anchorPoint or "TOPLEFT"
  local anchorToPoint = config.anchorToPoint or anchorPoint
  local defaultOffset = config.offset or 10
  local offsetX = config.offsetX or defaultOffset
  local offsetY = config.offsetY or defaultOffset
  
  if hasAnchor then
    -- Adjust offset direction based on anchor point
    if string.find(anchorPoint, "RIGHT") then
      offsetX = math.abs(offsetX)
    elseif string.find(anchorPoint, "LEFT") then
      offsetX = -math.abs(offsetX)
    end
    
    if string.find(anchorPoint, "BOTTOM") then
      offsetY = -math.abs(offsetY)
    elseif string.find(anchorPoint, "TOP") then
      offsetY = math.abs(offsetY)
    end
    
    border:SetPoint(anchorPoint, config.anchorTo, anchorToPoint, offsetX, offsetY)
  end
  
  -- Set dimensions or fill
  if width == "Fill" then
    if hasAnchor and (string.find(anchorPoint, "LEFT") or string.find(anchorPoint, "RIGHT")) then
      -- If anchored left/right, fill to opposite edge of parent
      if string.find(anchorPoint, "LEFT") then
        border:SetPoint("RIGHT", parent, "RIGHT", -fillPadding, 0)
      else
        border:SetPoint("LEFT", parent, "LEFT", fillPadding, 0)
      end
    elseif not hasAnchor then
      -- No anchor, fill horizontally with padding
      border:SetPoint("LEFT", parent, "LEFT", fillPadding, 0)
      border:SetPoint("RIGHT", parent, "RIGHT", -fillPadding, 0)
    end
  else
    border:SetWidth(width)
  end
  
  if height == "Fill" then
    if hasAnchor and (string.find(anchorPoint, "TOP") or string.find(anchorPoint, "BOTTOM")) then
      -- If anchored top/bottom, fill to opposite edge of parent
      if string.find(anchorPoint, "TOP") then
        border:SetPoint("BOTTOM", parent, "BOTTOM", 0, fillPadding)
      else
        border:SetPoint("TOP", parent, "TOP", 0, -fillPadding)
      end
    elseif not hasAnchor then
      -- No anchor, fill vertically with padding
      border:SetPoint("TOP", parent, "TOP", 0, -fillPadding)
      border:SetPoint("BOTTOM", parent, "BOTTOM", 0, fillPadding)
    end
  else
    border:SetHeight(height)
  end
  
  -- Set default position if no anchor and not filling both dimensions
  if not hasAnchor and not (width == "Fill" and height == "Fill") then
    border:SetPoint("TOPLEFT", parent, "TOPLEFT", fillPadding, -fillPadding)
  end
  
  -- Create border textures
  local top = border:CreateTexture(nil, "OVERLAY")
  top:SetPoint("TOPLEFT", border, "TOPLEFT")
  top:SetPoint("TOPRIGHT", border, "TOPRIGHT")
  top:SetHeight(thickness)
  top:SetTexture(color.r, color.g, color.b, alpha)
  
  local bottom = border:CreateTexture(nil, "OVERLAY")
  bottom:SetPoint("BOTTOMLEFT", border, "BOTTOMLEFT")
  bottom:SetPoint("BOTTOMRIGHT", border, "BOTTOMRIGHT")
  bottom:SetHeight(thickness)
  bottom:SetTexture(color.r, color.g, color.b, alpha)
  
  local left = border:CreateTexture(nil, "OVERLAY")
  left:SetPoint("TOPLEFT", border, "TOPLEFT")
  left:SetPoint("BOTTOMLEFT", border, "BOTTOMLEFT")
  left:SetWidth(thickness)
  left:SetTexture(color.r, color.g, color.b, alpha)
  
  local right = border:CreateTexture(nil, "OVERLAY")
  right:SetPoint("TOPRIGHT", border, "TOPRIGHT")
  right:SetPoint("BOTTOMRIGHT", border, "BOTTOMRIGHT")
  right:SetWidth(thickness)
  right:SetTexture(color.r, color.g, color.b, alpha)
  
  -- Store properties
  border.borderTextures = {top = top, bottom = bottom, left = left, right = right}
  border.fillPadding = fillPadding
  
  return border
end

-- Anchor an element to another with standard spacing
-- @param element: The frame to position
-- @param anchorTo: The frame to anchor to
-- @param config: Configuration table (optional)
--   - position: "below", "above", "right", "left", "center" (default: "below")
--   - gap: Distance between elements (default: 10)
--   - align: "left", "center", "right" for vertical positioning; "top", "center", "bottom" for horizontal (default: "left"/"top")
--   - offsetX: Manual X offset (overrides calculated offset)
--   - offsetY: Manual Y offset (overrides calculated offset)
-- @return The element (for chaining)

-- Content Panel (window-within-a-window section)
-- Creates a panel with backdrop for grouping related content
-- @param parent The parent frame
-- @param config Table with options:
--   - name: Frame name (optional)
--   - width: Panel width (default 200)
--   - height: Panel height (default 100)
-- @return The panel frame
function OGST.CreateContentPanel(parent, config)
  config = config or {}
  
  local panel = CreateFrame("Frame", config.name, parent)
  panel:SetWidth(config.width or 200)
  panel:SetHeight(config.height or 100)
  panel:EnableMouse(true)
  
  -- Set backdrop
  panel:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 }
  })
  panel:SetBackdropColor(0, 0, 0, 0.8)
  panel:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
  
  -- Default padding from parent edges (can be overridden)
  local padding = config.padding or 5
  
  -- Auto-anchor if anchor config provided
  if config.anchorTo then
    OGST.AnchorElement(panel, config.anchorTo, {
      position = config.position or "below",
      gap = config.gap or 0,
      align = config.align
    })
  elseif config.fillParent then
    -- Fill parent with padding
    panel:SetPoint("TOPLEFT", parent, "TOPLEFT", padding, -padding)
    panel:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -padding, padding)
  end
  
  -- Design mode tooltip (always register, shows only when design mode active)
  OGST.AddDesignTooltip(panel, config.name or "Content Panel", "Frame")
  
  return panel
end

function OGST.AnchorElement(element, anchorTo, config)
  if not element or not anchorTo then return element end
  
  config = config or {}
  local position = config.position or "below"
  -- Default gap: 0 for static text controls, otherwise 5
  local defaultGap = (element.isStaticText and 0) or 5
  -- Use config.gap if provided, otherwise element's anchorGap property, otherwise defaultGap
  local gap = config.gap or element.anchorGap or defaultGap
  local align = config.align
  local fill = config.fill
  local fillToParent = config.fillToParent  -- Fill width/height to parent instead of anchorTo
  
  element:ClearAllPoints()
  
  -- Check if element has custom anchor offset (e.g., CreateMenuButton has internal padding)
  local defaultOffset = element._anchorOffset or gap
  
  -- Handle fillHeight option - anchor top and bottom to parent while staying on left/right
  if config.fillHeight then
    local parent = anchorTo
    if align == "left" then
      element:SetPoint("TOPLEFT", parent, "TOPLEFT", config.offsetX or defaultOffset, config.offsetY or -defaultOffset)
      element:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", config.offsetX or defaultOffset, config.offsetY or defaultOffset)
    elseif align == "right" then
      element:SetPoint("TOPRIGHT", parent, "TOPRIGHT", config.offsetX or -defaultOffset, config.offsetY or -defaultOffset)
      element:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", config.offsetX or -defaultOffset, config.offsetY or defaultOffset)
    end
    return
  end
  
  if position == "top" then
    -- Anchor to top of parent (like positioning within a content panel)
    if fill then
      element:SetPoint("TOPLEFT", anchorTo, "TOPLEFT", config.offsetX or defaultOffset, config.offsetY or -defaultOffset)
      element:SetPoint("TOPRIGHT", anchorTo, "TOPRIGHT", config.offsetX or -defaultOffset, config.offsetY or -defaultOffset)
    else
      align = align or "left"
      if align == "left" then
        element:SetPoint("TOPLEFT", anchorTo, "TOPLEFT", config.offsetX or defaultOffset, config.offsetY or -defaultOffset)
      elseif align == "center" then
        element:SetPoint("TOP", anchorTo, "TOP", config.offsetX or 0, config.offsetY or -defaultOffset)
      elseif align == "right" then
        element:SetPoint("TOPRIGHT", anchorTo, "TOPRIGHT", config.offsetX or -defaultOffset, config.offsetY or -defaultOffset)
      end
    end
    
  elseif position == "below" then
    -- Stack below
    if fillToParent then
      -- Anchor top to anchorTo, but left/right to parent
      local parent = element:GetParent()
      element:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", config.offsetX or 0, config.offsetY or -gap)
      element:SetPoint("TOPRIGHT", anchorTo, "BOTTOMRIGHT", 0, config.offsetY or -gap)
    elseif fill then
      element:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", config.offsetX or 0, config.offsetY or -gap)
      element:SetPoint("TOPRIGHT", anchorTo, "BOTTOMRIGHT", config.offsetX or 0, config.offsetY or -gap)
    else
      align = align or "left"
      if align == "left" then
        element:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", config.offsetX or 0, config.offsetY or -gap)
      elseif align == "center" then
        element:SetPoint("TOP", anchorTo, "BOTTOM", config.offsetX or 0, config.offsetY or -gap)
      elseif align == "right" then
        element:SetPoint("TOPRIGHT", anchorTo, "BOTTOMRIGHT", config.offsetX or 0, config.offsetY or -gap)
      end
    end
    
  elseif position == "above" then
    -- Stack above
    if fill then
      element:SetPoint("BOTTOMLEFT", anchorTo, "TOPLEFT", config.offsetX or 0, config.offsetY or gap)
      element:SetPoint("BOTTOMRIGHT", anchorTo, "TOPRIGHT", config.offsetX or 0, config.offsetY or gap)
    else
      align = align or "left"
      if align == "left" then
        element:SetPoint("BOTTOMLEFT", anchorTo, "TOPLEFT", config.offsetX or 0, config.offsetY or gap)
      elseif align == "center" then
        element:SetPoint("BOTTOM", anchorTo, "TOP", config.offsetX or 0, config.offsetY or gap)
      elseif align == "right" then
        element:SetPoint("BOTTOMRIGHT", anchorTo, "TOPRIGHT", config.offsetX or 0, config.offsetY or gap)
      end
    end
    
  elseif position == "right" then
    -- Place to the right
    if fill then
      element:SetPoint("TOPLEFT", anchorTo, "TOPRIGHT", config.offsetX or gap, config.offsetY or 0)
      element:SetPoint("BOTTOMLEFT", anchorTo, "BOTTOMRIGHT", config.offsetX or gap, config.offsetY or 0)
    else
      align = align or "top"
      if align == "top" then
        element:SetPoint("TOPLEFT", anchorTo, "TOPRIGHT", config.offsetX or gap, config.offsetY or 0)
      elseif align == "center" then
        element:SetPoint("LEFT", anchorTo, "RIGHT", config.offsetX or gap, config.offsetY or 0)
      elseif align == "bottom" then
        element:SetPoint("BOTTOMLEFT", anchorTo, "BOTTOMRIGHT", config.offsetX or gap, config.offsetY or 0)
      end
    end
    
  elseif position == "left" then
    -- Place to the left
    if fill then
      element:SetPoint("TOPRIGHT", anchorTo, "TOPLEFT", config.offsetX or -gap, config.offsetY or 0)
      element:SetPoint("BOTTOMRIGHT", anchorTo, "BOTTOMLEFT", config.offsetX or -gap, config.offsetY or 0)
    else
      align = align or "top"
      if align == "top" then
        element:SetPoint("TOPRIGHT", anchorTo, "TOPLEFT", config.offsetX or -gap, config.offsetY or 0)
      elseif align == "center" then
        element:SetPoint("RIGHT", anchorTo, "LEFT", config.offsetX or -gap, config.offsetY or 0)
      elseif align == "bottom" then
        element:SetPoint("BOTTOMRIGHT", anchorTo, "BOTTOMLEFT", config.offsetX or -gap, config.offsetY or 0)
      end
    end
    
  elseif position == "center" then
    -- Center on element
    element:SetPoint("CENTER", anchorTo, "CENTER", config.offsetX or 0, config.offsetY or 0)
    
  elseif position == "fillBelow" then
    -- Fill remaining space below the anchor element within the parent
    -- Anchors: TOP below anchorTo, LEFT/RIGHT/BOTTOM to parent edges
    local padding = config.padding or 5
    local parent = anchorTo:GetParent()
    element:ClearAllPoints()
    element:SetPoint("TOP", anchorTo, "BOTTOM", 0, config.offsetY or -gap)
    element:SetPoint("LEFT", parent, "LEFT", padding, 0)
    element:SetPoint("RIGHT", parent, "RIGHT", -padding, 0)
    element:SetPoint("BOTTOM", parent, "BOTTOM", 0, padding)
    -- Force width to match parent minus padding
    local targetWidth = parent:GetWidth() - (padding * 2)
    element:SetWidth(targetWidth)
    
  elseif position == "fillRight" then
    -- Fill remaining space to the right of anchor element within the parent
    -- Anchors: TOPLEFT/BOTTOMLEFT to right edge of anchorTo, RIGHT to parent's right edge
    local padding = config.padding or 5
    element:ClearAllPoints()
    element:SetPoint("TOPLEFT", anchorTo, "TOPRIGHT", gap, 0)
    element:SetPoint("BOTTOMLEFT", anchorTo, "BOTTOMRIGHT", gap, 0)
    element:SetPoint("RIGHT", anchorTo:GetParent(), "RIGHT", -padding, 0)
    
  elseif position == "fillBelowFromParent" then
    -- Fill remaining space below a specified offsetY within the parent
    -- Used when anchor element doesn't represent the top edge (e.g., centered button)
    -- Anchors: TOPLEFT/RIGHT/BOTTOM to parent edges with offsetY
    local padding = config.padding or 5
    element:ClearAllPoints()
    element:SetPoint("TOPLEFT", anchorTo, "TOPLEFT", padding, config.offsetY or -gap)
    element:SetPoint("RIGHT", anchorTo, "RIGHT", -padding, 0)
    element:SetPoint("BOTTOM", anchorTo, "BOTTOM", 0, padding)
    
  elseif position == "fillBetween" then
    -- Fill space between two elements vertically
    -- Requires config.bottomElement to specify the bottom anchor
    -- Anchors: TOPLEFT/TOPRIGHT below anchorTo, BOTTOM above bottomElement
    if not config.bottomElement then
      DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OGST:|r fillBetween requires config.bottomElement")
      return
    end
    element:ClearAllPoints()
    element:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", config.offsetX or 0, config.offsetYTop or -gap)
    element:SetPoint("TOPRIGHT", anchorTo, "BOTTOMRIGHT", config.offsetX or 0, config.offsetYTop or -gap)
    element:SetPoint("BOTTOM", config.bottomElement, "TOP", 0, config.offsetYBottom or -gap)
    
  elseif position == "spanHorizontal" then
    -- Span horizontally between left anchor (anchorTo) and right anchor (config.rightElement)
    -- Requires config.rightElement to specify the right anchor
    -- Anchors: TOPLEFT to anchorTo, TOPRIGHT to rightElement
    if not config.rightElement then
      DEFAULT_CHAT_FRAME:AddMessage("|cffff0000OGST:|r spanHorizontal requires config.rightElement")
      return
    end
    element:ClearAllPoints()
    local verticalAlign = config.verticalAlign or "top"
    if verticalAlign == "top" then
      element:SetPoint("TOPLEFT", anchorTo, "TOPLEFT", config.offsetXLeft or 0, config.offsetY or 0)
      element:SetPoint("TOPRIGHT", config.rightElement, "TOPLEFT", config.offsetXRight or 0, config.offsetY or 0)
    elseif verticalAlign == "bottom" then
      element:SetPoint("BOTTOMLEFT", anchorTo, "BOTTOMLEFT", config.offsetXLeft or 0, config.offsetY or 0)
      element:SetPoint("BOTTOMRIGHT", config.rightElement, "BOTTOMLEFT", config.offsetXRight or 0, config.offsetY or 0)
    end
    
  elseif position == "alignBottom" then
    -- Align element to bottom of parent, maintaining horizontal position relative to anchorTo
    -- Anchors: BOTTOMLEFT/BOTTOMRIGHT aligned with anchorTo horizontally, at parent bottom
    -- Supports align="right" to right-align element with anchorTo
    local parent = config.parent or element:GetParent()
    element:ClearAllPoints()
    
    if config.align == "right" then
      -- Right-align element with anchorTo
      element:SetPoint("BOTTOMRIGHT", parent, "BOTTOMLEFT", anchorTo:GetRight() - parent:GetLeft(), config.offsetY or 0)
    else
      -- Default: left-align element with anchorTo
      element:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", anchorTo:GetLeft() - parent:GetLeft(), config.offsetY or 0)
    end
  end
  
  return element
end

-- ============================================
-- DOCKED PANEL POSITIONING SYSTEM
-- ============================================
-- System for automatically positioning panels around a parent frame
-- - Horizontal panels: Dock LEFT or RIGHT (swaps sides if off-screen)
-- - Vertical panels: Dock TOP or BOTTOM (swaps sides if off-screen)
-- - Priority determines stacking order (lower = closer to parent)

OGST.DockedPanels = OGST.DockedPanels or {
  panels = {},
  updateFrame = nil
}

-- Register a docked panel for automatic positioning
-- @param frame: The panel frame to manage
-- @param config: Configuration table
--   - parentFrame: The frame to position relative to (required)
--   - axis: "horizontal" or "vertical" (required)
--   - preferredSide: "left"/"right" for horizontal, "top"/"bottom" for vertical (default: "left" or "bottom")
--   - priority: Lower numbers closer to parent (default: 100)
--   - autoMove: Enable automatic repositioning (default: true)
--   - hideInCombat: Hide panel when entering combat (default: false)
function OGST.RegisterDockedPanel(frame, config)
  if not frame or not config or not config.parentFrame or not config.axis then return end
  
  config = config or {}
  local axis = config.axis -- "horizontal" or "vertical"
  local preferredSide = config.preferredSide
  if not preferredSide then
    preferredSide = (axis == "horizontal") and "left" or "bottom"
  end
  
  local priority = config.priority or 100
  local autoMove = config.autoMove
  if autoMove == nil then autoMove = true end
  local hideInCombat = config.hideInCombat or false
  
  -- Check if already registered
  for i, panel in ipairs(OGST.DockedPanels.panels) do
    if panel.frame == frame then
      panel.parentFrame = config.parentFrame
      panel.axis = axis
      panel.preferredSide = preferredSide
      panel.priority = priority
      panel.autoMove = autoMove
      panel.hideInCombat = hideInCombat
      OGST.RepositionDockedPanels()
      return
    end
  end
  
  -- Track if dimensions were explicitly set
  local explicitWidth = frame:GetWidth() and frame:GetWidth() > 0
  local explicitHeight = frame:GetHeight() and frame:GetHeight() > 0
  
  -- Apply standard window styling
  frame:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 16,
    insets = {left = 4, right = 4, top = 4, bottom = 4}
  })
  frame:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
  frame:SetBackdropBorderColor(0.4, 0.6, 0.6, 1)
  
  -- Add title if provided
  local titleText = nil
  if config.title then
    titleText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    titleText:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -6)
    titleText:SetText(config.title)
    titleText:SetTextColor(1, 1, 1, 1)
    frame.titleText = titleText
  end
  
  -- Add new panel
  table.insert(OGST.DockedPanels.panels, {
    frame = frame,
    parentFrame = config.parentFrame,
    axis = axis,
    preferredSide = preferredSide,
    priority = priority,
    autoMove = autoMove,
    hideInCombat = hideInCombat,
    wasVisibleBeforeCombat = false,
    explicitWidth = explicitWidth,
    explicitHeight = explicitHeight
  })
  
  -- Sort by priority
  table.sort(OGST.DockedPanels.panels, function(a, b)
    return a.priority < b.priority
  end)
  
  OGST.RepositionDockedPanels()
end

-- Unregister a docked panel
-- @param frame: The panel frame to unregister
function OGST.UnregisterDockedPanel(frame)
  if not frame then return end
  
  for i, panel in ipairs(OGST.DockedPanels.panels) do
    if panel.frame == frame then
      table.remove(OGST.DockedPanels.panels, i)
      OGST.RepositionDockedPanels()
      return
    end
  end
end

-- Reposition all registered docked panels
function OGST.RepositionDockedPanels()
  -- Group panels by parent frame and axis
  local panelGroups = {}
  
  for _, panel in ipairs(OGST.DockedPanels.panels) do
    if panel.autoMove then
      -- Hide panels whose parent is hidden, show them when parent is visible
      if not panel.parentFrame:IsVisible() then
        if panel.frame:IsVisible() then
          panel.frame:Hide()
          panel.wasAutoHidden = true
        end
      else
        -- Parent is visible - restore panel if it was auto-hidden
        if panel.wasAutoHidden then
          panel.frame:Show()
          panel.wasAutoHidden = false
        end
        
        -- Group visible panels with visible parents
        if panel.frame:IsVisible() then
          local key = tostring(panel.parentFrame) .. "_" .. panel.axis
          if not panelGroups[key] then
            panelGroups[key] = {
              parentFrame = panel.parentFrame,
              axis = panel.axis,
              panels = {}
            }
          end
          table.insert(panelGroups[key].panels, panel)
        end
      end
    end
  end
  
  -- Position each group
  for _, group in pairs(panelGroups) do
    OGST.PositionPanelGroup(group)
  end
end

-- Position a group of panels on the same axis of a parent
function OGST.PositionPanelGroup(group)
  local parent = group.parentFrame
  local axis = group.axis
  local panels = group.panels
  local gap = 2  -- Positive gap = separation, negative gap = overlap
  
  if axis == "vertical" then
    -- Match panel widths to parent width if not explicitly set
    local parentWidth = parent:GetWidth()
    for _, panel in ipairs(panels) do
      if not panel.explicitWidth then
        panel.frame:SetWidth(parentWidth)
      end
    end
    
    -- Calculate total height needed for all panels
    local totalHeight = 0
    for _, panel in ipairs(panels) do
      totalHeight = totalHeight + panel.frame:GetHeight()
    end
    totalHeight = totalHeight + (table.getn(panels) - 1) * gap
    
    -- Determine actual side based on screen space
    local parentBottom = parent:GetBottom()
    local parentTop = parent:GetTop()
    local screenHeight = UIParent:GetHeight()
    
    local actualSide
    local preferredSide = panels[1].preferredSide
    
    if preferredSide == "bottom" then
      -- Check if we have space below
      if parentBottom - totalHeight > 0 then
        actualSide = "bottom"
      elseif parentTop + totalHeight < screenHeight then
        actualSide = "top"
      else
        actualSide = "bottom" -- Fallback to preferred
      end
    else
      -- Preferred side is top
      if parentTop + totalHeight < screenHeight then
        actualSide = "top"
      elseif parentBottom - totalHeight > 0 then
        actualSide = "bottom"
      else
        actualSide = "top" -- Fallback to preferred
      end
    end
    
    if actualSide == "bottom" then
      -- Stack downward from parent
      local currentAnchor = parent
      local currentPoint = "BOTTOM"
      
      for _, panel in ipairs(panels) do
        panel.frame:ClearAllPoints()
        panel.frame:SetPoint("TOP", currentAnchor, currentPoint, 0, gap)
        currentAnchor = panel.frame
        currentPoint = "BOTTOM"
      end
    else
      -- Stack upward from parent
      local currentAnchor = parent
      local currentPoint = "TOP"
      
      for _, panel in ipairs(panels) do
        panel.frame:ClearAllPoints()
        panel.frame:SetPoint("BOTTOM", currentAnchor, currentPoint, 0, -gap)
        currentAnchor = panel.frame
        currentPoint = "TOP"
      end
    end
    
  elseif axis == "horizontal" then
    -- Match panel heights to parent height if not explicitly set
    local parentHeight = parent:GetHeight()
    for _, panel in ipairs(panels) do
      if not panel.explicitHeight then
        panel.frame:SetHeight(parentHeight)
      end
    end
    
    -- Calculate total width needed for all panels
    local totalWidth = 0
    for _, panel in ipairs(panels) do
      totalWidth = totalWidth + panel.frame:GetWidth()
    end
    totalWidth = totalWidth + (table.getn(panels) - 1) * gap
    
    -- Determine actual side based on screen space
    local parentLeft = parent:GetLeft()
    local parentRight = parent:GetRight()
    local screenWidth = UIParent:GetWidth()
    
    local actualSide
    local preferredSide = panels[1].preferredSide
    
    if preferredSide == "left" then
      -- Check if we have space on left
      if parentLeft - totalWidth > 0 then
        actualSide = "left"
      elseif parentRight + totalWidth < screenWidth then
        actualSide = "right"
      else
        actualSide = "left" -- Fallback to preferred
      end
    else
      -- Preferred side is right
      if parentRight + totalWidth < screenWidth then
        actualSide = "right"
      elseif parentLeft - totalWidth > 0 then
        actualSide = "left"
      else
        actualSide = "right" -- Fallback to preferred
      end
    end
    
    if actualSide == "left" then
      -- Stack leftward from parent
      local currentAnchor = parent
      local currentPoint = "LEFT"
      
      for _, panel in ipairs(panels) do
        panel.frame:ClearAllPoints()
        panel.frame:SetPoint("RIGHT", currentAnchor, currentPoint, gap, 0)
        currentAnchor = panel.frame
        currentPoint = "LEFT"
      end
    else
      -- Stack rightward from parent
      local currentAnchor = parent
      local currentPoint = "RIGHT"
      
      for _, panel in ipairs(panels) do
        panel.frame:ClearAllPoints()
        panel.frame:SetPoint("LEFT", currentAnchor, currentPoint, -gap, 0)
        currentAnchor = panel.frame
        currentPoint = "RIGHT"
      end
    end
  end
end

-- Initialize automatic repositioning and combat handling
if not OGST.DockedPanels.updateFrame then
  local updateFrame = CreateFrame("Frame")
  updateFrame.lastParentPositions = {}
  updateFrame.lastPanelStates = {}
  
  -- Handle repositioning on frame movement/visibility changes
  updateFrame:SetScript("OnUpdate", function()
    -- Check for parent movement or panel visibility changes
    local needsUpdate = false
    
    for i, panel in ipairs(OGST.DockedPanels.panels) do
      if panel.autoMove and panel.parentFrame then
        -- Check parent position change
        local parentPos = panel.parentFrame:GetLeft()
        local lastPos = this.lastParentPositions[panel.parentFrame]
        if parentPos and parentPos ~= lastPos then
          this.lastParentPositions[panel.parentFrame] = parentPos
          needsUpdate = true
        end
        
        -- Check parent visibility change
        local parentKey = tostring(panel.parentFrame) .. "_visible"
        local parentVisible = panel.parentFrame:IsVisible()
        if this.lastParentPositions[parentKey] ~= parentVisible then
          this.lastParentPositions[parentKey] = parentVisible
          needsUpdate = true
        end
        
        -- Check panel visibility change
        local isVisible = panel.frame:IsVisible()
        if this.lastPanelStates[i] ~= isVisible then
          this.lastPanelStates[i] = isVisible
          needsUpdate = true
        end
      end
    end
    
    if needsUpdate then
      OGST.RepositionDockedPanels()
    end
  end)
  
  -- Handle combat events
  updateFrame:RegisterEvent("PLAYER_REGEN_DISABLED") -- Entering combat
  updateFrame:RegisterEvent("PLAYER_REGEN_ENABLED")  -- Leaving combat
  
  updateFrame:SetScript("OnEvent", function()
    if event == "PLAYER_REGEN_DISABLED" then
      -- Entering combat - hide panels with hideInCombat flag
      for _, panel in ipairs(OGST.DockedPanels.panels) do
        if panel.hideInCombat and panel.frame:IsVisible() then
          panel.wasVisibleBeforeCombat = true
          panel.frame:Hide()
        end
      end
    elseif event == "PLAYER_REGEN_ENABLED" then
      -- Leaving combat - restore panels
      for _, panel in ipairs(OGST.DockedPanels.panels) do
        if panel.hideInCombat and panel.wasVisibleBeforeCombat then
          panel.frame:Show()
          panel.wasVisibleBeforeCombat = false
        end
      end
    end
  end)
  
  OGST.DockedPanels.updateFrame = updateFrame
end

-- Library loaded message
DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00OGST:|r Standard Templates Library v" .. OGST.version .. " loaded")
