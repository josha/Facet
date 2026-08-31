--!strict
-- RenderTargetAdapter conformance (the billboard extension of the §13 seam): the
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

local Facet = require("../src")
local target_contract = require("../src/render/target_contract")
local renderer = require("../src/render/renderer")
local fake_target = require("../tests/lib/fake_target")
local adapter_source = require("./lib/adapter_source")

describe("RenderTargetAdapter contract", function()
	it("the FakeTarget satisfies every required and optional method", function()
		local result = target_contract.check(fake_target.new())
		expect(#result.missing).toBe(0)
		expect(#result.optionalAbsent).toBe(0)
	end)

	-- SEAM-20: `check` used to answer a narrower question than the seam. Ten
	-- methods the framework CALLS — five feature-detected by the renderer, five
	-- by the theme controller — were on neither list, so an adapter could pass
	-- with `#optionalAbsent == 0` and still ship with no hit-target floor, no
	-- wheel channel, no display order, no reduced-motion suppression and no
	-- theming. The lists are the contract, so the pin is: the ten are declared,
	-- the fake implements them, and the LIVE adapter names every one it has grown.
	--
	-- The tenth is `setThemeStyle` (ARCH-5): F-35's repair stopped at nine, and the
	-- one the controller still called through a bare `type(...) == "function"` was
	-- the one the file that states the rule did not declare.
	-- ELEVEN since C1 (2026-08-12): `setReducedMotion` is the bespoke half of the
	-- reduced-motion fact, feature-detected by the renderer beside the sheet half.
	it("the contract DECLARES all eleven methods the framework feature-detects", function()
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
			setReducedMotion = "OPTIONAL",
			setRootDisplayOrder = "OPTIONAL",
			-- theme-controller-called
			themeRootGui = "THEME",
			setThemePackage = "THEME",
			relinkThemeSheet = "THEME",
			nativeStyleInfo = "THEME",
			setThemeStyle = "THEME",
		}
		for name, list in expected do
			expect(`{name}={declared[name]}`).toBe(`{name}={list}`)
		end
		-- and the framework's own call sites are the source of that list: every
		-- `type(adapter.X) == "function"` guard in the theme controller must be a
		-- declared THEME name. This is the check that would have caught the gap.
		local controllerSource = fs.readFile("src/client/theme_controller.luau")
		for name in string.gmatch(controllerSource, 'type%(adapter%.([%w_]+)%) == "function"') do
			expect(`{name}={declared[name]}`).toBe(`{name}=THEME`)
		end
	end)

	-- ...and exactly one of those THEME names is a GROWTH seam, not a prerequisite
	-- (the controller calls it "for any target that grows the seam").
	-- Pinned as its own set so `themeable` cannot quietly become false for every
	-- shipping adapter the day a growth name joins the list.
	it("setThemeStyle is a GROWTH seam: declared, feature-detected, never a theming blocker", function()
		expect(target_contract.THEME_GROWTH.setThemeStyle).toBe(true)
		local growthNames: { string } = {}
		for name in target_contract.THEME_GROWTH do
			table.insert(growthNames, name)
		end
		expect(table.concat(growthNames, ",")).toBe("setThemeStyle")

		-- a target with every prerequisite but no growth seam is STILL themeable,
		-- and the absence is reported rather than swallowed
		local bare = target_contract.check({
			nativeStyleInfo = function() end,
			themeRootGui = function() end,
			setThemePackage = function() end,
			relinkThemeSheet = function() end,
		})
		expect(#bare.themeAbsent).toBe(0)
		expect(bare.themeable).toBe(true)
		expect(table.concat(bare.themeGrowthAbsent, ",")).toBe("setThemeStyle")

		-- the FakeTarget HAS grown it, and records what the controller pushed
		local themed = fake_target.new({ trackThemeRoots = true })
		expect(#target_contract.check(themed).themeGrowthAbsent).toBe(0)
		expect(#themed.themeStylePushes()).toBe(0)
		themed.setThemeStyle({ marker = "compiled" })
		expect(themed.themeStylePushes()[1].marker).toBe("compiled")
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
		-- is read exactly as check_prop_parity reads it.
		--
		-- TWO SHAPES COUNT AS IMPLEMENTED, because the adapter is no longer one
		-- file: a seam extracted to a sibling (src/client/screen_scroll_indicators,
		-- for Studio's 200_000-char `Source` write cap) declares its function there
		-- and screen_target BINDS it onto `adapter` under the same name. Either the
		-- definition or the binding proves the name is on the shipped adapter; a
		-- name with neither is genuinely absent.
		local liveSource = fs.readFile("src/client/screen_target.luau")
		local absent: { string } = {}
		local growthAbsent: { string } = {}
		for _, list in { target_contract.REQUIRED, target_contract.OPTIONAL, target_contract.THEME } do
			for _, name in list do
				local declared = string.find(liveSource, `function adapter.{name}(`, 1, true) ~= nil
				local bound = string.find(liveSource, `adapter.{name} = `, 1, true) ~= nil
				if not declared and not bound then
					if target_contract.THEME_GROWTH[name] then
						table.insert(growthAbsent, name)
					else
						table.insert(absent, name)
					end
				end
			end
		end
		table.sort(absent)
		table.sort(growthAbsent)
		-- ScreenTarget's ONE declared-but-ungrown name, asserted exactly (ARCH-5).
		-- The ruling: it takes its bespoke style at construction and exposes
		-- no runtime setter, so the palette half of a swap does not reach it. Pinned
		-- both ways — if it grows the seam this fails and says "move it".
		expect(table.concat(growthAbsent, ",")).toBe("setThemeStyle")
		if #absent > 0 then
			error(
				`src/client/screen_target.luau declares no `
					.. `{table.concat(absent, ", ")} — a declared contract name the shipped adapter does not implement`,
				0
			)
		end
	end)

	it("a billboard-sized pixel canvas renders a nameplate and updates paint-only", function()
		local core = Facet.newCore()
		local env = Facet.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 300, h = 96 }) -- the canvas
		local adapter = fake_target.new()
		local health = core:signal("100")
		local root = Facet.mount(
			core,
			Facet.UI.Screen({
				id = "Nameplate",
				padding = 8,
				gap = 4,
				children = {
					Facet.UI.Text({ id = "Name", text = "Razz Raccoon", textSize = 18 }),
					Facet.UI.Text({ id = "Health", text = health, textSize = 14 }),
				},
			})
		)
		local controller = Facet.renderer.attach(core, root, env, adapter, {})
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

-- ===== HANDLED-PROP PARITY (found defect SF-M9) ==================
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
-- view is read from source exactly as check_prop_parity reads it — `adapter_source
-- .live()`, since the whole `prop == "<name>"` switch is `screen_props.luau` now
-- (source-cap-ledger, 2026-08-28): screen_target itself branches on no prop at all.
describe("adapter prop parity: the fake and the live target handle the same props", function()
	local liveSource = adapter_source.live()

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
				return Facet.UI.Text({ id = "T", text = "x", role = role })
			end)
			expect(`{role}=accepted:{ok}`).toBe(`{role}=accepted:true`)
		end
		local rejected = pcall(function()
			return Facet.UI.Text({ id = "T", text = "x", role = "accent" })
		end)
		expect(rejected).toBe(false)
		expect(blueprint ~= nil).toBe(true)

		-- the FALLBACK path (no native StyleSheets) is where the one-way write was:
		-- the branch must key its colour off the value, not gate the whole write on
		-- `value == "secondary"`. The `role` branch is `screen_props.luau`'s now
		-- (source-cap-ledger, 2026-08-28).
		local source = fs.readFile("src/client/screen_props.luau")
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

--[[ THE PLAYBOOK'S OPTIONAL-METHOD ROSTER IS THE CONTRACT'S (MAINT-8b).

	`docs/extending/new-render-target.md` transcribed the OPTIONAL list by hand —
	23 names against the contract's 28 — and nothing cross-checked the doc against
	the table it copies, so the drift was already three days old at freeze. The
	consequence is not cosmetic: the doc's whole job is to tell a target author
	which absences are legal degrades, and five methods the renderer feature-
	detects were simply not in the list they were reading. ]]
describe("the render-target playbook's OPTIONAL roster (MAINT-8b)", function()
	local MARKER_OPEN = "<!-- OPTIONAL-METHODS: derived from src/render/target_contract.luau OPTIONAL -->"
	local MARKER_CLOSE = "<!-- /OPTIONAL-METHODS -->"

	local function documentedOptional(source: string): { [string]: boolean }
		local from = string.find(source, MARKER_OPEN, 1, true)
		local to = string.find(source, MARKER_CLOSE, 1, true)
		assert(from ~= nil and to ~= nil, "new-render-target.md lost its OPTIONAL-METHODS markers")
		local block = string.sub(source, (from :: number) + #MARKER_OPEN, (to :: number) - 1)
		local out: { [string]: boolean } = {}
		for name in string.gmatch(block, "`([%w_]+)`") do
			out[name] = true
		end
		return out
	end

	it("names every OPTIONAL method the contract declares, and nothing else", function()
		local documented = documentedOptional(fs.readFile("docs/extending/new-render-target.md"))
		local declared: { [string]: boolean } = {}
		for _, name in target_contract.OPTIONAL do
			declared[name] = true
			expect(`documented {name}: {tostring(documented[name] == true)}`).toBe(`documented {name}: true`)
		end
		for name in documented do
			expect(`declared {name}: {tostring(declared[name] == true)}`).toBe(`declared {name}: true`)
		end
		-- the instrument is not vacuous: there really are that many
		expect(#target_contract.OPTIONAL >= 25).toBe(true)
	end)

	it("BITES: a method added to the contract and not to the playbook fails", function()
		local documented = documentedOptional(fs.readFile("docs/extending/new-render-target.md"))
		-- the mutation the finding describes, in miniature
		expect(documented.setSomethingBrandNew).toBe(nil)
		local missing: { string } = {}
		for _, name in { "setSomethingBrandNew", "setActivateHandler" } do
			if not documented[name] then
				table.insert(missing, name)
			end
		end
		expect(missing).toEqual({ "setSomethingBrandNew" })
	end)
end)

--[[ EVERY SKINNED CONTROL'S ART IS ENFORCED, NOT JUST THE WORKED EXAMPLE
	(MAINT-8d). `docs/extending/skinned-control.md` promised a contributor that
	`check_docs_cli` enforced their control's art, provenance and manifest; the
	checker hardcoded `assets/themes/ornate-gauge`. The roster is derived from the
	manifests now — a manifest with a `control` and a null `package` IS the
	registration — so a second control is covered the moment it ships one. ]]
describe("skinned-control asset roots are derived (MAINT-8d)", function()
	local skinned_controls = require("../tools/lune/skinned_controls")

	it("finds the shipped rung-3 control from its manifest, not from a path", function()
		local roots = skinned_controls.roots()
		expect(#roots >= 1).toBe(true)
		local gauge: any = nil
		for _, root in roots do
			if root.control == "OrnateGauge" then
				gauge = root
			end
		end
		expect(gauge ~= nil).toBe(true)
		expect(gauge.dir).toBe("assets/themes/ornate-gauge")
		expect(gauge.controlModule).toBe("examples/themes/ornate_gauge.luau")
		-- ...and the files come from the manifest's own assets table
		local files: { [string]: boolean } = {}
		for _, file in gauge.files do
			files[file] = true
		end
		for _, file in
			{
				"assets/themes/ornate-gauge/gauge_face.png",
				"assets/themes/ornate-gauge/gauge_needle.png",
				"assets/themes/ornate-gauge/gauge_endcap.png",
				"assets/themes/ornate-gauge/provenance.md",
				"assets/themes/ornate-gauge/upload-manifest.json",
				"assets/themes/ornate-gauge/source/generate_art.py",
			}
		do
			expect(`{file}: {tostring(files[file] == true)}`).toBe(`{file}: true`)
		end
	end)

	it("a THEME package's art is not mistaken for a control's", function()
		for _, root in skinned_controls.roots() do
			-- a package's manifest names a package; a control's names a control
			expect(`{root.dir} control: {tostring(#root.control > 0)}`).toBe(`{root.dir} control: true`)
			expect(root.dir ~= "assets/themes/fantasy-parchment").toBe(true)
		end
	end)

	it("BITES: check_docs requires every file the manifest names", function()
		local check_docs = require("../tools/lune/check_docs")
		local gauge = skinned_controls.ownerOf("assets/themes/ornate-gauge/gauge_face.png")
		expect(gauge ~= nil).toBe(true)
		local result = check_docs.check({ missingFiles = { ["assets/themes/ornate-gauge/gauge_needle.png"] = true } })
		expect(result.ok).toBe(false)
		local named = false
		for _, problem in result.problems do
			local text = if type(problem) == "table"
				then tostring(problem.what) .. tostring(problem.path)
				else tostring(problem)
			if string.find(text, "gauge_needle.png", 1, true) ~= nil then
				named = true
				-- the message names the OWNER it derived, not a hardcoded string
				expect(string.find(text, "OrnateGauge", 1, true) ~= nil).toBe(true)
			end
		end
		expect(named).toBe(true)
	end)
end)
