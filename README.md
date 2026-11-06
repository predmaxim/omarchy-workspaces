# Workspaces

Workspaces with app bindings, names and sessions.

![Workspaces](preview.png)

## Monitors

Omarchy 4.5 gives every monitor desks 1–10 of its own (a block of ten workspace
ids per monitor). A desk in a session or a binding ("Firefox on desk 2") is desk 2
of the focused monitor, as `Super + 2` is: `hypr/init.lua` turns desks into
workspace ids with Omarchy's `o.workspaces.workspace_id`, and re-sends its named
window rules when the focus moves to another monitor. Collapsing renumbers each
monitor's own desks. A session switch, a launch or a capture works with the windows
on the focused monitor's desks; windows on another monitor stay where they are.

## Desks on the bar

The desk row is Omarchy's own `Workspaces.qml` with `desks.patch` on top (names,
desks with bindings, right click for the settings), built into `Desks.qml` by
`./sync-desks`. Run it after installing and after every Omarchy update (my
`keep-custom-widgets.sh` hook does), so the row follows Omarchy. If the patch no
longer fits, `sync-desks` removes `Desks.qml` and the bar shows Omarchy's row as it
is until `desks.patch` is updated: edit a fresh `Desks.qml` and
`diff -u --label Workspaces.qml --label Desks.qml "$OMARCHY_PATH/shell/plugins/bar/widgets/Workspaces.qml" Desks.qml > desks.patch`.
The running bar loads a new `Desks.qml` after `omarchy restart shell`.

## Colours

Status colours (red, orange) are fixed rather than the theme's, whose red or
yellow can be any colour: `FixedColors.qml` reads them from
`~/.config/omarchy/predmaxim/palette.json` (`{"red": "#e5534b", ...}`) and
falls back to the theme's alert colour without that file.
