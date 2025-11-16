-- OG-RaidHelper.lua  (Turtle-WoW 1.12)   v1.12.1
-- Control window + Roles board, ordering, C'Thun, 4HM, Sand helper, Poll/Test SV, Healing pairs.

local ADDON, CMD = "OG-RaidHelper", "ogrh"

------------------------------------------------------------
-- SavedVariables guard
------------------------------------------------------------
local function ensureSV()
  if not OGRH_SV then OGRH_SV = { roles = {}, order = {}, pollTime = 5, tankCategory = {}, healerBoss = {}, ui = {} } end
  if not OGRH_SV.roles then OGRH_SV.roles = {} end
  if not OGRH_SV.order then OGRH_SV.order = {} end
  if not OGRH_SV.order.TANKS   then OGRH_SV.order.TANKS   = {} end
  if not OGRH_SV.order.HEALERS then OGRH_SV.order.HEALERS = {} end
  if not OGRH_SV.order.MELEE   then OGRH_SV.order.MELEE   = {} end
  if not OGRH_SV.order.RANGED  then OGRH_SV.order.RANGED  = {} end
  if OGRH_SV.pollTime == nil then OGRH_SV.pollTime = 5 end
  if not OGRH_SV.tankCategory then OGRH_SV.tankCategory = {} end
  if not OGRH_SV.healerBoss then OGRH_SV.healerBoss = {} end
  if not OGRH_SV.ui then OGRH_SV.ui = {} end
end
local _svf = CreateFrame("Frame"); _svf:RegisterEvent("VARIABLES_LOADED")
_svf:SetScript("OnEvent", function() ensureSV() end)
ensureSV()

------------------------------------------------------------
-- Utils
------------------------------------------------------------
local function msg(s) if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cff66ccff[OGRH]|r "..tostring(s)) end end
local function trim(s) return string.gsub(s or "", "^%s*(.-)%s*$", "%1") end
local function mod1(n,t) return math.mod(n-1, t)+1 end
local CLASS_RGB = {
  DRUID={1,0.49,0.04}, HUNTER={0.67,0.83,0.45}, MAGE={0.25,0.78,0.92}, PALADIN={0.96,0.55,0.73},
  PRIEST={1,1,1}, ROGUE={1,0.96,0.41}, SHAMAN={0,0.44,0.87}, WARLOCK={0.53,0.53,0.93}, WARRIOR={0.78,0.61,0.43}
}
local function classColorHex(c)
  if not c then return "|cffffffff" end
  local r,g,b=1,1,1
  if RAID_CLASS_COLORS and RAID_CLASS_COLORS[c] then r,g,b=RAID_CLASS_COLORS[c].r,RAID_CLASS_COLORS[c].g,RAID_CLASS_COLORS[c].b
  elseif CLASS_RGB[c] then r,g,b=CLASS_RGB[c][1],CLASS_RGB[c][2],CLASS_RGB[c][3] end
  return string.format("|cff%02x%02x%02x", r*255, g*255, b*255)
end
local function canRW() return (IsRaidLeader() == 1) or (IsRaidOfficer and IsRaidOfficer()==1) or (IsRaidOfficer and IsRaidOfficer()) end
local function sayRW(t) if canRW() then SendChatMessage(t,"RAID_WARNING") else SendChatMessage(t,"RAID") end end

-- Roles container
Roles = Roles or { active=false, phaseIndex=0, silence=0, silenceGate=5, lastPlus=0, nextAdvanceTime=0,
                   tankHeaders=false, healerHeaders=false, healRank={},
                   buckets={TANKS={},HEALERS={},MELEE={},RANGED={}},
                   nameClass={}, raidNames={}, raidParty={}, testing=false }

-- Colorize a name based on class
local function colorName(name)
  if not name or name=="" then return "" end
  local c = Roles.nameClass[name]
  return (classColorHex(c or "PRIEST"))..name.."|r"
end

------------------------------------------------------------
-- Driver frame (timers)
------------------------------------------------------------
local F = CreateFrame("Frame","OGRH_Frame"); F:Hide()
F.tick, F.interval = 0, 0.10

------------------------------------------------------------
-- SAND HELPER
------------------------------------------------------------
local ITEM_SAND, SAND_COUNT = 19183, 5
F.state, F.didSplit, F.placed, F.acceptTries, F.maxAcceptTries = "IDLE", false, false, 0, 20
F.dBag, F.dSlot = nil, nil
local function itemIdFromLink(link) if not link then return nil end local id=string.match(link,"Hitem:(%d+):"); return id and tonumber(id) or nil end
local function findStackExact(id, need) for b=0,4 do local n=GetContainerNumSlots(b) or 0 for s=1,n do local l=GetContainerItemLink(b,s) if l and itemIdFromLink(l)==id then local _,c,lck=GetContainerItemInfo(b,s) if (c or 0)==need and not lck then return b,s end end end end end
local function findSourceStack(id, need) for b=0,4 do local n=GetContainerNumSlots(b) or 0 for s=1,n do local l=GetContainerItemLink(b,s) if l and itemIdFromLink(l)==id then local _,c,lck=GetContainerItemInfo(b,s) if (c or 0)>=need and not lck then return b,s end end end end end
local function findEmptySlot() for b=0,4 do local n=GetContainerNumSlots(b) or 0 for s=1,n do local tex,cnt,lck=GetContainerItemInfo(b,s) if not tex and not cnt and not lck then return b,s end end end end
local function firstOpenTradeSlot() for i=1,6 do if not GetTradePlayerItemInfo(i) then return i end end end
local function tradeItemButton(i) return getglobal("TradePlayerItem"..i.."ItemButton") end
local function resetSand() F.state="IDLE"; F.didSplit=false; F.placed=false; F.acceptTries=0; F.dBag=nil; F.dSlot=nil; if not Roles or not Roles.active then F:Hide() end; ClearCursor() end
local function runSand() if F.state~="IDLE" then msg("Already running."); return end F.state="SAND"; F.tick=F.interval; F:Show() end

------------------------------------------------------------
-- ROLES & ORDERING
------------------------------------------------------------
local ROLES_ORDER = {"HEALERS","TANKS","RANGED","MELEE"}
local CLASS_HINT = { ROGUE="MELEE", MAGE="RANGED", WARLOCK="RANGED" }

local TANK_HEADER_IDS = {"__HDR_THANE__","__HDR_LADY__","__HDR_ZELIEK__","__HDR_MOGRAINE__"}
local TANK_HEADER_LABEL = { __HDR_THANE__="-- Thane --", __HDR_LADY__="-- Lady --", __HDR_ZELIEK__="-- Zeliek --", __HDR_MOGRAINE__="-- Mograine --" }
local function isTankHeader(name) return name=="__HDR_THANE__" or name=="__HDR_LADY__" or name=="__HDR_ZELIEK__" or name=="__HDR_MOGRAINE__" end

