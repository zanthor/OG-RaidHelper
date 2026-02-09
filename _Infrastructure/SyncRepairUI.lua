--[[
    OG-RaidHelper: SyncRepairUI.lua
    
    UI panels for session-based repair system.
    Provides feedback to admin and clients during synchronization.
    
    PHASE 4 IMPLEMENTATION (STUB)
    
    Responsibilities:
    - Admin repair panel (client tracking, progress)
    - Client repair panel (countdown, progress bar)
    - Waiting panel (join-during-repair)
    - Admin button tooltip (sync status display)
    - Auxiliary panel registration (priority 20)
]]

if not OGRH then OGRH = {} end
if not OGRH.SyncRepairUI then OGRH.SyncRepairUI = {} end

--[[
    ============================================================================
    MODULE STATE
    ============================================================================
]]

OGRH.SyncRepairUI.State = {
    -- Panel references
    adminPanel = nil,
    clientPanel = nil,
    waitingPanel = nil,
    
    -- Tooltip state
    tooltipData = {},  -- {playerName, version, syncStatus, classColor}
    
    -- Timeout tracking (10s inactivity = auto-hide)
    timeouts = {
        adminTimer = nil,        -- Timer reference for admin panel
        clientTimer = nil,       -- Timer reference for client panel
        waitingTimer = nil,      -- Timer reference for waiting panel
        lastAdminActivity = 0,   -- Timestamp of last admin activity
        lastClientActivity = 0,  -- Timestamp of last client activity
        lastWaitingActivity = 0, -- Timestamp of last waiting activity
        timeoutDuration = 10.0   -- 10 seconds timeout
    }
}

--[[
    ============================================================================
    PHASE 4 - ADMIN REPAIR PANEL
    ============================================================================
]]

-- Create admin repair panel
function OGRH.SyncRepairUI.CreateAdminPanel()
    if OGRH.SyncRepairUI.State.adminPanel then
        return OGRH.SyncRepairUI.State.adminPanel
    end
    
    local mainWidth = OGRH_Main and OGRH_Main:GetWidth() or 180
    local panel = CreateFrame("Frame", "OGRHAdminRepairPanel", UIParent)
    panel:SetWidth(mainWidth)
    panel:SetHeight(150)  -- Start smaller, will resize dynamically
    panel:SetFrameStrata("MEDIUM")
    panel:EnableMouse(false)
    panel:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = {left = 2, right = 2, top = 2, bottom = 2}
    })
    panel:SetBackdropColor(0, 0, 0, 0.85)
    
    -- Register with auxiliary panel system (priority 20)
    panel:SetScript("OnShow", function()
        if OGRH.RegisterAuxiliaryPanel then
            OGRH.RegisterAuxiliaryPanel(this, 20)
        end
    end)
    
    panel:SetScript("OnHide", function()
        if OGRH.UnregisterAuxiliaryPanel then
            OGRH.UnregisterAuxiliaryPanel(this)
        end
    end)
    
    panel:Hide()
    
    -- Status text (top left)
    local status = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    status:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -8)
    status:SetText("Status: Initializing...")
    status:SetJustifyH("LEFT")
    panel.status = status
    
    -- Progress bar
    local progressBar = OGST.CreateProgressBar(panel, {
        width = mainWidth - 16,
        height = 14,
        barColor = {r = 0.2, g = 0.8, b = 0.2},
        showText = true,
        min = 0,
        max = 100,
        value = 0
    })
    progressBar:SetPoint("TOPLEFT", status, "BOTTOMLEFT", 0, -5)
    progressBar:SetText("0%  (0/0 packets)")
    panel.progressBar = progressBar
    
    -- Client list label
    local clientLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    clientLabel:SetPoint("TOPLEFT", progressBar, "BOTTOMLEFT", 0, -10)
    clientLabel:SetText("Repairing Clients:")
    clientLabel:SetJustifyH("LEFT")
    panel.clientLabel = clientLabel
    
    -- Store mainWidth for updates
    panel.mainWidth = mainWidth
    
    -- Client list scroll frame (height will be set dynamically on show)
    local scrollFrame = CreateFrame("ScrollFrame", nil, panel)
    scrollFrame:SetWidth(mainWidth - 16)
    scrollFrame:SetHeight(50)  -- Minimum height, resized dynamically
    scrollFrame:SetPoint("TOPLEFT", clientLabel, "BOTTOMLEFT", 0, -5)
    
    -- Add visible border to scroll frame
    scrollFrame:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = {left = 3, right = 3, top = 3, bottom = 3}
    })
    scrollFrame:SetBackdropColor(0, 0, 0, 0.5)
    scrollFrame:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.8)
    
    -- Enable mouse wheel scrolling
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function()
        local scroll = this:GetVerticalScroll()
        local maxScroll = this:GetVerticalScrollRange()
        if arg1 > 0 then
            -- Scroll up
            this:SetVerticalScroll(math.max(0, scroll - 15))
        else
            -- Scroll down
            this:SetVerticalScroll(math.min(maxScroll, scroll + 15))
        end
    end)
    
    -- OGST Design Mode support
    scrollFrame.hasDesignBorder = true
    scrollFrame.designBorderColor = {r = 1, g = 0.5, b = 0}  -- Orange for scroll areas
    if OGST and OGST.AddDesignTooltip then
        OGST.AddDesignTooltip(scrollFrame, "Client List (Scrollable)", "ScrollFrame")
    end
    
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(mainWidth - 22)  -- Account for insets
    scrollChild:SetHeight(50)
    scrollFrame:SetScrollChild(scrollChild)
    panel.clientList = scrollChild
    panel.clientListScroll = scrollFrame
    
    -- Cancel button (using OGST)
    local cancelBtn = OGST.CreateButton(panel, {
        text = "Cancel Repair",
        width = mainWidth - 6,
        height = 20,
        onClick = function()
            if OGRH.SyncSession and OGRH.SyncSession.CancelSession then
                OGRH.SyncSession.CancelSession("Manual cancellation by admin")
            end
            OGRH.SyncRepairUI.HideAdminPanel()
        end
    })
    cancelBtn:SetPoint("BOTTOM", panel, "BOTTOM", 0, 2)
    panel.cancelBtn = cancelBtn
    
    OGRH.SyncRepairUI.State.adminPanel = panel
    return panel
