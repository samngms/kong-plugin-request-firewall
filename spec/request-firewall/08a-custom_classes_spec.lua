local helpers = require "spec.helpers"
local version = require("version").version or require("version")


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
  describe(PLUGIN_NAME .. ": (json-body) [#" .. strategy .. "]", function()
    local client

    lazy_setup(function()
      local bp, route1
      local myconfig = {
        exact_match = {
          ["/post"] = {
            POST = {
              body = {
                usertx = {type = "UserTx"},
                timestamp = {type = "number", required = true}
              },
              custom_classes = {
                UserClass = {
                  uid = {type = "number", required = true, max = 1000000},
                  roles = {type = "string", is_array = 1, min = 1, max = 32}
                },
                Transaction = {
                  to = {type = "string", min = 1, max = 100},
                  amount = {type = "number", max = 1000000}
                },
                UserTx = {
                  user = {type = "UserClass", required = true},
                  transaction = {type = "Transaction"}
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


    describe("testing custom classes", function()

      it("valid body", function()
        local r = assert(client:send {
          method = "POST",
          path = "/post", 
          headers = {
            host = "postman-echo.com",
            ["Content-type"] = "application/json"
          },
          body = '{"usertx":{"user":{"uid":123,"roles":["manager","finance_dept"]},"transaction":{"to":"mary","amount":12.34}},"timestamp":36882121}'
        })
        assert.response(r).has.status(200)
      end)

      it("invalid body - unexpected field: tx", function()
        local r = assert(client:send {
          method = "POST",
          path = "/post", 
          headers = {
            host = "postman-echo.com",
            ["Content-type"] = "application/json"
          },
          body = '{"usertx":{"user":{"uid":123,"roles":["manager","finance_dept"]},"tx":{"to":"mary","amount":12.34}},"timestamp":36882121}'
        })
        assert.response(r).has.status(400)
      end)

      it("invalid body - missing user.uid", function()
        local r = assert(client:send {
          method = "POST",
          path = "/post", 
          headers = {
            host = "postman-echo.com",
            ["Content-type"] = "application/json"
          },
          body = '{"usertx":{"user":{"roles":["manager","finance_dept"]},"transaction":{"to":"mary","amount":12.34}},"timestamp":36882121}'
        })
        assert.response(r).has.status(400)
      end)

      it("invalid body - missing user obj", function()
        local r = assert(client:send {
          method = "POST",
          path = "/post", 
          headers = {
            host = "postman-echo.com",
            ["Content-type"] = "application/json"
          },
          body = '{"usertx":{transaction":{"to":"mary","amount":12.34}},"timestamp":36882121}'
        })
        assert.response(r).has.status(400)
      end)

      it("invalid body - missing timestamp", function()
        local r = assert(client:send {
          method = "POST",
          path = "/post", 
          headers = {
            host = "postman-echo.com",
            ["Content-type"] = "application/json"
          },
          body = '{"usertx":{"user":{"uid":123,"roles":["manager","finance_dept"]},"transaction":{"to":"mary","amount":12.34}}}'
        })
        assert.response(r).has.status(400)
      end)

    end)

  end)
end
