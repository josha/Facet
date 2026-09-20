--!strict
--[[ The showcase host path: every catalogue demo, mounted through the SHIPPED
	`demo_host.mount` (required, not copied) against a host-shaped application.

	A demo builds against the host's context, so the adaptive facts it needs
	arrive from the host's environment with no wiring. This file sweeps the whole
	catalogue rather than the two demos a live session once reported: the next
	adaptive control to appear in any of them is the one nobody will be looking at.

	The last case of the first block is the negative control: a core with no
	environment anywhere must still refuse, or this file would be evidence that the
	guarantee had been quietly turned off. ]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local fs = require("@lune/fs")
local scenario_ctx = require("./lib/scenario_ctx")
local harness = require("./lib/harness")
local world = require("./lib/world")
local demo_host = require("../examples/gallery/client/demo_host")
local demo_picker = require("../examples/gallery/client/demo_picker")
local Compose = require("../src/vendor/compose/core")

--[[ The showcase's own bootstrap: one application, its environment set to a
	phone, because that is the combination the compact rungs resolve on and the
	one a device pass holds. ]]
local function showcaseHost(opts: any?): any
	local options: any = opts or {}
	local w: any = world.new({
		viewport = { x = 0, y = 0, w = options.w or 390, h = options.h or 844 },
		capabilities = if options.touch ~= false
			then { touch = true, mouse = false, keyboard = false, gamepad = false }
			else nil,
		preferredInput = if options.touch ~= false then "Touch" else nil,
		hostOpts = { keyboardNavigation = true },
		overflowGuardOff = "this sweep asks whether each demo mounts, not how it lays out",
	})
	--[[ The engine seams, degraded honestly. The shipped host binds
		`roblox_resources` and adopts real Instances through `foreign`; a Lune
		process has neither, and `async_images` calls the transport binder at build. ]]
	w.ctx = scenario_ctx.of(w, {
		foreign = {
			adopt = function(): any
				return nil
			end,
		},
	})
	return w
end

local function mountDemo(host: any, demo: any): any
	local folder = if demo.kind == "fixture" then "scenarios" else "examples"
	local mod = require(`../examples/gallery/{folder}/{demo.module}`) :: any
	local built = demo_host.mount(host.ctx, mod)
	host.pres.refresh()
	return built
end

local function settle(host: any)
	for _ = 1, 120 do
		host.pres.tick(1 / 60)
		host.pres.refresh()
	end
end

describe("the showcase host path: a demo builds on the host's own facts", function()
	it("card-rail mounts through the host path, and arranges itself from the host's facts", function()
		local host = showcaseHost()
		local built = mountDemo(host, { id = "card-rail", kind = "fixture", module = "card_rail" })
		host.pres.refresh()
		-- the compact touch rung, resolved from the host's facts: one card and a peek
		local railWidth = host.adapter.node("/CardRail/Page/RailPane/Rail").rect.w
		expect(built.itemExtent() < railWidth and built.itemExtent() * 2 > railWidth).toBe(true)
		expect(host.core.lastError()).toBeNil()
		built.dispose()
	end)

	it("sorted-entries mounts through the host path, and its picker chooses a presentation", function()
		local host = showcaseHost()
		local built = mountDemo(host, { id = "sorted-entries", kind = "fixture", module = "sorted_entries" })
		expect(built.screen).never().toBeNil()
		expect(host.core.lastError()).toBeNil()
		built.dispose()
	end)

	it("every demo in the catalogue mounts through the host path", function()
		local demos = demo_picker.list()
		expect(#demos).toBeGreaterThan(0)
		local broken: { string } = {}
		for _, demo in demos do
			local host = showcaseHost()
			local built: any = nil
			local ok, err = pcall(function()
				built = mountDemo(host, demo)
			end)
			local mountError = host.core.lastError()
			if built ~= nil then
				pcall(built.dispose)
				settle(host)
			end
			local teardownError = host.core.lastError()
			if not ok then
				table.insert(broken, `{demo.id} ({demo.kind}/{demo.module}): {tostring(err)}`)
			elseif mountError ~= nil then
				table.insert(broken, `{demo.id}: core error at mount {tostring(mountError)}`)
			elseif teardownError ~= nil then
				table.insert(broken, `{demo.id}: core error after teardown {tostring(teardownError)}`)
			end
		end
		if #broken > 0 then
			error(
				`{#broken} of {#demos} demos do not mount on the SHOWCASE HOST PATH:\n  {table.concat(broken, "\n  ")}`,
				0
			)
		end
	end)

	it("a core with no environment at all still REFUSES, naming the environment", function()
		local bare = harness.newCore()
		local ok, err = pcall(function()
			return harness.Controls.Picker(bare, {
				id = "Choice",
				label = "Choice",
				selected = Compose.cell("a"),
				options = { { value = "a", label = "A" } },
			})
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "environment", 1, true) ~= nil).toBe(true)
	end)

	it("the shipped host uses this module rather than its own mount path", function()
		local source = fs.readFile("examples/gallery/client/init.client.luau")
		expect(string.find(source, "demo_host.mount", 1, true) ~= nil).toBe(true)
	end)
end)

describe("showcase cleanup ordering", function()
	it("keeps demo resources alive until the presented tree has unmounted", function()
		local host = showcaseHost()
		local released = false
		local built = demo_host.mount(host.ctx, {
			build = function(ctx: any)
				return {
					screen = function()
						return ctx.UI.Screen("Held")({ ctx.UI.Text("T")({ text = "held" }) })
					end,
					dispose = function()
						released = true
					end,
				}
			end,
		})
		host.pres.refresh()
		built.dispose()
		-- the demo's own resources are released with the screen's owner, not before it
		expect(released).toBe(host.adapter.node("/Held") == nil)
		settle(host)
		expect(released).toBe(true)
		expect(host.adapter.node("/Held")).toBeNil()
		expect(host.core.lastError()).toBe(nil)
	end)

	it("a demo disposed and dismissed in the same frame leaves no core error", function()
		local host = showcaseHost()
		local built = mountDemo(host, demo_picker.find("all-controls"))
		built.dispose()
		host.pres.dismiss(built.handle)
		settle(host)
		expect(host.core.lastError()).toBe(nil)
	end)

	it("a demo that presents itself is disposed by its own dispose, once", function()
		local host = showcaseHost()
		local disposals = 0
		local built = demo_host.mount(host.ctx, {
			build = function()
				return {
					handle = {},
					dispose = function()
						disposals += 1
					end,
				}
			end,
		})
		built.dispose()
		built.dispose()
		expect(disposals).toBe(1)
	end)
end)
