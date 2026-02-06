--[[
    OGAddonMsg - Retry
    Retry buffer management and self-healing
]]

-- Initialize retry buffer
OGAddonMsg.retryBuffer = {}

-- Duplicate detection (hash-based with 60s window)
OGAddonMsg.duplicateHashes = {}

--[[
    Duplicate Detection
]]
local function ComputeMessageHash(msgId, sender, prefix, data)
    -- Generate a hash for duplicate detection
    -- Combine msgId, sender, prefix, and first 100 chars of data
    -- msgId ensures each intentional send is unique while still catching network duplicates
    local hashInput = msgId .. ":" .. sender .. ":" .. prefix .. ":" .. string.sub(data, 1, 100)
    local hash = 0
    for i = 1, string.len(hashInput) do
        hash = mod(hash + string.byte(hashInput, i) * i, 65536)
    end
    return string.format("%04x", hash)
end

function OGAddonMsg.IsDuplicate(msgId, sender, prefix, data)
    local hash = ComputeMessageHash(msgId, sender, prefix, data)
    local now = GetTime()
    
    -- Check if we've seen this recently
    if OGAddonMsg.duplicateHashes[hash] then
        local lastSeen = OGAddonMsg.duplicateHashes[hash]
        if now - lastSeen < 60 then
            -- Duplicate within 60 second window
            if OGAddonMsg_Config.debug then
                OGAddonMsg.Msg(
                    string.format("OGAddonMsg: Duplicate message from %s (hash: %s)", sender, hash)
                )
            end
            return true
        end
    end
    
    -- Not a duplicate, record it
    OGAddonMsg.duplicateHashes[hash] = now
    return false
end

function OGAddonMsg.CleanupDuplicateHashes()
    -- Remove old entries (older than 60 seconds)
    local now = GetTime()
    for hash, timestamp in pairs(OGAddonMsg.duplicateHashes) do
        if now - timestamp > 60 then
            OGAddonMsg.duplicateHashes[hash] = nil
        end
    end
end

--[[
    Retry Buffer Management
]]
function OGAddonMsg.StoreForRetry(msgId, chunks)
    -- Store chunks for potential retry
    local now = GetTime()
    local retainTime = OGAddonMsg_Config.retainTime
    
    OGAddonMsg.retryBuffer[msgId] = {
        chunks = chunks,
        sentTime = now,
        expiresAt = now + retainTime
    }
    
    if OGAddonMsg_Config.debug then
        OGAddonMsg.Msg(
            string.format("OGAddonMsg: Stored %s for retry (%d chunks)", msgId, table.getn(chunks))
        )
    end
end

function OGAddonMsg.SendRetryRequest(sender, msgId, missingChunks, channel)
    -- Send a retry request to the sender
    -- Format: 1R[msgId][target]:[missing chunks comma-separated]
    -- target is included so other clients know to ignore this request
    
    local missingStr = ""
    if missingChunks and table.getn(missingChunks) > 0 then
        -- Build comma-separated list
        for i = 1, table.getn(missingChunks) do
            if i > 1 then
                missingStr = missingStr .. ","
            end
            missingStr = missingStr .. missingChunks[i]
        end
    end
    
    local retryMsg = string.format("1R%s%s:%s", msgId, sender, missingStr)
    
    -- Send via the same channel the original message came from
    -- Turtle WoW doesn't support WHISPER for addon messages
    local success = pcall(SendAddonMessage, "OGAM", retryMsg, channel or "RAID")
    
    -- Increment stat regardless of success (we attempted the retry)
    OGAddonMsg.stats.retriesRequested = OGAddonMsg.stats.retriesRequested + 1
    
    if success then
        OGAddonMsg.Msg(
            string.format("OGAddonMsg: Retry requested from %s via %s (total: %d)", sender, channel or "RAID", OGAddonMsg.stats.retriesRequested)
        )
    else
        OGAddonMsg.Msg(
            string.format("OGAddonMsg: Retry request to %s failed (total: %d)", sender, OGAddonMsg.stats.retriesRequested)
        )
    end
end

