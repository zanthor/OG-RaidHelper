-- OGRH_Core.lua  (Turtle-WoW 1.12)  v1.14.0
OGRH = OGRH or {}
OGRH.ADDON = "OG-RaidHelper"
OGRH.CMD   = "ogrh"
OGRH.ADDON_PREFIX = "OGRH"

-- Standard announcement colors
OGRH.COLOR = {
  HEADER = "|cff00ff00",   -- Bright Green
  ROLE = "|cffffcc00",     -- Bright Yellow
  ANNOUNCE = "|cffff8800", -- Orange
  RESET = "|r",
  
  -- Class colors
  CLASS = {
    WARRIOR = "|cffC79C6E",
    PALADIN = "|cffF58CBA",
    HUNTER = "|cffABD473",
    ROGUE = "|cffFFF569",
    PRIEST = "|cffFFFFFF",
    SHAMAN = "|cff0070DE",
    MAGE = "|cff69CCF0",
    WARLOCK = "|cff9482C9",
    DRUID = "|cffFF7D0A"
  },
  
  -- Raid marker colors
  MARK = {
    [1] = "|cffFFFF00", -- Star - Yellow
    [2] = "|cffFF7F00", -- Circle - Orange
    [3] = "|cffFF00FF", -- Diamond - Purple/Magenta
    [4] = "|cff00FF00", -- Triangle - Green
    [5] = "|cffC0C0FF", -- Moon - Light Blue/Silver
    [6] = "|cff0080FF", -- Square - Blue
    [7] = "|cffFF0000", -- Cross - Red
    [8] = "|cffFFFFFF"  -- Skull - White
  }
}

function OGRH.EnsureSV()
  if not OGRH_SV then OGRH_SV = { roles = {}, order = {}, pollTime = 5, tankCategory = {}, healerBoss = {}, ui = {}, tankIcon = {}, healerIcon = {}, rolesUI = {}, playerAssignments = {}, allowRemoteReadyCheck = true, tradeItems = {} } end
  if not OGRH_SV.roles then OGRH_SV.roles = {} end
  if not OGRH_SV.order then OGRH_SV.order = {} end
  if not OGRH_SV.order.TANKS then OGRH_SV.order.TANKS = {} end
  if not OGRH_SV.order.HEALERS then OGRH_SV.order.HEALERS = {} end
  if not OGRH_SV.order.MELEE then OGRH_SV.order.MELEE = {} end
  if not OGRH_SV.order.RANGED then OGRH_SV.order.RANGED = {} end
  if OGRH_SV.pollTime == nil then OGRH_SV.pollTime = 5 end
  if not OGRH_SV.tankCategory then OGRH_SV.tankCategory = {} end
  if not OGRH_SV.healerBoss then OGRH_SV.healerBoss = {} end
  if not OGRH_SV.ui then OGRH_SV.ui = {} end
  if not OGRH_SV.tankIcon then OGRH_SV.tankIcon = {} end
  if not OGRH_SV.healerIcon then OGRH_SV.healerIcon = {} end
  if not OGRH_SV.rolesUI then OGRH_SV.rolesUI = {} end
  if not OGRH_SV.playerAssignments then OGRH_SV.playerAssignments = {} end
  if OGRH_SV.allowRemoteReadyCheck == nil then OGRH_SV.allowRemoteReadyCheck = true end
  if not OGRH_SV.tradeItems then OGRH_SV.tradeItems = {} end
  
  -- Migrate old healerTankAssigns to playerAssignments (as icons)
  if OGRH_SV.healerTankAssigns and not OGRH_SV._assignmentsMigrated then
    for name, iconId in pairs(OGRH_SV.healerTankAssigns) do
      if iconId and iconId >= 1 and iconId <= 8 then
        OGRH_SV.playerAssignments[name] = {type = "icon", value = iconId}
      end
    end
    OGRH_SV._assignmentsMigrated = true
  end
end
local _svf = CreateFrame("Frame"); _svf:RegisterEvent("VARIABLES_LOADED")
_svf:SetScript("OnEvent", function() OGRH.EnsureSV() end)
OGRH.EnsureSV()

function OGRH.Msg(s) if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cff66ccff[OGRH]|r "..tostring(s)) end end
function OGRH.Trim(s) return string.gsub(s or "", "^%s*(.-)%s*$", "%1") end
function OGRH.Mod1(n,t) return math.mod(n-1, t)+1 end
function OGRH.CanRW() if IsRaidLeader and IsRaidLeader()==1 then return true end if IsRaidOfficer and IsRaidOfficer()==1 then return true end return false end
function OGRH.SayRW(text) if OGRH.CanRW() then SendChatMessage(text, "RAID_WARNING") else SendChatMessage(text, "RAID") end end

-- Ready Check functionality
function OGRH.DoReadyCheck()
  -- Check if in a raid
  local numRaid = GetNumRaidMembers() or 0
  if numRaid == 0 then
    OGRH.Msg("You are not in a raid.")
    return
  end
  
  -- Check if player is raid leader
  if IsRaidLeader and IsRaidLeader() == 1 then
    -- Set flag to capture AFK messages
    OGRH.readyCheckInProgress = true
    DoReadyCheck()
  -- Check if player is raid assistant
  elseif IsRaidOfficer and IsRaidOfficer() == 1 then
    -- Send addon message to raid asking leader to start ready check
    SendAddonMessage(OGRH.ADDON_PREFIX, "READYCHECK_REQUEST", "RAID")
    OGRH.Msg("Ready check request sent to raid leader.")
  else
    OGRH.Msg("You must be raid leader or assistant to start a ready check.")
  end
