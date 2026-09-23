--!strict
--[[ M74 "View" capabilities as recipes over the existing primitives (phase6 P6a
	items 14-16; docs/guide/17-recipes.md §17.7). Each case asserts SOLVED rects
	or mounted paint data, never the numbers it authored. There is no catchall
	View constructor. ]]
local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect
local world = require("./lib/world")
local Facet = require("../src") :: any
local Compose = Facet.Compose

local function mount(content: (UI: any) -> { any }, why: string?): any
	local w = world.new({
		viewport = { x = 0, y = 0, w = 800, h = 700 },
		reducedMotion = true,
		overflowGuardOff = why,
	})
	local UI = w.UI
	w.present(function()
		return UI.Screen("S")({ padding = 0, gap = 0, table.unpack(content(UI)) })
	end)
	w.settle(2)
	return w
end

local function rect(w: any, path: string): any
	return w.adapter.node(path).rect
end

local function fixed(px: number): any
	return { type = "fixed", px = px }
end

describe("View recipes (M74)", function()
	it("a styled group with one activation, disabled by inheritance", function()
		local taps = 0
		local enabled = Compose.cell(true)
		local w = mount(function(UI)
			return {
				UI.ZStack("Group")({
					surface = "raised",
					enabled = enabled,
					UI.Button("Act")({
						label = "Count",
						onActivate = function()
							taps += 1
						end,
					}),
				}),
			}
		end)
		w.adapter.tap("/S/Group/Act")
		enabled:set(false)
		w.settle(1)
		w.adapter.tap("/S/Group/Act")
		expect(taps).toBe(1)
	end)

	it("fixed, percent, fill, hug and minimum axes; a fixed axis lets its child overflow", function()
		local w = mount(function(UI)
			return {
				UI.HStack("Row")({
					width = fixed(400),
					height = fixed(60),
					UI.Box("Fixed")({ width = fixed(160), height = fixed(48) }),
					UI.Box("Percent")({ width = { type = "percent", fraction = 0.25 }, height = fixed(10) }),
					UI.Box("Fill")({ width = UI.fill(), height = fixed(10) }),
				}),
				UI.VStack("Hug")({ UI.Box("Child")({ width = fixed(70), height = fixed(30) }) }),
				UI.frame(UI.VStack("Min")({ UI.Box("Small")({ width = fixed(10), height = fixed(10) }) }), {
					minWidth = 120,
				}),
				UI.ZStack("Tight")({
					width = fixed(100),
					height = fixed(40),
					overflow = "intentionalOverlap",
					UI.Box("Wide")({ width = fixed(160), height = fixed(20) }),
				}),
			}
		end)
		expect(rect(w, "/S/Row/Fixed").w).toBe(160)
		expect(rect(w, "/S/Row/Percent").w).toBe(100)
		expect(rect(w, "/S/Row/Fill").w).toBe(140)
		expect(rect(w, "/S/Hug").w).toBe(70)
		expect(rect(w, "/S/Hug").h).toBe(30)
		expect(rect(w, "/S/Min").w).toBe(120)
		expect(rect(w, "/S/Tight").w).toBe(100)
		expect(rect(w, "/S/Tight/Wide").w).toBe(160)
	end)

	it("1:1, 16:9 and 9:16 all fit inside the same 96x96 offer", function()
		local ratios = { 1, 16 / 9, 9 / 16 }
		local w = mount(function(UI)
			local cells = {}
			for i, r in ratios do
				table.insert(
					cells,
					UI.ZStack(`Offer{i}`)({
						width = fixed(96),
						height = fixed(96),
						alignH = "center",
						alignV = "center",
						UI.Box("Subject")({
							width = fixed(96 * math.min(1, r)),
							height = fixed(96 / math.max(1, r)),
						}),
					})
				)
			end
			return { UI.HStack("Ratios")({ gap = 8, table.unpack(cells) }) }
		end)
		local expected = { "96x96", "96x54", "54x96" }
		for i in ratios do
			local r = rect(w, `/S/Ratios/Offer{i}/Subject`)
			expect(`{math.floor(r.w + 0.5)}x{math.floor(r.h + 0.5)}`).toBe(expected[i])
		end
	end)

	it("scale paints larger or smaller while the solved and input rects stay put", function()
		local w = mount(function(UI)
			local cells = {}
			for i, s in { 0.75, 1, 1.5 } do
				table.insert(
					cells,
					UI.ZStack(`Scaled{i}`)({ scale = s, UI.Button("Tap")({ label = "Tap", width = fixed(80) }) })
				)
			end
			return { UI.HStack("Scales")({ gap = 40, table.unpack(cells) }) }
		end, "the 1.5 scale paints past its box by design")
		local a, b, c =
			rect(w, "/S/Scales/Scaled1/Tap"), rect(w, "/S/Scales/Scaled2/Tap"), rect(w, "/S/Scales/Scaled3/Tap")
		expect(a.w == b.w and b.w == c.w and a.h == b.h and b.h == c.h).toBe(true)
		expect(w.adapter.node("/S/Scales/Scaled3").motionScaleInstance.scale).toBe(1.5)
		expect(w.adapter.node("/S/Scales/Scaled1").motionScaleInstance.scale).toBe(0.75)
	end)

	it("group opacity fades a nested subtree as one group; zero still focuses, hidden does not", function()
		local w = mount(function(UI)
			local groups = {}
			for i, o in { 1, 0.75, 0.5, 0.25, 0 } do
				table.insert(
					groups,
					UI.ZStack(`Fade{i}`)({
						opacity = o,
						UI.VStack("Inner")({
							UI.Text("Child")({ text = "Child" }),
							UI.Button("Bar")({ label = "Bar" }),
						}),
					})
				)
			end
			table.insert(groups, UI.ZStack("Gone")({ hidden = true, UI.Button("Bar")({ label = "Bar" }) }))
			return { UI.HStack("Fades")({ gap = 8, table.unpack(groups) }) }
		end)
		for i, o in { 1, 0.75, 0.5, 0.25, 0 } do
			local group = w.adapter.node(`/S/Fades/Fade{i}`).canvasGroupInstance
			expect(math.abs(group.groupTransparency - (1 - o)) < 1e-6).toBe(true)
		end
		expect(w.pres.focus.focusOn("/S/Fades/Fade5/Inner/Bar")).toBe(true)
		expect(w.pres.focus.focusOn("/S/Fades/Gone/Bar")).toBe(false)
	end)

	it("nine alignments move a child through spare room; a hugging parent has none", function()
		local spots = {}
		local w = mount(function(UI)
			local cells = {}
			for _, v in { "start", "center", "end" } do
				for _, h in { "start", "center", "end" } do
					table.insert(spots, `{h}-{v}`)
					table.insert(
						cells,
						UI.ZStack(`{h}-{v}`)({
							width = fixed(60),
							height = fixed(60),
							alignH = h,
							alignV = v,
							UI.Box("Dot")({ width = fixed(20), height = fixed(20) }),
						})
					)
				end
			end
			table.insert(
				cells,
				UI.ZStack("Hugging")({ alignH = "end", UI.Box("Dot")({ width = fixed(20), height = fixed(20) }) })
			)
			return { UI.HStack("Align")({ gap = 4, table.unpack(cells) }) }
		end)
		local seen: { [string]: boolean } = {}
		for _, spot in spots do
			local p, d = rect(w, `/S/Align/{spot}`), rect(w, `/S/Align/{spot}/Dot`)
			seen[`{d.x - p.x},{d.y - p.y}`] = true
		end
		local distinct = 0
		for _ in seen do
			distinct += 1
		end
		expect(distinct).toBe(9)
		expect(seen["40,40"]).toBe(true)
		local h, d = rect(w, "/S/Align/Hugging"), rect(w, "/S/Align/Hugging/Dot")
		expect(d.x).toBe(h.x)
	end)

	it("gaps space siblings without insetting them; a per-edge padding moves only its edge", function()
		local w = mount(function(UI)
			return {
				UI.HStack("Gap")({
					gap = 24,
					UI.Box("A")({ width = fixed(10), height = fixed(10) }),
					UI.Box("B")({ width = fixed(10), height = fixed(10) }),
				}),
				UI.VStack("Pad")({
					padding = { top = 8, bottom = 8, left = 32, right = 8 },
					UI.Box("C")({ width = fixed(10), height = fixed(10) }),
				}),
			}
		end)
		local g, a, b = rect(w, "/S/Gap"), rect(w, "/S/Gap/A"), rect(w, "/S/Gap/B")
		expect(a.x).toBe(g.x)
		expect(b.x - (a.x + a.w)).toBe(24)
		local p, c = rect(w, "/S/Pad"), rect(w, "/S/Pad/C")
		expect(c.x - p.x).toBe(32)
		expect(c.y - p.y).toBe(8)
		expect(p.w).toBe(50)
	end)

	it("wrap moves children to a second line; no-wrap overruns; clip cuts at the edge", function()
		local w = mount(function(UI)
			local function three(): { any }
				return {
					UI.Box("One")({ width = fixed(80), height = fixed(20) }),
					UI.Box("Two")({ width = fixed(80), height = fixed(20) }),
					UI.Box("Three")({ width = fixed(80), height = fixed(20) }),
				}
			end
			return {
				UI.HStack("Wrap")({ width = fixed(200), wrap = true, table.unpack(three()) }),
				UI.HStack("NoWrap")({ width = fixed(200), overflow = "intentionalOverlap", table.unpack(three()) }),
				UI.HStack("Clip")({ width = fixed(200), overflow = "clip", table.unpack(three()) }),
			}
		end)
		local wrap = rect(w, "/S/Wrap/Three")
		expect(wrap.y > rect(w, "/S/Wrap/One").y).toBe(true)
		local nowrap = rect(w, "/S/NoWrap/Three")
		expect(nowrap.x + nowrap.w > rect(w, "/S/NoWrap").x + 200).toBe(true)
		expect(w.adapter.node("/S/Clip").props.clipChildren).toBe(true)
		expect(w.adapter.node("/S/NoWrap").props.clipChildren ~= true).toBe(true)
	end)

	it("mixed per-corner rounding, an authored stroke and a shadow are data on one node", function()
		local w = mount(function(UI)
			return {
				UI.shadow(
					UI.stroke(
						UI.corners(UI.Box("Styled")({ width = fixed(80), height = fixed(40), surface = "raised" }), {
							topLeft = 16,
							bottomRight = 16,
						}),
						{ thickness = 2, color = "accent" }
					),
					"raised"
				),
			}
		end)
		local props = w.adapter.node("/S/Styled").props
		expect(props.corners.topLeft).toBe(16)
		expect(props.corners.topRight).toBe(0)
		expect(props.corners.bottomRight).toBe(16)
		expect(props.stroke ~= nil).toBe(true)
		expect(props.shadow ~= nil).toBe(true)
	end)
end)

return nil
