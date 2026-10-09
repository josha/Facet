# Facet Lab

An interactive catalog for every Facet control, with device, input, motion,
text-size and theme previews. The control list uses larger text and taller rows.

## Build and run

From the repository root, run `lune run tools/lune/build lab`, then open
`examples/facet-lab/build/Facet-Lab.rbxl` in Roblox Studio and start Play.
The build checks catalog coverage and keeps all generated outputs in
`examples/facet-lab/build/`.

The build also creates `Foundation-Light.rbxm` and `Foundation-Dark.rbxm`
in the same directory. These themes are optional. The Facet runtime
package does not install them; import a standalone model or copy the
`themes/foundation.luau` package when a game chooses to use Foundation.
The standalone entries expose `build(Facet.themes)` for `Facet.app`'s `theme` option.

`lune run tools/check_themes.luau` validates both palettes through the public
theme compiler. `lune run tools/coverage.luau check` checks catalog coverage
against Facet's exported control types.

## Browse controls

The outline groups controls by family and supports search. Select a control
for its playground, options, states, variants and usage examples. Settings
contains the device, input, text, motion and theme previews. Compact layouts
open the control list through Browse and Back.

Choose **Navigation → NavigationSplitView** (or search for it) to resize related
panes and try compact navigation. The File library showcase combines two
splits for Files, Inbox and Linked view. Each file pane has its own folder
history, so opening a folder does not move the other panes.

Choose **Layout → ZoomView** to try pointer-centered zoom and camera capture
when picking up collection items. **Layout → Travel** includes straight and
arc paths, row shuffles, multiple items, and recycled destinations.

Table, VirtualList, and VirtualGrid start with a working **Editing** section.
Rename items, create an item, select several items, reorder them, delete the
selection, and Undo. Enable editing controls permission. Desktop names are
editable immediately; touch and gamepad use Edit/Done. The examples use
CellEditor and the containers' shared selection and editing APIs.

Choose **Lab → Drag and drop demo** (or search for it) to drag a portrait onto
a 3D canvas or a color onto the canvas or block. This demo was moved from
Showcase's File library. The draggable and dropTarget pages also link to it.
The demo includes legal-target feedback, return/completion motion, Undo, Reset,
and keyboard/gamepad destination actions. Touch dragging starts when the
finger moves; a tap offers destination buttons. Short layouts keep space for
the canvas. The camera and objects are restored
or removed when you leave the demo.

The previews use Facet's environment options. Automatic input follows the
selected device: touch for phone and tablet, gamepad for console, and pointer
for desktop. An explicit input choice takes precedence. Open controls update
when these settings change. Overlays use the device frame's live bounds,
including after rotation.

A simulated text preference
changes Facet's layout decisions; the engine's text preference must still be
set in Studio to test native accessibility rendering.

## Studio driver

`workspace.FacetLabAPI` exposes `pages`, `open`, `section`, `top`, `report`,
`configure`, `sweep`, `probe`, `audit`, `themes`, `theme`, `preview`,
`orientation`, `input`, `distance`, `text`, `motion`, `transparency`, `hover`,
`reset` and `status`. Each entry is a BindableFunction.

Source files live in `src/`, optional Foundation palettes and entry modules
in `themes/`, and local captures in the ignored `evidence/` directory.
The project maps Facet and the shared gallery directly from this repository.
