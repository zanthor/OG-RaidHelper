# OG-RaidHelper: Advanced Encounter Settings Design

**Version:** 1.0 (January 2026)  
**Status:** Design Phase  
**Target Module:** OGRH_EncounterSetup.lua

---

## Overview

This document defines the design for adding Advanced Encounter Settings to OG-RaidHelper. These settings will provide per-encounter configuration for BigWigs integration and consume tracking requirements.

---

## Feature Requirements

### 1. UI Access Point

**Location:** Encounter Planning window (shown via `/ogrh planning` or menu)

**Access Method:**
- Add a settings icon (📋 notepad icon) next to each **raid name** in the Raids list (top-left panel)
- Add a settings icon (📋 notepad icon) next to each **encounter name** in the Encounters list (bottom-left panel)
- Position: To the right of the raid/encounter name, inline with the text
- Icon style: Same size and styling as the existing edit icons (📋 notepad) used for individual roles - using INV_Misc_Note_01 texture
- Tooltips:
  - Raid level: "Raid-Wide Settings"
  - Encounter level: "Encounter Settings"

**Visual Reference:**
```
┌─ Raids: ─────────────────────────┐
│ MC                          [📋]  │  <- Raid-wide settings
│ BWL                         [📋]  │
│ AQ40                        [📋]  │
│ Naxx                        [📋]  │
└──────────────────────────────────┘

┌─ Encounters: ────────────────────┐
│ Tanks and Heals             [📋]  │  <- Encounter settings
│ Incindis                    [📋]  │
│ Lucifron                    [📋]  │
│ Magmadar                    [📋]  │
│ Golem Twins                 [📋]  │
└──────────────────────────────────┘

Note: [📋] = Settings icon (using notepad texture, same as role editor)
      This is the ONLY icon at raid/encounter level
      No other edit functionality exists at this level
```

### 2. Advanced Settings Dialog

**Dialog Properties:**
- Window Title: 
  - Raid level: "Raid-Wide Settings: [Raid Name]"
  - Encounter level: "Encounter Settings: [Encounter Name]"
- Size: 500w x 450h
- Modal: No (can have both Planning and Advanced Settings open)
- Resizable: No
- Close on ESC: Yes
- Frame Type: Standard OGST window

**Dialog Layout (Encounter-Specific):**

```
┌─ Encounter Settings: Tanks and Heals ─────────────── [Close] ─┐
│                                                                 │
│  BigWigs Encounter Detection                                   │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │ ☑ Enable BigWigs Auto-Select                              │ │
│  │                                                            │ │
│  │   BigWigs Encounter ID: [___________] [?]                 │ │
│  │                                                            │ │
│  │   ⓘ When BigWigs detects this encounter, OGRH will        │ │
│  │     automatically select this raid/encounter.             │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
│  Consume Tracking Requirements                                 │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │ ☑ Enable Consume Tracking                                 │ │
│  │                                                            │ │
│  │   Ready Threshold: [___85___] %                           │ │
│  │                                                            │ │
│  │   Flask Requirements (by Role):                           │ │
│  │   ┌─────────────────────────────────────────────────────┐ │ │
│  │   │ ☑ Tanks                                             │ │ │
│  │   │ ☑ Healers                                           │ │ │
│  │   │ ☐ Melee                                             │ │ │
│  │   │ ☐ Ranged                                            │ │ │
│  │   └─────────────────────────────────────────────────────┘ │ │
│  │                                                            │ │
│  │   ⓘ Only roles checked will be required to have flasks   │ │
│  │     for raid readiness checks.                           │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
│                                      [Cancel]  [Save Changes]  │
└─────────────────────────────────────────────────────────────────┘
```

**Dialog Layout (Raid-Wide Defaults):**

```
┌─ Raid-Wide Settings: MC ──────────────────────────── [Close] ─┐
│                                                                 │
│  Consume Tracking Requirements                                 │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │ ☑ Enable Consume Tracking                                 │ │
│  │                                                            │ │
│  │   Ready Threshold: [___85___] %                           │ │
│  │                                                            │ │
│  │   Flask Requirements (by Role):                           │ │
│  │   ┌─────────────────────────────────────────────────────┐ │ │
│  │   │ ☑ Tanks                                             │ │ │
│  │   │ ☑ Healers                                           │ │ │
│  │   │ ☐ Melee                                             │ │ │
│  │   │ ☐ Ranged                                            │ │ │
│  │   └─────────────────────────────────────────────────────┘ │ │
│  │                                                            │ │
│  │   ⓘ Only roles checked will be required to have flasks   │ │
│  │     for raid readiness checks.                           │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
│  ⓘ Raid-wide settings apply to all encounters in this raid    │
│    unless overridden. BigWigs detection is encounter-specific. │
│                                                                 │
│                                      [Cancel]  [Save Changes]  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Data Structures

### SavedVariables Extension

Add `advancedSettings` table at both raid and encounter levels:

```lua
-- Current structure (in OGRH_SV.encounterMgmt):
OGRH_SV.encounterMgmt = {
    raids = {
        {
            name = "MC",
            -- NEW: Add raid-wide default settings
            advancedSettings = {
                consumeTracking = {
                    enabled = false,
                    readyThreshold = 85,
                    requiredFlaskRoles = {
                        ["Tanks"] = false,
                        ["Healers"] = false,
                        ["Melee"] = false,
                        ["Ranged"] = false,
                    }
                }
                -- Note: BigWigs is encounter-specific only
            },
            encounters = {
                {
                    name = "Tanks and Heals",
                    roles = {...},
                    -- NEW: Add encounter-specific settings
                    advancedSettings = {
                        -- BigWigs Integration (encounter-specific only)
                        bigwigs = {
                            enabled = false,
                            encounterId = "",  -- e.g., "486" for Garr, "Lucifron", etc.
                        },
                        -- Consume Tracking (can override raid defaults)
                        consumeTracking = {
                            enabled = false,  -- nil = inherit from raid, true/false = override
                            readyThreshold = 85,  -- nil = inherit from raid, number = override
                            requiredFlaskRoles = {
                                -- Key = RolesUI role name (Tanks, Healers, Melee, Ranged)
                                -- Value = boolean (true = requires flasks)
                                ["Tanks"] = true,
                                ["Healers"] = true,
                                ["Melee"] = false,
                                ["Ranged"] = false,
                            }
                        }
                    }
                }
            }
        }
    }
}
```

### Default Values

When creating a new raid, encounter, or upgrading existing data:

```lua
-- Raid-wide defaults
local DEFAULT_RAID_SETTINGS = {
    consumeTracking = {
        enabled = false,
        readyThreshold = 85,
        requiredFlaskRoles = {
            ["Tanks"] = false,
            ["Healers"] = false,
            ["Melee"] = false,
            ["Ranged"] = false,
        }
    }
}

