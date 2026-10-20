# Theme-identity

Turn the art direction of a game into a theme that reads over its world.

- Map the art direction to roles. A brief such as "dark metal, cyan and
  violet neon" becomes a dark `surface`, a cyan `accent`, a violet
  `controlSelected` and a cyan `hairline`.
- Keep plates visible over the scene: `control` and `surfaceStrong` must be
  clearly lighter than a dark world, and `content` pale. Faint text and plates
  that vanish into the scene read as unfinished.
- Use one font family and a few sizes. At 1080p, keep body text at 18 or
  more, captions and HUD labels at 15 or more, and HUD numbers at 20 or more.
  Smaller text reads as unfinished on a TV and is hard to read on a phone. Check clocks and numbers in the chosen font: some display fonts
  draw a colon so thin that "24:51" reads as "2451" at small sizes.
- Set `font.family` for each typography role. A `body` override does not
  change all roles. The recipe patches the base font tables and keeps their
  weight, style and line height. `strong` derives from an authored `body`, and
  `numeral` from an authored `control`, unless you set those roles too.
- Use `label` for item names, `caption` for supporting facts and `numeral`
  for important balances or rewards. Check headings, main values and captions
  together with long translated text over the game world.
- Stroke at most the outer frame of a large panel, such as a Sheet. A stroke
  on every card or panel inside it reads as noise.
- `rules` add native StyleSheet rules. `{ role = "accent" }` and
  `{ metric = "..." }` follow palette and distance changes.
- Check `report` before you pass the package to the app.

Back to [Tasks.theme](Tasks.theme.md).
