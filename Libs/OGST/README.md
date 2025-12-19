# OGST - OG Standard Templates Library

Version 1.0.0

A reusable UI template library for World of Warcraft 1.12.1 (Vanilla) addons, providing standardized components with consistent styling and behavior.

## Installation

Add to your addon's `.toc` file:

```
Libs\OGST\OGST.lua
```

## API Reference

### Constants

#### Color Constants
```lua
OGST.LIST_COLORS = {
  SELECTED = {r = 0.2, g = 0.4, b = 0.2, a = 0.8},
  INACTIVE = {r = 0.2, g = 0.2, b = 0.2, a = 0.5},
  HOVER = {r = 0.2, g = 0.5, b = 0.2, a = 0.5}
}
```

#### Dimension Constants
```lua
OGST.LIST_ITEM_HEIGHT = 20
OGST.LIST_ITEM_SPACING = 2
```

---

### Window Management

#### OGST.CreateStandardWindow(config)
Create a standardized window frame with optional close button, ESC handling, resize control, and window management.

**Parameters:**
- `config` (table): Configuration options (required)
  - `name` (string): Unique frame name (required)
  - `width` (number): Window width (required)
  - `height` (number): Window height (required)
  - `title` (string): Window title text (required)
  - `closeButton` (boolean): Add close button (default: true)
  - `escapeCloses` (boolean): ESC key closes window (default: true)
  - `closeOnNewWindow` (boolean): Close when other windows open (default: false)
  - `resizable` (boolean): Add resize handle in bottom-right corner (default: false)
  - `minWidth` (number): Minimum width when resizing (default: 200)
  - `minHeight` (number): Minimum height when resizing (default: 150)
  - `maxWidth` (number): Maximum width when resizing (default: screen width)
  - `maxHeight` (number): Maximum height when resizing (default: screen height)

**Returns:** Window frame with properties:
- `contentFrame`: Area for adding custom content
- `titleText`: Title font string
- `closeButton`: Close button (if enabled)

**Example:**
```lua
local window = OGST.CreateStandardWindow({
  name = "MyAddonWindow",
  width = 600,
  height = 400,
  title = "My Addon",
  closeButton = true,
  escapeCloses = true,
  closeOnNewWindow = true,
  resizable = true,  -- Add resize handle
  minWidth = 400,    -- Don't allow smaller than 400px wide
  minHeight = 300    -- Don't allow smaller than 300px tall
})

-- Add content to the window
local text = window.contentFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
text:SetPoint("CENTER")
text:SetText("Hello, World!")

window:Show()
```

---

### Button Styling

#### OGST.StyleButton(button)
Style a button with consistent dark teal theme.

**Parameters:**
- `button` (Frame): The button frame to style

**Example:**
```lua
local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
btn:SetText("My Button")
OGST.StyleButton(btn)
```

---

### Menu System

#### OGST.CreateStandardMenu(config)
Create a standardized dropdown menu with optional title and submenus.

**Parameters:**
- `config` (table): Configuration options
  - `name` (string): Frame name for ESC key handling and registry
  - `width` (number): Menu width (default: 160)
  - `title` (string): Optional title text
  - `titleColor` (table): RGB table `{r, g, b}` for title (default: white)
  - `itemColor` (table): RGB table `{r, g, b}` for items (default: white)
  - `register` (boolean): Register menu globally (default: true if name provided)

**Returns:** Menu frame with methods:
- `AddItem(itemConfig)`: Add a menu item
- `Finalize()`: Finalize menu height

**Item Config:**
- `text` (string): Display text
- `onClick` (function): Click handler
- `submenu` (table): Array of submenu item configs

**Example:**
```lua
local menu = OGST.CreateStandardMenu({
  name = "MyAddonMenu",
  width = 180,
  title = "Options"
})

menu:AddItem({
  text = "Enable Feature",
  onClick = function()
    -- Handle click
  end
})

menu:AddItem({
  text = "More Options",
  submenu = {
    {text = "Option 1", onClick = function() end},
    {text = "Option 2", onClick = function() end}
  }
})

menu:Finalize()
menu:Show()
```

