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
  describe(PLUGIN_NAME .. ": (query) [#" .. strategy .. "]", function()
    local client

    lazy_setup(function()
      local bp, route1
      local myconfig = {
        exact_match = {
          ["/get"] = {
            GET = {
              query = {
                n0 = {type = "number"},
                n1 = {type = "number", precision = 4, min = -10, max = 100},
                n2 = {type = "number", positive = false, max = 100},
                n3 = {type = "number", is_array = 2, max = 100},
                n4 = {type = "number", is_array = 2, enum = {"10", "100", "1000"}},
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


    describe("testing query number", function()

      it("default positive number only", function()
        local r = assert(client:send {
          method = "GET",
          path = "/get", 
          headers = {
            host = "postman-echo.com"
          },
          query = "n0=-0.1"
        })
        assert.response(r).has.status(400)
      end)

      it("digits only", function()
        local r = assert(client:send {
          method = "GET",
          path = "/get", 
          headers = {
            host = "postman-echo.com"
          },
          query = "n0=1e1"
        })
        assert.response(r).has.status(400)
      end)

      it("min (bad1)", function()
        local r = assert(client:send {
          method = "GET",
          path = "/get", 
          headers = {
            host = "postman-echo.com"
          },
          query = "n1=-10.1"
        })
        assert.response(r).has.status(400)
      end)

      it("min (good)", function()
        local r = assert(client:send {
          method = "GET",
          path = "/get", 
          headers = {
            host = "postman-echo.com"
          },
          query = "n1=-10"
        })
        assert.response(r).has.status(200)
      end)

      it("max (good)", function()
        local r = assert(client:send {
          method = "GET",
          path = "/get",
          headers = {
            host = "postman-echo.com"
          },
          query = "n1=100"
        })
        assert.response(r).has.status(200)
      end)

      it("max (bad)", function()
        local r = assert(client:send {
          method = "GET",
          path = "/get",
          headers = {
            host = "postman-echo.com"
          },
          query = "n1=100.01"
        })
        assert.response(r).has.status(400)
      end)

      it("precision", function()
        local r = assert(client:send {
          method = "GET",
          path = "/get",
          headers = {
            host = "postman-echo.com"
          },
          query = "n1=20.12345"
        })
        assert.response(r).has.status(400)
      end)

      it("positive=false", function()
        local r = assert(client:send {
          method = "GET",
          path = "/get",
          headers = {
            host = "postman-echo.com"
          },
          query = "n2=0"
        })
        assert.response(r).has.status(200)
      end)
    
      it("array (good)", function()
        local r = assert(client:send {
          method = "GET",
          path = "/get",
          headers = {
            host = "postman-echo.com"
          },
          query = "n3=1&n3=2"
        })
        assert.response(r).has.status(200)
      end)
 
      it("array (bad)", function()
        local r = assert(client:send {
          method = "GET",
          path = "/get",
          headers = {
            host = "postman-echo.com"
          },
          query = "n3=1&n3=101"
        })
        assert.response(r).has.status(400)
      end)

      it("good enum1", function()
        local r = assert(client:send {
          method = "GET",
          path = "/get", 
          headers = {
            host = "postman-echo.com"
          },
          query = "n4=100"
        })
        assert.response(r).has.status(200)
      end)

      it("good enum2", function()
        local r = assert(client:send {
          method = "GET",
          path = "/get", 
          headers = {
            host = "postman-echo.com"
          },
          query = "n4=100&n4=10"
        })
        assert.response(r).has.status(200)
      end)

      it("bad enum", function()
        local r = assert(client:send {
          method = "GET",
          path = "/get", 
          headers = {
            host = "postman-echo.com"
          },
          query = "n4=100&n4=99"
        })
        assert.response(r).has.status(400)
      end)

    end)

  end)
end
