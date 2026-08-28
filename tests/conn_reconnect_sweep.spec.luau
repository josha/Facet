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
local adapter_source = require("./lib/adapter_source")

local pointerSrc = fs.readFile("src/client/screen_pointer.luau")
local chromeSrc = fs.readFile("src/client/screen_chrome.luau")
local targetSrc = fs.readFile("src/client/screen_target.luau")

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
	-- task CONN round 2: the 8 screen_target.luau sites round 1's completeness
	-- table disclosed as deferred (same family, different file), now swept
	{ field = "hoverStateConn", helper = "reconnectOnChange", label = "screen_target.luau", src = targetSrc },
	{ field = "discloseEnterConn", helper = "reconnectOnChange", label = "screen_target.luau", src = targetSrc },
	{ field = "discloseLeaveConn", helper = "reconnectOnChange", label = "screen_target.luau", src = targetSrc },
	{ field = "discloseTouchConn", helper = "reconnectOnChange", label = "screen_target.luau", src = targetSrc },
	{ field = "textChangedConn", helper = "reconnect", label = "screen_target.luau", src = targetSrc },
	{ field = "focusedConn", helper = "reconnect", label = "screen_target.luau", src = targetSrc },
	{ field = "focusLostConn", helper = "reconnect", label = "screen_target.luau", src = targetSrc },
	{ field = "oskReturnConn", helper = "reconnect", label = "screen_target.luau", src = targetSrc },
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

-- `chromeTextConns` (screen_chrome.luau): task CONN round 2 swept this too,
-- but it is not a `reconnect`/`reconnectOnChange` site — a LIST of connections
-- plus a label instance whose Focused/FocusLost closures capture `deco` BY
-- VALUE at build time, so the fix is a REBUILD (destroy + recreate) on
-- identity change, keyed on the same `handle.path` every other site uses.
describe("chromeTextConns: rebuilds (not merely reconnects) on a recycle, keyed on handle.path", function()
	it("syncChromeText forces a destroy+rebuild when chromeTextPath no longer matches handle.path", function()
		local at = string.find(chromeSrc, "handle.chromeText ~= nil and handle.chromeTextPath ~= handle.path", 1, true)
		expect(at ~= nil).toBe(true)
		local destroyAt = string.find(chromeSrc, "destroyChromeText(handle)", at :: number, true)
		expect(destroyAt ~= nil).toBe(true)
	end)
	it("the identity is stamped when the label is (re)built, and cleared when it is destroyed", function()
		expect(string.find(chromeSrc, "handle.chromeTextPath = handle.path", 1, true) ~= nil).toBe(true)
		expect(string.find(chromeSrc, "handle.chromeTextPath = nil", 1, true) ~= nil).toBe(true)
	end)
end)

-- `chromeOverrideConn` is checked here because it is the one CENSUS_SLOTS
-- field the findings named as needing the fix that this round's own
-- investigation found was ALREADY correct.
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

