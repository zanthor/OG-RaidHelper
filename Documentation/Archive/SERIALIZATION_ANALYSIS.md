# Serialization/Deserialization Analysis & Best Practice

**Date:** January 21, 2026  
**Status:** CRITICAL - Constant Source of Bugs

---

## Current State: Inconsistent & Error-Prone

### Current Architecture

**MessageRouter Flow:**
1. **Sender**: Must call `OGRH.Serialize(table)` → produces string
2. **MessageRouter.Send/Broadcast**: Validates data is string, sends it
3. **MessageRouter.OnMessageReceived**: Auto-deserializes string → produces table
4. **Handler**: Receives table (already deserialized)

**Code Evidence:**

```lua
-- MessageRouter.Send (lines 60-77) - REQUIRES STRING
function OGRH.MessageRouter.Send(messageType, data, options)
    -- VALIDATION: Ensure data is a string (common mistake: passing tables)
    if type(data) ~= "string" then
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff0000[RH-MessageRouter]|r ERROR: data must be a STRING, got %s. Use OGRH.Serialize() first!", type(data)))
        return nil
    end
    -- ... sends string ...
end

-- MessageRouter.OnMessageReceived (lines 206-217) - AUTO DESERIALIZES
function OGRH.MessageRouter.OnMessageReceived(sender, messageType, data, channel)
    -- Deserialize data if it's a string (handles both serialized tables and raw strings)
    local deserializedData = data
    if type(data) == "string" and OGRH.Deserialize then
        local success, result = pcall(OGRH.Deserialize, data)
        if success and result then
            deserializedData = result
        end
    end
    
    -- Call the handler with deserialized data
    handler(sender, deserializedData, channel)
end
```

### Problems Identified Today

**All from MessageRouter handlers calling Deserialize on already-deserialized data:**

1. **ASSIGN.DELTA_BATCH Handler** - Line 449 (FIXED)
   - ❌ WAS: `local deltaData = OGRH.Deserialize(data)`
   - ✅ NOW: `local deltaData = data`

2. **STATE.CHANGE_ENCOUNTER Handler** - Line 410 (FIXED)
   - ❌ WAS: `local encounterData = OGRH.Deserialize(data)`
   - ✅ NOW: `local encounterData = data`

3. **STATE.CHANGE_LEAD Handler** - Line 639 (CORRECT)
   - ✅ Correctly uses `data.adminName` directly

**Still Inconsistent - Mix of patterns:**

4. **SYNC.REQUEST_PARTIAL Handler** - Line 438 (WRONG)
   - ❌ `local requestData = OGRH.Deserialize(data)` ← Should be `data` directly

5. **ASSIGN.DELTA_PLAYER Handler** - Line 557 (WRONG)
   - ❌ `local changeData = OGRH.Deserialize(data)` ← Should be `data` directly

6. **ASSIGN.DELTA_ROLE Handler** - Line 568 (WRONG)
   - ❌ `local changeData = OGRH.Deserialize(data)` ← Should be `data` directly

7. **ASSIGN.DELTA_GROUP Handler** - Line 586 (WRONG)
   - ❌ `local changeData = OGRH.Deserialize(data)` ← Should be `data` directly

8. **ADMIN.POLL_RESPONSE Handler** - Line 626 (CORRECT)
   - ✅ Uses `data.version` and `data.checksum` directly

---

## Why This Keeps Happening

**Cognitive Load Issues:**

1. **Asymmetric API**: Senders serialize, receivers get tables (confusing)
2. **No Visual Cue**: Handler signature `function(sender, data, channel)` doesn't indicate type
3. **Memory Burden**: Developers must remember "MessageRouter auto-deserializes"
4. **Inconsistent Examples**: Old code has both patterns, copy-paste spreads bugs
5. **Error is Silent**: Deserializing a table usually returns nil, code continues

**Error Message From User:**
```
Interface\AddOns\OG-RaidHelper\OGRH_Core.lua:4410: attempt to concatenate local 'str' (a table value)
```

This happens when a handler passes a table to `OGRH.Deserialize(data)` which expects a string.

---

## Proposed Solution: Auto-Serialize in _OGAddonMsg Library

### New Architecture (BEST SOLUTION - Library Level)

**Push serialization down to _OGAddonMsg, not OGRH.MessageRouter**

The library should handle wire format, not every consumer.

**_OGAddonMsg becomes the serialization boundary:**

