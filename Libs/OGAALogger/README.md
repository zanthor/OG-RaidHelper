# _OGAALogger - Auto Addon Logger

**Version:** 1.0.0  
**Author:** OG Development

---

## Overview

_OGAALogger (Auto Addon Logger) is a lightweight TWoW library that provides a dedicated logging window for addon output. Addons explicitly send messages to the logger for easy viewing and export.

---

## Features

- ✅ **Explicit Logging** - Only displays messages sent via `OGAALogger.AddMessage()`
- ✅ **500 Message Buffer** - Retains last 500 messages (newest at top)
- ✅ **Formatted Output** - `[Date/Timestamp] [Source] Message`
- ✅ **Pre-formatted Messages** - Supports color codes and formatting in messages
- ✅ **Session Markers** - Clear indicators when UI/client reloads
- ✅ **Copy/Paste Support** - Full text selection and clipboard export
- ✅ **Clean UI** - 750×500px non-resizable window with Clear and Select All buttons
- ✅ **Embeddable** - Other addons can integrate the logger via API
- ✅ **No Dependencies** - Standalone library

---

## Usage

### Slash Commands

```
/ogl          Toggle log viewer window
/ogl show     Open log viewer window
/ogl hide     Close log viewer window
/ogl clear    Clear all log messages
```

---

## API Reference (Embedding)

### Initialization

```lua
-- Check if logger is available
if OGAALogger then
    -- Logger is loaded and ready
end
```

### Public Functions

#### `OGAALogger.AddMessage(source, message)`

Add a message to the log programmatically.

**Parameters:**
- `source` (string) - Source addon/system name
- `message` (string) - Pre-formatted message text (can include WoW color codes)

**Examples:**
```lua
-- Simple message
OGAALogger.AddMessage("MyAddon", "Feature initialized")

-- Message with color codes
OGAALogger.AddMessage("OGRH", "|cff00ff00Sync completed successfully|r")

-- Multi-line or complex message
OGAALogger.AddMessage("RaidHelper", "|cffff0000Error:|r Failed to load encounter data")
```

---

#### `OGAALogger.Clear()`

Clear all logged messages.

**Example:**
```lua
OGAALogger.Clear()
```

---

#### `OGAALogger.Show()`

Show the log viewer window.

**Example:**
```lua
OGAALogger.Show()
```

---

#### `OGAALogger.Hide()`

Hide the log viewer window.

**Example:**
```lua
OGAALogger.Hide()
```

---

#### `OGAALogger.Toggle()`

Toggle log viewer visibility.

**Example:**
```lua
OGAALogger.Toggle()
```

---
 (YYYY-MM-DD HH:MM:SS)
- `source` (string) - Message source
- `text` (string) - Pre-formatted message content (may include color codes)

**Returns:** Array of message objects with fields:
- `timestamp` (string) - Formatted date/time
- `source` (string) - Message source
- `text` (string) - Message content
- `r, g, b` (number) - Color values

**Example:**
```lua
local messages = OGAALogger.GetMessages()
for i = 1, table.getn(messages) do
    local msg = messages[i]
    print(msg.timestamp, msg.source, msg.text)
end
```

---

## Installation

### Standalone

1. Extract `_OGAALogger` folder to `Interface/AddOns/`
2. Restart game or `/reload`
3. Use `/ogl` to open log viewer

### Embedded in Another Addon

1. Copy `_OGAALogger` folder to `Interface/AddOns/`
2. In your addon's TOC, add:
   ```
   ## OptionalDeps: _OGAALogger
   ```
3. In your code:
   ```lua
   if OGAALogger then
       OGAALogger.AddMessage("MyAddon", "Initialized")
   end
   ```

---

## Technical Details

### Message Format

```
[2026-02-06 14:23:45] [OGRH] Sync integrity check passed
└─ Timestamp          └─ Source └─ Message content
```

### Storage

- Messages stored in `OGAAL_SV.messages` (SavedVariables)
- Circular buffer: max 500 messages
- Session markers added on PLAYER_L (configurable 50-5000)
- Session markers added on PLAYER_LOGIN

### Message Handling

The logger only displays messages explicitly sent via `OGAALogger.AddMessage()`:
- No automatic hooking or capturing
- Addons must call `AddMessage()` to log output
- Messages can include WoW color codes for formatting
- Source is always specified by the calling addon
---

## Styling

The UI uses _OGST-inspired styling (inlined, no dependencies):
- Dark background with cyan borders
- Styled buttons with hover effects
- Scrollable text area with copy/paste support

---

## Known Limitations
displays messages explicitly sent via `OGAALogger.AddMessage()`
2. Not a replacement for DEFAULT_CHAT_FRAME (addons must opt-in)
3. 500 message limit (oldest messages automatically pruned, configurable
3. 500 message limit (oldest messages automatically pruned)

---

## Changelog

### Version 1.0.0 (February 6, 2026)
- Initial release
- Message capture system
- Log viewer UI
- Embedding API
- Slash commands

---

## License

Part of the OG Development addon suite.

---

## Support

For issues or feature requests, contact OG Development team.
