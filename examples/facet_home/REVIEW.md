# Facet Home review receipt

Base: `clean-type-aliases`, the head of PR #58 (`ccceb112`). PR #58 was merged
while this example was being built. The work stays in `feat/facet-home`.

## Native API choices

The reviewed Roblox engine APIs were ProximityPrompt, DataStore, SurfaceGui,
ScreenGui.ScreenInsets, Model.ScaleTo, Model.PivotTo, and SurfaceAppearance.Color.
They provide room activation, durable storage, and world UI. Parts provide the
room and furniture. Native Table and RowActions provide collection behavior.
Compose cells, formulas, keyed mounts, cleanup, and owners provide local state
and lifetime control. The custom model contains only game-specific validation,
room slots, revision policy, and a memory activity.

## Fresh Studio checks

Initial checks used a local smoke place with Home installed as a fixture.
After restarting Studio, the checks used the built Facet Home place.
Other project windows were not changed. This was a Studio client/server session,
not a published or physical phone test.

- Home mounted without console errors.
- All six reusable furniture cells showed their current names and categories.
- A 368-pixel panel produced a 292-pixel table with only the name column.
- A 720-pixel panel produced a 644-pixel table with name, count, and finish columns.
- The inventory context menu opened on a row. Choose selected that row's piece.
- Server requests placed furniture, rotated it twelve times, saved it, removed
  it, and restored it. An invalid slot request was rejected and left the room intact.
- The server retained one furniture model, eight furniture descendants, and six
  room prompts after the repeated edits.
- DataStore loading was unavailable. Save reported session-only storage.

The initial wide check resized the live native panel in a compact viewport.
Later screenshots checked the native Home place in a wide Studio viewport.
A compact panel check used a 368-pixel panel inside that viewport.
It does not prove physical phone behavior.
Cloud persistence, multi-client sessions, physical devices, swipe input, and
console navigation still need fresh evidence.

## Visual and safe area checks

- The built place uses wood flooring, plaster walls, window framing, and a path.
- Four static Creator Store furniture models load with PBR surfaces. The subset
  contains no scripts. All six furniture pieces fit their room slots.
- A native check confirmed that the sofa surface received the selected finish.
- A build defect used the non-serialized Position property for the ground.
  The project now stores CFrame. The ground no longer covers the floor.
- Home and the Facet Design experience use CoreUISafeInsets. Core UI remains
  enabled in Facet Design. The background can extend behind the safe area.
- Native Home bounds were 1593 by 778. The panel began 12 pixels inside the
  safe area, ended at 714, and the dock began at 722. Screenshots confirmed
  the top offset. There was an eight-pixel gap between panel and dock.
- A 353-pixel native parent produced a 329-pixel panel with 12 pixels of
  space at each side. The panel uses a native UISizeConstraint for its desktop
  maximum width. It measures its safe-area parent, not the full camera viewport.
- Immersive mode uses the normal Custom avatar camera while Home is open or
  closed. Flat mode uses a Scriptable room overview. Explore hides the panel
  and enters immersive mode. A native movement check kept Home open and
  observed 14.79 studs of camera travel with the Humanoid as its subject.
  Switching to flat mode selected Scriptable; switching back selected Custom.

## Verification

`tools/verify.sh full` passed its current native gate: 74 producers selected,
72 passed, and two reported performance environment failures. The clean main
baseline had the same two failures and the same six host timing violations.
The suite passed 3,632 cases, with one case deferred. Historical parity remains
not established.

The focused strict type check passed for 29 changed targets. The final safe-area
width change also passed its focused type check. The collection and Home
behavior tests passed 19 cases. Native geometry and camera checks are listed
above; engine doubles do not establish those behaviors.

The shipped-client export census previously read type annotations as runtime
member calls. It now recognizes declared type annotations, including function
parameter types, and still rejects missing runtime exports and missing types.

`tools/bench.sh` and `tools/package.sh build` passed in the final full run.
`tools/package.sh status` completed and reported existing publication drift and
missing release evidence. This work does not publish the Facet package.
