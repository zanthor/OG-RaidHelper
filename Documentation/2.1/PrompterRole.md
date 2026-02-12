# Prompter Role Specification

**Version:** 2.1  
**Module:** PrompterRole.lua  
**Location:** `_Raid/PrompterRole.lua`

---

## Overview

The Prompter Role is a specialized role type that provides a teleprompter-style interface for raid leaders to deliver sequential announcements during encounters. It displays announcements mid-screen with configurable durations and supports navigation through multiple prompts using mouse wheel or clicks.

---

## Key Features

### 1. Role Type: Prompter

- **Unique Per Encounter:** Only one Prompter role can exist per encounter (similar to Consume Check behavior)
- **Multiple Announcements:** Contains X configurable single-line text prompts
- **Tag Support:** Each prompt supports the full announcement tag system (`[Rx.Px]`, `[Rx.T]`, etc.)
- **Selective Announcement:** Each prompt has an individual "announce" checkbox to control whether it's sent to raid chat
- **Configurable Duration:** Display duration setting applies to all prompts in the role

### 2. Prompter Dock

When an encounter containing a Prompter role becomes the active encounter:

- **Auto-Show:** Prompter dock appears on screen automatically
- **Repositionable:** Drag to move anywhere on screen
- **Lock Option:** Lock button prevents accidental movement
- **Persistent Position:** Saves position and lock state per character
- **Auto-Hide:** Hides when switching to encounters without Prompter role

### 3. Navigation System

**Mouse Wheel:**
- Scroll up = Previous prompt
- Scroll down = Next prompt

**Mouse Clicks:**
- Left click = Next prompt
- Right click = Previous prompt

**Behavior:**
- Wraps around (last prompt → first prompt and vice versa)
- Shows current position indicator (e.g., "3/7")
- Highlights active prompt in dock

### 4. Mid-Screen Display

**Appearance:**
- Large, centered overlay frame
- Semi-transparent dark background
- White text with high readability
- Fades in quickly (0.2s)
- Fades out based on configured duration

**Content:**
- Displays current prompt text with tags replaced
- Shows prompt number and total (e.g., "Prompt 3 of 7")
- Optional: Shows next/previous prompt preview

**Duration:**
- Configurable per Prompter role (1-30 seconds)
- Default: 5 seconds
- Manual dismiss option (ESC key or close button)
- Duration resets when navigating to different prompt

---

## Role Structure

### Prompter Role Schema

```lua
{
  roleId = 5,
  name = "Prompter",
  isPrompter = true,              -- Flag identifying this as Prompter role
  displayDuration = 5,            -- Duration in seconds (1-30)
  promptCount = 5,                -- Number of prompt slots (configurable, default 5)
  prompts = {                      -- Array of prompt configurations
    {
      text = "",                   -- Prompt text with tags
      announce = true              -- Whether to send to raid chat
    },
    {
      text = "",
      announce = true
    },
    -- ... more prompts
  }
}
```

### Example Prompter Role

```lua
{
  roleId = 3,
  name = "Ragnaros Prompts",
  isPrompter = true,
  displayDuration = 7,
  promptCount = 5,
  prompts = {
    {
      text = "Welcome to Molten Core! [R1.T]: [R1.P]",
      announce = true
    },
    {
      text = "Phase 1: [R2.T] handle adds. [R3.T] on Ragnaros.",
      announce = true
    },
    {
      text = "Phase 2: Sons incoming! [R4.PA]",
      announce = true
    },
    {
      text = "Back on Ragnaros - burn phase!",
      announce = false  -- Personal reminder, not announced
    },
    {
      text = "Great job everyone! Loot time.",
      announce = true
    }
  }
}
```

---

## UI Components

### 1. Prompter Dock

**Visual Design:**
- Compact frame (200x60 pixels)
- Semi-transparent background
- Title bar with "Prompter" text and lock/unlock button
- Current prompt indicator: "3 / 7"
- Navigation hints: "Scroll or Click to Navigate"

**Positioning:**
- Default: Top-center of screen, below minimap
- Saved per character in SavedVariables
- Respects UI scaling

