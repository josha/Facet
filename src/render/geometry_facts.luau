--!strict
--[[ geometry_facts — WHICH ENVIRONMENT FACTS ARE GEOMETRY FOR A SURFACE, AND WHEN
	TWO READINGS OF THEM ARE THE SAME.

	Public interface, two pure functions and no state:

	  `geometry_facts.keysFor(rootPolicy) -> { key }`
	      the environment keys a surface under that root policy must re-solve for,
	      already narrowed for the policy. `rootPolicy` is fixed for a controller's
	      life (read once at attach), so the list is safe to fix with it.
	  `geometry_facts.same(keys, a, b) -> boolean`
	      the comparator for two readings of that list, BY CONTENT.

	The renderer builds one memo over the list and hands the comparator to it; both
	halves are here because a key added to the list and not taught to the comparator
	is a surface that goes deaf to a fact, and the two are one decision.

	WHY IT IS ITS OWN FILE. `tools/lune/verify/data/source-cap-ledger.md`'s row for
	`render/renderer.luau` carries a trigger that is a STATE — take a seam BEFORE the
	round that needs the room — and the seam it still named (the tap-echo guard) had
	already left as `render/tap_arm.luau`. This is the block the round that found that
	was opening anyway (the text-measure epoch below), and it is one-way by
	construction: a policy string in, a list of strings out; two readings in, a
	boolean out. It reads no controller local, holds no state, and requires only
	`src/rect.luau` for the flat-record comparison every layer of this library shares.
]]

local rect = require("../rect")

local geometry_facts = {}

--[[ ENVIRONMENT GEOMETRY DRIVES RE-ARRANGEMENT — AS ONE FACT, NOT EIGHT.
	These eight keys all mean the same thing to this surface: "the space you
	were solved for is no longer the space you are in." They were once
	observed INDEPENDENTLY, each callback running a full `solveAndApply()`,
	and the multiplication was real work on a real device: L-27 recorded "one
	viewport change costs 5 solves and 2 structural syncs, reproducibly" and
	the 2026-08-13 device capture priced a solve at 8.270 ms of arrange +
	3.057 ms of measure, 58.5% of wall.

	Two facts compound to make five. An adapter learns SEVERAL of these at
	once (`roblox_env.pushViewport()` writes six on one resize), and some are
	DERIVED from others — `typographyScale` is a memo over `displaySize` and
	`preferredTextOffset`, so even a single loose write fires twice.

	One memo over all eight fixes both. The core is glitch-free, so it
	recomputes at most ONCE per flush no matter how many of its dependencies
	moved, and the fresh table is deliberate: identity-inequality means "some
	geometry fact changed", which is exactly the question this observer asks.
	Paired with the adapter batching a platform event into one transaction
	(`env:batch`), five solves become one — measured, not assumed, in
	tests/geometry_solve_coalescing.spec.

	THE MEMO CARRIES VALUES, NOT A FRESH TABLE (RED-TEAM 2026-08-13). The first
	cut returned `{}` and relied on identity-inequality, which made "recomputed"
	mean "changed" and discarded both guarantees the core states in its own
	header — set-and-revert transactions and unchanged recomputes are fire-free.
	Measured then: a viewport set-and-reverted inside one batch cost 1 solve
	instead of 0, and a `preferredTextSize` change that left `typographyScale`
	on the same clamped value cost 1 instead of 0. Wasted solves in exactly the
	dimension this entry exists to remove. So it returns the pulled values and
	compares them element-wise; eight comparisons per flush buys both properties
	back, and it stays honest if a DERIVED key is ever added to the list.

	ADDING A KEY: put it in the list and nowhere else. REMOVING one silently
	makes the surface deaf to it, which is why that spec drives every key
	individually and asserts each still costs exactly one solve. ]]

--[[ BY CONTENT, NOT BY TABLE IDENTITY. Every one of these facts that is not a
	scalar is a FLAT RECORD — a rect (`x,y,w,h`) or a four-edge inset — and the
	adapter builds a BRAND NEW one on every `pushViewport()`. A `TopbarInset`
	change alone re-publishes a viewportRect whose numbers are identical, and
	under identity comparison that is a full re-solve of the surface for a
	viewport that did not move. Comparing the numbers costs at most eight field
	reads and removes a whole class of solve nobody asked for.

	One level deep is deliberate and sufficient: no environment geometry fact
	nests, and a deep walk would be a general-purpose comparison bolted to a
	specific eight. A nested fact is REFUSED rather than half-compared — any
	table-valued FIELD returns false, i.e. re-solves.

	That refusal is load-bearing and the reason is worth stating, because the
	comment here used to promise conservatism it did not deliver (architecture
	gate F3, 2026-08-14). Comparing a nested field by identity is only safe
	when the inner table is rebuilt with the outer one. A future fact shaped
	`{ rect = <cached>, insets = <fresh> }` — outer rebuilt, inner reused —
	would compare the inner references as EQUAL and report "unchanged", which
	is a MISSED re-solve, not an extra one: the surface goes silently deaf to
	one platform fact. Refusing the shape costs nothing today (no fact has a
	table-valued field) and makes the conservative claim literally true. ]]
-- ...and the comparison itself is `src/rect.luau`'s, from the reuse audit: the
-- same body
-- lived here and in `src/controls/selection_indicator.luau`, across a layer
-- boundary, with the indicator's copy carrying a comment naming this one.
-- ...and the comparison itself is `src/rect.luau`'s, from the reuse audit: the same
-- body lived here and in `src/controls/selection_indicator.luau`, across a layer
-- boundary, with the indicator's copy carrying a comment naming this one.
local sameGeometryValue = rect.sameFlatValue

