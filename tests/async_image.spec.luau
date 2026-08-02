--!strict
-- AsyncImage (native-substrate NS-A14, ledger rows NS-A13/NS-A14): the
-- provider's placeholder/ready/failed states drive the composite's visuals
-- headlessly; stale completions after release never resurrect (E1 half of the
-- honesty rule — the engine transport half is scenario 'async_images').

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local customFactory = require("../src/core/custom")
local LuauUIRoot = require("../src")
local resources = require("../src/async/resources")
local mountLib = require("../src/mount")
local environment = require("../src/env/environment")
local renderer = require("../src/render/renderer")
local fake_target = require("../tests/lib/fake_target")

local function slice(key: string)
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = 300, h = 300 })
	env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
	local provider = resources.newProvider(core)
	local scope = core:scope()
	local img = LuauUIRoot.newAsyncImage(LuauUIRoot, core, {
		id = "Avatar",
		scope = scope,
		provider = provider,
		key = key,
	})
	local bp = LuauUIRoot.UI.Screen({ id = "S", children = { img.blueprint } })
	local root = mountLib.mount(core, bp)
	local adapter = fake_target.new()
	local controller = renderer.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
	controller.initialRender()
	return core, provider, scope, adapter, controller, img, root
end

describe("AsyncImage (NS-A14)", function()
	it("pending shows the placeholder and an empty image", function()
		local _, _, _, adapter, controller, img = slice("rbxthumb://type=AvatarHeadShot&id=1")
		expect(img.state:get()).toBe("pending")
		expect(adapter.node("/S/Avatar/Placeholder/then/Fill") ~= nil).toBe(true)
		expect(adapter.node("/S/Avatar/Content").props.image).toBe("")
		expect(adapter.node("/S/Avatar/Failure/then/Mark")).toBe(nil)
	end)

	it("transport completion swaps placeholder for the content", function()
		local core, provider, _, adapter, controller, img = slice("rbxthumb://a")
		local pending = provider.pendingRequests()
		expect(#pending).toBe(1)
		local verdict = provider.complete(pending[1].key, pending[1].generation, pending[1].key)
		expect(verdict).toBe("applied")
		controller.refresh()
		expect(img.state:get()).toBe("ready")
		expect(adapter.node("/S/Avatar/Content").props.image).toBe("rbxthumb://a")
		expect(adapter.node("/S/Avatar/Placeholder/then/Fill")).toBe(nil)
	end)

	it("transport failure is SILENT by default: the placeholder persists, no mark (SF-A1)", function()
		local _, provider, _, adapter, controller, img = slice("rbxassetid://999999999999999")
		local pending = provider.pendingRequests()
		provider.fail(pending[1].key, pending[1].generation, "AssetFetchStatus.Failure")
		controller.refresh()
		expect(img.state:get()).toBe("failed")
		-- P5-F2 fix: no failure glyph unless the call site opted in — the failed
		-- state is the placeholder persisting, a complete presentable state
		expect(adapter.node("/S/Avatar/Failure/then/Mark")).toBe(nil)
		expect(adapter.node("/S/Avatar/Placeholder/then/Fill") ~= nil).toBe(true)
	end)

	it("release-then-stale-completion never resurrects (honest cancellation)", function()
		local _, provider, scope, adapter, controller, img = slice("rbxthumb://b")
		local pending = provider.pendingRequests()
		local key, generation = pending[1].key, pending[1].generation
		img.handle.release()
		-- the engine fetch cannot be stopped; its late completion must be stale
		local verdict = provider.complete(key, generation, key)
		expect(verdict).toBe("stale")
		controller.refresh()
		expect(adapter.node("/S/Avatar/Content").props.image).toBe("")
	end)
end)
