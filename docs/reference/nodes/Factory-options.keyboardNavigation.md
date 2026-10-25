# Factory-options.keyboardNavigation

Factory-options.keyboardNavigation option values and behavior.

- `keyboardNavigation`: `true` (the default) binds Tab traversal and Space
  next to Return on a selected Button. `false` binds neither: Return still
  activates. Use `false` for an app whose keys belong to the game (see
  [Selection](Selection.md) and [responder](responder.md)).
- `translator`: a native `Translator` or a readable of one, for example from
  `LocalizationService:GetTranslatorForPlayerAsync(player)`. Facet localizes
  with the Roblox mechanism:
  - A fixed string that a control shows, such as `Close`, `Back` or `Clear`,
    and every string that you pass, is the `Text` of a native label with
    `AutoLocalize` on. The engine translates it from your experience's
    `LocalizationTable` (and its automatic text capture).
  - A string that Facet assembles from values uses
    `Translator:FormatByKey` with the keys below. Add these keys to your
    `LocalizationTable`. Without a translator, or when a key is missing, Facet
    uses the English source.


    | Key | English source |
    |---|---|
    | `Facet.Page` | `Page {current}` |
    | `Facet.PageOf` | `Page {current} of {count}` |
    | `Facet.IndexOf` | `{current} of {count}` |
    | `Facet.StepOf` | `Step {current} of {count} — {label}` |
    | `Facet.RemoveItem` | `Remove {item}` |
    | `Facet.RangeThumb` | `{range} {thumb}` |

  - Assemble your own strings with values in the same way:
    `translator:FormatByKey(key, args)` in a readable. Do not join
    translated parts with `..`: word order changes between languages. Set
    `AutoLocalize = false` on a label that shows a player name or other text
    that players write.
  - Keep the game's English source in one keyed table that builds its
    `LocalizationTable`. Get every player-facing string from a key, fixed
    labels too. Check that each code key exists in the table. Call
    `FormatByKey` in a readable and pass string arguments, such as
    `tostring(count)`. Set `AutoLocalize = false` for already translated text.
    Reuse this translator and source table across task components.
- `buttonGuides`: a boolean or a readable boolean, `true` by default. `false`
  hides every [ButtonGuide](ButtonGuide.reference.md). Bind one player
  settings Toggle to it.
- `gameplay`: `{ contexts = { InputContext }?, controls = { GuiObject }? }`,
  the game's gameplay input. While a NavigationStack path is nonempty or a
  Sheet is presented, Facet sets each context's `Enabled` and each control's
  `Visible` to `false` and turns off `GuiService.TouchControlsEnabled`. When
  the last of them closes, Facet restores the prior values. See
  [Tasks.pages](Tasks.pages.md).
- `services`, `guiService`, `userInputService` and `types`: native dependencies.
- `inputParent` and `overlayParent`: placement targets. Presented controls
  mount inside `overlayParent` when you set it. They measure its live bounds
  for placement and size, including color and date pickers, menus, dialogs,
  sheets, popovers, callouts and help plates.
