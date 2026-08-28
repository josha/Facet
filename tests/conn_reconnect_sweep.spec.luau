--!strict
-- THE SHARED RECONNECT HELPERS, AND THE CENSUS_SLOTS COMPLETENESS SWEEP (task
-- CONN, review-fix234-findings.md Findings 1 & 4).
--
-- FIX-2 fixed exactly one `handle.*Conn` field (`activatedConn`) against a
-- recycled handle carrying every prior life's connection forward untouched:
-- `screen_target.adapter.adopt` re-keys the SAME Lua table across a
-- park->adopt life, so an unconditional overwrite left the STALE connection
-- (closed over a prior life's `handlers`/`path`) live beside the fresh one,
-- and Roblox's connection-order-preserving dispatch let the older one win a
-- race it should have lost. FIX-2's own self-review flagged, and this
-- campaign's review then confirmed, that every SIBLING setter in
-- `screen_pointer.luau` shared the exact same bug (Finding 1:
-- `pointerBeganConn`, `hoverEnterConn`, `hoverLeaveConn`, `scrollConn`), plus a
-- SECOND shape in the same family — a `== nil` guard that never rewires AT ALL
-- once a connection exists, which is not a duplicate-listener leak but a
-- PERMANENT misroute surviving every future recycle (Finding 4:
-- `hitExpanderPointerConn`).
--
-- Two shared helpers replace eight hand-repeated guards
-- (`src/client/screen_vocabulary.luau`, the one pure/one-way module already
-- required by every sibling this bug spans):
--   * `reconnect(handle, field, factory)` — for a setter called exactly ONCE
--     per (path, fresh-or-adopted handle): disconnect any prior connection,
--     unconditionally take whatever `factory()` answers (including nil).
--   * `reconnectOnChange(handle, field, identityField, identity, factory)` —
--     for a setter that may run MANY times within one life and must stay a
--     no-op then, but rewire on a genuine identity change (a recycle:
--     `adopt` reassigns `handle.path`, which IS the generation stamp,
--     needing no new field).
--
-- `screen_vocabulary.luau` reaches `Enum` at module scope (see
-- `CLASS_TO_INSTANCE`/`TEXT_ALIGN_MAP`) and cannot be required headlessly —
-- verified directly (`lune run` on a probe script reaches
-- "attempt to index nil with 'TextXAlignment'" at load) — so, like the rest of
-- this adapter family (`theme_layer_application.spec.luau`,
-- `focus_ring_float_geometry.spec.luau`, `activate_handler_reconnect.spec.luau`),
-- this file reads the live source as TEXT and pins the fix structurally rather
-- than by requiring the module.
--
-- MUTATION PROOF (performed by hand during task CONN, not a permanent case —
-- there is no headless harness to flip source and re-run against engine
-- globals): reverting `screen_pointer.luau`'s `setPointerHandlers` line for
-- `pointerBeganConn` back to the pre-fix
-- `handle.pointerBeganConn = connectPointerBegan(handle, instance, handlers)`
-- turned this file's "pointerBeganConn ... wired through reconnect" case AND
-- its "no raw assignment survives" case red; restored afterward. Recorded in
-- task-conn-report.md.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local fs = require("@lune/fs")

local vocab = fs.readFile("src/client/screen_vocabulary.luau")
local pointerSrc = fs.readFile("src/client/screen_pointer.luau")
local chromeSrc = fs.readFile("src/client/screen_chrome.luau")

describe("screen_vocabulary.reconnect: disconnects any prior connection before making a fresh one", function()
	it("found the function", function()
		expect(string.find(vocab, "local function reconnect(", 1, true) ~= nil).toBe(true)
	end)

	it("disconnects the PRIOR value before calling factory()", function()
		local disconnectAt = string.find(vocab, "(prior :: RBXScriptConnection):Disconnect()", 1, true)
		local factoryAt = string.find(vocab, "local conn = factory()", 1, true)
		expect(disconnectAt ~= nil and factoryAt ~= nil).toBe(true)
		expect((disconnectAt :: number) < (factoryAt :: number)).toBe(true)
	end)

	it(
		"assigns the field from factory()'s own result unconditionally (a nil answer clears a no-longer-wanted slot)",
		function()
			expect(string.find(vocab, "handle[field] = conn", 1, true) ~= nil).toBe(true)
		end
	)
end)

describe("screen_vocabulary.reconnectOnChange: no-ops on an unchanged identity, rewires on a changed one", function()
	it("found the function", function()
		expect(string.find(vocab, "local function reconnectOnChange(", 1, true) ~= nil).toBe(true)
	end)

	it("the no-op guard checks BOTH the field and the identity before returning", function()
		local at = string.find(vocab, "if handle[field] ~= nil and handle[identityField] == identity then", 1, true)
		expect(at ~= nil).toBe(true)
	end)

	it("disconnects the prior connection, THEN restamps identity, THEN reconnects (in that order)", function()
		local disconnectAt = string.find(vocab, "(handle[field] :: RBXScriptConnection):Disconnect()", 1, true)
		local restampAt = string.find(vocab, "handle[identityField] = identity", 1, true)
		local reconnectAt = string.find(vocab, "handle[field] = factory()", 1, true)
		expect(disconnectAt ~= nil and restampAt ~= nil and reconnectAt ~= nil).toBe(true)
		expect((disconnectAt :: number) < (restampAt :: number)).toBe(true)
		expect((restampAt :: number) < (reconnectAt :: number)).toBe(true)
	end)
end)

-- CENSUS_SLOTS COMPLETENESS (the table task-conn-report.md owes, mechanised):
-- every `*Conn` field Findings 1 and 4 name, swept through the helper its own
-- call cadence needs. A site listed here with NO matching call, or with a raw
-- assignment surviving beside the helper, is exactly the defect these findings
-- reported — which is what makes reverting any one site a red case (see the
-- mutation proof in the header).
local SWEPT_SITES = {
	{ field = "activatedConn", helper = "reconnect", label = "screen_pointer.luau", src = pointerSrc },
	{ field = "pointerBeganConn", helper = "reconnect", label = "screen_pointer.luau", src = pointerSrc },
	{ field = "hoverEnterConn", helper = "reconnect", label = "screen_pointer.luau", src = pointerSrc },
	{ field = "hoverLeaveConn", helper = "reconnect", label = "screen_pointer.luau", src = pointerSrc },
	{ field = "scrollConn", helper = "reconnect", label = "screen_pointer.luau", src = pointerSrc },
	{
		field = "hitExpanderPointerConn",
		helper = "reconnectOnChange",
		label = "screen_pointer.luau",
		src = pointerSrc,
	},
	{ field = "barConn", helper = "reconnectOnChange", label = "screen_chrome.luau", src = chromeSrc },
	{ field = "barWindowConn", helper = "reconnect", label = "screen_chrome.luau", src = chromeSrc },
}

describe("CENSUS_SLOTS completeness: every Finding-1/4-named *Conn field is swept", function()
	for _, site in SWEPT_SITES do
		local field, helper, label, src = site.field, site.helper, site.label, site.src
		it(field .. " (" .. label .. "): wired through " .. helper, function()
			local callAt = string.find(src, helper .. '(handle, "' .. field .. '"', 1, true)
			expect(callAt ~= nil).toBe(true)
		end)
		it(
			field .. " (" .. label .. "): no raw `handle." .. field .. " = ` assignment survives beside the helper",
			function()
				local rawAt = string.find(src, "handle." .. field .. " = ", 1, true)
				expect(rawAt == nil).toBe(true)
			end
		)
	end
end)

-- THE REMAINING CENSUS_SLOTS: `hoverStateConn`, `discloseEnterConn`,
-- `discloseLeaveConn`, `discloseTouchConn`, `textChangedConn`, `focusedConn`,
-- `focusLostConn`, `oskReturnConn` and `chromeTextConns` all live in
-- `screen_target.luau` (size-banded, `docs/handoff/SOURCE_CAP_LEDGER.md`) or
-- (`chromeTextConns`) have their own disconnect-and-rebuild pairing already.
-- task-conn-report.md's completeness table carries the per-field argument for
-- each (safe-by-dynamic-re-read, or a same-defect-family follow-up named and
-- out of this round's scope); `chromeOverrideConn` is checked here because it
-- is the one CENSUS_SLOTS field the findings named as needing the fix that
-- this round's own investigation found was ALREADY correct.
describe(
	"chromeOverrideConn: argued safe, not swept (Finding 1 named it; investigation found it already correct)",
	function()
		it("still disconnects before nil-ing when its plan clears (unchanged by this round)", function()
			local at = string.find(chromeSrc, "handle.chromeOverrideConn:Disconnect()", 1, true)
			expect(at ~= nil).toBe(true)
		end)
		it(
			"still connects only once per identity via its own `== nil` guard (unchanged by this round: its callback re-reads handle.chromeOverrideVariants/-Rest at FIRE time rather than closing over a per-life value, so a never-rewired connection cannot answer with stale data — see task-conn-report.md)",
			function()
				local at = string.find(chromeSrc, "if handle.chromeOverrideConn == nil then", 1, true)
				expect(at ~= nil).toBe(true)
			end
		)
	end
)
