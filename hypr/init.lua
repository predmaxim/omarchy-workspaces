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

-- Omarchy 4.5 gives every monitor desks 1-10 of its own, a block of ten workspace
-- ids each (default/hypr/monitor-workspaces.lua). A desk key here is a slot on the
-- focused monitor, as Super + N is; Omarchy's o.workspaces turns it into an id.
local SLOTS = o.workspaces.slots
local function block_of(monitor) return (o.workspaces.workspace_id(monitor, 1) - 1) // SLOTS end

-- The workspace of desk `key` ("3", "scratchpad" or a rule's "special:scratchpad")
-- on `monitor`, the focused one unless given; nil before Hyprland has a monitor.
local function ws_of(key, monitor)
  if key == bind.SCRATCH or key == bind.hypr_ws(bind.SCRATCH) then return bind.hypr_ws(bind.SCRATCH) end
  monitor = monitor or hl.get_active_monitor()
  return monitor and tostring(o.workspaces.workspace_id(monitor, tonumber(key))) or nil
end

-- The desk key of a workspace: its slot when it is in the focused monitor's own
-- block, nil for another monitor's workspace (or a guest from an unplugged one).
local function key_of(ws)
  if ws.name == bind.hypr_ws(bind.SCRATCH) then return bind.SCRATCH end
  local monitor = hl.get_active_monitor()
  if ws.id < 1 or not monitor or (ws.id - 1) // SLOTS ~= block_of(monitor) then return nil end
  return tostring((ws.id - 1) % SLOTS + 1)
end

local function fixed_of(c)
  local out = {}
  for ws, d in pairs(config.active(c)) do
    if tonumber(ws) and (next(d.slots) ~= nil or (d.name and d.name.mode == "static")) then out[tonumber(ws)] = true end
  end
  return out
end

-- Named rules, re-sent when the focus goes to another monitor, so apps open on
-- that monitor's desks: the way Omarchy keeps its own open rules current
-- (default/hypr/workspace-modes.lua). A desk's layout stays on the monitors it
-- was given to, so their desks keep their schemes.
local rules = bind.rules(desks)
local function sync_rules()
  if not hl.get_active_monitor() then return end
  for i, r in ipairs(rules) do
    hl.window_rule({ name = "predmaxim-workspaces-" .. i, enabled = true, match = { class = r.class }, workspace = ws_of(r.workspace) .. " silent" })
  end
  for ws, d in pairs(desks) do
    local l = bind.layout(d.scheme)
    if l then
      hl.workspace_rule({ workspace = ws_of(ws), layout = l.layout,
                          layout_opts = l.orientation and { orientation = l.orientation } or nil })
    end
  end
end
sync_rules()

-- Desks of the focused monitor with windows, as slots.
local function occupied()
  local out = {}
  for _, w in ipairs(hl.get_workspaces()) do
    local key = w.windows > 0 and key_of(w)
    if key and tonumber(key) then out[#out + 1] = tonumber(key) end
  end
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

-- `hyprctl reload` starts a fresh Lua state (checked: globals and old hl.on handlers
-- are gone), so there is nothing to unsubscribe here.
local function on(ev, fn) hl.on(ev, fn) end

-- At login the config runs before Hyprland has a monitor.
on("hyprland.start", sync_rules)
on("monitor.focused", sync_rules)

on("window.open", function(w)
  if not w or not w.workspace or w.floating then return end
  local id, key = w.workspace.id, key_of(w.workspace)
  -- An app on several desks: the rule put it on its first one; go where a place is free.
  local counts = {}
  for _, ws in ipairs(hl.get_workspaces()) do
    for _, o in ipairs(hl.get_workspace_windows(ws.id)) do
      if o.address ~= w.address and o.class == w.class and o.workspace and o.workspace.id == ws.id then
        local k = key_of(ws)
        if k then counts[k] = (counts[k] or 0) + 1 end
      end
    end
  end
  local to = bind.target(desks, w.class, counts)
  if key and to and to ~= key and bind.target(desks, w.class, {}) == key then
    hl.dispatch(hl.dsp.window.move({ window = "address:" .. w.address, workspace = ws_of(to), follow = false }))
    local td = desks[to]
    if tonumber(to) and bind.layout(td.scheme) and bind.layout(td.scheme).layout == "master" then
      hl.timer(function() place_master(tonumber(ws_of(to)), td) end, { timeout = 50, type = "oneshot" })
    end
    return
  end
  local d = key and desks[key]
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
    if (bind.layout(d.scheme) or {}).layout == "dwindle" then
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
  if key == bind.SCRATCH then return end   -- the scratchpad keeps any window sent there
  local f = bind.foreign(cfg, desks, key, occupied())
  local win = "address:" .. w.address
  if f.action == "float" then
    hl.dispatch(hl.dsp.window.float({ window = win, action = "enable" }))
    hl.dispatch(hl.dsp.window.center({ window = win }))
  elseif f.action == "move" then
    hl.dispatch(hl.dsp.window.move({ window = win, workspace = ws_of(tostring(f.workspace)) }))
  end
end)

local function schedule() hl.timer(function() collapse.run(get_cfg, fixed_of, SLOTS) end, { timeout = 50, type = "oneshot" }) end
on("workspace.removed", schedule)
on("window.open", schedule)
on("window.move_to_workspace", schedule)

single.setup(function() return cfg.singleInstance end)

predmaxim_workspaces = {
  reload = function() hl.exec_cmd("hyprctl reload") end,
  -- For the shell (`hyprctl dispatch 'predmaxim_workspaces.move("0x…", "3")'`): move a
  -- window to a desk of the focused monitor, as o.workspaces' own actions do.
  move = function(address, key)
    return function()
      local ws = ws_of(tostring(key))
      if ws then hl.dispatch(hl.dsp.window.move({ window = "address:" .. address, workspace = ws, follow = false })) end
    end
  end,
}
