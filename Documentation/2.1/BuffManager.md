# BuffManager Specification

**Version:** 2.1  
**Module:** BuffManager.lua  
**Location:** `_Raid/BuffManager.lua`

---

## Overview

BuffManager is an optional buff coordination system inspired by PallyPower, expanded to handle all raid buffs across all classes. It is **not** a standalone encounter — it lives as a **role inside the Admin encounter** (encounter index 1). The Admin role provides an at-a-glance buff status summary and a button that opens the full Buff Manager configuration window.

The full window provides visual assignment of buff responsibilities to specific players and groups, tracks buff compliance, and provides shameable announcements for missing buffs.

---

## UI Toolkit Requirement

All BuffManager UI components **must** be built with the OGST toolkit (`_OGST/OGST.lua`). This ensures visual consistency with the rest of OG-RaidHelper. The following OGST components are expected to be used:

| Component | Usage |
|-----------|-------|
| `OGST.CreateStandardWindow` | Buff Manager window, Buff Tracker window |
| `OGST.CreateButton` | Apply, Scan, Announce, Sync buttons |
| `OGST.CreateMenuButton` | Blessing dropdowns, class-assignment selectors, player dropdowns |
| `OGST.CreateCheckbox` | Group 1-8 checkboxes, PallyPower sync toggles, auto-scan |
| `OGST.CreateProgressBar` | Buff coverage bars per role |
| `OGST.CreateStyledScrollList` | Scrollable role list in the Buff Manager window |
| `OGST.CreateStyledListItem` | Individual buff role rows |
| `OGST.CreateStaticText` | Labels, coverage percentages, section headers |
| `OGST.CreateColoredPanel` | Buff status indicator panels in the Admin role |
| `OGST.CreateContentPanel` | Section containers within the window |
| `OGST.CreateDialog` | Confirmation dialogs (disable BuffManager, clear assignments) |
| `OGST.MakeFrameCloseOnEscape` | Window close-on-Escape behavior |
| `OGST.CreateSingleLineTextBox` | Threshold/interval config inputs |

Raw `CreateFrame` should only be used for invisible layout containers or custom draw regions — never for interactive controls that have an OGST equivalent.

---

## Key Features

### 1. Admin Encounter Role

- **Position:** New role in the Admin encounter (right column, below Loot Rules)
- **No Standalone Encounter:** BuffManager does not occupy encounter index 2 or any other index
- **Role Type:** `isBuffManager = true` flag (similar to `isLootSettings` and `isTextField`)
- **Admin Role Rendering:** Shows a compact buff status summary with colored indicators and a "Manage Buffs" button that opens the full configuration window
- **Persistence:** Buff assignments persist per raid template via SVM, same as other Admin role data

### 2. Multi-Class Buff Coordination

**Supported Buffs:**
- **Fortitude** (Priest) — Power Word: Fortitude / Prayer of Fortitude
- **Spirit** (Priest) — Divine Spirit / Prayer of Spirit
- **Shadow Protection** (Priest) — Shadow Protection / Prayer of Shadow Protection
- **Mark of the Wild** (Druid) — Mark of the Wild / Gift of the Wild
- **Arcane Brilliance** (Mage) — Arcane Intellect / Arcane Brilliance
- **Paladin Blessings** (Paladin) — Per-class assignments (Might, Wisdom, Kings, Salvation, etc.)

### 3. Group-Based Assignment System

- Each buff role has player assignment slots
- Each slot has **8 checkboxes** (`OGST.CreateCheckbox`) for raid groups 1-8
- Players can be assigned to multiple groups
- Visual indication of assigned groups
- Automatic conflict detection (multiple players on same group)

### 4. Paladin Special Handling

- **Pally Power Integration:** Broadcasts assignments to PallyPower addon
- **Per-Class Buffs:** Each paladin assigned specific classes (Warrior gets Might, Mages get Wisdom, etc.)
- **Backwards Compatible:** Reads existing PallyPower settings
- **Two-Way Sync:** Can import from PallyPower or export to it

### 5. Buff Tracking & Monitoring

- **Real-Time Monitoring:** Tracks who has which buffs
- **Group Coverage:** Shows which groups have full coverage via `OGST.CreateProgressBar`
- **Missing Buffs:** Highlights unbuffed players
- **Buff Duration:** Shows time remaining on buffs
- **Auto-Scan:** Periodic raid scan for buff status

### 6. Name & Shame System

- **Announcement Builder:** Generate reports of unbuffed players
- **Compliance Report:** Show which buffers are not doing their job
- **Integration with Consume Logging:** Cross-reference with consume tracker
- **Configurable Threshold:** Set minimum buff coverage % before shaming
- **Whisper Option:** Private reminder vs public announcement

---

## Admin Encounter Integration

### Role Definition

The BuffManager role is added to the Admin encounter template:

```lua
local ADMIN_ENCOUNTER_TEMPLATE = {
  name = "Admin",
  displayName = "Raid Admin",
  roles = {
    -- Role 1: Loot Settings (column 1)
    { ... },
    -- Role 2: Loot Rules (column 2)
    { ... },
    -- Role 3: Discord (column 1)
    { ... },
    -- Role 4: SR Link (column 1)
    { ... },
    -- Role 5: Buff Manager (column 2, below Loot Rules)
    {
      roleId = 5,
      name = "Buff Manager",
      column = 2,
      isBuffManager = true,  -- New role type flag
      enabled = false,       -- Master enable/disable
      buffRoles = {
        -- Sub-structure for buff assignments (see Buff Role Data Structure below)
      },
      settings = {
        autoScan = true,
        scanInterval = 30,
        warnThreshold = 5,
        shameThreshold = 80,
        whisperFirst = true,
        pallyPowerSync = false,
        pallyPowerBroadcast = false
      }
    }
  }
}
```

### Admin Role Rendering (`RenderBuffManagerRole`)

When `EncounterMgmt` encounters a role with `isBuffManager = true`, it calls `OGRH.RenderBuffManagerRole()`. This renders a compact set of controls inside the Admin encounter's right column:

```
┌─ Buff Manager ──────────────────────────┐
│  [✓] Paladin    [✓] Priest              │
│  [✓] Druid      [ ] Mage                │
│                                          │
│         [ Manage Buffs ]                 │
└──────────────────────────────────────────┘
```

The checkboxes indicate which buff classes are actively being managed for the encounter:

- **Managed (checked):** BuffManager assignments control which groups/players need the buff. Deficits are included in chat announcements directed at the assigned caster.
- **Unmanaged (unchecked):** The Readiness Dashboard performs a simple X/Y evaluation (every raid member checked against provider-class presence in raid, respecting blacklists). Deficits contribute to the readiness score but are **not** included in chat announcements.
- **Paladin** is a special case — it always ties into the PallyPower integration regardless of the checkbox state.

**Components:**
- `MANAGED_BUFF_CLASSES` constant: 4 entries defining the 2×2 grid layout (`paladin`, `priest`, `druid`, `mage`)
- `OGST.CreateCheckbox` for each buff class (disabled when user lacks edit permission)
- Styled "Manage Buffs" button which opens the Buff Manager window

