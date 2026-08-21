--!strict
--[[ THE SHOWCASE HOST PATH — the one mount path in this repository that had no
	headless coverage, and the two demos that died on it (live Studio session,
	2026-08-20).

	WHAT HAPPENED. `card-rail` and `sorted-entries` FAILED TO MOUNT in the shipped
	showcase while the whole suite was green. Both build an adaptive control that
	asks the core it was built on for its environment (ADAPT-1: the facts arrive by
	themselves, or the control refuses rather than silently taking the large-screen
	answer). The showcase DOES publish one — `Facet.newEnvironment(core)` at the top
	of `init.client.luau` — but a demo is not built on that core. It is built on the
	per-demo PROXY that installs a disposal scope
	(`examples/gallery/client/demo_host.luau`), and a proxy that hides the
	registration is a core with no environment as far as the framework can tell.

	WHY EVERY SPEC MISSED IT. They all build their own bare core and their own
	environment — which is the correct shape for a unit test and the wrong shape
	for this question. The gap was never a missing fact; it was that nothing
	exercised the path where the fact has to travel one hop. So this file mounts
	demos through the SHIPPED proxy (`demo_host.scopedCore`, required, not copied)
	against a host-shaped core, and it sweeps the WHOLE catalogue rather than the
	two that were reported: the next adaptive control to appear in any of the
	thirty-six is the one nobody will be looking at.

	IT IS NOT A TEST OF THE REFUSAL. The last case is the negative control: a core
	with genuinely no environment anywhere must still refuse, or this file would be
	evidence that ADAPT-1's whole guarantee had been quietly turned off.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local fs = require("@lune/fs")
local Facet = require("../src") :: any
local fake_target = require("./lib/fake_target")
local demo_host = require("../examples/gallery/client/demo_host")
local demo_picker = require("../examples/gallery/client/demo_picker")

--[[ THE SHOWCASE'S OWN BOOTSTRAP, in the order `init.client.luau` runs it: one
	core, one environment published against it, one action system, one adapter, one
	presenter. The viewport is a phone, because that is the combination the compact
	rungs actually resolve on and the one a device pass holds. ]]
local function showcaseHost(opts: any?): any
	local options: any = opts or {}
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	env:set("viewportRect", { x = 0, y = 0, w = options.w or 390, h = options.h or 844 })
	if options.touch ~= false then
		env:set("capabilities", { touch = true, mouse = false, keyboard = false, gamepad = false })
		env:set("preferredInput", "Touch")
	end
	local system = Facet.newActionSystem(core)
	local adapter = fake_target.new()
	local pres = Facet.newPresenter(core, env, adapter, system, { keyboardNavigation = true })
	return { core = core, env = env, system = system, adapter = adapter, pres = pres }
end

--[[ `mountDemo`'s two branches, reduced to what a Lune process can run: the
	per-demo scope, the SHIPPED proxy over it, and each kind's own build contract
	(a fixture takes one ctx table and hands back a screen; a tutorial example
	takes `(Facet, core, opts)` and may present itself). Everything this leaves out
	— replicated folders, the foreign-instance seam, the live geometry probe — is
	Instances, and none of it touches the question this file asks. ]]
local function mountDemo(host: any, demo: any): any
	local demoScope = host.core:scope(`showcase-demo-{demo.id}`)
	local demoCore = demo_host.scopedCore(host.core, demoScope)
	local built: any
	if demo.kind == "fixture" then
		local mod = require(`../examples/gallery/scenarios/{demo.module}`) :: any
		built = mod.build({
			Facet = Facet,
			core = demoCore,
			env = host.env,
			actionSystem = host.system,
			presenter = host.pres,
			--[[ THE ENGINE SEAMS, DEGRADED HONESTLY. The shipped host binds
				`roblox_resources` here and adopts real Instances through `foreign`; a
				Lune process has neither, and `async_images` calls the transport binder
				unconditionally at build. A stub that returns a no-op unbind is what the
				fixture's own header already describes for the absent case ("degrades
				honestly when it is absent"), and it keeps this sweep about the question
				it asks — does the demo BUILD on this core — rather than about
				ContentProvider. ]]
			bindResourceTransport = function(): () -> ()
				return function() end
			end,
			foreign = {
				adopt = function(): any
					return nil
				end,
			},
		})
		built.handle = host.pres.present(built.screen, built.present)
	else
		local mod = require(`../examples/gallery/examples/{demo.module}`) :: any
		built = mod.build(Facet, demoCore, {
			env = host.env,
			actionSystem = host.system,
			presenter = host.pres,
			adapter = host.adapter,
		})
		if built.handle == nil and built.screen ~= nil then
			built.handle = host.pres.present(built.screen, built.present)
		end
	end
	host.pres.refresh()
	local ownDispose = built.dispose
	built.dispose = function()
		if ownDispose ~= nil then
			pcall(ownDispose)
		end
		demoScope:dispose()
	end
	return built
end

local function demoById(id: string): any
	for _, demo in demo_picker.list() do
		if demo.id == id then
			return demo
		end
	end
	error(`no demo '{id}' in the catalogue`, 0)
end

describe("the showcase host path: a demo core is the core it delegates to", function()
	--[[ THE TWO THE LIVE SESSION REPORTED, named individually and ahead of the
		sweep, because a sweep that goes red says "something" and these two say what.
		Each one's adaptive control is different — a card rail arranging itself, a
		picker choosing its presentation — so they are two independent witnesses to
		one root cause rather than one defect counted twice. ]]
	it("card-rail mounts through the host path, and arranges itself from the host's facts", function()
		local host = showcaseHost()
		local built = mountDemo(host, demoById("card-rail"))
		local d = built.rail.dump()
		-- the compact touch rung, resolved from an environment nobody handed it
		expect(d.cardsPerView).toBe(1)
		expect(d.snap).toBe("item")
		expect(host.core:lastError()).toBeNil()
		built.dispose()
	end)

	it("sorted-entries mounts through the host path, and its picker chooses a presentation", function()
		local host = showcaseHost()
		local built = mountDemo(host, demoById("sorted-entries"))
		expect(built.screen).never().toBeNil()
		expect(host.core:lastError()).toBeNil()
		built.dispose()
	end)

	--[[ ...AND THE WHOLE CATALOGUE, because the two above are symptoms of a path,
		not of themselves. Every demo the picker offers is mounted through the same
		proxy and disposed; a build error surfaces with the demo's id, which is the
		only thing that makes a 36-way sweep debuggable. ]]
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
			--[[ THE VERDICT IS TAKEN AT MOUNT, BEFORE DISPOSAL, and deliberately.
				Two demos raise a core error when the demo scope tears down what the
				demo already tore down (`with-animation`, `tab-view`: "double disposal
				of scope"), which is a real finding on this path and is reported as one
				— but it is a DISPOSAL defect, and folding it in here would make "does
				the showcase mount" unanswerable until somebody fixed something else. ]]
			local mountError = host.core:lastError()
			if built ~= nil then
				pcall(built.dispose)
			end
			if not ok then
				table.insert(broken, `{demo.id} ({demo.kind}/{demo.module}): {tostring(err)}`)
			elseif mountError ~= nil then
				table.insert(broken, `{demo.id}: core error at mount {tostring(mountError)}`)
			end
		end
		if #broken > 0 then
			error(
				`{#broken} of {#demos} demos do not mount on the SHOWCASE HOST PATH (they may still mount on a `
					.. `bare spec core, which is why the suite was green):\n  {table.concat(broken, "\n  ")}`,
				0
			)
		end
	end)

	--[[ THE PROPERTY, ASSERTED DIRECTLY. Everything above is a consequence of it,
		and a consequence can be made to pass by accident (an adaptive control could
		stop adapting). A demo core must ANSWER for its host's environment while
		owning none of its own — one owner, one registration, one hop. ]]
	it("the proxy answers with the host's environment, and publishes none of its own", function()
		local host = showcaseHost()
		local scope = host.core:scope("probe")
		local demoCore = demo_host.scopedCore(host.core, scope)
		local surfaceEnv = require("../src/env/surface_env")
		local found, reason = surfaceEnv.find(demoCore)
		expect(`reason={tostring(reason)}`).toBe("reason=nil")
		expect(found).toBe(host.env)
		-- ...and it did not acquire one by being asked: the registration still lives
		-- on the core the environment was built on, which is what makes disposal and
		-- ambiguity answerable in one place
		expect(rawget(demoCore :: any, "__facetSurfaceEnv")).toBeNil()
		scope:dispose()
	end)

	--[[ THE NEGATIVE CONTROL. If a core with no environment ANYWHERE stopped
		refusing, every case above would still be green and ADAPT-1's guarantee would
		be gone — the failure this file exists to prevent, arriving through the fix
		for it. ]]
	it("a core with no environment at all still REFUSES, naming the environment", function()
		local bare = Facet.newCore()
		local scope = bare:scope("bare")
		local proxied = demo_host.scopedCore(bare, scope)
		local ok, err = pcall(function()
			return Facet.Controls.VirtualList(proxied, {
				id = "Rail",
				axis = "x",
				rows = bare:signal({ { id = "a" } }),
				key = function(item: any): string
					return item.id
				end,
				itemExtent = "cards",
				viewportExtent = 390,
				cell = function(): any
					return Facet.UI.Text({ id = "N", text = "x", textSize = 14 })
				end,
			})
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "environment", 1, true) ~= nil).toBe(true)
		scope:dispose()
	end)

	--[[ AND THE SPEC'S OWN HONESTY: the proxy driven above is the SHIPPED one. If
		`init.client.luau` ever inlines its own again, this file goes back to testing
		a copy — which is the exact state the defect was found in. ]]
	it("the shipped host uses this module rather than its own proxy", function()
		local source = fs.readFile("examples/gallery/client/init.client.luau")
		expect(string.find(source, "demo_host.scopedCore", 1, true) ~= nil).toBe(true)
		expect(string.find(source, "setmetatable({}, {", 1, true)).toBeNil()
	end)
end)
