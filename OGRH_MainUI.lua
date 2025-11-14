-- OGRH_MainUI.lua
if not OGRH then
  DEFAULT_CHAT_FRAME:AddMessage("|cffff0000Error: OGRH_MainUI requires OGRH_Core to be loaded first!|r")
  return
end

local Main = CreateFrame("Frame","OGRH_Main",UIParent)
Main:SetWidth(165); Main:SetHeight(56)  -- Fixed height for title bar + encounter nav
Main:SetPoint("CENTER", UIParent, "CENTER", -380, 120)
Main:SetFrameStrata("HIGH")
Main:SetBackdrop({bgFile="Interface/Tooltips/UI-Tooltip-Background", edgeFile="Interface/Tooltips/UI-Tooltip-Border", edgeSize=12, insets={left=4,right=4,top=4,bottom=4}})
Main:SetBackdropColor(0,0,0,0.85)
Main:EnableMouse(true); Main:SetMovable(true)
Main:RegisterForDrag("LeftButton")
Main:SetScript("OnDragStart", function() if not OGRH_SV.ui.locked then Main:StartMoving() end end)
Main:SetScript("OnDragStop", function()
  Main:StopMovingOrSizing()
  if not OGRH_SV.ui then OGRH_SV.ui = {} end
  local p,_,r,x,y = Main:GetPoint()
  OGRH_SV.ui.point, OGRH_SV.ui.relPoint, OGRH_SV.ui.x, OGRH_SV.ui.y = p, r, x, y
end)

local H = CreateFrame("Frame", nil, Main)
H:SetPoint("TOPLEFT", Main, "TOPLEFT", 4, -4)
H:SetPoint("TOPRIGHT", Main, "TOPRIGHT", -4, -4)
H:SetHeight(20)
local title = H:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
title:SetPoint("LEFT", H, "LEFT", 4, 0); title:SetText("|cffffff00RH|r")

local btnRoles = CreateFrame("Button", nil, H, "UIPanelButtonTemplate"); btnRoles:SetWidth(35); btnRoles:SetHeight(20); btnRoles:SetText("Roles"); btnRoles:SetPoint("RIGHT", H, "RIGHT", -26, 0); OGRH.StyleButton(btnRoles)
local btnLock = CreateFrame("Button", nil, H, "UIPanelButtonTemplate"); btnLock:SetWidth(20); btnLock:SetHeight(20); btnLock:SetPoint("RIGHT", H, "RIGHT", -4, 0); OGRH.StyleButton(btnLock)

-- Sync button (S) - Send encounter configuration to raid
local syncBtn = CreateFrame("Button", nil, H, "UIPanelButtonTemplate"); syncBtn:SetWidth(35); syncBtn:SetHeight(20); syncBtn:SetText("Sync"); syncBtn:SetPoint("RIGHT", btnRoles, "LEFT", -2, 0); OGRH.StyleButton(syncBtn)
syncBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

-- Function to update sync button color based on lock state
local function UpdateSyncButtonColor()
  OGRH.EnsureSV()
  if OGRH_SV.syncLocked then
    syncBtn:SetText("|cff00ff00Sync|r")  -- Bright green when locked
  else
    syncBtn:SetText("|cffffff00Sync|r")  -- Yellow when unlocked
  end
end

-- Store globally for access from other files
OGRH.UpdateSyncButtonColor = UpdateSyncButtonColor

