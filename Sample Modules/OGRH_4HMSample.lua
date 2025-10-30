-- OGRH_4HM.lua
local bosses={"Thane","Mograine","Lady","Zeliek"}

local function assign4HM()
  ensureSV(); OGRH.RefreshRoster(); OGRH.PruneBucketsToRaid()
  local heals = OGRH.SortedRoleNamesRaw("HEALERS")
  local perBossTanks = { {}, {}, {}, {} }

  if OGRH.Roles.tankHeaders then
    local full = OGRH.Columns and OGRH.Columns["TANKS"] and OGRH.Columns["TANKS"].list; if not full then full = OGRH.SortedRoleNamesRaw("TANKS") end
    local currentHeader=nil; local i
    for i=1,table.getn(full) do local nm=full[i]
      if nm=="__HDR_THANE__" then currentHeader=1
      elseif nm=="__HDR_LADY__" then currentHeader=3
      elseif nm=="__HDR_ZELIEK__" then currentHeader=4
      elseif nm=="__HDR_MOGRAINE__" then currentHeader=2
      else if currentHeader and nm and nm~="" then table.insert(perBossTanks[currentHeader], nm) end end
    end
  else
    local tanks = OGRH.SortedRoleNamesRaw("TANKS")
    if tanks[1] then table.insert(perBossTanks[1], tanks[1]) end
    if tanks[2] then table.insert(perBossTanks[2], tanks[2]) end
    if tanks[3] then table.insert(perBossTanks[2], tanks[3]) end
    if tanks[4] then table.insert(perBossTanks[3], tanks[4]) end
    if tanks[5] then table.insert(perBossTanks[3], tanks[5]) end
    if tanks[6] then table.insert(perBossTanks[4], tanks[6]) end
    if tanks[7] then table.insert(perBossTanks[4], tanks[7]) end
  end

  local perBossHeals = { {}, {}, {}, {} }
  if OGRH.Roles.healerHeaders then
    local order = OGRH_SV.order["HEALERS"] or {}
    table.sort(heals, function(a,b) local ia=order[a] or 9999; local ib=order[b] or 9999; if ia~=ib then return ia<ib else return a<b end end)
    local i; for i=1,table.getn(heals) do local nm=heals[i]; local g=OGRH_SV.healerBoss[nm] or 1; if g<1 then g=1 elseif g>4 then g=4 end; if nm and nm~="" then table.insert(perBossHeals[g], nm) end end
  else
    local i; for i=1,table.getn(heals) do local g=math.mod(i-1,4)+1; local nm=heals[i]; if nm and nm~="" then table.insert(perBossHeals[g], nm) end end
  end

  local b; for b=1,4 do
    local tnames=perBossTanks[b]; local colT={}; local ti; for ti=1,table.getn(tnames) do colT[ti]=colorName(tnames[ti]) end
    local hnames={}; local hlist=perBossHeals[b]; local k; for k=1,3 do if hlist and hlist[k] then table.insert(hnames, colorName(hlist[k]).." ["..k.."]") end end
    if tnames and table.getn(tnames)>0 then sayRW("|cff00ff00["..bosses[b].."]|r |cffffff00Tanks:|r "..table.concat(colT, " || ")) end
    if table.getn(hnames)>0 then sayRW("|cffffff00Healers:|r "..table.concat(hnames, " || ")) end
  end
end

if OGRH.btn4HM then
  OGRH.btn4HM:RegisterForClicks("LeftButtonUp","RightButtonUp")
  OGRH.btn4HM:SetScript("OnClick", function()
    local btn = arg1 or "LeftButton"

    if btn == "LeftButton" then
      if not OGRH.Roles.tankHeaders then
        OGRH.Roles.tankHeaders = true
        OGRH.Roles.healerHeaders = true

        if not OGRH._didDefault4HM then
          OGRH._didDefault4HM = true
          local tanks = OGRH.SortedRoleNamesRaw("TANKS")
          for i = 1, table.getn(tanks) do
            if not OGRH_SV.tankCategory[tanks[i]] then
              local cat = 4
              if i == 1 then cat = 1
              elseif i == 2 or i == 3 then cat = 4
              elseif i == 4 or i == 5 then cat = 3
              elseif i == 6 or i == 7 then cat = 2 end
              OGRH_SV.tankCategory[tanks[i]] = cat
            end
          end

          local heals = OGRH.SortedRoleNamesRaw("HEALERS")
          for i = 1, table.getn(heals) do
            if not OGRH_SV.healerBoss[heals[i]] then
              OGRH_SV.healerBoss[heals[i]] = OGRH.Mod1(i, 4)
            end
          end
        end

        -- ✅ reindex immediately after enabling 4HM headers
        OGRH.ReindexRole("TANKS")
        OGRH.ReindexRole("HEALERS")

        OGRH.Board_Refresh()
        OGRH.Msg("Headers enabled for 4HM. Click 4HM again to announce.")
        return
      end

      assign4HM()
      OGRH.Msg("4HM assignments sent.")
    else
      OGRH.Roles.tankHeaders = not OGRH.Roles.tankHeaders
      OGRH.Roles.healerHeaders = OGRH.Roles.tankHeaders

      -- ✅ reindex immediately after toggling headers off/on
      OGRH.ReindexRole("TANKS")
      OGRH.ReindexRole("HEALERS")

      OGRH.Board_Refresh()
      if OGRH.Roles.tankHeaders then
        OGRH.Msg("4HM headers ON")
      else
        OGRH.Msg("4HM headers OFF")
      end
    end
  end)
end

