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
-- Two shared helpers in `src/client/handle_conn.luau` replace eight
-- hand-repeated guards:
--   * `reconnect(handle, field, factory)` — for a setter called exactly ONCE
--     per (path, fresh-or-adopted handle): disconnect any prior connection,
--     unconditionally take whatever `factory()` answers (including nil).
--   * `reconnectOnChange(handle, field, identityField, identity, factory)` —
--     for a setter that may run MANY times within one life and must stay a
--     no-op then, but rewire on a genuine identity change (a recycle:
--     `adopt` reassigns `handle.path`, which IS the generation stamp,
--     needing no new field).
--
-- `handle_conn.luau` is deliberately its own module rather than a
-- `screen_vocabulary.luau` addition — see its header — SPECIFICALLY so it
-- touches no engine global and can be required and driven directly here,
-- which is strictly stronger evidence than the text-pin family this adapter
-- usually needs (`screen_pointer.luau`/`screen_chrome.luau` themselves still
-- reach `game`/`Enum` and are pinned as text below, for the CENSUS_SLOTS
-- completeness sweep — a real behavioral proof of the fix's effect on live
-- connections lives in `tests/pointer_seam_ownership.spec.luau`, task CONN's
-- own addition there).
--
-- MUTATION PROOF (performed by hand during task CONN, not a permanent case —
-- screen_pointer.luau/screen_chrome.luau cannot run headlessly past module
-- scope, so there is no way to flip their source and re-require in-process):
-- reverting screen_pointer.luau's `setPointerHandlers` line for
-- `pointerBeganConn` back to the pre-fix raw assignment turned this file's
-- "pointerBeganConn ... wired through reconnect" case AND its "no raw
-- assignment survives" case red; restored afterward. A SECOND, sharper
-- mutation proof lives in `pointer_seam_ownership.spec.luau`: reverting
-- `hitExpanderPointerConn`'s fix to the pre-fix `== nil` guard passed a first
-- draft of that file's rewire case that checked only a live-connection COUNT
-- (a guard that never rewires also leaves exactly one connection, forever —
-- just the wrong one) and reddened the corrected case that checks the
-- CONNECTION OBJECT ITSELF changed identity. Both recorded in
-- task-conn-report.md.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local fs = require("@lune/fs")
local handle_conn = require("../src/client/handle_conn")

local pointerSrc = fs.readFile("src/client/screen_pointer.luau")
local chromeSrc = fs.readFile("src/client/screen_chrome.luau")

local function newFakeConn(): any
	local live = true
	return {
		isLive = function()
			return live
		end,
		Disconnect = function()
			live = false
		end,
	}
end

describe("handle_conn.reconnect: disconnects any prior connection before making a fresh one", function()
	it("a first call with no prior field just takes the factory's connection", function()
		local handle: any = {}
		local made = newFakeConn()
		local conn = handle_conn.reconnect(handle, "fooConn", function()
			return made
		end)
		expect(conn).toBe(made)
		expect(handle.fooConn).toBe(made)
	end)

	it("a second call disconnects the PRIOR connection before installing the fresh one", function()
		local handle: any = {}
		local first = newFakeConn()
		handle_conn.reconnect(handle, "fooConn", function()
			return first
		end)
		local second = newFakeConn()
		handle_conn.reconnect(handle, "fooConn", function()
			return second
		end)
		expect(first.isLive()).toBe(false)
		expect(second.isLive()).toBe(true)
		expect(handle.fooConn).toBe(second)
	end)

	it("a nil answer from factory() clears the field (and still disconnects the prior one)", function()
		local handle: any = {}
		local first = newFakeConn()
		handle_conn.reconnect(handle, "fooConn", function()
			return first
		end)
		handle_conn.reconnect(handle, "fooConn", function()
			return nil
		end)
		expect(first.isLive()).toBe(false)
		expect(handle.fooConn).toBeNil()
	end)
end)

describe("handle_conn.reconnectOnChange: no-ops on an unchanged identity, rewires on a changed one", function()
	it("a first call with no prior field connects and stamps the identity", function()
		local handle: any = {}
		local made = newFakeConn()
		handle_conn.reconnectOnChange(handle, "fooConn", "fooConnId", "A", function()
			return made
		end)
		expect(handle.fooConn).toBe(made)
		expect(handle.fooConnId).toBe("A")
	end)

	it("an unchanged identity is a total no-op, even if factory() would answer something new", function()
		local handle: any = {}
		local first = newFakeConn()
		handle_conn.reconnectOnChange(handle, "fooConn", "fooConnId", "A", function()
			return first
		end)
		local calledAgain = false
		handle_conn.reconnectOnChange(handle, "fooConn", "fooConnId", "A", function()
			calledAgain = true
			return newFakeConn()
		end)
		expect(calledAgain).toBe(false)
		expect(handle.fooConn).toBe(first)
		expect(first.isLive()).toBe(true)
	end)

	it("a changed identity disconnects the prior connection and installs a genuinely fresh one", function()
		local handle: any = {}
		local first = newFakeConn()
		handle_conn.reconnectOnChange(handle, "fooConn", "fooConnId", "A", function()
			return first
		end)
		local second = newFakeConn()
		handle_conn.reconnectOnChange(handle, "fooConn", "fooConnId", "B", function()
			return second
		end)
		expect(first.isLive()).toBe(false)
		expect(second.isLive()).toBe(true)
		expect(handle.fooConn).toBe(second)
		expect(handle.fooConnId).toBe("B")
	end)

	it(
		"retries on every call while the field stays nil (a track/target not found yet), regardless of identity",
		function()
			local handle: any = {}
			local attempts = 0
			handle_conn.reconnectOnChange(handle, "fooConn", "fooConnId", "A", function()
				attempts += 1
				return nil
			end)
			handle_conn.reconnectOnChange(handle, "fooConn", "fooConnId", "A", function()
				attempts += 1
				return nil
			end)
			expect(attempts).toBe(2)
			expect(handle.fooConn).toBeNil()
		end
	)
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