local HEAL_HEADER_IDS = {"__HDR_H_THANE__","__HDR_H_LADY__","__HDR_H_ZELIEK__","__HDR_H_MOGRAINE__"}
local HEAL_HEADER_LABEL = { __HDR_H_THANE__="-- Thane --", __HDR_H_LADY__="-- Lady --", __HDR_H_ZELIEK__="-- Zeliek --", __HDR_H_MOGRAINE__="-- Mograine --" }
local function isHealerHeader(name) return name=="__HDR_H_THANE__" or name=="__HDR_H_LADY__" or name=="__HDR_H_ZELIEK__" or name=="__HDR_H_MOGRAINE__" end

local function refreshRoster()
  if Roles.testing then return end
  Roles.raidNames = {}; Roles.nameClass={}; Roles.raidParty={}
  local n=GetNumRaidMembers() or 0
  for i=1,n do local name,_,subgroup,_,class = GetRaidRosterInfo(i)
    if name then Roles.raidNames[name]=true; if class then Roles.nameClass[name]=string.upper(class) end; if subgroup then Roles.raidParty[name]=subgroup end end
  end
end
local function pruneBucketsToRaid()
  if Roles.testing then return end
  for r,_ in pairs(Roles.buckets) do for nm,_ in pairs(Roles.buckets[r]) do if not Roles.raidNames[nm] then Roles.buckets[r][nm]=nil end end end
end
local function inAnyBucket(nm) for r,_ in pairs(Roles.buckets) do if Roles.buckets[r][nm] then return true end end end

local function ensureOrderContiguous(role, present)
  ensureSV()
  local o = OGRH_SV.order[role] or {}
  for k,_ in pairs(o) do if not present[k] then o[k]=nil end end
  local max = 0; for _,v in pairs(o) do if v>max then max=v end end
  for nm,_ in pairs(present) do if not o[nm] then max=max+1; o[nm]=max end end
  local arr = {}; for name,idx in pairs(o) do arr[idx]=name end
  local newIndex, j = {}, 1
  for i=1,table.getn(arr) do if arr[i] then newIndex[arr[i]]=j; j=j+1 end end
  OGRH_SV.order[role]=newIndex
end

local function addTo(role, name)
  ensureSV()
  if not name or name == "" or not Roles.buckets[role] then return end
  if not Roles.testing and not Roles.raidNames[name] then msg("Cannot assign "..name.." (not in raid)."); return end
  for k,_ in pairs(Roles.buckets) do Roles.buckets[k][name]=nil; if OGRH_SV.order[k] then OGRH_SV.order[k][name]=nil end end
  Roles.buckets[role][name]=true; OGRH_SV.roles[name]=role
  if OGRH_SV.tankCategory then OGRH_SV.tankCategory[name]=nil end
  if OGRH_SV.healerBoss then OGRH_SV.healerBoss[name]=nil end
  local present = {}; for nm,_ in pairs(Roles.buckets[role]) do if Roles.testing or Roles.raidNames[nm] then present[nm]=true end end
  ensureOrderContiguous(role, present)
  local o = OGRH_SV.order[role] or {}; local max=0; for _,v in pairs(o) do if v>max then max=v end end
  if not o[name] then o[name]=max+1 end; OGRH_SV.order[role]=o
end

local function sortedRoleList(role)
  ensureSV()
  local present={}; for nm,_ in pairs(Roles.buckets[role]) do if Roles.testing or Roles.raidNames[nm] then present[nm]=true end end
  ensureOrderContiguous(role, present)
  local o=OGRH_SV.order[role]; local arr={}; for nm,_ in pairs(present) do table.insert(arr,nm) end
  table.sort(arr, function(a,b) local ia=o[a] or 9999; local ib=o[b] or 9999; if ia~=ib then return ia<ib else return a<b end end)

  if role=="TANKS" and Roles.tankHeaders then
    local groups = { {}, {}, {}, {} }; for i=1,table.getn(arr) do local n=arr[i]; local g=OGRH_SV.tankCategory[n] or 1; if g<1 then g=1 elseif g>4 then g=4 end; table.insert(groups[g], n) end
    local out = {}; for h=1,4 do table.insert(out, TANK_HEADER_IDS[h]); for j=1,table.getn(groups[h]) do table.insert(out, groups[h][j]) end end
    return out
  end
  if role=="HEALERS" and Roles.healerHeaders then
    local groupsH = { {}, {}, {}, {} }
    for i=1,table.getn(arr) do local n=arr[i]; local g=OGRH_SV.healerBoss[n] or 1; if g<1 then g=1 elseif g>4 then g=4 end; table.insert(groupsH[g], n) end
    Roles.healRank = {}; local outH = {}
    for h=1,4 do table.insert(outH, HEAL_HEADER_IDS[h]); for j=1,table.getn(groupsH[h]) do local nm2=groupsH[h][j]; Roles.healRank[nm2]=j; table.insert(outH, nm2) end end
    return outH
  end
  return arr
end

local function sortedRoleNamesRaw(role)
  ensureSV()
  local present={}; for nm,_ in pairs(Roles.buckets[role]) do if Roles.testing or Roles.raidNames[nm] then present[nm]=true end end
  ensureOrderContiguous(role, present)
  local o=OGRH_SV.order[role] or {}; local arr={}; for nm,_ in pairs(present) do table.insert(arr,nm) end
  table.sort(arr, function(a,b) local ia=o[a] or 9999; local ib=o[b] or 9999; if ia~=ib then return ia<ib else return a<b end end)
  return arr
end

