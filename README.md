# PvE Stats

In-game RmlUi widget for Beyond All Reason PvE lobby/game stats.

The widget posts the current game context to a `/stats` API and shows representative-team win chance, placement among played games, match evidence, and accomplishment-focused player stats. Its histogram stays visible across accomplishment tabs. The header can minimize the panel or close only the current window; closing does not disable the widget for the next game. It is distributed as a standalone BAR RmlWidget so it can be installed without waiting for a full game release.

## Files

- `gui_pve_stats.lua`
- `gui_pve_stats.rml`
- `gui_pve_stats.rcss`
- `include/pve_stats_rml_model.lua`
- `include/pve_stats_http_client.lua`

## Live Development

For BAR hot reload on Windows, keep the live checkout under a Windows path such as:

```text
C:\Users\a\git\Widgets\rmlwidgets\gui_pve_stats
```

Expose that same checkout to WSL through `/mnt/c/Users/a/git/Widgets/rmlwidgets/gui_pve_stats` when editing or testing from Linux. This avoids making the game load files from `\\wsl$`, which is more fragile for file watching, permissions, and runtime access.

If another repo needs this widget as local context, bind-mount or clone the same Git repo there instead of maintaining a copied tree.
