local helpers = require "spec.helpers"
local version = require("version").version or require("version")
local GqlParser = require('graphql-parser')

local PLUGIN_NAME = "request-firewall"
local KONG_VERSION
do
  local _, _, std_out = assert(helpers.kong_exec("version"))
  if std_out:find("[Ee]nterprise") then
    std_out = std_out:gsub("%-", ".")
  end
  std_out = std_out:match("(%d[%d%.]+%d)")
  KONG_VERSION = version(std_out)
end

for _, strategy in helpers.each_strategy() do
  describe(PLUGIN_NAME .. ": (graphql-whitelist) [#" .. strategy .. "]", function()
    local client

    lazy_setup(function()
      local bp, route1
      local myconfig = {
        debug = true,
        graphql_match = {
          ["/graphql"] = {
            nestDepth = 4,
            structure = {
              ["mutation"] = {
                ["createToken"] = {
                    variables = {
                      email = {type = "string", max = 20},
                      password = {type = "string", enum = {"abc","def"}, required=true}
                    },
                    subfields = {
                      token = {subElements = {"message", "path", "message.secret", "message.secret.deeperSecret"}},
                      clientMutationId = {subElements = { "url"}}
                    }
                }
              },
              ["query"] = {
                ["activateStatus"] = {
                  variables = {
                    teamId = {type = "number", min = 1, max = 100},
                  },
                  subfields = {
                    businessAccountStatus = {subElements = {}},
                    kycLevel = {subElements = {}}
                  }
                }
              }  
            }
          }
        }
      }
      
     

      if KONG_VERSION >= version("0.35.0") or
         KONG_VERSION == version("0.15.0") then
        --
        -- Kong version 0.15.0/1.0.0+, and
        -- Kong Enterprise 0.35+ new test helpers
        --
        local bp = helpers.get_db_utils(strategy, nil, { PLUGIN_NAME })

        local route1 = bp.routes:insert({
          hosts = { "postman-echo.com" },
        })
        bp.plugins:insert {
          name = PLUGIN_NAME,
          route = { id = route1.id },
          config = myconfig
        }
      else
        --
        -- Kong Enterprise 0.35 older test helpers
        -- Pre Kong version 0.15.0/1.0.0, and
        --
        local bp = helpers.get_db_utils(strategy)

        local route1 = bp.routes:insert({
          hosts = { "postman-echo.com" },
        })
        bp.plugins:insert {
          name = PLUGIN_NAME,
          route_id = route1.id,
          config = myconfig
        }
      end

      -- start kong
      assert(helpers.start_kong({
        -- set the strategy
        database   = strategy,
        -- use the custom test template to create a local mock server
        nginx_conf = "spec/fixtures/custom_nginx.template",
        -- set the config item to make sure our plugin gets loaded
        plugins = "bundled," .. PLUGIN_NAME,  -- since Kong CE 0.14
        custom_plugins = PLUGIN_NAME,         -- pre Kong CE 0.14
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong(nil, true)
    end)

    before_each(function()
      client = helpers.proxy_client()
    end)

    after_each(function()
      if client then client:close() end
    end)


    describe("testing body string", function()

      it("Correct nested queries", function()
        local r = assert(client:send {
          method = "POST",
          path = "/graphql", 
          headers = {
            host = "postman-echo.com",
            ["Content-type"] = "application/json"
          },
          body = [[
            {"query":"mutation createToken1 ($input: CreateTokenMutationInput!) { createToken (input: $input) {  token { path message { secret { deeperSecret } } } } } ",
              "variables": {"email":"a@a.com", "password":"abc"}
            }
          ]]
        })
        assert.response(r).has.status(200)
      end)
      
      it("Extra parameter in query", function()
        local r = assert(client:send {
          method = "POST",
          path = "/graphql", 
          headers = {
            host = "postman-echo.com",
            ["Content-type"] = "application/json"
          },
          body = [[
            {"query":"mutation createToken1 ($input: CreateTokenMutationInput!) { createToken (input: $input) { PrivateSecret } }",
              "variables": {"email":"a@a.com", "password":"abc"}
            }
          ]]
        })
        assert.response(r).has.status(400)
      end)
      
      it("Correct number variable", function()
        local r = assert(client:send {
          method = "POST",
          path = "/graphql", 
          headers = {
            host = "postman-echo.com",
            ["Content-type"] = "application/json"
          },
          body = [[
            {"query":"query activateStatus ($teamId: ID!) { activateStatus (teamId: $teamId) { businessAccountStatus  kycLevel } }",
              "variables": {"teamId": 1}
            }
          ]]
        })
        assert.response(r).has.status(200)
      end)
        
      it("Incorrect number variable", function()
        local r = assert(client:send {
          method = "POST",
          path = "/graphql", 
          headers = {
            host = "postman-echo.com",
            ["Content-type"] = "application/json"
          },
          body = [[
            {"query":"query activateStatus ($teamId: ID!) { activateStatus (teamId: $teamId) { businessAccountStatus  kycLevel } }",
              "variables": {"teamId": 0}
            }
          ]]
        })
        assert.response(r).has.status(400)
      end)
      
      it("Required parameter exist", function()
        local r = assert(client:send {
          method = "POST",
          path = "/graphql", 
          headers = {
            host = "postman-echo.com",
            ["Content-type"] = "application/json"
          },
          body = [[
            {"query":"mutation createToken1 ($input: CreateTokenMutationInput!) { createToken (input: $input) {  token  } } ",
              "variables": {"email":"a@a.com", "password":"abc"}
            }
          ]]
        })
        assert.response(r).has.status(200)
      end)
      
      it("Required parameter not exist", function()
        local r = assert(client:send {
          method = "POST",
          path = "/graphql", 
          headers = {
            host = "postman-echo.com",
            ["Content-type"] = "application/json"
          },
          body = [[
            {"query":"mutation createToken1 ($input: CreateTokenMutationInput!) { createToken (input: $input) {  token  } } ",
              "variables": {"email":"a@a.com"}
            }
          ]]
        })
        assert.response(r).has.status(400)
      end)


    end)

  end)
end