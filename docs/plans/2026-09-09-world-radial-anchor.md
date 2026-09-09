# World anchors for radial actions

Decision: 2026-09-09. Extend the existing screen anchor with measured `clearance`,
and add the public client-only `world_anchor` binding. The user requested automatic
Part/Model/avatar measurement and a proximity-prompt use case. This supersedes the
original radial brief’s requirement that consumers own world projection. Domain
actions and prompts remain consumer-owned; the shared control stays engine-free.

Reuse the host frame, reactive values, existing follow springs and selection freeze.
Do not add an input system, world GUI target, renderer, dependency, or beta gradient.
Use native bounding boxes, project eight corners, reserve padding, and dismiss if
the object cannot be safely projected. Do not cap clearance and cover the object to
force a ring to fit. Explicit minimum clearance wins; normal list fallback remains.

Engine sources checked 2026-09-09:
- [Camera projection and near plane](https://create.roblox.com/docs/reference/engine/classes/Camera): WorldToViewportPoint matches Facet’s window coordinate system. NearPlaneZ is negative. Projection does not test occlusion.
- [Model bounds](https://create.roblox.com/docs/reference/engine/classes/Model#GetBoundingBox): GetBoundingBox returns a CFrame and size enclosing the model’s parts. Physics constraints may affect accuracy.

Evidence lives in `artifacts/studio/radial-menu/world-anchor/`. Headless projection
uses simulated camera/target facts; Studio exercises native bounds, prompt input,
rendering and teardown. Neither is physical phone or controller evidence.

Sizing revision, 2026-09-09: author padding as a fraction of the measured projected
radius, from 0 to 1, default 0.15. Clearance is radius × (1 + padding), so it
follows apparent object size. Remove the unpublished pixel `minimumRadius`
option; reuse RadialMenu’s existing theme-based `clearance` for an optional floor.
This keeps theme resolution in the control and avoids a second sizing authority
in the projection helper. Migrate the former `padding = 12` examples to 0.15.
