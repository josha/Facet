# Facet Design verification

Date: 2026-10-01. Native Studio evidence base: `e6abca0f`.
Latest-main PR verification base: `c55ee609`.

## Evidence

- 86 targeted tests pass. They cover the public constructor registry, all 63
  adapter exports and mounts, template source round trips, literal escaping,
  unsupported source rejection, document bounds, history, owner cleanup,
  independent comparison state, presented overlays, storage revisions, and every
  choice and boolean preset with stable export round trips.
- The modules and companion client/server scripts pass Roblox Luau analysis.
  The source map uses absolute paths for these checks.
- The plugin model and companion place build with Rojo.
- Native Studio geometry matches between the direct design and compiled exported
  component for all 63 constructors. This includes presented Alert, Sheet,
  Dialog, Popover, Callout, and Toast contents. See
  [native-coverage.json](native-coverage.json).
- Native pointer input selected a layer, opened the compact Inspector, selected
  canvas controls, and switched compact panes. TextBox editing changed the
  exported source. Undo restored the previous design.
- A native source-watch probe saw one supported external source change, no
  self-write feedback event, and blocked a visual write after custom source was
  added. The custom source remained intact.
- The phone portrait and tablet landscape simulators rendered the
  editor. The simulator was reset after testing.
- `lune run tools/lune/verify full` passed: 3,605 tests passed and one test was deferred.
  Of 74 producers, 72 passed. The performance gate and its evidence check
  reported host timing failures rather than functional failures.
- A separate `lune run tools/lune/bench` run passed after full verification completed.
  The full run reported six host timing violations. The earlier baseline also
  had environment failures for these two performance producers. No functional
  regression was reported.
  `python3 tools/package.py build` and
  `python3 tools/package.py status` completed. The library package was not published.

## Expanded editor checks

The expanded inspector has 1,000 field definitions across 63 constructors. Native
Studio checks mounted 1,015 choice and boolean presets, 117 structured and color
values, and 96 edited template/profile/palette/text-size combinations without
errors. See [native-gap-review.json](native-gap-review.json). These checks prove
constructor acceptance, not every property interaction.

The desktop review used 1280×800, 1440×900, and 1920×1080 simulator viewports.
The 1440×900 check included device safe insets.
Layers, canvas, and Inspector remained visible together. Fit zoom shows the full
phone design. Native canvas size, window size, and content size all measured
849×734 after the scrollbar fix. The visual gallery shows six live designs in
three columns. The actual companion startup now selects Fit after the first
nonzero screen measurement; its canvas and content both measured 943×756.
An explicit zoom choice disables automatic zoom changes. A compact gallery search and pointer selection opened Quest
journal. Native text input changed side padding and its generated source.