**Data persistence:** Each checkbox persists to `role.managedBuffClasses[classKey]` via SVM at path:
```
encounterMgmt.raids[raidIdx].encounters[encounterIdx].roles[roleIndex].managedBuffClasses.<classKey>
```

```lua
local MANAGED_BUFF_CLASSES = {
  { key = "paladin", label = "Paladin", col = 1, row = 1 },
  { key = "priest",  label = "Priest",  col = 2, row = 1 },
  { key = "druid",   label = "Druid",   col = 1, row = 2 },
  { key = "mage",    label = "Mage",    col = 2, row = 2 },
}

function OGRH.RenderBuffManagerRole(container, role, roleIndex, raidIdx, encounterIdx, containerWidth)
  if not role or not role.isBuffManager then return nil end

  OGRH.BuffManager.EnsureBuffRoles(role)

  if not role.managedBuffClasses then
    role.managedBuffClasses = {}
  end

  local frame = CreateFrame("Frame", nil, container)
  frame:SetWidth(containerWidth - 10)
  frame:SetHeight(75)
  frame:SetPoint("TOPLEFT", container, "TOPLEFT", 5, -25)

  local canEdit = OGRH.BuffManager.CanEdit(raidIdx)
  local basePath = SVMBase(raidIdx, encounterIdx, roleIndex)

  -- 2×2 checkbox grid
  local colWidth = math.floor((containerWidth - 10) / 2)
  local rowHeight = 26

  for _, def in ipairs(MANAGED_BUFF_CLASSES) do
    local x = (def.col - 1) * colWidth
    local y = -(def.row - 1) * rowHeight
    local capturedKey = def.key

    local cb = OGST.CreateCheckbox(frame, {
      label = def.label,
      labelWidth = 60,
      checked = role.managedBuffClasses[def.key] and true or false,
      disabled = not canEdit,
      onChange = function(checked)
        role.managedBuffClasses[capturedKey] = checked
        OGRH.SVM.SetPath(
          basePath .. ".managedBuffClasses." .. capturedKey,
          checked,
          BuildSyncMeta(raidIdx)
        )
      end
    })
    cb:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y)
  end

  -- "Manage Buffs" button (centered at bottom)
  -- ...

  return frame
end
```

### `OGRH.BuffManager.IsClassManaged(classKey, raidIdx)`

Public API to check whether a particular buff class is being managed (checkbox enabled in Admin).

```lua
-- @param classKey string  One of "paladin", "priest", "druid", "mage"
-- @param raidIdx number   (optional) Defaults to 1
-- @return boolean  true if managed, false otherwise
OGRH.BuffManager.IsClassManaged("paladin")  -- true/false
```

---

## Buff Manager Window

