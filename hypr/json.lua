-- hypr/json.lua — JSON → Lua tables (Hyprland's Lua has no JSON library).
-- Arrays keep their length with null inside (field n).
local M = {}

function M.decode(text)
  local pos = 1
  local function fail(msg) error({ msg = msg .. " at " .. pos }, 0) end
  local function ws() pos = text:find("[^ \t\r\n]", pos) or #text + 1 end
  local value
  local function str()
    local out, i = {}, pos + 1
    while true do
      local c = text:sub(i, i)
      if c == "" then fail("unexpected end in string") end
      if c == '"' then pos = i + 1; return table.concat(out) end
      if c == "\\" then
        local e = text:sub(i + 1, i + 1)
        local map = { n = "\n", t = "\t", r = "\r", b = "\b", f = "\f", ['"'] = '"', ["\\"] = "\\", ["/"] = "/" }
        if map[e] then out[#out + 1] = map[e]; i = i + 2
        elseif e == "u" then
          out[#out + 1] = utf8.char(tonumber(text:sub(i + 2, i + 5), 16)); i = i + 6
        else fail("bad escape") end
      else out[#out + 1] = c; i = i + 1 end
    end
  end
  function value()
    ws()
    local c = text:sub(pos, pos)
    if c == "" then fail("unexpected end") end
    if c == "{" then
      local t = {}; pos = pos + 1; ws()
      if text:sub(pos, pos) == "}" then pos = pos + 1; return t end
      while true do
        ws(); if text:sub(pos, pos) ~= '"' then fail("expected key") end
        local k = str(); ws()
        if text:sub(pos, pos) ~= ":" then fail("expected :") end
        pos = pos + 1; t[k] = value(); ws()
        local d = text:sub(pos, pos); pos = pos + 1
        if d == "}" then return t end
        if d ~= "," then fail(d == "" and "unexpected end" or "expected , or }") end
      end
    elseif c == "[" then
      local t, n = {}, 0; pos = pos + 1; ws()
      if text:sub(pos, pos) == "]" then pos = pos + 1; return t end
      while true do
        n = n + 1; t[n] = value(); ws()
        local d = text:sub(pos, pos); pos = pos + 1
        if d == "]" then t.n = n; return setmetatable(t, { __len = function() return n end }) end
        if d ~= "," then fail(d == "" and "unexpected end" or "expected , or ]") end
      end
    elseif c == '"' then return str()
    elseif text:find("^true", pos) then pos = pos + 4; return true
    elseif text:find("^false", pos) then pos = pos + 5; return false
    elseif text:find("^null", pos) then pos = pos + 4; return nil
    else
      local num = text:match("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
      if not num or num == "" then fail("unexpected character") end
      pos = pos + #num; return tonumber(num)
    end
  end
  if type(text) ~= "string" or text:match("^%s*$") then return nil, "empty" end
  local ok, res = pcall(value)
  if not ok then return nil, type(res) == "table" and res.msg or tostring(res) end
  return res
end

return M
