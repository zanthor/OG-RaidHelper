--[[
    OGAddonMsg - Chunker
    Message chunking, reassembly, and hash verification
]]

-- Constants
local MAX_CHUNK_SIZE = 200  -- Conservative limit for SendAddonMessage
local HEADER_OVERHEAD = 39  -- 1M + msgId(4) + chunk(4) + total(4) + hash(4) + chunkHash(4) + prefix + tab

-- Initialize reassembly buffer
OGAddonMsg.reassembly = {}

--[[
    Message Chunking
]]
local function GenerateMsgId()
    -- Generate unique 4-character message ID using time and random
    local chars = "0123456789abcdefghijklmnopqrstuvwxyz"
    local id = ""
    for i = 1, 4 do
        local idx = math.random(1, string.len(chars))
        id = id .. string.sub(chars, idx, idx)
    end
    return id
end

local function ComputeHash(data)
    -- Simple hash for WoW 1.12 (no real CRC available)
    local hash = 0
    for i = 1, string.len(data) do
        hash = mod(hash + string.byte(data, i) * i, 65536)
    end
    return string.format("%04x", hash)
end

function OGAddonMsg.ChunkMessage(prefix, data)
    -- Split message into chunks that fit within SendAddonMessage limits
    -- Returns: msgId, chunks table, isMultiChunk
    
    local msgId = GenerateMsgId()
    local hash = ComputeHash(data)
    
    -- Calculate available space per chunk
    local prefixSize = string.len(prefix)
    local dataPerChunk = MAX_CHUNK_SIZE - HEADER_OVERHEAD - prefixSize
    
    if string.len(data) <= dataPerChunk then
        -- Single chunk message
        local message = string.format("1S%s%s\t%s", msgId, prefix, data)
        return msgId, {message}, false
    end
    
    -- Multi-chunk message
    local chunks = {}
    local totalChunks = math.ceil(string.len(data) / dataPerChunk)
    
    for i = 1, totalChunks do
        local startPos = (i - 1) * dataPerChunk + 1
        local endPos = math.min(i * dataPerChunk, string.len(data))
        local chunkData = string.sub(data, startPos, endPos)
        
        -- Compute per-chunk hash for integrity verification
        local chunkHash = ComputeHash(chunkData)
        
        local message = string.format("1M%s%04d%04d%s%s%s\t%s",
            msgId, i, totalChunks, hash, chunkHash, prefix, chunkData)
        
        table.insert(chunks, message)
    end
    
    return msgId, chunks, true
end

--[[
    Message Parsing
]]
local function ParseMessageHeader(message)
    -- Parse the message header to determine type and extract metadata
    -- Returns: version, msgType, msgId, prefix, data, (chunkNum, totalChunks, hash for multi-chunk)
    
    local version = string.sub(message, 1, 1)
    local msgType = string.sub(message, 2, 2)
    
    if msgType == "S" then
        -- Single chunk: 1S[msgId:4][prefix]\t[data]
        local msgId = string.sub(message, 3, 6)
        local _, _, prefix, data = string.find(message, "^1S%w%w%w%w([^%s]+)\t(.*)$")
        return version, msgType, msgId, prefix, data, nil, nil, nil
        
    elseif msgType == "M" then
        -- Multi-chunk: 1M[msgId:4][chunk:3][total:3][fullHash:4][chunkHash:4][prefix]\t[data]
        -- Positions: 1-2=1M, 3-6=msgId, 7-9=chunk, 10-12=total, 13-16=hash, 17-20=chunkHash, 21+=prefix
        local msgId = string.sub(message, 3, 6)
        local chunkNum = tonumber(string.sub(message, 7, 9))
        -- Multi-chunk: 1M[msgId:4][chunk:4][total:4][fullHash:4][chunkHash:4][prefix]\t[data]
        local msgId = string.sub(message, 3, 6)
        local chunkNum = tonumber(string.sub(message, 7, 10))
        local totalChunks = tonumber(string.sub(message, 11, 14))
        local hash = string.sub(message, 15, 18)
        local chunkHash = string.sub(message, 19, 22)
        
        -- Find tab separator
        local tabPos = string.find(message, "\t", 23)
        local prefix = tabPos and string.sub(message, 23, tabPos - 1) or ""
        local data = tabPos and string.sub(message, tabPos + 1) or ""
        
        return version, msgType, msgId, prefix, data, chunkNum, totalChunks, hash, chunkHash
        
    elseif msgType == "R" then
        -- Retry request: 1R[msgId:4][missing]
        local msgId = string.sub(message, 3, 6)
        local missing = string.sub(message, 7)
        return version, msgType, msgId, nil, missing, nil, nil, nil
    end
    
    return nil, nil, nil, nil, nil, nil, nil, nil