function OGAddonMsg.OnRetryRequest(sender, msgId, data)
    -- Handle retry request from receiver
    -- Format: [target]:[missing chunks]
    -- Parse target and missing chunks
    
    OGAddonMsg.Msg(
        string.format("[DEBUG] OnRetryRequest: sender=%s msgId=%s data='%s'", sender, msgId, data or "nil")
    )
    
    local target, missingStr = string.match(data, "^([^:]+):(.*)$")
    
    OGAddonMsg.Msg(
        string.format("[DEBUG] Parsed: target='%s' missingStr='%s' myName='%s'", 
            target or "nil", missingStr or "nil", UnitName("player"))
    )
    
    if not target then
        -- Old format without target, process anyway
        missingStr = data
        OGAddonMsg.Msg("[DEBUG] No target found, using old format")
    elseif target ~= UnitName("player") then
        -- Not for us, ignore
        OGAddonMsg.Msg(
            string.format("[DEBUG] Ignoring retry request for %s (I am %s)", target, UnitName("player"))
        )
        return
    else
        OGAddonMsg.Msg("[DEBUG] Target matches, processing retry")
    end
    
    -- Re-enqueue requested chunks with HIGH priority
    
    local entry = OGAddonMsg.retryBuffer[msgId]
    
    OGAddonMsg.Msg(
        string.format("[DEBUG] RetryBuffer lookup for msgId=%s: %s", msgId, entry and "FOUND" or "NOT FOUND")
    )
    
    if not entry then
        OGAddonMsg.Msg(
            "OGAddonMsg: Retry request for expired message from " .. sender
        )
        OGAddonMsg.Msg("[DEBUG] Available msgIds in retryBuffer:")
        for id, _ in pairs(OGAddonMsg.retryBuffer) do
            OGAddonMsg.Msg(string.format("  - %s", id))
        end
        return
    end
    
    -- Parse missing chunks
    local missingChunks = {}
    if missingStr and missingStr ~= "" then
        -- Parse comma-separated list
        for numStr in string.gfind(missingStr, "(%d+)") do
            table.insert(missingChunks, tonumber(numStr))
        end
    end
    
    -- Determine which chunks to resend
    local chunksToSend = {}
    if table.getn(missingChunks) > 0 then
        -- Specific chunks requested
        for i = 1, table.getn(missingChunks) do
            local chunkNum = missingChunks[i]
            if entry.chunks[chunkNum] then
                table.insert(chunksToSend, entry.chunks[chunkNum])
            end
        end
    else
        -- All chunks requested
        chunksToSend = entry.chunks
    end
    
    if OGAddonMsg_Config.debug then
        OGAddonMsg.Msg(
            string.format("OGAddonMsg: Honoring retry request from %s for %s (%d chunks)", 
                sender, msgId, table.getn(chunksToSend))
        )
    end
    
    -- Re-enqueue chunks (HIGH priority for retries)
    -- Send back via RAID/PARTY/GUILD since WHISPER not supported
    local replyChannel = OGAddonMsg.DetectBestChannel()
    for i = 1, table.getn(chunksToSend) do
        OGAddonMsg.Enqueue("HIGH", chunksToSend[i], replyChannel, nil, nil)
    end
    
    OGAddonMsg.stats.retriesSent = OGAddonMsg.stats.retriesSent + 1
    OGAddonMsg.Msg(
        string.format("OGAddonMsg: Retry sent to %s (%d chunks, total: %d)", sender, table.getn(chunksToSend), OGAddonMsg.stats.retriesSent)
    )
end

function OGAddonMsg.CleanupRetryBuffer()
    -- Remove expired entries
    local now = GetTime()
    
    for msgId, entry in pairs(OGAddonMsg.retryBuffer) do
        if now >= entry.expiresAt then
            OGAddonMsg.retryBuffer[msgId] = nil
            
            if OGAddonMsg_Config.debug then
                OGAddonMsg.Msg("OGAddonMsg: Expired retry buffer for " .. msgId)
            end
        end
    end
end

--[[
    Self-Healing
]]
function OGAddonMsg.CheckIncompleteMessages()
    -- Called on PLAYER_ENTERING_WORLD
    -- Check reassembly buffer for incomplete messages and request retries
    
    local incomplete = 0
    
    for msgId, entry in pairs(OGAddonMsg.reassembly) do
        if entry.receivedCount < entry.totalChunks then
            incomplete = incomplete + 1
            
            -- Determine which chunks are missing
            local missingChunks = {}
            for i = 1, entry.totalChunks do
                if not entry.chunks[i] then
                    table.insert(missingChunks, i)
                end
            end
            
            -- Send retry request
            OGAddonMsg.SendRetryRequest(entry.sender, msgId, missingChunks, entry.channel)
            
            if OGAddonMsg_Config.debug then
                OGAddonMsg.Msg(
                    string.format("OGAddonMsg: Requesting retry for incomplete %s (%d/%d chunks, missing: %d)",
                        msgId, entry.receivedCount, entry.totalChunks, table.getn(missingChunks))
                )
            end
        end
    end
    
    if incomplete > 0 then
        OGAddonMsg.Msg(
            string.format("OGAddonMsg: Found %d incomplete messages after zone, requesting retries", incomplete)
        )
    end
end
