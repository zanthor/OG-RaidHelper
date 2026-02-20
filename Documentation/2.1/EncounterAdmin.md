# Admin Encounter Specification

**Version:** 2.1  
**Module:** EncounterAdmin.lua  
**Location:** `_Raid/EncounterAdmin.lua`

---

## Overview

The Admin Encounter is a special encounter that is automatically added to every raid at index 1 (first position). It provides raid-wide administrative functions including loot management, disenchanting assignments, and informational fields like Discord links and Soft Reserve links.

---

## Key Features

### 1. Auto-Initialization

- **Automatic Addition:** The Admin encounter is automatically added to any raid that doesn't already have it
- **Index Position:** Always inserted at index 1, bumping all other encounters down
- **Persistence:** Once added, behaves like any other encounter but cannot be deleted through normal means
- **Not Selectable from Main UI:** While it's always index 1 it's not available with < or > buttons and does not appear in the encounter select menu.
- **Sorting Restriction:** Other encounters cannot be sorted above the Admin encounter (index 1 is reserved)

### 2. Special Role Types

The Admin encounter introduces two new role types to the OG-RaidHelper system:

#### Text Field Role
- Renders similar to a player assignment slot
- Displays a single-line text input field instead of a player dropdown
- Uses the same announcement tag system as player assignments
- Tag format: `[Rx.Px]` announces the text content of that field
- Maximum length: 200 characters
- Use cases: Discord links, SR links, loot rules text

#### Loot Settings Role
- Custom UI component for managing raid loot configuration
- Works in conjunction with Master Looter assignment
- Configuration options:
  - **Loot Method:** Master Looter or Group Loot (dropdown)
  - **Auto Switch:** Boolean toggle to automatically switch between Master for bosses and Group for trash
  - **Loot Threshold:** Uncommon, Rare, or Epic (dropdown)
- Applies settings to raid when announced or when "Apply" button is clicked
- Only functional when player is Raid Leader or Assistant

---

## Admin Encounter Role Structure

The Admin encounter contains the following roles (in order):

### Role 1: Master Looter
- **Type:** Raider Role (standard player assignment)
- **Slots:** 1
- **Raid Icons:** Disabled
- **Assignment Numbers:** Disabled
- **Default Role:** None (must be manually assigned)

### Role 2: Loot Settings
- **Type:** Custom Role (new type)
- **UI Components:**
  - Loot Method dropdown (Master Looter / Group Loot)
  - Auto Switch checkbox
  - Threshold dropdown (Uncommon / Rare / Epic)
  - Apply button (applies settings to raid)
- **Purpose:** Configure raid loot behavior

### Role 3: Disenchant
- **Type:** Raider Role (standard player assignment)
- **Slots:** 1
- **Raid Icons:** Disabled
- **Assignment Numbers:** Disabled
- **Default Role:** None (must be manually assigned)
- **Purpose:** Designates who collects and disenchants unwanted loot
- **Tag:** `[R3.P1]` for the assigned player

### Role 4: Loot Rules
- **Type:** Text Field (new type)
- **Max Length:** 200 characters
- **Purpose:** Free-form text describing loot distribution rules
- **Example Content:** "MS > OS | BiS Priority | Discord SR Required"
- **Tag:** `[R4.P1]` outputs the loot rules text

### Role 5: Bagspace Buffer
- **Type:** Raider Role (standard player assignment)
- **Slots:** 1
- **Raid Icons:** Disabled
- **Assignment Numbers:** Disabled
- **Default Role:** None (must be manually assigned)
- **Purpose:** Designates backup player for bag management during extended raids
- **Tag:** `[R5.P1]` for the assigned player

### Role 6: Discord
- **Type:** Text Field (new type)
- **Max Length:** 200 characters
- **Purpose:** Discord server invite link or server name
- **Example Content:** "discord.gg/TurtleWow"

### Role 7: SR Link
- **Type:** Text Field (new type)
- **Max Length:** 200 characters
- **Purpose:** Soft Reserve list link (SR+ or other system)
- **Example Content:** "sr.turtle-wow.com/raid/ABC123"

---

## Implementation Details

### Encounter Template

The encounter template is stored at the top of `EncounterAdmin.lua` for easy modification:

