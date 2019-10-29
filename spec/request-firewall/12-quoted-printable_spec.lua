local qp = require("kong.plugins.request-firewall.quoted-printable")
local mime = require("mime")

describe("Quoted-printable Decoding", function()
    it("it works", function()
        local str = qp.decode("ab=41=42=")
        assert.is_equal("abAB=", str)
    end)

    it("it works 2", function()
        local str = qp.decode("=41=42=")
        assert.is_equal("AB=", str)
    end)

    it("it works 3", function()
        local str = qp.decode("=41")
        assert.is_equal("A", str)
    end)

    it("hex code is case insensitive", function()
        local str = qp.decode("ab=4f=4F")
        assert.is_equal("abOO", str)
    end)

    it("hex code is not recurrsive", function()
        local str = qp.decode("ab=3D41")
        assert.is_equal("ab=41", str)
    end)

    it("skip invalid codes", function()
        local str = qp.decode("a=41=3Xport")
        assert.is_equal("aA=3Xport", str)
    end)

    it("can handle null byte", function()
        local str = qp.decode("abc=00def")
        assert.is_equal("abc\0def", str)
    end)

    it("ignore newline in encoded string", function() 
        local str = qp.decode("ab\r\nde=0d=0azz")
        assert.is_equal("abde\r\nzz", str)
    end)
end)