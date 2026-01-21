# Phase 3B: OGRH_Core.lua SendAddonMessage Audit

**Date:** January 2026  
**Status:** Audit Complete - Migration Pending

---

## Overview

Comprehensive audit of all `SendAddonMessage` calls in OGRH_Core.lua to prepare for migration to OGAddonMsg/MessageRouter system.

**Total Direct Calls: 18** (excluding 2 comments/function definitions)

---

## Detailed Audit

### 1. Ready Check Request (Line 1319) ✅ COMPLETED
```lua
SendAddonMessage(OGRH.ADDON_PREFIX, "READYCHECK_REQUEST", "RAID")
```
- **Context**: `OGRH.StartReadyCheck()` - Raid assistant requests raid leader to start ready check
- **Message Format**: `READYCHECK_REQUEST` (no data)
- **Current Issues**: No ACK, no guarantee of delivery
- **Migration Target**: `OGRH.MessageTypes.ADMIN.READY_REQUEST`
- **Priority**: Medium
- **Notes**: Simple broadcast, low risk
- **Status**: Migrated to MessageRouter.Broadcast with HIGH priority

---

### 2. Announcement Broadcast (Line 1353) ✅ COMPLETED
```lua
-- SendAddonMessage(OGRH.ADDON_PREFIX, message, "RAID")  -- "ANNOUNCE;..." format
```
- **Context**: `OGRH.BroadcastAnnouncement()` - Disabled due to item link issues
- **Message Format**: `ANNOUNCE;line1;line2;...`
- **Current Issues**: Commented out - doesn't support item links with pipe characters
- **Action**: Can be deleted or migrated if re-enabled
- **Priority**: N/A (disabled)
- **Status**: Announcements now use SendChatMessage directly to RAID_WARNING/RAID channels only, no addon messages sent

---

### 3. Generic SendAddonMessage Wrapper (Line 1386) ✅ COMPLETED
```lua
function OGRH.SendAddonMessage(msgType, data)
  local message = msgType .. ";" .. data
  SendAddonMessage(OGRH.ADDON_PREFIX, message, "RAID")
end
```
- **Context**: Generic wrapper function used throughout addon
- **Message Format**: `{msgType};{data}`
- **Current Issues**: No chunking, no retry, no validation
- **Action**: Replace entire function body to use MessageRouter
- **Priority**: High (affects all callers)
- **Migration Strategy**: Replace body with `OGRH.MessageRouter.Broadcast(msgType, data)`
- **Status**: Deprecated with red warning messages, function body removed

---

### 4. Broadcast Encounter Selection (Line 1396) ✅ COMPLETED
```lua
SendAddonMessage(OGRH.ADDON_PREFIX, message, "RAID")  -- "ENCOUNTER_SELECT;raidName;encounterName"
```
- **Context**: `OGRH.BroadcastEncounterSelection()` - Notify raid of UI state change
- **Message Format**: `ENCOUNTER_SELECT;{raidName};{encounterName}`
- **Current Issues**: No confirmation, state changes may be lost
- **Migration Target**: `OGRH.MessageTypes.STATE.CHANGE_ENCOUNTER`
- **Priority**: Medium
- **Data Format**: Change to table `{raidName = "...", encounterName = "..."}`
- **Status**: All 5 call sites migrated to MessageRouter with serialization (BigWigs + 3 EncounterMgmt navigation functions + BroadcastEncounterSelection deprecated stub)

---

### 5. Request Encounter Sync (Line 1412) ✅ COMPLETED
```lua
SendAddonMessage(OGRH.ADDON_PREFIX, requestMsg, "RAID")  -- "REQUEST_ENCOUNTER_SYNC;raidName;encounterName"
```
- **Context**: `OGRH.BroadcastEncounterSelection()` - Non-admin requests sync from admin
- **Message Format**: `REQUEST_ENCOUNTER_SYNC;{raidName};{encounterName}`
- **Current Issues**: No timeout, no retry if admin doesn't respond
- **Migration Target**: `OGRH.MessageTypes.SYNC.REQUEST_PARTIAL`
- **Priority**: Medium
- **Enhancement**: Add timeout + retry logic
- **Status**: Migrated to SYNC.REQUEST_PARTIAL via MessageRouter (item 4 migration), orphaned CHAT_MSG_ADDON handler removed

---

