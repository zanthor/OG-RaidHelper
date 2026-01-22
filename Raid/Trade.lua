local _G = getfenv(0)
local OGRH = _G.OGRH

-- Item constants
local ITEM_SAND = 19183  -- Hourglass Sand
local SAND_COUNT = 5

-- Current trade selection (does not persist between sessions)
local currentTradeType = nil
local currentTradeItemId = nil
local currentTradeQuantity = nil

-- Trade frame for automated trading
local tradeFrame = CreateFrame("Frame", "OGRH_TradeFrame")
tradeFrame:Hide()
tradeFrame.tick = 0
tradeFrame.interval = 0.10
tradeFrame.state = "IDLE"
tradeFrame.didSplit = false
tradeFrame.placed = false
tradeFrame.dBag = nil
tradeFrame.dSlot = nil

-- Helper functions
local function itemIdFromLink(link)
    if not link then return nil end
    local id = string.match(link, "Hitem:(%d+):")
    return id and tonumber(id) or nil
end

local function findStackExact(itemId, needCount)
    local bag
    for bag = 0, 4 do
        local numSlots = GetContainerNumSlots(bag) or 0
        local slot
        for slot = 1, numSlots do
            local link = GetContainerItemLink(bag, slot)
            if link and itemIdFromLink(link) == itemId then
                local _, count, locked = GetContainerItemInfo(bag, slot)
                if (count or 0) == needCount and not locked then
                    return bag, slot
                end
            end
        end
    end
    return nil, nil
end

local function findSourceStack(itemId, needCount)
    local bag
    for bag = 0, 4 do
        local numSlots = GetContainerNumSlots(bag) or 0
        local slot
        for slot = 1, numSlots do
            local link = GetContainerItemLink(bag, slot)
            if link and itemIdFromLink(link) == itemId then
                local _, count, locked = GetContainerItemInfo(bag, slot)
                if (count or 0) >= needCount and not locked then
                    return bag, slot
                end
            end
        end
    end
    return nil, nil
end

local function findEmptySlot()
    local bag
    for bag = 0, 4 do
        local numSlots = GetContainerNumSlots(bag) or 0
        local slot
        for slot = 1, numSlots do
            local texture, count, locked = GetContainerItemInfo(bag, slot)
            if not texture and not count and not locked then
                return bag, slot
            end
        end
    end
    return nil, nil
end

local function firstOpenTradeSlot()
    local i
    for i = 1, 6 do
        if not GetTradePlayerItemInfo(i) then
            return i
        end
    end
    return nil
end

local function tradeItemButton(slotIndex)
    return getglobal("TradePlayerItem" .. slotIndex .. "ItemButton")
end

local function resetTrade()
    tradeFrame.state = "IDLE"
    tradeFrame.didSplit = false
    tradeFrame.placed = false
    tradeFrame.dBag = nil
    tradeFrame.dSlot = nil
    tradeFrame:Hide()
    ClearCursor()
end

-- Sand trading function
local function runSandTrade()
    if tradeFrame.state ~= "IDLE" then
        OGRH.Msg("Trade already in progress.")
        return
    end
    
    tradeFrame.state = "SAND"
    tradeFrame.tick = tradeFrame.interval
    tradeFrame:Show()
end

-- Generic trade function for any item ID and quantity
local function runTrade(itemId, quantity)
    if tradeFrame.state ~= "IDLE" then
        OGRH.Msg("Trade already in progress.")
        return
    end
    
    -- Check if trade window is open
    if not TradeFrame or not TradeFrame:IsShown() then
        OGRH.Msg("Open the trade window first.")
        return
    end
    
    -- Try to find exact stack of the specified quantity
    local bag, slot = findStackExact(itemId, quantity)
    
    if bag and slot then
        -- We have a stack of the exact quantity, place it in trade
        local tradeSlot = firstOpenTradeSlot()
        if not tradeSlot then
            OGRH.Msg("No free trade slot available.")
            return
        end
        
        PickupContainerItem(bag, slot)
        local btn = tradeItemButton(tradeSlot)
        if not btn then
            ClearCursor()
            return
        end
        
        btn:Click()
        OGRH.Msg("Item placed in trade. Click Trade button to complete.")
    else
        -- Need to split a stack
        local sourceBag, sourceSlot = findSourceStack(itemId, quantity)
        if not sourceBag then
            OGRH.Msg("Not enough items found in bags (need " .. quantity .. ").")
            return
        end
        
        local emptyBag, emptySlot = findEmptySlot()
        if not emptyBag then
            OGRH.Msg("No empty bag slot available for splitting.")
            return
        end
        
        -- Split the stack
        SplitContainerItem(sourceBag, sourceSlot, quantity)
        PickupContainerItem(emptyBag, emptySlot)
        
        -- Wait a moment for split to complete, then place in trade
        local waitFrame = CreateFrame("Frame")
        waitFrame.elapsed = 0
        waitFrame:SetScript("OnUpdate", function()
            waitFrame.elapsed = waitFrame.elapsed + arg1
            if waitFrame.elapsed > 0.5 then
                local bag5, slot5 = findStackExact(itemId, quantity)
                if bag5 and slot5 then
                    local tradeSlot = firstOpenTradeSlot()
                    if tradeSlot then
                        PickupContainerItem(bag5, slot5)
                        local btn = tradeItemButton(tradeSlot)
                        if btn then
                            btn:Click()
                            OGRH.Msg("Item placed in trade. Click Trade button to complete.")
                        end
                    end
                end
                waitFrame:SetScript("OnUpdate", nil)
            end
        end)
    end
