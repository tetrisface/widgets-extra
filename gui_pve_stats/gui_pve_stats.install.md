# PvE Stats RmlUi Widget

Shows PvE setting difficulty, match result, wins, and ratings from a `/stats` API.

## Automatic Install

On Windows with BAR installed in the default location, open PowerShell and run:

```pwsh
$n="gui_pve_stats"
$d="$env:LOCALAPPDATA\Programs\Beyond-All-Reason\data\LuaUI\Widgets\$n"
$u="https://raw.githubusercontent.com/tetrisface/widgets-extra/main/gui_pve_stats"
$files = @(
    "$n.lua",
    "$n.rml",
    "$n.rcss",
    "manifest.json",
    "include/request.lua",
    "include/remote.lua",
    "include/fetch.lua",
    "include/display.lua",
    "include/player_stats.lua",
    "include/histogram.lua",
    "include/diagnostics.lua",
    "include/view_model.lua"
)

New-Item -ItemType Directory -Force "$d\include" | Out-Null
foreach ($file in $files) {
    iwr "$u/$file" -OutFile "$d\$file"
}

```

## Manual Install

1. Download `https://github.com/tetrisface/widgets-extra/archive/refs/heads/main.zip`.
2. Extract it.
3. Open `widgets-extra-main/gui_pve_stats`.
4. Move that folder to `%LOCALAPPDATA%\Programs\Beyond-All-Reason\data\LuaUI\Widgets`.
5. Restart BAR or run `/luaui reload`, then enable **PvE Stats RmlUi** in F11.

Expected layout:

```text
LuaUI/
└─ Widgets/
   └─ gui_pve_stats/
      ├─ gui_pve_stats.lua
      ├─ gui_pve_stats.rml
      ├─ gui_pve_stats.rcss
      ├─ manifest.json
      └─ include/
         ├─ request.lua
         ├─ remote.lua
         ├─ fetch.lua
         ├─ display.lua
         ├─ player_stats.lua
         ├─ histogram.lua
         ├─ diagnostics.lua
         └─ view_model.lua
```

## Live Development Install

For hot reload, clone this repo and sync `gui_pve_stats` into your BAR widgets folder:

```pwsh
$repoRoot = "C:\Users\a\git\widgets-extra"
$destination = "$env:LOCALAPPDATA\Programs\Beyond-All-Reason\data\LuaUI\Widgets\gui_pve_stats"

git clone git@github-tetrisface:tetrisface/widgets-extra.git $repoRoot
New-Item -ItemType Directory -Force $destination | Out-Null
Copy-Item "$repoRoot\gui_pve_stats\*" -Destination $destination -Recurse -Force
```

If you keep your live widgets under `C:\Users\a\git\Widgets`, clone there and let your existing symlinks/junctions point BAR at that directory. From WSL, edit through:

```text
/mnt/c/Users/a/git/widgets-extra/gui_pve_stats
```

Prefer this direction over pointing BAR at files stored under `\\wsl$`.

## API Config

The widget currently uses these Spring config options:

- `LuaSocketEnabled` (default `1`, requires `luasocket`)
- `PveStatsAutoFetch` (default `1`)
- `PveStatsEvidenceLog` (default `1`)
- `PveStatsDebugLog` (default `0`)
- `PveStatsLoadingExpectedSeconds` (default `19`)
- `PveStatsShowSpectators` (default `0`)
- `PveStatsMinimized` (default `0`)

The API endpoint is not configurable by Spring settings and is fixed to `POST http://d29i3oohxql6zz.cloudfront.net:80/stats`.
