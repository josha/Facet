--!strict
local harness = require("./lib/harness")
--[[
	`UI.Foreign{ onHost = ... }` — THE CONTENT SEAM, DELIVERED INSTEAD OF POLLED.

	`controller.foreignHost(path)` is the seam, and only a CONTROLLER can be
	asked for it. A component builds before its own `app.mount` returns one, so a
	component that wants to fill its own box has no controller at the moment it
	declares the box. Every consumer that met this wrote the same workaround —
	the virtual-monitors showcase is the shipped example: smuggle the controller
	out through a mutable box the host fills in later, then ask for the handle on
	EVERY FRAME, forever, until it stops answering nil. A per-frame busy-wait for
	a structural event the renderer knows the exact moment of.

	`onHost` is that moment, declared where the box is. Five contracts:

	  (a) it is called ONCE, with the same `{ adopt }` handle `foreignHost`
	      answers — never with the container, because the box is Facet's and
	      handing it out is the writable-handle hole §Foreign refuses;
	  (b) the function it RETURNS runs when the node goes away — on removal and
	      on teardown, once, and never twice;
	  (c) it is contained: a caller's engine code throwing is not a reason for
	      the render pass around it to unwind;
	  (d) it composes with `onAppear`/`onDisappear` rather than replacing them;
	  (e) it is Foreign's alone, and a non-function is refused at construction.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
local Compose = require("../src/vendor/compose/core")
local environment = require("../src/env/environment")
local rendererLib = require("../src/render/renderer")
local fake_target = require("./lib/fake_target")
local foreign_content = require("../src/render/foreign_content")

local UI = harness.UI

local function stub(className: string?): any
	return {
		present = true,
		className = className or "VideoFrame",
		isGuiObject = true,
		isLayerCollector = false,
		alive = true,
	}
end

local function mount(spec: { [string]: any }, opts: { [string]: any }?)
	local core = harness.newCore()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = 400, h = 400 })
	env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
	local foreignSpec: { [string]: any } = {
		id = "Foreign",
		width = { type = "fixed", px = 200 },
		height = { type = "fixed", px = 120 },
	}
	for key, value in spec do
		foreignSpec[key] = value
	end
	local shown = Compose.cell(true)
	local root = harness.mount(core, function()
		return UI.Screen({
			id = "S",
			padding = 0,
			gap = 0,
			children = {
				Compose.show(shown, function()
					return UI.Foreign(foreignSpec)
				end),
			},
		})
	end)
	local adapter = if opts and opts.adapter then opts.adapter else fake_target.new()
	local controller = rendererLib.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
	controller.initialRender()
	return { core = core, root = root, adapter = adapter, controller = controller, shown = shown }
end

