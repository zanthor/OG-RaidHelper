# _OGAddonMsg: Unified Addon Network Interface
**Design Specification v1.0**  
**Target Environment:** WoW 1.12 (Turtle WoW)  
**Date:** January 2026

---

## Table of Contents
1. [Executive Summary](#executive-summary)
2. [Core Requirements](#core-requirements)
3. [Architecture Overview](#architecture-overview)
4. [Technical Specifications](#technical-specifications)
5. [API Reference](#api-reference)
6. [Configuration & Commands](#configuration--commands)
7. [Development Constraints](#development-constraints)
8. [Testing Requirements](#testing-requirements)

---

## Executive Summary

`_OGAddonMsg` is a unified network communication library for Turtle WoW addons. It provides:
- **Reliable messaging** with automatic chunking, retry, and self-healing
- **Asynchronous operation** with callback-based design
- **Network health monitoring** with configurable warnings
- **Embeddable library** that auto-loads the newest version (like `_OGST`)

### Design Goals
- Simplify addon-to-addon communication
- Handle Turtle WoW message size limits transparently
- Prevent disconnects through throttling
- Recover gracefully from zoning/reloads
- Provide clear feedback on network health

---

## Core Requirements

### 1. Deployment Model
- **Stand-alone addon** OR **embeddable library**
- Multiple copies can exist in `AddOns/` folder
- Newest version automatically takes precedence
- Single global namespace: `OGAddonMsg`

### 2. Message Size Handling
- **Respect Turtle WoW limits:**
  - Base addon channel: ~255 bytes per message
  - Actual safe limit: **~200 bytes** after overhead
- **Automatic chunking** for messages exceeding limit
- **Transparent reassembly** on receiving end
- **Header overhead** for chunk metadata (sequence, count, hash)

### 3. Network Latency Monitoring
- **Queue depth tracking** in seconds of delay
- **Warning thresholds:**
  - Single warning if queue exceeds 5 seconds
  - Periodic warnings (every 10s) if queue exceeds 5s for more than 30s consecutive
- **Configurable via commands:**
  - `/ogmsg warnqueue <seconds>` - Set warning threshold (default: 5)
  - `/ogmsg warnperiod <seconds>` - Set sustained warning duration (default: 30)
  - `/ogmsg warninterval <seconds>` - Set periodic warning interval (default: 10)

### 4. Asynchronous Operation
- **Non-blocking sends** - Calling addon continues immediately
- **Callback-based delivery:**
  ```lua
  OGAddonMsg.Send(channel, target, prefix, data, {
      onSuccess = function() end,
      onFailure = function(reason) end,
      onProgress = function(sent, total) end  -- For chunked messages
  })
  ```
- **Queue system** - Messages queued and sent over time

### 5. Self-Healing & Retry
- **Sending side:**
  - Retain sent packets for **60 seconds** (configurable)
  - Honor retry requests from receivers
  - Track active multi-chunk transmissions
- **Receiving side:**
  - Detect incomplete transmissions (partial chunks received)
  - Request retransmission on zone-in if incomplete message detected
  - Timeout incomplete messages after 90 seconds
- **Configuration:**
  - `/ogmsg retaintime <seconds>` - How long to retain sent packets (default: 60)
  - `/ogmsg timeout <seconds>` - When to give up on incomplete receives (default: 90)

### 6. Priority System
- **Priority levels:** `CRITICAL`, `HIGH`, `NORMAL`, `LOW`
- **Queue ordering:**
  - CRITICAL always first
  - HIGH before NORMAL before LOW
  - Within same priority: FIFO
- **Usage:**
  ```lua
  OGAddonMsg.Send(channel, target, prefix, data, {
      priority = "HIGH"
  })
  ```

### 7. Channel Management
- **Auto-detect best channel:**
  1. RAID (if in raid)
  2. PARTY (if in party)
  3. GUILD (if in guild and target is guildmate)
  4. WHISPER (for direct messages)
  5. Explicit channel override
- **Channel types supported:**
  - `"ADDON"` - Hidden addon channel (primary)
  - `"RAID"` - Raid chat
  - `"PARTY"` - Party chat
  - `"GUILD"` - Guild chat
  - `"WHISPER"` - Direct whisper

### 9. Callback Registration
- **Register handlers by prefix:**
  ```lua
  OGAddonMsg.RegisterHandler("OGRH", function(sender, data, channel)
      -- Handle message from OG-RaidHelper
  end)
  ```
- **Wildcard handlers:** Register for all messages
- **Multiple handlers** per prefix (all called)

### 10. Duplicate Detection
- **Hash-based deduplication** within 60-second window
- **Prevents processing** same message multiple times
- **Handles network quirks** and retransmissions

### 11. Bandwidth Throttling
- **Respect Blizzard rate limits:**
  - Max ~10 messages per second
  - Burst limit: ~20 messages
  - Exceeding causes disconnect
- **Configurable safety margin:**
  - `/ogmsg maxrate <msgs/sec>` - Default: 8 (conservative)
  - `/ogmsg burstlimit <count>` - Default: 15

### 12. Statistics & Diagnostics
- **Track metrics:**
  - Messages sent/received
  - Bytes sent/received
  - Queue depth (current/max)
  - Chunks sent/reassembled
  - Retries requested/honored
  - Failures and reasons
- **Display stats:**
  - `/ogmsg stats` - Show statistics
  - `/ogmsg stats reset` - Clear statistics

### 13. Debug Mode
- **Verbose logging:** `/ogmsg debug on|off`
- **Log to chat:**
  - Message send/receive
  - Chunk assembly
  - Retries
  - Queue depth
  - Throttling events

### 14. Protocol Versioning
- **Version handshake** on first message
- **Compatibility checks:**
  - Warn if remote version incompatible
  - Graceful degradation when possible
- **Version in every packet header**

---

## Architecture Overview

### Component Diagram

```
┌─────────────────────────────────────────────────────────┐
│  Calling Addon (e.g., OG-RaidHelper)                    │
└────────────────┬────────────────────────────────────────┘
                 │ Send()/RegisterHandler()
                 ▼
┌─────────────────────────────────────────────────────────┐
│  OGAddonMsg - Public API Layer                          │
│  - Send(), SendTo(), Broadcast()                        │
│  - RegisterHandler(), UnregisterHandler()               │
│  - GetStats(), SetConfig()                              │
└────────────────┬────────────────────────────────────────┘
                 │
        ┌────────┴────────┐
        ▼                 ▼
┌──────────────┐  ┌──────────────────┐
│ Chunker      │  │ Callback Manager │
│ - Chunk()    │  │ - Dispatch()     │
│ - Reassemble│  │ - Register()     │
└──────┬───────┘  └──────────────────┘
       │
       ▼
┌─────────────────────────────────────────────────────────┐
│  Priority Queue & Throttler                             │
│  - Enqueue by priority                                  │
│  - Rate limiting                                        │
│  - Burst detection                                      │
└────────────────┬────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────┐
│  Retry Manager                                           │
│  - Retain sent packets (60s)                            │
│  - Track incomplete receives                            │
│  - Handle retransmission requests                       │
└────────────────┬────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────┐
│  WoW SendAddonMessage / CHAT_MSG_ADDON Event            │
└─────────────────────────────────────────────────────────┘
```

### Data Flow: Sending a Large Message

```
1. Addon calls: OGAddonMsg.Send("RAID", nil, "OGRH_SYNC", largeData)
```
1. Validate data and prefix
2. Chunk into 200-byte segments
3. Generate message ID and chunk headers
4. Enqueue chunks by priority
5. Throttler sends chunks over time
6. Store in retry buffer (60s)
7. Call onSuccess callback when all chunks sent
```

### Data Flow: Receiving a Chunked Message

```
1. CHAT_MSG_ADDON fires with chunk
2. Parse header (msgId, chunkNum, totalChunks, hash)
3. Store chunk in reassembly buffer
4. If all chunks received:
   a. Verify hash
   b. Dispatch to registered handlers
   c. Call sender's callback (if local)
5. If incomplete after timeout:
   a. Request retransmission
   b. Or discard and notify failure
```

### Data Flow: Zoning During Receive

```
1. Player zones (PLAYER_ENTERING_WORLD)
2. Check reassembly buffer for incomplete messages
3. For each incomplete:
   a. Generate retry request
   b. Send to original sender
4. Sender checks retry buffer
5. Re-enqueue chunks if still retained
6. Resume normal receive flow
```

---

## Technical Specifications

### Message Format

#### Single-Chunk Message (< 200 bytes)
```
[Version:1] [Type:S] [MsgID:4] [Prefix:*] \t [Data:*]

Example:
"1S4a2fOGRH_SYNC\t{raid=1,players=40}"
```

#### Multi-Chunk Message Header
```
[Version:1] [Type:M] [MsgID:4] [Chunk:2/3] [Total:2] [Hash:4] [Prefix:*] \t [Data:*]

Example (chunk 1 of 3):
"1M4a2f1/3ab3cOGRH_SYNC\t{partial data...}"
```

#### Retry Request
```
[Version:1] [Type:R] [MsgID:4] [Missing:*]

Example (request chunks 2 and 4):
"1R4a2f2,4"
```

#### Fields:
- **Version:** Protocol version (1 byte)
- **Type:** S=Single, M=Multi, R=Retry, A=Ack (1 byte)
- **MsgID:** Unique message identifier (4 bytes hex)
- **Chunk:** Current chunk number (2 bytes hex)
- **Total:** Total chunks (2 bytes hex)
- **Hash:** CRC of full message (4 bytes hex)
- **Prefix:** Addon-specific prefix (variable)
- **Data:** Actual payload (variable)

### Chunking Algorithm

```lua
function ChunkMessage(prefix, data, maxChunkSize)
    -- maxChunkSize ~= 200 bytes minus header overhead
    local headerSize = 20  -- Estimate for version+type+msgId+chunk+total+hash
    local prefixSize = string.len(prefix) + 1  -- +1 for tab
    local dataPerChunk = maxChunkSize - headerSize - prefixSize
    
    local chunks = {}
    local msgId = GenerateMsgId()
    local hash = ComputeHash(data)
    local totalChunks = math.ceil(string.len(data) / dataPerChunk)
    
    for i = 1, totalChunks do
        local startPos = (i - 1) * dataPerChunk + 1
        local endPos = math.min(i * dataPerChunk, string.len(data))
        local chunkData = string.sub(data, startPos, endPos)
        
        local header = string.format("1M%s%02d/%02d%s%s\t", 
            msgId, i, totalChunks, hash, prefix)
        
        table.insert(chunks, header .. chunkData)
    end
    
    return msgId, chunks
end
```

### Queue Management

```lua
OGAddonMsg.queue = {
    CRITICAL = {},
    HIGH = {},
    NORMAL = {},
    LOW = {}
}

function Enqueue(priority, message, callbacks)
    local item = {
        msg = message,
        callbacks = callbacks,
        enqueueTime = GetTime()
    }
    table.insert(OGAddonMsg.queue[priority], item)
end

function Dequeue()
    -- Check priorities in order
    for _, priority in ipairs({"CRITICAL", "HIGH", "NORMAL", "LOW"}) do
        if table.getn(OGAddonMsg.queue[priority]) > 0 then
            local item = table.remove(OGAddonMsg.queue[priority], 1)
            return item
        end
    end
    return nil
end
```

### Throttling Engine

```lua
-- OnUpdate handler (runs every frame)
local lastSend = 0
local burstCount = 0
local burstWindow = 1  -- 1 second

function ThrottlerUpdate()
    local now = GetTime()
    
    -- Reset burst counter every second
    if now - lastSend >= burstWindow then
        burstCount = 0
    end
    
    -- Check if we can send
    local config = OGAddonMsg.config
    if burstCount >= config.burstLimit then
        return  -- Burst limit hit, wait
    end
    
    -- Calculate time since last send
    local timeSinceLast = now - lastSend
    local minInterval = 1 / config.maxRate  -- e.g., 1/8 = 0.125s
    
    if timeSinceLast < minInterval then
        return  -- Too soon, wait
    end
    
    -- Dequeue and send
    local item = Dequeue()
    if item then
        SendAddonMessage(item.msg, ...)
        lastSend = now
        burstCount = burstCount + 1
        
        -- Update stats
        OGAddonMsg.stats.messagesSent = OGAddonMsg.stats.messagesSent + 1
        
        -- Callback
        if item.callbacks and item.callbacks.onSuccess then
            item.callbacks.onSuccess()
        end
    end
end
```

### Reassembly Buffer

```lua
OGAddonMsg.reassembly = {
    -- [msgId] = {
    --     sender = "PlayerName",
    --     prefix = "OGRH_SYNC",
    --     totalChunks = 5,
    --     hash = "ab3c",
    --     chunks = {[1] = "data", [3] = "data", ...},
    --     receivedCount = 2,
    --     firstReceived = 123456.78,
    --     lastReceived = 123460.12
    -- }
}

function OnChunkReceived(sender, msgId, chunkNum, totalChunks, hash, prefix, data)
    local entry = OGAddonMsg.reassembly[msgId]
    
    if not entry then
        -- New message
        entry = {
            sender = sender,
            prefix = prefix,
            totalChunks = totalChunks,
            hash = hash,
            chunks = {},
            receivedCount = 0,
            firstReceived = GetTime()
        }
        OGAddonMsg.reassembly[msgId] = entry
    end
    
    -- Store chunk if not duplicate
    if not entry.chunks[chunkNum] then
        entry.chunks[chunkNum] = data
        entry.receivedCount = entry.receivedCount + 1
        entry.lastReceived = GetTime()
    end
    
    -- Check if complete
    if entry.receivedCount == entry.totalChunks then
        CompleteMessage(msgId, entry)
    end
end

function CompleteMessage(msgId, entry)
    -- Concatenate chunks
    local fullData = ""
    for i = 1, entry.totalChunks do
        fullData = fullData .. entry.chunks[i]
    end
    
    -- Verify hash
    local computedHash = ComputeHash(fullData)
    if computedHash ~= entry.hash then
        -- Hash mismatch, request retry
        RequestRetry(entry.sender, msgId, nil)  -- All chunks
        return
    end
    
    -- Dispatch to handlers
    DispatchToHandlers(entry.sender, entry.prefix, fullData)
    
    -- Clean up
    OGAddonMsg.reassembly[msgId] = nil
end
```

### Retry System

```lua
OGAddonMsg.retryBuffer = {
    -- [msgId] = {
    --     chunks = {"chunk1", "chunk2", ...},
    --     sentTime = 123456.78,
    --     expiresAt = 123516.78  -- sentTime + retainTime
    -- }
}

function OnRetryRequest(sender, msgId, missingChunks)
    local entry = OGAddonMsg.retryBuffer[msgId]
    
    if not entry then
        -- Message expired or unknown
        DEFAULT_CHAT_FRAME:AddMessage(
            "OGAddonMsg: Retry request for expired message from " .. sender,
            1, 1, 0
        )
        return
    end
    
    -- Determine which chunks to resend
    local chunksToSend = {}
    if missingChunks then
        -- Specific chunks requested
        for _, chunkNum in ipairs(missingChunks) do
            table.insert(chunksToSend, entry.chunks[chunkNum])
        end
    else
        -- All chunks requested
        chunksToSend = entry.chunks
    end
    
    -- Re-enqueue chunks (HIGH priority for retries)
    for _, chunk in ipairs(chunksToSend) do
        Enqueue("HIGH", chunk, nil)
    end
    
    -- Update stats
    OGAddonMsg.stats.retriesSent = OGAddonMsg.stats.retriesSent + 1
end

-- Cleanup expired entries (called on OnUpdate)
function CleanupRetryBuffer()
    local now = GetTime()
    for msgId, entry in pairs(OGAddonMsg.retryBuffer) do
        if now >= entry.expiresAt then
            OGAddonMsg.retryBuffer[msgId] = nil
        end
    end
end
```

### Latency Warning System

```lua
OGAddonMsg.latencyMonitor = {
    queueExceededAt = nil,  -- Time when queue first exceeded threshold
    lastWarning = 0
}

function CheckLatencyWarnings()
    local queueTime = CalculateQueueTime()  -- Sum of all items in queue
    local config = OGAddonMsg.config
    local now = GetTime()
    
    if queueTime > config.warnQueue then
        -- Queue exceeded threshold
        if not OGAddonMsg.latencyMonitor.queueExceededAt then
            -- First time exceeding
            OGAddonMsg.latencyMonitor.queueExceededAt = now
            DEFAULT_CHAT_FRAME:AddMessage(
                string.format("OGAddonMsg: Network queue at %.1fs", queueTime),
                1, 1, 0
            )
        else
            -- Already exceeded, check duration
            local duration = now - OGAddonMsg.latencyMonitor.queueExceededAt
            if duration > config.warnPeriod then
                -- Sustained high queue
                if now - OGAddonMsg.latencyMonitor.lastWarning > config.warnInterval then
                    DEFAULT_CHAT_FRAME:AddMessage(
                        string.format(
                            "OGAddonMsg: Network queue at %.1fs for %.0fs",
                            queueTime, duration
                        ),
                        1, 0.5, 0
                    )
                    OGAddonMsg.latencyMonitor.lastWarning = now
                end
            end
        end
    else
        -- Queue back to normal
        OGAddonMsg.latencyMonitor.queueExceededAt = nil
    end
end

function CalculateQueueTime()
    local totalBytes = 0
    for _, priority in ipairs({"CRITICAL", "HIGH", "NORMAL", "LOW"}) do
        for i = 1, table.getn(OGAddonMsg.queue[priority]) do
            local item = OGAddonMsg.queue[priority][i]
            totalBytes = totalBytes + string.len(item.msg)
        end
    end
    
    -- Estimate time: bytes / (maxRate * avgBytesPerMsg)
    local avgBytes = 150  -- Conservative estimate
    local timeEstimate = totalBytes / (OGAddonMsg.config.maxRate * avgBytes)
    
    return timeEstimate
end
```

---

## API Reference

### Sending Messages

#### OGAddonMsg.Send(channel, target, prefix, data, options)
Send a message through the addon communication system.

**Parameters:**
- `channel` (string): "RAID", "PARTY", "GUILD", "WHISPER", or nil for auto-detect
- `target` (string): Player name for WHISPER, nil otherwise
- `prefix` (string): Message prefix (identifies your addon)
- `data` (string): Message payload
- `options` (table, optional):
  - `priority` (string): "CRITICAL", "HIGH", "NORMAL" (default), "LOW"
  - `onSuccess` (function): Called when message fully sent
  - `onFailure` (function(reason)): Called on send failure
  - `onProgress` (function(sent, total)): Called for chunked messages

**Returns:**
- `msgId` (string): Unique message ID for tracking

**Example:**
```lua
local msgId = OGAddonMsg.Send("RAID", nil, "OGRH_SYNC", raidData, {
    priority = "HIGH",
    onSuccess = function()
        print("Raid data sent!")
    end,
    onFailure = function(reason)
        print("Send failed: " .. reason)
    end,
    onProgress = function(sent, total)
        print(string.format("Sending: %d/%d chunks", sent, total))
    end
})
```

#### OGAddonMsg.Broadcast(prefix, data, options)
Broadcast to all available channels (RAID > PARTY > GUILD).

**Parameters:** Same as `Send()`, but no channel/target

**Example:**
```lua
OGAddonMsg.Broadcast("OGRH_ANNOUNCE", "Boss dead!", {priority = "CRITICAL"})
```

#### OGAddonMsg.SendTo(playerName, prefix, data, options)
Send direct message to a specific player.

**Parameters:** Same as `Send()`, but playerName instead of channel/target

**Example:**
```lua
OGAddonMsg.SendTo("Healbot", "OGRH_REQUEST", "Need healer assignments")
```

### Receiving Messages

#### OGAddonMsg.RegisterHandler(prefix, callback)
Register a handler for messages with a specific prefix.

**Parameters:**
- `prefix` (string): Message prefix to listen for
- `callback` (function): `function(sender, data, channel)`
  - `sender` (string): Name of sending player
  - `data` (string): Decoded message payload
  - `channel` (string): Channel message came from

**Returns:**
- `handlerId` (number): ID for unregistering

**Example:**
```lua
local handlerId = OGAddonMsg.RegisterHandler("OGRH_SYNC", function(sender, data, channel)
    print("Received sync from " .. sender .. " via " .. channel)
    -- Parse data and update local state
end)
```

#### OGAddonMsg.UnregisterHandler(handlerId)
Remove a previously registered handler.

**Example:**
```lua
OGAddonMsg.UnregisterHandler(handlerId)
```

#### OGAddonMsg.RegisterWildcard(callback)
Register a handler for ALL messages (debugging/logging).

**Example:**
```lua
OGAddonMsg.RegisterWildcard(function(sender, prefix, data, channel)
    print(string.format("[%s] %s -> %s", channel, sender, prefix))
end)
```

### Configuration

#### OGAddonMsg.SetConfig(key, value)
Set a configuration value.

**Keys:**
- `"warnQueue"` (number): Queue time threshold for warnings (default: 5)
- `"warnPeriod"` (number): Sustained duration before periodic warnings (default: 30)
- `"warnInterval"` (number): Interval between periodic warnings (default: 10)
- `"retainTime"` (number): How long to retain sent messages for retry (default: 60)
- `"timeout"` (number): Timeout for incomplete receives (default: 90)
- `"maxRate"` (number): Max messages per second (default: 8)
- `"burstLimit"` (number): Max burst messages (default: 15)
- `"debug"` (boolean): Enable debug logging (default: false)

**Example:**
```lua
OGAddonMsg.SetConfig("warnQueue", 10)  -- Warn at 10s queue
OGAddonMsg.SetConfig("debug", true)    -- Enable debug mode
```

#### OGAddonMsg.GetConfig(key)
Get current configuration value.

### Statistics

#### OGAddonMsg.GetStats()
Get current statistics.

**Returns:** Table with:
- `messagesSent` (number): Total messages sent
- `messagesReceived` (number): Total messages received
- `bytesSent` (number): Total bytes sent
- `bytesReceived` (number): Total bytes received
- `chunksSent` (number): Total chunks sent
- `chunksReceived` (number): Total chunks received
- `messagesReassembled` (number): Multi-chunk messages reassembled
- `retriesRequested` (number): Retry requests sent
- `retriesSent` (number): Retry requests honored
- `failures` (number): Send failures
- `queueDepth` (number): Current queue depth
- `queueDepthMax` (number): Max queue depth seen
- `queueTimeEstimate` (number): Estimated time to clear queue (seconds)

**Example:**
```lua
local stats = OGAddonMsg.GetStats()
print(string.format("Sent: %d msgs, %d bytes", stats.messagesSent, stats.bytesSent))
print(string.format("Queue: %d msgs (%.1fs)", stats.queueDepth, stats.queueTimeEstimate))
```

#### OGAddonMsg.ResetStats()
Reset all statistics to zero.

### Utility Functions

#### OGAddonMsg.GetVersion()
Get library version.

**Returns:** `"1.0.0"` (string)

#### OGAddonMsg.IsLoaded()
Check if library is loaded and ready.

**Returns:** `true` or `false`

#### OGAddonMsg.GetActiveVersion()
Get the active version if multiple copies loaded.

**Returns:** Version string of active instance

---

## Configuration & Commands

### Slash Commands

All commands start with `/ogmsg` or `/ogaddonmsg`:

#### Queue Warning Configuration
```
/ogmsg warnqueue <seconds>     - Set queue warning threshold (default: 5)
/ogmsg warnperiod <seconds>    - Set sustained warning duration (default: 30)
/ogmsg warninterval <seconds>  - Set periodic warning interval (default: 10)
```

#### Retry Configuration
```
/ogmsg retaintime <seconds>    - How long to retain sent packets (default: 60)
/ogmsg timeout <seconds>       - When to give up on incomplete receives (default: 90)
```

#### Throttling Configuration
```
/ogmsg maxrate <msgs/sec>      - Max messages per second (default: 8)
/ogmsg burstlimit <count>      - Max burst messages (default: 15)
```

#### Statistics & Diagnostics
```
/ogmsg stats                   - Show current statistics
/ogmsg stats reset             - Reset statistics
/ogmsg debug on|off            - Enable/disable debug logging
/ogmsg status                  - Show queue status and config
```

#### Examples
```
/ogmsg warnqueue 10            - Warn when queue exceeds 10 seconds
/ogmsg retaintime 120          - Keep sent packets for 2 minutes
/ogmsg maxrate 5               - Reduce to 5 msgs/sec (very conservative)
/ogmsg debug on                - Enable verbose logging
/ogmsg stats                   - View statistics
```

### SavedVariables

```lua
-- Global saved variables (TOC file)
## SavedVariables: OGAddonMsg_Config

-- Default structure
OGAddonMsg_Config = {
    version = "1.0.0",
    warnQueue = 5,
    warnPeriod = 30,
    warnInterval = 10,
    retainTime = 60,
    timeout = 90,
    maxRate = 8,
    burstLimit = 15,
    debug = false
}
```

---

## Development Constraints

**⚠️ ALL DEVELOPMENT MUST FOLLOW THESE RULES:**

This section incorporates the complete WoW 1.12 development constraints from the OG-RaidHelper Design Philosophy. All code must be compatible with Lua 5.0/5.1 and WoW 1.12 API.

### 1. Language Compatibility: Lua 5.0/5.1 (WoW 1.12)

All code MUST be compatible with WoW 1.12's restricted Lua environment. This is **non-negotiable**.

#### Operators & Syntax Constraints

| ❌ NEVER USE | ✅ ALWAYS USE | Notes |
|-------------|----------------|-------|
| `#table` | `table.getn(table)` | Length operator doesn't exist |
| `a % b` | `mod(a, b)` | Modulo operator doesn't exist |
| `string.gmatch()` | `string.gfind()` | Different function name in 1.12 |
| `continue` | Conditional blocks or flags | Continue statement doesn't exist |
| `...` (varargs) | `arg` table | Varargs work differently |
| `ipairs()` where order matters | Manual numeric iteration | Use `for i = 1, table.getn(t) do` |

#### String Functions (Lua 5.0/5.1)
```lua
-- Available functions
string.find(s, pattern)      -- Returns start, end indices
string.gfind(s, pattern)     -- Iterator (NOT gmatch!)
string.gsub(s, pattern, repl) -- Replace
string.sub(s, i, j)          -- Substring
string.format(fmt, ...)      -- Printf-style formatting
string.len(s)                -- Length (or just s:len())
string.lower(s) / string.upper(s)

-- Pattern syntax uses % not \ for escapes
-- %d = digit, %s = whitespace, %a = letter, %w = alphanumeric
-- . = any char, * = 0+, + = 1+, - = 0+ non-greedy, ? = 0-1
```

#### Table Functions
```lua
table.insert(t, value)       -- Append to end
table.insert(t, pos, value)  -- Insert at position
table.remove(t, pos)         -- Remove at position
table.getn(t)                -- Get length (NOT #t)
table.sort(t, comp)          -- Sort in-place
table.concat(t, sep)         -- Join to string

-- Iteration
for i = 1, table.getn(t) do  -- Numeric indices
    local v = t[i]
end
for k, v in pairs(t) do end  -- All keys (unordered)
```

#### Math Functions
```lua
math.floor(x), math.ceil(x), math.abs(x)
math.min(a, b, ...), math.max(a, b, ...)
math.random()                -- 0-1
math.random(n)               -- 1-n
math.random(m, n)            -- m-n
mod(a, b)                    -- NOT math.mod, NOT %
floor(x)                     -- Global shortcut exists
```

---

### 2. WoW 1.12 API Constraints

#### Event Handlers: Implicit Globals Only

**CRITICAL:** Event handlers in 1.12 do NOT use parameters. They use implicit globals.

```lua
-- ❌ WRONG (Modern WoW style - WILL NOT WORK)
frame:SetScript("OnEvent", function(self, event, ...)
    -- This pattern does not exist in 1.12
end)

-- ✅ CORRECT (1.12 style)
frame:SetScript("OnEvent", function()
    -- Use these implicit globals:
    -- this   = the frame
    -- event  = event name (string)
    -- arg1, arg2, arg3... = event arguments
    
    if event == "ADDON_LOADED" and arg1 == "_OGAddonMsg" then
        OGAddonMsg.OnLoad()
    end
end)
```

#### Common Handler Globals Reference

| Handler | Available Globals |
|---------|-------------------|
| OnEvent | `this`, `event`, `arg1`-`arg9` |
| OnUpdate | `this`, `arg1` (elapsed time in seconds) |
| OnClick | `this`, `arg1` (button: "LeftButton"/"RightButton") |

#### Frame & Event Methods

```lua
-- Event registration
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:UnregisterEvent("CHAT_MSG_ADDON")

-- Enable mouse wheel - NO PARAMETER
frame:EnableMouseWheel()  -- Not EnableMouseWheel(true)

-- Common methods
frame:Show() / frame:Hide()
frame:IsVisible() / frame:IsShown()
frame:SetScript("OnUpdate", function() end)
```

#### SendAddonMessage API (1.12)

```lua
-- Syntax
SendAddonMessage(prefix, message, channel, target)

-- Parameters
-- prefix: String up to 16 chars (addon identifier)
-- message: String payload (max ~255 bytes)
-- channel: "RAID", "PARTY", "GUILD", "BATTLEGROUND", or "WHISPER"
-- target: Player name (only for WHISPER)

-- Example
SendAddonMessage("OGAM", "1S4a2fTEST\tHello", "RAID")
```

#### CHAT_MSG_ADDON Event

```lua
-- Register for addon messages
frame:RegisterEvent("CHAT_MSG_ADDON")

-- Event handler uses implicit globals
frame:SetScript("OnEvent", function()
    if event == "CHAT_MSG_ADDON" then
        local prefix = arg1   -- Addon prefix
        local message = arg2  -- Message payload
        local channel = arg3  -- "RAID", "PARTY", etc.
        local sender = arg4   -- Sender player name
        
        OGAddonMsg.OnMessageReceived(prefix, message, channel, sender)
    end
end)
```

---

### 3. Code Style & Conventions

#### Namespace & Structure

```lua
-- All public functions in OGAddonMsg namespace
OGAddonMsg = OGAddonMsg or {}

-- Version checking for multi-copy loading
if not OGAddonMsg.__version or OGAddonMsg.__version < 1.0 then
    OGAddonMsg.__version = 1.0
    -- Initialize this version
else
    -- Older version, do not initialize
    return
end

-- Public functions use PascalCase
function OGAddonMsg.Send(channel, target, prefix, data, options)
    -- Implementation
end

-- Local functions also use PascalCase
local function ChunkMessage(data, maxSize)
    -- Implementation
end

-- Variables use camelCase
local messageQueue = {}
local retryBuffer = {}
```

#### Comments & Documentation

```lua
-- Document complex logic
-- Parse message header: [Version][Type][MsgID][Chunk/Total][Hash][Prefix]\t[Data]
local _, _, version, msgType, msgId, chunk, total = 
    string.find(message, "^(%d)(%a)(%w%w%w%w)(%d%d)/(%d%d)")

-- Document non-obvious behavior
-- Note: SendAddonMessage has ~255 byte limit including prefix
-- We use 200 bytes to be safe after header overhead
local MAX_CHUNK_SIZE = 200
```

#### File Structure

```
_OGAddonMsg/
├── _OGAddonMsg.toc        # Load order, SavedVariables
├── Core.lua               # Namespace, version check, initialization
├── Config.lua             # Configuration management, SavedVariables
├── Chunker.lua            # Message chunking and reassembly
├── Queue.lua              # Priority queue and throttler
├── Retry.lua              # Retry buffer and self-healing
├── Handlers.lua           # Callback registration and dispatch
├── Commands.lua           # Slash commands
├── Documentation/
│   └── OGAddonMsg-Specification.md
└── README.md
```

**TOC Load Order:**
```toc
## Interface: 11200
## Title: OGAddonMsg
## Notes: Unified addon network interface
## Author: OG
## Version: 1.0.0
## SavedVariables: OGAddonMsg_Config

Core.lua
Config.lua
Chunker.lua
Queue.lua
Retry.lua
Handlers.lua
Commands.lua
```

---

### 4. Testing Requirements

All implementations must be tested in WoW 1.12 client (Turtle WoW):

1. **Message Size Testing:**
   - Test chunking with messages from 1 byte to 10KB
   - Verify chunk sizes stay under 255 bytes
   - Test with special characters and unicode

2. **Network Conditions:**
   - Test with high raid traffic (40-man raids)
   - Test during lag spikes
   - Test with multiple addons sending simultaneously

3. **Retry Scenarios:**
   - Zone while receiving chunked message
   - /reload while receiving chunked message
   - Disconnect/reconnect during transmission
   - Sender zones after partial send

4. **Throttling:**
   - Verify no disconnects under max load
   - Test burst limits with rapid sends
   - Test priority ordering (CRITICAL > HIGH > NORMAL > LOW)

5. **Edge Cases:**
   - Empty messages
   - Duplicate messages (network quirk)
   - Out-of-order chunks
   - Hash mismatches
   - Missing chunks
   - Expired retry requests

6. **Integration:**
   - Test with other addons using addon channel
   - Test multi-version loading (multiple copies in AddOns folder)
   - Test SavedVariables persistence
   - Test slash commands

---

## Testing Requirements

### Unit Tests (Manual)

Due to WoW 1.12 limitations, create manual test scripts:

```lua
-- Test 1: Single message send/receive
/script OGAddonMsg.Send("RAID", nil, "TEST", "Hello World", {onSuccess = function() print("OK") end})

-- Test 2: Large message (force chunking)
/script local data = string.rep("A", 1000); OGAddonMsg.Send("RAID", nil, "TEST", data, {onProgress = function(s,t) print(s.."/"..t) end})

-- Test 3: Priority ordering
/script OGAddonMsg.Send("RAID", nil, "LOW", "L", {priority="LOW"})
/script OGAddonMsg.Send("RAID", nil, "CRIT", "C", {priority="CRITICAL"})
/script OGAddonMsg.Send("RAID", nil, "NORM", "N", {priority="NORMAL"})
-- Verify order: CRIT, NORM, LOW

-- Test 4: Stats
/script local s = OGAddonMsg.GetStats(); print("Sent: "..s.messagesSent..", Queue: "..s.queueDepth)

-- Test 5: Retry (requires helper)
-- Sender: Send large message, then /reload mid-send
-- Receiver: Should auto-request retry on zone-in
```

### Integration Tests

1. **Multi-addon scenario:**
   - Install OG-RaidHelper + _OGAddonMsg
   - Verify OGRH uses OGAddonMsg for comms
   - Send raid sync data
   - Verify no conflicts

2. **Version precedence:**
   - Place two copies: `_OGAddonMsg/` (v1.0) and `OG-RaidHelper\_OGAddonMsg/` (v0.9)
   - Verify v1.0 loads
   - Check `/ogmsg status` shows correct version

3. **Load testing:**
   - 40-man raid, all using addon
   - Boss pull with high traffic
   - Monitor queue times
   - Verify no disconnects

### Performance Benchmarks

Target performance metrics:
- **Chunking:** <1ms for 10KB message
- **Queue processing:** <0.1ms per frame
- **Reassembly:** <2ms for 100-chunk message
- **Hash computation:** <1ms for 10KB
- **Memory usage:** <500KB for normal operation

---

## Implementation Phases

### Phase 1: Core Communication (MVP)
- ✅ Namespace and version loading
- ✅ Basic Send/Receive
- ✅ CHAT_MSG_ADDON event handling
- ✅ Simple chunking (no retry)
- ✅ Basic queue
- ✅ Slash commands for testing

### Phase 2: Reliability
- ✅ Retry buffer
- ✅ Reassembly buffer with timeout
- ✅ Self-healing on zone/reload
- ✅ Hash verification
- ✅ Duplicate detection

### Phase 3: Performance
- ✅ Priority queue
- ✅ Throttling engine
- ✅ Latency monitoring/warnings
- ✅ Statistics tracking

### Phase 4: Polish
- ✅ Full slash command suite
- ✅ SavedVariables persistence
- ✅ Debug mode
- ✅ Documentation
- ✅ Testing

---

## FAQ

### Q: Why not use ChatThrottleLib directly?
**A:** ChatThrottleLib is excellent for throttling but doesn't handle:
- Multi-chunk reassembly across reloads
- Automatic retry requests
- Latency warnings
- High-level async callbacks

OGAddonMsg can potentially use CTL internally for throttling while adding these features.

### Q: What's the actual message limit in Turtle WoW?
**A:** Base limit is ~255 bytes per SendAddonMessage call. We use 200 bytes per chunk to account for:
- Prefix (up to 16 bytes)
- Header metadata (~20-30 bytes)
- Safety margin

### Q: How does version precedence work?
**A:** First loaded copy checks `OGAddonMsg.__version`. If unset or older, it initializes. If newer version already loaded, it returns early and does nothing.

### Q: Can I use this for non-addon channels (RAID chat, etc.)?
**A:** Yes, but it's designed for CHAT_MSG_ADDON. Using visible channels will spam chat and annoy users. Stick to addon channel.

### Q: What happens if sender logs off during chunked send?
**A:** Receiver will timeout after 90s (configurable) and discard incomplete message. No retry possible if sender is offline.

### Q: How do I debug message flow?
**A:**
```lua
/ogmsg debug on
-- Then send messages, watch chat for detailed logs
/ogmsg debug off
```

---

## Glossary

- **Chunk:** A segment of a large message split to fit in one SendAddonMessage call
- **MsgID:** Unique identifier for a message (used to group chunks)
- **Priority:** CRITICAL/HIGH/NORMAL/LOW - determines queue order
- **Reassembly:** Process of combining chunks back into original message
- **Retry:** Re-sending chunks that were lost or incomplete
- **Throttling:** Rate-limiting sends to prevent disconnects
- **Prefix:** Short string identifying addon (e.g., "OGRH", "OGAM")
- **Queue Depth:** Number of messages waiting to send
- **Queue Time:** Estimated seconds to clear current queue
- **Latency:** Delay between send and receive
- **Hash:** CRC checksum to verify message integrity

---

## Version History

- **v1.0.0** (January 2025): Initial specification

---

**END OF SPECIFICATION**

This document defines the complete requirements and architecture for `_OGAddonMsg`. All development must conform to this specification and the WoW 1.12 development constraints.