-- Encounter-specific defaults
local DEFAULT_ENCOUNTER_SETTINGS = {
    bigwigs = {
        enabled = false,
        encounterId = ""
    },
    consumeTracking = {
        enabled = nil,  -- nil = inherit from raid
        readyThreshold = nil,  -- nil = inherit from raid
        requiredFlaskRoles = {}
    }
}
```

---

## Implementation Plan

### Phase 1: File Creation & TOC Updates

Before implementing any functionality, create all necessary files and update the TOC to minimize client reboots during development.

#### 1.0 Create Empty Files

Create the following empty files in the addon directory:

**New File: OGRH_BigWigs.lua**
```lua
-- OGRH_BigWigs.lua
-- BigWigs encounter detection integration
-- Implementation: Phase 3

OGRH.BigWigs = OGRH.BigWigs or {}
```

**New File: OGRH_AdvancedSettings.lua**
```lua
-- OGRH_AdvancedSettings.lua
-- Advanced settings UI dialogs for raids and encounters
-- Implementation: Phase 2

-- Dialog functions will be added here
```

#### 1.0.1 Update OG-RaidHelper.toc

Add the new files to `OG-RaidHelper.toc` in the appropriate sections:

```
## Interface: 11200
## Title: OG-RaidHelper
## Notes: Raid management and coordination tool
## Author: OG Team
## Version: 1.0.0
## SavedVariables: OGRH_SV
## Dependencies: _OGST

# Core
OGRH_Core.lua
OGRH_Sync.lua
OGRH_Share.lua
OGRH_FactoryDefaults.lua

# Encounter Management
OGRH_EncounterSetup.lua
OGRH_AdvancedSettings.lua

# Integrations
OGRH_BigWigs.lua

# UI Components
OGRH_ConsumesTracking.lua
OGRH_RolesUI.lua
OGRH_RGO_Roster.lua
OGRH_RGO_ClassPriority.lua
```

**Note:** After making TOC changes, reload the WoW client ONCE. All subsequent development in Phases 2-4 can be done with `/reload` commands.

---

### Phase 2: Data Layer (OGRH_EncounterSetup.lua)

#### 2.1 Initialize Advanced Settings

Add functions to ensure advanced settings exist at both raid and encounter levels:

```lua
-- Ensure raid has advanced settings structure
function OGRH.EnsureRaidAdvancedSettings(raid)
    if not raid.advancedSettings then
        raid.advancedSettings = {
            consumeTracking = {
                enabled = false,
                readyThreshold = 85,
                requiredFlaskRoles = {
                    ["Tanks"] = false,
                    ["Healers"] = false,
                    ["Melee"] = false,
                    ["Ranged"] = false,
                }
            }
        }
    end
    
    -- Ensure sub-tables exist (for upgrades)
    if not raid.advancedSettings.consumeTracking then
        raid.advancedSettings.consumeTracking = {
            enabled = false,
            readyThreshold = 85,
            requiredFlaskRoles = {
                ["Tanks"] = false,
                ["Healers"] = false,
                ["Melee"] = false,
                ["Ranged"] = false,
            }
        }
    end
    
    -- Ensure requiredFlaskRoles exists
    if not raid.advancedSettings.consumeTracking.requiredFlaskRoles then
        raid.advancedSettings.consumeTracking.requiredFlaskRoles = {
            ["Tanks"] = false,
            ["Healers"] = false,
            ["Melee"] = false,
            ["Ranged"] = false,
        }
    end
end

-- Ensure encounter has advanced settings structure
function OGRH.EnsureEncounterAdvancedSettings(raid, encounter)
    if not encounter.advancedSettings then
        encounter.advancedSettings = {
            bigwigs = {
                enabled = false,
                encounterId = ""
            },
            consumeTracking = {
                enabled = nil,  -- nil = inherit from raid
                readyThreshold = nil,  -- nil = inherit from raid
                requiredFlaskRoles = {}
            }
        }
    end
    
    -- Ensure sub-tables exist (for upgrades)
    if not encounter.advancedSettings.bigwigs then
        encounter.advancedSettings.bigwigs = {
            enabled = false,
            encounterId = ""
        }
    end
    
    if not encounter.advancedSettings.consumeTracking then
        encounter.advancedSettings.consumeTracking = {
            enabled = nil,
            readyThreshold = nil,
            requiredFlaskRoles = {}
        }
    end
end
```

Call this function in:
- `OGRH.ShowEncounterSetup()` when loading an encounter
- `StaticPopupDialogs["OGRH_ADD_ENCOUNTER"].OnAccept` when creating new encounter
- Any encounter load/select function

#### 2.2 Get/Set Functions

```lua
-- Get advanced settings for currently selected encounter
function OGRH.GetCurrentEncounterAdvancedSettings()
    local frame = OGRH_EncounterSetupFrame
    if not frame or not frame.selectedRaid or not frame.selectedEncounter then
        return nil
    end
    
    local raid = OGRH.FindRaidByName(frame.selectedRaid)
    if not raid then return nil end
    
    local encounter = OGRH.FindEncounterByName(raid, frame.selectedEncounter)
    if not encounter then return nil end
    
    OGRH.EnsureEncounterAdvancedSettings(raid, encounter)
    return encounter.advancedSettings
end

-- Save advanced settings for currently selected encounter
function OGRH.SaveCurrentEncounterAdvancedSettings(settings)
    local frame = OGRH_EncounterSetupFrame
    if not frame or not frame.selectedRaid or not frame.selectedEncounter then
        return false
    end
    
    local raid = OGRH.FindRaidByName(frame.selectedRaid)
    if not raid then return false end
    
    local encounter = OGRH.FindEncounterByName(raid, frame.selectedEncounter)
    if not encounter then return false end
    
    encounter.advancedSettings = settings
    return true
end
```

### Phase 3: UI Layer (OGRH_EncounterSetup.lua & OGRH_AdvancedSettings.lua)

#### 3.1 Add Settings Icon to Raid List Items

In `OGRH.ShowEncounterSetup()`, within the `RefreshRaidsList()` function where raid list items are created:

```lua
-- Inside RefreshRaidsList(), when creating each raid list item:

-- After creating the item button and setting up click handler, add settings button

-- Settings button (notepad icon, right side of raid item)
local settingsBtn = CreateFrame("Button", nil, item)
settingsBtn:SetWidth(16)
settingsBtn:SetHeight(16)
settingsBtn:SetPoint("RIGHT", item, "RIGHT", -5, 0)

-- Use notepad icon texture (same as role editor)
local settingsIcon = settingsBtn:CreateTexture(nil, "ARTWORK")
settingsIcon:SetAllPoints()
settingsIcon:SetTexture("Interface\\Icons\\INV_Misc_Note_01")
settingsIcon:SetTexCoord(0.1, 0.9, 0.1, 0.9)  -- Crop edges

settingsBtn:SetScript("OnEnter", function()
    settingsIcon:SetVertexColor(1, 1, 0.5)  -- Yellow tint
    GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
    GameTooltip:SetText("Raid-Wide Settings")
    GameTooltip:AddLine("Configure default settings for all encounters", 1, 1, 1, 1)
    GameTooltip:Show()
end)