### 6. Assignment Update (Line 1893) ✅ COMPLETED
```lua
SendAddonMessage(OGRH.ADDON_PREFIX, "ASSIGNMENT_UPDATE;" .. data, "RAID")
```
- **Context**: `OGRH.BroadcastAssignmentUpdate()` - Broadcast single assignment change
- **Message Format**: `ASSIGNMENT_UPDATE;{raid};{encounter};{roleIndex};{slotIndex};{playerName};{checksum}`
- **Current Issues**: Semicolon-delimited, size limit issues, no batching
- **Migration Strategy**: **Replace with Phase 3A delta sync** (`OGRH.SyncDelta.RecordAssignmentChange`)
- **Priority**: HIGH - Already have delta sync implementation
- **Action**: Replace direct calls with delta sync recorder
- **Status**: All 5 call sites in EncounterMgmt.lua migrated to delta sync
  - Player list drag assignment (line 2478)
  - Slot drag swap - both sides recorded (line 3331-3339)
  - Slot drag move - both move and clear recorded (line 3352-3360)
  - Right-click remove (line 3417)
  - Core function deprecated with warning wrapper
- **Enhancement**: Swap operations now properly record BOTH players' new assignments instead of moving one and clearing the other

---

### 7. Encounter Sync Fallback (Line 1943) ✅ DELETED
```lua
SendAddonMessage(OGRH.ADDON_PREFIX, "ENCOUNTER_SYNC;" .. serialized, "RAID")
```
- **Context**: `OGRH.BroadcastFullEncounterSync()` - Fallback if chunked send unavailable
- **Message Format**: `ENCOUNTER_SYNC;{serializedData}`
- **Current Issues**: Truncation risk for large encounters (>255 bytes)
- **Action**: **DELETE ENTIRE FALLBACK** - obsolete with delta sync + Phase 2 chunked sync
- **Priority**: HIGH (safety issue)
- **Status**: Fallback deleted (else block lines 1877-1880)
- **Rationale**: 
  - Delta sync (Phase 3A) handles incremental updates immediately
  - Atomic SWAP operations (Phase 3B Item 6) prevent assignment race conditions
  - Phase 2 chunked sync handles full state transfers when needed
  - Fallback never executes since OGRH.Sync always loaded
  - Project spec: no backwards compatibility required

---

### 8. RolesUI Checksum Check (Line 2204) ✅ MOVED TO SYNCINTEGRITY
```lua
SendAddonMessage(OGRH.ADDON_PREFIX, "ROLESUI_CHECK;" .. myChecksum, "RAID")
```
- **Context**: `OGRH.SendRolesUIChecksum()` - Non-admin verifies sync state
- **Message Format**: `ROLESUI_CHECK;{checksum}`
- **Current Issues**: Pull model (client requests), no automatic repair
- **Action**: **DELETE from Core, integrate into unified checksum polling system**
- **Priority**: Medium
- **Status**: Moved to unified polling (OGRH_SyncIntegrity.lua)
- **Implementation**: 
  - Admin broadcasts unified checksum every 30 seconds (structure + RolesUI + assignments)
  - Clients silently compare their checksums to admin's broadcast
  - Auto-repair on mismatch (admin pushes RolesUI data to all raid members)
  - Single polling system instead of multiple timers
- **Functions Deleted from Core**:
  - `OGRH.SendRolesUIChecksum()` - obsolete pull model
  - `OGRH.BroadcastRolesUISync()` - replaced by unified sync
  - `ROLESUI_CHECK` handler in CHAT_MSG_ADDON - no longer needed

---

### 9. ReadHelper Sync Response (Line 2461) ✅ REMOVED
```lua
-- SendAddonMessage(OGRH.ADDON_PREFIX, "READHELPER_SYNC_RESPONSE;" .. serialized, "RAID")
```
- **Context**: `OGRH.SendReadHelperSyncData()` - Respond to ReadHelper module sync request
- **Message Format**: `READHELPER_SYNC_RESPONSE;{serializedData}`
- **Current Issues**: Large payload (raids, encounters, roles, consumes), truncation risk
- **Action**: **REMOVED** - ReadHelper addon deprecated
- **Priority**: N/A (obsolete)
- **Status**: All ReadHelper sync support removed
  - `OGRH.SendReadHelperSyncData()` function deleted (170 lines)
  - `READHELPER_POLL_RESPONSE` handler removed
  - `READHELPER_SYNC_REQUEST` handler removed
  - Calls from OGRH_MainUI.lua removed
  - Calls from OGRH_Announce.lua removed
  - Routing from OGRH_Sync.lua removed
