# BuffManager Specification

**Version:** 2.1  
**Module:** BuffManager.lua  
**Location:** `_Raid/BuffManager.lua`

---

## Overview

BuffManager is an optional encounter-based buff coordination system inspired by PallyPower, expanded to handle all raid buffs across all classes. It provides visual assignment of buff responsibilities to specific players and groups, tracks buff compliance, and provides shameable announcements for missing buffs.

---

## Key Features

### 1. Optional Encounter at Index 2

- **Position:** Always at encounter index 2 (after Admin at index 1)
- **Toggle:** Enabled/Disabled via raid's Advanced Settings
- **Auto-Creation:** Automatically added when enabled, removed when disabled
- **Persistence:** Settings persist per raid template

### 2. Multi-Class Buff Coordination

**Supported Buffs:**
- **Fortitude** (Priest) - Power Word: Fortitude / Prayer of Fortitude
- **Spirit** (Priest) - Divine Spirit / Prayer of Spirit
- **Shadow Protection** (Priest) - Shadow Protection / Prayer of Shadow Protection
- **Mark of the Wild** (Druid) - Mark of the Wild / Gift of the Wild
- **Arcane Brilliance** (Mage) - Arcane Intellect / Arcane Brilliance
- **Paladin Blessings** (Paladin) - Per-class assignments (Might, Wisdom, Kings, Salvation, etc.)

### 3. Group-Based Assignment System

- Each buff role has player assignment slots
- Each slot has **8 checkboxes** for raid groups 1-8
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
- **Group Coverage:** Shows which groups have full coverage
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

## Encounter Structure

### BuffManager Encounter Template

```lua
local BUFFMANAGER_ENCOUNTER_TEMPLATE = {
  name = "BuffManager",
  displayName = "Buff Manager",
  isBuffManager = true,  -- Special flag
  roles = {
    -- Role 1: Fortitude (Priest)
    {
      roleId = 1,
      name = "Fortitude",
      buffType = "fortitude",
      spellIds = {1243, 1244, 1245, 2791, 10937, 10938, 21562, 21564},  -- All ranks + Prayer
      slots = 3,  -- Max 3 priests
      groupAssignments = {
        -- playerSlot -> array of group numbers
        [1] = {1, 2, 3},  -- Player 1 assigned groups 1-3
        [2] = {4, 5, 6},  -- Player 2 assigned groups 4-6
        [3] = {7, 8}      -- Player 3 assigned groups 7-8
      },
      assignedPlayers = {},
      showRaidIcons = false,
      showAssignment = false,
      allowOtherRoles = true
    },
    -- Role 2: Spirit (Priest)
    {
      roleId = 2,
      name = "Spirit",
      buffType = "spirit",
      spellIds = {14752, 14818, 14819, 27841, 25312, 27681},
      slots = 3,
      groupAssignments = {},
      assignedPlayers = {},
      showRaidIcons = false,
      showAssignment = false,
      allowOtherRoles = true
    },
    -- Role 3: Shadow Protection (Priest)
    {
      roleId = 3,
      name = "Shadow Protection",
      buffType = "shadowprot",
      spellIds = {976, 10957, 10958, 27683, 39374},
      slots = 2,
      groupAssignments = {},
      assignedPlayers = {},
      showRaidIcons = false,
      showAssignment = false,
      allowOtherRoles = true
    },
    -- Role 4: Mark of the Wild (Druid)
    {
      roleId = 4,
      name = "Mark of the Wild",
      buffType = "motw",
      spellIds = {1126, 5232, 6756, 5234, 8907, 9884, 9885, 21849, 21850},
      slots = 3,
      groupAssignments = {},
      assignedPlayers = {},
      showRaidIcons = false,
      showAssignment = false,
      allowOtherRoles = true
    },
    -- Role 5: Arcane Brilliance (Mage)
    {
      roleId = 5,
      name = "Arcane Brilliance",
      buffType = "int",
      spellIds = {1459, 1460, 1461, 10156, 10157, 23028, 27126},
      slots = 3,
      groupAssignments = {},
      assignedPlayers = {},
      showRaidIcons = false,
      showAssignment = false,
      allowOtherRoles = true
    },
    -- Role 6: Paladin Blessings (Special)
    {
      roleId = 6,
      name = "Paladin Blessings",
      buffType = "paladin",
      isPaladinRole = true,
      slots = 5,  -- Max 5 paladins
      paladinAssignments = {
        -- playerSlot -> classAssignments
        [1] = {
          classes = {"WARRIOR", "ROGUE"},  -- This paladin buffs Warriors and Rogues
          blessing = "might"                -- Blessing of Might
        },
        [2] = {
          classes = {"MAGE", "WARLOCK"},
          blessing = "wisdom"
        },
        [3] = {
          classes = {"PRIEST", "DRUID"},
          blessing = "wisdom"
        },
        [4] = {
          classes = {"HUNTER"},
          blessing = "might"
        },
        [5] = {
          classes = {"PALADIN"},
          blessing = "kings"
        }
      },
      assignedPlayers = {},
      showRaidIcons = false,
      showAssignment = false,
      allowOtherRoles = true
    }
  },
  settings = {
    enabled = false,              -- Master enable/disable
    autoScan = true,              -- Automatic buff scanning
    scanInterval = 30,            -- Scan every 30 seconds
    warnThreshold = 5,            -- Warn if buff expires in 5 minutes
    shameThreshold = 80,          -- Shame if less than 80% coverage
    whisperFirst = true,          -- Whisper before shaming
    pallyPowerSync = false,       -- Sync with PallyPower addon
    pallyPowerBroadcast = false   -- Broadcast to PallyPower
  }
}
```