settingsBtn:SetScript("OnLeave", function()
    settingsIcon:SetVertexColor(1, 1, 1)  -- Reset tint
    GameTooltip:Hide()
end)

settingsBtn:SetScript("OnClick", function()
    -- Set this raid as selected first
    frame.selectedRaid = raid.name
    frame.RefreshRaidsList()
    frame.RefreshEncountersList()
    
    -- Show raid-wide settings dialog
    OGRH.ShowRaidSettingsDialog()
end)

-- Store reference for potential updates
item.settingsBtn = settingsBtn
```

#### 3.2 Add Settings Icon to Encounter List Items

In `OGRH.ShowEncounterSetup()`, within the `RefreshEncountersList()` function where encounter list items are created:

```lua
-- Inside RefreshEncountersList(), when creating each encounter list item:

-- After creating the item button and setting up click handler, add settings button

-- Settings button (notepad icon, right side of encounter item)
local settingsBtn = CreateFrame("Button", nil, item)
settingsBtn:SetWidth(16)
settingsBtn:SetHeight(16)
settingsBtn:SetPoint("RIGHT", item, "RIGHT", -5, 0)

-- Use notepad icon texture (same as role editor)
local settingsIcon = settingsBtn:CreateTexture(nil, "ARTWORK")
settingsIcon:SetAllPoints()
settingsIcon:SetTexture("Interface\\Icons\\INV_Misc_Note_01")
settingsIcon:SetTexCoord(0.1, 0.9, 0.1, 0.9)  -- Crop edges

settingsBtn:SetScript("OnEnter", function()
    settingsIcon:SetVertexColor(1, 1, 0.5)  -- Yellow tint
    GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
    GameTooltip:SetText("Encounter Settings")
    GameTooltip:AddLine("Configure BigWigs detection and consume requirements", 1, 1, 1, 1)
    GameTooltip:Show()
end)

settingsBtn:SetScript("OnLeave", function()
    settingsIcon:SetVertexColor(1, 1, 1)  -- Reset tint
    GameTooltip:Hide()
end)

settingsBtn:SetScript("OnClick", function()
    -- Set this encounter as selected first
    frame.selectedEncounter = encounter.name
    frame.RefreshEncountersList()
    frame.RefreshRolesList()
    
    -- Then show settings dialog
    OGRH.ShowAdvancedSettingsDialog()
end)

-- Store reference for potential updates
item.settingsBtn = settingsBtn
```

#### 3.3 Create Raid-Wide Settings Dialog

Move to new file `OGRH_AdvancedSettings.lua`. Create new function `OGRH.ShowRaidSettingsDialog()`:

```lua
function OGRH.ShowRaidSettingsDialog()
    -- Get current raid settings
    local frame = OGRH_EncounterSetupFrame
    if not frame or not frame.selectedRaid then
        OGRH.Msg("Please select a raid first.")
        return
    end
    
    local raid = OGRH.FindRaidByName(frame.selectedRaid)
    if not raid then
        OGRH.Msg("Raid not found.")
        return
    end
    
    OGRH.EnsureRaidAdvancedSettings(raid)
    local settings = raid.advancedSettings
    
    -- Create or reuse dialog (identical to encounter dialog but without BigWigs section)
    if not OGRH_RaidSettingsFrame then
        -- ... create dialog identical to encounter dialog ...
        -- Include consume tracking section with checkboxes and flask requirements
        -- Exclude BigWigs section entirely
        OGRH_RaidSettingsFrame = dialog
    end
    
    local dialog = OGRH_RaidSettingsFrame
    
    -- Load settings and show
    dialog.titleText:SetText("Raid-Wide Settings: " .. raid.name)
    dialog.consumeCheck:SetChecked(settings.consumeTracking.enabled or false)
    dialog.thresholdInput:SetText(tostring(settings.consumeTracking.readyThreshold or 85))
    
    -- Load flask role checkboxes
    OGRH.RefreshFlaskRolesList(dialog, settings)
    
    dialog:Show()
