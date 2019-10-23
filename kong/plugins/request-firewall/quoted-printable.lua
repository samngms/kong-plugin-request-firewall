local function decode(str) 
    local output = str:gsub("=%x%x", function(hexStr)
        local number = tonumber(hexStr:sub(2, 4), 16)
        return string.char(number)
    end)
    return output, nil
end

return {
    decode = decode
}