1. **Sender**: Pass table directly → `OGAddonMsg.Send(channel, target, prefix, {key = value})`
2. **OGAddonMsg.Send**: Auto-serializes table → chunks string → sends
3. **OGAddonMsg.DispatchToHandlers**: Reassembles → auto-deserializes → passes table
4. **Handler**: Receives table (no serialization awareness needed)

**Benefits:**

✅ **Single Responsibility**: Library owns wire format (correct architectural boundary)  
✅ **Symmetric API**: Tables in, tables out  
✅ **Less Error-Prone**: Impossible to forget serialization  
✅ **Backward Compatible**: Can still accept strings (for raw text messages)  
✅ **Helps ALL Addons**: Not just OG-RaidHelper, but EVERY addon using _OGAddonMsg  
✅ **Pit of Success**: Hard to use wrong, easy to use right  
✅ **Industry Stand in _OGAddonMsg

**File: `_OGAddonMsg/API.lua`** (lines 34-60)

```lua
-- BEFORE: Only accepts strings
function OGAddonMsg.Send(channel, target, prefix, data, options)
    if not prefix or not data then
        DEFAULT_CHAT_FRAME:AddMessage("OGAddonMsg: Missing prefix or data", 1, 0, 0)
        return nil
    end
    
    -- Chunk the message (expects string)
    local msgId, chunks, isMultiChunk = OGAddonMsg.ChunkMessage(prefix, data)
    -- ...
end

-- AFTER: Accepts both tables and strings
function OGAddonMsg.Send(channel, target, prefix, data, options)
    if not prefix or not data then
        DEFAULT_CHAT_FRAME:AddMessage("OGAddonMsg: Missing prefix or data", 1, 0, 0)
        return nil
    end
    
    -- Auto-serialize tables (library owns wire format)
    local serializedData = data
    local dataType = type(data)
    
    if dataType == "table" then
        -- Use AceSerializer or custom serializer
        serializedData = OGAddonMsg.Serialize(data)
        if not serializedData then
            DEFAULT_CHAT_FRAME:AddMessage("OGAddonMsg: Failed to serialize table", 1, 0, 0)
            if options.onFailure then
                options.onFailure("Serialization failed")
            end
            return nil
        end
    elseif dataType ~= "string" then
        DEFAULT_CHAT_FRAME:AddMessage(
            string.format("OGAddonMsg: data must be table or string, got %s", dataType), 
            1, 0, 0
        )
        if options.onFailure then
            options.onFailure("Invalid data type")
        end
        return nil
    end
    
    -- Store original type for receiver (prepend type flag)
    local wireData = string.format("%s:%s", dataType == "table" and "T" or "S", serializedData)
    
    -- Chunk the message (now always string)
    local msgId, chunks, isMultiChunk = OGAddonMsg.ChunkMessage(prefix, wireData)
    -- ... rest un_OGAddonMsg Library**
- Modify `API.lua`: Accept tables, auto-serialize before chunking
- Modify `Handlers.lua`: Auto-deserialize tables before dispatching
- Create `Serialization.lua`: Serialize/Deserialize functions
- Add to TOC: Load `Serialization.lua` before `API.lua`

**Phase 2: Update OGRH.MessageRouter (Remove Double Work)**
- REMOVE auto-deserialize from `OnMessageReceived` (library does it now)
- REMOVE string validation from `Send/Broadcast` (library handles it)
- Simplify to just permission checks + pass-through to OGAddonMsg

**Phase 3: Update All OG-RaidHelper Senders (18 locations)**

Current (manual serialization):
```lua
-- OLD: Manual serialization
local encounterData = OGRH.Serialize({raidName = raidName, encounterName = encounterName})
OGRH.MessageRouter.Broadcast(OGRH.MessageTypes.STATE.CHANGE_ENCOUNTER, encounterData, {...})

-- NEW: Pass table directly
OGRH.MessageRouter.Broadcast(OGRH.MessageTypes.STATE.CHANGE_ENCOUNTER, {
    raidName = raidName,
    encounterName = encounterName
}, {...})
```

**Phase 4: Update All OG-RaidHelper Handlers (5 locations)**

Current (manual deserialization - causes bugs):
```lua
-- OLD: Manual deserialization (double-deserialize bug!)
local requestData = OGRH.Deserialize(data)

