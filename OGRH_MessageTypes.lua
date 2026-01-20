-- OGRH_MessageTypes.lua (Turtle-WoW 1.12)
-- Defines all message types for OG-RaidHelper addon communication
-- Uses _OGAddonMsg for reliable addon-to-addon data sync

OGRH = OGRH or {}
OGRH.MessageTypes = {}

-- Message type prefix for all OG-RaidHelper messages
OGRH.MESSAGE_PREFIX = "OGRH"

--[[
    Message Category Enums
    Format: {CATEGORY}_{ACTION}_{SUBJECT}
]]

-- STRUCT: Structure-related messages (encounters, groups, roles)
OGRH.MessageTypes.STRUCT = {
    -- Encounter structure operations
    SET_ENCOUNTER = "OGRH_STRUCT_SET_ENCOUNTER",
    UPDATE_ENCOUNTER = "OGRH_STRUCT_UPDATE_ENCOUNTER",
    DELETE_ENCOUNTER = "OGRH_STRUCT_DELETE_ENCOUNTER",
    REQUEST_ENCOUNTER = "OGRH_STRUCT_REQUEST_ENCOUNTER",
    RESPONSE_ENCOUNTER = "OGRH_STRUCT_RESPONSE_ENCOUNTER",
    
    -- Group structure operations
    SET_GROUP = "OGRH_STRUCT_SET_GROUP",
    UPDATE_GROUP = "OGRH_STRUCT_UPDATE_GROUP",
    DELETE_GROUP = "OGRH_STRUCT_DELETE_GROUP",
    
    -- Role structure operations
    SET_ROLE = "OGRH_STRUCT_SET_ROLE",
    UPDATE_ROLE = "OGRH_STRUCT_UPDATE_ROLE",
    DELETE_ROLE = "OGRH_STRUCT_DELETE_ROLE"
}

-- ASSIGN: Assignment-related messages (player assignments, role assignments)
OGRH.MessageTypes.ASSIGN = {
    -- Player assignment operations
    SET_PLAYER = "OGRH_ASSIGN_SET_PLAYER",
    CLEAR_PLAYER = "OGRH_ASSIGN_CLEAR_PLAYER",
    UPDATE_PLAYER = "OGRH_ASSIGN_UPDATE_PLAYER",
    
    -- Role assignment operations
    SET_ROLE = "OGRH_ASSIGN_SET_ROLE",
    CLEAR_ROLE = "OGRH_ASSIGN_CLEAR_ROLE",
    
    -- Group assignment operations
    SET_GROUP = "OGRH_ASSIGN_SET_GROUP",
    CLEAR_GROUP = "OGRH_ASSIGN_CLEAR_GROUP",
    
    -- Batch operations
    BATCH_UPDATE = "OGRH_ASSIGN_BATCH_UPDATE",
    
    -- Delta operations (incremental changes)
    DELTA_PLAYER = "OGRH_ASSIGN_DELTA_PLAYER",
    
    -- Request/Response
    REQUEST_ASSIGNMENTS = "OGRH_ASSIGN_REQUEST_ASSIGNMENTS",
    RESPONSE_ASSIGNMENTS = "OGRH_ASSIGN_RESPONSE_ASSIGNMENTS"
}

-- SYNC: Synchronization messages (checksums, full sync, delta sync)
OGRH.MessageTypes.SYNC = {
    -- Full sync operations
    REQUEST_FULL = "OGRH_SYNC_REQUEST_FULL",
    RESPONSE_FULL = "OGRH_SYNC_RESPONSE_FULL",
    
    -- Partial sync operations
    REQUEST_PARTIAL = "OGRH_SYNC_REQUEST_PARTIAL",
    RESPONSE_PARTIAL = "OGRH_SYNC_RESPONSE_PARTIAL",
    
    -- Delta sync operations
    REQUEST_DELTA = "OGRH_SYNC_REQUEST_DELTA",
    RESPONSE_DELTA = "OGRH_SYNC_RESPONSE_DELTA",
    DELTA = "OGRH_SYNC_DELTA", -- Broadcast delta changes
    
    -- Checksum operations
    CHECKSUM_STRUCTURE = "OGRH_SYNC_CHECKSUM_STRUCTURE",
    CHECKSUM_ASSIGNMENTS = "OGRH_SYNC_CHECKSUM_ASSIGNMENTS",
    CHECKSUM_MISMATCH = "OGRH_SYNC_CHECKSUM_MISMATCH",
    
    -- Repair operations
    REPAIR_REQUEST = "OGRH_SYNC_REPAIR_REQUEST",
    REPAIR_DATA = "OGRH_SYNC_REPAIR_DATA",
    
    -- Read-only operations
    REQUEST_READONLY = "OGRH_SYNC_REQUEST_READONLY",
    READONLY_DATA = "OGRH_SYNC_READONLY_DATA",
    
    -- Sync control
    CANCEL = "OGRH_SYNC_CANCEL",
    COMPLETE = "OGRH_SYNC_COMPLETE"
}