---

## UI Components

### 1. Advanced Settings Toggle

In the raid's Advanced Settings window, add BuffManager control:

```
┌─────────────────────────────────────────────┐
│ Raid Advanced Settings                      │
├─────────────────────────────────────────────┤
│ ... existing settings ...                   │
├─────────────────────────────────────────────┤
│ Buff Manager                                │
│ ☐ Enable Buff Manager                       │
│   Automatically coordinate raid buffs       │
│   across Priests, Druids, Mages, Paladins  │
│                                             │
│   [Configure Buff Assignments]              │
└─────────────────────────────────────────────┘
```

**Behavior:**
- Checking box creates BuffManager encounter at index 2
- Unchecking removes it (with confirmation)
- Configure button opens BuffManager planning window

### 2. BuffManager Planning Window

Extended version of standard Encounter Planning with special buff UI:

```
┌───────────────────────────────────────────────────────────────┐
│ Buff Manager                            [Settings] [Track] [X]│
├───────────────────────────────────────────────────────────────┤
│ ┌─ Fortitude (Priest) ──────────────────────────────────────┐│
│ │ Player 1: [Dropdown: Player Name]  Groups: [1][2][3][4][5][6][7][8] │
│ │ Player 2: [Dropdown: Player Name]  Groups: [1][2][3][4][5][6][7][8] │
│ │ Player 3: [Dropdown: Player Name]  Groups: [1][2][3][4][5][6][7][8] │
│ │ Coverage: ████████ 100% (40/40 players)                   │
│ └───────────────────────────────────────────────────────────┘│
│ ┌─ Spirit (Priest) ─────────────────────────────────────────┐│
│ │ Player 1: [Dropdown: Player Name]  Groups: [1][2][3][4][5][6][7][8] │
│ │ Player 2: [Dropdown: Player Name]  Groups: [1][2][3][4][5][6][7][8] │
│ │ Coverage: ████░░░░ 60% (24/40 players)                    │
│ └───────────────────────────────────────────────────────────┘│
│ ┌─ Mark of the Wild (Druid) ───────────────────────────────┐│
│ │ Player 1: [Dropdown: Player Name]  Groups: [1][2][3][4][5][6][7][8] │
│ │ Coverage: ████████ 100% (40/40 players)                   │
│ └───────────────────────────────────────────────────────────┘│
│ ┌─ Paladin Blessings ───────────────────────────────────────┐│
│ │ Paladin 1: [Dropdown: Name]  → [Warrior▼] [Rogue▼]       │
│ │            Blessing: [Might ▼]                             │
│ │ Paladin 2: [Dropdown: Name]  → [Mage▼] [Warlock▼]        │
│ │            Blessing: [Wisdom ▼]                            │
│ │ ☑ Sync with PallyPower  ☐ Broadcast to PallyPower        │
│ │ Coverage: ████████ 100% (40/40 players)                   │
│ └───────────────────────────────────────────────────────────┘│
└───────────────────────────────────────────────────────────────┘
```

