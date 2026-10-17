# Choices and input

Part of [Designing game interfaces with Facet](../GAME_UI_DESIGN_GUIDE.md). Choose a control from the shape of the value and the cost of changing it. Decide whether a change previews, applies immediately, or remains a draft until commitment. The visible control must tell the same story as the model.

## Choose by value, precision, and commitment

| Need | Start with | Why |
| --- | --- | --- |
| One independent binary state | `Toggle` | Shows the state and changes it directly |
| One or several members of a defined set | `Picker` | Preserves the identity and selection rules of options |
| Typed lookup, optionally accepting new values | `ComboBox` | Combines finding an existing option with text entry |
| A small incremental count | `Stepper` | Each press makes one understandable change |
| An exact number or a wide numeric range | `NumberInput` | Supports precision without excessive repeated presses |
| Continuous feel or an interval | `Slider` | Makes position and relative magnitude visible |
| A short discrete intensity scale | `LevelPicker` | Represents a few meaningful levels |
| A judgment on a rating scale | `Rating` | Expresses evaluation, rather than intensity or quantity |
| An up/down/no-vote judgment | `Vote` | Makes a directional response and its current state clear |
| Free text | `TextInput` | Supports text composition, correction, and validation |
| Arbitrary color | `ColorPicker` | Provides color-specific techniques and preview |
| Calendar date, time, or date range | `DateTimePicker` | Encodes calendar structure rather than a duration |
| An active filter or removable token | `Chip` | Keeps a small selected concept visible and manageable |

Several controls can represent the same number. Volume benefits from continuous exploration; a purchase quantity benefits from precise increments and a clear total. Do not choose a slider merely because the data type is numeric.

## Commit at the right boundary

Apply a reversible setting immediately when the result helps the player judge it: volume, preview lighting, or a local filter. Use a draft when multiple values belong together, experimentation must be reversible, or commitment has consequences. Keep Apply and Cancel close to the draft and show what they affect.

`onChange` and `onCommit` are control events, not universal promises of saved server state. Some controls continuously propose values; some commit on release or focus loss; some add Apply/Cancel only when configured. Map those events deliberately to preview, draft, and accepted state. A rejected request must not leave a success-looking value with no explanation.

Validate at a useful moment. Keep typing fluid when an intermediate string is incomplete. Show constraints before commitment, explain errors beside the field, and retain the attempted value for correction. Disable unrelated repeated submission while pending, but preserve a usable escape or recovery path. Never use a placeholder as the only field label once text has been entered.

## Toggle

Use `Toggle` for an independent on/off value. Choose the visual presentation from its meaning:

- `presentation = "switch"` suggests a setting with an immediate effect, such as vibration.
- `"checkbox"` suits membership, agreement, or a field within a form. For exclusive alternatives, use a single-choice picker instead of mutually exclusive checkboxes.
- `"button"` suits a compact persistent mode, such as a visible filter. Its selected state must be obvious even without color.

Use `label` to name the state positively and unambiguously. Avoid double negatives such as “Disable no-collision warnings.” `mixed` represents differing values across a selected group; define what the next activation will set. Mixed is not a third ordinary choice. `indicatorPosition` should keep related settings aligned. `busy` represents pending application; `enabled` expresses availability. Keep a clear distinction between unchecked, disabled, and unavailable.

## Picker

Use `Picker` for a bounded set of named values. It supports single selection and `multiple = true` with a selected key set. Use a collection when records need rich browsing, comparison, row commands, or bulk management beyond choosing values.

| Style | Choose when | Tradeoff |
| --- | --- | --- |
| `automatic` | The content and input can use Facet's adaptive choice | Inspect the actual result; it never automatically chooses cards |
| `segmented` | A few short peer values benefit from simultaneous visibility | Consumes width; long descriptions and search do not belong in the strip |
| `inline` | Options should be encountered directly in the surrounding form | Uses more page area than a closed picker |
| `radioGroup` | An explicit exclusive choice needs readable labels or explanations | Strong clarity at a vertical-space cost |
| `cards` | Visual identity or a short description helps distinguish consequential options | More space and attention; avoid decoration that obscures comparison |
| `menu` | The current value is sufficient until the player chooses again | Requires opening before alternatives can be inspected |
| `navigationLink` | A compact field should open a more substantial/searchable option list | It opens an anchored adaptive chooser; it is not the page's navigation history |

Use `required` to define whether an empty choice is legal; show a meaningful placeholder when it is. `onChanging` can veto a choice, but explain relevant restrictions before repeated attempts. `onChange` observes the accepted control selection; it does not by itself establish server acceptance.

