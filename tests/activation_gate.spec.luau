--!strict
-- `UI.activationGate` — "this subtree takes one activation to become active".
-- An input POLICY, honoured on the one Activate dispatch every source arrives
-- through, so a tap, a Return and a gamepad A all spend their first press the
-- same way. Before it, an app covered the subtree with a full-size transparent
-- Button: a second focus stop, a second hit target and a second thing to size.
local t = require("./lib/testkit")
local Facet = require("../src")
local fake = require("./lib/fake_target")
local Compose = Facet.Compose

local function world()
	local adapter, frame, input = fake.new(), nil, nil
	local app = Facet.new({
		newAdapter = function()
			return adapter
		end,
		newInputSystem = function(core)
			input = Facet.newActionSystem(core)
			return input
		end,
		bindEnv = function(env)
			env:set("viewportRect", { x = 0, y = 0, w = 640, h = 480 })
			env:set("reducedMotion", true)
			return function() end
		end,
		connectFrame = function(fn)
			frame = fn
			return function() end
		end,
	})
	return app, adapter, function(count: number?)
		for _ = 1, count or 3 do
			frame(1 / 60)
		end
	end, input
end

t.describe("UI.activationGate", function()
	local function screen(app: any, asleep: any, log: any)
		local UI = app.controls
		return function()
			return UI.Screen("S")({
				UI.activationGate(
					UI.ZStack("Panel")({
						width = { type = "fill" },
						height = { type = "fill" },
						UI.Button("Launch")({
							label = "Launch",
							onActivate = function()
								log.launched += 1
							end,
						}),
					}),
					{
						closed = asleep,
						onOpen = function(path)
							log.opened += 1
							log.path = path
						end,
					}
				),
			})
		end
	end

	t.it("spends a tap waking the subtree, then lets the next tap through", function()
		local app, adapter, settle = world()
		local asleep = Compose.cell(true)
		local log = { launched = 0, opened = 0, path = nil }
		app.mount(screen(app, asleep, log))
		settle(3)
		adapter.driveActivate("/S/Panel/Launch")
		t.expect(log.opened).toBe(1)
		t.expect(log.launched).toBe(0)
		-- the gate reports what the press WOULD have reached
		t.expect(log.path).toBe("/S/Panel/Launch")
		asleep:set(false)
		settle(1)
		adapter.driveActivate("/S/Panel/Launch")
		t.expect(log.launched).toBe(1)
		t.expect(log.opened).toBe(1)
		app.dispose()
	end)

	t.it("spends a keyboard and a gamepad Activate the same way", function()
		for _, key in { "Return", "ButtonA" } do
			local app, _, settle, input = world()
			local asleep = Compose.cell(true)
			local log = { launched = 0, opened = 0, path = nil }
			app.mount(screen(app, asleep, log))
			settle(3)
			input.deviceKey(key, true)
			input.deviceKey(key, false)
			settle(1)
			t.expect(log.opened).toBe(1)
			t.expect(log.launched).toBe(0)
			asleep:set(false)
			settle(1)
			input.deviceKey(key, true)
			input.deviceKey(key, false)
			settle(1)
			t.expect(log.launched).toBe(1)
			t.expect(log.opened).toBe(1)
			app.dispose()
		end
	end)

	t.it("wakes one level per press, innermost gate first", function()
		local app, adapter, settle = world()
		local UI = app.controls
		local outer, inner = Compose.cell(true), Compose.cell(true)
		local log = { launched = 0, outer = 0, inner = 0 }
		app.mount(function()
			return UI.Screen("S")({
				UI.activationGate(
					UI.ZStack("Outer")({
						width = { type = "fill" },
						height = { type = "fill" },
						UI.activationGate(
							UI.ZStack("Inner")({
								width = { type = "fill" },
								height = { type = "fill" },
								UI.Button("Launch")({
									label = "Launch",
									onActivate = function()
										log.launched += 1
									end,
								}),
							}),
							{
								closed = inner,
								onOpen = function()
									log.inner += 1
								end,
							}
						),
					}),
					{
						closed = outer,
						onOpen = function()
							log.outer += 1
						end,
					}
				),
			})
		end)
		settle(3)
		adapter.driveActivate("/S/Outer/Inner/Launch")
		t.expect(log.inner).toBe(1)
		t.expect(log.outer).toBe(0)
		inner:set(false)
		settle(1)
		adapter.driveActivate("/S/Outer/Inner/Launch")
		t.expect(log.outer).toBe(1)
		t.expect(log.launched).toBe(0)
		outer:set(false)
		settle(1)
		adapter.driveActivate("/S/Outer/Inner/Launch")
		t.expect(log.launched).toBe(1)
		app.dispose()
	end)

	t.it("reads a binding, a readable and a plain boolean", function()
		local app, adapter, settle = world()
		local UI = app.controls
		local cell = Compose.cell(true)
		local log = { launched = 0, opened = 0 }
		app.mount(function()
			return UI.Screen("S")({
				UI.activationGate(
					UI.ZStack("Panel")({
						width = { type = "fill" },
						height = { type = "fill" },
						UI.Button("Launch")({
							label = "Launch",
							onActivate = function()
								log.launched += 1
							end,
						}),
					}),
					{
						closed = function(use)
							return use(cell)
						end,
						onOpen = function()
							log.opened += 1
						end,
					}
				),
			})
		end)
		settle(3)
		adapter.driveActivate("/S/Panel/Launch")
		t.expect(log.opened).toBe(1)
		cell:set(false)
		adapter.driveActivate("/S/Panel/Launch")
		t.expect(log.launched).toBe(1)
		app.dispose()
	end)

	t.it("refuses a malformed declaration where it is written", function()
		local blueprint = require("../src/blueprint")
		local node = { class = "ZStack", id = "X", props = {}, children = {} }
		local function declare(spec: any)
			return (pcall(blueprint.activationGate, node, spec))
		end
		t.expect(declare({})).toBe(false)
		t.expect(declare({ closed = true, onOpen = "later" })).toBe(false)
		t.expect(declare({ closed = true, when = "later" })).toBe(false)
		t.expect(declare({ closed = true })).toBe(true)
	end)
end)
