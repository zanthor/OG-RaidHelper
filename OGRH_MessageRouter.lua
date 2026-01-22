-- OGRH_MessageRouter.lua (Turtle-WoW 1.12)
-- Central message routing and handling system for OGAddonMsg integration
-- Routes all addon messages through a unified handler system

OGRH = OGRH or {}
OGRH.MessageRouter = {}

--[[
    Message Router State
]]
OGRH.MessageRouter.State = {
    handlers = {},              -- Registered message handlers
    messageQueue = {},          -- Outgoing message queue
    receivedMessages = {},      -- Recently received messages (for deduplication)
    isInitialized = false       -- Initialization flag
}

--[[
    Handler Registration
]]

-- Register a message handler
-- messageType: Full message type string (e.g., "OGRH_STRUCT_SET_ENCOUNTER")
-- handler: Function(sender, data, channel) to handle the message
function OGRH.MessageRouter.RegisterHandler(messageType, handler)
    if not messageType or not handler then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[RH-MessageRouter]|r Invalid handler registration")
        return false
    end
    
    if not OGRH.IsValidMessageType(messageType) then
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff8800[RH-MessageRouter]|r Registering unknown message type: %s", messageType))
    end
    
    OGRH.MessageRouter.State.handlers[messageType] = handler
    return true
end

-- Unregister a message handler
function OGRH.MessageRouter.UnregisterHandler(messageType)
    if not messageType then return false end
    OGRH.MessageRouter.State.handlers[messageType] = nil
    return true
end

-- Get handler for message type
function OGRH.MessageRouter.GetHandler(messageType)
    if not messageType then return nil end
    return OGRH.MessageRouter.State.handlers[messageType]
end

--[[
    Message Sending
]]

-- Send a message via OGAddonMsg with automatic permission checking
-- Accepts both tables and strings (OGAddonMsg auto-serializes tables)
-- @param messageType string - Message type from OGRH.MessageTypes
-- @param data table or string - Data to send (tables auto-serialized by OGAddonMsg)
-- @param options table - Optional {priority, target, channel, onSuccess, onFailure}
-- @return messageId or nil
function OGRH.MessageRouter.Send(messageType, data, options)
    if not messageType then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[RH-MessageRouter]|r No message type specified")
        return nil
    end
    
    -- Validate message type (strip @target suffix if present for validation)
    local baseMessageType = messageType
    local atPos = string.find(messageType, "@")
    if atPos then
        baseMessageType = string.sub(messageType, 1, atPos - 1)
    end
    
    if not OGRH.IsValidMessageType(baseMessageType) then
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff8800[RH-MessageRouter]|r Sending unknown message type: %s", baseMessageType))
    end
    
    -- Check permissions based on message category
    local category = OGRH.GetMessageCategory(messageType)
    local playerName = UnitName("player")
    
    if category == "STRUCT" then
        -- Structure changes require ADMIN permission
        if not OGRH.CanModifyStructure(playerName) then
            OGRH.HandlePermissionDenied(playerName, "STRUCT change")
            return nil
        end
    elseif category == "ASSIGN" then
        -- Assignment changes require OFFICER or ADMIN permission
        if not OGRH.CanModifyAssignments(playerName) then
            OGRH.HandlePermissionDenied(playerName, "ASSIGN change")
            return nil
        end
    end
    -- SYNC, ADMIN, STATE messages have no permission restrictions (anyone can query)
    
    -- Default options
    options = options or {}
    local priority = options.priority or "NORMAL"
    local target = options.target
    local channel = options.channel
    
    -- Ensure OGAddonMsg is available
    if not OGAddonMsg or not OGAddonMsg.Send then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[RH-MessageRouter]|r OGAddonMsg not available")
        return nil
    end
    
    -- Send via OGAddonMsg
    local msgId = OGAddonMsg.Send(channel, target, messageType, data, {
        priority = priority,
        onSuccess = options.onSuccess,
        onFailure = options.onFailure,
        onComplete = options.onComplete
    })
    
    return msgId
end

