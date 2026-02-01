-- OGRH_MainUI.lua
if not OGRH then
  DEFAULT_CHAT_FRAME:AddMessage("|cffff0000Error: OGRH_MainUI requires OGRH_Core to be loaded first!|r")
  return
end

-- MainUI State
OGRH.MainUI = OGRH.MainUI or {}
OGRH.MainUI.State = {
  debug = false  -- Toggle with /ogrh debug ui
}

local Main = CreateFrame("Frame","OGRH_Main",UIParent)
Main:SetWidth(180); Main:SetHeight(56)  -- Fixed height for title bar + encounter nav
Main:SetPoint("CENTER", UIParent, "CENTER", -380, 120)
Main:SetFrameStrata("HIGH")
Main:SetBackdrop({bgFile="Interface/Tooltips/UI-Tooltip-Background", edgeFile="Interface/Tooltips/UI-Tooltip-Border", edgeSize=12, insets={left=4,right=4,top=4,bottom=4}})
Main:SetBackdropColor(0,0,0,0.85)
Main:EnableMouse(true); Main:SetMovable(true)
Main:RegisterForDrag("LeftButton")
Main:SetScript("OnDragStart", function() if not OGRH.SVM.Get("ui", "locked") then Main:StartMoving() end end)
Main:SetScript("OnDragStop", function()
  Main:StopMovingOrSizing()
  local p,_,r,x,y = Main:GetPoint()
  OGRH.SVM.Set("ui", "point", p)
  OGRH.SVM.Set("ui", "relPoint", r)
  OGRH.SVM.Set("ui", "x", x)
  OGRH.SVM.Set("ui", "y", y)
end)

local H = CreateFrame("Frame", nil, Main)
H:SetPoint("TOPLEFT", Main, "TOPLEFT", 4, -4)
H:SetPoint("TOPRIGHT", Main, "TOPRIGHT", -4, -4)
H:SetHeight(20)

-- RH button (opens menu like minimap right-click)
local rhBtn = CreateFrame("Button", nil, H, "UIPanelButtonTemplate")
rhBtn:SetWidth(28)
rhBtn:SetHeight(20)
rhBtn:SetPoint("LEFT", H, "LEFT", 2, 0)
rhBtn:SetText("RH")
OGRH.StyleButton(rhBtn)

rhBtn:SetScript("OnClick", function()
  -- Initialize menu if needed by calling the global show function
  if OGRH.ShowMinimapMenu then
    -- This will create the menu if it doesn't exist
    OGRH.ShowMinimapMenu(rhBtn)
  elseif OGRH_MinimapMenu then
    -- Menu exists, just toggle it
    local menu = OGRH_MinimapMenu
    
    if menu:IsVisible() then
      menu:Hide()
      return
    end
    
    -- Update toggle button text
    if menu.UpdateToggleText then
      menu.UpdateToggleText()
    end
    
    -- Position menu near RH button
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", rhBtn, "BOTTOMLEFT", 0, -2)
    menu:Show()
  end
end)

-- ReadyCheck button
local readyCheck = CreateFrame("Button", nil, H, "UIPanelButtonTemplate"); readyCheck:SetWidth(33); readyCheck:SetHeight(20); readyCheck:SetText("Rdy"); readyCheck:SetPoint("LEFT", rhBtn, "RIGHT", 2, 0); OGRH.StyleButton(readyCheck)

-- Admin button - Manage raid admin and poll
local adminBtn = CreateFrame("Button", nil, H, "UIPanelButtonTemplate"); adminBtn:SetWidth(45); adminBtn:SetHeight(20); adminBtn:SetText("Admin"); adminBtn:SetPoint("LEFT", readyCheck, "RIGHT", 2, 0); OGRH.StyleButton(adminBtn)

-- Lock button
local btnLock = CreateFrame("Button", nil, H, "UIPanelButtonTemplate"); btnLock:SetWidth(20); btnLock:SetHeight(20); btnLock:SetPoint("RIGHT", H, "RIGHT", -4, 0); OGRH.StyleButton(btnLock)

-- Roles button (fills remaining space between Admin and Lock)
local btnRoles = CreateFrame("Button", nil, H, "UIPanelButtonTemplate")
btnRoles:SetHeight(20)
btnRoles:SetPoint("LEFT", adminBtn, "RIGHT", 2, 0)
btnRoles:SetPoint("RIGHT", btnLock, "LEFT", -2, 0)
btnRoles:SetText("Roles")
OGRH.StyleButton(btnRoles)
OGRH.MainUI_RolesBtn = btnRoles  -- Store reference for menu access
adminBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

-- Function to update admin button color based on admin status
local function UpdateAdminButtonColor()
  OGRH.EnsureSV()
  local currentAdmin = OGRH.GetRaidAdmin and OGRH.GetRaidAdmin() or nil
  local isCurrentAdmin = (currentAdmin == UnitName("player"))
  
  if isCurrentAdmin then
    adminBtn:SetText("|cff00ff00Admin|r")  -- Bright green when you are admin
  else
    adminBtn:SetText("|cffffff00Admin|r")  -- Yellow when not admin
  end
end

-- Store globally for access from other files
OGRH.UpdateAdminButtonColor = UpdateAdminButtonColor
-- Backward compatibility alias
OGRH.UpdateSyncButtonColor = UpdateAdminButtonColor

-- Add tooltip to show current raid admin
adminBtn:SetScript("OnEnter", function()
  local adminName = "None"
  if OGRH.GetRaidAdmin then
    adminName = OGRH.GetRaidAdmin() or "None"
  end
  
  local isRaidAdmin = OGRH.IsRaidAdmin and OGRH.IsRaidAdmin(UnitName("player"))
  
  GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
  GameTooltip:SetText("Raid Admin", 1, 1, 1)
  GameTooltip:AddLine("Current Raid Admin: " .. adminName, 1, 0.82, 0)
  GameTooltip:AddLine(" ", 1, 1, 1)
  GameTooltip:AddLine("Left-click: Open admin poll interface", 0.7, 0.7, 0.7)
  GameTooltip:AddLine("Right-click: Take over as raid admin", 0.7, 0.7, 0.7)
  GameTooltip:Show()
end)

adminBtn:SetScript("OnLeave", function()
  GameTooltip:Hide()
end)

adminBtn:SetScript("OnClick", function()
  local btn = arg1 or "LeftButton"
  
  if btn == "RightButton" then
    -- Right-click: Take over as raid admin
    if GetNumRaidMembers() == 0 then
      OGRH.Msg("You must be in a raid to take over as raid admin.")
      return
    end
    
    -- Use Permissions system to request admin role
    if OGRH.RequestAdminRole then
      OGRH.RequestAdminRole()
    else
      OGRH.Msg("ERROR: Permissions system not loaded.")
    end
    return
  end
  
  -- Left-click: Open admin poll interface
  if OGRH.PollAddonUsers then
    OGRH.PollAddonUsers()
  end
end)

-- ReadyCheck button click handlers
readyCheck:RegisterForClicks("LeftButtonUp", "RightButtonUp")