end

--[[
    Message Reassembly
]]
function OGAddonMsg.ProcessIncomingMessage(addonPrefix, message, channel, sender)
    -- Parse and process incoming addon messages
    -- Handle single-chunk and multi-chunk messages
    
    if OGAddonMsg_Config.debug then
        DEFAULT_CHAT_FRAME:AddMessage(string.format("OGAddonMsg: RX from %s via %s: %s", 
            sender, channel, string.sub(message, 1, 50)), 0.7, 0.7, 1)
    end
    
    -- Update stats
    OGAddonMsg.stats.messagesReceived = OGAddonMsg.stats.messagesReceived + 1
    OGAddonMsg.stats.bytesReceived = OGAddonMsg.stats.bytesReceived + string.len(message)
    
    -- Parse message header
    local version, msgType, msgId, prefix, data, chunkNum, totalChunks, hash, chunkHash = ParseMessageHeader(message)
    
    if not version or version ~= "1" then
        if OGAddonMsg_Config.debug then
            DEFAULT_CHAT_FRAME:AddMessage("OGAddonMsg: Unknown message version", 1, 0, 0)
        end
        return
    end
    
    if msgType == "S" then
        -- Single-chunk message - check for duplicates then dispatch
        if OGAddonMsg.IsDuplicate(msgId, sender, prefix, data) then
            OGAddonMsg.stats.ignored = OGAddonMsg.stats.ignored + 1
            return  -- Skip duplicate
        end
        
        OGAddonMsg.stats.chunksReceived = OGAddonMsg.stats.chunksReceived + 1
        OGAddonMsg.DispatchToHandlers(sender, prefix, data, channel)
        
    elseif msgType == "M" then
        -- Multi-chunk message - store and reassemble
        OGAddonMsg.stats.chunksReceived = OGAddonMsg.stats.chunksReceived + 1
        OGAddonMsg.OnChunkReceived(sender, msgId, chunkNum, totalChunks, hash, chunkHash, prefix, data, channel)
        
    elseif msgType == "R" then
        -- Retry request
        OGAddonMsg.OnRetryRequest(sender, msgId, data)
    end
end

function OGAddonMsg.OnChunkReceived(sender, msgId, chunkNum, totalChunks, hash, chunkHash, prefix, data, channel)
    -- Initialize reassembly buffer first (before validation)
    local entry = OGAddonMsg.reassembly[msgId]
    
    if not entry then
        -- New message
        entry = {
            sender = sender,
            prefix = prefix,
            channel = channel,
            totalChunks = totalChunks,
            hash = hash,
            chunks = {},
            receivedCount = 0,
            firstReceived = GetTime(),
            retryAttempts = {}
        }
        OGAddonMsg.reassembly[msgId] = entry
    end
    
    -- Hash verification with detailed debugging
    if chunkHash then
        local computedChunkHash = ComputeHash(data)
        if computedChunkHash ~= chunkHash then
            -- Detailed debug output
            DEFAULT_CHAT_FRAME:AddMessage(
                string.format("[HASH FAIL] Chunk %d/%d msgId=%s", chunkNum, totalChunks, msgId),
                1, 0, 0
            )
            DEFAULT_CHAT_FRAME:AddMessage(
                string.format("  Expected: %s, Got: %s", chunkHash, computedChunkHash),
                1, 0.5, 0
            )
            DEFAULT_CHAT_FRAME:AddMessage(
                string.format("  Data length: %d, First 20 bytes: %s", 
                    string.len(data), string.sub(data, 1, 20)),
                1, 0.5, 0
            )
            OGAddonMsg.stats.failures = OGAddonMsg.stats.failures + 1
            -- Don't return - accept the chunk anyway and let full message hash catch corruption
        end
    end
    
    -- Store chunk if not duplicate
    if not entry.chunks[chunkNum] then
        entry.chunks[chunkNum] = data
        entry.receivedCount = entry.receivedCount + 1
        entry.lastReceived = GetTime()
        
        -- Debug completion check
        if entry.receivedCount == entry.totalChunks then
            DEFAULT_CHAT_FRAME:AddMessage(
                string.format("[DEBUG] All %d chunks received for %s, calling CompleteMessage",
                    entry.totalChunks, msgId),
                0, 1, 1
            )
        end
        
        if OGAddonMsg_Config.debug then
            DEFAULT_CHAT_FRAME:AddMessage(
                string.format("OGAddonMsg: Chunk %d/%d for %s", chunkNum, totalChunks, msgId),
                0.5, 0.5, 1
            )
        end
    end
    
    -- Debug before completion check
    DEFAULT_CHAT_FRAME:AddMessage(
        string.format("[DEBUG] OnChunkReceived END: msgId=%s, receivedCount=%d, totalChunks=%d",
            msgId, entry.receivedCount, entry.totalChunks),
        1, 1, 0
    )
    
    -- Check if complete
    if entry.receivedCount == entry.totalChunks then
        DEFAULT_CHAT_FRAME:AddMessage("[DEBUG] CALLING CompleteMessage", 0, 1, 0)
        OGAddonMsg.CompleteMessage(msgId, entry)
    else
        DEFAULT_CHAT_FRAME:AddMessage(
            string.format("[DEBUG] NOT COMPLETE: %d/%d chunks", entry.receivedCount, entry.totalChunks),
            1, 0.5, 0
        )
    end
