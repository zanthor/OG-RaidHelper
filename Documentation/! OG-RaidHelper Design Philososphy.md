# OG-RaidHelper: Development Guide for AI Agents

**Version:** 2.0 (January 2026)

This document defines the complete development framework for OG-RaidHelper and all related addons. All AI agents must follow these constraints when implementing features, fixing bugs, or making any code modifications.

---

## CRITICAL IMPLEMENTATION CONSTRAINTS

**⚠️ ALL AI AGENTS MUST FOLLOW THESE RULES:**

### 1. Language Compatibility: Lua 5.0/5.1 (WoW 1.12)

All code MUST be compatible with WoW 1.12's restricted Lua environment. This is **non-negotiable**.

#### Operators & Syntax Constraints

| ❌ NEVER USE | ✅ ALWAYS USE | Notes |
|-------------|----------------|-------|
| `#table` | `table.getn(table)` | Length operator doesn't exist |
| `a % b` | `mod(a, b)` | Modulo operator doesn't exist |
| `string.gmatch()` | `string.gfind()` | Different function name in 1.12 |
| `continue` | Conditional blocks or flags | Continue statement doesn't exist |
| `...` (varargs) | `arg` table | Varargs work differently |
| `ipairs()` where order matters | Manual numeric iteration | Use `for i = 1, table.getn(t) do` |

#### String Functions (Lua 5.0/5.1)
```lua
-- Available functions
string.find(s, pattern)      -- Returns start, end indices
string.gfind(s, pattern)     -- Iterator (NOT gmatch!)
string.gsub(s, pattern, repl) -- Replace
string.sub(s, i, j)          -- Substring
string.format(fmt, ...)      -- Printf-style formatting
string.len(s)                -- Length (or just s:len())
string.lower(s) / string.upper(s)

-- Pattern syntax uses % not \ for escapes
-- %d = digit, %s = whitespace, %a = letter, %w = alphanumeric
-- . = any char, * = 0+, + = 1+, - = 0+ non-greedy, ? = 0-1
```

#### Table Functions
```lua
table.insert(t, value)       -- Append to end
table.insert(t, pos, value)  -- Insert at position
table.remove(t, pos)         -- Remove at position
table.getn(t)                -- Get length (NOT #t)
table.sort(t, comp)          -- Sort in-place
table.concat(t, sep)         -- Join to string

-- Iteration
for i = 1, table.getn(t) do  -- Numeric indices
    local v = t[i]
end
for k, v in pairs(t) do end  -- All keys (unordered)
```

#### Math Functions
```lua
math.floor(x), math.ceil(x), math.abs(x)
math.min(a, b, ...), math.max(a, b, ...)
math.random()                -- 0-1
math.random(n)               -- 1-n
math.random(m, n)            -- m-n
mod(a, b)                    -- NOT math.mod, NOT %
floor(x)                     -- Global shortcut exists
```

---

### 2. WoW 1.12 API Constraints

#### Event Handlers: Implicit Globals Only

**CRITICAL:** Event handlers in 1.12 do NOT use parameters. They use implicit globals.

```lua
-- ❌ WRONG (Modern WoW style - WILL NOT WORK)
frame:SetScript("OnEvent", function(self, event, ...)
    -- This pattern does not exist in 1.12
end)

-- ✅ CORRECT (1.12 style)
frame:SetScript("OnEvent", function()
    -- Use these implicit globals:
    -- this   = the frame
    -- event  = event name (string)
    -- arg1, arg2, arg3... = event arguments
    
    if event == "ADDON_LOADED" and arg1 == "OG-RaidHelper" then
        -- Initialize
    end
end)
```

#### Common Handler Globals Reference

| Handler | Available Globals |
|---------|-------------------|
| OnEvent | `this`, `event`, `arg1`-`arg9` |
| OnClick | `this`, `arg1` (button: "LeftButton"/"RightButton") |
| OnUpdate | `this`, `arg1` (elapsed time in seconds) |
| OnEnter/OnLeave | `this` |
| OnShow/OnHide | `this` |
| OnMouseWheel | `this`, `arg1` (+1 up, -1 down) |
| OnDragStart/Stop | `this` |
| OnEditFocusGained/Lost | `this` |
| OnTextChanged | `this` |

