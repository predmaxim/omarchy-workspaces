-- predmaxim.workspaces engine inside Hyprland: app → desk rules, places in schemes,
-- foreign windows, collapsing, single-instance apps. Settings: config.json (the
-- plugin's modal writes it and runs `hyprctl reload`, which re-runs this file).
local dir = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
package.path = dir .. "?.lua;" .. package.path
local config = require("config")
local bind = require("bind")
local collapse = require("collapse")
local single = require("single")

local cfg = config.load()
local function get_cfg() return cfg end
local desks = config.active(cfg)

local function fixed_of(c)
  local out = {}
  for ws, d in pairs(config.active(c)) do
    if #d.slots > 0 or (d.name and d.name.mode == "static") then out[tonumber(ws)] = true end
  end
  return out
end

for _, r in ipairs(bind.rules(desks)) do
  hl.window_rule({ match = { class = r.class }, workspace = r.workspace .. " silent" })
end
for ws, d in pairs(desks) do
  local l = bind.layout(d.scheme)
  if l then
    hl.workspace_rule({ workspace = ws, layout = l.layout,
                        layout_opts = l.orientation and { orientation = l.orientation } or nil })
  end
end

local function occupied()
  local out = {}
  for _, w in ipairs(hl.get_workspaces()) do if w.id > 0 and w.windows > 0 then out[#out + 1] = w.id end end
  return out
end

hl.on("window.open", function(w)
  if not w.workspace or w.floating then return end
  local ws = tostring(w.workspace.id)
  local d = desks[ws]
  if not d then return end
  local taken = {}
  for _, o in ipairs(hl.get_windows({ workspace = w.workspace.id })) do
    if o.address ~= w.address then
      local i = bind.slot(d, o.class, taken)
      if i then taken[i] = true end
    end
  end
  local i = bind.slot(d, w.class, taken)
  if i then
    for _, msg in ipairs(bind.place_cmds(d.scheme, i, #d.slots)) do hl.dispatch(hl.dsp.layout(msg)) end
    return
  end
  local f = bind.foreign(cfg, desks, ws, occupied())
  local win = "address:" .. w.address
  if f.action == "float" then
    hl.dispatch(hl.dsp.window.float({ window = win, action = "enable" }))
    hl.dispatch(hl.dsp.window.center({ window = win }))
  elseif f.action == "move" then
    hl.dispatch(hl.dsp.window.move({ window = win, workspace = tostring(f.workspace) }))
  end
end)

local function schedule() hl.timer(function() collapse.run(get_cfg, fixed_of) end, { timeout = 50, type = "oneshot" }) end
hl.on("workspace.removed", schedule)
hl.on("window.open", schedule)
hl.on("window.move_to_workspace", schedule)

single.setup(function() return cfg.singleInstance end)

predmaxim_workspaces = { reload = function() hl.exec_cmd("hyprctl reload") end }