#### OGST.GetMenu(name)
Get a registered menu by name.

**Parameters:**
- `name` (string): Menu name

**Returns:** Menu frame or nil

**Example:**
```lua
local menu = OGST.GetMenu("MyAddonMenu")
if menu then
  menu:Show()
end
```

#### OGST.AddMenuItem(menuName, itemConfig)
Add an item to an existing registered menu. Items must be added before `Finalize()` is called.

**Parameters:**
- `menuName` (string): Name of the registered menu
- `itemConfig` (table): Item configuration (same as menu:AddItem)

**Returns:** Boolean indicating success

**Example:**
```lua
-- Component A creates menu
local menu = OGST.CreateStandardMenu({
  name = "MainMenu",
  title = "Options"
})
menu:AddItem({ text = "Item 1", onClick = function() end })

-- Component B adds to it later
OGST.AddMenuItem("MainMenu", {
  text = "Component B Feature",
  onClick = function()
    -- Handle click
  end
})

-- Finalize when all components have added their items
menu:Finalize()
```

---

### Scroll List

#### OGST.CreateStyledScrollList(parent, width, height, hideScrollBar)
Create a standardized scrolling list container.

**Parameters:**
- `parent` (Frame): Parent frame
- `width` (number): List width
- `height` (number): List height
- `hideScrollBar` (boolean): Optional, true to hide scrollbar

**Returns:**
- `outerFrame`: Container frame
- `scrollFrame`: Scroll frame
- `scrollChild`: Content container
- `scrollBar`: Scrollbar slider
- `contentWidth`: Available content width

**Example:**
```lua
local outerFrame, scrollFrame, scrollChild, scrollBar, contentWidth = 
  OGST.CreateStyledScrollList(parent, 300, 400)

-- Add items to scrollChild
local item = CreateFrame("Frame", nil, scrollChild)
item:SetPoint("TOPLEFT", 0, 0)
```

---

### List Items

#### OGST.CreateStyledListItem(parent, width, height, frameType)
Create a standardized list item with background and hover effects.

**Parameters:**
- `parent` (Frame): Parent frame
- `width` (number): Item width
- `height` (number): Item height (default: `OGST.LIST_ITEM_HEIGHT`)
- `frameType` (string): "Button" or "Frame" (default: "Button")

**Returns:** Item frame with `.bg` property

**Example:**
```lua
local item = OGST.CreateStyledListItem(scrollChild, 280, 20, "Button")
item:SetPoint("TOPLEFT", 0, 0)

local text = item:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
text:SetPoint("LEFT", item, "LEFT", 8, 0)
text:SetText("List Item")
```

#### OGST.AddListItemButtons(listItem, index, listLength, onMoveUp, onMoveDown, onDelete, hideUpDown)
Add up/down/delete buttons to a list item.

**Parameters:**
- `listItem` (Frame): Parent frame
- `index` (number): Current index (1-based)
- `listLength` (number): Total items
- `onMoveUp` (function): Up button callback
- `onMoveDown` (function): Down button callback
- `onDelete` (function): Delete button callback
- `hideUpDown` (boolean): Optional, true to only show delete button

**Returns:**
- `deleteButton`: Delete button frame
- `downButton`: Down button frame (or nil if hideUpDown)
- `upButton`: Up button frame (or nil if hideUpDown)

**Example:**
```lua
OGST.AddListItemButtons(item, 1, 5, 
  function() -- Move up
    print("Moving up")
  end,
  function() -- Move down
    print("Moving down")
  end,
  function() -- Delete
    print("Deleting")
  end
)
```

#### OGST.SetListItemSelected(item, isSelected)
Set list item selected state.

**Parameters:**
- `item` (Frame): List item frame
- `isSelected` (boolean): Selection state

**Example:**
```lua
OGST.SetListItemSelected(item, true) -- Highlight as selected
```

#### OGST.SetListItemColor(item, r, g, b, a)
Set custom list item color.

**Parameters:**
- `item` (Frame): List item frame
- `r, g, b, a` (number): Color components (0-1)