end
```

#### 3.4 Create Encounter Settings Dialog

In `OGRH_AdvancedSettings.lua`, create new function `OGRH.ShowAdvancedSettingsDialog()`:

```lua
function OGRH.ShowAdvancedSettingsDialog()
    -- Get current encounter settings
    local settings = OGRH.GetCurrentEncounterAdvancedSettings()
    if not settings then
        OGRH.Msg("Please select an encounter first.")
        return
    end
    
    local frame = OGRH_EncounterSetupFrame
    local encounterName = frame.selectedEncounter or "Unknown"
    
    -- Create or reuse dialog frame using OGST
    if not OGRH_AdvancedSettingsFrame then
        local dialog = OGST.CreateStandardWindow({
            name = "OGRH_AdvancedSettingsFrame",
            width = 500,
            height = 450,
            title = "Encounter Settings: " .. encounterName,
            closeButton = true,
            escapeCloses = true,
            resizable = false
        })
        
        local content = dialog.contentFrame
        
        -- === BigWigs Section ===
        local bigwigsHeader = OGST.CreateStaticText(content, {
            text = "BigWigs Encounter Detection",
            font = "GameFontNormalLarge",
            color = {r = 1, g = 1, b = 1},
            width = 460
        })
        
        -- BigWigs section background panel
        local bigwigsPanel = OGST.CreateColoredPanel(content, 460, 120,
            {r = 1, g = 1, b = 1},  -- White border
            {r = 0.1, g = 0.1, b = 0.1, a = 0.8})  -- Dark background
        OGST.AnchorElement(bigwigsPanel, bigwigsHeader, {position = "below", gap = 5})
        
        -- Enable checkbox
        local bigwigsCheckContainer, bigwigsCheck, bigwigsCheckLabel = OGST.CreateCheckbox(bigwigsPanel, {
            label = "Enable BigWigs Auto-Select",
            labelAnchor = "RIGHT",
            checked = false
        })
        OGST.AnchorElement(bigwigsCheckContainer, bigwigsPanel, {
            position = "below",
            gap = 10,
            offsetX = 10,
            offsetY = -10
        })
        dialog.bigwigsCheck = bigwigsCheck
        
        -- Encounter ID input with label
        local encounterIdBackdrop, encounterIdBox, encounterIdLabel = OGST.CreateSingleLineTextBox(bigwigsPanel, 200, 24, {
            label = "BigWigs Encounter ID:",
            labelAnchor = "LEFT",
            maxLetters = 50,
            align = "LEFT"
        })
        OGST.AnchorElement(encounterIdBackdrop, bigwigsCheckContainer, {position = "below", gap = 10})
        dialog.encounterIdBox = encounterIdBox
        
        -- Description text
        local bigwigsDesc = OGST.CreateStaticText(bigwigsPanel, {
            text = "When enabled, OG-RaidHelper will automatically select this encounter when BigWigs detects the specified boss encounter. The encounter will be auto-selected but the Roles UI will not be opened automatically.",
            font = "GameFontHighlightSmall",
            color = {r = 0.7, g = 0.7, b = 1},
            width = 440,
            multiline = true
        })
        OGST.AnchorElement(bigwigsDesc, encounterIdBackdrop, {position = "below", gap = 5})
        
        -- === Consume Tracking Section ===
        local consumeHeader = OGST.CreateStaticText(content, {
            text = "Consume Tracking Requirements",
            font = "GameFontNormalLarge",
            color = {r = 1, g = 1, b = 1},
            width = 460
        })
        OGST.AnchorElement(consumeHeader, bigwigsPanel, {position = "below", gap = 15})
        
        -- Consume section background panel
        local consumePanel = OGST.CreateColoredPanel(content, 460, 220,
            {r = 1, g = 1, b = 1},  -- White border
            {r = 0.1, g = 0.1, b = 0.1, a = 0.8})  -- Dark background
        OGST.AnchorElement(consumePanel, consumeHeader, {position = "below", gap = 5})
        
        -- Enable consume tracking checkbox
        local consumeCheckContainer, consumeCheck, consumeCheckLabel = OGST.CreateCheckbox(consumePanel, {
            label = "Enable Consume Tracking",
            labelAnchor = "RIGHT",
            checked = false
        })
        OGST.AnchorElement(consumeCheckContainer, consumePanel, {
            position = "below",
            gap = 10,
            offsetX = 10,
            offsetY = -10
        })
        dialog.consumeCheck = consumeCheck
        
        -- Ready Threshold input with label
        local thresholdBackdrop, thresholdInput, thresholdLabel = OGST.CreateSingleLineTextBox(consumePanel, 50, 24, {
            label = "Ready Threshold (%):",
            labelAnchor = "LEFT",
            maxLetters = 3,
            numeric = true,
            align = "CENTER"
        })
        OGST.AnchorElement(thresholdBackdrop, consumeCheckContainer, {position = "below", gap = 10})
        dialog.thresholdInput = thresholdInput
        
        -- Flask Requirements label
        local flaskLabel = OGST.CreateStaticText(consumePanel, {
            text = "Flask Requirements (by Role):",
            font = "GameFontNormal",
            color = {r = 1, g = 0.82, b = 0},
            width = 420
        })
        OGST.AnchorElement(flaskLabel, thresholdBackdrop, {position = "below", gap = 10})
        
        -- Role checkboxes scroll list
        local rolesListFrame, rolesScrollFrame, rolesScrollChild, rolesScrollBar = 
            OGST.CreateStyledScrollList(consumePanel, 420, 80, false)
        OGST.AnchorElement(rolesListFrame, flaskLabel, {position = "below", gap = 5})
        dialog.rolesScrollChild = rolesScrollChild
        dialog.flaskRoleCheckboxes = {}
        
        -- Info text
        local consumeInfo = OGST.CreateStaticText(consumePanel, {
            text = "ⓘ Only roles checked will be required to have flasks for raid readiness checks.",
            font = "GameFontHighlightSmall",
            color = {r = 0.7, g = 0.7, b = 1},
            width = 440,
            multiline = true
        })
        OGST.AnchorElement(consumeInfo, rolesListFrame, {position = "below", gap = 5})
        
        -- Bottom buttons
        local cancelBtn = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
        cancelBtn:SetWidth(80)
        cancelBtn:SetHeight(24)
        cancelBtn:SetText("Cancel")
        OGST.StyleButton(cancelBtn)
        OGST.AnchorElement(cancelBtn, dialog, {
            position = "below",
            gap = -70,
            offsetX = -175
        })
        cancelBtn:SetScript("OnClick", function() dialog:Hide() end)
        
        local saveBtn = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
        saveBtn:SetWidth(120)
        saveBtn:SetHeight(24)
        saveBtn:SetText("Save Changes")
        OGST.StyleButton(saveBtn)
        OGST.AnchorElement(saveBtn, cancelBtn, {position = "right", gap = 5})
        dialog.saveBtn = saveBtn
        
        saveBtn:SetScript("OnClick", function()
            OGRH.SaveAdvancedSettingsDialog()
        end)
        
        OGRH_AdvancedSettingsFrame = dialog
    end
    
    local dialog = OGRH_AdvancedSettingsFrame
    
    -- Update title
    dialog.titleText:SetText("Advanced Settings: " .. encounterName)
    
    -- Load settings into UI
    dialog.bigwigsCheck:SetChecked(settings.bigwigs.enabled or false)
    dialog.encounterIdBox:SetText(settings.bigwigs.encounterId or "")
    
    dialog.consumeCheck:SetChecked(settings.consumeTracking.enabled or false)
    dialog.thresholdInput:SetText(tostring(settings.consumeTracking.readyThreshold or 85))
    
    -- Build role checkboxes from current encounter roles
    OGRH.RefreshFlaskRolesList(dialog, settings)
    
    dialog:Show()
end
```

#### 3.5 Refresh Flask Roles List

```lua
-- Build checkboxes for flask requirements based on RolesUI roles
function OGRH.RefreshFlaskRolesList(dialog, settings)
    local scrollChild = dialog.rolesScrollChild
    
    -- Clear existing checkboxes
    if dialog.flaskRoleCheckboxes then
        for _, cb in pairs(dialog.flaskRoleCheckboxes) do
            cb:Hide()
            cb:SetParent(nil)
        end
    end
    dialog.flaskRoleCheckboxes = {}
    
    local requiredFlaskRoles = settings.consumeTracking.requiredFlaskRoles or {}
    
    -- RolesUI role names (fixed 4 roles)
    local rolesUIRoles = {"Tanks", "Healers", "Melee", "Ranged"}
    
    local yPos = 0
    
    -- Create checkbox for each RolesUI role using OGST
    local previousElement = nil
    for i = 1, table.getn(rolesUIRoles) do
        local roleName = rolesUIRoles[i]
        
        local checkContainer, checkbox, checkLabel = OGST.CreateCheckbox(scrollChild, {
            label = roleName,
            labelAnchor = "RIGHT",
            checked = requiredFlaskRoles[roleName] or false
        })
        
        if not previousElement then
            OGST.AnchorElement(checkContainer, scrollChild, {
                position = "below",
                gap = 10,
                offsetX = 10,
                offsetY = -10
            })
        else
            OGST.AnchorElement(checkContainer, previousElement, {position = "below", gap = 5})
        end
        
        -- Store role name for save function
        checkbox.roleName = roleName
        
        table.insert(dialog.flaskRoleCheckboxes, checkbox)
        previousElement = checkContainer
    end
    
    -- Update scroll child height
    scrollChild:SetHeight(math.max(80, 4 * 25))
