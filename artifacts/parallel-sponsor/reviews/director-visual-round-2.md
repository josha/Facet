# Director visual round 2 — pre-packet feedback (2026-07-31, verbatim)

Six findings, all binding. Anchoring rule unchanged: legacy's ACTUAL source
values, cited.

| # | Director's words | Reading |
|---|---|---|
| DV2-1 | "make the background for the racer names more transparent and a more readable font like PS-B3-legacy-max-iphone16-landscape" | Map name tags: background too heavy, font weaker than legacy's. Extract legacy's tag BackgroundTransparency + font/weight from SponsorRacerList tag construction and match |
| DV2-2 | "lap and race drama overlap the sponsor view" (DV-verify-max both orientations) | The chip band still paints over the table plate. Legacy: both chips sit ABOVE the panel. Reserve real space above the table in BOTH orientations |
| DV2-3 | "messages at the bottom are unreadable" (C2 results portrait) | The rivalry/streak lines above the CTAs: too small, too low-contrast. Legacy's results text values apply |
| DV2-4 | "make the race results more opaque; too hard to read over the sponsor view" | NOTE: the cited captures predate fix round 3 (the table behind results is already torn down). The remaining truth: the WORLD still shows through — results gets legacy's heavy dark backdrop opacity |
| DV2-5 | "design of this screen in both landscape and portrait is bad — small text, tons of empty space, not readable over sponsor view" | The results composition is sparse vs legacy's full band structure. Rebuild to legacy's density: role banner, hero, recap, full standings band, sponsors row, points band, promo chips, CTAs — legacy type sizes throughout, no dead bands |
| DV2-6 | "we should hide the roblox leaderboard thing in all modes" | DIRECTOR RULING: CoreGui PlayerList hidden GAME-WIDE (all modes, both presenters). This closes the round-1 open question; it is a shipped-behavior change made on the director's explicit instruction — log in games/RascalRally/docs/DECISIONS.md |