describe("(a) `onHost` is handed the node's own seam, once", function()
	it("runs with the same { adopt } handle `foreignHost` answers, and adopting lands", function()
		local seen: { any } = {}
		local w = mount({
			onHost = function(seam: any)
				table.insert(seen, seam)
				seam.adopt(stub("VideoFrame"))
			end,
		})
		expect(#seen).toBe(1)
		expect(seen[1]).toBe(w.controller.foreignHost("/S/Foreign"))
		local calls = (seen[1] :: any).calls
		expect(#calls).toBe(1)
		expect(calls[1].method).toBe("adopt")
		expect(calls[1].className).toBe("VideoFrame")
		expect(calls[1].property).toBe(foreign_content.CLAIMED_PROPERTY)
		--[[ ONCE, not once per solve: the polling this replaces cost a frame
			connection and a `foreignHost` call sixty times a second. ]]
		w.controller.refresh()
		w.controller.refresh()
		expect(#seen).toBe(1)
		w.controller.dispose()
		w.root.dispose()
	end)

	it("is handed nil where the render target has no foreign seam at all", function()
		--[[ A world canvas withholds `foreignHost` (src/client/billboard_target),
			so the box still paints its `surface` and the caller gates on the nil —
			the same fallback contract `foreignHost` already documents, reached
			without asking. ]]
		local adapter = fake_target.new()
		adapter.foreignHost = nil
		local seen = 0
		local answered: any = "unset"
		local w = mount({
			onHost = function(seam: any)
				seen += 1
				answered = seam
			end,
		}, { adapter = adapter })
		expect(seen).toBe(1)
		expect(answered).toBeNil()
		w.controller.dispose()
		w.root.dispose()
	end)
end)

describe("(b) what it returns is run when the node goes away", function()
	it("runs the cleanup when the node is removed, and only then", function()
		local released = 0
		local w = mount({
			onHost = function()
				return function()
					released += 1
				end
			end,
		})
		expect(released).toBe(0)
		w.shown:set(false)
		w.controller.refresh()
		expect(released).toBe(1)
		-- ...and never twice, however the surface ends
		w.controller.dispose()
		w.root.dispose()
		expect(released).toBe(1)
	end)

	it("runs the cleanup on teardown, for a node that never left", function()
		local released = 0
		local w = mount({
			onHost = function()
				return function()
					released += 1
				end
			end,
		})
		w.controller.dispose()
		expect(released).toBe(1)
		w.root.dispose()
		expect(released).toBe(1)
	end)

	it("returning nothing is legal — not every adoption needs undoing", function()
		local w = mount({
			onHost = function(seam: any)
				seam.adopt(stub())
			end,
		})
		w.shown:set(false)
		w.controller.refresh()
		expect(w.core.lastError()).toBeNil()
		w.controller.dispose()
		w.root.dispose()
	end)
end)

describe("(c) a caller's engine code cannot unwind the render pass", function()
	it("contains a throwing host and reports it by node path", function()
		local w = mount({
			onHost = function()
				error("no video for you", 0)
			end,
		})
		expect(w.core.lastError() ~= nil).toBe(true)
		expect(string.find(tostring(w.core.lastError()), "/S/Foreign", 1, true) ~= nil).toBe(true)
		-- the surface is still standing
		expect(w.adapter.node("/S/Foreign") ~= nil).toBe(true)
		expect(#w.controller.diagnostics()).toBe(0)
		w.controller.dispose()
		w.root.dispose()
	end)

	it("contains a throwing cleanup", function()
		local w = mount({
			onHost = function()
				return function()
					error("cleanup exploded", 0)
				end
			end,
		})
		w.shown:set(false)
		w.controller.refresh()
		expect(string.find(tostring(w.core.lastError()), "cleanup exploded", 1, true) ~= nil).toBe(true)
		w.controller.dispose()
		w.root.dispose()
	end)
end)

describe("(d) it composes with the lifetime hooks rather than replacing them", function()
	it("`onAppear` and `onDisappear` still fire alongside it", function()
		local order: { string } = {}
		local w = mount({
			onAppear = function()
				table.insert(order, "appear")
			end,
			onDisappear = function()
				table.insert(order, "disappear")
			end,
			onHost = function()
				table.insert(order, "onHost")
				return function()
					table.insert(order, "release")
				end
			end,
		})
		expect(table.concat(order, " ")).toBe("appear onHost")
		w.shown:set(false)
		w.controller.refresh()
		expect(table.concat(order, " ")).toBe("appear onHost release disappear")
		w.controller.dispose()
		w.root.dispose()
	end)
end)

describe("(e) it belongs to Foreign, and only as a function", function()
	it("a non-function is refused at construction", function()
		harness.newCore()
		local ok, err = pcall(function()
			UI.Foreign({ id = "F", onHost = "please" })
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "onHost", 1, true) ~= nil).toBe(true)
	end)

	it("no other class takes it", function()
		harness.newCore()
		local ok, err = pcall(function()
			UI.Box({ id = "B", onHost = function() end })
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "onHost", 1, true) ~= nil).toBe(true)
	end)

	it("is still not an engine property: `class`/`instance` stay refused by name", function()
		harness.newCore()
		local ok, err = pcall(function()
			UI.Foreign({ id = "F", instance = {} })
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "foreignHost", 1, true) ~= nil).toBe(true)
	end)
end)

local _ = Facet