-- Roles button handler
btnRoles:SetScript("OnClick", function()
  -- Close encounter windows if they're open
  if OGRH_EncounterFrame and OGRH_EncounterFrame:IsVisible() then
    OGRH_EncounterFrame:Hide()
  end
  if OGRH_EncounterSetupFrame and OGRH_EncounterSetupFrame:IsVisible() then
    OGRH_EncounterSetupFrame:Hide()
  end
  if OGRH_InvitesFrame and OGRH_InvitesFrame:IsVisible() then
    OGRH_InvitesFrame:Hide()
  end
  if OGRH_SRValidationFrame and OGRH_SRValidationFrame:IsVisible() then
    OGRH_SRValidationFrame:Hide()
  end
  if OGRH_AddonAuditFrame and OGRH_AddonAuditFrame:IsVisible() then
    OGRH_AddonAuditFrame:Hide()
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

-- Mark button
local markBtn = CreateFrame("Button", nil, encounterNav, "UIPanelButtonTemplate")
markBtn:SetWidth(20)
markBtn:SetHeight(20)
markBtn:SetPoint("LEFT", encounterNav, "LEFT", 0, 0)
markBtn:SetText("M")
OGRH.StyleButton(markBtn)
markBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
markBtn:SetScript("OnClick", function()
  local btn = arg1 or "LeftButton"
  
  if btn == "RightButton" then
    -- Right-click: Clear all raid marks
    local numRaidMembers = GetNumRaidMembers()
    if numRaidMembers > 0 then
      for i = 1, numRaidMembers do
        SetRaidTarget("raid"..i, 0)
      end
      if OGRH and OGRH.Msg then
        OGRH.Msg("Cleared all raid marks.")
      end
    else
      if OGRH and OGRH.Msg then
        OGRH.Msg("Not in a raid group.")
      end
    end
  else
    -- Left-click: Mark players from encounter
    if OGRH.MarkPlayersFromMainUI then
      OGRH.MarkPlayersFromMainUI()
    end
  end
end)
encounterNav.markBtn = markBtn

-- Announce button
local announceBtn = CreateFrame("Button", nil, encounterNav, "UIPanelButtonTemplate")
announceBtn:SetWidth(20)
announceBtn:SetHeight(20)
announceBtn:SetPoint("LEFT", markBtn, "RIGHT", 2, 0)
announceBtn:SetText("A")
OGRH.StyleButton(announceBtn)
announceBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
announceBtn:SetScript("OnClick", function()
  local button = arg1 or "LeftButton"
  
  -- Check authorization - must be raid lead, raid leader, or assistant
  if GetNumRaidMembers() > 0 then
    if not OGRH.CanNavigateEncounter or not OGRH.CanNavigateEncounter() then
      OGRH.Msg("Only the Raid Leader, Assistants, or Raid Admin can announce.")
      return
    end
  end
  
  if button == "RightButton" then
    -- Right-click: Announce consumes
    if not OGRH.GetCurrentEncounter then
      OGRH.Msg("Encounter management not loaded.")
      return
    end
    
    local currentRaid, currentEncounter = OGRH.GetCurrentEncounter()
    if not currentRaid or not currentEncounter then
      return -- Silently do nothing if no encounter selected
    end
    
    -- Get role configuration
    OGRH.EnsureSV()
    local roles = OGRH.SVM.GetPath("encounterMgmt.roles")
    if not roles or not roles[currentRaid] or not roles[currentRaid][currentEncounter] then
      return -- Silently do nothing if no roles configured
    end
    
    local encounterRoles = roles[currentRaid][currentEncounter]
    local column1 = encounterRoles.column1 or {}
    local column2 = encounterRoles.column2 or {}
    
    -- Find consume check role
    local consumeRole = nil
    for i = 1, table.getn(column1) do
      if column1[i].isConsumeCheck then
        consumeRole = column1[i]
        break
      end
    end
    if not consumeRole then
      for i = 1, table.getn(column2) do
        if column2[i].isConsumeCheck then
          consumeRole = column2[i]
          break
        end
      end
    end
    
    -- If no consume role found, do nothing
    if not consumeRole or not consumeRole.consumes then
      return
    end
    
    -- Check if in raid
    if GetNumRaidMembers() == 0 then
      OGRH.Msg("You must be in a raid to announce.")
      return
    end
    
    -- Build consume announcement lines
    local announceLines = {}
    local titleColor = OGRH.COLOR.HEADER or "|cFFFFD100"
    table.insert(announceLines, titleColor .. "Consumes for " .. currentEncounter .. OGRH.COLOR.RESET)
    
    for i = 1, (consumeRole.slots or 1) do
      if consumeRole.consumes[i] then
        local consumeData = consumeRole.consumes[i]
        local items = {}
        
        -- Add primary item
        if consumeData.primaryId then
          table.insert(items, consumeData.primaryId)
        end
        
        -- Add secondary item if alternate allowed
        if consumeData.allowAlternate and consumeData.secondaryId then
          table.insert(items, consumeData.secondaryId)
        end
        
        -- Build line with item links
        if table.getn(items) > 0 then
          local lineText = ""
          for j = 1, table.getn(items) do
            local itemId = items[j]
            local itemName, itemLink, quality = GetItemInfo(itemId)
            
            if j > 1 then
              lineText = lineText .. " / "
            end
            
            -- Construct chat link using AtlasLoot method
            if itemLink and itemName then
              local _, _, _, color = GetItemQualityColor(quality)
              lineText = lineText .. color .. "|H" .. itemLink .. "|h[" .. itemName .. "]|h|r"
            elseif itemName then
              lineText = lineText .. itemName
            else
              lineText = lineText .. "Item " .. itemId
            end
          end
          table.insert(announceLines, lineText)
        end
      end
    end
    
    -- Send to raid warning
    for _, line in ipairs(announceLines) do
      SendChatMessage(line, "RAID_WARNING")
    end
    
    OGRH.Msg("Consumes announced to raid warning.")
    return
  end
  
  -- Left-click: Normal announcement
  if OGRH.Announcements and OGRH.Announcements.SendEncounterAnnouncement then
    local selectedRaid, selectedEncounter = OGRH.GetCurrentEncounter()
    OGRH.Announcements.SendEncounterAnnouncement(selectedRaid, selectedEncounter)
  end
end)
announceBtn:SetScript("OnEnter", function()
  if OGRH.ShowAnnouncementTooltip then
    OGRH.ShowAnnouncementTooltip(this)
  end
end)
announceBtn:SetScript("OnLeave", function()
  GameTooltip:Hide()
end)
encounterNav.announceBtn = announceBtn

-- Previous Encounter button
local prevEncBtn = CreateFrame("Button", nil, encounterNav, "UIPanelButtonTemplate")
prevEncBtn:SetWidth(20)
prevEncBtn:SetHeight(20)
prevEncBtn:SetPoint("LEFT", announceBtn, "RIGHT", 2, 0)
prevEncBtn:SetText("<")
OGRH.StyleButton(prevEncBtn)
prevEncBtn:SetScript("OnClick", function()
  if OGRH.NavigateToPreviousEncounter then
    OGRH.NavigateToPreviousEncounter()
  end
end)
encounterNav.prevEncBtn = prevEncBtn

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
encounterBtn:SetPoint("LEFT", prevEncBtn, "RIGHT", 2, 0)
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
    
    OGRH.CloseAllWindows("OGRH_EncounterFrame")
    
    if OGRH.OpenEncounterPlanning then
      OGRH.OpenEncounterPlanning()
    end
  end
end)
encounterNav.encounterBtn = encounterBtn