### 3. Group Assignment Checkboxes

Each player slot has 8 checkboxes for groups:

```lua
-- Create group checkboxes for a player slot
local function CreateGroupCheckboxes(parent, roleIndex, slotIndex)
  local checkboxes = {}
  
  for group = 1, 8 do
    local checkbox = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    checkbox:SetWidth(16)
    checkbox:SetHeight(16)
    checkbox:SetPoint("LEFT", parent, "LEFT", 100 + (group - 1) * 20, 0)
    
    -- Label
    local label = checkbox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOP", checkbox, "BOTTOM", 0, -2)
    label:SetText(group)
    label:SetTextColor(0.7, 0.7, 0.7)
    
    -- Click handler
    checkbox:SetScript("OnClick", function()
      local checked = this:GetChecked()
      OGRH.SetBuffGroupAssignment(roleIndex, slotIndex, group, checked)
      OGRH.UpdateBuffCoverage()
    end)
    
    -- Tooltip
    checkbox:SetScript("OnEnter", function()
      GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
      GameTooltip:SetText("Group " .. group, 1, 1, 1)
      GameTooltip:AddLine("Assign this player to buff group " .. group, 0.8, 0.8, 0.8, 1)
      GameTooltip:Show()
    end)
    checkbox:SetScript("OnLeave", function()
      GameTooltip:Hide()
    end)
    
    checkboxes[group] = checkbox
  end
  
  return checkboxes
end
```

### 4. Paladin Assignment UI

Special UI for per-class buff assignments:

```lua
-- Create paladin class assignment UI
local function CreatePaladinAssignmentUI(parent, slotIndex)
  local frame = CreateFrame("Frame", nil, parent)
  frame:SetWidth(400)
  frame:SetHeight(30)
  
  -- Player dropdown
  local playerDropdown = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  playerDropdown:SetWidth(150)
  playerDropdown:SetHeight(20)
  playerDropdown:SetPoint("LEFT", frame, "LEFT", 0, 0)
  playerDropdown:SetText("Select Paladin")
  
  -- Class selection (multi-select)
  local classFrame = CreateFrame("Frame", nil, frame)
  classFrame:SetWidth(200)
  classFrame:SetHeight(20)
  classFrame:SetPoint("LEFT", playerDropdown, "RIGHT", 10, 0)
  
  local classes = {"WARRIOR", "ROGUE", "HUNTER", "MAGE", "WARLOCK", "PRIEST", "DRUID", "PALADIN"}
  local classButtons = {}
  
  for i, class in ipairs(classes) do
    local btn = CreateFrame("CheckButton", nil, classFrame, "UICheckButtonTemplate")
    btn:SetWidth(16)
    btn:SetHeight(16)
    btn:SetPoint("LEFT", classFrame, "LEFT", (i - 1) * 20, 0)
    
    -- Class icon/color
    local icon = btn:CreateTexture(nil, "OVERLAY")
    icon:SetTexture("Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes")
    icon:SetAllPoints()
    -- Set texture coordinates based on class
    
    btn:SetScript("OnClick", function()
      OGRH.TogglePaladinClassAssignment(slotIndex, class, this:GetChecked())
    end)
    
    classButtons[class] = btn
  end
  
  -- Blessing dropdown
  local blessingDropdown = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  blessingDropdown:SetWidth(100)
  blessingDropdown:SetHeight(20)
  blessingDropdown:SetPoint("LEFT", classFrame, "RIGHT", 10, 0)
  blessingDropdown:SetText("Might")
  
  frame.playerDropdown = playerDropdown
  frame.classButtons = classButtons
  frame.blessingDropdown = blessingDropdown
  
  return frame
end
```

### 5. Coverage Display

Visual progress bar showing buff coverage:

```lua
local function UpdateCoverageDisplay(roleFrame, coverage)
  local bar = roleFrame.coverageBar
  local text = roleFrame.coverageText
  
  -- Calculate percentage
  local percent = (coverage.buffed / coverage.total) * 100
  
  -- Update bar width
  bar:SetWidth(math.floor((300 * percent) / 100))
  
  -- Color coding
  if percent >= 100 then
    bar:SetVertexColor(0, 1, 0)  -- Green
  elseif percent >= 80 then
    bar:SetVertexColor(1, 1, 0)  -- Yellow
  else
    bar:SetVertexColor(1, 0, 0)  -- Red
  end
  
  -- Update text
  text:SetText(string.format("%d%% (%d/%d players)", 
    math.floor(percent), 
    coverage.buffed, 
    coverage.total))
end
```

### 6. Buff Tracking Window

Real-time buff status display:

```
┌─────────────────────────────────────────────────┐
│ Buff Tracker                         [Scan] [X] │
├─────────────────────────────────────────────────┤
│ Last Scan: 15 seconds ago                       │
│ Overall Coverage: 87% (35/40 players)           │
├─────────────────────────────────────────────────┤
│ Missing Buffs:                                  │
│   Group 1: Tankmedady - Missing Fort, Spirit   │
│   Group 3: Gnuzmas - Missing Spirit             │
│   Group 5: Shadyman - Missing Mark, Int         │
│   Group 7: Holyman - Missing Fort               │
│                                                 │
│ Buff Assignments Not Met:                      │
│   Priestbro (Fort, Groups 1-3): 2 unbuffed     │
│   Druidguy (MotW, Groups 4-5): 3 unbuffed      │
│                                                 │
│ [Whisper Missing] [Announce Report]            │
└─────────────────────────────────────────────────┘
```

---

## Buff Tracking System

### 1. Raid Scan

```lua
function OGRH.ScanRaidBuffs()
  local buffData = {
    timestamp = GetTime(),
    players = {}
  }
  
  -- Iterate through raid members
  for i = 1, GetNumRaidMembers() do
    local name, rank, subgroup, level, class = GetRaidRosterInfo(i)
    if name then
      local playerData = {
        name = name,
        class = class,
        group = subgroup,
        buffs = {}
      }
      
      -- Scan buffs on unit
      local unitId = "raid" .. i
      for buffSlot = 1, 32 do
        local buffName, rank, icon, count, debuffType, duration, expirationTime = UnitBuff(unitId, buffSlot)
        if not buffName then
          break
        end
        
        -- Categorize buff type
        local buffType = OGRH.GetBuffCategory(buffName)
        if buffType then
          playerData.buffs[buffType] = {
            name = buffName,
            duration = duration,
            expiration = expirationTime,
            timeLeft = expirationTime - GetTime()
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
  -- Fortitude
  if string.find(buffName, "Fortitude") then
    return "fortitude"
  end
  
  -- Spirit
  if string.find(buffName, "Divine Spirit") or string.find(buffName, "Prayer of Spirit") then
    return "spirit"
  end
  
  -- Shadow Protection
  if string.find(buffName, "Shadow Protection") then
    return "shadowprot"
  end
  
  -- Mark of the Wild
  if string.find(buffName, "Mark of the Wild") or string.find(buffName, "Gift of the Wild") then
    return "motw"
  end
  
  -- Arcane Intellect / Brilliance
  if string.find(buffName, "Arcane Intellect") or string.find(buffName, "Arcane Brilliance") then
    return "int"
  end
  
  -- Paladin Blessings
  if string.find(buffName, "Blessing of") or string.find(buffName, "Greater Blessing") then
    return "paladin"
  end
  
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
  
  local coverage = {
    buffed = 0,
    total = 0,
    missing = {}
  }
  
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
-- Setup automatic scanning
function OGRH.StartBuffScanning()
  if OGRH.BuffManager.scanFrame then
    return  -- Already running
  end
  
  local frame = CreateFrame("Frame")
  local elapsed = 0
  local interval = OGRH.GetBuffScanInterval()
  
  frame:SetScript("OnUpdate", function()
    elapsed = elapsed + arg1
    if elapsed >= interval then
      elapsed = 0
      OGRH.ScanRaidBuffs()
      OGRH.UpdateBuffTrackerUI()
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
  if not PP_Assignment then
    return false  -- PallyPower not installed/loaded
  end
  
  -- PP_Assignment structure: [playerName][className] = blessingId
  local paladinAssignments = {}
  
  for playerName, classAssignments in pairs(PP_Assignment) do
    local assignment = {
      player = playerName,
      classes = {},
      blessing = nil
    }
    
    for className, blessingId in pairs(classAssignments) do
      table.insert(assignment.classes, className)
      -- Convert blessing ID to name
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
  if not paladinRole then
    return false
  end
  
  -- Convert our assignments to PallyPower format
  for slotIndex, assignment in pairs(paladinRole.paladinAssignments) do
    local playerName = paladinRole.assignedPlayers[slotIndex]
    if playerName and assignment.classes then
      if not PP_Assignment[playerName] then
        PP_Assignment[playerName] = {}
      end
      
      local blessingId = OGRH.GetBlessingId(assignment.blessing)
      for _, className in ipairs(assignment.classes) do
        PP_Assignment[playerName][className] = blessingId
      end
    end
  end
  
  -- Trigger PallyPower update
  if PP_Update then
    PP_Update()
  end
  
  OGRH.Msg("|cff00ff00[BuffManager]|r Assignments broadcast to PallyPower")
  return true
end
```

