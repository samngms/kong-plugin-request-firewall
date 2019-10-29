local function decode(str) 
    local tmp = str:gsub("[\r\n]", "")
    local output = tmp:gsub("=%x%x", function(hexStr)
        local number = tonumber(hexStr:sub(2, 4), 16)
        return string.char(number)
    end)
    return output, nil
end

return {
    decode = decode
}