local function moveInRole(role, name, dir)
  ensureSV(); if not name then return end
  if role=="TANKS" and Roles.tankHeaders and (not isTankHeader(name)) then
    local list=sortedRoleList(role); local idx=0; for i=1,table.getn(list) do if list[i]==name then idx=i; break end end; if idx==0 then return end
    local tgt=idx+dir; if tgt<1 or tgt>table.getn(list) then return end
    if isTankHeader(list[tgt]) then tgt=tgt+dir; if tgt<1 or tgt>table.getn(list) then return end
      local hdr; if dir>0 then hdr=list[idx+1] else hdr=list[tgt] end
      local headerIdx=1; if hdr==TANK_HEADER_IDS[1] then headerIdx=1 elseif hdr==TANK_HEADER_IDS[2] then headerIdx=2 elseif hdr==TANK_HEADER_IDS[3] then headerIdx=3 elseif hdr==TANK_HEADER_IDS[4] then headerIdx=4 end
      OGRH_SV.tankCategory[name]=headerIdx; if isTankHeader(list[tgt]) then return end
    end
    local a=name; local b=list[tgt]; if isTankHeader(b) or isHealerHeader(b) then return end
    local o=OGRH_SV.order[role] or {}; local ia=o[a] or 9999; local ib=o[b] or 9999; o[a],o[b]=ib,ia; return
  end
  if role=="HEALERS" and Roles.healerHeaders and (not isHealerHeader(name)) then
    local list=sortedRoleList(role); local idx=0; for i=1,table.getn(list) do if list[i]==name then idx=i; break end end; if idx==0 then return end
    local tgt=idx+dir; if tgt<1 or tgt>table.getn(list) then return end
    if isHealerHeader(list[tgt]) then tgt=tgt+dir; if tgt<1 or tgt>table.getn(list) then return end
      local hdr; if dir>0 then hdr=list[idx+1] else hdr=list[tgt] end
      local headerIdx=1; if hdr==HEAL_HEADER_IDS[1] then headerIdx=1 elseif hdr==HEAL_HEADER_IDS[2] then headerIdx=2 elseif hdr==HEAL_HEADER_IDS[3] then headerIdx=3 elseif hdr==HEAL_HEADER_IDS[4] then headerIdx=4 end
      OGRH_SV.healerBoss[name]=headerIdx; if isHealerHeader(list[tgt]) then return end
    end
    local a=name; local b=list[tgt]; if isHealerHeader(b) or isTankHeader(b) then return end
    local o=OGRH_SV.order[role] or {}; local ia=o[a] or 9999; local ib=o[b] or 9999; o[a],o[b]=ib,ia; return
  end
  local list=sortedRoleList(role); local idx=0; for i=1,table.getn(list) do if list[i]==name then idx=i; break end end; if idx==0 then return end
  local tgt=idx+dir; if tgt<1 or tgt>table.getn(list) then return end
  local a=list[idx]; local b=list[tgt]; if isTankHeader(a) or isTankHeader(b) or isHealerHeader(a) or isHealerHeader(b) then return end
  local o=OGRH_SV.order[role] or {}; local ia=o[a] or 9999; local ib=o[b] or 9999; o[a],o[b]=ib,ia
end

------------------------------------------------------------
-- Control Window (vertical buttons)
------------------------------------------------------------
local Main = CreateFrame("Frame","OGRH_Main",UIParent)
Main:SetWidth(140); Main:SetHeight(84); Main:SetPoint("CENTER", UIParent, "CENTER", -380, 120)
Main:SetBackdrop({bgFile="Interface/Tooltips/UI-Tooltip-Background", edgeFile="Interface/Tooltips/UI-Tooltip-Border", edgeSize=12, insets={left=4,right=4,top=4,bottom=4}})
Main:SetBackdropColor(0,0,0,0.85); Main:EnableMouse(true); Main:SetMovable(true)
Main:RegisterForDrag("LeftButton")
Main:SetScript("OnDragStart", function() if not OGRH_SV.ui.locked then Main:StartMoving() end end)
Main:SetScript("OnDragStop", function() Main:StopMovingOrSizing(); if not OGRH_SV.ui then OGRH_SV.ui={} end; OGRH_SV.ui.point,_,OGRH_SV.ui.relPoint,OGRH_SV.ui.x,OGRH_SV.ui.y = Main:GetPoint() end)

local H = CreateFrame("Frame", nil, Main); H:SetPoint("TOPLEFT", Main, "TOPLEFT", 4, -4); H:SetPoint("TOPRIGHT", Main, "TOPRIGHT", -4, -4); H:SetHeight(20)
local title = H:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); title:SetPoint("LEFT", H, "LEFT", 4, 0); title:SetText("|cffffff00OGRH|r")
local btnMin = CreateFrame("Button", nil, H, "UIPanelButtonTemplate"); btnMin:SetWidth(20); btnMin:SetHeight(16); btnMin:SetText("-"); btnMin:SetPoint("RIGHT", H, "RIGHT", -46, 0)
local btnLock = CreateFrame("Button", nil, H, "UIPanelButtonTemplate"); btnLock:SetWidth(28); btnLock:SetHeight(16); btnLock:SetText("Lock"); btnLock:SetPoint("RIGHT", H, "RIGHT", -4, 0)

local Content = CreateFrame("Frame", nil, Main); Content:SetPoint("TOPLEFT", Main, "TOPLEFT", 6, -26); Content:SetPoint("BOTTOMRIGHT", Main, "BOTTOMRIGHT", -6, 6)

local function makeBtn(text, anchorTo) local b=CreateFrame("Button", nil, Content, "UIPanelButtonTemplate"); b:SetWidth(110); b:SetHeight(20); b:SetText(text); if not anchorTo then b:SetPoint("TOP", Content, "TOP", 0, 0) else b:SetPoint("TOP", anchorTo, "BOTTOM", 0, -6) end; return b end
local bHelper = makeBtn("Helper", nil)
local bTrade  = makeBtn("Trade", bHelper)

bHelper:SetScript("OnClick", function() OGRH_ShowBoard() end)

bTrade:RegisterForClicks("LeftButtonUp","RightButtonUp")
bTrade:SetScript("OnClick", function()
  local btn = arg1 or "LeftButton"
  if btn == "LeftButton" then
    runSand()
  else
    if not OGRH_TradeMenu then
      local M = CreateFrame("Frame","OGRH_TradeMenu",UIParent)
      M:SetBackdrop({bgFile="Interface/Tooltips/UI-Tooltip-Background", edgeFile="Interface/Tooltips/UI-Tooltip-Border", edgeSize=12, insets={left=4,right=4,top=4,bottom=4}})
      M:SetBackdropColor(0,0,0,0.95); M:SetWidth(120); M:SetHeight(1); M:Hide()
      M.items = { "Sand", "Runes", "GFPP", "GAPP", "GSPP", "Invis" }
      M.btns = {}
      for i=1,6 do
        local it = CreateFrame("Button", nil, M, "UIPanelButtonTemplate")
        it:SetWidth(100); it:SetHeight(18)
        if i==1 then it:SetPoint("TOPLEFT", M, "TOPLEFT", 10, -10) else it:SetPoint("TOPLEFT", M.btns[i-1], "BOTTOMLEFT", 0, -6) end
        local fs = it:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); fs:SetAllPoints(); fs:SetJustifyH("CENTER"); it.fs=fs
        local label = M.items[i]
        if i==1 then fs:SetText(label) else fs:SetText("|cff888888"..label.."|r") end
        it:SetScript("OnClick", function() if i==1 then runSand() end; M:Hide() end)
        M.btns[i]=it
      end
      M:SetHeight(10 + 6*18 + 5*6 + 10)
    end
    local M = OGRH_TradeMenu
    M:ClearAllPoints(); M:SetPoint("TOPLEFT", bTrade, "BOTTOMLEFT", 0, -2); M:Show()
  end
end)