-- ADMIN: Administrative messages (polls, version checks, ready checks)
OGRH.MessageTypes.ADMIN = {
    -- Version polling
    POLL_VERSION = "OGRH_ADMIN_POLL_VERSION",
    POLL_RESPONSE = "OGRH_ADMIN_POLL_RESPONSE",
    
    -- Ready check operations
    READY_REQUEST = "OGRH_ADMIN_READY_REQUEST",
    READY_RESPONSE = "OGRH_ADMIN_READY_RESPONSE",
    READY_COMPLETE = "OGRH_ADMIN_READY_COMPLETE",
    
    -- Permission operations
    TAKEOVER = "OGRH_ADMIN_TAKEOVER",
    ASSIGN = "OGRH_ADMIN_ASSIGN",
    PERMISSION_DENIED = "OGRH_ADMIN_PERMISSION_DENIED",
    
    -- Promotion operations
    PROMOTE_REQUEST = "OGRH_ADMIN_PROMOTE_REQUEST",
    PROMOTE_RESPONSE = "OGRH_ADMIN_PROMOTE_RESPONSE"
}

-- STATE: State change messages (raid lead, encounter, phase)
OGRH.MessageTypes.STATE = {
    -- Raid lead state
    CHANGE_LEAD = "OGRH_STATE_CHANGE_LEAD",
    QUERY_LEAD = "OGRH_STATE_QUERY_LEAD",
    RESPONSE_LEAD = "OGRH_STATE_RESPONSE_LEAD",
    
    -- Encounter state
    CHANGE_ENCOUNTER = "OGRH_STATE_CHANGE_ENCOUNTER",
    QUERY_ENCOUNTER = "OGRH_STATE_QUERY_ENCOUNTER",
    RESPONSE_ENCOUNTER = "OGRH_STATE_RESPONSE_ENCOUNTER",
    
    -- Phase state
    CHANGE_PHASE = "OGRH_STATE_CHANGE_PHASE",
    QUERY_PHASE = "OGRH_STATE_QUERY_PHASE",
    RESPONSE_PHASE = "OGRH_STATE_RESPONSE_PHASE"
}

-- ReadHelper integration messages
OGRH.MessageTypes.READHELPER = {
    SYNC_REQUEST = "OGRH_RH_SYNC_REQUEST",
    SYNC_RESPONSE = "OGRH_RH_SYNC_RESPONSE",
    UPDATE = "OGRH_RH_UPDATE"
}

