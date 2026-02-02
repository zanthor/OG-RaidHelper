# v2 Invites Update - Project Plan

**Version:** 1.0  
**Created:** February 2, 2026  
**Status:** Planning  
**Estimated Effort:** 3-4 days

---

## Overview

Comprehensive refactoring of the Invites module to improve UX, streamline invite workflow, and integrate roster data with EncounterMgmt planning system.

### Goals

1. **Simplify UI** - Remove redundant buttons, clarify purpose of remaining controls
2. **Improve Invite Mode** - Better communication with guild about invite status
3. **Streamline Import Flow** - User-initiated only, no auto-refresh
4. **Enable Planning Integration** - Export roster to EncounterMgmt for assignment planning
5. **Clean Up Data** - Clear stale history on new imports

---

## Current State Analysis

### Current UI Elements

**Player List Actions (per player):**
- ✅ "Invite" button - Invites single player
- ✅ "Msg" button - Opens whisper dialog

**Bulk Actions:**
- ✅ "Invite All Active" - Mass invite online players
- ✅ "AutoGroup" button - Applies Raid-Helper group assignments
- ✅ "Start Invite Mode" - Automated invite cycles

**Import Flow:**
- ✅ "Import Roster" button with 3 sources (RollFor, Invites, Groups)
- ✅ Window title shows raid name (e.g., "Raid Invites - Blackwing Lair")
- ✅ JSON import prompts for raid name

**Background Behavior:**
- ✅ RollFor auto-refresh checks every 5 seconds for SR data changes
- ✅ Auto-opens RollFor import when SR data detected

### Current Schema (OGRH_SV.v2.invites)

```lua
OGRH_SV.v2.invites = {
    currentSource = "rollfor",  -- or "raidhelper"
    
    raidhelperData = {
        id = "raid-123",
        name = "MC Raid",
        players = {...}
    },
    
    raidhelperGroupsData = {...},
    
    inviteMode = {
        enabled = false,
        interval = 60,
        lastInviteTime = 0,
        totalPlayers = 0,
        invitedCount = 0
    },
    
    declinedPlayers = {},
    history = {},  -- Never cleared
    
    invitePanelPosition = {...}
}
```

---

## Proposed Changes

### Phase 1: UI Simplification

#### 1.1 Remove Per-Player Action Buttons

**Current:**
```
[PlayerName]  [Role]  [Status]  [Invite] [Msg]
```

**Proposed:**
```
[PlayerName]  [Role]  [Status]
```

**Rationale:**
- Invite Mode handles automated invites
- Whisper functionality redundant (can use /w directly)
- Reduces UI clutter
- Players can still right-click for actions if needed

**Implementation:**
- Remove button creation in `RefreshPlayerList()`
- Remove `InvitePlayer()` and `WhisperPlayer()` button click handlers
- Keep underlying functions for Invite Mode use

---

#### 1.2 Remove "Invite All Active" Button

**Rationale:**
- Functionality replaced by "Start Invite Mode"
- One-off mass invites are edge case
- Invite Mode provides better control and feedback

**Implementation:**
- Remove `InviteAllOnline()` button from UI
- Keep function for potential programmatic use
- Update layout to reclaim space

---

#### 1.3 Rename "AutoGroup" to "Sort" with Toggle

**Current:**
```lua
-- Button applies group assignments (one-time action)
autoGroupBtn:SetText("AutoGroup")
autoGroupBtn:SetScript("OnClick", function()
    OGRH.Invites.OrganizeRaidGroups()
end)
```

**Proposed:**
```lua
-- Button toggles auto-sort flag
local sortBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
sortBtn:SetText("Sort")

-- Update button color based on state
local function UpdateSortButtonColor()
    local autoSort = OGRH.SVM.GetPath("invites.autoSort")
    if autoSort then
        sortBtn:SetText("|cff00ff00Sort|r")  -- Green = enabled
    else
        sortBtn:SetText("|cffff0000Sort|r")  -- Red = disabled
    end
end

sortBtn:SetScript("OnClick", function()
    local current = OGRH.SVM.GetPath("invites.autoSort") or false
    OGRH.SVM.SetPath("invites.autoSort", not current, {
        syncLevel = "MANUAL",
        componentType = "settings"
    })
    UpdateSortButtonColor()
end)
```

