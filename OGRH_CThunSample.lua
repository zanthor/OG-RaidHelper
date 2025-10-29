-- OGRH_CThun.lua
local function collectRangedInterleavedByParty()
  local parties = {}; local p; for p=1,8 do parties[p]={druids={},others={}} end
  local n,_; for n,_ in pairs(OGRH.Roles.buckets["RANGED"]) do
    if OGRH.Roles.testing or OGRH.Roles.raidNames[n] then
      local pg=OGRH.Roles.raidParty[n] or 1; local c=OGRH.Roles.nameClass[n]
      if c=="DRUID" then table.insert(parties[pg].druids,n) else table.insert(parties[pg].others,n) end
    end
  end
  for p=1,8 do table.sort(parties[p].druids); table.sort(parties[p].others) end
  local out={}; for p=1,8 do local di,oi=1,1; while (di<=table.getn(parties[p].druids) or oi<=table.getn(parties[p].others)) do if di<=table.getn(parties[p].druids) then table.insert(out, parties[p].druids[di]); di=di+1 end; if oi<=table.getn(parties[p].others) then table.insert(out, parties[p].others[oi]); oi=oi+1 end end end
  return out
end

local function assignCthunZones()
  OGRH.RefreshRoster(); OGRH.PruneBucketsToRaid()
  local zones={}; local i; for i=1,8 do zones[i]={} end
  local tanks=OGRH.SortedRoleNamesRaw("TANKS")
  local melee=OGRH.SortedRoleNamesRaw("MELEE")
  local healers=OGRH.SortedRoleNamesRaw("HEALERS")
  local ranged=collectRangedInterleavedByParty()
  local spread8={1,2,4,6,8,7,5,3}

  local tcount=table.getn(tanks)
  if tcount>=1 then table.insert(zones[1], tanks[1]) end
  if tcount>=2 then table.insert(zones[8], tanks[2]) end

  local mergedMelee={}; local j; for j=3,tcount do table.insert(mergedMelee, tanks[j]) end; for j=1,table.getn(melee) do table.insert(mergedMelee, melee[j]) end

  local mm=table.getn(mergedMelee); local mi=1; for j=1,mm do local z=spread8[OGRH.Mod1(mi,8)]; table.insert(zones[z], mergedMelee[j]); mi=mi+1 end

  local function spread(list) local n=table.getn(list); local k=1; local j; for j=1,n do local z=spread8[OGRH.Mod1(k,8)]; table.insert(zones[z], list[j]); k=k+1 end end
  spread(healers); spread(ranged)

  for i=1,8 do local names=zones[i]; if table.getn(names)>0 then local col={} ; local k; for k=1,table.getn(names) do col[k]=colorName(names[k]) end; sayRW("|cff00ff00[Zone "..i.."]|r: "..table.concat(col, " || ")) end end
end
if OGRH.btnCTHUN then OGRH.btnCTHUN:SetScript("OnClick", function() assignCthunZones(); OGRH.Msg("C'Thun zone assignments sent.") end) end
