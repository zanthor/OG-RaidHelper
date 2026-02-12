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
- **Purpose:** Designates who will handle master looting
- **Tag:** `[R1.P1]` for the assigned player

### Role 2: Loot Settings
- **Type:** Custom Role (new type)
- **UI Components:**
  - Loot Method dropdown (Master Looter / Group Loot)
  - Auto Switch checkbox
  - Threshold dropdown (Uncommon / Rare / Epic)
  - Apply button (applies settings to raid)
- **Purpose:** Configure raid loot behavior
- **Announcement:** Announces current loot configuration when `[R2.P1]` tag is used
- **Tag Format:** `[R2.P1]` outputs formatted loot settings text

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
- **Tag:** `[R6.P1]` outputs the Discord link/info

### Role 7: SR Link
- **Type:** Text Field (new type)
- **Max Length:** 200 characters
- **Purpose:** Soft Reserve list link (SR+ or other system)
- **Example Content:** "sr.turtle-wow.com/raid/ABC123"
- **Tag:** `[R7.P1]` outputs the SR link

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

## Testing Considerations

### Test Cases

1. **Auto-Add:** Verify Admin encounter is added when creating new raid
2. **Position Lock:** Attempt to sort another encounter to index 1
3. **Text Fields:** Verify text input saves and announces correctly
4. **Loot Settings:** Test applying loot settings to raid
5. **Tag Replacement:** Verify all tags output correct values
6. **Persistence:** Verify Admin encounter persists across sessions

### Edge Cases

- What happens if user manually deletes Admin encounter?
- How to handle migrations from raids without Admin encounter?
- Text field max length enforcement
- Loot settings when not Raid Leader

---

## Future Enhancements

- **Admin Permissions:** Restrict Admin encounter editing to Raid Admin only
- **Templates:** Allow saving/loading Admin encounter templates
- **Quick Apply:** Button to apply all Admin settings at once
- **Validation:** Warn if Master Looter is not assigned
- **History:** Track changes to loot settings
- **Multi-Language:** Support for localized role names

---

## Related Modules

- **EncounterMgmt.lua:** Encounter rendering and UI
- **Announce.lua:** Tag replacement system
- **EncounterSetup.lua:** Role editor integration

---

## Change Log

| Version | Date | Changes |
|---------|------|---------|
| 2.1.0 | Feb 2026 | Initial Admin encounter implementation |