end

-- Announcement storage and re-announce functionality
OGRH.storedAnnouncement = nil  -- Stores {lines = {...}, timestamp = time()}

-- Store announcement lines and broadcast to raid
function OGRH.StoreAndBroadcastAnnouncement(lines)
  if not lines or table.getn(lines) == 0 then return end
  
  -- Store locally (with single pipes for color codes)
  OGRH.storedAnnouncement = {
    lines = lines,
    timestamp = time()
  }
  
  -- Broadcast to other addon users in raid
  -- Use a different delimiter (semicolon) to avoid pipe confusion
  local message = "ANNOUNCE;" .. table.concat(lines, ";")
  SendAddonMessage(OGRH.ADDON_PREFIX, message, "RAID")
end

-- Helper function: Send announcement lines and store for re-announce
-- This is the recommended way to send announcements from any module
function OGRH.SendAnnouncement(lines, testMode)
  if not lines or table.getn(lines) == 0 then return end
  
  -- Store and broadcast for re-announce functionality
  OGRH.StoreAndBroadcastAnnouncement(lines)
  
  -- Send each line to chat
  local canRW = OGRH.CanRW()
  for _, line in ipairs(lines) do
    if testMode then
      -- In test mode, display to local chat frame
      DEFAULT_CHAT_FRAME:AddMessage(OGRH.Announce("OGRH: ") .. line)
    else
      -- Send to raid warning or raid chat
      if canRW then
        SendChatMessage(line, "RAID_WARNING")
      else
        SendChatMessage(line, "RAID")
      end
    end
  end
end

-- Re-announce stored announcement
function OGRH.ReAnnounce()
  if not OGRH.storedAnnouncement then
    OGRH.Msg("No announcement to repeat.")
    return
  end
  
  -- Check if we can send raid warnings
  local canRW = OGRH.CanRW()
  
  -- Send each line (no escaping needed for SendChatMessage)
  for _, line in ipairs(OGRH.storedAnnouncement.lines) do
    if canRW then
      SendChatMessage(line, "RAID_WARNING")
    else
      SendChatMessage(line, "RAID")
    end
  end
  
  OGRH.Msg("Re-announced " .. table.getn(OGRH.storedAnnouncement.lines) .. " line(s).")
end

-- Handle incoming addon messages and game events
local addonFrame = CreateFrame("Frame")
addonFrame:RegisterEvent("CHAT_MSG_ADDON")
addonFrame:RegisterEvent("CHAT_MSG_SYSTEM")
addonFrame:SetScript("OnEvent", function()
  if event == "CHAT_MSG_ADDON" then
    local prefix, message, distribution, sender = arg1, arg2, arg3, arg4
    
    if prefix == OGRH.ADDON_PREFIX then
      -- Handle ready check request from assistant
      if message == "READYCHECK_REQUEST" then
        -- Only process if we are the raid leader
        if IsRaidLeader and IsRaidLeader() == 1 then
          -- Check if remote ready checks are allowed
          OGRH.EnsureSV()
          if OGRH_SV.allowRemoteReadyCheck then
            -- Set flag to capture AFK messages
            OGRH.readyCheckInProgress = true
            DoReadyCheck()
          end
        end
      -- Handle announcement broadcast
      elseif string.sub(message, 1, 9) == "ANNOUNCE;" then
        -- Parse the announcement lines (semicolon delimited)
        local content = string.sub(message, 10)
        local lines = {}
        local lastPos = 1
        local pos = 1
        
        -- Split by semicolon delimiter
        while pos <= string.len(content) do
          local found = string.find(content, ";", pos, true)
          if found then
            table.insert(lines, string.sub(content, lastPos, found - 1))
            lastPos = found + 1
            pos = found + 1
          else
            -- Last segment
            table.insert(lines, string.sub(content, lastPos))
            break
          end
        end
        
        -- Store the announcement
        if table.getn(lines) > 0 then
          OGRH.storedAnnouncement = {
            lines = lines,
            timestamp = time()
          }
        end
      end
    end
  elseif event == "CHAT_MSG_SYSTEM" then
    -- Capture ready check AFK messages
    if OGRH.readyCheckInProgress and IsRaidLeader() == 1 then
      local msg = arg1
      
      -- Check for "No players are AFK" or "The following players are AFK:"
      if msg and string.find(msg, "No players are AFK") then
        -- Echo "No players are AFK" with header color
        OGRH.SayRW(OGRH.Header("No players are AFK"))
        OGRH.readyCheckInProgress = false
      elseif msg and string.find(msg, "The following players are AFK:") then
        -- Parse the player names from the message
        local playersPart = string.gsub(msg, "The following players are AFK: ", "")
        local players = {}
        
        -- Split by comma and space
        local pos = 1
        while pos <= string.len(playersPart) do
          local commaPos = string.find(playersPart, ", ", pos, true)
          local playerName
          if commaPos then
            playerName = string.sub(playersPart, pos, commaPos - 1)
            pos = commaPos + 2
          else
            playerName = string.sub(playersPart, pos)
            pos = string.len(playersPart) + 1
          end
          
          -- Trim whitespace
          playerName = string.gsub(playerName, "^%s*(.-)%s*$", "%1")
          if playerName ~= "" then
            table.insert(players, playerName)
          end
        end
        
        -- Build lookup table of raid members with class and online status
        local raidInfo = {}
        local numRaid = GetNumRaidMembers() or 0
        for j = 1, numRaid do
          local name, _, _, _, class, _, _, online = GetRaidRosterInfo(j)
          if name then
            raidInfo[name] = {class = class, online = online}
          end
        end
        
        -- Build colored message
        local coloredPlayers = {}
        for i = 1, table.getn(players) do
          local playerName = players[i]
          local info = raidInfo[playerName]
          local coloredName
          
          if info and info.class then
            -- Use the class from raid roster to color the name
            local classUpper = string.upper(info.class)
            local classColorHex = OGRH.ClassColorHex(classUpper)
            coloredName = classColorHex .. playerName .. "|r"
          else
            -- Fallback to white if class not found
            coloredName = playerName
          end
          
          -- Add asterisk if offline
          if info and not info.online then
            coloredName = coloredName .. OGRH.COLOR.ROLE .. "*" .. OGRH.COLOR.RESET
          end
          
          table.insert(coloredPlayers, coloredName)
        end
        
        -- Build the final message
        local coloredMsg = OGRH.Header("The following players are AFK:") .. " " .. table.concat(coloredPlayers, ", ")
        OGRH.SayRW(coloredMsg)
        OGRH.readyCheckInProgress = false
      end
    end
  end
end)