end

-- Show admin panel with client tracking
function OGRH.SyncRepairUI.ShowAdminPanel(sessionToken, clientList)
    local panel = OGRH.SyncRepairUI.CreateAdminPanel()
    
    -- Clear existing client entries (FontStrings are regions, not children)
    local clientListFrame = panel.clientList
    if not clientListFrame.entries then
        clientListFrame.entries = {}
    end
    for i = 1, table.getn(clientListFrame.entries) do
        clientListFrame.entries[i]:Hide()
        clientListFrame.entries[i]:SetText("")
    end
    clientListFrame.entries = {}  -- Reset tracking array
    
    -- Calculate dynamic height based on client count
    local actualClientCount = (clientList and table.getn(clientList)) or 0
    local visibleClientCount = actualClientCount
    if visibleClientCount == 0 then visibleClientCount = 1 end  -- At least 1 line for "no clients" message
    
    -- Clamp visible height (min 1 line, max 3 lines for scrolling)
    if visibleClientCount > 3 then visibleClientCount = 3 end
    
    local lineHeight = 15
    local borderInsets = 10  -- Border padding adjustment
    local visibleHeight = visibleClientCount * lineHeight + 10 + borderInsets  -- Visible area + border insets
    local fullHeight = actualClientCount * lineHeight + 10                      -- Full content height
    
    -- Calculate total panel height
    -- status(18) + gap(5) + progressBar(14) + gap(10) + label(18) + gap(5) + clientList(visible) + gap(5) + button(20) + bottomPadding(2)
    local fixedHeight = 18 + 5 + 14 + 10 + 18 + 5 + 5 + 20 + 2  -- 97px fixed
    local totalHeight = fixedHeight + visibleHeight
    
    panel:SetHeight(totalHeight)
    panel.clientListScroll:SetHeight(visibleHeight)  -- Viewport shows 3 lines + border
    panel.clientList:SetHeight(fullHeight)           -- Content is full height of all entries
    
    -- Create client entries
    if clientList and table.getn(clientList) > 0 then
        for i = 1, table.getn(clientList) do
            local client = clientList[i]
            local entry = clientListFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            entry:SetPoint("TOPLEFT", clientListFrame, "TOPLEFT", 5, -3 - (i-1) * 15)  -- -3 for top inset
            entry:SetJustifyH("LEFT")
            entry:SetWidth(370)
            
            local icon = "|cffff9900⏳|r"  -- Waiting icon
            local components = client.components or "Unknown"
            local coloredName = OGRH.ColorName(client.name)  -- Apply class color
            entry:SetText(string.format("%s %s  (%s)", icon, coloredName, components))
            
            -- Track for cleanup
            table.insert(clientListFrame.entries, entry)
        end
    else
        local noClients = clientListFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        noClients:SetPoint("TOPLEFT", clientListFrame, "TOPLEFT", 5, -3)  -- -3 for top inset
        noClients:SetText("|cffaaaaaa(No clients requesting repair)|r")
        
        -- Track for cleanup
        table.insert(clientListFrame.entries, noClients)
    end
    
    panel.status:SetText("Status: Initializing session...")
    panel.progressBar:SetValue(0)
    panel.progressBar:SetText("0%  (0/0 packets)")
    
    -- Start timeout (10s inactivity = auto-close)
    OGRH.SyncRepairUI.StartAdminTimeout()
    
    panel:Show()
