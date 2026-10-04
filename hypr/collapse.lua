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

function M.run(get_cfg, fixed_of)
  local cfg = get_cfg()
  local mode = M.mode(cfg)
  local list = {}
  for _, w in ipairs(hl.get_workspaces()) do list[#list + 1] = { id = w.id, windows = w.windows } end
  local moves = M.plan(list, mode, fixed_of(cfg))
  for _, m in ipairs(moves) do hl.dispatch(hl.dsp.workspace.change_id({ workspace = m[1], id = m[2] })) end
  -- The bar (Quickshell 0.3) ignores changeworkspaceid and re-reads workspaces only on configreloaded.
  -- ponytail: drop this reload once Quickshell handles changeworkspaceid.
  if #moves > 0 then hl.exec_cmd("hyprctl reload") end
end

return M
