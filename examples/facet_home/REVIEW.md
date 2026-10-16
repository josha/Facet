# Facet Home verification

Facet Home uses ProximityPrompt for room actions, DataStore for durable storage,
and SurfaceGui and ScreenGui for interface surfaces. Model.ScaleTo and
Model.PivotTo place furniture. SurfaceAppearance.Color applies a finish.
Compose cells, formulas, keyed mounts, and cleanup own local presentation.
The game model validates room slots, revisions, and the memory activity.

## Check the example

Build with `lute run tools/facet build home`. Open the built place in Studio.
Check the six furniture choices and their names and categories. Open a row
context menu and choose a piece. Place, rotate, save, remove, and restore it.
Send an invalid slot request and confirm that the room stays intact.

Check compact and wide panels. The compact table shows the name column;
the wide table also shows count and finish. Confirm that the panel measures
its safe-area parent and keeps a gap from the dock.

Change the sofa finish and inspect its native surface. Check that furniture
fits the room slots and the ground stays below the floor. Explore hides the
panel and uses the normal avatar camera. Flat mode uses the room overview.
Switch both ways and inspect camera restoration.

If DataStore loading is unavailable, Save must report session-only storage.
Test cloud persistence on a published server. Multi-client sessions, physical
devices, swipe input, and console navigation need separate live checks.

Run `lute run tools/facet gate full` for committed behavior and tooling cases.
A native engine double does not prove geometry, camera behavior, or cloud saves.