-- Legacy message type mapping (for backward compatibility during migration)
-- Maps old message format to new MessageTypes enum
OGRH.MessageTypes.Legacy = {
    ["READYCHECK_REQUEST"] = OGRH.MessageTypes.ADMIN.READY_REQUEST,
    ["READYCHECK_COMPLETE"] = OGRH.MessageTypes.ADMIN.READY_COMPLETE,
    ["AUTOPROMOTE_REQUEST"] = OGRH.MessageTypes.ADMIN.PROMOTE_REQUEST,
    ["ADDON_POLL"] = OGRH.MessageTypes.ADMIN.POLL_VERSION,
    ["ADDON_POLL_RESPONSE"] = OGRH.MessageTypes.ADMIN.POLL_RESPONSE,
    ["ASSIGNMENT_UPDATE"] = OGRH.MessageTypes.ASSIGN.BATCH_UPDATE,
    ["ENCOUNTER_SYNC"] = OGRH.MessageTypes.SYNC.RESPONSE_FULL,
    ["ROLESUI_CHECK"] = OGRH.MessageTypes.SYNC.CHECKSUM_STRUCTURE,
    ["READHELPER_SYNC_RESPONSE"] = OGRH.MessageTypes.READHELPER.SYNC_RESPONSE,
    ["RAID_LEAD_SET"] = OGRH.MessageTypes.STATE.CHANGE_LEAD,
    ["REQUEST_RAID_DATA"] = OGRH.MessageTypes.SYNC.REQUEST_FULL,
    ["REQUEST_CURRENT_ENCOUNTER"] = OGRH.MessageTypes.STATE.QUERY_ENCOUNTER,
    ["REQUEST_STRUCTURE_SYNC"] = OGRH.MessageTypes.SYNC.REQUEST_FULL,
    ["SYNC_REQUEST"] = OGRH.MessageTypes.SYNC.REQUEST_FULL,
    ["SYNC_RESPONSE"] = OGRH.MessageTypes.SYNC.RESPONSE_FULL,
    ["SYNC_CANCEL"] = OGRH.MessageTypes.SYNC.CANCEL,
    ["SYNC_DATA_START"] = OGRH.MessageTypes.SYNC.RESPONSE_PARTIAL,
    ["SYNC_DATA_CHUNK"] = OGRH.MessageTypes.SYNC.RESPONSE_PARTIAL,
    ["SYNC_DATA_END"] = OGRH.MessageTypes.SYNC.COMPLETE,
    ["RAID_LEAD_QUERY"] = OGRH.MessageTypes.STATE.QUERY_LEAD
}

--[[
    Helper Functions
]]

-- Get message type category from full message type
function OGRH.GetMessageCategory(messageType)
    if not messageType then return nil end
    
    -- Extract category from message type (e.g., "OGRH_STRUCT_SET_ENCOUNTER" -> "STRUCT")
    local pattern = "OGRH_([^_]+)_"
    local _, _, category = string.find(messageType, pattern)
    
    return category
end

-- Check if message type is valid
function OGRH.IsValidMessageType(messageType)
    if not messageType then return false end
    
    -- Check all categories
    for categoryName, category in pairs(OGRH.MessageTypes) do
        if categoryName ~= "Legacy" then
            for _, msgType in pairs(category) do
                if msgType == messageType then
                    return true
                end
            end
        end
    end
    
    return false
end

-- Get new message type from legacy message format
function OGRH.TranslateLegacyMessage(legacyMessage)
    if not legacyMessage then return nil end
    
    -- Extract base message type (before any colons or semicolons)
    local baseMessage = legacyMessage
    local colonPos = string.find(legacyMessage, ":")
    local semicolonPos = string.find(legacyMessage, ";")
    
    if colonPos then
        baseMessage = string.sub(legacyMessage, 1, colonPos - 1)
    elseif semicolonPos then
        baseMessage = string.sub(legacyMessage, 1, semicolonPos - 1)
    end
    
    return OGRH.MessageTypes.Legacy[baseMessage]
end

-- Debug: Print all message types
function OGRH.DebugPrintMessageTypes()
    DEFAULT_CHAT_FRAME:AddMessage("[OGRH] === OG-RaidHelper Message Types ===")
    
    for categoryName, category in pairs(OGRH.MessageTypes) do
        if categoryName ~= "Legacy" then
            DEFAULT_CHAT_FRAME:AddMessage(string.format("[OGRH] Category: %s", categoryName))
            
            for actionName, messageType in pairs(category) do
                DEFAULT_CHAT_FRAME:AddMessage(string.format("[OGRH]   %s = %s", actionName, messageType))
            end
        end
    end
    
    DEFAULT_CHAT_FRAME:AddMessage("[OGRH] === End Message Types ===")
end

-- Initialize message type system
DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff00ff00[RH-MsgTypes]|r Loaded %d message categories", 
    table.getn({OGRH.MessageTypes.STRUCT, OGRH.MessageTypes.ASSIGN, OGRH.MessageTypes.SYNC, OGRH.MessageTypes.ADMIN, OGRH.MessageTypes.STATE, OGRH.MessageTypes.READHELPER})))
