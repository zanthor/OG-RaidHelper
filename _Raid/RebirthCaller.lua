-- RebirthCaller.lua (Phase 1 + 2: Core Logic & Announcement)
-- Death tracking, assignment algorithm, API, announcement
-- Module: _Raid/RebirthCaller.lua
-- Dependencies: ReadynessDashboard.lua (CooldownTrackers.rebirth)

if not OGRH then
  DEFAULT_CHAT_FRAME:AddMessage("|cffff0000Error: RebirthCaller requires OGRH_Core to be loaded first!|r")
  return
end

-- ============================================
-- Module Namespace
-- ============================================
OGRH.RebirthCaller = OGRH.RebirthCaller or {}
local RC = OGRH.RebirthCaller

-- ============================================
-- Module State
-- ============================================
RC.State = {
  debug = false,
  initialized = false,
}

-- Dead players: keyed by name
-- { [name] = { name, unitId, deathTime, class, role } }
RC.deadPlayers = {}

-- Ordered list of dead player names for UI iteration
RC.deadPlayerList = {}

-- UnitXP SP3 availability (checked once at init)
RC.hasUnitXP = false

-- ============================================
-- Role Priority for multi-death assignment
-- ============================================
RC.ROLE_PRIORITY = {
  TANKS   = 1,
  HEALERS = 2,
  RANGED  = 3,
  MELEE   = 4,
}

-- ============================================
-- SVM Defaults
-- ============================================
RC.SVM_DEFAULTS = {
  enabled = true,
  isDocked = true,
  columns = 2,
  columnWidth = 80,
  growthDirection = "down",  -- "up", "down", "left", "right"
  autoShow = true,
  autoHide = true,
  whisperDruid = true,
}

-- ============================================
-- Initialization
-- ============================================
function RC.Initialize()
  if RC.State.initialized then return end

  -- Ensure SVM defaults are present
  RC.EnsureSVMDefaults()

  -- Check for UnitXP SP3
  RC.hasUnitXP = (UnitXP ~= nil)
  if not RC.hasUnitXP then
    OGRH.Msg("|cffff8800[RebirthCaller]|r UnitXP SP3 not detected — spatial features disabled")
  end

  RC.RegisterEvents()

  RC.State.initialized = true
  OGRH.Msg("|cffff6666[RH-RebirthCaller]|r module loaded")
  if RC.State.debug then
    OGRH.Msg("|cffff6666[RebirthCaller][DEBUG]|r Initialized (UnitXP: " .. (RC.hasUnitXP and "yes" or "no") .. ")")
  end
end

-- ============================================
-- SVM Integration
-- ============================================
function RC.EnsureSVMDefaults()
  if not OGRH.SVM or not OGRH.SVM.GetPath then return end

  local existing = OGRH.SVM.GetPath("rebirthCaller")
  if not existing then
    OGRH.SVM.SetPath("rebirthCaller", RC.SVM_DEFAULTS)
  else
    for key, val in pairs(RC.SVM_DEFAULTS) do
      if existing[key] == nil then
        OGRH.SVM.SetPath("rebirthCaller." .. key, val)
      end
    end
  end
end

function RC.GetSetting(path)
  if not OGRH.SVM or not OGRH.SVM.GetPath then return nil end
  return OGRH.SVM.GetPath("rebirthCaller." .. path)
end

function RC.SetSetting(path, value)
  if not OGRH.SVM or not OGRH.SVM.SetPath then return end
  OGRH.SVM.SetPath("rebirthCaller." .. path, value)
end

function RC.IsEnabled()
  local val = RC.GetSetting("enabled")
  if val == nil then return true end
  return val
end

function RC.Toggle()
  local current = RC.IsEnabled()
  RC.SetSetting("enabled", not current)
  if not current then
    -- Was disabled, now enabled
    if RC.ShowUI then RC.ShowUI() end
    OGRH.Msg("|cffff6666[RH-RebirthCaller]|r |cff00ff00enabled|r")
  else
    -- Was enabled, now disabled
    if RC.HideUI then RC.HideUI() end
    OGRH.Msg("|cffff6666[RH-RebirthCaller]|r |cffff0000disabled|r")
  end
end

