# Director visual round 5 (2026-07-31, verbatim)

"S16v2-results-sponsor-iphone16-landscape is still bad. what about a layout
like this: 1. spanning the width below the 'next race' line, let's have 0
passes created and all that. then in the left column, 'hot streak' and 'Rhoda
Rhino is on the grid'. In the middle column, scrolling results list. on the
right, just the sponsor a race and race buttons. we should also change the
button labels to reflect your last role. like here they should be 'Sponsor
Again' and 'Race'. If you were driving, they should be 'Race Again' and
'Sponsor a Race'. in the results screen, we might want to animate the points
increasing rather than just showing a '+10'. maybe something like '+10'
appearing bigger/more featured, animating onto the counter, then the counter
animating up that amount. basically reward earning points."

| # | Item | Disposition |
|---|---|---|
| DV5-1 | Landscape layout, DIRECTED: masthead ("Next race in") → **recap line SPANNING the full width** → three columns: LEFT = streak + rivalry callout (+ hero/celebration when present, above them — the director's sketch is the quiet-sponsor case), MIDDLE = the scrolling results list, RIGHT = the two CTAs only | Requires the **spanning-row capability** flagged as UI.Composition's one contract gap last round — build it as public framework API first (the director's layout is its proof case), then re-declare the screen |
| DV5-2 | CTA labels reflect the LAST role: post-sponsor = "Sponsor Again" + "Race"; post-racer = "Race Again" + "Sponsor a Race" | NEW COPY authorized by the director (two new strings, localized additively; emphasis still follows the selected role per SponsorResults:855-857). Log in DECISIONS |
| DV5-3 | Animate earning points: the "+N" appears featured/bigger, animates ONTO the counter, the counter counts UP by that amount — "basically reward earning points" | Economy-piece PRESENTATION change (the celebration schedule/read-floors unchanged): declared reward beat via LuauUI motion (value chase driving the numeral + an object-class flight of the "+N" to the counter). RM: final value instant + static "+N" (information preserved). Any missing framework value-counter primitive → framework row first |
