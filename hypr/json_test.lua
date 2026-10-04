-- hypr/json_test.lua
package.path = arg[0]:match("(.*/)") .. "?.lua;" .. package.path
local json = require("json")
local v = json.decode('{"a":[1,2.5,"x\\n\\u0416",true,false,null],"b":{}}')
assert(v.a[1] == 1 and v.a[2] == 2.5 and v.a[3] == "x\nЖ" and v.a[4] == true and v.a[5] == false)
assert(v.a[6] == nil and #v.a == 6, "null keeps the array length")
assert(next(v.b) == nil)
local bad, err = json.decode('{"a":')
assert(bad == nil and err:find("unexpected end"))
assert(json.decode("") == nil)
print("json ok")