local function applyMinimized(mini) if mini then Content:Hide(); Main:SetHeight(28); btnMin:SetText("+") else Content:Show(); Main:SetHeight(84); btnMin:SetText("-") end end
btnMin:SetScript("OnClick", function() ensureSV(); OGRH_SV.ui.minimized = not OGRH_SV.ui.minimized; applyMinimized(OGRH_SV.ui.minimized) end)
local function applyLocked(lock) btnLock:SetText("Lock") end
btnLock:SetScript("OnClick", function() ensureSV(); OGRH_SV.ui.locked = not OGRH_SV.ui.locked; applyLocked(OGRH_SV.ui.locked) end)

local function restoreMain() ensureSV(); local ui=OGRH_SV.ui or {}; if ui.point and ui.x and ui.y then Main:ClearAllPoints(); Main:SetPoint(ui.point, UIParent, ui.relPoint or ui.point, ui.x, ui.y) end; applyMinimized(ui.minimized); applyLocked(ui.locked) end
local _mainLoader = CreateFrame("Frame","OGRH_MainLoader"); _mainLoader:RegisterEvent("VARIABLES_LOADED"); _mainLoader:SetScript("OnEvent", function() restoreMain() end)

------------------------------------------------------------
-- Roles Board (columns)
------------------------------------------------------------
local Drag = { name=nil, fromRole=nil }
local Board = CreateFrame("Frame","OGRH_Board",UIParent); Board:SetWidth(640); Board:SetHeight(520)
Board:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
Board:SetBackdrop({bgFile="Interface/Tooltips/UI-Tooltip-Background", edgeFile="Interface/Tooltips/UI-Tooltip-Border", edgeSize=12, insets={left=4,right=4,top=4,bottom=4}})
Board:SetBackdropColor(0,0,0,0.85); Board:Hide(); Board:EnableMouse(true); Board:SetMovable(true)
Board:RegisterForDrag("LeftButton"); Board:SetScript("OnDragStart", function() Board:StartMoving() end)
Board:SetScript("OnDragStop", function() Board:StopMovingOrSizing() end)

local btnClose = CreateFrame("Button", nil, Board, "UIPanelButtonTemplate"); btnClose:SetWidth(60); btnClose:SetHeight(20); btnClose:SetText("Close"); btnClose:SetPoint("TOPRIGHT", Board, "TOPRIGHT", -8, -6); btnClose:SetScript("OnClick", function() Board:Hide() end)

local btnPoll = CreateFrame("Button", nil, Board, "UIPanelButtonTemplate"); btnPoll:SetWidth(60); btnPoll:SetHeight(20); btnPoll:SetText("Poll"); btnPoll:SetPoint("TOPLEFT", Board, "TOPLEFT", 8, -6)
local btnHealing = CreateFrame("Button", nil, Board, "UIPanelButtonTemplate"); btnHealing:SetWidth(60); btnHealing:SetHeight(20); btnHealing:SetText("Healing"); btnHealing:SetPoint("LEFT", btnPoll, "RIGHT", 6, 0)
local btnCTHUN = CreateFrame("Button", nil, Board, "UIPanelButtonTemplate"); btnCTHUN:SetWidth(60); btnCTHUN:SetHeight(20); btnCTHUN:SetText("C'Thun"); btnCTHUN:SetPoint("LEFT", btnHealing, "RIGHT", 6, 0)
local btn4HM  = CreateFrame("Button", nil, Board, "UIPanelButtonTemplate"); btn4HM:SetWidth(60); btn4HM:SetHeight(20); btn4HM:SetText("4HM");  btn4HM:SetPoint("LEFT", btnCTHUN, "RIGHT", 6, 0)

local pollLbl = Board:CreateFontString(nil,"OVERLAY","GameFontNormalSmall"); pollLbl:SetText("Poll Time:"); pollLbl:SetTextColor(1,1,0)
local pollBox = CreateFrame("EditBox", "OGRH_PollTime", Board, "InputBoxTemplate")
pollBox:SetWidth(24); pollBox:SetHeight(18); pollBox:SetAutoFocus(false); pollBox:SetMaxLetters(2); if pollBox.SetNumeric then pollBox:SetNumeric(true) end
pollBox:SetText(tostring(tonumber(OGRH_SV.pollTime) or 5))
pollBox:SetScript("OnEnterPressed", function() local txt=pollBox:GetText() or ""; if txt=="" then txt=tostring(OGRH_SV.pollTime or 5) end; OGRH_SV.pollTime=tonumber(txt) or 5; Roles.silenceGate=OGRH_SV.pollTime; pollBox:ClearFocus() end)
pollBox:SetScript("OnEscapePressed", function() pollBox:ClearFocus(); pollBox:SetText(tostring(tonumber(OGRH_SV.pollTime) or 5)) end)
pollLbl:ClearAllPoints(); pollLbl:SetPoint("RIGHT", btnClose, "LEFT", -120, 0); pollLbl:Show()
pollBox:ClearAllPoints(); pollBox:SetPoint("LEFT", pollLbl, "RIGHT", 4, 0)

local btnTest = CreateFrame("Button", nil, Board, "UIPanelButtonTemplate"); btnTest:SetWidth(64); btnTest:SetHeight(20); btnTest:SetText("Test SV")
btnTest:SetPoint("LEFT",  pollBox,  "RIGHT",  6,  0)
function OGRH_LoadSavedAsRaid(enable)
  ensureSV()
  if enable then
    Roles.testing=true; Roles.raidNames={}; Roles.nameClass={}; Roles.raidParty={}
    for k,_ in pairs(Roles.buckets) do Roles.buckets[k]={} end
    local i=0; for name,role in pairs(OGRH_SV.roles or {}) do i=i+1; if i>40 then break end; Roles.raidNames[name]=true; Roles.raidParty[name]=mod1(i,8); if Roles.buckets[role] then Roles.buckets[role][name]=true end end
    msg("Test SV: loaded "..tostring(i).." saved names.")
  else
    Roles.testing=false; refreshRoster(); pruneBucketsToRaid(); OGRH_Preassign(false); msg("Test SV: disabled.")
  end
  OGRH_Board_Refresh()
end
btnTest:SetScript("OnClick", function() if Roles.testing then OGRH_LoadSavedAsRaid(false); Roles.testing=false; msg("Test SV: OFF") else OGRH_LoadSavedAsRaid(true); Roles.testing=true; msg("Test SV: ON") end end)

