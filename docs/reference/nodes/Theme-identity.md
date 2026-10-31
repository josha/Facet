# Theme-identity

Turn the brief's art direction into a readable theme. The examples below are
conditional design choices, not required colors, type sizes or surface treatments.

- Map the art direction to roles. A brief such as "dark metal, cyan and
  violet neon" becomes a dark `surface`, a cyan `accent`, a violet
  `controlSelected` and a cyan `hairline`. Give `controlHover` and
  `controlPressed` the hue of `control`. An extra that you omit keeps the
  blue-gray value of the dark Neutral palette.
- Keep text and controls readable against their actual backgrounds. Dark and
  light themes need different contrast relationships; a backing plate can help
  over a changing scene. Check focus, selection, disabled and error states too.
- Use legible fonts and a scale suited to the content and viewing distance.
  Resolution alone does not establish physical readability. Check clocks and numbers in the chosen font: some display fonts
  draw a colon so thin that "24:51" reads as "2451" at small sizes. Wide display
  fonts can also make ordinary captions compete with headings and force short
  labels to wrap. Start with the base readable family; express character
  through the palette, icons and surface treatment before changing all text.
- Set `font.family` for each typography role. A `body` override does not
  change all roles. The recipe patches the base font tables and keeps their
  weight, style and line height. `strong` derives from an authored `body`, and
  `numeral` from an authored `control`, unless you set those roles too.
- Use `strong` for an item name, `caption` for supporting facts and `numeral`
  for an important balance, cost or reward. Give the name, cost and current
  state distinct places. Avoid one caption that combines category, price,
  description and ownership with equal weight. Check headings, main values
  and captions together with long translated text over the game world.
- Keep selection, ownership and purchase emphasis distinct. A quiet Owned
  state must not compete with Buy. Preserve the words as well as any color
  difference. Use stable icons or category marks when they help identify items.
- Choose a surface from the task's relationship to play, input ownership and
  space needs. A [page](Tasks.pages.md) can replace the play view; a Sheet can
  hold a modal task. Task duration alone does not decide the surface. Allow
  enough room for comparison, reading and accessible controls.
- Use quiet boundaries when they help separate items from their container.
  Reserve strong outlines for the current selection or action; equal bright
  strokes on every nested panel erase that hierarchy.
- Use elevation consistently to express relationships. `chrome.panel.shadow`
  and `chrome.control.shadow` can differ when panels and controls have different
  roles. Flat surfaces can also work; judge separation in the actual task.
- `rules` add native StyleSheet rules. `{ role = "accent" }` and
  `{ metric = "..." }` follow palette and distance changes.
- Check `report` before you pass the package to the app.

Back to [Tasks.theme](Tasks.theme.md).
