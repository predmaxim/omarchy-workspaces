-- predmaxim.workspaces engine inside Hyprland: app → desk rules, places in schemes,
-- foreign windows, collapsing, single-instance apps. Settings: config.json (the
-- plugin's modal writes it and runs `hyprctl reload`, which re-runs this file).
local dir = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
dofile(dir .. "prefix.lua")(dir)
local config = require("predmaxim_workspaces.config")
local bind = require("predmaxim_workspaces.bind")
local collapse = require("predmaxim_workspaces.collapse")
local single = require("predmaxim_workspaces.single")

local cfg = config.load()
local function get_cfg() return cfg end
local desks = config.active(cfg)

local function fixed_of(c)
  local out = {}
  for ws, d in pairs(config.active(c)) do
    if next(d.slots) ~= nil or (d.name and d.name.mode == "static") then out[tonumber(ws)] = true end
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

-- Master schemes: the window of place 1 must be the master, wherever the desk is shown
-- (hl.dsp.layout acts on the active desk, so swap by address instead).
local function place_master(ws, d)
  local tiled, first = {}, nil
  for _, o in ipairs(hl.get_workspace_windows(ws)) do
    if not o.floating and o.workspace and o.workspace.id == ws then tiled[#tiled + 1] = o end
  end
  local key = bind.layout(d.scheme).orientation == "top" and "y" or "x"
  local master
  for _, o in ipairs(tiled) do
    if not first and bind.slot(d, o.class, {}) == 1 then first = o end
    if not master or o.at[key] < master.at[key] then master = o end
  end
  if first and master and first.address ~= master.address then
    hl.dispatch(hl.dsp.window.swap({ window = "address:" .. first.address, target = "address:" .. master.address }))
  end
end

if predmaxim_workspaces then
  for _, sub in ipairs(predmaxim_workspaces.subs or {}) do sub:remove() end
end
local subs = {}
local function on(ev, fn) subs[#subs + 1] = hl.on(ev, fn) end

on("window.open", function(w)
  if not w or not w.workspace or w.floating then return end
  local id = w.workspace.id
  local d = desks[tostring(id)]
  if not d then return end
  local taken = {}
  for _, o in ipairs(hl.get_workspace_windows(id)) do
    if o.address ~= w.address and o.workspace and o.workspace.id == id then
      local i = bind.slot(d, o.class, taken)
      if i then taken[i] = true end
    end
  end
  local i = bind.slot(d, w.class, taken)
  if i then
    if d.scheme == "grid" then
      local active = hl.get_active_workspace()
      if active and active.id == id then
        for _, msg in ipairs(bind.place_cmds(d.scheme, i, config.PLACES[d.scheme])) do hl.dispatch(hl.dsp.layout(msg)) end
      end
    elseif bind.layout(d.scheme) then
      -- ponytail: wait for the layout to give the new window its position; 50 ms was enough live.
      hl.timer(function() place_master(id, d) end, { timeout = 50, type = "oneshot" })
    end
    return
  end
  local f = bind.foreign(cfg, desks, tostring(id), occupied())
  local win = "address:" .. w.address
  if f.action == "float" then
    hl.dispatch(hl.dsp.window.float({ window = win, action = "enable" }))
    hl.dispatch(hl.dsp.window.center({ window = win }))
  elseif f.action == "move" then
    hl.dispatch(hl.dsp.window.move({ window = win, workspace = tostring(f.workspace) }))
  end
end)

local function schedule() hl.timer(function() collapse.run(get_cfg, fixed_of) end, { timeout = 50, type = "oneshot" }) end
on("workspace.removed", schedule)
on("window.open", schedule)
on("window.move_to_workspace", schedule)

subs[#subs + 1] = single.setup(function() return cfg.singleInstance end)

predmaxim_workspaces = { subs = subs, reload = function() hl.exec_cmd("hyprctl reload") end }
