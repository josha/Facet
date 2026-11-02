# Types.ToggleCellProps

Types.ToggleCellProps option values and behavior.

- The binding shapes of each binding control, for example
  `ToggleCellProps`, `ToggleRequestProps`, `TextInputCellProps`,
  `TextInputRequestProps`, `TextInputNumberCellProps`,
  `TextInputNumberRequestProps`, `NumberInputCellProps`,
  `NumberInputRequestProps`, `StepperCellProps`, `StepperRequestProps`,
  `SliderCellProps`, `SliderRequestProps`, `SliderRangeProps`,
  `RatingCellProps`, `RatingRequestProps`, `RatingReadOnlyProps`,
  `LevelPickerCellProps`, `LevelPickerRequestProps`,
  `LevelPickerReadOnlyProps`, `ChipCellProps`, `ChipRequestProps`,
  `ChipRemovableProps`, `ShortcutHintKeysProps` and
  `ShortcutHintActionProps`.
- The spec shapes `SinglePickerSpec`, `MultiplePickerSpec`,
  `KeyedOutlineSpec`, `IdentityOutlineSpec` and `FocusControls`.
- The action and overlay parts `DialogAction`, `ActionRole`, `ToastAction`,
  `CardAction`, `CardMenu`, `CardBadge`, `CardBadges`, `PopoverSource`,
  `OverlayRect` and `CollectionPlacement`.
- The value types `ButtonRole`, `TextCommitReason`, `CommitReason`,
  `ClearButtonMode`, `ControlSize`, `Status`, `TextRole`, `Presence`,
  `ImageScaleMode`, `ImageLoader`, `VoteValue`, `StepState`,
  `PaginationForm`, `TabPlacement`, `TabSelectionIndicator`,
  `NoticeSeverity`, `ColorSwatch`, `ColorPickerMode` and `DateRangePreset`.
- The dismiss reasons `DialogDismissReason`, `PopoverDismissReason`,
  `ToastDismissReason`, `ColorPickerDismissReason` and
  `DateTimePickerDismissReason`.
- The theme definition types `ThemeDefinition`, `PalettePatch`,
  `PaletteExtra` and `TypographyPatch`.

Give option arrays an explicit item type when their union or generic type is
ambiguous. This applies to `actions`, `items`, `options`, `tabs`, `steps` and
`detents`. The root module exports each item type:

| Option | Item type |
| --- | --- |
| `Dialog` `actions` | `DialogAction` |
| `Sheet`, `Popover` and `Notice` `actions` | `OverlayAction` |
| `Alert` `actions` | `AlertAction` |
| `RowActions` `leading` and `trailing` | `RowAction` |
| `Menu` and `SplitButton` `items` | `MenuItem` |
| `RadialMenu` `items` | `RadialItem` |
| `Picker` `options` | `PickerOption` |
| `TabView` `tabs` and `PageView` `pages` | `Tab` |
| `StepIndicator` `steps` | `Step` |
| `Table` `columns` | `TableColumn` |
| `Sheet` `detents` | `SheetDetent` |
| `ColorPicker` `swatches` | `ColorSwatch` |
