# BigWigs Dropdown Menu - Debug Session

## Problem Statement
The BigWigs Encounter dropdown menu in Advanced Settings shows zone names (like "Molten Core", "Blackwing Lair") but hovering over them does NOT open the submenu showing boss names. The submenu should open on hover.

## Root Cause Found
In `_OGST\OGST.lua` around line 2175, the `CreateMenuButton` function calls `menu:AddItem()` but was NOT passing the `submenu` property through:

```lua
-- WRONG (original code):
local item = menu:AddItem({
  text = capturedConfig.text,
  onClick = capturedConfig._internalOnClick
})

-- FIXED:
local item = menu:AddItem({
  text = capturedConfig.text,
  onClick = capturedConfig._internalOnClick,
  submenu = capturedConfig.submenu  -- THIS LINE WAS MISSING
})
```

## Changes Made

### File: `_OGST\OGST.lua`
**Line ~2175-2179**: Added `submenu = capturedConfig.submenu` to the AddItem call

### File: `OG-RaidHelper\Libs\OGST\OGST.lua` 
**Line ~2149-2153**: Made the same fix (in case this file is used instead)

### File: `OGRH_AdvancedSettings.lua`
**Lines ~308-327**: Added debug output (can be removed later):
- Debug before CreateMenuButton call
- Debug showing bigwigsPanel and bigwigsCheckContainer values
- pcall wrapper to catch errors

## Current Status
- Fix has been applied to both OGST.lua files
- Menu still NOT working after `/reload`
- Debug output shows CreateMenuButton is called successfully with 9 items
- No errors reported

## Next Steps to Try

1. **Exit WoW completely and restart** (not just /reload)
   - Lua files may be cached in memory
   
2. **Verify which OGST is loading**:
   - Check `OG-RaidHelper.toc` line 12 for which OGST path
   - Add debug at TOP of `function OGST.CreateMenuButton` (before line 2032 `if not parent`) to confirm right file is loaded
   
3. **Check if submenu property is preserved**:
   - Add debug in AddItem (line ~676) to print `hasSubmenu` value
   - Verify submenuItems array is not nil/empty
   
4. **Verify OnEnter handler fires**:
   - The fix should make `hasSubmenu = true` for parent items
   - OnEnter script (line ~707) should create submenu on hover
   - Add debug there to confirm it's firing

## Menu Structure
```lua
menuItems = {
  {text = "<Clear Selection>", onClick = function...},  -- Leaf item
  {text = "Molten Core", submenu = {...}},              -- Parent with submenu
  {text = "Blackwing Lair", submenu = {...}},           -- Parent with submenu
  ...
}

submenu = {
  {text = "Lucifron", onClick = function...},           -- Leaf item
  {text = "Magmadar", onClick = function...},           -- Leaf item
  ...
}
```

## Code Locations
- **Menu creation**: `OGRH_AdvancedSettings.lua` lines 263-306
- **CreateMenuButton**: `_OGST\OGST.lua` line 2031
- **AddItem call**: `_OGST\OGST.lua` line 2175
- **AddItem function**: `_OGST\OGST.lua` line 670
- **OnEnter handler**: `_OGST\OGST.lua` line 707
- **CreateSubmenu**: `_OGST\OGST.lua` line 744

## Debug Lines Added (Remove Later)
All debug lines can be searched for with: `DEFAULT_CHAT_FRAME:AddMessage.*CreateMenuButton|bigwigsPanel|About to call`

- Line 2036 in OGST.lua: "=== CreateMenuButton START ==="
- Line 2039 in OGST.lua: "MenuItems array has X items"
- Line 2124 in OGST.lua: "OGST: Adding parent item..."
- Line 676 in OGST.lua: "AddItem called: text=..."
- Line 709 in OGST.lua: "OnEnter for: ..."
- Line 2191 in OGST.lua: "BUTTON CLICKED!..."
- Lines 308-310 in OGRH_AdvancedSettings.lua: Various debug about CreateMenuButton call

## Theory Why Still Not Working
Despite the fix being applied, submenu still doesn't work. Possibilities:
1. The Lua file in memory is stale (requires WoW restart, not just /reload)
2. There's another OGST.lua being loaded we haven't found
3. The submenu array itself is malformed or empty
4. OnEnter handler has a different bug preventing submenu creation
