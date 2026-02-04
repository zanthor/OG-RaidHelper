# Turtle WoW Addon Development - Comprehensive Reference

You are developing a World of Warcraft addon for **Turtle WoW**, a private server based on **WoW 1.12 (Vanilla)**. This uses **Lua 5.1** with significant restrictions compared to modern Lua and retail WoW.

---

## Critical Lua 5.1 Constraints

### Operators & Syntax

| ❌ DON'T USE | ✅ USE INSTEAD | Notes |
|-------------|----------------|-------|
| `a % b` | `mod(a, b)` | Modulo operator doesn't exist |
| `#table` | `table.getn(table)` | Length operator doesn't exist |
| `string.gmatch()` | `string.gfind()` | Different function name |
| `...` (varargs) | `arg` table | Varargs work differently |
| `x = x or default` in params | Set defaults in function body | No default parameters |
| `local function f() end` at file root | Works, but be careful with ordering | Forward declarations may be needed |

### String Functions (Lua 5.1)
```lua
-- Pattern matching
string.find(s, pattern)      -- Returns start, end indices
string.gfind(s, pattern)     -- Iterator (NOT gmatch!)
string.gsub(s, pattern, repl) -- Replace
string.sub(s, i, j)          -- Substring
string.format(fmt, ...)      -- Printf-style formatting
string.len(s)                -- Length (or just s:len())
string.lower(s) / string.upper(s)

-- NOTE: Patterns use % not \ for escapes
-- %d = digit, %s = whitespace, %a = letter, %w = alphanumeric
-- . = any char, * = 0+, + = 1+, - = 0+ non-greedy, ? = 0-1
```

### Table Functions (Lua 5.1)
```lua
table.insert(t, value)       -- Append to end
table.insert(t, pos, value)  -- Insert at position
table.remove(t, pos)         -- Remove at position (default: last)
table.getn(t)                -- Get length (NOT #t)
table.sort(t, comp)          -- Sort in-place
table.concat(t, sep)         -- Join to string

-- Iteration
for i, v in ipairs(t) do end -- Numeric indices only (1, 2, 3...)
for k, v in pairs(t) do end  -- All keys
```

### Math Functions
```lua
math.floor(x)
math.ceil(x)
math.abs(x)
math.min(a, b, ...)
math.max(a, b, ...)
math.random()                -- 0-1
math.random(n)               -- 1-n
math.random(m, n)            -- m-n
mod(a, b)                    -- NOT math.mod, NOT %
floor(x)                     -- Global shortcut exists
```

---

## WoW 1.12 API Constraints

### Frame Event Handlers

**Critical:** Event handlers use implicit globals, not parameters!

```lua
-- ❌ WRONG (Modern WoW style)
frame:SetScript("OnEvent", function(self, event, ...)
    -- DOES NOT WORK
end)

-- ✅ CORRECT (1.12 style)
frame:SetScript("OnEvent", function()
    -- Use these implicit globals:
    -- this   = the frame
    -- event  = event name (string)
    -- arg1, arg2, arg3... = event arguments
    
    if event == "ADDON_LOADED" then
        if arg1 == "MyAddon" then
            -- Initialize
        end
    end
end)
```

### Common Handler Globals

| Handler | Available Globals |
|---------|-------------------|
| OnEvent | `this`, `event`, `arg1`-`arg9` |
| OnClick | `this`, `arg1` (button: "LeftButton"/"RightButton") |
| OnUpdate | `this`, `arg1` (elapsed time in seconds) |
| OnEnter/OnLeave | `this` |
| OnShow/OnHide | `this` |
| OnMouseDown/Up | `this`, `arg1` (button) |
| OnMouseWheel | `this`, `arg1` (+1 up, -1 down) |
| OnDragStart/Stop | `this` |
| OnReceiveDrag | `this` |
| OnKeyDown/Up | `this`, `arg1` (key) |
| OnChar | `this`, `arg1` (character) |
| OnEditFocusGained/Lost | `this` |
| OnTextChanged | `this` |

### Frame Methods (1.12 Differences)

```lua
-- ❌ WRONG
frame:EnableMouseWheel(true)

-- ✅ CORRECT (no parameter = enable)
frame:EnableMouseWheel()

-- Creating frames
local frame = CreateFrame("Frame", "GlobalName", parent)
local button = CreateFrame("Button", "MyButton", parent, "UIPanelButtonTemplate")

-- Common methods
frame:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
frame:SetWidth(100)
frame:SetHeight(100)
frame:SetSize(100, 100)  -- May not exist, use SetWidth + SetHeight
frame:Show()
frame:Hide()
frame:IsVisible()
frame:IsShown()
frame:SetAlpha(0.5)
frame:EnableMouse(true)
frame:SetMovable(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", function() this:StartMoving() end)
frame:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)

-- Backdrop (1.12 style)
frame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileSize = 32,
    edgeSize = 32,
    insets = { left = 8, right = 8, top = 8, bottom = 8 }
})
frame:SetBackdropColor(0, 0, 0, 0.8)
frame:SetBackdropBorderColor(1, 1, 1, 1)
```