-- (Columns, Unknown area, Poll flow, C'Thun, 4HM, Healing) — reuse the same implementations from prior section.


-- === Columns and Unknown area from earlier build ===
local PAD_L, PAD_R, PAD_T = 12, 12, 36
local BOARD_W = 640
local COL_W = 140
local free = BOARD_W - PAD_L - PAD_R - 4*COL_W
local GUTTER = math.floor((free/3)+0.5); if GUTTER<10 then GUTTER=10 end
local ROW_H = 18
local VISIBLE_ROWS = 16
local COL_H = (VISIBLE_ROWS*ROW_H) + 36
local Columns = {}
local function columnX(i) return PAD_L + (i-1)*(COL_W + GUTTER) end
local function textureButton(b, upTex, downTex, hiTex)
  local n=b:CreateTexture(nil,"ARTWORK"); n:SetTexture(upTex); n:SetAllPoints(); n:SetTexCoord(0.15,0.85,0.15,0.85); b:SetNormalTexture(n)
  local d=b:CreateTexture(nil,"ARTWORK"); d:SetTexture(downTex); d:SetAllPoints(); d:SetTexCoord(0.15,0.85,0.15,0.85); b:SetPushedTexture(d)
  local h=b:CreateTexture(nil,"HIGHLIGHT"); h:SetTexture(hiTex); h:SetAllPoints(); h:SetTexCoord(0.15,0.85,0.15,0.85); b:SetHighlightTexture(h)
end

local function createColumn(idx, label)
  local col = CreateFrame("Frame","OGRH_Col_"..label,Board); col:SetWidth(COL_W); col:SetHeight(COL_H)
  col:SetBackdrop({bgFile="Interface/Tooltips/UI-Tooltip-Background", edgeFile="Interface/Tooltips/UI-Tooltip-Border", edgeSize=10, insets={left=2,right=2,top=2,bottom=2}})
  col:SetBackdropColor(0.1,0.1,0.1,0.9); col:SetPoint("TOPLEFT", Board, "TOPLEFT", columnX(idx), -PAD_T)

  local hdr = CreateFrame("Button", nil, col, "UIPanelButtonTemplate"); hdr:SetWidth(COL_W-10); hdr:SetHeight(18); hdr:SetText(label); hdr:SetPoint("TOP", col, "TOP", 0, -4)
  hdr:SetScript("OnClick", function() if Drag.name then addTo(label, Drag.name); Drag.name=nil; Drag.fromRole=nil; OGRH_Board_Refresh() end end)

  local anchor = CreateFrame("Frame", nil, col); anchor:SetPoint("TOPLEFT", col, "TOPLEFT", 6, -28); anchor:SetWidth(COL_W-26); anchor:SetHeight(VISIBLE_ROWS*ROW_H); col.anchor=anchor
  local sf = CreateFrame("ScrollFrame","OGRH_SF_"..label,col,"FauxScrollFrameTemplate"); sf:SetPoint("TOPRIGHT", col, "TOPRIGHT", -6, -26); sf:SetWidth(16); sf:SetHeight(VISIBLE_ROWS*ROW_H+2); col.scroll=sf
  local sb=getglobal(sf:GetName().."ScrollBar"); if sb then sb:ClearAllPoints(); sb:SetPoint("TOPRIGHT", col, "TOPRIGHT", -6, -26); sb:SetPoint("BOTTOMRIGHT", col, "BOTTOMRIGHT", -6, 10); sb:SetWidth(16) end

  col.rows={}
  for i=1,VISIBLE_ROWS do
    local row=CreateFrame("Frame", nil, anchor); row:SetWidth(anchor:GetWidth()); row:SetHeight(ROW_H); row:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, -((i-1)*ROW_H)); row.name=nil
    row.btnUp=CreateFrame("Button", nil, row); row.btnUp:SetWidth(18); row.btnUp:SetHeight(18); row.btnUp:ClearAllPoints(); row.btnUp:SetPoint("LEFT", row, "LEFT", 0, -1)
    textureButton(row.btnUp,"Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Up","Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Down","Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Highlight")
    row.btnUp:SetScript("OnClick", function() if row.name and (not isTankHeader(row.name)) and (not isHealerHeader(row.name)) then moveInRole(label, row.name, -1); OGRH_Board_Refresh() end end)

    row.btnDown=CreateFrame("Button", nil, row); row.btnDown:SetWidth(18); row.btnDown:SetHeight(18); row.btnDown:ClearAllPoints(); row.btnDown:SetPoint("LEFT", row.btnUp, "RIGHT", 1, -1)
    textureButton(row.btnDown,"Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up","Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Down","Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Highlight")
    row.btnDown:SetScript("OnClick", function() if row.name and (not isTankHeader(row.name)) and (not isHealerHeader(row.name)) then moveInRole(label, row.name, 1); OGRH_Board_Refresh() end end)

    row.btnName=CreateFrame("Button", nil, row); row.btnName:ClearAllPoints(); row.btnName:SetPoint("LEFT", row.btnDown, "RIGHT", 5, 0); row.btnName:SetWidth(row:GetWidth()-54); row.btnName:SetHeight(ROW_H)
    local fs=row.btnName:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); fs:SetAllPoints(); fs:SetJustifyH("LEFT"); row.btnName.fs=fs
    row.btnName:EnableMouse(true); row.btnName:SetScript("OnClick", function() if row.name and (not isTankHeader(row.name)) and (not isHealerHeader(row.name)) then Drag.name=row.name; Drag.fromRole=label; msg("Selected "..row.name..". Click a column header to move.") end end)

    col.rows[i]=row
  end

  col.update=function()
    ensureSV()
    local arr=sortedRoleList(label); col.list=arr
    local total=table.getn(arr); FauxScrollFrame_Update(sf,total,VISIBLE_ROWS,ROW_H); local offset=FauxScrollFrame_GetOffset(sf) or 0
    if sb then if total<=VISIBLE_ROWS then sb:Hide() else sb:Show() end end
    for i=1,VISIBLE_ROWS do
      local idx=i+offset; local row=col.rows[i]
      if idx<=total then
        local name=arr[idx]; row.name=name
        if isTankHeader(name) or isHealerHeader(name) then
          row.btnUp:Hide(); row.btnDown:Hide()
          local hdr = TANK_HEADER_LABEL[name] or HEAL_HEADER_LABEL[name] or name
          row.btnName.fs:SetText("|cffffd100"..hdr.."|r")
          row.btnName:Disable(); row.btnName:EnableMouse(false)
          row.btnName:ClearAllPoints(); row.btnName:SetPoint("LEFT", row, "LEFT", 2, 0)
          row:Show()
        else
          row.btnUp:Show(); row.btnDown:Show()
          local prefix=""
          if label=="HEALERS" and Roles.healerHeaders then local rk=Roles.healRank[name] or 0; if rk>0 then prefix="["..rk.."] " end end
          row.btnName.fs:SetText(prefix..colorName(name))
          row.btnName:EnableMouse(true)
          row.btnName:ClearAllPoints(); row.btnName:SetPoint("LEFT", row.btnDown, "RIGHT", 5, 0)
          row:Show()
        end
      else
        row.name=nil; row.btnName.fs:SetText(""); row:Hide()
      end
    end
  end
  sf:SetScript("OnVerticalScroll", function() FauxScrollFrame_OnVerticalScroll(ROW_H, col.update) end)

  Columns[label]=col
end