end

function OGAddonMsg.CompleteMessage(msgId, entry)
    -- Verify all chunks present before concatenation
    for i = 1, entry.totalChunks do
        if not entry.chunks[i] then
            DEFAULT_CHAT_FRAME:AddMessage(
                string.format("OGAddonMsg: Incomplete message %s, missing chunk %d/%d",
                    msgId, i, entry.totalChunks),
                1, 0.5, 0
            )
            return
        end
    end
    
    -- Concatenate all chunks
    local fullData = ""
    for i = 1, entry.totalChunks do
        fullData = fullData .. entry.chunks[i]
    end
    
    -- Verify full message hash
    local computedHash = ComputeHash(fullData)
    if computedHash ~= entry.hash then
        -- With per-chunk hashing, this should only happen if chunk order is wrong
        -- Don't auto-retry large messages - log and clean up instead
        DEFAULT_CHAT_FRAME:AddMessage(
            string.format("OGAddonMsg: Hash failure for %s (expected %s, got %s) - per-chunk verification should have caught this",
                msgId, entry.hash, computedHash),
            1, 0, 0
        )
        OGAddonMsg.stats.failures = OGAddonMsg.stats.failures + 1
        OGAddonMsg.reassembly[msgId] = nil
        return
    end
    
    -- Check for duplicate (full message)
    if OGAddonMsg.IsDuplicate(msgId, entry.sender, entry.prefix, fullData) then
        if OGAddonMsg_Config.debug then
            DEFAULT_CHAT_FRAME:AddMessage("OGAddonMsg: Duplicate reassembled message", 1, 1, 0)
        end
        OGAddonMsg.stats.ignored = OGAddonMsg.stats.ignored + 1
        OGAddonMsg.reassembly[msgId] = nil
        return
    end
    
    -- Successfully reassembled
    OGAddonMsg.stats.messagesReassembled = OGAddonMsg.stats.messagesReassembled + 1
    
    if OGAddonMsg_Config.debug then
        DEFAULT_CHAT_FRAME:AddMessage(
            string.format("OGAddonMsg: Reassembled %s (%d chunks, %d bytes)", 
                msgId, entry.totalChunks, string.len(fullData)),
            0.5, 1, 0.5
        )
    end
    
    -- Dispatch to handlers
    OGAddonMsg.DispatchToHandlers(entry.sender, entry.prefix, fullData, entry.channel)
    
    -- Clean up
    OGAddonMsg.reassembly[msgId] = nil
end

function OGAddonMsg.CleanupReassemblyBuffer()
    -- Remove incomplete messages that have timed out
    local now = GetTime()
    local timeout = OGAddonMsg_Config.timeout
    
    for msgId, entry in pairs(OGAddonMsg.reassembly) do
        -- Use lastReceived instead of firstReceived - timeout should be since LAST activity
        local lastActivity = entry.lastReceived or entry.firstReceived
        if lastActivity and (now - lastActivity) > timeout then
            -- Timed out
            if OGAddonMsg_Config.debug then
                DEFAULT_CHAT_FRAME:AddMessage(
                    string.format("OGAddonMsg: Message %s timed out (%d/%d chunks)", 
                        msgId, entry.receivedCount, entry.totalChunks),
                    1, 0.5, 0
                )
            end
            OGAddonMsg.reassembly[msgId] = nil
            OGAddonMsg.stats.failures = OGAddonMsg.stats.failures + 1
            DEFAULT_CHAT_FRAME:AddMessage(
                string.format("OGAddonMsg: Timeout failure (total: %d)", OGAddonMsg.stats.failures),
                1, 0.5, 0
            )
        end
    end
end