-- Store reference for external access
OGRH.encounterNav = encounterNav

-- ============================================
-- ENCOUNTER NAVIGATION FUNCTIONS
-- ============================================

function OGRH.NavigateToPreviousEncounter()
  -- Check authorization - must be raid lead, assistant, or designated raid admin
  if not OGRH.CanNavigateEncounter or not OGRH.CanNavigateEncounter() then
    OGRH.Msg("Only the Raid Leader, Assistants, or Raid Admin can change the selected encounter.")
    return
  end
  
  -- Get current encounter from main UI selection
  local raidName, currentEncounter = OGRH.GetCurrentEncounter()
  
  if not raidName or not currentEncounter then
    return
  end
  
  local raid = OGRH.FindRaidByName(raidName)
  if raid and raid.encounters then
    local encounters = {}
    for i = 1, table.getn(raid.encounters) do
      table.insert(encounters, raid.encounters[i].name)
    end
    
    for i = 1, table.getn(encounters) do
      if encounters[i] == currentEncounter and i > 1 then
        -- Update encounter using centralized setter (triggers REALTIME sync)
        OGRH.SetCurrentEncounter(raidName, encounters[i - 1])
        
        -- Update UI
        OGRH.UpdateEncounterNavButton()
        
        -- Refresh Encounter Planning window if it's open
        if OGRH_EncounterFrame and OGRH_EncounterFrame:IsVisible() then
          if OGRH_EncounterFrame.RefreshRoleContainers then
            OGRH_EncounterFrame.RefreshRoleContainers()
          end
          if OGRH_EncounterFrame.UpdateAnnouncementBuilder then
            OGRH_EncounterFrame.UpdateAnnouncementBuilder()
          end
        end
        
        -- Update consume monitor if enabled
        if OGRH.ShowConsumeMonitor then
          OGRH.ShowConsumeMonitor()
        end
        
        break
      end
    end
  end
end

function OGRH.NavigateToNextEncounter()
  -- Check authorization - must be raid lead, assistant, or designated raid admin
  if not OGRH.CanNavigateEncounter or not OGRH.CanNavigateEncounter() then
    OGRH.Msg("Only the Raid Leader, Assistants, or Raid Admin can change the selected encounter.")
    return
  end
  
  -- Get current encounter from main UI selection
  local raidName, currentEncounter = OGRH.GetCurrentEncounter()
  
  if not raidName or not currentEncounter then
    return
  end
  
  local raid = OGRH.FindRaidByName(raidName)
  if raid and raid.encounters then
    local encounters = {}
    for i = 1, table.getn(raid.encounters) do
      table.insert(encounters, raid.encounters[i].name)
    end
    
    for i = 1, table.getn(encounters) do
      if encounters[i] == currentEncounter and i < table.getn(encounters) then
        -- Update encounter using centralized setter (triggers REALTIME sync)
        OGRH.SetCurrentEncounter(raidName, encounters[i + 1])
        
        -- Update UI
        OGRH.UpdateEncounterNavButton()
        
        -- Refresh Encounter Planning window if it's open
        if OGRH_EncounterFrame and OGRH_EncounterFrame:IsVisible() then
          if OGRH_EncounterFrame.RefreshRoleContainers then
            OGRH_EncounterFrame.RefreshRoleContainers()
          end
          if OGRH_EncounterFrame.UpdateAnnouncementBuilder then
            OGRH_EncounterFrame.UpdateAnnouncementBuilder()
          end
        end
        
        -- Update consume monitor if enabled
        if OGRH.ShowConsumeMonitor then
          OGRH.ShowConsumeMonitor()
        end
        
        break
      end
    end
  end
end

-- ============================================
-- UPDATE ENCOUNTER NAVIGATION BUTTON
-- ============================================

function OGRH.UpdateEncounterNavButton()
  if not OGRH.encounterNav then return end
  
  local btn = OGRH.encounterNav.encounterBtn
  local prevBtn = OGRH.encounterNav.prevEncBtn
  local nextBtn = OGRH.encounterNav.nextEncBtn
  
  -- Get raid and encounter from SVM (active schema)
  local raidName = OGRH.SVM.Get("ui", "selectedRaid")
  local encounterName = OGRH.SVM.Get("ui", "selectedEncounter")
  
  if OGRH.MainUI.State.debug then
    OGRH.Msg("|cff66ccff[RH][DEBUG]|r UpdateEncounterNavButton called: raid=" .. tostring(raidName) .. ", encounter=" .. tostring(encounterName))
  end
  
  -- Load modules for the selected encounter (main UI only)
  if OGRH.LoadModulesForRole and OGRH.UnloadAllModules and raidName and encounterName then
    -- Get raids array to find the encounter's roles
    local raids = OGRH.SVM.GetPath("encounterMgmt.raids")
    
    if OGRH.MainUI.State.debug then
      OGRH.Msg("|cff66ccff[RH][DEBUG]|r raids = " .. tostring(raids) .. " (count: " .. (raids and table.getn(raids) or 0) .. ")")
    end
    
    if raids then
      -- Find raid and encounter indices
      local raidIdx, encIdx
      for i = 1, table.getn(raids) do
        if raids[i].name == raidName then
          raidIdx = i
          if raids[i].encounters then
            for j = 1, table.getn(raids[i].encounters) do
              if raids[i].encounters[j].name == encounterName then
                encIdx = j
                break
              end
            end
          end
          break
        end
      end
      
      if OGRH.MainUI.State.debug then
        OGRH.Msg(string.format("|cff66ccff[RH][DEBUG]|r Found indices: raidIdx=%s, encIdx=%s", tostring(raidIdx), tostring(encIdx)))
      end
      
      -- Get roles from the encounter
      if raidIdx and encIdx then
        local rolesPath = string.format("encounterMgmt.raids.%d.encounters.%d.roles", raidIdx, encIdx)
        local rolesData = OGRH.SVM.GetPath(rolesPath)
        
        if OGRH.MainUI.State.debug then
          OGRH.Msg(string.format("|cff66ccff[RH][DEBUG]|r rolesData = %s", tostring(rolesData)))
        end
        
        if rolesData then
          if OGRH.MainUI.State.debug then
            OGRH.Msg(string.format("|cff66ccff[RH][DEBUG]|r roles array count: %d", table.getn(rolesData)))
          end
          
          -- Collect all modules from custom module roles
          -- Roles are stored as a flat array with column field inside each role
          local allModules = {}
          for i = 1, table.getn(rolesData) do
            local role = rolesData[i]
            if OGRH.MainUI.State.debug then
              OGRH.Msg(string.format("|cff66ccff[RH][DEBUG]|r Role %d: isCustomModule=%s, modules=%s, column=%s", 
                i, tostring(role.isCustomModule), tostring(role.modules), tostring(role.column)))
            end
            if role.isCustomModule and role.modules then
              if OGRH.MainUI.State.debug then
                OGRH.Msg(string.format("|cff66ccff[RH][DEBUG]|r Found custom module role with %d modules", table.getn(role.modules)))
              end
              for _, moduleId in ipairs(role.modules) do
                if OGRH.MainUI.State.debug then
                  OGRH.Msg(string.format("|cff66ccff[RH][DEBUG]|r Adding module: %s", tostring(moduleId)))
                end
                table.insert(allModules, moduleId)
              end
            end
          end
          
          -- Load the modules
          if table.getn(allModules) > 0 then
            OGRH.Msg(string.format("|cff00ff00[RH-MainUI]|r Loading %d custom modules for encounter", table.getn(allModules)))
            OGRH.LoadModulesForRole(allModules)
          else
            if OGRH.MainUI.State.debug then
              OGRH.Msg("|cff00ccff[RH-MainUI-DEBUG]|r No modules found, unloading all")
            end
            OGRH.UnloadAllModules()
          end
        else
          OGRH.UnloadAllModules()
        end
      else
        OGRH.UnloadAllModules()
      end
    else
      OGRH.UnloadAllModules()
    end
  end
  
  -- Get Active Raid info for display
  local activeRaid = OGRH.GetActiveRaid and OGRH.GetActiveRaid()
  local activeRaidName = ""
  if activeRaid and activeRaid.displayName then
    activeRaidName = activeRaid.displayName
  end
  
  if not raidName then
    if activeRaidName ~= "" then
      btn:SetText(activeRaidName)
    else
      btn:SetText("Select Raid")
    end
    prevBtn:Disable()
    nextBtn:Disable()
    return
  end
  
  -- Always show encounter name if one is selected
  if encounterName then
    local displayName = encounterName
    if string.len(displayName) > 15 then
      displayName = string.sub(displayName, 1, 12) .. "..."
    end
    btn:SetText(displayName)
  elseif activeRaidName ~= "" then
    -- Show Active Raid name when no encounter selected
    btn:SetText(activeRaidName)
  elseif raidName then
    btn:SetText("Select Encounter")
  else
    btn:SetText("Select Raid")
  end
  
  -- Enable/disable prev/next buttons
  local raid = OGRH.FindRaidByName(raidName)
  if raid and raid.encounters then
    local encounters = {}
    for i = 1, table.getn(raid.encounters) do
      table.insert(encounters, raid.encounters[i].name)
    end
    
    local currentIndex = nil
    for i = 1, table.getn(encounters) do
      if encounters[i] == encounterName then
        currentIndex = i
        break
      end
    end
    
    if currentIndex then
      if currentIndex > 1 then
        prevBtn:Enable()
      else
        prevBtn:Disable()
      end
      
      if currentIndex < table.getn(encounters) then
        nextBtn:Enable()
      else
        nextBtn:Disable()
      end
    else
      prevBtn:Disable()
      nextBtn:Disable()
    end
  else
    prevBtn:Disable()
    nextBtn:Disable()
  end
