-- hypr/bind_test.lua
package.path = arg[0]:match("(.*/)") .. "?.lua;" .. package.path
local config = require("config")
local bind = require("bind")
local cfg = config.parse([[{"workspaces":{
  "1":{"scheme":"main-left","slots":[{"class":"code"},{"class":"firefox"},{"class":"foot"}]},
  "2":{"scheme":"single","slots":[{"class":"chrome-x.y__-Default"}]}}}]])
local desks = config.active(cfg)
local r = bind.rules(desks)
table.sort(r, function(a, b) return a.class < b.class end)
assert(#r == 4)
assert(r[1].class == "^(chrome\\-x\\.y__\\-Default)$" and r[1].workspace == "2", "regex-escaped class")
assert(bind.layout("main-left").layout == "master" and bind.layout("main-left").orientation == "left")
assert(bind.layout("top-bottom").orientation == "top")
assert(bind.layout("grid").layout == "dwindle" and bind.layout("single") == nil)
assert(bind.slot(desks["1"], "firefox", {}) == 2)
assert(bind.slot(desks["1"], "code", { [1] = true }) == nil, "second code window is foreign")
assert(bind.slot(desks["1"], "nautilus", {}) == nil)
-- foreign
assert(bind.foreign(cfg, desks, "1", { 1, 3 }).action == "tile")
cfg.foreignWindow = "float"; assert(bind.foreign(cfg, desks, "1", {}).action == "float")
cfg.foreignWindow = "next"
local f = bind.foreign(cfg, desks, "1", { 1, 2, 3 })
assert(f.action == "move" and f.workspace == 4, "first free desk without bindings")
assert(bind.foreign(cfg, desks, "5", {}).action == "tile", "desk without a scheme keeps it")
-- place_cmds: exact strings as per controller decision
assert(#bind.place_cmds("single", 1, 1) == 0)
assert(#bind.place_cmds("left-right", 1, 2) == 1 and bind.place_cmds("left-right", 1, 2)[1] == "swapwithmaster master")
assert(#bind.place_cmds("left-right", 2, 2) == 0)
assert(#bind.place_cmds("top-bottom", 1, 2) == 1 and bind.place_cmds("top-bottom", 1, 2)[1] == "swapwithmaster master")
assert(#bind.place_cmds("main-left", 1, 3) == 1 and bind.place_cmds("main-left", 1, 3)[1] == "swapwithmaster master")
assert(#bind.place_cmds("grid", 1, 2) == 1 and bind.place_cmds("grid", 1, 2)[1] == "preselect r")
assert(#bind.place_cmds("grid", 2, 2) == 1 and bind.place_cmds("grid", 2, 2)[1] == "preselect d")
assert(#bind.place_cmds("grid", 3, 4) == 0)
print("bind ok")
