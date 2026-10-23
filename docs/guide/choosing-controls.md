# Choosing controls

Choose behavior from the player's task, then read that control's API node.
For design principles and tradeoffs, use the
[game UI design guide](../../skills/use-facet/references/GAME_UI_DESIGN_GUIDE.md).

| Need | Control |
| --- | --- |
| Arrange gameplay groups by importance | Composition and Region. |
| Read sections, a compact row, or layered content | VStack, HStack or ZStack. |
| Browse visual objects or descriptions | VirtualGrid or VirtualList. |
| Compare common attributes or a real hierarchy | Table or Outline. |
| Do one action | Button. |
| Do a primary action with alternatives | SplitButton. |
| Choose a known value or independent boolean | Picker or Toggle. |
| Edit text, a number, or a bounded range | TextInput, NumberInput or Slider. |
| Adjust in exact increments | Stepper. |
| Navigate peer destinations or deeper detail | TabView or NavigationStack. |
| Browse beside selected detail | NavigationSplitView. |
| Ask for a brief confirmation | Alert. |
| Own a bounded interruption | Dialog or Sheet. |
| Explain something at its source | Popover or Callout. |
| Expand optional facts in the flow | DisclosureGroup. |
| Expose secondary commands | Menu or RadialMenu. |
| Show progress, time or acknowledgement | ProgressView, Timer or Toast. |
| Inspect a 3D object | Stage. |
| Preserve a spatial map | ZoomView and Path. |

Use the [task map](../reference/nodes/Map.md) for implementation recipes.
For a known control, read its card and props with
`lute run tools/facet docs <Control>.card` and `<Control>.props`, or read
the installed StringValues through Studio Model Context Protocol (MCP).
Use `Icons.names` for glyphs.

Keep one owned tree. A page, panel or overlay belongs inside the existing
mount; choosing another control is not a reason to create another app.

## Interactive collections

Keep stable keys and durable row state in the model. The render callback receives
a readable row; read it with `use` in property functions. Recycled rows must not
own lasting selection, favorites or drafts. Bound the viewport and use the
collection's measurement and focus contracts rather than a second row manager.
