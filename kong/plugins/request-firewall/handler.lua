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

local function wrapped(cfg) 
    -- check query params
    local query = kong.request.get_query()
    m.validateTable(cfg, cfg.query, "query", query)
  
    -- check body params, this includes JSON, x-www-url-encoded and multi-part etc..
    local contentType = kong.request.get_header("Content-Type")
    local parser = MultiPart:new(contentType)
    -- we have to call get_body(), otherwies, get_body_file() will always be nil
    local body, err, mimetype = kong.request.get_body() 
    if parser:isFormData() then 
      local filename = ngx.req.get_body_file()
      body = parser:parseFile(filename) 
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
  
    m.validateTable(cfg, cfg.body, "body", body) 
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
  if nil == url_cfg then
    returnError(config, "Kong cfg for the URL is not found", 404)
    return
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

  local status, err = pcall(function() wrapped(cfg) end)
  if not status then
    returnError(config, err)
  end

end

-- set the plugin priority, which determines plugin execution order
plugin.PRIORITY = 850

-- return our plugin object
return plugin