### 3. Two-Way Sync

```lua
-- Sync button in settings
local syncBtn = CreateFrame("Button", nil, settingsFrame, "UIPanelButtonTemplate")
syncBtn:SetText("Sync with PallyPower")
syncBtn:SetScript("OnClick", function()
  local imported = OGRH.ImportFromPallyPower()
  if imported then
    OGRH.ApplyPaladinAssignments(imported)
    OGRH.Msg("|cff00ff00[BuffManager]|r Imported assignments from PallyPower")
  else
    OGRH.Msg("|cffff6666[BuffManager]|r Could not import from PallyPower")
  end
end)

-- Broadcast button
local broadcastBtn = CreateFrame("Button", nil, settingsFrame, "UIPanelButtonTemplate")
broadcastBtn:SetText("Broadcast to PallyPower")
broadcastBtn:SetScript("OnClick", function()
  OGRH.BroadcastToPallyPower()
end)
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
    
    -- Find unbuffed players
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
    
    -- Find buffers not meeting their assignments
    local role = OGRH.GetBuffRole(buffType)
    if role then
      for slotIndex, playerName in pairs(role.assignedPlayers) do
        if playerName then
          local assignedGroups = role.groupAssignments[slotIndex] or {}
          local unbuffedInGroups = OGRH.CountUnbuffedInGroups(buffType, assignedGroups)
          
          if unbuffedInGroups > 0 then
            if not report.underperformingBuffers[playerName] then
              report.underperformingBuffers[playerName] = {}
            end
            table.insert(report.underperformingBuffers[playerName], {
              buffType = buffType,
              groups = assignedGroups,
              unbuffedCount = unbuffedInGroups
            })
          end
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
    -- Send private whispers first
    for playerName, failures in pairs(report.underperformingBuffers) do
      local msg = "You have unbuffed players in your assigned groups:"
      for _, failure in ipairs(failures) do
        msg = msg .. " " .. failure.buffType .. " (Groups " .. table.concat(failure.groups, ",") .. ")"
      end
      SendChatMessage(msg, "WHISPER", nil, playerName)
    end
    
    -- Wait before public shame
    OGRH.ScheduleBuffShame(report, 30)  -- 30 second grace period
  else
    -- Public announcement immediately
    OGRH.AnnounceBuffShame(report)
  end
end

function OGRH.AnnounceBuffShame(report)
  local settings = OGRH.GetBuffManagerSettings()
  local threshold = settings.shameThreshold or 80
  
  -- Calculate overall coverage
  local totalCoverage = OGRH.CalculateOverallBuffCoverage()
  
  if totalCoverage < threshold then
    local msg = string.format("Buff Coverage: %d%% - UNACCEPTABLE!", math.floor(totalCoverage))
    ChatThrottleLib:SendChatMessage("ALERT", "OGRH", msg, "RAID_WARNING")
    
    -- List underperforming buffers
    for playerName, failures in pairs(report.underperformingBuffers) do
      local failureText = ""
      for _, failure in ipairs(failures) do
        failureText = failureText .. failure.buffType .. " "
      end
      local shameMsg = playerName .. " is not buffing: " .. failureText
      ChatThrottleLib:SendChatMessage("NORMAL", "OGRH", shameMsg, "RAID")
    end
  end
end
```