**Behavior:**
- **Enabled (Green):** Auto-organize new raid members during Invite Mode
- **Disabled (Red):** No auto-organization

**Implementation:**
- Add `autoSort` boolean to schema
- Update button creation and click handler
- Modify `AutoOrganizeNewMembers()` to check flag before organizing
- Persist state across sessions

---

#### 1.4 Simplify Window Title

**Current:**
```lua
titleText:SetText("Raid Invites - " .. raidName)
-- Attempts to determine raid name from source
```

**Proposed:**
```lua
titleText:SetText("Raid Invites")
-- Static title, no raid name detection
```

**Rationale:**
- Raid name now comes from Active Raid in EncounterMgmt
- Removes complexity of detecting raid name from various sources
- Consistent title regardless of source

**Implementation:**
- Update title text to static string
- Remove raid name detection logic

---

#### 1.5 Remove Raid Name Prompt on JSON Import

**Current:**
```lua
-- ShowJSONImportDialog prompts for raid name
-- Stores in raidhelperData.name
```

**Proposed:**
```lua
-- Import JSON without raid name prompt
-- Use metadata from JSON or leave blank
```

**Rationale:**
- Raid name determined by Active Raid selection in EncounterMgmt
- Removes extra step in import flow
- User confusion about which name to use

**Implementation:**
- Remove raid name input field from import dialog
- Store JSON title/metadata as-is
- Update `ParseRaidHelperJSON()` to not require user-provided name

---

### Phase 2: Invite Mode Enhancements

#### 2.1 Guild Announcements

**On Invite Mode Start:**
```lua
function OGRH.Invites.ToggleInviteMode()
    if inviteMode.enabled then
        -- Get Active Raid name
        local activeRaid = OGRH.GetActiveRaid()
        local raidName = activeRaid and activeRaid.displayName or "Raid"
        
        -- Strip [AR] prefix
        raidName = string.gsub(raidName, "%[AR%] ", "")
        
        -- Announce to guild
        SendChatMessage(
            string.format("Starting invites for %s. Whisper me if you're signed up and need an invite!", raidName),
            "GUILD"
        )
        
        -- ... rest of existing logic
    end
end
```

**On Each Invite Cycle:**
```lua
function OGRH.Invites.DoInviteCycle()
    -- ... existing invite logic
    
    -- Announce to guild
    local activeRaid = OGRH.GetActiveRaid()
    local raidName = activeRaid and string.gsub(activeRaid.displayName, "%[AR%] ", "") or "Raid"
    
    SendChatMessage(
        string.format("Sending invites for %s - whisper me if you need an invite!", raidName),
        "GUILD"
    )
    
    inviteMode.lastInviteTime = GetTime()
end
```

**Implementation:**
- Add guild announcements at start and each cycle
- Use Active Raid name from EncounterMgmt
- Strip [AR] prefix for cleaner announcement

---

#### 2.2 Auto-Whisper Non-Invited Players

**Trigger:** Player whispers during Invite Mode but is not invited

**Responses:**

```lua
function OGRH.Invites.HandleWhisperAutoResponse(sender, message)
    -- ... existing roster lookup
    
    if player.bench then
        SendChatMessage(
            "You are currently on the bench for this raid. Please check with the raid leader if you want to participate.",
            "WHISPER", nil, sender
        )
        return
    end
    
    if player.absent then
        SendChatMessage(
            "You are marked as absent for this raid. If you can attend, please update your status and whisper the raid leader.",
            "WHISPER", nil, sender
        )
        return
    end
    
    -- Not in roster at all
    local currentSource = OGRH.SVM.GetPath("invites.currentSource")
    if currentSource == OGRH.Invites.SOURCE_TYPE.ROLLFOR then
        SendChatMessage(
            "You are not on the soft reserve list for this raid. Please check RollFor if you believe this is an error.",
            "WHISPER", nil, sender
        )
    else
        SendChatMessage(
            "You are not signed up for this raid. Please check Raid-Helper if you believe this is an error.",
            "WHISPER", nil, sender
        )
    end
end
```

**Implementation:**
- Extend existing `HandleWhisperAutoResponse()` function
- Add case for players not in roster
- Provide source-specific feedback (RollFor vs Raid-Helper)

---

### Phase 3: Operational Changes

