-- hypr/config.lua — config.json of predmaxim.workspaces: defaults, checks, the active desk set.
local json = require("predmaxim_workspaces.json")
local M = {}

M.PATH = os.getenv("HOME") .. "/.config/predmaxim.workspaces/config.json"
M.PLACES = { single = 1, ["left-right"] = 2, ["top-bottom"] = 2, ["main-left"] = 3, grid = 4 }
local CHOICES = { foreignWindow = { tile = 1, float = 1, next = 1 },
                  collapse = { free = 1, all = 1, off = 1 }, collapseInSession = { free = 1, all = 1, off = 1 } }
M.DEFAULTS = { foreignWindow = "tile", collapse = "free", collapseInSession = "free",
               sequentialLaunch = false, schedule = true }

local function desks(t)
  local out = {}
  for ws, d in pairs(type(t) == "table" and t or {}) do
    if type(d) == "table" and tonumber(ws) then
      local scheme = M.PLACES[d.scheme] and d.scheme or "single"
      local slots = {}
      for i, s in ipairs(type(d.slots) == "table" and d.slots or {}) do
        if i <= M.PLACES[scheme] and type(s) == "table" and type(s.class) == "string" and s.class ~= "" then
          slots[#slots + 1] = { app = s.app, class = s.class }
        end
      end
      out[tostring(ws)] = { scheme = scheme, slots = slots, name = type(d.name) == "table" and d.name or { mode = "number" } }
    end
  end
  return out
end

function M.parse(text)
  local raw, err = json.decode(text)
  if type(raw) ~= "table" then return nil, err or "not an object" end
  local c = {}
  for k, v in pairs(M.DEFAULTS) do
    local r = raw[k]
    if CHOICES[k] then c[k] = CHOICES[k][r] and r or v
    elseif type(r) == type(v) then c[k] = r else c[k] = v end
  end
  c.singleInstance = type(raw.singleInstance) == "table" and raw.singleInstance or {}
  c.workspaces = desks(raw.workspaces)
  c.sessions = {}
  for name, s in pairs(type(raw.sessions) == "table" and raw.sessions or {}) do
    if type(s) == "table" then c.sessions[name] = { workspaces = desks(s.workspaces), schedule = s.schedule } end
  end
  c.activeSession = type(raw.activeSession) == "string" and raw.activeSession or nil
  return c
end

-- The desks in force: the active session's, else the plain ones.
function M.active(c)
  local s = c.activeSession and c.sessions[c.activeSession]
  return s and s.workspaces or c.workspaces
end

local last = M.parse("{}")
function M.load(path)
  local f = io.open(path or M.PATH)
  if not f then last = M.parse("{}"); return last end
  local text = f:read("a"); f:close()
  local c, err = M.parse(text)
  if c then last = c else print("predmaxim.workspaces: config.json: " .. tostring(err) .. " — keeping the last good one") end
  return last
end

return M