#### Frame Methods (1.12 Specific)

```lua
-- Enable mouse wheel - NO PARAMETER
frame:EnableMouseWheel()  -- Not EnableMouseWheel(true)

-- Common frame methods
frame:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
frame:SetWidth(100)
frame:SetHeight(100)
frame:Show() / frame:Hide()
frame:IsVisible() / frame:IsShown()
frame:SetAlpha(0.5)
frame:EnableMouse(1)  -- Use 1/nil, not true/false
frame:SetMovable(1)
frame:RegisterForDrag("LeftButton")

-- Backdrop system (1.12 style)
frame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = 1, tileSize = 32, edgeSize = 32,
    insets = { left = 8, right = 8, top = 8, bottom = 8 }
})
frame:SetBackdropColor(0, 0, 0, 0.8)
frame:SetBackdropBorderColor(1, 1, 1, 1)
```

#### Font Strings & Textures

```lua
-- Font strings
local text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
text:SetPoint("CENTER", frame, "CENTER", 0, 0)
text:SetText("Hello World")
text:SetTextColor(1, 1, 1)  -- RGB 0-1
text:SetJustifyH("LEFT")    -- LEFT, CENTER, RIGHT
text:SetJustifyV("TOP")     -- TOP, MIDDLE, BOTTOM

-- Textures
local tex = frame:CreateTexture(nil, "BACKGROUND")
tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
tex:SetAllPoints(frame)
tex:SetTexCoord(0, 1, 0, 1)  -- For texture atlas slicing
tex:SetVertexColor(1, 0, 0)  -- Tint red
```

---

### 3. UI Framework: OGST Library (MANDATORY)

**ALL interface components MUST use the OGST Library.** Reference the complete API in `_OGST/README.md`.

#### Core OGST Principles

1. **Always use OGST components first:**
   ```lua
   -- ✅ CORRECT
   local window = OGST.CreateStandardWindow({...})
   local button = CreateFrame("Button", ...)
   OGST.StyleButton(button)
   
   -- ❌ WRONG
   local window = CreateFrame("Frame", ...)
   -- ... custom styling code ...
   ```

2. **If a component doesn't exist, ADD IT TO OGST FIRST:**
   - Do NOT create custom UI code in OG-RaidHelper
   - Add the new component to OGST with proper documentation
   - Then use it in OG-RaidHelper

3. **Use OGST resource paths:**
   ```lua
   local texPath = OGST.GetResourcePath() .. "img\\my-texture"
   ```

4. **Reference the OGST README:**
   - Window management: `OGST.CreateStandardWindow()`
   - Buttons: `OGST.StyleButton()`
   - Menus: `OGST.CreateStandardMenu()`
   - Lists: `OGST.CreateStyledScrollList()`, `OGST.CreateStyledListItem()`
   - Text inputs: `OGST.CreateSingleLineTextBox()`, `OGST.CreateScrollingTextBox()`
   - Layout: `OGST.AnchorElement()`, `OGST.CreateHighlightBorder()`
   - Checkboxes: `OGST.CreateCheckbox()`
   - Menu buttons: `OGST.CreateMenuButton()`
   - Docked panels: `OGST.RegisterDockedPanel()`

#### Common OGST Usage Patterns

```lua
-- Creating a window
local window = OGST.CreateStandardWindow({
    name = "OGRH_MyFeature",
    width = 600, height = 400,
    title = "My Feature",
    closeButton = true,
    escapeCloses = true,
    resizable = true
})

-- Using layout helpers
OGST.AnchorElement(element2, element1, {position = "below", gap = 10})

-- Creating lists
local outer, scroll, child, bar, width = OGST.CreateStyledScrollList(parent, 300, 400)
local item = OGST.CreateStyledListItem(child, width, 20, "Button")
```

