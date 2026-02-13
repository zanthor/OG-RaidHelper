--[[
    OGAddonMsg - Public API
    Send functions and convenience methods
]]

--[[
    Channel Auto-Detection
]]
function OGAddonMsg.DetectBestChannel()
    -- Detect best available channel for broadcasting
    -- RAID > PARTY > GUILD
    
    if GetNumRaidMembers() > 0 then
        return "RAID"
    elseif GetNumPartyMembers() > 0 then
        return "PARTY"
    elseif IsInGuild() then
        return "GUILD"
    end
    
    return nil
end

-- Local alias for internal use
local DetectBestChannel = OGAddonMsg.DetectBestChannel

--[[
    Public API - Sending Messages
    
    Accepts both tables and strings for 'data' parameter:
    - Tables: Auto-serialized to string (recommended)
    - Strings: Passed through as-is (for raw text messages)
]]
function OGAddonMsg.Send(channel, target, prefix, data, options)
    -- Send a message through the addon communication system
    -- Returns: msgId
    
    if not OGAddonMsg.initialized then
        OGAddonMsg.Msg("OGAddonMsg: Not initialized")
        return nil
    end
    
    if not prefix or not data then
        OGAddonMsg.Msg("OGAddonMsg: Missing prefix or data")
        return nil
    end
    
    -- Default options
    options = options or {}
    local priority = options.priority or "NORMAL"
    
    -- Auto-serialize tables to strings (library owns wire format)
    local serializedData = data
    local dataType = type(data)
    
    if dataType == "table" then
        serializedData = OGAddonMsg.Serialize(data)
        if not serializedData or type(serializedData) ~= "string" then
            OGAddonMsg.Msg("OGAddonMsg: Failed to serialize table")
            if options.onFailure then
                options.onFailure("Serialization failed")
            end
            return nil
        end
    elseif dataType ~= "string" then
        OGAddonMsg.Msg(
            string.format("OGAddonMsg: data must be table or string, got %s", dataType))
        if options.onFailure then
            options.onFailure("Invalid data type")
        end
        return nil
    end
    
    -- Prepend type flag to preserve original type for receiver
    -- Format: "T:" for table, "S:" for string
    local wireData = (dataType == "table" and "T:" or "S:") .. serializedData
    
    -- Auto-detect channel if not specified
    if not channel then
        channel = DetectBestChannel()
        if not channel then
            if options.onFailure then
                options.onFailure("No available channel")
            end
            return nil
        end
    end
    
    -- TURTLE WOW: Addon messages don't support WHISPER channel
    -- Redirect to RAID/PARTY/GUILD and warn in debug mode
    if channel == "WHISPER" then
        local originalChannel = channel
        local originalTarget = target
        channel = DetectBestChannel()
        target = nil  -- Clear target since we're broadcasting
        
        if not channel then
            OGAddonMsg.Msg(
                "OGAddonMsg: Cannot send - WHISPER unsupported and no RAID/PARTY/GUILD available")
            if options.onFailure then
                options.onFailure("WHISPER unsupported, no alternative channel available")
            end
            return nil
        end
        
        if OGAddonMsg_Config.debug then
            OGAddonMsg.Msg(
                string.format("OGAddonMsg: WHISPER to %s redirected to %s (TWoW limitation)",
                    originalTarget or "?", channel))
        end
    end
    
    -- Chunk the message (wireData is always string at this point)
    local msgId, chunks, isMultiChunk = OGAddonMsg.ChunkMessage(prefix, wireData)
    
    if OGAddonMsg_Config.debug then
        OGAddonMsg.Msg(
            string.format("OGAddonMsg: Sending %s to %s (%d chunks)", 
                prefix, channel, table.getn(chunks)))
    end
    
    -- Enqueue all chunks
    local totalChunks = table.getn(chunks)
    local sentChunks = 0
    
    -- Store chunks for retry if multi-chunk
    if isMultiChunk then
        OGAddonMsg.StoreForRetry(msgId, chunks)
    end
    
    for i = 1, totalChunks do
        local chunkCallbacks = {}
        
        -- Add success callback for progress tracking
        if options.onProgress or options.onSuccess then
            chunkCallbacks.onSuccess = function()
                sentChunks = sentChunks + 1
                
                if options.onProgress then
                    options.onProgress(sentChunks, totalChunks)
                end
                
                -- Call final success when all chunks sent
                if sentChunks == totalChunks and options.onSuccess then
                    options.onSuccess()
                end
            end
        end
        
        -- Add failure callback
        if options.onFailure then
            chunkCallbacks.onFailure = options.onFailure
        end
        
        -- Enqueue chunk
        OGAddonMsg.Enqueue(priority, chunks[i], channel, target, chunkCallbacks)
    end
    
    return msgId
end

function OGAddonMsg.Broadcast(prefix, data, options)
    -- Broadcast to all available channels (RAID > PARTY > GUILD)
    -- Returns: msgId
    
    return OGAddonMsg.Send(nil, nil, prefix, data, options)
end

function OGAddonMsg.SendTo(playerName, prefix, data, options)
    -- Send direct message to a specific player
    -- NOTE: Turtle WoW doesn't support WHISPER for addon messages.
    -- This will redirect to RAID > PARTY > GUILD and broadcast to all players.
    -- Returns: msgId
    
    -- Warn user if not in debug mode
    if not OGAddonMsg_Config.debug then
        OGAddonMsg.Msg(
            string.format("OGAddonMsg: SendTo(%s) will broadcast to RAID/PARTY/GUILD (TWoW doesn't support direct player targeting)",
                playerName))
    end
    
    return OGAddonMsg.Send("WHISPER", playerName, prefix, data, options)
end
