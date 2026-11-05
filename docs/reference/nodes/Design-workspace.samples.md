# Host Design samples and source

Use the [host Design workspace](Design-workspace.md) to preview registered
components with literal props, slots or live inputs.

`bindings(UI, stage)` has type `Facet.DesignStudioSampleBindings`. It returns a
map of input names to `Facet.DesignResolved` values. It runs under each preview's
Compose owner and receives the workspace controls and the selected device profile.
Use `{ slot = function() return UI.Text { text = "Details" } end }` for a slot,
`{ readable = source }` for a readable literal, or `{ value = cell }` to keep a
writable cell's identity. Bindings override `props` for the same input. Build fresh
slot content per call. Compose releases owned resources when the sample changes
or the editor closes. Keep borrowed host state outside the factory.

For example, assume `PreviewPanel` has required `content` and cell `label` inputs:

```luau
local samples: { Facet.DesignStudioSample } = {
    {
        design = "PreviewPanel",
        name = "Ready",
        props = {},
        bindings = function(UI, stage)
            return {
                label = { value = Facet.Compose.cell("Ready") },
                content = { slot = function()
                    return UI.Text { text = stage.name }
                end },
            }
        end,
    },
}
```

Sample selection changes the rendered preview only. It does not write the source
link or add an undo step. `design` and `session.document` identify the authored
Design opened by `edit`; `previews.Sample` identifies the rendered sample, which
can be from another registered Design. Explicit edit commands change the authored
document. To edit another Design, open it with `kit.edit(parent, designName, link)`.

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

To compare packages from one shared base, register each package in `themes`.
This example takes the host's registry and samples in `options`:

```luau
local function openThemes(options: Facet.DesignStudioOptions, parent: Instance)
    local base = Facet.themes.neutralPackage()
    local blue, blueReport = Facet.themes.define({
        base = base,
        style = { themes = {
            { name = "Dark", colors = { accent = { r = 0.3, g = 0.2, b = 0.3 } } },
        } },
    })
    local purple, purpleReport = Facet.themes.define({
        base = base,
        style = { themes = {
            { name = "Dark", colors = { accent = { r = 0.3, g = 0.2, b = 0.6 } } },
        } },
        metrics = { space = { m = 24 } },
    })
    assert(blueReport.ok and purpleReport.ok)
    local kit = Facet.composeDesign({
        registry = options.registry,
        samples = options.samples,
        themes = {
            { name = "Blue", theme = assert(blue) },
            { name = "Purple", theme = assert(purple) },
        },
    })
    local editor = kit.edit(parent, "Emblem")
    local result = editor.execute({ action = "Preview", name = "Theme", choice = "Purple" })
    assert(result.ok, result.problem)
    return editor
end
```

Both entries supply their full tokens, assets, focus rules and metrics. Theme
selection changes the live preview in place and keeps the editor session.
String entries can share the list to select palettes from `theme`.