syncBtn:SetScript("OnClick", function()
  local btn = arg1 or "LeftButton"
  
  if btn == "RightButton" then
    -- Right-click: Toggle sync lock
    OGRH.EnsureSV()
    OGRH_SV.syncLocked = not OGRH_SV.syncLocked
    UpdateSyncButtonColor()
    
    if OGRH_SV.syncLocked then
      OGRH.Msg("Sync locked: Will not receive encounter syncs from others.")
    else
      OGRH.Msg("Sync unlocked: Will receive encounter syncs from raid leader/assistants.")
    end
    return
  end
  
  -- Left-click: Send sync
  -- Get current encounter selection from EncounterMgmt
  if not OGRH.GetCurrentEncounter then
    OGRH.Msg("Encounter management not loaded.")
    return
  end
  
  local currentRaid, currentEncounter = OGRH.GetCurrentEncounter()
  if not currentRaid or not currentEncounter then
    OGRH.Msg("No encounter selected to sync. Open Encounter Planning and select an encounter first.")
    return
  end
  
  -- Build sync data package
  local syncData = {
    raid = currentRaid,
    encounter = currentEncounter,
    roles = {},
    assignments = {},
    marks = {},
    numbers = {},
    announcements = ""
  }
  
  -- Get roles configuration
  if OGRH_SV.encounterMgmt and OGRH_SV.encounterMgmt.roles and 
     OGRH_SV.encounterMgmt.roles[currentRaid] and 
     OGRH_SV.encounterMgmt.roles[currentRaid][currentEncounter] then
    syncData.roles = OGRH_SV.encounterMgmt.roles[currentRaid][currentEncounter]
  end
  
  -- Get player assignments
  if OGRH_SV.encounterAssignments and OGRH_SV.encounterAssignments[currentRaid] and 
     OGRH_SV.encounterAssignments[currentRaid][currentEncounter] then
    syncData.assignments = OGRH_SV.encounterAssignments[currentRaid][currentEncounter]
  end
  
  -- Get raid marks
  if OGRH_SV.encounterRaidMarks and OGRH_SV.encounterRaidMarks[currentRaid] and 
     OGRH_SV.encounterRaidMarks[currentRaid][currentEncounter] then
    syncData.marks = OGRH_SV.encounterRaidMarks[currentRaid][currentEncounter]
  end
  
  -- Get assignment numbers
  if OGRH_SV.encounterAssignmentNumbers and OGRH_SV.encounterAssignmentNumbers[currentRaid] and 
     OGRH_SV.encounterAssignmentNumbers[currentRaid][currentEncounter] then
    syncData.numbers = OGRH_SV.encounterAssignmentNumbers[currentRaid][currentEncounter]
  end
  
  -- Get announcements
  if OGRH_SV.encounterAnnouncements and OGRH_SV.encounterAnnouncements[currentRaid] and 
     OGRH_SV.encounterAnnouncements[currentRaid][currentEncounter] then
    syncData.announcements = OGRH_SV.encounterAnnouncements[currentRaid][currentEncounter]
  end
  
  -- Serialize and send
  local serialized = OGRH.Serialize(syncData)
  OGRH.SendAddonMessage("ENCOUNTER_SYNC", serialized)
  
  OGRH.Msg("Encounter configuration for " .. currentEncounter .. " synced to raid (excluding self).")
end)

-- ReadyCheck button
local readyCheck = CreateFrame("Button", nil, H, "UIPanelButtonTemplate"); readyCheck:SetWidth(35); readyCheck:SetHeight(20); readyCheck:SetText("Rdy"); readyCheck:SetPoint("RIGHT", syncBtn, "LEFT", -2, 0); OGRH.StyleButton(readyCheck)
readyCheck:RegisterForClicks("LeftButtonUp", "RightButtonUp")

-- Roles button handler
btnRoles:SetScript("OnClick", function()
  -- Close encounter windows if they're open
  if OGRH_BWLEncounterFrame and OGRH_BWLEncounterFrame:IsVisible() then
    OGRH_BWLEncounterFrame:Hide()
  end
  if OGRH_EncounterSetupFrame and OGRH_EncounterSetupFrame:IsVisible() then
    OGRH_EncounterSetupFrame:Hide()
  end
  -- Close encounters menu if it's open
  if OGRH_EncountersMenu and OGRH_EncountersMenu:IsVisible() then
    OGRH_EncountersMenu:Hide()
  end
  -- Close Trade menu if it's open
  if OGRH_TradeMenu and OGRH_TradeMenu:IsVisible() then
    OGRH_TradeMenu:Hide()
  end
  
  if OGRH.ShowRolesUI then OGRH.ShowRolesUI()
  else OGRH.Msg("Roles UI not yet loaded. If this persists after /reload, a Lua error prevented it from loading.");
  end
end)

-- Encounter navigation controls
local encounterNav = CreateFrame("Frame", nil, Main)
encounterNav:SetPoint("TOPLEFT", Main, "TOPLEFT", 6, -26)
encounterNav:SetPoint("TOPRIGHT", Main, "TOPRIGHT", -6, -26)
encounterNav:SetHeight(24)
encounterNav:Show()