### Font Strings & Textures

```lua
-- Font strings
local text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
text:SetPoint("CENTER", frame, "CENTER", 0, 0)
text:SetText("Hello World")
text:SetTextColor(1, 1, 1)  -- RGB 0-1
text:SetJustifyH("LEFT")    -- LEFT, CENTER, RIGHT
text:SetJustifyV("TOP")     -- TOP, MIDDLE, BOTTOM
text:SetWidth(200)
text:SetHeight(0)           -- 0 = auto height
text:GetStringWidth()       -- Actual text width

-- Textures
local tex = frame:CreateTexture(nil, "BACKGROUND")
tex:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
tex:SetAllPoints(frame)
-- or
tex:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
tex:SetWidth(32)
tex:SetHeight(32)
tex:SetTexCoord(0, 1, 0, 1)  -- For texture atlas slicing
tex:SetVertexColor(1, 0, 0)  -- Tint
```

### Scroll Frames (1.12 Pattern)

```lua
-- Create scroll frame
local scrollFrame = CreateFrame("ScrollFrame", "MyScrollFrame", parent)
scrollFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -10)
scrollFrame:SetWidth(200)
scrollFrame:SetHeight(300)
scrollFrame:EnableMouseWheel()  -- No parameter!

-- Create content frame
local content = CreateFrame("Frame", nil, scrollFrame)
content:SetWidth(200)
content:SetHeight(1)  -- Will grow as content added
scrollFrame:SetScrollChild(content)

-- Mouse wheel handler
scrollFrame:SetScript("OnMouseWheel", function()
    local current = scrollFrame:GetVerticalScroll()
    local max = scrollFrame:GetVerticalScrollRange()
    local step = 20
    
    if arg1 > 0 then  -- Scroll up
        scrollFrame:SetVerticalScroll(math.max(0, current - step))
    else  -- Scroll down
        scrollFrame:SetVerticalScroll(math.min(max, current + step))
    end
end)
```

---

## Common WoW 1.12 API Functions

### Item Information

```lua
-- Get item info (may return nil if item not in cache!)
local name, link, quality, iLevel, reqLevel, class, subclass, 
      maxStack, equipSlot, texture, vendorPrice = GetItemInfo(itemIdOrLink)

-- Quality colors
-- 0 = Poor (gray), 1 = Common (white), 2 = Uncommon (green)
-- 3 = Rare (blue), 4 = Epic (purple), 5 = Legendary (orange)

-- Extract item ID from link
local function GetItemIdFromLink(link)
    if not link then return nil end
    local _, _, id = string.find(link, "item:(%d+)")
    return tonumber(id)
end

-- Item link format:
-- |cFFFFFFFF|Hitem:12345:0:0:0|h[Item Name]|h|r
-- |cAARRGGBB = color, |H = hyperlink start, |h = hyperlink text, |r = reset
```

### Bag Functions

```lua
for bag = 0, 4 do  -- 0 = backpack, 1-4 = bags
    local slots = GetContainerNumSlots(bag)
    for slot = 1, slots do
        local link = GetContainerItemLink(bag, slot)
        local texture, count, locked, quality, readable = GetContainerItemInfo(bag, slot)
        
        if link then
            -- Process item
        end
    end
end
```

### Auction House

```lua
-- Must be at AH with window open
local numItems = GetNumAuctionItems("list")  -- "list", "bidder", "owner"

for i = 1, numItems do
    local name, texture, count, quality, canUse, level, 
          minBid, minIncrement, buyoutPrice, bidAmount, 
          highBidder, owner = GetAuctionItemInfo("list", i)
    local link = GetAuctionItemLink("list", i)
end
```

### Merchant/Vendor

```lua
-- Must have merchant window open
local numItems = GetMerchantNumItems()

for i = 1, numItems do
    local name, texture, price, quantity, numAvailable, 
          isUsable, extendedCost = GetMerchantItemInfo(i)
    local link = GetMerchantItemLink(i)
    
    -- extendedCost = true if requires tokens/marks (not just gold)
    -- numAvailable = -1 if unlimited supply
end
```

### Tradeskill/Crafting