**Example:**
```lua
OGST.SetListItemColor(item, 1, 0, 0, 0.5) -- Red with 50% opacity
```

---

### Texture & Panel Utilities

#### OGST.CreateColoredPanel(parent, width, height, borderColor, bgColor)
Create a colored panel with border and background textures properly configured for WoW 1.12.

**Parameters:**
- `parent` (Frame): Parent frame
- `width` (number): Panel width
- `height` (number): Panel height
- `borderColor` (table): RGB table `{r, g, b}` for border (optional, default: white)
- `bgColor` (table): RGBA table `{r, g, b, a}` for background (optional, default: black 0.8)

**Returns:** Panel frame with `.border` and `.bg` texture properties

**Example:**
```lua
local panel = OGST.CreateColoredPanel(UIParent, 100, 50, 
  {r=1, g=0, b=0},  -- Red border
  {r=0, g=0, b=0, a=0.9}  -- Black background
)
panel:SetPoint("CENTER")
```

#### OGST.AddCenteredLabel(frame, text, font)
Add a centered text label to a frame.

**Parameters:**
- `frame` (Frame): Parent frame
- `text` (string): Text to display
- `font` (string): Font object name (optional, default: "GameFontNormalSmall")

**Returns:** FontString

**Example:**
```lua
local label = OGST.AddCenteredLabel(panel, "My Label", "GameFontNormal")
label:SetTextColor(1, 1, 0)  -- Yellow text
```

#### OGST.AnchorElement(element, anchorTo, config)
Position one UI element relative to another with standard spacing. Makes creating clean, consistent layouts easy.

**Parameters:**
- `element` (Frame): The frame to position
- `anchorTo` (Frame): The frame to anchor to
- `config` (table): Configuration options (optional)
  - `position` (string): "below", "above", "right", "left", "center" (default: "below")
  - `gap` (number): Distance between elements (default: 10)
  - `align` (string): For vertical positioning: "left", "center", "right"; For horizontal: "top", "center", "bottom" (default: "left"/"top")
  - `offsetX` (number): Manual X offset (overrides calculated offset)
  - `offsetY` (number): Manual Y offset (overrides calculated offset)

**Returns:** The element (for chaining)

**Example:**
```lua
-- Stack elements vertically with standard 10px gap
local label1 = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
label1:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -10)
label1:SetText("First Label")

local label2 = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
OGST.AnchorElement(label2, label1, {position = "below"})
label2:SetText("Second Label")

-- Place elements side by side
local button1 = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
button1:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -50)
button1:SetWidth(80)
button1:SetHeight(24)

local button2 = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
OGST.AnchorElement(button2, button1, {position = "right", gap = 5})
button2:SetWidth(80)
button2:SetHeight(24)

-- Chain multiple elements
OGST.AnchorElement(element3, element2, {position = "below", align = "center"})
```

#### OGST.CreateHighlightBorder(parent, config)
Create a highlight border frame for layout segregation and visual grouping. Borders can be sized explicitly or set to "Fill" to automatically fill their parent with padding.

**Parameters:**
- `parent` (Frame): Parent frame
- `config` (table): Configuration options
  - `width` (number|"Fill"): Width in pixels or "Fill" (default: "Fill")
  - `height` (number|"Fill"): Height in pixels or "Fill" (default: "Fill")
  - `color` (table): RGB table `{r, g, b}` (default: green `{r=0, g=1, b=0}`)
  - `alpha` (number): Border opacity 0-1 (default: 1)
  - `thickness` (number): Border thickness in pixels (default: 2)
  - `fillPadding` (number): Padding when using "Fill" mode (default: 25)
  - `anchorTo` (Frame): Another highlight border to anchor to (optional)
  - `anchorPoint` (string): Anchor point like "TOPLEFT", "BOTTOMLEFT" (default: "TOPLEFT")
  - `anchorToPoint` (string): Point on anchorTo frame (default: same as anchorPoint)
  - `offset` (number): Distance from anchorTo (default: 10)
  - `offsetX` (number): Horizontal offset (overrides offset)
  - `offsetY` (number): Vertical offset (overrides offset)