end
```

#### 3.6 Save Function

```lua
-- Save advanced settings from dialog to encounter data
function OGRH.SaveAdvancedSettingsDialog()
    local dialog = OGRH_AdvancedSettingsFrame
    if not dialog then return end
    
    -- Collect settings from UI
    local newSettings = {
        bigwigs = {
            enabled = dialog.bigwigsCheck:GetChecked() or false,
            encounterId = OGRH.Trim(dialog.encounterIdBox:GetText() or "")
        },
        consumeTracking = {
            enabled = dialog.consumeCheck:GetChecked() or false,
            readyThreshold = tonumber(dialog.thresholdInput:GetText()) or 85,
            requiredFlaskRoles = {}
        }
    }
    
    -- Validate threshold (0-100)
    if newSettings.consumeTracking.readyThreshold < 0 then
        newSettings.consumeTracking.readyThreshold = 0
    elseif newSettings.consumeTracking.readyThreshold > 100 then
        newSettings.consumeTracking.readyThreshold = 100
    end
    
    -- Collect flask role checkboxes
    for _, checkbox in pairs(dialog.flaskRoleCheckboxes) do
        local roleName = checkbox.roleName
        if roleName then
            newSettings.consumeTracking.requiredFlaskRoles[roleName] = checkbox:GetChecked() or false
        end
    end
    
    -- Save to encounter data
    if OGRH.SaveCurrentEncounterAdvancedSettings(newSettings) then
        OGRH.Msg("Advanced settings saved.")
        dialog:Hide()
    else
        OGRH.Msg("Failed to save advanced settings. Please select an encounter.")
    end
end
```

### Phase 4: BigWigs Integration (OGRH_BigWigs.lua)

Implement BigWigs integration in the previously created `OGRH_BigWigs.lua` file:

```lua
-- OGRH_BigWigs.lua
-- BigWigs encounter detection integration

OGRH.BigWigs = OGRH.BigWigs or {}

-- Track currently detected encounter
OGRH.BigWigs.currentBoss = nil

-- Register for BigWigs messages
local bigwigsFrame = CreateFrame("Frame")
bigwigsFrame:RegisterEvent("CHAT_MSG_ADDON")

bigwigsFrame:SetScript("OnEvent", function()
    if event == "CHAT_MSG_ADDON" then
        local prefix = arg1
        local message = arg2
        local channel = arg3
        local sender = arg4
        
        -- BigWigs sends boss engage messages
        if prefix == "BigWigs" then
            OGRH.BigWigs.HandleBigWigsMessage(message, sender)
        end
    end
end)

-- Parse BigWigs message for encounter start
function OGRH.BigWigs.HandleBigWigsMessage(message, sender)
    -- BigWigs message format varies, but typically contains boss name
    -- We need to detect when a boss encounter starts
    
    -- Example: "BOSSENG:Garr" or similar
    local bossName = string.match(message, "BOSSENG:(.+)")
    
    if bossName then
        OGRH.BigWigs.OnBossEngage(bossName)
    end
end

-- Called when BigWigs detects a boss engage
function OGRH.BigWigs.OnBossEngage(bossId)
    OGRH.BigWigs.currentBoss = bossId
    
    -- Find encounter with matching BigWigs ID
    local raid, encounter = OGRH.FindEncounterByBigWigsId(bossId)
    
    if raid and encounter then
        -- Auto-select this encounter
        OGRH.Msg("BigWigs detected: " .. bossId .. " - Selecting " .. encounter.name)
        
        -- Load encounter setup (auto-select raid/encounter)
        OGRH.LoadEncounter(raid.name, encounter.name)
    end
end

-- Find encounter by BigWigs encounter ID
function OGRH.FindEncounterByBigWigsId(bossId)
    OGRH.EnsureSV()
    
    if not OGRH_SV.encounterMgmt or not OGRH_SV.encounterMgmt.raids then
        return nil, nil
    end
    
    for i = 1, table.getn(OGRH_SV.encounterMgmt.raids) do
        local raid = OGRH_SV.encounterMgmt.raids[i]
        
        if raid.encounters then
            for j = 1, table.getn(raid.encounters) do
                local encounter = raid.encounters[j]
                
                -- Check if advanced settings exist and BigWigs is enabled
                if encounter.advancedSettings and
                   encounter.advancedSettings.bigwigs and
                   encounter.advancedSettings.bigwigs.enabled then
                    
                    local encounterId = encounter.advancedSettings.bigwigs.encounterId
                    
                    -- Match by exact ID or case-insensitive name
                    if encounterId and (
                        encounterId == bossId or
                        string.lower(encounterId) == string.lower(bossId)
                    ) then
                        return raid, encounter
                    end
                end
            end
        end
    end
    
    return nil, nil
end

-- Load an encounter (set as current and sync to raid if admin)
function OGRH.LoadEncounter(raidName, encounterName)
    -- Set current encounter
    OGRH_SV.currentRaid = raidName
    OGRH_SV.currentEncounter = encounterName
    
    -- Broadcast to raid if admin
    if OGRH.CanRW() then
        OGRH.BroadcastEncounterSelection(raidName, encounterName)
    end
end
```

**Note:** The `OGRH_BigWigs.lua` file was already added to the TOC in Phase 1.

### Phase 5: Consume Tracking Integration

Update consume tracking logic to respect advanced settings:

```lua
-- In OGRH_RolesUI.lua or wherever consume tracking logic lives

-- Check if a RolesUI role requires flasks based on advanced settings
-- roleName should be one of: "Tanks", "Healers", "Melee", "Ranged"
function OGRH.RoleRequiresFlask(roleName)
    -- Get current encounter advanced settings
    OGRH.EnsureSV()
    
    if not OGRH_SV.currentRaid or not OGRH_SV.currentEncounter then
        return false
    end
    
    local raid = OGRH.FindRaidByName(OGRH_SV.currentRaid)
    if not raid then return false end
    
    local encounter = OGRH.FindEncounterByName(raid, OGRH_SV.currentEncounter)
    if not encounter then return false end
    
    -- Check advanced settings
    if encounter.advancedSettings and
       encounter.advancedSettings.consumeTracking and
       encounter.advancedSettings.consumeTracking.enabled then
        
        local requiredRoles = encounter.advancedSettings.consumeTracking.requiredFlaskRoles or {}
        return requiredRoles[roleName] or false
    end
    
    -- Default: no flask requirement
    return false
end

-- Get ready threshold for current encounter
function OGRH.GetReadyThreshold()
    OGRH.EnsureSV()
    
    if not OGRH_SV.currentRaid or not OGRH_SV.currentEncounter then
        return 85  -- Default
    end
    
    local raid = OGRH.FindRaidByName(OGRH_SV.currentRaid)
    if not raid then return 85 end
    
    local encounter = OGRH.FindEncounterByName(raid, OGRH_SV.currentEncounter)
    if not encounter then return 85 end
    
    if encounter.advancedSettings and
       encounter.advancedSettings.consumeTracking then
        return encounter.advancedSettings.consumeTracking.readyThreshold or 85
    end
    
    return 85
end
```

---

## Sync Behavior

### Admin-Only Editing

- Only raid leaders/assistants can modify advanced settings
- Settings are stored per-encounter and synced with structure
- When admin changes settings, they are included in structure sync

### Structure Sync Protocol

Update `OGRH.ExportShareData()` to include advanced settings:

```lua
-- In OGRH_Share.lua (or wherever ExportShareData is defined)

