-- returns true if "table" contains "value"
local function contains(table, value)
    for k, v in pairs(table) do 
        if value == v then return true end 
    end
    return false
end

local function escape(s) 
    if not s then return s end
    local s2 = s:gsub("[%\"%\\%c%z]", function(ch)
        local b = string.byte(ch)
        if ch == "\"" then return "\\\"" 
        elseif ch == "\\" then return "\\\\"
        elseif ch == "\r" then return "\\r"
        elseif ch == "\n" then return "\\n"
        elseif ch == "\0" then return "\\0"
        else return string.format("\\x%02X", b) end
    end)
    if s2:len() > 32 then
        return s:sub(1, 32) .. "..."
    else
        return s
    end
end

local function dump(o, value)
    if nil ~= value then
        -- if value is not nil, then 'o' is the name
        -- we output name=value
        if nil == o then o = "(nil)" end
        local t = type(value)
        if nil == value then
            return o .. '=(null)'
        elseif t == 'table' then
            return o .. '=' .. dump(value)
        elseif t == 'string' then
            return o .. '=' .. escape(value)
        else
            return o .. '=' .. tostring(value)
        end
    else
        -- if value is nil, then 'o' is an object
        -- we output something like the JSON.stringify(o)
        if nil == o then
            return "(nil)"
        elseif type(o) == 'table' then
            local s = '{ '
            local i = 0
            for k,v in pairs(o) do
                if i > 0 then s = s .. ', ' end
                s = s .. k .. '=' .. dump(v) 
                i = i + 1
            end
            return s .. ' } '
        elseif type(o) == 'string' then
            return "\"" .. escape(o) .. "\""
        else
            return tostring(o)
        end
    end
 end

 return {
    contains = contains,
    escape = escape,
    dump = dump
}