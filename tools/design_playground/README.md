# Compose Design playground

The playground is a place that opens the Compose Design editor with the Facet
library in a play session. It uses the same editor and the same
`Facet.composeDesign()` kit as the Studio plugin. Each player keeps one saved
design in a data store.

Build the place:

```sh
lute run tools/facet build playground
```

Open `build/Compose-Design-Playground.rbxl` in Studio and press Play. Publish
the place to keep saved designs; an unpublished place edits without saving.

To edit designs in Studio, build the Compose Design plugin from the pinned
Compose commit (`studio/design/plugin.project.json` in Compose) and click
**Design** in the Compose toolbar. The plugin finds Facet in
`ReplicatedStorage` and opens the selected design module.
