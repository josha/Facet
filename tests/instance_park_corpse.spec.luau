--[[
	The corpse-in-the-pool defect class (found live 2026-08-08, reference-app
	matrix, ref_glade under Fantasy Parchment).

	Mechanism: the renderer's removal loop visits `handles` in hash order, and
	`parkEligible` refuses clip hosts — so a host is always destroyed by
	`adapter.remove`, and when the loop reaches it BEFORE its descendants,
	engine Destroy propagation kills the descendants' instances while they are
	still awaiting their own park. Every write `park` then makes is legal on a
	destroyed instance (`Parent = nil` included), so the pool collects corpses
	stamped with the CURRENT chrome epoch — and the only symptom is the next
	`adopt`'s non-nil Parent write throwing "The Parent property of X is
	locked, current parent: NULL", which crashes the mount of an unrelated
	surface arbitrarily later.

	Live repro (deterministic, Studio): mount ref_glade, navigate two sections
	(fills the pool), install a theme package on the mounted tree (the metrics
	change forces a relayout remount wave), then switch sections once more —
	the mount adopts a corpse and throws. An unthemed control run of the same
	navigation is clean, and installing the theme FIRST (empty pool) is clean,
	which is what isolates the removal-wave ordering as the cause.

	The fix is two guards in the live adapter, both at seams the contract
	already owns ("park refuses what cannot travel"):
	  1. `parkEligible` refuses an instance whose Parent is already nil — a
	     live handle's instance is ALWAYS parented at park time (creation
	     parents it under its clip host or the root gui, and nothing else
	     unparents it before removal), so nil Parent proves the instance was
	     destroyed by an ancestor's removal.
	  2. `adopt` treats the Parent write as the one seam that can still detect
	     a destroyed instance (every other write is legal on one), and refuses
	     the adoption instead of throwing — restoring the parked identity so
	     the caller's discard tears it down as parked.

	SINCE T4b (2026-09-04) THE MECHANISM ABOVE IS HISTORY, NOT THE PRESENT SHAPE,
	and the third case below is where the difference is argued: the sweep visits
	departed paths deepest-first now, and a PLAIN host with no children left is
	parked rather than destroyed. Both guards stay — a host can still be destroyed
	by a path the sweep does not order — and both are still pinned here.

	screen_target is engine-only (module-level `game` requires), so this class
	cannot execute headless and the fake target deliberately models NO
	parenting ("there is no parenting here" — fake_target.luau). Following the
	suite's established pattern for engine-only invariants (adaptive.spec's
	screen_target source anchors), these cases pin the two guards in the
	source itself; the behavior proof is the live A/B recorded in
	artifacts/swiftui-reference-app-validation/framework-fixes.md.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local fs = require("@lune/fs")

local source = fs.readFile("src/client/screen_target.luau")