-- Helper functions for colored text
function OGRH.Header(text) return OGRH.COLOR.HEADER .. text .. OGRH.COLOR.RESET end
function OGRH.Role(text) return OGRH.COLOR.ROLE .. text .. OGRH.COLOR.RESET end
function OGRH.Announce(text) return OGRH.COLOR.ANNOUNCE .. text .. OGRH.COLOR.RESET end

OGRH.CLASS_RGB = {
  DRUID={1,0.49,0.04}, HUNTER={0.67,0.83,0.45}, MAGE={0.25,0.78,0.92}, PALADIN={0.96,0.55,0.73},
  PRIEST={1,1,1}, ROGUE={1,0.96,0.41}, SHAMAN={0,0.44,0.87}, WARLOCK={0.53,0.53,0.93}, WARRIOR={0.78,0.61,0.43}
}
function OGRH.ClassColorHex(class)
  if not class then return "|cffffffff" end
  local r,g,b = 1,1,1
  if RAID_CLASS_COLORS and RAID_CLASS_COLORS[class] then r,g,b = RAID_CLASS_COLORS[class].r, RAID_CLASS_COLORS[class].g, RAID_CLASS_COLORS[class].b
  elseif OGRH.CLASS_RGB[class] then r,g,b = OGRH.CLASS_RGB[class][1], OGRH.CLASS_RGB[class][2], OGRH.CLASS_RGB[class][3] end
  return string.format("|cff%02x%02x%02x", r*255, g*255, b*255)
end

OGRH.Roles = OGRH.Roles or {
  active=false, phaseIndex=0, silence=0, silenceGate=5, lastPlus=0, nextAdvanceTime=0,
  tankHeaders=false, healerHeaders=false, healRank={},
  buckets={ TANKS={}, HEALERS={}, MELEE={}, RANGED={} },
  nameClass={}, raidNames={}, raidParty={}, testing=false,
  iconHeaders = {}
}

function OGRH.ColorName(name)
  if not name or name=="" then return "" end
  local c = OGRH.Roles.nameClass[name]
  return (OGRH.ClassColorHex(c or "PRIEST"))..name.."|r"
end

function OGRH.RefreshRoster()
  if OGRH.Roles.testing then return end
  OGRH.Roles.raidNames = {}
  OGRH.Roles.nameClass = {}
  OGRH.Roles.raidParty = {}
  local n = GetNumRaidMembers() or 0
  local i
  for i=1,n do
    local name,_,subgroup,_,class = GetRaidRosterInfo(i)
    if name then
      OGRH.Roles.raidNames[name] = true
      if class then OGRH.Roles.nameClass[name] = string.upper(class) end
      if subgroup then OGRH.Roles.raidParty[name] = subgroup end
    end
  end
end

function OGRH.PruneBucketsToRaid()
  if OGRH.Roles.testing then return end
  local r, nm
  for r,_ in pairs(OGRH.Roles.buckets) do
    for nm,_ in pairs(OGRH.Roles.buckets[r]) do
      if not OGRH.Roles.raidNames[nm] then OGRH.Roles.buckets[r][nm] = nil end
    end
  end
end

function OGRH.InAnyBucket(nm)
  local r,_
  for r,_ in pairs(OGRH.Roles.buckets) do if OGRH.Roles.buckets[r][nm] then return true end end
end

function OGRH.EnsureOrderContiguous(role, present)
  OGRH.EnsureSV()
  local o = OGRH_SV.order[role] or {}
  local k
  for k,_ in pairs(o) do if not present[k] then o[k] = nil end end
  local max = 0
  local _,v; for _,v in pairs(o) do if v>max then max=v end end
  local nm; for nm,_ in pairs(present) do if not o[nm] then max=max+1; o[nm]=max end end
  local arr = {}; for name,idx in pairs(o) do arr[idx]=name end
  local newIndex, j = {}, 1
  local i; for i=1,table.getn(arr) do if arr[i] then newIndex[arr[i]]=j; j=j+1 end end
  OGRH_SV.order[role]=newIndex
end

