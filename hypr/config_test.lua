-- hypr/config_test.lua
package.path = arg[0]:match("(.*/)") .. "?.lua;" .. package.path
local config = require("config")
local c = config.parse("{}")
assert(c.foreignWindow == "tile" and c.collapse == "free" and c.collapseInSession == "free")
assert(c.sequentialLaunch == false and c.schedule == true and #c.singleInstance == 0)
c = config.parse('{"foreignWindow":"warp","collapse":"all"}')
assert(c.foreignWindow == "tile", "unknown value -> default")
assert(c.collapse == "all")
c = config.parse([[{"workspaces":{"1":{"scheme":"left-right","slots":[{"app":"a.desktop","class":"a"}]}},
  "sessions":{"Работа":{"workspaces":{"2":{"slots":[{"app":"b.desktop","class":"b"}]}}}},
  "activeSession":"Работа"}]])
local act = config.active(c)
assert(act["2"] and act["2"].slots[1].class == "b" and act["1"] == nil, "session replaces plain desks")
c.activeSession = "Нет такой"
assert(config.active(c)["1"], "missing session -> plain desks")
local s = config.parse('{"workspaces":{"1":{"scheme":"single","slots":[{"class":"a"},{"class":"b"}]}}}')
assert(#s.workspaces["1"].slots == 1, "slots cut to the scheme's places")
local bad, err = config.parse("{")
assert(bad == nil and err)
print("config ok")
