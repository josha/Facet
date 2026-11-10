# Make art without image generation

Use this page when the direction needs a material, a scene, shaped control
surfaces or icons, and no image model is available. A missing image model
changes how the art is made. It does not change the target to flat panels.
When image generation is available, it remains a good source; apply the same
runtime roles and checks below to its output. Use it for illustration that a
script cannot reach, such as a figure or an object in perspective, and draw
flat marks, plates and materials by script. For a cut-out of a dark object,
generate it on white and remove the background by script; a colored
background leaves a fringe. View every cut-out edge at twice its size.

Generated pieces that share one scene must agree with each other. When the
direction has depth, choose one view (for example straight down, or three
quarters from the front) and one light direction, and state both in every
prompt. Give the first accepted piece as a reference when the model takes
one. Ask for each object alone, with no ground and no cast shadow, and draw
the shadows for all the objects with one script, so they fall the same way.
A flat graphic direction has no light and no perspective; it needs only one
outline weight and one palette.

## Choose the cheapest medium that carries the look

1. **Native drawing** for flat graphic directions: gradients, strokes, corners,
   rotation, paths and type. See [native drawing](finish.md#native-drawing).
2. **A script that renders image files** for materials, lighting, shaped
   plates, ornaments and simple illustrated subjects. This page covers it.
3. **`UI.Stage`** for an object that reads best as a lit 3D form.
4. **Existing game art** when the project already has images or models of the
   subject.

Do not use EditableImage or packed pixel data for authored UI art. A dynamic
player drawing canvas can use EditableImage.

## Render files with a script

Write one script that renders every file, so a color or size change is one
edit and one run. Python with Pillow is enough; check that it is installed
before planning around it. Any raster or vector tool on the machine can
replace it.

Techniques that produce a finished surface from a few lines:

- **Supersample.** Draw at three or four times the final size, then downsample
  with a high-quality filter. Shapes and curves get smooth edges.
- **Material.** Start from a base color. Add low-contrast noise, blur it
  lightly and blend it at a low opacity for cloth, paper, stone or brushed
  metal. Stretch the noise along one axis for wood grain or fibre.
- **Light.** Multiply a soft radial falloff over a ground so the centre is
  lit and the corners fall away. Add a thin highlight on the upper edge of a
  raised surface and a darker band on its lower edge.
- **Depth.** Draw a blurred, offset, darker copy under a raised shape. Leave a
  transparent margin for it and account for that margin in `contentInsets`.
- **Edges.** Outline, double rule, stitching (short dashes along an inset
  path), rivets or a bevel. Use one edge language on every surface.
- **Shapes and subjects.** Build icons and simple subjects from primitives:
  ellipses, polygons, arcs and rounded rectangles, with a highlight and a
  shadow shape for volume. Keep a consistent outline weight and light
  direction.
- **Printed lettering.** Lettering that is part of the scenery and never
  changes, such as a painted sign, can be in the image. Every fact, label,
  value and control stays live text.

Give each file one runtime role, because the role decides its geometry.

| Role | Make it as | Bind it as |
| --- | --- | --- |
| Ground backdrop | One opaque image near 1024 pixels wide, focal content centred, quiet where live text will sit | The Screen's [`ground`](finish.md#the-ground): `UI.Image` with `scaleMode = "crop"` |
| Edge piece of the ground | A transparent strip that tiles or stretches along its edge | A layer of the ground's `ZStack`, pinned to that edge |
| Repeating material | A seamless square tile, 128 to 512 pixels | `UI.Image` with `scaleMode = "tile"` and `tileSize`, or theme `chrome` `tile` |
| Stretchable plate, per state | A small transparent image with corners and edge detail inside fixed margins; record the slice rectangle | Theme `assets` and `chrome` `nineSlice` with `contentInsets` |
| Subject or icon | A transparent cutout with a little padding | `UI.Image`, or theme `icons` |
| Piece that carries a live label | A note, a card, a sign or a stamp with a calm area for the label; record its painted rectangle | The `ground` of the stack that holds the label: `UI.Image` with `paintRect` |

A piece that carries a live label, such as a note, a card, a sign or a
stamp, needs two more things. Give the label a calm area of the piece, in a
color that the label contrasts with. Then tell Facet where the paint is.
Record the painted rectangle and the pixel size of the file in the art
module as `{ x0, y0, x1, y1, width, height }`; your render script knows
them, and `Facet.review.paintRect(image)` reads them from the uploaded asset
in Studio. Make the piece the `ground` of the stack that holds the label:
`UI.VStack { ground = UI.Image { image = art.note, scaleMode = "stretch",
paintRect = art.notePaint }, padding = "s", label }`. The art fills the
stack, and the padding starts at the edge of the paint, so the label cannot
sit on the transparent margin or on a soft shadow. Choose the label size
from the size of the piece at each form, so the label stays inside the
shape. Keep such a piece near its drawn proportions: give the stack the
proportions of the art, or draw the piece as a `slice` plate when it must
grow with its text. When its slot has another shape, show more pieces or
change the arrangement; do not stretch one.

Keep files small and few. One plate that stretches serves every button. Draw
state variants (default, pressed, selected, disabled) only where a tint or a
180-degree rotation of the default cannot express the state; see
`Themes.chrome`.

## Spend the detail where the player looks

Rank the art by how long the player looks at each piece. The objects of the
lead come first, and they carry the most detail on the screen.

- **Parts.** Before you draw an object that players know from the real world,
  list the parts that they expect to find on it: its markings, its label, its
  fastenings, its wear. Draw each part, in the standard arrangement that
  players know. An object that has only an outline, a
  fill and one symbol looks like a placeholder.
- **Size.** Render each file at the largest size it has on a desktop, or
  larger. An image that is stretched past its pixels turns soft. Make a
  material a seamless tile, not one strip stretched across the screen.
- **Volume.** Every raised thing has a lit edge, a shaded edge and a shadow
  under it, with one light direction and one camera angle for the whole screen. A prop
  that is drawn from another angle than the objects beside it looks pasted on. A stack or a pile
  shows its side as well as its top.
- **Material.** A surface that is cloth, wood, paper, metal or stone has the
  grain of that material at the size the player sees it. A flat fill reads as
  plastic.
- **Lettering.** Marks that are printed on the place are part of its art.
  Curve, space and weight them as a sign painter would, and let them span the
  surface that they belong to.
- **Outline.** Draw the place with its real outline and edge, as a person
  there sees it. A flat rectangle with a strip along one side reads as a
  mat, not as a place.
- **Truth.** Art that shows a value is built from that value: a pile from the
  real pieces, a gauge at the real level.

## Look before uploading

Open each rendered file and view it. Check it at the size it will have on a
phone as well as at full size. Fix the script and render again until the file
shows the material, the edge and the light that the direction card names. A
file that looks like a flat rectangle will look like one in the game.

View the set together on one sheet as well. The members of a set differ by
their own mark or shape, not only by color. Every object has the same outline
weight, camera angle, light direction, shadow and level of detail as the
lead; a plain box that stands for an object is unfinished, so draw it or
leave it out.

## Upload and bind

Follow [the upload route](asset-upload.md): one request per file, then poll
each operation for its asset ID. Roblox limits an image to 1024 pixels on a
side, so split a wider piece into parts that meet edge to edge. Keep a small art module that maps a semantic
name to its `rbxassetid://` string, its delivered pixel size and its slice
rectangle. Roblox can resize an upload, so read `ImageRectSize` or the loaded
size in Studio (`Facet.review.paintRect(image)` returns it) before trusting
slice coordinates or a painted rectangle from the source file.

Then view the art on real controls at each device size. Check that it loaded,
that a sliced image is whole at its smallest and its largest size (a slice can
cut a shape that crosses its lines),
that live labels fit inside the painted area, and that pressed, selected,
focused and disabled states still read. Keep a flat-color fallback so a
failed load leaves readable controls.