-- ============================================
-- Event Registration
-- ============================================
function RC.RegisterEvents()
  if RC.eventFrame then return end

  RC.eventFrame = CreateFrame("Frame", "OGRH_RebirthCallerFrame")
  RC.eventFrame:RegisterEvent("UNIT_HEALTH")
  RC.eventFrame:RegisterEvent("CHAT_MSG_COMBAT_FRIENDLY_DEATH")
  RC.eventFrame:RegisterEvent("RAID_ROSTER_UPDATE")

  RC.eventFrame:SetScript("OnEvent", function()
    if event == "UNIT_HEALTH" then
      RC.OnUnitHealth(arg1)
    elseif event == "CHAT_MSG_COMBAT_FRIENDLY_DEATH" then
      RC.OnFriendlyDeath(arg1)
    elseif event == "RAID_ROSTER_UPDATE" then
      RC.OnRaidRosterUpdate()
    end
  end)
end

-- ============================================
-- Event Handlers
-- ============================================
function RC.OnUnitHealth(unitId)
  if not unitId then return end
  if not UnitExists(unitId) then return end
  if not string.find(unitId, "^raid") then return end
  if string.find(unitId, "^raidpet") then return end  -- Pets can't be Rebirthed

  local name = UnitName(unitId)
  if not name then return end

  if UnitIsDead(unitId) and not UnitIsGhost(unitId) then
    -- Dead (not released) — add to tracking
    if not RC.deadPlayers[name] then
      RC.AddDeadPlayer(name, unitId)
    end
  else
    -- Alive or ghost — remove from tracking
    if RC.deadPlayers[name] then
      RC.RemoveDeadPlayer(name)
    end
  end
end

function RC.OnFriendlyDeath(msg)
  if not msg then return end
  -- Pattern: "Playername dies."
  local _, _, name = string.find(msg, "^(.+) dies%.$")
  if name then
    local unitId = RC.FindRaidUnit(name)
    if unitId and not RC.deadPlayers[name] then
      RC.AddDeadPlayer(name, unitId)
    end
  end
end

function RC.OnRaidRosterUpdate()
  -- Validate existing dead players are still in the raid
  for name, _ in pairs(RC.deadPlayers) do
    local unitId = RC.FindRaidUnit(name)
    if not unitId then
      -- Player left the raid
      RC.RemoveDeadPlayer(name)
    else
      -- Update unitId (raid indices can shift)
      RC.deadPlayers[name].unitId = unitId
    end
  end
end

-- ============================================
-- Dead Player Management
-- ============================================
function RC.AddDeadPlayer(name, unitId)
  if RC.deadPlayers[name] then return end

  local _, class = UnitClass(unitId)
  local role = OGRH_GetPlayerRole and OGRH_GetPlayerRole(name) or nil

  RC.deadPlayers[name] = {
    name = name,
    unitId = unitId,
    deathTime = GetTime(),
    class = class and string.upper(class) or "UNKNOWN",
    role = role,
  }

  -- Add to ordered list
  table.insert(RC.deadPlayerList, name)
  RC.SortDeadPlayerList()

  if RC.State.debug then
    OGRH.Msg("|cffff6666[RebirthCaller][DEBUG]|r Added dead player: " .. name .. " (" .. (role or "?") .. ")")
  end

  -- Fire callback
  RC.FireCallback("OnPlayerDeath", name)
end

function RC.RemoveDeadPlayer(name)
  if not RC.deadPlayers[name] then return end

  RC.deadPlayers[name] = nil

  -- Remove from ordered list
  for i = table.getn(RC.deadPlayerList), 1, -1 do
    if RC.deadPlayerList[i] == name then
      table.remove(RC.deadPlayerList, i)
      break
    end
  end

  if RC.State.debug then
    OGRH.Msg("|cffff6666[RebirthCaller][DEBUG]|r Removed dead player: " .. name)
  end

  -- Fire callback
  RC.FireCallback("OnPlayerResurrected", name)
end

function RC.SortDeadPlayerList()
  table.sort(RC.deadPlayerList, function(a, b)
    local dataA = RC.deadPlayers[a]
    local dataB = RC.deadPlayers[b]
    if not dataA or not dataB then return false end

    local prioA = RC.ROLE_PRIORITY[dataA.role] or 99
    local prioB = RC.ROLE_PRIORITY[dataB.role] or 99

    if prioA ~= prioB then
      return prioA < prioB  -- Tanks first, then healers, etc.
    end
    return (dataA.deathTime or 0) < (dataB.deathTime or 0)  -- Earlier death first
  end)
end

-- ============================================
-- Raid Unit Lookup
-- ============================================
function RC.FindRaidUnit(name)
  for i = 1, GetNumRaidMembers() do
    local raidName = UnitName("raid" .. i)
    if raidName == name then
      return "raid" .. i
    end
  end
  return nil
end