end

-- OnUpdate handler for automated trading
tradeFrame:SetScript("OnUpdate", function()
    local elapsed = arg1 or 0
    tradeFrame.tick = tradeFrame.tick + elapsed
    
    if tradeFrame.tick < tradeFrame.interval then
        return
    end
    
    tradeFrame.tick = 0
    
    if tradeFrame.state == "SAND" then
        -- Check if trade window is open
        if not TradeFrame or not TradeFrame:IsShown() then
            OGRH.Msg("Open the trade window first.")
            return resetTrade()
        end
        
        -- Try to find exact stack of 5 sand
        local bag5, slot5 = findStackExact(ITEM_SAND, SAND_COUNT)
        
        if bag5 and slot5 then
            -- We have a stack of 5, place it in trade
            if not tradeFrame.placed then
                local tradeSlot = firstOpenTradeSlot()
                if not tradeSlot then
                    OGRH.Msg("No free trade slot available.")
                    return resetTrade()
                end
                
                PickupContainerItem(bag5, slot5)
                local btn = tradeItemButton(tradeSlot)
                if not btn then
                    return resetTrade()
                end
                
                btn:Click()
                tradeFrame.placed = true
                OGRH.Msg("Sand placed in trade. Click Trade button to complete.")
                return resetTrade()
            end
        else
            -- Need to split a stack
            if not tradeFrame.didSplit then
                local sourceBag, sourceSlot = findSourceStack(ITEM_SAND, SAND_COUNT)
                if not sourceBag then
                    OGRH.Msg("No stack of sand with >= 5 found.")
                    return resetTrade()
                end
                
                local emptyBag, emptySlot = findEmptySlot()
                if not emptyBag then
                    OGRH.Msg("No empty bag slot available.")
                    return resetTrade()
                end
                
                SplitContainerItem(sourceBag, sourceSlot, SAND_COUNT)
                PickupContainerItem(emptyBag, emptySlot)
                tradeFrame.didSplit = true
                tradeFrame.dBag = emptyBag
                tradeFrame.dSlot = emptySlot
                return
            else
                -- Wait for split to complete
                local bag5a, slot5a = findStackExact(ITEM_SAND, SAND_COUNT)
                if not (bag5a and slot5a) then
                    return
                end
            end
        end
    end
end)

-- Export functions to OGRH namespace
OGRH.RunSand = runSandTrade

OGRH.SetTradeType = function(tradeType)
    currentTradeType = tradeType
    OGRH.Msg("Trade set to: " .. tradeType)
end

OGRH.GetTradeType = function()
    return currentTradeType
end

-- Helper to truncate text if it's too long for the button
local function TruncateText(text, maxLength)
    if not text then return "" end
    if string.len(text) <= maxLength then
        return text
    end
    return string.sub(text, 1, maxLength - 2) .. ".."
end

OGRH.SetTradeItem = function(itemId, quantity)
    currentTradeItemId = itemId
    currentTradeQuantity = quantity
    currentTradeType = nil  -- Clear old type when setting specific item
    
    -- Get item name for display
    local itemName = GetItemInfo(itemId)
    local displayName = itemName or ("Item " .. itemId)
    
    if itemName then
        OGRH.Msg("Trade item set to: " .. itemName .. " x" .. quantity)
    else
        OGRH.Msg("Trade item set to: Item " .. itemId .. " x" .. quantity)
    end
    
    -- Update button text if it exists
    local btn = getglobal("OGRH_TradeButton")
    if btn then
        btn:SetText(TruncateText(displayName, 16))
        btn:Enable()
    end
end

OGRH.GetCurrentTradeItemId = function()
    return currentTradeItemId
end

OGRH.ExecuteTrade = function(itemId, quantity)
    -- If called with itemId and quantity, trade those items directly
    if itemId and quantity then
        runTrade(itemId, quantity)
        return
    end
    
    -- Check if we have a stored trade item
    if currentTradeItemId and currentTradeQuantity then
        runTrade(currentTradeItemId, currentTradeQuantity)
        return
    end
    
    -- Legacy behavior: use currentTradeType
    if not currentTradeType then
        OGRH.Msg("Please select a trade item first (click Trade button).")
        return
    end
    
    if currentTradeType == "sand" then
        runSandTrade()
    else
        OGRH.Msg("Trade type '" .. currentTradeType .. "' not yet implemented.")
    end
end

