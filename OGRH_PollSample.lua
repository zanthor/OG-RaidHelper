-- OGRH_Poll.lua
local ROLES_ORDER = {"HEALERS","TANKS","RANGED","MELEE"}

local function startRolesFlow()
  OGRH.Roles.active=true; OGRH.Roles.phaseIndex=1; OGRH.Roles.silence=0
  OGRH.Roles.lastPlus=GetTime() or 0; OGRH.Roles.silenceGate=tonumber(OGRH_SV.pollTime) or 5
  if OGRH.Roles.silenceGate<=0 then OGRH.Roles.silenceGate=5 end
  OGRH.Roles.nextAdvanceTime=(GetTime() or 0)+OGRH.Roles.silenceGate
  sayRW("HEALERS put + in raid chat.")
  if not OGRH._TickFrame then OGRH._TickFrame=CreateFrame("Frame") end
  OGRH._TickFrame:SetScript("OnUpdate", function() OGRH.Poll_Tick(arg1 or 0) end)
end
local function stopRolesFlow() OGRH.Roles.active=false; OGRH.Roles.phaseIndex=0; if OGRH._TickFrame then OGRH._TickFrame:SetScript("OnUpdate", nil) end end
if OGRH.pollBox then
  OGRH.pollBox:SetText(tostring(tonumber(OGRH_SV.pollTime) or 5))
  OGRH.pollBox:SetScript("OnEnterPressed", function() local txt=OGRH.pollBox:GetText() or ""; if txt=="" then txt=tostring(OGRH_SV.pollTime or 5) end; OGRH_SV.pollTime=tonumber(txt) or 5; OGRH.Roles.silenceGate=OGRH_SV.pollTime; OGRH.pollBox:ClearFocus() end)
  OGRH.pollBox:SetScript("OnEscapePressed", function() OGRH.pollBox:ClearFocus(); OGRH.pollBox:SetText(tostring(tonumber(OGRH_SV.pollTime) or 5)) end)
end

local E=CreateFrame("Frame","OGRH_PollEvents")
E:RegisterEvent("CHAT_MSG_RAID"); E:RegisterEvent("CHAT_MSG_RAID_LEADER"); E:RegisterEvent("RAID_ROSTER_UPDATE")
E:SetScript("OnEvent", function()
  local ev=event
  if ev=="RAID_ROSTER_UPDATE" then if OGRH.Roles.testing then return end; OGRH.RefreshRoster(); OGRH.PruneBucketsToRaid(); OGRH.Board_Refresh(); return end
  if not OGRH.Roles.active then return end
  if ev=="CHAT_MSG_RAID" or ev=="CHAT_MSG_RAID_LEADER" then
    local text,sender=arg1,arg2; if not text or not sender then return end
    if string.find(text, "%+") then
      local pname=string.match(sender,"^[^-]+") or sender
      if not OGRH.Roles.testing and not OGRH.Roles.raidNames[pname] then return end
      local pick = ROLES_ORDER[OGRH.Roles.phaseIndex] or "HEALERS"
      OGRH.AddTo(pick, pname); OGRH.Board_Refresh()
      OGRH.Roles.lastPlus=GetTime() or 0; OGRH.Roles.nextAdvanceTime=(GetTime() or 0)+(OGRH.Roles.silenceGate or 5)
    end
  end
end)

function OGRH.Poll_Tick(elapsed)
  if not OGRH.Roles.active then return end
  local now=GetTime() or 0
  if not OGRH.Roles.nextAdvanceTime then OGRH.Roles.nextAdvanceTime=now+(OGRH.Roles.silenceGate or 5) end
  if now >= OGRH.Roles.nextAdvanceTime then
    OGRH.Roles.silence=0; OGRH.Roles.lastPlus=now; OGRH.Roles.phaseIndex=OGRH.Roles.phaseIndex+1
    OGRH.Roles.nextAdvanceTime=now+(OGRH.Roles.silenceGate or 5)
    local nxt=ROLES_ORDER[OGRH.Roles.phaseIndex]
    if nxt=="HEALERS" then sayRW("HEALERS put + in raid chat.")
    elseif nxt=="TANKS" then sayRW("TANKS put + in raid chat.")
    elseif nxt=="RANGED" then sayRW("RANGED put + in raid chat.")
    elseif nxt=="MELEE" then sayRW("MELEE put + in raid chat.")
    else OGRH.Roles.active=false; if OGRH._TickFrame then OGRH._TickFrame:SetScript("OnUpdate", nil) end; return end
  end
end

if OGRH.btnPoll then OGRH.btnPoll:SetScript("OnClick", function() startRolesFlow(); OGRH.Msg("Polling roles for "..tostring(OGRH.Roles.silenceGate).."s per phase.") end) end

if OGRH.btnTest then
  function OGRH_LoadSavedAsRaid(enable)
    ensureSV()
    if enable then
      OGRH.Roles.testing=true; OGRH.Roles.raidNames={}; OGRH.Roles.nameClass={}; OGRH.Roles.raidParty={}
      local k,_; local i=0
      for k,_ in pairs(OGRH_SV.roles or {}) do local name=k; local role=OGRH_SV.roles[k]; i=i+1; if i>40 then break end; OGRH.Roles.raidNames[name]=true; OGRH.Roles.raidParty[name]=OGRH.Mod1(i,8); if OGRH.Roles.buckets[role] then OGRH.Roles.buckets[role][name]=true end end
      OGRH.Msg("Test SV: loaded "..tostring(i).." saved names.")
    else
      OGRH.Roles.testing=false; OGRH.RefreshRoster(); OGRH.PruneBucketsToRaid(); OGRH.Board_Refresh(); OGRH.Msg("Test SV: disabled.")
    end
    OGRH.Board_Refresh()
  end
  OGRH.btnTest:SetScript("OnClick", function() if OGRH.Roles.testing then OGRH_LoadSavedAsRaid(false); OGRH.Roles.testing=false; OGRH.Msg("Test SV: OFF") else OGRH_LoadSavedAsRaid(true); OGRH.Roles.testing=true; OGRH.Msg("Test SV: ON") end end)
end
