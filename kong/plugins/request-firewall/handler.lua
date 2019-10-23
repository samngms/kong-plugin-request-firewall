-- If you're not sure your plugin is executing, uncomment the line below and restart Kong
-- then it will throw an error which indicates the plugin is being loaded at least.
-- assert(ngx.get_phase() == "timer", "Request Validator CE coming to an end!")

-- Grab pluginname from module name
local plugin_name = ({...})[1]:match("^kong%.plugins%.([^%.]+)")

-- load the base plugin object and create a subclass
local plugin = require("kong.plugins.base_plugin"):extend()

local MultiPart = require("kong.plugins.request-firewall.multipart")

local m = require("kong.plugins.request-firewall.access")
-- redefine fail function
m.fail = function(msg)
  kong.log.info(msg)
  return false
end

-- constructor
function plugin:new()
  plugin.super.new(self, plugin_name)
end

function plugin:access(config)
  plugin.super.access(self)

  -- get per url config object
  local path = kong.request.get_path()
  local cfg = config.exact_match and config.exact_match[path]
  if nil == cfg then
    kong.response.exit(400)
    return
  end

  -- check query params
  local query = kong.request.get_query()
  if not m.validateTable(cfg, cfg.query, "query", query) then
    kong.response.exit(400)
    return
  end

  -- check body params, this includes JSON, x-www-url-encoded and multi-part etc..
  local contentType = kong.request.get_header("Content-Type")
  local parser = MultiPart:new(contentType)
  -- we have to call get_body(), otherwies, get_body_file() will always be nil
  local body, err, mimetype = kong.request.get_body() 
  if parser:isFormData() then 
    local filename = ngx.req.get_body_file()
    local status, err = pcall(function() body = parser:parseFile(filename) end)
    if not status then 
      kong.log.info(err)
      kong.response.exit(400)
      return
    end
  end

  if nil == body then body = {} end

  if not m.validateTable(cfg, cfg.body, "body", body) then
    kong.response.exit(400)
    return
  end

end

-- set the plugin priority, which determines plugin execution order
plugin.PRIORITY = 850

-- return our plugin object
return plugin