The "Manage Buffs" button opens a standalone `OGST.CreateStandardWindow` that floats above the encounter planning UI. This is where all detailed buff assignment, tracking, and announcement controls live. A **roster panel** on the right side lets the raid leader drag players directly into buff assignment slots — this panel is shared with EncounterMgmt via the reusable `OGRH.CreateRosterPanel` component (see [Shared Roster Panel](#shared-roster-panel-_uirosterpanellua)).

### Window Layout

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│ Buff Manager                                                   [Settings] [Track] [X]   │
├─────────────────────────────────────────────────────────────┬───────────────────────────┤
│ ┌─ Fortitude (Priest) ──────────────────────────────────┐   │  Players:                 │
│ │ P1: [Dropdown▼]  Groups: ☑1 ☑2 ☑3 ☐4 ☐5 ☐6 ☐7 ☐8   │   │  [Raid    ▼] [All Roles▼]│
│ │ P2: [Dropdown▼]  Groups: ☐1 ☐2 ☐3 ☑4 ☑5 ☑6 ☑7 ☑8   │   │  [Search...             ]│
│ │ P3: [Dropdown▼]  Groups: ☐1 ☐2 ☐3 ☐4 ☐5 ☐6 ☐7 ☐8   │   │  ┌───────────────────┐  │
│ │ Coverage: █████████████████████ 100% (40/40)          │   │  │ ── Tanks ────────  │  │
│ └───────────────────────────────────────────────────────┘   │  │  Playername        │  │
│ ┌─ Spirit (Priest) ─────────────────────────────────────┐   │  │  Playername        │  │
│ │ P1: [Dropdown▼]  Groups: ☑1 ☑2 ☑3 ☑4 ☐5 ☐6 ☐7 ☐8   │   │  │ ── Healers ──────  │  │
│ │ P2: [Dropdown▼]  Groups: ☐1 ☐2 ☐3 ☐4 ☑5 ☑6 ☑7 ☑8   │   │  │  Playername        │  │
│ │ Coverage: █████████████░░░░░░░ 60% (24/40)            │   │  │  Playername        │  │
│ └───────────────────────────────────────────────────────┘   │  │ ── Melee ─────────  │  │
│ ┌─ Mark of the Wild (Druid) ────────────────────────────┐   │  │  Playername        │  │
│ │ P1: [Dropdown▼]  Groups: ☑1 ☑2 ☑3 ☑4 ☑5 ☑6 ☑7 ☑8   │   │  │ ── Ranged ────────  │  │
│ │ Coverage: █████████████████████ 100% (40/40)          │   │  │  Playername        │  │
│ └───────────────────────────────────────────────────────┘   │  │  Playername        │  │
│ ┌─ Arcane Brilliance (Mage) ────────────────────────────┐   │  │                    │  │
│ │ P1: [Dropdown▼]  Groups: ☑1 ☑2 ☑3 ☑4 ☑5 ☑6 ☑7 ☑8   │   │  │                    │  │
│ │ Coverage: █████████████████████ 100% (40/40)          │   │  └───────────────────┘  │
│ └───────────────────────────────────────────────────────┘   │                           │
│ ┌─ Paladin Blessings ───────────────────────────────────┐   │                           │
│ │ P1: [Dropdown▼]  → Classes: [Warrior▼] [Rogue▼]      │   │                           │
│ │                     Blessing: [Might ▼]                │   │                           │
│ │ P2: [Dropdown▼]  → Classes: [Mage▼] [Warlock▼]       │   │                           │
│ │                     Blessing: [Wisdom ▼]               │   │                           │
│ │ ☑ Sync with PallyPower  ☐ Broadcast to PallyPower    │   │                           │
│ │ Coverage: █████████████████████ 100% (40/40)          │   │                           │
│ └───────────────────────────────────────────────────────┘   │                           │
└─────────────────────────────────────────────────────────────┴───────────────────────────┘
```

The window is split into two regions:

| Region | Width | Contents |
|--------|-------|----------|
| Left (buff sections) | ~490px | Scrollable list of buff role sections with dropdowns, group checkboxes, coverage bars |
| Right (roster panel) | 200px | Shared `OGRH.CreateRosterPanel` — identical to the Encounter Planning players panel |

The roster panel provides:
- **Source toggle** — Raid (live raid members) vs Roster (planning roster from `OGRH.Invites.GetPlanningRoster()`)
- **Role filter** — All Roles / Tanks / Healers / Melee / Ranged / Unassigned
- **Search box** — Text filter on player names
- **Scrollable player list** — Section headers (Tanks, Healers, Melee, Ranged) with class-colored player names
- **Drag & drop** — Drag a player from the roster onto a buff assignment `[Dropdown]` slot to assign them

**Window construction:**
- `OGST.CreateStandardWindow` for the main frame with title bar and close button
- `OGST.MakeFrameCloseOnEscape` for Escape key handling
- `OGST.CreateStyledScrollList` for the scrollable role list (needed when window is small)
- `OGST.CreateContentPanel` for each buff type section
- `OGST.CreateMenuButton` for player assignment dropdowns and blessing selectors
- `OGST.CreateCheckbox` for group 1-8 checkboxes and PallyPower toggles
- `OGST.CreateProgressBar` for coverage bars
- `OGST.CreateStaticText` for labels and coverage text
- `OGST.CreateButton` for title bar buttons (Settings, Track)
- `OGRH.CreateRosterPanel` for the right-side player roster (shared component)

```lua
function OGRH.ShowBuffManagerWindow(raidIdx, encounterIdx, roleIndex)
  if OGRH.BuffManager.window then
    OGRH.BuffManager.window:Show()
    return
  end

  local window = OGST.CreateStandardWindow({
    name = "OGRHBuffManagerWindow",
    title = "Buff Manager",
    width = 710,
    height = 550,
    closable = true,
    movable = true
  })
  OGST.MakeFrameCloseOnEscape(window, "OGRHBuffManagerWindow")

  -- Title bar buttons
  local settingsBtn = OGST.CreateButton(window.titleBar, {
    text = "Settings",
    width = 60, height = 18,
    point = {"RIGHT", window.closeButton, "LEFT", -4, 0},
    onClick = function() OGRH.ShowBuffManagerSettings() end
  })

  OGST.CreateButton(window.titleBar, {
    text = "Track",
    width = 50, height = 18,
    point = {"RIGHT", settingsBtn, "LEFT", -4, 0},
    onClick = function() OGRH.ShowBuffTracker() end
  })

  -- Left side: scrollable buff sections
  local scrollList = OGST.CreateStyledScrollList(window.content, 480, 500)

  -- Render each buff role section
  OGRH.RenderBuffSections(scrollList, raidIdx, encounterIdx, roleIndex)

  -- Right side: shared roster panel
  local rosterPanel = OGRH.CreateRosterPanel(window.content, {
    width = 200,
    height = 500,
    anchor = {"TOPLEFT", scrollList, "TOPRIGHT", 10, 0},
    onPlayerDrop = function(playerName, playerClass, dropTarget)
      -- Handle player dropped onto a buff assignment slot
      OGRH.BuffManager.AssignPlayer(playerName, playerClass, dropTarget)
    end,
    getDropTargets = function()
      -- Return current buff assignment dropdown frames for hit-testing
      return OGRH.BuffManager.GetAssignmentSlots()
    end
  })
  window.rosterPanel = rosterPanel

  OGRH.BuffManager.window = window
end
```

---

## Shared Roster Panel (`_UI/RosterPanel.lua`)

The roster panel that appears in both Encounter Planning (EncounterMgmt.lua) and Buff Manager is extracted into a single reusable component. This avoids duplicating the ~870 lines of panel structure + refresh logic across two files.

### File Location

```
OG-RaidHelper/
  _UI/
    RosterPanel.lua    ← NEW shared component
```

Add to `OG-RaidHelper.toc`:
```
_UI\RosterPanel.lua
```

### API

```lua
--- Create a reusable roster panel with source toggle, role filter, search, and scrollable player list.
-- @param parent  Frame  The parent frame to anchor the panel inside
-- @param config  Table  Configuration options (see below)
-- @return panel  Frame  The roster panel frame (also has :Refresh() method)
OGRH.CreateRosterPanel(parent, config)
```

**Config table:**

| Key | Type | Required | Description |
|-----|------|----------|-------------|
| `width` | number | No | Panel width (default 200) |
| `height` | number | No | Panel height (default 390) |
| `anchor` | table | Yes | Standard SetPoint args, e.g. `{"TOPLEFT", sibling, "TOPRIGHT", 10, 0}` |
| `onPlayerDrop` | function | No | `function(playerName, playerClass, dropTarget)` — called when a player is dragged onto a valid drop target |
| `getDropTargets` | function | No | `function() → table` — returns array of frames that accept player drops (hit-tested during drag) |
| `enableDrag` | boolean | No | Enable drag-and-drop from player list items (default true) |
| `showRoleFilter` | boolean | No | Show the role filter button (default true) |
| `showSourceToggle` | boolean | No | Show Raid/Roster source toggle (default true) |
| `defaultSource` | string | No | `"Raid"` or `"Roster"` (default `"Raid"`) |significant

**Returned panel fields:**

| Field | Type | Description |
|-------|------|-------------|
| `panel` | Frame | The outer container frame |
| `panel.Refresh()` | function | Re-render the player list with current filters |
| `panel.selectedUnitSource` | string | Current source: `"Raid"` or `"Roster"` |
| `panel.selectedPlayerRole` | string | Current role filter: `"all"`, `"tanks"`, `"healers"`, `"melee"`, `"ranged"`, `"unassigned"` |
| `panel.searchBox` | EditBox | The search text input |
| `panel.scrollChild` | Frame | The scroll child (for external anchoring) |

### Internal Structure

```
┌─────────────────────┐
│  "Players:"         │  ← header label
│  [Raid ▼][All Roles▼]│  ← unitSourceBtn (85×24), playerRoleBtn (85×24)
│  [Search...         ]│  ← searchBox (180×24, EditBox)
│  ┌─────────────────┐│
│  │ ── Tanks ────── ││  ← section headers (GameFontNormalSmall, dimmed)
│  │  Playername     ││  ← OGRH.CreateStyledListItem, class-colored
│  │  Playername     ││
│  │ ── Healers ──── ││
│  │  Playername     ││
│  │ ── Melee ───── ││
│  │  Playername     ││
│  │ ── Ranged ──── ││
│  │  Playername     ││
│  └─────────────────┘│  ← OGRH.CreateStyledScrollList (width-20, height-110)
└─────────────────────┘
```

### Skeleton Implementation

```lua
-- _UI/RosterPanel.lua
-- Shared roster panel used by EncounterMgmt and BuffManager

function OGRH.CreateRosterPanel(parent, config)
  config = config or {}
  local width = config.width or 200
  local height = config.height or 390
  local enableDrag = config.enableDrag ~= false
  local showRoleFilter = config.showRoleFilter ~= false
  local showSourceToggle = config.showSourceToggle ~= false

  -- Outer container
  local panel = CreateFrame("Frame", nil, parent)
  panel:SetWidth(width)
  panel:SetHeight(height)
  if config.anchor then
    panel:SetPoint(unpack(config.anchor))
  end
  panel:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = {left = 3, right = 3, top = 3, bottom = 3}
  })
  panel:SetBackdropColor(0.1, 0.1, 0.1, 0.8)

  -- "Players:" label
  local label = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  label:SetPoint("TOP", panel, "TOP", 0, -10)
  label:SetText("Players:")

  -- Source toggle (Raid / Roster)
  panel.selectedUnitSource = config.defaultSource or "Raid"
  local unitSourceBtn
  if showSourceToggle then
    unitSourceBtn = OGST.CreateMenuButton(panel, {
      text = panel.selectedUnitSource,
      width = 85, height = 24,
      point = {"TOP", label, "BOTTOM", -47, -5},
      items = {
        {text = "Raid", value = "Raid"},
        {text = "Roster", value = "Roster"}
      },
      onClick = function(value)
        panel.selectedUnitSource = value
        panel:Refresh()
      end
    })
  end

  -- Role filter
  panel.selectedPlayerRole = "all"
  if showRoleFilter then
    local roleAnchor = unitSourceBtn
      and {"LEFT", unitSourceBtn, "RIGHT", 5, 0}
      or  {"TOP", label, "BOTTOM", 0, -5}
    OGST.CreateMenuButton(panel, {
      text = "All Roles",
      width = 85, height = 24,
      point = roleAnchor,
      items = {
        {text = "All Roles",  value = "all"},
        {text = "Tanks",      value = "tanks"},
        {text = "Healers",    value = "healers"},
        {text = "Melee",      value = "melee"},
        {text = "Ranged",     value = "ranged"},
        {text = "Unassigned", value = "unassigned"}
      },
      onClick = function(value, label)
        panel.selectedPlayerRole = value
        panel:Refresh()
      end
    })
  end

  -- Search box
  local searchBox = OGST.CreateSingleLineTextBox(panel, {
    width = width - 20,
    height = 24,
    point = {"TOPLEFT", unitSourceBtn or label, "BOTTOMLEFT", 0, -5},
    placeholder = "Search...",
    onTextChanged = function(text)
      panel:Refresh()
    end
  })
  panel.searchBox = searchBox

  -- Scrollable player list
  local listHeight = height - 110  -- room for header + buttons + search
  local listFrame, scrollFrame, scrollChild, scrollBar, contentWidth =
    OGRH.CreateStyledScrollList(panel, width - 20, listHeight)
  listFrame:SetPoint("TOP", searchBox, "BOTTOM", 0, -5)
  panel.scrollChild = scrollChild
  panel.scrollFrame = scrollFrame
  panel.scrollBar = scrollBar
  panel.contentWidth = contentWidth

  -----------------------------------------------------------
  -- Refresh: rebuild the player list from current data source
  -----------------------------------------------------------
  function panel:Refresh()
    -- Clear existing items
    local children = {self.scrollChild:GetChildren()}
    for _, child in ipairs(children) do
      child:Hide()
      child:SetParent(nil)
    end

    -- Gather players from selected source
    local players
    if self.selectedUnitSource == "Roster" then
      players = OGRH.Invites.GetPlanningRoster()
    else
      players = OGRH.GetRaidMembers()  -- wrapper around GetRaidRosterInfo
    end

    -- Apply role filter
    if self.selectedPlayerRole ~= "all" then
      players = OGRH.FilterPlayersByRole(players, self.selectedPlayerRole)
    end

    -- Apply search filter
    local searchText = string.lower(self.searchBox:GetText() or "")
    if searchText ~= "" then
      local filtered = {}
      for _, p in ipairs(players) do
        if string.find(string.lower(p.name), searchText, 1, true) then
          table.insert(filtered, p)
        end
      end
      players = filtered
    end

    -- Group by role section
    local sections = OGRH.GroupPlayersBySection(players)
    local yOffset = 0

    for _, section in ipairs(sections) do
      -- Section header
      local header = self.scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      header:SetPoint("TOPLEFT", self.scrollChild, "TOPLEFT", 5, -yOffset)
      header:SetText("|cff888888── " .. section.name .. " ──|r")
      yOffset = yOffset + OGRH.LIST_ITEM_HEIGHT

      -- Player items
      for _, player in ipairs(section.players) do
        local item = OGRH.CreateStyledListItem(self.scrollChild, self.contentWidth)
        item:SetPoint("TOPLEFT", self.scrollChild, "TOPLEFT", 0, -yOffset)

        -- Class-colored name
        local color = RAID_CLASS_COLORS[player.class] or {r=1,g=1,b=1}
        item.text:SetText(player.name)
        item.text:SetTextColor(color.r, color.g, color.b)

        -- Drag-and-drop support
        if enableDrag and config.onPlayerDrop and config.getDropTargets then
          OGRH.EnableRosterDrag(item, player, config.getDropTargets, config.onPlayerDrop)
        end

        yOffset = yOffset + OGRH.LIST_ITEM_HEIGHT + OGRH.LIST_ITEM_SPACING
      end
    end

    self.scrollChild:SetHeight(math.max(yOffset, 1))
  end

  -- Initial render
  panel:Refresh()

  return panel