-- Send a targeted message to a specific player
-- NOTE: WoW 1.12 does not support WHISPER for addon messages in raids
-- We broadcast to RAID with target prefix, receiver filters by target
function OGRH.MessageRouter.SendTo(targetPlayer, messageType, data, options)
    options = options or {}
    options.target = targetPlayer
    options.channel = nil  -- Use auto-detect (will use RAID)
    
    -- Prepend target to message type for filtering on receive
    local targetedMessageType = messageType .. "@" .. targetPlayer
    
    return OGRH.MessageRouter.Send(targetedMessageType, data, options)
end

-- Broadcast a message to all raid/party members
function OGRH.MessageRouter.Broadcast(messageType, data, options)
    options = options or {}
    options.channel = nil  -- Auto-detect best channel
    
    return OGRH.MessageRouter.Send(messageType, data, options)
end

--[[
    Message Receiving
]]

-- Check if message was recently received (deduplication)
function OGRH.MessageRouter.WasRecentlyReceived(msgId)
    if not msgId then return false end
    
    -- Check if msgId is in recent messages
    for i = 1, table.getn(OGRH.MessageRouter.State.receivedMessages) do
        if OGRH.MessageRouter.State.receivedMessages[i] == msgId then
            return true
        end
    end
    
    return false
end

-- Mark message as received
function OGRH.MessageRouter.MarkReceived(msgId)
    if not msgId then return end
    
    table.insert(OGRH.MessageRouter.State.receivedMessages, msgId)
    
    -- Keep only last 100 messages for deduplication
    while table.getn(OGRH.MessageRouter.State.receivedMessages) > 100 do
        table.remove(OGRH.MessageRouter.State.receivedMessages, 1)
    end
end

-- Handle incoming message from OGAddonMsg
function OGRH.MessageRouter.OnMessageReceived(sender, messageType, data, channel)
    -- Validate sender
    if not sender or sender == UnitName("player") then
        return  -- Ignore messages from self
    end
    
    -- Validate message type
    if not messageType then
        return
    end
    
    -- Check for targeted message (messageType@targetPlayer format)
    local actualMessageType = messageType
    local targetPlayer = nil
    local atPos = string.find(messageType, "@")
    if atPos then
        actualMessageType = string.sub(messageType, 1, atPos - 1)
        targetPlayer = string.sub(messageType, atPos + 1)
        
        -- Filter: only process if we're the target
        if targetPlayer ~= UnitName("player") then
            return
        end
    end
    
    -- Use the actual message type (without target suffix)
    messageType = actualMessageType
    
    -- OGAddonMsg auto-deserializes tables, so data is already in original form
    -- (table if sender sent table, string if sender sent string)
    
    -- Get handler for this message type
    local handler = OGRH.MessageRouter.GetHandler(messageType)
    
    if not handler then
        -- No handler registered - this is normal for some message types
        return
    end
    
    -- Call the handler with data (already deserialized by OGAddonMsg)
    local success, err = pcall(handler, sender, data, channel)
    
    if not success then
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff0000[RH-MessageRouter]|r Handler error for %s: %s", messageType, tostring(err)))
    end
end

--[[
    OGAddonMsg Integration
]]

-- Initialize OGAddonMsg message listener
function OGRH.MessageRouter.InitializeOGAddonMsg()
    if not OGAddonMsg or not OGAddonMsg.RegisterWildcard then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[RH-MessageRouter]|r OGAddonMsg not available for initialization")
        return false
    end
    
    -- Register a wildcard handler for all messages
    OGAddonMsg.RegisterWildcard(function(sender, prefix, data, channel)
        -- Only process OGRH messages
        if string.sub(prefix, 1, 5) == "OGRH_" then
            OGRH.MessageRouter.OnMessageReceived(sender, prefix, data, channel)
        end
    end)
    
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[RH-MessageRouter]|r Registered wildcard handler with OGAddonMsg")
    return true
end

--[[
    Legacy SendAddonMessage Wrapper (for gradual migration)
]]

