-- Single-instance windows: an app with a rule doesn't keep a second window.
--
-- Rules come from cfg.singleInstance (config.json), via init.lua:
--   single.setup(function() return cfg.singleInstance end)
-- Example list:
--   { class = "chrome-youtube.com__-Default", action = "focus" },
--   { match = "^chrome%-telemost%.[%w.]*yandex%.ru__j_", action = "ask", name = "встречи Телемоста" },
-- class is the exact window class; match is a Lua pattern (escape - and . with %).
-- Every window matching the same rule is the same app; the first matching rule wins.
--   focus:   close the new window, focus the old one. The handler runs inside Hyprland
--            before the frame is drawn, so the new window never shows.
--   ask:     keep the new window and ask (single-instance-ask) whether to close the old ones.
--   replace: close the old windows.

local M = {}

local actions = { focus = true, ask = true, replace = true }

function M.validate(rules)
  for i, rule in ipairs(rules) do
    if (rule.class == nil) == (rule.match == nil) then
      error(("single: rule %d needs exactly one of class or match"):format(i), 2)
    end
    if not actions[rule.action] then
      error(("single: rule %d has unknown action %q"):format(i, tostring(rule.action)), 2)
    end
  end
end

local function matches(rule, class)
  if rule.class then
    return class == rule.class
  end
  return class:find(rule.match) ~= nil
end

-- What to do with a new window: nil, or the action with the old windows of its group
-- (keep is the one focused last; focus_history_id 0 is the current focus, -1 never focused).
function M.decide(rules, new, windows)
  local rule
  for _, r in ipairs(rules) do
    if matches(r, new.class) then
      rule = r
      break
    end
  end
  if not rule then
    return nil
  end

  local old, keep, best = {}, nil, math.huge
  for _, w in ipairs(windows) do
    if w.address ~= new.address and matches(rule, w.class) then
      old[#old + 1] = w.address
      if w.focus_history_id >= 0 and w.focus_history_id < best then
        keep, best = w.address, w.focus_history_id
      end
    end
  end
  if #old == 0 then
    return nil
  end
  return { action = rule.action, rule = rule, keep = keep or old[1], old = old }
end

local function close(address)
  hl.dispatch(hl.dsp.window.close({ window = "address:" .. address }))
end

local function focus(address)
  hl.dispatch(hl.dsp.focus({ window = "address:" .. address }))
end

-- get_rules() is called on every window.open, so config edits apply without a reload.
-- Invalid rules are logged and skipped; nothing here raises into Hyprland.
-- Is the rule safe to run in the handler? Returns true, or false and the reason.
function M.usable(rule)
  if type(rule) ~= "table" then
    return false, "rule is not a table"
  end
  local ok, err = pcall(M.validate, { rule })
  if not ok then
    return false, (tostring(err):gsub("^.-rule %d+ ", ""))
  end
  local field = rule.class ~= nil and rule.class or rule.match
  if type(field) ~= "string" then
    return false, "class/match is not a string"
  end
  if rule.match and not pcall(string.find, "", rule.match) then
    return false, "match is not a valid Lua pattern"
  end
  return true
end

local function valid_rules(get_rules)
  local ok, rules = pcall(get_rules)
  if not ok or type(rules) ~= "table" then
    print("single: cannot read rules: " .. tostring(ok and "not a list" or rules))
    return {}
  end
  local good = {}
  for i, rule in ipairs(rules) do
    local usable, reason = M.usable(rule)
    if usable then
      good[#good + 1] = rule
    else
      print(("single: skipping rule %d: %s"):format(i, reason))
    end
  end
  return good
end

function M.setup(get_rules)
  return hl.on("window.open", function(w)
    if not w then
      return
    end
    local rules = valid_rules(get_rules)
    local windows = {}
    for _, x in ipairs(hl.get_windows()) do
      windows[#windows + 1] = { address = x.address, class = x.class, focus_history_id = x.focus_history_id }
    end
    local d = M.decide(rules, { address = w.address, class = w.class }, windows)
    if not d then
      return
    end
    if d.action == "focus" then
      hl.dispatch(hl.dsp.window.move({ window = "address:" .. w.address, workspace = "special:single-instance", follow = false }))
      close(w.address)
      focus(d.keep)
    elseif d.action == "ask" then
      focus(w.address)
      hl.exec_cmd(table.concat({
        o.shell_quote(os.getenv("HOME") .. "/.local/bin/single-instance-ask"),
        o.shell_quote(d.rule.name or w.class),
        w.address,
        d.keep,
        table.concat(d.old, " "),
      }, " "))
    else
      for _, address in ipairs(d.old) do
        close(address)
      end
    end
  end)
end

return M
