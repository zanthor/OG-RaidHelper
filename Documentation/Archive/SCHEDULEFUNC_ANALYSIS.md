# OGRH.ScheduleFunc() - Function Analysis & Refactoring Plan

**Status:** Analysis Complete  
**Date:** January 21, 2026  
**Current Location:** OGRH_RaidLead.lua (to be OGRH_AdminSelection.lua)  
**Lines:** 746-756

---

## Function Overview

### Current Implementation

```lua
function OGRH.ScheduleFunc(func, delay)
  local frame = CreateFrame("Frame")
  local elapsed = 0
  frame:SetScript("OnUpdate", function()
    elapsed = elapsed + arg1
    if elapsed >= delay then
      frame:SetScript("OnUpdate", nil)
      func()
    end
  end)
end
```

### Purpose

Simple timer utility that executes a function after a specified delay (in seconds). Uses WoW's OnUpdate frame mechanism to track elapsed time.

### Signature

- **Parameters:**
  - `func` (function) - Callback function to execute after delay
  - `delay` (number) - Delay in seconds (fractional values supported)
- **Returns:** Nothing
- **Side Effects:** Creates a temporary frame that self-destructs after execution

---

## Usage Analysis

### Total Call Sites: 16 across 8 files

| File | Line | Purpose | Delay | Context |
|------|------|---------|-------|---------|
| **OGRH_RaidLead.lua** | 174 | Close poll window | 5s | Admin selection poll timeout |
| **OGRH_RaidLead.lua** | 794 | Clear admin on raid leave | varies | Raid roster event handler |
| **OGRH_RaidLead.lua** | 809 | Query admin on raid join | 1s | Auto-discovery after join |
| **OGRH_Core.lua** | 483 | Hide sync panel | 3s | UI auto-hide after sync complete |
| **OGRH_DataManagement.lua** | 229 | Refresh push list | 2s | Collect checksum responses |
| **OGRH_MessageRouter.lua** | 601 | Randomized poll response | 0-2s | Prevent 40-man response spam |
| **OGRH_SyncDelta.lua** | 201 | Flush batched changes | 2s | Delta sync batch window |
| **OGRH_Sync.lua** | 1389 | Hide sync status panel | 3s | UI auto-hide |
| **OGRH_Sync.lua** | 1859 | Update sync timer display | 1s | Periodic UI refresh |
| **OGRH_Sync.lua** | 1999 | Send next chunk | 0.1s | Throttled chunk transmission |
| **OGRH_Sync.lua** | 2029 | Clear chunk state | 1s | Cleanup after sync |
| **OGRH_Sync.lua** | 2135 | Check receive timeout | 1s | Timeout detection |
| **OGRH_Sync.lua** | 2280 | Trigger checksum check | 5s | Integrity verification |
| **OGRH_Sync_v2.lua** | 185 | Hide sync progress bar | 2s | UI auto-hide |
| **OGRH_Sync_v2.lua** | 417 | Send next chunk (v2) | 0.1s | Throttled transmission |
| **OGRH_Sync_v2.lua** | (1 more) | Various sync operations | varies | Phase 2 sync system |

### Usage Patterns

1. **UI Auto-Hide** (5 uses): Hide panels/frames after displaying status
   - Typical delay: 2-5 seconds
   - Files: Core, Sync, Sync_v2, DataManagement

2. **Response Deduplication** (1 use): Randomized delays to prevent spam
   - Typical delay: 0-2 seconds random
   - File: MessageRouter (poll responses)

3. **Batch Windowing** (1 use): Collect changes before flush
   - Typical delay: 2 seconds
   - File: SyncDelta (assignment batching)

4. **Throttled Operations** (3 uses): Rate-limit network operations
   - Typical delay: 0.1 seconds
   - Files: Sync, Sync_v2 (chunk transmission)

5. **Event Debouncing** (2 uses): Delay actions after events
   - Typical delay: 1 second
   - File: RaidLead (raid roster changes)

6. **Periodic Tasks** (4 uses): Recurring checks/updates
   - Typical delay: 1-5 seconds
   - Files: Sync (timeouts, UI updates, integrity checks)

---

## Architectural Issues

### Problem 1: Wrong File Location

**Current:** Lives in OGRH_RaidLead.lua (to be OGRH_AdminSelection.lua)  
**Issue:** Generic utility function in file-specific module  
**Impact:** 10 out of 16 call sites are in OTHER files (62.5% external usage)

### Problem 2: No Cancellation Mechanism

**Issue:** Once scheduled, cannot be cancelled  
**Example:** SyncDelta stores `flushTimer` but cannot cancel it if immediate flush needed  
**Workaround:** Code checks `if not timer then` before scheduling

