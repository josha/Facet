--!strict
--[[ THE THREE DEPENDENCY-FREE LEAVES (reuse audit REUSE-1/3/4/6/39).

	`src/num.luau`, `src/paths.luau` and `src/rect.luau` each own a question that
	had between six and seventeen private answers across the tree. This file pins
	the contract of each owner, and — for the one place where the copies had
	actually DIVERGED into a live defect — reproduces the defect through the
	public presenter rather than against the helper.

	THE LIVE DEFECT (REUSE-3). `src/present/focus_map.luau` exported a
	segment-aligned prefix test and `presenter.luau` imported it at line 270 —
	then wrote `string.sub(path, 1, #rootPath) == rootPath` at line 640 (which
	surface draws the focus ring) and again at line 3326 (which surface a tap
	routes to). Two presented screens named `Menu` and `MenuBar` therefore routed
	each other's taps. The case below presents exactly those two and taps the
	longer one's button; before the fix, the tap was dispatched against the `Menu`
	handle, resolved to no node there, and the button never fired.

	ONLY ONE OF THE TWO SITES IS OBSERVABLE, AND THAT IS RECORDED RATHER THAN
	PAPERED OVER. Line 640 decides which surface draws the focus ring and drives
	the adjust bindings; reverting it to the raw form and running the ENTIRE fast
	tier (5810 cases) leaves everything green, and it stays green through the
	engine-selection bridge too, because a surface that wrongly claims a foreign
	path resolves it to no node of its own and therefore paints nothing and
	selects nothing — the same nothing the correct answer produces. Its damage is
	LATENT: it becomes visible the first time two prefix-sharing surfaces both
	declare adjust targets, which is a shape no shipped surface has yet. So line
	640 is fixed by the same one-line owner and pinned by `paths.isPrefix`'s
	contract above, and this file claims no witness it does not have. Line 3326 —
	the one below — is the live half, and the mutation reddens it.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local worldLib = require("./lib/world")

local num = require("../src/num")
local paths = require("../src/paths")
local rectLib = require("../src/rect")

local customFactory = require("../src/core/custom")
local UI = require("../src/blueprint")
local environment = require("../src/env/environment")
local actionsLib = require("../src/input/actions")
local presenterLib = require("../src/present/presenter")
local fake_target = require("../tests/lib/fake_target")

describe("num: the predicate seventeen modules wrote by hand", function()
	it("isFinite refuses NaN, both infinities, and every non-number", function()
		for _, good in { 0, -1, 1e9, 0.5, -0.0 } do
			expect(`isFinite({good}): {num.isFinite(good)}`).toBe(`isFinite({good}): true`)
		end
		expect(num.isFinite(0 / 0)).toBe(false) -- NaN never compares equal to itself
		expect(num.isFinite(math.huge)).toBe(false)
		expect(num.isFinite(-math.huge)).toBe(false)
		for _, bad in { "1", true, {}, print } do
			expect(`isFinite({typeof(bad)}): {num.isFinite(bad)}`).toBe(`isFinite({typeof(bad)}): false`)
		end
		expect(num.isFinite(nil)).toBe(false)
	end)

	--[[ The seventeen copies were byte-identical, so the risk in consolidating is
		not that one of them meant something different — it is that a future edit to
		the single owner changes them all. That is what this pins: the exact
		expression, not a looser paraphrase. ]]
	it("isFinite is the same expression every copy carried", function()
		local function original(v: any): boolean
			return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
		end
		for _, v in { 0, 1, -1, 0.5, 1e308, -1e308, 0 / 0, math.huge, -math.huge, "x", true, {} } :: { any } do
			expect(`{tostring(v)}: {num.isFinite(v)}`).toBe(`{tostring(v)}: {original(v)}`)
		end
	end)

	it("roundPx is floor(v + 0.5), which is NOT math.round at a negative half", function()
		expect(num.roundPx(0.4)).toBe(0)
		expect(num.roundPx(0.5)).toBe(1)
		expect(num.roundPx(2.5)).toBe(3)
		expect(num.roundPx(-0.5)).toBe(0) -- math.round(-0.5) is -1; layout wants 0
		expect(num.roundPx(-1.5)).toBe(-1)
		expect(num.roundPx(7)).toBe(7)
	end)
end)

describe("paths: the prefix test with two wrong copies in live routing", function()
	it("a prefix must land on a segment boundary", function()
		expect(paths.isPrefix("/S/Name", "/S/Name/Field")).toBe(true)
		expect(paths.isPrefix("/S/Name", "/S/Name")).toBe(true) -- a node is inside itself
		expect(paths.isPrefix("/S/Name", "/S/NameX/Field")).toBe(false)
		expect(paths.isPrefix("/Menu", "/MenuBar/Save")).toBe(false)
		expect(paths.isPrefix("/S/Name/Field", "/S/Name")).toBe(false) -- not the other way
	end)

	--[[ THE UNSAFE FORM, WRITTEN OUT. Both presenter sites carried exactly this,
		and the difference between the two functions is the whole finding: on the
		`Menu` / `MenuBar` pair they disagree, and the unsafe one is the one that
		decided where a tap went. ]]
	it("disagrees with the raw string.sub form exactly where the defect was", function()
		local function unsafe(prefix: string, path: string): boolean
			return string.sub(path, 1, #prefix) == prefix
		end
		expect(unsafe("/Menu", "/MenuBar/Save")).toBe(true)
		expect(paths.isPrefix("/Menu", "/MenuBar/Save")).toBe(false)
	end)

	it("escape makes an id safe to interpolate into a Lua pattern", function()
		expect(paths.escape("Row-1")).toBe("Row%-1")
		expect(paths.escape("a.b")).toBe("a%.b")
		expect(paths.escape("plain")).toBe("plain")
		-- the point of escaping: the escaped id matches ITSELF and nothing else
		expect(string.match("/S/Row-1/Cell", "^/S/" .. paths.escape("Row-1") .. "/")).toBe("/S/Row-1/")
		expect(string.match("/S/RowX1/Cell", "^/S/" .. paths.escape("Row-1") .. "/")).toBeNil()
	end)
end)

describe("rect: fifteen bodies, four epsilons, two edge conventions", function()
	local a = { x = 0, y = 0, w = 10, h = 10 }

	it("touching is not overlapping, and the epsilon is the caller's", function()
		local touching = { x = 10, y = 0, w = 10, h = 10 }
		expect(rectLib.overlaps(a, touching)).toBe(false) -- epsilon 0: an intersection needs area
		local byHalf = { x = 9.6, y = 0, w = 10, h = 10 }
		expect(rectLib.overlaps(a, byHalf)).toBe(true) -- 0.4 of overlap counts by default
		expect(rectLib.overlaps(a, byHalf, 0.5)).toBe(false) -- ...and is forgiven at 0.5
	end)

	it("intersection reports the depth on both axes, which is what a report prints", function()
		local dx, dy = rectLib.intersection(a, { x = 6, y = 8, w = 10, h = 10 })
		expect(dx).toBe(4)
		expect(dy).toBe(2)
		local mx, my = rectLib.intersection(a, { x = 20, y = 0, w = 5, h = 5 })
		expect(mx).toBe(-10)
		expect(my).toBe(5) -- a miss on ONE axis is a miss
	end)

	it("containment is exact by default and forgiving with an epsilon", function()
		expect(rectLib.contains(a, { x = 1, y = 1, w = 8, h = 8 })).toBe(true)
		expect(rectLib.contains(a, { x = 0, y = 0, w = 10, h = 10 })).toBe(true)
		local halfOut = { x = -0.5, y = 0, w = 10, h = 10 }
		expect(rectLib.contains(a, halfOut)).toBe(false)
		expect(rectLib.contains(a, halfOut, 0.5)).toBe(true)
	end)

	--[[ THE ONE THAT COULD NOT BE MERGED. A tap exactly on a shared edge is inside
		for the modal-zone test and a miss for the drop test, and both are right for
		what they do — so both keep a name rather than one of them silently
		inheriting the other's answer. ]]
	it("the two edge conventions are two functions, and they disagree on the edge", function()
		expect(rectLib.containsClosed(a, 10, 5)).toBe(true)
		expect(rectLib.containsHalfOpen(a, 10, 5)).toBe(false)
		expect(rectLib.containsClosed(a, 5, 10)).toBe(true)
		expect(rectLib.containsHalfOpen(a, 5, 10)).toBe(false)
		-- ...and they agree everywhere else
		for _, p in { { 0, 0 }, { 5, 5 }, { 9.9, 9.9 }, { -1, 5 }, { 5, 11 } } do
			local x, y = p[1], p[2]
			expect(`closed({x},{y}): {rectLib.containsClosed(a, x, y)}`).toBe(
				`closed({x},{y}): {rectLib.containsHalfOpen(a, x, y)}`
			)
		end
	end)

	it("equality is field-for-field and nil-tolerant on both sides", function()
		expect(rectLib.equal(a, { x = 0, y = 0, w = 10, h = 10 })).toBe(true)
		expect(rectLib.equal(a, { x = 0, y = 0, w = 10, h = 11 })).toBe(false)
		expect(rectLib.equal(nil, nil)).toBe(true) -- no rect then, no rect now: unchanged
		expect(rectLib.equal(a, nil)).toBe(false)
		expect(rectLib.equal(nil, a)).toBe(false)
	end)

	it("centre tolerates an unmeasured target, and round snaps all four fields", function()
		local cx, cy = rectLib.centre(a)
		expect(cx).toBe(5)
		expect(cy).toBe(5)
		local ux, uy = rectLib.centre({ x = 4, y = 6 } :: any)
		expect(ux).toBe(4)
		expect(uy).toBe(6)
		expect(rectLib.round({ x = 0.5, y = 1.4, w = 9.5, h = 10.6 })).toEqual({ x = 1, y = 1, w = 10, h = 11 })
	end)
end)

--[[ THE DEFECT ITSELF, THROUGH THE PUBLIC SURFACE. Not a unit test of the helper:
	the finding is that the PRESENTER used the unsafe form to decide which surface
	a tap belongs to, so the proof has to be a tap. ]]
describe("REUSE-3: a tap on /MenuBar does not route to /Menu", function()
	--[[ THE R12 TRIGGER, HONOURED (R5 review §3c-2). The ledger's follow-up rule
		is "the next spec file that ADDS a builder migrates its file" — and this
		file added one, in the same wave that wrote the rule, hours before the
		substrate landed. `tests/lib/world.luau` owns the construction and its two
		invariants; this is the shim, in the one order the suite has. ]]
	local function world()
		local w = worldLib.new({ viewport = { x = 0, y = 0, w = 390, h = 844 } })
		return w.core, w.env, w.adapter, w.system, w.pres
	end

	it("the longer-named screen owns its own button, whichever order they were presented", function()
		local _core, _env, adapter, _system, pres = world()
		local fired: { string } = {}

		--[[ `MenuBar` FIRST, `Menu` SECOND. That order is the whole reproduction:
			`handleByPath` searches the stack from the TOP so a modal above wins, and
			`/Menu` is a raw string prefix of `/MenuBar/Save`. With the safe test the
			search skips `Menu` and reaches `MenuBar`; with the raw one it stops at the
			first screen whose id happens to start the same way. ]]
		pres.present(UI.Screen({
			id = "MenuBar",
			children = {
				UI.Button({
					id = "Save",
					label = "Save",
					onActivate = function()
						table.insert(fired, "MenuBar/Save")
					end,
				}),
			},
		}))
		pres.present(UI.Screen({
			id = "Menu",
			children = {
				UI.Button({
					id = "Open",
					label = "Open",
					onActivate = function()
						table.insert(fired, "Menu/Open")
					end,
				}),
			},
		}))
		pres.refresh()

		adapter.tap("/MenuBar/Save")
		expect(table.concat(fired, ",")).toBe("MenuBar/Save")
	end)

	-- the control: the SAME two screens with no shared prefix must behave the same,
	-- so a green above is about the prefix rule and not about presentation order
	it("POSITIVE CONTROL: two screens with unrelated names route the same way", function()
		local _core, _env, adapter, _system, pres = world()
		local fired: { string } = {}
		pres.present(UI.Screen({
			id = "Toolbar",
			children = {
				UI.Button({
					id = "Save",
					label = "Save",
					onActivate = function()
						table.insert(fired, "Toolbar/Save")
					end,
				}),
			},
		}))
		pres.present(UI.Screen({
			id = "Menu",
			children = { UI.Button({ id = "Open", label = "Open" }) },
		}))
		pres.refresh()
		adapter.tap("/Toolbar/Save")
		expect(table.concat(fired, ",")).toBe("Toolbar/Save")
	end)
end)
