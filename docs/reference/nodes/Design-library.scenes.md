# Design native scene documents

Set `context.space = "3d"` for a scene. The library selects Compose Design's
3D stage, uses Model as its container kind and emits an `Instance` return
type. The default space is `"2d"`, with a `GuiObject` return type.

With `context.host`, native `Model`, `Part` and `PointLight` are in the
`Roblox` category. Model and Part take a list of children. PointLight takes
no children. Facet adapts the child modes and field metadata from Compose
Design's Roblox 3D library. These kinds use native property names and emit
native `Host` constructors.

Part has `CFrame`, `Size`, `Color`, `Material`, `Transparency`, `Anchored`
and `CanCollide`. PointLight has `Brightness`, `Range` and `Color`.

A `CFrame` literal is a list of zero, three, seven or twelve numbers for
`CFrame.new`. `Size` is a list of three numbers for `Vector3.new`. A color
is a hex string, such as `"#334455"`. Material is an item name, such as
`"WoodPlanks"`, emitted as `Enum.Material.WoodPlanks`.

Numeric datatype components can read required numeric inputs. Readable
inputs update the native property through Compose. Put a PointLight under
a Part so the native light has a world position.

Use the same library to emit, parse, render and edit a scene. Pass
`context.types` when the host uses an engine double. The game's runtime
supplies the native constructors through `context.host`.

See [Design library](Design-library.md) for the library context and document
operations.