```lua
local ADMIN_ENCOUNTER_TEMPLATE = {
  name = "Admin",
  displayName = "Raid Admin",
  roles = {
    -- Role 1: Master Looter
    {
      roleId = 1,
      name = "Master Looter",
      slots = 1,
      showRaidIcons = false,
      showAssignment = false,
      markPlayer = false,
      allowOtherRoles = true,
      linkRole = false,
      invertFillOrder = false,
      assignedPlayers = {},
      raidMarks = {0},
      assignmentNumbers = {0}
    },
    -- Role 2: Loot Settings
    {
      roleId = 2,
      name = "Loot Settings",
      isLootSettings = true,  -- New flag
      lootMethod = "master",   -- "master" or "group"
      autoSwitch = false,      -- Auto-switch for trash/bosses
      threshold = "rare"       -- "uncommon", "rare", "epic"
    },
    -- Role 3: Disenchant
    {
      roleId = 3,
      name = "Disenchant",
      slots = 1,
      showRaidIcons = false,
      showAssignment = false,
      markPlayer = false,
      allowOtherRoles = true,
      linkRole = false,
      invertFillOrder = false,
      assignedPlayers = {},
      raidMarks = {0},
      assignmentNumbers = {0}
    },
    -- Role 4: Loot Rules
    {
      roleId = 4,
      name = "Loot Rules",
      isTextField = true,  -- New flag
      textValue = ""
    },
    -- Role 5: Bagspace Buffer
    {
      roleId = 5,
      name = "Bagspace Buffer",
      slots = 1,
      showRaidIcons = false,
      showAssignment = false,
      markPlayer = false,
      allowOtherRoles = true,
      linkRole = false,
      invertFillOrder = false,
      assignedPlayers = {},
      raidMarks = {0},
      assignmentNumbers = {0}
    },
    -- Role 6: Discord
    {
      roleId = 6,
      name = "Discord",
      isTextField = true,
      textValue = ""
    },
    -- Role 7: SR Link
    {
      roleId = 7,
      name = "SR Link",
      isTextField = true,
      textValue = ""
    }
  }
}
```

### Auto-Initialization Logic

```lua
function OGRH.EnsureAdminEncounter(raidIdx)
  -- Check if Admin encounter exists at index 1
  local raid = OGRH.SVM.GetPath("encounterMgmt.raids[" .. raidIdx .. "]")
  if not raid or not raid.encounters then
    return
  end
  
  -- Check if first encounter is Admin
  if table.getn(raid.encounters) > 0 and raid.encounters[1].name == "Admin" then
    return -- Admin encounter already exists
  end
  
  -- Insert Admin encounter at index 1
  local adminEncounter = OGRH.CreateAdminEncounter()
  table.insert(raid.encounters, 1, adminEncounter)
  
  -- Write back to SVM
  OGRH.SVM.SetPath("encounterMgmt.raids[" .. raidIdx .. "]", raid)
  OGRH.SVM.Save()
end
```

### Sorting Restriction

When sorting encounters, the system must prevent any encounter from being moved to index 1:

```lua
-- Prevent sorting above Admin encounter
if newIndex == 1 and encounter.name ~= "Admin" then
  OGRH.Msg("|cffff6666[RH-Admin]|r Cannot move encounters above Admin encounter")
  return false
end
```

---

## UI Rendering

### Text Field Roles

Text field roles render with a text input box instead of player slots:

```lua
if role.isTextField then
  -- Create text input box
  local textBox = CreateFrame("EditBox", nil, container)
  textBox:SetWidth(containerWidth - 10)
  textBox:SetHeight(20)
  textBox:SetBackdrop(...)
  textBox:SetText(role.textValue or "")
  
  -- Save on text change
  textBox:SetScript("OnTextChanged", function()
    role.textValue = this:GetText()
    OGRH.SaveRoleData(raidIdx, encounterIdx, roleIdx, role)
  end)
end
```

### Loot Settings Role

Loot settings role renders with specialized controls:

```lua
if role.isLootSettings then
  -- Create dropdowns and checkboxes for loot configuration
  -- Method dropdown
  local methodDropdown = CreateFrame("Frame", nil, container, "UIDropDownMenuTemplate")
  
  -- Auto Switch checkbox
  local autoSwitchCheck = CreateFrame("CheckButton", nil, container, "UICheckButtonTemplate")
  
  -- Threshold dropdown
  local thresholdDropdown = CreateFrame("Frame", nil, container, "UIDropDownMenuTemplate")
  
  -- Apply button
  local applyBtn = CreateFrame("Button", nil, container, "UIPanelButtonTemplate")
  applyBtn:SetScript("OnClick", function()
    OGRH.ApplyLootSettings(role)
  end)
end
```

---

## Announcement Tag Integration

### Text Field Tags

Text field roles use the standard player tag format but output text instead of player names:

```lua
-- In Announce.lua tag replacement
if role.isTextField then
  -- For [Rx.P1] tags on text field roles
  local textValue = role.textValue or ""
  result = string.gsub(result, "%[R" .. roleIdx .. "%.P1%]", textValue)
end
```

### Loot Settings Tags

Loot settings roles format their output as a config summary:

```lua
if role.isLootSettings then
  local methodText = (role.lootMethod == "master") and "Master Looter" or "Group Loot"
  local autoText = role.autoSwitch and " (Auto-Switch: ON)" or ""
  local thresholdText = role.threshold or "rare"
  local output = methodText .. autoText .. " | Threshold: " .. thresholdText
  
  result = string.gsub(result, "%[R" .. roleIdx .. "%.P1%]", output)
end
```

---

## API Functions

### `OGRH.CreateAdminEncounter()`
Creates a fresh Admin encounter from the template.

**Returns:** Table containing complete Admin encounter structure

**Example:**
```lua
local adminEncounter = OGRH.CreateAdminEncounter()
```

---

### `OGRH.EnsureAdminEncounter(raidIdx)`
Ensures the Admin encounter exists at index 1 of the specified raid.

**Parameters:**
- `raidIdx` (number) - Raid index in SVM

**Returns:** `nil`

**Example:**
```lua
OGRH.EnsureAdminEncounter(1)  -- Ensure Admin in Active Raid
```

---

### `OGRH.ApplyLootSettings(lootSettingsRole)`
Applies loot settings from a Loot Settings role to the raid.

**Parameters:**
- `lootSettingsRole` (table) - Role object with loot configuration

**Returns:** `boolean` - Success status

**Example:**
```lua
local role = encounter.roles[2]
OGRH.ApplyLootSettings(role)
```

---

### `OGRH.IsAdminEncounter(encounter)`
Checks if an encounter is the Admin encounter.

**Parameters:**
- `encounter` (table) - Encounter object

**Returns:** `boolean`

**Example:**
```lua
if OGRH.IsAdminEncounter(encounter) then
  -- Special handling for Admin
end
```

---

## Usage Examples

### Setting Up Admin Encounter

```lua
-- When creating a new raid
local newRaid = {
  name = "Molten Core",
  encounters = {}
}

-- Admin encounter is automatically added
OGRH.EnsureAdminEncounter(raidIdx)

-- Result: encounters[1] = Admin encounter
```

### Announcing Admin Info

```lua
-- Example announcement template
local announcement = [[
=== Raid Info ===
Master Looter: [R1.P1]
Loot Settings: [R2.P1]
Disenchant: [R3.P1]
Rules: [R4.P1]
Discord: [R6.P1]
SR: [R7.P1]
]]

OGRH.Announcements.ReplaceTags(announcement, encounter.roles, ...)
```

---

## Implementation Plan

### Status Key

- ⬜ Not started
- 🔧 In progress
- ✅ Done

---

### Phase 1: Core Data & Lifecycle (No UI)

Goal: Admin encounter exists in the data layer and survives all lifecycle events. Nothing renders yet — just prove the data is correct.

| # | Task | Status | Owner | Notes |
|---|------|--------|-------|-------|
| 1.1 | `ADMIN_ENCOUNTER_TEMPLATE` defined in `EncounterAdmin.lua` | ✅ | — | Already in codebase |
| 1.2 | `CreateAdminEncounter()` deep-copies template | ✅ | — | Already in codebase |
| 1.3 | `EnsureAdminEncounter(raidIdx)` inserts at index 1 | ✅ | — | Already in codebase |
| 1.4 | `IsAdminEncounter(encounter)` helper | ✅ | — | Already in codebase |
| 1.5 | `InitializeAdminEncounters()` runs on ADDON_LOADED for all existing raids | ✅ | — | Already in codebase |
| 1.6 | `CanMoveEncounterToIndex()` blocks non-Admin from index 1 | ✅ | — | Already in codebase |

