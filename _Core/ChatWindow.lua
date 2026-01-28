--[[
    ChatWindow.lua - Dedicated OGRH chat window management
    
    This file loads FIRST to ensure the chat window is available
    before any other addon messages are sent.
    
    Features:
    - Auto-creates OGRH chat window on load
    - Removes all default channels and message types
    - Provides OGRH.ChatMsg() for dedicated window output
    - Falls back to DEFAULT_CHAT_FRAME if window unavailable
--]]

OGRH = OGRH or {}
OGRH._ogrhChatFrame = nil
OGRH._ogrhChatFrameIndex = nil
OGRH._chatWindowEnabled = true  -- Always enabled for now
OGRH._chatMessageQueue = {}     -- Queue messages until window ready

-- ============================================
-- CHAT WINDOW CREATION
-- ============================================
function OGRH.CreateChatWindow()
    -- Check if already exists (including hidden frames)
    local existingFrame = nil
    local existingIndex = nil
    
    for i = 1, NUM_CHAT_WINDOWS do
        local frame = getglobal("ChatFrame" .. i)
        if frame then
            local tab = getglobal("ChatFrame" .. i .. "Tab")
            if tab then
                local tabText = tab:GetText()
                -- Check for OGRH window (visible OR hidden)
                if tabText and tabText == "OGRH" then
                    existingFrame = frame
                    existingIndex = i
                    -- If hidden, show it
                    if not frame:IsShown() then
                        frame:Show()
                    end
                    break
                end
            end
        end
    end
    
    if existingFrame then
        OGRH._ogrhChatFrame = existingFrame
        OGRH._ogrhChatFrameIndex = existingIndex
        OGRH.Msg("|cff66ff66[RH-ChatWindow]|r Using existing chat window (ChatFrame" .. existingIndex .. ")")
        return existingFrame
    end
    
    -- Create new window only if none found
    local newFrame = FCF_OpenNewWindow("OGRH")
    if not newFrame then
        OGRH.Msg("|cffFF0000[ChatWindow] Failed to create chat window|r")
        return nil
    end
    
    -- Find the index
    local frameIndex = nil
    for i = 1, NUM_CHAT_WINDOWS do
        if getglobal("ChatFrame" .. i) == newFrame then
            frameIndex = i
            break
        end
    end
    
    OGRH._ogrhChatFrame = newFrame
    OGRH._ogrhChatFrameIndex = frameIndex
    
    OGRH.Msg("|cff66ff66[RH-ChatWindow]|r Created NEW chat window (ChatFrame" .. (frameIndex or "?") .. ")")
    
    -- If pfUI detected, refresh layout
    if pfUI and pfUI.chat and pfUI.chat.RefreshChat then
        pfUI.chat.RefreshChat()
    end
    
    -- Remove channels and message types
    if frameIndex then
        -- Remove channels
        local channels = {GetChatWindowChannels(frameIndex)}
        for i = 1, table.getn(channels), 2 do
            local channelName = channels[i]
            if channelName then
                RemoveChatWindowChannel(frameIndex, channelName)
            end
        end
        
        -- Remove message groups
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
    end
    
    return newFrame
end

-- ============================================
-- MESSAGE HANDLER
-- ============================================
-- Send message to OGRH window or fallback to default
function OGRH.ChatMsg(text, r, g, b)
    if OGRH._chatWindowEnabled and OGRH._ogrhChatFrame then
        OGRH._ogrhChatFrame:AddMessage(text, r or 1, g or 1, b or 1)
    else
        DEFAULT_CHAT_FRAME:AddMessage(text, r or 1, g or 1, b or 1)
    end
end

-- Override OGRH.Msg to use chat window (will be defined in Core.lua, but we provide fallback)
local originalMsg = OGRH.Msg
OGRH.Msg = function(text, r, g, b)
    -- Always add [OG] prefix
    local formattedText = "|cff66ccff[OG]|r" .. tostring(text)
    
    if OGRH._chatWindowEnabled and OGRH._ogrhChatFrame then
        OGRH.ChatMsg(formattedText, r, g, b)
    elseif OGRH._chatWindowEnabled and not OGRH._ogrhChatFrame then
        -- Window not ready yet, queue the message
        table.insert(OGRH._chatMessageQueue, {text = formattedText, r = r, g = g, b = b})
    elseif originalMsg then
        originalMsg(text, r, g, b)
    else
        DEFAULT_CHAT_FRAME:AddMessage(formattedText, r or 1, g or 1, b or 1)
    end
end

-- Flush queued messages to window
local function FlushMessageQueue()
    if OGRH._ogrhChatFrame and OGRH._chatMessageQueue then
        for i = 1, table.getn(OGRH._chatMessageQueue) do
            local msg = OGRH._chatMessageQueue[i]
            OGRH.ChatMsg(msg.text, msg.r, msg.g, msg.b)
        end
        OGRH._chatMessageQueue = {}
    end
