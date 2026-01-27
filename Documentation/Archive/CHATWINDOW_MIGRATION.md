# Chat Window Migration - DEFAULT_CHAT_FRAME to OGRH.Msg()

## Overview
This document tracks the migration of all DEFAULT_CHAT_FRAME:AddMessage() calls to use OGRH.Msg() for proper routing to the OGRH chat window.

## Status Legend
- ✅ COMPLETED: Converted to OGRH.Msg()
- ⏩ SKIP: Should remain as DEFAULT_CHAT_FRAME (system messages, fallbacks, or special cases)
- 🔄 PENDING: Needs conversion

---

## Core Files

### Core/ChatWindow.lua - ⏩ SKIP ALL (Internal chat window management)
- Line 51: Using existing chat window (system message about window itself)
- Line 58: Failed to create chat window (system error)
- Line 74: Created NEW chat window (system message about window itself)
- Line 117: ChatMsg fallback to DEFAULT_CHAT_FRAME
- Line 138: OGRH.Msg fallback to DEFAULT_CHAT_FRAME  
- Lines 168, 173, 211, 254, 270: Window management messages

**Reason**: These are meta-messages ABOUT the chat window system itself, should go to default frame.

### Core/Core.lua - Mixed
- Line 537: ⏩ SKIP - Fallback definition of OGRH.Msg() itself
- Line 1633-1650: 🔄 PENDING - Deprecated function warnings
- Lines 2179-2697: 🔄 PENDING - Debug/sync messages
- Lines 3172-3364: 🔄 PENDING - Raid data request/chunk messages
- Line 4527-4529: 🔄 PENDING - Import messages

### Core/SavedVariablesManager.lua - ✅ COMPLETED
- Line 369: Module load message (converted to OGRH.Msg)

### Core/Utilities.lua - ✅ COMPLETED  
- Line 32: Module load message (converted to OGRH.Msg)

---

## Infrastructure Files

### Infrastructure/MessageTypes.lua - 🔄 PENDING
- Lines 209-221: Debug command output (list message types)
- Line 225: **Module load message** - PRIORITY

### Infrastructure/Permissions.lua - 🔄 PENDING
- Line 457: **Module load message** - PRIORITY

### Infrastructure/Versioning.lua - 🔄 PENDING
- Line 340: **Module load message** - PRIORITY
- Lines 361-406: Debug command output (version state, changes)
- Line 678: **Module load message** - PRIORITY

### Infrastructure/MessageRouter.lua - 🔄 PENDING
- Lines 27-292: Various router errors/warnings
- Line 306: Initialized message
- Lines 317-346: Admin assignment messages
- Line 1389: Auto-promote message
- Lines 1404-1428: Debug command output
- Line 1431: **Module load message** - PRIORITY

### Infrastructure/Sync_v2.lua - 🔄 PENDING
- Line 7: Error message
- Lines 67-219: Sync-related messages
- Line 613: Factory defaults loaded
- Line 694: **Module load message** - PRIORITY

### Infrastructure/DataManagement.lua - 🔄 PENDING
- Line 6: Error message
- Line 57: Factory defaults loaded
- Line 841: **Module load message** - PRIORITY

### Infrastructure/SyncIntegrity.lua - 🔄 PENDING
- Line 790: **Module load message** - PRIORITY
- Line 1109: Module loaded (PASS message)

### Infrastructure/SyncDelta.lua - 🔄 PENDING
- Line 367: **Module load message** - PRIORITY
- Line 370: **Module load message** - PRIORITY

### Infrastructure/SyncUI.lua - 🔄 PENDING
- Line 80: **Module load message** - PRIORITY
- Line 83: **Module load message** - PRIORITY

---

## Configuration Files

### Configuration/Invites.lua - 🔄 PENDING
- Line 4: Error message
- Line 15: JSON error
- Lines 755-786: Debug command output (RollFor metadata)
- Line 2590: ⏩ SKIP - Commented out

### Configuration/Invites_Test.lua - ⏩ SKIP ALL (Test framework output)
- Lines 57-247: All test output messages
**Reason**: Test output should go to default chat for visibility

### Configuration/Roster.lua - 🔄 PENDING
- Line 1665: ELO calculation message
- Lines 1702-1704: Player update messages

