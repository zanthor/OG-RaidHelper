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