-- Previous Encounter button
local prevEncBtn = CreateFrame("Button", nil, encounterNav, "UIPanelButtonTemplate")
prevEncBtn:SetWidth(20)
prevEncBtn:SetHeight(20)
prevEncBtn:SetPoint("LEFT", encounterNav, "LEFT", 0, 0)
prevEncBtn:SetText("<")
OGRH.StyleButton(prevEncBtn)
prevEncBtn:SetScript("OnClick", function()
  if OGRH.NavigateToPreviousEncounter then
    OGRH.NavigateToPreviousEncounter()
  end
end)
encounterNav.prevEncBtn = prevEncBtn

-- Announce button
local announceBtn = CreateFrame("Button", nil, encounterNav, "UIPanelButtonTemplate")
announceBtn:SetWidth(20)
announceBtn:SetHeight(20)
announceBtn:SetPoint("LEFT", prevEncBtn, "RIGHT", 2, 0)
announceBtn:SetText("A")
OGRH.StyleButton(announceBtn)
announceBtn:SetScript("OnClick", function()
  if OGRH.PrepareEncounterAnnouncement then
    OGRH.PrepareEncounterAnnouncement()
  end
end)
encounterNav.announceBtn = announceBtn

-- Mark button
local markBtn = CreateFrame("Button", nil, encounterNav, "UIPanelButtonTemplate")
markBtn:SetWidth(20)
markBtn:SetHeight(20)
markBtn:SetPoint("LEFT", announceBtn, "RIGHT", 2, 0)
markBtn:SetText("M")
OGRH.StyleButton(markBtn)
markBtn:SetScript("OnClick", function()
  if OGRH.MarkPlayersFromMainUI then
    OGRH.MarkPlayersFromMainUI()
  end
end)
encounterNav.markBtn = markBtn

-- Next Encounter button
local nextEncBtn = CreateFrame("Button", nil, encounterNav, "UIPanelButtonTemplate")
nextEncBtn:SetWidth(20)
nextEncBtn:SetHeight(20)
nextEncBtn:SetPoint("RIGHT", encounterNav, "RIGHT", 0, 0)
nextEncBtn:SetText(">")
OGRH.StyleButton(nextEncBtn)
nextEncBtn:SetScript("OnClick", function()
  if OGRH.NavigateToNextEncounter then
    OGRH.NavigateToNextEncounter()
  end
end)
encounterNav.nextEncBtn = nextEncBtn

-- Encounter button (middle, fills remaining space)
local encounterBtn = CreateFrame("Button", nil, encounterNav, "UIPanelButtonTemplate")
encounterBtn:SetHeight(20)
encounterBtn:SetPoint("LEFT", markBtn, "RIGHT", 2, 0)
encounterBtn:SetPoint("RIGHT", nextEncBtn, "LEFT", -2, 0)
encounterBtn:SetText("Select Raid")
OGRH.StyleButton(encounterBtn)
encounterBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
encounterBtn:SetScript("OnClick", function()
  if arg1 == "RightButton" then
    -- Show raid selection menu
    if OGRH.ShowEncounterRaidMenu then
      OGRH.ShowEncounterRaidMenu(encounterBtn)
    end
  else
    -- Left click: Open Encounter Planning with selected encounter
    -- Close Roles UI if it's open
    if getglobal("OGRH_RolesFrame") and getglobal("OGRH_RolesFrame"):IsVisible() then
      getglobal("OGRH_RolesFrame"):Hide()
    end
    
    if OGRH.OpenEncounterPlanning then
      OGRH.OpenEncounterPlanning()
    end
  end
end)
encounterNav.encounterBtn = encounterBtn

-- Store reference for external access
OGRH.encounterNav = encounterNav

local function applyLocked(lock)
  if lock then
    btnLock:SetText("|cff00ff00L|r")  -- Green when locked
  else
    btnLock:SetText("|cffffff00L|r")  -- Yellow when unlocked
  end
end
btnLock:SetScript("OnClick", function() ensureSV(); OGRH_SV.ui.locked = not OGRH_SV.ui.locked; applyLocked(OGRH_SV.ui.locked) end)

