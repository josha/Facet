# Choices and input

Part of [Designing game interfaces with Facet](../GAME_UI_DESIGN_GUIDE.md).
Choose from the value's meaning, required precision and commitment cost. Use the
installed API docs for exact signatures; these are the design-significant choices.

## Choose by value, precision, and commitment

| Need | Starting control |
| --- | --- |
| Independent binary state | Toggle |
| One/several members of a defined set | Picker |
| Typed lookup, possibly a new value | ComboBox |
| Small incremental count | Stepper |
| Exact number or wide range | NumberInput |
| Continuous magnitude or interval | Slider |
| Short intensity scale | LevelPicker |
| Evaluation on an ordered scale | Rating |
| Up/down/no-vote judgment | Vote |
| Free text | TextInput |
| Arbitrary color | ColorPicker |
| Calendar date/time/range | DateTimePicker |
| Active filter/removable token | Chip |

Meaning distinguishes controls that share a numeric type: continuous volume,
precise purchase quantity and a quality rating are different decisions.

## Commit at the right boundary

Reversible settings can apply immediately when the result helps judgment. Use a
draft for coupled values, reversible experimentation or consequential commitment.
Keep Apply/Cancel and their scope near the draft.

`onChange`/`onCommit` describe control events, not saved server state. Map them to
preview, draft and accepted state deliberately; release, blur and configured Apply
have different meanings. Do not purchase on incidental blur. Pending work must
prevent duplicate consequences; rejection keeps useful input for correction.

Keep incomplete typing fluid, show constraints before commitment and errors beside
the field, with recovery/escape available. Use persistent labels: a placeholder
cannot explain a field after text replaces it. Across controls, distinguish
read-only, unavailable, pending, empty and zero. Preserve keyboard, pointer, touch
and gamepad routes, including precise alternatives to gesture-only adjustment.

## Toggle

Use `presentation = "switch"` for an immediate setting, `checkbox` for form
membership/agreement and `button` for a compact persistent mode. Exclusive
alternatives need a single-choice Picker. Name the state positively with `label`.

`mixed` means selected records differ; define the next activation's value rather
than treating it as an ordinary third choice. Align indicators consistently.
`busy` is pending application; `enabled` is availability. Keep unchecked and
disabled visibly distinct beyond color.

## Picker

Use for named values, with single selection or `multiple = true` and a selected
key set. Use a collection for rich record browsing, comparison or bulk management.

| Style | Useful distinction |
| --- | --- |
| `automatic` | Adapts presentation; never automatically chooses cards |
| `segmented` | A few short peers visible together; unsuitable for long descriptions or search |
| `inline` | Options remain in the surrounding form |
| `radioGroup` | Explicit exclusive choice with readable explanations, using more height |
| `cards` | Visual identity/descriptions justify the space |
| `menu` | Current value is enough until opened |
| `navigationLink` | Compact field opens an anchored adaptive chooser, not navigation history |

`required` determines whether empty is legal; name an allowed empty state.
`onChanging` can veto, but restrictions should be understood before repeated
attempts. `onChange` confirms control selection, not server acceptance.

Use `query` with a compatible searchable style, not `segmented`. `axis = "y"`
helps longer options; horizontal cards can wrap. `sizing = "hug"` fits toolbar
values; `fill` distributes a short set within bounded space. Test labeled menu
`valueAlignment` with long current values.

Descriptions, `meta`, avatars, badges and status must distinguish options.
`iconOnly` needs familiar symbols and accessible names; customized `indicator`
needs equivalent selection clarity. Appearance families vary by style: segmented
`filled`/`stroke` is not a universal radio/card option.

## ComboBox

Use when typing helps find a value and possibly create one. Set `acceptCustom`
deliberately. Keep typed `text` separate from selected `value`; a substring is
not a valid record. `commitOnFocusLost` is suitable only for safe implicit
acceptance. Preserve the query through loading, no-results and invalid custom
input. A searchable Picker better expresses a choice restricted to known options.

## TextInput

Use for names, messages and search. `presentation = "search"` names lookup;
`plain` is ordinary entry. Supply `label`, useful `hint`, `errorText`/`invalid`
and a genuine `maxLength` when needed.

`validate` accepts/transforms text or returns nil to reject it. This differs from
CellEditor validation, which returns an error message or nil. Do not exchange
those contracts.

`multiline` without `visibleLines` grows; with it, the field is bounded and scrolls.
Keep the field, error and Send/Save visible with the on-screen keyboard.
`onChange` receives edits; `onCommit` distinguishes submit from focus loss;
`onCancel` abandons the edit. Sending needs intentional submit, not blur.

