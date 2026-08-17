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

	it("the instance-host refusal that makes the ordering hazard real is still in place", function()
		-- parkEligible refusing registered hosts is WHY a host is always destroyed
		-- (never parked) — if this refusal ever moves, the corpse gate's
		-- reasoning must be revisited, so the dependency is pinned here
		local fnStart = string.find(source, "local function parkEligible", 1, true)
		local fnEnd = string.find(source, "local PARKED_PATH", 1, true)
		local body = string.sub(source, fnStart :: number, fnEnd :: number)
		expect(string.find(body, "hostAt(path) ~= nil", 1, true) ~= nil).toBe(true)
	end)
end)

return true