function OGRH.AddTo(role, name)
  OGRH.EnsureSV()
  if not name or name=="" or not OGRH.Roles.buckets[role] then return end
  if not OGRH.Roles.testing and not OGRH.Roles.raidNames[name] then OGRH.Msg("Cannot assign "..name.." (not in raid)."); return end
  local k,_; for k,_ in pairs(OGRH.Roles.buckets) do OGRH.Roles.buckets[k][name]=nil; if OGRH_SV.order[k] then OGRH_SV.order[k][name]=nil end end
  OGRH.Roles.buckets[role][name]=true
  OGRH_SV.roles[name]=role
  OGRH_SV.tankCategory[name]=nil; OGRH_SV.healerBoss[name]=nil
  local present = {}; local nm; for nm,_ in pairs(OGRH.Roles.buckets[role]) do if OGRH.Roles.testing or OGRH.Roles.raidNames[nm] then present[nm]=true end end
  OGRH.EnsureOrderContiguous(role, present)
  local o = OGRH_SV.order[role] or {}; local max = 0; local _,v; for _,v in pairs(o) do if v>max then max=v end end
  if not o[name] then o[name]=max+1 end; OGRH_SV.order[role]=o
end

OGRH.CLASS_RGB = OGRH.CLASS_RGB
OGRH.ICON_NAMES = {"Star","Circle","Diamond","Triangle","Moon","Square","Cross","Skull"}

Roles = OGRH.Roles
ensureSV = OGRH.EnsureSV
colorName = OGRH.ColorName
sayRW = OGRH.SayRW
msg = OGRH.Msg


-- Return an array of names in a role, sorted by saved order, filtering to current raid unless testing
function OGRH.SortedRoleNamesRaw(role)
  OGRH.EnsureSV()
  local out = {}
  local bucket = OGRH.Roles.buckets[role] or {}
  local name,_
  for name,_ in pairs(bucket) do
    if OGRH.Roles.testing or OGRH.Roles.raidNames[name] then
      table.insert(out, name)
    end
  end
  local ord = OGRH_SV.order[role] or {}
  table.sort(out, function(a,b)
    local ia = ord[a] or 9999
    local ib = ord[b] or 9999
    if ia ~= ib then return ia < ib else return a < b end
  end)
  return out
end


-- === MIGRATION: icon index mapping old->blizzard (run once) ===
function OGRH.MigrateIconOrder()
  if OGRH_SV and not OGRH_SV._icons_migrated then
    local function remap(v) if type(v)=="number" and v>=1 and v<=8 then return 9 - v end return v end
    if OGRH_SV.tankIcon then for k,v in pairs(OGRH_SV.tankIcon) do OGRH_SV.tankIcon[k]=remap(v) end end
    if OGRH_SV.healerIcon then for k,v in pairs(OGRH_SV.healerIcon) do OGRH_SV.healerIcon[k]=remap(v) end end
    OGRH_SV._icons_migrated = true
  end
end

-- === Player Assignment Functions (raid icons 1-8 or numbers 0-9) ===
-- Assignments are stored as tables: {type="icon", value=8} or {type="number", value=5}
-- Get player assignment: returns table {type="icon"|"number", value=0-9} or nil if unassigned
function OGRH.GetPlayerAssignment(playerName)
  OGRH.EnsureSV()
  return OGRH_SV.playerAssignments[playerName]
end

-- Set player assignment: assignData should be {type="icon"|"number", value=number} or nil to clear
function OGRH.SetPlayerAssignment(playerName, assignData)
  OGRH.EnsureSV()
  if assignData == nil then
    OGRH_SV.playerAssignments[playerName] = nil
  elseif type(assignData) == "table" and assignData.type and assignData.value then
    if (assignData.type == "icon" and assignData.value >= 1 and assignData.value <= 8) or
       (assignData.type == "number" and assignData.value >= 0 and assignData.value <= 9) then
      OGRH_SV.playerAssignments[playerName] = {type = assignData.type, value = assignData.value}
    end
  end
end

-- Clear all player assignments
function OGRH.ClearAllAssignments()
  OGRH.EnsureSV()
  OGRH_SV.playerAssignments = {}
end

