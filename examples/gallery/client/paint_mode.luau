--!strict
--[[ WHICH PAINT PATH THIS PLACE BOOTS — one decision, taken before the adapter.

	WHAT IT IS FOR. The gallery is the place the native-stylesheets A/B is driven
	in (ledger NSS-A2 / NSS-A10), and the three workspace attributes that drive it
	have a PRECEDENCE that used to live inside one `and`/`or` expression in the
	bootstrap's argument list. An ordering spelled as operator precedence is an
	ordering nobody can test, and this one has to survive a default flip.

	THE RULE, in the order it is applied:

	  1. `Facet_ForceStyleFallback` WINS OVER EVERYTHING. It is the A/B's forced
	     arm — the explicit-write path exercised deliberately, live, beside the
	     sheet path (NSS-A10 is a parity row, so the fallback has to be reachable
	     from the place even after the sheet path became the default). It returns
	     the framework's own per-target escape hatch, an explicit `false`.
	  2. `Facet_NativeStyle` (or `Facet_NativeTransitions`) asks for the sheet
	     path EXPLICITLY, and carries the transitions opt with it. Since the
	     2026-08-21 default flip this is REDUNDANT-BUT-HARMLESS for paint — it
	     still means something, because it is the only way to turn transitions on.
	  3. Neither set: return `nil`, which is not "off". `nil` is the absence of an
	     opt, and the absence of an opt is what `native_style.DEFAULT_ENABLED`
	     answers — so the gallery follows the library's default instead of pinning
	     a copy of it. BEFORE the flip this branch returned `false`, and a `false`
	     here would have made the gallery the one place in the repository that
	     could not see the new default.

	WHY A MODULE AND NOT AN EXPRESSION. `boot_mode.luau` is next to this file for
	exactly the same reason, and its header tells the story of the ordering bug
	that was invisible while it was control flow. This is the same shape: the
	bootstrap is a client script that no headless spec can run, so a decision left
	inside it has no witness at all. `tests/native_style_default.spec.luau` drives
	the three combinations here and reads the bootstrap's call back out of the
	source, so the place and the pin cannot drift apart.
]]

export type Selectors = {
	-- `workspace.Facet_NativeStyle == true`
	native: boolean,
	-- `workspace.Facet_ForceStyleFallback == true`
	fallback: boolean,
	-- `workspace.Facet_NativeTransitions == true`
	transitions: boolean,
}

local paint_mode = {}

-- the `nativeStyle` opt to hand `screen_target.new`: `false` (forced
-- explicit-write), a table (sheet paint, with the transitions opt), or `nil`
-- (no opt — the library default decides).
function paint_mode.decide(selectors: Selectors): any
	if selectors.fallback == true then
		return false
	end
	if selectors.native == true or selectors.transitions == true then
		return { transitions = selectors.transitions == true }
	end
	return nil
end

return paint_mode
