-- Tests for collapse.plan: lua hypr/collapse_test.lua
package.path = arg[0]:match("(.*/)") .. "?.lua;" .. package.path
local collapse = require("collapse")

local failed = 0
local function show(v)
  if type(v) ~= "table" then return tostring(v) end
  local parts = {}
  for _, x in ipairs(v) do parts[#parts + 1] = show(x) end
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

local function ws(t)
  local o = {}
  for _, p in ipairs(t) do
    o[#o + 1] = { id = p[1], windows = p[2] }
  end
  return o
end

local function same(a, b)
  return table.concat((function()
    local r = {}
    for _, m in ipairs(a) do
      r[#r + 1] = m[1] .. ">" .. m[2]
    end
    return r
  end)(), ",") == b
end

-- Tests from the brief
assert(same(collapse.plan(ws({ { 1, 1 }, { 3, 1 }, { 5, 1 } }), "all", {}), "3>2,5>3"))
assert(same(collapse.plan(ws({ { 1, 1 }, { 3, 1 } }), "off", {}), ""))
-- free: 3 is fixed (bound), 5 moves down to 2, 3 stays
assert(same(collapse.plan(ws({ { 1, 1 }, { 3, 1 }, { 5, 1 } }), "free", { [3] = true }), "5>2"))
-- free: a fixed empty desk keeps its number, free ones skip it
assert(same(collapse.plan(ws({ { 1, 1 }, { 4, 1 }, { 6, 1 } }), "free", { [2] = true }), "4>3,6>4"))

-- Old test cases ported with mode "all"
eq(collapse.plan(ws({ { 1, 1 }, { 2, 3 } }), "all", {}), {}, "no gaps: nothing to do")
eq(collapse.plan(ws({ { 1, 1 }, { 3, 1 }, { 5, 2 } }), "all", {}), { { 3, 2 }, { 5, 3 } }, "gaps collapse in order")
eq(collapse.plan(ws({ { 4, 1 } }), "all", {}), { { 4, 1 } }, "lone workspace becomes 1")
eq(collapse.plan(ws({ { 1, 1 }, { 2, 0 }, { 3, 1 } }), "all", {}), {}, "empty workspace between occupied ones is kept (you are on it)")
eq(collapse.plan(ws({ { 1, 1 }, { 2, 1 }, { 7, 0 } }), "all", {}), {}, "empty workspace after the last occupied one is left alone")
eq(collapse.plan(ws({ { 1, 1 }, { 4, 1 }, { 7, 0 } }), "all", {}), { { 4, 2 } }, "empty trailing workspace doesn't block collapsing")
eq(collapse.plan(ws({ { -98, 1 }, { 3, 1 }, { -1337, 1 } }), "all", {}), { { 3, 1 } }, "special and named workspaces are ignored")
eq(collapse.plan(ws({ { 5, 1 }, { 2, 1 } }), "all", {}), { { 2, 1 }, { 5, 2 } }, "input order doesn't matter")

print("collapse ok")

if failed > 0 then
  print(failed .. " failed")
  os.exit(1)
end
