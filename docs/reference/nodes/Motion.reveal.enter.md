# Motion.reveal.enter

Motion.reveal.enter option values and behavior.

| Control | Enter | Exit |
|---|---|---|
| Notice | The height opens from 0, 0.25 seconds (`reveal.enter`), Cubic Out. | After a press on its close button, the height closes to 0 in 0.2 seconds (`reveal.exit`). Then `onDismiss` runs. |

| Control | Enter | Exit |
|---|---|---|
| RadialMenu | The ring spreads out from its centre, starting at 20 percent of its radius (`materialize.radialSpread`), and fades in, 0.2 seconds (`radial.enter`), Cubic Out. | The reverse: the ring folds back into its centre as it fades out, 0.12 seconds (`radial.exit`). |

| Control | Enter | Exit |
|---|---|---|
| RadialMenu slot | A slot that enters an open ring fades in, 0.16 seconds (`radial.slot`). A slot of a submenu unfolds from the chosen item: it starts at that item's angle and ring band and sweeps along the ring to its own angle, its wedge growing from the theme's `motion.unfoldStart` of its arc (a quarter by default, Cubic Out). Other slots move from 30 percent (`materialize.branch`) of the distance toward the center to their positions. Back folds the level into its item and re-opens the parent around it: each parent slot starts at that item's angle and band and sweeps to its place. A ring that opens again starts from the centre. Reduced motion places the slot at once. | The slot fades out, 0.12 seconds (`radial.exit`). A submenu slot left by Back folds along the ring into the item it came from as it fades. |

| Control | Enter | Exit |
|---|---|---|
| NavBar | No motion. | No motion. |