`selectOnFocus = "all"` suits replacement, `end` appending and `none` ordinary
caret work. `readOnly` preserves readable/selectable content. Choose
`clearButtonMode` by the cost of accidental clearing: search differs from a
long draft.

## NumberInput

Use for precision or a broad range. Show units through label or `prefix`/`suffix`.
Set `min`, `max`, `step` and `precision`; `parse`/`format` must agree on units and
notation. Keep empty distinct from zero and make clamping visible if surprising.

`stepButtons` adds small adjustments; `scrub` adds a pointer gesture without
replacing typed/button access. `onCommit` includes submit, focus loss and clamping,
so map it to an appropriate edit boundary. Shared field labeling, errors,
read-only and pending rules apply.

## Stepper

Use for a modest discrete quantity; NumberInput suits large jumps. Choose useful
`min`, `max`, `step` and `format` including units/plurals. `repeatDelay` and
`repeatInterval` fit safe predictable holds. Keep quantity's total cost visible;
adjustment previews a transaction rather than buying repeatedly.

## Slider

Use for relative magnitude, continuous feel or an interval. `value` is one value;
`range` has two endpoints. Define `min`, `max`, meaningful `step` and any `minGap`.
Show a current value/scale through `format` or a clear label.

Map `onChange` to preview and `onCommit` to final gesture result where they differ.
`tapToPosition` trades faster jumps for accidental movement. Choose `axis = "y"`
for a genuine metaphor/layout reason. Hiding the `thumb` needs another discoverable
cue. `contained` and custom visuals must retain focus, range and hit-target
clarity; use an exact field if the required precision exceeds the gesture.

## LevelPicker

Use for short ordered intensity, Picker for separately explained values and
Rating for evaluation. `count` should reflect meaningful distinctions;
`allowZero` needs a real meaning such as Off. `segment = "bar"`, `glyph` or
`image` must preserve order/amount; keep `segmentSize` readable and reachable.
`readOnly` displays a level, while `onChange` edits it. Do not imply an immutable
stat is adjustable.

## Rating

Use for evaluation, not quantities or power merely because stars look suitable.
`count` defines the scale and `allowZero` whether zero/no rating is allowed;
explain unrated versus poor. `readOnly` presents aggregate/existing results;
`onChange` edits the player's judgment. Label ownership if both appear together,
and choose `starSize` for input/viewing distance.

## Vote

Use for up/down/none feedback, not choosing between several options. `value` and
`onChange` describe the player's response; `summary` is the aggregate. `readOnly`
shows results; disabled input means temporarily unavailable. Explain whether the
current vote toggles off and a new vote replaces it; show pending/refusal honestly.

## Chip

Use for a selected concept such as a filter/tag/recipient; Badge annotates and
Button performs unrelated commands. A chip can toggle (`selected`, `onToggle`)
or remove (`onRemove`). If it supports both, explicit `editing` switches activation
from selection to removal. Removal-only chips are always in edit mode. The Remove
mark belongs to the same button, not a separate target.

Make that mode clear, name `removeLabel` with the object and set a useful
`removeFocusFallback`. Keep `leading`/`trailing` content sparse. Wrap groups or
summarize them rather than compressing every token.

## ColorPicker

Use for arbitrary color; named choices need Picker and a fixed palette can use
`modes = { "swatches" }`. Expose only supported techniques: swatches, spectrum,
sliders or brick colors. Label custom swatches and own save/remove through
`onSaveSwatch`/`onRemoveSwatch`.

`style = "automatic"` opens a compact well/panel; `inline` fits a dedicated area.
`draft` adds Apply/Cancel. `onChange` previews, `onCommit` ends a gesture and Apply
commits a draft transaction. Expose `alpha` only if supported; `allowEmpty` needs
a meaningful absence such as inherited color. Preview actual material/lighting;
color alone cannot communicate team, rarity, eligibility or selection.

## DateTimePicker

Use for civil calendar dates/times/ranges. Timer measures elapsed/remaining time,
NumberInput a duration and Picker fixed event slots.

`selection = "single"` uses `value`; `range` uses `range` and matching callbacks.
`time` adds hour/minute to a single date. Choose meaningful `minuteStep`, `min`,
`max`, `isDateDisabled` and range `presets`; explain unavailable choices and
alternatives.

`locale`, `hourCycle` and `weekStart` clarify interpretation. Values are not
time-zone-aware instants: the game must define conversion for a shared event
and show the interpreted time before commitment. `style = "inline"` suits a
calendar task; `automatic` a compact field. `draft` adds reversible review.
A custom `format` disables typed entry; use it only when that tradeoff helps.