createColumn(1,"TANKS"); createColumn(2,"HEALERS"); createColumn(3,"MELEE"); createColumn(4,"RANGED")

-- Unknown area & refresh helpers
local Unknown=CreateFrame("Frame","OGRH_Unknown",Board)
Unknown:SetPoint("TOPLEFT", Board, "TOPLEFT", 12, -(36 + COL_H + 10)); Unknown:SetPoint("TOPRIGHT", Board, "TOPRIGHT", -12, -(36 + COL_H + 10))
Unknown:SetHeight(56)
Unknown:SetBackdrop({bgFile="Interface/Tooltips/UI-Tooltip-Background", edgeFile="Interface/Tooltips/UI-Tooltip-Border", edgeSize=10, insets={left=2,right=2,top=2,bottom=2}})
Unknown:SetBackdropColor(0.08,0.08,0.08,0.9)
local UnknownLabel=Unknown:CreateFontString(nil,"OVERLAY","GameFontNormalSmall"); UnknownLabel:SetPoint("TOPLEFT", Unknown, "TOPLEFT", 6, -4); UnknownLabel:SetText("Unassigned:")
local U_SF=CreateFrame("ScrollFrame","OGRH_UnknownScroll",Unknown,"UIPanelScrollFrameTemplate")
U_SF:SetPoint("TOPLEFT", Unknown, "TOPLEFT", 6, -18); U_SF:SetPoint("BOTTOMRIGHT", Unknown, "BOTTOMRIGHT", -6, 6)
local U_Content=CreateFrame("Frame",nil,U_SF); U_Content:SetWidth(1); U_Content:SetHeight(1); U_SF:SetScrollChild(U_Content)
local usb=getglobal(U_SF:GetName().."ScrollBar"); if usb then usb:ClearAllPoints(); usb:SetPoint("TOPRIGHT", Unknown, "TOPRIGHT", -6, -18); usb:SetPoint("BOTTOMRIGHT", Unknown, "BOTTOMRIGHT", -6, 6); usb:SetWidth(16) end
Unknown.btns={}
local function Unknown_GetButton(i) if Unknown.btns[i] then return Unknown.btns[i] end local b=CreateFrame("Button",nil,U_Content,"UIPanelButtonTemplate"); b:SetHeight(16); local fs=b:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); fs:SetAllPoints(); fs:SetJustifyH("LEFT"); b.text=fs; b:EnableMouse(true); b:SetScript("OnClick", function() Drag.name=b._name; Drag.fromRole=nil; msg("Selected "..tostring(b._name)..". Click a column header to assign.") end); Unknown.btns[i]=b; return b end
local function Unknown_ClearButtons() local n=table.getn(Unknown.btns) for i=1,n do Unknown.btns[i]:Hide() end end
local function OGRH_Unknown_Refresh()
  ensureSV(); Unknown_ClearButtons()
  local names={}; for nm,_ in pairs(Roles.raidNames) do if not inAnyBucket(nm) then table.insert(names,nm) end end; table.sort(names)
  local viewW=(Unknown:GetWidth() or 520) - 24; if viewW<120 then viewW=120 end
  local x,y,rowH=0,0,16; local lines=1; local count=table.getn(names)
  if count==0 then local b=Unknown_GetButton(1); b._name=nil; b.text:SetText("|cffaaaaaa(none)|r"); b:SetWidth(80); b:ClearAllPoints(); b:SetPoint("TOPLEFT", U_Content, "TOPLEFT", 4, -2); b:Show(); U_Content:SetWidth(viewW); U_Content:SetHeight(rowH+4); if usb then usb:Hide() end; return end
  for i=1,count do local n=names[i]; local b=Unknown_GetButton(i); b._name=n; local t=colorName(n); b.text:SetText(t); local w=b.text:GetStringWidth()+12; if w>viewW then w=viewW end; if x+w>viewW then x=0; y=y+rowH; lines=lines+1 end; b:SetWidth(w); b:ClearAllPoints(); b:SetPoint("TOPLEFT", U_Content, "TOPLEFT", x+4, -y-2); b:Show(); x=x+w+8 end
  local contentH=(lines*rowH)+4; U_Content:SetWidth(viewW); U_Content:SetHeight(contentH); if usb then if lines>2 then usb:Show() else usb:Hide() end end
end

-- Render helpers
function OGRH_Preassign(overwriteExisting)
  ensureSV(); refreshRoster(); pruneBucketsToRaid()
  for name,_ in pairs(Roles.raidNames) do
    local already=inAnyBucket(name)
    if overwriteExisting or not already then
      for k,_ in pairs(Roles.buckets) do Roles.buckets[k][name]=nil end
      local saved=OGRH_SV.roles[name]; local hinted; local class=Roles.nameClass[name]; if class and CLASS_HINT[class] then hinted=CLASS_HINT[class] end
      local pick=saved or hinted; if pick and Roles.buckets[pick] then Roles.buckets[pick][name]=true end
    end
  end
end
local function resizeBoardToFit() Board:SetHeight(8+20+(PAD_T-20)+COL_H+10+56+14) end
function OGRH_Board_Refresh() refreshRoster(); pruneBucketsToRaid(); Columns["TANKS"].update(); Columns["HEALERS"].update(); Columns["MELEE"].update(); Columns["RANGED"].update(); OGRH_Unknown_Refresh(); resizeBoardToFit() end
function OGRH_ShowBoard() Board:Show(); ensureSV(); Roles.silenceGate=tonumber(OGRH_SV.pollTime) or 5; OGRH_Preassign(false); OGRH_Board_Refresh() end

-- Poll loader
local _pollLoader = CreateFrame("Frame","OGRH_PollLoader"); _pollLoader:RegisterEvent("VARIABLES_LOADED")
_pollLoader:SetScript("OnEvent", function() ensureSV(); local v=tonumber(OGRH_SV.pollTime) or 5; Roles.silenceGate=v; if OGRH_PollTime and OGRH_PollTime.SetText then OGRH_PollTime:SetText(tostring(v)) end end)

