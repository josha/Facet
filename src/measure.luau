--!strict
--[[ THE HEADLESS MEASUREMENT ENTRY POINT (framework-gaps-phase2 gap 11).

	api.md's `text` section names the anti-pattern this exists to end,
	verbatim: "the alternative is what consumers were writing instead — a
	character count times a guessed average glyph width, which is the
	measurer's own conservative fallback." That fallback IS
	`text_metrics.luau`'s own math, and it has ZERO requires and ZERO
	GetService (still true as of this file — re-verify before trusting it
	again if this comment ever predates the module). Until now the only
	PUBLISHED route to it was `Facet.text` via `src/init.luau`, which makes 65
	`@self` requires and transitively pulls `src/client/*` — GetService and
	all. A model that must run headless (Lune, a benchmark, a shared game
	module with no DataModel) could not take that dependency for a fact the
	library already answers on its own.

	So this file is the seam, in the idiom `src/render/tag_sync.luau` set for
	this campaign: depends on ONE pure module and republishes it — the SAME
	table, not a fork, so there is exactly one implementation and it cannot
	drift — giving a headless consumer a NAMED path instead of reaching into
	`src/layout/text_metrics` as an unpublished implementation detail (it is
	OUTSIDE the `Facet` table on purpose, exactly as `tag_sync.luau` is, so
	`check_surface_ledger`'s coverage rule — which walks that table, not the
	filesystem — does not apply to it; `docs/MAINTAINERS.md`'s "layout" row
	and `docs/reference/api.md`'s `measure` section are its documentation of
	record). The live path (`Facet.text.measure` in `src/init.luau`) is
	UNCHANGED and still what every mounted surface should use; this is for the
	consumer that has no core, no environment and no engine to mount one on.

	NOT RascalRally's `HudZoneModel.fitSize` — tried, and measured to be the
	WRONG shape for it: `HudZoneModel` is mounted as a Rojo SIBLING of `Facet`
	(both direct children of `ReplicatedStorage`), and a relative-string
	`require` from there resolves by file-system depth under Lune and by
	instance-tree depth live, which disagree for that pair of mounts (measured
	live in Studio: "could not get parent of component ..'"). `HudZoneModel`
	takes Facet's `text.AVG_GLYPH_FRACTION` by INJECTION instead (its own
	caller already holds the live `Facet` table) — see that field's row in
	api.md's `text` section, and `src/shared/HudZoneModel.luau`'s header in
	RascalRally for the measured failure this file's own promise does not
	survive crossing an arbitrary consumer's Rojo mount.

	depends on: `src/layout/text_metrics` only — itself dependency-free. ]]

return require("./layout/text_metrics")