end

-- Update admin panel progress
function OGRH.SyncRepairUI.UpdateAdminProgress(packetsSent, totalPackets, currentPhase, validatedClients)
    local panel = OGRH.SyncRepairUI.State.adminPanel
    if not panel or not panel:IsShown() then
        return
    end
    
    -- Update status
    local phaseText = currentPhase or "In Progress"
    panel.status:SetText("Status: " .. phaseText)
    
    -- Update progress bar
    if totalPackets > 0 then
        local pct = packetsSent / totalPackets
        panel.progressBar:SetValue(pct * 100)
        
        local pctText = string.format("%.0f%%  (%d/%d packets)", pct * 100, packetsSent, totalPackets)
        panel.progressBar:SetText(pctText)
    end
    
    -- Update client list checkmarks
    if validatedClients then
        local clientListFrame = panel.clientList
        local children = {clientListFrame:GetChildren()}
        
        for i = 1, table.getn(children) do
            local entry = children[i]
            if entry and entry.GetText then
                local text = entry:GetText()
                local playerName = string.match(text, "⏳ ([%w]+)")
                
                if playerName and validatedClients[playerName] then
                    -- Replace ⏳ with ✓
                    text = string.gsub(text, "|cffff9900⏳|r", "|cff00ff00✓|r")
                    entry:SetText(text)
                end
            end
        end
    end
end

-- Hide admin panel
function OGRH.SyncRepairUI.HideAdminPanel()
    local panel = OGRH.SyncRepairUI.State.adminPanel
    if panel then
        -- Cancel timeout
        OGRH.SyncRepairUI.CancelAdminTimeout()
        panel:Hide()
    end
end

--[[
    ============================================================================
    PHASE 4 - CLIENT REPAIR PANEL
    ============================================================================
]]

-- Create client repair panel
function OGRH.SyncRepairUI.CreateClientPanel()
    if OGRH.SyncRepairUI.State.clientPanel then
        return OGRH.SyncRepairUI.State.clientPanel
    end
    
    local mainWidth = OGRH_Main and OGRH_Main:GetWidth() or 180
    local panel = CreateFrame("Frame", "OGRHClientRepairPanel", UIParent)
    panel:SetWidth(mainWidth)
    panel:SetHeight(220)
    panel:SetFrameStrata("MEDIUM")
    panel:EnableMouse(false)
    panel:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = {left = 2, right = 2, top = 2, bottom = 2}
    })
    panel:SetBackdropColor(0, 0, 0, 0.85)
    
    -- Register with auxiliary panel system (priority 20)
    panel:SetScript("OnShow", function()
        if OGRH.RegisterAuxiliaryPanel then
            OGRH.RegisterAuxiliaryPanel(this, 20)
        end
    end)
    
    panel:SetScript("OnHide", function()
        if OGRH.UnregisterAuxiliaryPanel then
            OGRH.UnregisterAuxiliaryPanel(this)
        end
    end)
    
    panel:Hide()
    
    -- Status text (top left)
    local status = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    status:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -8)
    status:SetText("Status: Waiting for repairs...")
    status:SetJustifyH("LEFT")
    panel.status = status
    
    -- Progress bar
    local progressBar = OGST.CreateProgressBar(panel, {
        width = mainWidth - 16,
        height = 14,
        barColor = {r = 0.2, g = 0.6, b = 0.9},
        showText = true,
        min = 0,
        max = 100,
        value = 0
    })
    progressBar:SetPoint("TOPLEFT", status, "BOTTOMLEFT", 0, -5)
    progressBar:SetText("0%  (0/0 packets)")
    panel.progressBar = progressBar
    
    -- ETA text
    local eta = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    eta:SetPoint("TOPLEFT", progressBar, "BOTTOMLEFT", 0, -5)
    eta:SetText("ETA: Calculating...")
    eta:SetJustifyH("LEFT")
    panel.eta = eta
    
    -- Components list label
    local componentLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    componentLabel:SetPoint("TOPLEFT", eta, "BOTTOMLEFT", 0, -5)
    componentLabel:SetText("Components Updated:")
    componentLabel:SetJustifyH("LEFT")
    panel.componentLabel = componentLabel
    
    -- Components list
    local componentsList = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    componentsList:SetPoint("TOPLEFT", componentLabel, "BOTTOMLEFT", 5, -3)
    componentsList:SetText("|cffaaaaaa(Waiting...)|r")
    componentsList:SetJustifyH("LEFT")
    panel.componentsList = componentsList
    
    -- Store mainWidth
    panel.mainWidth = mainWidth
    
    OGRH.SyncRepairUI.State.clientPanel = panel
    return panel