-- NEW: Data already deserialized by OGAddonMsg
local requestData = data
```

**Phase 5: Benefit ALL Addons**
- Other addons using _OGAddonMsg immediately benefit
- No more serialization bugs across entire addon ecosystem
- Consistent behavior for everyone
    end
    
    -- Call handlers with original type (table or string)
    if OGAddonMsg.handlers.byPrefix[prefix] then
        for handlerId, callback in pairs(OGAddonMsg.handlers.byPrefix[prefix]) do
            local success, err = pcall(callback, sender, actualData, channel)
            -- ...
        end
    end
    -- ... wildcard handlers unchanged ...
end
```

**File: `_OGAddonMsg/Serialization.lua`** (NEW FILE)

```lua
--[[
    OGAddonMsg - Serialization
    Simple Lua table serialization for WoW 1.12
    (Cannot use AceSerializer in vanilla - not available)
]]

-- Serialize a Lua table to string
function OGAddonMsg.Serialize(tbl)
    if type(tbl) ~= "table" then
        return tostring(tbl)
    end
    
    local result = "{"
    local first = true
    
    for k, v in pairs(tbl) do
        if not first then
            result = result .. ","
        end
        first = false
        
        -- Serialize key
        if type(k) == "number" then
            result = result .. "[" .. k .. "]="
        else
            result = result .. k .. "="
        end
        
        -- Serialize value
        if type(v) == "table" then
            result = result .. OGAddonMsg.Serialize(v)
        elseif type(v) == "string" then
            result = result .. string.format("%q", v)
        else
            result = result .. tostring(v)
        end
    end
    
    result = result .. "}"
    return result
end

-- Deserialize string back to Lua table
function OGAddonMsg.Deserialize(str)
    if type(str) ~= "string" then
        return nil
    end
    
    -- Use loadstring to evaluate serialized table
    local func, err = loadstring("return " .. str)
    if not func then
        DEFAULT_CHAT_FRAME:AddMessage(
            string.format("OGAddonMsg: Deserialize error: %s", tostring(err)),
            1, 0, 0
        )
        return nil
    end
    
    local success, result = pcall(func)
    if not success then
        DEFAULT_CHAT_FRAME:AddMessage(
            string.format("OGAddonMsg: Deserialize execution error: %s", tostring(result)),
            1, 0, 0
        )
        return nil
    end
    
    return result
end
```
```

**MessageRouter.OnMessageReceived remains unchanged** (already auto-deserializes)

### Migration Path

**Phase 1: Update MessageRouter.Send/Broadcast (This Change)**
- Accept both tables and strings
- Auto-serialize tables
- Keep string validation as fallback

**Phase 2: Update All Senders (Remove Manual OGRH.Serialize calls)**

Current (18 locations to update):
```lua
-- OLD: Manual serialization
local encounterData = OGRH.Serialize({raidName = raidName, encounterName = encounterName})
OGRH.MessageRouter.Broadcast(OGRH.MessageTypes.STATE.CHANGE_ENCOUNTER, encounterData, {...})

-- NEW: Pass table directly
OGRH.MessageRouter.Broadcast(OGRH.MessageTypes.STATE.CHANGE_ENCOUNTER, {
    raidName = raidName,
    encounterName = encounterName
}, {...})
```

**Phase 3: Update All Handlers (Remove Manual OGRH.Deserialize calls)**

Current (5 remaining locations in MessageRouter.lua):
```lua
-- OLD: Manual deserialization (causes double-deserialize bug)
local requestData = OGRH.Deserialize(data)

