# _OGAALogger Source Prefix Colors

This document defines the standardized color codes for different addon sources in the OG Auto Addon Logger.

## Color Assignments

| Source | Addon | Color Code | RGB | Preview |
|--------|-------|------------|-----|---------|
| `OGRH` | OG-RaidHelper | `\|cff66ccff` | (0.4, 0.8, 1.0) | Cyan/Aqua |
| `AM` | _OGAddonMsg | `\|cffcc66ff` | (0.8, 0.4, 1.0) | Purple/Magenta |
| `GUI` | _OGGUI | `\|cff66ff66` | (0.4, 1.0, 0.4) | Bright Green |
| `ST` | _OGST | `\|cffffff66` | (1.0, 1.0, 0.4) | Yellow/Gold |
| `SYSTEM` | System Messages | `\|cffaaaaaa` | (0.67, 0.67, 0.67) | Gray |
| `LUA-ERROR` | Lua Errors | `\|cffff4444` | (1.0, 0.27, 0.27) | Red |

## Color Format

WoW uses the format `|cffRRGGBB` where:
- `RR` = Red (00-FF hex)
- `GG` = Green (00-FF hex)
- `BB` = Blue (00-FF hex)

## Usage Guidelines

1. **Consistency**: Always use these exact color codes for the respective sources
2. **Readability**: Colors chosen to be distinct and readable on dark backgrounds
3. **Extensibility**: When adding new sources, choose colors that don't conflict with existing ones
4. **Fallback**: If OGAALogger is not available, addons should display with their assigned color prefix in DEFAULT_CHAT_FRAME

## Adding New Sources

When integrating a new addon:
1. Choose a unique 2-4 character source identifier
2. Select a color that's visually distinct from existing sources
3. Update this document with the new source
4. Create a MessageRouter.lua file in the addon with the routing function
5. Add `## OptionalDeps: _OGAALogger` to the addon's TOC file
6. Load MessageRouter.lua early in the TOC (before any messages are sent)

## Example Implementation

```lua
-- AddonName/MessageRouter.lua
AddonName = AddonName or {}

AddonName.Msg = function(text)
    if OGAALogger and OGAALogger.AddMessage then
        OGAALogger.AddMessage("SRC", tostring(text))
    else
        local formattedText = "|cffCOLOR[SRC]|r" .. tostring(text)
        DEFAULT_CHAT_FRAME:AddMessage(formattedText, r, g, b)
    end
end
```

## Version History

- **v1.0.0** (2026-02-06): Initial color scheme definition
  - OGRH: Cyan
  - AM: Purple
  - GUI: Green
  - ST: Yellow