end
```

### Drag-and-Drop Helper

```lua
--- Attach drag-and-drop behaviour to a roster list item.
-- Reused by both EncounterMgmt (slot assignment) and BuffManager (buff assignment).
function OGRH.EnableRosterDrag(item, player, getDropTargets, onDrop)
  item:RegisterForDrag("LeftButton")

  item:SetScript("OnDragStart", function()
    -- Create a floating drag frame showing the player name
    local drag = CreateFrame("Frame", nil, UIParent)
    drag:SetWidth(100)
    drag:SetHeight(20)
    drag:SetFrameStrata("TOOLTIP")
    local text = drag:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetAllPoints()
    text:SetText(player.name)
    local c = RAID_CLASS_COLORS[player.class] or {r=1,g=1,b=1}
    text:SetTextColor(c.r, c.g, c.b)
    OGRH._dragFrame = drag
    OGRH._dragPlayer = player
  end)

  item:SetScript("OnDragStop", function()
    if not OGRH._dragFrame then return end
    OGRH._dragFrame:Hide()
    OGRH._dragFrame = nil

    -- Hit-test against drop targets
    local targets = getDropTargets()
    for _, target in ipairs(targets or {}) do
      if MouseIsOver(target) then
        onDrop(player.name, player.class, target)
        break
      end
    end
    OGRH._dragPlayer = nil
  end)