---

### 4. Chat Communication: ChatThrottleLib (REQUIRED)

**For all visible chat channel announcements (RAID, PARTY, GUILD), use ChatThrottleLib.**

ChatThrottleLib (CTL) is the standard library for throttling chat messages to prevent disconnects. It handles Blizzard's rate limits automatically.

#### When to Use ChatThrottleLib

| Use Case | Library |
|----------|---------|
| Addon-to-addon communication | `_OGAddonMsg` (hidden addon channel) |
| Raid/party announcements | `ChatThrottleLib` (visible channels) |
| Guild announcements | `ChatThrottleLib` |
| Whispers | `ChatThrottleLib` |
| Boss warnings/timers | `ChatThrottleLib` |

#### Embedding ChatThrottleLib

1. **Copy ChatThrottleLib.lua to your addon:**
   ```
   OG-RaidHelper/
   ├── Libs/
   │   └── ChatThrottleLib.lua
   ```

2. **Add to TOC before your files:**
   ```toc
   ## Load order
   Libs\ChatThrottleLib.lua
   Core.lua
   ...
   ```

3. **Check if loaded:**
   ```lua
   if not ChatThrottleLib then
       DEFAULT_CHAT_FRAME:AddMessage("Error: ChatThrottleLib not loaded!", 1, 0, 0)
       return
   end
   ```

#### API Reference

**Basic Send:**
```lua
ChatThrottleLib:SendChatMessage(priority, prefix, text, channel, target, queueName)
```

**Parameters:**
- `priority`: `"ALERT"`, `"NORMAL"`, or `"BULK"`
  - `ALERT`: Critical messages (boss warnings, combat alerts)
  - `NORMAL`: Standard announcements (loot, ready checks)
  - `BULK`: Low priority (statistics, verbose output)
- `prefix`: Your addon identifier (e.g., `"OGRH"`)
- `text`: Message text
- `channel`: `"RAID"`, `"PARTY"`, `"GUILD"`, `"OFFICER"`, `"WHISPER"`, `"SAY"`, `"YELL"`, `"CHANNEL"`
- `target`: Player name (for WHISPER) or channel number (for CHANNEL)
- `queueName`: Optional custom queue name (usually nil)

**Examples:**

```lua
-- Raid warning (high priority)
ChatThrottleLib:SendChatMessage("ALERT", "OGRH", "Boss at 50%!", "RAID_WARNING")

-- Raid announcement (normal priority)
ChatThrottleLib:SendChatMessage("NORMAL", "OGRH", "Assignments updated", "RAID")

-- Guild announcement (low priority)
ChatThrottleLib:SendChatMessage("BULK", "OGRH", "Raid forming in 10 minutes", "GUILD")

-- Whisper
ChatThrottleLib:SendChatMessage("NORMAL", "OGRH", "You're assigned to group 1", "WHISPER", playerName)
```

#### Common Patterns for Raid Encounters

**Boss Phase Announcements:**
```lua
function OGRH.AnnounceBossPhase(phase, percent)
    local msg = string.format("Phase %d at %d%%!", phase, percent)
    ChatThrottleLib:SendChatMessage("ALERT", "OGRH", msg, "RAID_WARNING")
end
```

**Assignment Announcements:**
```lua
function OGRH.AnnounceAssignments(assignments)
    -- Use NORMAL priority for multiple messages
    for role, players in pairs(assignments) do
        local msg = string.format("%s: %s", role, table.concat(players, ", "))
        ChatThrottleLib:SendChatMessage("NORMAL", "OGRH", msg, "RAID")
    end
    -- CTL automatically queues and throttles
end
```

**Cooldown Tracking:**
```lua
function OGRH.RequestCooldown(spellName, playerName)
    local msg = string.format("%s: Use %s!", playerName, spellName)
    ChatThrottleLib:SendChatMessage("ALERT", "OGRH", msg, "RAID_WARNING")
end
```