-- ============================================
-- UnitXP Wrappers
-- ============================================
function RC.GetDistance(unit1, unit2)
  if not RC.hasUnitXP then return nil end
  local ok, dist = pcall(UnitXP, "distanceBetween", unit1, unit2, "ranged")
  if ok then return dist end
  return nil
end

function RC.HasLineOfSight(unit1, unit2)
  if not RC.hasUnitXP then return nil end
  local ok, los = pcall(UnitXP, "inSight", unit1, unit2)
  if ok then return los == true end
  return nil
end

-- ============================================
-- Cooldown Availability Check
-- ============================================
function RC.IsDruidRebirthAvailable(druidName)
  local RD = OGRH.ReadynessDashboard
  if not RD or not RD.CooldownTrackers then return true end  -- Default: assume available

  local tracker = RD.CooldownTrackers.rebirth
  if not tracker then return true end

  -- Self-reported ready overrides cast tracking
  if tracker.reportedReady and tracker.reportedReady[druidName] then
    return true
  end

  local cast = tracker.casts[druidName]
  if cast and cast.lastCast then
    local elapsed = GetTime() - cast.lastCast
    if elapsed < tracker.cooldownDuration then
      return false  -- Still on cooldown
    end
  end

  -- No cast data or cooldown expired — assume available
  return true
end

-- ============================================
-- Assignment Algorithm
-- ============================================

--- Get the best druid assignment for a single dead player.
-- @param deadPlayerName string Name of the dead player
-- @param excludeDruids table|nil Optional table of { [druidName] = true } to exclude (for multi-death dedup)
-- @return table Assignment result
function RC.GetAssignment(deadPlayerName, excludeDruids)
  local deadData = RC.deadPlayers[deadPlayerName]
  if not deadData then
    return { deadPlayer = deadPlayerName, druid = nil, reason = "Player not tracked as dead" }
  end

  local deadUnit = deadData.unitId
  if not deadUnit or not UnitExists(deadUnit) then
    -- Try to re-resolve
    deadUnit = RC.FindRaidUnit(deadPlayerName)
    if deadUnit then
      deadData.unitId = deadUnit
    else
      return { deadPlayer = deadPlayerName, druid = nil, reason = "Dead player unit not found" }
    end
  end

  -- Verify still dead
  if not UnitIsDead(deadUnit) then
    RC.RemoveDeadPlayer(deadPlayerName)
    return { deadPlayer = deadPlayerName, druid = nil, reason = "Player is no longer dead" }
  end

  -- Build candidate list
  local candidates = {}

  for i = 1, GetNumRaidMembers() do
    local name, _, _, _, class = GetRaidRosterInfo(i)
    if name and class then
      local upper = string.upper(class)
      if upper == "DRUID" then
        local unit = "raid" .. i

        -- Must be alive
        if not UnitIsDead(unit) then
          -- Must not be excluded (multi-death dedup)
          if not excludeDruids or not excludeDruids[name] then
            -- Must have Rebirth available
            if RC.IsDruidRebirthAvailable(name) then
              local distance = RC.GetDistance(unit, deadUnit)
              local hasLoS = RC.HasLineOfSight(unit, deadUnit)

              table.insert(candidates, {
                name = name,
                unit = unit,
                distance = distance,          -- nil if no UnitXP
                hasLoS = hasLoS,              -- nil if no UnitXP
              })
            end
          end
        end
      end
    end
  end

  -- Sort: by distance if available, otherwise alphabetical
  if RC.hasUnitXP then
    table.sort(candidates, function(a, b)
      local dA = a.distance or 999999
      local dB = b.distance or 999999
      return dA < dB
    end)
  else
    table.sort(candidates, function(a, b)
      return (a.name or "") < (b.name or "")
    end)
  end

  -- Select best
  if table.getn(candidates) > 0 then
    local best = candidates[1]
    local fallback = {}
    for i = 2, table.getn(candidates) do
      table.insert(fallback, candidates[i])
    end

    return {
      deadPlayer = deadPlayerName,
      druid = best.name,
      druidUnit = best.unit,
      distance = best.distance,
      hasLoS = best.hasLoS,
      fallbackDruids = fallback,
      reason = nil,
    }
  else
    return {
      deadPlayer = deadPlayerName,
      druid = nil,
      reason = "No druids with Rebirth available",
    }
  end
end

--- Get assignments for all currently dead players, avoiding double-booking.
-- @return table Array of assignment results, priority-ordered (tanks > healers > DPS)
function RC.GetAllAssignments()
  local usedDruids = {}
  local assignments = {}

  for _, name in ipairs(RC.deadPlayerList) do
    local result = RC.GetAssignment(name, usedDruids)
    if result.druid then
      usedDruids[result.druid] = true
    end
    table.insert(assignments, result)
  end

  return assignments