#### 3.1 Remove RollFor Auto-Refresh

**Current:**
```lua
-- rollForCheckFrame OnUpdate checks every 5 seconds
rollForCheckFrame:SetScript("OnUpdate", function()
    rollForTimeSinceCheck = rollForTimeSinceCheck + arg1
    if rollForTimeSinceCheck >= rollForCheckInterval then
        -- Check hash, auto-refresh if changed
    end
end)
```

**Proposed:**
```lua
-- Remove OnUpdate handler
-- User must manually click "Import Roster" > "RollFor Soft-Res"
```

**Rationale:**
- Auto-refresh creates unexpected UI updates
- User should explicitly control when roster data is imported
- Reduces CPU usage from constant polling

**Implementation:**
- Remove `rollForCheckFrame:SetScript("OnUpdate", ...)` handler
- Keep hash detection for manual import (detect changes on button click)
- Remove auto-open of RollFor import window

---

#### 3.2 Streamlined Import Flow

**Current Flow:**
1. RollFor data changes detected
2. Auto-opens import window
3. User clicks import

**Proposed Flow:**
1. User clicks "Import Roster" button
2. Dropdown shows: "RollFor Soft-Res", "Raid-Helper (Invites)", "Raid-Helper (Groups)"
3. User selects source
4. Data imported immediately (no intermediate window for RollFor)

**For RollFor (3 Possible Approaches):**

**Option A: Direct Read (Read-Only)**
```lua
-- Read current RollFor data without modifying RollFor
function OGRH.Invites.ImportRollFor()
    if not OGRH.ROLLFOR_AVAILABLE then
        OGRH.Msg("RollFor not available")
        return
    end
    
    -- Direct import from current RollFor state
    local players = OGRH.Invites.GetSoftResPlayers()
    
    -- Update source
    OGRH.SVM.SetPath("invites.currentSource", OGRH.Invites.SOURCE_TYPE.ROLLFOR, {
        syncLevel = "MANUAL",
        componentType = "settings"
    })
    
    -- Clear history
    OGRH.SVM.SetPath("invites.history", {}, {
        syncLevel = "MANUAL",
        componentType = "settings"
    })
    
    -- Clear planning roster (will be regenerated)
    OGRH.SVM.SetPath("invites.planningRoster", {}, {
        syncLevel = "MANUAL",
        componentType = "settings"
    })
    
    -- Generate planning roster
    OGRH.Invites.GeneratePlanningRoster()
    
    -- Refresh UI
    OGRH.Invites.RefreshPlayerList()
    
    OGRH.Msg("Imported " .. table.getn(players) .. " players from RollFor")
end
```

**Option B: OGRH Dialog → Update RollFor (Write-Back)**
```lua
-- Show our own import dialog, then update RollFor's data
function OGRH.Invites.ImportRollFor()
    -- Show OGRH import dialog
    local dialog = CreateFrame("Frame", "OGRH_RollForImportDialog", UIParent)
    -- ... dialog setup with text box for RollFor import data
    
    -- Parse button click:
    parseBtn:SetScript("OnClick", function()
        local importData = editBox:GetText()
        
        -- Parse RollFor import format
        local players = OGRH.Invites.ParseRollForImport(importData)
        
        -- Update RollFor's data structures (if API allows)
        if RollFor and RollFor.ImportData then
            RollFor.ImportData(importData)
        elseif RollForCharDb then
            -- Direct write to RollFor's SavedVariables
            RollForCharDb.softres = OGRH.Invites.ConvertToRollForFormat(players)
        else
            OGRH.Msg("Cannot update RollFor data - API not available")
            return
        end
        
        -- Now import to OGRH
        OGRH.Invites.ImportFromRollForData(players)
    end)
end
```

**Option C: Prompt User to Update RollFor First**
```lua
-- Show reminder dialog, user updates RollFor manually
function OGRH.Invites.ImportRollFor()
    -- Show dialog: "Please update RollFor with your soft reserve data first"
    local dialog = CreateFrame("Frame", "OGRH_RollForPromptDialog", UIParent)
    -- ... dialog setup
    
    local instructionText = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    instructionText:SetText(
        "Please ensure RollFor has the latest soft reserve data.\n\n" ..
        "1. Open RollFor\n" ..
        "2. Import your soft reserve data\n" ..
        "3. Click 'Import' below to sync to OG-RaidHelper"
    )
    
    local importBtn = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
    importBtn:SetText("Import")
    importBtn:SetScript("OnClick", function()
        -- Proceed with Option A (direct read)
        OGRH.Invites.ImportRollForDirect()
        dialog:Hide()
    end)
end
```

