-- OGRH_MainUI.lua
if not OGRH then
  DEFAULT_CHAT_FRAME:AddMessage("|cffff0000Error: OGRH_MainUI requires OGRH_Core to be loaded first!|r")
  return
end

local Main = CreateFrame("Frame","OGRH_Main",UIParent)
Main:SetWidth(140); Main:SetHeight(124)  -- Increased height for new button
Main:SetPoint("CENTER", UIParent, "CENTER", -380, 120)
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
title:SetPoint("LEFT", H, "LEFT", 4, 0); title:SetText("|cffffff00OGRH|r")

local btnMin = CreateFrame("Button", nil, H, "UIPanelButtonTemplate"); btnMin:SetWidth(20); btnMin:SetHeight(16); btnMin:SetText("-"); btnMin:SetPoint("RIGHT", H, "RIGHT", -26, 0)
local btnLock = CreateFrame("Button", nil, H, "UIPanelButtonTemplate"); btnLock:SetWidth(20); btnLock:SetHeight(16); btnLock:SetText("L"); btnLock:SetPoint("RIGHT", H, "RIGHT", -4, 0)

-- ReAnnounce button
local reAnnounce = CreateFrame("Button", nil, H, "UIPanelButtonTemplate"); reAnnounce:SetWidth(20); reAnnounce:SetHeight(16); reAnnounce:SetText("RA"); reAnnounce:SetPoint("RIGHT", btnMin, "LEFT", -2, 0)
reAnnounce:RegisterForClicks("LeftButtonUp", "RightButtonUp")

-- ReadyCheck button
local readyCheck = CreateFrame("Button", nil, H, "UIPanelButtonTemplate"); readyCheck:SetWidth(20); readyCheck:SetHeight(16); readyCheck:SetText("RC"); readyCheck:SetPoint("RIGHT", reAnnounce, "LEFT", -2, 0)
readyCheck:RegisterForClicks("LeftButtonUp", "RightButtonUp")

local Content = CreateFrame("Frame", nil, Main); Content:SetPoint("TOPLEFT", Main, "TOPLEFT", 6, -26); Content:SetPoint("BOTTOMRIGHT", Main, "BOTTOMRIGHT", -6, 6)
local function makeBtn(text, anchorTo)
  local b=CreateFrame("Button", nil, Content, "UIPanelButtonTemplate")
  b:SetWidth(110); b:SetHeight(20); b:SetText(text)
  if not anchorTo then b:SetPoint("TOP", Content, "TOP", 0, 0) else b:SetPoint("TOP", anchorTo, "BOTTOM", 0, -4) end
  return b
end
local bRoles = makeBtn("Roles", nil)
local bEncounters = makeBtn("Encounters", bRoles)
local bTrade  = makeBtn("Trade", bEncounters)
local bShare  = makeBtn("Share", bTrade)

