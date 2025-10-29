-- OGRH_Trade.lua
local ITEM_SAND, SAND_COUNT = 19183, 5
local F = CreateFrame("Frame","OGRH_TradeFrame")
F:Hide(); F.tick, F.interval = 0, 0.10; F.state, F.didSplit, F.placed, F.acceptTries, F.maxAcceptTries = "IDLE", false, false, 0, 20
F.dBag, F.dSlot = nil, nil

local function itemIdFromLink(link) if not link then return nil end local id=string.match(link,"Hitem:(%d+):"); return id and tonumber(id) or nil end
local function findStackExact(id, need) local b; for b=0,4 do local n=GetContainerNumSlots(b) or 0; local s; for s=1,n do local l=GetContainerItemLink(b,s) if l and itemIdFromLink(l)==id then local _,c,lck=GetContainerItemInfo(b,s) if (c or 0)==need and not lck then return b,s end end end end end
local function findSourceStack(id, need) local b; for b=0,4 do local n=GetContainerNumSlots(b) or 0; local s; for s=1,n do local l=GetContainerItemLink(b,s) if l and itemIdFromLink(l)==id then local _,c,lck=GetContainerItemInfo(b,s) if (c or 0)>=need and not lck then return b,s end end end end end
local function findEmptySlot() local b; for b=0,4 do local n=GetContainerNumSlots(b) or 0; local s; for s=1,n do local tex,cnt,lck=GetContainerItemInfo(b,s) if not tex and not cnt and not lck then return b,s end end end end
local function firstOpenTradeSlot() local i; for i=1,6 do if not GetTradePlayerItemInfo(i) then return i end end end
local function tradeItemButton(i) return getglobal("TradePlayerItem"..i.."ItemButton") end
local function resetSand() F.state="IDLE"; F.didSplit=false; F.placed=false; F.acceptTries=0; F.dBag=nil; F.dSlot=nil; if not Roles or not Roles.active then F:Hide() end; ClearCursor() end

function OGRH.RunSand() if F.state~="IDLE" then msg("Already running."); return end F.state="SAND"; F.tick=F.interval; F:Show() end

F:SetScript("OnUpdate", function()
  local elapsed=arg1 or 0
  F.tick=F.tick+elapsed; if F.tick<F.interval then return end; F.tick=0
  if F.state=="SAND" then
    if not TradeFrame or not TradeFrame:IsShown() then msg("Open the trade window first."); return resetSand() end
    local b5,s5=findStackExact(ITEM_SAND,SAND_COUNT)
    if b5 and s5 then
      if not F.placed then
        local tslot=firstOpenTradeSlot(); if not tslot then msg("No free trade slot."); return resetSand() end
        PickupContainerItem(b5,s5); local btn=tradeItemButton(tslot); if not btn then return resetSand() end; btn:Click(); F.placed=true; F.acceptTries=0; return
      end
      if not TradeAcceptButton:IsEnabled() then F.acceptTries=F.acceptTries+1; if F.acceptTries>F.maxAcceptTries then msg("Trade not ready to accept."); return resetSand() end; return end
      TradeAcceptButton:Click(); return resetSand()
    else
      if not F.didSplit then
        local sb,ss=findSourceStack(ITEM_SAND,SAND_COUNT); if not sb then msg("No stack of sand with >=5."); return resetSand() end
        local eb,es=findEmptySlot(); if not eb then msg("No empty bag slot."); return resetSand() end
        SplitContainerItem(sb,ss,SAND_COUNT); PickupContainerItem(eb,es); F.didSplit=true; F.dBag, F.dSlot=eb,es; return
      else
        local b5a,s5a=findStackExact(ITEM_SAND,SAND_COUNT); if not (b5a and s5a) then return end
      end
    end
  end
end)