```lua
-- Current workaround in SyncDelta.lua (line 200)
if not OGRH.SyncDelta.State.flushTimer then
    OGRH.SyncDelta.State.flushTimer = OGRH.ScheduleFunc(function()
        OGRH.SyncDelta.State.flushTimer = nil  -- Must manually clear
        OGRH.SyncDelta.FlushChangeBatch()
    end, delay)
end
```

### Problem 3: No Return Value

**Issue:** Cannot track or cancel scheduled timers  
**Example:** Cannot cancel "hide panel in 3 seconds" if user manually closes it  
**Result:** Dead frames continue OnUpdate until timer expires

### Problem 4: Memory Leak Potential

**Issue:** Each call creates orphaned frame that persists until execution  
**Example:** Rapid repeated calls create multiple frames in memory  
**Scale:** Low risk (small function, self-cleaning), but not optimal

---

## Recommended Solution

### Option A: Move to Utility Module (RECOMMENDED)

**Create:** `OGRH_Utilities.lua` or `OGRH_Timer.lua`  
**Load Order:** Early (before Core, MessageRouter, Sync, etc.)  
**TOC Entry:** Place after Versioning, before Core

**Benefits:**
- ✅ Generic utilities in dedicated location
- ✅ Can add other helpers (debounce, throttle, etc.)
- ✅ Clear dependency structure

**Implementation:**
```lua
-- OGRH_Utilities.lua
OGRH = OGRH or {}
OGRH.Utilities = {}

-- Simple delayed function execution
function OGRH.ScheduleFunc(func, delay)
  local frame = CreateFrame("Frame")
  local elapsed = 0
  frame:SetScript("OnUpdate", function()
    elapsed = elapsed + arg1
    if elapsed >= delay then
      frame:SetScript("OnUpdate", nil)
      func()
    end
  end)
  return frame  -- Allow cancellation if needed
end

-- Cancel a scheduled function (optional enhancement)
function OGRH.CancelScheduledFunc(frame)
  if frame then
    frame:SetScript("OnUpdate", nil)
  end
end
```

### Option B: Enhanced Timer System (FUTURE)

**If we need more features later:**

```lua
OGRH.Timer = {}
OGRH.Timer.ActiveTimers = {}

function OGRH.Timer.Schedule(func, delay, repeating)
  local frame = CreateFrame("Frame")
  local elapsed = 0
  local timerId = tostring(frame)
  
  frame:SetScript("OnUpdate", function()
    elapsed = elapsed + arg1
    if elapsed >= delay then
      if not repeating then
        frame:SetScript("OnUpdate", nil)
        OGRH.Timer.ActiveTimers[timerId] = nil
      else
        elapsed = 0  -- Reset for repeat
      end
      func()
    end
  end)
  
  OGRH.Timer.ActiveTimers[timerId] = frame
  return timerId
end

function OGRH.Timer.Cancel(timerId)
  local frame = OGRH.Timer.ActiveTimers[timerId]
  if frame then
    frame:SetScript("OnUpdate", nil)
    OGRH.Timer.ActiveTimers[timerId] = nil
  end
end
```

**Benefits:**
- ✅ Cancellable timers
- ✅ Repeating timers
- ✅ Timer tracking
- ⚠️ More complex (may be overkill)

---

## Migration Plan

### Phase 1: Move to Utilities Module

**Step 1: Create OGRH_Utilities.lua**
```lua
-- OGRH_Utilities.lua
-- Generic utility functions for OG-RaidHelper

OGRH = OGRH or {}

-- Schedule a function to execute after a delay
function OGRH.ScheduleFunc(func, delay)
  local frame = CreateFrame("Frame")
  local elapsed = 0
  frame:SetScript("OnUpdate", function()
    elapsed = elapsed + arg1
    if elapsed >= delay then
      frame:SetScript("OnUpdate", nil)
      func()
    end
  end)
  return frame  -- Allow optional cancellation
end

-- Cancel a scheduled function (optional)
function OGRH.CancelScheduledFunc(frame)
  if frame and frame.SetScript then
    frame:SetScript("OnUpdate", nil)
  end
end

DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[OGRH-Utilities]|r Loaded")
```

**Step 2: Update TOC Load Order**
```
## Interface: 11200
## Title: OG-RaidHelper
...
# Phase 1 - Infrastructure
_OGAddonMsg\OGAddonMsg.lua
OGRH_Versioning.lua
OGRH_Utilities.lua          # <-- NEW: Add after Versioning
OGRH_Permissions.lua
OGRH_MessageTypes.lua
OGRH_MessageRouter.lua
...
```

**Step 3: Remove from OGRH_AdminSelection.lua**
- Delete lines 746-756 (ScheduleFunc implementation)
- All call sites continue to work (global OGRH.ScheduleFunc)

**Step 4: Test**
- ✅ All 16 call sites still work
- ✅ No load order issues
- ✅ Timer behavior unchanged

### Phase 2: Optional Enhancements (FUTURE)

