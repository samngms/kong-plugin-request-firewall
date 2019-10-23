local base64 = require("kong.plugins.request-firewall.base64")
local mime = require("mime")

describe("Base64 Decoding", function()
    describe("valid input", function()
        it("Simple case 1", function()
            local str, err = base64.decode("cGxlYXN1cmUu")
            assert.is_nil(err)
            assert.is_equal("pleasure.", str)
        end)

        it("Simple case 2", function()
            local str, err = base64.decode("bGVhc3VyZS4=")
            assert.is_nil(err)
            assert.is_equal("leasure.", str)
        end)

        it("Simple case 3", function()
            local str, err = base64.decode("ZWFzdXJlLg==")
            assert.is_nil(err)
            assert.is_equal("easure.", str)
        end)

        it("Randome input", function()
            local i
            for i=1,10000 do
                local len = math.random(1, 9)
                local bytes = {}
                local j
                for j=1,len do
                    local b = math.random(0, 255)
                    table.insert(bytes, string.char(b))
                end
                local str = table.concat(bytes)
                local b64 = mime.b64(str)
                local str2, err = base64.decode(b64)
                assert.is_nil(err)
                assert.is_equal(str, str2)
            end
        end)
    end)

    describe("invalid input", function()
        it("Invalid padding 1", function()
            local str, err = base64.decode("TR==")
            assert.is.not_nil(err)
            local idx = string.find(err, "the last 4 bits of the throw-away byte", 1, true)
            assert.is.not_nil(idx)
        end)

        it("Invalid padding 2", function()
            local str, err = base64.decode("TWF=")
            assert.is.not_nil(err)
            local idx = string.find(err, "the last 2 bits of the throw-away byte", 1, true)
            assert.is.not_nil(idx)
        end)

        it("Invalid padding 3", function()
            local str, err = base64.decode("T===")
            assert.is.not_nil(err)
            local idx = string.find(err, "Invalid base64 char \"=\"", 1, true)
            assert.is.not_nil(idx)
        end)

        it("Invalid char", function()
            local str, err = base64.decode("ZW.z")
            assert.is.not_nil(err)
            local idx = string.find(err, "Invalid base64 char \".\"", 1, true)
            assert.is.not_nil(idx)
        end)

        it("Invalid length", function()
            local str, err = base64.decode("abcde")
            assert.is.not_nil(err)
            local idx = string.find(err, "Invalid base64 string length", 1, true)
            assert.is.not_nil(idx)
        end)

        it("Random bad input", function()
            local i
            for i=1,10000 do
                local len = math.random(1, 9)
                local bytes = {}
                local j
                for j=1,len do
                    local b = math.random(0, 255)
                    table.insert(bytes, string.char(b))
                end
                local str = table.concat(bytes)
                local str2, err = base64.decode(str)
                assert.truthy(str2 or err)
            end
        end)
    end)

end)