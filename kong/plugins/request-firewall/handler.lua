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

local function checkSubElements(enumList, subElements, name, layer)
  if subElements ~= nil then 
    if enumList == nil then
      error({msg = "Sub Element is not allowed in " .. name})
      return false
    end
    for _, element in pairs(subElements) do
      local elementName = element.name
      if layer ~= nil then
        elementName = layer..'.'..element.name
      end
      
      if not utils.contains(enumList, elementName) then
        error({msg = name .. "." .. elementName .. " is not allowed"})
        return false
      end

      if element.fields ~= nil then
        checkSubElements(enumList, element.fields, name, elementName)
      end
    end
    
  end 
end

function plugin:access(config)
  plugin.super.access(self)

  -- get per url config object
  local path = kong.request.get_path()

  if nil ~= path then
    path = string.gsub(path, "//", "/")
  end
  
  if config.graphql_match and config.graphql_match[path] then
    local g_config = config.graphql_match[path]
    local GqlParser = require('graphql-parser')
    local parser = GqlParser:new()
    local body, err, mimetype = kong.request.get_body()
    local graph = parser:parse(body["query"])
    
    if graph:nestDepth() > g_config["nestDepth"] then
      returnError(config, 'Nest depth exceeds limit') 
      return
    end
    
    --[[local path = ""
    for a, b in pairs(graph) do
      if nil ~= a then
        path = path .. "a"..a .. " "
      end
      if nil ~= b.name then
        path = path .. "b.name"..b.name .. " "
      end
      if nil ~= b.type then
        path = path .. "b.type"..b.type .. " "
      end
    end
    returnError(config, path)]]
    
    for _, op in pairs(graph) do
      -- Check operation type e.g. query / mutation
      
      if nil ~= op.type then 
      
        if nil == g_config["structure"][op.type] then
          returnError(config, 'Type '..op.type..' is not allowed')  
          return
        end
        
        for _,root in pairs(op.fields) do
          -- Check RootElement name e.g. CreateToken
          rootConfig = g_config["structure"][op.type][root.name]
          if nil == rootConfig then
            returnError(config, 'Root element '..root.name..' is not allowed')  
            return
          end
          
          -- Check variables by validateTable
          local status, err = pcall(function() m.validateTable(config, rootConfig.variables, config.allow_unknown_body, root.name, body["variables"]) end)
          if not status then
            returnError(config, tostring(err.msg))
            return
          end
          
          for _, field in pairs(root.fields) do
            -- Check field name e.g. token
            if nil == rootConfig.subfields[field.name] then
              returnError(config, 'Field '..root.name..'.'..field.name..' is not allowed')  
              return
            end
          
            -- Check sub-elements within the field
            -- if utils.contains(rootConfig.subfields[field.name].enum, field.fields)
            --if rootConfig.subfields[field.name] then
            
            
            local status, err = pcall(function() checkSubElements(rootConfig.subfields[field.name].subElements, field.fields, field.name) end)
            --checkSubElements(config, rootConfig.subfields[field.name].subElements, field.fields, field.name)
            if not status then
              returnError(config, tostring(err.msg))
              return
            end
          end
          
        end
      end
    end
    
    returnError(config, '', 200)
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