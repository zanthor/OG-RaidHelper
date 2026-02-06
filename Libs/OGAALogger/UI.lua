--[[
    _OGAALogger - User Interface
    
    Log viewer window with copy/paste support and message display.
    750×500px non-resizable window with _OGST-inspired styling.
]]

OGAALogger.UI = OGAALogger.UI or {}

-- UI State
local uiState = {
    frame = nil,
    scrollFrame = nil,
    editBox = nil,
    initialized = false
}

--[[
    Create styled border backdrop (inspired by _OGST)
]]
local function CreateStyledBackdrop()
    return {
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = {left = 4, right = 4, top = 4, bottom = 4}
    }
end

--[[
    Style a button (inspired by _OGST)
]]
local function StyleButton(button)
    button:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 8,
        edgeSize = 12,
        insets = {left = 2, right = 2, top = 2, bottom = 2}
    })
    button:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
    button:SetBackdropBorderColor(0, 0.8, 1, 1)  -- Cyan
    
    -- Hover effect
    button:SetScript("OnEnter", function()
        this:SetBackdropColor(0.2, 0.2, 0.2, 1)
        this:SetBackdropBorderColor(0.2, 1, 1, 1)
    end)
    
    button:SetScript("OnLeave", function()
        this:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
        this:SetBackdropBorderColor(0, 0.8, 1, 1)
    end)
end

--[[
    Initialize the UI
]]
function OGAALogger.UI.Initialize()
    if uiState.initialized then
        return
    end
    
    -- Create main frame
    local frame = CreateFrame("Frame", "OGAALoggerFrame", UIParent)
    frame:SetWidth(750)
    frame:SetHeight(500)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetBackdrop(CreateStyledBackdrop())
    frame:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
    frame:SetBackdropBorderColor(0, 0.8, 1, 1)  -- Cyan
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:Hide()
    
    uiState.frame = frame
    
    -- Title bar
    local titleBar = CreateFrame("Frame", nil, frame)
    titleBar:SetWidth(750)
    titleBar:SetHeight(30)
    titleBar:SetPoint("TOP", frame, "TOP", 0, 0)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function()
        frame:StartMoving()
    end)
    titleBar:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
    end)
    
    -- Title text
    local titleText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("CENTER", titleBar, "CENTER", 0, 0)
    titleText:SetText("|cff00ccffOG|r Auto Addon Logger")
    
    -- Close button (child of titleBar so it's above the draggable area)
    local closeBtn = CreateFrame("Button", nil, titleBar)
    closeBtn:SetWidth(28)
    closeBtn:SetHeight(28)
    closeBtn:SetPoint("TOPRIGHT", titleBar, "TOPRIGHT", -5, -5)
    closeBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
    closeBtn:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
    closeBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight", "ADD")
    closeBtn:SetFrameLevel(titleBar:GetFrameLevel() + 1)
    closeBtn:SetScript("OnClick", function()
        OGAALogger.UI.Hide()
    end)
    
    -- Scroll frame container
    local scrollContainer = CreateFrame("Frame", nil, frame)
    scrollContainer:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -40)
    scrollContainer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 40)
    scrollContainer:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = {left = 3, right = 3, top = 3, bottom = 3}
    })
    scrollContainer:SetBackdropColor(0, 0, 0, 0.8)
    scrollContainer:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    
    -- Scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", "OGAALoggerScrollFrame", scrollContainer, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", scrollContainer, "TOPLEFT", 8, -8)
    scrollFrame:SetPoint("BOTTOMRIGHT", scrollContainer, "BOTTOMRIGHT", -28, 8)
    
    uiState.scrollFrame = scrollFrame
    
    -- Edit box (for copy/paste)
    local editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetWidth(scrollFrame:GetWidth() - 20)
    editBox:SetHeight(5000)  -- Large enough for all content
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetFontObject(GameFontNormalSmall)
    editBox:SetTextColor(1, 1, 1, 1)
    editBox:SetScript("OnEscapePressed", function()
        this:ClearFocus()
    end)
    
    scrollFrame:SetScrollChild(editBox)
    uiState.editBox = editBox
    
    -- Button frame at bottom
    local buttonFrame = CreateFrame("Frame", nil, frame)
    buttonFrame:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, 5)
    buttonFrame:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 5)
    buttonFrame:SetHeight(30)
    
    -- Select All button
    local selectAllBtn = CreateFrame("Button", nil, buttonFrame)
    selectAllBtn:SetWidth(100)
    selectAllBtn:SetHeight(25)
    selectAllBtn:SetPoint("LEFT", buttonFrame, "LEFT", 0, 0)
    StyleButton(selectAllBtn)
    
    local selectAllText = selectAllBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    selectAllText:SetPoint("CENTER", selectAllBtn, "CENTER", 0, 0)
    selectAllText:SetText("Select All")
    
    selectAllBtn:SetScript("OnClick", function()
        editBox:SetFocus()
        editBox:HighlightText()
    end)
    
    -- Clear button
    local clearBtn = CreateFrame("Button", nil, buttonFrame)
    clearBtn:SetWidth(100)
    clearBtn:SetHeight(25)
    clearBtn:SetPoint("LEFT", selectAllBtn, "RIGHT", 10, 0)
    StyleButton(clearBtn)
    
    local clearText = clearBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    clearText:SetPoint("CENTER", clearBtn, "CENTER", 0, 0)
    clearText:SetText("Clear")
    
    clearBtn:SetScript("OnClick", function()
        OGAALogger.ClearMessages()
    end)
    
    -- Show Registrations button
    local regsBtn = CreateFrame("Button", nil, buttonFrame)
    regsBtn:SetWidth(140)
    regsBtn:SetHeight(25)
    regsBtn:SetPoint("LEFT", clearBtn, "RIGHT", 10, 0)
    StyleButton(regsBtn)
    
    local regsText = regsBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    regsText:SetPoint("CENTER", regsBtn, "CENTER", 0, 0)
    regsText:SetText("Show Registrations")
    
    regsBtn:SetScript("OnClick", function()
        OGAALogger.ShowRegistrations()
    end)
    
    -- Message count text
    local countText = buttonFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    countText:SetPoint("RIGHT", buttonFrame, "RIGHT", 0, 0)
    countText:SetTextColor(0.7, 0.7, 0.7, 1)
    uiState.countText = countText
    
    uiState.initialized = true
    
    -- Initial refresh
    OGAALogger.UI.Refresh()
