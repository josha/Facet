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
| A new interface or a visual redesign | Steps 1 to 5 below. Finish steps 1 to 4 on one screen before you build a second screen. |
| The user supplied a reference image or selected a concept | That image is the target. Read [the target contract](references/game-themes.md#commit-to-the-visual-target) in place of step 1, then do steps 2 to 5. |
| An open game brief, and image generation is available or the user asks to explore concepts | Do step 1 with finished concept art as the concept; see [rendered alternatives](references/game-themes.md#resolve-the-whole-composition). Then do steps 2 to 5. |
| A wireframe, a functional spike or a tool in its host's style | Stop at the stated scope. Keep the host's conventions. |

Identify the user's decision, the accepted outcome and the return path.
Preserve the brief, existing behavior, art direction and working routes.

Roblox runs on phones, tablets, desktops and consoles. Unless the brief or the
existing product restricts it, support touch, pointer and gamepad, and both
phone orientations. A Studio plugin supports only its host. Report the sizes
and inputs that you tested; a limited test is not general coverage.

This file is the workflow. Read [runtime essentials](references/runtime.md)
before the first code. Read each other page at the step that names it, and
search for a section before you read a whole page. Everything that you read
stays in context for the rest of the work.

The first screen settles the theme, the parts and the fit, and every later
screen copies them. A fault that stays in the first screen is repeated in
each one. Steps 1 to 4 are one screen of work, not a polish pass for the end,
and a theme definition alone does not complete them. In a product with many
screens, the number of screens that work is easy to count and the finish of
the first one is not. [Step 2](#know-when-it-is-done) gives it three tests
that you can count.

## 1. Decide the direction

Write this card before any other code, as a comment at the head of the
module that defines the theme. It stays in the source there, and you meet it
at every edit. Keep it to about ten lines. Each line names something that a
player can see, not a mood.

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

### Make the concept before the build

When the direction is a place, a material or an illustrated world, the first
picture of the work is a concept of the first screen. It comes before the
world is detailed, before the game logic and before any second surface. The
card is only words, and a build shows a weak composition after the routes
exist, when it costs most to change.

Make the concept with the best means that you have. Look at your tool list
before you say that a means is missing.

- **An image tool.** Generate two or three whole-screen compositions of the
  same task and data on one sheet, in the palette and the type of the card.
- **A drawing script.** Draw the same compositions as flat shapes, type and
  color.
- **The engine alone.** Block the screen in. Mount the ground, the lead at
  its size and the main action with fixed sample data, in the palette and
  the type of the card, and capture it. It has no game logic and no second
  surface.

View the concept. Change the composition until the lead and the world are
strong, then say in one message which composition you chose and what you
changed. Keep it: [step 2](#know-when-it-is-done) puts it beside the first
screen that you build. A quiet tool, a text-led design and an established
direction skip the concept.

The card and the concept are internal decisions, not user approval steps.

## 2. Build the first screen

Mount one real task with the authored theme, representative data, live labels
and real controls. Do not build every route with neutral panels and theme them
later.

**Choose the screen.** Take the screen that the player sees most. When play
continues behind the interface, the world is the ground and the lead, and the
first screen is the view of play with its HUD. A sheet that opens over play
does not stand in for it. A product that also has destinations that replace
play, such as a shop or an editor, has a second kind of ground. Finish one
such destination in the same way, after the view of play, before you build
the others.

**Give it an owner.** A surface that opens and closes needs a Facet presenter.
One screen with no navigation needs only `UI.Screen`.

| The player | Owner | Start from |
| --- | --- | --- |
| Watches or acts while play continues | `Composition` with `Region`s | Node `Tasks.hud` |
| Enters a destination that replaces play | A `NavigationStack` destination that holds a `Screen` | Node `Tasks.pages` |
| Completes a short task over play | `Sheet` or `Dialog` | Nodes `Tasks.sheet` and `Tasks.confirm` |
| Switches between peer tasks, or goes deeper and returns | `TabView`; a `NavigationStack` inside the surface | [Game screens](references/game-screens.md) |

The owner moves the selection to the first usable control when the surface
opens, and it skips disabled and hidden controls. It returns the selection to
the opener when the surface closes, and it routes Back and gamepad B. In an
app made with `Facet.app({ suspendGameplay = true })` it also turns off the
game's input and the touch controls while the surface is open. A cell that swaps one `Screen` for
another through `C.show` or `C.switch` is not an owner: the selection is not
moved in or returned, Back has no route and play is not suspended. Do not
repair that with a search through the descendants for a button to select:
the search finds disabled and covered controls. Present the surface through
its owner. Set `GuiService.SelectedObject` yourself only
on a named control whose state you know; [runtime essentials](references/runtime.md#input)
has the case. The owner decides behavior, not appearance: its node shows a
structure, and the composition stays yours.

**Build the shared parts on this screen.** In a product with many screens, a
few functions of your own draw most of them: the one that makes an action, a
record, a section and the body of a page. Every screen gets what those
return and little else. They are the product's design system, and a plain
helper makes every screen plain. Write them as the project's components and
finish them here, before a second screen calls them.

- **The theme.** It has an edge and a depth as well as colors and type. A
  definition that sets only colors, fonts and radii is the neutral theme in
  new colors: every plate stays a flat fill.
  [Finish](references/finish.md#edge-and-depth) has the levers.
- **A record.** One item with its visual, its name, the value that decides
  and its state, in a full form and a short form.
- **The actions.** The main action is the strongest thing in its column, in
  `emphasis` and at the column's width when it stands alone. The lesser
  actions are quieter.
- **The body of a page.** It uses the width of its surface: a bounded
  column, a `Grid` whose column count follows the room, or two panes. A
  stack that hugs one corner of a large surface is not a body.
- **The text.** `wrap = true` is for a sentence. A name, a value, a label
  and a heading are one line. A helper that wraps every text lets a value
  break in the middle when its part is narrow.

**Build it in layers.**

1. **Ground.** It reaches every edge of the glass on every device. A flat
   neutral fill is correct only when the card says so.
2. **Lead.** The subject at the size on the card, scaled from the room. Its
   objects are the largest things on the screen.
3. **Controls.** Real Facet controls in the theme's materials, placed where the
   input reaches them. In a place, they sit on its furniture, such as a rail,
   a counter or a tray, and not on a bar that floats over the scene.
4. **Type.** The display family at a confident size for the line that leads.
   Supporting facts stay smaller and quieter.
5. **Messages.** Each state's message (a prompt, a result, an error) has a
   reserved place in the composition. It does not cover the lead.

For a place, a material or an illustrated world, read
[build a screen as a place](references/place.md) before you write the screen.
It has the construction: a ground that reaches the glass, a scene region made
of layers, objects that are Buttons, and art without an image model. The
build shows the same place and the same objects as the chosen concept. Facet
changes how the picture is constructed, not what it shows: a wall of tools
stays a wall of tools. It does not become a grid of cards because a Card is
the nearest control. When the build looks plainer than the concept, it is
not finished.

Put the character in the theme, so every control inherits it. Read
[finish](references/finish.md) when you define the theme: it maps each line
of the card to the theme field or control that realizes it. Carry the
direction into the parts that the player uses: the choice surfaces, the
labels, the state marks and the commitment. A themed banner above neutral
cards leaves the task unchanged.

### Know when it is done

The first screen is done when three tests pass on one revision. Do not build
a second screen before they do.

1. **The card.** Put the card and the concept beside the desktop capture
   and mark each line of the card present or absent: the ground, the lead at
   its share of the screen, the palette roles, the two type families, the
   shared edge, the material of the controls, the signature and the
   response. An absent line is work to do. Do not remove it from the card to
   pass. A quiet interface marks the same lines with its quiet answers.
2. **The forms.** That revision is captured on a desktop, a phone in
   portrait and the same phone in landscape, as
   [step 3](#3-make-one-build-fit-every-screen) describes, and nothing
   overlaps or is cut in any of them.
3. **The review.** `Facet.review.screen().text` at each of those sizes has
   no `high` finding, and each `medium` finding is repaired or has a reason
   in one line, as [step 4](#4-look-then-repair) describes.

## 3. Make one build fit every screen

Each layer scales by its own rule. The ground covers the viewport and crops.
The lead fits its region and keeps its aspect ratio. Controls and text keep
their sizes and reflow. On a short wide screen the height is the scarce side:
the lead takes the full height and the other parts sit beside it, not above
or below it. One fixed canvas under a `UIScale` does none of these.
[Build a screen as a place](references/place.md#scale-each-layer-by-its-own-rule)
has the rest.

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
simulator:SetOrientationAsync(Enum.ScreenOrientation.Portrait) -- or LandscapeLeft; phones and tablets only
task.wait(1)
return tostring(workspace.CurrentCamera.ViewportSize)
```

`simulator:GetDeviceListAsync()` lists the device ids. The preview shows the
real safe-area insets and touch controls; a resized frame does not. Capture
the first screen on a desktop, a phone in portrait and the same phone in
landscape before you build more screens. Restore the desktop preview when you
finish.

Let a plate hug its content. A pixel width that makes a text fit on a
desktop does not shrink on a phone, and `mayDrop = true` does not repair it:
the Popover that shows the dropped part is as wide as the part.

A size that you fix stays fixed in a short room; Facet does not choose a
shorter form for you. A record that is taller than the room that scrolls it
is never seen whole. Measure that room with `UI.environment(body)` and give
the record a shorter form there, such as a thumbnail beside its facts;
compact compositions shows
[the switch](references/compact-compositions.md#change-the-form-of-a-record).

A shorter form keeps a route to what the fuller form offered. Press each
opener at the short size and see its task appear. What the player opens with
a button gets a Sheet or a Popover, not a HUD region that can drop;
[compact compositions](references/compact-compositions.md#allocate-the-remaining-room)
has the rule.

Add a console when the product supports one, and check focus there before you
build more screens. [Runtime essentials](references/runtime.md#input) has the
keys that stand for a controller in Studio.

## 4. Look, then repair

View each capture at its real size. A text report does not show the screen.
Check these in order and stop at the first failure.
[Look, then repair](references/look-and-repair.md) has the full form of each
check.

1. **Fit.** Nothing is clipped, overlapped or unreachable at any size. The
   ground reaches every edge. Every part of the desktop screen is present at
   every size under the same label. The main action is inside the thumb's
   reach on a phone.
2. **Lead.** The subject or the content is the largest and clearest thing on
   the screen, at every size. On a desktop its objects and markings span most
   of the width.
3. **Identity.** With the title hidden, the screen still belongs to this
   product. For an expressive game, these are signs of an unfinished direction:
   a flat neutral ground; one font family at nearly one size; choices that are
   equal rectangles with different labels; a main action that looks like every
   other button; a small subject beside a large empty area.
4. **States.** Selected, focused, pressed and disabled paint belong to the
   theme. In a still capture, a person who has not used the screen can name
   the selected choice.
5. **Response.** Commit with real input. The response on the card happens, and
   the action stays in place.
6. **Craft.** Crop the capture to each kind of object and view it at twice its
   size. Nothing is a placeholder, soft, stretched or off its baseline, and a
   label on a piece of art lies inside the paint.

Repair the two largest gaps at their cause, then capture again. Enlarge the
lead or the type before you add panels; fix the theme before you paint one
control. A quiet tool passes the identity check with a plain ground and one
family; judge its hierarchy, rhythm, density and states.

For an expressive game, an independent review is the largest gain in finish
that is available after the first build. When you can start a separate agent,
give it only the user's request and the captures of every size, and run
[the review round](references/look-and-repair.md). When you cannot start an
agent, tell the user that the screen has had no independent review.

Run `Facet.review.screen().text` in the Client data model on each changed
screen, at each size that you capture and in each state that has its own
message or its own rows, such as the empty state, the filled list and the
result. Fix `empty-screen`, `build-failed`, `runtime-error` and each `high`
finding before building the next screen. On a new interface, each `medium`
finding is work too. `hollow-plate`, `joined-facts`, `flat-hierarchy`,
`record-without-visual`, `competing-peaks` and `nested-surface` are how a
generic composition reads in numbers: a plate with its content in one
corner, a line that joins every fact, records that differ only by name.
Repair each one at its cause, or note in one line why the design keeps it.
`low` findings are prompts to look. A clean report covers only the state
that was mounted, and it does not judge identity.

## 5. Build the other screens

Build each remaining screen from what the first one settled: the theme, the
owners and the project's own components. Give each screen the composition
that its task needs, with its own lead, action and arrangement. One `Screen`
with a header and a scrolling column, used again for every destination, makes
every task a form, and the finish of the first screen does not reach it. Size
each surface to its task: a short task hugs its content, and a surface that
you make large is filled by a body that uses its width. The
examples in [Find the implementation route](#find-the-implementation-route)
compose a collection, an inspection, an outcome and settings differently.

A check covers only what was mounted when it ran. Check again what a change
touches.

- After a change to a builder that several screens share, mount each state
  that uses it, with data that enters every branch: the filled list, the
  empty one and the error. A syntax check does not build a control, and a
  branch that waits for data is not built on an empty state.
- After a change to focus, navigation or input ownership, start a fresh Play
  session. Check the first directional move, an activation and Back.
- After a change to the form or the size of a record, open the shortest
  screen, scroll from entry and activate a record.
- After a change to a HUD region, review the HUD again on the phone in both
  orientations. A region that is added late is the one that overlaps.

Use the [critique-ui loop](../critique-ui/SKILL.md#the-loop) when the user
asks for a review or a polish pass, or after choosing from rendered
alternatives when a separate reviewer is available.

## Build with Facet, not around it

Build the whole interface from Facet: layout, images, text, state and motion,
as well as controls. A Facet construct adapts to room, input, text scale and
ten-foot viewing, takes the theme, and is visible to `Facet.review`. A native
frame placed by `Position` does none of these, and two of them can overlap
when the room shrinks. [Runtime essentials](references/runtime.md#from-a-native-habit-to-facet)
names the Facet construct for each native habit.

Use the control that names a part before you build the part from stacks:
`Avatar` for a face or initials, `Badge` for a short status, `ProgressView`
for measured progress, `Timer` for a deadline, `StepIndicator` for steps and
`Chip` for a filter. Such a control brings its states, sizes and fallbacks.
Search the reference for the noun first.

Native Roblox remains correct for what Facet has no construct for: a
`UIPadding` or `UISizeConstraint` child, a `UIGradient` or `UIStroke` on a
shape, an `InputAction` and world content. Native properties on a Facet
construct, such as `Rotation`, `ZIndex` and `ImageTransparency`, are also
correct.

**When Facet has no control for the task, make one from Facet.** Do not build
the screen from native parts because one control is missing. Write a
component in the project's own module, outside the Facet package: a function
that takes an options table and returns one Instance, with the contract of a
Facet control. [Components](../../docs/guide/components.md) has the contract.
Report the need as a library gap and name the component as the proposal.

Before delivery, search the source for `Host.`, `Instance.new`, `AnchorPoint`
and `TweenService`. Replace each use that Facet covers. Report each one that
remains with its reason. A need that Facet cannot meet is a library gap to
report, not a detail to hide.

## Find the implementation route

Use Compose for composition, state and lifetime. Standard control behavior
does not require a standard visual composition.

Read a control's contract before its first use, and before you pass it an
option that you have not used on that control. An option that you have not
read is a guess, and options do not move between controls: `surface` belongs
to `VStack`, `HStack` and `Screen` and takes three values. With a shell, run
`lute run tools/facet docs --search TERM`, or search `docs/reference/nodes`
when that command is unavailable. In Studio with `FacetDocs` installed,
`loadstring(ServerStorage.FacetDocs["search.luau"].Value)()("Sheet detents")`
returns short matching sources; batch queries as `search({ "A", "B" })` and
use `search.read(path)` for a complete contract. Do not guess filenames.

| Task | Read and adapt |
| --- | --- |
| Choose a control or a surface for a task | [Choose an interaction](references/choose.md); [game screens](references/game-screens.md) for navigation and lifetime |
| Structure a HUD, a destination or a modal task | Nodes `Tasks.hud`, `Tasks.pages` and `Tasks.sheet` |
| Decide a game design tradeoff | [Game UI design](references/GAME_UI_DESIGN_GUIDE.md) |
| Define the theme or use image surfaces | [Finish](references/finish.md), then [theme contracts](references/game-themes.md#theme-contracts) |
| Build a place, a material or an illustrated world | [Build a screen as a place](references/place.md) |
| Browse records, products or equipment | [Collection](examples/collection.luau) and [patterns](references/patterns.md) |
| Inspect a selected object | [Inspection](examples/inspection.luau) |
| Preview a 3D object or choose its color | Node `Tasks.appearance` |
| Show stats, records, prices or progress | [Information display](references/information-display.md) |
| Act during play, then open brief help | [Exploration](examples/exploration.luau) |
| Fit a task into narrow or short room | [Compact compositions](references/compact-compositions.md) |
| Build a Studio plugin or mount in an existing runtime | [Runtime details](references/runtime-details.md) and the `Mounting` node |
| Work from saved source files with the Facet tooling | [Filesystem workflow](references/FILESYSTEM_WORKFLOW.md) |

Keep durable selection, drafts and accepted state outside disposable pages,
and give unrelated tasks separate scroll state. Connect pending, rejection,
retry and acceptance to the real operation. If a theme definition fails,
repair the reported errors; do not continue on the neutral package.

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
