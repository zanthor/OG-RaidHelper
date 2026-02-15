--[[
    OGAddonMsg - Serialization
    Automatic table serialization/deserialization for wire protocol
    
    Design Philosophy:
    - Library owns wire format (consumers work with data structures)
    - Accept both tables and strings (tables auto-serialize)
    - Return original type to handlers (transparent to consumers)
    - No manual Serialize/Deserialize calls needed by consumers
]]

--[[
    Escape pipe characters in a %q-formatted string
    
    WoW's chat system uses | as an escape prefix (|cff, |r, |H, etc.).
    Unescaped pipes in addon messages get corrupted or stripped by the client.
    We replace literal | with \124 inside the quoted string, which loadstring()
    natively interprets back to | on deserialize - no unescape step needed.
    
    @param quoted string - Output of string.format("%q", str)
    @return string - Same string with | replaced by \124
]]
local function EscapePipe(quoted)
    return string.gsub(quoted, "|", "\\124")
end

--[[
    Serialize a Lua table to string
    
    Handles nested tables, strings, numbers, booleans
    Does NOT handle: functions, userdata, threads
    
    @param tbl table - Lua table to serialize
    @return string - Serialized representation
]]
function OGAddonMsg.Serialize(tbl)
    if type(tbl) ~= "table" then
        -- Non-table types serialize to string directly
        return tostring(tbl)
    end
    
    local result = "{"
    local first = true
    
    for k, v in pairs(tbl) do
        if not first then
            result = result .. ","
        end
        first = false
        
        -- Serialize key
        if type(k) == "number" then
            result = result .. "[" .. k .. "]="
        elseif type(k) == "string" then
            result = result .. "[" .. EscapePipe(string.format("%q", k)) .. "]="
        else
            -- Skip non-string/number keys (functions, etc.)
            first = true
            result = string.sub(result, 1, -2)  -- Remove trailing comma if any
        end
        
        -- Serialize value
        if type(v) == "table" then
            result = result .. OGAddonMsg.Serialize(v)
        elseif type(v) == "string" then
            result = result .. EscapePipe(string.format("%q", v))
        elseif type(v) == "number" or type(v) == "boolean" then
            result = result .. tostring(v)
        elseif v == nil then
            result = result .. "nil"
        else
            -- Skip functions, userdata, threads
            first = true
            result = string.sub(result, 1, -2)  -- Remove trailing comma if any
        end
    end
    
    result = result .. "}"
    return result
end

--[[
    Deserialize string back to Lua table
    
    Uses loadstring to evaluate serialized table (safe for controlled data)
    
    @param str string - Serialized table representation
    @return table or nil - Deserialized table, or nil on error
]]
function OGAddonMsg.Deserialize(str)
    if type(str) ~= "string" then
        OGAddonMsg.Msg(
            string.format("OGAddonMsg: Deserialize expected string, got %s", type(str))
        )
        return nil
    end
    
    -- Use loadstring to evaluate serialized table
    local func, err = loadstring("return " .. str)
    if not func then
        OGAddonMsg.Msg(
            string.format("OGAddonMsg: Deserialize parse error: %s", tostring(err))
        )
        return nil
    end
    
    -- Execute in protected call
    local success, result = pcall(func)
    if not success then
        OGAddonMsg.Msg(
            string.format("OGAddonMsg: Deserialize execution error: %s", tostring(result))
        )
        return nil
    end
    
    return result
end
