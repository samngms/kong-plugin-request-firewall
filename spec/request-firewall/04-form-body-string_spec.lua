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
  describe(PLUGIN_NAME .. ": (form-body) [#" .. strategy .. "]", function()
    local client

    lazy_setup(function()
      local bp, route1
      local myconfig = {
        exact_match = {
          ["/post"] = {
            body = {
              b1 = {type = "string", min = 2, max = 5, not_match = "%p"},
              b_match = {type = "string", match = "^sam$"},
              b_enum = {type = "string", is_array = 2, enum = {"Monday", "WednesdayTuesday", "Wednesday"}},
              b_array = {type = "string", is_array = 1},
              b_any = {type = "string", allow_null = true},
              b_any2 = {type = "string", allow_null = false, min = 1}
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

      it("unexpected param name", function()
        local r = assert(client:send {
          method = "POST",
          path = "/post", 
          headers = {
            host = "postman-echo.com",
            ["Content-type"] = "application/x-www-form-urlencoded"
          },
          body = "no_such_name=foobar"
        })
        assert.response(r).has.status(400)
      end)

      it("min", function()
        local r = assert(client:send {
          method = "POST",
          path = "/post", 
          headers = {
            host = "postman-echo.com",
            ["Content-type"] = "application/x-www-form-urlencoded"
          },
          -- min is 2
          body = "b1=a"
        })
        assert.response(r).has.status(400)
      end)

      it("max", function()
        local r = assert(client:send {
          method = "POST",
          path = "/post",
          headers = {
            host = "postman-echo.com",
            ["Content-type"] = "application/x-www-form-urlencoded"
          },
          body = "b1=hello12"          
        })
        assert.response(r).has.status(400)
      end)

      it("not_match", function()
        local r = assert(client:send {
          method = "POST",
          path = "/post",
          headers = {
            host = "postman-echo.com",
            ["Content-type"] = "application/x-www-form-urlencoded"
          },
          body = "b1=a(b)"
        })
        assert.response(r).has.status(400)
      end)

      it("good match", function()
        local r = assert(client:send {
          method = "POST",
          path = "/post",
          headers = {
            host = "postman-echo.com",
            ["Content-type"] = "application/x-www-form-urlencoded"
          },
          body = "b_match=sam"
        })
        assert.response(r).has.status(200)
      end)
    
      it("bad match", function()
        local r = assert(client:send {
          method = "POST",
          path = "/post",
          headers = {
            host = "postman-echo.com",
            ["Content-type"] = "application/x-www-form-urlencoded"
          },
          body = "b_match=tom"
        })
        assert.response(r).has.status(400)
      end)

      it("good enum", function()
        local r = assert(client:send {
          method = "POST",
          path = "/post",
          headers = {
            host = "postman-echo.com",
            ["Content-type"] = "application/x-www-form-urlencoded"
          },
          body = "b_enum=Monday"
        })
        assert.response(r).has.status(200)
      end)

      it("good enum (array)", function()
        local r = assert(client:send {
          method = "POST",
          path = "/post",
          headers = {
            host = "postman-echo.com",
            ["Content-type"] = "application/x-www-form-urlencoded"
          },
          -- http_proxy has problem handling table correctly
          body = "b_enum=Monday&b_enum=Wednesday"
        })
        assert.response(r).has.status(200)
      end)

      it("bad enum", function()
        local r = assert(client:send {
          method = "POST",
          path = "/post",
          headers = {
            host = "postman-echo.com",
            ["Content-type"] = "application/x-www-form-urlencoded"
          },
          body = "b_enum=Sunday"
        })
        assert.response(r).has.status(400)
      end)

      it("bad enum (array)", function()
        local r = assert(client:send {
          method = "POST",
          path = "/post",
          headers = {
            host = "postman-echo.com",
            ["Content-type"] = "application/x-www-form-urlencoded"
          },
          -- http_proxy has problem handling table correctly
          body = "b_enum=Monday&b_enum=Sunday"
        })
        assert.response(r).has.status(400)
      end)

      it("good array", function()
        local r = assert(client:send {
          method = "POST",
          path = "/post",
          headers = {
            host = "postman-echo.com",
            ["Content-type"] = "application/x-www-form-urlencoded"
          },
          -- http_proxy has problem handling table correctly
          body = "b_array=a&b_array=b"
        })
        assert.response(r).has.status(200)
      end)

      it("bad array", function()
        local r = assert(client:send {
          method = "POST",
          path = "/post",
          headers = {
            host = "postman-echo.com",
            ["Content-type"] = "application/x-www-form-urlencoded"
          },
          -- http_proxy has problem handling table correctly
          body = "b_array=a"
        })
        assert.response(r).has.status(400)
      end)

      it("null string case 1", function()
        local r = assert(client:send {
          method = "POST",
          path = "/post",
          headers = {
            host = "postman-echo.com",
            ["Content-type"] = "application/x-www-form-urlencoded"
          },
          body = "b1=abc&b_any"
        })
        assert.response(r).has.status(200)
      end)

      it("null string case 2", function()
        local r = assert(client:send {
          method = "POST",
          path = "/post",
          headers = {
            host = "postman-echo.com",
            ["Content-type"] = "application/x-www-form-urlencoded"
          },
          body = "b1=abc&b_any2"
        })
        assert.response(r).has.status(400)
      end)

      it("empty string case", function()
        local r = assert(client:send {
          method = "POST",
          path = "/post",
          headers = {
            host = "postman-echo.com",
            ["Content-type"] = "application/x-www-form-urlencoded"
          },
          body = "b_any="
        })
        assert.response(r).has.status(200)
      end)

    end)

  end)
end
