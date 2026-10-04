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
      -- Places keep their numbers: an empty place (null in JSON) stays a nil hole,
      -- so read slots with `for i = 1, M.PLACES[scheme]`, not ipairs or #.
      local slots, raw = {}, type(d.slots) == "table" and d.slots or {}
      for i = 1, M.PLACES[scheme] do
        local s = raw[i]
        if type(s) == "table" and type(s.class) == "string" and s.class ~= "" then
          slots[i] = { app = s.app, class = s.class }
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
  -- "" is truthy in Lua; an ended session is stored as "".
  c.activeSession = type(raw.activeSession) == "string" and raw.activeSession ~= "" and raw.activeSession or nil
  return c
end

-- The desks in force: the active session's, else the plain ones.
function M.active(c)
  local s = c.activeSession and c.sessions[c.activeSession]
  return s and s.workspaces or c.workspaces
end

-- Hyprland starts a fresh Lua state on every reload, so the last good file and the last
-- reported error are kept on disk.
M.CACHE = (os.getenv("XDG_CACHE_HOME") or os.getenv("HOME") .. "/.cache") .. "/predmaxim.workspaces/"

local function slurp(p)
  local f = io.open(p); if not f then return nil end
  local t = f:read("a"); f:close(); return t
end
local function put(p, text)
  if slurp(p) == text then return end
  local f = io.open(p, "w")
  if not f then os.execute("mkdir -p '" .. p:match("(.*/)") .. "'"); f = io.open(p, "w") end
  if f then f:write(text); f:close() end
end

-- A broken file: log, notify once per distinct error, run on the last good one.
function M.load(path, cache)
  cache = cache or M.CACHE
  local text = slurp(path or M.PATH)
  if not text then return M.parse("{}") end
  local c, err = M.parse(text)
  if c then put(cache .. "last-good.json", text); put(cache .. "error", ""); return c end
  local msg = "config.json: " .. tostring(err) .. " — keeping the last good one"
  print("predmaxim.workspaces: " .. msg)
  if slurp(cache .. "error") ~= msg and hl then
    hl.exec_cmd("omarchy-notification-send -u critical 'Workspaces' '" .. msg:sub(1, 200):gsub("'", "'\\''") .. "'")
  end
  put(cache .. "error", msg)
  return M.parse(slurp(cache .. "last-good.json") or "{}") or M.parse("{}")
end

return M
