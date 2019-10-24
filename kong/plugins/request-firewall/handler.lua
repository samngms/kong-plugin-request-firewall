-- If you're not sure your plugin is executing, uncomment the line below and restart Kong
-- then it will throw an error which indicates the plugin is being loaded at least.
-- assert(ngx.get_phase() == "timer", "Request Validator CE coming to an end!")

-- Grab pluginname from module name
local plugin_name = ({...})[1]:match("^kong%.plugins%.([^%.]+)")

-- load the base plugin object and create a subclass
local plugin = require("kong.plugins.base_plugin"):extend()

local MultiPart = require("kong.plugins.request-firewall.multipart")

local m = require("kong.plugins.request-firewall.access")

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

function plugin:access(config)
  plugin.super.access(self)

  local debug = config.debug
  local err_code = config.err_code or 400

  -- get per url config object
  local path = kong.request.get_path()
  local cfg = config.exact_match and config.exact_match[path]
  if nil == cfg then
    kong.response.exit(403)
    return
  end

  local status, err = pcall(function() wrapped(cfg) end)
  if not status then 
    if debug then
      if err.msg then
        kong.log.info(err.msg)
        kong.response.exit(err_code, err.msg)
        return
      else
        kong.log.info(err)
        kong.response.exit(err_code, err)
        return
      end
    else
      if err.msg then 
        kong.log.info(err.msg)
      else
        kong.log.info(err)
      end
      kong.response.exit(err_code)
      return
    end
  end

end

-- set the plugin priority, which determines plugin execution order
plugin.PRIORITY = 850

-- return our plugin object
return plugin
