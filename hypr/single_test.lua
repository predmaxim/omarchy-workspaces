-- Tests for single.decide/validate: lua hypr/single_test.lua
local dir = arg[0]:match("(.*/)") or "./"; dofile(dir .. "prefix.lua")(dir)
local si = require("predmaxim_workspaces.single")

local failed = 0
local function show(v)
  if type(v) ~= "table" then return tostring(v) end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  local parts = {}
  for _, k in ipairs(keys) do parts[#parts + 1] = tostring(k) .. "=" .. show(v[k]) end
  return "{" .. table.concat(parts, ",") .. "}"
end
local function eq(got, want, what)
  if show(got) == show(want) then
    print("ok   " .. what)
  else
    failed = failed + 1
    print("FAIL " .. what .. "\n     got  " .. show(got) .. "\n     want " .. show(want))
  end
end
local function throws(fn, what)
  local ok = pcall(fn)
  eq(not ok, true, what)
end

local yt = { class = "chrome-youtube.com__-Default", action = "focus" }
local meet = { match = "^chrome%-telemost%.[%w.]*yandex%.ru__j_", action = "ask", name = "встречи Телемоста" }
local rules = { yt, meet }
local function win(address, class, h) return { address = address, class = class, focus_history_id = h } end

eq(si.decide(rules, { address = "0xn", class = "foot" }, { win("0xn", "foot", 0) }),
   nil, "no rule for the class: nothing")

eq(si.decide(rules, { address = "0xn", class = yt.class }, { win("0xn", yt.class, 0) }),
   nil, "first window of the group: nothing")

eq(si.decide(rules, { address = "0xn", class = yt.class },
     { win("0xa", yt.class, 3), win("0xn", yt.class, 0), win("0xf", "foot", 1) }),
   { action = "focus", rule = yt, keep = "0xa", old = { "0xa" } }, "duplicate by class: focus the old one")

eq(si.decide(rules, { address = "0xn", class = "chrome-telemost.yandex.ru__j_99-Default" },
     { win("0xa", "chrome-telemost.yandex.ru__j_12-Default", 2), win("0xn", "chrome-telemost.yandex.ru__j_99-Default", 0) }),
   { action = "ask", rule = meet, keep = "0xa", old = { "0xa" } }, "another meeting matches the same pattern: ask")

eq(si.decide(rules, { address = "0xn", class = "chrome-telemost.360.yandex.ru__j_99-Default" },
     { win("0xa", "chrome-telemost.yandex.ru__j_12-Default", 2), win("0xn", "chrome-telemost.360.yandex.ru__j_99-Default", 0) }),
   { action = "ask", rule = meet, keep = "0xa", old = { "0xa" } }, "a Yandex 360 meeting link is a meeting too: ask")

eq(si.decide(rules, { address = "0xn", class = "chrome-telemost.yandex.ru__j_99-Default" },
     { win("0xc", "chrome-telemost.360.yandex.ru__-Default", 1), win("0xn", "chrome-telemost.yandex.ru__j_99-Default", 0) }),
   nil, "the Telemost chat window is not a meeting: nothing")

eq(si.decide(rules, { address = "0xn", class = "chrome-telemost.360.yandex.ru__-Default" },
     { win("0xa", "chrome-telemost.yandex.ru__j_12-Default", 1), win("0xn", "chrome-telemost.360.yandex.ru__-Default", 0) }),
   nil, "opening the chat window next to a meeting: nothing")

eq(si.decide(rules, { address = "0xn", class = yt.class },
     { win("0xa", yt.class, 5), win("0xb", yt.class, 2), win("0xn", yt.class, 0) }),
   { action = "focus", rule = yt, keep = "0xb", old = { "0xa", "0xb" } }, "several old windows: all in old, keep the last focused")

eq(si.decide(rules, { address = "0xn", class = yt.class },
     { win("0xa", yt.class, -1), win("0xb", yt.class, 4), win("0xn", yt.class, 0) }),
   { action = "focus", rule = yt, keep = "0xb", old = { "0xa", "0xb" } }, "never focused window (-1) is not the one to keep")

eq(si.decide(rules, { address = "0xn", class = yt.class },
     { win("0xa", yt.class, -1), win("0xn", yt.class, 0) }),
   { action = "focus", rule = yt, keep = "0xa", old = { "0xa" } }, "only never focused old windows: keep the first")

local first = { match = "^chrome%-", action = "replace" }
eq(si.decide({ first, yt }, { address = "0xn", class = yt.class }, { win("0xa", yt.class, 1), win("0xn", yt.class, 0) }),
   { action = "replace", rule = first, keep = "0xa", old = { "0xa" } }, "the first matching rule wins")

eq(pcall(si.validate, rules), true, "validate accepts good rules")
throws(function() si.validate({ { action = "focus" } }) end, "validate: neither class nor match")
throws(function() si.validate({ { class = "a", match = "b", action = "focus" } }) end, "validate: both class and match")
throws(function() si.validate({ { class = "a", action = "close" } }) end, "validate: unknown action")
local _, msg = pcall(si.validate, { yt, { class = "a", action = "nope" } })
eq(tostring(msg):find("rule 2", 1, true) ~= nil, true, "validate names the rule number")

-- invalid rule is rejected (setup skips such rules instead of raising)
assert(not pcall(si.validate, { { action = "focus" } }), "rule without class/match is rejected")

eq({ si.usable({ match = "[", action = "focus" }) }, { false, "match is not a valid Lua pattern" }, "usable: malformed pattern")
eq({ si.usable({ match = "%", action = "focus" }) }, { false, "match is not a valid Lua pattern" }, "usable: trailing %")
eq({ si.usable({ class = 5, action = "focus" }) }, { false, "class/match is not a string" }, "usable: non-string class")
eq(select("#", si.usable({ class = "a", action = "focus" })), 1, "usable: good rule")
eq((select(2, si.usable({ class = "a", action = "x" }))):find("rule %d") == nil, true, "usable: reason has no index")

if failed > 0 then print(failed .. " failed"); os.exit(1) end
print("all passed")
