# Host Design workspace

Use `Facet.composeDesign(options)` to open registered components in Facet's
Compose Design workspace. Supply the `Facet.DesignRegistered` entries that
`Facet.DesignContext.designs` accepts. Names must be distinct from Facet kinds.

`Facet.DesignStudioOptions` has these fields:

| Field | Contract |
| --- | --- |
| `registry` | Map from Design name to `Facet.DesignRegistered`. |
| `samples` | Ordered list of `Facet.DesignStudioSample`: `{ design, name, props, bindings? }`. `props` maps contract fields to Design literals. Each registered Design needs at least one sample. |
| `stages` | Optional ordered list of `Facet.DesignStudioStage` device profiles. The default is Compose's device list. Profiles include size, insets, input mode and text scale. |
| `resolution` | Optional `{ X, Y }` with finite positive pixel dimensions. It opens one canvas at that logical resolution. Supply `resolution` or `stages`. |
| `theme` | Optional base `Facet.ReadOnlyThemePackage`. The default is Facet Neutral. |
| `themes` | Optional ordered list of base palette names or `Facet.DesignStudioTheme` entries: `{ name, theme }`. Entries register full packages and use their default palette. The default list is all base palettes, or `"Light"`, then `"Dark"` without a host package. |
| `textSizes` | Optional ordered list of `"Medium"`, `"Large"`, `"Larger"` and `"Largest"`. The default is all four, in that order. |
| `capture` | Optional `(name, frame: Facet.DesignStudioFrame) -> { string }` callback. The host saves the frame and returns its file paths. |

Lists must be nonempty. Stage ids and preview choices must be unique.
Theme names must be nonempty. Unknown names fail with a clear error.
Sample choices use `design/name`; the combined name must be unique.
Sample props must match the registered contract. Omitted props use the
contract's preview defaults. Samples belong to the host, outside Design source.

See [samples and themes](Design-workspace.samples.md) for examples. Sample
selection preserves authored source. Theme selection updates the mounted
StyleSheet and control theme. It preserves instances, source and undo history.
Explicit edit commands change the authored document.

Call `kit.edit(parent, designName)` with the existing host container and a
registered Design name. It opens that Design's first sample. The workspace
creates one Compose runtime and mounts its editor under `parent`. It creates
no host ScreenGui. The host keeps ownership of `parent`.

The kit has type `Facet.DesignStudioEditorKit`. Code that accepts any kit uses
`Facet.DesignStudioKit`. A kit from the Compose design editor also has that type.

The returned `Facet.DesignStudioEditor` is Compose's editor handle. Use its
`execute` and `canvas` APIs. These commands use the same actions as the visible
controls:

| Task | Command |
| --- | --- |
| Read selections, available choices and errors | `{ action = "Read" }` |
| Open another Design and sample | `{ action = "Preview", name = "Sample", choice = "Emblem/Ready" }` |
| Select a stage | `{ action = "Device", id = "phone-portrait" }` |
| Select a theme | `{ action = "Preview", name = "Theme", choice = "Dark" }` |
| Select a text size | `{ action = "Preview", name = "Text size", choice = "Largest" }` |
| Capture the selected frame | `{ action = "Capture", name = "EmblemReady" }` |
| Close the workspace | `{ action = "Close" }` |

`Facet.DesignStudioResult` is Compose's structured command result. Check `ok`
and `problem`. `design`, `device` and `previews` report the current selections.
`devices` and `previewChoices` list the available choices. Capture returns the
host's paths in `files`. Without a capture callback, Capture reports a problem.
`canvas.current()` returns the selected frame; `canvas.frames()` returns the
frames built so far.

Close, its visible control, and `dispose()` release the editor and its runtime
once. After the Close command, Read reports `closed = true` and later edit
commands fail.

Without options, `Facet.composeDesign()` opens the base Facet library with a
Screen document. It returns the same editor handle. `edit` also accepts
Compose's optional source `link`; the editor owns its subscription and cleanup.
