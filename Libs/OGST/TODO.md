# OGST TODO List

## Planned Features

### Dynamic Menu Item Registration System
Add support for external components to register menu items dynamically without editing base code.

**Requirements:**
- Allow external modules to register menu items to existing menus
- Support priority/sorting for item order
- Support nested submenus
- Items should be added declaratively without modifying OGST source
- Should work with existing `OGST.CreateStandardMenu()` function

**Proposed API:**
```lua
-- Register a menu item to an existing menu
OGST.RegisterMenuItem(menuName, {
  text = "My Feature",
  priority = 10,  -- Lower numbers appear first
  onClick = function() end,
  submenu = {
    {text = "Sub Option 1", onClick = function() end},
    {text = "Sub Option 2", onClick = function() end}
  }
})

-- Create a menu with dynamic item support
local menu = OGST.CreateDynamicMenu({
  name = "MyDynamicMenu",
  width = 180,
  title = "Options",
  allowExternalItems = true
})
```

**Use Cases:**
- Addons can extend main application menus
- Modular features can register their own menu items
- No need to maintain centralized menu definitions
- Easy to add/remove features without core changes

**Status:** Planned

---

### Menu Button Enable/Disable Support
Add enable/disable functionality to `OGST.CreateMenuButton()` with support for custom disabled text.

**Requirements:**
- Add functions to enable/disable menu buttons after creation
- When disabled, optionally change the button text (not the label)
- Should not change visual appearance (button styling should remain consistent)
- State should be queryable (check if button is enabled/disabled)

**Proposed API:**
```lua
-- Enable/disable a menu button
OGST.SetMenuButtonEnabled(menuButton, enabled, disabledText)
-- menuButton: The container returned from CreateMenuButton
-- enabled: boolean (true/false)
-- disabledText: optional string to display when disabled (e.g., "<Enable to Set>")

-- Query enabled state
local isEnabled = OGST.IsMenuButtonEnabled(menuButton)

-- Example usage
local menuBtn = OGST.CreateMenuButton(parent, {...})
OGST.SetMenuButtonEnabled(menuBtn, false, "<Enable to Set>")
```

**Use Cases:**
- Disable menu button when prerequisite settings are not configured
- Show contextual text like "<Enable to Set>" when disabled
- Enable menu button when dependencies are satisfied
- Maintain consistent UI styling regardless of enabled/disabled state

**Status:** Planned

---

## Bugs to Debug

### Click-Outside-to-Close Feature Not Working
The `closeOnClickOutside` feature in `CreateStandardWindow()` is not capturing clicks outside the dialog.

**Current Behavior:**
- Clicks outside the dialog window register on underlying UI elements
- Dialog does not close when clicking outside
- Feature enabled with `closeOnClickOutside = true` config option

**Implementation Details:**
- Backdrop frame created at FULLSCREEN_DIALOG strata with level 1
- Dialog frame at FULLSCREEN_DIALOG strata with level 2
- Backdrop has `EnableMouse(true)` and `OnMouseDown` handler to close window
- OnShow/OnHide handlers manage backdrop visibility

**Potential Issues:**
- Frame level conflicts with other FULLSCREEN_DIALOG frames
- Mouse event propagation not working as expected in WoW 1.12
- Backdrop may need different event handler (OnClick vs OnMouseDown)
- May need to adjust frame strata hierarchy or use different approach

**Status:** Investigation needed