-- === Share Window for Import/Export ===
function OGRH.ShowShareWindow()
  -- Create window if it doesn't exist
  if not OGRH_ShareFrame then
    local frame = CreateFrame("Frame", "OGRH_ShareFrame", UIParent)
    frame:SetWidth(600)
    frame:SetHeight(400)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetFrameStrata("DIALOG")
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function() frame:StartMoving() end)
    frame:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
    
    -- Backdrop
    frame:SetBackdrop({
      bgFile = "Interface/Tooltips/UI-Tooltip-Background",
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
      edgeSize = 12,
      insets = {left = 4, right = 4, top = 4, bottom = 4}
    })
    frame:SetBackdropColor(0, 0, 0, 0.85)
    
    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -15)
    title:SetText("Share Raid Data")
    
    -- Instructions
    local instructions = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    instructions:SetPoint("TOPLEFT", 20, -45)
    instructions:SetText("Export: Click 'Export' to generate data. Copy from box below.")
    
    local instructions2 = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    instructions2:SetPoint("TOPLEFT", 20, -60)
    instructions2:SetText("Import: Paste data in box below and click 'Import'.")
    
    -- Scroll frame backdrop
    local scrollBackdrop = CreateFrame("Frame", nil, frame)
    scrollBackdrop:SetPoint("TOPLEFT", 17, -80)
    scrollBackdrop:SetPoint("BOTTOMRIGHT", -17, 50)
    scrollBackdrop:SetBackdrop({
      bgFile = "Interface/Tooltips/UI-Tooltip-Background",
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
      tile = true,
      tileSize = 16,
      edgeSize = 16,
      insets = {left = 3, right = 3, top = 3, bottom = 3}
    })
    scrollBackdrop:SetBackdropColor(0, 0, 0, 1)
    scrollBackdrop:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    
    -- Scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", "OGRH_ShareScrollFrame", scrollBackdrop, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 5, -6)
    scrollFrame:SetPoint("BOTTOMRIGHT", -28, 6)
    
    -- Scroll child
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollFrame:SetScrollChild(scrollChild)
    scrollChild:SetWidth(scrollFrame:GetWidth())
    scrollChild:SetHeight(400)
    
    -- Edit box
    local editBox = CreateFrame("EditBox", nil, scrollChild)
    editBox:SetPoint("TOPLEFT", 0, 0)
    editBox:SetWidth(scrollChild:GetWidth())
    editBox:SetHeight(400)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetTextInsets(5, 5, 3, 3)
    editBox:SetScript("OnEscapePressed", function() editBox:ClearFocus() end)
    frame.editBox = editBox
    
    -- Update scroll child size when scroll frame resizes
    scrollFrame:SetScript("OnSizeChanged", function()
      scrollChild:SetWidth(scrollFrame:GetWidth())
      editBox:SetWidth(scrollFrame:GetWidth())
    end)
    
    -- Update scroll range when text changes
    editBox:SetScript("OnTextChanged", function()
      scrollFrame:UpdateScrollChildRect()
    end)
    
    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    closeBtn:SetWidth(80)
    closeBtn:SetHeight(25)
    closeBtn:SetPoint("BOTTOMRIGHT", -20, 15)
    closeBtn:SetText("Close")
    closeBtn:SetScript("OnClick", function() frame:Hide() end)
    
    -- Clear button
    local clearBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    clearBtn:SetWidth(80)
    clearBtn:SetHeight(25)
    clearBtn:SetPoint("RIGHT", closeBtn, "LEFT", -10, 0)
    clearBtn:SetText("Clear")
    clearBtn:SetScript("OnClick", function()
      editBox:SetText("")
      editBox:SetFocus()
    end)
    
    -- Import button
    local importBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    importBtn:SetWidth(100)
    importBtn:SetHeight(25)
    importBtn:SetPoint("RIGHT", clearBtn, "LEFT", -10, 0)
    importBtn:SetText("Import")
    importBtn:SetScript("OnClick", function()
      local text = editBox:GetText()
      if text and text ~= "" then
        if OGRH.ImportShareData then
          OGRH.ImportShareData(text)
        end
      else
        OGRH.Msg("No data to import.")
      end
    end)
    
    -- Export button
    local exportBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    exportBtn:SetWidth(100)
    exportBtn:SetHeight(25)
    exportBtn:SetPoint("BOTTOMLEFT", 20, 15)
    exportBtn:SetText("Export")
    exportBtn:SetScript("OnClick", function()
      if OGRH.ExportShareData then
        local data = OGRH.ExportShareData()
        editBox:SetText(data)
        editBox:HighlightText()
        editBox:SetFocus()
      end
    end)
    
    OGRH_ShareFrame = frame
  end
  
  OGRH_ShareFrame:Show()
end

-- Export data to string
function OGRH.ExportShareData()
  OGRH.EnsureSV()
  
  -- Collect all encounter management data
  local exportData = {
    version = "1.0",
    encounterMgmt = OGRH_SV.encounterMgmt or { raids = {}, encounters = {} },
    poolDefaults = OGRH_SV.poolDefaults or {},
    encounterPools = OGRH_SV.encounterPools or {},
    encounterAssignments = OGRH_SV.encounterAssignments or {},
    encounterRaidMarks = OGRH_SV.encounterRaidMarks or {},
    encounterAssignmentNumbers = OGRH_SV.encounterAssignmentNumbers or {},
    encounterAnnouncements = OGRH_SV.encounterAnnouncements or {},
    tradeItems = OGRH_SV.tradeItems or {}
  }
  
  -- Serialize to string (using a simple format)
  local serialized = OGRH.Serialize(exportData)
  return serialized
end

-- Import data from string
function OGRH.ImportShareData(dataString)
  if not dataString or dataString == "" then
    OGRH.Msg("No data to import.")
    return
  end
  
  -- Deserialize
  local success, importData = pcall(OGRH.Deserialize, dataString)
  
  if not success or not importData then
    OGRH.Msg("|cffff0000Error:|r Failed to parse import data.")
    return
  end
  
  -- Validate version
  if not importData.version then
    OGRH.Msg("|cffff0000Error:|r Invalid data format.")
    return
  end
  
  OGRH.EnsureSV()
  
  -- Import all encounter management data
  if importData.encounterMgmt then
    OGRH_SV.encounterMgmt = importData.encounterMgmt
  end
  if importData.poolDefaults then
    OGRH_SV.poolDefaults = importData.poolDefaults
  end
  if importData.encounterPools then
    OGRH_SV.encounterPools = importData.encounterPools
  end
  if importData.encounterAssignments then
    OGRH_SV.encounterAssignments = importData.encounterAssignments
  end
  if importData.encounterRaidMarks then
    OGRH_SV.encounterRaidMarks = importData.encounterRaidMarks
  end
  if importData.encounterAssignmentNumbers then
    OGRH_SV.encounterAssignmentNumbers = importData.encounterAssignmentNumbers
  end
  if importData.encounterAnnouncements then
    OGRH_SV.encounterAnnouncements = importData.encounterAnnouncements
  end
  if importData.tradeItems then
    OGRH_SV.tradeItems = importData.tradeItems
  end
  
  OGRH.Msg("|cff00ff00Success:|r Encounter data imported.")
  
  -- Refresh any open windows
  if OGRH_EncounterSetupFrame and OGRH_EncounterSetupFrame.RefreshAll then
    OGRH_EncounterSetupFrame.RefreshAll()
  end
  if OGRH_TradeSettingsFrame and OGRH_TradeSettingsFrame.RefreshList then
    OGRH_TradeSettingsFrame.RefreshList()
  end
  if OGRH_BWLEncounterFrame and OGRH_BWLEncounterFrame.RefreshRaidsList then
    OGRH_BWLEncounterFrame.RefreshRaidsList()
  end