function OGRH_ShowBoard() if OGRH.ShowRolesUI then OGRH.ShowRolesUI() else OGRH.Msg("Roles UI not yet loaded.") end end
bRoles:SetScript("OnClick", function()
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

-- Encounters button with collapsible menu
bEncounters:SetScript("OnClick", function()
  -- Close Trade menu if it's open
  if OGRH_TradeMenu and OGRH_TradeMenu:IsVisible() then
    OGRH_TradeMenu:Hide()
  end
  
  if not OGRH_EncountersMenu then
    -- Create encounter menu
    local menu = CreateFrame("Frame", "OGRH_EncountersMenu", UIParent)
    menu:SetWidth(140)
    menu:SetHeight(100)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetBackdrop({
      bgFile = "Interface/Tooltips/UI-Tooltip-Background",
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
      edgeSize = 12,
      insets = {left = 4, right = 4, top = 4, bottom = 4}
    })
    menu:SetBackdropColor(0, 0, 0, 0.95)
    menu:Hide()
    
    -- Track expanded raids
    local expandedRaids = {}
    
    -- Store all menu buttons for cleanup
    local menuButtons = {}
    
    -- Raid structure
    local raids = {
      {
        name = "Manage",
        encounters = nil,
        handler = function()
          -- Close Setup window if open
          if OGRH_EncounterSetupFrame and OGRH_EncounterSetupFrame:IsVisible() then
            OGRH_EncounterSetupFrame:Hide()
          end
          
          if OGRH.ShowBWLEncounterWindow then 
            OGRH.ShowBWLEncounterWindow() 
          else
            DEFAULT_CHAT_FRAME:AddMessage("Encounter Planning window not yet implemented")
          end
        end
      }
    }
    
    -- Add Setup option at the end
    local setupButton = nil
    
    -- Function to rebuild menu
    local function RebuildMenu()
      -- Clear existing buttons
      for _, btn in ipairs(menuButtons) do
        btn:Hide()
        btn:SetParent(nil)
      end
      menuButtons = {}
      
      local yOffset = -5
      
      for _, raid in ipairs(raids) do
        -- Check if this raid has encounters or a direct handler
        if raid.encounters then
          -- Expandable raid with encounters
          local isExpanded = expandedRaids[raid.name]
          
          -- Create raid header button
          local raidBtn = CreateFrame("Button", nil, menu, "UIPanelButtonTemplate")
          raidBtn:SetWidth(130)
          raidBtn:SetHeight(20)
          raidBtn:SetPoint("TOPLEFT", menu, "TOPLEFT", 5, yOffset)
          
          local expandIcon = isExpanded and "[-] " or "[+] "
          raidBtn:SetText(expandIcon .. raid.name)
          
          -- Capture raid.name in local variable for closure
          local raidName = raid.name
          raidBtn:SetScript("OnClick", function()
            expandedRaids[raidName] = not expandedRaids[raidName]
            RebuildMenu()
          end)
          table.insert(menuButtons, raidBtn)
          yOffset = yOffset - 22
          
          -- If expanded, show encounters
          if isExpanded then
            for _, encounter in ipairs(raid.encounters) do
              local encBtn = CreateFrame("Button", nil, menu, "UIPanelButtonTemplate")
              encBtn:SetWidth(120)
              encBtn:SetHeight(18)
              encBtn:SetPoint("TOPLEFT", menu, "TOPLEFT", 15, yOffset)
              encBtn:SetText(encounter.text)
              
              -- Capture handler in local variable for closure
              local encounterHandler = encounter.handler
              encBtn:SetScript("OnClick", function()
                menu:Hide()
                encounterHandler()
              end)
              table.insert(menuButtons, encBtn)
              yOffset = yOffset - 20
            end
          end
        else
          -- Direct handler button (no encounters)
          local raidBtn = CreateFrame("Button", nil, menu, "UIPanelButtonTemplate")
          raidBtn:SetWidth(130)
          raidBtn:SetHeight(20)
          raidBtn:SetPoint("TOPLEFT", menu, "TOPLEFT", 5, yOffset)
          raidBtn:SetText(raid.name)
          
          -- Capture handler in local variable for closure
          local raidHandler = raid.handler
          raidBtn:SetScript("OnClick", function()
            menu:Hide()
            if raidHandler then
              raidHandler()
            end
          end)
          table.insert(menuButtons, raidBtn)
          yOffset = yOffset - 22
        end
      end
      
      -- Update menu height
      local totalHeight = math.abs(yOffset) + 10
      
      -- Add Setup button at the bottom
      if not setupButton then
        setupButton = CreateFrame("Button", nil, menu, "UIPanelButtonTemplate")
        setupButton:SetWidth(130)
        setupButton:SetHeight(20)
        setupButton:SetScript("OnClick", function()
          menu:Hide()
          
          -- Close Manage window if open
          if OGRH_BWLEncounterFrame and OGRH_BWLEncounterFrame:IsVisible() then
            OGRH_BWLEncounterFrame:Hide()
          end
          
          if OGRH.ShowEncounterSetup then
            OGRH.ShowEncounterSetup()
          else
            DEFAULT_CHAT_FRAME:AddMessage("Encounter Setup not yet implemented")
          end
        end)
      end
      setupButton:SetPoint("TOPLEFT", menu, "TOPLEFT", 5, yOffset)
      setupButton:SetText("Setup")
      setupButton:Show()
      
      totalHeight = totalHeight + 22
      menu:SetHeight(totalHeight)
    end
    
    menu.Rebuild = RebuildMenu
  end
  
  local menu = OGRH_EncountersMenu
  if menu:IsVisible() then
    menu:Hide()
  else
    menu.Rebuild()
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", bEncounters, "BOTTOMLEFT", 0, -2)
    menu:Show()
  end
end)

bTrade:RegisterForClicks("LeftButtonUp","RightButtonUp")
bTrade:SetScript("OnClick", function()
  local btn = arg1 or "LeftButton"
  -- Close Encounters menu if it's open
  if OGRH_EncountersMenu and OGRH_EncountersMenu:IsVisible() then
    OGRH_EncountersMenu:Hide()
  end
  
  -- Both left and right click show/hide the menu
  if not OGRH_TradeMenu then
      local M = CreateFrame("Frame","OGRH_TradeMenu",UIParent)
      M:SetFrameStrata("FULLSCREEN_DIALOG")
      M:SetBackdrop({bgFile="Interface/Tooltips/UI-Tooltip-Background", edgeFile="Interface/Tooltips/UI-Tooltip-Border", edgeSize=12, insets={left=4,right=4,top=4,bottom=4}})
      M:SetBackdropColor(0,0,0,0.95); M:SetWidth(200); M:SetHeight(1); M:Hide()
      
      M.btns = {}
      M.Rebuild = function()
        -- Clear existing buttons
        if M.btns then
          for _, btn in ipairs(M.btns) do
            btn:Hide()
            btn:SetParent(nil)
          end
        end
        M.btns = {}
        
        OGRH.EnsureSV()
        local items = OGRH_SV.tradeItems
        
        -- Get current trade item info
        local currentItemId = OGRH.GetCurrentTradeItemId and OGRH.GetCurrentTradeItemId() or nil
        
        local yOffset = -10
        local buttonHeight = 18
        local buttonSpacing = 6
        
        -- Create buttons for each trade item
        for i, itemData in ipairs(items) do
          local it = CreateFrame("Button", nil, M, "UIPanelButtonTemplate")
          it:SetWidth(180)
          it:SetHeight(buttonHeight)
          
          if i == 1 then
            it:SetPoint("TOPLEFT", M, "TOPLEFT", 10, yOffset)
          else
            it:SetPoint("TOPLEFT", M.btns[i-1], "BOTTOMLEFT", 0, -buttonSpacing)
          end
          
          local fs = it:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
          fs:SetAllPoints()
          fs:SetJustifyH("CENTER")
          it.fs = fs
          
          local label = itemData.name or ("Item " .. itemData.itemId)
          
          -- Highlight if this is the active trade item
          if itemData.itemId == currentItemId then
            fs:SetText(OGRH.COLOR.HEADER .. label .. OGRH.COLOR.RESET)
          else
            fs:SetText(label)
          end
          
          local itemId = itemData.itemId
          local quantity = itemData.quantity
          
          it:SetScript("OnClick", function()
            if OGRH.SetTradeItem then
              OGRH.SetTradeItem(itemId, quantity)
            end
            M:Hide()
          end)
          
          table.insert(M.btns, it)
        end
        
        -- Add Settings button at the bottom
        local settingsBtn = CreateFrame("Button", nil, M, "UIPanelButtonTemplate")
        settingsBtn:SetWidth(180)
        settingsBtn:SetHeight(buttonHeight)
        
        if table.getn(M.btns) > 0 then
          settingsBtn:SetPoint("TOPLEFT", M.btns[table.getn(M.btns)], "BOTTOMLEFT", 0, -buttonSpacing)
        else
          settingsBtn:SetPoint("TOPLEFT", M, "TOPLEFT", 10, yOffset)
        end
        
        local settingsFs = settingsBtn:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        settingsFs:SetAllPoints()
        settingsFs:SetJustifyH("CENTER")
        settingsFs:SetText("|cff888888Settings|r")
        
        settingsBtn:SetScript("OnClick", function()
          M:Hide()
          if OGRH.ShowTradeSettings then
            OGRH.ShowTradeSettings()
          end
        end)
        
        table.insert(M.btns, settingsBtn)
        
        -- Calculate menu height
        local numButtons = table.getn(M.btns)
        local totalHeight = 10 + numButtons * buttonHeight + (numButtons - 1) * buttonSpacing + 10
        M:SetHeight(totalHeight)
      end
    end
    local M = OGRH_TradeMenu
    
    -- Toggle menu visibility
    if M:IsVisible() then
      M:Hide()
      return
    end
    
    -- Rebuild menu with current items
    M.Rebuild()
    
    M:ClearAllPoints(); M:SetPoint("TOPLEFT", bTrade, "BOTTOMLEFT", 0, -2); M:Show()
end)

-- Encounter navigation controls (shown when minimized)
local encounterNav = CreateFrame("Frame", nil, Main)
encounterNav:SetPoint("TOPLEFT", Main, "TOPLEFT", 6, -26)
encounterNav:SetPoint("TOPRIGHT", Main, "TOPRIGHT", -6, -26)
encounterNav:SetHeight(24)
encounterNav:Hide()

-- Previous Encounter button
local prevEncBtn = CreateFrame("Button", nil, encounterNav, "UIPanelButtonTemplate")
prevEncBtn:SetWidth(20)
prevEncBtn:SetHeight(20)
prevEncBtn:SetPoint("LEFT", encounterNav, "LEFT", 0, 0)
prevEncBtn:SetText("<")
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
announceBtn:SetScript("OnClick", function()
  if OGRH.PrepareEncounterAnnouncement then
    OGRH.PrepareEncounterAnnouncement()
  end
end)
encounterNav.announceBtn = announceBtn

-- Next Encounter button
local nextEncBtn = CreateFrame("Button", nil, encounterNav, "UIPanelButtonTemplate")
nextEncBtn:SetWidth(20)
nextEncBtn:SetHeight(20)
nextEncBtn:SetPoint("RIGHT", encounterNav, "RIGHT", 0, 0)
nextEncBtn:SetText(">")
nextEncBtn:SetScript("OnClick", function()
  if OGRH.NavigateToNextEncounter then
    OGRH.NavigateToNextEncounter()
  end
end)
encounterNav.nextEncBtn = nextEncBtn

-- Encounter button (middle, fills remaining space)
local encounterBtn = CreateFrame("Button", nil, encounterNav, "UIPanelButtonTemplate")
encounterBtn:SetHeight(20)
encounterBtn:SetPoint("LEFT", announceBtn, "RIGHT", 2, 0)
encounterBtn:SetPoint("RIGHT", nextEncBtn, "LEFT", -2, 0)
encounterBtn:SetText("Select Raid")
encounterBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
encounterBtn:SetScript("OnClick", function()
  if arg1 == "RightButton" then
    -- Show raid selection menu
    if OGRH.ShowEncounterRaidMenu then
      OGRH.ShowEncounterRaidMenu(encounterBtn)
    end
  else
    -- Left click: Open Encounter Planning with selected encounter
    if OGRH.OpenEncounterPlanning then
      OGRH.OpenEncounterPlanning()
    end
  end
end)
encounterNav.encounterBtn = encounterBtn

-- Store reference for external access
OGRH.encounterNav = encounterNav

local function applyMinimized(mini) 
  if mini then 
    Content:Hide()
    encounterNav:Show()
    Main:SetHeight(56)
    btnMin:SetText("+")
  else 
    Content:Show()
    encounterNav:Hide()
    Main:SetHeight(124)
    btnMin:SetText("-")
  end
end
btnMin:SetScript("OnClick", function() ensureSV(); OGRH_SV.ui.minimized = not OGRH_SV.ui.minimized; applyMinimized(OGRH_SV.ui.minimized) end)
local function applyLocked(lock) btnLock:SetText("L") end
btnLock:SetScript("OnClick", function() ensureSV(); OGRH_SV.ui.locked = not OGRH_SV.ui.locked; applyLocked(OGRH_SV.ui.locked) end)

-- ReAnnounce button handler
reAnnounce:SetScript("OnClick", function()
  local btn = arg1 or "LeftButton"
  
  if btn == "RightButton" then
    -- Test stub: Stage a multi-line announcement with timestamp
    local timestamp = date("%H:%M:%S")
    local testLines = {
      "|cff00ff00[Test Announcement " .. timestamp .. "]|r",
      "|cff00ff00[Main Tank]:|r |cFFC79C6ETankPlayer|r",
      "|cff00ff00[Near]:|r |cFFC79C6ETank1|r, |cFFC79C6ETank2|r - |cff00ff00Healers:|r |cFFFFFFFFHealer1|r |cFFFFFFFFHealer2|r",
      "|cff00ff00[Far]:|r |cFFC79C6ETank3|r, |cFFC79C6ETank4|r - |cff00ff00Healers:|r |cFFFFFFFFHealer3|r |cFFFFFFFFHealer4|r"
    }
    
    if OGRH and OGRH.StoreAndBroadcastAnnouncement then
      OGRH.StoreAndBroadcastAnnouncement(testLines)
      if OGRH.Msg then
        OGRH.Msg("Test announcement staged. Left-click RA to announce.")
      end
    else
      if OGRH and OGRH.Msg then
        OGRH.Msg("StoreAndBroadcastAnnouncement not loaded.")
      end
    end
  else
    -- Left click: Re-announce
    if OGRH and OGRH.ReAnnounce then
      OGRH.ReAnnounce()
    elseif OGRH and OGRH.Msg then
      OGRH.Msg("No announcement to repeat.")
    end
  end
end)

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

-- Share button handler
bShare:SetScript("OnClick", function()
  -- Close Trade menu if it's open
  if OGRH_TradeMenu and OGRH_TradeMenu:IsVisible() then
    OGRH_TradeMenu:Hide()
  end
  -- Close Encounters menu if it's open
  if OGRH_EncountersMenu and OGRH_EncountersMenu:IsVisible() then
    OGRH_EncountersMenu:Hide()
  end
  
  if OGRH.ShowShareWindow then
    OGRH.ShowShareWindow()
  else
    OGRH.Msg("Share functionality not loaded.")
  end
end)

-- Expose reAnnounce button for external access
OGRH.reAnnounceButton = reAnnounce

local function restoreMain()
  ensureSV()
  local ui=OGRH_SV.ui or {}
  if ui.point and ui.x and ui.y then Main:ClearAllPoints(); Main:SetPoint(ui.point, UIParent, ui.relPoint or ui.point, ui.x, ui.y) end
  applyMinimized(ui.minimized); applyLocked(ui.locked)
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