**Evaluation Criteria:**
- **Option A (Read-Only):** Simplest, but user must update RollFor separately
- **Option B (Write-Back):** Best UX, single import point, but requires RollFor API access
- **Option C (Prompt):** Explicit workflow, ensures data accuracy

**For Raid-Helper:**
```lua
-- Keep existing JSON import dialog
function OGRH.Invites.ImportRaidHelper(importType)
    OGRH.Invites.ShowJSONImportDialog(importType)  -- "invites" or "groups"
end
```

**Implementation:**
- **CRITICAL:** Evaluate RollFor integration approach (see Open Questions)
- Remove auto-refresh logic
- Update "Import Roster" button to show dropdown menu
- Clear history on every import
- Implement chosen approach based on RollFor API capabilities

---

### Phase 4: Planning List Integration

#### 4.1 Create Planning Roster

**Purpose:** Export roster data to EncounterMgmt for assignment planning

**Data Structure:**
```lua
OGRH_SV.v2.invites.planningRoster = {
    -- Array of players with standardized format
    [1] = {
        name = "PlayerName",
        class = "WARRIOR",
        role = "TANKS",  -- Mapped to OGRH format
        group = 1,       -- If using Groups source
        online = false,  -- Current online status
        source = "rollfor"
    },
    -- ...
}
```

**Generation:**
```lua
function OGRH.Invites.GeneratePlanningRoster()
    local players = OGRH.Invites.GetRosterPlayers()
    local planningRoster = {}
    
    for _, player in ipairs(players) do
        -- Exclude absent only (keep benched)
        if not player.absent then
            table.insert(planningRoster, {
                name = player.name,
                class = player.class,
                role = player.role,  -- Already in OGRH format
                group = player.group,
                online = player.online,
                source = player.source,
                benched = player.bench or false  -- Preserve benched status
            })
        end
    end
    
    -- Save to schema
    OGRH.SVM.SetPath("invites.planningRoster", planningRoster, {
        syncLevel = "MANUAL",
        componentType = "settings"
    })
    
    return planningRoster
end
```

**Trigger:** Called when:
1. Importing new roster data
2. Manually via "Update Planning Roster" button (optional)

**Implementation:**
- Add `planningRoster` to schema
- Generate on import
- Provide accessor function for EncounterMgmt: `OGRH.Invites.GetPlanningRoster()`

---

#### 4.2 EncounterMgmt Integration

**Usage in EncounterMgmt:**
```lua
-- Auto-Assign function can use planning roster
function OGRH.EncounterMgmt.AutoAssignFromRoster(raidIdx, encounterIdx)
    local planningRoster = OGRH.Invites.GetPlanningRoster()
    
    if not planningRoster or table.getn(planningRoster) == 0 then
        OGRH.Msg("No planning roster available. Import roster data first.")
        return
    end
    
    -- Auto-assign players to encounter roles based on their signed-up role
    for _, player in ipairs(planningRoster) do
        -- Find matching role column in encounter
        local roleColumn = FindRoleColumnByType(raidIdx, encounterIdx, player.role)
        
        if roleColumn then
            -- Find empty slot
            local slotIdx = FindEmptySlot(raidIdx, encounterIdx, roleColumn.index)
            
            if slotIdx then
                -- Assign player
                OGRH.SVM.SetPath(
                    string.format("encounterMgmt.raids.%d.encounters.%d.roles.%d.assignments.%d",
                        raidIdx, encounterIdx, roleColumn.index, slotIdx),
                    player.name,
                    {
                        syncLevel = "REALTIME",
                        componentType = "assignments",
                        scope = {raid = raidIdx, encounter = encounterIdx}
                    }
                )
            end
        end
    end
end
```

**Implementation:**
- Add `GetPlanningRoster()` accessor to Invites module
- Document integration point in API docs
- Update EncounterMgmt to use planning roster for auto-assign

---

### Phase 5: Schema Changes

#### 5.1 Add autoSort Flag