**Interaction:**
- Hoverable: Shows tooltip with current prompt preview
- Mouse wheel: Navigate prompts
- Left/Right click: Navigate prompts
- Drag: Reposition (when unlocked)
- Lock button: Toggle position lock

**Code Reference:**
```lua
-- Create dock using OGST
local dock = OGST.RegisterDockedPanel({
  name = "OGRH_PrompterDock",
  width = 200,
  height = 60,
  title = "Prompter",
  lockable = true,
  defaultPosition = {point = "TOP", x = 0, y = -100}
})
```

### 2. Mid-Screen Overlay

**Visual Design:**
- Large centered frame (600x200 pixels)
- Dark semi-transparent backdrop (0, 0, 0, 0.85)
- Border with subtle glow effect
- Large, readable font (18pt)
- Prompt counter in top-right
- Optional close button (X)

**Animation Sequence:**
1. Fade in: 0.2 seconds
2. Hold: Display duration (configurable)
3. Fade out: 1.0 second
4. Auto-hide after fade complete

**Behavior:**
- Blocks input to prevent accidental clicks (IgnoreMouseClicks)
- ESC key dismisses immediately
- Switching prompts resets fade timer
- Only visible to local player (not a raid frame)

### 3. Role Editor Integration

**Prompter Role Configuration Panel:**

```
┌─────────────────────────────────────────────┐
│ Role Type: [Prompter Role]       [Save]    │
├─────────────────────────────────────────────┤
│ Display Duration: [5] seconds               │
│ Number of Prompts: [5]                      │
├─────────────────────────────────────────────┤
│ Prompt 1:                                   │
│ [Text input field...........................] │
│ ☑ Announce to raid                          │
├─────────────────────────────────────────────┤
│ Prompt 2:                                   │
│ [Text input field...........................] │
│ ☑ Announce to raid                          │
├─────────────────────────────────────────────┤
│ ... (repeat for all prompts)               │
├─────────────────────────────────────────────┤
│ [Add Prompt] [Remove Prompt]                │
└─────────────────────────────────────────────┘
```

**Configuration Controls:**
- **Display Duration Slider:** 1-30 seconds with number input
- **Prompt Count Selector:** 1-20 prompts (dropdown or +/- buttons)
- **Prompt Text Boxes:** Single-line EditBox (max 300 chars)
- **Announce Checkboxes:** One per prompt
- **Add/Remove Buttons:** Dynamically adjust prompt count
- **Preview Button:** Test current prompt with tag replacement

---

## Prompter Dock Behavior

### Show/Hide Logic

**Show Conditions:**
- Active encounter contains Prompter role
- Player is in raid OR editing encounter offline
- Dock has not been manually hidden

**Hide Conditions:**
- Active encounter changes to one without Prompter role
- Player leaves raid (optional, configurable)
- User manually closes dock (temporary hide)

**Persistence:**
```lua
-- Saved per character
OGRH_PrompterDock_Settings = {
  position = {point = "TOP", relativeTo = nil, relativePoint = "TOP", x = 0, y = -100},
  locked = false,
  enabled = true,           -- Master enable/disable
  showOutOfRaid = false     -- Show dock when not in raid
}
```

### Navigation Behavior

**Current Prompt Tracking:**
```lua
local currentPromptIndex = 1  -- Starts at prompt 1

function NextPrompt()
  currentPromptIndex = currentPromptIndex + 1
  if currentPromptIndex > table.getn(prompts) then
    currentPromptIndex = 1  -- Wrap to first
  end
  DisplayPrompt(currentPromptIndex)
end

function PreviousPrompt()
  currentPromptIndex = currentPromptIndex - 1
  if currentPromptIndex < 1 then
    currentPromptIndex = table.getn(prompts)  -- Wrap to last
  end
  DisplayPrompt(currentPromptIndex)
end
```

**Mouse Wheel Handler:**
```lua
dock:SetScript("OnMouseWheel", function()
  if arg1 > 0 then
    PreviousPrompt()  -- Scroll up = previous
  else
    NextPrompt()      -- Scroll down = next
  end
end)
dock:EnableMouseWheel()
```

