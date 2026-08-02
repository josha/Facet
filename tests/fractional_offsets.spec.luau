--!strict
-- FRACTIONAL ANCHOR OFFSETS (ADR-0022 Decision 6; acceptance rows SF-P5/SF-K1).
--
-- The marker-overlay shape: a minimap dot's position is a SHARE of the map, not a
-- pixel count, and the game's projection math produces u,v in 0..1. Before this an
-- author had to multiply by a width nobody had yet — the anchor's inner extent is
-- only known at arrange — so every marker layer carried its own copy of the
-- solver's arithmetic and re-derived it on every viewport change.
--
-- The contract proven here: the fraction is spent at ARRANGE against the parent's
-- inner box, offsets stay arrange-only (no re-measure, no remount, so a moving dot
-- never blinks), and a viewport change re-resolves them like every other layout
-- input.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local customFactory = require("../src/core/custom")
local UI = require("../src/blueprint")
local mountLib = require("../src/mount")
local environment = require("../src/env/environment")
local rendererLib = require("../src/render/renderer")
local themeSnapshot = require("../src/themes/snapshot")
local fake_target = require("./lib/fake_target")

local function harness(screen: any, w: number?, h: number?)
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = w or 400, h = h or 600 })
	env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
	local root = mountLib.mount(core, screen)
	local adapter = fake_target.new()
	local controller = rendererLib.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
	controller.initialRender()
	return adapter, controller, core, env
end

local function fails(fn: () -> ()): string
	local ok, err = pcall(fn)
	expect(ok).toBe(false)
	return tostring(err)
end

local DOT = { type = "fixed", px = 10 }