end

-- Simple serialization (converts table to string)
function OGRH.Serialize(tbl)
  local function serializeValue(v)
    local t = type(v)
    if t == "string" then
      return string.format("%q", v)
    elseif t == "number" or t == "boolean" then
      return tostring(v)
    elseif t == "table" then
      return OGRH.SerializeTable(v)
    else
      return "nil"
    end
  end
  
  local function serializeTable(tbl)
    local parts = {}
    table.insert(parts, "{")
    
    for k, v in pairs(tbl) do
      local keyStr
      if type(k) == "string" then
        keyStr = string.format("[%q]", k)
      else
        keyStr = "[" .. tostring(k) .. "]"
      end
      table.insert(parts, keyStr .. "=" .. serializeValue(v) .. ",")
    end
    
    table.insert(parts, "}")
    return table.concat(parts, "")
  end
  
  OGRH.SerializeTable = serializeTable
  return serializeTable(tbl)
end

-- Simple deserialization (converts string back to table)
function OGRH.Deserialize(str)
  if not str or str == "" then return nil end
  
  -- Use loadstring to evaluate the table string
  local func = loadstring("return " .. str)
  if not func then return nil end
  
  return func()
end

-- Trade Settings Window
function OGRH.ShowTradeSettings()
  OGRH.EnsureSV()
  
  if OGRH_TradeSettingsFrame then
    OGRH_TradeSettingsFrame:Show()
    OGRH.RefreshTradeSettings()
    return
  end
  
  local frame = CreateFrame("Frame", "OGRH_TradeSettingsFrame", UIParent)
  frame:SetWidth(300)
  frame:SetHeight(450)
  frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  frame:SetFrameStrata("DIALOG")
  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function() frame:StartMoving() end)
  frame:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
  
  -- Backdrop
  frame:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 12,
    insets = {left = 4, right = 4, top = 4, bottom = 4}
  })
  frame:SetBackdropColor(0, 0, 0, 0.85)
  
  -- Title
  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOP", 0, -15)
  title:SetText("Trade Settings")
  
  -- Close button
  local closeBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  closeBtn:SetWidth(60)
  closeBtn:SetHeight(24)
  closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -10)
  closeBtn:SetText("Close")
  closeBtn:SetScript("OnClick", function() frame:Hide() end)
  
  -- Instructions
  local instructions = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  instructions:SetPoint("TOPLEFT", 20, -45)
  instructions:SetText("Configure trade items and quantities:")
  
  -- List backdrop
  local listBackdrop = CreateFrame("Frame", nil, frame)
  listBackdrop:SetPoint("TOPLEFT", 17, -75)
  listBackdrop:SetPoint("BOTTOMRIGHT", -17, 10)
  listBackdrop:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 12,
    insets = {left = 3, right = 3, top = 3, bottom = 3}
  })
  listBackdrop:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
  
  -- Scroll frame
  local scrollFrame = CreateFrame("ScrollFrame", nil, listBackdrop)
  scrollFrame:SetPoint("TOPLEFT", listBackdrop, "TOPLEFT", 5, -5)
  scrollFrame:SetPoint("BOTTOMRIGHT", listBackdrop, "BOTTOMRIGHT", -22, 5)
  
  -- Scroll child
  local scrollChild = CreateFrame("Frame", nil, scrollFrame)
  scrollChild:SetWidth(235)
  scrollChild:SetHeight(1)
  scrollFrame:SetScrollChild(scrollChild)
  frame.scrollChild = scrollChild
  frame.scrollFrame = scrollFrame
  
  -- Create scrollbar
  local scrollBar = CreateFrame("Slider", nil, scrollFrame)
  scrollBar:SetPoint("TOPRIGHT", listBackdrop, "TOPRIGHT", -5, -16)
  scrollBar:SetPoint("BOTTOMRIGHT", listBackdrop, "BOTTOMRIGHT", -5, 16)
  scrollBar:SetWidth(16)
  scrollBar:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 8,
    insets = {left = 3, right = 3, top = 3, bottom = 3}
  })
  scrollBar:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
  scrollBar:SetOrientation("VERTICAL")
  scrollBar:SetMinMaxValues(0, 1)
  scrollBar:SetValue(0)
  scrollBar:SetValueStep(22)
  scrollBar:Hide()
  frame.scrollBar = scrollBar
  
  scrollBar:SetScript("OnValueChanged", function()
    scrollFrame:SetVerticalScroll(this:GetValue())
  end)
  
  scrollFrame:EnableMouseWheel(true)
  scrollFrame:SetScript("OnMouseWheel", function()
    if not scrollBar:IsShown() then
      return
    end
    
    local delta = arg1
    local current = scrollBar:GetValue()
    local minVal, maxVal = scrollBar:GetMinMaxValues()
    
    if delta > 0 then
      scrollBar:SetValue(math.max(minVal, current - 22))
    else
      scrollBar:SetValue(math.min(maxVal, current + 22))
    end
  end)
  
  frame:Show()
  OGRH.RefreshTradeSettings()
end