--[[ TASK CONN ROUND 2 (review-conn-verdicts.md Finding 4 residual). Round 1
	fixed `hitExpanderPointerConn`'s FIRST writer (`screen_pointer.setPointer-
	Handlers`) but left its SECOND — `screen_target.setHitRect` — byte-for-byte
	unchanged, still the pre-fix `== nil` guard, and marked the field "SWEPT" in
	the completeness table with no caveat. The re-review traced a concrete
	permanent-misroute scenario through it: a handle's earlier life declares
	`setPointerHandlers` (so `handle.pointer` holds that occupant's handlers)
	with no hit rect; a later life recycles the SAME pooled handle (`park`/
	`adopt` touched neither field) into a plain Activated-only control that
	gets a hit rect but never calls `setPointerHandlers` — `setHitRect` then
	wires the expander to the STALE `handle.pointer`, permanently, because the
	wiring lived inside `if expander == nil` (never re-entered once an expander
	exists) AND was itself `== nil`-guarded (never rewires once set). Two
	independent fixes close it: `adapter.adopt` now resets `handle.pointer` to
	nil on every recycle (so a life that declares no pointer handlers cannot
	inherit a prior occupant's), and the wiring moved OUTSIDE the
	`expander == nil` block onto `reconnectOnChange` keyed on `handle.path`,
	exactly like `screen_pointer.luau`'s sibling site.

	`screen_target.luau` reaches engine globals at module scope
	(`game:GetService`, confirmed by a direct `lune run` probe) and cannot be
	required headlessly, so — the established pattern for this adapter family —
	this reads the live source as TEXT. ]]
describe("screen_target: hitExpanderPointerConn's SECOND writer (Finding 4 residual)", function()
	it("adapter.adopt resets handle.pointer to nil on every recycle", function()
		local FN = adapter_source.bodyOf(targetSrc, "function adapter.adopt(")
		expect(#FN > 0).toBe(true)
		expect(string.find(FN, "handle.pointer = nil", 1, true) ~= nil).toBe(true)
	end)

	it(
		"setHitRect's wiring runs OUTSIDE the `expander == nil` block (the block closes right after mirrorToHitExpander)",
		function()
			local FN = adapter_source.bodyOf(targetSrc, "function adapter.setHitRect(")
			expect(#FN > 0).toBe(true)
			local gateCloseAt = string.find(FN, "mirrorToHitExpander(handle)\n\t\tend", 1, true)
			local reconnectAt = string.find(FN, 'reconnectOnChange(handle, "hitExpanderPointerConn"', 1, true)
			expect(gateCloseAt ~= nil and reconnectAt ~= nil).toBe(true)
			expect((reconnectAt :: number) > (gateCloseAt :: number)).toBe(true)
		end
	)

	it("no raw `== nil` guard survives at this site (the exact pre-fix pattern the re-review quoted)", function()
		local FN = adapter_source.bodyOf(targetSrc, "function adapter.setHitRect(")
		local rawAt = string.find(FN, "handle.hitExpanderPointerConn == nil", 1, true)
		expect(rawAt == nil).toBe(true)
	end)

	it("a nil handle.pointer disconnects any stale connection rather than leaving it wired", function()
		local FN = adapter_source.bodyOf(targetSrc, "function adapter.setHitRect(")
		local at = string.find(FN, "elseif handle.hitExpanderPointerConn ~= nil then", 1, true)
		expect(at ~= nil).toBe(true)
		local disconnectAt = string.find(FN, "handle.hitExpanderPointerConn:Disconnect()", 1, true)
		expect(disconnectAt ~= nil and (disconnectAt :: number) > (at :: number)).toBe(true)
	end)
end)

--[[ TASK CONN ROUND 2, ITEM 5 — the ten-foot focus "pop" (`tenFootFocusScale`,
	1.05x) overflowing a scroll-reserved edge, found+diagnosed by the MISC lane
	(task-misc-report.md's appendix): a table row's `FocusScale` grew it to
	306.6x40.95 against a scroll body whose `AbsoluteWindowSize` is 292 — the
	root-frame lift-cap check (`setFocusVisual`) had no way to see that
	reservation, since the whole-screen root is far larger than one scrolled
	row. Fixed by ALSO capping the lift against the nearest scroll/clip host's
	own window (`AbsoluteWindowSize` when it is a `ScrollingFrame`, else
	`AbsoluteSize`), narrowing an already-true `lift`, never widening a false
	one. `screen_target.luau` cannot run headlessly (confirmed: reaches
	`game:GetService` at module scope) so this is pinned as text, matching the
	rest of this adapter family. ]]
describe(
	"screen_target.setFocusVisual: the ten-foot lift also respects the nearest scroll/clip host's window (item 5)",
	function()
		local FN = adapter_source.bodyOf(targetSrc, "function adapter.setFocusVisual(")

		it("found the function", function()
			expect(#FN > 0).toBe(true)
		end)

		it("the host-window cap runs AFTER (and narrows) the root-frame lift, not instead of it", function()
			local rootLiftAt = string.find(FN, "lift = pos.X + size.X * scale <= boundsPos.X + bounds.X", 1, true)
			local hostGateAt = string.find(FN, "handle.instanceHost.crops", 1, true)
			expect(rootLiftAt ~= nil and hostGateAt ~= nil).toBe(true)
			expect((hostGateAt :: number) > (rootLiftAt :: number)).toBe(true)
		end)

		it(
			"only applies when `lift` is already true (AND, not OR — never widens a refusal into an allowance)",
			function()
				-- pattern, not plain-text: tolerant of stylua's own line-wrapping of the
				-- multi-clause `if`, which is not this test's business to pin exactly
				expect(string.find(FN, "if%s+lift%s+and handle%.instanceHost ~= nil") ~= nil).toBe(true)
			end
		)

		it("reads AbsoluteWindowSize for a ScrollingFrame host, AbsoluteSize otherwise", function()
			expect(string.find(FN, 'hostInst:IsA("ScrollingFrame")', 1, true) ~= nil).toBe(true)
			expect(string.find(FN, "AbsoluteWindowSize", 1, true) ~= nil).toBe(true)
			expect(string.find(FN, "else hostInst.AbsoluteSize", 1, true) ~= nil).toBe(true)
		end)
	end
)