### Configuration/Promotes.lua - ⏩ SKIP
- Line 611: Commented out

### Configuration/Consumes.lua - 🔄 PENDING
- Line 11: Error message

### Configuration/ConsumesTracking.lua - ✅ COMPLETED (uses OGRH.Msg already)
- Line 2727: Module load message

---

## Raid Files

### Raid/EncounterMgmt.lua - 🔄 PENDING
- Line 4: Error message
- Lines 582-653: Migration messages
- Lines 698-5343: Many encounter management messages

### Raid/EncounterSetup.lua - 🔄 PENDING
- Lines 15-2600: Setup/management messages

### Raid/RolesUI.lua - 🔄 PENDING
- Line 161: Permission error
- Line 223: Delta sync error

### Raid/LinkRole.lua - 🔄 PENDING
- Line 297: Linked roles updated

### Raid/Announce.lua - 🔄 PENDING
- Line 6: Error message
- Lines 731-813: Announcement errors
- Line 837: ⏩ SKIP - Commented out

### Raid/BigWigs.lua - 🔄 PENDING
- Lines 122-244: BigWigs integration messages

### Raid/AdvancedSettings.lua - 🔄 PENDING
- Lines 9-326: BigWigs settings messages

### Raid/ClassPriority.lua - 🔄 PENDING
- Line 362: Class priority saved
- Line 371: ⏩ SKIP - Commented out

### Raid/Trade.lua - ⏩ SKIP
- Line 543: Commented out

---

## Administration Files

### Administration/Recruitment.lua - 🔄 PENDING
- Line 5: Error message

### Administration/SRValidation.lua - 🔄 PENDING
- Lines 689-691: Validation save messages

### Administration/AddonAudit.lua - 🔄 PENDING
- Line 11: Error message

---

## UI Files

### UI/MainUI.lua - ✅ COMPLETED (mostly)
- Line 3: Error message - NEEDS REVIEW
- Lines 706-784: Chat window commands - ⏩ SKIP (meta-messages about window)
- Lines 834-846: ✅ COMPLETED - Module load/RollFor messages

---

## Modules

### Modules/cthun.lua - 🔄 PENDING
- Lines 18-25: BigWigs error messages

### Modules/OGRH-ConsumeHelper.lua - ✅ COMPLETED (uses OGRH.Msg already)
- Line 71: Uses OGRH.Msg
- Line 2921: Uses OGRH.Msg

---

## Libraries (External Code)

### Libs/OGAddonMsg/*.lua - ⏩ SKIP ALL
**Reason**: External library, should not be modified

### Libs/OGST/*.lua - ⏩ SKIP ALL  
**Reason**: External library

---

## Tests

### Tests/test_hierarchical_checksums.lua - ⏩ SKIP ALL
**Reason**: Test output should remain visible in default chat

---

## Priority Conversion Order

1. **PRIORITY 1: Module Load Messages** (High visibility, users always see these)
   - Infrastructure/MessageTypes.lua:225
   - Infrastructure/Permissions.lua:457
   - Infrastructure/Versioning.lua:340, 678
   - Infrastructure/MessageRouter.lua:1431
   - Infrastructure/Sync_v2.lua:694
   - Infrastructure/DataManagement.lua:841
   - Infrastructure/SyncIntegrity.lua:790
   - Infrastructure/SyncDelta.lua:367, 370
   - Infrastructure/SyncUI.lua:80, 83

2. **PRIORITY 2: Error Messages** (Users need to see these)
   - All error messages in Configuration/Administration files

3. **PRIORITY 3: User Action Feedback** (Role updates, saves, etc.)
   - Raid/* feedback messages
   - Configuration/* user action results

4. **PRIORITY 4: Debug/Info Messages** (Lower priority)
   - Core/Core.lua debug messages
   - Infrastructure/* debug outputs

---

## Migration Strategy

For each file:
1. Create a replacement list for all instances
2. Use multi_replace_string_in_file for efficiency
3. Test module load to verify messages appear in OGRH window
4. Mark as completed in this document

## Notes
- Some messages should intentionally stay in DEFAULT_CHAT_FRAME (test output, meta-messages about window system)
- Library code (OGAddonMsg, OGST) should not be modified
- Commented-out messages can be skipped
