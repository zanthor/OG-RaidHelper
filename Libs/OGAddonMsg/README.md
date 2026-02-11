# OGAddonMsg

**Unified addon network interface for WoW 1.12 (Turtle WoW)**

Version 1.2.0

---

## Overview

OGAddonMsg provides reliable, asynchronous addon communication with:
- Automatic message chunking for large payloads
- Self-healing retry mechanism for zoning/reloads
- Priority queue with bandwidth throttling
- Network health monitoring with configurable warnings
- Callback-based async API

## Features

- ✅ Respects Turtle WoW message size limits (~255 bytes)
- ✅ Automatic chunking of large messages
- ✅ Asynchronous operation with callbacks
- ✅ Self-healing: auto-retry after zone/reload
- ✅ Priority queue (CRITICAL/HIGH/NORMAL/LOW)
- ✅ ChatThrottleLib integration for bandwidth management
- ✅ Network latency warnings
- ✅ Statistics and diagnostics
- ✅ Debug mode for troubleshooting
- ✅ Embeddable: newest version auto-loads

## Turtle WoW Limitations

**No WHISPER Support for Addon Messages:**
- Turtle WoW only supports addon messages on RAID, PARTY, and GUILD channels
- `SendTo(playerName, ...)` automatically redirects to RAID > PARTY > GUILD
- Messages are broadcast to all members, not sent directly to one player
- Applications must handle filtering on the receiving side if needed

## Quick Start

### Basic Send
```lua
OGAddonMsg.Send("RAID", nil, "MYADDON_MSG", "Hello raid!", {
    onSuccess = function()
        print("Message sent!")
    end
})
```

### Register Handler
```lua
OGAddonMsg.RegisterHandler("MYADDON_MSG", function(sender, data, channel)
    print("Received from " .. sender .. ": " .. data)
end)
```

### Check Status
```
/ogmsg status
/ogmsg stats
```

## Commands

- `/ogmsg help` - Show all commands
- `/ogmsg status` - Show queue status and config
- `/ogmsg stats` - Show statistics
- `/ogmsg debug on|off` - Toggle debug logging

**Configuration:**
- `/ogmsg warnqueue <sec>` - Queue warning threshold (default: 5)
- `/ogmsg maxrate <msgs/sec>` - Throttling rate (default: 8)
- `/ogmsg retaintime <sec>` - Retry buffer retention (default: 60)

See `/ogmsg help` for full command list.

## API Reference

See [Documentation/OGAddonMsg-Specification.md](Documentation/OGAddonMsg-Specification.md) for complete API documentation.

### Core Functions

**Sending:**
- `OGAddonMsg.Send(channel, target, prefix, data, options)` - Send message
- `OGAddonMsg.Broadcast(prefix, data, options)` - Broadcast to all channels
- `OGAddonMsg.SendTo(playerName, prefix, data, options)` - Broadcast (TWoW: no direct messaging)

**Receiving:**
- `OGAddonMsg.RegisterHandler(prefix, callback)` - Register message handler
- `OGAddonMsg.UnregisterHandler(handlerId)` - Remove handler

**Stats & Config:**
- `OGAddonMsg.GetStats()` - Get statistics
- `OGAddonMsg.SetConfig(key, value)` - Set config value
- `OGAddonMsg.GetConfig(key)` - Get config value

## Development Status

**Current Phase:** Phase 1 - Stubs Created
- ✅ File structure and TOC
- ✅ Basic namespace and events
- ✅ Command system
- ⚠️ Core functionality (chunking, queue, retry) - TODO

**Next Steps:**
1. Implement chunking algorithm
2. Implement queue processing and SendAddonMessage integration
3. Implement reassembly logic
4. Implement retry system
5. Testing and optimization

## Requirements

- WoW 1.12 client (Vanilla/Turtle WoW)
- Lua 5.0/5.1 compatibility

## License

Created for OG addons. Free to use and modify.

---

For detailed implementation specification, see [Documentation/OGAddonMsg-Specification.md](Documentation/OGAddonMsg-Specification.md)
