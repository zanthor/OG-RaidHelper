--[[
    OGAddonMsg - Stats Panel
    Native WoW 1.12 API stats display with OGST-style visuals
]]

-- Panel state
local statsPanel = nil
local isPanelVisible = false

-- Update interval (in seconds)
local UPDATE_INTERVAL = 0.5
local timeSinceLastUpdate = 0

--[[
    Create Stats Panel
]]
local function CreateStatsPanel()
    if statsPanel then
        return statsPanel
    end
    
    -- Main frame
    local frame = CreateFrame("Frame", "OGAddonMsg_StatsPanel", UIParent)
    frame:SetWidth(280)
    frame:SetHeight(200)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetMovable(1)
    frame:EnableMouse(1)
    frame:SetClampedToScreen(1)
    frame:SetFrameStrata("DIALOG")
    
    -- Backdrop (OGST style - dark with tooltip border)
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    frame:SetBackdropColor(0, 0, 0, 0.85)
    
    -- Title bar background
    local titleBG = frame:CreateTexture(nil, "BACKGROUND")
    titleBG:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -8)
    titleBG:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -8)
    titleBG:SetHeight(24)
    titleBG:SetTexture(0, 0, 0, 0.7)
    
    -- Title text
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -12)
    title:SetText("OGAddonMsg Stats")
    title:SetTextColor(0.8, 1, 0.8)
    
    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame)
    closeBtn:SetWidth(20)
    closeBtn:SetHeight(20)
    closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, -10)
    closeBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
    closeBtn:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
    closeBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight", "ADD")
    closeBtn:SetScript("OnClick", function()
        OGAddonMsg.HideStatsPanel()
    end)
    
    -- Drag functionality
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function()
        this:StartMoving()
    end)
    frame:SetScript("OnDragStop", function()
        this:StopMovingOrSizing()
    end)
    
    -- Stat labels (left column)
    local yOffset = -44
    local lineHeight = 18
    
    local labels = {
        "Messages:",
        "Bytes:",
        "Chunks:",
        "Reassembled:",
        "Queue:",
        "Retries:",
        "Failures:"
    }
    
    frame.labels = {}
    for i = 1, table.getn(labels) do
        local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, yOffset)
        label:SetText(labels[i])
        label:SetTextColor(0.7, 0.7, 0.7)
        label:SetJustifyH("LEFT")
        frame.labels[i] = label
        yOffset = yOffset - lineHeight
    end
    
    -- Stat values (right column)
    yOffset = -44
    frame.values = {}
    for i = 1, table.getn(labels) do
        local value = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        value:SetPoint("TOPLEFT", frame, "TOPLEFT", 100, yOffset)
        value:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -16, yOffset)
        value:SetText("0")
        value:SetTextColor(1, 1, 1)
        value:SetJustifyH("LEFT")
        frame.values[i] = value
        yOffset = yOffset - lineHeight
    end
    
    -- Update function
    frame:SetScript("OnUpdate", function()
        timeSinceLastUpdate = timeSinceLastUpdate + arg1
        if timeSinceLastUpdate >= UPDATE_INTERVAL then
            timeSinceLastUpdate = 0
            OGAddonMsg.UpdateStatsPanel()
        end
    end)
    
    statsPanel = frame
    frame:Hide()
    
    return frame
end

--[[
    Update Stats Panel
]]
function OGAddonMsg.UpdateStatsPanel()
    if not statsPanel or not statsPanel:IsVisible() then
        return
    end
    
    local stats = OGAddonMsg.stats
    
    -- Format large numbers
    local function FormatBytes(bytes)
        if bytes >= 1048576 then
            return string.format("%.1fM", bytes / 1048576)
        elseif bytes >= 1024 then
            return string.format("%.1fK", bytes / 1024)
        else
            return tostring(bytes)
        end
    end
    
    -- Update values
    statsPanel.values[1]:SetText(string.format("%d sent, %d rcvd", 
        stats.messagesSent, stats.messagesReceived))
    
    statsPanel.values[2]:SetText(string.format("%s sent, %s rcvd",
        FormatBytes(stats.bytesSent), FormatBytes(stats.bytesReceived)))
    
    statsPanel.values[3]:SetText(string.format("%d sent, %d rcvd",
        stats.chunksSent, stats.chunksReceived))
    
    statsPanel.values[4]:SetText(string.format("%d messages",
        stats.messagesReassembled))
    
    -- Queue depth with color coding
    local queueText = string.format("%d msgs (%.1fs)",
        stats.queueDepth, stats.queueTimeEstimate)
    statsPanel.values[5]:SetText(queueText)
    if stats.queueTimeEstimate > 5 then
        statsPanel.values[5]:SetTextColor(1, 0.5, 0)  -- Orange warning
    elseif stats.queueTimeEstimate > 2 then
        statsPanel.values[5]:SetTextColor(1, 1, 0)    -- Yellow caution
    else
        statsPanel.values[5]:SetTextColor(1, 1, 1)    -- White normal
    end
    
    statsPanel.values[6]:SetText(string.format("%d req, %d sent, %d ignored",
        stats.retriesRequested, stats.retriesSent, stats.ignored))
    
    -- Failures with color coding
    statsPanel.values[7]:SetText(tostring(stats.failures))
    if stats.failures > 0 then
        statsPanel.values[7]:SetTextColor(1, 0, 0)    -- Red
    else
        statsPanel.values[7]:SetTextColor(0.5, 1, 0.5)  -- Green
    end
end

--[[
    Public API
]]
function OGAddonMsg.ShowStatsPanel()
    if not statsPanel then
        CreateStatsPanel()
    end
    
    statsPanel:Show()
    isPanelVisible = true
    OGAddonMsg.UpdateStatsPanel()
end

function OGAddonMsg.HideStatsPanel()
    if statsPanel then
        statsPanel:Hide()
        isPanelVisible = false
    end
end

function OGAddonMsg.ToggleStatsPanel()
    if isPanelVisible then
        OGAddonMsg.HideStatsPanel()
    else
        OGAddonMsg.ShowStatsPanel()
    end
end

function OGAddonMsg.IsStatsPanelVisible()
    return isPanelVisible
end
