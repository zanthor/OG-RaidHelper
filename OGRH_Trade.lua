local _G = getfenv(0)
local OGRH = _G.OGRH

-- Item constants
local ITEM_SAND = 19183  -- Hourglass Sand
local SAND_COUNT = 5

-- Current trade selection (does not persist between sessions)
local currentTradeType = nil

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

OGRH.ExecuteTrade = function()
    if not currentTradeType then
        OGRH.Msg("Please select a trade type first (right-click Trade button).")
        return
    end
    
    if currentTradeType == "sand" then
        runSandTrade()
    else
        OGRH.Msg("Trade type '" .. currentTradeType .. "' not yet implemented.")
    end
end

-- Create OGRH button on the trade frame
local function CreateTradeButton()
    if not TradeFrame then return end
    
    -- Try to find the Trade button to position relative to it
    local tradeButton = getglobal("TradeFrameTradeButton")
    
    local ogrhBtn = CreateFrame("Button", "OGRH_TradeButton", TradeFrame, "UIPanelButtonTemplate")
    ogrhBtn:SetWidth(60)
    ogrhBtn:SetHeight(22)
    
    -- Position directly above the Trade button
    if tradeButton then
        ogrhBtn:SetPoint("BOTTOM", tradeButton, "TOP", 0, 2)
    else
        -- Fallback position if we can't find the Trade button
        ogrhBtn:SetPoint("BOTTOMRIGHT", TradeFrame, "BOTTOMRIGHT", -20, 50)
    end
    
    ogrhBtn:SetText("OGRH")
    
    ogrhBtn:SetScript("OnClick", function()
        if OGRH.ExecuteTrade then
            OGRH.ExecuteTrade()
        end
    end)
    
    -- Show/hide with trade frame
    ogrhBtn:SetScript("OnShow", function()
        if not currentTradeType then
            this:Disable()
        else
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

print("|cFFFFFF00OGRH:|r Trade module loaded")
