local MultiPart = require("kong.plugins.request-firewall.multipart")

describe("Multipart testing", function()
    it("should work", function()
        local parser = MultiPart:new("multipart/form-data; boundary=---------------------------735323031399963166993862150")
        assert.truthy(parser:isFormData())
        local filename = os.tmpname();
        local tmpfile = io.open(filename, "wb")
        local s = [[-----------------------------735323031399963166993862150
Content-Disposition: form-data; name="text1"
Content-Transfer-Encoding: quoted-printable

ab=41abc
-----------------------------735323031399963166993862150
Content-Disposition: form-data; name="file2"; filename="a.html"
Content-Type: text/html

<!DOCTYPE html><title>Content of a.html.
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
</title>
-----------------------------735323031399963166993862150
Content-Disposition: form-data; name="text2"
Content-Transfer-Encoding: base64

aGVsbG8gd29ybGQ=
-----------------------------735323031399963166993862150
Content-Disposition: form-data; name="text3"

aGVsbG8gd29ybGQ=
-----------------------------735323031399963166993862150--]]
        s = s:gsub("\n", "\r\n")
        tmpfile:write(s);
        tmpfile:close()
        local data = parser:parseFile(filename)
        assert.is_equal(data.text1, "abAabc")
        assert.is_equal(data.file2.filename, "a.html")
        assert.truthy(data.file2.size > 400)
        assert.is_equal(data.file2.contentType, "text/html")
        assert.is_equal(data.text2, "hello world")
        assert.is_equal(data.text3, "aGVsbG8gd29ybGQ=")
    end)

    it("should reject unknown transfer encoding", function()
        local parser = MultiPart:new("multipart/form-data; boundary=---------------------------735323031399963166993862150")
        assert.truthy(parser:isFormData())
        local filename = os.tmpname();
        local tmpfile = io.open(filename, "wb")
        local s = [[-----------------------------735323031399963166993862150
Content-Disposition: form-data; name="text1"
Content-Transfer-Encoding: quoted-printable2

ab=41abc
-----------------------------735323031399963166993862150--]]
        s = s:gsub("\n", "\r\n")
        tmpfile:write(s);
        tmpfile:close()

        local data, err = pcall(function () parser:parseFile(filename) end)
        assert.is.not_nil(err)
        local idx = string.find(err, "Invalid Content-Transfer-Encoding", 1, true)
        assert.is.not_nil(idx)
    end)

    it("should reject unclosed boundary", function()
        local parser = MultiPart:new("multipart/form-data; boundary=---------------------------735323031399963166993862150")
        assert.truthy(parser:isFormData())
        local filename = os.tmpname();
        local tmpfile = io.open(filename, "wb")
        local s = [[-----------------------------735323031399963166993862150
Content-Disposition: form-data; name="text1"

abcdef
-----------------------------735323031399963166993862151--]]
        s = s:gsub("\n", "\r\n")
        tmpfile:write(s);
        tmpfile:close()

        local data, err = pcall(function () parser:parseFile(filename) end)
        assert.is.not_nil(err)
        local idx = string.find(err, "end-of-boundary", 1, true)
        assert.is.not_nil(idx)
    end)
end)