-- Modify encounter export to include advancedSettings
for j = 1, table.getn(raid.encounters) do
    local encounter = raid.encounters[j]
    
    -- Ensure advanced settings exist
    OGRH.EnsureEncounterAdvancedSettings(raid, encounter)
    
    local encounterData = {
        name = encounter.name,
        roles = encounter.roles,
        advancedSettings = encounter.advancedSettings  -- ADD THIS
    }
    
    table.insert(raidData.encounters, encounterData)
end
```

Update `OGRH.ImportShareData()` to preserve advanced settings:

```lua
-- When importing encounter data
local newEncounter = {
    name = encounterData.name,
    roles = encounterData.roles,
    advancedSettings = encounterData.advancedSettings or {
        bigwigs = { enabled = false, encounterId = "" },
        consumeTracking = { enabled = false, readyThreshold = 85, requiredFlaskRoles = {} }
    }
}
```

Update checksum calculation to include advanced settings:

```lua
-- In OGRH.CalculateStructureChecksum()
-- After hashing roles, add:

-- Hash BigWigs settings
if encounter.advancedSettings and encounter.advancedSettings.bigwigs then
    local bw = encounter.advancedSettings.bigwigs
    checksum = checksum + (bw.enabled and 1 or 0) * 10000000
    
    if bw.encounterId and bw.encounterId ~= "" then
        for i = 1, string.len(bw.encounterId) do
            checksum = checksum + string.byte(bw.encounterId, i) * (i + 100)
        end
    end
end

-- Hash consume tracking settings
if encounter.advancedSettings and encounter.advancedSettings.consumeTracking then
    local ct = encounter.advancedSettings.consumeTracking
    checksum = checksum + (ct.enabled and 1 or 0) * 100000000
    checksum = checksum + (ct.readyThreshold or 0) * 1000000
    
    if ct.requiredFlaskRoles then
        for roleName, required in pairs(ct.requiredFlaskRoles) do
            if required then
                for i = 1, string.len(roleName) do
                    checksum = checksum + string.byte(roleName, i) * (i + 200)
                end
            end
        end
    end
end
```

---

## Synchronization & Checksum Integration

### Overview

Advanced settings must be included in the existing synchronization and checksum systems to ensure all raid members have consistent encounter configurations. This section details the integration points and implementation requirements.

**CRITICAL: Checkbox/Boolean Handling**

Encounter-level settings use `nil` to mean "inherit from raid defaults". This creates a three-state system:
- `nil` = inherit from raid
- `false` = explicitly disabled  
- `true` = explicitly enabled

**The standard Lua pattern `(value and 1 or 0)` DOES NOT WORK** because it treats both `nil` and `false` as `0`, causing checksum mismatches. Always use explicit `== true`, `== false`, and `~= nil` checks when hashing encounter-level settings.

Raid-level settings are always explicit (never nil), so they can use the standard `(value and 1 or 0)` pattern.

### Integration Points

The following systems must be updated to include `advancedSettings`:

1. **Structure Checksum Calculation** (OGRH_Core.lua)
2. **Share Export/Import** (OGRH_Share.lua)
3. **Sync Data Management** (OGRH_Sync.lua)
4. **Factory Defaults** (OGRH_FactoryDefaults.lua)

---

### 1. Structure Checksum Calculation

#### Files to Modify
- `OGRH_Core.lua`: Functions `OGRH.CalculateStructureChecksum()` and `OGRH.CalculateAllStructureChecksum()`

#### Implementation

**In `OGRH.CalculateStructureChecksum(raid, encounter)`:**

Add checksum calculation for advanced settings after the roles hashing section:

```lua
-- After existing role hashing code...

-- Hash advanced settings if they exist
if encounter.advancedSettings then
    -- Hash BigWigs settings
    if encounter.advancedSettings.bigwigs then
        local bw = encounter.advancedSettings.bigwigs
        
        -- Hash enabled flag (multiply by large prime to avoid collisions)
        checksum = checksum + (bw.enabled and 1 or 0) * 10000019
        
        -- Hash encounter ID string
        if bw.encounterId and bw.encounterId ~= "" then
            for i = 1, string.len(bw.encounterId) do
                checksum = checksum + string.byte(bw.encounterId, i) * (i + 107) * 1009
            end
        end
    end
    
    -- Hash consume tracking settings
    if encounter.advancedSettings.consumeTracking then
        local ct = encounter.advancedSettings.consumeTracking
        
        -- Hash enabled flag (nil=inherit, false=disabled, true=enabled)
        -- Must distinguish between nil/false/true for proper checksum
        local enabledValue = 0  -- default for nil
        if ct.enabled == true then
            enabledValue = 2
        elseif ct.enabled == false then
            enabledValue = 1
        end
        checksum = checksum + enabledValue * 100000037
        
        -- Hash ready threshold (nil means inherit from raid)
        if ct.readyThreshold ~= nil then
            checksum = checksum + ct.readyThreshold * 1000039
        end
        
        -- Hash required flask roles (must be deterministic)
        -- Sort role names alphabetically to ensure consistent ordering
        local roleNames = {"Tanks", "Healers", "Melee", "Ranged"}
        if ct.requiredFlaskRoles then
            for _, roleName in ipairs(roleNames) do
                -- Only hash if explicitly set (not nil)
                if ct.requiredFlaskRoles[roleName] ~= nil then
                    -- Hash role name
                    for i = 1, string.len(roleName) do
                        checksum = checksum + string.byte(roleName, i) * (i + 211) * 1013
                    end
                    -- Hash the boolean value (false=1, true=2)
                    local roleValue = ct.requiredFlaskRoles[roleName] and 2 or 1
                    checksum = checksum + roleValue * 1017
                end
            end
        end
    end
end

return tostring(checksum)
```

**In `OGRH.CalculateAllStructureChecksum()`:**

The existing code already iterates through all raids and encounters. Ensure `OGRH.EnsureEncounterAdvancedSettings()` is called before checksumming:

```lua
-- Inside the loop that processes encounters
for encIndex = 1, table.getn(raid.encounters) do
    local encounter = raid.encounters[encIndex]
    
    -- Ensure advanced settings exist (adds defaults if missing)
    OGRH.EnsureEncounterAdvancedSettings(raid, encounter)
    
    -- Existing checksum code for encounter name
    for i = 1, string.len(encounter.name) do
        checksum = checksum + string.byte(encounter.name, i) * (i + 400)
    end
    
    -- Call CalculateStructureChecksum which now includes advancedSettings
    local encounterChecksum = OGRH.CalculateStructureChecksum(raid, encounter)
    checksum = checksum + tonumber(encounterChecksum)
