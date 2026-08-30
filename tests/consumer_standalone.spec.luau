--!strict
--[[ THE STANDALONE CONSUMER, PROVED.

	`examples/consumer/` is the smallest complete Facet project: a Rojo project
	file, a client script, and one screen module. This spec mounts THAT SAME
	screen module — not a copy of it — against the headless fake render target and
	proves the six things a consumer needs to be true:

	  1. it mounts;
	  2. a theme reaches it, and the paint follows the theme rather than a colour
	     written into the example;
	  3. a button answers a press through the public input path;
	  4. a signal write repaints the label that reads it;
	  5. a viewport change and a preferred-text change both RE-SOLVE the same
	     mounted surface rather than rebuilding it; and
	  6. teardown returns the reactive registries to the baseline they had before
	     the screen existed.

	WHY IT SHARES THE MODULE RATHER THAN RESTATING IT. An example that only Roblox
	can run is an example that rots: the guide keeps teaching it and nothing
	notices when the library moves underneath. `screen.build(Facet, core, deps)`
	takes the library as an argument precisely so the client script can reach it
	through the instance tree while this file reaches it by path, and both mount
	the identical description.

	The host is the real one, `src/client/host.luau`, driven through its own
	documented seams: a hand-cranked frame source, the public action system, and
	the fake target. Nothing here reaches a Facet internal that a consumer could
	not.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
local host = require("../src/client/host") :: any
local sheet_model = require("../src/tokens/sheet_model") :: any
local fake_target = require("./lib/fake_target")
local consumerScreen = require("../examples/consumer/src/screen") :: any
local parchment = require("../examples/themes/fantasy_parchment") :: any

local PATHS = consumerScreen.PATHS

local COMPACT = { w = 390, h = 844 }
local WIDE = { w = 1440, h = 900 }

--[[ A hand-cranked frame source, the same shape `tests/client_host.spec.luau`
	uses: `step(dt)` is one PreRender edge. ]]
local function newFrames()
	local fns: { (dt: number) -> () } = {}
	return {
		connect = function(fn: (dt: number) -> ()): () -> ()
			table.insert(fns, fn)
			return function()
				local i = table.find(fns, fn)
				if i ~= nil then
					table.remove(fns, i)
				end
			end
		end,
		step = function(dt: number)
			for _, fn in table.clone(fns) do
				fn(dt)
			end
		end,
	}
end

type Stand = {
	h: any,
	adapter: any,
	built: any,
	step: (dt: number) -> (),
	baseline: any,
	teardown: () -> (),
}

local function stand(viewport: { w: number, h: number }): Stand
	local frames = newFrames()
	local adapter = fake_target.new()
	local h = host.new({
		newAdapter = function()
			return adapter
		end,
		newInputSystem = function(core: any)
			return Facet.newActionSystem(core)
		end,
		bindEnv = function(env: any)
			env:set("viewportRect", { x = 0, y = 0, w = viewport.w, h = viewport.h })
			return function() end
		end,
		connectFrame = frames.connect,
	})

	--[[ The baseline is taken with the host standing and NOTHING presented, which
		is the only honest comparison for "the screen left nothing behind": the
		host's own environment and presenter are supposed to survive until
		`h.dispose()`. ]]
	local baseline = h.core:counters()

	local built = consumerScreen.build(Facet, h.core, { env = h.env, presenter = h.presenter })
	local handle = h.presenter.present(built.blueprint)
	frames.step(1 / 60)

	local torn = false
	return {
		h = h,
		adapter = adapter,
		built = built,
		step = frames.step,
		baseline = baseline,
		teardown = function()
			if torn then
				return
			end
			torn = true
			--[[ The presented surface first: `dismiss` retires the screen, its focus
				scope and its input context. Then the screen's own scope, then the
				host. A consumer that disposes the host while a surface is still
				presented leaves that surface's observers alive on the core, which is
				what the baseline case below would report. ]]
			h.presenter.dismiss(handle)
			built.dispose()
			h.dispose()
		end,
	}
end

local function rectOf(adapter: any, path: string): any
	local node = adapter.node(path)
	assert(node ~= nil, `no node at {path}`)
	return node.rect
end

local function near(a: number, b: number): boolean
	return math.abs(a - b) < 0.001
end

describe("examples/consumer: the standalone project mounts", function()
	it("puts every part of the screen on the target", function()
		local s = stand(COMPACT)
		for _, path in { PATHS.root, PATHS.title, PATHS.blurb, PATHS.count, PATHS.sound, PATHS.bump, PATHS.close } do
			local node = s.adapter.node(path)
			expect(node ~= nil).toBe(true)
			expect(node.rect ~= nil and node.rect.w > 0 and node.rect.h > 0).toBe(true)
		end
		expect(s.h.core:lastError()).toBe(nil)
		s.teardown()
	end)

	it("reads its label out of the signal, not out of a literal", function()
		local s = stand(COMPACT)
		expect(s.adapter.node(PATHS.count).props.text).toBe("0 taps")
		s.teardown()
	end)
end)

describe("examples/consumer: the theme decides the paint", function()
	it("repaints the accent tint when a theme package is committed", function()
		local s = stand(COMPACT)
		local before = s.adapter.node(PATHS.count).tintColor
		expect(before ~= nil).toBe(true)

		local package = parchment.build(Facet.themes)
		local themeName = package.style.themes[1].name
		s.adapter.setThemePackage(package, themeName, nil)
		s.h.presenter.refresh()

		local after = s.adapter.node(PATHS.count).tintColor
		local accent = sheet_model.paletteColor(package.style.themes[1], "accent")
		expect(after ~= nil).toBe(true)
		-- blend = 1 lands exactly on the role, so the painted colour IS the
		-- package's accent — a colour this example never names
		expect(near(after.r, accent.r) and near(after.g, accent.g) and near(after.b, accent.b)).toBe(true)
		expect(#s.adapter.themePackagePushes()).toBe(1)
		s.teardown()
	end)
end)

describe("examples/consumer: input and state", function()
	it("a press on Bump raises the count and repaints the label", function()
		local s = stand(COMPACT)
		expect(s.built.count:get()).toBe(0)

		s.adapter.tap(PATHS.bump)
		s.h.presenter.refresh()

		expect(s.built.count:get()).toBe(1)
		expect(s.adapter.node(PATHS.count).props.text).toBe("1 tap")
		expect(s.h.core:lastError()).toBe(nil)
		s.teardown()
	end)

	it("a write to the signal repaints the label with no press at all", function()
		local s = stand(COMPACT)
		s.built.count:set(41)
		s.h.presenter.refresh()
		expect(s.adapter.node(PATHS.count).props.text).toBe("41 taps")
		s.teardown()
	end)

	it("the toggle carries the signal the screen owns", function()
		local s = stand(COMPACT)
		expect(s.adapter.node(PATHS.sound).props.value).toBe(true)
		s.built.soundOn:set(false)
		s.h.presenter.refresh()
		expect(s.adapter.node(PATHS.sound).props.value).toBe(false)
		s.teardown()
	end)

	it("Close reports itself, which is what the client script tears down on", function()
		local s = stand(COMPACT)
		expect(s.built.closed:get()).toBe(false)
		s.adapter.tap(PATHS.close)
		s.h.presenter.refresh()
		expect(s.built.closed:get()).toBe(true)
		s.teardown()
	end)
end)

describe("examples/consumer: it adapts by re-solving", function()
	it("the button stack arranges differently at a compact and a wide viewport", function()
		local compact = stand(COMPACT)
		local wide = stand(WIDE)

		local compactRow = near(rectOf(compact.adapter, PATHS.bump).y, rectOf(compact.adapter, PATHS.close).y)
		local wideRow = near(rectOf(wide.adapter, PATHS.bump).y, rectOf(wide.adapter, PATHS.close).y)
		-- the point is not WHICH way each one goes; it is that the same
		-- description answers differently, with no device name in the example
		expect(compactRow ~= wideRow).toBe(true)

		compact.teardown()
		wide.teardown()
	end)

	it("a viewport change re-solves the mounted surface without rebuilding it", function()
		local s = stand(COMPACT)
		local created = #s.adapter.paths()
		local before = near(rectOf(s.adapter, PATHS.bump).y, rectOf(s.adapter, PATHS.close).y)

		s.h.env:set("viewportRect", { x = 0, y = 0, w = WIDE.w, h = WIDE.h })
		s.step(1 / 60)

		local after = near(rectOf(s.adapter, PATHS.bump).y, rectOf(s.adapter, PATHS.close).y)
		expect(after ~= before).toBe(true)
		-- the same nodes, moved: a rebuild would have changed the node set
		expect(#s.adapter.paths()).toBe(created)
		expect(s.h.core:lastError()).toBe(nil)
		s.teardown()
	end)

	it("the player's preferred text size grows the untouched label", function()
		local s = stand(COMPACT)
		local before = rectOf(s.adapter, PATHS.blurb).h

		s.h.env:set("preferredTextSize", 2)
		s.step(1 / 60)

		--[[ `Blurb` declares no text size at all: it takes the body role and moves
			with the accessibility setting. That is what "respected by doing
			nothing" means, and a hard-coded pixel size is what breaks it. ]]
		expect(rectOf(s.adapter, PATHS.blurb).h > before).toBe(true)
		s.teardown()
	end)
end)

describe("examples/consumer: teardown leaves nothing behind", function()
	it("returns the reactive registries to their pre-screen baseline", function()
		local s = stand(COMPACT)
		s.adapter.tap(PATHS.bump)
		s.h.presenter.refresh()

		s.teardown()

		local after = s.h.core:counters()
		expect(after.observers).toBe(s.baseline.observers)
		expect(after.scopes).toBe(s.baseline.scopes)
	end)

	it("takes every node off the render target", function()
		local s = stand(COMPACT)
		expect(#s.adapter.paths() > 0).toBe(true)
		s.teardown()
		expect(s.adapter.rootCount()).toBe(0)
	end)
end)