end

-- Show client panel with countdown
function OGRH.SyncRepairUI.ShowClientPanel(sessionToken, totalPackets)
    local panel = OGRH.SyncRepairUI.CreateClientPanel()
    
    -- Calculate dynamic height
    local componentLines = 3  -- Typically 3 lines of components
    local totalHeight = 18 + 5 + 20 + 5 + 15 + 5 + 13 + 3 + (componentLines * 13) + 5
    panel:SetHeight(totalHeight)
    
    panel.status:SetText("Status: Receiving repairs...")
    panel.progressBar:SetValue(0)
    panel.progressBar:SetText("0%  (0/" .. (totalPackets or 0) .. " packets)")
    panel.eta:SetText("ETA: Calculating...")
    panel.componentsList:SetText("|cffaaaaaa⏳ Raid Structure|r\n|cffaaaaaa⏳ Encounters|r\n|cffaaaaaa⏳ Roles|r")
    
    -- Start timeout (10s inactivity = auto-close)
    OGRH.SyncRepairUI.StartClientTimeout()
    
    panel:Show()
end

-- Update client panel countdown
function OGRH.SyncRepairUI.UpdateClientCountdown(secondsRemaining)
    local panel = OGRH.SyncRepairUI.State.clientPanel
    if not panel or not panel:IsShown() then
        return
    end
    
    if secondsRemaining > 0 then
        panel.eta:SetText(string.format("ETA: %ds", secondsRemaining))
    else
        panel.eta:SetText("ETA: Completing...")
    end
end

-- Update client panel progress bar
function OGRH.SyncRepairUI.UpdateClientProgress(packetsReceived, totalPackets, currentPhase)
    local panel = OGRH.SyncRepairUI.State.clientPanel
    if not panel or not panel:IsShown() then
        return
    end
    
    -- Update status
    if currentPhase then
        panel.status:SetText("Status: " .. currentPhase)
    end
    
    -- Update progress bar
    if totalPackets > 0 then
        local pct = packetsReceived / totalPackets
        panel.progressBar:SetValue(pct * 100)
        
        local pctText = string.format("%.0f%%  (%d/%d packets)", pct * 100, packetsReceived, totalPackets)
        panel.progressBar:SetText(pctText)
    end
end

-- Hide client panel
function OGRH.SyncRepairUI.HideClientPanel()
    local panel = OGRH.SyncRepairUI.State.clientPanel
    if panel then
        -- Cancel timeout
        OGRH.SyncRepairUI.CancelClientTimeout()
        panel:Hide()
    end
end

--[[
    ============================================================================
    PHASE 4 - WAITING PANEL
    ============================================================================
]]