describe("Anchor: fractional offsets", function()
	it("places a child at a share of the anchor's inner width and height", function()
		local adapter = harness(UI.Screen({
			id = "S",
			padding = 0,
			children = {
				UI.Anchor({
					id = "Map",
					width = { type = "fixed", px = 200 },
					height = { type = "fixed", px = 100 },
					children = {
						UI.Box({
							id = "Dot",
							anchor = "topLeft",
							width = DOT,
							height = DOT,
							offsetX = { scale = 0.5 },
							offsetY = { scale = 0.25 },
						}),
					},
				}),
			},
		}))
		local map = adapter.node("/S/Map").rect
		local dot = adapter.node("/S/Map/Dot").rect
		expect(dot.x).toBe(map.x + 100)
		expect(dot.y).toBe(map.y + 25)
	end)

	it("adds the px part on top of the fraction (a dot centred on its own point)", function()
		local adapter = harness(UI.Screen({
			id = "S",
			padding = 0,
			children = {
				UI.Anchor({
					id = "Map",
					width = { type = "fixed", px = 200 },
					height = { type = "fixed", px = 200 },
					children = {
						UI.Box({
							id = "Dot",
							anchor = "topLeft",
							width = DOT,
							height = DOT,
							offsetX = { scale = 0.5, offset = -5 },
							offsetY = { scale = 0.5, offset = -5 },
						}),
					},
				}),
			},
		}))
		local map = adapter.node("/S/Map").rect
		local dot = adapter.node("/S/Map/Dot").rect
		expect(dot.x).toBe(map.x + 95)
		expect(dot.y).toBe(map.y + 95)
	end)

	it("the px part may itself be a THEME METRIC name", function()
		local adapter = harness(UI.Screen({
			id = "S",
			padding = 0,
			children = {
				UI.Anchor({
					id = "Map",
					width = { type = "fixed", px = 100 },
					height = { type = "fixed", px = 100 },
					children = {
						UI.Box({
							id = "Dot",
							anchor = "topLeft",
							width = DOT,
							height = DOT,
							offsetX = { scale = 0.5, offset = "s" },
						}),
					},
				}),
			},
		}))
		local step = themeSnapshot.neutral().space.s
		local map = adapter.node("/S/Map").rect
		expect(adapter.node("/S/Map/Dot").rect.x).toBe(map.x + 50 + step)
	end)

	it("respects the anchor's own PADDING: the fraction is of the INNER box", function()
		local adapter = harness(UI.Screen({
			id = "S",
			padding = 0,
			children = {
				UI.Anchor({
					id = "Map",
					padding = 10,
					width = { type = "fixed", px = 220 },
					height = { type = "fixed", px = 120 },
					children = {
						UI.Box({ id = "Dot", anchor = "topLeft", width = DOT, height = DOT, offsetX = { scale = 0.5 } }),
					},
				}),
			},
		}))
		local map = adapter.node("/S/Map").rect
		-- inner width is 220 - 20 = 200, so half of it is 100 from the inner edge
		expect(adapter.node("/S/Map/Dot").rect.x).toBe(map.x + 10 + 100)
	end)

	it("composes with the anchor CORNER, which is what makes a centred marker layer work", function()
		local adapter = harness(UI.Screen({
			id = "S",
			padding = 0,
			children = {
				UI.Anchor({
					id = "Map",
					width = { type = "fixed", px = 200 },
					height = { type = "fixed", px = 200 },
					children = {
						UI.Box({
							id = "Dot",
							anchor = "center",
							width = DOT,
							height = DOT,
							offsetX = { scale = 0.25 },
						}),
					},
				}),
			},
		}))
		local map = adapter.node("/S/Map").rect
		-- centred (200-10)/2 = 95, plus a quarter of the inner width
		expect(adapter.node("/S/Map/Dot").rect.x).toBe(map.x + 95 + 50)
	end)

	it("NESTS: an inner anchor's fraction is of ITS box, not the screen's", function()
		local adapter = harness(UI.Screen({
			id = "S",
			padding = 0,
			children = {
				UI.Anchor({
					id = "Outer",
					width = { type = "fixed", px = 300 },
					height = { type = "fixed", px = 300 },
					children = {
						UI.Anchor({
							id = "Inner",
							anchor = "topLeft",
							offsetX = { scale = 0.5 },
							width = { type = "fixed", px = 100 },
							height = { type = "fixed", px = 100 },
							children = {
								UI.Box({
									id = "Dot",
									anchor = "topLeft",
									width = DOT,
									height = DOT,
									offsetX = { scale = 0.5 },
								}),
							},
						}),
					},
				}),
			},
		}))
		local outer = adapter.node("/S/Outer").rect
		expect(adapter.node("/S/Outer/Inner").rect.x).toBe(outer.x + 150)
		expect(adapter.node("/S/Outer/Inner/Dot").rect.x).toBe(outer.x + 150 + 50)
	end)

	it("re-resolves on a viewport change, like every other layout input", function()
		local adapter, controller, _, env = harness(
			UI.Screen({
				id = "S",
				padding = 0,
				children = {
					UI.Anchor({
						id = "Map",
						width = { type = "fill", weight = 1 },
						height = { type = "fixed", px = 100 },
						children = {
							UI.Box({
								id = "Dot",
								anchor = "topLeft",
								width = DOT,
								height = DOT,
								offsetX = { scale = 0.5 },
							}),
						},
					}),
				},
			}),
			400,
			600
		)
		expect(adapter.node("/S/Map/Dot").rect.x).toBe(200)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		controller.refresh()
		expect(adapter.node("/S/Map/Dot").rect.x).toBe(400)
	end)

	it("a MOVING marker costs an arrange and a rect write — no remount, no re-measure", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local u = core:signal({ scale = 0.1 } :: any)
		local root = mountLib.mount(
			core,
			UI.Screen({
				id = "S",
				padding = 0,
				children = {
					UI.Anchor({
						id = "Map",
						width = { type = "fixed", px = 200 },
						height = { type = "fixed", px = 200 },
						children = {
							UI.Box({ id = "Dot", anchor = "topLeft", width = DOT, height = DOT, offsetX = u }),
						},
					}),
				},
			})
		)
		local adapter = fake_target.new()
		local controller = rendererLib.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
		controller.initialRender()
		local mapX = adapter.node("/S/Map").rect.x
		expect(adapter.node("/S/Map/Dot").rect.x).toBe(mapX + 20)
		local identity = adapter.node("/S/Map/Dot")
		adapter.takeOps()
		u:set({ scale = 0.75 })
		controller.refresh()
		expect(adapter.node("/S/Map/Dot").rect.x).toBe(mapX + 150)
		-- the SAME node object: mounted identity survives (a dot that remounts blinks)
		expect(adapter.node("/S/Map/Dot")).toBe(identity)
		for _, op in adapter.takeOps() do
			expect(string.sub(op, 1, 4) == "rect" or string.sub(op, 1, 1) == "z").toBe(true)
		end
	end)

	it("a fill child still pays for its own fractional offset (the round-10 give-back)", function()
		local adapter = harness(UI.Screen({
			id = "S",
			padding = 0,
			children = {
				UI.Anchor({
					id = "Map",
					width = { type = "fixed", px = 200 },
					height = { type = "fixed", px = 100 },
					children = {
						UI.Box({
							id = "Column",
							anchor = "topLeft",
							width = { type = "fill", weight = 1 },
							height = { type = "fixed", px = 20 },
							offsetX = { scale = 0.25 },
						}),
					},
				}),
			},
		}))
		local map = adapter.node("/S/Map").rect
		local column = adapter.node("/S/Map/Column").rect
		-- pushed 50 in, so it may only be 150 wide: the far edge stays inside
		expect(column.x).toBe(map.x + 50)
		expect(column.x + column.w).toBeLessThanOrEqual(map.x + map.w)
	end)
end)

describe("Anchor: fractional offsets — the authoring boundary", function()
	it("rejects a fraction with no scale, and an unknown field", function()
		expect(string.find(
			fails(function()
				UI.Box({ id = "D", offsetX = { offset = 4 } })
			end),
			"scale must be a number",
			1,
			true
		) ~= nil).toBe(true)
		expect(string.find(
			fails(function()
				UI.Box({ id = "D", offsetY = { scale = 0.5, px = 4 } })
			end),
			"unknown fractional-offset field 'px'",
			1,
			true
		) ~= nil).toBe(true)
	end)

	it("rejects a metric NAME that names no metric inside the px part", function()
		local err = fails(function()
			UI.Box({ id = "D", offsetX = { scale = 0.5, offset = "hugeGap" } })
		end)
		expect(string.find(err, "names no theme metric", 1, true) ~= nil).toBe(true)
	end)

	it("keeps both older forms working untouched (a number and a metric name)", function()
		UI.Box({ id = "D", offsetX = 12, offsetY = "-s" })
		local adapter = harness(UI.Screen({
			id = "S",
			padding = 0,
			children = {
				UI.Anchor({
					id = "Map",
					width = { type = "fixed", px = 200 },
					height = { type = "fixed", px = 100 },
					children = {
						UI.Box({ id = "Dot", anchor = "topLeft", width = DOT, height = DOT, offsetX = 12 }),
					},
				}),
			},
		}))
		expect(adapter.node("/S/Map/Dot").rect.x).toBe(adapter.node("/S/Map").rect.x + 12)
	end)
end)