end
```

### Migration Plan — EncounterMgmt.lua

When `_UI/RosterPanel.lua` is implemented:

1. Replace the inline players panel creation (current EncounterMgmt.lua L1488-1742) with:
   ```lua
   frame.rosterPanel = OGRH.CreateRosterPanel(frame, {
     anchor = {"TOPLEFT", rightPanel, "TOPRIGHT", 10, 0},
     height = 390,
     onPlayerDrop = function(name, class, target)
       OGRH.HandleEncounterPlayerDrop(name, class, target)
     end,
     getDropTargets = function()
       return OGRH.GetEncounterSlotTargets(frame)
     end
   })
   ```

2. Replace the inline `RefreshPlayersList` (current L2375-2870) with calls to `frame.rosterPanel:Refresh()`.

3. Move the existing drag-from-player logic (L2732-2849) into `OGRH.EnableRosterDrag`.

4. Slot-to-slot swap logic (L3716-3950) stays in EncounterMgmt since it is encounter-specific.

> **Note:** This extraction should happen as a Phase 0 prerequisite step *before* BuffManager implementation begins so that the component is available for both consumers from day one.

---

## Buff Role Data Structure

The buff assignment data lives inside the Admin role's `buffRoles` table. The `managedBuffClasses` table controls which buff classes are actively being managed via the Admin checkboxes:

```lua
managedBuffClasses = {
  paladin = true,   -- Paladin blessings managed
  priest  = false,  -- Priest buffs (Fort, Spirit, SP) not managed
  druid   = true,   -- Druid buffs (MotW) managed
  mage    = false,  -- Mage buffs (Int) not managed
}
```

```lua
buffRoles = {
  -- Buff Role 1: Fortitude (Priest)
  {
    buffRoleId = 1,
    name = "Fortitude",
    buffType = "fortitude",
    spellIds = {1243, 1244, 1245, 2791, 10937, 10938, 21562, 21564},
    slots = 3,
    groupAssignments = {
      [1] = {1, 2, 3},
      [2] = {4, 5, 6},
      [3] = {7, 8}
    },
    assignedPlayers = {}
  },
  -- Buff Role 2: Spirit (Priest)
  {
    buffRoleId = 2,
    name = "Spirit",
    buffType = "spirit",
    spellIds = {14752, 14818, 14819, 27841, 25312, 27681},
    slots = 3,
    groupAssignments = {},
    assignedPlayers = {}
  },
  -- Buff Role 3: Shadow Protection (Priest)
  {
    buffRoleId = 3,
    name = "Shadow Protection",
    buffType = "shadowprot",
    spellIds = {976, 10957, 10958, 27683, 39374},
    slots = 2,
    groupAssignments = {},
    assignedPlayers = {}
  },
  -- Buff Role 4: Mark of the Wild (Druid)
  {
    buffRoleId = 4,
    name = "Mark of the Wild",
    buffType = "motw",
    spellIds = {1126, 5232, 6756, 5234, 8907, 9884, 9885, 21849, 21850},
    slots = 3,
    groupAssignments = {},
    assignedPlayers = {}
  },
  -- Buff Role 5: Arcane Brilliance (Mage)
  {
    buffRoleId = 5,
    name = "Arcane Brilliance",
    buffType = "int",
    spellIds = {1459, 1460, 1461, 10156, 10157, 23028, 27126},
    slots = 3,
    groupAssignments = {},
    assignedPlayers = {}
  },
  -- Buff Role 6: Paladin Blessings (Special)
  {
    buffRoleId = 6,
    name = "Paladin Blessings",
    buffType = "paladin",
    isPaladinRole = true,
    slots = 5,
    paladinAssignments = {
      [1] = { classes = {"WARRIOR", "ROGUE"}, blessing = "might" },
      [2] = { classes = {"MAGE", "WARLOCK"}, blessing = "wisdom" },
      [3] = { classes = {"PRIEST", "DRUID"}, blessing = "kings" },
      [4] = { classes = {}, blessing = "salvation" },
      [5] = { classes = {}, blessing = "light" }
    },
    assignedPlayers = {}
  }
}
```

**SVM Path:** All buff data lives under the Admin encounter's role:
```
encounterMgmt.raids[raidIdx].encounters[1].roles[5].buffRoles[buffRoleId].assignedPlayers[slotIdx]
encounterMgmt.raids[raidIdx].encounters[1].roles[5].buffRoles[buffRoleId].groupAssignments[slotIdx]
encounterMgmt.raids[raidIdx].encounters[1].roles[5].settings.*
```

---

## UI Components

### 1. Group Assignment Checkboxes

Each player slot has 8 group checkboxes built with `OGST.CreateCheckbox`:

```lua
local function CreateGroupCheckboxes(parent, buffRoleIndex, slotIndex, currentGroups)
  local checkboxes = {}

  for group = 1, 8 do
    local isChecked = false
    if currentGroups then
      for _, g in ipairs(currentGroups) do
        if g == group then isChecked = true; break end
      end
    end

    local capturedGroup = group
    checkboxes[group] = OGST.CreateCheckbox(parent, {
      label = tostring(group),
      labelFont = "GameFontNormalSmall",
      labelColor = {r = 0.7, g = 0.7, b = 0.7},
      checked = isChecked,
      width = 16,
      height = 16,
      point = {"LEFT", parent, "LEFT", 100 + (group - 1) * 24, 0},
      tooltip = {
        title = "Group " .. group,
        text = "Assign this player to buff group " .. group
      },
      onClick = function(checked)
        OGRH.SetBuffGroupAssignment(buffRoleIndex, slotIndex, capturedGroup, checked)
        OGRH.UpdateBuffCoverage()
      end
    })
  end

  return checkboxes
end
```

### 2. Paladin Assignment UI

Special UI for per-class buff assignments using `OGST.CreateMenuButton`:

```lua
local function CreatePaladinAssignmentUI(parent, slotIndex, assignment)
  local frame = CreateFrame("Frame", nil, parent)
  frame:SetWidth(400)
  frame:SetHeight(50)

  -- Player dropdown (OGST.CreateMenuButton with raid paladin list)
  local playerContainer, playerBtn = OGST.CreateMenuButton(frame, {
    label = "P" .. slotIndex .. ":",
    labelWidth = 30,
    buttonText = assignment.player or "Select Paladin",
    buttonWidth = 120,
    buttonHeight = 20,
    menuItems = OGRH.GetRaidPaladinMenuItems(slotIndex),
    singleSelect = true
  })
  playerContainer:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)

  -- Class selection checkboxes (OGST.CreateCheckbox per class)
  local classes = {"WARRIOR", "ROGUE", "HUNTER", "MAGE", "WARLOCK", "PRIEST", "DRUID", "PALADIN"}
  for i, class in ipairs(classes) do
    local isAssigned = false
    if assignment.classes then
      for _, c in ipairs(assignment.classes) do
        if c == class then isAssigned = true; break end
      end
    end

    OGST.CreateCheckbox(frame, {
      label = string.sub(class, 1, 3),
      labelFont = "GameFontNormalSmall",
      checked = isAssigned,
      width = 16, height = 16,
      point = {"LEFT", frame, "LEFT", 160 + (i - 1) * 28, 0},
      onClick = function(checked)
        OGRH.TogglePaladinClassAssignment(slotIndex, class, checked)
      end
    })
  end

  -- Blessing dropdown
  local blessingContainer, blessingBtn = OGST.CreateMenuButton(frame, {
    label = "Blessing:",
    labelWidth = 50,
    buttonText = assignment.blessing or "Might",
    buttonWidth = 80,
    buttonHeight = 20,
    menuItems = OGRH.GetBlessingMenuItems(slotIndex),
    singleSelect = true
  })
  blessingContainer:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -22)

  return frame
end
```

### 3. Coverage Display

Visual progress bar using `OGST.CreateProgressBar`:

```lua
local function CreateCoverageDisplay(parent, buffType)
  local coverage = OGRH.CalculateBuffCoverage(buffType)
  local percent = (coverage.total > 0) and ((coverage.buffed / coverage.total) * 100) or 0

  local bar = OGST.CreateProgressBar(parent, {
    width = 300,
    height = 14,
    min = 0,
    max = 100,
    value = percent,
    color = (percent >= 100) and {r=0, g=1, b=0}
           or (percent >= 80) and {r=1, g=1, b=0}
           or {r=1, g=0, b=0}
  })

  local text = OGST.CreateStaticText(parent, {
    text = string.format("%d%% (%d/%d)", math.floor(percent), coverage.buffed, coverage.total),
    font = "GameFontNormalSmall",
    color = {r = 0.8, g = 0.8, b = 0.8}
  })

  return bar, text