### 3. Integration with Consume Logging

```lua
function OGRH.GenerateCombinedComplianceReport()
  local buffReport = OGRH.GenerateMissingBuffReport()
  local consumeReport = OGRH.ConsumeMon.GetComplianceReport()  -- From consume tracker
  
  local combined = {
    timestamp = GetTime(),
    slackers = {}
  }
  
  -- Cross-reference players in both systems
  for playerName, buffData in pairs(buffReport.unbuffedPlayers) do
    if not combined.slackers[playerName] then
      combined.slackers[playerName] = {
        missingBuffs = buffData.missingBuffs,
        missingConsumes = {}
      }
    end
  end
  
  if consumeReport then
    for playerName, consumeData in pairs(consumeReport.missingConsumes) do
      if not combined.slackers[playerName] then
        combined.slackers[playerName] = {
          missingBuffs = {},
          missingConsumes = consumeData
        }
      else
        combined.slackers[playerName].missingConsumes = consumeData
      end
    end
  end
  
  return combined
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
  
  -- Check if player has Prayer of Fortitude
  if OGRH.PlayerHasSpell(playerName, 21562) or OGRH.PlayerHasSpell(playerName, 21564) then
    table.insert(buffs, {name = "Fortitude", type = "prayer", spellId = 21564})
  elseif OGRH.PlayerHasSpell(playerName, 1243) then
    table.insert(buffs, {name = "Fortitude", type = "single", spellId = 10938})
  end
  
  -- Similar checks for Spirit, Shadow Protection
  
  return buffs
end

function OGRH.PriestBuffs.GetOptimalCoverage(priests, raidSize)
  -- Algorithm to optimally distribute priests across groups
  -- Prefer prayers over single-target buffs when possible
  -- Returns recommended group assignments
end
```

### 2. Druid Buff Monitor

```lua
-- _Companions/DruidBuffs.lua
OGRH.DruidBuffs = {}

function OGRH.DruidBuffs.GetAvailableBuffs(playerName)
  local buffs = {}
  
  -- Check for Gift of the Wild
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
  
  -- Check for Arcane Brilliance
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

### `OGRH.CreateBuffManagerEncounter()`
Creates a fresh BuffManager encounter from template.

**Returns:** Table containing complete BuffManager encounter structure

---

### `OGRH.EnableBuffManager(raidIdx)`
Enables BuffManager for the specified raid, adding encounter at index 2.

**Parameters:**
- `raidIdx` (number) - Raid index

**Returns:** `boolean` - Success status

---

### `OGRH.DisableBuffManager(raidIdx)`
Disables BuffManager for the specified raid, removing encounter.

**Parameters:**
- `raidIdx` (number) - Raid index

**Returns:** `boolean` - Success status

---

### `OGRH.IsBuffManagerEnabled(raidIdx)`
Checks if BuffManager is enabled for a raid.

**Parameters:**
- `raidIdx` (number) - Raid index

**Returns:** `boolean`

---

### `OGRH.SetBuffGroupAssignment(roleIndex, slotIndex, groupNumber, enabled)`
Assigns or unassigns a player to buff a specific group.

**Parameters:**
- `roleIndex` (number) - Role index in encounter
- `slotIndex` (number) - Player slot index
- `groupNumber` (number) - Group number 1-8
- `enabled` (boolean) - Assign or unassign

**Returns:** `nil`

---

### `OGRH.ScanRaidBuffs()`
Performs a scan of all raid members' buffs.

**Returns:** Table with buff data

---

### `OGRH.CalculateBuffCoverage(buffType)`
Calculates coverage percentage for a specific buff type.

**Parameters:**
- `buffType` (string) - "fortitude", "spirit", "motw", etc.

**Returns:** Table with coverage stats

---

### `OGRH.AnnounceMissingBuffs(whisperFirst)`
Announces missing buffs to raid chat.

**Parameters:**
- `whisperFirst` (boolean) - Whisper underperformers before public shame

**Returns:** `nil`

---

### `OGRH.ImportFromPallyPower()`
Imports paladin assignments from PallyPower addon.

**Returns:** Table with imported assignments or `false`

---

### `OGRH.BroadcastToPallyPower()`
Broadcasts current paladin assignments to PallyPower addon.

**Returns:** `boolean` - Success status

---

## Usage Examples

### Example 1: Basic Setup

```lua
-- Enable BuffManager for a raid
OGRH.EnableBuffManager(1)  -- Active Raid

