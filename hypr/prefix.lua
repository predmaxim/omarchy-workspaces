-- hypr/prefix.lua — makes require("predmaxim_workspaces.<name>") load <dir>/<name>.lua and
-- drops cached copies. Hyprland starts a fresh Lua state on every `hyprctl reload`, so the
-- cleanup only matters when the file runs twice in one state (the tests).
-- Usage: dofile(<dir>/prefix.lua)(<dir>)
return function(dir)
  for i = #package.searchers, 1, -1 do
    if debug.getinfo(package.searchers[i], "S").source == debug.getinfo(1, "S").source then
      table.remove(package.searchers, i) -- our own searcher from a previous run
    end
  end
  table.insert(package.searchers, 2, function(name)
    local m = name:match("^predmaxim_workspaces%.(.+)$")
    if not m then return nil end
    local f, err = loadfile(dir .. m .. ".lua")
    return f or ("\n\t" .. tostring(err))
  end)
  for k in pairs(package.loaded) do
    if k:match("^predmaxim_workspaces%.") then package.loaded[k] = nil end
  end
end