**Phase 1 Gate:** `/ogrh test admin-data` passes (see Testing below).

---

### Phase 2: EncounterMgmt Integration

Goal: EncounterMgmt knows about the new role types and renders them. Admin encounter is invisible to the nav buttons and encounter select menu but visible in Encounter Planning.

| # | Task | Status | Owner | Notes |
|---|------|--------|-------|-------|
| 2.1 | **Navigation skip** — `NavigateToPreviousEncounter` / `NavigateToNextEncounter` skip index 1 when Admin is present. Min navigable index becomes 2. | ✅ | — | `MainUI.lua` boundary logic + init default + button enable/disable |
| 2.2 | **Encounter select menu** — `ShowEncounterRaidMenu` omits Admin encounter from the dropdown list | ✅ | — | Filter in `EncounterMgmt.lua:ShowEncounterRaidMenu` |
| 2.3 | **Render: isTextField roles** — When `EncounterMgmt` iterates roles for the Admin encounter, call `OGRH.RenderTextFieldRole()` for text-field roles instead of normal player slot rendering | ✅ | — | Branch in `CreateRoleContainer` + height calc |
| 2.4 | **Render: isLootSettings role** — Same as above but call `OGRH.RenderLootSettingsRole()` | ✅ | — | Branch in `CreateRoleContainer` + height calc |
| 2.5 | **Sorting hook** — `OGRH.CanMoveEncounterToIndex()` wired into encounter move-up/move-down in `EncounterSetup.lua` | ✅ | — | Admin pinned to index 1; non-Admin blocked from index 1 |
| 2.6 | **Delete guard** — Prevent deletion of the Admin encounter through the encounter setup UI | ✅ | — | Guard in delete callback + safety net in confirm dialog |
| 2.7 | **Column fields** — Added `column` fields to Admin template roles (1-4 left, 5-7 right) | ✅ | — | Required for column-split rendering |

**Phase 2 Gate:** Open UI → Admin does not appear in nav/select → select Admin in Encounter Planning → text fields and loot settings render and are interactive.

---

### Phase 3: Announce Integration

Goal: Announcement tags resolve correctly for new role types.

| # | Task | Status | Owner | Notes |
|---|------|--------|-------|-------|
| 3.1 | **Tag replacement: isTextField** — In `Announce.lua:ReplaceTags`, detect text-field roles and substitute `[Rx.P1]` with `role.textValue` | ✅ | — | Add branch before normal player lookup |
| 3.2 | **Tag replacement: isLootSettings** — Substitute `[Rx.P1]` with `OGRH.GetLootSettingsText(role)` output | ✅ | — | Same area |
| 3.3 | **Announce apply** — When Admin encounter is announced, also call `OGRH.ApplyLootSettings()` for the loot settings role | ✅ | — | In `SendEncounterAnnouncement` or a hook |

**Phase 3 Gate:** `/ogrh test admin-announce` — build a test announcement string, run `ReplaceTags`, verify output contains expected text values and loot summary.

---

### Phase 4: Loot Settings Runtime

Goal: Loot method actually changes in-game, auto-switch works during encounters.

| # | Task | Status | Owner | Notes |
|---|------|--------|-------|-------|
| 4.1 | `ApplyLootSettings()` calls `SetLootMethod` / `SetLootThreshold` | ✅ | — | Already in codebase |
| 4.2 | **Auto-switch hook** — If `autoSwitch` is true, listen for boss-pull / boss-kill events to toggle between master and group loot | ✅ | — | Needs event wiring; could piggyback on BigWigs integration or `PLAYER_REGEN_DISABLED` / `PLAYER_REGEN_ENABLED` |
| 4.3 | **Permission enforcement** — `ApplyLootSettings` verifies RL/RA before calling WoW APIs | ✅ | — | Already in codebase |

**Phase 4 Gate:** Manual in-raid test — apply settings, check `/loot`, toggle auto-switch with a target dummy or trash pack.

---

### Phase 5: Sync & Persistence

Goal: Admin encounter data syncs to raid members and survives `/reload`.

