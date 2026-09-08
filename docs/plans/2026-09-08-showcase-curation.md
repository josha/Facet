# Showcase curation

The picker contains 41 addressable fixtures and examples. Twelve useful examples
now lead the list; the other 29 are inside the collapsed **UI laboratory**. All
stable IDs, scripted drives and regression fixtures remain available.

The first visit offers All controls, Writing and search, Choices and filters,
Actions and menus, Swipe row actions, Animation, Playlist table, Settings sync,
Word game, Crossword, Match 3 and Plan a journey. These let a person do something
and see the result. “Async images” is now **Loading profile pictures**, with a
plain explanation of loading space and the unavailable-picture fallback.

The new journey already combines navigation, mixed input, first/last baselines,
minimum spacers, adaptive arrangement, multiline notes and shared transitions.
The existing animation example now includes state-driven theme tint. This is the
pattern to follow: demonstrate a capability inside an interaction that needs it.

| Cluster | Recommendation | Why |
|---|---|---|
| Loading pictures | Keep as a laboratory probe; use profile/catalog pictures in reference apps as the main example | Three transport states alone are hard to relate to a product. The probe still tests real loading and failure. |
| Progress rings, level pickers, time curves, fade groups | Consolidate next into the existing animation/activity example | A charging task can explain progress, timing, cancellation and reduced motion together. Keep exact timing/compositing probes available in the laboratory. |
| Variable/measured extents, virtual tables, grids and rails | Consolidate next into one searchable inventory with list/grid/rail views | One dataset makes scrolling, measurement and virtualization understandable without five unrelated pages. |
| Flow wrap and label degradation | Use journey tags or inventory filters as the primary explanation | A user can see why a label wraps or a row changes shape. Keep the comparison switches as laboratory probes. |
| Menu triggers, nested tabs, callouts, inherited power/tint | Integrate into the reference apps' settings and editing flows | These are supporting behaviors, not separate products. Each migration must retain keyboard/gamepad reachability and cleanup checks. |
| Branch scope, hidden lifecycle, dictionaries, surface overlap, foreign content | Keep in the laboratory | These teach authoring contracts or diagnose faults. Deliberately broken comparison arms should not lead the ordinary Showcase. |
| Games, journey, playlist and settings sync | Keep distinct | Each has a clear goal and demonstrates several capabilities in a coherent flow. |

This change curates the picker and clarifies one unclear example. It does not
claim that the remaining multi-demo consolidations have been implemented. Those
need their own interaction designs and coverage migrations; deleting the small
fixtures first would lose useful failure and lifecycle evidence.
