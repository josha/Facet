### Group

<!-- aliases: Group | groupTransparency -->

`UI.Group(spec) -> CanvasGroup` blends its children as one native image.
`groupTransparency` accepts a number or a readable number. `0` is opaque and
`1` is transparent. The returned object's `GroupTransparency` exposes the
current value. Compose owns the binding and the children.

Use a Group when text, images, fills and child focus outlines must dim
together. Put an HStack or VStack inside it to arrange a strip. Options are
`width`, `height`, `maxWidth` and `padding`. Width and height hug by default.
Native CanvasGroup properties and positional children are also accepted.

Transparency does not disable input. Keep `enabled` on controls and use
`Visible` to hide the group. Native child sizes and hit areas remain in use.
Content in an overlay portal is outside the group.

CanvasGroup always clips descendants at its bounds. Leave room for outlines
and shadows. The ancestor LayerCollector must use `ZIndexBehavior.Sibling` for
group compositing. Roblox uses an extra texture whose quality and memory limit
depend on client quality. The group can become blank above that limit. Prefer
a stable size to avoid allocating new textures when the size changes. See the
[Roblox CanvasGroup reference](https://create.roblox.com/docs/reference/engine/classes/CanvasGroup).

The Facet Design library exposes `Group` as a list container and
`groupTransparency` as a number field. Bind a readable numeric input to keep
the host value through import, edit and export.