**Mouse Click Handler:**
```lua
dock:RegisterForClicks("LeftButtonUp", "RightButtonUp")
dock:SetScript("OnClick", function()
  if arg1 == "LeftButton" then
    NextPrompt()
  elseif arg1 == "RightButton" then
    PreviousPrompt()
  end
end)
```

---

## Mid-Screen Display Implementation

### Display Function

```lua
function OGRH.DisplayPrompt(promptIndex)
  local role = GetCurrentPrompterRole()
  if not role or not role.prompts or not role.prompts[promptIndex] then
    return
  end
  
  local prompt = role.prompts[promptIndex]
  
  -- Replace tags
  local displayText = OGRH.Announcements.ReplaceTags(
    prompt.text,
    encounterRoles,
    assignments,
    raidMarks,
    assignmentNumbers
  )
  
  -- Show mid-screen overlay
  OGRH.ShowPrompterOverlay(displayText, promptIndex, table.getn(role.prompts))
  
  -- Announce to raid if enabled
  if prompt.announce then
    OGRH.AnnounceToRaid(displayText)
  end
end
```

### Overlay Frame Structure

```lua
local overlay = CreateFrame("Frame", "OGRH_PrompterOverlay", UIParent)
overlay:SetWidth(600)
overlay:SetHeight(200)
overlay:SetPoint("CENTER", UIParent, "CENTER", 0, 100)
overlay:SetFrameStrata("FULLSCREEN_DIALOG")
overlay:SetAlpha(0)  -- Start hidden

-- Backdrop
overlay:SetBackdrop({
  bgFile = "Interface/Tooltips/UI-Tooltip-Background",
  edgeFile = "Interface/DialogFrame/UI-DialogBox-Border",
  tile = true,
  tileSize = 32,
  edgeSize = 32,
  insets = {left = 11, right = 12, top = 12, bottom = 11}
})
overlay:SetBackdropColor(0, 0, 0, 0.85)
overlay:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)

-- Prompt text (large, centered)
local text = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
text:SetPoint("CENTER", overlay, "CENTER", 0, 10)
text:SetWidth(560)
text:SetJustifyH("CENTER")
text:SetJustifyV("MIDDLE")
text:SetTextColor(1, 1, 1)
overlay.text = text

-- Counter text (top-right)
local counter = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
counter:SetPoint("TOPRIGHT", overlay, "TOPRIGHT", -15, -15)
counter:SetTextColor(0.7, 0.7, 0.7)
overlay.counter = counter

-- Close button
local closeBtn = CreateFrame("Button", nil, overlay, "UIPanelCloseButton")
closeBtn:SetPoint("TOPRIGHT", overlay, "TOPRIGHT", -5, -5)
closeBtn:SetScript("OnClick", function()
  OGRH.HidePrompterOverlay()
end)

-- ESC key handler
overlay:SetScript("OnKeyDown", function()
  if arg1 == "ESCAPE" then
    OGRH.HidePrompterOverlay()
  end
end)
```

### Fade Animation

```lua
function OGRH.ShowPrompterOverlay(text, currentIndex, totalPrompts)
  local overlay = OGRH_PrompterOverlay
  overlay.text:SetText(text)
  overlay.counter:SetText("Prompt " .. currentIndex .. " of " .. totalPrompts)
  
  -- Cancel any existing fade
  if overlay.fadeTimer then
    overlay.fadeTimer:SetScript("OnUpdate", nil)
  end
  
  -- Fade in
  local fadeInTime = 0.2
  local holdTime = GetPrompterDisplayDuration()
  local fadeOutTime = 1.0
  local elapsed = 0
  local phase = "fadein"  -- fadein, hold, fadeout, complete
  
  overlay:Show()
  overlay.fadeTimer = CreateFrame("Frame")
  overlay.fadeTimer:SetScript("OnUpdate", function()
    elapsed = elapsed + arg1
    
    if phase == "fadein" then
      local alpha = math.min(1, elapsed / fadeInTime)
      overlay:SetAlpha(alpha)
      if elapsed >= fadeInTime then
        phase = "hold"
        elapsed = 0
      end
    elseif phase == "hold" then
      overlay:SetAlpha(1)
      if elapsed >= holdTime then
        phase = "fadeout"
        elapsed = 0
      end
    elseif phase == "fadeout" then
      local alpha = math.max(0, 1 - (elapsed / fadeOutTime))
      overlay:SetAlpha(alpha)
      if elapsed >= fadeOutTime then
        phase = "complete"
        overlay:Hide()
        this:SetScript("OnUpdate", nil)
      end
    end
  end)
end

function OGRH.HidePrompterOverlay()
  local overlay = OGRH_PrompterOverlay
  if overlay.fadeTimer then
    overlay.fadeTimer:SetScript("OnUpdate", nil)
  end
  overlay:Hide()
  overlay:SetAlpha(0)
end
```