```lua
-- Must have tradeskill window open
local numSkills = GetNumTradeSkills()

for i = 1, numSkills do
    local name, type, numAvailable, isExpanded = GetTradeSkillInfo(i)
    -- type: "header", "subheader", or "recipe"
    
    if type ~= "header" and type ~= "subheader" then
        local link = GetTradeSkillItemLink(i)
        local numReagents = GetTradeSkillNumReagents(i)
        
        for j = 1, numReagents do
            local reagentName, reagentTexture, reagentCount, 
                  playerReagentCount = GetTradeSkillReagentInfo(i, j)
            local reagentLink = GetTradeSkillReagentItemLink(i, j)
        end
    end
end
```

### Unit Functions

```lua
UnitName("player")           -- Player name
UnitName("target")           -- Target name (nil if none)
UnitClass("player")          -- Localized class, english class
UnitRace("player")           -- Localized race, english race
UnitLevel("player")          -- Level
UnitFactionGroup("player")   -- "Alliance" or "Horde"
UnitGUID("player")           -- May not exist in 1.12!

-- Check unit type
UnitIsPlayer("target")
UnitIsFriend("player", "target")
UnitIsEnemy("player", "target")
UnitIsDead("target")
```

### Reputation

```lua
-- Iterate all factions
for i = 1, GetNumFactions() do
    local name, description, standingId, barMin, barMax, barValue,
          atWarWith, canToggleAtWar, isHeader, isCollapsed,
          hasRep, isWatched, isChild = GetFactionInfo(i)
    
    -- standingId: 1=Hated, 2=Hostile, 3=Unfriendly, 4=Neutral,
    --             5=Friendly, 6=Honored, 7=Revered, 8=Exalted
end

-- NOTE: GetFactionInfoByID() does NOT exist in 1.12!
-- Must iterate and match by name
```

### Chat Output

```lua
-- Print to default chat frame
DEFAULT_CHAT_FRAME:AddMessage("Hello", r, g, b)  -- RGB 0-1

-- Print with color codes
DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00Green text|r normal text")

-- Color code format: |cAARRGGBB  (AA = alpha, usually FF)
```

### Slash Commands

```lua
SlashCmdList["MYADDON"] = function(msg)
    -- msg = everything after the command
    local cmd, args = string.match(msg, "^(%S+)%s*(.*)$")
    cmd = string.lower(cmd or "")
    
    if cmd == "help" then
        -- Show help
    elseif cmd == "config" then
        -- Open config
    else
        -- Default action
    end
end
SLASH_MYADDON1 = "/myaddon"
SLASH_MYADDON2 = "/ma"
```

### Tooltip Hooking

```lua
-- Hook the main game tooltip
local origSetBagItem = GameTooltip.SetBagItem
GameTooltip.SetBagItem = function(self, bag, slot)
    origSetBagItem(self, bag, slot)
    -- Add custom lines after original tooltip
    GameTooltip:AddLine("My custom info", 1, 1, 0)
    GameTooltip:Show()  -- Refresh to include new line
end

-- Other hookable functions:
-- SetInventoryItem, SetLootItem, SetMerchantItem
-- SetTradeSkillItem, SetAuctionItem, SetHyperlink, etc.
```

---

## SavedVariables (Persistent Data)

### TOC File Declaration

```toc
## Interface: 11200
## Title: My Addon
## Notes: Description here
## Author: Your Name
## Version: 1.0
## SavedVariables: MyAddonDB
## SavedVariablesPerCharacter: MyAddonCharDB

Core.lua
Module1.lua
Module2.lua
```

### Loading/Saving Pattern

```lua
-- Declare with defaults
MyAddonDB = MyAddonDB or {}

local defaults = {
    setting1 = true,
    setting2 = 50,
    prices = {}
}

-- On VARIABLES_LOADED event
local function OnLoad()
    -- Merge with defaults
    for k, v in pairs(defaults) do
        if MyAddonDB[k] == nil then
            MyAddonDB[k] = v
        end
    end
end

-- Data automatically saves on logout/reload
-- Force save: not possible in 1.12 (no explicit SaveVariables call)
```

---

## Events Reference

### Addon Lifecycle

```lua
"ADDON_LOADED"       -- arg1 = addon name
"VARIABLES_LOADED"   -- SavedVariables are now available
"PLAYER_LOGIN"       -- Player is fully in the world
"PLAYER_ENTERING_WORLD" -- Fired on login and every zone transition
"PLAYER_LOGOUT"      -- About to logout (save data here!)
```

### Common Events