end

-- ============================================
-- AUTO-INITIALIZATION
-- ============================================
local chatWindowFrame = CreateFrame("Frame")
chatWindowFrame:RegisterEvent("ADDON_LOADED")
chatWindowFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

local hasInitialized = false
local pfUILoaded = false

chatWindowFrame:SetScript("OnEvent", function()
    if event == "ADDON_LOADED" and arg1 == "OG-RaidHelper" then
        -- Create window immediately when addon loads (before pfUI)
        OGRH.CreateChatWindow()
        FlushMessageQueue()  -- Flush any queued messages
        OGRH.Msg("|cff66ff66[RH-ChatWindow]|r Chat window created (before pfUI)")
        
    elseif event == "ADDON_LOADED" and arg1 == "pfUI" then
        -- pfUI just loaded - wait a moment for it to initialize, then clean our window
        pfUILoaded = true
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[OGRH]|r pfUI detected - will clean channels after initialization")
        
        -- Schedule cleanup after pfUI initializes (1 second delay)
        if OGRH.ScheduleTimer then
            OGRH.ScheduleTimer(function()
                if OGRH._ogrhChatFrameIndex then
                    -- Remove channels that pfUI added
                    local channels = {GetChatWindowChannels(OGRH._ogrhChatFrameIndex)}
                    for i = 1, table.getn(channels), 2 do
                        local channelName = channels[i]
                        if channelName then
                            RemoveChatWindowChannel(OGRH._ogrhChatFrameIndex, channelName)
                        end
                    end
                    
                    -- Remove message groups
                    local messageGroups = {
                        "SAY", "YELL", "EMOTE",
                        "PARTY", "RAID", "GUILD", "OFFICER",
                        "WHISPER",
                        "CHANNEL",
                        "SYSTEM"
                    }
                    
                    for i = 1, table.getn(messageGroups) do
                        RemoveChatWindowMessages(OGRH._ogrhChatFrameIndex, messageGroups[i])
                    end
                    
                    -- Dock into pfUI layout
                    if pfUI and pfUI.chat then
                        if pfUI.chat.SetupFrame then
                            pfUI.chat.SetupFrame(OGRH._ogrhChatFrame)
                        end
                        if pfUI.chat.RefreshChat then
                            pfUI.chat.RefreshChat()
                        end
                    end
                    
                    OGRH.Msg("|cff66ff66[RH-ChatWindow]|r Cleaned channels and docked into pfUI")
                end
            end, 1.0)
        else
            -- Fallback if ScheduleTimer not available yet - use simple frame timer
            local cleanupFrame = CreateFrame("Frame")
            local elapsed = 0
            cleanupFrame:SetScript("OnUpdate", function()
                elapsed = elapsed + arg1
                if elapsed >= 1.0 then
                    cleanupFrame:SetScript("OnUpdate", nil)
                    
                    if OGRH._ogrhChatFrameIndex then
                        local channels = {GetChatWindowChannels(OGRH._ogrhChatFrameIndex)}
                        for i = 1, table.getn(channels), 2 do
                            local channelName = channels[i]
                            if channelName then
                                RemoveChatWindowChannel(OGRH._ogrhChatFrameIndex, channelName)
                            end
                        end
                        
                        local messageGroups = {
                            "SAY", "YELL", "EMOTE",
                            "PARTY", "RAID", "GUILD", "OFFICER",
                            "WHISPER",
                            "CHANNEL",
                            "SYSTEM"
                        }
                        
                        for i = 1, table.getn(messageGroups) do
                            RemoveChatWindowMessages(OGRH._ogrhChatFrameIndex, messageGroups[i])
                        end
                        
                        -- Dock into pfUI layout
                        if pfUI and pfUI.chat then
                            if pfUI.chat.SetupFrame then
                                pfUI.chat.SetupFrame(OGRH._ogrhChatFrame)
                            end
                            if pfUI.chat.RefreshChat then
                                pfUI.chat.RefreshChat()
                            end
                        end
                        
                        OGRH.Msg("|cff66ff66[RH-ChatWindow]|r Cleaned channels and docked into pfUI")
                    end
                end
            end)
        end
        
    elseif event == "PLAYER_ENTERING_WORLD" and not hasInitialized then
        -- Ensure window exists after entering world (in case it was closed)
        if not OGRH._ogrhChatFrame or not OGRH._ogrhChatFrame:IsShown() then
            OGRH.CreateChatWindow()
        end
        hasInitialized = true
    end
end)

-- Success message (will be queued until window exists)
OGRH.Msg("|cff66ff66[RH-ChatWindow]|r module loaded")