**Returns:** Highlight border frame

**Example:**
```lua
-- Create a highlight border that fills the left side of window
local leftBorder = OGST.CreateHighlightBorder(window.contentFrame, {
  width = 250,
  height = "Fill",
  color = {r=0, g=1, b=0},  -- Green
  fillPadding = 20
})

-- Create another border anchored to the first
local rightBorder = OGST.CreateHighlightBorder(window.contentFrame, {
  width = "Fill",
  height = "Fill",
  anchorTo = leftBorder,
  anchorPoint = "TOPLEFT",
  anchorToPoint = "TOPRIGHT",
  offset = 10,
  color = {r=0, g=1, b=0}
})

-- Create a bottom section
local bottomBorder = OGST.CreateHighlightBorder(window.contentFrame, {
  width = "Fill",
  height = 150,
  anchorTo = leftBorder,
  anchorPoint = "BOTTOMLEFT",
  anchorToPoint = "BOTTOMLEFT",
  offsetY = -10
})
```

---

### Docked Panel Positioning

#### OGST.RegisterDockedPanel(frame, config)
Register a panel for automatic positioning relative to a parent frame. Panels automatically detect screen boundaries and swap sides as needed. Multiple panels on the same axis are stacked in priority order.

**Parameters:**
- `frame` (Frame): The panel frame to manage
- `config` (table): Configuration options
  - `parentFrame` (Frame): The frame to position relative to (required)
  - `axis` (string): "horizontal" or "vertical" (required)
  - `preferredSide` (string): "left"/"right" for horizontal, "top"/"bottom" for vertical
  - `priority` (number): Lower numbers closer to parent (default: 100)
  - `autoMove` (boolean): Enable automatic repositioning (default: true)
  - `hideInCombat` (boolean): Hide panel when entering combat (default: false)

**Behavior:**
- **Horizontal axis**: Panels dock to LEFT or RIGHT. If parent position would push the panel off-screen, it automatically swaps to the opposite side.
- **Vertical axis**: Panels dock to TOP or BOTTOM. If parent position would push the panel off-screen, it automatically swaps to the opposite side.
- **Priority stacking**: Multiple panels on the same axis stack in priority order (lower = closer to parent).

**Example:**
```lua
local panel = CreateFrame("Frame", nil, UIParent)
panel:SetWidth(300)
panel:SetHeight(50)

-- Horizontal panel (left/right with auto-swap)
OGST.RegisterDockedPanel(panel, {
  parentFrame = OGRH_Main,
  axis = "horizontal",
  preferredSide = "left",
  priority = 1,
  autoMove = true,
  hideInCombat = false
})

-- Vertical panel (top/bottom with auto-swap)
OGST.RegisterDockedPanel(panel2, {
  parentFrame = OGRH_Main,
  axis = "vertical",
  preferredSide = "bottom",
  priority = 1
})

panel:Show()
```

#### OGST.UnregisterDockedPanel(frame)
Unregister a panel from automatic positioning.

**Parameters:**
- `frame` (Frame): The panel frame to unregister

**Example:**
```lua
OGST.UnregisterDockedPanel(panel)
```

#### OGST.RepositionDockedPanels()
Manually trigger repositioning of all registered panels. This is automatically called when parent frames move or panel visibility changes.

**Example:**
```lua
OGST.RepositionDockedPanels()
```

---

### Checkbox

#### OGST.CreateCheckbox(parent, config)
Create a checkbox with optional label that follows the same design philosophy as text boxes. Includes design mode border support and easy anchoring.

**Parameters:**
- `parent` (Frame): Parent frame
- `config` (table): Optional configuration
  - `label` (string): Label text (optional)
  - `labelAnchor` (string): "LEFT" or "RIGHT" (default: "RIGHT")
  - `labelFont` (string): Font object for label (default: GameFontNormalSmall)
  - `labelColor` (table): RGB table `{r, g, b}` (default: white)
  - `labelWidth` (number): Width for label (default: auto-size based on text)
  - `gap` (number): Distance between checkbox and label (default: 5)
  - `padding` (number): Container padding (default: 5)
  - `checked` (boolean): Initial checked state (default: false)
  - `onChange` (function): Callback(isChecked) when state changes
  - `disabled` (boolean): Initial disabled state (default: false)
  - `anchorGap` (number): Gap for use with AnchorElement (default: -12)