-- Create waiting panel (join-during-repair)
function OGRH.SyncRepairUI.CreateWaitingPanel()
    if OGRH.SyncRepairUI.State.waitingPanel then
        return OGRH.SyncRepairUI.State.waitingPanel
    end
    
    local mainWidth = OGRH_Main and OGRH_Main:GetWidth() or 180
    local panel = CreateFrame("Frame", "OGRHWaitingPanel", UIParent)
    panel:SetWidth(mainWidth)
    panel:SetHeight(47)  -- Reduced: message(18) + gap(8) + bar(12) + bottom(4)
    panel:SetFrameStrata("MEDIUM")
    panel:EnableMouse(false)
    panel:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = {left = 2, right = 2, top = 2, bottom = 2}
    })
    panel:SetBackdropColor(0, 0, 0, 0.85)
    
    -- Register with auxiliary panel system (priority 20)
    panel:SetScript("OnShow", function()
        if OGRH.RegisterAuxiliaryPanel then
            OGRH.RegisterAuxiliaryPanel(this, 20)
        end
    end)
    
    panel:SetScript("OnHide", function()
        if OGRH.UnregisterAuxiliaryPanel then
            OGRH.UnregisterAuxiliaryPanel(this)
        end
    end)
    
    panel:Hide()
    
    -- Status message (top)
    local message = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    message:SetPoint("TOP", panel, "TOP", 0, -8)
    message:SetText("⏳ Admin is syncing data")
    message:SetJustifyH("CENTER")
    panel.message = message
    
    -- Progress bar with ETA text overlay (blue color)
    local progressBar = OGST.CreateProgressBar(panel, {
        width = mainWidth - 16,
        height = 12,
        barColor = {r = 0.2, g = 0.6, b = 0.9},  -- Blue color
        showText = true,
        min = 0,
        max = 100,
        value = 100  -- Full bar for indeterminate state
    })
    progressBar:SetPoint("TOP", message, "BOTTOM", 0, -8)
    progressBar:SetText("ETA: Unknown")  -- ETA text on progress bar
    panel.progressBar = progressBar
    
    -- Enable Sync button (shown only for admin in sync_disabled mode, replaces progress bar)
    local enableSyncBtn = OGST.CreateButton(panel, {
        text = "Enable Sync",
        width = 120,
        height = 20,
        onClick = function()
            if OGRH.SyncMode and OGRH.SyncMode.EnableSync then
                OGRH.SyncMode.EnableSync()
            end
        end
    })
    enableSyncBtn:SetPoint("TOP", message, "BOTTOM", 0, -2)
    enableSyncBtn:Hide()  -- Hidden by default
    panel.enableSyncBtn = enableSyncBtn
    
    OGRH.SyncRepairUI.State.waitingPanel = panel
    return panel
end

-- Show waiting panel
function OGRH.SyncRepairUI.ShowWaitingPanel(estimatedSeconds)
    OGRH.Msg(string.format("|cffaaaaaa[RH-SyncRepairUI]|r ShowWaitingPanel called with estimatedSeconds=%s", tostring(estimatedSeconds)))
    
    local panel = OGRH.SyncRepairUI.CreateWaitingPanel()
    
    -- Handle special sync_disabled modes
    if estimatedSeconds == "sync_disabled" or estimatedSeconds == "sync_disabled_admin" then
        local isAdmin = (estimatedSeconds == "sync_disabled_admin")
        OGRH.Msg(string.format("|cffaaaaaa[RH-SyncRepairUI]|r Configuring panel for sync_disabled mode (isAdmin=%s)", tostring(isAdmin)))
        
        if panel.message then
            panel.message:SetText("|cffff9900⏸ Admin Sync Disabled|r")
        end
        if panel.progressBar then
            panel.progressBar:Hide()
        end
        if panel.enableSyncBtn then
            if isAdmin then
                panel.enableSyncBtn:Show()
            else
                panel.enableSyncBtn:Hide()
            end
        end
    elseif estimatedSeconds and estimatedSeconds > 0 then
        -- Normal repair case - reset to default message
        if panel.message then
            panel.message:SetText("⏳ Admin is syncing data")
        end
        if panel.progressBar then
            panel.progressBar:Show()
            panel.progressBar:SetText(string.format("ETA: %ds", estimatedSeconds))
        end
        if panel.enableSyncBtn then
            panel.enableSyncBtn:Hide()
        end
    else
        -- Normal repair case with unknown ETA - reset to default message
        if panel.message then
            panel.message:SetText("⏳ Admin is syncing data")
        end
        if panel.progressBar then
            panel.progressBar:Show()
            panel.progressBar:SetText("ETA: Unknown")
        end
        if panel.enableSyncBtn then
            panel.enableSyncBtn:Hide()
        end
    end
    
    -- Start timeout (10s inactivity = auto-close) - but not for sync_disabled modes
    if estimatedSeconds ~= "sync_disabled" and estimatedSeconds ~= "sync_disabled_admin" then
        OGRH.SyncRepairUI.StartWaitingTimeout()
    else
        OGRH.Msg("|cffaaaaaa[RH-SyncRepairUI]|r Skipping timeout for sync_disabled mode")
    end
    
    panel:Show()
    OGRH.Msg("|cff00ff00[RH-SyncRepairUI]|r Waiting panel shown successfully")
end

-- Update waiting panel countdown
function OGRH.SyncRepairUI.UpdateWaitingCountdown(remainingSeconds)
    local panel = OGRH.SyncRepairUI.State.waitingPanel
    if not panel or not panel:IsShown() then
        return
    end
    
    if remainingSeconds and remainingSeconds > 0 then
        panel.progressBar:SetText(string.format("ETA: %ds", remainingSeconds))
    else
        panel.progressBar:SetText("ETA: Unknown")
    end