end

-- ============================================
-- UI STATE MANAGEMENT
-- ============================================

local function applyLocked(lock)
  if lock then
    btnLock:SetText("|cff00ff00L|r")  -- Green when locked
  else
    btnLock:SetText("|cffffff00L|r")  -- Yellow when unlocked
  end
end
btnLock:SetScript("OnClick", function() ensureSV(); local locked = not OGRH.SVM.Get("ui", "locked"); OGRH.SVM.Set("ui", "locked", locked); applyLocked(locked) end)

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
        local newValue = not OGRH.SVM.Get("allowRemoteReadyCheck")
        OGRH.SVM.Set("allowRemoteReadyCheck", nil, newValue)
        
        -- Update button text
        if newValue then
          fs:SetText("|cff00ff00Allow Remote Readycheck|r")
        else
          fs:SetText("|cffff0000Allow Remote Readycheck|r")
        end
        
        if OGRH and OGRH.Msg then
          if newValue then
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
    if OGRH.SVM.Get("allowRemoteReadyCheck") then
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
OGRH.adminButton = adminBtn
-- Backward compatibility alias
OGRH.syncButton = adminBtn

local function restoreMain()
  ensureSV()
  local point = OGRH.SVM.Get("ui", "point")
  local relPoint = OGRH.SVM.Get("ui", "relPoint")
  local x = OGRH.SVM.Get("ui", "x")
  local y = OGRH.SVM.Get("ui", "y")
  if point and x and y then Main:ClearAllPoints(); Main:SetPoint(point, UIParent, relPoint or point, x, y) end
  applyLocked(OGRH.SVM.Get("ui", "locked"))
  
  -- Initialize raid lead system
  if OGRH.InitRaidLead then
    OGRH.InitRaidLead()
  end
  
  -- Update raid lead UI state
  if OGRH.UpdateRaidAdminUI then
    OGRH.UpdateRaidAdminUI()
  end
  
  -- Update encounter nav button with saved state
  if OGRH.UpdateEncounterNavButton then
    OGRH.UpdateEncounterNavButton()
  end
  
  -- Show consume monitor if enabled and encounter has consumes
  if OGRH.ShowConsumeMonitor then
    OGRH.ShowConsumeMonitor()
  end
  
  -- Check if window should be hidden
  if OGRH.SVM.Get("ui", "hidden") then
    Main:Hide()
  end
end
local _loader = CreateFrame("Frame"); _loader:RegisterEvent("VARIABLES_LOADED"); _loader:SetScript("OnEvent", function() restoreMain() end)