- **Impact**: None - ReadHelper is separate addon, one-way sync only

---

### 10. Addon Poll Response (Line 2587) ✅ COMPLETED
```lua
SendAddonMessage(OGRH.ADDON_PREFIX, response, "RAID")  -- "ADDON_POLL_RESPONSE;version;checksum"
```
- **Context**: CHAT_MSG_ADDON handler - Respond to version/checksum poll
- **Message Format**: `ADDON_POLL_RESPONSE;{version};{checksum}`
- **Current Issues**: No deduplication, all 40 raid members respond simultaneously
- **Migration Target**: `OGRH.MessageTypes.ADMIN.POLL_RESPONSE`
- **Priority**: Medium
- **Enhancement**: Add response delay randomization (0-2 seconds) to prevent spam
- **Status**: 
  - Migrated to MessageRouter with ADMIN.POLL_VERSION (request) and ADMIN.POLL_RESPONSE (response)
  - Added 0-2 second randomized delay to spread out 40 raid member responses
  - Updated PollAddonUsers() to use MessageRouter.SendMessage
  - Re-enabled right-click on Sync button to trigger poll and show raid lead selection UI
  - Handlers in OGRH_MessageRouter.lua, removed old code from OGRH_Core.lua

---

### 11. Raid Lead Set Response (Line 2679)
```lua
SendAddonMessage(OGRH.ADDON_PREFIX, "RAID_LEAD_SET;" .. OGRH.RaidLead.currentLead, "RAID")
```
- **Context**: CHAT_MSG_ADDON handler - Respond to `RAID_LEAD_QUERY`
- **Message Format**: `RAID_LEAD_SET;{playerName}`
- **Current Issues**: All raid members with addon respond (spam)
- **Migration Target**: `OGRH.MessageTypes.STATE.RESPONSE_LEAD`
- **Priority**: Low
- **Enhancement**: Only admin or L/A should respond

---

### 12. Raid Data Chunk (Line 3388)
```lua
SendAddonMessage(OGRH.ADDON_PREFIX, msg, "RAID")  -- "RAID_DATA_CHUNK;chunkIndex;totalChunks;data"
```
- **Context**: `OGRH.SendRaidDataChunked()` - Manual chunking for raid data export
- **Message Format**: `RAID_DATA_CHUNK;{chunkIndex};{totalChunks};{chunk}`
- **Current Issues**: Custom chunking, 500ms delay between chunks, no retry, no reassembly guarantee
- **Action**: **Replace with OGAddonMsg auto-chunking**
- **Priority**: HIGH (reinventing the wheel)
- **Migration Strategy**: Remove manual chunking, use `OGAddonMsg.Send()` with large data

---

### 13. Ready Check Complete (Line 3818)
```lua
SendAddonMessage(OGRH.ADDON_PREFIX, "READYCHECK_COMPLETE", "RAID")
```
- **Context**: `OGRH.ReportReadyCheckResults()` - Broadcast completion to hide timers
- **Message Format**: `READYCHECK_COMPLETE` (no data)
- **Current Issues**: May not reach all clients
- **Migration Target**: `OGRH.MessageTypes.ADMIN.READY_COMPLETE`
- **Priority**: Medium
- **Notes**: Simple broadcast

---

### 14. Request Raid Data (Line 4116)
```lua
SendAddonMessage(OGRH.ADDON_PREFIX, "REQUEST_RAID_DATA", "RAID")
```
- **Context**: `OGRH.RequestRaidData()` - Request full encounter data from raid members
- **Message Format**: `REQUEST_RAID_DATA` (no data)
- **Current Issues**: All 40 raid members may respond with large chunked data simultaneously
- **Migration Target**: `OGRH.MessageTypes.SYNC.REQUEST_FULL`
- **Priority**: Medium
- **Enhancement**: Target specific player (admin) instead of broadcast

---

