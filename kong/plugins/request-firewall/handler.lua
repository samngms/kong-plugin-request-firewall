-- If you're not sure your plugin is executing, uncomment the line below and restart Kong
-- then it will throw an error which indicates the plugin is being loaded at least.
-- assert(ngx.get_phase() == "timer", "Request Validator CE coming to an end!")

-- Grab pluginname from module name
local plugin_name = ({...})[1]:match("^kong%.plugins%.([^%.]+)")

-- load the base plugin object and create a subclass
local plugin = require("kong.plugins.base_plugin"):extend()

local MultiPart = require("kong.plugins.request-firewall.multipart")

local m = require("kong.plugins.request-firewall.access")
local utils = require("kong.plugins.request-firewall.utils")

-- constructor
function plugin:new()
  plugin.super.new(self, plugin_name)
end

local function quoteRegex(str)
  local s, count = string.gsub(str, "-", "%%-")
  return s
end

local function parseUrlPattern(template)
  local list = {}
  local offset = 1
  local output = ""
  while true do
    local startIdx, endIdx = string.find(template, "${.-}", offset, false)
    if nil == startIdx then
      local plain = string.sub(template, offset)
      if string.len(plain) > 0 then
        output = output .. quoteRegex(plain)
      end
      break
    else
      local plain = string.sub(template, offset, startIdx-1)
      if string.len(plain) > 0 then
        output = output .. quoteRegex(plain)
      end
      local found = string.sub(template, startIdx+2, endIdx-1)
      local idx = string.find(found, ":", 1, true)
      if nil == idx then
        table.insert(list, m.trim(found))
        output = output .. "([^%/]+)"
      else
        table.insert(list, m.trim(string.sub(found, 1, idx-1)))
        output = output .. "(" .. m.trim(string.sub(found, idx+1, -1)) .. ")"
      end
      offset = endIdx+1
    end
  end

  return "^" .. output .. "$", list
end

local function wrapped(cfg, pathParams) 
    -- check path params
    -- there is no allow_unknown_path, because you specify the path variables in the path, there is no way to have unknown path variables
    m.validateTable(cfg, cfg.path, true, "path", pathParams)

    -- check query params
    local query = kong.request.get_query()
    m.validateTable(cfg, cfg.query, cfg.allow_unknown_query, "query", query)
  
    -- check body params, this includes JSON, x-www-url-encoded and multi-part etc..
    local contentType = kong.request.get_header("Content-Type")
    local parser = MultiPart:new(contentType)
    -- we have to call get_body(), otherwies, get_body_file() will always be nil
    local body, err, mimetype = kong.request.get_body() 
    if parser:isFormData() then 
      local content = ngx.req.get_body_data()  -- if body < 8k, get_body_data() will be valid
      local filename = ngx.req.get_body_file() -- if body > 8k, get_body_file() will be valid
      body = parser:parseFile(filename, content) 
    elseif nil ~= err then
      local te = kong.request.get_header("Transfer-Encoding")
      if nil ~= te and nil ~= te.find("chunked", 1, true) then
        error({msg = err})
      end
      local cl = kong.request.get_header("Content-Length")
      if nil ~= cl and cl ~= "0" then
        error({msg = err})
      end
    end
  
    if nil == body then body = {} end
  
    m.validateTable(cfg, cfg.body, cfg.allow_unknown_body, "body", body) 
end

local function returnError(config, err, code)
  local debug = config.debug
  local err_code = code or config.err_code or 400

  if debug then
    if nil == err then
      kong.response.exit(err_code)
    elseif type(err) == 'table' and err.msg then
      -- if err.msg is avaiable, we use it
      kong.log.info(err.msg)
      kong.response.exit(err_code, err.msg)
    else
      -- no err.msg, we output the whole err
      kong.log.info(err)
      kong.response.exit(err_code, err)
    end
  else
    -- not in debug mode, we still want to log the error message
    if nil == err then
      -- can't log anything...
    elseif type(err) == 'table' and err.msg then 
      kong.log.info(err.msg)
    else
      kong.log.info(err)
    end
    kong.response.exit(err_code)
  end
end

function plugin:access(config)
  plugin.super.access(self)

  -- get per url config object
  local path = kong.request.get_path()

  if nil ~= path then
    path = string.gsub(path, "//", "/")
  end

  local url_cfg = config.exact_match and config.exact_match[path]
  local pathParams = {}
  if nil == url_cfg then
    if nil ~= config.pattern_match then
      for str, c in pairs(config.pattern_match) do
        local pattern, names = parseUrlPattern(str)
        local m = {string.match(path, pattern)}
        if next(m) then -- that means it matches
          -- note I loop thru names, not m because if there is no match group, then m is non-nil and contains the full string
          -- but in that case, then names should be empty
          for i, name in ipairs(names) do
            -- remember to do url hex decode
            -- https://github.com/openresty/lua-nginx-module#ngxescape_uri
            pathParams[name] = ngx.unescape_uri(m[i])
          end
          url_cfg = c
          break
        end
      end
    end

    if nil == url_cfg then
      returnError(config, "Kong cfg for the URL is not found", 404)
      return
    end
  end

  local cfg = url_cfg[kong.request.get_method()] or url_cfg["*"]
  if cfg == nil then
    returnError(config, "Method not allowed")
    return
  end

  if nil ~= cfg.content_type then 
    local ct = kong.request.get_header("Content-Type")
    if nil == ct then
      returnError(config, "Content-Type cannot be null")
      return
    elseif nil == string.find(ct, cfg.content_type, 1, true) then
      returnError(config, "Content-Type not match: " .. ct)
      return
    end
  end

  local status, err = pcall(function() wrapped(cfg, pathParams) end)
  if not status then
    returnError(config, err)
  end

end

-- set the plugin priority, which determines plugin execution order
plugin.PRIORITY = 850

-- return our plugin object
return plugin