-- Wrapper for old SendAddonMessage calls - redirects to MessageRouter
function OGRH.SendAddonMessage(msg, channel, target)
    -- Parse legacy message format
    local messageType = msg
    local data = nil
    
    -- Extract data if message has colon or semicolon delimiter
    local colonPos = string.find(msg, ":")
    local semicolonPos = string.find(msg, ";")
    
    if colonPos then
        messageType = string.sub(msg, 1, colonPos - 1)
        data = string.sub(msg, colonPos + 1)
    elseif semicolonPos then
        messageType = string.sub(msg, 1, semicolonPos - 1)
        data = string.sub(msg, semicolonPos + 1)
    end
    
    -- Translate legacy message type to new format
    local newMessageType = OGRH.TranslateLegacyMessage(messageType)
    
    if not newMessageType then
        -- No translation available - use original format with prefix
        newMessageType = "OGRH_LEGACY_" .. messageType
        DEFAULT_CHAT_FRAME:AddMessage(string.format("|cffff8800[RH-MessageRouter]|r Untranslated legacy message: %s", messageType))
    end
    
    -- Send via MessageRouter
    local options = {
        channel = channel,
        target = target,
        priority = "NORMAL"
    }
    
    return OGRH.MessageRouter.Send(newMessageType, data, options)
end

--[[
    Initialization
]]

-- Initialize message router
function OGRH.MessageRouter.Initialize()
    if OGRH.MessageRouter.State.isInitialized then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff8800[RH-MessageRouter]|r Already initialized")
        return false
    end
    
    -- Initialize OGAddonMsg integration
    if not OGRH.MessageRouter.InitializeOGAddonMsg() then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff0000[RH-MessageRouter]|r Failed to initialize OGAddonMsg")
        return false
    end
    
    -- Register default handlers (will be expanded in future phases)
    OGRH.MessageRouter.RegisterDefaultHandlers()
    
    OGRH.MessageRouter.State.isInitialized = true
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[RH-MessageRouter]|r Initialized")
    
    return true
end

