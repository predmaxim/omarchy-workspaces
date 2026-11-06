-- hypr/bind.lua — app → desk rules, a window's place in the scheme, foreign windows.
local config = require("predmaxim_workspaces.config")
local M = {}

local function regex(class) return "^(" .. class:gsub("[%-%.%+%*%?%[%]%(%)%^%$|\\]", "\\%0") .. ")$" end

-- The scratchpad desk ("scratchpad" in config.json) is Hyprland's special:scratchpad.
M.SCRATCH = "scratchpad"
function M.hypr_ws(key) return key == M.SCRATCH and "special:" .. M.SCRATCH or key end

local function ordered(desks)
  local ids = {}
  for ws in pairs(desks) do if tonumber(ws) then ids[#ids + 1] = tonumber(ws) end end
  table.sort(ids)
  for i, n in ipairs(ids) do ids[i] = tostring(n) end
  if desks[M.SCRATCH] then ids[#ids + 1] = M.SCRATCH end
  return ids
end

-- One rule per class, to its first desk: an app on several desks opens there and
-- window.open moves it on (M.target).
function M.rules(desks)
  local out, seen = {}, {}
  for _, ws in ipairs(ordered(desks)) do
    local d = desks[ws]
    for i = 1, config.PLACES[d.scheme] do
      local s = d.slots[i]
      if s and not seen[s.class] then
        seen[s.class] = true
        out[#out + 1] = { class = regex(s.class), workspace = M.hypr_ws(ws) }
      end
    end
  end
  return out
end

-- The desk for a new window of `class`: the first one with fewer of its windows
-- (counts[ws], the others open) than places for it, else its first desk; nil — no places.
function M.target(desks, class, counts)
  local first
  for _, ws in ipairs(ordered(desks)) do
    local d, places = desks[ws], 0
    for i = 1, config.PLACES[d.scheme] do
      if d.slots[i] and d.slots[i].class == class then places = places + 1 end
    end
    if places > 0 then
      first = first or ws
      if (counts[ws] or 0) < places then return ws end
    end
  end
  return first
end

local LAYOUTS = { ["left-right"] = { layout = "master", orientation = "left" },
                  ["main-left"] = { layout = "master", orientation = "left" },
                  ["top-bottom"] = { layout = "master", orientation = "top" },
                  grid = { layout = "dwindle" }, ["main-right"] = { layout = "dwindle" } }
function M.layout(scheme) return LAYOUTS[scheme] end

function M.slot(desk, class, taken)
  if not desk then return nil end
  for i = 1, config.PLACES[desk.scheme] do
    local s = desk.slots[i]
    if s and s.class == class and not taken[i] then return i end
  end
  return nil
end

function M.foreign(cfg, desks, ws, occupied)
  local d = desks[tostring(ws)]
  if not d or d.scheme == "single" or cfg.foreignWindow == "tile" then return { action = "tile" } end
  if cfg.foreignWindow == "float" then return { action = "float" } end
  local busy = {}
  for _, n in ipairs(occupied) do busy[n] = true end
  for n = 1, 10 do
    if not busy[n] and not desks[tostring(n)] then return { action = "move", workspace = n } end
  end
  return { action = "tile" }
end

-- Layout messages after the window of place `index` opened (Task 0 settled their form).
function M.place_cmds(scheme, index, count)
  if scheme == "single" then return {} end
  if scheme == "grid" then
    if index == 1 then return { "preselect r" } end
    if index == 2 then return { "preselect d" } end
    return {}
  end
  -- Built without moving focus: 2 opens left of 1, 3 right of 2, 4 under 3.
  if scheme == "main-right" then
    return ({ { "preselect l" }, { "preselect r" }, { "preselect d" } })[index] or {}
  end
  if index == 1 then return { "swapwithmaster master" } end
  return {}
end

return M
