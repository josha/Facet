---
name: use-facet
description: Design, build and refine Roblox game UI and Studio plugin interfaces with Facet, including touch, pointer and controller use.
---

# Use Facet

**Design the product first, then choose the controls that realize it.**

Facet supplies behavior: input, focus, navigation, adaptive layout and state
paint. The product supplies character through one authored theme and its own
composition. Aim for one build that looks like this product and works on a
phone, a desktop and a television.

## Size the work

| Request | Route |
| --- | --- |
| A small edit to an established interface | Reuse its decisions and check the affected states. Go to [Find the implementation route](#find-the-implementation-route). |
| A new interface or a visual redesign | Steps 1 to 4 below, all within the first delivery. |
| The user supplied a reference image or selected a concept | That image is the target. Read [the target contract](references/game-themes.md#commit-to-the-visual-target) in place of step 1, then do steps 2 to 4. |
| An open game brief, and image generation is available or the user asks to explore concepts | Do step 1 with finished concept art in place of sketches; see [rendered alternatives](references/game-themes.md#resolve-the-whole-composition). Then do steps 2 to 4. |
| A wireframe, a functional spike or a tool in its host's style | Stop at the stated scope. Keep the host's conventions. |

Identify the user's decision, the accepted outcome and the return path.
Preserve the brief, existing behavior, art direction and working routes.

Roblox runs on phones, tablets, desktops and consoles. Unless the brief or the
existing product restricts it, support touch, pointer and gamepad, and both
phone orientations. A Studio plugin supports only its host. Report the sizes
and inputs that you tested; a limited test is not general coverage.

Read this file, [runtime essentials](references/runtime.md) and, for a new
interface, [finish](references/finish.md). Read one route from the table below
when the work reaches it. Everything else is reference to search, not to read
whole.

## 1. Decide the direction

Write this card in the working notes before any code. Keep it to about ten
lines. Each line names something that a player can see, not a mood.

| Line | Decide |
| --- | --- |
| Premise | Where the player is and what they do there, in one concrete sentence taken from the brief. It adds no game systems. |
| Lead | The one subject or scene that owns the first screen, and about how much of the screen it takes. A place needs the things that make it that place: its surface, its markings and its furniture. |
| Ground | What covers the whole screen behind the content: a material, a scene, a color field. |
| Palette | Five to seven colors by role, with values: ground, surface, ink, action, selection, and one or two colors from the world. |
| Type | A display family and a reading family, plus numerals when numbers decide. Choose from [fonts that load](references/finish.md#type). |
| Shape and edge | The corner, the edge and the depth that every surface shares. |
| Controls | What a choice and the main action are made of in this world. |
| Signature | One detail that a player would describe to a friend. |
| Response | What visibly happens when the player commits. |

Then make two checks.

- **Keep the recognizable, replace the reflex.** A player should name the
  genre from a thumbnail, so keep the conventions that carry recognition.
  The other first answers are usually genre defaults. Replace at least two of
  them with a choice that only this premise would produce. Two games in one
  genre must not get the same card.
- **Count the departures.** Mark each line that differs from the neutral
  theme. With fewer than five marks, the card describes the neutral theme
  with a new accent color. Revise it before building.

The card also fits a professional tool, a text-led game or an explicitly
minimal brief. Its answers are quiet there: the lead is the content, the
ground is a plain surface, and the signature can be a type relationship or a
state treatment. Name the product family that the user already knows and keep
its conventions. Polish then comes from [hierarchy, rhythm, density and
states](references/finish.md#quiet-interfaces), not from decoration.

**See the screen before building it.** When the direction is a place, a
material or an illustrated world, draw the first screen as a picture: two or
three whole-screen compositions of the same task and data on one sheet. Use
image generation when it is available. Otherwise a short script that draws
flat shapes, type and color is enough. View the sheet. Choose the composition
where the lead and the world are strongest, and note what to take from the
others. A sketch shows a thin scene or a weak hierarchy in minutes; a build
shows it much later. A quiet tool, a text-led design and an established
direction skip the sketch.

The card and the sketch are internal decisions, not user approval steps.

## 2. Build the first screen as that place

Mount one real task with the authored theme, representative data, live labels
and real controls. Do not build every route with neutral panels and theme them
later.

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
motion are all theme values. [Finish](references/finish.md) maps each line of
the card to the theme field or control that realizes it.

Make the art that the card needs. Native gradients, strokes, paths and type
can carry a graphic direction. A material, a scene or shaped control surfaces
need image files: [make them without image generation](references/art.md)
when no image model is available, then [upload them](references/asset-upload.md)
and verify that they load. Do not use EditableImage or packed pixels for
authored UI art. A missing image model does not reduce the target to flat
panels; it changes how the art is made.

Carry the direction into the parts that the player uses: the choice surfaces,
the labels, the state marks and the commitment. A themed banner above neutral
cards leaves the task unchanged. Keep standard control behavior under custom
paint: one semantic target, live text, and focus that Facet draws.

## 3. Make one build fit every screen

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
`local env = UI.environment()` once and read `use(env.isCompact)`,
`use(env.isShort)` and `use(env.isLandscape)` in property functions. Plan the
same parts for a wide view, a narrow tall view and a short wide view before
writing the first one. `AdaptiveStack`, `NavigationSplitView`, `TabView` and
`Composition` regions change form by themselves; use them before writing a
branch. Read [compact compositions](references/compact-compositions.md) when
the parts cannot fit.

Look at every form. Studio can switch its device preview from a command. Run
this in the Client data model during Play, or in the Edit data model before
Play:

```luau
local simulator = game:GetService("StudioDeviceSimulatorService")
simulator:SetDeviceAsync("iphone_14") -- or "hd_1080", "xbox", "ipad_a16"
simulator:SetOrientationAsync(Enum.ScreenOrientation.Portrait) -- or LandscapeLeft
task.wait(1)
return tostring(workspace.CurrentCamera.ViewportSize)
```

`simulator:GetDeviceListAsync()` lists the device ids. The preview shows the
real safe-area insets and touch controls; a resized frame does not. Capture
the first screen on a desktop, a phone in portrait and the same phone in
landscape before you build more screens. Add a console when the product
supports one. Restore the desktop preview when you finish.

## 4. Look, then repair

View each capture at its real size. A text report does not show the screen.
Check these in order and stop at the first failure.

1. **Fit.** Nothing is clipped, overlapped or unreachable at any size. The
   ground reaches every edge, with no band of the game world beside it. The
   main action is inside the thumb's reach on a phone. Every part of the
   desktop screen is present at every size under the same label: a part can
   move or shrink, but it does not vanish or change its name. List the parts
   and labels of the desktop capture and find each one in the other captures.
   A part stays with its group at every size, and an action that discards
   work does not sit beside the main action. The furniture of the place stays
   where it is when the state changes. On a phone, a row of controls keeps a
   margin of 16 pixels or more at each side.
2. **Lead.** The subject or the content is the largest and clearest thing on
   the screen, at every size. On a desktop its objects and markings span most
   of the width. Play that sits in a centre column under half the width is too
   small: scale the lead from the measured room.
3. **Identity.** With the title hidden, the screen still belongs to this
   product. For an expressive game, these are signs of an unfinished direction:
   a flat neutral ground; one font family at nearly one size; choices that are
   equal rectangles with different labels; a main action that looks like every
   other button; a small subject beside a large empty area. Put the capture
   beside the chosen sketch: the place, the lead and the objects of the
   sketch are all in the capture.
4. **States.** Selected, focused, pressed and disabled paint belong to the
   theme, and selection stays clear when focus moves to a peer. In a still
   capture, a person who has not used the screen can name the selected choice.
5. **Response.** Commit with real input. The response on the card happens, and
   the action stays in place.
6. **Craft.** Crop the capture to each kind of object and view it at twice its
   size. The objects of the lead have the most detail on the screen, with the
   parts that a player expects on the real thing. No image is soft, stretched
   or flat where its material has grain. Nothing is a placeholder: no dash
   for a missing value, no empty outline, no hint glyph that looks like debug
   text. All numerals use one family. Art that shows a value shows the real
   one. A disabled control is drawn in the same family as the enabled one.
   Parts of one group share a baseline, also after an animation ends. A label
   on a piece of art lies inside the painted shape, with a margin, and
   contrasts with the paint behind it. No object is stretched away from its
   drawn proportions. [Art](references/art.md#spend-the-detail-where-the-player-looks)
   has the standard.

For an expressive game, an independent review is the largest gain in finish
that is available after the first build. Your own check of your own screen
misses faults that a fresh viewer sees at once. When you can start a separate
agent, give it only the user's request and the captures of every size. Ask it
to act as a strict art director who has not seen the work: to score identity,
craft, hierarchy and the fit at each size from 1 to 5, and to list every
fault that stops a 5, most important first, each specific enough to act on
without its other notes. Repair the list in order, at the cause, and keep
what works. Capture again and repeat with a new reviewer. Two rounds are
usual. Stop when the list is small polish, and do not ask a reviewer to
approve the result. When you cannot start an agent, tell the user that the
screen has had no independent review.

Repair the two largest gaps at their cause, then capture again. Enlarge the
lead or the type before you add panels; fix the theme before you paint one
control. A quiet tool passes the identity check with a plain ground and one
family; judge its hierarchy, rhythm, density and states.

Run `Facet.review.screen().text` in the Client data model on each changed
screen, at each size that you capture and in each state that has its own
message, such as the empty state and the result. A collision at one size does
not show at another. Fix `empty-screen`, `build-failed`, `runtime-error` and
each `high` finding before building the next screen. `overlapping-text` is
high: two texts collide at this size. `covered-text` names a label that is
under a plate from another part at this size, and `escaped-text` names a
label that runs past its backing or that a clip cuts; repair them unless the
effect is deliberate. `native-text` names labels that were built outside
Facet; rebuild them with `UI.Text`. Treat other findings as prompts to look,
not as verdicts. The review reads rectangles, not pixels: it does not see a
label on the transparent margin of an image, so look at the capture too.

Then build the remaining routes around the working treatment, each with its
own composition. Use the [critique-ui loop](../critique-ui/SKILL.md#the-loop)
when the user asks for a review or a polish pass, or after choosing from
rendered alternatives when a separate reviewer is available.

## Build with Facet, not around it

Build the whole interface from Facet: layout, images, text, state and motion,
as well as controls. A Facet construct adapts to room, input, text scale and
ten-foot viewing, takes the theme, and is visible to `Facet.review`. A native
frame placed by `Position` does none of these, and two of them can overlap
when the room shrinks.

| Native habit | Use |
| --- | --- |
| `Frame` with a `UIListLayout` | `UI.VStack` or `UI.HStack` with `gap`, `padding`, `align` and `distribute` |
| A row that must become a column | `UI.AdaptiveStack`, or `HStack { wrap = true }` for many short items |
| `UIGridLayout` or computed cell positions | `UI.Grid`, or `UI.VirtualGrid` with `minColumnWidth` for a long collection that scrolls |
| Children layered with `AnchorPoint` and `Position` | `UI.ZStack` with `alignH` and `alignV` |
| A block pinned to the bottom or the far side | `UI.Spacer {}` or `UI.fill()` in a bounded stack |
| `ImageLabel` with a computed `Size` | `UI.Image` with `width`, `height` and `aspectRatio` (`"fill"` or pixels, bound to the room when needed), `scaleMode`, `shape` and `tint`; native image properties still apply |
| A separate ScreenGui for a full-screen backdrop | `UI.Screen { ground = UI.Image { ... } }`, or a `UI.ZStack` of images for layers |
| A transparent `ImageButton` or `TextButton` over art | `UI.Button { appearance = "bare", name = ..., face }`: the Button has the size of its face, Facet draws focus and keeps the touch target |
| Objects placed in a scene by coordinates | Layers of a `ZStack`, each a filling stack that aligns its own content; a negative `gap` for overlap; `Rotation` on a face |
| `TextLabel` | `UI.Text` with a `textRole`; `UI.Label` for an icon with a value |
| A count or status pill; a mark on a corner | `UI.Badge`; `UI.badged(host, value)` |
| A plate image behind a group | `surface = "panel"` with theme `chrome.panel` art |
| A thin frame as a rule | `UI.Divider` |
| Pixel tables chosen by screen size | `AdaptiveStack`, `ViewThatFits`, or one `UI.environment()` class |
| `TweenService` | Theme motion with `UI.countUp`, `UI.follow`, `UI.sequence`, `UI.shake`, `Flash` and `Travel` |
| `UserInputService` key checks | An `InputAction` with the Button's `shortcutHint` |

Native Roblox remains correct for what Facet has no construct for: a
`UIPadding` or `UISizeConstraint` child, a `UIGradient` or `UIStroke` on a
shape, an `InputAction` and world content. Native properties on a Facet
construct, such as `Rotation`, `ZIndex` and `ImageTransparency`, are also
correct.

The table changes the construction and never the design. When the Facet build
looks plainer than the sketch, the build is not finished: add the missing
layers with `UI.Image` and `ZStack`. Do not simplify the picture to fit a
control.

**When Facet has no control for the task, make one from Facet.** Do not build
the screen from native parts because one control is missing. Write a
component: a function in the project's own module that takes an options table
and returns one Instance. Give it the contract of a Facet control: a semantic
name, live values that are cells or functions, a change callback, `enabled`,
and a `bare` Button for each target, so that Facet draws focus and takes
touch, pointer and gamepad input. Compose it from stacks, `UI.Image`, `UI.Text` and
Facet controls, with Compose for state and cleanup. Call
`Facet.controls(runtime)` in it, so it uses the app's theme and text scale.
Use `Host` only inside it, and only for the part that no construct makes,
such as a drawing surface or a path. Then use the component in every place
that has the need.

Keep the component outside the Facet package. A Facet update replaces the
package and leaves the component in place. Do not edit or copy the package's
source, and use only the public API in the component. Report the need as a
library gap and name the component as the proposal; see
[components](../../docs/guide/components.md).

Before delivery, search the source for `Host.`, `Instance.new`, `AnchorPoint`
and `TweenService`. Replace each use that the table covers. Report each one
that remains with its reason. A need that Facet cannot meet is a library gap
to report, not a detail to hide.

## Find the implementation route

Use Compose for composition, state and lifetime. Standard control behavior
does not require a standard visual composition.

Look up a control's contract when you are about to use it; everything that you
read stays in context. With a shell, run `lute run tools/facet docs --search TERM`,
or search `docs/reference/nodes` when that command is unavailable. In Studio
with `FacetDocs` installed,
`loadstring(ServerStorage.FacetDocs["search.luau"].Value)()("Sheet detents")`
returns short matching sources; batch queries as `search({ "A", "B" })` and
use `search.read(path)` for a complete contract. Do not guess filenames.

| Task | Read and adapt |
| --- | --- |
| Choose a control or a surface for a task | [Choose an interaction](references/choose.md); [game screens](references/game-screens.md) for navigation and lifetime |
| Decide a game design tradeoff | [Game UI design](references/GAME_UI_DESIGN_GUIDE.md) |
| Define the theme or use image surfaces | [Finish](references/finish.md), then [theme contracts](references/game-themes.md#theme-contracts) |
| Browse records, products or equipment | [Collection](examples/collection.luau) and [patterns](references/patterns.md) |
| Inspect a selected object | [Inspection](examples/inspection.luau) |
| Preview a 3D object or choose its color | Node `Tasks.appearance` |
| Show stats, records, prices or progress | [Information display](references/information-display.md) |
| Act during play, then open brief help | [Exploration](examples/exploration.luau) |
| Fit a task into narrow or short room | [Compact compositions](references/compact-compositions.md) |
| Build a Studio plugin or mount in an existing runtime | [Runtime details](references/runtime-details.md) and the `Mounting` node |
| Work from saved source files with the Facet tooling | [Filesystem workflow](references/FILESYSTEM_WORKFLOW.md) |

Put `table.unpack(rows)` last in a constructor; before other entries Luau keeps
only its first value. In a `Stage` where the player chooses colors, keep
`Ambient` and `LightColor` near white. Use typed constructors and reactive
callbacks. Keep durable selection, drafts and accepted state outside
disposable pages, and give unrelated tasks separate scroll state. Connect
pending, rejection, retry and acceptance to the real operation. If a theme
definition fails, repair the reported errors; do not continue on the neutral
package.

## Work in Studio

Edit persistent source; Play-only changes are not delivered. Split modules by
responsibility. Write a new module whole and patch a revision after reading
the range that changes. Try an unfamiliar API in a small mounted component
before spreading its pattern.

Keep tool output small, because it stays in context. Batch independent reads
and related patches. In Play, drive a route and collect its errors, state and
findings in one call that returns a short report, and wait for an outcome
inside that call. Injected input differs between previews: when a click by
instance path or by coordinate does not register, try the other form, and
confirm the result from state, not from the tool's success. Capture after a
visual change, not after every step.

A mounted surface with no content, or a missing control, is a construction
error to find, not a style to adjust. A control that fails to build shows a red
placeholder with its error while the rest of the screen builds, so collect
every failure from one Play session and fix them together.
`Facet.review.screens()` in the Client opens, reviews and closes each mounted
Sheet and returns build errors and findings; pass `{ Name = presentedCell }`
for other screens. If the command tool cannot require modules, call it from a
temporary client script.

Before delivery, run the main routes from start to finish in a fresh Play
session with real input: acceptance, rejection, cancellation and return. A late
patch can break a route that worked earlier. Report what you tested and at
which sizes. Keep implementation, input testing and visual review distinct;
an untested claim stays unverified. Explain a deliberate choice when a
heuristic disagrees; do not change an appropriate design to clear a warning.

For a Compose Design module, read [the design editing contract](../compose/references/design.md)
first and run `lute run tools/facet design check <module>`.