```lua
OGRH_SV.v2.invites = {
    -- ... existing fields
    
    autoSort = false,  -- NEW: Enable/disable auto-group sorting
}
```

**Default:** `false` (disabled)

**Migration:**
- Check for existing field on load
- Default to `false` if missing

---

#### 5.2 Add planningRoster

```lua
OGRH_SV.v2.invites = {
    -- ... existing fields
    
    planningRoster = {},  -- NEW: Array of players for EncounterMgmt planning
}
```

**Default:** `{}` (empty array)

**Regeneration:** Cleared and rebuilt on every roster import

---

#### 5.3 Clear history on Import

**Current:**
```lua
history = {}  -- Grows indefinitely
```

**Proposed:**
```lua
-- Clear on every import
function OGRH.Invites.ImportRoster(source)
    -- ... import logic
    
    -- Clear history
    OGRH.SVM.SetPath("invites.history", {}, {
        syncLevel = "MANUAL",
        componentType = "settings"
    })
    
    -- Clear declined players
    OGRH.SVM.SetPath("invites.declinedPlayers", {}, {
        syncLevel = "MANUAL",
        componentType = "settings"
    })
    
    -- Clear planning roster (will be regenerated)
    OGRH.SVM.SetPath("invites.planningRoster", {}, {
        syncLevel = "MANUAL",
        componentType = "settings"
    })
    
    -- ... continue import
end
```

**Rationale:**
- History is session-specific (tied to one raid)
- New import = new raid = new session
- Planning roster must match current import source
- Prevents stale data accumulation

---

## Implementation Plan

### Task Breakdown (Ordered)

#### Sprint 1: Schema & Core Changes (Day 1)

1. **[SCHEMA]** Add `autoSort` boolean to schema
   - Default: `false`
   - Location: `OGRH_SV.v2.invites.autoSort`

2. **[SCHEMA]** Add `planningRoster` array to schema
   - Default: `{}`
   - Location: `OGRH_SV.v2.invites.planningRoster`

3. **[CORE]** Implement `GeneratePlanningRoster()`
   - Filters out absent players only (keep benched)
   - Maps roles to OGRH format
   - Saves to schema

4. **[CORE]** Implement `GetPlanningRoster()`
   - Accessor for EncounterMgmt integration
   - Returns cached planning roster

5. **[CORE]** Update import flow to clear history and planning roster
   - Clear `history` on import
   - Clear `declinedPlayers` on import
   - Clear `planningRoster` on import (before regenerating)
   - Call `GeneratePlanningRoster()` after clearing

---

#### Sprint 2: UI Simplification (Day 2)

6. **[UI]** Remove per-player "Invite" buttons
   - Remove button creation in `RefreshPlayerList()`
   - Remove click handlers

7. **[UI]** Remove per-player "Msg" buttons
   - Remove button creation
   - Remove `ShowWhisperDialog()` calls from UI

8. **[UI]** Remove "Invite All Active" button
   - Remove button from main window
   - Keep `InviteAllOnline()` function (unused)

9. **[UI]** Rename "AutoGroup" to "Sort"
   - Update button text
   - Implement toggle behavior
   - Add color coding (green/red)
   - Save state to `autoSort` flag

10. **[UI]** Simplify window title
    - Change to static "Raid Invites"
    - Remove raid name detection logic

11. **[UI]** Remove raid name prompt from JSON import
    - Remove input field from `ShowJSONImportDialog()`
    - Update `ParseRaidHelperJSON()` to not require name

---

#### Sprint 3: Invite Mode Enhancements (Day 2-3)

12. **[INVITE-MODE]** Add guild announcement on start
    - Get Active Raid name from EncounterMgmt
    - Strip [AR] prefix
    - Announce to guild chat

13. **[INVITE-MODE]** Add guild announcement on each cycle
    - Announce before sending invites
    - Include raid name

14. **[INVITE-MODE]** Implement auto-whisper responses
    - Extend `HandleWhisperAutoResponse()`
    - Add benched reason
    - Add absent reason
    - Add not-in-roster reason (source-specific)

15. **[BEHAVIOR]** Update `AutoOrganizeNewMembers()` to check `autoSort` flag
    - Only organize if `autoSort == true`
    - No change if disabled

---

#### Sprint 4: Import Flow Overhaul (Day 3-4)

