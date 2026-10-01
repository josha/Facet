# Touch labels and Outpost verification

## Changes

The Outpost world terminal uses the live space below its commands. Its surface canvas follows that space, and a short canvas scrolls its power controls. The camera fit uses native `ScreenPointToRay` or `ViewportPointToRay` to account for the host ScreenGui inset and the engine projection. Leaving the world restores the camera frame, type, focus, field of view and field-of-view mode.

Radial names and long-press Help use the actual held contact. Shared placement prefers the space above the fingertip, then beside or below it inside the safe area. Radial names use the existing tooltip style rules without an arrow. Native `AutomaticSize`, `UISizeConstraint` and wrapping fit the full name. Measurement reuses the existing layout unit instead of adding a measuring child inside the automatically sized label.

The opening radial contact does not choose an item. A launcher drag must cross the existing 14-pixel threshold before it aims; returning to the center after a drag still cancels. Touch does not borrow mouse hover to choose an item.

## Native API and Compose check

Checked Roblox Camera projection, `FieldOfViewMode`, `ViewportSize`, `GuiObject.AutomaticSize` and `UISizeConstraint`. These native APIs handle the surface projection and text measurement. Compose cells, formulas, watches and cleanup own the responsive values and release camera and input state. The existing overlay placement solver handles safe-area fallback; the new shared touch helper adds only the fingertip clearance policy. No vendor changes or new dependency are needed.

## Live Studio evidence

Used a separate rebuilt Showcase place with a phone preset and the Showcase device setting left on automatic. The camera viewport was 401 by 777 in portrait and 749 by 361 in landscape.

- Portrait: the world terminal fits below Back and Power controls, with its title, power rows, Apply and Reset visible.
- Rotation to landscape and back: the surface changes its canvas and camera fit without leaving world mode. The shorter landscape surface has a native scrolling control area.
- Opening Quick actions by touch: no radial candidate and no visible selection plate during the opening contact, including a hold longer than the name delay and small touch movements.
- Holding Workshop: the full word fits (`TextFits = true`), in a 60 by 24 plate. Its bottom is 52 logical pixels above the held contact.
- Neutral and Pixel Quest: the plate uses the installed theme’s tooltip fill and text style. The held name still fits after the theme change.
- Final opening and holding produced no Studio console errors. Play was stopped and Studio returned to its default viewport.

Studio device simulation is engine evidence. It does not establish physical phone behavior or hardware timing.

## Automated evidence

Targeted suites cover shared safe-area placement, long-press Help, radial opening and drag cancellation, held label sizing, and Outpost rotation and camera restoration. The full behavioral suite, source types, formatting, benchmarks and local package build pass.

Full verification of the combined working tree included a separate staged Lab rename and failed its stale project references. That rename is outside this commit; the clean commit passes the brand scan. Host performance trend checks still flagged screen lifecycle timing. No timing baseline was changed and no package was published.