The agent CLI edit and inspect commands passed against a generated component.
Atomic agent edits, invalid-batch rejection, supported source round trips, and
archived-library reload have deterministic tests. A native Studio agent edit triggered one source callback, changed the heading,
and updated FacetDesignDocument and synchronized status. Native custom-source
protection retained an external expression and blocked visual writes. An agent
edit also updated the mounted editor canvas and generated code, and enabled Undo.
Native Plugin settings reload preserved archived designs and quotes, backslashes,
and newlines. The settings key avoids periods, and EncodingService Base64 protects
JSON strings from the [Plugin settings restrictions](https://create.roblox.com/docs/reference/engine/classes/Plugin#SetSetting).
Writes verify the stored string before reporting success.
[EncodingService](https://create.roblox.com/docs/reference/engine/classes/EncodingService)
supplies Base64 encoding; Compose does not own persistent Studio storage. Visual
history behavior has deterministic tests; a new native export/undo probe was
blocked by the Assistant plugin's active ChangeHistoryService recording.

Roblox UIGridLayout, TextBox, ScrollingFrame, Color3, and HttpService JSON supply
the new layout, editing, color, and transfer mechanisms. Compose cleanup owns
thumbnail sessions. Custom code supplies authoring operations and validation;
no missing general engine or Compose mechanism required an upstream change.

## Workflow review

See [workflow-review.md](workflow-review.md) for editor workflows, evidence, and
remaining checks.

The phone check uses a 402×874 preset in portrait and landscape. The tablet
check uses a 1376×1032 preset in landscape. The experience uses Sensor
orientation and DeviceSafeInsets. Studio was reset to the default viewport after the check.

Native input opened Design commands and Insert. Search filtered while typing.
An empty query result showed a message. Clear restored all 62 insert choices.
Canvas input selected the heading and opened Inspector. Text input changed the
exported source. Reset restored the adapter default. Undo restored the previous
text. Redo restored the default. Native bounds confirm that Insert and the
canvas card fit the phone width. Property labels precede their inputs. Selection
uses native UIStroke.BorderStrokePosition.Inner to stay inside clipped canvases.
A failed structured edit keeps the data editor open.

All 329 choice and boolean presets pass native Studio mounting checks. The
recipes handle form-dependent properties for Skeleton, LevelPicker,
DateTimePicker, and Toast. Conditional fields match the selected form. See
[native-presets.json](native-presets.json).

The implementation uses TextBox editing, ScrollingFrame, UIListLayout.SortOrder,
AutomaticSize, UIScale, and UIStroke. Compose cells, formulas, keyed children,
and owner cleanup already supply state, lists, and lifetime. No missing general
engine or Compose mechanism was found. Custom code stores editor commands,
property defaults, filtering policy, and document history.

## Limits

Native geometry evidence covers adapter defaults in a light 390×844 preview;
it is not complete interaction coverage for every control property. The native
verification suite does not establish the historical parity described in
`docs/guide/18-verification-scope.md`.

The companion was published on 2026-10-01 as a new private experience named
Facet Design. All five Studio platform options were selected: Computer, Phone,
Tablet, Console, and VR. Team Create and Data Sharing were off at creation.
Reopened settings confirmed Team Create off. The publish completion dialog
showed Successfully published and Private. See [publish-receipt.json](publish-receipt.json).

Cliclick reached the correct window through desktop window selection. The earlier
native UI binding issue no longer blocks publication through this workflow.
Cloud-save behavior on a published server and physical device input still need
verification. Complete interaction coverage and product readiness on every platform remain
separate checks.


## Desktop outline and layout fixes, 2026-10-01

The Layers pane uses Facet VirtualList for full-width rows. A native TextBox
edits a layer name after a double-click. Native Studio input committed and
canceled names, moved Season below Introduction, and restored the order with
Undo. Selection moved between rows without retaining the prior highlight.
The root Screen cannot move. Duplicate and Delete were disabled for the root
and for an empty selection. Calling either action with no selection changed
nothing. The drag-handle column and the up/down buttons are removed.

The list has a native UISizeConstraint for its content height. Actions follow
it with an 8-pixel gap, including in a 700 by 650 compact pane. Compact rows
measured 673 by 44 pixels and the list measured 676 by 216 pixels. The list
scrolls when its content is taller than the available space.

Bounded Button captions shrink before their trailing icons. Facet owns hover
and pressed paint by default through AutoButtonColor=false. Inspector headings
and controls use native automatic height. Gallery previews, actions, and detail
text use separate native layout rows. All six preview bounds stayed inside
their thumbnails and their actions stayed below the preview.

Roblox GuiButton.Activated starts its click count at zero. Collection activation
and the playlist example now use that contract. Plugin row dragging uses
GuiObject.MouseButton1Down, MouseMoved, and InputEnded. These events preserve
button activation in a PluginGui. Studio did not send the required plugin mouse
movement through UserInputService, and a UIDragDetector on the button suppressed
its click activation. The collection still owns reorder thresholds, scrolling,
and the insertion slot. Compose owns row state and resource cleanup.

Final isolated full verification passed: 3,610 tests passed, none failed, and
one was deferred. Of 74 producers, 72 passed; the performance gate and its
evidence check reported host timing failures. A separate benchmark run passed.
Library package build and status completed. The local Studio plugin and
companion place were rebuilt. No library or experience was published.

## Shared drag preview and help fixes, 2026-10-01

Facet collection feedback now raises the entire cloned row above the list.
The selection badge and keyboard Drop button stay above that preview. Native
Studio rendering retained the Preferences row background, text, and 300 by 52
pixel bounds under both Sibling and Global ZIndexBehavior. The preview's lowest
child ZIndex was 1002; the feedback root was 1000 and Drop was 1004.

Help waits for 0.45 seconds without pointer motion and without a held mouse
button. Native GUI events and UserInputService events share the same state, so
moving from one row to another during a plugin drag cannot start another help
timer. Losing window focus hides help. Overlay portals carry the nearest
StyleLink, preserving a theme scoped below the LayerCollector. A native Studio
check rendered the rounded bubble and arrow with BorderSizePixel=0 and no
outer rectangle. Changing the source StyleSheet updates its overlay link.

Roblox Instance.Clone, GuiObject.ZIndex, Path2D.ZIndex, StyleLink, GuiObject input
events, UserInputService, and PluginGui focus events provide the engine behavior.
Compose portal, property observation, createSharedResource, and cleanup provide
placement and lifetime ownership. Facet supplies the idle delay and collection
feedback order; no new general runtime mechanism is needed.

The focused checks passed: 89 collection cases, 34 callout/help cases, seven
motion policy cases, and analysis of both changed source files. Native preview
activation used the existing Facet activation callback. Desktop automation
returned windowNotFoundAtPosition when attempting a physical drag; actual mouse
drag verification of this revision remains open. The temporary Studio fixture
was removed after the rendering checks.

Final full verification ran against c870895b with these edits: 3,613 tests
passed, none failed, and one was deferred. Of 74 producers, 66 passed. Five
legacy brand/API scans failed on RascalRally files or cached logs outside this
change. The capture check found six older performance captures with obsolete
scenario versions. The performance gate and its evidence check reported three
host timing violations. These broader failures leave the full command red.
The separate benchmark passed. Package build, status, tree verification,
canary, and purity checks passed. Empty legacy source directories were removed
because Rojo included them as unwanted package folders.

The designer plugin and companion place were rebuilt. The installed local
Facet-Design-PR52.rbxm matches the new plugin build. Restart Studio to load it.
The previous local plugin is backed up at
/tmp/Facet-Design-PR52-before-drag-fix.rbxm. No package or experience was published.