end
```

### 4. Buff Tracking Window

A separate `OGST.CreateStandardWindow` for real-time buff monitoring:

```
┌─────────────────────────────────────────────────┐
│ Buff Tracker                         [Scan] [X] │
├─────────────────────────────────────────────────┤
│ Last Scan: 15 seconds ago                       │
│ Overall Coverage: 87% (35/40 players)           │
├─────────────────────────────────────────────────┤
│ Missing Buffs:                                  │
│   Group 1: Tankmedady - Missing Fort, Spirit    │
│   Group 3: Gnuzmas - Missing Spirit             │
│   Group 5: Shadyman - Missing Mark, Int         │
│   Group 7: Holyman - Missing Fort               │
│                                                 │
│ Buff Assignments Not Met:                       │
│   Priestbro (Fort, Groups 1-3): 2 unbuffed      │
│   Druidguy (MotW, Groups 4-5): 3 unbuffed       │
│                                                 │
│ [ Whisper Missing ]  [ Announce Report ]        │
└─────────────────────────────────────────────────┘
```

**Components:**
- `OGST.CreateStandardWindow` for the tracker window
- `OGST.CreateButton` for Scan, Whisper Missing, Announce Report
- `OGST.CreateStyledScrollList` for the missing-buffs list
- `OGST.CreateStaticText` for scan timestamp, overall coverage
- `OGST.CreateProgressBar` for overall coverage bar

---

## Buff Tracking System

### 1. Raid Scan

```lua
function OGRH.ScanRaidBuffs()
  local buffData = {
    timestamp = GetTime(),
    players = {}
  }

  for i = 1, GetNumRaidMembers() do
    local name, rank, subgroup, level, class = GetRaidRosterInfo(i)
    if name then
      local playerData = {
        name = name,
        class = class,
        group = subgroup,
        buffs = {}
      }

      local unitId = "raid" .. i
      for buffSlot = 1, 32 do
        local buffName, buffRank, buffIcon = UnitBuff(unitId, buffSlot)
        if not buffName then break end

        local category = OGRH.GetBuffCategory(buffName)
        if category then
          playerData.buffs[category] = {
            name = buffName,
            rank = buffRank,
            icon = buffIcon
          }
        end
      end

      buffData.players[name] = playerData
    end
  end

  OGRH.BuffManager.lastScan = buffData
  return buffData
end
```

### 2. Buff Category Detection

```lua
function OGRH.GetBuffCategory(buffName)
  if string.find(buffName, "Fortitude") then return "fortitude" end
  if string.find(buffName, "Divine Spirit") or string.find(buffName, "Prayer of Spirit") then return "spirit" end
  if string.find(buffName, "Shadow Protection") then return "shadowprot" end
  if string.find(buffName, "Mark of the Wild") or string.find(buffName, "Gift of the Wild") then return "motw" end
  if string.find(buffName, "Arcane Intellect") or string.find(buffName, "Arcane Brilliance") then return "int" end
  if string.find(buffName, "Blessing of") or string.find(buffName, "Greater Blessing") then return "paladin" end
  return nil
end
```

### 3. Coverage Calculation

```lua
function OGRH.CalculateBuffCoverage(buffType)
  local lastScan = OGRH.BuffManager.lastScan
  if not lastScan then
    return {buffed = 0, total = 0, missing = {}}
  end

  local coverage = { buffed = 0, total = 0, missing = {} }

  for playerName, playerData in pairs(lastScan.players) do
    coverage.total = coverage.total + 1
    if playerData.buffs[buffType] then
      coverage.buffed = coverage.buffed + 1
    else
      table.insert(coverage.missing, {
        name = playerName,
        class = playerData.class,
        group = playerData.group
      })
    end
  end

  return coverage
end
```

### 4. Automatic Scanning

```lua
function OGRH.StartBuffScanning()
  if OGRH.BuffManager.scanFrame then return end

  local frame = CreateFrame("Frame")
  local elapsed = 0
  local interval = OGRH.GetBuffScanInterval()

  frame:SetScript("OnUpdate", function()
    elapsed = elapsed + arg1
    if elapsed >= interval then
      elapsed = 0
      OGRH.ScanRaidBuffs()
      OGRH.UpdateBuffTrackerUI()
      OGRH.UpdateAdminBuffIndicators()  -- Refresh compact indicators in Admin role
    end
  end)

  OGRH.BuffManager.scanFrame = frame
end

function OGRH.StopBuffScanning()
  if OGRH.BuffManager.scanFrame then
    OGRH.BuffManager.scanFrame:SetScript("OnUpdate", nil)
    OGRH.BuffManager.scanFrame = nil
  end
end
```

---

## PallyPower Integration

### 1. Reading PallyPower Data

```lua
function OGRH.ImportFromPallyPower()
  if not PP_Assignment then return false end

  local paladinAssignments = {}
  for playerName, classAssignments in pairs(PP_Assignment) do
    local assignment = { player = playerName, classes = {}, blessing = nil }
    for className, blessingId in pairs(classAssignments) do
      table.insert(assignment.classes, className)
      assignment.blessing = OGRH.GetBlessingName(blessingId)
    end
    table.insert(paladinAssignments, assignment)
  end

  return paladinAssignments
end
```

### 2. Broadcasting to PallyPower

```lua
function OGRH.BroadcastToPallyPower()
  if not PP_Assignment then
    OGRH.Msg("|cffff6666[BuffManager]|r PallyPower addon not found")
    return false
  end

  local paladinRole = OGRH.GetPaladinBuffRole()
  if not paladinRole then return false end

  for slotIndex, assignment in pairs(paladinRole.paladinAssignments) do
    local playerName = paladinRole.assignedPlayers[slotIndex]
    if playerName and assignment.classes then
      if not PP_Assignment[playerName] then
        PP_Assignment[playerName] = {}
      end
      for _, className in ipairs(assignment.classes) do
        PP_Assignment[playerName][className] = OGRH.GetBlessingId(assignment.blessing)
      end
    end
  end

  if PP_Update then PP_Update() end

  OGRH.Msg("|cff00ff00[BuffManager]|r Assignments broadcast to PallyPower")
  return true
