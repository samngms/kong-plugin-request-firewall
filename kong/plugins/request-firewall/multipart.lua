local FileReader = require("kong.plugins.request-firewall.file-reader")
local base64 = require("kong.plugins.request-firewall.base64")
local qp = require("kong.plugins.request-firewall.quoted-printable")
local MultiPart = {}
local CRLF = "\r\n"

local function unquote(s) 
    local s2 = s:match('^"(.*)"$')
    if s2 then return s2 else return s end
end

local function trim(s)
    if not s then return nil end
    return s:match("^%s*(.-)%s*$")
end

local function splitParameter(line, delimit)
    local idx = line:find(delimit, 1, true)
    if not idx then return line, "" end
    return trim(line:sub(0, idx-1)), trim(line:sub(idx+1))
end

function MultiPart:new(contentType)
    local obj = {}
    setmetatable(obj, self)
    self.__index = self
    if not contentType then
        obj._isValid = false
    else
        local first = true
        for segment in contentType:gmatch("[^%;]+") do
            if first then
                first = false
                local s = trim(segment)
                if s == "multipart/form-data" then
                    obj._isValid = true
                else
                    obj._isValid = false
                    break -- break the for loop
                end
            else
                local name, value = splitParameter(trim(segment), "=")
                if name == "boundary" then
                    -- boundary1 is only used for the first time
                    obj.boundary1 = "--" .. unquote(value)
                    obj.boundary1_len = obj.boundary1:len()
                    -- from 2nd time onward, we will use boundary2 which is prefixed with '\r\n'
                    obj.boundary2 = CRLF .. obj.boundary1
                    obj.boundary2_len = obj.boundary2:len()
                elseif name == "charset" then
                    -- do nothing
                else 
                    obj._isValid = false
                end
            end
        end
    end
    return obj
end

function MultiPart:isFormData()
    return self._isValid
end

function MultiPart:parseFile(filename) 
    local reader = FileReader:new(filename)
    self.reader = reader

    local init = true
    local params = {}
    local idx, blen

    while true do
        reader:load(8192)
        if init then
            blen = self.boundary1_len
            idx = reader:indexOf(self.boundary1)
        else
            blen = self.boundary2_len
            idx = reader:indexOf(self.boundary2)
        end

        if init then
            init = false
            if idx == nil then
                error({msg = "error finding mime boundary"})
            end
            -- everything *before* the first mime boundary can be ignored
            if idx ~= 1 then
                -- everything *before* the first mime boundary can be ignored.. only if it is not too long
                if idx > 32 then
                    error({msg = "too many garbage before the first mime boundary: " .. idx})
                end
                reader.consume(idx-1)
            end
        else
            if idx == nil then
                error({msg = "can't find mime boundary"})
            elseif idx ~= 1 then
                -- parsePart() should have read to the end, therefore, when we call indexOf, it should always be 1
                error({msg = "data does not start with the mime boundary, this should be a program bug"})
            end
        end

        reader:consume(blen)
        local item = self:parsePart()
        -- the only case that item is nil is EoF
        if not item then break end

        if params[item.name] then error({msg = "duplicate parameter name: " .. item.name}) end

        if item.isFile then
            params[item.name] = {filename = item.filename, size = item.filesize, contentType = item.contentType}
        else
            params[item.name] = item.value
        end
    end

    return params
end

function MultiPart:parsePart()
    self.reader:load(1024) -- make sure there is enough data
    local afterBoundary = self.reader:readLine()
    if afterBoundary:len() >= 2 and afterBoundary:sub(1, 3) == "--" then return nil end
    if not afterBoundary or trim(afterBoundary):len() ~= 0 then error({msg = "no empty line following the boundary"}) end
    local item = {}
    local headers = {}
    local maxHeaders = 8
    for i=1,maxHeaders do
        if i == maxHeaders then error({msg = "too many content headers"}) end
        self.reader:load(1024) -- make sure there is enough data
        local line = self.reader:readLine()
        if not line then error({msg = "immature end of data"}) end
        line = trim(line)
        if line:len() == 0 then
            -- empty line, header is done, read body
            -- filename is optional. e.g. for drag-n-drop action, filename may not be available
            if not item.filename and (not item.contentType or item.contentType == "plain/text") then
                item.isFile = false
                self.reader:load(1024*8) -- max body size is 8k
                local idx = self.reader:indexOf(self.boundary2)
                if not idx then error({msg = "can't find mime boundary"}) end
                local value = self.reader:retrieve(idx-1)
                local cte = item.contentTransferEncoding
                if cte == "base64" then
                    local str, err = base64.decode(value)
                    if err then error({msg = err}) end
                    value = str
                elseif cte == "quoted-printable" then
                    local str, err = qp.decode(value)
                    if err then error({msg = err}) end
                    value = str
                end
                item.value = value
                self.reader:consume(idx-1)
            else
                item.isFile = true
                local filesize = 0
                local idx
                while true do
                    self.reader:load(1024*8)
                    idx = self.reader:indexOf(self.boundary2)
                    if idx then break end
                    local tmp = self.reader:len()
                    filesize = filesize + tmp
                    self.reader:consume(tmp)
                end
                self.reader:consume(idx-1)
                filesize = filesize + (idx-1)
                if item.contentLength and item.contentLength ~= filesize then
                    error({msg = "incorrect Content-length specified: " .. item.contentLength .. " != " .. filesize})
                end
                item.filesize = filesize
            end
            return item
        else
            -- parse one single header, such as "Content-Disposition", or "Content-Type", etc..
            local headerName, headerValue = line:match("^(.-)%s*%:%s*(.-)%s*$")
            if not headerName or not headerValue then error({msg = "invalid header: " .. line}) end
            headerName = headerName:lower()
            if headers[headerName] then error({msg = "duplicate header: " .. headerName}) end
            headers[headerName] = self:parseHeaderValue(headerValue)
            if headerName == "content-disposition" then
                if headers[headerName].value ~= "form-data" then
                    error({msg = "content-disposition is not form-data"})
                end
                item.name = headers[headerName].attributes.name
                if not item.name then
                    error({msg = "form-data without name"})
                end
                item.filename = headers[headerName].attributes.filename
            elseif headerName == "content-type" then
                item.contentType = headers[headerName].value
            elseif headerName == "content-transfer-encoding" then
                local cte = headers[headerName].value:lower()
                if cte ~= "base64" and cte ~= "quoted-printable" then
                    error({msg = "invalid Content-Transfer-Encoding: " .. headers[headerName].value})
                end
                item.contentTransferEncoding = cte
            elseif headerName == "content-length" then
                -- content-length should be detected by boundary, not by the Content-Length headers
                -- in here, we still allow content-length, it's just we will double check and make sure it is correct
                local len = tonumber(headers[headerName].value)
                if not len then error({msg = "invalid Content-Length specified: " .. headers[headerName].value}) end
                item.contentLength = len
            end
        end
    end
    error({msg = "the program should not reach here, must be program bug"})
end

function MultiPart:parseHeaderValue(value)
    local firstPart = nil
    local attributes = {}
    for token in value:gmatch("[^;]+") do
        token = trim(token)
        if not firstPart then
            firstPart = trim(token)
        else
            local attrName, attrValue = token:match("^(.-)%s*%=%s*(.*)$")
            if not attrName then 
                -- the only caes for attrName is nil is token does not contain "="
                attributes[token] = ""
            else
                attributes[trim(attrName)] = unquote(trim(attrValue))
            end
        end
    end
    return { value = firstPart, attributes = attributes }
end

return MultiPart