16. **[IMPORT]** Remove RollFor auto-refresh
    - Remove `rollForCheckFrame:SetScript("OnUpdate", ...)`
    - Remove auto-open import window logic

17. **[IMPORT]** **CRITICAL:** Evaluate RollFor API capabilities
    - Research RollFor's API documentation
    - Test if RollFor exposes `ImportData()` or similar function
    - Check if `RollForCharDb` SavedVariables can be safely modified
    - Test round-trip: OGRH writes → RollFor reads
    - Document findings in evaluation section

18. **[IMPORT]** Choose RollFor integration approach
    - **Option A (Read-Only):** Simple, user updates RollFor separately
    - **Option B (Write-Back):** OGRH dialog → update RollFor programmatically
    - **Option C (Prompt):** Explicit two-step workflow
    - **Decision:** Based on API evaluation results

19. **[IMPORT]** Implement chosen RollFor import approach
    - If Option A: Direct read from RollFor data
    - If Option B: Create import dialog, parse data, write to RollFor, then read
    - If Option C: Show prompt dialog, then direct read
    - Update `ImportRollFor()` function
    - Test with live RollFor data

20. **[IMPORT]** Update "Import Roster" button
    - Show dropdown menu with 3 sources
    - Call appropriate import function on selection

21. **[IMPORT]** Test import flow for all sources
    - RollFor Soft-Res (chosen approach)
    - Raid-Helper (Invites)
    - Raid-Helper (Groups)

---

#### Sprint 5: Testing & Polish (Day 4)

22. **[TEST]** Test UI changes
    - Verify button removal
    - Test Sort toggle
    - Verify window title

23. **[TEST]** Test Invite Mode
    - Guild announcements
    - Auto-whisper responses
    - Auto-sort behavior

24. **[TEST]** Test import flow
    - RollFor (chosen approach)
    - Raid-Helper (Invites)
    - Raid-Helper (Groups)
    - History clearing
    - Planning roster generation

25. **[TEST]** Test RollFor integration specifically
    - If Option B: Test OGRH import dialog → RollFor update
    - If Option C: Test prompt workflow
    - Verify RollFor data matches OGRH data
    - Test edge cases (invalid format, RollFor not loaded)

26. **[TEST]** Test EncounterMgmt integration
    - Planning roster accessor
    - Auto-assign from roster

27. **[DOCS]** Update API documentation
    - Document new functions
    - Document chosen RollFor approach
    - Update schema spec
    - Add integration examples

---

## Testing Checklist

### UI Testing

- [ ] Per-player "Invite" buttons removed
- [ ] Per-player "Msg" buttons removed
- [ ] "Invite All Active" button removed
- [ ] "Sort" button present and toggles state
- [ ] "Sort" button color reflects state (green=on, red=off)
- [ ] Window title is "Raid Invites" (no raid name)
- [ ] JSON import does not prompt for raid name

### Invite Mode Testing

- [ ] Guild announcement sent on Invite Mode start
- [ ] Guild announcement includes Active Raid name
- [ ] Guild announcement sent on each invite cycle
- [ ] Auto-whisper sent to benched players
- [ ] Auto-whisper sent to absent players
- [ ] Auto-whisper sent to non-roster players (RollFor source)
- [ ] Auto-whisper sent to non-roster players (Raid-Helper source)
- [ ] Auto-sort only runs when enabled
- [ ] Auto-sort does not run when disabled

### Import Flow Testing

- [ ] RollFor auto-refresh disabled (no OnUpdate polling)
- [ ] "Import Roster" button shows dropdown
- [ ] RollFor import works correctly
- [ ] Raid-Helper (Invites) import works correctly
- [ ] Raid-Helper (Groups) import works correctly
- [ ] History cleared on import
- [ ] Declined players cleared on import
- [ ] Planning roster generated on import

### Planning Roster Testing

- [ ] Planning roster excludes benched players
- [ ] Planning roster excludes absent players
- [ ] Planning roster includes correct role mappings
- [ ] `GetPlanningRoster()` returns correct data
- [ ] EncounterMgmt can access planning roster
- [ ] Auto-assign uses planning roster correctly

### Schema Testing

- [ ] `autoSort` flag persists across sessions
- [ ] `planningRoster` updates on import
- [ ] `history` cleared on import
- [ ] `declinedPlayers` cleared on import

