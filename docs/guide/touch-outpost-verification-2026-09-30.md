# Touch labels and Outpost verification

## Behavior

The Outpost world terminal uses the live space below its commands. Its surface canvas follows that space, and a short canvas scrolls its power controls. The camera fit uses native `ScreenPointToRay` or `ViewportPointToRay` to account for the host ScreenGui inset and the engine projection. Leaving the world restores the camera frame, type, focus, field of view and field-of-view mode.

Radial names and long-press Help use the actual held contact. Shared placement prefers the space above the fingertip, then beside or below it inside the safe area. Radial names use the existing tooltip style rules without an arrow. Native `AutomaticSize`, `UISizeConstraint` and wrapping fit the full name. Measurement reuses the existing layout unit instead of adding a measuring child inside the automatically sized label.

The opening radial contact does not choose an item. A launcher drag must cross the existing 14-pixel threshold before it aims; returning to the center after a drag still cancels. Touch does not borrow mouse hover to choose an item.

## Native API and Compose check

Checked Roblox Camera projection, `FieldOfViewMode`, `ViewportSize`, `GuiObject.AutomaticSize` and `UISizeConstraint`. These native APIs handle the surface projection and text measurement. Compose cells, formulas, watches and cleanup own the responsive values and release camera and input state. The existing overlay placement solver handles safe-area fallback; the shared touch placement policy adds only the fingertip clearance policy. No vendor changes or new dependency are needed.

## Verify in Studio

Build the Showcase with `lute run tools/facet build standalone`. Use a phone
preset and the automatic device setting. Open Outpost and rotate between
portrait and landscape. Check the terminal below Back and Power. Check scrolling
at the shorter height and camera restoration when leaving world mode.

Open Quick actions by touch. The opening contact must not choose an item.
Hold a name and inspect its text fit and clearance above the contact. Change
the theme while the name is visible. Check reduced motion and console errors.
Studio simulation does not prove physical phone input or hardware timing.
