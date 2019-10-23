local map = {
    A=0,  B=1,  C=2,  D=3,  E=4,  F=5,  G=6,  H=7,  I=8,  J=9,  K=10, L=11, M=12, N=13, O=14, P=15, Q=16, R=17, S=18, T=19, U=20, V=21, W=22, X=23, Y=24, Z=25,
    a=26, b=27, c=28, d=29, e=30, f=31, g=32, h=33, i=34, j=35, k=36, l=37, m=38, n=39, o=40, p=41, q=42, r=43, s=44, t=45, u=46, v=47, w=48, x=49, y=50, z=51, 
    ["0"]=52, ["1"]=53, ["2"]=54, ["3"]=55, ["4"]=56, ["5"]=57, ["6"]=58, ["7"]=59, ["8"]=60, ["9"]=61, ["+"]=62, ["/"]=63
}

local function decode(str) 
    if (str:len() % 4) == 1 then 
        return nil, "Invalid base64 string length: " .. str:len()
    end

    local i = 0
    local isPadding = 0
    local tmp1 = 0
    local tmp2 = 0
    local tmp3 = 0
    local bytes = {}
    local err = nil
    str:gsub(".", function(c)
        local x = i % 4
        if err then return end
        if 0 == isPadding then
            if x == 0 then
                local tmp = map[c]
                if not tmp then 
                    err = "Invalid base64 char \"" .. c .. "\" at index: " .. i
                    return
                end
                tmp1 = tmp * 4
            elseif x == 1 then
                local tmp = map[c]
                if not tmp then 
                    err = "Invalid base64 char \"" .. c .. "\" at index: " .. i
                    return
                end
                local tt = math.floor(tmp / 16)
                tmp1 = tmp1 + tt
                tmp2 = (tmp % 16) * 16
                table.insert(bytes, string.char(tmp1))
            elseif x == 2 then
                if '=' == c then
                    if tmp2 ~= 0 then 
                        err = "Invalid base64 padding, the last 4 bits of the throw-away byte is not zero: " .. tmp2
                        return
                    end
                    isPadding = 1
                else
                    local tmp = map[c]  
                    if not tmp then 
                        err = "Invalid base64 char \"" .. c .. "\" at index: " .. i
                        return
                    end
                    local tt = math.floor(tmp / 4)
                    tmp2 = tmp2 + tt
                    tmp3 = (tmp % 4) * 64
                    table.insert(bytes, string.char(tmp2))
                end
            else
                if '=' == c then
                    if tmp3 ~= 0 then 
                        err = "Invalid base64 padding, the last 2 bits of the throw-away byte is not zero: " .. tmp2
                        return
                    end
                else
                    local tmp = map[c]
                    if not tmp then 
                        err = "Invalid base64 char \"" .. c .. "\" at index: " .. i
                        return 
                    end
                    tmp3 = tmp3 + tmp
                    table.insert(bytes, string.char(tmp3))
                end
            end
        else
            if 1 == isPadding then
                isPadding = 2
            else
                err = "Invalid base64 padding"
                return
            end
        end
        i = i + 1
    end)
    if err then
        return nil, err
    else
        return table.concat(bytes), nil
    end
end

return {
    decode = decode
}