| # | Task | Status | Owner | Notes |
|---|------|--------|-------|-------|
| 5.1 | **SVM metadata on text field save** — `SetPath` calls include correct `syncLevel`, `componentType`, and `scope.isActiveRaid` | ✅ | — | Audit all `SVM.SetPath` calls in EncounterAdmin rendering |
| 5.2 | **SVM metadata on loot settings save** — Same for loot method, autoSwitch, threshold | ✅ | — | Same |
| 5.3 | **Receiver-side rendering** — Non-admin raid members receive synced Admin encounter and render it read-only (text fields disabled, Apply hidden unless RL/RA) | ✅ | — | Permission check in render functions |
| 5.4 | ** /reload persistence** — Verify `EnsureAdminEncounter` doesn't duplicate or reset data on reload when the Admin encounter already exists | ✅ | — | Already handled by name check, but verify text/loot values survive |

**Phase 5 Gate:** Two-box test — make changes on leader, verify they appear on synced client after sync interval.

---

### Implementation Order & Dependencies

```
Phase 1 (done) ─► Phase 2 ─► Phase 3
                      │
                      └──► Phase 4
                              │
               Phase 2 + 3 ──► Phase 5
```

Phases 2 and 3 can be worked in parallel. Phase 4 can start as soon as Phase 2 rendering works. Phase 5 depends on everything else being functional.

---

## Testing Procedures

All tests follow the WoW 1.12 pattern: loaded via TOC, executed via `/ogrh test <name>`.

### Test File: `Tests/test_admin.lua`

Register under the existing test infrastructure in `MainUI.lua`:

```lua
-- /ogrh test admin       → runs all admin tests
-- /ogrh test admin-data  → Phase 1 only
-- /ogrh test admin-nav   → Phase 2 nav logic
-- /ogrh test admin-announce → Phase 3 tag replacement
```

---

### Phase 1 Tests — Data Layer (`/ogrh test admin-data`)

```
TEST 1.1  CreateAdminEncounter returns valid table
          → assert: result.name == "Admin"
          → assert: table.getn(result.roles) == 7
          → assert: result.roles[2].isLootSettings == true
          → assert: result.roles[4].isTextField == true

TEST 1.2  Deep copy isolation
          → local a = CreateAdminEncounter()
          → local b = CreateAdminEncounter()
          → a.roles[4].textValue = "modified"
          → assert: b.roles[4].textValue == ""

TEST 1.3  EnsureAdminEncounter adds to empty raid
          → Create temp raid with 0 encounters
          → Call EnsureAdminEncounter
          → assert: encounters[1].name == "Admin"

TEST 1.4  EnsureAdminEncounter is idempotent
          → Call EnsureAdminEncounter twice on same raid
          → assert: table.getn(encounters) has not changed
          → assert: encounters[1].name == "Admin"

TEST 1.5  EnsureAdminEncounter preserves existing encounters
          → Create raid with 2 encounters ("Boss1", "Boss2")
          → Call EnsureAdminEncounter
          → assert: encounters[1].name == "Admin"
          → assert: encounters[2].name == "Boss1"
          → assert: encounters[3].name == "Boss2"

TEST 1.6  CanMoveEncounterToIndex blocks non-Admin to index 1
          → assert: CanMoveEncounterToIndex(2, 1, {name="Boss"}) == false
          → assert: CanMoveEncounterToIndex(1, 1, {name="Admin"}) == true
          → assert: CanMoveEncounterToIndex(2, 3, {name="Boss"}) == true

TEST 1.7  IsAdminEncounter
          → assert: IsAdminEncounter({name="Admin"}) == true
          → assert: IsAdminEncounter({name="Ragnaros"}) == false
          → assert: IsAdminEncounter(nil) == false
```

---

### Phase 2 Tests — UI Integration (Manual + `/ogrh test admin-nav`)

#### Automated

```
TEST 2.1  Nav boundaries skip Admin encounter
          → Set selectedEncounterIndex = 2
          → Call NavigateToPreviousEncounter
          → assert: selectedEncounterIndex == 2 (should not go to 1)

TEST 2.2  Nav forward from last encounter stays put
          → Set selectedEncounterIndex = table.getn(encounters)
          → Call NavigateToNextEncounter
          → assert: selectedEncounterIndex unchanged
```

#### Manual Checklist

