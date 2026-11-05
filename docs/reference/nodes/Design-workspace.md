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
| `theme` | Optional `Facet.ReadOnlyThemePackage`, such as a package from `Facet.themes.define`. It supplies the base metrics, rules and named palette variants. The default is Facet Neutral. |
| `themes` | Optional ordered list of palette names from `theme.style.themes`. With a host package, the default is all its palettes in package order. Without a package, the default is `"Light"`, then `"Dark"`. |
| `textSizes` | Optional ordered list of `"Medium"`, `"Large"`, `"Larger"` and `"Largest"`. The default is all four, in that order. |
| `capture` | Optional `(name, frame: Facet.DesignStudioFrame) -> { string }` callback. The host saves the frame and returns its file paths. |

Lists must be nonempty. Stage ids and preview choices must be unique.
Sample choices use `design/name`; the combined name must be unique.
Sample props must match the registered contract. Omitted props use the
contract's preview defaults. Samples belong to the host, outside Design source.

`bindings(UI, stage)` has type `Facet.DesignStudioSampleBindings`. It returns a
map of input names to `Facet.DesignResolved` values. It runs under each preview's
Compose owner and receives the workspace controls and the selected device profile.
Use `{ slot = function() return UI.Text { text = "Details" } end }` for a slot,
`{ readable = source }` for a readable literal, or `{ value = cell }` to keep a
writable cell's identity. Bindings override `props` for the same input. Build fresh
slot content per call. Compose releases owned resources when the sample changes
or the editor closes. Keep borrowed host state outside the factory.

For example, a sample for a Design with required `content` and cell `label` inputs
can use this factory:

```luau
bindings = function(UI, stage)
    return {
        label = { value = Facet.Compose.cell("Ready") },
        content = { slot = function()
            return UI.Text { text = stage.name }
        end },
    }
end,
```

Call `kit.edit(parent, designName)` with the existing host container and a
registered Design name. It opens that Design's first sample. The workspace
creates one Compose runtime and mounts its editor under `parent`. It creates
no host ScreenGui. The host keeps ownership of `parent`.

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

Sample selection changes the rendered preview only. It does not write the source
link or add an undo step. `design` and `session.document` identify the authored
Design opened by `edit`; `previews.Sample` identifies the rendered sample, which
can be from another registered Design. Explicit edit commands change the authored
document. To edit another Design, open it with `kit.edit(parent, designName, link)`.

Close, its visible control, and `dispose()` release the editor and its runtime
once. After the Close command, Read reports `closed = true` and later edit
commands fail.

For example, assume `registry` supplies `Emblem` and `Bulletin` components with
a string `label` input, and `parent` is the host's existing editor container:

```luau
local function openSample(registry: { [string]: Facet.DesignRegistered }, parent: Instance)
    local samples: { Facet.DesignStudioSample } = {
        { design = "Emblem", name = "Ready", props = { label = "Ready" } },
        { design = "Bulletin", name = "Empty", props = { label = "No entries" } },
    }
    local kit = Facet.composeDesign({ registry = registry, samples = samples })
    local editor = kit.edit(parent, "Emblem")
    local result = editor.execute({ action = "Preview", name = "Sample", choice = "Bulletin/Empty" })
    assert(result.ok, result.problem)
    return editor
end
```

Without options, `Facet.composeDesign()` opens the base Facet library with a
Screen document. It returns the same editor handle. `edit` also accepts
Compose's optional source `link`; the editor owns its subscription and cleanup.