### 15. Request Current Encounter (Line 4186)
```lua
SendAddonMessage(OGRH.ADDON_PREFIX, "REQUEST_CURRENT_ENCOUNTER", "RAID")
```
- **Context**: `OGRH.RequestCurrentEncounterSync()` - Ask what encounter is active
- **Message Format**: `REQUEST_CURRENT_ENCOUNTER` (no data)
- **Current Issues**: All raid members may respond
- **Migration Target**: `OGRH.MessageTypes.STATE.QUERY_ENCOUNTER`
- **Priority**: Low
- **Enhancement**: Target admin only

---

### 16. Request Structure Sync (Line 4210)
```lua
SendAddonMessage(OGRH.ADDON_PREFIX, "REQUEST_STRUCTURE_SYNC", "RAID")
```
- **Context**: `OGRH.RequestStructureSync()` - Request full structure sync from admin
- **Message Format**: `REQUEST_STRUCTURE_SYNC` (no data)
- **Current Issues**: May timeout, no retry
- **Migration Target**: `OGRH.MessageTypes.SYNC.REQUEST_FULL`
- **Priority**: High (critical path)
- **Enhancement**: Use OGAddonMsg success/failure callbacks

---

### 17. Structure Sync Chunk (Line 4290)
```lua
SendAddonMessage(OGRH.ADDON_PREFIX, msg, "RAID")  -- "STRUCTURE_SYNC_CHUNK;chunkIndex;totalChunks;data"
```
- **Context**: `OGRH.BroadcastStructureSync()` - Manual chunking for structure sync
- **Message Format**: `STRUCTURE_SYNC_CHUNK;{chunkIndex};{totalChunks};{data}`
- **Current Issues**: Custom chunking, 500ms delay, no retry
- **Action**: **Replace with OGAddonMsg auto-chunking**
- **Priority**: HIGH (critical path, reinventing the wheel)
- **Migration Strategy**: Use `OGAddonMsg.Send()` with MessageRouter

---

### 18. Encounter Structure Sync Chunk (Line 4365)
```lua
SendAddonMessage(OGRH.ADDON_PREFIX, msg, "RAID")  -- "ENCOUNTER_STRUCTURE_SYNC_CHUNK;requesterName;chunkIndex;totalChunks;data"
```
- **Context**: `OGRH.BroadcastEncounterStructureSync()` - Manual chunking for single encounter
- **Message Format**: `ENCOUNTER_STRUCTURE_SYNC_CHUNK;{requesterName};{chunkIndex};{totalChunks};{data}`
- **Current Issues**: Custom chunking with requester filter (inefficient broadcast)
- **Action**: **Replace with OGAddonMsg targeted send**
- **Priority**: HIGH
- **Migration Strategy**: Use `OGAddonMsg.SendTo(requesterName, ...)` instead of broadcast

---

## Migration Summary

### By Category

**Ready Check (2 calls):**
- `READYCHECK_REQUEST` → `ADMIN.READY_REQUEST`
- `READYCHECK_COMPLETE` → `ADMIN.READY_COMPLETE`

**Polls/Queries (4 calls):**
- `ADDON_POLL_RESPONSE` → `ADMIN.POLL_RESPONSE`
- `RAID_LEAD_QUERY` response → `STATE.RESPONSE_LEAD`q
- `REQUEST_CURRENT_ENCOUNTER` → `STATE.QUERY_ENCOUNTER`
- (Poll request in other file)

**Assignments (1 call):**
- `ASSIGNMENT_UPDATE` → Use Phase 3A delta sync (already implemented)

**Sync Requests (4 calls):**
- `REQUEST_ENCOUNTER_SYNC` → `SYNC.REQUEST_PARTIAL`
- `REQUEST_RAID_DATA` → `SYNC.REQUEST_FULL`
- `REQUEST_STRUCTURE_SYNC` → `SYNC.REQUEST_FULL`

**Sync Responses (1 call):**
- `READHELPER_SYNC_RESPONSE` → REMOVED (ReadHelper deprecated)

**Checksums (1 call):**
- `ROLESUI_CHECK` → `SYNC.CHECKSUM_STRUCTURE` (may be obsolete)

**Manual Chunking (3 calls - HIGH PRIORITY):**
- `RAID_DATA_CHUNK` → Replace with OGAddonMsg auto-chunking
- `STRUCTURE_SYNC_CHUNK` → Replace with OGAddonMsg auto-chunking
- `ENCOUNTER_STRUCTURE_SYNC_CHUNK` → Replace with OGAddonMsg targeted send