**Returns:**
- `container`: Container frame (shows orange border in design mode)
- `checkButton`: CheckButton frame
- `labelText`: Label FontString (or nil if no label)

**Example:**
```lua
-- Checkbox with label on right (default)
local container, checkButton, label = OGST.CreateCheckbox(parent, {
  label = "Enable Feature",
  labelAnchor = "RIGHT",
  checked = true,
  onChange = function(isChecked)
    print("Checkbox is now:", isChecked)
  end
})

container:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -10)

-- Checkbox with label on left
local container2, checkButton2 = OGST.CreateCheckbox(parent, {
  label = "Auto-save",
  labelAnchor = "LEFT",
  labelWidth = 80,
  checked = false,
  onChange = function(isChecked)
    MySavedVar.autoSave = isChecked
  end
})

-- Stack checkboxes using AnchorElement
OGST.AnchorElement(container2, container, {position = "below"})

-- Checkbox without label
local container3, checkButton3 = OGST.CreateCheckbox(parent, {
  checked = false,
  onChange = function(isChecked)
    -- Handle state change
  end
})
```

---

### Menu Button

#### OGST.CreateMenuButton(parent, config)
Create a menu button that combines a styled button with a dropdown menu. Supports selection highlighting (green text) and easy anchoring.

**Parameters:**
- `parent` (Frame): Parent frame
- `config` (table): Configuration table
  - `label` (string): Label text (optional)
  - `labelAnchor` (string): "LEFT" or "RIGHT" (default: "LEFT")
  - `labelFont` (string): Font object for label (default: GameFontNormalSmall)
  - `labelColor` (table): RGB table `{r, g, b}` (default: white)
  - `labelWidth` (number): Width for label (default: auto-size based on text)
  - `buttonText` (string): Text displayed on button (required)
  - `buttonWidth` (number): Button width (default: 100)
  - `buttonHeight` (number): Button height (default: 24)
  - `gap` (number): Distance between label and button (default: 5)
  - `padding` (number): Container padding (default: 5)
  - `menuItems` (table): Array of menu item configs (required)
    - Each item: `{text, onClick, selected}`
  - `anchorGap` (number): Gap for use with AnchorElement (default: -12)

**Returns:**
- `container`: Container frame (shows cyan border in design mode)
- `button`: Button frame
- `menu`: Menu frame
- `labelText`: Label FontString (or nil if no label)

**Menu Item Config:**
- `text` (string): Display text for menu item
- `onClick` (function): Callback when item is clicked
- `selected` (boolean): If true, displays in green (default: false)

**Example:**
```lua
-- Menu button with label
local menuItems = {
  {text = "Option 1", selected = true, onClick = function()
    print("Option 1 selected")
  end},
  {text = "Option 2", selected = false, onClick = function()
    print("Option 2 selected")
  end},
  {text = "Option 3", selected = false, onClick = function()
    print("Option 3 selected")
  end}
}

local container, button, menu, label = OGST.CreateMenuButton(parent, {
  label = "Choose Option",
  labelAnchor = "LEFT",
  labelWidth = 100,
  buttonText = "Select...",
  buttonWidth = 120,
  menuItems = menuItems
})

container:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -10)

-- Stack menu buttons using AnchorElement
local container2, button2, menu2 = OGST.CreateMenuButton(parent, {
  label = "Another Menu",
  labelAnchor = "LEFT",
  labelWidth = 100,
  buttonText = "Pick One",
  menuItems = {
    {text = "Choice A", selected = false, onClick = function() end},
    {text = "Choice B", selected = true, onClick = function() end}
  }
})

OGST.AnchorElement(container2, container, {position = "below"})
```

