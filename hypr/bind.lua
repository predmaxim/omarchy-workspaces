-- hypr/bind.lua — app → desk rules, a window's place in the scheme, foreign windows.
local config = require("predmaxim_workspaces.config")
local M = {}

local function regex(class) return "^(" .. class:gsub("[%-%.%+%*%?%[%]%(%)%^%$|\\]", "\\%0") .. ")$" end

function M.rules(desks)
  local out = {}
  for ws, d in pairs(desks) do
    for _, s in ipairs(d.slots) do out[#out + 1] = { class = regex(s.class), workspace = ws } end
  end
  return out
end

local LAYOUTS = { ["left-right"] = { layout = "master", orientation = "left" },
                  ["main-left"] = { layout = "master", orientation = "left" },
                  ["top-bottom"] = { layout = "master", orientation = "top" },
                  grid = { layout = "dwindle" } }
function M.layout(scheme) return LAYOUTS[scheme] end

function M.slot(desk, class, taken)
  for i, s in ipairs(desk and desk.slots or {}) do
    if s.class == class and not taken[i] then return i end
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
  if index == 1 then return { "swapwithmaster master" } end
  return {}
end

return M
