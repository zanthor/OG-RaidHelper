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
  RESET = "|r"
}

function OGRH.EnsureSV()
  if not OGRH_SV then OGRH_SV = { roles = {}, order = {}, pollTime = 5, tankCategory = {}, healerBoss = {}, ui = {}, tankIcon = {}, healerIcon = {}, rolesUI = {}, playerAssignments = {} } end
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

-- Handle incoming addon messages
local addonFrame = CreateFrame("Frame")
addonFrame:RegisterEvent("CHAT_MSG_ADDON")
addonFrame:SetScript("OnEvent", function()
  if event == "CHAT_MSG_ADDON" then
    local prefix, message, distribution, sender = arg1, arg2, arg3, arg4
    
    if prefix == OGRH.ADDON_PREFIX then
      -- Handle ready check request from assistant
      if message == "READYCHECK_REQUEST" then
        -- Only process if we are the raid leader
        if IsRaidLeader and IsRaidLeader() == 1 then
          DoReadyCheck()
        end
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