-- Register default message handlers
function OGRH.MessageRouter.RegisterDefaultHandlers()
    -- ADMIN messages
    OGRH.MessageRouter.RegisterHandler(OGRH.MessageTypes.ADMIN.TAKEOVER, function(sender, data, channel)
        if data and data.newAdmin then
            OGRH.SetRaidAdmin(data.newAdmin)
            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[RH]|r %s is now the raid admin", data.newAdmin))
        end
    end)
    
    OGRH.MessageRouter.RegisterHandler(OGRH.MessageTypes.ADMIN.ASSIGN, function(sender, data, channel)
        if data and data.newAdmin then
            OGRH.SetRaidAdmin(data.newAdmin)
            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[RH]|r %s assigned %s as raid admin", data.assignedBy or sender, data.newAdmin))
        end
    end)
    
    OGRH.MessageRouter.RegisterHandler(OGRH.MessageTypes.ADMIN.QUERY, function(sender, data, channel)
        -- Respond to admin query with current admin info
        if OGRH.GetRaidAdmin then
            local currentAdmin = OGRH.GetRaidAdmin()
            if currentAdmin then
                OGRH.MessageRouter.SendTo(sender, OGRH.MessageTypes.ADMIN.RESPONSE, {
                    currentAdmin = currentAdmin,
                    timestamp = GetTime(),
                    version = OGRH.VERSION
                }, {priority = "HIGH"})
            end
        end
    end)
    
    OGRH.MessageRouter.RegisterHandler(OGRH.MessageTypes.ADMIN.RESPONSE, function(sender, data, channel)
        -- Receive admin info from query response
        if data and data.currentAdmin then
            OGRH.SetRaidAdmin(data.currentAdmin)
            DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[RH]|r Raid admin is %s", data.currentAdmin))
        end
    end)
    
    OGRH.MessageRouter.RegisterHandler(OGRH.MessageTypes.ADMIN.POLL_VERSION, function(sender, data, channel)
        -- Respond to version poll
        OGRH.MessageRouter.SendTo(sender, OGRH.MessageTypes.ADMIN.POLL_RESPONSE, {
            version = OGRH.VERSION,
            dataVersion = OGRH.GetDataVersion(),
            checksum = OGRH.ComputeChecksum and OGRH.ComputeChecksum(OGRH.GetCurrentEncounter and OGRH.GetCurrentEncounter() or {}) or "UNKNOWN"
        }, {
            priority = "LOW"
        })
    end)
    
    OGRH.MessageRouter.RegisterHandler(OGRH.MessageTypes.ADMIN.READY_REQUEST, function(sender, data, channel)
        -- Only process if we are the raid leader
        if IsRaidLeader and IsRaidLeader() == 1 then
            -- Check if remote ready checks are allowed
            OGRH.EnsureSV()
            if OGRH_SV.allowRemoteReadyCheck then
                -- Set flag to capture ready check responses
                OGRH.readyCheckInProgress = true
                OGRH.readyCheckResponses = {
                    notReady = {},
                    afk = {}
                }
                -- Show timer
                OGRH.ShowReadyCheckTimer()
                DoReadyCheck()
            else
                OGRH.Msg("Remote ready checks are disabled in settings.")
            end
        end
    end)
    
    OGRH.MessageRouter.RegisterHandler(OGRH.MessageTypes.ADMIN.READY_COMPLETE, function(sender, data, channel)
        -- Hide timer when raid leader reports results
        OGRH.HideReadyCheckTimer()
    end)
    
    -- STATE messages
    OGRH.MessageRouter.RegisterHandler(OGRH.MessageTypes.STATE.QUERY_LEAD, function(sender, data, channel)
        -- Respond with current raid lead
        local currentLead = OGRH.GetRaidAdmin and OGRH.GetRaidAdmin() or "Unknown"
        
        OGRH.MessageRouter.SendTo(sender, OGRH.MessageTypes.STATE.RESPONSE_LEAD, {
            lead = currentLead
        }, {
            priority = "LOW"
        })
    end)
    
    OGRH.MessageRouter.RegisterHandler(OGRH.MessageTypes.STATE.CHANGE_ENCOUNTER, function(sender, data, channel)
        -- Data is already deserialized by MessageRouter
        local encounterData = data
        if not encounterData then return end
        
        -- Update local UI to match encounter selection
        if encounterData.raidName and encounterData.encounterName then
            OGRH.EnsureSV()
            OGRH_SV.ui.selectedRaid = encounterData.raidName
            OGRH_SV.ui.selectedEncounter = encounterData.encounterName
            
            -- Update UI button if available
            if OGRH.UpdateEncounterNavButton then
                OGRH.UpdateEncounterNavButton()
            end
            
            -- Update consume monitor if available
            if OGRH.ShowConsumeMonitor then
                OGRH.ShowConsumeMonitor()
            end
        end
    end)
    
    OGRH.MessageRouter.RegisterHandler(OGRH.MessageTypes.SYNC.REQUEST_PARTIAL, function(sender, data, channel)
        -- Only admin should respond to partial sync requests
        if not OGRH.IsRaidAdmin or not OGRH.IsRaidAdmin() then
            return
        end
        
        -- Data already deserialized by OGAddonMsg
        local requestData = data
        if not requestData then return end
        
        -- If data contains raidName and encounterName, sync that specific encounter
        if requestData.raidName and requestData.encounterName then
            if OGRH.BroadcastFullEncounterSync then
                OGRH.BroadcastFullEncounterSync()
            end
        end
    end)
    
    -- ASSIGN delta messages (Phase 3A)
    OGRH.MessageRouter.RegisterHandler(OGRH.MessageTypes.ASSIGN.DELTA_BATCH, function(sender, data, channel)
        -- MessageRouter auto-deserializes, so data is already a table
        local deltaData = data
        
        if not deltaData or type(deltaData) ~= "table" or not deltaData.changes then
            return
        end
        
        -- Apply each change
        for i = 1, table.getn(deltaData.changes) do
            local change = deltaData.changes[i]
            
            if change.type == "SWAP" then
                -- Handle atomic swap operation
                if change.assignData1 and change.assignData2 then
                    local data1 = change.assignData1
                    local data2 = change.assignData2
                    
                    -- Validate both have required fields
                    if data1.raid and data1.encounter and data1.roleIndex and data1.slotIndex and
                       data2.raid and data2.encounter and data2.roleIndex and data2.slotIndex then
                        
                        -- Initialize nested tables
                        if not OGRH_SV.encounterAssignments then OGRH_SV.encounterAssignments = {} end
                        if not OGRH_SV.encounterAssignments[data1.raid] then 
                            OGRH_SV.encounterAssignments[data1.raid] = {} 
                        end
                        if not OGRH_SV.encounterAssignments[data1.raid][data1.encounter] then 
                            OGRH_SV.encounterAssignments[data1.raid][data1.encounter] = {} 
                        end
                        if not OGRH_SV.encounterAssignments[data1.raid][data1.encounter][data1.roleIndex] then 
                            OGRH_SV.encounterAssignments[data1.raid][data1.encounter][data1.roleIndex] = {} 
                        end
                        if not OGRH_SV.encounterAssignments[data1.raid][data1.encounter][data2.roleIndex] then 
                            OGRH_SV.encounterAssignments[data1.raid][data1.encounter][data2.roleIndex] = {} 
                        end
                        
                        -- Apply BOTH assignments atomically (no UI refresh between)
                        OGRH_SV.encounterAssignments[data1.raid][data1.encounter][data1.roleIndex][data1.slotIndex] = change.player1
                        OGRH_SV.encounterAssignments[data2.raid][data2.encounter][data2.roleIndex][data2.slotIndex] = change.player2  -- nil for empty slot
                    end
                end
                
            elseif change.type == "ROLE" then
                -- Apply role change (RolesUI bucket assignments)
                if not OGRH_SV.roles then OGRH_SV.roles = {} end
                OGRH_SV.roles[change.player] = change.newValue
                
            elseif change.type == "ASSIGNMENT" then
                -- Apply assignment changes (check assignmentType to determine what kind)
                
                if change.assignmentType == "RAID_MARK" then
                    -- Apply raid mark change
                    if change.newValue and type(change.newValue) == "table" and change.newValue.assignData then
                        local assignData = change.newValue.assignData
                        if assignData.raid and assignData.encounter and assignData.roleIndex and assignData.slotIndex then
                            -- Initialize nested tables
                            if not OGRH_SV.encounterRaidMarks then OGRH_SV.encounterRaidMarks = {} end
                            if not OGRH_SV.encounterRaidMarks[assignData.raid] then 
                                OGRH_SV.encounterRaidMarks[assignData.raid] = {} 
                            end
                            if not OGRH_SV.encounterRaidMarks[assignData.raid][assignData.encounter] then 
                                OGRH_SV.encounterRaidMarks[assignData.raid][assignData.encounter] = {} 
                            end
                            if not OGRH_SV.encounterRaidMarks[assignData.raid][assignData.encounter][assignData.roleIndex] then 
                                OGRH_SV.encounterRaidMarks[assignData.raid][assignData.encounter][assignData.roleIndex] = {} 
                            end
                            
                            -- Apply the mark
                            local markValue = change.newValue.mark or 0
                            OGRH_SV.encounterRaidMarks[assignData.raid][assignData.encounter][assignData.roleIndex][assignData.slotIndex] = markValue
                        end
                    end
                    
                elseif change.assignmentType == "ASSIGNMENT_NUMBER" then
                    -- Apply assignment number change
                    if change.newValue and type(change.newValue) == "table" and change.newValue.assignData then
                        local assignData = change.newValue.assignData
                        if assignData.raid and assignData.encounter and assignData.roleIndex and assignData.slotIndex then
                            -- Initialize nested tables
                            if not OGRH_SV.encounterAssignmentNumbers then OGRH_SV.encounterAssignmentNumbers = {} end
                            if not OGRH_SV.encounterAssignmentNumbers[assignData.raid] then 
                                OGRH_SV.encounterAssignmentNumbers[assignData.raid] = {} 
                            end
                            if not OGRH_SV.encounterAssignmentNumbers[assignData.raid][assignData.encounter] then 
                                OGRH_SV.encounterAssignmentNumbers[assignData.raid][assignData.encounter] = {} 
                            end
                            if not OGRH_SV.encounterAssignmentNumbers[assignData.raid][assignData.encounter][assignData.roleIndex] then 
                                OGRH_SV.encounterAssignmentNumbers[assignData.raid][assignData.encounter][assignData.roleIndex] = {} 
                            end
                            
                            -- Apply the number
                            local numberValue = change.newValue.number or 0
                            OGRH_SV.encounterAssignmentNumbers[assignData.raid][assignData.encounter][assignData.roleIndex][assignData.slotIndex] = numberValue
                        end
                    end
                    
                elseif change.assignmentType == "ANNOUNCEMENT" then
                    -- Apply announcement change
                    if change.newValue and type(change.newValue) == "table" and change.newValue.announcementData then
                        local announcementData = change.newValue.announcementData
                        if announcementData.raid and announcementData.encounter and announcementData.lineIndex then
                            -- Initialize nested tables
                            if not OGRH_SV.encounterAnnouncements then OGRH_SV.encounterAnnouncements = {} end
                            if not OGRH_SV.encounterAnnouncements[announcementData.raid] then 
                                OGRH_SV.encounterAnnouncements[announcementData.raid] = {} 
                            end
                            if not OGRH_SV.encounterAnnouncements[announcementData.raid][announcementData.encounter] then 
                                OGRH_SV.encounterAnnouncements[announcementData.raid][announcementData.encounter] = {} 
                            end
                            
                            -- Apply the announcement text
                            local textValue = change.newValue.text or ""
                            OGRH_SV.encounterAnnouncements[announcementData.raid][announcementData.encounter][announcementData.lineIndex] = textValue
                        end
                    end
                    
                elseif change.assignmentType == "CONSUME_SELECTION" then
                    -- Apply consume selection change
                    if change.newValue and type(change.newValue) == "table" and change.newValue.consumeData then
                        local consumeData = change.newValue.consumeData
                        if consumeData.raid and consumeData.encounter and consumeData.roleIndex and consumeData.slotIndex then
                            -- Get the role from encounterMgmt.roles
                            OGRH.EnsureSV()
                            if not OGRH_SV.encounterMgmt then OGRH_SV.encounterMgmt = {raids = {}, roles = {}} end
                            if not OGRH_SV.encounterMgmt.roles then OGRH_SV.encounterMgmt.roles = {} end
                            if not OGRH_SV.encounterMgmt.roles[consumeData.raid] then 
                                OGRH_SV.encounterMgmt.roles[consumeData.raid] = {} 
                            end
                            if not OGRH_SV.encounterMgmt.roles[consumeData.raid][consumeData.encounter] then 
                                OGRH_SV.encounterMgmt.roles[consumeData.raid][consumeData.encounter] = {column1 = {}, column2 = {}} 
                            end
                            
                            local encounterRoles = OGRH_SV.encounterMgmt.roles[consumeData.raid][consumeData.encounter]
                            local column1 = encounterRoles.column1 or {}
                            local column2 = encounterRoles.column2 or {}
                            
                            -- Find the role based on roleIndex (1-based across both columns)
                            local role = nil
                            if consumeData.roleIndex <= table.getn(column1) then
                                role = column1[consumeData.roleIndex]
                            else
                                role = column2[consumeData.roleIndex - table.getn(column1)]
                            end
                            
                            if role then
                                -- Initialize consumes array if needed
                                if not role.consumes then
                                    role.consumes = {}
                                end
                                
                                -- Apply the consume selection
                                role.consumes[consumeData.slotIndex] = change.newValue.consume
                            end
                        end
                    end
                
                elseif change.assignmentType == "ENCOUNTER_ROLE" then
                    -- Extract encounter assignment data from newValue table
                    local assignData = change.newValue
                    if type(assignData) == "table" and assignData.raid and assignData.encounter and 
                       assignData.roleIndex and assignData.slotIndex then
                        
                        -- Initialize nested tables
                        if not OGRH_SV.encounterAssignments then OGRH_SV.encounterAssignments = {} end
                        if not OGRH_SV.encounterAssignments[assignData.raid] then 
                            OGRH_SV.encounterAssignments[assignData.raid] = {} 
                        end
                        if not OGRH_SV.encounterAssignments[assignData.raid][assignData.encounter] then 
                            OGRH_SV.encounterAssignments[assignData.raid][assignData.encounter] = {} 
                        end
                        if not OGRH_SV.encounterAssignments[assignData.raid][assignData.encounter][assignData.roleIndex] then 
                            OGRH_SV.encounterAssignments[assignData.raid][assignData.encounter][assignData.roleIndex] = {} 
                        end
                        
                        -- Apply the assignment
                        OGRH_SV.encounterAssignments[assignData.raid][assignData.encounter][assignData.roleIndex][assignData.slotIndex] = assignData.playerName
                    end
                else
                    -- Generic assignment (fallback for other types)
                    if OGRH.SetPlayerAssignment then
                        OGRH.SetPlayerAssignment(change.player, {
                            type = change.assignmentType,
                            value = change.newValue
                        })
                    end
                end
                
            elseif change.type == "GROUP" then
                -- Apply group change (if group assignment system exists)
                -- (Implementation pending)
            end
        end
        
        -- Update Encounter Planning UI if open (must be done after all changes applied)
        local encounterFrame = OGRH_EncounterFrame or _G["OGRH_EncounterFrame"]
        if encounterFrame and encounterFrame:IsShown() then
            -- Refresh role containers (includes assignments, marks, numbers, and announcements)
            if encounterFrame.RefreshRoleContainers then
                encounterFrame.RefreshRoleContainers()
            end
            
            -- Also refresh announcement EditBoxes specifically if they exist and the change affects current selection
            if encounterFrame.announcementLines and encounterFrame.selectedRaid and encounterFrame.selectedEncounter then
                for i = 1, table.getn(deltaData.changes) do
                    local change = deltaData.changes[i]
                    if change.type == "ANNOUNCEMENT" and change.newValue and change.newValue.announcementData then
                        local announcementData = change.newValue.announcementData
                        -- Only update if this announcement is for the currently selected encounter
                        if announcementData.raid == encounterFrame.selectedRaid and 
                           announcementData.encounter == encounterFrame.selectedEncounter then
                            local lineIndex = announcementData.lineIndex
                            if lineIndex and lineIndex >= 1 and lineIndex <= table.getn(encounterFrame.announcementLines) then
                                encounterFrame.announcementLines[lineIndex]:SetText(change.newValue.text or "")
                            end
                        end
                    end
                end
            end
        end
        
        -- Update RolesUI if open
        local rolesFrame = OGRH.rolesFrame or _G["OGRH_RolesFrame"]
        if rolesFrame and rolesFrame:IsShown() and rolesFrame.UpdatePlayerLists then
            rolesFrame.UpdatePlayerLists()
        end
        
        -- Update data version if provided
        if deltaData.version and OGRH.Versioning and OGRH.Versioning.UpdateDataVersion then
            OGRH.Versioning.UpdateDataVersion("SYNC", deltaData.version)
        end
    end)
    
    OGRH.MessageRouter.RegisterHandler(OGRH.MessageTypes.ASSIGN.DELTA_PLAYER, function(sender, data, channel)
        -- Handle individual player assignment delta (for backwards compatibility)
        -- Data already deserialized by OGAddonMsg
        local changeData = data
        if not changeData then return end
        
        OGRH.SetPlayerAssignment(changeData.player, {
            type = changeData.assignmentType,
            value = changeData.newValue
        })
    end)
    
    OGRH.MessageRouter.RegisterHandler(OGRH.MessageTypes.ASSIGN.DELTA_ROLE, function(sender, data, channel)
        -- Handle individual role delta (modern format only)
        -- Data already deserialized by OGAddonMsg
        local changeData = data
        
        if not changeData or not changeData.player or not changeData.newValue then
            return
        end
        
        if not OGRH_SV.roles then OGRH_SV.roles = {} end
        OGRH_SV.roles[changeData.player] = changeData.newValue
        
        -- Update UI if open
        local frame = OGRH.rolesFrame or _G["OGRH_RolesFrame"]
        if frame and frame:IsShown() and frame.RefreshColumnDisplays then
            frame.RefreshColumnDisplays()
        end
    end)
    
    OGRH.MessageRouter.RegisterHandler(OGRH.MessageTypes.ASSIGN.DELTA_GROUP, function(sender, data, channel)
        -- Handle individual group delta
        -- Data already deserialized by OGAddonMsg
        local changeData = data
        if not changeData then return end
        
        -- Placeholder for group assignment feature
    end)

    -- Item 10: Addon Poll (version/checksum detection for raid lead selection)
    OGRH.MessageRouter.RegisterHandler(OGRH.MessageTypes.ADMIN.POLL_VERSION, function(sender, data, channel)
        -- Don't respond to our own poll (we add ourselves manually in PollAddonUsers)
        local playerName = UnitName("player")
        if sender == playerName then
            return
        end
        
        -- Only respond if in a raid
        if GetNumRaidMembers() == 0 then
            return
        end
        
        -- Randomize response delay 0-2 seconds to spread out 40 raid member responses
        local delay = math.random() * 2
        OGRH.ScheduleFunc(function()
            -- Calculate checksum for ALL structure data
            local checksum = "0"
            if OGRH.CalculateAllStructureChecksum then
                checksum = OGRH.CalculateAllStructureChecksum()
            end
            
            -- Send response with version and checksum
            local response = {
                version = OGRH.VERSION,
                checksum = checksum
            }
            OGRH.MessageRouter.Broadcast(OGRH.MessageTypes.ADMIN.POLL_RESPONSE, response)
        end, delay)
    end)

    OGRH.MessageRouter.RegisterHandler(OGRH.MessageTypes.ADMIN.POLL_RESPONSE, function(sender, data, channel)
        if OGRH.HandleAddonPollResponse then
            local version = data.version or "Unknown"
            local checksum = data.checksum or "0"
            OGRH.HandleAddonPollResponse(sender, version, checksum)
        end
    end)

    -- Item 11: Raid Admin/Lead Change Notification
    OGRH.MessageRouter.RegisterHandler(OGRH.MessageTypes.STATE.CHANGE_LEAD, function(sender, data, channel)
        if OGRH.SetRaidAdmin then
            local adminName = data.adminName
            if adminName then
                -- Pass true to suppress re-broadcast (we're receiving from network)
                OGRH.SetRaidAdmin(adminName, true)
            end
        end
    end)
    
    -- Auto-Promote Request Handler
    OGRH.MessageRouter.RegisterHandler(OGRH.MessageTypes.ADMIN.PROMOTE_REQUEST, function(sender, data, channel)
        -- Only process if we are the raid leader
        if not IsRaidLeader or IsRaidLeader() ~= 1 then
            return
        end
        
        local playerToPromote = data.playerName
        if not playerToPromote or playerToPromote == "" then
            return
        end
        
        -- Find the player in the raid and promote them
        local numRaid = GetNumRaidMembers()
        for i = 1, numRaid do
            local name, rank = GetRaidRosterInfo(i)
            if name == playerToPromote and rank == 0 then
                PromoteToAssistant(playerToPromote)
                DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00OGRH:|r Auto-promoted %s to assistant (requested by %s).", playerToPromote, sender))
                break
            end
        end
    end)
    
    -- More handlers will be added in future phases
end

--[[
    Debug Commands
]]

-- Debug: Print registered handlers
function OGRH.MessageRouter.DebugPrintHandlers()
    DEFAULT_CHAT_FRAME:AddMessage("[OGRH] === Registered Message Handlers ===")
    
    local count = 0
    for messageType, handler in pairs(OGRH.MessageRouter.State.handlers) do
        DEFAULT_CHAT_FRAME:AddMessage(string.format("[OGRH]   %s", messageType))
        count = count + 1
    end
    
    DEFAULT_CHAT_FRAME:AddMessage(string.format("[OGRH] Total: %d handlers", count))
    DEFAULT_CHAT_FRAME:AddMessage("[OGRH] === End Handlers ===")
end

-- Debug: Print recent received messages
function OGRH.MessageRouter.DebugPrintReceivedMessages()
    DEFAULT_CHAT_FRAME:AddMessage("[OGRH] === Recent Received Messages ===")
    
    if table.getn(OGRH.MessageRouter.State.receivedMessages) == 0 then
        DEFAULT_CHAT_FRAME:AddMessage("[OGRH] No messages received")
    else
        for i = 1, table.getn(OGRH.MessageRouter.State.receivedMessages) do
            DEFAULT_CHAT_FRAME:AddMessage(string.format("[OGRH]   %s", OGRH.MessageRouter.State.receivedMessages[i]))
        end
    end
    
    DEFAULT_CHAT_FRAME:AddMessage("[OGRH] === End Messages ===")
end

DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00[RH-MessageRouter]|r Loaded")
