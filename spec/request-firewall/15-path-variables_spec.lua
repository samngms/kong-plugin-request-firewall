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
                q1 = {type = "string", min = 2, max = 5, not_match = "%p"},
                q_match = {type = "string", match = "^sam$"},
                q_enum = {type = "string", is_array = 2, enum = {"Monday", "WednesdayTuesday", "Wednesday"}},
                q_array = {type = "string", is_array = 1}
              }
            }
          }
        },
        pattern_match = {
          ["/get/v1/${job}/${id}"] = {
            GET = {
              path = {
                job = {type = "string", max = 10},
                id = {type = "number", min = 10}
              }
            }
          },
          ["/get/v2/${id:%d+}/show"] = {
            GET = {
              path = {
                id = {type = "number", min = 100}
              }
            }
          },
          ["/get/v2/x-${id:%d+}/show"] = {
            GET = {
              path = {
                id = {type = "number", min = 10}
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


    describe("testing query string", function()

      it("happy path 1", function()
        local r = assert(client:send {
          method = "GET",
          path = "/get/v1/update/123",
          headers = {
            host = "postman-echo.com"
          }
        })
        assert.response(r).has.status(200)
      end)

      it("value is hex decoded", function()
        local r = assert(client:send {
          method = "GET",
          -- if not decoded, len will be over 10
          path = "/get/v1/update000%3d/123",
          headers = {
            host = "postman-echo.com"
          }
        })
        assert.response(r).has.status(200)
      end)

      it("job name too long", function()
        local r = assert(client:send {
          method = "GET",
          path = "/get/v1/update-very-long0000000/123",
          headers = {
            host = "postman-echo.com"
          }
        })
        assert.response(r).has.status(400)
      end)

      it("invalid id", function()
        local r = assert(client:send {
          method = "GET",
          path = "/get/v1/update/aaa",
          headers = {
            host = "postman-echo.com"
          }
        })
        assert.response(r).has.status(400)
      end)

      it("regex is working properly 1", function()
        local r = assert(client:send {
          method = "GET",
          path = "/get/v2/x-12/show",
          headers = {
            host = "postman-echo.com"
          }
        })
        assert.response(r).has.status(200)
      end)

      it("regex is working properly 2", function()
        local r = assert(client:send {
          method = "GET",
          path = "/get/v2/x-abc/show",
          headers = {
            host = "postman-echo.com"
          }
        })
        assert.response(r).has.status(404)
      end)

      it("regex is working properly 3", function()
        local r = assert(client:send {
          method = "GET",
          path = "/get/v2/12/show",
          headers = {
            host = "postman-echo.com"
          }
        })
        assert.response(r).has.status(400)
      end)

      it("regex is working properly 4", function()
        local r = assert(client:send {
          method = "GET",
          path = "/get/v2/123/show",
          headers = {
            host = "postman-echo.com"
          }
        })
        assert.response(r).has.status(200)
      end)
    
    end)

  end)
end