SlashCmdList[string.upper(OGRH.CMD)] = function(m)
  local fullMsg = OGRH.Trim(m or "")
  local sub = string.lower(fullMsg)
  
  if sub=="sand" then 
    if OGRH.SetTradeType and OGRH.ExecuteTrade then 
      OGRH.SetTradeType("sand")
      OGRH.ExecuteTrade()
    else 
      OGRH.Msg("Trade helper not loaded.") 
    end
  elseif string.find(sub, "^shuffle") then
    if OGRH.ShuffleRaid then
      -- Extract number from command (e.g., "shuffle 50")
      local _, _, numStr = string.find(fullMsg, "^%s*%a+%s+(%d+)")
      local delayMs = tonumber(numStr)
      OGRH.ShuffleRaid(delayMs)
    else
      OGRH.Msg("Shuffle function not loaded.")
    end
  elseif string.find(sub, "^sortspeed") then
    -- Extract number from command (e.g., "sortspeed 50")
    local _, _, numStr = string.find(fullMsg, "^%s*%a+%s+(%d+)")
    local speedMs = tonumber(numStr)
    if speedMs then
      OGRH.SVM.Set("sorting", "speed", speedMs)
      OGRH.Msg("Auto-sort speed set to " .. speedMs .. "ms between moves")
    else
      local currentSpeed = OGRH.SVM.Get("sorting", "speed")
      if currentSpeed then
        OGRH.Msg("Current auto-sort speed: " .. currentSpeed .. "ms")
      else
        OGRH.Msg("Current auto-sort speed: 250ms (default)")
      end
    end
  -- Phase 1 Debug Commands
  elseif sub == "debug messages" or sub == "messages" then
    if OGRH.DebugPrintMessageTypes then
      OGRH.DebugPrintMessageTypes()
    else
      OGRH.Msg("Message types not loaded.")
    end
  elseif sub == "debug permissions" or sub == "permissions" then
    if OGRH.Permissions and OGRH.Permissions.DebugPrintRaidPermissions then
      OGRH.Permissions.DebugPrintRaidPermissions()
    else
      OGRH.Msg("Permissions system not loaded.")
    end
  elseif sub == "debug denials" or sub == "denials" then
    if OGRH.Permissions and OGRH.Permissions.DebugPrintDenials then
      OGRH.Permissions.DebugPrintDenials()
    else
      OGRH.Msg("Permissions system not loaded.")
    end
  elseif sub == "debug version" or sub == "version" then
    if OGRH.Versioning and OGRH.Versioning.DebugPrintState then
      OGRH.Versioning.DebugPrintState()
    else
      OGRH.Msg("Versioning system not loaded.")
    end
  elseif sub == "debug changes" or sub == "changes" then
    if OGRH.Versioning and OGRH.Versioning.DebugPrintChanges then
      OGRH.Versioning.DebugPrintChanges()
    else
      OGRH.Msg("Versioning system not loaded.")
    end
  elseif sub == "debug handlers" or sub == "handlers" then
    if OGRH.MessageRouter and OGRH.MessageRouter.DebugPrintHandlers then
      OGRH.MessageRouter.DebugPrintHandlers()
    else
      OGRH.Msg("Message router not loaded.")
    end
  -- Debug Commands (centralized under /ogrh debug [option])
  elseif string.find(sub, "^debug ") then
    local _, _, debugOption = string.find(sub, "^debug%s+(.+)")
    if debugOption == "help" then
      -- Show all debug options and their current state
      OGRH.Msg("|cff66ccff[RH][DEBUG]|r Available debug options:")
      OGRH.Msg("  |cff00ccff/ogrh debug sync|r - Toggle SyncIntegrity verbose messages " ..
        (OGRH.SyncIntegrity and (OGRH.SyncIntegrity.State.debug and "|cff00ff00(ON)|r" or "|cffff0000(OFF)|r") or "|cff888888(not loaded)|r"))
      OGRH.Msg("  |cff00ccff/ogrh debug ui|r - Toggle MainUI debug messages " ..
        (OGRH.MainUI and (OGRH.MainUI.State.debug and "|cff00ff00(ON)|r" or "|cffff0000(OFF)|r") or "|cff888888(not loaded)|r"))
      OGRH.Msg("  |cff00ccff/ogrh debug svm-read|r - Toggle SVM read operations " ..
        (OGRH.SVM and (OGRH.SVM.SyncConfig.debugRead and "|cff00ff00(ON)|r" or "|cffff0000(OFF)|r") or "|cff888888(not loaded)|r"))
      OGRH.Msg("  |cff00ccff/ogrh debug svm-write|r - Toggle SVM write operations " ..
        (OGRH.SVM and (OGRH.SVM.SyncConfig.debugWrite and "|cff00ff00(ON)|r" or "|cffff0000(OFF)|r") or "|cff888888(not loaded)|r"))
      OGRH.Msg("  |cff00ccff/ogrh debug consumes|r - Toggle ConsumesTracking debug messages " ..
        (OGRH.ConsumesTracking and (OGRH.ConsumesTracking.State.debug and "|cff00ff00(ON)|r" or "|cffff0000(OFF)|r") or "|cff888888(not loaded)|r"))
      OGRH.Msg("|cff66ccff[RH][DEBUG]|r Use /ogrh debug [option] to toggle")
    elseif debugOption == "sync" then
      if OGRH.SyncIntegrity then
        OGRH.SyncIntegrity.State.debug = not OGRH.SyncIntegrity.State.debug
        local status = OGRH.SyncIntegrity.State.debug and "|cff00ff00ON|r" or "|cffff0000OFF|r"
        OGRH.Msg("Sync debug: " .. status)
      else
        OGRH.Msg("SyncIntegrity not loaded.")
      end
    elseif debugOption == "ui" then
      if OGRH.MainUI then
        OGRH.MainUI.State.debug = not OGRH.MainUI.State.debug
        local status = OGRH.MainUI.State.debug and "|cff00ff00ON|r" or "|cffff0000OFF|r"
        OGRH.Msg("MainUI debug: " .. status)
      else
        OGRH.Msg("MainUI not loaded.")
      end
    elseif debugOption == "svm-read" then
      if OGRH.SVM and OGRH.SVM.SyncConfig then
        OGRH.SVM.SyncConfig.debugRead = not OGRH.SVM.SyncConfig.debugRead
        local status = OGRH.SVM.SyncConfig.debugRead and "|cff00ff00ON|r" or "|cffff0000OFF|r"
        OGRH.Msg("SVM read debug: " .. status)
      else
        OGRH.Msg("SavedVariablesManager not loaded.")
      end
    elseif debugOption == "svm-write" then
      if OGRH.SVM and OGRH.SVM.SyncConfig then
        OGRH.SVM.SyncConfig.debugWrite = not OGRH.SVM.SyncConfig.debugWrite
        local status = OGRH.SVM.SyncConfig.debugWrite and "|cff00ff00ON|r" or "|cffff0000OFF|r"
        OGRH.Msg("SVM write debug: " .. status)
      else
        OGRH.Msg("SavedVariablesManager not loaded.")
      end
    elseif debugOption == "consumes" then
      if OGRH.ConsumesTracking then
        OGRH.ConsumesTracking.State.debug = not OGRH.ConsumesTracking.State.debug
        local status = OGRH.ConsumesTracking.State.debug and "|cff00ff00ON|r" or "|cffff0000OFF|r"
        OGRH.Msg("ConsumesTracking debug: " .. status)
      else
        OGRH.Msg("ConsumesTracking not loaded.")
      end
    else
      OGRH.Msg("|cffff0000[RH]|r Unknown debug option: " .. debugOption)
      OGRH.Msg("Use |cff00ccff/ogrh debug help|r to see available options")
    end
  elseif sub == "admin take" or sub == "takeadmin" then
    if OGRH.RequestAdminRole then
      OGRH.RequestAdminRole()
    else
      OGRH.Msg("Permission system not loaded.")
    end
  elseif sub == "sa" then
    if OGRH.SetSessionAdmin then
      OGRH.SetSessionAdmin()
    else
      OGRH.Msg("Permission system not loaded.")
    end
  -- Migration Commands (Phase 1 - SavedVariables v2)
  -- Check force FIRST before regular create (order matters for string matching)
  elseif sub == "migration create force" or sub == "migrate force" then
    if OGRH.Migration and OGRH.Migration.MigrateToV2 then
      OGRH.Migration.MigrateToV2(true)
    else
      OGRH.Msg("Migration system not loaded.")
    end
  elseif sub == "migration create" or sub == "migrate" then
    if OGRH.Migration and OGRH.Migration.MigrateToV2 then
      OGRH.Migration.MigrateToV2(false)
    else
      OGRH.Msg("Migration system not loaded.")
    end
  elseif sub == "migration validate" then
    if OGRH.Migration and OGRH.Migration.ValidateV2 then
      OGRH.Migration.ValidateV2()
    else
      OGRH.Msg("Migration system not loaded.")
    end
  elseif sub == "migration cutover confirm" then
    if OGRH.Migration and OGRH.Migration.CutoverToV2 then
      OGRH.Migration.CutoverToV2()
    else
      OGRH.Msg("Migration system not loaded.")
    end
  elseif sub == "migration rollback" then
    if OGRH.Migration and OGRH.Migration.RollbackFromV2 then
      OGRH.Migration.RollbackFromV2()
    else
      OGRH.Msg("Migration system not loaded.")
    end
  elseif sub == "migration purge" then
    if OGRH.Migration and OGRH.Migration.PurgeV1Data then
      OGRH.Migration.PurgeV1Data(false)
    else
      OGRH.Msg("Migration system not loaded.")
    end
  elseif string.find(sub, "^migration comp raid") then
    local _, _, raidName = string.find(fullMsg, "^%s*migration%s+comp%s+raid%s+(.+)$")
    if not raidName or raidName == "" then
      OGRH.Msg("Usage: /ogrh migration comp raid <raidname>")
      OGRH.Msg("Example: /ogrh migration comp raid MC")
    else
      if OGRH.Migration and OGRH.Migration.CompareRaid then
        OGRH.Migration.CompareRaid(raidName)
      else
        OGRH.Msg("Migration system not loaded.")
      end
    end
  elseif string.find(fullMsg, "^%s*migration%s+comp%s+enc") then
    -- Extract raid/encounter from "migration comp enc RaidName/EncounterName"
    local _, _, fullPath = string.find(fullMsg, "^%s*migration%s+comp%s+enc%s+(.+)$")
    if not fullPath or fullPath == "" then
      OGRH.Msg("Usage: /ogrh migration comp enc <raidname>/<encountername>")
      OGRH.Msg("Example: /ogrh migration comp enc BWL/Razorgore")
    else
      -- Split by / delimiter
      local slashPos = string.find(fullPath, "/")
      if not slashPos then
        OGRH.Msg("ERROR: Missing '/' delimiter. Use format: <raidname>/<encountername>")
        OGRH.Msg("Example: /ogrh migration comp enc BWL/Razorgore")
      else
        local raidName = string.sub(fullPath, 1, slashPos - 1)
        local encounterName = string.sub(fullPath, slashPos + 1)
        
        -- Trim whitespace
        raidName = string.gsub(raidName, "^%s*(.-)%s*$", "%1")
        encounterName = string.gsub(encounterName, "^%s*(.-)%s*$", "%1")
        
        if raidName == "" or encounterName == "" then
          OGRH.Msg("ERROR: Both raid name and encounter name required")
          OGRH.Msg("Example: /ogrh migration comp enc BWL/Razorgore")
        else
          if OGRH.Migration and OGRH.Migration.CompareEncounter then
            OGRH.Migration.CompareEncounter(raidName, encounterName)
          else
            OGRH.Msg("Migration system not loaded.")
          end
        end
      end
    end
  elseif string.find(fullMsg, "^%s*migration%s+comp%s+roles") then
    -- Extract raid/encounter/role from "migration comp roles RaidName/EncounterName/RoleID"
    local _, _, fullPath = string.find(fullMsg, "^%s*migration%s+comp%s+roles%s+(.+)$")
    if not fullPath or fullPath == "" then
      OGRH.Msg("Usage: /ogrh migration comp roles <raid>/<encounter>/<role>")
      OGRH.Msg("Example: /ogrh migration comp roles BWL/Vael/R1")
    else
      -- Split by / delimiter (Lua 5.0 compatible)
      local slash1 = string.find(fullPath, "/")
      if not slash1 then
        OGRH.Msg("ERROR: Format must be <raid>/<encounter>/<role>")
        OGRH.Msg("Example: /ogrh migration comp roles BWL/Vael/R1")
      else
        local slash2 = string.find(fullPath, "/", slash1 + 1)
        if not slash2 then
          OGRH.Msg("ERROR: Format must be <raid>/<encounter>/<role>")
          OGRH.Msg("Example: /ogrh migration comp roles BWL/Vael/R1")
        else
          local raidName = string.sub(fullPath, 1, slash1 - 1)
          local encounterName = string.sub(fullPath, slash1 + 1, slash2 - 1)
          local roleId = string.sub(fullPath, slash2 + 1)
          
          -- Trim whitespace
          raidName = string.gsub(raidName, "^%s*(.-)%s*$", "%1")
          encounterName = string.gsub(encounterName, "^%s*(.-)%s*$", "%1")
          roleId = string.gsub(roleId, "^%s*(.-)%s*$", "%1")
          
          if raidName == "" or encounterName == "" or roleId == "" then
            OGRH.Msg("ERROR: All parts required: <raid>/<encounter>/<role>")
            OGRH.Msg("Example: /ogrh migration comp roles BWL/Vael/R1")
          else
            if OGRH.Migration and OGRH.Migration.CompareRole then
              OGRH.Migration.CompareRole(raidName, encounterName, roleId)
            else
              OGRH.Msg("Migration system not loaded.")
            end
          end
        end
      end
    end
  elseif string.find(fullMsg, "^%s*migration%s+comp%s+class") then
    -- Extract raid/encounter/role from "migration comp class RaidName/EncounterName/RoleID"
    local _, _, fullPath = string.find(fullMsg, "^%s*migration%s+comp%s+class%s+(.+)$")
    if not fullPath or fullPath == "" then
      OGRH.Msg("Usage: /ogrh migration comp class <raid>/<encounter>/<role>")
      OGRH.Msg("Example: /ogrh migration comp class BWL/Vael/R1")
    else
      -- Split by / delimiter (Lua 5.0 compatible)
      local slash1 = string.find(fullPath, "/")
      if not slash1 then
        OGRH.Msg("ERROR: Format must be <raid>/<encounter>/<role>")
        OGRH.Msg("Example: /ogrh migration comp class BWL/Vael/R1")
      else
        local slash2 = string.find(fullPath, "/", slash1 + 1)
        if not slash2 then
          OGRH.Msg("ERROR: Format must be <raid>/<encounter>/<role>")
          OGRH.Msg("Example: /ogrh migration comp class BWL/Vael/R1")
        else
          local raidName = string.sub(fullPath, 1, slash1 - 1)
          local encounterName = string.sub(fullPath, slash1 + 1, slash2 - 1)
          local roleId = string.sub(fullPath, slash2 + 1)
          
          -- Trim whitespace
          raidName = string.gsub(raidName, "^%s*(.-)%s*$", "%1")
          encounterName = string.gsub(encounterName, "^%s*(.-)%s*$", "%1")
          roleId = string.gsub(roleId, "^%s*(.-)%s*$", "%1")
          
          if raidName == "" or encounterName == "" or roleId == "" then
            OGRH.Msg("ERROR: All parts required: <raid>/<encounter>/<role>")
            OGRH.Msg("Example: /ogrh migration comp class BWL/Vael/R1")
          else
            if OGRH.Migration and OGRH.Migration.CompareClassPriority then
              OGRH.Migration.CompareClassPriority(raidName, encounterName, roleId)
            else
              OGRH.Msg("Migration system not loaded.")
            end
          end
        end
      end
    end
  elseif string.find(fullMsg, "^%s*migration%s+comp%s+announce") then
    local _, _, fullPath = string.find(fullMsg, "^%s*migration%s+comp%s+announce%s+(.+)$")
    if fullPath then
      -- Manual "/" parsing for Lua 5.0 compatibility
      local firstSlashPos = string.find(fullPath, "/")
      if firstSlashPos then
        local raidName = string.sub(fullPath, 1, firstSlashPos - 1)
        local encounterName = string.sub(fullPath, firstSlashPos + 1)
        
        if raidName and encounterName and string.len(raidName) > 0 and string.len(encounterName) > 0 then
          if OGRH.Migration and OGRH.Migration.CompareAnnouncements then
            OGRH.Migration.CompareAnnouncements(raidName, encounterName)
          else
            OGRH.Msg("|cffff0000[OGRH]|r Migration system not loaded")
          end
        else
          OGRH.Msg("|cffff0000[OGRH]|r Invalid format. Use: /ogrh migration comp announce <raid>/<encounter>")
        end
      else
        OGRH.Msg("|cffff0000[OGRH]|r Invalid format. Use: /ogrh migration comp announce <raid>/<encounter>")
      end
    else
      OGRH.Msg("|cffff0000[OGRH]|r Usage: /ogrh migration comp announce <raid>/<encounter>")
    end
  elseif sub == "migration comp recruitment" or sub == "migration comp recruit" then
    if OGRH.Migration and OGRH.Migration.CompareRecruitment then
      OGRH.Migration.CompareRecruitment()
    else
      OGRH.Msg("Migration system not loaded.")
    end
  elseif sub == "migration comp consumes" or sub == "migration comp consumestracking" then
    if OGRH.Migration and OGRH.Migration.CompareConsumesTracking then
      OGRH.Migration.CompareConsumesTracking()
    else
      OGRH.Msg("Migration system not loaded.")
    end
  elseif sub == "migration comp baseconsumes" then
    if OGRH.Migration and OGRH.Migration.CompareBaseConsumes then
      OGRH.Migration.CompareBaseConsumes()
    else
      OGRH.Msg("Migration system not loaded.")
    end
  elseif sub == "migration comp trade" then
    if OGRH.Migration and OGRH.Migration.CompareTrade then
      OGRH.Migration.CompareTrade()
    else
      OGRH.Msg("Migration system not loaded.")
    end
  elseif sub == "migration comp promotes" then
    if OGRH.Migration and OGRH.Migration.ComparePromotes then
      OGRH.Migration.ComparePromotes()
    else
      OGRH.Msg("Migration system not loaded.")
    end
  elseif sub == "migration comp roster" then
    if OGRH.Migration and OGRH.Migration.CompareRoster then
      OGRH.Migration.CompareRoster()
    else
      OGRH.Msg("Migration system not loaded.")
    end
  elseif sub == "migration comp core" then
    if OGRH.Migration and OGRH.Migration.CompareCore then
      OGRH.Migration.CompareCore()
    else
      OGRH.Msg("Migration system not loaded.")
    end
  elseif sub == "migration comp messagerouter" or sub == "migration comp router" then
    if OGRH.Migration and OGRH.Migration.CompareMessageRouter then
      OGRH.Migration.CompareMessageRouter()
    else
      OGRH.Msg("Migration system not loaded.")
    end
  elseif sub == "migration comp permissions" or sub == "migration comp perms" then
    if OGRH.Migration and OGRH.Migration.ComparePermissions then
      OGRH.Migration.ComparePermissions()
    else
      OGRH.Msg("Migration system not loaded.")
    end
  elseif sub == "migration comp versioning" or sub == "migration comp version" then
    if OGRH.Migration and OGRH.Migration.CompareVersioning then
      OGRH.Migration.CompareVersioning()
    else
      OGRH.Msg("Migration system not loaded.")
    end
  elseif sub == "migration help" then
    OGRH.Msg("|cff00ff00[OGRH Migration]|r Available commands:")
    OGRH.Msg("  /ogrh migration create - Create v2 schema")
    OGRH.Msg("  /ogrh migration validate - Compare v1 vs v2")
    OGRH.Msg("  /ogrh migration cutover confirm - Switch to v2")
    OGRH.Msg("  /ogrh migration rollback - Revert to v1")
    OGRH.Msg("  /ogrh migration purge - Remove v1 data (keeps only v2)")
    OGRH.Msg(" ")
    OGRH.Msg("|cff00ff00Encounter Comparisons:|r")
    OGRH.Msg("  /ogrh migration comp raid <name> - Compare raid")
    OGRH.Msg("  /ogrh migration comp enc <raid>/<encounter> - Compare encounter")
    OGRH.Msg("  /ogrh migration comp roles <raid>/<enc>/<role> - Compare role data")
    OGRH.Msg("  /ogrh migration comp class <raid>/<enc>/<role> - Compare class priority")
    OGRH.Msg("  /ogrh migration comp announce <raid>/<encounter> - Compare announcements")
    OGRH.Msg(" ")
    OGRH.Msg("|cff00ff00Component Comparisons:|r")
    OGRH.Msg("  /ogrh migration comp recruitment - Compare recruitment settings")
    OGRH.Msg("  /ogrh migration comp consumes - Compare consumes tracking")
    OGRH.Msg("  /ogrh migration comp promotes - Compare auto-promotes list")
    OGRH.Msg("  /ogrh migration comp roster - Compare roster management")
    OGRH.Msg("  /ogrh migration comp core - Compare core settings")
    OGRH.Msg("  /ogrh migration comp messagerouter - Compare message router state")
    OGRH.Msg("  /ogrh migration comp permissions - Compare permissions data")
    OGRH.Msg("  /ogrh migration comp versioning - Compare versioning data")
  -- Chat Window Cleanup Command
  elseif sub == "chat clean" or sub == "chatclean" then
    if OGRH._ogrhChatFrame and OGRH._ogrhChatFrameIndex then
      local frameIndex = OGRH._ogrhChatFrameIndex
      
      -- Remove all channels using the correct API
      local channels = {GetChatWindowChannels(frameIndex)}
      for i = 1, table.getn(channels), 2 do
        local channelName = channels[i]
        if channelName then
          RemoveChatWindowChannel(frameIndex, channelName)
        end
      end
      
      -- Remove all message groups using the correct API
      local messageGroups = {
        "SAY", "YELL", "EMOTE",
        "PARTY", "RAID", "GUILD", "OFFICER",
        "WHISPER",
        "CHANNEL",
        "SYSTEM"
      }
      
      for i = 1, table.getn(messageGroups) do
        RemoveChatWindowMessages(frameIndex, messageGroups[i])
      end
      
      OGRH.Msg("Cleaned OGRH chat window (ChatFrame" .. frameIndex .. ") - removed all channels and message types")
    else
      OGRH.Msg("|cffFF0000[OGRH]|r OGRH chat window not found. Run /ogrh chatwindow first.")
    end
  -- Chat Window Test
  elseif sub == "chatwindow" or sub == "chat window" or sub == "chat test" then
    -- Detect pfUI
    local pfUIDetected = pfUI ~= nil
    if pfUIDetected then
      DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[OGRH]|r pfUI detected - keeping window docked")
    end
    
    -- Find or create OGRH chat window
    local ogrh_frame = nil
    local frameIndex = nil
    
    -- Search existing chat frames by checking their tab text AND if they're actually shown/active
    for i = 1, NUM_CHAT_WINDOWS do
      local frame = getglobal("ChatFrame" .. i)
      if frame then
        local tab = getglobal("ChatFrame" .. i .. "Tab")
        if tab then
          local tabText = tab:GetText()
          -- Check if this is OGRH AND the frame is actually shown/visible (not a zombie)
          if tabText and tabText == "OGRH" and frame:IsShown() then
            ogrh_frame = frame
            frameIndex = i
            break
          elseif tabText and tabText == "OGRH" and not frame:IsShown() then
            -- Found zombie frame - log it but keep searching
            DEFAULT_CHAT_FRAME:AddMessage("|cffFFFF00[OGRH]|r Found hidden OGRH window (ChatFrame" .. i .. ") - ignoring zombie frame")
          end
        end
      end
    end
    
    -- Create if doesn't exist
    if not ogrh_frame then
      ogrh_frame = FCF_OpenNewWindow("OGRH")
      if ogrh_frame then
        -- Find the index of the newly created frame
        for i = 1, NUM_CHAT_WINDOWS do
          if getglobal("ChatFrame" .. i) == ogrh_frame then
            frameIndex = i
            break
          end
        end
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[OGRH]|r Created new OGRH chat window (ChatFrame" .. (frameIndex or "?") .. ")")
        
        -- If pfUI detected, trigger a refresh first so pfUI knows about the new window
        if pfUIDetected and pfUI.chat and pfUI.chat.RefreshChat then
          pfUI.chat.RefreshChat()
          DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[OGRH]|r Refreshed pfUI chat layout")
        end
        
        -- Remove all channels using the correct API
        if frameIndex then
          local channels = {GetChatWindowChannels(frameIndex)}
          for i = 1, table.getn(channels), 2 do
            local channelName = channels[i]
            if channelName then
              RemoveChatWindowChannel(frameIndex, channelName)
            end
          end
        end
        
        -- Remove all message groups using the correct API
        local messageGroups = {
          "SAY", "YELL", "EMOTE",
          "PARTY", "RAID", "GUILD", "OFFICER",
          "WHISPER",
          "CHANNEL",
          "SYSTEM"
        }
        
        if frameIndex then
          for i = 1, table.getn(messageGroups) do
            RemoveChatWindowMessages(frameIndex, messageGroups[i])
          end
        end
        
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[OGRH]|r Removed channels and message types - OGRH-only window")
      else
        OGRH.Msg("|cffFF0000[OGRH]|r Failed to create chat window")
        return
      end
    else
      DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[OGRH]|r Found existing OGRH chat window (ChatFrame" .. (frameIndex or "?") .. ")")
    end
    
    -- Store frame reference and index globally for later access
    OGRH._ogrhChatFrame = ogrh_frame
    OGRH._ogrhChatFrameIndex = frameIndex
    
    -- Test it
    if ogrh_frame then
      ogrh_frame:AddMessage("|cff00ff00[OGRH]|r Dedicated chat window test successful!", 1, 1, 1)
      ogrh_frame:AddMessage("|cff00ff00[OGRH]|r All addon messages can be directed here.", 1, 1, 1)
      if pfUIDetected then
        ogrh_frame:AddMessage("|cff00ff00[OGRH]|r pfUI detected - window stays docked", 1, 1, 1)
      end
    end
  -- Phase 6.1 Test Commands
  elseif string.find(sub, "^test") then
    local _, _, testName = string.find(fullMsg, "^%s*test%s+(%S+)")
    
    -- Route to appropriate test suite
    if testName == "svm" then
      if OGRH.Tests and OGRH.Tests.SVM and OGRH.Tests.SVM.RunAll then
        OGRH.Tests.SVM.RunAll()
      else
        OGRH.Msg("SVM tests not loaded.")
      end
    elseif testName == "phase1" then
      if OGRH.Tests and OGRH.Tests.Phase1 and OGRH.Tests.Phase1.RunAll then
        OGRH.Tests.Phase1.RunAll()
      else
        OGRH.Msg("Phase 1 tests not loaded.")
      end
    elseif OGRH.SyncIntegrity and OGRH.SyncIntegrity.RunTests then
      OGRH.SyncIntegrity.RunTests(testName)
    else
      OGRH.Msg("Test system not loaded. Available: test svm, test phase1")
    end
  elseif sub == "help" or sub == "" then
    OGRH.Msg("Usage: /" .. OGRH.CMD .. " <command>")
    OGRH.Msg("Commands:")
    OGRH.Msg("  sand - Execute sand trade")
    OGRH.Msg("  shuffle [ms] - Shuffle raid with delay")
    OGRH.Msg("  sortspeed [ms] - Set/get auto-sort speed")
    OGRH.Msg("Migration Commands:")
    OGRH.Msg("  migration help - Show migration commands")
    OGRH.Msg("Chat Window Commands:")
    OGRH.Msg("  chatwindow - Create/find OGRH chat window")
    OGRH.Msg("  chat clean - Remove channels from OGRH window")
    OGRH.Msg("Debug Commands (Phase 1):")
    OGRH.Msg("  messages - Show all message types")
    OGRH.Msg("  permissions - Show raid permissions")
    OGRH.Msg("  denials - Show permission denials")
    OGRH.Msg("  version - Show version state")
    OGRH.Msg("  changes - Show recent changes")
    OGRH.Msg("  handlers - Show message handlers")
    OGRH.Msg("  takeadmin - Request admin role")
    OGRH.Msg("  sa - Set session admin (temporary)")
    OGRH.Msg("Test Commands:")
    OGRH.Msg("  test svm - Run SavedVariablesManager tests")
    OGRH.Msg("  test phase1 - Run Phase 1 Core Infrastructure tests")
  else
    OGRH.Msg("Unknown command. Type /" .. OGRH.CMD .. " help for usage.")
  end
end
_G["SLASH_"..string.upper(OGRH.CMD).."1"] = "/"..OGRH.CMD

if OGRH and OGRH.Msg then
  if OGRH.MainUI.State.debug then
    OGRH.Msg("|cff66ccff[RH][DEBUG]|r v" .. OGRH.VERSION .. " loaded")
  end
  
  -- Notify about RollFor status
  if OGRH.ROLLFOR_AVAILABLE then
    OGRH.Msg("|cff66ccff[RH]|r RollFor v" .. OGRH.ROLLFOR_REQUIRED_VERSION .. " detected")
  else
    local rollForVersion = GetAddOnMetadata("RollFor", "Version")
    if rollForVersion then
      OGRH.Msg("|cffffaa00[RH] Warning:|r RollFor v" .. rollForVersion .. " found, but v" .. OGRH.ROLLFOR_REQUIRED_VERSION .. " required")
    else
      OGRH.Msg("|cffffaa00[RH] Warning:|r RollFor v" .. OGRH.ROLLFOR_REQUIRED_VERSION .. " not found")
    end
    OGRH.Msg("|cff66ccff[RH]|r Some features disabled: Invites, SR Validation, RollFor sync")
  end
end