end

-- Hide waiting panel
function OGRH.SyncRepairUI.HideWaitingPanel()
    local panel = OGRH.SyncRepairUI.State.waitingPanel
    if panel then
        -- Cancel timeout
        OGRH.SyncRepairUI.CancelWaitingTimeout()
        panel:Hide()
    end
end

--[[
    ============================================================================
    PHASE 4 - ADMIN BUTTON TOOLTIP
    ============================================================================
]]

-- Build tooltip data from client validations
function OGRH.SyncRepairUI.BuildTooltipData()
    -- This will be populated by SyncSession validation tracking
    -- For now, return empty table
    return {}
end

-- Format tooltip with sync status
function OGRH.SyncRepairUI.FormatTooltipLine(playerName, version, syncStatus, classColor)
    local icon = OGRH.SyncRepairUI.GetSyncStatusIcon(syncStatus)
    local colorCode = string.format("|cff%02x%02x%02x", classColor.r * 255, classColor.g * 255, classColor.b * 255)
    return string.format("%s %s%s|r  (v%s)", icon, colorCode, playerName, version or "?")
end

-- Show tooltip on admin button
function OGRH.SyncRepairUI.ShowAdminButtonTooltip()
    -- TODO: Implement tooltip display on admin button hover
    -- This will hook into MainUI admin button
end

-- Hide tooltip
function OGRH.SyncRepairUI.HideAdminButtonTooltip()
    -- TODO: Implement tooltip hiding
end

--[[
    ============================================================================
    PHASE 4 - AUXILIARY PANEL REGISTRATION
    ============================================================================
]]

-- Register all repair panels with priority 20
function OGRH.SyncRepairUI.RegisterPanels()
    if not OGRH.RegisterAuxiliaryPanel then
        return
    end
    
    -- Create all panels
    local adminPanel = OGRH.SyncRepairUI.CreateAdminPanel()
    local clientPanel = OGRH.SyncRepairUI.CreateClientPanel()
    local waitingPanel = OGRH.SyncRepairUI.CreateWaitingPanel()
    
    -- Register with priority 20
    if adminPanel then
        OGRH.RegisterAuxiliaryPanel(adminPanel, 20)
    end
    if clientPanel then
        OGRH.RegisterAuxiliaryPanel(clientPanel, 20)
    end
    if waitingPanel then
        OGRH.RegisterAuxiliaryPanel(waitingPanel, 20)
    end
end

-- Unregister panels
function OGRH.SyncRepairUI.UnregisterPanels()
    if not OGRH.UnregisterAuxiliaryPanel then
        return
    end
    
    local adminPanel = OGRH.SyncRepairUI.State.adminPanel
    local clientPanel = OGRH.SyncRepairUI.State.clientPanel
    local waitingPanel = OGRH.SyncRepairUI.State.waitingPanel
    
    if adminPanel then
        OGRH.UnregisterAuxiliaryPanel(adminPanel)
    end
    if clientPanel then
        OGRH.UnregisterAuxiliaryPanel(clientPanel)
    end
    if waitingPanel then
        OGRH.UnregisterAuxiliaryPanel(waitingPanel)
    end
end

--[[
    ============================================================================
    PHASE 4 - PANEL TIMEOUT SYSTEM
    ============================================================================
    
    Auto-hide panels after 10s of inactivity to handle edge cases:
    - Admin disconnects during repair
    - Player leaves raid during repair
    - Network packets stop flowing
    
    Timeouts are reset every time a related packet is received.
]]