**Loot Announcements:**
```lua
function OGRH.AnnounceLoot(itemLink, winner)
    local msg = string.format("%s won %s", winner, itemLink)
    ChatThrottleLib:SendChatMessage("BULK", "OGRH", msg, "RAID")
end
```

#### Priority Guidelines

| Priority | Use For | Examples |
|----------|---------|----------|
| **ALERT** | Time-sensitive combat info | Boss phase changes, ability warnings, wipe calls |
| **NORMAL** | Important but not urgent | Ready checks, assignments, loot rolls |
| **BULK** | Nice-to-have info | Statistics, verbose logs, formation announcements |

#### Best Practices

1. **Always use a priority** - Don't send directly with SendChatMessage()
2. **Use your addon prefix** - Makes it clear where messages come from
3. **Batch related messages** - CTL will queue and send smoothly
4. **Higher priority for combat** - Use ALERT for boss fights
5. **Test with multiple addons** - Ensure throttling works with other CTL users

#### Channel-Specific Notes

```lua
-- Raid Warning (requires assist/lead)
if IsRaidOfficer() or IsRaidLeader() then
    ChatThrottleLib:SendChatMessage("ALERT", "OGRH", msg, "RAID_WARNING")
else
    -- Fallback to RAID if no permissions
    ChatThrottleLib:SendChatMessage("ALERT", "OGRH", msg, "RAID")
end

-- Officer Chat (requires officer rank)
ChatThrottleLib:SendChatMessage("NORMAL", "OGRH", msg, "OFFICER")

-- Custom Channel
local channelNum = GetChannelName("MyChannel")
if channelNum > 0 then
    ChatThrottleLib:SendChatMessage("NORMAL", "OGRH", msg, "CHANNEL", channelNum)
end
```

#### Error Handling

```lua
-- CTL doesn't return errors, but you can wrap it
local function SafeSend(priority, msg, channel, target)
    if not ChatThrottleLib then
        DEFAULT_CHAT_FRAME:AddMessage("OGRH: CTL not loaded!", 1, 0, 0)
        return false
    end
    
    if not msg or msg == "" then
        return false
    end
    
    ChatThrottleLib:SendChatMessage(priority, "OGRH", msg, channel, target)
    return true
end
```

#### Debugging

ChatThrottleLib has built-in verbose mode:
```lua
-- Enable debug output
ChatThrottleLib.VERBOSE = true

-- You'll see queue status in chat
-- Disable for production:
ChatThrottleLib.VERBOSE = false
```

---

### 5. Message Routing & Prefix System: OGRH.Msg() (REQUIRED)

**ALL addon chat output MUST use OGRH.Msg() for routing to the dedicated OGRH chat window.**

OGRH has a dedicated chat window that isolates addon output from player chat. Messages sent via OGRH.Msg() are automatically routed to this window.

#### Message Prefix Format

All messages use a standardized two-part prefix:

```lua
OGRH.Msg("[Category-Module] Message text")
-- Displays as: [OG][Category-Module] Message text
--              ^^^^  ^^^^^^^^^^^^^^^^
--              Auto  Your prefix
```

**The [OG] prefix is automatically added** - you only provide the module-specific portion.

#### Category Color Codes

Use these color codes based on the file's location:

| Category | Color Code | RGB | Usage |
|----------|------------|-----|-------|
| **Infrastructure** | `|cff00ccff` | Cyan | Infrastructure/* (MessageRouter, Sync, Versioning, etc.) |
| **Core** | `|cff66ff66` | Light Green | Core/* (Core.lua, SavedVariablesManager, Utilities, ChatWindow) |
| **Configuration** | `|cffffaa00` | Orange | Configuration/* (Invites, Recruitment, Roster, Consumes) |
| **Raid** | `|cffff6666` | Light Red | Raid/* (EncounterMgmt, RolesUI, Announce, BigWigs) |
| **Administration** | `|cffcc99ff` | Light Purple | Administration/* (Recruitment, SRValidation, AddonAudit) |
| **UI** | `|cff66ccff` | Sky Blue | UI/* (MainUI, windows, dialogs) |
| **Modules** | `|cffffff66` | Light Yellow | Modules/* (specific encounter modules, helpers) |
| **Error** | `|cffff0000` | Red | Any error message regardless of location |
| **Warning** | `|cffffaa00` | Orange | Any warning message |
| **Success** | `|cff00ff00` | Green | Successful operations, confirmations |

#### Usage Patterns

**Module Load Messages:**
```lua
-- Infrastructure module
OGRH.Msg("|cff00ccff[RH-MessageRouter]|r Loaded")
-- Displays: [OG][RH-MessageRouter] Loaded (cyan)

-- Core module  
OGRH.Msg("|cff66ff66[RH-SVM]|r loaded")
-- Displays: [OG][RH-SVM] loaded (light green)

-- Configuration module
OGRH.Msg("|cffffaa00[RH-ConsumesTracking]|r module loaded (v1.0.0)")
-- Displays: [OG][RH-ConsumesTracking] module loaded (v1.0.0) (orange)
```

**Error Messages:**
```lua
-- Use red for all errors, regardless of file location
OGRH.Msg("|cffff0000[RH-Permissions]|r Error: Invalid permission level")
-- Displays: [OG][RH-Permissions] Error: Invalid permission level (red)
```

**User Action Feedback:**
```lua
-- Success (green)
OGRH.Msg("|cff00ff00[RH-EncounterMgmt]|r Assignments saved successfully")

-- Warning (orange)
OGRH.Msg("|cffffaa00[RH-Sync]|r Warning: Sync locked by raid leader")

-- Info (category color)
OGRH.Msg("|cffff6666[RH-RolesUI]|r Role updated: Tank -> Healer")
```

**Debug Messages:**
```lua
-- Use category color + [DEBUG] prefix
OGRH.Msg("|cff00ccff[RH-Sync][DEBUG]|r BroadcastFullSync called")
```

#### Complete Examples by Location

```lua
-- Infrastructure/MessageRouter.lua
function OGRH.MessageRouter.Initialize()
    -- ... initialization code ...
    OGRH.Msg("|cff00ccff[RH-MessageRouter]|r Loaded")
end

function OGRH.MessageRouter.HandleError(err)
    OGRH.Msg("|cffff0000[RH-MessageRouter]|r Error: " .. err)
end

-- Core/SavedVariablesManager.lua
function OGRH.SVM.Initialize()
    -- ... initialization code ...
    OGRH.Msg("|cff66ff66[RH-SVM]|r loaded")
end

-- Configuration/Invites.lua  
function OGRH.Invites.SendInvite(player)
    -- ... send invite ...
    OGRH.Msg("|cffffaa00[RH-Invites]|r Invited " .. player)
end

-- Raid/EncounterMgmt.lua
function OGRH.EncounterMgmt.SaveAssignments()
    -- ... save ...
    OGRH.Msg("|cff00ff00[RH-EncounterMgmt]|r Assignments saved successfully")
end

function OGRH.EncounterMgmt.HandleConflict()
    OGRH.Msg("|cffffaa00[RH-EncounterMgmt]|r Warning: Conflicting assignment")
end

-- Administration/Recruitment.lua
function OGRH.Recruitment.ProcessApplicant(name)
    OGRH.Msg("|cffcc99ff[RH-Recruitment]|r Processing application from " .. name)
end

-- UI/MainUI.lua
function OGRH.ShowMainWindow()
    OGRH.Msg("|cff66ccff[RH]|r v1.31.2 loaded")
end

-- Modules/cthun.lua
function CThunModule.OnLoad()
    OGRH.Msg("|cffffff66[RH-CThun]|r Encounter module loaded")
end
```

#### Prefix Naming Conventions

**ALL modules use the `[RH-ModuleName]` format for consistency:**

| File Location | Prefix Format | Examples |
|---------------|---------------|----------|
| Infrastructure/* | `[RH-ModuleName]` | `[RH-MessageRouter]`, `[RH-Sync]`, `[RH-Permissions]` |
| Core/* | `[RH-ModuleName]` | `[RH-SVM]`, `[RH-Utilities]`, `[RH-ChatWindow]` |
| Configuration/* | `[RH-ModuleName]` | `[RH-Invites]`, `[RH-Recruitment]`, `[RH-ConsumesTracking]` |
| Raid/* | `[RH-ModuleName]` | `[RH-EncounterMgmt]`, `[RH-RolesUI]`, `[RH-Announce]` |
| Administration/* | `[RH-ModuleName]` | `[RH-Recruitment]`, `[RH-SRValidation]`, `[RH-AddonAudit]` |
| UI/* | `[RH]` or `[RH-UI-Name]` | `[RH]`, `[RH-UI-Roles]`, `[RH-UI-Consumes]` |
| Modules/* | `[RH-ModuleName]` | `[RH-CThun]`, `[RH-ConsumeHelper]` |

#### Message Queue System

Messages sent before the chat window exists are automatically queued:

```lua
-- Early in load process - message is queued
OGRH.Msg("|cff66ff66[SVM]|r loaded")  

-- Later, when ChatWindow.lua creates the window
-- FlushMessageQueue() automatically displays all queued messages
```

#### When NOT to Use OGRH.Msg()

**Do NOT use OGRH.Msg() for:**
- Meta-messages about the chat window itself (use DEFAULT_CHAT_FRAME directly)
- Test framework output (should be visible in default chat)
- External library code (OGAddonMsg, OGST, ChatThrottleLib)
- Fallback handlers within OGRH.Msg() itself

**Example of valid DEFAULT_CHAT_FRAME usage:**
```lua
-- In ChatWindow.lua - message ABOUT the window system
DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[OGRH]|r Failed to create chat window", 1, 0, 0)

-- In test file - test output should be visible
DEFAULT_CHAT_FRAME:AddMessage("Test 1: PASS", 0, 1, 0)
```

#### Migration from DEFAULT_CHAT_FRAME

When converting existing code:

```lua
-- ❌ OLD
DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[OGRH]|r MessageRouter loaded", 0, 1, 0)

-- ✅ NEW
OGRH.Msg("|cff00ccff[RH-MessageRouter]|r Loaded")
```

**Key Changes:**
1. Remove `[OGRH]` prefix (auto-added as `[OG]`)
2. Add category color code
3. Use standardized module prefix
4. Remove RGB parameters (colors in text)
5. Shorten "loaded" messages for consistency

#### Color Code Reference (Copy-Paste)

```lua
-- Quick reference for copy-pasting
local COLORS = {
    INFRASTRUCTURE = "|cff00ccff",  -- Cyan
    CORE = "|cff66ff66",            -- Light Green
    CONFIG = "|cffffaa00",          -- Orange
    RAID = "|cffff6666",            -- Light Red
    ADMIN = "|cffcc99ff",           -- Light Purple
    UI = "|cff66ccff",              -- Sky Blue
    MODULE = "|cffffff66",          -- Light Yellow
    ERROR = "|cffff0000",           -- Red
    WARNING = "|cffffaa00",         -- Orange
    SUCCESS = "|cff00ff00",         -- Green
    RESET = "|r"                    -- Reset color
}
```

---

### 6. Code Style & Conventions

#### Namespace & Structure

```lua
-- All public functions in OGRH namespace
OGRH = OGRH or {}

-- Public functions use PascalCase
function OGRH.DoSomething(param1, param2)
    -- Implementation
end

-- Local functions also use PascalCase
local function HelperFunction(param)
    -- Implementation
end

-- Variables use camelCase
local myVariable = "value"
local itemCount = 0
```

#### Comments & Documentation

```lua
-- Document complex logic
-- Parse the item link to extract item ID
-- Format: |cFFFFFFFF|Hitem:12345:0:0:0|h[Item Name]|h|r
local _, _, itemId = string.find(itemLink, "item:(%d+)")

-- Document non-obvious behavior
-- Note: GetItemInfo returns nil if item not in cache
-- We must query it first and check again later
```

#### File Structure

```
OG-RaidHelper/
├── OG-RaidHelper.toc     # Load order, SavedVariables
├── Core.lua              # Namespace, initialization
├── Database.lua          # Static data tables
├── Utils.lua             # Helper functions
├── Modules/
│   ├── Module1.lua
│   └── Module2.lua
├── UI/
│   └── MainUI.lua
└── Libs/
    └── OGST/             # UI library
```

**TOC Load Order Matters:**
```toc
## Load order is critical in 1.12
Core.lua          # First - creates namespace
Database.lua      # Static data
Utils.lua         # Helpers
Modules/Feature1.lua
UI/MainUI.lua
Commands.lua      # Last - references everything
```

---

### 7. Integration Patterns

#### SavedVariables

```lua
-- Declare in TOC
## SavedVariables: OGRH_DB
## SavedVariablesPerCharacter: OGRH_CharDB

-- Use OGRH.EnsureSV() pattern
function OGRH.EnsureSV()
    OGRH_DB = OGRH_DB or {}
    
    -- Set defaults only if not present
    if OGRH_DB.myFeature == nil then
        OGRH_DB.myFeature = {
            enabled = true,
            settings = {}
        }
    end
end

-- Call in ADDON_LOADED
if event == "ADDON_LOADED" and arg1 == "OG-RaidHelper" then
    OGRH.EnsureSV()
end
```

#### Event Registration

```lua
-- Create event frame in Core.lua
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("VARIABLES_LOADED")

eventFrame:SetScript("OnEvent", function()
    if event == "ADDON_LOADED" and arg1 == "OG-RaidHelper" then
        OGRH.OnLoad()
    elseif event == "VARIABLES_LOADED" then
        OGRH.OnVariablesLoaded()
    end
end)
```

#### Menu Registration

```lua
-- Register menu items in proper location
-- In MainUI.lua or Module.lua
local menu = OGST.GetMenu("OGRH_MainMenu")
if menu then
    OGST.AddMenuItem("OGRH_MainMenu", {
        text = "My Feature",
        onClick = function()
            OGRH.ShowMyFeatureWindow()
        end
    })
end
```

---

### 8. Common WoW 1.12 API Patterns

#### Safe Item Info Fetching

```lua
-- GetItemInfo returns nil if item not cached
-- Must query first, then check again
function OGRH.GetItemInfoSafe(itemId, callback)
    local name = GetItemInfo(itemId)
    if name then
        callback(GetItemInfo(itemId))
        return
    end
    
    -- Query item by creating tooltip
    local scanTip = CreateFrame("GameTooltip", "OGRH_ScanTip", nil, "GameTooltipTemplate")
    scanTip:SetOwner(UIParent, "ANCHOR_NONE")
    scanTip:SetHyperlink("item:" .. itemId .. ":0:0:0")
    
    -- Schedule check after brief delay
    OGRH.ScheduleTimer(function()
        local name = GetItemInfo(itemId)
        if name then
            callback(GetItemInfo(itemId))
        end
    end, 0.1)
end
```

#### Item Link Parsing

```lua
-- Extract item ID from link
-- Format: |cFFFFFFFF|Hitem:12345:0:0:0|h[Item Name]|h|r
function OGRH.GetItemIdFromLink(link)
    if not link then return nil end
    local _, _, itemId = string.find(link, "item:(%d+)")
    return tonumber(itemId)
end

-- Extract item name from link
function OGRH.GetItemNameFromLink(link)
    if not link then return nil end
    local _, _, name = string.find(link, "%[(.-)%]")
    return name
end
```

#### Bag Scanning

```lua
function OGRH.ScanBags(callback)
    for bag = 0, 4 do  -- 0 = backpack, 1-4 = bags
        local slots = GetContainerNumSlots(bag)
        for slot = 1, slots do
            local link = GetContainerItemLink(bag, slot)
            if link then
                local _, count = GetContainerItemInfo(bag, slot)
                callback(bag, slot, link, count)
            end
        end
    end
end
```

#### Delayed/Scheduled Execution

```lua
-- Use OnUpdate for timers (only way in 1.12)
OGRH.timers = {}
local timerFrame = CreateFrame("Frame")

timerFrame:SetScript("OnUpdate", function()
    local now = GetTime()
    for id, timer in pairs(OGRH.timers) do
        if now >= timer.when then
            timer.callback()
            if timer.repeating then
                timer.when = now + timer.delay
            else
                OGRH.timers[id] = nil
            end
        end
    end
end)

function OGRH.ScheduleTimer(callback, delay, repeating)
    local id = GetTime() .. math.random()
    OGRH.timers[id] = {
        callback = callback,
        when = GetTime() + delay,
        delay = delay,
        repeating = repeating
    }
    return id
end
```

---

### 9. Testing Requirements

All implementations must be tested in WoW 1.12 client:

1. **No modern WoW API calls** - If unsure, verify in 1.12 API documentation
2. **Test with Turtle WoW custom features** - Some items/quests/zones are custom
3. **Test with common addons present/absent:**
   - DPSMate
   - ShaguDPS
   - pfUI
   - SuperWoW (if applicable)
4. **Test error cases:**
   - Item not in cache
   - Player in combat
   - Addon not fully loaded
5. **Test saved variables:**
   - Fresh install (no saved variables)
   - Upgrade from previous version
   - Corrupted data

---

## Quick Reference Card

```lua
-- Length of table
table.getn(t)           -- NOT #t

-- Modulo
mod(a, b)               -- NOT a % b

-- String iterator
string.gfind(s, pat)    -- NOT string.gmatch

-- Event handlers use globals
this, event, arg1, arg2, arg3...

-- Enable mouse wheel (no parameter)
frame:EnableMouseWheel()

-- Print to chat
DEFAULT_CHAT_FRAME:AddMessage("text", r, g, b)

-- Color codes
"|cFFRRGGBB text|r"     -- AARRGGBB format

-- Time functions
time()                  -- Unix timestamp
GetTime()               -- Game time (seconds since login)
date("*t", timestamp)   -- Parse timestamp to table

-- Item link parsing
string.find(link, "item:(%d+)")
string.find(link, "%[(.-)%]")
```

---

## Important Events Reference

```lua
"ADDON_LOADED"          -- arg1 = addon name
"VARIABLES_LOADED"      -- SavedVariables available
"PLAYER_LOGIN"          -- Player fully in world
"PLAYER_ENTERING_WORLD" -- Login + every zone change
"PLAYER_LOGOUT"         -- About to logout (save data!)

"BAG_UPDATE"            -- arg1 = bag number
"MERCHANT_SHOW"         -- Vendor window opened
"AUCTION_HOUSE_SHOW"    -- AH opened
"TRADE_SKILL_SHOW"      -- Tradeskill window opened

"PLAYER_REGEN_DISABLED" -- Entered combat
"PLAYER_REGEN_ENABLED"  -- Left combat
```

---

## Turtle WoW Specific Notes

1. **Custom Content**: Turtle WoW has custom items, quests, zones not in original 1.12
2. **Extended Level Cap**: May exceed level 60
3. **Custom Races/Classes**: Check Turtle WoW wiki for specifics
4. **API Extensions**: Some custom API functions may exist - verify before use
5. **Hardcore Mode**: Special rules may apply for hardcore characters

---

## AI Agent Best Practices

When implementing features:

1. **Read existing code first** - Understand patterns before making changes
2. **Use grep_search liberally** - Find existing implementations to reference
3. **Check OGST README** - Don't reinvent UI components
4. **Test incrementally** - Verify each change in-game before proceeding
5. **Ask for clarification** - If requirements are unclear, ask before implementing
6. **Document assumptions** - If making decisions, explain why in comments
7. **Preserve existing style** - Match the coding style of surrounding code

---

**END OF DEVELOPMENT GUIDE**

This document supersedes all previous development guidelines. When in doubt, refer to this guide first, then existing code patterns, then ask for clarification.