describe("instance park corpse: the pool can never hold a destroyed instance", function()
	it("parkEligible refuses an unparented (destroyed) instance", function()
		-- the guard must live INSIDE parkEligible so every park path inherits it
		local fnStart = string.find(source, "local function parkEligible", 1, true)
		local fnEnd = string.find(source, "local PARKED_PATH", 1, true)
		expect(fnStart ~= nil and fnEnd ~= nil and (fnStart :: number) < (fnEnd :: number)).toBe(true)
		local body = string.sub(source, fnStart :: number, fnEnd :: number)
		expect(string.find(body, "A CORPSE CANNOT TRAVEL", 1, true) ~= nil).toBe(true)
		-- DIRECTIONAL (platform review M1): the anchor ties the condition to its
		-- consequent, so inverting the guard to `return true` — the exact
		-- pre-fix behavior — reddens this case instead of passing it
		expect(string.match(body, "if handle%.instance%.Parent == nil then%s+return false%s+end") ~= nil).toBe(true)
	end)

	it("adopt refuses (never throws) when the Parent write fails", function()
		local fnStart = string.find(source, "function adapter.adopt", 1, true)
		local fnEnd = string.find(source, "function adapter.discardParked", 1, true)
		expect(fnStart ~= nil and fnEnd ~= nil and (fnStart :: number) < (fnEnd :: number)).toBe(true)
		local body = string.sub(source, fnStart :: number, fnEnd :: number)
		-- the write is guarded...
		expect(string.find(body, "local reparented = pcall", 1, true) ~= nil).toBe(true)
		-- ...and a failure restores the parked identity IN FULL before refusing.
		-- DIRECTIONAL (platform review M1): one anchored pattern over the whole
		-- failure block — parked flag, epoch stamp, sentinel path, refusal — so
		-- dropping ANY restore line (or flipping the return) reddens this case
		expect(
			string.match(
				body,
				"if not reparented then%s+"
					.. "handle%.parked = true%s+"
					.. "handle%.parkedChromeEpoch = savedEpoch%s+"
					.. "handle%.path = PARKED_PATH%s+"
					.. "return false%s+end"
			) ~= nil
		).toBe(true)
	end)

	it("the instance-host refusal is NARROWED to a host that CROPS or still has children", function()
		--[[ THE REVISIT THIS CASE ASKED FOR. It used to pin `hostAt(path) ~= nil`
			verbatim, with the note that "if this refusal ever moves, the corpse gate's
			reasoning must be revisited". T4b moved it, so here is the revisit.

			WHAT CHANGED. A registered host is no longer refused outright: a PLAIN one
			(no `crops` — so no fade-group buffer, no authored `clipChildren`, no
			`ScrollView`) whose child list is EMPTY is parkable, because that is exactly
			what a fresh `create` would build for its adopter. Plan C made those common
			— every reactive-placement container with children is one — and refusing
			them cost the arena's `removeItem` class +21.3 % (FacetBench §C1.3).

			WHAT THE CORPSE GATE'S REASONING BECOMES. The hazard was "a host is always
			DESTROYED, and a host destroyed before its descendants kills their instances
			while they are still awaiting their own park". The sweep now visits departed
			paths deepest-first (`renderer.luau`'s `deeperFirst`), which is what makes
			the emptiness test above answerable at all — and it also means the sweep
			itself can no longer reach a descendant after its ancestor. So the ordering
			hazard is closed at the source rather than merely caught.

			THE GATE STAYS, and it is not belt-and-braces about the sweep alone: an
			ancestor's instance can be destroyed by paths the sweep does not order —
			`destroyRoot`'s own per-node teardown, and any engine-side Destroy of a tree
			the adapter is still holding handles into. It costs one comparison, and the
			live A/B it was found by is not reproducible headless. ]]
		local fnStart = string.find(source, "local function parkEligible", 1, true)
		local fnEnd = string.find(source, "local PARKED_PATH", 1, true)
		local body = string.sub(source, fnStart :: number, fnEnd :: number)
		-- DIRECTIONAL (platform review M1): one anchored pattern tying BOTH halves of
		-- the condition to the refusal, so widening it back to every host, dropping
		-- either clause, or flipping the return reddens this case
		expect(
			string.match(
				body,
				"local hostEntry = hostAt%(path%)%s+"
					.. "if hostEntry ~= nil and %(hostEntry%.crops == true or #hostEntry%.children > 0%) then%s+"
					.. "return false%s+end"
			) ~= nil
		).toBe(true)
		-- ...and the emptiness half only means anything because BOTH exits maintain
		-- the array: `park` always did, `remove` never did until T4b
		expect(string.find(source, "local function releaseHostMembership", 1, true) ~= nil).toBe(true)
		local removeStart = string.find(source, "function adapter.remove(handle: any)", 1, true)
		local removeEnd = string.find(source, "function adapter.destroyRoot", 1, true)
		local removeBody = string.sub(source, removeStart :: number, removeEnd :: number)
		expect(string.find(removeBody, "releaseHostMembership(handle)", 1, true) ~= nil).toBe(true)
	end)

	it("a host that has carried a PRESENTATION TRANSFORM is refused, and no children rule lifts it", function()
		--[[ THE SECOND REFUSAL, and it is the one T4b could NOT narrow.
			`presentationTransforms[path]` is keyed to the PATH, so a recycled instance
			would inherit an offset with nothing left driving it — the fake target's own
			mirror records that it once accepted such a node and "a re-created path came
			back at -50 instead of at rest". Emptying a host's child list says nothing
			about that record, so a plain, childless host that has ever carried a
			transform stays out of the pool for good. Pinned here beside the narrowed
			clause so a later widening cannot take this one with it. ]]
		local fnStart = string.find(source, "local function parkEligible", 1, true)
		local fnEnd = string.find(source, "local PARKED_PATH", 1, true)
		local body = string.sub(source, fnStart :: number, fnEnd :: number)
		-- DIRECTIONAL (platform review M1): the clause is tied to its consequent —
		-- the multi-condition `if` it closes and that `if`'s `return false` — so
		-- inverting the guard or moving the clause out of the refusal reddens this
		expect(
			string.match(body, "or presentationTransforms%[path%] ~= nil%s+then%s+return false%s+end%s+return true")
				~= nil
		).toBe(true)
		-- ...and it is NOT one of the two clauses the host rule now owns: those are
		-- decided above, against `hostEntry`, and this one is not
		expect(string.find(body, "hostEntry.crops == true or #hostEntry.children > 0", 1, true) ~= nil).toBe(true)
	end)
end)

return true