---

## Schema Migration

### New Fields

```lua
OGRH_SV.v2.invites = {
    -- EXISTING FIELDS (unchanged)
    currentSource = "rollfor",
    raidhelperData = {...},
    raidhelperGroupsData = {...},
    inviteMode = {...},
    declinedPlayers = {},
    history = {},
    invitePanelPosition = {...},
    
    -- NEW FIELDS
    autoSort = false,        -- Enable/disable auto-group sorting
    planningRoster = {},     -- Array of players for EncounterMgmt planning
}
```

### Migration Code

```lua
-- Add to Invites.EnsureSV()
function OGRH.Invites.EnsureSV()
    OGRH.EnsureSV()
    
    -- ... existing initialization
    
    -- Add new fields if missing (v2 Invites Update)
    if OGRH.SVM.GetPath("invites.autoSort") == nil then
        OGRH.SVM.SetPath("invites.autoSort", false, {
            syncLevel = "MANUAL",
            componentType = "settings"
        })
    end
    
    if not OGRH.SVM.GetPath("invites.planningRoster") then
        OGRH.SVM.SetPath("invites.planningRoster", {}, {
            syncLevel = "MANUAL",
            componentType = "settings"
        })
    end
end
```

### Backward Compatibility

- ✅ New fields have safe defaults
- ✅ No breaking changes to existing schema
- ✅ Old behavior preserved if new fields missing
- ✅ Migration runs on first load after update

---

## Rollback Plan

### If Issues Arise

1. **Revert UI Changes:**
   - Restore per-player buttons (copy from git history)
   - Restore "Invite All Active" button
   - Restore "AutoGroup" button behavior

2. **Revert Schema Changes:**
   - Remove `autoSort` and `planningRoster` fields
   - Set `schemaVersion = "v1"` if needed

3. **Revert Operational Changes:**
   - Re-enable RollFor auto-refresh
   - Restore auto-open import window

4. **Restore Import Flow:**
   - Restore raid name prompt for JSON import
   - Restore original "Import Roster" button behavior

### Emergency Rollback Command (CRITICAL DECISION)

**Question:** How should we handle RollFor import workflow?

**Background:**
- RollFor is external addon with its own import interface
- Users currently paste soft reserve data into RollFor
- We need to decide if we can/should provide our own import interface

**Option A: Read-Only (Simplest)**
- User pastes import data into RollFor (their interface)
- RollFor processes and stores data
- OGRH reads from RollFor's SavedVariables
- ✅ No RollFor API dependency
- ✅ RollFor remains source of truth
- ❌ Two-step process (RollFor first, then OGRH)
- ❌ User confusion about which addon to use

**Option B: Write-Back (Best UX)**
- User pastes import data into OGRH dialog
- OGRH parses and validates data
- OGRH writes to RollFor's SavedVariables or calls RollFor API
- OGRH reads back from RollFor to confirm
- ✅ Single import point
- ✅ Better UX
- ❌ Requires RollFor API or direct SavedVariables access
- ❌ Risk of data corruption if RollFor format changes
- ❌ May conflict with RollFor's validation

**Option C: Prompt Workflow (Explicit)**
- OGRH shows dialog: "Update RollFor first, then click Import"
- User updates RollFor manually
- User clicks "Import" in OGRH
- OGRH reads from RollFor
- ✅ Clear workflow
- ✅ No API dependency
- ✅ Ensures data accuracy
- ❌ Extra step vs direct read
- ❌ User might forget to update RollFor

**Evaluation Tasks:**
1. **Research RollFor API:**
   - Does RollFor expose public functions for import?
   - Can we safely write to `RollForCharDb.softres`?
   - Does RollFor validate data on load?

2. **Test Write-Back:**
   - Try direct SavedVariables modification
   - Check if RollFor detects changes
   - Verify no data corruption

3. **Assess Risk:**
   - What happens if RollFor format changes?
   - Can we version-check RollFor?
   - Fallback strategy if write fails?

**Decision Criteria:**
- If RollFor API exists → **Option B** (write-back)
- If no API but SavedVariables stable → **Option B** (write-back with version check)
- If SavedVariables risky → **Option C** (prompt workflow)
- If all else fails → **Option A** (read-only)