end

--- Check if any druid with Rebirth available is within 30 yards and has LoS to a dead player.
-- Used for the green backdrop indicator in the UI.
-- @param deadPlayerName string
-- @return boolean
function RC.HasDruidInRange(deadPlayerName)
  if not RC.hasUnitXP then return false end

  local deadData = RC.deadPlayers[deadPlayerName]
  if not deadData then return false end

  local deadUnit = deadData.unitId
  if not deadUnit or not UnitExists(deadUnit) then return false end

  for i = 1, GetNumRaidMembers() do
    local name, _, _, _, class = GetRaidRosterInfo(i)
    if name and class and string.upper(class) == "DRUID" then
      local unit = "raid" .. i
      if not UnitIsDead(unit) and RC.IsDruidRebirthAvailable(name) then
        local distance = RC.GetDistance(unit, deadUnit)
        local hasLoS = RC.HasLineOfSight(unit, deadUnit)
        if distance and distance <= 30 and hasLoS then
          return true
        end
      end
    end
  end

  return false
end

-- ============================================
-- Public API (convenience wrappers)
-- ============================================

--- Check if a player is dead and tracked
function RC.IsPlayerDead(playerName)
  return RC.deadPlayers[playerName] ~= nil
end

--- Get list of currently dead players (ordered by priority)
function RC.GetDeadPlayers()
  local result = {}
  for _, name in ipairs(RC.deadPlayerList) do
    local data = RC.deadPlayers[name]
    if data then
      table.insert(result, {
        name = data.name,
        unitId = data.unitId,
        deathTime = data.deathTime,
        class = data.class,
        role = data.role,
      })
    end
  end
  return result
end

--- Check if UnitXP SP3 is available
function RC.HasSpatialData()
  return RC.hasUnitXP
end

-- ============================================
-- Callback System
-- ============================================
RC.callbacks = {}

function RC.RegisterCallback(event, fn)
  if not RC.callbacks[event] then
    RC.callbacks[event] = {}
  end
  table.insert(RC.callbacks[event], fn)
end

function RC.FireCallback(event, ...)
  if not RC.callbacks[event] then return end
  for _, fn in ipairs(RC.callbacks[event]) do
    local ok, err = pcall(fn, unpack(arg))
    if not ok and RC.State.debug then
      OGRH.Msg("|cffff6666[RebirthCaller][DEBUG]|r Callback error (" .. event .. "): " .. tostring(err))
    end
  end
end

-- ============================================
-- Announcement System
-- ============================================

--- Announce a Rebirth assignment to raid chat + whisper druid.
-- @param assignment table from GetAssignment()
function RC.AnnounceAssignment(assignment)
  if not assignment or not assignment.druid then return end

  local druid = assignment.druid
  local dead = assignment.deadPlayer
  local distText = assignment.distance and string.format("%.0f yds", assignment.distance) or "?"

  -- Build text: "DruidName [Rebirth] -> DeadName (28 yds)"
  local spellLink = "|cff71d5ff|Hspell:20748|h[Rebirth]|h|r"
  local text = druid .. " " .. spellLink .. " -> " .. dead .. " (" .. distText .. ")"

  -- Send to raid warning if possible, otherwise raid chat
  if OGRH.CanRW and OGRH.CanRW() then
    SendChatMessage(text, "RAID_WARNING")
  else
    SendChatMessage(text, "RAID")
  end

  -- Whisper the druid (if setting enabled)
  local whisper = RC.GetSetting("whisperDruid")
  if whisper ~= false then
    SendChatMessage("Rebirth " .. dead .. " (" .. distText .. ")", "WHISPER", nil, druid)
  end

  -- Mark as announced
  local deadData = RC.deadPlayers[dead]
  if deadData then
    deadData.assignedDruid = druid
    deadData.announced = true
  end

  if RC.State.debug then
    OGRH.Msg("|cffff6666[RebirthCaller][DEBUG]|r Announced: " .. druid .. " -> " .. dead)
  end
end

--- Compute the assignment for a dead player and announce it.
-- @param deadPlayerName string
-- @param cycleIndex number|nil If provided, pick the Nth druid instead of the closest
function RC.CallRebirth(deadPlayerName, cycleIndex)
  if not deadPlayerName then return end

  local result = RC.GetAssignment(deadPlayerName)
  if not result.druid then
    OGRH.Msg("|cffff6666[RH-RebirthCaller]|r " .. (result.reason or "No druids available"))
    return
  end

  -- If cycling, pick from fallback druids
  if cycleIndex and cycleIndex > 1 and result.fallbackDruids then
    local idx = cycleIndex - 1
    if idx <= table.getn(result.fallbackDruids) then
      local alt = result.fallbackDruids[idx]
      result.druid = alt.name
      result.druidUnit = alt.unit
      result.distance = alt.distance
      result.hasLoS = alt.hasLoS
    end
  end

  RC.AnnounceAssignment(result)
  return result
