local FileReader = {}

function FileReader:new(filename)
    local obj = {}
    setmetatable(obj, self)
    self.__index = self

    local fh = io.open(filename, "rb")
    if not fh then return nil end
    obj.fh = fh
    obj.offset = 0 -- offset starts with 0, NOT 1, I hate Lua's index starts with 1
    return obj
end

-- load at least "num" of chars into memory
-- note this is just best effort, when we are close to EOF, loaded data maybe less than "num"
-- return actual size of the buffer, nil if no buffer
function FileReader:load(num)
    if not self.data or self.data:len()-self.offset == 0 then
        if io.type(self.fh) == "file" then
            self.data = self.fh:read(num)
            self.offset = 0
            if not self.data then
                self.fh:close()
                return nil
            else
                return self.data:len()-self.offset
            end
        else
            -- file closed?
            return nil
        end
    elseif self.data:len()-self.offset < num then
        if io.type(self.fh) == "file" then
            local tmp = self.fh:read(num)
            if not tmp then
                self.fh:close()
                return self.data:len()-self.offset
            else
                if self.offset > 0 then
                    self.data = self.data:sub(self.offset+1) .. tmp
                    self.offset = 0
                    return self.data:len()-self.offset
                else
                    self.data = self.data .. tmp
                    return self.data:len()-self.offset
                end
            end
        else
            -- file closed?
            return self.data:len()-self.offset
        end
    else
        return self.data:len()-self.offset
    end
end

-- locate pattern in current buffer
-- return the index (relative to the current buffer, starts from 1) if found, otherwise, nil
function FileReader:indexOf(pattern)
    if self.data then
        local x = self.data:find(pattern, self.offset+1, true)
        if x ~= nil then return x - self.offset
        else return nil end
    else
        return nil
    end
end

-- discard "num" of chars from current buffer
function FileReader:consume(num)
    self.offset = self.offset + num
end

function FileReader:retrieve(num)
    return self.data:sub(self.offset+1, self.offset+num)
end

function FileReader:len()
    return self.data:len() - self.offset
end

-- read a line from current buffer
-- if [\r\n] is not found, return nil
-- otherwies, return the line without [\r\n] and consume the line
function FileReader:readLine()
    if self.data then
        local startIdx, endIdx = self.data:find("\r?\n", self.offset+1)
        if startIdx then
            local line = self.data:sub(self.offset+1, startIdx-1)
            self.offset = endIdx
            return line
        else
            return self.data:sub(self.offset+1)
        end
    end
    return nil
end

return FileReader