**Decision:** TBD after Sprint 4, Task 17 (API evaluation)
**Question:** Should we prompt user to update RollFor, or import directly?

**Option A: Direct Import**
- ✅ Simpler UX (one click)
- ❌ May import stale data if RollFor not updated

**Option B: Prompt First**
- ✅ Ensures data is current
- ❌ Extra step for user

**Decision:** TBD based on RollFor API capabilities

### 2. Planning Roster Update Frequency

**Question:** When should planning roster be regenerated?

**Options:**
- On import only (proposed)
- On import + manual button
- On import + auto-refresh when players join/leave

**Decision:** Import only (can add manual button later if needed)

### 3. History vs Declined Players

**Question:** Should we keep `declinedPlayers` separate from `history`?

**Analysis:**
- `declinedPlayers` - Session-specific (cleared on import)
- `history` - Could track long-term stats (but currently grows forever)

**Proposal:** Keep separate, clear both on import

---

## Success Criteria

### Must Have

- ✅ All UI buttons removed/updated as specified
- ✅ Guild announcements working in Invite Mode
- ✅ Auto-whisper responses working for all cases
- ✅ RollFor auto-refresh disabled
- ✅ Import flow works for all sources
- ✅ Planning roster generated and accessible
- ✅ History cleared on import
- ✅ No breaking changes to existing functionality

### Nice to Have

- ✅ EncounterMgmt auto-assign using planning roster
- ✅ Improved error messaging in import flow
- ✅ Tooltips on Sort button explaining behavior
- ✅ Visual feedback when planning roster updates

### Out of Scope

- ❌ Advanced roster editing (name changes, manual adds)
- ❌ Multi-raid planning roster support
- ❌ Automatic role suggestions based on class
- ❌ Integration with other invite addons

---

## Timeline

| Day | Tasks | Deliverable |
|-----|-------|-------------|
| **Day 1** | Schema changes, core functions | Planning roster generation working |
| **Day 2** | UI simplification, Invite Mode updates | New UI layout complete, guild announcements working |
| **Day 3** | Import flow overhaul | All sources importable via new flow |
| **Day 4** | Testing, polish, documentation | All tests passing, docs updated |

**Total Estimated Effort:** 3-4 days

---

## Dependencies

### External Modules

- ✅ **EncounterMgmt.lua** - Provides Active Raid name, will consume planning roster
- ✅ **RollFor addon** - Must be loaded for RollFor import
- ✅ **Core.lua** - `GetActiveRaid()` function
- ✅ **SVM** - Schema read/write operations

### Internal Functions

- ✅ `OGRH.Invites.GetRosterPlayers()` - Used by planning roster generation
- ✅ `OGRH.Invites.MapRoleToOGRH()` - Role mapping for planning roster
- ✅ `OGRH.Invites.IsPlayerInRaid()` - Used by auto-whisper logic
- ✅ `OGRH.GetActiveRaid()` - Used for guild announcements

---

## Notes

### Design Decisions

1. **Why remove per-player buttons?**
   - Invite Mode handles automated invites better
   - Reduces visual clutter
   - Aligns with "batch operation" philosophy

2. **Why clear history on import?**
   - History is raid-specific
   - New import = new raid = fresh start
   - Prevents stale data accumulation

3. **Why use Active Raid name for announcements?**
   - Single source of truth for raid identity
   - Consistent with rest of addon
   - User can change Active Raid to change announced name

4. **Why planning roster instead of direct integration?**
   - Decouples Invites from EncounterMgmt
   - Allows manual review/editing in future
   - Clear data contract between modules

### Future Enhancements

- **Multi-roster support** - Store planning rosters for multiple raids
- **Role suggestions** - Suggest roles based on class/spec
- **Attendance tracking** - Long-term history across imports
- **Advanced filtering** - Filter planning roster by class/role/group

---

## References

- [Invites.lua](../\_Configuration/Invites.lua) - Current implementation
- [! OG-RaidHelper API.md](../! OG-RaidHelper API.md) - API documentation
- [! V2 Schema Specification.md](! V2 Schema Specification.md) - Schema reference
- [! SVM-API-Documentation.md](! SVM-API-Documentation.md) - SVM usage guide

---

**Status:** Ready for implementation  
**Next Steps:** Begin Sprint 1 (Schema & Core Changes)
