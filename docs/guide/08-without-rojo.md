# Installing without Rojo

1. Run `tools/package.sh build` to build the local distributable.
2. In Studio, insert `build/Facet.rbxm` into ReplicatedStorage.
3. Set `Workspace.PlayerScriptsUseInputActionSystem` to true. The native action
   controls need it.
4. Put a LocalScript in StarterPlayerScripts. Follow
   [Getting started](03-getting-started.md).

Keep the full module tree together. Facet contains its pinned Compose snapshot
and the license notice. Do not copy selected private implementation files into
an application.

`Facet.app` mounts a ScreenGui into PlayerGui. To set other ScreenGui
properties, such as the safe areas or the display order, mount your own
ScreenGui with `runtime.mount`. See [Mounting](../reference/api.md#mounting).

```luau
local Facet = require(game.ReplicatedStorage:WaitForChild("Facet"))
local app = Facet.app()
app.mount(function()
    return app.UI.Button { label = "Ready", onActivate = function() print("Ready") end }
end)
script.Destroying:Connect(app.dispose)
```

`app.mount` puts a StyleSheet and a StyleLink in the ScreenGui. The StyleLink
references the sheet and applies the themed paint. Keep game models, remotes
and assets outside the Facet module tree.

## The official Roblox Package

The official Roblox Package asset does not exist until the package metadata
says so. Do not invent an asset id. Do not publish a package from a pull
request. The [package maintainer instructions](../../package/README.md) describe
the local build and status commands and the release-only publish process.