-- ReadyCheck button handler
readyCheck:SetScript("OnClick", function()
  local btn = arg1 or "LeftButton"
  
  if btn == "RightButton" then
    -- Show RC settings menu
    if not OGRH_RCMenu then
      local M = CreateFrame("Frame", "OGRH_RCMenu", UIParent)
      M:SetFrameStrata("FULLSCREEN_DIALOG")
      M:SetBackdrop({bgFile="Interface/Tooltips/UI-Tooltip-Background", edgeFile="Interface/Tooltips/UI-Tooltip-Border", edgeSize=12, insets={left=4,right=4,top=4,bottom=4}})
      M:SetBackdropColor(0,0,0,0.95); M:SetWidth(180); M:SetHeight(50); M:Hide()
      
      local toggleBtn = CreateFrame("Button", nil, M, "UIPanelButtonTemplate")
      toggleBtn:SetWidth(160); toggleBtn:SetHeight(20)
      toggleBtn:SetPoint("TOPLEFT", M, "TOPLEFT", 10, -15)
      OGRH.StyleButton(toggleBtn)
      
      local fs = toggleBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      fs:SetAllPoints(); fs:SetJustifyH("CENTER")
      toggleBtn.fs = fs
      
      toggleBtn:SetScript("OnClick", function()
        OGRH.EnsureSV()
        -- Toggle the setting
        OGRH_SV.allowRemoteReadyCheck = not OGRH_SV.allowRemoteReadyCheck
        
        -- Update button text
        if OGRH_SV.allowRemoteReadyCheck then
          fs:SetText("|cff00ff00Allow Remote Readycheck|r")
        else
          fs:SetText("|cffff0000Allow Remote Readycheck|r")
        end
        
        if OGRH and OGRH.Msg then
          if OGRH_SV.allowRemoteReadyCheck then
            OGRH.Msg("Remote ready checks |cff00ff00enabled|r.")
          else
            OGRH.Msg("Remote ready checks |cffff0000disabled|r.")
          end
        end
        
        -- Hide the menu after toggling
        M:Hide()
      end)
      
      M.toggleBtn = toggleBtn
    end
    
    local M = OGRH_RCMenu
    
    -- Toggle menu visibility
    if M:IsVisible() then
      M:Hide()
      return
    end
    
    -- Update button text based on current setting
    OGRH.EnsureSV()
    if OGRH_SV.allowRemoteReadyCheck then
      M.toggleBtn.fs:SetText("|cff00ff00Allow Remote Readycheck|r")
    else
      M.toggleBtn.fs:SetText("|cffff0000Allow Remote Readycheck|r")
    end
    
    M:ClearAllPoints(); M:SetPoint("TOPLEFT", readyCheck, "BOTTOMLEFT", 0, -2); M:Show()
  else
    -- Left click: Do ready check
    if OGRH.DoReadyCheck then
      OGRH.DoReadyCheck()
    else
      OGRH.Msg("Ready check functionality not loaded.")
    end
  end
end)

-- Expose sync button for external access
OGRH.syncButton = syncBtn

local function restoreMain()
  ensureSV()
  local ui=OGRH_SV.ui or {}
  if ui.point and ui.x and ui.y then Main:ClearAllPoints(); Main:SetPoint(ui.point, UIParent, ui.relPoint or ui.point, ui.x, ui.y) end
  applyLocked(ui.locked)
  
  -- Update sync button color after saved variables are loaded
  if OGRH.UpdateSyncButtonColor then
    OGRH.UpdateSyncButtonColor()
  end
  
  -- Check if window should be hidden
  if ui.hidden then
    Main:Hide()
  end
end
local _loader = CreateFrame("Frame"); _loader:RegisterEvent("VARIABLES_LOADED"); _loader:SetScript("OnEvent", function() restoreMain() end)

SlashCmdList[string.upper(OGRH.CMD)] = function(m)
  local sub = string.lower(OGRH.Trim(m or ""))
  if sub=="sand" then 
    if OGRH.SetTradeType and OGRH.ExecuteTrade then 
      OGRH.SetTradeType("sand")
      OGRH.ExecuteTrade()
    else 
      OGRH.Msg("Trade helper not loaded.") 
    end
  else OGRH.Msg("Usage: /"..OGRH.CMD.." sand") end
end
_G["SLASH_"..string.upper(OGRH.CMD).."1"] = "/"..OGRH.CMD

if OGRH and OGRH.Msg then
  OGRH.Msg(OGRH.ADDON.." v1.14.0 loaded. Use /"..OGRH.CMD.." roles or the OGRH window.")
end