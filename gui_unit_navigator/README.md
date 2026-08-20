===== UNIT NAVIGATOR =====

Unit Navigator is an experimental RmlUi selection overlay for navigating recent command-backed unit groups. Hold CapsLock to open the QWE / ASD grid, hover or press grid keys to preview groups, and release CapsLock to commit. Press the focused card's grid key again to enter subgroup mode; the next grid key commits a semantic subgroup. Left-click commits immediately; Escape, right-click, or leaving the configured guard cancels and restores the previous camera.

Activation and traversal keys are remappable in the built-in settings panel. Up to six activation keys can coexist, each using one of two modes:

- **Hold** opens on key-down and commits when that key is released.
- **Press + release** opens after the first tap and remains open; tapping that activation key again commits.

CapsLock is only the initial default because operating systems and keyboard layouts do not all expose its toggle behavior in the same way.

If activation bindings become unusable, restart the widget five times within 20 seconds. Unit Navigator clears only the activation bindings and reopens onboarding; add a new activation key in settings. The rapid-restart history is consumed when recovery triggers, so it cannot repeatedly clear the replacement keys.

--- GROUPING ---

- Recent cards contain authoritative command recipients. Units in the issued selection that did not receive the command are exposed as a selectable Skipped subgroup and are not selected by the card root.
- Formation recipients reported in one dispatch stay grouped even when each unit has a distinct position.
- Pure construction queues compare as unordered multisets of normalized building type, x/z position, facing, and duplicate count.
- Other queues preserve command order. Runtime command tags and timestamps are not part of equivalence.
- Pinned slots are stable. Unpinned cards use strict MRU ordering around those slots.

Pins are match-local. Their population definition can be a manual set, exact unit types, or All army. All army means owned, mobile, combat-capable units. Automatic populations accept include/exclude selections. Split strategy can be semantic queue, strict unit type, or unit type followed by semantic queue.

--- COMMAND EVENT IOC ---

`CommandNotify` is the default human-input admission gate. The observer captures the units selected during that call and accepts subsequent `UnitCommandNotify(unitID, cmdID, params, opts)` and authoritative `UnitCommand` events only when the unit belonged to that captured selection and the command matches. Standalone unit-command events from automation widgets are ignored. The observer snapshots queues two frames after an admitted dispatch and has no dependency on formation or custom-command widgets.

Producers that already have a high-level human-input dispatch boundary may optionally call:

```
WG.UnitNavigator.RecordBatch({
  humanIssued = true,
  batchID = "optional-stable-id",
  semanticKind = "formation",
  selectedUnitIDs = {...},
  recipientUnitIDs = {...},
  commandID = CMD.MOVE,
  paramsByUnit = {[unitID] = {x, y, z}},
})
```

`humanIssued = true` is an explicit trust assertion by the adapter, not an inference from the resulting unit commands. Only the supplied, currently owned recipient units are admitted; queue changes do not expand a producer batch. Automation widgets must not call this seam. Producers remain optional and should use it only when a custom human command cannot pass through the ordinary `CommandNotify` path.

--- CURRENT VERTICAL-SLICE LIMIT ---

Each card uses the live minimap texture, current/other-unit markers, queued destination rings, and approximate build-footprint squares as its tactical signal. RmlUi does not provide six independent world cameras, so true cropped perspective renders and precise footprint geometry are deliberately behind the future renderer seam. Camera preview itself is live and centers on the current group.