end
```

Also update raid-level checksum to include raid advancedSettings:

```lua
-- After hashing raid name, add:
if raid.advancedSettings and raid.advancedSettings.consumeTracking then
    local ct = raid.advancedSettings.consumeTracking
    
    -- Raid-level settings are always explicit (never nil)
    checksum = checksum + (ct.enabled and 1 or 0) * 50000023
    checksum = checksum + (ct.readyThreshold or 85) * 500029
    
    if ct.requiredFlaskRoles then
        local roleNames = {"Tanks", "Healers", "Melee", "Ranged"}
        for _, roleName in ipairs(roleNames) do
            if ct.requiredFlaskRoles[roleName] then
                for i = 1, string.len(roleName) do
                    checksum = checksum + string.byte(roleName, i) * (i + 311) * 1019
                end
            end
        end
    end
end
```

---

### 2. Share Export/Import System

#### Files to Modify
- `OGRH_Share.lua`: Functions `OGRH.ExportShareData()` and `OGRH.ImportShareData()`

#### Export Implementation

**In `OGRH.ExportShareData()`:**

Modify the raid export loop to include raid-level advanced settings:

```lua
-- When building raidData table
local raidData = {
    name = raid.name,
    encounters = {},
    advancedSettings = raid.advancedSettings  -- ADD THIS
}
```

Modify the encounter export loop to include encounter-level advanced settings:

```lua
for j = 1, table.getn(raid.encounters) do
    local encounter = raid.encounters[j]
    
    -- Ensure advanced settings exist before export
    OGRH.EnsureRaidAdvancedSettings(raid)
    OGRH.EnsureEncounterAdvancedSettings(raid, encounter)
    
    local encounterData = {
        name = encounter.name,
        roles = encounter.roles,
        advancedSettings = encounter.advancedSettings  -- ADD THIS
    }
    
    table.insert(raidData.encounters, encounterData)
end
```

#### Import Implementation

**In `OGRH.ImportShareData()`:**

Update raid import to handle raid-level advanced settings:

```lua
-- When importing raid
local newRaid = {
    name = raidData.name,
    encounters = {},
    advancedSettings = raidData.advancedSettings or {
        consumeTracking = {
            enabled = false,
            readyThreshold = 85,
            requiredFlaskRoles = {
                ["Tanks"] = false,
                ["Healers"] = false,
                ["Melee"] = false,
                ["Ranged"] = false,
            }
        }
    }
}
```

Update encounter import to handle encounter-level advanced settings:

```lua
-- When importing encounter
local newEncounter = {
    name = encounterData.name,
    roles = encounterData.roles,
    advancedSettings = encounterData.advancedSettings or {
        bigwigs = {
            enabled = false,
            encounterId = ""
        },
        consumeTracking = {
            enabled = nil,  -- nil = inherit from raid
            readyThreshold = nil,  -- nil = inherit from raid
            requiredFlaskRoles = {}
        }
    }
}
```

---

### 3. Sync System Integration

#### Files to Modify
- `OGRH_Sync.lua`: Function `OGRH.Sync.CalculateChecksum(data)`

#### Implementation

The sync system already uses a checksum calculation. Update it to match the core checksum:

```lua
-- In OGRH.Sync.CalculateChecksum(data)
-- After hashing encounterMgmt.raids and encounterMgmt.encounters

-- Hash encounter advanced settings
if data.encounterMgmt and data.encounterMgmt.raids then
    for raidIndex = 1, table.getn(data.encounterMgmt.raids) do
        local raid = data.encounterMgmt.raids[raidIndex]
        
        -- Hash raid-level advanced settings
        if raid.advancedSettings and raid.advancedSettings.consumeTracking then
            local ct = raid.advancedSettings.consumeTracking
            checksum = checksum + (ct.enabled and 1 or 0) * 50000023
            checksum = checksum + (ct.readyThreshold or 0) * 500029
            
            if ct.requiredFlaskRoles then
                local roleNames = {"Tanks", "Healers", "Melee", "Ranged"}
                for _, roleName in ipairs(roleNames) do
                    if ct.requiredFlaskRoles[roleName] then
                        for i = 1, string.len(roleName) do
                            checksum = checksum + string.byte(roleName, i) * (i + 311) * 1019
                        end
                    end
                end
            end
        end
        
        -- Hash encounter-level advanced settings
        if raid.encounters then
            for encIndex = 1, table.getn(raid.encounters) do
                local encounter = raid.encounters[encIndex]
                
                if encounter.advancedSettings then
                    -- BigWigs settings
                    if encounter.advancedSettings.bigwigs then
                        local bw = encounter.advancedSettings.bigwigs
                        checksum = checksum + (bw.enabled and 1 or 0) * 10000019
                        
                        if bw.encounterId and bw.encounterId ~= "" then
                            for i = 1, string.len(bw.encounterId) do
                                checksum = checksum + string.byte(bw.encounterId, i) * (i + 107) * 1009
                            end
                        end
                    end
                    
                    -- Consume tracking settings
                    if encounter.advancedSettings.consumeTracking then
                        local ct = encounter.advancedSettings.consumeTracking
                        checksum = checksum + (ct.enabled and 1 or 0) * 100000037
                        
                        if ct.readyThreshold then
                            checksum = checksum + ct.readyThreshold * 1000039
                        end
                        
                        if ct.requiredFlaskRoles then
                            local roleNames = {"Tanks", "Healers", "Melee", "Ranged"}
                            for _, roleName in ipairs(roleNames) do
                                if ct.requiredFlaskRoles[roleName] then
                                    for i = 1, string.len(roleName) do
                                        checksum = checksum + string.byte(roleName, i) * (i + 211) * 1013
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end
```

#### Export/Import Functions

The sync system's `OGRH.Sync.ExportData()` and `OGRH.Sync.ImportData()` rely on the same data structures as the Share system. No additional changes needed beyond ensuring `encounterMgmt` includes the full structure.

---

### 4. Factory Defaults Integration

#### Files to Modify
- `OGRH_FactoryDefaults.lua`: Update default data structure

#### Implementation

Ensure factory defaults include advanced settings for all raids and encounters:

```lua
-- In OGRH_FactoryDefaults.lua
-- For each raid in the defaults

local raidData = {
    name = "MC",
    advancedSettings = {
        consumeTracking = {
            enabled = false,
            readyThreshold = 85,
            requiredFlaskRoles = {
                ["Tanks"] = false,
                ["Healers"] = false,
                ["Melee"] = false,
                ["Ranged"] = false,
            }
        }
    },
    encounters = {
        {
            name = "Lucifron",
            roles = {...},
            advancedSettings = {
                bigwigs = {
                    enabled = false,
                    encounterId = "Lucifron"
                },
                consumeTracking = {
                    enabled = nil,
                    readyThreshold = nil,
                    requiredFlaskRoles = {}
                }
            }
        },
        -- ... other encounters
    }
}
```

---

### 5. Migration Strategy

#### Backward Compatibility

When loading old saved variables that don't have `advancedSettings`:

```lua
-- In VARIABLES_LOADED event handler or OGRH.EnsureSV()

