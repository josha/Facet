--!strict
--[[
	THE LYING `itemExtent` GUARD (game-director approved 2026-08-13).

	`newVirtualList` windows by `index × itemExtent`. That arithmetic is O(1) and
	EXACT only because the extent is one declared number — and the control makes
	the CONSUMER responsible for predicting its own row's height, for every input
	that could change it. Until this guard, nothing checked the prediction.

	THE CASE STUDY is the performance lab's own `rows.heightFor`, whose comments
	record it learning each input only AFTER that input broke something: the
	viewport width, then the type scale (the ten-foot row overflowed its 56px slot
	by 3px), then the theme insets (19px under fantasy-ornate), and — found on a
	real device on 2026-08-13 — never the accessibility text preference. At
	`preferredTextOffset` 4/10/14 every row overflowed its slot and the lab
	refused to mount. Four inputs, three of them added post-mortem, and the class
	is `docs/lessons/luauui-fixed-px-heights.md`: a px height fixed against
	unfixed content.

	The ruling was NOT to build variable extents (a subsystem, and it changes what
	the perf harness measures) but to build the CHECK — because it catches every
	consumer's version of this at once.

	WHAT THE GUARD IS. `virtual_list.luau` stamps each row ZStack with
	`virtualSlot = { list, axis, extent, contentFrom }` — the DECLARED extent,
	shared by every row of the list — and the solver's ZStack arrange compares the
	slot content's measure against it on the list's axis, reusing the measure the
	overlap diagnostic already takes. Too TALL is the defect; shorter is fine (the
	lab over-reserves on purpose). The finding names BOTH numbers, and the node it
	is filed under is the row's own path, key included.

	The fixture below is a clean-room copy of the lab row's SHAPE (avatar, a
	VStack of primary/secondary text) — the lab's own file is never imported, so
	this spec cannot be repaired by editing the lab.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local LuauUI = require("../src") :: any
local fake_target = require("./lib/fake_target")
local virtual_list = require("../src/controls/virtual_list")

local UI = LuauUI.UI

local SLOT = 56

local function makeRows(n: number): { any }
	local out = {}
	for i = 1, n do
		table.insert(out, { id = `r{i}`, name = `Racer {i}`, detail = `lap detail {i}` })
	end
	return out
end

type WorldOpts = {
	offset: number?,
	itemExtent: number?,
	cell: string?,
	axis: string?,
	hide: boolean?,
}

-- the lab row's shape, rebuilt from the plan's own words ("an image, a `VStack`
-- of primary/secondary text"), never imported from the lab
local function labCell(item: any, kind: string): any
	local labels = UI.VStack({
		id = "Labels",
		gap = 2,
		children = {
			UI.Text({ id = "Name", text = item.name, textSize = 14 }),
			UI.Text({ id = "Detail", text = item.detail, textSize = 12 }),
		},
	})
	local props: any = {
		id = "Cell",
		gap = 8,
		padding = 8,
		align = "center",
		children = {
			UI.Box({
				id = "Avatar",
				width = { type = "fixed", px = 40 },
				height = { type = "fixed", px = 40 },
			}),
			labels,
		},
	}
	if kind == "fill" then
		-- THE SHAPE THE OLD FILL GATE WAS BLIND TO: a cell that declares it fills
		-- its slot does not thereby FIT it — `measure` answers `fill` with content.
		props.width = { type = "fill", weight = 1 }
		props.height = { type = "fill", weight = 1 }
	end
	return UI.HStack(props)
end

local function cellFor(kind: string): (any) -> any
	return function(item: any): any
		if kind == "short" then
			-- legitimately SHORTER than its slot: the deliberate over-reservation the
			-- lab's own ROW_HEIGHT comment calls the correct direction
			return UI.Box({
				id = "Cell",
				width = { type = "fill", weight = 1 },
				height = { type = "fixed", px = 24 },
			})
		end
		if kind == "scroller" then
			-- a cell that ABSORBS its own overflow: 900px of content inside a filling
			-- scroller that will scroll it. Not a lying extent.
			return UI.ScrollView({
				id = "Cell",
				axis = "y",
				width = { type = "fill", weight = 1 },
				height = { type = "fill", weight = 1 },
				children = {
					UI.Box({
						id = "Tall",
						width = { type = "fill", weight = 1 },
						height = { type = "fixed", px = 900 },
					}),
				},
			})
		end
		if kind == "tiny" then
			-- comfortably inside a dense 16px slot: the only thing in this row that
			-- measures more is the control's own hit
			return UI.Box({
				id = "Cell",
				width = { type = "fill", weight = 1 },
				height = { type = "fixed", px = 12 },
			})
		end
		if kind == "wide" then
			-- overflows ACROSS the list's axis only: a different defect, and the
			-- generic ZStack overlap finding must keep reporting it
			return UI.Box({
				id = "Cell",
				width = { type = "fixed", px = 1600 },
				height = { type = "fixed", px = 20 },
			})
		end
		if kind == "card" then
			-- the horizontal-axis fixture: a card WIDER than the strip's itemExtent
			return UI.Box({
				id = "Cell",
				width = { type = "fixed", px = 210 },
				height = { type = "fill", weight = 1 },
			})
		end
		return labCell(item, kind)
	end
end

local function world(opts: WorldOpts): any
	local core = LuauUI.newCore()
	local env = LuauUI.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = 900, h = 600 })
	env:set("preferredTextOffset", opts.offset or 0)
	local system = LuauUI.newActionSystem(core)
	local adapter = fake_target.new()
	local presenter = LuauUI.newPresenter(core, env, adapter, system)
	local list = LuauUI.newVirtualList(LuauUI, core, {
		id = "VL",
		axis = opts.axis,
		rows = core:signal(makeRows(60)),
		key = function(item: any)
			return item.id
		end,
		itemExtent = opts.itemExtent or SLOT,
		viewportExtent = 300,
		overscan = 1,
		cell = cellFor(opts.cell or "hug"),
	})
	local screen: any
	if opts.hide then
		-- the deliberate zero-rect case: a LOSING ViewThatFits candidate is
		-- measured and arranged hidden on purpose, and a hidden subtree is not a
		-- defect. Every diagnostic in the solver is `hiddenDepth`-gated; this one
		-- must be too.
		screen = UI.Screen({
			id = "Root",
			children = {
				UI.ViewThatFits({
					id = "Fits",
					children = {
						UI.VStack({
							id = "TooWide",
							width = { type = "fixed", px = 4000 },
							children = { list.blueprint },
						}),
						UI.Text({ id = "Fallback", text = "narrow", textSize = 12 }),
					},
				}),
			},
		})
	else
		screen = UI.Screen({ id = "Root", children = { list.blueprint } })
	end
	local handle = presenter.present(screen, {})
	presenter.refresh()
	return handle