end
```

---

## Name & Shame System

### 1. Missing Buff Report

```lua
function OGRH.GenerateMissingBuffReport()
  local report = {
    timestamp = GetTime(),
    unbuffedPlayers = {},
    underperformingBuffers = {}
  }

  local buffTypes = {"fortitude", "spirit", "shadowprot", "motw", "int", "paladin"}

  for _, buffType in ipairs(buffTypes) do
    local coverage = OGRH.CalculateBuffCoverage(buffType)

    for _, missing in ipairs(coverage.missing) do
      if not report.unbuffedPlayers[missing.name] then
        report.unbuffedPlayers[missing.name] = {
          class = missing.class,
          group = missing.group,
          missingBuffs = {}
        }
      end
      table.insert(report.unbuffedPlayers[missing.name].missingBuffs, buffType)
    end

    local role = OGRH.GetBuffRole(buffType)
    if role then
      for slotIndex, playerName in pairs(role.assignedPlayers) do
        local assignedGroups = role.groupAssignments[slotIndex] or {}
        local unbuffedCount = 0
        for _, groupNum in ipairs(assignedGroups) do
          for _, missingPlayer in ipairs(coverage.missing) do
            if missingPlayer.group == groupNum then
              unbuffedCount = unbuffedCount + 1
            end
          end
        end
        if unbuffedCount > 0 then
          table.insert(report.underperformingBuffers, {
            player = playerName,
            buffType = buffType,
            groups = assignedGroups,
            unbuffedCount = unbuffedCount
          })
        end
      end
    end
  end

  return report
end
```

### 2. Announcement Builder

```lua
function OGRH.AnnounceMissingBuffs(whisperFirst)
  local report = OGRH.GenerateMissingBuffReport()

  if whisperFirst then
    for _, failure in ipairs(report.underperformingBuffers) do
      local msg = "You have " .. failure.unbuffedCount .. " unbuffed players in your assigned groups for " .. failure.buffType
      SendChatMessage(msg, "WHISPER", nil, failure.player)
    end
    OGRH.ScheduleBuffShame(report, 30)
  else
    OGRH.AnnounceBuffShame(report)
  end
end

function OGRH.AnnounceBuffShame(report)
  local settings = OGRH.GetBuffManagerSettings()
  local threshold = settings.shameThreshold or 80

  local totalCoverage = OGRH.CalculateOverallBuffCoverage()

  if totalCoverage < threshold then
    local msg = string.format("Buff Coverage: %d%% - UNACCEPTABLE!", math.floor(totalCoverage))
    ChatThrottleLib:SendChatMessage("ALERT", "OGRH", msg, "RAID_WARNING")

    for _, failure in ipairs(report.underperformingBuffers) do
      local shameMsg = string.format("%s: %d unbuffed in %s groups",
        failure.player, failure.unbuffedCount, failure.buffType)
      ChatThrottleLib:SendChatMessage("NORMAL", "OGRH", shameMsg, "RAID")
    end
  end
end
```

---

## Companion Modules

### 1. Priest Buff Monitor

```lua
-- _Companions/PriestBuffs.lua
OGRH.PriestBuffs = {}

function OGRH.PriestBuffs.GetAvailableBuffs(playerName)
  local buffs = {}
  if OGRH.PlayerHasSpell(playerName, 21562) or OGRH.PlayerHasSpell(playerName, 21564) then
    table.insert(buffs, {name = "Fortitude", type = "prayer", spellId = 21564})
  elseif OGRH.PlayerHasSpell(playerName, 1243) then
    table.insert(buffs, {name = "Fortitude", type = "single", spellId = 10938})
  end
  return buffs
end

function OGRH.PriestBuffs.GetOptimalCoverage(priests, raidSize)
  -- Algorithm to optimally distribute priests across groups
  -- Prefer prayers over single-target buffs when possible
end
```

### 2. Druid Buff Monitor

```lua
-- _Companions/DruidBuffs.lua
OGRH.DruidBuffs = {}

function OGRH.DruidBuffs.GetAvailableBuffs(playerName)
  local buffs = {}
  if OGRH.PlayerHasSpell(playerName, 21849) or OGRH.PlayerHasSpell(playerName, 21850) then
    table.insert(buffs, {name = "Mark of the Wild", type = "party", spellId = 21850})
  elseif OGRH.PlayerHasSpell(playerName, 1126) then
    table.insert(buffs, {name = "Mark of the Wild", type = "single", spellId = 9885})
  end
  return buffs
end
```

### 3. Mage Buff Monitor

```lua
-- _Companions/MageBuffs.lua
OGRH.MageBuffs = {}

function OGRH.MageBuffs.GetAvailableBuffs(playerName)
  local buffs = {}
  if OGRH.PlayerHasSpell(playerName, 23028) or OGRH.PlayerHasSpell(playerName, 27126) then
    table.insert(buffs, {name = "Arcane Brilliance", type = "party", spellId = 27126})
  elseif OGRH.PlayerHasSpell(playerName, 1459) then
    table.insert(buffs, {name = "Arcane Intellect", type = "single", spellId = 10157})
  end
  return buffs
end
```

---

## API Functions

### `OGRH.RenderBuffManagerRole(container, role, roleIndex, raidIdx, encounterIdx, containerWidth)`
Renders the compact buff status summary inside the Admin encounter.

**Parameters:**
- `container` (frame) — Parent container from EncounterMgmt role rendering
- `role` (table) — The BuffManager role data
- `roleIndex` (number) — Role index in Admin encounter
- `raidIdx` (number) — Raid index
- `encounterIdx` (number) — Encounter index (always 1 for Admin)
- `containerWidth` (number) — Available width

**Returns:** Frame — the rendered summary frame

---

### `OGRH.ShowBuffManagerWindow(raidIdx, encounterIdx, roleIndex)`
Opens the full Buff Manager configuration window.

**Parameters:**
- `raidIdx` (number) — Raid index
- `encounterIdx` (number) — Encounter index (1)
- `roleIndex` (number) — Role index of the BuffManager role in Admin

**Returns:** `nil`

---

### `OGRH.SetBuffGroupAssignment(buffRoleIndex, slotIndex, groupNumber, enabled)`
Assigns or unassigns a player to buff a specific group.

**Parameters:**
- `buffRoleIndex` (number) — Buff role index within `buffRoles`
- `slotIndex` (number) — Player slot index
- `groupNumber` (number) — Group number 1-8
- `enabled` (boolean) — Assign or unassign

---

### `OGRH.ScanRaidBuffs()`
Performs a scan of all raid members' buffs.

**Returns:** Table with buff data

---

### `OGRH.CalculateBuffCoverage(buffType)`
Calculates coverage percentage for a specific buff type.

**Parameters:**
- `buffType` (string) — "fortitude", "spirit", "motw", etc.

**Returns:** Table with `{buffed, total, missing}`

---

### `OGRH.AnnounceMissingBuffs(whisperFirst)`
Announces missing buffs to raid chat.

**Parameters:**
- `whisperFirst` (boolean) — Whisper underperformers before public shame

---

### `OGRH.ImportFromPallyPower()`
Imports paladin assignments from PallyPower addon.

**Returns:** Table with imported assignments or `false`

---

### `OGRH.BroadcastToPallyPower()`
Broadcasts current paladin assignments to PallyPower addon.

**Returns:** `boolean` — Success status

---

### `OGRH.UpdateAdminBuffIndicators()`
Refreshes the compact buff status indicators in the Admin encounter role. Called after each buff scan and when the Buff Manager window saves changes.

---

## Usage Examples

### Example 1: Basic Setup

```lua
-- Buff data lives inside Admin encounter role 5
local adminEnc = OGRH.SVM.GetPath("encounterMgmt.raids[1].encounters[1]")
local buffRole = adminEnc.roles[5]  -- isBuffManager = true