-- Migrate raids
if OGRH_SV.encounterMgmt and OGRH_SV.encounterMgmt.raids then
    for i = 1, table.getn(OGRH_SV.encounterMgmt.raids) do
        local raid = OGRH_SV.encounterMgmt.raids[i]
        
        -- Add raid-level settings if missing
        OGRH.EnsureRaidAdvancedSettings(raid)
        
        -- Migrate encounters
        if raid.encounters then
            for j = 1, table.getn(raid.encounters) do
                local encounter = raid.encounters[j]
                OGRH.EnsureEncounterAdvancedSettings(raid, encounter)
            end
        end
    end
end
```

---

### 6. Testing Sync & Checksum

#### Checksum Verification

Test that checksums change when advanced settings change:

```lua
-- Test script (can be run via /script)
local function TestChecksumChange()
    -- Get initial checksum
    local checksum1 = OGRH.CalculateAllStructureChecksum()
    DEFAULT_CHAT_FRAME:AddMessage("Initial checksum: " .. checksum1)
    
    -- Modify a setting
    local raid = OGRH_SV.encounterMgmt.raids[1]
    local encounter = raid.encounters[1]
    OGRH.EnsureEncounterAdvancedSettings(raid, encounter)
    encounter.advancedSettings.bigwigs.enabled = true
    
    -- Get new checksum
    local checksum2 = OGRH.CalculateAllStructureChecksum()
    DEFAULT_CHAT_FRAME:AddMessage("After BigWigs enable: " .. checksum2)
    
    if checksum1 ~= checksum2 then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00Checksum changed correctly!|r")
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000ERROR: Checksum did not change!|r")
    end
end

TestChecksumChange()
```

#### Sync Testing Checklist

- [ ] Export encounter data with advanced settings
- [ ] Import encounter data preserves advanced settings
- [ ] Structure sync transmits advanced settings correctly
- [ ] Checksum detects changes to BigWigs enabled flag
- [ ] Checksum detects changes to BigWigs encounter ID
- [ ] Checksum detects changes to consume tracking enabled flag
- [ ] Checksum detects changes to ready threshold
- [ ] Checksum detects changes to flask requirements
- [ ] Raid-level settings included in checksum
- [ ] Migration from old data without advancedSettings works
- [ ] Factory defaults include advancedSettings
- [ ] Push Structure in Data Management shows correct checksum

---

### 7. Implementation Order

**Phase 1: Core Functions**
1. Implement `OGRH.EnsureRaidAdvancedSettings()` in OGRH_Core.lua
2. Implement `OGRH.EnsureEncounterAdvancedSettings()` in OGRH_Core.lua
3. Add migration code to `OGRH.EnsureSV()`

**Phase 2: Checksum Integration**
1. Update `OGRH.CalculateStructureChecksum()` in OGRH_Core.lua
2. Update `OGRH.CalculateAllStructureChecksum()` in OGRH_Core.lua
3. Update `OGRH.Sync.CalculateChecksum()` in OGRH_Sync.lua

**Phase 3: Export/Import**
1. Update `OGRH.ExportShareData()` in OGRH_Share.lua
2. Update `OGRH.ImportShareData()` in OGRH_Share.lua
3. Update factory defaults in OGRH_FactoryDefaults.lua

**Phase 4: Testing**
1. Test checksum changes with script
2. Test export/import round-trip
3. Test structure sync between clients
4. Test migration from old saved variables

---

## Testing Checklist

### UI Testing

- [ ] Settings icon appears in Design frame header
- [ ] Settings icon is disabled when no encounter selected
- [ ] Settings icon is enabled when encounter selected
- [ ] Clicking settings icon opens Advanced Settings dialog
- [ ] Dialog shows correct encounter name in title
- [ ] Dialog loads current settings correctly
- [ ] ESC key closes dialog
- [ ] Close button closes dialog

### BigWigs Section

- [ ] Enable checkbox toggles properly
- [ ] Encounter ID input accepts text
- [ ] Help button shows correct tooltip
- [ ] Settings save correctly
- [ ] BigWigs detection works (if BigWigs installed)
- [ ] RolesUI opens automatically on detection

### Consume Tracking Section

- [ ] Enable checkbox toggles properly
- [ ] Ready Threshold input accepts numbers only
- [ ] Ready Threshold validates (0-100)
- [ ] Flask role checkboxes populate from encounter roles
- [ ] Only consume check roles appear in list
- [ ] Player counts show correctly
- [ ] Checkboxes save correctly

### Data Persistence

- [ ] Settings persist across /reload
- [ ] Settings persist across logout/login
- [ ] Settings sync to other raid members (structure sync)
- [ ] Settings included in share export
- [ ] Settings imported from share data
- [ ] Checksum includes advanced settings

### Edge Cases

- [ ] Creating new encounter initializes default settings
- [ ] Upgrading old encounter adds advancedSettings table
- [ ] Deleting encounter removes settings
- [ ] Renaming encounter preserves settings
- [ ] Invalid threshold values are clamped (0-100)
- [ ] Missing advancedSettings table is created on access

---

## Future Enhancements

### Potential Future Features

1. **Multiple BigWigs IDs per Encounter**
   - Allow comma-separated list of boss IDs
   - Useful for encounters with phases or multiple bosses

2. **Per-Consume-Role Thresholds**
   - Different ready thresholds for different consume checks
   - Example: 100% for Onyxia Scale Cloak, 80% for fire resist gear

3. **Automatic Consume Announcements**
   - Auto-announce missing consumes when BigWigs triggers
   - Configurable delay before raid start

4. **Ready Check Integration**
   - Include consume readiness in ready check results
   - Show "X% ready (consumes: Y%)" in summary

5. **DBM Support**
   - Add similar integration for Deadly Boss Mods addon
   - Support both BigWigs and DBM detection

---

## Implementation Notes

### WoW 1.12 Compatibility

All code must follow constraints in "! OG-RaidHelper Design Philososphy.md":

- ✅ Use `table.getn(t)` not `#t`
- ✅ Use `mod(a, b)` not `a % b`
- ✅ Use `string.gfind()` not `string.gmatch()`
- ✅ Event handlers use implicit globals (`this`, `event`, `arg1-9`)
- ✅ No varargs `...`, use `arg` table instead
- ✅ All UI uses OGST library components

### OGST Library Usage

All UI components must use OGST library:

- `OGST.CreateStandardWindow()` for dialog frame
- `OGST.StyleButton()` for buttons
- `OGST.CreateStyledScrollList()` for scrolling lists
- `OGST.MakeFrameCloseOnEscape()` for ESC handling

### Backward Compatibility

When adding `advancedSettings`:

```lua
-- Always use OGRH.EnsureEncounterAdvancedSettings() before access
-- This handles upgrades from old data without advancedSettings

function OGRH.EnsureEncounterAdvancedSettings(raid, encounter)
    if not encounter.advancedSettings then
        encounter.advancedSettings = {
            bigwigs = {
                enabled = false,
                encounterId = ""
            },
            consumeTracking = {
                enabled = false,
                readyThreshold = 85,
                requiredFlaskRoles = {}
            }
        }
    end
end
```

---

**END OF DESIGN DOCUMENT**