---

## Role Editor Integration

### Adding Prompter Role Type

In **EncounterSetup.lua**, the role type dropdown should include Prompter:

```lua
local roleTypes = {
  {text = "Raider Roles", value = "raider"},
  {text = "Consume Check", value = "consume"},
  {text = "Custom Module", value = "custom"},
  {text = "Prompter", value = "prompter"}  -- New
}
```

### Prompter Role Validation

```lua
-- Only one Prompter role per encounter
function ValidatePrompterRole(encounterRoles, currentRoleIndex)
  local prompterCount = 0
  for i, role in ipairs(encounterRoles) do
    if i ~= currentRoleIndex and role.isPrompter then
      prompterCount = prompterCount + 1
    end
  end
  
  if prompterCount > 0 then
    OGRH.Msg("|cffff0000[RH-Error]|r Only one Prompter role allowed per encounter.")
    return false
  end
  
  return true
end
```

### Prompter Configuration UI

```lua
function OGRH.ShowPrompterRoleEditor(role)
  local frame = CreateFrame("Frame", "OGRH_PrompterRoleEditor", UIParent)
  frame:SetWidth(500)
  frame:SetHeight(400)
  -- ... standard window setup
  
  -- Display duration slider
  local durationSlider = CreateFrame("Slider", nil, frame, "OptionsSliderTemplate")
  durationSlider:SetMinMaxValues(1, 30)
  durationSlider:SetValue(role.displayDuration or 5)
  durationSlider:SetValueStep(1)
  
  -- Prompt count selector
  local promptCountBox = CreateFrame("EditBox", nil, frame)
  promptCountBox:SetText(tostring(role.promptCount or 5))
  promptCountBox:SetNumeric(true)
  
  -- Scrolling prompt list
  local scrollFrame = CreateFrame("ScrollFrame", nil, frame)
  local scrollChild = CreateFrame("Frame", nil, scrollFrame)
  
  -- Generate prompt editors
  for i = 1, role.promptCount do
    local promptFrame = CreateFrame("Frame", nil, scrollChild)
    promptFrame:SetHeight(50)
    
    -- Prompt number label
    local label = promptFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetText("Prompt " .. i .. ":")
    
    -- Text input
    local textBox = CreateFrame("EditBox", nil, promptFrame)
    textBox:SetWidth(350)
    textBox:SetMaxLetters(300)
    textBox:SetText(role.prompts[i] and role.prompts[i].text or "")
    
    -- Announce checkbox
    local announceCheck = CreateFrame("CheckButton", nil, promptFrame, "UICheckButtonTemplate")
    announceCheck:SetChecked(role.prompts[i] and role.prompts[i].announce or true)
    
    -- Save handlers
    textBox:SetScript("OnTextChanged", function()
      if not role.prompts[i] then
        role.prompts[i] = {}
      end
      role.prompts[i].text = this:GetText()
    end)
    
    announceCheck:SetScript("OnClick", function()
      if not role.prompts[i] then
        role.prompts[i] = {}
      end
      role.prompts[i].announce = this:GetChecked()
    end)
  end
end
```

---

## Announcement Integration

### Tag Replacement

Prompter prompts use the existing tag replacement system from **Announce.lua**:

```lua
-- When displaying prompt
local displayText = OGRH.Announcements.ReplaceTags(
  prompt.text,
  encounterRoles,
  assignments,
  raidMarks,
  assignmentNumbers
)
```