Use `query` for searchable options in a compatible list/menu style. Do not combine it with `segmented`. `axis = "y"` can make longer options easier to read; horizontal cards can wrap. `sizing = "hug"` suits a compact toolbar value, while `"fill"` can distribute a short set across its allotted area. `valueAlignment` tunes a labeled menu field's title/value arrangement; test wrapping with long current values.

Option descriptions, `meta`, avatars, badges, and status indicators should carry distinguishing information. A badge is useful for a count, not as decoration on every option. `iconOnly` needs familiar symbols and accessible names. Keep selection visible when changing `indicator`; removing all selection paint without an equivalent cue makes a chooser ambiguous. Appearance families depend on style: a segmented strip's `filled`/`stroke` treatment is not a universal option for radio groups or cards.

## ComboBox

Use `ComboBox` when typing is a useful way to find a known value, and possibly to create a new one. A car model selector should normally reject arbitrary text; a saved-build tag editor may accept new tags.

Set `acceptCustom` deliberately. Keep `text` (what the player is typing) distinct from `value` (the selected/accepted option). A typed substring is not automatically a valid selected record. `commitOnFocusLost` is appropriate only when losing focus can safely accept the current content; otherwise require explicit commitment. Show no-results, invalid custom value, and loading states without discarding the query. Use a searchable `Picker` when the player must choose from known options and freeform entry would imply a capability the game lacks.

## TextInput

Use `TextInput` for names, search terms, messages, and other free text. `presentation = "search"` communicates finding content; `"plain"` is ordinary entry; use `NumberInput` for a dedicated numeric field.

Use a persistent `label`, optional `hint`, and `errorText`/`invalid` for field state. `placeholder` can show an example, not a necessary instruction that disappears while typing. `maxLength` should express a real limit and leave space to explain it. Its `validate` callback accepts/transforms text or returns nil to reject it; this is different from `CellEditor.validate`, which returns an error message. Do not substitute one validation contract for the other.

Use `multiline` for content that may span paragraphs. `visibleLines` creates a bounded field that scrolls; without it, multiline content grows. Choose based on whether the player needs to read the whole draft while editing. Ensure the on-screen keyboard does not hide the field, error, or Send/Save action.

`onChange` handles edits; `onCommit` distinguishes submit and focus loss. Sending a message should require the intended Send/submit action, not an incidental blur. `onCancel` supports abandoning the edit. Set `selectOnFocus = "all"` for replaceable short values, `"end"` for appending, or `"none"` for normal caret behavior. `readOnly` preserves readable/selectable content without presenting it as disabled. `clearButtonMode` should match the task; clearing a search is useful, accidentally clearing a long composition is costly.

## NumberInput

Use `NumberInput` when exact numeric entry matters, the range is broad, or repeated stepping would be slow. Show units through `prefix`/`suffix` or the label, not only in a disappearing hint.

Set `min`, `max`, `step`, and `precision` to the game's valid values. `parse` and `format` must agree about units and accepted notation. Preserve a meaningful distinction between an empty field and zero. If commitment clamps a value, show the resulting value and explain a surprising limit.

`stepButtons` adds small adjustments around the entered value. `scrub` supports a precise pointer gesture, but typed or button access should remain available. Use `onCommit` for an intended edit boundary, recognizing submit, focus loss, and clamping; do not attach a purchase to every focus loss. `readOnly`, `selectOnFocus`, error text, and pending behavior should follow the same field principles as text input.

## Stepper

Use `Stepper` for a modest discrete quantity where plus/minus is easier than opening text input: laps, local preview quantity, or a short count. Use `NumberInput` when the player may need to jump from 1 to 200.

Set `min`, `max`, and `step` to useful increments. `format` should make the resulting value intelligible, including units or singular/plural where needed. Set `repeatDelay`/`repeatInterval` only when holding to adjust is safe and predictable. Keep the total cost visible when a stepper changes a purchase quantity; adjustment should preview the transaction, not buy repeatedly.

## Slider

Use `Slider` for relative magnitude, continuous feel, or a selectable interval. Use an exact field or stepper when precision is the main task.

`value` represents one value; `range` represents two endpoints. Set `min`/`max` from useful bounds and `step` when discrete values are meaningful. `minGap` prevents an invalid interval. Show the current value or a meaningful label through `format`; an unlabeled track cannot explain its scale.

Use `onChange` for preview and `onCommit` for a final gesture result when those differ. `tapToPosition` speeds choosing a point but can produce larger accidental jumps; turn it off when that risk outweighs speed. `axis = "y"` should follow a genuine vertical metaphor or available layout, not novelty. Keep the `thumb` visible when adjustment must be discoverable; `"none"` needs another clear interaction cue. `contained` and custom track/thumb visuals must preserve focus, range, and hit-target clarity. Provide a precise alternative if the game requires precision beyond the gesture.

