-- collapse empty workspaces, like GNOME: windows on 1, 3, 5 →
-- 3 becomes 2, 5 becomes 3 (renumbered in place, the layout stays). mode: "all" —
-- every desk, "free" — desks in `fixed` (bindings or an own name) keep their number,
-- "off" — nothing.
local M = {}

function M.plan(workspaces, mode, fixed)
  if mode == "off" then return {} end
  fixed = mode == "free" and fixed or {}
  local last = 0
  for _, w in ipairs(workspaces) do
    if w.id > 0 and w.windows > 0 and w.id > last then last = w.id end
  end
  local ids = {}
  for _, w in ipairs(workspaces) do
    if w.id > 0 and not fixed[w.id] and (w.windows > 0 or w.id < last) then ids[#ids + 1] = w.id end
  end
  table.sort(ids)
  local moves, n = {}, 0
  for _, id in ipairs(ids) do
    repeat n = n + 1 until not fixed[n]
    if id ~= n then moves[#moves + 1] = { id, n } end
  end
  return moves
end

function M.mode(cfg) return cfg.activeSession and cfg.collapseInSession or cfg.collapse end

-- Each monitor's own desks collapse among themselves (Omarchy 4.5: a block of
-- `slots` workspace ids per monitor). The bar learns renumbered workspaces from
-- changeworkspaceid (Omarchy's Workspaces.qml asks Hyprland again).
function M.run(get_cfg, fixed_of, slots)
  local cfg = get_cfg()
  local mode = M.mode(cfg)
  if mode == "off" then return end
  local blocks = {}
  for _, m in ipairs(hl.get_monitors()) do
    if not m.is_mirror then blocks[(o.workspaces.workspace_id(m, 1) - 1) // slots] = true end
  end
  for block in pairs(blocks) do
    local base, list = block * slots, {}
    for _, w in ipairs(hl.get_workspaces()) do
      if w.id > 0 and (w.id - 1) // slots == block then list[#list + 1] = { id = w.id - base, windows = w.windows } end
    end
    for _, m in ipairs(M.plan(list, mode, fixed_of(cfg))) do
      hl.dispatch(hl.dsp.workspace.change_id({ workspace = tostring(base + m[1]), id = base + m[2] }))
    end
  end
end

return M
