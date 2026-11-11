# Build a screen as a place

Read this page before you build a screen whose [direction](../SKILL.md#1-decide-the-direction)
is a place, a material or an illustrated world. It shows how the layers of
such a screen are made from Facet, how each layer scales, and where its art
comes from. A quiet tool or a text-led design does not need it; use
[quiet interfaces](finish.md#quiet-interfaces).

## The layers

Build the screen in layers.

1. **Ground.** It reaches every edge of the glass on every device, including
   the bands beside a phone's notch. `UI.Screen { ground = ... }` does this for
   art. A flat neutral fill is correct only when the card says so.
2. **Lead.** The subject at the size on the card. It grows and shrinks with the
   room. Its objects are the largest things on the screen, larger than any
   message panel, and its markings span the room.
3. **Controls.** Real Facet controls in the theme's materials, placed where the
   input reaches them. They keep their target sizes. In a place, they sit on
   its furniture, such as a rail, a counter or a tray, and not on a bar that
   floats over the scene.
4. **Type.** The display family at a confident size for the line that leads.
   Supporting facts stay smaller and quieter.
5. **Messages.** Each state's message (a prompt, a result, an error) has a
   reserved place in the composition. It does not cover the lead or the
   markings that make the place.

Compose the layers with Facet, and keep the picture. The build shows the same
place and the same objects as the chosen sketch. Facet changes how the picture
is constructed, not what it shows: a wall of tools stays a wall of tools. It
does not become a grid of cards because a Card is the nearest control.

```luau
local env = UI.environment()

-- An object in the scene is one Button. Its face is the object.
local function piece(index: number)
    return UI.Button("Piece" .. index) {
        appearance = "bare", -- no plate, padding or minimum size: the face is the Button
        name = names[index],
        selected = function(use) return use(chosen) == index end,
        onActivate = function() chosen:set(index) end,
        UI.ZStack "Face" {
            alignH = "center", alignV = "end",
            Rotation = tilt[index], -- tilt the face; a stack keeps its children upright
            UI.Image {
                image = art.piece[index], aspectRatio = 5 / 7,
                width = function(use) return if use(env.isCompact) or use(env.isShort) then 72 else 150 end,
            },
            UI.Image { -- the selected mark belongs to the object
                image = art.mark, width = 36, height = 36,
                ImageTransparency = function(use) return if use(chosen) == index then 0 else 1 end,
            },
            UI.Text { text = labels[index], textSize = "title" },
        },
    }
end

UI.Screen "Root" {
    -- The place. Art reaches every edge of the glass; the content stays safe.
    ground = UI.ZStack "Place" {
        alignV = "end",
        UI.Image { image = art.backdrop, scaleMode = "crop", width = "fill", height = "fill" },
        UI.Image { image = art.foreground, scaleMode = "crop", width = "fill", height = 120 },
    },
    UI.HStack "Header" { width = "fill", title, UI.Spacer {}, readout },
    -- The lead. One region takes the free room and holds the layers.
    UI.ZStack "Scene" {
        UI.fill(), width = "fill", alignH = "center", alignV = "center",
        UI.Image { image = art.subject, scaleMode = "fit", height = "fill", aspectRatio = 1 },
        UI.VStack { width = "fill", height = "fill", align = "end", distribute = "end", sign }, -- a corner
        UI.HStack "Row" { gap = -30, piece(1), piece(2), piece(3) }, -- a negative gap overlaps
    },
    UI.HStack "Actions" { width = "fill", gap = "m", distribute = "center", action },
}
```

The names, sizes and arrangement above are placeholders. They show mechanics,
not a layout to copy: a `ground` that reaches the glass; a `ZStack` region
whose layers can each be a filling stack that aligns its own content; `width`,
`height` and `aspectRatio` on `UI.Image`, bound to the room; a negative `gap`
for overlap; and a `bare` Button whose face is the object. Compose your own picture
from them. The layers of a `ZStack` do not make room for each other. Keep the
`ZStack` for parts that are meant to overlap, and put parts that must not
cover each other, such as two groups with a message between them, in one
stack or `AdaptiveStack`. An action with a shaped face is the same `bare` Button with a
sliced image behind its label.

Put the character in the theme, so every control inherits it. The palette,
type roles, radii, strokes, gradients, shadows, focus look, control art and
motion are all theme values. [Finish](finish.md) maps each line of
the card to the theme field or control that realizes it.

Make the art that the card needs. Native gradients, strokes, paths and type
can carry a graphic direction. A material, a scene or shaped control surfaces
need image files: [make them without image generation](art.md)
when no image model is available, then [upload them](asset-upload.md)
and verify that they load. Do not use EditableImage or packed pixels for
authored UI art. A missing image model does not reduce the target to flat
panels; it changes how the art is made.

Carry the direction into the parts that the player uses: the choice surfaces,
the labels, the state marks and the commitment. A themed banner above neutral
cards leaves the task unchanged. Keep standard control behavior under custom
paint: one semantic target, live text, and focus that Facet draws.

## Scale each layer by its own rule

Each layer scales by its own rule. The ground covers the viewport and crops.
The lead fits its region and keeps its aspect ratio. Controls and text keep
their sizes and reflow. On a wide screen the lead takes most of the free room:
bind the size of its objects to the room, so a desktop does not show
phone-size objects in an empty field. Text that is part of a scene object,
such as the writing on a note, grows with the object. On a short screen, keep
the pieces that identify the place and drop repetition. On a short wide
screen the height is the scarce side: the lead takes the full height and the
other parts sit beside it, not above or below it.

A row of scene objects that scrolls is clipped at its own edge, and a clip
inside the picture reads as a seam. Run a scrolling row to the edge of the
screen, or make the objects smaller until the set fits. One fixed canvas under a `UIScale` does none of these:
it shrinks targets and text on a phone and strands the art on a wide screen.

Choose the arrangement from the room, not from a device name. Call
[Compact compositions](compact-compositions.md) covers the case where the
parts cannot fit.
