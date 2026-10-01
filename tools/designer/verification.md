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
- `tools/verify.sh full` passed: 3,605 tests passed and one test was deferred.
  Of 74 producers, 72 passed. The performance gate and its evidence check
  reported host timing failures rather than functional failures.
- A separate `tools/bench.sh` run passed after full verification completed.
  The full run reported six host timing violations. The earlier baseline also
  had environment failures for these two performance producers. No functional
  regression was reported.
  `tools/package.sh build` and
  `tools/package.sh status` completed. The library package was not published.

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