## LevelPicker

Use `LevelPicker` for a short ordered intensity scale such as low-to-high effect strength. Use a `Picker` if the levels need distinct explanations, and a `Rating` if the player is evaluating quality.

Choose `count` from meaningful distinctions. `allowZero` is correct only if zero has a real meaning such as Off. `segment = "bar"`, `"glyph"`, or `"image"` should reinforce the scale; custom glyphs must still show order and selected amount. `segmentSize` preserves readable, reachable steps. Use `readOnly` for a displayed level and `onChange` for an editable value; do not make a stat look adjustable when it is only informational.

## Rating

Use `Rating` for evaluation on an ordered star-like scale, not currency, power, or difficulty simply because stars look appealing. `count` defines the scale; `allowZero` defines whether no rating/zero is possible. Distinguish an unrated state from a poor rating in accompanying text.

Use `readOnly` for an aggregate or an existing score, with a textual summary where context matters. Use `onChange` for the player's own evaluation. Choose `starSize` for the input and viewing distance. Avoid placing a displayed aggregate immediately beside an editable rating with identical appearance and no ownership labels.

## Vote

Use `Vote` for an up/down/none response, such as whether a community course was helpful. It is not a substitute for choosing among several maps.

`value` and `onChange` represent the player's response; `summary` describes the aggregate separately. `readOnly` shows results without inviting input; `enabled = false` communicates a temporarily unavailable action. Make it clear whether selecting the current vote removes it and whether changing a vote replaces the earlier one. Show pending/rejected submission honestly through surrounding state.

## Chip

Use `Chip` for a small selected concept: active filters, tags, party members in a recipient list, or removable options. Use `Badge` for a noninteractive annotation, and a normal button for an unrelated verb.

Choose whether the chip toggles (`selected`, `onToggle`) or removes (`onRemove`). A chip supporting both requires an explicit `editing` state: outside editing, activation selects; while editing, activation removes. A removal-only chip is always in edit mode. The Remove mark is part of the one chip button, not a separate target. Make this mode change clear rather than implying that the body still selects beside an independent close button. Give `removeLabel` the object name, such as “Remove Drift filter.” `removeFocusFallback` should leave focus in a useful place after removal. `leading`/`trailing` content should clarify the token without crowding it. Let chip groups wrap or use another summary rather than narrowing every chip into an unreadable fragment.

## ColorPicker

Use `ColorPicker` for choosing arbitrary colors. A few named team colors usually need a `Picker`; a fixed color palette can use `modes = { "swatches" }`.

Choose `modes` to match the task: swatches for repeatable choices, spectrum for exploration, sliders for adjustment, and brick for the supported named-color set. Do not expose every technique if the game's paint system only accepts a fixed palette. Label custom swatches and define save/remove behavior through `onSaveSwatch`/`onRemoveSwatch`.

`style = "automatic"` uses a compact well opening a panel; `"inline"` suits a dedicated color-editing area. `draft` adds Apply/Cancel when experimentation should be reversible. Use `onChange` for preview and `onCommit` for the end of a gesture; Apply is the relevant boundary for a draft transaction. Expose `alpha` only when opacity is actually supported. `allowEmpty` needs a meaningful absence state, such as inherited color, rather than an unexplained blank.

Preview the color on the actual material and under representative lighting. Color alone must not communicate team, rarity, eligibility, or selection. Provide those meanings separately.

## DateTimePicker

Use `DateTimePicker` for calendar dates, event dates/times, and date ranges. Use `Timer` for elapsed/remaining time, `NumberInput` for a duration, and `Picker` for a few fixed event slots.

Choose `selection = "single"` with `value` or `"range"` with `range`; keep their callbacks consistent with that mode. `time` is for a single date with hour/minute. `minuteStep` should reflect schedulable increments. `min`, `max`, and `isDateDisabled` should show genuine availability, and range `presets` can accelerate common reporting periods.

`locale`, `hourCycle`, and `weekStart` should make dates unambiguous. These are civil date values, not time-zone-aware instants. A shared multiplayer event needs an explicitly defined time zone and conversion in the game model; the picker does not establish that policy. Show the interpreted event time before commitment.

Use `style = "inline"` for a calendar-centered task and `"automatic"` for a compact field. `draft` adds a reversible selection stage. A custom `format` changes the field wording and disables typed entry; use it only when that tradeoff helps. Keep an unavailable date's reason and a valid alternative discoverable.