-- Function to show trade menu
local function ShowTradeMenu(anchorBtn)
    if not OGRH_TradeFrameMenu then
        local M = CreateFrame("Frame", "OGRH_TradeFrameMenu", UIParent)
        M:SetFrameStrata("FULLSCREEN_DIALOG")
        M:SetBackdrop({
            bgFile = "Interface/Tooltips/UI-Tooltip-Background",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            edgeSize = 12,
            insets = {left = 4, right = 4, top = 4, bottom = 4}
        })
        M:SetBackdropColor(0, 0, 0, 0.95)
        M:SetWidth(200)
        M:SetHeight(1)
        M:Hide()
        
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
            
            local yOffset = -10
            local buttonHeight = 18
            local buttonSpacing = 6
            
        -- Create buttons for each trade item
        for i, itemData in ipairs(items) do
          local it = CreateFrame("Button", nil, M, "UIPanelButtonTemplate")
          it:SetWidth(180)
          it:SetHeight(buttonHeight)
          OGRH.StyleButton(it)                if i == 1 then
                    it:SetPoint("TOPLEFT", M, "TOPLEFT", 10, yOffset)
                else
                    it:SetPoint("TOPLEFT", M.btns[i-1], "BOTTOMLEFT", 0, -buttonSpacing)
                end
                
                local fs = it:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                fs:SetAllPoints()
                fs:SetJustifyH("CENTER")
                it.fs = fs
                
                local label = itemData.name or ("Item " .. itemData.itemId)
                
                -- Highlight if this is the active trade item
                if itemData.itemId == currentTradeItemId then
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
        OGRH.StyleButton(settingsBtn)            if table.getn(M.btns) > 0 then
                settingsBtn:SetPoint("TOPLEFT", M.btns[table.getn(M.btns)], "BOTTOMLEFT", 0, -buttonSpacing)
            else
                settingsBtn:SetPoint("TOPLEFT", M, "TOPLEFT", 10, yOffset)
            end
            
            local settingsFs = settingsBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
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
    
    local M = OGRH_TradeFrameMenu
    
    -- Toggle menu visibility
    if M:IsVisible() then
        M:Hide()
        return
    end
    
    -- Rebuild menu with current items
    M.Rebuild()
    
    M:ClearAllPoints()
    M:SetPoint("BOTTOMLEFT", anchorBtn, "TOPLEFT", 0, 2)
    M:Show()
end

-- Create OGRH button on the trade frame
local function CreateTradeButton()
    if not TradeFrame then return end
    
    -- Try to find the Trade button to position relative to it
    local tradeButton = getglobal("TradeFrameTradeButton")
    
    local ogrhBtn = CreateFrame("Button", "OGRH_TradeButton", TradeFrame, "UIPanelButtonTemplate")
    ogrhBtn:SetWidth(120)
    ogrhBtn:SetHeight(22)
    
    -- Position to the left of the Trade button
    if tradeButton then
        ogrhBtn:SetPoint("RIGHT", tradeButton, "LEFT", -5, 0)
    else
        -- Fallback position if we can't find the Trade button
        ogrhBtn:SetPoint("BOTTOMRIGHT", TradeFrame, "BOTTOMRIGHT", -150, 16)
    end
    
    -- Set initial text based on whether item is selected
    if currentTradeItemId then
        local itemName = GetItemInfo(currentTradeItemId)
        local displayName = itemName or ("Item " .. currentTradeItemId)
        ogrhBtn:SetText(TruncateText(displayName, 16))
    else
        ogrhBtn:SetText("Select")
    end
    
    -- Register for both left and right clicks
    ogrhBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    
    ogrhBtn:SetScript("OnClick", function()
        if arg1 == "RightButton" then
            -- Right-click: Always show menu
            ShowTradeMenu(ogrhBtn)
        else
            -- Left-click: Execute trade if item selected, otherwise show menu
            if currentTradeItemId then
                if OGRH.ExecuteTrade then
                    OGRH.ExecuteTrade()
                end
            else
                ShowTradeMenu(ogrhBtn)
            end
        end
    end)
    
    -- Update button when trade frame shows
    ogrhBtn:SetScript("OnShow", function()
        if currentTradeItemId then
            local itemName = GetItemInfo(currentTradeItemId)
            local displayName = itemName or ("Item " .. currentTradeItemId)
            this:SetText(TruncateText(displayName, 16))
            this:Enable()
        else
            this:SetText("Select")
            this:Enable()
        end
    end)
    
    return ogrhBtn
end

-- Hook into trade frame show to create button
local tradeFrameHooked = false
local ogrhTradeButton = nil

local hookFrame = CreateFrame("Frame")
hookFrame:RegisterEvent("ADDON_LOADED")
hookFrame:SetScript("OnEvent", function()
    if event == "ADDON_LOADED" and arg1 == "Blizzard_TradeSkillUI" or TradeFrame then
        if not tradeFrameHooked and TradeFrame then
            ogrhTradeButton = CreateTradeButton()
            tradeFrameHooked = true
        end
    end
end)

-- Also try to create immediately if TradeFrame exists
if TradeFrame then
    ogrhTradeButton = CreateTradeButton()
    tradeFrameHooked = true
end

-- DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[RaidHelper]|r Trade module loaded")
