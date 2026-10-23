# Choices and input

Part of [game UI design](../GAME_UI_DESIGN_GUIDE.md).

| Decision | Control |
| --- | --- |
| Independent boolean | Toggle |
| One value from a known set | Picker |
| Searchable choice with permitted custom values | ComboBox |
| Text or a precise number | TextInput or NumberInput |
| A bounded range | Slider |
| Exact increments | Stepper |
| A discrete amount or rating | LevelPicker or Rating |
| Compact filter or removable selection | Chip |
| Color with inspection | ColorPicker |
| An instant or interval | DateTimePicker |

Choose by meaning, precision and commitment. Tabs navigate; they do not edit
a value. A Button performs a command. Shared voting and personal settings have
different authority and feedback needs.

Keep the label, current value, units, limits and error together. Sliders need
readable values and digital steps for gamepad or precise adjustment. Color
choices need visible swatches and names. Displayed numbers and parsing must
agree on units and precision.

Reversible settings can preview immediately. Coupled edits need one draft and
an explicit commitment. Never purchase on incidental blur. Distinguish pending
work from accepted state; keep rejected input available for correction.
Incoming accepted values must not silently overwrite an active draft.

Text input must yield to native editing and IME. Define submit, cancel and
validation behavior from the task. A validation result is not a server save.
Consult TextInput and CellEditor contracts separately; their validation
callbacks are not interchangeable.

Test touch, pointer and gamepad adjustment, long localized labels, invalid and
empty values, cancellation, delayed acceptance and reopening. A displayed
control or a changed label does not prove its effect.