**Encounter Selection (1 call):**
- `ENCOUNTER_SELECT` → `STATE.CHANGE_ENCOUNTER`

**Wrapper Functions (1 call):**
- `OGRH.SendAddonMessage()` → Replace body with MessageRouter call

---

## Priority Order for Migration

### Phase 1: High Priority (Safety & Efficiency)
1. **Manual Chunking Systems** (Lines 3388, 4290, 4365)
   - Replace with OGAddonMsg auto-chunking
   - Critical: Eliminates custom chunking bugs
   - Impact: Large data transfers become reliable

2. **Assignment Updates** (Line 1893)
   - Replace with Phase 3A delta sync
   - Critical: Already implemented, just need to swap calls
   - Impact: Batching, combat blocking, offline queue

3. **Encounter Sync Fallback Removal** (Line 1943)
   - Delete unsafe fallback path
   - Critical: Prevents data truncation
   - Impact: Forces proper chunked sync

### Phase 2: Medium Priority (Standardization)
1. **Request/Response Patterns** (Lines 1412, 4116, 4186, 4210)
   - Migrate to MessageRouter with proper message types
   - Add timeout/retry logic via OGAddonMsg callbacks
   - Impact: Reliable sync requests

2. **State Broadcasts** (Lines 1396, 2679)
   - Standardize encounter selection and raid lead announcements
   - Impact: Consistent state management

3. **ReadHelper Sync** (Line 2461)
   - Add chunking for large payloads
   - Impact: Reliable ReadHelper integration

### Phase 3: Low Priority (Polish)
1. **Simple Broadcasts** (Lines 1319, 3818)
   - Ready check messages
   - Impact: Minor reliability improvement

2. **Polls** (Line 2587)
   - Add response randomization
   - Impact: Reduces simultaneous response spam

3. **Checksums** (Line 2204)
   - May be obsolete after Phase 2
   - Impact: Cleanup only

---

## Testing Strategy

### Per-Call Testing
Each migration should be tested individually:
1. Replace SendAddonMessage call with MessageRouter equivalent
2. `/reload` on 2+ clients
3. Trigger the specific feature
4. Verify message received and processed correctly
5. Check for errors in chat log
6. Validate data integrity

### Regression Testing
After each migration:
- Full addon reload
- Test all major workflows
- Verify no existing features broken
- Check for nil errors

### Integration Testing
After all migrations complete:
- 40-player raid simulation
- Zone transitions during sync
- `/reload` during large transfers
- Combat blocking scenarios
- Offline queue scenarios

---

## Progress Log

### Completed (Session 1 - January 21, 2026)
- ✅ **Item 1**: Ready Check Request migrated to ADMIN.READY_REQUEST
- ✅ **Item 2**: Announcement Broadcast - no addon messages sent (uses direct chat only)
- ✅ **Item 3**: Generic SendAddonMessage wrapper deprecated with warnings
- ✅ **Item 4**: Broadcast Encounter Selection migrated (5 locations) to STATE.CHANGE_ENCOUNTER
- ✅ **Item 5**: Request Encounter Sync handler removed (replaced by SYNC.REQUEST_PARTIAL)
- ✅ **Item 6**: Assignment Update migrated to delta sync (5 locations in EncounterMgmt.lua)
- ✅ **Item 7**: Encounter Sync Fallback deleted (unsafe, obsolete with delta sync)
- ✅ **Item 8**: RolesUI checksum moved to unified SyncIntegrity polling system
- ✅ **Item 9**: ReadHelper sync removed (addon deprecated, 6 locations cleaned up)
- ✅ **Item 10**: Addon Poll Response migrated with 0-2s randomization, Sync button right-click restored

### Next Session
- Items 11-18: Remaining migrations per priority order
  - Item 11: Raid Lead Set Response (only admin/L/A respond)
  - Items 12, 17, 18: Manual chunking replacements (HIGH PRIORITY - reinventing the wheel)
  - Items 13-16: Remaining request/response patterns

---

## Next Steps

1. ✅ Audit complete (this document)
2. ✅ Begin migrations (Items 1, 3, 4, 5 complete)
3. Continue migrations per priority order
4. Test each migration thoroughly before proceeding
5. Update design document with progress

---

**Maintainer:** AI Agent  
**Last Updated:** January 2026