-- Assign priests to groups
local fortRole = buffRole.buffRoles[1]
fortRole.assignedPlayers[1] = "Priestbro"
fortRole.groupAssignments[1] = {1, 2, 3}

fortRole.assignedPlayers[2] = "Holyman"
fortRole.groupAssignments[2] = {4, 5, 6, 7, 8}

-- Start scanning
OGRH.StartBuffScanning()
```

### Example 2: Paladin Assignments

```lua
local buffRole = OGRH.GetAdminBuffManagerRole(1)  -- raidIdx=1
local paladinRole = buffRole.buffRoles[6]

paladinRole.assignedPlayers[1] = "Retpal"
paladinRole.paladinAssignments[1] = {
  classes = {"WARRIOR", "ROGUE"},
  blessing = "might"
}

paladinRole.assignedPlayers[2] = "Holypal"
paladinRole.paladinAssignments[2] = {
  classes = {"MAGE", "WARLOCK"},
  blessing = "wisdom"
}

OGRH.BroadcastToPallyPower()
```

### Example 3: Buff Compliance Check

```lua
OGRH.ScanRaidBuffs()

local overallCoverage = OGRH.CalculateOverallBuffCoverage()
if overallCoverage < 80 then
  OGRH.AnnounceMissingBuffs(true)  -- Whisper first
end
```

---

## Testing Considerations

### Test Cases

1. **Admin Role Rendering:**
   - Open Admin encounter → Buff Manager role renders in right column
   - Buff indicators show correct colors based on coverage
   - "Manage Buffs" button opens the window

2. **Buff Manager Window:**
   - Window opens via `OGST.CreateStandardWindow`
   - All buff sections render with correct OGST components
   - Closes on Escape via `OGST.MakeFrameCloseOnEscape`

3. **Group Assignments:**
   - `OGST.CreateCheckbox` checkboxes toggle correctly for groups 1-8
   - Assignments save to SVM under Admin encounter path
   - Conflict detection for overlapping assignments

4. **Coverage Calculation:**
   - `OGST.CreateProgressBar` updates with correct percentage
   - Color coding: green >= 100%, yellow >= 80%, red < 80%
   - Coverage text matches bar value

5. **PallyPower Integration:**
   - Import from PallyPower populates `OGST.CreateMenuButton` dropdowns
   - Broadcast updates `PP_Assignment` table
   - `OGST.CreateCheckbox` sync toggles work correctly

6. **Buff Scanning:**
   - Scan detects all buff types on raid members
   - Auto-scan interval triggers correctly
   - Admin role indicators refresh after each scan

7. **Announcements:**
   - Missing buff report generates correctly
   - Whisper-first mode sends whispers, then shames after delay
   - Threshold setting respected

8. **Persistence:**
   - Buff assignments survive /reload
   - Settings persist per raid template
   - SVM paths resolve correctly under Admin encounter

---

## Future Enhancements

### Automation
- **Auto-Assignment:** Automatically distribute buffers across groups based on class availability
- **Smart Suggestions:** Recommend optimal group assignments
- **Auto-Whisper:** Whisper specific players when their buffs expire

### Advanced Tracking
- **Buff Uptime:** Track historical buff uptime per player
- **Performance Metrics:** Rate buffers on consistency
- **Boss Fight Analysis:** Buff compliance during actual encounters

### Integration
- **Consume Monitor:** Unified compliance dashboard
- **BigWigs/DBM:** Auto-remind buffers before boss pulls
- **Loot Integration:** Bonus loot priority for high compliance

### UI Improvements
- **Color Coding:** Visual indicators for buff status
- **Mini-Map Icon:** Quick access to buff tracker
- **Raid Frames Integration:** Show buff status on raid frames

---

## Implementation Priority

### Phase 0 (Shared Roster Panel — prerequisite)
- [x] Create `_UI/RosterPanel.lua` with `OGRH.CreateRosterPanel` and `OGRH.EnableRosterDrag`
- [x] Extract EncounterMgmt.lua players panel (L1488-1742) to use `OGRH.CreateRosterPanel`
- [x] Extract EncounterMgmt.lua `RefreshPlayersList` (L2375-2870) to use `panel:Refresh()`
- [x] Extract EncounterMgmt.lua drag-from-player (L2732-2849) to use `OGRH.EnableRosterDrag`
- [x] Verify Encounter Planning still works identically after extraction
- [x] Add `_UI\RosterPanel.lua` to `OG-RaidHelper.toc`

### Phase 1 (Core)
- [x] BuffManager role in Admin encounter template (`isBuffManager = true`)
- [x] `RenderBuffManagerRole` with compact indicators using OGST components
- [x] Buff Manager window via `OGST.CreateStandardWindow` (710×550)
- [x] Roster panel in Buff Manager window via `OGRH.CreateRosterPanel`
- [x] Basic buff role UI with `OGST.CreateCheckbox` group checkboxes
- [x] Drag-and-drop from roster panel to buff assignment slots
- [x] Simple buff scanning
- [x] Coverage calculation with `OGST.CreateProgressBar`

### Phase 2 (Paladin)
- [x] Paladin role special UI with `OGST.CreateMenuButton` dropdowns
- [x] Per-class buff assignments via `OGST.CreateCheckbox`
- [x] PallyPower import
- [x] PallyPower broadcast

### Phase 3 (Tracking)
- [ ] Real-time buff tracker window (`OGST.CreateStandardWindow`)
- [ ] Automatic scanning with OnUpdate
- [ ] Missing buff detection
- [ ] Admin role indicator auto-refresh

### Phase 4 (Announcements)
- [ ] Missing buff report generation
- [ ] Whisper system
- [ ] Public announcements
- [ ] Consume integration

### Phase 5 (Companions)
- [ ] Priest buff module
- [ ] Druid buff module
- [ ] Mage buff module
- [ ] Smart recommendations

---

## Related Modules

- **`_UI/RosterPanel.lua` (NEW):** Shared roster panel component — used by both EncounterMgmt and BuffManager for the player list / drag-drop panel
- **`_Raid/EncounterAdmin.lua`:** Admin encounter template — hosts the BuffManager role
- **`_Raid/EncounterMgmt.lua`:** Encounter rendering — needs `isBuffManager` branch in `CreateRoleContainer`; roster panel refactored to use shared `OGRH.CreateRosterPanel`
- **`_Infrastructure/Announce.lua`:** Announcement system for buff shaming
- **`ConsumeMon.lua`:** Consume tracking integration for combined compliance
- **PallyPower (external):** Third-party addon integration
- **`_OGST/OGST.lua`:** UI toolkit — all interactive components must use OGST

---

## Change Log

| Version | Date | Changes |
|---------|------|---------|
| 2.1.0 | Feb 2026 | Initial BuffManager specification |
| 2.1.0 | Feb 2026 | Reworked: moved from standalone encounter to Admin encounter role; added OGST toolkit requirement |
| 2.1.0 | Feb 2026 | Added roster panel to window layout (710px wide); added shared `_UI/RosterPanel.lua` spec with extraction plan from EncounterMgmt; added Phase 0 prerequisite |

