# Theme-identity

Turn the art direction of a game into a theme that reads over its world.

- Map the art direction to roles. A brief such as "dark metal, cyan and
  violet neon" becomes a dark `surface`, a cyan `accent`, a violet
  `controlSelected` and a cyan `hairline`. Give `controlHover` and
  `controlPressed` the hue of `control`. An extra that you omit keeps the
  blue-gray value of the dark Neutral palette.
- Keep plates visible over the scene: `control` and `surfaceStrong` must be
  clearly lighter than a dark world, and `content` pale. Faint text and plates
  that vanish into the scene read as unfinished.
- Use a legible font family and a few sizes. At 1080p, keep body text at 18 or
  more, captions and HUD labels at 15 or more, and HUD numbers at 20 or more.
  Smaller text reads as unfinished on a TV and is hard to read on a phone. Check clocks and numbers in the chosen font: some display fonts
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
- Choose a surface for the task. Give recurring destinations a readable
  [page](Tasks.pages.md), with art and comparison space. Use a content-sized
  Sheet for a short interruption. A large empty panel makes a small decision
  harder to scan; a small scrolling window hides a collection's useful choices.
- Use quiet boundaries when they help separate items from their container.
  Reserve strong outlines for the current selection or action; equal bright
  strokes on every nested panel erase that hierarchy.
- Choose elevation for the whole theme, not per element. Neutral plates are
  flat. When `chrome.panel.shadow` lifts panels, give `chrome.control.shadow` a
  matching shadow, or keep both flat and separate plates by value. A shadow on
  panels but not on the Buttons beside them reads as an error.
- `rules` add native StyleSheet rules. `{ role = "accent" }` and
  `{ metric = "..." }` follow palette and distance changes.
- Check `report` before you pass the package to the app.

Back to [Tasks.theme](Tasks.theme.md).