-- Refresh the trade settings list
function OGRH.RefreshTradeSettings()
  if not OGRH_TradeSettingsFrame then return end
  
  local scrollChild = OGRH_TradeSettingsFrame.scrollChild
  
  -- Clear existing rows
  if scrollChild.rows then
    for _, row in ipairs(scrollChild.rows) do
      row:Hide()
      row:SetParent(nil)
    end
  end
  scrollChild.rows = {}
  
  OGRH.EnsureSV()
  local items = OGRH_SV.tradeItems
  
  local yOffset = -5
  local rowHeight = 22
  local rowSpacing = 2
  
  for i, itemData in ipairs(items) do
    local row = CreateFrame("Button", nil, scrollChild)
    row:SetWidth(235)
    row:SetHeight(rowHeight)
    row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, yOffset)
    
    -- Background
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    bg:SetVertexColor(0.2, 0.2, 0.2, 0.5)
    row.bg = bg
    
    local idx = i
    
    -- Delete button (X mark - raid target icon 7)
    local deleteBtn = CreateFrame("Button", nil, row)
    deleteBtn:SetWidth(16)
    deleteBtn:SetHeight(16)
    deleteBtn:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    
    local deleteIcon = deleteBtn:CreateTexture(nil, "ARTWORK")
    deleteIcon:SetWidth(16)
    deleteIcon:SetHeight(16)
    deleteIcon:SetAllPoints(deleteBtn)
    deleteIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    deleteIcon:SetTexCoord(0.5, 0.75, 0.25, 0.5)  -- Cross/X icon (raid mark 7)
    
    local deleteHighlight = deleteBtn:CreateTexture(nil, "HIGHLIGHT")
    deleteHighlight:SetWidth(16)
    deleteHighlight:SetHeight(16)
    deleteHighlight:SetAllPoints(deleteBtn)
    deleteHighlight:SetTexture("Interface\\Buttons\\UI-Common-MouseHilight")
    deleteHighlight:SetBlendMode("ADD")
    
    deleteBtn:SetScript("OnClick", function()
      table.remove(OGRH_SV.tradeItems, idx)
      OGRH.RefreshTradeSettings()
    end)
    
    -- Down button
    local downBtn = CreateFrame("Button", nil, row)
    downBtn:SetWidth(32)
    downBtn:SetHeight(32)
    downBtn:SetPoint("RIGHT", deleteBtn, "LEFT", 5, 0)
    downBtn:SetNormalTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up")
    downBtn:SetPushedTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Down")
    downBtn:SetHighlightTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Highlight")
    downBtn:SetScript("OnClick", function()
      if idx < table.getn(OGRH_SV.tradeItems) then
        local temp = OGRH_SV.tradeItems[idx + 1]
        OGRH_SV.tradeItems[idx + 1] = OGRH_SV.tradeItems[idx]
        OGRH_SV.tradeItems[idx] = temp
        OGRH.RefreshTradeSettings()
      end
    end)
    
    -- Up button
    local upBtn = CreateFrame("Button", nil, row)
    upBtn:SetWidth(32)
    upBtn:SetHeight(32)
    upBtn:SetPoint("RIGHT", downBtn, "LEFT", 13, 0)
    upBtn:SetNormalTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Up")
    upBtn:SetPushedTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Down")
    upBtn:SetHighlightTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Highlight")
    upBtn:SetScript("OnClick", function()
      if idx > 1 then
        local temp = OGRH_SV.tradeItems[idx - 1]
        OGRH_SV.tradeItems[idx - 1] = OGRH_SV.tradeItems[idx]
        OGRH_SV.tradeItems[idx] = temp
        OGRH.RefreshTradeSettings()
      end
    end)
    
    -- Quantity (positioned 10px from up arrow)
    local qtyText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    qtyText:SetPoint("RIGHT", upBtn, "LEFT", -10, 0)
    qtyText:SetText("x" .. (itemData.quantity or 1))
    
    -- Item name (fill remaining space)
    local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    nameText:SetPoint("LEFT", row, "LEFT", 5, 0)
    nameText:SetPoint("RIGHT", qtyText, "LEFT", -5, 0)
    nameText:SetJustifyH("LEFT")
    nameText:SetText(itemData.name or ("Item " .. itemData.itemId))
    upBtn:SetHighlightTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Highlight")
    upBtn:SetScript("OnClick", function()
      if idx > 1 then
        local temp = OGRH_SV.tradeItems[idx - 1]
        OGRH_SV.tradeItems[idx - 1] = OGRH_SV.tradeItems[idx]
        OGRH_SV.tradeItems[idx] = temp
        OGRH.RefreshTradeSettings()
      end
    end)
    
    table.insert(scrollChild.rows, row)
    yOffset = yOffset - rowHeight - rowSpacing
  end
  
  -- Add "Add Item" placeholder row at the bottom
  local addItemBtn = CreateFrame("Button", nil, scrollChild)
  addItemBtn:SetWidth(235)
  addItemBtn:SetHeight(rowHeight)
  addItemBtn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, yOffset)
  
  -- Background
  local bg = addItemBtn:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetTexture("Interface\\Buttons\\WHITE8X8")
  bg:SetVertexColor(0.1, 0.3, 0.1, 0.5)
  
  -- Highlight
  local highlight = addItemBtn:CreateTexture(nil, "HIGHLIGHT")
  highlight:SetAllPoints()
  highlight:SetTexture("Interface\\Buttons\\WHITE8X8")
  highlight:SetVertexColor(0.2, 0.5, 0.2, 0.5)
  
  -- Text
  local addText = addItemBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  addText:SetPoint("CENTER", addItemBtn, "CENTER", 0, 0)
  addText:SetText("|cff00ff00Add Item|r")
  
  addItemBtn:SetScript("OnClick", function()
    OGRH.ShowAddTradeItemDialog()
  end)
  
  table.insert(scrollChild.rows, addItemBtn)
  yOffset = yOffset - rowHeight
  
  -- Update scroll child height
  local contentHeight = math.abs(yOffset) + 5
  scrollChild:SetHeight(contentHeight)
  
  -- Update scrollbar visibility
  local scrollFrame = OGRH_TradeSettingsFrame.scrollFrame
  local scrollBar = OGRH_TradeSettingsFrame.scrollBar
  local scrollFrameHeight = scrollFrame:GetHeight()
  
  if contentHeight > scrollFrameHeight then
    scrollBar:Show()
    scrollBar:SetMinMaxValues(0, contentHeight - scrollFrameHeight)
    scrollBar:SetValue(0)
    scrollFrame:SetVerticalScroll(0)
  else
    scrollBar:Hide()
    scrollFrame:SetVerticalScroll(0)
  end
