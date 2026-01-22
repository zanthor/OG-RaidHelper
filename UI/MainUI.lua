-- OGRH_MainUI.lua
if not OGRH then
  DEFAULT_CHAT_FRAME:AddMessage("|cffff0000Error: OGRH_MainUI requires OGRH_Core to be loaded first!|r")
  return
end

local Main = CreateFrame("Frame","OGRH_Main",UIParent)
Main:SetWidth(180); Main:SetHeight(56)  -- Fixed height for title bar + encounter nav
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
    local roles = OGRH_SV.encounterMgmt.roles
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
OGRH.adminButton = adminBtn
-- Backward compatibility alias
OGRH.syncButton = adminBtn

local function restoreMain()
  ensureSV()
  local ui=OGRH_SV.ui or {}
  if ui.point and ui.x and ui.y then Main:ClearAllPoints(); Main:SetPoint(ui.point, UIParent, ui.relPoint or ui.point, ui.x, ui.y) end
  applyLocked(ui.locked)
  
  -- Initialize raid lead system
  if OGRH.InitRaidLead then
    OGRH.InitRaidLead()
  end
  
  -- Update raid lead UI state
  if OGRH.UpdateRaidLeadUI then
    OGRH.UpdateRaidLeadUI()
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
  if ui.hidden then
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
      if not OGRH_SV.sorting then OGRH_SV.sorting = {} end
      OGRH_SV.sorting.speed = speedMs
      OGRH.Msg("Auto-sort speed set to " .. speedMs .. "ms between moves")
    else
      if OGRH_SV.sorting and OGRH_SV.sorting.speed then
        OGRH.Msg("Current auto-sort speed: " .. OGRH_SV.sorting.speed .. "ms")
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
  elseif sub == "help" or sub == "" then
    OGRH.Msg("Usage: /" .. OGRH.CMD .. " <command>")
    OGRH.Msg("Commands:")
    OGRH.Msg("  sand - Execute sand trade")
    OGRH.Msg("  shuffle [ms] - Shuffle raid with delay")
    OGRH.Msg("  sortspeed [ms] - Set/get auto-sort speed")
    OGRH.Msg("Debug Commands (Phase 1):")
    OGRH.Msg("  messages - Show all message types")
    OGRH.Msg("  permissions - Show raid permissions")
    OGRH.Msg("  denials - Show permission denials")
    OGRH.Msg("  version - Show version state")
    OGRH.Msg("  changes - Show recent changes")
    OGRH.Msg("  handlers - Show message handlers")
    OGRH.Msg("  takeadmin - Request admin role")
    OGRH.Msg("  sa - Set session admin (temporary)")
  else
    OGRH.Msg("Unknown command. Type /" .. OGRH.CMD .. " help for usage.")
  end
end
_G["SLASH_"..string.upper(OGRH.CMD).."1"] = "/"..OGRH.CMD

if OGRH and OGRH.Msg then
  DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[RaidHelper]|r v" .. OGRH.VERSION .. " loaded")
  
  -- Notify about RollFor status
  if OGRH.ROLLFOR_AVAILABLE then
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[RaidHelper]|r RollFor v" .. OGRH.ROLLFOR_REQUIRED_VERSION .. " detected")
  else
    local rollForVersion = GetAddOnMetadata("RollFor", "Version")
    if rollForVersion then
      DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[RaidHelper]|r |cffff8800Warning:|r RollFor v" .. rollForVersion .. " found, but v" .. OGRH.ROLLFOR_REQUIRED_VERSION .. " required")
    else
      DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[RaidHelper]|r |cffff8800Warning:|r RollFor v" .. OGRH.ROLLFOR_REQUIRED_VERSION .. " not found")
    end
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[RaidHelper]|r Some features disabled: Invites, SR Validation, RollFor sync")
  end
end