### Raid Announcement

When a prompt has `announce = true`, send to raid chat:

```lua
function OGRH.AnnouncePrompt(promptText, isAnnounceEnabled)
  if not isAnnounceEnabled then
    return  -- Silent display only
  end
  
  -- Use ChatThrottleLib for raid announcements
  if GetNumRaidMembers() > 0 then
    ChatThrottleLib:SendChatMessage("NORMAL", "OGRH", promptText, "RAID")
  elseif GetNumPartyMembers() > 0 then
    ChatThrottleLib:SendChatMessage("NORMAL", "OGRH", promptText, "PARTY")
  end
end
```

---

## API Functions

### `OGRH.CreatePrompterRole(promptCount, displayDuration)`
Creates a new Prompter role with default configuration.

**Parameters:**
- `promptCount` (number, optional) - Number of prompts (default: 5)
- `displayDuration` (number, optional) - Display duration in seconds (default: 5)

**Returns:** Table containing Prompter role structure

**Example:**
```lua
local prompter = OGRH.CreatePrompterRole(7, 10)
```

---

### `OGRH.IsPrompterRole(role)`
Checks if a role is a Prompter role.

**Parameters:**
- `role` (table) - Role object to check

**Returns:** `boolean`

**Example:**
```lua
if OGRH.IsPrompterRole(role) then
  -- Handle prompter display
end
```

---

### `OGRH.ShowPrompterDock()`
Shows the prompter dock for the current active encounter.

**Returns:** `nil`

**Example:**
```lua
OGRH.ShowPrompterDock()
```

---

### `OGRH.HidePrompterDock()`
Hides the prompter dock.

**Returns:** `nil`

**Example:**
```lua
OGRH.HidePrompterDock()
```

---

### `OGRH.DisplayPrompt(promptIndex)`
Displays a specific prompt mid-screen with tag replacement.

**Parameters:**
- `promptIndex` (number) - Index of prompt to display (1-based)

**Returns:** `nil`

**Example:**
```lua
OGRH.DisplayPrompt(3)  -- Show prompt 3
```

---

### `OGRH.NextPrompt()`
Advances to the next prompt (wraps to first).

**Returns:** `nil`

**Example:**
```lua
OGRH.NextPrompt()
```

---

### `OGRH.PreviousPrompt()`
Goes back to the previous prompt (wraps to last).

**Returns:** `nil`

**Example:**
```lua
OGRH.PreviousPrompt()
```

---

### `OGRH.GetPrompterDisplayDuration()`
Gets the display duration for the current Prompter role.

**Returns:** `number` - Duration in seconds

**Example:**
```lua
local duration = OGRH.GetPrompterDisplayDuration()
```

---

## User Commands

### Slash Commands

```lua
/ogrh prompter show     -- Show prompter dock
/ogrh prompter hide     -- Hide prompter dock
/ogrh prompter lock     -- Lock dock position
/ogrh prompter unlock   -- Unlock dock position
/ogrh prompter next     -- Next prompt
/ogrh prompter prev     -- Previous prompt
/ogrh prompter reset    -- Reset to first prompt
```

---

## Usage Examples

### Example 1: Boss Encounter Prompts

```lua
-- Ragnaros Encounter with Prompter
{
  name = "Ragnaros",
  roles = {
    {
      roleId = 1,
      name = "Main Tank",
      slots = 1,
      -- ... standard role config
    },
    {
      roleId = 2,
      name = "Off Tanks",
      slots = 3,
      -- ... standard role config
    },
    {
      roleId = 3,
      name = "Encounter Prompts",
      isPrompter = true,
      displayDuration = 8,
      promptCount = 6,
      prompts = {
        {
          text = "Pull Ragnaros! [R1.P1] main tank, [R2.P] handle sons.",
          announce = true
        },
        {
          text = "Phase 1: Spread out for lava splash!",
          announce = true
        },
        {
          text = "Sons spawning! [R2.P] pick up adds NOW!",
          announce = true
        },
        {
          text = "Sons dead - back on Ragnaros!",
          announce = true
        },
        {
          text = "Submerge phase - move to center!",
          announce = true
        },
        {
          text = "40% - Final burn! Pop cooldowns!",
          announce = true
        }
      }
    }
  }
}
```