-- Poll flow
local ROLES_ORDER = {"HEALERS","TANKS","RANGED","MELEE"}
local function startRolesFlow() Roles.active=true; Roles.phaseIndex=1; Roles.silence=0; Roles.lastPlus=GetTime() or 0; Roles.silenceGate=tonumber(OGRH_SV.pollTime) or 5; if Roles.silenceGate<=0 then Roles.silenceGate=5 end; Roles.nextAdvanceTime=(GetTime() or 0)+Roles.silenceGate; sayRW("HEALERS put + in raid chat."); F:Show() end
local function stopRolesFlow() Roles.active=false; Roles.phaseIndex=0; Roles.silence=0; if F.state=="IDLE" then F:Hide() end end
local E=CreateFrame("Frame","OGRH_RolesEvents"); E:RegisterEvent("CHAT_MSG_RAID"); E:RegisterEvent("CHAT_MSG_RAID_LEADER"); E:RegisterEvent("RAID_ROSTER_UPDATE")
E:SetScript("OnEvent", function() local ev=event; if ev=="RAID_ROSTER_UPDATE" then if Roles.testing then return end; refreshRoster(); pruneBucketsToRaid(); OGRH_Preassign(false); OGRH_Board_Refresh(); return end; if not Roles.active then return end; if ev=="CHAT_MSG_RAID" or ev=="CHAT_MSG_RAID_LEADER" then local text,sender=arg1,arg2; if not text or not sender then return end; if string.find(text, "%+") then local pname=string.match(sender,"^[^-]+") or sender; if not Roles.testing and not Roles.raidNames[pname] then return end; local phase=ROLES_ORDER[Roles.phaseIndex]; if phase=="HEALERS" then addTo("HEALERS",pname) elseif phase=="TANKS" then addTo("TANKS",pname) elseif phase=="RANGED" then addTo("RANGED",pname) elseif phase=="MELEE" then addTo("MELEE",pname) end; Roles.silence=0; Roles.lastPlus=GetTime() or Roles.lastPlus; Roles.nextAdvanceTime=(GetTime() or 0)+(Roles.silenceGate or 5); OGRH_Board_Refresh() end end end)
local function rolesTick(elapsed) if not Roles.active then return end; local now=GetTime() or 0; if not Roles.nextAdvanceTime then Roles.nextAdvanceTime=now+(Roles.silenceGate or 5) end; if now >= Roles.nextAdvanceTime then Roles.silence=0; Roles.lastPlus=now; Roles.phaseIndex=Roles.phaseIndex+1; Roles.nextAdvanceTime=now+(Roles.silenceGate or 5); local nxt=ROLES_ORDER[Roles.phaseIndex]; if nxt=="HEALERS" then sayRW("HEALERS put + in raid chat.") elseif nxt=="TANKS" then sayRW("TANKS put + in raid chat.") elseif nxt=="RANGED" then sayRW("RANGED put + in raid chat.") elseif nxt=="MELEE" then sayRW("MELEE put + in raid chat.") else stopRolesFlow(); msg("Roles collection complete.") end end end
btnPoll:SetScript("OnClick", function() startRolesFlow(); msg("Polling roles for "..tostring(Roles.silenceGate).."s per phase.") end)

-- Ranged interleave helper
local function collectRangedInterleavedByParty() local parties={}; for p=1,8 do parties[p]={druids={},others={}} end; for n,_ in pairs(Roles.buckets["RANGED"]) do if Roles.testing or Roles.raidNames[n] then local pg=Roles.raidParty[n] or 1; local c=Roles.nameClass[n]; if c=="DRUID" then table.insert(parties[pg].druids,n) else table.insert(parties[pg].others,n) end end end; for p=1,8 do table.sort(parties[p].druids); table.sort(parties[p].others) end; local out={}; for p=1,8 do local d,o=parties[p].druids, parties[p].others; local di,oi,dn,on=1,1,table.getn(d),table.getn(o); while (oi<=on) or (di<=dn) do if oi<=on then table.insert(out,o[oi]); oi=oi+1 end; if di<=dn then table.insert(out,d[di]); di=di+1 end end end; return out end

-- C'Thun assignments
local function assignCthunZones()
  refreshRoster(); pruneBucketsToRaid()
  local zones={}; for i=1,8 do zones[i]={} end
  local tanks=sortedRoleNamesRaw("TANKS"); local melee=sortedRoleNamesRaw("MELEE"); local healers=sortedRoleNamesRaw("HEALERS"); local ranged=collectRangedInterleavedByParty()
  local spread8={1,2,4,6,8,7,5,3}
  local tcount=table.getn(tanks); if tcount>=1 then table.insert(zones[1], tanks[1]) end; if tcount>=2 then table.insert(zones[8], tanks[2]) end
  local mergedMelee={}; for i=3,tcount do table.insert(mergedMelee,tanks[i]) end; for i=1,table.getn(melee) do table.insert(mergedMelee,melee[i]) end
  local mm=table.getn(mergedMelee); local mi=1; for i=1,mm do local z=spread8[mod1(mi,8)]; table.insert(zones[z], mergedMelee[i]); mi=mi+1 end
  local function spread(list) local n=table.getn(list); local k=1; for i=1,n do local z=spread8[mod1(k,8)]; table.insert(zones[z], list[i]); k=k+1 end end
  spread(healers); spread(ranged)
  for i=1,8 do local names=zones[i]; if table.getn(names)>0 then local col={} ; for j=1,table.getn(names) do col[j]=colorName(names[j]) end ; sayRW("|cff00ff00[Zone "..i.."]|r: "..table.concat(col, " || ")) end end
end
btnCTHUN:SetScript("OnClick", function() assignCthunZones(); msg("C'Thun zone assignments sent.") end)

-- 4HM
local function assign4HM()
  ensureSV(); refreshRoster(); pruneBucketsToRaid()
  local heals = sortedRoleNamesRaw("HEALERS")
  local perBossTanks = { {}, {}, {}, {} } -- Thane, Mograine, Lady, Zeliek
  if Roles.tankHeaders then
    local tlist = sortedRoleList("TANKS"); local currentHeader=nil
    for i=1,table.getn(tlist) do local name=tlist[i]
      if name=="__HDR_THANE__" then currentHeader=1 elseif name=="__HDR_LADY__" then currentHeader=3 elseif name=="__HDR_ZELIEK__" then currentHeader=4 elseif name=="__HDR_MOGRAINE__" then currentHeader=2
      else if currentHeader and name and name~="" then table.insert(perBossTanks[currentHeader], name) end end
    end
  else
    local tanks = sortedRoleNamesRaw("TANKS")
    if tanks[1] then table.insert(perBossTanks[1], tanks[1]) end
    if tanks[2] then table.insert(perBossTanks[2], tanks[2]) end
    if tanks[3] then table.insert(perBossTanks[2], tanks[3]) end
    if tanks[4] then table.insert(perBossTanks[3], tanks[4]) end
    if tanks[5] then table.insert(perBossTanks[3], tanks[5]) end
    if tanks[6] then table.insert(perBossTanks[4], tanks[6]) end
    if tanks[7] then table.insert(perBossTanks[4], tanks[7]) end
  end
  local perBossHeals = { {}, {}, {}, {} }
  if Roles.healerHeaders then
    local order = OGRH_SV.order["HEALERS"] or {}
    table.sort(heals, function(a,b) local ia=order[a] or 9999; local ib=order[b] or 9999; if ia~=ib then return ia<ib else return a<b end end)
    for i=1,table.getn(heals) do local nm=heals[i]; local g=OGRH_SV.healerBoss[nm] or 1; if g<1 then g=1 elseif g>4 then g=4 end; if nm and nm~="" then table.insert(perBossHeals[g], nm) end end
  else
    for i=1,table.getn(heals) do local g=math.mod(i-1,4)+1; local nm=heals[i]; if nm and nm~="" then table.insert(perBossHeals[g], nm) end end
  end
  local bosses={"Thane","Mograine","Lady","Zeliek"}
  for b=1,4 do
    local tnames=perBossTanks[b]; local colT={}; for ti=1,table.getn(tnames) do colT[ti]=colorName(tnames[ti]) end
    local hnames={}; local hlist=perBossHeals[b]; for k=1,3 do if hlist and hlist[k] then table.insert(hnames, colorName(hlist[k]).." ["..k.."]") end end
    if tnames and table.getn(tnames)>0 then sayRW("|cff00ff00["..bosses[b].."]|r |cffffff00Tanks:|r "..table.concat(colT, " || ")) end
    if table.getn(hnames)>0 then sayRW("|cffffff00Healers:|r "..table.concat(hnames, " || ")) end
  end