**Only if needed:**
- Add `CancelScheduledFunc()` support
- Update SyncDelta to cancel flush timer on immediate flush
- Add repeating timer support if recurring tasks emerge

---

## Testing Plan

### Test 1: Basic Timer Execution
```lua
/run OGRH.ScheduleFunc(function() DEFAULT_CHAT_FRAME:AddMessage("Timer fired!") end, 2)
-- Wait 2 seconds, should see "Timer fired!"
```

### Test 2: Multiple Timers
```lua
/run OGRH.ScheduleFunc(function() DEFAULT_CHAT_FRAME:AddMessage("Timer 1") end, 1)
/run OGRH.ScheduleFunc(function() DEFAULT_CHAT_FRAME:AddMessage("Timer 2") end, 2)
/run OGRH.ScheduleFunc(function() DEFAULT_CHAT_FRAME:AddMessage("Timer 3") end, 3)
-- Should see all 3 messages in order
```

### Test 3: Admin Selection Poll Timeout
```lua
-- Join raid, poll for admin selection
/ogrh poll
-- Poll window should auto-close after 5 seconds
```

### Test 4: Delta Sync Batching
```lua
-- Make rapid assignment changes
-- Changes should batch and flush after 2 seconds
```

### Test 5: Sync Panel Auto-Hide
```lua
-- Trigger structure sync
-- Panel should auto-hide after 3 seconds
```

### Test 6: Load Order Validation
```lua
-- After moving to Utilities.lua
/reload
-- Check chat for load messages, ensure Utilities loads before Core
/dump OGRH.ScheduleFunc  -- Should not be nil
```

---

## Call Site Migration (NO CHANGES NEEDED)

Since `OGRH.ScheduleFunc()` is a global function, all 16 call sites continue to work after moving to Utilities.lua. No code changes required in calling files.

**Affected Files (no changes):**
- ✅ OGRH_AdminSelection.lua (3 internal uses)
- ✅ OGRH_Core.lua
- ✅ OGRH_DataManagement.lua
- ✅ OGRH_MessageRouter.lua
- ✅ OGRH_SyncDelta.lua
- ✅ OGRH_Sync.lua
- ✅ OGRH_Sync_v2.lua

---

## Implementation Checklist

- [ ] Create `OGRH_Utilities.lua` with ScheduleFunc
- [ ] Add Utilities.lua to TOC after Versioning
- [ ] Test basic timer execution
- [ ] Test all 16 call sites
- [ ] Remove ScheduleFunc from OGRH_AdminSelection.lua (lines 746-756)
- [ ] Update Phase 3C migration document
- [ ] Verify load order (Utilities before Core)
- [ ] Test with /reload
- [ ] Confirm no Lua errors

---

## Success Criteria

**Migration complete when:**
1. ✅ `OGRH_Utilities.lua` created and loaded
2. ✅ TOC updated with correct load order
3. ✅ All 16 call sites tested and working
4. ✅ ScheduleFunc removed from AdminSelection.lua
5. ✅ No Lua errors on /reload
6. ✅ Admin poll timeout works (5s)
7. ✅ Delta sync batching works (2s)
8. ✅ Sync panel auto-hide works (3s)

---

## Future Enhancements (Optional)

### Potential Additions to OGRH_Utilities.lua

1. **Debounce Function**
```lua
function OGRH.Debounce(func, delay)
  local timer
  return function(...)
    if timer then OGRH.CancelScheduledFunc(timer) end
    timer = OGRH.ScheduleFunc(func, delay)
  end
end
```

2. **Throttle Function**
```lua
function OGRH.Throttle(func, cooldown)
  local lastRun = 0
  return function(...)
    local now = GetTime()
    if now - lastRun >= cooldown then
      lastRun = now
      func(...)
    end
  end
end
```

3. **Repeating Timer**
```lua
function OGRH.RepeatFunc(func, interval)
  local frame = CreateFrame("Frame")
  local elapsed = 0
  frame:SetScript("OnUpdate", function()
    elapsed = elapsed + arg1
    if elapsed >= interval then
      elapsed = 0
      func()
    end
  end)
  return frame
end
```

**Note:** Only add if clear use cases emerge. Keep utilities minimal and focused.

---

## Notes

**Design Philosophy Alignment:**
- ✅ WoW 1.12 compatible (OnUpdate frame pattern)
- ✅ Simple, focused utility
- ✅ Proper module organization
- ✅ Clear dependencies (Utilities loaded early)
- ✅ No breaking changes to existing code

**Related Documents:**
- `PHASE3C_RAIDLEAD_MIGRATION.md` - AdminSelection.lua migration
- `OGAddonMsg Migration - Design Document.md` - Overall migration strategy

**Current Status:**
- Function works correctly in current location
- Migration is **non-critical** (nice-to-have cleanup)
- Can be done independently of Phase 3C migration
- Zero risk (pure code move, no behavior change)
