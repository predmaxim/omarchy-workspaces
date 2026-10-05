-- hypr/bind_test.lua
local dir = arg[0]:match("(.*/)") or "./"; dofile(dir .. "prefix.lua")(dir)
local config = require("predmaxim_workspaces.config")
local bind = require("predmaxim_workspaces.bind")
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
assert(bind.foreign(cfg, desks, "2", {}).action == "tile", "single desk keeps it")
local one = config.active(config.parse('{"workspaces":{"3":{"scheme":"left-right","slots":[{"class":"a"}]}}}'))
assert(bind.foreign(cfg, one, "3", {}).action == "move", "scheme with one bound place still guards it")
-- place_cmds: exact strings as per controller decision
assert(#bind.place_cmds("single", 1, 1) == 0)
assert(#bind.place_cmds("left-right", 1, 2) == 1 and bind.place_cmds("left-right", 1, 2)[1] == "swapwithmaster master")
assert(#bind.place_cmds("left-right", 2, 2) == 0)
assert(#bind.place_cmds("top-bottom", 1, 2) == 1 and bind.place_cmds("top-bottom", 1, 2)[1] == "swapwithmaster master")
assert(#bind.place_cmds("main-left", 1, 3) == 1 and bind.place_cmds("main-left", 1, 3)[1] == "swapwithmaster master")
assert(#bind.place_cmds("grid", 1, 2) == 1 and bind.place_cmds("grid", 1, 2)[1] == "preselect r")
assert(#bind.place_cmds("grid", 2, 2) == 1 and bind.place_cmds("grid", 2, 2)[1] == "preselect d")
assert(#bind.place_cmds("grid", 3, 4) == 0)
assert(bind.layout("main-right").layout == "dwindle")
assert(bind.place_cmds("main-right", 1, 4)[1] == "preselect l" and bind.place_cmds("main-right", 2, 4)[1] == "preselect r")
assert(bind.place_cmds("main-right", 3, 4)[1] == "preselect d" and #bind.place_cmds("main-right", 4, 4) == 0)
-- holes: [null, A] on left-right → A is place 2
local holes = config.active(config.parse('{"workspaces":{"4":{"scheme":"left-right","slots":[null,{"app":"a.desktop","class":"a"}]}}}'))
assert(holes["4"].slots[1] == nil and holes["4"].slots[2].class == "a", "hole kept")
assert(bind.slot(holes["4"], "a", {}) == 2, "A keeps place 2")
assert(#bind.rules(holes) == 1 and bind.rules(holes)[1].workspace == "4")
print("bind ok")

-- an app on two desks: one rule (first desk); new windows fill the desks in order
local two = config.active(config.parse('{"workspaces":{"3":{"slots":[{"class":"f"}]},"2":{"scheme":"left-right","slots":[{"class":"w"},{"class":"f"}]}}}'))
local fr = 0
for _, r in ipairs(bind.rules(two)) do if r.class == "^(f)$" then fr = fr + 1; assert(r.workspace == "2") end end
assert(fr == 1)
assert(bind.target(two, "f", {}) == "2" and bind.target(two, "f", { ["2"] = 1 }) == "3")
assert(bind.target(two, "f", { ["2"] = 1, ["3"] = 1 }) == "2" and bind.target(two, "x", {}) == nil)
print("ok target")
