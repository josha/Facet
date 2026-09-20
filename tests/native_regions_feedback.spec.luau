--!strict
-- What an application reaches through `app.controls`: region disclosure,
-- sensory feedback, the modifiers, the navigation bar and the composite Button.
local t = require("./lib/testkit")
local Facet = require("../src") :: any
local Compose = Facet.Compose
local world = require("./lib/native_motion_world")
local describe, it, expect = t.describe, t.it, t.expect

local function has(adapter: any, suffix: string): string?
	for _, path in adapter.paths() do
		if path:sub(-#suffix) == suffix then
			return path
		end
	end
	return nil
end

describe("app.controls: regions", function()
	it("a stepped-down region opens a plate carrying a copy of its richest form", function()
		local app, adapter, advance = world()
		-- 30px of height: the two-line form cannot stand, the one-line one can
		app.environment:set("viewportRect", { x = 0, y = 0, w = 390, h = 30 })
		local UI = app.controls
		local score = Compose.cell("12 - 9")
		local close = app.mount(function()
			return UI.Screen("S")({
				width = UI.fill(),
				height = UI.fill(),
				UI.Composition("C")({
					arrangements = { "column" },
					width = UI.fill(),
					height = UI.fill(),
					groups = { { id = "body", lane = "main", sizing = "fill" } },
					UI.Region("Clock")({
						group = "body",
						rank = 1,
						recover = "overflow",
						UI.VStack("Full")({
							UI.Text("Timer")({ text = "2:14", textSize = 16 }),
							UI.Text("Scores")({ text = score, textSize = 16 }),
						}),
						UI.Text("TimerOnly")({ text = "2:14", textSize = 16 }),
					}),
				}),
			})
		end)
		advance(0.1)
		expect(adapter.node("/S/C/Clock/Expand")).never().toBeNil()
		adapter.tap("/S/C/Clock/Expand")
		advance(0.1)
		local scores = "/Expand:Clock/Layer/Surface/ExpandPanel/ExpandPlate/Full/Scores"
		expect(adapter.node(scores)).never().toBeNil()
		-- the copy keeps the original's bindings
		score:set("13 - 9")
		advance(0.1)
		expect(adapter.node(scores).props.text).toBe("13 - 9")
		adapter.driveActivate(has(adapter, "/ExpandClose") :: string)
		advance(0.3)
		expect(adapter.node(scores)).toBeNil()
		close()
		app.dispose()
	end)

	it("a declaration the composition refuses is refused where it is written", function()
		local app = world()
		local UI = app.controls
		local close = app.mount(function()
			local ok, err = pcall(function()
				return UI.Composition("Hud")({
					groups = Facet.composition.HUD_GROUPS,
					arrangements = { Facet.composition.HUD },
					UI.Region("Rounds")({
						group = "topLeft",
						rank = 1,
						UI.Text("A")({ text = "a" }),
						UI.Text("B")({ text = "b" }),
					}),
				})
			end)
			expect(ok).toBe(false)
			expect(string.find(tostring(err), "no 'recover'", 1, true) ~= nil).toBe(true)
			return UI.Screen("S")({})
		end)
		close()
		app.dispose()
	end)
end)

describe("app.controls: sensory feedback and modifiers", function()
	it("reports a change and an inherited activation verb on the presenter's bus", function()
		local app, adapter, advance = world()
		local UI = app.controls
		local trigger = Compose.cell(0)
		local events = {}
		app.presenter.onFeedback(function(event)
			if event.type == "select" or event.type == "commit" then
				table.insert(events, event)
			end
		end)
		local close = app.mount(function()
			return UI.Screen("S")({
				UI.sensoryFeedback(
					UI.sensoryFeedback(
						UI.VStack("Panel")({
							UI.Button("Go")({ label = "Go", onActivate = function() end }),
						}),
						{ trigger = trigger, event = "select" }
					),
					{ activation = "commit" }
				),
			})
		end)
		advance(0.1)
		expect(#events).toBe(0)
		trigger:set(1)
		expect(#events).toBe(1)
		expect(events[1].type).toBe("select")
		expect(events[1].path).toBe("/S/Panel")
		adapter.driveActivate("/S/Panel/Go")
		expect(events[2].type).toBe("commit")
		close()
		trigger:set(2)
		expect(#events).toBe(2)
		app.dispose()
	end)

	it("offers the modifiers an application needs", function()
		local app = world()
		for _, name in { "focusSection", "styleGroup", "draggable", "dropTarget", "sensoryFeedback", "navBar" } do
			expect(`{name}: {type(app.controls[name])}`).toBe(`{name}: function`)
		end
		app.dispose()
	end)
end)

describe("app.controls: navBar and the composite Button", function()
	it("navBar builds a bar an application can mount", function()
		local app, adapter, advance = world()
		local UI = app.controls
		local backs = 0
		local close = app.mount(function()
			return UI.Screen("S")({
				Facet.navBar({
					title = "Detail",
					backLabel = "Back",
					onBack = function()
						backs += 1
					end,
					trailing = { UI.Button("Fav")({ label = "Fav", onActivate = function() end }) },
				}, UI),
			})
		end)
		advance(0.1)
		expect(adapter.node("/S/NavBar/Title").props.text).toBe("Detail")
		expect(adapter.node("/S/NavBar/Fav")).never().toBeNil()
		adapter.driveActivate("/S/NavBar/Back")
		expect(backs).toBe(1)
		close()
		app.dispose()
	end)

	it("the Button takes selected, hidden, anchor, onAppear and pointer handlers", function()
		local app, adapter, advance = world()
		local UI = app.controls
		local hidden, appeared, downs = Compose.cell(false), 0, 0
		local close = app.mount(function()
			return UI.Screen("S")({
				UI.Anchor("Layer")({
					width = UI.fill(),
					height = UI.fill(),
					UI.Button("Pin")({
						label = "Pin",
						selected = true,
						hidden = hidden,
						anchor = "bottomRight",
						onAppear = function()
							appeared += 1
						end,
						onPointerDown = function()
							downs += 1
						end,
					}),
				}),
			})
		end)
		advance(0.1)
		local node = adapter.node("/S/Layer/Pin")
		expect(node.props.selected).toBe(true)
		-- anchored to the far corner of the 640x480 layer
		expect(node.rect.x + node.rect.w).toBe(640)
		expect(node.rect.y + node.rect.h).toBe(480)
		adapter.pointerDown("/S/Layer/Pin", node.rect.x + 4, node.rect.y + 4)
		expect(downs).toBe(1)
		expect(appeared).toBe(1)
		hidden:set(true)
		advance(0.1)
		expect(adapter.visibleOf("/S/Layer/Pin")).toBe(false)
		close()
		app.dispose()
	end)

	it("a composite Button given as a Menu trigger opens the menu before its own effect", function()
		local app, adapter, advance = world()
		local UI = app.controls
		local own = 0
		local close = app.mount(function()
			return UI.Screen("S")({
				UI.Menu("More")({
					trigger = UI.Button("More")({
						label = "More",
						onActivate = function()
							own += 1
						end,
					}),
					items = { { id = "one", label = "One", onSelect = function() end } },
				}),
			})
		end)
		advance(0.1)
		adapter.driveActivate("/S/More")
		advance(0.3)
		expect(has(adapter, "/Item:one")).never().toBeNil()
		expect(own).toBe(0)
		close()
		app.dispose()
	end)
end)