-- Assign priests to groups
local fortRole = GetBuffRole("fortitude")
fortRole.assignedPlayers[1] = "Priestbro"
fortRole.groupAssignments[1] = {1, 2, 3}

fortRole.assignedPlayers[2] = "Holyman"
fortRole.groupAssignments[2] = {4, 5, 6, 7, 8}

-- Start automatic scanning
OGRH.StartBuffScanning()
```

### Example 2: Paladin Assignments

```lua
local paladinRole = GetBuffRole("paladin")

-- Paladin 1: Might on Warriors and Rogues
paladinRole.assignedPlayers[1] = "Retpal"
paladinRole.paladinAssignments[1] = {
  classes = {"WARRIOR", "ROGUE"},
  blessing = "might"
}

-- Paladin 2: Wisdom on Mages and Warlocks
paladinRole.assignedPlayers[2] = "Holypal"
paladinRole.paladinAssignments[2] = {
  classes = {"MAGE", "WARLOCK"},
  blessing = "wisdom"
}

-- Broadcast to PallyPower
OGRH.BroadcastToPallyPower()
```

### Example 3: Buff Compliance Check

```lua
-- Scan raid
OGRH.ScanRaidBuffs()

-- Generate report
local report = OGRH.GenerateMissingBuffReport()

-- Announce if coverage is low
local overallCoverage = OGRH.CalculateOverallBuffCoverage()
if overallCoverage < 80 then
  OGRH.AnnounceMissingBuffs(true)  -- Whisper first
end
```

---

## Testing Considerations

### Test Cases

1. **Encounter Creation:**
   - Enable BuffManager from Advanced Settings
   - Verify encounter appears at index 2
   - Disable and verify encounter is removed

2. **Group Assignments:**
   - Assign players to multiple groups
   - Verify checkboxes update correctly
   - Test conflict detection (overlapping assignments)

3. **Coverage Calculation:**
   - Mock raid with various buff states
   - Verify coverage percentages accurate
   - Test with missing buffs

4. **PallyPower Integration:**
   - Import from PallyPower
   - Modify assignments
   - Broadcast back to PallyPower
   - Verify sync accuracy

5. **Buff Scanning:**
   - Join raid and scan buffs
   - Verify buff detection works for all types
   - Test with multiple ranks of same buff

6. **Announcements:**
   - Generate missing buff report
   - Test whisper-first mode
   - Test public shame announcements
   - Verify threshold settings work

7. **UI Interaction:**
   - Click group checkboxes
   - Change paladin class assignments
   - Update blessing selections
   - Verify all changes save to SVM

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
- **Drag & Drop:** Drag players to group assignments
- **Color Coding:** Visual indicators for buff status
- **Mini-Map Icon:** Quick access to buff tracker
- **Raid Frames Integration:** Show buff status on raid frames

---

## Related Modules

- **EncounterMgmt.lua:** Encounter rendering and planning
- **AdvancedSettings.lua:** Settings toggle integration
- **Announce.lua:** Announcement system
- **ConsumeMon.lua:** Consume tracking integration
- **PallyPower (external):** Third-party addon integration

---

## Implementation Priority

### Phase 1 (Core)
- [ ] BuffManager encounter structure
- [ ] Advanced Settings toggle
- [ ] Basic role UI with group checkboxes
- [ ] Simple buff scanning
- [ ] Coverage calculation

### Phase 2 (Paladin)
- [ ] Paladin role special UI
- [ ] Per-class buff assignments
- [ ] PallyPower import
- [ ] PallyPower broadcast

### Phase 3 (Tracking)
- [ ] Real-time buff tracker window
- [ ] Automatic scanning
- [ ] Missing buff detection
- [ ] Coverage displays

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

## Change Log

| Version | Date | Changes |
|---------|------|---------|
| 2.1.0 | Feb 2026 | Initial BuffManager specification |

