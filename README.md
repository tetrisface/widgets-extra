# widgets-extra

This repository contains BAR widgets that are intentionally kept out of the community-widget snapshot in this workspace.

## Structure

Each widget lives in its own top-level folder. That keeps their code, resources, tests, and install notes grouped together.

- [`gui_pve_stats/`](./gui_pve_stats)

## Current intent

- Keep experimental, specialized, or non-standard widgets versioned here.
- Maintain widget-specific documentation inside each widget folder.
- Keep root-level files for repository-wide notes only.

## Notes

- If a widget should be shared with `community-widgets`, move it there explicitly and remove it from this repo.
- If another project needs local access to a widget, point it at this repository as a submodule and consume the target folder directly.