-- Admin Panel Timeout Functions
function OGRH.SyncRepairUI.StartAdminTimeout()
    -- Cancel any existing timer
    OGRH.SyncRepairUI.CancelAdminTimeout()
    
    -- Record activity
    OGRH.SyncRepairUI.State.timeouts.lastAdminActivity = GetTime()
    
    -- Start new timeout timer
    OGRH.SyncRepairUI.State.timeouts.adminTimer = OGRH.ScheduleTimer(function()
        local panel = OGRH.SyncRepairUI.State.adminPanel
        if panel and panel:IsShown() then
            -- Display timeout message on panel
            if panel.status then
                panel.status:SetText("|cffff9900Status: TIMEOUT - No activity for 10s|r")
            end
            
            OGRH.Msg("|cffff9900[RH-SyncRepair]|r Admin panel timeout - closing in 10 seconds...")
            
            -- Initialize countdown state
            panel.timeoutCountdown = 10
            
            -- Countdown update function
            local function updateCountdown()
                if not panel or not panel:IsShown() or not panel.timeoutCountdown then
                    return
                end
                
                if panel.timeoutCountdown > 0 then
                    -- Update progress bar
                    if panel.progressBar then
                        local pct = (panel.timeoutCountdown / 10) * 100
                        panel.progressBar:SetValue(pct)
                        panel.progressBar:SetText(string.format("|cffff9900Closing in %d seconds...|r", panel.timeoutCountdown))
                    end
                    
                    -- Decrement and schedule next update
                    panel.timeoutCountdown = panel.timeoutCountdown - 1
                    OGRH.ScheduleTimer(updateCountdown, 1.0)
                else
                    -- Countdown finished - close panel
                    panel.timeoutCountdown = nil
                    OGRH.SyncRepairUI.HideAdminPanel()
                    
                    if OGRH.SyncSession and OGRH.SyncSession.CancelSession then
                        OGRH.SyncSession.CancelSession("Admin panel timeout (no activity)")
                    end
                end
            end
            
            -- Start countdown immediately
            updateCountdown()
        end
    end, OGRH.SyncRepairUI.State.timeouts.timeoutDuration)
end

function OGRH.SyncRepairUI.ResetAdminTimeout()
    local panel = OGRH.SyncRepairUI.State.adminPanel
    if not panel or not panel:IsShown() then
        return
    end
    
    -- Record activity
    OGRH.SyncRepairUI.State.timeouts.lastAdminActivity = GetTime()
    
    -- Restart timeout timer
    OGRH.SyncRepairUI.StartAdminTimeout()
end

function OGRH.SyncRepairUI.CancelAdminTimeout()
    if OGRH.SyncRepairUI.State.timeouts.adminTimer then
        OGRH.CancelTimer(OGRH.SyncRepairUI.State.timeouts.adminTimer)
        OGRH.SyncRepairUI.State.timeouts.adminTimer = nil
    end
end

-- Client Panel Timeout Functions
function OGRH.SyncRepairUI.StartClientTimeout()
    -- Cancel any existing timer
    OGRH.SyncRepairUI.CancelClientTimeout()
    
    -- Record activity
    OGRH.SyncRepairUI.State.timeouts.lastClientActivity = GetTime()
    
    -- Start new timeout timer
    OGRH.SyncRepairUI.State.timeouts.clientTimer = OGRH.ScheduleTimer(function()
        local panel = OGRH.SyncRepairUI.State.clientPanel
        if panel and panel:IsShown() then
            -- Display timeout message on panel
            if panel.status then
                panel.status:SetText("|cffff9900Status: TIMEOUT - No activity for 10s|r")
            end
            if panel.eta then
                panel.eta:SetText("|cffff9900Connection lost or admin disconnected|r")
            end
            
            OGRH.Msg("|cffff9900[RH-SyncRepair]|r Client panel timeout - closing in 10 seconds...")
            
            -- Initialize countdown state
            panel.timeoutCountdown = 10
            
            -- Countdown update function
            local function updateCountdown()
                if not panel or not panel:IsShown() or not panel.timeoutCountdown then
                    return
                end
                
                if panel.timeoutCountdown > 0 then
                    -- Update progress bar
                    if panel.progressBar then
                        local pct = (panel.timeoutCountdown / 10) * 100
                        panel.progressBar:SetValue(pct)
                        panel.progressBar:SetText(string.format("|cffff9900Closing in %d seconds...|r", panel.timeoutCountdown))
                    end
                    
                    -- Decrement and schedule next update
                    panel.timeoutCountdown = panel.timeoutCountdown - 1
                    OGRH.ScheduleTimer(updateCountdown, 1.0)
                else
                    -- Countdown finished - close panel
                    panel.timeoutCountdown = nil
                    OGRH.SyncRepairUI.HideClientPanel()
                    
                    if OGRH.SyncRepairHandlers then
                        OGRH.SyncRepairHandlers.currentToken = nil
                    end
                end
            end
            
            -- Start countdown immediately
            updateCountdown()
        end
    end, OGRH.SyncRepairUI.State.timeouts.timeoutDuration)
end

function OGRH.SyncRepairUI.ResetClientTimeout()
    local panel = OGRH.SyncRepairUI.State.clientPanel
    if not panel or not panel:IsShown() then
        return
    end
    
    -- Record activity
    OGRH.SyncRepairUI.State.timeouts.lastClientActivity = GetTime()
    
    -- Restart timeout timer
    OGRH.SyncRepairUI.StartClientTimeout()
end

