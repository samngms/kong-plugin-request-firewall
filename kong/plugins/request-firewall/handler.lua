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

local function checkSubElements(enumList, restrictedAccessFields, fields, rootName, layer)
	if fields ~= nil then
		for _, element in pairs(fields) do
			local elementName = element.name
			if layer ~= nil then
				elementName = layer..'.'..element.name
			end
			
			if enumList ~= nil then
				if not utils.contains(enumList, elementName) then
					error({msg = rootName .. "." .. elementName .. " is not allowed"})
					return false
				end
			end
			
			if restrictedAccessFields ~= nil then
				for _, forbiddenField in pairs(restrictedAccessFields) do
					if string.match(element.name, forbiddenField) and not utils.contains(enumList, elementName) then
						error({msg = rootName .. "." .. elementName .. " is access restricted"})
						return false
					end
				end
			end
			
  		if element.fields ~= nil then
  			checkSubElements(enumList, restrictedAccessFields, element.fields, rootName, elementName)
  		end
  	end
	end
end



function resolveArgument(config, rootArguments, parent_op, bodyVariables)
    local result = {}
    
    for _, arg in ipairs(rootArguments) do
        local item = {}
        local value = arg.value
        if type(value) == "table" then
          
      		tmp_result = resolveArgument(config, value, parent_op, bodyVariables)
--      		returnError(config,to_string(tmp_result))
      		tableMerge(result, tmp_result)

        elseif type(value) == "string" then
		      if string.match(value, "^%$") then
		          local variable = parent_op:findVariable(value)
		          
		          local tmp = string.sub(value, 2)
		          local input_value = bodyVariables[tmp]
		          
		          if input_value then
		          	if type(input_value) == "table" then

		          		for k, v in pairs(input_value) do
		          			result[k] = v
		          		end
		          		break
		          	elseif type(input_value) == "string" then
		              item["value"] = input_value
		            end
		          elseif variable ~= nil then
		          	if variable.default_value then
		              item["value"] = variable.default_value
		            end
		          end
		      else
		          item["value"] = value
		      end
		    end
        result[arg.name] = item["value"]
    end
    return result
end

function tableMerge(t1, t2)
   for k,v in pairs(t2) do
      t1[k]=v
   end 
 
   return t1
end

function table_print (tt, indent, done)
  done = done or {}
  indent = indent or 0
  if type(tt) == "table" then
    local sb = {}
    for key, value in pairs (tt) do
      table.insert(sb, string.rep (" ", indent)) -- indent it
      if type (value) == "table" and not done [value] then
        done [value] = true
        table.insert(sb, key .. " = {\n");
        table.insert(sb, table_print (value, indent + 2, done))
        table.insert(sb, string.rep (" ", indent)) -- indent it
        table.insert(sb, "}\n");
      elseif "number" == type(key) then
        table.insert(sb, string.format("\"%s\"\n", tostring(value)))
      else
        table.insert(sb, string.format(
            "%s = \"%s\"\n", tostring (key), tostring(value)))
       end
    end
    return table.concat(sb)
  else
    return tt .. "\n"
  end
end

function to_string( tbl )
    if  "nil"       == type( tbl ) then
        return tostring(nil)
    elseif  "table" == type( tbl ) then
        return table_print(tbl)
    elseif  "string" == type( tbl ) then
        return tbl
    else
        return tostring(tbl)
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
    	
    if body ~= nil and body["query"] ~= nil then
		  local graph = parser:parse(body["query"])
		  
			---local argument = graph:listOps()[1]:getRootFields()[1]:resolveArgument({})
			---returnError(config, 'Field '..to_string(argument)..' is not allowed')
		  
		  if graph:nestDepth() > g_config["nestDepth"] then
		  	returnError(config, 'Nest depth exceeds limit')	
		    return
		  end
		  
		  for _, op in pairs(graph) do
		    -- Check operation type e.g. query / mutation
		    
		    if nil ~= op.type then 
		   
				  if nil == g_config["structure"][op.type] then
				    returnError(config, 'Type '..op.type..' is not allowed')	
				    return
				  end
				  
				  for _,root in pairs(op.fields) do
				    -- Check RootElement name e.g. CreateToken
				    local rootConfig = g_config["structure"][op.type][root.name]
				    if nil == rootConfig then
				      returnError(config, 'Root element '..root.name..' is not allowed')	
				      return
				    end
				    
				    -- Check variables by validateTable
				    if type(body["variables"]) ~= "table" then
				    	returnError(config, "Body variables in wrong format")
					    return
				    end
				    				    
				    resolvedVariables = resolveArgument(config, root.arguments, op, body["variables"])
				    --returnError(config,to_string(resolvedVariables))
				    
					  local status, err = pcall(function() m.validateTable(config, rootConfig.variables, config.allow_unknown_body, root.name, resolvedVariables) end)
					  
					  if not status then
					    returnError(config, tostring(err.msg))
					    return
					  end
				    
			      -- Check field name e.g. token
				    local status, err = pcall(function() checkSubElements(rootConfig.fields, g_config["accessRestrictedFields"],root.fields, root.name) end)
				    if not status then
				      returnError(config, tostring(err.msg))
				      return
				    end
		        
		      end
		    end
		  end
		else
			returnError(config, 'Body is empty / Error has occured')	
		  return
		end
		return
    --returnError(config, '', 200)
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