--[[ ...AND THE ONE NESTED FACT, compared exactly rather than refused.
	`platformChrome` is `{ band, rects, insets, bandInsets }` — three flat
	records and a LIST of them — and it is a memo, so it hands back a brand-new
	frozen table on every recompute; under identity OR `sameFlatValue` a
	band-riding surface would re-solve on every flush. This walks exactly the four
	fields the fact has, and an unknown fifth would compare as "changed", which is
	the safe direction. ]]
local function sameChrome(a: any, b: any): boolean
	if a == nil or b == nil then
		return a == b
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	if not sameGeometryValue(a.band, b.band) then
		return false
	end
	if not sameGeometryValue(a.insets, b.insets) or not sameGeometryValue(a.bandInsets, b.bandInsets) then
		return false
	end
	local ar, br = a.rects, b.rects
	if type(ar) ~= "table" or type(br) ~= "table" or #ar ~= #br then
		return false
	end
	for i = 1, #ar do
		if not sameGeometryValue(ar[i], br[i]) then
			return false
		end
	end
	return true
end

local function sameChrome(a: any, b: any): boolean
	if a == nil or b == nil then
		return a == b
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	if not sameGeometryValue(a.band, b.band) then
		return false
	end
	if not sameGeometryValue(a.insets, b.insets) or not sameGeometryValue(a.bandInsets, b.bandInsets) then
		return false
	end
	local ar, br = a.rects, b.rects
	if type(ar) ~= "table" or type(br) ~= "table" or #ar ~= #br then
		return false
	end
	for i = 1, #ar do
		if not sameGeometryValue(ar[i], br[i]) then
			return false
		end
	end
	return true
end

local BASE_KEYS = {
	"viewportRect",
	"coreSafeInsets",
	"deviceSafeInsets",
	"overscanInsets",
	"displaySize",
	-- geometry-affecting (matrix D.1): a preferredTextSize or displaySize
	-- change re-scales text at measure AND paint
	"typographyScale",
	"preferredTextOffset",
	-- a theme commit is geometry: new type sizes, spacing,
	-- control metrics and content insets all reach the solver, so the
	-- surface RE-SOLVES — it is never rebuilt, so mount identity, focus,
	-- selection, scroll and text entry survive a swap untouched
	"themeMetrics",
}
--[[ AN edgeToEdge SURFACE DOES NOT CONSUME A SAFE-AREA INSET (L-31).
	`solveAndApply` opens with `if rootPolicy == "edgeToEdge" then insets =
	{0,0,0,0}` — it reads `coreSafeInsets` and throws the value away, and never
	reads `deviceSafeInsets` at all. Leaving both in the dependency list made
	every scrim, backdrop and dock re-solve for an inset it is defined to
	ignore, and the shipped case is the one that hurts: a dock that PUBLISHES
	its measured height into `coreSafeInsets` re-solved for its own
	publication, every time, forever. Measured on the general two-surface
	shape: 4 arranges per geometry change, 3 with this narrowing.

	The two remaining policies both consume both keys (`coreSafeContent` uses
	coreSafeInsets; `deviceSafeContent` takes the per-edge max of both), so
	this is the only policy that can be narrowed and it is narrowed on the
	exact branch that proves it. `rootPolicy` is fixed for the controller's
	life (read once at attach), so the key list is safe to fix with it. ]]
--[[ ...AND `bandSafeContent` READS ONE FACT WHERE THE OTHERS READ THREE. Its content rect comes from `platformChrome`, which is DERIVED
	from the core and device insets, the two topbar facts, the declared app chrome
	and the overscan — so subscribing to the raw three would be both incomplete (a
	`TopbarInset` change would move the band and re-solve nothing) and redundant.
	Same narrowing `edgeToEdge` gets above, in the other direction.

	It is the one NESTED fact in this list and it has a comparator of its own
	(`sameChrome`); the refusal the block above documents stands for facts with
	none. ]]
function geometry_facts.keysFor(rootPolicy: string?): { string }
	if rootPolicy == "edgeToEdge" then
		local narrowed = {}
		for _, key in BASE_KEYS do
			if key ~= "coreSafeInsets" and key ~= "deviceSafeInsets" then
				table.insert(narrowed, key)
			end
		end
		return narrowed
	end
	if rootPolicy == "bandSafeContent" then
		local swapped = { "platformChrome" }
		for _, key in BASE_KEYS do
			if key ~= "coreSafeInsets" and key ~= "deviceSafeInsets" and key ~= "overscanInsets" then
				table.insert(swapped, key)
			end
		end
		return swapped
	end
	-- the two policies that consume both inset facts get the list unchanged, and a
	-- COPY of it: the caller holds this list for the life of a surface and a shared
	-- one would let a second surface's narrowing rewrite the first's dependencies
	return table.clone(BASE_KEYS)
end

-- Two readings of `keysFor`'s list, compared BY CONTENT (above). `nil` on either
-- side is only equal to `nil` — a memo that has not run yet is not "unchanged".
function geometry_facts.same(keys: { string }, a: any, b: any): boolean
	if a == nil or b == nil then
		return a == b
	end
	for i = 1, #keys do
		local same = if keys[i] == "platformChrome" then sameChrome(a[i], b[i]) else sameGeometryValue(a[i], b[i])
		if not same then
			return false
		end
	end
	return true
end

return geometry_facts