end

--[[
    Refresh the log display
]]
function OGAALogger.UI.Refresh()
    if not uiState.initialized or not uiState.editBox then
        return
    end
    
    local messages = OGAALogger.GetMessages()
    local lines = {}
    
    -- Build formatted text
    for i = 1, table.getn(messages) do
        local msg = messages[i]
        
        -- Format line (messages are pre-formatted and may contain color codes)
        local line
        if msg.isSessionMarker then
            line = string.format("|cff00ccff%s|r", msg.text)  -- Cyan for session markers
        else
            -- Format: [timestamp] [source] message
            line = string.format("[%s] [%s] %s", 
                msg.timestamp, 
                msg.source, 
                msg.text)
        end
        
        table.insert(lines, line)
    end
    
    -- Set text
    uiState.editBox:SetText(table.concat(lines, "\n"))
    
    -- Update count
    if uiState.countText then
        uiState.countText:SetText(string.format("Messages: %d/%d", 
            table.getn(messages), 
            OGAALogger.State.maxMessages))
    end
    
    -- Scroll to top
    uiState.scrollFrame:SetVerticalScroll(0)
end

--[[
    Show the log viewer
]]
function OGAALogger.UI.Show()
    if not uiState.initialized then
        OGAALogger.UI.Initialize()
    end
    
    OGAALogger.UI.Refresh()
    uiState.frame:Show()
end

--[[
    Hide the log viewer
]]
function OGAALogger.UI.Hide()
    if uiState.frame then
        uiState.frame:Hide()
    end
end

--[[
    Toggle log viewer visibility
]]
function OGAALogger.UI.Toggle()
    if not uiState.initialized then
        OGAALogger.UI.Show()
        return
    end
    
    if uiState.frame:IsVisible() then
        OGAALogger.UI.Hide()
    else
        OGAALogger.UI.Show()
    end
end

--[[
    Check if log viewer is shown
]]
function OGAALogger.UI.IsShown()
    return uiState.initialized and uiState.frame and uiState.frame:IsVisible()
end

--[[
    Show registered addons in the log
]]
function OGAALogger.ShowRegistrations()
    local addons = OGAALogger.GetRegisteredAddons()
    
    if table.getn(addons) == 0 then
        OGAALogger.AddMessage("SYSTEM", "|cffffaa00No addons registered for error capture|r")
    else
        OGAALogger.AddMessage("SYSTEM", "|cff00ccffRegistered Addons for Error Capture:|r")
        for i = 1, table.getn(addons) do
            OGAALogger.AddMessage("SYSTEM", string.format("  |cffffff00[%d]|r %s", i, addons[i]))
        end
        OGAALogger.AddMessage("SYSTEM", "|cff888888Use /ogl unreg <number> to remove|r")
    end
    
    -- Show UI if hidden
    if not OGAALogger.UI.IsShown() then
        OGAALogger.UI.Show()
    end
end

-- Public API shortcuts
OGAALogger.Show = OGAALogger.UI.Show
OGAALogger.Hide = OGAALogger.UI.Hide
OGAALogger.Toggle = OGAALogger.UI.Toggle