end

-- ============================================
-- Debug Toggle
-- ============================================
function RC.ToggleDebug()
  RC.State.debug = not RC.State.debug
  OGRH.Msg("|cffff8800[RebirthCaller]|r Debug " .. (RC.State.debug and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
end

-- ============================================
-- Test Mode (layout testing with live/fake data)
-- ============================================
function RC.TestMode(count)
  -- If already in test mode, clear and exit (unless count specified to change)
  if RC.State.testMode then
    RC.ClearTestData()
    if not count then return end
  end

  RC.State.testMode = true

  -- Default count
  if not count or count < 1 then count = 8 end
  if count > 40 then count = 40 end

  -- Base class templates for generating names
  local classTemplates = {
    { class = "WARRIOR", role = "TANKS", prefix = "Tank" },
    { class = "PRIEST", role = "HEALERS", prefix = "Heal" },
    { class = "PALADIN", role = "HEALERS", prefix = "Pala" },
    { class = "ROGUE", role = "MELEE", prefix = "Stab" },
    { class = "MAGE", role = "RANGED", prefix = "Frost" },
    { class = "WARLOCK", role = "RANGED", prefix = "Dot" },
    { class = "DRUID", role = "HEALERS", prefix = "Paws" },
    { class = "HUNTER", role = "RANGED", prefix = "Arrow" },
    { class = "SHAMAN", role = "HEALERS", prefix = "Totem" },
  }
  local numTemplates = table.getn(classTemplates)

  -- Collect class info from raid or generate fake data
  local testNames = {}

  local raidCount = GetNumRaidMembers()
  if raidCount > 0 then
    -- Use real raid members up to count
    local added = 0
    for i = 1, raidCount do
      if added >= count then break end
      local name, _, _, _, class = GetRaidRosterInfo(i)
      if name and class then
        local role = OGRH_GetPlayerRole and OGRH_GetPlayerRole(name) or "RANGED"
        table.insert(testNames, {
          name = name,
          class = string.upper(class),
          role = role,
        })
        added = added + 1
      end
    end
    -- Fill remainder with fake names if raid is smaller than count
    while added < count do
      added = added + 1
      local tmpl = classTemplates[math.mod(added - 1, numTemplates) + 1]
      table.insert(testNames, {
        name = tmpl.prefix .. added,
        class = tmpl.class,
        role = tmpl.role,
      })
    end
  else
    -- Generate fake names up to count
    for i = 1, count do
      local tmpl = classTemplates[math.mod(i - 1, numTemplates) + 1]
      table.insert(testNames, {
        name = tmpl.prefix .. i,
        class = tmpl.class,
        role = tmpl.role,
      })
    end
  end

  -- Inject fake dead entries
  local now = GetTime()
  for i, entry in ipairs(testNames) do
    if not RC.deadPlayers[entry.name] then
      RC.deadPlayers[entry.name] = {
        name = entry.name,
        unitId = "raid" .. i,
        deathTime = now - (i * 2),
        class = entry.class,
        role = entry.role,
      }
      table.insert(RC.deadPlayerList, entry.name)
    end
  end
  RC.SortDeadPlayerList()

  -- Force show UI
  if RC.ShowUI then RC.ShowUI() end
  RC.RefreshUI()

  OGRH.Msg("|cffff6666[RH-RebirthCaller]|r Test mode |cff00ff00ON|r — " .. table.getn(testNames) .. " fake deaths injected")
  OGRH.Msg("|cffff6666[RH-RebirthCaller]|r Type /ogrh test rebirth again to clear")
end

function RC.ClearTestData()
  RC.State.testMode = false
  RC.deadPlayers = {}
  RC.deadPlayerList = {}

  if RC.RefreshUI then RC.RefreshUI() end

  OGRH.Msg("|cffff6666[RH-RebirthCaller]|r Test mode |cffff0000OFF|r — dead list cleared")
end

-- ============================================
-- Bootstrap (runs at file load time)
-- ============================================
local bootFrame = CreateFrame("Frame")
bootFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
bootFrame:SetScript("OnEvent", function()
  RC.Initialize()
  bootFrame:UnregisterAllEvents()
end)
