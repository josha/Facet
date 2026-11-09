---
name: use-facet
description: Design, build and refine Roblox game UI and Studio plugin interfaces with Facet, including touch, pointer and controller use.
---

# Use Facet

**Design the product first, then choose the controls that realize it.**

## Start with the requested task

Identify the user's decision, accepted outcome and return path. Preserve the
brief, existing behavior, art direction and working routes. For a small edit,
reuse established decisions rather than redesigning the application.
For a new interface, complete theme development, needed artwork and visual
verification within the initial request. Use internal drafts and repairs to
reach the first delivery. A request for a wireframe or functional spike can
stop at that stated scope.

Establish the supported viewports and inputs from the brief and existing product.
Record the minimum usable width and height for each supported orientation,
after insets and scaling. Use the [minimum-viewport checks](references/compact-compositions.md#verify-the-minimum-viewport)
to choose and prove those limits; a named phone preset alone is not coverage.
For phone use, cover portrait and landscape unless the product deliberately
restricts orientation. A landscape-only test does not establish that restriction
or prove general mobile support. Respect a limited test request and report its
coverage accurately.

## Choose the visual direction before building screens

For a new interface or visual redesign, choose its identity from the brief.
A game should express its world and intended feeling. A professional mail app
or Studio tool can use quiet, familiar styling. Preserve established direction
for small edits and respect an explicitly minimal or text-led brief.
Set the level and kind of visual detail from the game's art, tone and audience.
Finished pixel art, soft colorful shapes and detailed illustrated or realistic
surfaces can each be high quality. Judge craft within that language; greater
realism or complexity is not a universal improvement. See [appropriate finish](references/game-themes.md#match-the-finish-to-the-game).

Decide what the player should see, understand and do, and how the experience
should feel. Design that composition before mapping it to library components.
Establish the subject, type hierarchy, choice treatment and main action in
the first mounted screen. Do not spread a neutral panel helper across all
routes and defer the visual direction until later. Use the first-screen
capture and review below as the checkpoint for expanding the interface.

For a new expressive game, complete these steps within the initial request:

1. **Explore before choosing.** Infer a specific creative premise from the
   activity, audience and world when the brief leaves style open. Inspect
   relevant visual references, then render three whole-screen directions for
   the same representative task. Vary composition, type and rendering approach
   where the game's direction leaves room, not just palette or subject art.
   Keep every alternative appropriate to its world, tone and audience.
   Use available image generation by default
   for an open direction. Choosing to call your own first idea "graphic" does
   not waive exploration. An established direction or an explicitly minimal,
   text-led or prototype brief can use a focused native study instead. Follow
   [visual study](references/game-themes.md#resolve-the-whole-composition).
2. **Review and commit to a target.** Compare the directions together in one
   [design-target review](../critique-ui/SKILL.md#review-a-design-target).
   Choose for character, craft, task clarity and feasible runtime production.
   If every candidate is generic, revise the concepts before building routes.
   Record the few visible qualities the implementation must preserve and how
   each will appear in live controls, type or artwork. Then
   inspect the [worked translations](references/visual-translations/guide.md)
   for implementation techniques relevant to that target. Their layouts and
   materials are examples, not a style to choose by default. Resolve visual
   `must` fixes before functional routes. This is an internal choice, not a
   user approval step.
3. **Prove one real screen before expanding.** Create the reusable artwork
   needed to preserve that target's finish. Upload original UI art and icons
   through [Open Cloud](references/asset-upload.md), bind the returned IDs and
   verify loading. Do not use EditableImage or packed pixels for UI assets.
   A dynamic player drawing canvas can use EditableImage. Use Facet's theme
   and chrome contracts, live labels and standard control behavior.
   Build a representative choice, primary action and opened control where
   the task has them. Use static data if useful. Capture a wide view, then the
   minimum supported narrow and short layouts after insets and control scaling.
   For phones supporting both orientations, check portrait and landscape here;
   neither substitutes for the other. Include the notched safe-area case too
   when it imposes different constraints. Use [compact compositions](references/compact-compositions.md)
   to change the arrangement when its readable content and targets cannot fit.
   View phone captures at the recorded camera width to judge text size; Studio
   can enlarge them. Use the full-resolution capture to inspect painted edges.
   Enter this task through its normal opener using the supported inputs.
   Exercise the real choice while selected and focused, then move focus to a
   peer; inspect pressed and disabled states where relevant. Include changed
   labels and the longest supported content, not only convenient sample text.
   Open confirmation if the action uses it, and compare feedback before and
   after acceptance. Test cancellation and return while the task is still small.
   Use the [tested state patterns](references/visual-translations/guide.md#keep-the-task-stable-through-state-changes)
   for label clearance, separate focus and selection, and stable action space.
   Compare runtime and target at the same viewing size. For each defining
   quality, record what the capture preserves, weakens or replaces, and why.
   Repair a lost defining quality or revise the target into a coherent finish
   the runtime can deliver. Loaded art alone does not preserve subject
   separation, material depth or hierarchy. Use the next
   fresh critique round here; include these state captures. Resolve visual
   `must` fixes and inspect the repaired screen before adding routes or
   repeating its skin. Check proposed repairs against control contracts;
   a suggested shape does not require replacing a control's behavior.
4. **Complete and verify.** Build the remaining routes around that working
   treatment. Inspect supported desktop, phone portrait, short landscape and
   console views, including the declared minima and stateful rotation back.
   Follow the [minimum-viewport checks](references/compact-compositions.md#verify-the-minimum-viewport).
   Record input proof separately from visual review. Check
   acceptance, cancellation and return; overflow and painted-edge overlap; essential text; selection
   with focus; and action placement before and after feedback. Recheck identity
   after readability and layout repairs. Preserve the game's materials and
   hierarchy rather than replacing them with generic utility panels.

Keep the critique skill's three-round limit across target, first Studio screen
and completed task. This is internal design and repair within the request,
not a user approval step. In review notes, record the image paths actually
viewed, the first-screen captures and the affected states tested. A later
capture cannot establish that early review happened.
When a focused native study fits the brief, its first Studio screen can supply
both the design target and runtime evidence without a duplicate concept round.

Plan [labels and states](references/game-themes.md#protect-labels-from-artwork)
with the art. A small edit needs only its affected states checked. Do not add
choices or actions to a passive display to satisfy this workflow. A quiet tool
or an established text-led design can use a focused native prototype and review
without new illustration or decorative surfaces. Choose layout from its task,
content, input and room; examples show relationships, not required features.

## Find the implementation route

Search Facet controls, options and helpers first. Use Compose for composition,
state and lifetime, then native Roblox for an unmet need. Build custom behavior
only for the remaining gap. Standard control behavior does not require a
standard visual composition.

Read [runtime essentials](references/runtime.md) and the relevant route below.
With a search tool, search the route for the decision at hand instead of reading
it whole.
Read a theme asset only when adapting it. Retrieve exact control contracts as
needed; an example does not cover every option or integration. Everything you
read stays in context for the rest of the session. Look up a control's contract
when you are about to use it rather than every route up front. In Studio,
`loadstring(ServerStorage.FacetDocs["search.luau"].Value)()("Sheet detents")`
returns short matching sources. Keep the callable as `search` for later calls.
Batch related queries as `search({ "Sheet detents", "Stage camera" })` for a
shared 4000-byte result cap. Hits identify sources; use `search.read(path)` for
the complete contract. Separate calls have separate caps.

| Task | Read and adapt |
| --- | --- |
| Plan a game interface or choose its surface | [Game UI design](references/GAME_UI_DESIGN_GUIDE.md), then the relevant section of [game screens](references/game-screens.md) |
| Build a Studio plugin or use an existing runtime | [Runtime details](references/runtime-details.md) and the `Mounting` reference; preserve the host's UI and input conventions |
| Browse records, products or equipment | [Collection](examples/collection.luau) and [patterns](references/patterns.md); supply the application's records and subject treatment |
| Inspect a selected object | [Inspection](examples/inspection.luau); allocate subject space from the details the user needs to see |
| Preview a 3D object or choose its color | Read node `Tasks.appearance`; bind scene, facts and labeled swatches to one draft |
| Implement the chosen theme or use image-based surfaces | [Game themes](references/game-themes.md#theme-contracts); example themes are optional |
| Show stats, records, prices or progress | [Information display](references/information-display.md); choose density and emphasis from the decision |
| Act during play, then open brief help | [Exploration](examples/exploration.luau) |
| Another composition | [Patterns](references/patterns.md) or [capability routes](references/choose.md) |

Read [compact compositions](references/compact-compositions.md) when room is
constrained, [advanced compositions](references/advanced-compositions.md) for
richer navigation, forms or spatial UI, and [runtime details](references/runtime-details.md)
for integration contracts. With a shell, search unknown names with
`lute run tools/facet docs --search TERM`; in Studio, use `FacetDocs["search.luau"]`.
Do not guess filenames.
Use [filesystem workflow](references/FILESYSTEM_WORKFLOW.md) when its tooling
is available and the project uses saved source files.

Put `table.unpack(rows)` last in a constructor; before other entries Luau keeps
only its first value. When the player chooses colors in a `Stage` preview, keep
its `Ambient` and `LightColor` near white so the preview shows the real colors.
Use typed constructors and reactive callbacks. Keep durable selection, drafts
and accepted state outside disposable pages. Give unrelated tasks separate
scroll state. Connect pending, rejection, retry and acceptance to the actual
operation. Demonstration callbacks do not implement a production transaction.

## Author through Studio tools

Keep the project's source and sync path. Edit persistent source; Play-only
changes are not the delivered result. Split modules by responsibility and
lifetime. Batch independent reads and changes that can be checked together.
Keep responses focused: repeated source dumps, whole-module rewrites and large
tool outputs grow the context carried into later calls. Write new modules
whole when useful; use focused patches for revisions. Check an unfamiliar API
in a small mounted component before spreading its pattern.

Read the relevant source range before patching. Group the patches for one
module, or for modules fixed together, into one call. An exact-text patch should
assert that its old text occurs once. Return focused diagnostics rather than
whole source trees. Put independent reads in one call. In Play, drive a route
and collect its errors, state and UI findings in one call that returns a short
report, rather than one probe per call. Wait for an outcome inside that call,
within the host's time limit, instead of polling it across calls, and send an
input and its capture together when the host allows. To check every screen in
one Client call, run `Facet.review.screens()`: it opens, reviews and closes each
mounted Sheet and returns build errors and findings. For other screens, pass
`{ Name = presentedCell }`.
Capture a screen when its report needs a visual check or after a visual change,
not after every step; each capture is resent with every later call.

For a new visual direction, prove one complete task before repeating its
treatment. Then make every required screen reachable before deepening gameplay,
and complete the remaining routes in the order of the brief. An existing
interface with an established direction can start with its missing routes.

Exercise changed routes in their real host: Play for game screens, the plugin
host for edit-mode tools. Inspect errors. Treat a mounted surface
that shows no content, or a control that is missing, as a construction error to
find, not a style to adjust. In the Client data model, `Facet.review.screen().text`
provides layout and design findings, including compact-layout findings when the
host shows only one size; run it on each changed screen, including during
gameplay. Its `empty-screen`, `build-failed` and `runtime-error` findings mean
a screen or control failed to build; fix that before anything else. A control
that fails to build shows a red placeholder with its error while the rest of the
screen still builds, so collect every failure from one Play session and fix them
together before restarting Play. Fix each `high` finding, such as a
composition that does not fit a phone, before building the next screen. If the host's command
tool cannot require modules, call it from a temporary client script and read its
output.
Automated findings are evidence to investigate, not a substitute for viewing
the interface or testing input. Capture representative changed states at the
supported sizes the host can show, then capture again after visual repairs.

## Verify against the brief

Before repeating a new layout, check one complete task in its real context.
Can the user find the relevant facts, understand the action and return with
the expected state? Check visual hierarchy, readability and fit against the
chosen direction. For a game, name the visible choices that connect the UI to
its world and tone. If only the title and accent changed from the starter,
revisit the theme before repeating it, unless that restraint fits the brief.
For a professional tool, check clarity, density and familiar interaction.
Keep useful context visible when the task needs it; choose
full-screen, modal, docked or contextual presentation deliberately.

Inspect `report.advice` and review findings against actual content and use.
Fix real defects. Explain deliberate choices when a heuristic disagrees;
do not change an appropriate design only to remove a warning or raise a score.
Use the [critique-ui loop](../critique-ui/SKILL.md#the-loop) for a new game
direction or substantial game visual redesign, as required above. Use a
focused review for a small edit within an established style. A deeper review
can also help when the user requests it or another visual change warrants it.

Leave time for a fresh run of the main routes from start to finish in their
real host; a late patch can break a route that worked earlier.
Exercise affected acceptance, rejection, cancellation and return routes through
real input. Check relevant compact forms, large text, focus and native-control
clearance. For lifetime or performance changes, measure after successful
returns. Scale verification to the change and report what was actually tested.
Missing captures or input evidence leave those claims unverified.

For a Compose Design module, read [the design editing contract](../compose/references/design.md)
before changing it. Keep its design shapes and run `lute run tools/facet design check <module>`
so the Studio editor stays in sync.