end

-- Show add trade item dialog
function OGRH.ShowAddTradeItemDialog()
  if OGRH_AddTradeItemDialog then
    OGRH_AddTradeItemDialog:Show()
    return
  end
  
  local dialog = CreateFrame("Frame", "OGRH_AddTradeItemDialog", UIParent)
  dialog:SetWidth(250)
  dialog:SetHeight(160)
  dialog:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  dialog:SetFrameStrata("FULLSCREEN_DIALOG")
  dialog:EnableMouse(true)
  dialog:SetMovable(true)
  dialog:RegisterForDrag("LeftButton")
  dialog:SetScript("OnDragStart", function() dialog:StartMoving() end)
  dialog:SetScript("OnDragStop", function() dialog:StopMovingOrSizing() end)
  
  -- Backdrop
  dialog:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 12,
    insets = {left = 4, right = 4, top = 4, bottom = 4}
  })
  dialog:SetBackdropColor(0, 0, 0, 0.9)
  
  -- Title
  local title = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOP", 0, -15)
  title:SetText("Add Trade Item")
  
  -- Item ID label
  local itemIdLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  itemIdLabel:SetPoint("TOPLEFT", 20, -50)
  itemIdLabel:SetText("Item ID:")
  
  -- Item ID input
  local itemIdInput = CreateFrame("EditBox", nil, dialog)
  itemIdInput:SetPoint("LEFT", itemIdLabel, "RIGHT", 10, 0)
  itemIdInput:SetWidth(120)
  itemIdInput:SetHeight(25)
  itemIdInput:SetAutoFocus(false)
  itemIdInput:SetFontObject(ChatFontNormal)
  itemIdInput:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 12,
    insets = {left = 4, right = 4, top = 4, bottom = 4}
  })
  itemIdInput:SetBackdropColor(0, 0, 0, 0.8)
  itemIdInput:SetTextInsets(8, 8, 0, 0)
  itemIdInput:SetScript("OnEscapePressed", function() itemIdInput:ClearFocus() end)
  dialog.itemIdInput = itemIdInput
  
  -- Quantity label
  local qtyLabel = dialog:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  qtyLabel:SetPoint("TOPLEFT", 20, -90)
  qtyLabel:SetText("Quantity:")
  
  -- Quantity input
  local qtyInput = CreateFrame("EditBox", nil, dialog)
  qtyInput:SetPoint("LEFT", qtyLabel, "RIGHT", 10, 0)
  qtyInput:SetWidth(120)
  qtyInput:SetHeight(25)
  qtyInput:SetAutoFocus(false)
  qtyInput:SetFontObject(ChatFontNormal)
  qtyInput:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 12,
    insets = {left = 4, right = 4, top = 4, bottom = 4}
  })
  qtyInput:SetBackdropColor(0, 0, 0, 0.8)
  qtyInput:SetTextInsets(8, 8, 0, 0)
  qtyInput:SetText("1")
  qtyInput:SetScript("OnEscapePressed", function() qtyInput:ClearFocus() end)
  dialog.qtyInput = qtyInput
  
  -- Cancel button
  local cancelBtn = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
  cancelBtn:SetWidth(80)
  cancelBtn:SetHeight(25)
  cancelBtn:SetPoint("BOTTOMRIGHT", -20, 15)
  cancelBtn:SetText("Cancel")
  cancelBtn:SetScript("OnClick", function()
    dialog:Hide()
  end)
  
  -- Add button
  local addBtn = CreateFrame("Button", nil, dialog, "UIPanelButtonTemplate")
  addBtn:SetWidth(80)
  addBtn:SetHeight(25)
  addBtn:SetPoint("RIGHT", cancelBtn, "LEFT", -10, 0)
  addBtn:SetText("Add")
  addBtn:SetScript("OnClick", function()
    local itemIdText = itemIdInput:GetText()
    local qtyText = qtyInput:GetText()
    
    local itemId = tonumber(itemIdText)
    local quantity = tonumber(qtyText)
    
    if not itemId or itemId <= 0 then
      OGRH.Msg("Invalid Item ID. Please enter a valid number.")
      return
    end
    
    if not quantity or quantity <= 0 then
      OGRH.Msg("Invalid Quantity. Please enter a valid number.")
      return
    end
    
    -- Get item name from game
    local itemName, itemLink = GetItemInfo(itemId)
    
    -- Add to list
    OGRH.EnsureSV()
    table.insert(OGRH_SV.tradeItems, {
      itemId = itemId,
      name = itemName or ("Item " .. itemId),
      quantity = quantity
    })
    
    -- Clear inputs
    itemIdInput:SetText("")
    qtyInput:SetText("1")
    
    -- Refresh settings window
    OGRH.RefreshTradeSettings()
    
    dialog:Hide()
    OGRH.Msg("Added trade item: " .. (itemName or ("Item " .. itemId)))
  end)
  
  dialog:Show()
end