```
☐ 2.3  Open encounter planning → Admin does NOT appear in nav buttons
☐ 2.4  Open encounter select menu → Admin is NOT listed
☐ 2.5  Navigate to encounter 2 (first real boss) → press "<" → stays on encounter 2
☐ 2.6  Manually force index 1 → text fields render with label and edit box
☐ 2.7  Manually force index 1 → loot settings render: method toggle, auto-switch checkbox, threshold cycle, apply button
☐ 2.8  Try to delete Admin encounter via setup UI → blocked with message
☐ 2.9  Try to sort another encounter above Admin → blocked with message
```

---

### Phase 3 Tests — Announcements (`/ogrh test admin-announce`)

```
TEST 3.1  TextField tag replacement
          → Set role 4 textValue = "MS > OS"
          → Run ReplaceTags with "[R4.P1]"
          → assert: output == "MS > OS"

TEST 3.2  Empty TextField tag replacement
          → Set role 6 textValue = ""
          → Run ReplaceTags with "Discord: [R6.P1]"
          → assert: output == "Discord: "

TEST 3.3  LootSettings tag replacement
          → Set role 2: lootMethod="master", autoSwitch=true, threshold="epic"
          → Run ReplaceTags with "[R2.P1]"
          → assert: output contains "Master Looter"
          → assert: output contains "Auto-Switch: ON"
          → assert: output contains "Epic"

TEST 3.4  Mixed tags in one string
          → Template: "ML: [R1.P1] | Rules: [R4.P1] | SR: [R7.P1]"
          → Set role 1 assignedPlayers = {"Tankguy"}
          → Set role 4 textValue = "BiS Prio"
          → Set role 7 textValue = "sr.example.com/123"
          → Run ReplaceTags
          → assert: output == "ML: Tankguy | Rules: BiS Prio | SR: sr.example.com/123"
```

---

### Phase 4 Tests — Loot Settings Runtime (Manual, in-raid)

```
☐ 4.1  As RL: Apply loot settings with method = master → /loot shows Master Looter
☐ 4.2  As RL: Apply loot settings with method = group → /loot shows Group Loot
☐ 4.3  As RL: Apply threshold = epic → verify green items are FFA
☐ 4.4  As non-RL/RA: Apply button shows error message, no loot change
☐ 4.5  Not in raid: Apply button shows "Not in a raid" message
☐ 4.6  Auto-switch ON: Pull boss → loot switches to master; exit combat → loot switches to group
        (deferred if BigWigs integration not ready — can test with PLAYER_REGEN events)
```

---

### Phase 5 Tests — Sync & Persistence (Two-box, manual)

```
☐ 5.1  Leader sets Master Looter assignment → synced client shows name in slot
☐ 5.2  Leader types Discord link → synced client sees text in read-only field
☐ 5.3  Leader changes loot method toggle → synced client shows updated toggle state
☐ 5.4  /reload on leader → Admin encounter still at index 1, all field values intact
☐ 5.5  /reload on synced client → Admin encounter present, values match leader
☐ 5.6  Non-RL/RA client → text fields are read-only, Apply button hidden or disabled
☐ 5.7  Create brand new raid on leader → synced client receives Admin at index 1
```

---

### Regression Watchlist

These existing features must not break during implementation:

- Normal encounter navigation (< > buttons) for non-Admin encounters
- Encounter select dropdown for non-Admin encounters
- Normal role rendering (player assignment slots)
- Existing announcement tag replacement (`[Rx.Py]`, `[Rx.T]`, `[Rx.P]`, `[Rx.PA]`)
- Encounter sorting for non-Admin encounters
- Encounter export/import (Admin encounter should be excluded or handled gracefully)
- Sync of normal encounter data

---

## Related Modules

- **EncounterMgmt.lua:** Encounter rendering and UI — needs role-type branching (Phase 2)
- **MainUI.lua:** Navigation boundary logic — needs Admin skip (Phase 2)
- **Announce.lua:** Tag replacement system — needs text/loot role branches (Phase 3)
- **EncounterSetup.lua:** Role editor — needs delete guard (Phase 2)

---

## Change Log

| Version | Date | Changes |
|---------|------|---------|
| 2.1.0 | Feb 2026 | Initial Admin encounter spec + implementation plan |