end
btn4HM:RegisterForClicks("LeftButtonUp","RightButtonUp")
btn4HM:SetScript("OnClick", function() local btn=arg1 or "LeftButton"; if btn=="LeftButton" then if not Roles.tankHeaders then Roles.tankHeaders=true; Roles.healerHeaders=true; OGRH_DefaultTankCategories(); OGRH_DefaultHealerBoss(); OGRH_Board_Refresh(); msg("Headers enabled for 4HM. Click 4HM again to announce."); return end; assign4HM(); msg("4HM assignments sent.") else Roles.tankHeaders=not Roles.tankHeaders; Roles.healerHeaders=Roles.tankHeaders; if Roles.tankHeaders then OGRH_DefaultTankCategories(); OGRH_DefaultHealerBoss() end; OGRH_Board_Refresh(); msg("Headers "..(Roles.tankHeaders and "enabled" or "disabled")..". Right-click 4HM toggles.") end end)

-- Defaults
function OGRH_DefaultTankCategories() ensureSV(); local tanks={}; for n,_ in pairs(Roles.buckets["TANKS"]) do if Roles.testing or Roles.raidNames[n] then table.insert(tanks,n) end end; table.sort(tanks, function(a,b) local o=OGRH_SV.order["TANKS"] or {}; local ia=o[a] or 9999; local ib=o[b] or 9999; if ia~=ib then return ia<ib else return a<b end end); for i=1,table.getn(tanks) do local name=tanks[i]; if not OGRH_SV.tankCategory[name] then local cat=4; if i==1 then cat=1 elseif i==2 or i==3 then cat=4 elseif i==4 or i==5 then cat=2 elseif i==6 or i==7 then cat=3 end; OGRH_SV.tankCategory[name]=cat end end end
function OGRH_DefaultHealerBoss() ensureSV(); local heals={}; for n,_ in pairs(Roles.buckets["HEALERS"]) do if Roles.testing or Roles.raidNames[n] then table.insert(heals,n) end end; table.sort(heals, function(a,b) local o=OGRH_SV.order["HEALERS"] or {}; local ia=o[a] or 9999; local ib=o[b] or 9999; if ia~=ib then return ia<ib else return a<b end end); for i=1,table.getn(heals) do local nm=heals[i]; if not OGRH_SV.healerBoss[nm] then OGRH_SV.healerBoss[nm]=mod1(i,4) end end end

-- Healing pairs (general)
local function assignHealingPairs() ensureSV(); refreshRoster(); pruneBucketsToRaid(); local tanks=sortedRoleNamesRaw("TANKS"); local heals=sortedRoleNamesRaw("HEALERS"); local nt=table.getn(tanks); local nh=table.getn(heals); local n=nt; if nh<n then n=nh end; if n==0 then return end; sayRW("|cff00ff00Heal Assignments:|r"); for i=1,n do local t=tanks[i]; local h=heals[i]; if t and h then sayRW(colorName(h).." |cffffff00heals|r "..colorName(t)) end end end
btnHealing:SetScript("OnClick", function() assignHealingPairs() end)

-- OnUpdate timers
local rolesElapsed=0
F:SetScript("OnUpdate", function() local elapsed=arg1 or 0; rolesElapsed=rolesElapsed+elapsed; if rolesElapsed>0.10 then rolesTick(rolesElapsed); rolesElapsed=0 end; F.tick=F.tick+elapsed; if F.tick<F.interval then return end; F.tick=0; if F.state=="SAND" then if not TradeFrame or not TradeFrame:IsShown() then msg("Open the trade window first."); return resetSand() end; local b5,s5=findStackExact(ITEM_SAND,SAND_COUNT); if b5 and s5 then if not F.placed then local tslot=firstOpenTradeSlot(); if not tslot then msg("No open trade slot."); return resetSand() end; if CursorHasItem() then ClearCursor() end; PickupContainerItem(b5,s5); if not CursorHasItem() then return end; local btn=tradeItemButton(tslot); if not btn or not btn:IsVisible() then msg("Trade slot not usable."); return resetSand() end; btn:Click(); if CursorHasItem() then PickupContainerItem(b5,s5); return end; F.placed=true; F.acceptTries=0; msg("Placed 5x "..ITEM_SAND.." into trade."); return else if not CursorHasItem() then AcceptTrade(); F.acceptTries=F.acceptTries+1; if F.acceptTries>=F.maxAcceptTries then return resetSand() end end; return end end; if not F.didSplit then local sb,ss=findSourceStack(ITEM_SAND,SAND_COUNT); if not sb then msg("No stack of "..ITEM_SAND.." >= "..SAND_COUNT.."."); return resetSand() end; local db,ds=findEmptySlot(); if not db then msg("No empty bag slot."); return resetSand() end; if CursorHasItem() then ClearCursor() end; SplitContainerItem(sb,ss,SAND_COUNT); if CursorHasItem() then PickupContainerItem(db,ds); F.dBag,F.dSlot=db,ds; F.didSplit=true; msg("Split 5x "..ITEM_SAND..".") end; return else if F.dBag and F.dSlot then local _,_,locked=GetContainerItemInfo(F.dBag,F.dSlot); if locked then return end end; return end end end)

-- Slash
SlashCmdList[string.upper(CMD)] = function(m) local sub=string.lower(trim(m or "")); if sub=="sand" then runSand() elseif sub=="roles" then OGRH_ShowBoard(); msg("Roles board opened. Use arrows to re-order. 'Poll' to collect. C'Thun / 4HM for assignments. Right-click 4HM to toggle headers.") else msg("Usage: /"..CMD.." sand | /"..CMD.." roles") end end
_G["SLASH_"..string.upper(CMD).."1"] = "/"..CMD

msg(ADDON.." v1.12.1 loaded. Use /"..CMD.." roles (GUI) or the OGRH control window.")