function OGRH.SyncRepairUI.CancelClientTimeout()
    if OGRH.SyncRepairUI.State.timeouts.clientTimer then
        OGRH.CancelTimer(OGRH.SyncRepairUI.State.timeouts.clientTimer)
        OGRH.SyncRepairUI.State.timeouts.clientTimer = nil
    end
end

-- Waiting Panel Timeout Functions
function OGRH.SyncRepairUI.StartWaitingTimeout()
    -- Cancel any existing timer
    OGRH.SyncRepairUI.CancelWaitingTimeout()
    
    -- Record activity
    OGRH.SyncRepairUI.State.timeouts.lastWaitingActivity = GetTime()
    
    -- Start new timeout timer
    OGRH.SyncRepairUI.State.timeouts.waitingTimer = OGRH.ScheduleTimer(function()
        local panel = OGRH.SyncRepairUI.State.waitingPanel
        if panel and panel:IsShown() then
            -- Display timeout message on panel
            if panel.message then
                panel.message:SetText("|cffff9900⚠ TIMEOUT - No activity for 10s|r")
            end
            
            OGRH.Msg("|cffff9900[RH-SyncRepair]|r Waiting panel timeout - closing in 10 seconds...")
            
            -- Initialize countdown state
            panel.timeoutCountdown = 10
            
            -- Countdown update function
            local function updateCountdown()
                if not panel or not panel:IsShown() or not panel.timeoutCountdown then
                    return
                end
                
                if panel.timeoutCountdown > 0 then
                    -- Update progress bar
                    if panel.progressBar then
                        local pct = (panel.timeoutCountdown / 10) * 100
                        panel.progressBar:SetValue(pct)
                        panel.progressBar:SetText(string.format("|cffff9900Closing in %d seconds...|r", panel.timeoutCountdown))
                    end
                    
                    -- Decrement and schedule next update
                    panel.timeoutCountdown = panel.timeoutCountdown - 1
                    OGRH.ScheduleTimer(updateCountdown, 1.0)
                else
                    -- Countdown finished - close panel
                    panel.timeoutCountdown = nil
                    OGRH.SyncRepairUI.HideWaitingPanel()
                    
                    if OGRH.SyncRepairHandlers then
                        OGRH.SyncRepairHandlers.waitingForRepair = false
                        OGRH.SyncRepairHandlers.waitingToken = nil
                    end
                end
            end
            
            -- Start countdown immediately
            updateCountdown()
        end
    end, OGRH.SyncRepairUI.State.timeouts.timeoutDuration)
end

function OGRH.SyncRepairUI.ResetWaitingTimeout()
    local panel = OGRH.SyncRepairUI.State.waitingPanel
    if not panel or not panel:IsShown() then
        return
    end
    
    -- Record activity
    OGRH.SyncRepairUI.State.timeouts.lastWaitingActivity = GetTime()
    
    -- Restart timeout timer
    OGRH.SyncRepairUI.StartWaitingTimeout()
end

function OGRH.SyncRepairUI.CancelWaitingTimeout()
    if OGRH.SyncRepairUI.State.timeouts.waitingTimer then
        OGRH.CancelTimer(OGRH.SyncRepairUI.State.timeouts.waitingTimer)
        OGRH.SyncRepairUI.State.timeouts.waitingTimer = nil
    end
end

--[[
    ============================================================================
    PHASE 4 - UTILITY
    ============================================================================
]]

-- Get class color for player
function OGRH.SyncRepairUI.GetClassColor(playerName)
    if not playerName then
        return {r=1, g=1, b=1}
    end
    
    -- Try to get class from raid roster
    for i = 1, GetNumRaidMembers() do
        local name, _, _, _, class = GetRaidRosterInfo(i)
        if name == playerName then
            local classColor = RAID_CLASS_COLORS[class]
            if classColor then
                return {r=classColor.r, g=classColor.g, b=classColor.b}
            end
        end
    end
    
    -- Default to white if not found
    return {r=1, g=1, b=1}
end

-- Format sync status icon
function OGRH.SyncRepairUI.GetSyncStatusIcon(status)
    if status == "synced" then
        return "|cff00ff00✓|r"
    elseif status == "out_of_sync" then
        return "|cffff0000✗|r"
    elseif status == "repairing" then
        return "|cffff9900⏳|r"
    else
        return "|cffaaaaaa?|r"
    end
end

--[[
    ============================================================================
    MODULE INITIALIZATION
    ============================================================================
    
    Note: Panels are created lazily on first Show() call.
    This ensures OGRH_Main exists and avoids load-time errors.
]]