### Example 2: Trash Pack Prompts

```lua
{
  name = "Suppression Room",
  roles = {
    {
      roleId = 1,
      name = "Pull Instructions",
      isPrompter = true,
      displayDuration = 5,
      promptCount = 3,
      prompts = {
        {
          text = "Pull left pack first - CC dragon",
          announce = true
        },
        {
          text = "Interrupt all shadow bolts",
          announce = false  -- Personal reminder
        },
        {
          text = "Loot and rebuff before next pull",
          announce = true
        }
      }
    }
  }
}
```

---

## Testing Considerations

### Test Cases

1. **Role Creation:**
   - Create Prompter role in encounter
   - Verify only one Prompter allowed per encounter
   - Test with various prompt counts (1, 5, 10, 20)

2. **Dock Behavior:**
   - Dock shows when encounter with Prompter becomes active
   - Dock hides when switching to encounter without Prompter
   - Position persists across sessions
   - Lock/unlock functions correctly

3. **Navigation:**
   - Mouse wheel scrolling (both directions)
   - Left/right click navigation
   - Wrap-around behavior (first ↔ last)
   - Current prompt indicator updates

4. **Display:**
   - Mid-screen overlay appears with correct text
   - Tag replacement works correctly
   - Fade in/out animations smooth
   - ESC key dismisses overlay
   - Display duration respects configuration

5. **Announcement:**
   - Prompts with `announce = true` send to raid
   - Prompts with `announce = false` stay local
   - ChatThrottleLib integration works
   - Tags replaced before sending to raid

6. **Edge Cases:**
   - Empty prompt text
   - Very long prompt text (300 chars)
   - Switching encounters mid-display
   - Raid leader leaves raid during display
   - Multiple rapid navigation clicks

---

## Future Enhancements

### Automation Features
- **Auto-Advance:** Option to automatically advance to next prompt after duration
- **Trigger Integration:** Link prompts to BigWigs/DBM encounter events
- **Phase Detection:** Auto-advance based on boss HP thresholds
- **Keybinds:** Configurable hotkeys for next/previous prompt

### Visual Enhancements
- **Custom Fonts:** Allow font size/family customization
- **Color Coding:** Different colors for different prompt types (warning, info, etc.)
- **Icons:** Add icon support to prompts (raid icons, item icons)
- **Sound Effects:** Play sound when prompt changes

### Organization Features
- **Prompt Groups:** Organize prompts into collapsible sections (Pre-pull, Phase 1, Phase 2, etc.)
- **Prompt Templates:** Save/load common prompt sets
- **Import/Export:** Share prompter configurations

### Advanced Display
- **Multi-Line Prompts:** Support for wrapped text or multiple lines
- **Countdown Timer:** Visual countdown bar showing remaining display time
- **Preview Window:** Small preview of next prompt
- **History:** Recently displayed prompts log

---

## Related Modules

- **EncounterMgmt.lua:** Role rendering and encounter display
- **EncounterSetup.lua:** Role editor integration
- **Announce.lua:** Tag replacement system
- **OGST:** Docked panel system
- **ChatThrottleLib:** Raid announcement throttling

---

## Implementation Priority

### Phase 1 (Core Functionality)
- [ ] Prompter role structure and storage
- [ ] Role editor UI for Prompter configuration
- [ ] Basic prompter dock (show/hide/position)
- [ ] Navigation (wheel/click)
- [ ] Mid-screen overlay with fade

### Phase 2 (Polish)
- [ ] Lock/unlock positioning
- [ ] Persistent settings
- [ ] Announcement integration
- [ ] Tag replacement
- [ ] ESC key dismiss

### Phase 3 (Enhancement)
- [ ] Slash commands
- [ ] Visual polish (animations, styling)
- [ ] Tooltip preview on dock hover
- [ ] Preview button in role editor
- [ ] Add/remove prompt buttons

---

## Change Log

| Version | Date | Changes |
|---------|------|---------|
| 2.1.0 | Feb 2026 | Initial Prompter Role specification |

