# Ticket: make my kart look like mine

Start from the previous turn's completed workspace (`hub-race-scoreboard`). Keep every earlier feature and the same visual identity. Add Livery to the hub. I want to choose body and accent colors from labeled palette swatches, adjust shade, and choose one of six decals in a grid. Show a live car preview as I edit. Keep the preview, controls, and Save or Revert reachable on a phone.

Use Red, Amber, Green, Cyan, Blue, and Violet (hues 0, 60, 120, 180, 240, and 300 degrees). Shade supports at least 50%, 75%, and 100%. Use the decal names from the supplied catalog. Show a readable summary `Preview: Body DEGREES Accent DEGREES Shade PERCENT DECAL` and mark Unsaved changes. The visual car must change too.

Save applies the draft and shows Saved only after success. Reopen with the saved design. Revert and leaving with unsaved changes ask `Discard unsaved changes?` with Discard and Cancel. Cancel keeps the draft. Discard restores the saved design; when leaving, it also returns to the hub. Clean Close returns at once. On console B follows the same rules and restores selection.

The game team supplies `src/shared/Extended.luau` in this turn. Use `Extended.client()` for `get`, `request(action, value)`, `onChanged`, and `now`. `request("livery", { body, accent, shade, decal })` accepts hue fractions from 0 to 1 and a shade fraction from 0 to 1. The server owns the saved design. Do not change the supplied server or shared files. Other systems in this contract are for later turns.

All actions must work with mouse, touch, and console selection. Keep theme and device settings available. Keep all previous behavior.

## Design direction

Use a sci-fi neon identity with dark panels, cyan and violet accents, and readable pale text. Keep the world visible around the HUD.
