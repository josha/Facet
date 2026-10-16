# Picker.requiredMark

Picker.requiredMark option values and behavior.

- `requiredMark`, `hint` and `errorText`: as on [TextInput](Field-chrome.md). The
  message line shows under the picker in each style. An error adds the
  `facet-invalid` tag to a menu trigger. The picker does not move.
- `controlSize`: the height of the menu trigger, the segmented track and the
  rows. A horizontal segmented track is one control height tall. Each segment
  fills the track inside a 3 pixel inset on all sides. The corner radius of a
  segment is the track radius minus the inset.
- `appearance`: for `menu` and `navigationLink`, `standard`, `contrast` (the
  emphasis plate) or `utility`. For `segmented`, `filled` (the default plate),
  `stroke` (the `facet-segmented-stroke` tag) or `utility` (no plate).
  `automatic` takes all five words and maps them onto the style on screen.
  `inline`, `radioGroup` and `cards` refuse `appearance`. A readable word that
  is not in the family causes an error, and the last correct paint stays.
- `corners`: `pill` or `square`, on the menu trigger or the segmented strip. A segmented strip's segments and its selection highlight take the same corners.
- `maxHeight`: for `menu`, `navigationLink` and `automatic`, a finite number of
  pixels above zero. It caps the open panel. The panel always shows one row.
- `valueAlignment`: `end` (the default) or `start`, for a labelled `menu`.
  `end` shows the title above the trigger. `start` shows the title and the
  trigger on one row, with the trigger right after the title. The row is a
  horizontal UIListLayout with `Wraps`, so the trigger moves below the title
  only when the pair does not fit, for example at a large player text size.
  With `sizing = "hug"` the row hugs the pair, which suits a toolbar setting.
  The trigger hugs its value on each input, touch included.
- `indicatorPosition`: for `radioGroup` only, `leading` (the default) or
  `trailing`. It puts the radio mark in its own slot on that edge of the
  content row of each option. The label is next to the mark and does not go
  under it.