```lua
-- Bags
"BAG_UPDATE"         -- arg1 = bag number

-- Trading/Vendors
"MERCHANT_SHOW"      -- Vendor window opened
"MERCHANT_CLOSED"    -- Vendor window closed
"AUCTION_HOUSE_SHOW" -- AH opened
"AUCTION_HOUSE_CLOSED"

-- Tradeskills
"TRADE_SKILL_SHOW"
"TRADE_SKILL_CLOSE"
"TRADE_SKILL_UPDATE"

-- Chat
"CHAT_MSG_SYSTEM"    -- arg1 = message
"CHAT_MSG_SAY"       -- arg1 = message, arg2 = sender

-- Combat
"PLAYER_REGEN_DISABLED" -- Entered combat
"PLAYER_REGEN_ENABLED"  -- Left combat
```

---

## Common Patterns

### Addon Namespace

```lua
-- Create addon namespace (Core.lua)
MyAddon = MyAddon or {}
MyAddon.version = "1.0"

-- In other files
MyAddon.SomeFunction = function(self, arg)
    -- Can use self:OtherFunction()
end

-- Or
function MyAddon:SomeFunction(arg)
    -- self is automatically MyAddon
end
```

### Delayed/Scheduled Execution

```lua
-- Using OnUpdate (only way in 1.12)
local timerFrame = CreateFrame("Frame")
local timers = {}

timerFrame:SetScript("OnUpdate", function()
    local now = GetTime()
    for id, timer in pairs(timers) do
        if now >= timer.when then
            timer.callback()
            if timer.repeating then
                timer.when = now + timer.delay
            else
                timers[id] = nil
            end
        end
    end
end)

function MyAddon:ScheduleTimer(callback, delay, repeating)
    local id = GetTime() .. math.random()
    timers[id] = {
        callback = callback,
        when = GetTime() + delay,
        delay = delay,
        repeating = repeating
    }
    return id
end

function MyAddon:CancelTimer(id)
    timers[id] = nil
end
```

### Safe Item Info Fetching

```lua
-- GetItemInfo returns nil if item not cached
-- Must wait for item to be queried from server
function MyAddon:GetItemInfoSafe(itemId, callback)
    local name = GetItemInfo(itemId)
    if name then
        callback(GetItemInfo(itemId))
    else
        -- Create a tooltip to query the item
        local tip = CreateFrame("GameTooltip", "MyAddonScanTip", nil, "GameTooltipTemplate")
        tip:SetOwner(UIParent, "ANCHOR_NONE")
        tip:SetHyperlink("item:" .. itemId .. ":0:0:0")
        
        -- Check again after a short delay
        local checkFrame = CreateFrame("Frame")
        local elapsed = 0
        checkFrame:SetScript("OnUpdate", function()
            elapsed = elapsed + arg1
            local name = GetItemInfo(itemId)
            if name or elapsed > 2 then
                checkFrame:SetScript("OnUpdate", nil)
                if name then
                    callback(GetItemInfo(itemId))
                end
            end
        end)
    end
end
```

---

## Turtle WoW Specific Notes

1. **Custom Content**: Turtle WoW has custom items, quests, and zones not in original 1.12
2. **Extended Level Cap**: May have higher level cap than 60
3. **Custom Races/Classes**: Check their wiki for specifics
4. **API Extensions**: Some custom API functions may exist - check their addon documentation
5. **Hardcore Mode**: Special rules may apply for hardcore characters

---

## Debugging Tips

```lua
-- Debug mode toggle
MyAddonDebug = MyAddonDebug or false

local function Debug(msg)
    if MyAddonDebug then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF00FF[MyAddon]|r " .. tostring(msg))
    end
end

-- Print table contents
local function PrintTable(t, indent)
    indent = indent or ""
    for k, v in pairs(t) do
        if type(v) == "table" then
            Debug(indent .. tostring(k) .. ":")
            PrintTable(v, indent .. "  ")
        else
            Debug(indent .. tostring(k) .. " = " .. tostring(v))
        end
    end
end
```

---

## File Structure Best Practice

```
MyAddon/
├── MyAddon.toc          # Addon metadata, load order
├── Core.lua             # Namespace, events, initialization
├── Database.lua         # Static data tables
├── Utils.lua            # Helper functions
├── Modules/
│   ├── Feature1.lua
│   └── Feature2.lua
├── UI.lua               # Frame creation, display logic
└── Commands.lua         # Slash commands (load last)
```

### TOC Load Order Matters!
Files are executed in the order listed. Dependencies must load first:
```toc
Core.lua          # First - creates namespace
Database.lua      # Second - static data
Utils.lua         # Third - helpers
Modules/Feature1.lua
Modules/Feature2.lua
UI.lua
Commands.lua      # Last - references everything else
```

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

-- Time
time()                  -- Unix timestamp
GetTime()               -- Game time (seconds since login)
date("*t", timestamp)   -- Parse timestamp to table

-- Item link parsing
string.find(link, "item:(%d+)")
string.find(link, "%[(.-)%]")
```
