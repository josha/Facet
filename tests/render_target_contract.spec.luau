--!strict
-- RenderTargetAdapter conformance (ADR-0009 extension of the §13 seam): the
-- FakeTarget satisfies the full contract headless, and a billboard-shaped
-- pixel canvas (small offset-Size viewport — BillboardGui canvases are offset
-- pixels ONLY; scale means studs) renders and updates through the ordinary
-- pipeline with prop-only writes. The engine BillboardTarget reuses the
-- ScreenTarget internals via a root factory, so this canvas contract is the
-- headless half of its conformance; the instance half runs in the Studio
-- drive (artifacts/studio/part2-billboard.json).

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local fs = require("@lune/fs")

local LuauUI = require("../src")
local target_contract = require("../src/render/target_contract")
local renderer = require("../src/render/renderer")
local fake_target = require("../tests/lib/fake_target")

describe("RenderTargetAdapter contract", function()
	it("the FakeTarget satisfies every required and optional method", function()
		local result = target_contract.check(fake_target.new())
		expect(#result.missing).toBe(0)
		expect(#result.optionalAbsent).toBe(0)
	end)

	-- SEAM-20: `check` used to answer a narrower question than the seam. Nine
	-- methods the framework CALLS — five feature-detected by the renderer, four
	-- by the theme controller — were on neither list, so an adapter could pass
	-- with `#optionalAbsent == 0` and still ship with no hit-target floor, no
	-- wheel channel, no display order, no reduced-motion suppression and no
	-- theming. The lists are the contract, so the pin is: the nine are declared,
	-- the fake implements them, and the LIVE adapter names every one.
	it("the contract DECLARES all nine methods the framework feature-detects", function()
		local declared: { [string]: string } = {}
		for _, name in target_contract.OPTIONAL do
			declared[name] = "OPTIONAL"
		end
		for _, name in target_contract.THEME do
			declared[name] = "THEME"
		end
		local expected = {
			-- renderer-called
			getScrollPosition = "OPTIONAL",
			setHitRect = "OPTIONAL",
			setScrollHandler = "OPTIONAL",
			setNativeTransitionsEnabled = "OPTIONAL",
			setRootDisplayOrder = "OPTIONAL",
			-- theme-controller-called
			themeRootGui = "THEME",
			setThemePackage = "THEME",
			relinkThemeSheet = "THEME",
			nativeStyleInfo = "THEME",
		}
		for name, list in expected do
			expect(`{name}={declared[name]}`).toBe(`{name}={list}`)
		end
	end)

	it("the FakeTarget satisfies the THEME group too (relink rides the opt-in)", function()
		-- `relinkThemeSheet` is declared ONLY under trackThemeRoots, deliberately:
		-- a fake that always carried it would never exercise the single-root
		-- `linkAt` fallback every other target still uses (fake_target.luau:137).
		-- So the themeable fake is the opted-in one, and the default fake's only
		-- theme gap is that one method.
		local themed = target_contract.check(fake_target.new({ trackThemeRoots = true }))
		expect(#themed.themeAbsent).toBe(0)
		expect(themed.themeable).toBe(true)

		local plain = target_contract.check(fake_target.new())
		expect(table.concat(plain.themeAbsent, ",")).toBe("relinkThemeSheet")
		expect(plain.themeable).toBe(false)
	end)

	it("the LIVE ScreenTarget implements every declared name (its source is the contract)", function()
		-- screen_target.luau cannot load headless (engine globals at load), so it
		-- is read exactly as check_prop_parity reads it
		local liveSource = fs.readFile("src/client/screen_target.luau")
		local absent: { string } = {}
		for _, list in { target_contract.REQUIRED, target_contract.OPTIONAL, target_contract.THEME } do
			for _, name in list do
				if string.find(liveSource, `function adapter.{name}(`, 1, true) == nil then
					table.insert(absent, name)
				end
			end
		end
		table.sort(absent)
		if #absent > 0 then
			error(
				`src/client/screen_target.luau declares no `
					.. `{table.concat(absent, ", ")} — a declared contract name the shipped adapter does not implement`,
				0
			)
		end
	end)

	it("a billboard-sized pixel canvas renders a nameplate and updates paint-only", function()
		local core = LuauUI.newCore()
		local env = LuauUI.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 300, h = 96 }) -- the canvas
		local adapter = fake_target.new()
		local health = core:signal("100")
		local root = LuauUI.mount(
			core,
			LuauUI.UI.Screen({
				id = "Nameplate",
				padding = 8,
				gap = 4,
				children = {
					LuauUI.UI.Text({ id = "Name", text = "Razz Raccoon", textSize = 18 }),
					LuauUI.UI.Text({ id = "Health", text = health, textSize = 14 }),
				},
			})
		)
		local controller = LuauUI.renderer.attach(core, root, env, adapter, {})
		controller.initialRender()
		local name = adapter.node("/Nameplate/Name")
		expect(name.rect.x).toBe(8)
		expect(name.rect.w <= 300 - 16).toBe(true)
		adapter.takeOps()
		health:set("87")
		controller.refresh()
		expect(adapter.node("/Nameplate/Health").props.text).toBe("87")
		-- minimal writes: the prop write plus re-measure rect updates only —
		-- never creates/removes (text is geometry-affecting by contract)
		local ops = adapter.takeOps()
		expect(#ops >= 1).toBe(true)
		expect(string.sub(ops[1], 1, 4)).toBe("prop")
		for i = 2, #ops do
			expect(string.sub(ops[i], 1, 4)).toBe("rect")
		end
	end)
end)

-- ===== HANDLED-PROP PARITY (ADR-0022; found defect SF-M9) ==================
--
-- The defect this pins: `setProp` is a STRING-keyed switch on both adapters, and
-- the fake one recorded anything. So the renderer could write a prop the live
-- adapter had no branch for, headlessly forever — which is exactly how the
-- keyboard keep-visible transform shipped as a device no-op while its specs were
-- green. Method-level conformance (above) could never catch it: both adapters had
-- `setProp`.
--
-- Three views, pinned against each other: what the renderer DECLARES it emits,
-- what the FakeTarget declares it handles, and what the live adapter's own switch
-- actually branches on. `screen_target` is client-only (it reaches engine globals
-- at load, and check_boundary forbids requiring it outside client code), so its
-- view is read from source exactly as check_prop_parity reads it.
describe("adapter prop parity: the fake and the live target handle the same props", function()
	local liveSource = fs.readFile("src/client/screen_target.luau")

	local function liveHandled(): { [string]: boolean }
		local handled: { [string]: boolean } = {}
		for prop in string.gmatch(liveSource, 'prop == "([%w_]+)"') do
			handled[prop] = true
		end
		return handled
	end

	local function fakeHandled(): { [string]: boolean }
		local handled: { [string]: boolean } = {}
		for _, prop in fake_target.HANDLED_PROPS do
			handled[prop] = true
		end
		return handled
	end

	it("every prop the renderer can emit is handled by the LIVE adapter", function()
		local live = liveHandled()
		local missing: { string } = {}
		for prop in renderer.EMITTED_PROPS do
			if not live[prop] then
				table.insert(missing, prop)
			end
		end
		table.sort(missing)
		if #missing > 0 then
			error(
				`screen_target.setProp has no branch for: {table.concat(missing, ", ")} — `
					.. "the renderer writes them, so on a device they would be silent no-ops (SF-M9)",
				0
			)
		end
		-- the channel is real, not merely declared: both presentation props included
		expect(renderer.EMITTED_PROPS.transform).toBe(true)
		expect(renderer.EMITTED_PROPS.transparency).toBe(true)
		expect(live.transform).toBe(true)
		expect(live.transparency).toBe(true)
	end)

	it("every prop the renderer can emit is handled by the FAKE adapter", function()
		local fake = fakeHandled()
		local missing: { string } = {}
		for prop in renderer.EMITTED_PROPS do
			if not fake[prop] then
				table.insert(missing, prop)
			end
		end
		table.sort(missing)
		expect(#missing == 0).toBe(true)
		if #missing > 0 then
			error(`FakeTarget declares no handler for: {table.concat(missing, ", ")}`, 0)
		end
	end)

	it("the two adapters agree: nothing is handled by one and not the other", function()
		local live, fake = liveHandled(), fakeHandled()
		local onlyFake: { string } = {}
		for prop in fake do
			if not live[prop] then
				table.insert(onlyFake, prop)
			end
		end
		table.sort(onlyFake)
		if #onlyFake > 0 then
			error(
				`the FakeTarget handles props the live adapter does not: {table.concat(onlyFake, ", ")} — `
					.. "a headless green that cannot land on a device is the SF-M9 defect class",
				0
			)
		end
		-- the other direction is intentionally looser: the live adapter may branch on
		-- a prop the renderer does not emit yet (a control-owned write), and that is
		-- dead code rather than a lie about a channel. It still has to be declared
		-- emitted for the fake to accept it, which the two checks above enforce.
		local declared: { [string]: boolean } = {}
		for prop in renderer.EMITTED_PROPS do
			declared[prop] = true
		end
		for prop in fake do
			expect(declared[prop]).toBe(true)
		end
	end)

	it("the FakeTarget REFUSES an undeclared prop instead of recording it", function()
		local adapter = fake_target.new()
		local handle = adapter.create(adapter.createRoot("S"), "/S", "Box")
		local ok, err = pcall(function()
			adapter.setProp(handle, "glowIntensity", 1, "style")
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "not a declared handled prop", 1, true) ~= nil).toBe(true)
		-- and the message names BOTH files, because the fix is always both
		expect(string.find(tostring(err), "screen_target", 1, true) ~= nil).toBe(true)
	end)

	-- A REACTIVE STYLE ROLE MUST BE ABLE TO COME BACK (found building RascalRally's
	-- racer list: rows recede to `secondary` while blocked and return when the
	-- block lifts). `role` is declared reactive, so the closed set has to name its
	-- RESTING end too — a binding can only resolve to a value, and `nil` drops the
	-- prop instead of writing the default. Both halves are asserted here: the
	-- schema accepts the word, and the engine adapter paints both directions (its
	-- source is the contract — screen_target.luau cannot load headless).
	it("Text.role names BOTH ends of its closed set, and both adapters write both", function()
		local blueprint = require("../src/blueprint")
		for _, role in { "secondary", "content" } do
			local ok = pcall(function()
				return LuauUI.UI.Text({ id = "T", text = "x", role = role })
			end)
			expect(`{role}=accepted:{ok}`).toBe(`{role}=accepted:true`)
		end
		local rejected = pcall(function()
			return LuauUI.UI.Text({ id = "T", text = "x", role = "accent" })
		end)
		expect(rejected).toBe(false)
		expect(blueprint ~= nil).toBe(true)

		-- the FALLBACK path (no native StyleSheets) is where the one-way write was:
		-- the branch must key its colour off the value, not gate the whole write on
		-- `value == "secondary"`
		local source = fs.readFile("src/client/screen_target.luau")
		expect(string.find(source, 'and value == "secondary" then', 1, true)).toBe(nil)
		expect(
			string.find(
				source,
				'instance.TextColor3 = if value == "secondary" then COLOR.contentSecondary else COLOR.content',
				1,
				true
			) ~= nil
		).toBe(true)
		-- and the NATIVE path stays a round-trippable boolean tag
		expect(string.find(source, 'handle.nativeRoleSecondary = value == "secondary"', 1, true) ~= nil).toBe(true)
	end)

	it("the renderer's declared emissions are exactly its two channels plus its own seams", function()
		for prop in renderer.BINDING_PROPS do
			expect(renderer.EMITTED_PROPS[prop]).toBe(true)
		end
		for prop in renderer.STYLE_PROPS do
			expect(renderer.EMITTED_PROPS[prop]).toBe(true)
		end
		-- each dedicated seam names itself, so an exemption is a decision on the
		-- record rather than a hole
		for prop, seam in renderer.DIRECT_PROPS do
			expect(renderer.EMITTED_PROPS[prop]).toBe(true)
			expect(#seam > 0).toBe(true)
		end
	end)
end)
