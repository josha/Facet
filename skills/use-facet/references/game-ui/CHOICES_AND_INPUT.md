# Choices and input

Part of [game UI design](../GAME_UI_DESIGN_GUIDE.md).

## Expose the decision

Make the available choices, current value and effect understandable before
the player acts. Prefer recognition over recall: show named alternatives when
comparison matters. Choose by meaning, precision and commitment, then adapt
the presentation to the room and input.

| Decision | Control |
| --- | --- |
| Independent boolean | Toggle |
| One value from a known set, with search if needed | Picker |
| Searchable choice with permitted custom values | ComboBox |
| Text or a precise number | TextInput or NumberInput |
| A bounded range | Slider |
| Exact increments | Stepper |
| A discrete amount or rating | LevelPicker or Rating |
| Compact filter or removable selection | Chip |
| Color with inspection | ColorPicker |
| An instant or interval | DateTimePicker |

Tabs navigate; they do not edit a value. A Button performs a command. Shared
voting and personal settings have different authority and feedback needs.
Do not use a command that cycles through hidden values when the player needs
to compare or correct a choice.

Picker's automatic style uses the available room, labels and input. Set an
explicit style when the decision needs it: `radioGroup` keeps explanations
visible, and `cards` can show meaningful visual alternatives. Automatic does
not select `cards`. Use Picker's `query` for a searchable known set; ComboBox
requires separate accepted `value`, editable `text` and `acceptCustom` policy.
Use ColorPicker for a color space; a few named colors can use Picker.
A horizontal `segmented` strip stays on one row and scrolls when it does not
fit. To show a menu on a narrow screen instead, use
`ViewThatFits { segmentedPicker, menuPicker }`.

## Make adjustment understandable

Keep the label, current value, units, limits and error together. Sliders need
readable values and digital steps for gamepad or precise adjustment. Color
choices need visible swatches and names. Displayed numbers and parsing must
agree on units and precision.

Use field `label`, `hint` and `errorText` to retain the explanation while the
player types. A placeholder is an example or format hint, not the only label.
Explain what a setting changes and show a useful preview where its effect is
otherwise unclear. Offer a clear way to restore a previous or default value.
Do not require text entry when visible choices or steps serve the task better.

Slider's `step` and `onCommit` support bounded adjustment and the end of a
gesture. Stepper supplies exact increments. NumberInput keeps editable `value`
and committed `numericValue` in separate cells; `stepButtons` provides visible
increment and decrement actions. Match `parse`, `format`, bounds and precision
to the value the game actually accepts.

## Separate editing from acceptance

Reversible settings can preview immediately. Coupled edits need one draft and
an explicit commitment. Never purchase on incidental blur. Distinguish pending
work from accepted state; keep rejected input available for correction.
Incoming accepted values must not silently overwrite an active draft.

Text input must yield to native editing and IME. Define submit, cancel and
validation behavior from the task. TextInput's `onCommit` can run for `submit`
or `focusLost`; it does not mean the server saved the value. Its `validate`
returns accepted text or nil to reject. CellEditor's validator instead returns
an error message or nil, and its model callback owns acceptance. Use its
external `draft` for record edits that must survive recycling and conflicts.

ColorPicker and DateTimePicker offer `draft = true` for Apply and Cancel.
Their `onChange` callbacks propose values; their commit callbacks follow the
control's documented rules. Do not infer one control's save or cancellation
contract from another. Keep a draft in the game's model when several fields
share one accepted result.

## Verify the effect

Test touch, pointer and gamepad adjustment, long localized labels, invalid and
empty values, cancellation, delayed acceptance and reopening. A displayed
control or a changed label does not prove its effect.

Also open the native keyboard in the shortest supported layout. The active
field, its error and the route to submit or cancel must remain usable. Check
an input change during an edit without losing the player's draft.

Read `Picker.selected`, `Picker.menu`, `TextInput.reference`,
`NumberInput.reference`, `Stepper-and-Slider.value` and `CellEditor.draft`
for exact field behavior. Read `Tasks.state` for game authority and
`Sheet.dismissal` when the edit can leave through several routes.
