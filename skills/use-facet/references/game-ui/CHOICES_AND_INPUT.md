# Choices and input

Part of [game UI design](../GAME_UI_DESIGN_GUIDE.md).

A choice is understandable when the player can see the alternatives, the current value and the effect before acting.  Choose the control by meaning, precision and commitment.  Then adapt its presentation to the room and the input.

## Expose the decision

| Decision | Control |
| --- | --- |
| An independent on or off | Toggle |
| One value from a known set, searchable if needed | Picker |
| A searchable choice that permits custom values | ComboBox |
| Text or a precise number | TextInput or NumberInput |
| A bounded range | Slider |
| Exact increments | Stepper |
| A discrete amount or a rating | LevelPicker or Rating |
| A compact filter or a removable selection | Chip |
| A color that needs inspection | ColorPicker |
| An instant or an interval | DateTimePicker |

Prefer recognition to recall: show named alternatives when comparison matters.  Tabs navigate; they never edit a value.  A Button runs a command.  A command that cycles through hidden values prevents comparison and correction.  Shared voting and personal settings have different authority and different feedback needs.

Facet: Picker's automatic style follows the room, the labels and the input.  Set an explicit style when the decision needs it: `radioGroup` keeps explanations visible, and `cards` shows meaningful visual alternatives.  The automatic style never selects `cards`.  Use Picker's `query` for a searchable known set; ComboBox needs separate accepted `value`, editable `text` and an `acceptCustom` policy.  Use ColorPicker for a color space; a few named colors can use a Picker.

## Make adjustment understandable

Keep the label, current value, units, limits and error together.  A Slider shows a readable value and offers digital steps for gamepad and precise adjustment.  A color choice shows its swatch and its name.  The displayed number and the parser agree on units and precision.

Explain what a setting changes, and preview its effect where the effect is otherwise unclear.  Offer a clear way back to the previous or default value.  Do not require text entry when visible choices or steps serve the task better.  A placeholder is an example or a format hint, never the only label.

Facet: fields keep `label`, `hint` and `errorText` visible while the player types.  Slider's `step` and `onCommit` support bounded adjustment and the end of a gesture.  Stepper supplies exact increments.  NumberInput keeps the editable `value` and the committed `numericValue` in separate cells, and `stepButtons` adds visible increment and decrement actions.  Match `parse`, `format`, bounds and precision to the value the game accepts.

## Separate editing from acceptance

A reversible setting can preview at once.  Coupled edits share one draft and one explicit commitment.  Never purchase on an incidental blur.  Distinguish pending work from accepted state, and keep rejected input available for correction.  When an accepted value arrives during an edit, keep the draft and show that the saved value changed.

Text input yields to native editing and IME.  Define submit, cancel and validation from the task.  A passing validation is not a server save.

Facet:

- TextInput's `onCommit` can run for `submit` or `focusLost`; it does not mean the server saved the value.  Its `validate` returns accepted text, or nil to reject.
- CellEditor's validator returns an error message or nil, and its model callback owns acceptance.  Use its external `draft` for record edits that must survive recycling and conflicts.
- ColorPicker and DateTimePicker offer `draft = true` for Apply and Cancel.  Their `onChange` callbacks propose values, and their commit callbacks follow each control's documented rules.  Do not infer one control's save or cancel contract from another's.
- Keep a draft in the game's model when several fields share one accepted result.

## Check

Adjust each value with touch, pointer and gamepad.  Test long localized labels, invalid and empty values, cancellation, delayed acceptance and reopening.  Open the on-screen keyboard in the shortest supported layout: the active field, its error and the route to submit or cancel stay usable.  Change the input during an edit without losing the draft.  A displayed control or a changed label does not prove the effect.

Read `Picker.selected`, `Picker.menu`, `TextInput.reference`, `NumberInput.reference`, `Stepper-and-Slider.value` and `CellEditor.draft` for exact field behavior.  Read `Tasks.state` for game authority and `Sheet.dismissal` when an edit can leave through several routes.