**Note:** When a menu item is clicked, it automatically becomes selected (green text) and all other items in that menu are deselected. The menu is automatically rebuilt to reflect the new selection state.

---

### Text Input

#### OGST.CreateSingleLineTextBox(parent, width, height, config)
Create a single-line text input box with backdrop and optional label.

**Parameters:**
- `parent` (Frame): Parent frame
- `width` (number): Text box width
- `height` (number): Text box height (default: 24)
- `config` (table): Optional configuration
  - `align` (string): "LEFT", "CENTER", or "RIGHT" (default: "LEFT")
  - `maxLetters` (number): Maximum characters (default: 0 = unlimited)
  - `numeric` (boolean): Only allow numeric input (default: false)
  - `font` (string): Font object (default: ChatFontNormal)
  - `onChange` (function): Callback(text) when text changes
  - `onEnter` (function): Callback(text) when Enter is pressed
  - `onEscape` (function): Callback() when Escape is pressed
  - `autoFocus` (boolean): Auto-focus on creation (default: false)
  - `label` (string): Label text (optional)
  - `labelAnchor` (string): "TOP-LEFT", "TOP-RIGHT", "BOTTOM-LEFT", "BOTTOM-RIGHT", "LEFT", "RIGHT" (default: "LEFT")
  - `labelFont` (string): Font object for label (default: GameFontNormalSmall)
  - `labelColor` (table): RGB table `{r, g, b}` (default: white)

**Returns:**
- `backdrop`: Container frame
- `editBox`: EditBox frame
- `labelText`: Label FontString (or nil if no label)

**Example:**
```lua
-- Text box with label to the left
local backdrop, editBox, label = OGST.CreateSingleLineTextBox(parent, 200, 24, {
  align = "CENTER",
  maxLetters = 50,
  numeric = false,
  label = "Player Name",
  labelAnchor = "LEFT",
  onChange = function(text)
    print("Text changed:", text)
  end,
  onEnter = function(text)
    print("Enter pressed with:", text)
  end,
  onEscape = function()
    print("Escape pressed")
  end
})

backdrop:SetPoint("CENTER", parent, "CENTER")
editBox:SetText("Initial text")

-- Numeric text box with label above
local numBackdrop, numEditBox = OGST.CreateSingleLineTextBox(parent, 80, 24, {
  align = "CENTER",
  numeric = true,
  label = "Count",
  labelAnchor = "TOP-LEFT",
  onEnter = function(text)
    local value = tonumber(text) or 0
    print("Value:", value)
  end
})
```

#### OGST.CreateScrollingTextBox(parent, width, height)
Create a scrolling multi-line text box with backdrop and scrollbar.

**Parameters:**
- `parent` (Frame): Parent frame
- `width` (number): Text box width
- `height` (number): Text box height

**Returns:**
- `backdrop`: Container frame
- `editBox`: EditBox frame
- `scrollFrame`: Scroll frame
- `scrollBar`: Scrollbar slider

**Example:**
```lua
local backdrop, editBox, scrollFrame, scrollBar = 
  OGST.CreateScrollingTextBox(parent, 400, 300)

backdrop:SetPoint("CENTER", parent, "CENTER")
editBox:SetText("Multi-line text here...")
```

---

### Frame Utilities

#### OGST.MakeFrameCloseOnEscape(frame, frameName, closeCallback)
Register a frame to close when ESC is pressed.

**Parameters:**
- `frame` (Frame): The frame to register
- `frameName` (string): Unique frame identifier
- `closeCallback` (function): Optional callback on close

**Example:**
```lua
local myFrame = CreateFrame("Frame", "MyAddonFrame", UIParent)
OGST.MakeFrameCloseOnEscape(myFrame, "MyAddonFrame", function()
  print("Frame closed")
end)
```

---

## License

This library is part of the OG-RaidHelper project and shares the same license.

## Version History

### 1.0.0 (December 8, 2025)
- Initial release
- Extracted from OG-RaidHelper Core
- Button styling
- Menu system with submenus
- Scroll lists
- List items with buttons
- Text boxes
- Frame utilities