end

-- the guard's findings, told from every other solver finding by the one phrase
-- that makes it worth having: it names the declared field
local function slotFindings(handle: any): { any }
	local out = {}
	for _, d in handle.controller.diagnostics() do
		if string.find(d.issue, "itemExtent", 1, true) ~= nil then
			table.insert(out, d)
		end
	end
	return out
end

local function findingsMatching(handle: any, needle: string): { any }
	local out = {}
	for _, d in handle.controller.diagnostics() do
		if string.find(d.issue, needle, 1, true) ~= nil then
			table.insert(out, d)
		end
	end
	return out
end

describe("newVirtualList: a lying itemExtent is named, with both numbers", function()
	it("FIRES on the pre-fix lab shape and names the declared extent AND the measure", function()
		-- the exact device case: a 56px slot predicted without the accessibility
		-- text preference, at `preferredTextOffset` 10
		local handle = world({ offset = 10 })
		local found = slotFindings(handle)
		expect(#found > 0).toBe(true)
		local issue = found[1].issue
		-- BOTH NUMBERS. A boolean assert is worthless here: the whole value of this
		-- finding is that a reader learns what they declared and what it really is.
		expect(string.find(issue, "itemExtent = 56", 1, true) ~= nil).toBe(true)
		expect(string.find(issue, "measures 74px", 1, true) ~= nil).toBe(true)
		-- ...AND THE ROW. The finding is filed under the row's own path, which
		-- carries the key the ForEach mounted it under.
		expect(string.find(found[1].node, "/W/[r1]/Row/", 1, true) ~= nil).toBe(true)
		-- the list says its own name, so a finding read on its own is actionable
		expect(string.find(issue, "'VL'", 1, true) ~= nil).toBe(true)
		-- ONE finding per row, not two: the axis this names is taken out of the
		-- sibling overlap finding, which would otherwise report the same px again
		-- with the repair advice a windowed row must not follow
		expect(#findingsMatching(handle, "overflows its zstack")).toBe(0)
	end)

	it("names the RIGHT numbers at every step of the preference (4 -> 60, 14 -> 84)", function()
		local at4 = slotFindings(world({ offset = 4 }))
		expect(#at4 > 0).toBe(true)
		expect(string.find(at4[1].issue, "measures 60px", 1, true) ~= nil).toBe(true)
		local at14 = slotFindings(world({ offset = 14 }))
		expect(#at14 > 0).toBe(true)
		expect(string.find(at14[1].issue, "measures 84px", 1, true) ~= nil).toBe(true)
	end)

	it("is SILENT on the fixed shape — the same rows in a slot that tells the truth", function()
		-- what `rows.heightFor` produces once it has learned the preference: a slot
		-- big enough at offset 10. Nothing to say.
		expect(#slotFindings(world({ offset = 10, itemExtent = 84 }))).toBe(0)
		-- and at the default preference the pre-fix 56 was never a lie
		expect(#slotFindings(world({ offset = 0 }))).toBe(0)
	end)

	it("is SILENT on a row that is legitimately SHORTER than its slot", function()
		-- the deliberate over-reservation: the lab's own rule is that a slot a few
		-- px too TALL is the correct direction. Only content taller than its slot
		-- is the defect.
		expect(#slotFindings(world({ cell = "short" }))).toBe(0)
	end)

	it("SEES a cell that declares `height = fill` — filling a slot is not fitting it", function()
		-- the generic ZStack overlap finding cannot see this shape at all: a fill
		-- axis is granted the box at arrange, so its gate skips it, and all the
		-- consumer gets is a finding on some inner stack that never mentions the
		-- slot. A VirtualList row is a DECLARED CAP, not a grant.
		local found = slotFindings(world({ offset = 10, cell = "fill" }))
		expect(#found > 0).toBe(true)
		expect(string.find(found[1].issue, "itemExtent = 56", 1, true) ~= nil).toBe(true)
		expect(string.find(found[1].issue, "measures 74px", 1, true) ~= nil).toBe(true)
		-- ...and it stays silent when the same fill cell fits
		expect(#slotFindings(world({ offset = 0, cell = "fill" }))).toBe(0)
	end)

	it("is SILENT on a cell that ABSORBS its own overflow (a scroller on the list's axis)", function()
		-- 900px of content in a 56px slot, inside a scroller that will scroll it.
		-- Lifting the fill gate must not re-introduce the false positive
		-- `zstack_fill_diagnostic.spec` was written to kill.
		expect(#slotFindings(world({ cell = "scroller" }))).toBe(0)
	end)

	it("is SILENT inside a hidden subtree (a losing ViewThatFits candidate)", function()
		expect(#slotFindings(world({ offset = 14, hide = true }))).toBe(0)
	end)

	it("still reports a CROSS-axis overflow through the generic overlap finding", function()
		-- a 1600px cell in a ~900px row is a real defect and a DIFFERENT one; the
		-- slot guard must not swallow it
		local handle = world({ cell = "wide" })
		expect(#slotFindings(handle)).toBe(0)
		expect(#findingsMatching(handle, "overflows its zstack") > 0).toBe(true)
	end)

	it("never accuses the list's OWN furniture: a 16px slot, and the row hit is 24px", function()
		-- the control's full-row hit Button is child 1 of every row and measures its
		-- own chrome (24px with an empty label) whatever the slot is. It is granted
		-- the box — it is a `fill` on both axes — and it is not the consumer's cell,
		-- so `contentFrom = 2` keeps it out of the comparison. Without that, every
		-- dense list would be accused of a lie the framework itself wrote.
		local handle = world({ itemExtent = 16, cell = "tiny" })
		expect(#slotFindings(handle)).toBe(0)
	end)

	it("compares against the DECLARED extent, never the row's current box", function()
		-- Proved through the public prop, because the shape that needs it is a
		-- hosted row-actions commit collapse: that drives ONE row's box down its own
		-- height ladder on purpose, and a guard reading the box would shout through
		-- the whole animation. Here the box is 20px and the declared extent 56px —
		-- content of 40px is inside the promise and must say nothing.
		local core = LuauUI.newCore()
		local env = LuauUI.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 300 })
		local presenter = LuauUI.newPresenter(core, env, fake_target.new(), LuauUI.newActionSystem(core))
		local handle = presenter.present(
			UI.Screen({
				id = "Root",
				children = {
					UI.ZStack({
						id = "Row",
						virtualSlot = { list = "Collapsing", extent = 56 },
						-- NO `overflow` opt-out here, deliberately: declaring one skips the
						-- whole diagnostic block and this case would then pass whatever the
						-- guard compares against — a check that proves nothing. The sibling
						-- overlap finding does fire on this shape (40 > 20) and is ignored;
						-- `slotFindings` counts only findings that name `itemExtent`.
						width = { type = "fixed", px = 300 },
						height = { type = "fixed", px = 20 }, -- mid-collapse
						children = {
							UI.Box({
								id = "Cell",
								width = { type = "fill", weight = 1 },
								height = { type = "fixed", px = 40 },
							}),
						},
					}),
				},
			}),
			{}
		)
		presenter.refresh()
		expect(#slotFindings(handle)).toBe(0)
	end)

	it("refuses a garbled slot declaration at construction", function()
		-- the guard is only worth trusting if what feeds it is: a bad `extent` would
		-- either shout at every honest row or silence a real defect
		local ok, err = pcall(function()
			return UI.ZStack({ id = "Row", virtualSlot = { list = "X", extent = 0 } })
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "extent", 1, true) ~= nil).toBe(true)
	end)

	it("A FIXED ROW STOPS BEING REPORTED — the finding does not outlive the defect", function()
		--[[ FOUND BY A SURVIVING MUTATION, 2026-08-15, and it is worth the whole
			paragraph because a stale finding is the one failure mode this instrument
			cannot survive: `tests/overflow_sweep.spec.luau` fails the suite on this
			channel, so a finding that outlives its defect reports a bug that is
			already fixed and sends the next agent to repair working code.

			THE MECHANISM. Incremental layout skips a subtree it can prove did not
			change and REPLAYS that subtree's findings, gated on "was the node that
			FILED this finding skipped?" (`solver.solve`'s replay loop). This finding is
			filed by the row ZSTACK and names its CHILD — the exact `filedBy` split
			`inertPlacement` was stamped for — so the gate was asking about the wrong
			node: the row was walked and filed nothing, its content child landed on the
			rect it already had and was skipped, and the old "declares itemExtent = 20"
			was copied forward on every solve forever.

			THE CASE IS THE ONE THAT MATTERS IN PRACTICE: a per-item extent that
			re-derives correctly after the text preference moves. Under the bug, the
			list that had just been FIXED went on shouting the old number. ]]
		local core = LuauUI.newCore()
		local env = LuauUI.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local adapter = fake_target.new()
		local pres = LuauUI.newPresenter(core, env, adapter, LuauUI.newActionSystem(core))
		local rows = core:signal({ { id = "a" }, { id = "b" }, { id = "c" } })
		local declared = core:signal(20)
		local list = virtual_list.build(LuauUI, core, {
			id = "VL",
			rows = rows,
			key = function(item: any)
				return item.id
			end,
			-- a PER-ITEM extent that reads its live fact through `use`, which is the
			-- shape the feature exists for — and the shape that gets it right on the
			-- second try
			itemExtent = function(_item: any, _index: number, use: any)
				return use(declared)
			end,
			viewportExtent = 600,
			cell = function()
				return LuauUI.UI.Box({
					id = "Plate",
					width = { type = "fill", weight = 1 },
					height = { type = "fixed", px = 60 },
				})
			end,
		})
		local handle = pres.present(LuauUI.UI.Screen({ id = "S", children = { list.blueprint } }))
		local function slotCount(): number
			local n = 0
			for _, d in handle.controller.diagnostics() do
				if string.find(d.issue, "declares itemExtent", 1, true) ~= nil then
					n += 1
				end
			end
			return n
		end
		-- 20 declared against a 60px plate: every row is a finding, which is the
		-- guard doing its job and is what makes the silence below mean something
		expect(slotCount() > 0).toBe(true)
		-- ...the consumer fixes the declaration, exactly as the accessibility case
		-- would fix it live
		declared:set(60)
		pres.refresh()
		pres.refresh()
		expect(slotCount()).toBe(0)
		list.dispose()
	end)

	it("speaks the AXIS: a horizontal strip's item is too WIDE for its itemExtent", function()
		local handle = world({ axis = "x", itemExtent = 180, cell = "card" })
		local found = slotFindings(handle)
		expect(#found > 0).toBe(true)
		expect(string.find(found[1].issue, "itemExtent = 180", 1, true) ~= nil).toBe(true)
		expect(string.find(found[1].issue, "measures 210px", 1, true) ~= nil).toBe(true)
		expect(string.find(found[1].issue, "wider", 1, true) ~= nil).toBe(true)
	end)
end)