-- NEW: Data already deserialized by MessageRouter
local requestData = data
```
Why Library Level is Superior

**Architectural Principle: "Don't Trust Callers"**

If we only fix OGRH.MessageRouter:
- ❌ Only helps OG-RaidHelper
- ❌ Other addons have same problem
- ❌ If anyone calls OGAddonMsg directly, bug returns

If we fix _OGAddonMsg library:
- ✅ Helps EVERY addon using the library
- ✅ Impossible to bypass (all messages go through library)
- ✅ Future-proof (new addons automatically correct)
- ✅ Centralized fix (one place, not scattered across addons)

**Real-World Analogy:**

Bad: "Every caller of socket.send() must remember to encrypt data"  
Good: "socket.send() encrypts automatically, decrypt on receive"

Bad: "Every HTTP client must remember to encode JSON"  
Good: "HTTP library accepts objects, encodes automatically"

**This is Standard Practice:**
- gRPC: You send objects, library serializes to protobuf
- REST APIs: You send JSON, library handles marshalling
- Database ORMs: You work with objects, ORM handles SQL serialization
- **Network libraries ALWAYS own wire format**

---

## Recommendation: AUTO-SERIALIZE IN _OGADDONMSG

**Implement auto-serialization in _OGAddonMsg library (not OGRH wrapper)**

**Rationale:**
1. **Correct Boundary**: Library owns wire format, not consumers
2. **Ecosystem Benefit**: ALL addons benefit, not just OG-RaidHelper
3. **Pit of Success**: Makes correct usage the default path
4. **Eliminates Root Cause**: Fixes problem at source, not symptom
5. **Industry Standard**: Network/RPC libraries handle marshalling

**Estimated Work:**
- _OGAddonMsg changes: 3 files, ~150 lines (60 min)
- OGRH.MessageRouter simplification: Remove double-work (20 min)
- 18 sender updates: Remove manual Serialize (30 min)
- 5 handler updates: Remove manual Deserialize (10 min)
- Testing: 30 min
- **Total: ~2.5 hours to eliminate serialization bugs FOREVER across ALL addons**

**Risk Assessment:**
- MEDIUM: Library change affects all consumers (test carefully)
- LOW: Backward compatible (still accepts strings for raw messages)
- HIGH REWARD: Eliminates bug class for entire addon ecosysteme (10 min)
- Testing: 20 min
- **Total: ~70 minutes to eliminate serialization bugs forever**

**Risk Assessment:**
- LOW: Changes are mechanical and easily verified
- LOW: Can be tested incrementally (backward compatible)
- HIGH REWARD: Eliminates recurring bug class

---

## F_OGAddonMsg Library Changes (3 files)

1. **`_OGAddonMsg/Serialization.lua`** (NEW FILE)
   - Create `OGAddonMsg.Serialize(tbl)` function
   - Create `OGAddonMsg.Deserialize(str)` function
   - ~80 lines total

2. **`_OGAddonMsg/API.lua`** (MODIFY)
   - Line 34-60: Update `OGAddonMsg.Send()` to accept tables
   - Auto-serialize before chunking
   - Prepend type flag ("T:" or "S:") to wire data
   - ~30 lines changed

3. **`_OGAddonMsg/Handlers.lua`** (MODIFY)
   - Line 86-110: Update `OGAddonMsg.DispatchToHandlers()`
   - Check type flag, auto-deserialize if table
   - ~25 lines changed

4. **`_OGAddonMsg/_OGAddonMsg.toc`** (MODIFY)
   - Add `Serialization.lua` before `API.lua`
   - 1 line added

### OGRH Changes (Simplification)

5. **`OGRH_MessageRouter.lua`** (SIMPLIFY)
   - Line 60-77: Remove string validation (library handles it)
   - Line 206-217: Remove auto-deserialize (library does it now)
   - Net result: ~30 lines REMOVED (simpler code!)

### OG-RaidHelper Handler Fixes (5 locations in MessageRouter.lua)
- Line 438: `SYNC.REQUEST_PARTIAL` handler (remove Deserialize call)
- Line 557: `ASSIGN.DELTA_PLAYER` handler (remove Deserialize call)
- Line 568: `ASSIGN.DELTA_ROLE` handler (remove Deserialize call)
- Line 586: `ASSIGN.DELTA_GROUP` handler (remove Deserialize call)
- ~5 lines changed total

### OG-RaidHelper Sender Updates (18 locations across 8 files)

1. **OGRH_EncounterMgmt.lua** (6 calls)
   - Remove lines: 4184, 4195, 4245, 4256, 4516, 4527
   - Pass table directly to Broadcast

2. **OGRH_Core.lua** (4 calls)
   - Remove lines: 3081, 3092, 4016, 4084

3. **OGRH_BigWigs.lua** (2 calls)
   - Remove lines: 99, 110

4. **OGRH_Permissions.lua** (2 calls)
   - Remove lines: 188, 230

5. **OGRH_RaidLead.lua** (1 call)
   - Remove line: 140

6. **OGRH_SyncDelta.lua** (1 call)
   - Remove line: 242

7. **OGRH_Sync_v2.lua** (1 call)
   - Remove line: 257

8. **OGRH_DataManagement.lua** (1 call)
   - Remove line: 120

---

## Decision: Implement in _OGAddonMsg Library

**This is the correct architectural solution.**

The library owns the wire format. Consumers work with data structures.

Proceed with implementation

**User Decision Needed:** Which option do you prefer?
