-- If you're not sure your plugin is executing, uncomment the line below and restart Kong
-- then it will throw an error which indicates the plugin is being loaded at least.
-- assert(ngx.get_phase() == "timer", "Request Validator CE coming to an end!")

-- Grab pluginname from module name
local plugin_name = ({...})[1]:match("^kong%.plugins%.([^%.]+)")

-- load the base plugin object and create a subclass
local plugin = require("kong.plugins.base_plugin"):extend()

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
  end

  -- check query params
  if not m.validateTable(cfg, cfg.query, "query", kong.request.get_query()) then
    kong.response.exit(400)
  end

  -- check body params, this includes JSON, x-www-url-encoded and multi-part etc..
  local body, err, mimetype = kong.request.get_body()
  if body ~= nil then
    if not m.validateTable(cfg, cfg.body, "body", body) then
      kong.response.exit(400)
    end
  elseif nil ~= err then
    local te = kong.request.get_header("Transfer-Encoding") 
    if nil ~= te and nil ~= te:find("chunked", 1, true) then
      m.fail("Invalid body: " .. tostring(error))
      kong.response.exit(400)
    end
    local s = kong.request.get_header("Content-Length")
    if nil ~= s then
      local len = tonumber(s)
      if nil ~= len and len == 0 then
        -- the only content for we are good to go if the len is defined and is 0
      else 
        m.fail("Invalid body: " .. tostring(error))
        kong.response.exit(400)
      end
    end
  end
end

-- set the plugin priority, which determines plugin execution order
plugin.PRIORITY = 850

-- return our plugin object
return plugin
