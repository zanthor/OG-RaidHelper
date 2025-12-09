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
Create a standardized window frame with optional close button, ESC handling, and window management.

**Parameters:**
- `config` (table): Configuration options (required)
  - `name` (string): Unique frame name (required)
  - `width` (number): Window width (required)
  - `height` (number): Window height (required)
  - `title` (string): Window title text (required)
  - `closeButton` (boolean): Add close button (default: true)
  - `escapeCloses` (boolean): ESC key closes window (default: true)
  - `closeOnNewWindow` (boolean): Close when other windows open (default: false)

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
  closeOnNewWindow = true
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
  - `name` (string): Frame name for ESC key handling
  - `width` (number): Menu width (default: 160)
  - `title` (string): Optional title text
  - `titleColor` (table): RGB table `{r, g, b}` for title (default: white)
  - `itemColor` (table): RGB table `{r, g, b}` for items (default: white)

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

### Text Box

#### OGST.CreateScrollingTextBox(parent, width, height)
Create a scrolling multi-line text box.

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
