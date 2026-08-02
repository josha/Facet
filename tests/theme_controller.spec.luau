--!strict
-- THE THEME CONTROLLER (ADR-0019 §3/§6/§7, stage theme-packages-and-skinning).
--
-- What this spec pins, all of it headless:
--   * INSTALL is all-or-nothing. Every capability check runs before the first
--     mutation, so a refused install leaves the target and the environment
--     exactly as it found them — the failure mode that would otherwise restyle
--     somebody else's tree.
--   * THE SWAP IS ONE TRANSACTION. The derive swap and the metric commit share
--     one invocation (feasibility m5), costing exactly ONE solve pass and zero
--     factory reruns, creates or removes: mount identity, focus, scroll and
--     text entry survive because nothing is rebuilt.
--   * THE LIVE AUTHORING LOOP. A supported metric/font token edited on the
--     ACTIVE theme sheet re-resolves the snapshot and re-solves the surface; an
--     unknown attribute is ignored with exactly one warn; the watch never leaks
--     a connection across swap or uninstall.
--   * THE SYNC CODEC round-trips every typed kind value-exact and its diff is
--     what the freshness gate fails on (feasibility m6).
--   * FONT PREFLIGHT reserves conservatively until a descriptor calibrates and
--     never invents a second relayout loop.
--
-- The engine half (StyleSheet, StyleLink, attributes) is injected through
-- `opts.nativeStyle`, the same seam the native_style scenario stubs — so the
-- controller's ORDERING and BOOKKEEPING are provable with no engine, while the
-- materialization itself stays the Studio scenario's evidence.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local luau = require("@lune/luau")

local customFactory = require("../src/core/custom")
local UI = require("../src/blueprint")
local mountLib = require("../src/mount")
local environment = require("../src/env/environment")
local renderer = require("../src/render/renderer")
local themes = require("../src/themes/package")
local snapshot = require("../src/themes/snapshot")
local token_sync = require("../src/themes/token_sync")
local text_metrics = require("../src/layout/text_metrics")
local theme_controller = require("../src/client/theme_controller")
local defaultStyle = require("../src/tokens/default_style")
local defaultLightStyle = require("../src/tokens/default_light_style")
local fake_target = require("./lib/fake_target")

-- ===== fixtures ============================================================

local function definePackage(id: string, metrics: any?, extra: any?): any
	local def: any = {
		base = snapshot.neutralPackage(),
		identity = { id = id, displayName = id, schemaVersion = themes.SCHEMA, version = "1.0.0" },
		style = {
			defaultTheme = "Dark",
			themes = {
				{ name = "Dark", colors = defaultStyle.colors, extra = defaultStyle.extra },
				{ name = "Light", colors = defaultLightStyle.colors, extra = defaultLightStyle.extra },
			},
		},
	}
	if metrics ~= nil then
		def.metrics = metrics
	end
	for key, value in extra or {} do
		def[key] = value
	end
	local pkg, report = themes.define(def)
	assert(
		pkg ~= nil,
		"fixture package failed to compile: " .. (if report.errors[1] then report.errors[1].message else "?")
	)
	return pkg
end

-- an in-memory stand-in for the engine half: sheets are tables, attributes are
-- typed records, and `AttributeChanged` is a listener list. It records every
-- call the controller makes so ordering claims are checkable.
local function fakeNative()
	local state: any = { ensures = 0, setThemes = 0, links = 0, live = 0, connects = 0, sheets = {} }
	local api: any = {}

	function api.available(): boolean
		return true
	end

	function api.ensure(model: any, opts: any): any
		state.ensures += 1
		local sheetThemes: any = {}
		for _, theme in model.themes do
			local entry = { attributes = {} :: any, listeners = {} :: { any } }
			for tokenName in theme.tokens do
				entry.attributes[tokenName] = { engineColor = tokenName } -- Step 2 paint token
			end
			for _, record in opts.tokens or {} do
				if entry.attributes[record.attribute] == nil then
					entry.attributes[record.attribute] = record
				end
			end
			sheetThemes[theme.name] = entry
		end
		local handle: any
		handle = {
			sheet = { Name = opts.sheetName },
			sheetName = opts.sheetName,
			themes = sheetThemes,
			stamp = model.stamp,
			seeded = true,
			migrated = false,
			activeTheme = "",
			mirrors = opts.mirrors,
			setTheme = function(name: string)
				assert(sheetThemes[name] ~= nil, `fakeNative: unknown theme '{name}'`)
				state.setThemes += 1
				handle.activeTheme = name
			end,
			setTransitionsEnabled = function() end,
			readTokens = function(theme: string, wanted: { any }): { any }
				local out: { any } = {}
				local entry = sheetThemes[theme]
				for _, record in wanted do
					local held = if entry ~= nil then entry.attributes[record.attribute] else nil
					table.insert(out, if type(held) == "table" and held.kind ~= nil then held else record)
				end
				return out
			end,
			watchTokens = function(theme: string, fn: (string) -> ()): () -> ()
				local entry = sheetThemes[theme]
				state.live += 1
				state.connects += 1
				table.insert(entry.listeners, fn)
				local alive = true
				return function()
					if not alive then
						return
					end
					alive = false
					state.live -= 1
					for index, listener in entry.listeners do
						if listener == fn then
							table.remove(entry.listeners, index)
							break
						end
					end
				end
			end,
		}
		handle.setTheme(opts.theme or model.defaultTheme)
		state.sheets[opts.sheetName] = { handle = handle, themes = sheetThemes }
		return handle
	end

	function api.linkAt(_rootGui: any, sheet: any): (any, any?, boolean)
		state.links += 1
		local link: any = { StyleSheet = sheet, destroyed = false }
		function link.Destroy(self: any)
			self.destroyed = true
			state.links -= 1
		end
		state.lastLink = link
		return link, nil, true
	end

	-- a designer edit in the Style Editor: set the attribute, fire the signal
	function state.edit(sheetName: string, theme: string, attribute: string, value: any)
		local entry = state.sheets[sheetName].themes[theme]
		entry.attributes[attribute] = value
		for _, listener in table.clone(entry.listeners) do
			listener(attribute)
		end
	end

	return api, state
end

local function nativeAdapter(adapter: any, root: any)
	adapter.nativeStyleInfo = function()
		return { active = true }
	end
	adapter.themeRootGui = function()
		return root
	end
	return adapter
end

-- a mounted world so a commit is observable as a real solve
local function world(build: (core: any) -> any)
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
	local root = mountLib.mount(core, build(core))
	local adapter = fake_target.new()
	local controller = renderer.attach(core, root, env, adapter, {})
	controller.initialRender()
	return { core = core, env = env, root = root, adapter = adapter, renderer = controller }
end

local function screen()
	return UI.Screen({
		id = "S",
		padding = 0,
		gap = "m",
		children = {
			UI.Text({ id = "Title", text = "Settings", textSize = "title" }),
			UI.TextField({ id = "Field", text = "Ada" }),
			UI.Button({ id = "Go", label = "Go", height = { type = "minMax", min = "targetSizes.minimum" } }),
		},
	})
end

-- ===== install =============================================================

describe("theme_controller.install: per-target, all-or-nothing", function()
	it("installs a package on a native target: sheet, one link, one metric commit", function()
		local w = world(screen)
		local native, state = fakeNative()
		local pkg = definePackage("install-native", { space = { m = 40 } })
		local before = w.renderer.stats().solves
		local controller = theme_controller.install(nativeAdapter(w.adapter, { name = "Root" }), pkg, {
			env = w.env,
			nativeStyle = native,
		})
		expect(state.ensures).toBe(1)
		expect(state.links).toBe(1)
		expect(controller.current()).toBe("Dark")
		local info = controller.inspect()
		expect(info.mode).toBe("native")
		expect(info.fallback).toBe(false)
		expect(info.sheet.present).toBe(true)
		expect(info.sheet.name).toBe("LuauUITheme install-native")
		expect(info.link.present).toBe(true)
		expect(info.package.id).toBe("install-native")
		expect(info.snapshot.space.m).toBe(40)
		-- the commit reached the environment and the mounted surface re-solved
		expect(w.env:get("themeMetrics"):get().space.m).toBe(40)
		expect(w.renderer.stats().solves).toBe(before + 1)
	end)

	it("the sheet name is per package and NEVER the library's own name", function()
		local w = world(screen)
		local native = fakeNative()
		local controller = theme_controller.install(
			nativeAdapter(w.adapter, {}),
			definePackage("parchment"),
			{ env = w.env, nativeStyle = native }
		)
		expect(controller.inspect().sheet.name).toBe("LuauUITheme parchment")
		expect(controller.inspect().sheet.name ~= "LuauUI").toBe(true)
	end)

	it("package sheets carry NO reference mirrors — their attributes are the source", function()
		local w = world(screen)
		local native, state = fakeNative()
		theme_controller.install(nativeAdapter(w.adapter, {}), definePackage("no-mirrors"), {
			env = w.env,
			nativeStyle = native,
		})
		expect(state.sheets["LuauUITheme no-mirrors"].handle.mirrors).toBe(false)
	end)

	it("a fallback target still installs: the whole metric half, no sheet", function()
		local w = world(screen)
		local pkg = definePackage("fallback", { space = { m = 40 } })
		local controller = theme_controller.install(w.adapter, pkg, { env = w.env })
		local info = controller.inspect()
		expect(info.mode).toBe("fallback")
		expect(info.fallback).toBe(true)
		expect(type(info.fallbackReason)).toBe("string")
		expect(info.sheet.present).toBe(false)
		expect(info.link.present).toBe(false)
		-- the metrics landed anyway, which is where every layout value lives
		expect(w.env:get("themeMetrics"):get().space.m).toBe(40)
		-- ...and the compiled bespoke style is available for screen_target.new{style=}
		expect(info.style.colors.surface.r).toBe(defaultStyle.colors.surface.r)
		expect(info.style.extra.hairlineOpacity).toBe(defaultStyle.extra.hairlineOpacity)
		expect(info.style.space.m).toBe(40)
	end)
end)

describe("theme_controller.install: capability errors leave everything untouched", function()
	local function untouched(w: any, before: any, run: () -> ())
		local ok, err = pcall(run)
		expect(ok).toBe(false)
		expect(w.env:get("themeMetrics"):get()).toBe(before)
		return tostring(err)
	end

	it("a package requiring native paint on a fallback target names the capability", function()
		local w = world(screen)
		local before = w.env:get("themeMetrics"):get()
		local pkg = definePackage("needs-native", nil, { compatibility = { capabilities = { "nativeStyleSheets" } } })
		local err = untouched(w, before, function()
			theme_controller.install(w.adapter, pkg, { env = w.env })
		end)
		expect(string.find(err, "nativeStyleSheets", 1, true) ~= nil).toBe(true)
		expect(string.find(err, "environment", 1, true) ~= nil).toBe(true)
	end)

	it("a target that cannot expose its root fails, naming rootGui and themeRootGui", function()
		local w = world(screen)
		local before = w.env:get("themeMetrics"):get()
		local native = fakeNative()
		local blind = w.adapter
		blind.nativeStyleInfo = function()
			return { active = true }
		end
		local err = untouched(w, before, function()
			theme_controller.install(blind, definePackage("no-root"), { env = w.env, nativeStyle = native })
		end)
		expect(string.find(err, "opts.rootGui", 1, true) ~= nil).toBe(true)
		expect(string.find(err, "themeRootGui", 1, true) ~= nil).toBe(true)
	end)

	it("an unknown required capability names the set this build knows", function()
		local w = world(screen)
		local before = w.env:get("themeMetrics"):get()
		local pkg = definePackage("unknown-cap", nil, { compatibility = { capabilities = { "holograms" } } })
		local err = untouched(w, before, function()
			theme_controller.install(w.adapter, pkg, { env = w.env })
		end)
		expect(string.find(err, "holograms", 1, true) ~= nil).toBe(true)
		expect(string.find(err, "nativeStyleSheets", 1, true) ~= nil).toBe(true)
		expect(string.find(err, "themeMetrics", 1, true) ~= nil).toBe(true)
	end)

	it("a package built against another schema is refused before anything is touched", function()
		local w = world(screen)
		local before = w.env:get("themeMetrics"):get()
		local compiled = definePackage("future")
		local fromTheFuture = table.clone(compiled)
		fromTheFuture.identity = table.clone(compiled.identity)
		fromTheFuture.identity.schemaVersion = "luauui-theme/2"
		local err = untouched(w, before, function()
			theme_controller.install(w.adapter, fromTheFuture, { env = w.env })
		end)
		expect(string.find(err, "luauui-theme/2", 1, true) ~= nil).toBe(true)
		expect(string.find(err, themes.SCHEMA, 1, true) ~= nil).toBe(true)
	end)

	it("install without an environment is refused: the snapshot has nowhere to ride", function()
		local w = world(screen)
		expect(function()
			theme_controller.install(w.adapter, definePackage("no-env"), {} :: any)
		end).toThrow()
	end)
end)

-- ===== the swap transaction ================================================

describe("the swap transaction: one solve, zero rebuilds", function()
	local function installed(metrics: any?)
		local w = world(screen)
		local native, state = fakeNative()
		local pkg = definePackage("swapper", metrics)
		local controller = theme_controller.install(nativeAdapter(w.adapter, {}), pkg, {
			env = w.env,
			nativeStyle = native,
		})
		return w, controller, native, state, pkg
	end

	it("swap costs exactly one solve pass and zero factory reruns, creates or removes", function()
		local w, controller, _, state = installed()
		local solvesBefore = w.renderer.stats().solves
		local createsBefore = w.renderer.stats().creates
		local removesBefore = w.renderer.stats().removes
		local factoryBefore = w.root.counters().factoryRuns
		local mountedBefore = w.root.counters().mounted
		local derivesBefore = state.setThemes
		local titleHandle = w.adapter.node("/S/Title")
		local fieldText = w.adapter.node("/S/Field").props.text

		controller.swap("Light")

		expect(controller.current()).toBe("Light")
		expect(w.renderer.stats().solves).toBe(solvesBefore + 1)
		expect(w.renderer.stats().creates).toBe(createsBefore)
		expect(w.renderer.stats().removes).toBe(removesBefore)
		expect(w.root.counters().factoryRuns).toBe(factoryBefore)
		expect(w.root.counters().mounted).toBe(mountedBefore)
		-- the derive swap happened, exactly once, in that same commit
		expect(state.setThemes).toBe(derivesBefore + 1)
		-- mount identity: the SAME node object, with its text-entry state intact
		expect(w.adapter.node("/S/Title")).toBe(titleHandle)
		expect(w.adapter.node("/S/Field").props.text).toBe(fieldText)
	end)

	it("swapPackage moves geometry in one solve, still without a rebuild", function()
		local w, controller, native, state = installed()
		local solvesBefore = w.renderer.stats().solves
		local createsBefore = w.renderer.stats().creates
		local factoryBefore = w.root.counters().factoryRuns
		local gapBefore = w.adapter.node("/S/Field").rect.y
			- (w.adapter.node("/S/Title").rect.y + w.adapter.node("/S/Title").rect.h)
		expect(native ~= nil).toBe(true)

		controller.swapPackage(definePackage("roomy", { space = { m = 40 }, targetSizes = { minimum = 60 } }))

		local gapAfter = w.adapter.node("/S/Field").rect.y
			- (w.adapter.node("/S/Title").rect.y + w.adapter.node("/S/Title").rect.h)
		expect(gapAfter).toBe(40)
		expect(gapAfter > gapBefore).toBe(true)
		expect(w.adapter.node("/S/Go").rect.h).toBe(60)
		expect(w.renderer.stats().solves).toBe(solvesBefore + 1)
		expect(w.renderer.stats().creates).toBe(createsBefore)
		expect(w.renderer.stats().removes).toBe(0)
		expect(w.root.counters().factoryRuns).toBe(factoryBefore)
		-- the new package got its OWN sheet and the one link now points at it
		expect(state.sheets["LuauUITheme roomy"] ~= nil).toBe(true)
		expect(state.links).toBe(1)
		expect(state.lastLink.StyleSheet.Name).toBe("LuauUITheme roomy")
		expect(controller.inspect().package.id).toBe("roomy")
	end)

	it("swapPackage lands on the NEW package's default when its theme names differ", function()
		-- regression (found live, TP matrix 2026-07-25): the active theme name
		-- ("Daylight") leaked into materialize() before commit flipped it, and a
		-- package without that theme name threw "unknown theme" from the seeder.
		-- The fixture corpus shares Dark/Light everywhere, which is why the
		-- suite was blind to it.
		local _, controller = installed()
		local other = definePackage("renamed-themes", nil, {
			style = {
				defaultTheme = "Day",
				themes = {
					{ name = "Day", colors = defaultLightStyle.colors, extra = defaultLightStyle.extra },
					{ name = "Night", colors = defaultStyle.colors, extra = defaultStyle.extra },
				},
			},
		})
		controller.swapPackage(other)
		expect(controller.current()).toBe("Day")
		expect(controller.inspect().package.id).toBe("renamed-themes")
	end)

	it("swapping to an unknown theme names the declared themes and changes nothing", function()
		local w, controller = installed()
		local before = w.env:get("themeMetrics"):get()
		local ok, err = pcall(function()
			controller.swap("Sepia")
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "Dark", 1, true) ~= nil).toBe(true)
		expect(string.find(tostring(err), "Light", 1, true) ~= nil).toBe(true)
		expect(w.env:get("themeMetrics"):get()).toBe(before)
		expect(controller.current()).toBe("Dark")
	end)

	it("onChange reports every commit with its reason, and unsubscribes", function()
		local w, controller = installed()
		local seen: { string } = {}
		local off = controller.onChange(function(event: any)
			table.insert(seen, event.reason)
		end)
		controller.swap("Light")
		controller.swap("Dark")
		off()
		controller.swap("Light")
		expect(#seen).toBe(2)
		expect(seen[1]).toBe("swap")
		expect(seen[2]).toBe("swap")
		expect(w ~= nil).toBe(true)
	end)

	it("uninstall restores the pre-install snapshot and link, and drops every connection", function()
		local w, controller, _, state = installed({ space = { m = 40 } })
		local neutral = snapshot.neutral()
		expect(w.env:get("themeMetrics"):get().space.m).toBe(40)
		expect(state.live).toBe(1)
		controller.uninstall()
		expect(w.env:get("themeMetrics"):get()).toBe(neutral)
		expect(state.live).toBe(0)
		expect(state.lastLink.destroyed).toBe(true)
		-- a controller that was uninstalled refuses to keep driving the target
		expect(function()
			controller.swap("Light")
		end).toThrow()
	end)
end)

-- ===== the live authoring loop =============================================

describe("live authoring: a supported token edit re-solves, an unknown one warns once", function()
	local function authoring()
		local w = world(screen)
		local native, state = fakeNative()
		local warns: { string } = {}
		local controller = theme_controller.install(nativeAdapter(w.adapter, {}), definePackage("authoring"), {
			env = w.env,
			nativeStyle = native,
			warn = function(message: string)
				table.insert(warns, message)
			end,
		})
		return w, controller, state, warns
	end

	it("editing a metric token on the ACTIVE theme sheet re-resolves and re-solves", function()
		local w, controller, state = authoring()
		local solvesBefore = w.renderer.stats().solves
		local gapBefore = w.adapter.node("/S/Field").rect.y
			- (w.adapter.node("/S/Title").rect.y + w.adapter.node("/S/Title").rect.h)

		state.edit(
			"LuauUITheme authoring",
			"Dark",
			"Space_m",
			{ path = "space.m", attribute = "Space_m", kind = "number", value = 40 }
		)

		local gapAfter = w.adapter.node("/S/Field").rect.y
			- (w.adapter.node("/S/Title").rect.y + w.adapter.node("/S/Title").rect.h)
		expect(gapAfter).toBe(40)
		expect(gapAfter > gapBefore).toBe(true)
		expect(w.renderer.stats().solves).toBe(solvesBefore + 1)
		-- the edit shows up as a deliberate override, not a silent rewrite
		expect(controller.inspect().overrides["space.m"]).toBe(40)
		expect(controller.inspect().snapshot.space.m).toBe(40)
	end)

	it("editing a FONT token re-keys measurement so the descriptor follows the theme", function()
		local w, controller, state = authoring()
		state.edit("LuauUITheme authoring", "Dark", "Type_body_font", {
			path = "type.body.font",
			attribute = "Type_body_font",
			kind = "font",
			family = "GothamSSm",
			weight = "SemiBold",
			weightValue = 600,
			style = "Normal",
		})
		local snap = controller.inspect().snapshot
		expect(snap.type.body.font.family).toBe("GothamSSm")
		expect(snap.type.body.fontKey).toBe("GothamSSm#SemiBold#Normal")
		expect(w ~= nil).toBe(true)
	end)

	it("an unknown attribute is ignored with ONE warn naming the supported set", function()
		local w, controller, state, warns = authoring()
		local solvesBefore = w.renderer.stats().solves
		state.edit("LuauUITheme authoring", "Dark", "Spacing_medium", 40)
		state.edit("LuauUITheme authoring", "Dark", "Spacing_medium", 41)
		expect(#warns).toBe(1)
		expect(string.find(warns[1], "Spacing_medium", 1, true) ~= nil).toBe(true)
		expect(string.find(warns[1], "Space_", 1, true) ~= nil).toBe(true)
		expect(string.find(warns[1], "inspect().tokens", 1, true) ~= nil).toBe(true)
		-- ignored means ignored: no commit, no solve
		expect(w.renderer.stats().solves).toBe(solvesBefore)
		expect(controller.inspect().overrides["space.m"]).toBeNil()
	end)

	it("a Step 2 COLOUR token edit is silent — native paint owns it, not the solver", function()
		local w, _, state, warns = authoring()
		local solvesBefore = w.renderer.stats().solves
		state.edit("LuauUITheme authoring", "Dark", "Accent", { engineColor = "Accent" })
		expect(#warns).toBe(0)
		expect(w.renderer.stats().solves).toBe(solvesBefore)
	end)

	it("the watch follows the ACTIVE theme and never leaks a connection", function()
		local w, controller, state = authoring()
		expect(state.live).toBe(1)
		controller.swap("Light")
		expect(state.live).toBe(1) -- moved, not doubled
		expect(controller.inspect().connections).toBe(1)
		-- the Dark sheet no longer drives anything; the Light one does
		local solvesAfterSwap = w.renderer.stats().solves
		state.edit(
			"LuauUITheme authoring",
			"Dark",
			"Space_m",
			{ path = "space.m", attribute = "Space_m", kind = "number", value = 40 }
		)
		expect(w.renderer.stats().solves).toBe(solvesAfterSwap)
		state.edit(
			"LuauUITheme authoring",
			"Light",
			"Space_m",
			{ path = "space.m", attribute = "Space_m", kind = "number", value = 32 }
		)
		expect(w.renderer.stats().solves).toBe(solvesAfterSwap + 1)
		controller.uninstall()
		expect(state.live).toBe(0)
		expect(controller.inspect().connections).toBe(0)
	end)

	it("a swapPackage moves the watch to the new package's sheet without leaking", function()
		local _, controller, state = authoring()
		expect(state.connects).toBe(1)
		controller.swapPackage(definePackage("authoring-2"))
		expect(state.live).toBe(1)
		expect(state.connects).toBe(2)
		controller.uninstall()
		expect(state.live).toBe(0)
	end)
end)

-- ===== the sync codec and its freshness gate ===============================

describe("token_sync: typed records round-trip and drift is detectable", function()
	it("every supported typed kind survives canonicalization exactly (m6)", function()
		local records = {
			{ path = "a.n", attribute = "A_n", kind = "number", value = 16.5 },
			{ path = "a.b", attribute = "A_b", kind = "bool", value = true },
			{ path = "a.s", attribute = "A_s", kind = "string", value = "parchment" },
			{ path = "a.c", attribute = "A_c", kind = "color", hex = "1c2029" },
			{ path = "a.u", attribute = "A_u", kind = "udim", scale = 0, offset = 8 },
			{
				path = "a.f",
				attribute = "A_f",
				kind = "font",
				family = "BuilderSans",
				weight = "SemiBold",
				weightValue = 600,
				style = "Italic",
			},
		}
		local copy = {}
		for _, record in records do
			table.insert(copy, table.clone(record))
		end
		expect(#token_sync.diff(records, copy)).toBe(0)
		-- and each kind renders to something stable and distinguishing
		local seen: { [string]: boolean } = {}
		for _, record in records do
			local canonical = token_sync.canonical(record)
			expect(seen[canonical]).toBeNil()
			seen[canonical] = true
		end
	end)

	it("a package's metrics round-trip through the generated Luau, value-exact", function()
		local pkg = definePackage("roundtrip", { space = { m = 40 }, motion = { fast = 0.11 } })
		local records = token_sync.records(pkg)
		local source = "return {\n" .. token_sync.renderMetrics(records) .. "}\n"
		local loaded: any = (luau.load(source, { debugName = "roundtrip" }))()
		local reread = token_sync.recordsFromMetrics(loaded.metrics)
		expect(#token_sync.diff(records, reread)).toBe(0)
		-- the rename is the only difference between the two namespaces
		expect(loaded.metrics.typography.body.size).toBe(defaultStyle.type.body)
		expect(loaded.metrics.space.m).toBe(40)
		expect(loaded.metrics.motion.fast).toBe(0.11)
		-- emission is deterministic: same records, byte-identical source
		expect(token_sync.renderMetrics(records)).toBe(token_sync.renderMetrics(token_sync.records(pkg)))
	end)

	it("the freshness gate fails on drift and names the token that drifted", function()
		local pkg = definePackage("drifted")
		local committed = token_sync.records(pkg)
		local fromTheSheet = {}
		for _, record in committed do
			local copy = table.clone(record)
			if copy.path == "space.m" then
				copy.value = 40 -- a designer retuned the medium step in the Style Editor
			end
			table.insert(fromTheSheet, copy)
		end
		local drift = token_sync.diff(fromTheSheet, committed)
		expect(#drift).toBe(1)
		expect(drift[1].path).toBe("space.m")
		expect(drift[1].left ~= drift[1].right).toBe(true)
		-- and it is CLEAN once the committed file is regenerated from the dump
		local source = "return {\n" .. token_sync.renderMetrics(fromTheSheet) .. "}\n"
		local regenerated: any = (luau.load(source, { debugName = "regenerated" }))()
		expect(#token_sync.diff(fromTheSheet, token_sync.recordsFromMetrics(regenerated.metrics))).toBe(0)
	end)

	it("a marker-delimited package file keeps its hand-authored sections", function()
		local pkg = definePackage("marked")
		local dump = theme_controller.dumpFromPackage(pkg)
		local handAuthored = "return {\n"
			.. '\tstyle = { defaultTheme = "Dark" },\n'
			.. token_sync.BEGIN_MARKER
			.. "\n\tmetrics = { space = { m = 1 } },\n"
			.. token_sync.END_MARKER
			.. "\n}\n"
		local patched, mode = token_sync.applyToSource(handAuthored, dump)
		expect(mode).toBe("patched")
		expect(string.find(patched, 'style = { defaultTheme = "Dark" }', 1, true) ~= nil).toBe(true)
		local chunk = token_sync.extractMetricsChunk(patched)
		expect(chunk ~= nil).toBe(true)
		local loaded: any = (luau.load(chunk :: string, { debugName = "patched" }))()
		expect(#token_sync.diff(dump.tokens, token_sync.recordsFromMetrics(loaded.metrics))).toBe(0)
	end)

	it("attribute names are engine-legal and reverse uniquely to their paths", function()
		local records = token_sync.records(definePackage("attrs"))
		local byAttribute = token_sync.indexByAttribute(records)
		local count = 0
		for _, record in records do
			expect(string.match(record.attribute, "^[%a][%w_]*$") ~= nil).toBe(true)
			expect(byAttribute[record.attribute].path).toBe(record.path)
			count += 1
		end
		expect(count).toBe(#records) -- no two tokens collide on one attribute name
		expect(token_sync.attributeName("type.body.size")).toBe("Type_body_size")
		expect(token_sync.attributeName("space.m")).toBe("Space_m")
		-- namespaced contribution roles: ':' is ILLEGAL in an engine attribute
		-- name (found live: a package covering demo:gauge threw at seed time —
		-- the fake sheets never enforce engine naming, only the engine does)
		expect(token_sync.attributeName("controlSizes.demo:gauge.height")).toBe("ControlSizes_demo__gauge_height")
		local nsRecords = token_sync.records(definePackage("ns-attrs", {
			controlSizes = { ["demo:gauge"] = { height = 30, paddingX = 10, iconSize = 16 } },
		}))
		for _, record in nsRecords do
			expect(string.match(record.attribute, "^[%a][%w_]*$") ~= nil).toBe(true)
		end
	end)

	it("the client dump reads the ACTIVE theme sheet and is the shape the CLI consumes", function()
		local w = world(screen)
		local native, state = fakeNative()
		local pkg = definePackage("dumped")
		local controller = theme_controller.install(nativeAdapter(w.adapter, {}), pkg, {
			env = w.env,
			nativeStyle = native,
		})
		local dump = controller.dumpTokens()
		expect(dump.schema).toBe(token_sync.SCHEMA)
		expect(dump.package.id).toBe("dumped")
		expect(dump.theme).toBe("Dark")
		expect(dump.stamp).toBe(pkg.stamp)
		-- an untouched sheet dumps exactly the committed package: zero drift
		expect(#token_sync.diff(dump.tokens, token_sync.records(pkg))).toBe(0)
		-- ...and a designer edit shows up in the dump, which is what the gate sees
		state.edit(
			"LuauUITheme dumped",
			"Dark",
			"Space_m",
			{ path = "space.m", attribute = "Space_m", kind = "number", value = 40 }
		)
		local drift = token_sync.diff(controller.dumpTokens().tokens, token_sync.records(pkg))
		expect(#drift).toBe(1)
		expect(drift[1].path).toBe("space.m")
	end)
end)

-- ===== font preflight ======================================================

describe("font preflight: conservative until calibrated, then ONE relayout", function()
	it("every declared descriptor is preflighted, pending until it measures", function()
		local w = world(screen)
		local native = fakeNative()
		local pkg = definePackage("fonts", {
			typography = {
				body = { font = { family = "GothamSSm", weight = "SemiBold" }, size = 16, lineHeight = 1.2 },
			},
		})
		local asked: { string }? = nil
		local controller = theme_controller.install(nativeAdapter(w.adapter, {}), pkg, {
			env = w.env,
			nativeStyle = native,
			calibrate = function(keys: { string })
				asked = keys
				return { ["GothamSSm#SemiBold#Normal"] = 0.42 }
			end,
		})
		local keys: { [string]: string } = {}
		for _, entry in controller.inspect().fonts do
			keys[entry.key] = entry.state
		end
		expect(asked ~= nil).toBe(true)
		expect(keys["GothamSSm#SemiBold#Normal"]).toBe("calibrated")
		-- the descriptors the package did NOT get an answer for stay conservative
		expect(keys["BuilderSans#Regular#Normal"]).toBe("unavailable")
	end)

	it("an uncalibrated descriptor reserves MORE, never less — it can never clip", function()
		text_metrics.resetCalibration()
		text_metrics.resetMeasured()
		local known = text_metrics.measure("Volume", "BuilderSans#Regular#Normal", 16, math.huge)
		local themed = text_metrics.measure("Volume", "Parchment#Bold#Normal", 16, math.huge)
		expect(known.state).toBe("ready")
		expect(themed.state).toBe("pending")
		expect(themed.width > known.width).toBe(true)
		text_metrics.resetCalibration()
	end)

	it("a successful calibration drives EXACTLY ONE bounded relayout", function()
		-- re-baselined in the review-fix round (A8). Measurement changes under the
		-- solver when a descriptor calibrates, and nothing else would ever ask it
		-- to look again — so the surface must re-solve exactly once, here. The old
		-- claim ("preflight drives no solve") described a preview that stayed laid
		-- out to the conservative estimate forever.
		local w = world(screen)
		local native = fakeNative()
		local solvesAtInstall: number? = nil
		local reasons: { string } = {}
		local controller = theme_controller.install(nativeAdapter(w.adapter, {}), definePackage("one-relayout"), {
			env = w.env,
			nativeStyle = native,
			calibrate = function(keys: { string })
				solvesAtInstall = w.renderer.stats().solves
				local out: { [string]: number } = {}
				for _, key in keys do
					out[key] = 0.45
				end
				return out
			end,
		})
		expect(w.renderer.stats().solves).toBe((solvesAtInstall :: number) + 1)
		expect(controller.inspect().fonts[1].state).toBe("calibrated")
		-- ...and it is ONE: a second preflight finds every descriptor calibrated
		local after = w.renderer.stats().solves
		controller.onChange(function(event: any)
			table.insert(reasons, event.reason)
		end)
		controller.swap("Light")
		expect(w.renderer.stats().solves).toBe(after + 1) -- the swap only
		expect(#reasons).toBe(1)
		expect(reasons[1]).toBe("swap")
	end)

	it("the solver measures with the role's DESCRIPTOR, so a theme weight is its own cache entry", function()
		local w = world(screen)
		text_metrics.resetMeasured()
		local native = fakeNative()
		theme_controller.install(
			nativeAdapter(w.adapter, {}),
			definePackage("weights", {
				typography = {
					title = { font = { family = "BuilderSans", weight = "Bold" }, size = 24, lineHeight = 1.2 },
				},
			}),
			{ env = w.env, nativeStyle = native, preflightFonts = false }
		)
		-- the premeasure batch carries the DESCRIPTOR, not the bare family, so the
		-- client adapter measures the face the theme declared (ADR-0019 §6)
		local requested: { [string]: boolean } = {}
		w.adapter.deliverTextWidths(function(_word: string, _size: number, font: string): number?
			requested[font] = true
			return nil
		end)
		expect(requested["BuilderSans#Bold#Normal"]).toBe(true)
		expect(requested["BuilderSans"]).toBeNil()
		text_metrics.resetMeasured()
	end)
end)

-- ===========================================================================
-- REVIEW-FIX ROUND. Every case below was reproduced against the shipped
-- controller before the fix landed; each one is a way a live theme could go
-- wrong with a green suite.
-- ===========================================================================

local function fakeAdapterSpy()
	local calls: { any } = {}
	local adapter: any = fake_target.new()
	nativeAdapter(adapter, { name = "Root" })
	-- boxed: `table.insert` cannot record a nil, and the nil push (uninstall) is
	-- exactly the call this spy exists to see
	adapter.setThemePackage = function(pkg: any?): boolean
		table.insert(calls, { package = pkg })
		return false
	end
	return adapter, calls
end

describe("the decoration half rides the SAME transaction (A1)", function()
	it("install and each swapPackage push exactly one setThemePackage with the active package", function()
		local w = world(screen)
		local native = fakeNative()
		local adapter, calls = fakeAdapterSpy()
		w.adapter = adapter
		local first = definePackage("deco-a")
		local controller = theme_controller.install(adapter, first, { env = w.env, nativeStyle = native })
		expect(#calls).toBe(1)
		expect(calls[1].package).toBe(first)

		local second = definePackage("deco-b")
		controller.swapPackage(second)
		expect(#calls).toBe(2)
		expect(calls[2].package).toBe(second)

		controller.uninstall()
		expect(#calls).toBe(3)
		expect(calls[3].package).toBeNil()
	end)
end)

describe("sheet overrides belong to the theme being resolved TO (A2)", function()
	it("swapping to Light does not apply Dark's authored edits", function()
		local w = world(screen)
		local native, state = fakeNative()
		local controller = theme_controller.install(
			nativeAdapter(w.adapter, {}),
			definePackage("per-theme", { space = { m = 16 } }),
			{ env = w.env, nativeStyle = native }
		)
		-- a designer retunes the medium step on DARK only
		state.edit(
			"LuauUITheme per-theme",
			"Dark",
			"Space_m",
			{ path = "space.m", attribute = "Space_m", kind = "number", value = 40 }
		)
		expect(controller.inspect().snapshot.space.m).toBe(40)
		expect(controller.inspect().overrides["space.m"]).toBe(40)

		controller.swap("Light")

		-- Light's own sheet was never touched, so Light resolves the PACKAGE value
		expect(controller.current()).toBe("Light")
		expect(controller.inspect().snapshot.space.m).toBe(16)
		expect(next(controller.inspect().overrides)).toBeNil()
		expect(w.env:get("themeMetrics"):get().space.m).toBe(16)

		-- ...and going back to Dark still finds the designer's edit
		controller.swap("Dark")
		expect(controller.inspect().snapshot.space.m).toBe(40)
	end)
end)

describe("swapPackage is all-or-nothing (A3)", function()
	it("an unknown theme on the new package leaves a fully working controller", function()
		local w = world(screen)
		local native, state = fakeNative()
		local controller = theme_controller.install(nativeAdapter(w.adapter, {}), definePackage("stay"), {
			env = w.env,
			nativeStyle = native,
		})
		local before = w.env:get("themeMetrics"):get()

		local ok, err = pcall(function()
			controller.swapPackage(definePackage("other"), "NoSuchTheme")
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "NoSuchTheme", 1, true) ~= nil).toBe(true)
		expect(string.find(tostring(err), "unchanged", 1, true) ~= nil).toBe(true)

		-- identity, environment, watcher and inspect() all survive
		expect(controller.inspect().package.id).toBe("stay")
		expect(controller.current()).toBe("Dark")
		expect(controller.inspect().connections).toBe(1)
		expect(state.live).toBe(1)
		expect(w.env:get("themeMetrics"):get()).toBe(before)
		-- and it still WORKS afterwards
		controller.swap("Light")
		expect(controller.current()).toBe("Light")
	end)
end)

describe("one live controller per environment (A4)", function()
	it("a second install on the same environment is refused, naming the conflict", function()
		local w = world(screen)
		local nativeA = fakeNative()
		local nativeB, stateB = fakeNative()
		local first = theme_controller.install(nativeAdapter(w.adapter, {}), definePackage("incumbent"), {
			env = w.env,
			nativeStyle = nativeA,
		})
		local live = w.env:get("themeMetrics"):get()

		local ok, err = pcall(function()
			theme_controller.install(nativeAdapter(fake_target.new(), {}), definePackage("intruder"), {
				env = w.env,
				nativeStyle = nativeB,
			})
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "incumbent", 1, true) ~= nil).toBe(true)
		expect(string.find(tostring(err), "themeMetrics", 1, true) ~= nil).toBe(true)
		-- nothing was touched: no sheet materialized, environment intact
		expect(stateB.ensures).toBe(0)
		expect(w.env:get("themeMetrics"):get()).toBe(live)
		expect(first.inspect().package.id).toBe("incumbent")
	end)

	it("a legitimate uninstall frees the environment for the next controller", function()
		local w = world(screen)
		local nativeA = fakeNative()
		local nativeB = fakeNative()
		local pre = w.env:get("themeMetrics"):get()
		local first = theme_controller.install(nativeAdapter(w.adapter, {}), definePackage("first-owner"), {
			env = w.env,
			nativeStyle = nativeA,
		})
		first.uninstall()
		expect(w.env:get("themeMetrics"):get()).toBe(pre)
		local second = theme_controller.install(nativeAdapter(fake_target.new(), {}), definePackage("second-owner"), {
			env = w.env,
			nativeStyle = nativeB,
		})
		expect(second.inspect().package.id).toBe("second-owner")
		second.uninstall()
	end)

	it("uninstall does not clobber a themeMetrics value it no longer owns", function()
		local w = world(screen)
		local native = fakeNative()
		local controller = theme_controller.install(nativeAdapter(w.adapter, {}), definePackage("polite"), {
			env = w.env,
			nativeStyle = native,
		})
		-- something else takes over the fact (another system, a test harness)
		local foreign = snapshot.neutral()
		w.env:set("themeMetrics", foreign)
		controller.uninstall()
		expect(w.env:get("themeMetrics"):get()).toBe(foreign)
	end)
end)

describe("change listeners are observers, never drivers (A5)", function()
	local function installed()
		local w = world(screen)
		local native = fakeNative()
		local warns: { string } = {}
		local controller = theme_controller.install(nativeAdapter(w.adapter, {}), definePackage("listeners"), {
			env = w.env,
			nativeStyle = native,
			warn = function(message: string)
				table.insert(warns, message)
			end,
		})
		return w, controller, warns
	end

	it("a listener that unsubscribes itself does not skip the next listener", function()
		local _, controller = installed()
		local seen: { string } = {}
		local off: (() -> ())? = nil
		off = controller.onChange(function()
			table.insert(seen, "first")
			local unsubscribe: any = off
			unsubscribe()
		end)
		controller.onChange(function()
			table.insert(seen, "second")
		end)
		controller.onChange(function()
			table.insert(seen, "third")
		end)
		controller.swap("Light")
		expect(#seen).toBe(3)
		expect(seen[2]).toBe("second")
		expect(seen[3]).toBe("third")
	end)

	it("a throwing listener neither aborts the swap nor robs its siblings", function()
		local w, controller, warns = installed()
		local reached = false
		controller.onChange(function()
			error("listener exploded")
		end)
		controller.onChange(function()
			reached = true
		end)
		controller.swap("Light")
		expect(reached).toBe(true)
		expect(controller.current()).toBe("Light")
		expect(w.env:get("themeMetrics"):get()).toBe(controller.inspect().snapshot)
		expect(#warns).toBe(1)
		expect(string.find(warns[1], "listener", 1, true) ~= nil).toBe(true)
		-- warned ONCE per listener, however many commits it ruins
		controller.swap("Dark")
		expect(#warns).toBe(1)
	end)

	it("a listener that re-enters swap hits a named error instead of a stack overflow", function()
		local _, controller, warns = installed()
		local depth = 0
		controller.onChange(function()
			depth += 1
			controller.swap("Light")
		end)
		controller.swap("Light")
		-- the outer swap completed; the re-entrant one was refused by name
		expect(controller.current()).toBe("Light")
		expect(depth).toBe(1)
		expect(#warns).toBe(1)
		expect(string.find(warns[1], "theme swap feedback loop", 1, true) ~= nil).toBe(true)
	end)
end)

describe("install validates before it mutates (A6)", function()
	it("an opts.theme the package does not declare materializes nothing", function()
		local w = world(screen)
		local native, state = fakeNative()
		local before = w.env:get("themeMetrics"):get()
		local ok, err = pcall(function()
			theme_controller.install(nativeAdapter(w.adapter, {}), definePackage("typo"), {
				env = w.env,
				nativeStyle = native,
				theme = "Darkk",
			})
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "Darkk", 1, true) ~= nil).toBe(true)
		expect(string.find(tostring(err), "Dark, Light", 1, true) ~= nil).toBe(true)
		expect(state.ensures).toBe(0)
		expect(state.links).toBe(0)
		expect(w.env:get("themeMetrics"):get()).toBe(before)
	end)

	it("a throwing calibrator leaves a live, working controller", function()
		local w = world(screen)
		local native, state = fakeNative()
		local warns: { string } = {}
		local controller = theme_controller.install(nativeAdapter(w.adapter, {}), definePackage("bad-calibrate"), {
			env = w.env,
			nativeStyle = native,
			warn = function(message: string)
				table.insert(warns, message)
			end,
			calibrate = function()
				error("no text service here")
			end,
		})
		expect(controller.inspect().package.id).toBe("bad-calibrate")
		expect(state.live).toBe(1)
		expect(controller.inspect().connections).toBe(1)
		expect(#warns).toBe(1)
		expect(string.find(warns[1], "calibration failed", 1, true) ~= nil).toBe(true)
		controller.swap("Light")
		expect(controller.current()).toBe("Light")
		controller.uninstall()
		expect(state.live).toBe(0)
	end)
end)

describe("a disposed controller says so (A7)", function()
	it("inspect() reports disposal and dumpTokens/onChange refuse", function()
		local w = world(screen)
		local native = fakeNative()
		local controller = theme_controller.install(nativeAdapter(w.adapter, {}), definePackage("gone"), {
			env = w.env,
			nativeStyle = native,
		})
		controller.uninstall()
		local info = controller.inspect()
		expect(info.disposed).toBe(true)
		expect(info.sheet.present).toBe(false)
		expect(info.link.present).toBe(false)
		expect(info.connections).toBe(0)
		expect(function()
			controller.dumpTokens()
		end).toThrow()
		expect(function()
			controller.onChange(function() end)
		end).toThrow()
		-- calling it twice is still a no-op, not an error
		controller.uninstall()
	end)
end)

describe("font preflight has a lifecycle (A8)", function()
	local function yieldingWorld(id: string)
		local w = world(screen)
		local native, state = fakeNative()
		local resume: (() -> ())? = nil
		local runs = 0
		local controller = theme_controller.install(nativeAdapter(w.adapter, {}), definePackage(id), {
			env = w.env,
			nativeStyle = native,
			calibrate = function(keys: { string })
				runs += 1
				local answered: { [string]: number } = {}
				for _, key in keys do
					answered[key] = 0.5
				end
				local pending = answered
				resume = function()
					resume = nil
					return pending
				end
				-- the injected calibrator answers immediately here; the DEFERRED
				-- shape is exercised by the swapPackage double-spawn case below
				return answered
			end,
		})
		return w, controller, state, function()
			return runs
		end
	end

	it("two rapid swapPackage calls launch ONE flight per descriptor", function()
		local w = world(screen)
		local native = fakeNative()
		local asked: { { string } } = {}
		local controller = theme_controller.install(nativeAdapter(w.adapter, {}), definePackage("flights"), {
			env = w.env,
			nativeStyle = native,
			calibrate = function(keys: { string })
				table.insert(asked, keys)
				local out: { [string]: number } = {}
				for _, key in keys do
					out[key] = 0.5
				end
				return out
			end,
		})
		expect(#asked).toBe(1)
		-- the same descriptors are already calibrated, so neither swap re-asks
		controller.swapPackage(definePackage("flights-2"))
		controller.swapPackage(definePackage("flights-3"))
		expect(#asked).toBe(1)
		-- ...but a package with a NEW descriptor is asked exactly once
		controller.swapPackage(definePackage("flights-4", {
			typography = { body = { font = { family = "GothamSSm", weight = "Bold" }, size = 16, lineHeight = 1.2 } },
		}))
		expect(#asked).toBe(2)
		expect(#asked[2]).toBe(1)
		expect(asked[2][1]).toBe("GothamSSm#Bold#Normal")
	end)

	it("a descriptor that came back unavailable is retried on the next swapPackage", function()
		local w = world(screen)
		local native = fakeNative()
		local rounds = 0
		local controller = theme_controller.install(nativeAdapter(w.adapter, {}), definePackage("retry"), {
			env = w.env,
			nativeStyle = native,
			calibrate = function(keys: { string })
				rounds += 1
				if rounds == 1 then
					return {} -- the text service was not ready yet
				end
				local out: { [string]: number } = {}
				for _, key in keys do
					out[key] = 0.5
				end
				return out
			end,
		})
		expect(controller.inspect().fonts[1].state).toBe("unavailable")
		controller.swapPackage(definePackage("retry-2"))
		expect(rounds).toBe(2)
		expect(controller.inspect().fonts[1].state).toBe("calibrated")
	end)

	it("uninstall mid-flight writes nothing through the dead controller", function()
		local w = world(screen)
		local native = fakeNative()
		local controller: any = nil
		local disposeNext = false
		local solvesAtDispose: number? = nil
		local pre = w.env:get("themeMetrics"):get()
		controller = theme_controller.install(nativeAdapter(w.adapter, {}), definePackage("mid-flight"), {
			env = w.env,
			nativeStyle = native,
			calibrate = function(keys: { string })
				if disposeNext then
					-- the controller dies while the calibrator is away; every
					-- resumption point downstream must notice
					controller.uninstall()
					solvesAtDispose = w.renderer.stats().solves
				end
				local out: { [string]: number } = {}
				for _, key in keys do
					out[key] = 0.5
				end
				return out
			end,
		})
		disposeNext = true
		-- a package with a font this controller has never measured launches a
		-- fresh flight, and that flight is the one that dies
		controller.swapPackage(definePackage("mid-flight-2", {
			typography = { body = { font = { family = "GothamSSm", weight = "Bold" }, size = 16, lineHeight = 1.2 } },
		}))

		expect(solvesAtDispose ~= nil).toBe(true)
		-- no post-dispose commit: the environment kept the restored snapshot and
		-- the surface did not re-solve behind the uninstall
		expect(w.env:get("themeMetrics"):get()).toBe(pre)
		expect(w.renderer.stats().solves).toBe(solvesAtDispose :: number)
		expect(controller.inspect().disposed).toBe(true)
	end)
end)

describe("metric rule pushes happen on a token EDIT and nowhere else (A9)", function()
	local function withRuleSpy(id: string, opts: any?)
		local w = world(screen)
		local native, state = fakeNative()
		local pushes: { any } = {}
		local missing: { string } = {}
		local warns: { string } = {}
		local baseEnsure = native.ensure
		native.ensure = function(model: any, ensureOpts: any): any
			local handle = baseEnsure(model, ensureOpts)
			handle.setRuleProperty = function(ruleName: string, prop: string, value: any): boolean
				for _, gone in missing do
					if gone == ruleName then
						return false
					end
				end
				table.insert(pushes, { rule = ruleName, prop = prop, value = value })
				return true
			end
			return handle
		end
		local o: any = {
			env = w.env,
			nativeStyle = native,
			warn = function(message: string)
				table.insert(warns, message)
			end,
		}
		for key, value in opts or {} do
			o[key] = value
		end
		local controller = theme_controller.install(nativeAdapter(w.adapter, {}), definePackage(id), o)
		return w, controller, state, pushes, missing, warns
	end

	it("a designer's rule edit survives install and every ordinary commit", function()
		local _, controller, _, pushes = withRuleSpy("rule-edits")
		-- install pushed NOTHING: re-pushing the generated literal on every commit
		-- silently reverted whatever the designer had typed into that rule
		expect(#pushes).toBe(0)
		controller.swap("Light")
		expect(#pushes).toBe(0)
		controller.swapPackage(definePackage("rule-edits-2"))
		expect(#pushes).toBe(0)
	end)

	it("a metric token edit DOES push, so paint follows the geometry", function()
		local _, controller, state, pushes = withRuleSpy("rule-metric")
		state.edit(
			"LuauUITheme rule-metric",
			"Dark",
			"Radii_control",
			{ path = "radii.control", attribute = "Radii_control", kind = "number", value = 20 }
		)
		expect(#pushes > 0).toBe(true)
		local corner: any = nil
		for _, push in pushes do
			if push.rule == "Control — corner" then
				corner = push
			end
		end
		expect(corner ~= nil).toBe(true)
		expect(corner.prop).toBe("CornerRadius")
		expect(corner.value.offset).toBe(20)
		expect(controller.inspect().snapshot.radii.control).toBe(20)
	end)

	it("a FONT token edit pushes FontFace on every recorded rule and preflights the new face", function()
		local asked: { { string } } = {}
		local _, controller, state, pushes = withRuleSpy("rule-font", {
			calibrate = function(keys: { string })
				table.insert(asked, keys)
				return {}
			end,
		})
		local before = #asked
		state.edit("LuauUITheme rule-font", "Dark", "Type_control_font", {
			path = "type.control.font",
			attribute = "Type_control_font",
			kind = "font",
			family = "GothamSSm",
			weight = "SemiBold",
			weightValue = 600,
			style = "Normal",
		})
		local fontRules: { [string]: any } = {}
		for _, push in pushes do
			if push.prop == "FontFace" then
				fontRules[push.rule] = push.value
			end
		end
		expect(fontRules["Button text default"] ~= nil).toBe(true)
		expect(fontRules["Field text default"] ~= nil).toBe(true)
		expect(fontRules["Button text default"].family).toBe("GothamSSm")
		expect(fontRules["Button text default"].weight).toBe("SemiBold")
		-- the body role was NOT edited, so its rule keeps the package face
		expect(fontRules["Text default"].family).toBe("BuilderSans")
		-- ...and the new descriptor was preflighted rather than left conservative
		expect(#asked > before).toBe(true)
		expect(controller.inspect().snapshot.type.control.fontKey).toBe("GothamSSm#SemiBold#Normal")
	end)

	it("a rule the designer renamed away warns ONCE instead of failing silently", function()
		local _, _, state, _, missing, warns = withRuleSpy("rule-missing")
		table.insert(missing, "Control — corner")
		for _, value in { 20, 21 } do
			state.edit(
				"LuauUITheme rule-missing",
				"Dark",
				"Radii_control",
				{ path = "radii.control", attribute = "Radii_control", kind = "number", value = value }
			)
		end
		expect(#warns).toBe(1)
		expect(string.find(warns[1], "Control — corner", 1, true) ~= nil).toBe(true)
		expect(string.find(warns[1], "radii.control", 1, true) ~= nil).toBe(true)
	end)
end)

describe("a sheet edit is sanitized before it reaches the resolver (A10)", function()
	it("a negative inset and a zero type size are DROPPED, naming attribute and reason", function()
		local w = world(screen)
		local native, state = fakeNative()
		local warns: { string } = {}
		local controller = theme_controller.install(nativeAdapter(w.adapter, {}), definePackage("sanitize"), {
			env = w.env,
			nativeStyle = native,
			warn = function(message: string)
				table.insert(warns, message)
			end,
		})
		local packageInsetTop = controller.inspect().snapshot.insets.panel.top
		local packageBodySize = controller.inspect().snapshot.type.body.size

		state.edit(
			"LuauUITheme sanitize",
			"Dark",
			"Insets_panel_top",
			{ path = "insets.panel.top", attribute = "Insets_panel_top", kind = "number", value = -5 }
		)
		state.edit(
			"LuauUITheme sanitize",
			"Dark",
			"Type_body_size",
			{ path = "type.body.size", attribute = "Type_body_size", kind = "number", value = 0 }
		)

		local info = controller.inspect()
		expect(info.snapshot.insets.panel.top).toBe(packageInsetTop)
		expect(info.snapshot.type.body.size).toBe(packageBodySize)
		expect(info.overrides["insets.panel.top"]).toBeNil()
		expect(info.overrides["type.body.size"]).toBeNil()
		expect(#warns).toBe(2)
		expect(string.find(warns[1], "Insets_panel_top", 1, true) ~= nil).toBe(true)
		expect(string.find(warns[1], "negative", 1, true) ~= nil).toBe(true)
		expect(string.find(warns[2], "Type_body_size", 1, true) ~= nil).toBe(true)
	end)

	it("a NaN is refused and a good edit beside it still applies", function()
		local w = world(screen)
		local native, state = fakeNative()
		local warns: { string } = {}
		local controller = theme_controller.install(nativeAdapter(w.adapter, {}), definePackage("sanitize-2"), {
			env = w.env,
			nativeStyle = native,
			warn = function(message: string)
				table.insert(warns, message)
			end,
		})
		state.edit(
			"LuauUITheme sanitize-2",
			"Dark",
			"Space_l",
			{ path = "space.l", attribute = "Space_l", kind = "number", value = 0 / 0 }
		)
		state.edit(
			"LuauUITheme sanitize-2",
			"Dark",
			"Space_m",
			{ path = "space.m", attribute = "Space_m", kind = "number", value = 40 }
		)
		expect(controller.inspect().overrides["space.l"]).toBeNil()
		expect(controller.inspect().overrides["space.m"]).toBe(40)
		expect(string.find(warns[1], "NaN", 1, true) ~= nil).toBe(true)
		expect(w.env:get("themeMetrics"):get().space.m).toBe(40)
	end)
end)

describe("native transitions are provided only when opted into (A11)", function()
	local function transitionPackage(id: string): any
		return definePackage(id, nil, { compatibility = { capabilities = { "styleTransitions" } } })
	end

	it("a package requiring styleTransitions fails install without opts.transitions", function()
		local w = world(screen)
		local native = fakeNative()
		local before = w.env:get("themeMetrics"):get()
		local ok, err = pcall(function()
			theme_controller.install(nativeAdapter(w.adapter, {}), transitionPackage("needs-transitions"), {
				env = w.env,
				nativeStyle = native,
			})
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "styleTransitions", 1, true) ~= nil).toBe(true)
		expect(w.env:get("themeMetrics"):get()).toBe(before)
	end)

	it("...and installs when the target opts in", function()
		local w = world(screen)
		local native = fakeNative()
		local controller = theme_controller.install(nativeAdapter(w.adapter, {}), transitionPackage("opted-in"), {
			env = w.env,
			nativeStyle = native,
			transitions = true,
		})
		expect(controller.inspect().capabilities.provided.styleTransitions).toBe(true)
	end)
end)

describe("the theme sheet follows EVERY root of the target (B12)", function()
	local function relinkWorld()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local root = mountLib.mount(core, screen())
		local adapter = fake_target.new({ trackThemeRoots = true })
		nativeAdapter(adapter, { name = "Root" })
		local controller = renderer.attach(core, root, env, adapter, {})
		controller.initialRender()
		return { env = env, adapter = adapter, renderer = controller }
	end

	it("roots before install, after install and after a swap all point at the package sheet", function()
		local w = relinkWorld()
		local native = fakeNative()
		local legacy = w.adapter.legacyThemeSheet()
		-- the mounted screen's root exists BEFORE the install
		expect(w.adapter.rootThemeSheets()["S"]).toBe(legacy)

		local theme = theme_controller.install(w.adapter, definePackage("relink-a"), {
			env = w.env,
			nativeStyle = native,
		})
		expect(w.adapter.rootThemeSheets()["S"].Name).toBe("LuauUITheme relink-a")
		expect(theme.inspect().link.present).toBe(true)
		expect(theme.inspect().link.whole).toBe(true)

		-- a modal opened AFTER the install inherits the themed sheet
		w.adapter.createRoot("Modal")
		expect(w.adapter.rootThemeSheets()["Modal"].Name).toBe("LuauUITheme relink-a")

		theme.swapPackage(definePackage("relink-b"))
		local after = w.adapter.rootThemeSheets()
		expect(after["S"].Name).toBe("LuauUITheme relink-b")
		expect(after["Modal"].Name).toBe("LuauUITheme relink-b")

		theme.uninstall()
		local restored = w.adapter.rootThemeSheets()
		expect(restored["S"]).toBe(legacy)
		expect(restored["Modal"]).toBe(legacy)
	end)
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- COMPOSITION AT RUNG 2 (ADR-0020 R8: "the view modifier wins on that node").
-- A theme package swap is the case that would break it: the swap re-solves the
-- whole surface and re-applies paint, so a per-view gradient could plausibly be
-- clobbered (the view loses on the next swap — the exact failure the untagged
-- decoration rule exists to prevent) or DUPLICATED (a second UIGradient stacked
-- on the node, which reads as a darker wash and is invisible in code review).
-- Neither is allowed, and the fake target mirrors the real adapter's one-child
-- contract so both are provable here.
-- ─────────────────────────────────────────────────────────────────────────────
describe("rung 2: a per-view gradient survives a theme-package swap", function()
	local function gradientScreen()
		return UI.Screen({
			id = "S",
			padding = 0,
			gap = "m",
			children = {
				UI.gradient(UI.Box({ id = "Card", surface = "raised" }), {
					colors = { "surfaceStrong", "accent" },
					rotation = 90,
					transparency = { 0.1, 0.3 },
				}),
				UI.Box({ id = "Plain", surface = "raised" }),
			},
		})
	end

	it("the child is materialized once, keeps the VIEW's values, and is not duplicated by a swap", function()
		local w = world(gradientScreen)
		local native = fakeNative()
		local a = definePackage("grad-a", { space = { m = 16 } })
		local b = definePackage("grad-b", { space = { m = 40 } })
		local controller = theme_controller.install(nativeAdapter(w.adapter, { name = "Root" }), a, {
			env = w.env,
			nativeStyle = native,
		})

		local card = w.adapter.node("/S/Card")
		local before = card.gradientInstance
		expect(before ~= nil).toBe(true)
		expect(before.className).toBe("UIGradient")
		expect(before.creations).toBe(1)
		expect(before.rotation).toBe(90)
		expect(#before.colorStops).toBe(2)
		expect(before.alphaStops[2].v).toBe(0.3)
		-- the sibling with no modifier has NO child at all: a per-view wash costs
		-- exactly the node that asked for one
		expect(w.adapter.node("/S/Plain").gradientInstance).toBeNil()

		-- the SECOND child is what a gap change moves, so it is the honest
		-- witness that this swap re-solved geometry rather than doing nothing
		local movedBefore = w.adapter.node("/S/Plain").rect.y
		controller.swapPackage(b)
		w.renderer.refresh()

		-- the swap DID move geometry (so this is a real swap, not a no-op)…
		expect(w.adapter.node("/S/Plain").rect.y ~= movedBefore).toBe(true)
		-- …and the SAME node object still carries the SAME gradient child
		expect(w.adapter.node("/S/Card")).toBe(card)
		local after = w.adapter.node("/S/Card").gradientInstance
		expect(after).toBe(before)
		expect(after.creations).toBe(1) -- reused, never a second ramp stacked on the node
		expect(after.rotation).toBe(90)
		expect(after.colorStops[2].r).toBe(before.colorStops[2].r)
		expect(w.adapter.node("/S/Plain").gradientInstance).toBeNil()
		controller.uninstall()
	end)

	it("a package's own chromeGradient still paints everywhere ELSE — the view wins on ONE node", function()
		-- the two authorities are different mechanisms on purpose: the theme's
		-- gradients compile to phantom ::UIGradient RULES (zero instances), the
		-- view's to one real child. So "the view wins here" costs the theme
		-- nothing anywhere else, and the package still emits its rule.
		local w = world(gradientScreen)
		local native = fakeNative()
		local themedExtra = table.clone(defaultStyle.extra)
		themedExtra.chromeGradient = {
			panel = {
				rotation = 90,
				stops = { { t = 0, r = 0.2, g = 0.2, b = 0.3 }, { t = 1, r = 0.1, g = 0.1, b = 0.2 } },
			},
		}
		local themed = definePackage("grad-themed", nil, {
			style = {
				defaultTheme = "Dark",
				themes = {
					{ name = "Dark", colors = defaultStyle.colors, extra = themedExtra },
					{ name = "Light", colors = defaultLightStyle.colors, extra = defaultLightStyle.extra },
				},
			},
		})
		local controller = theme_controller.install(nativeAdapter(w.adapter, { name = "Root" }), themed, {
			env = w.env,
			nativeStyle = native,
		})
		local card = w.adapter.node("/S/Card")
		expect(card.gradientInstance ~= nil).toBe(true)
		expect(card.gradientInstance.creations).toBe(1)
		-- the package compiled its own gradient as a RULE, not as a child
		local model = require("../src/tokens/sheet_model").buildPackage(themed)
		local found = false
		for _, rule in model.rules do
			if string.find(rule.selector, "::UIGradient", 1, true) ~= nil then
				found = true
			end
		end
		expect(found).toBe(true)
		controller.uninstall()
	end)
end)

-- ===== A12: the install-policy preload seam is DRIVEN, not merely published ==
--
-- platform verifier F2. ADR-0020 R2 promises "PreloadAsync belt-and-braces by
-- default". The package half was real and specced — `chrome_slots.assetsToPreload`
-- returns the install-policy list — but nothing in the shipped controller ever
-- asked for it, so the actual default was NO preload and RS-A17's preload numbers
-- were list lengths. The framework is engine-free, so the transport is an opts
-- seam: with a provider the list is requested, without one the step is lazily
-- skipped and nothing is claimed.

describe("the install-policy preload list is requested through the provider (A12)", function()
	local function skinned(id: string, ids: { [string]: string }): any
		local assets: any = {}
		for name, content in ids do
			assets[name] = {
				content = content,
				sliceCenter = { x0 = 8, y0 = 8, x1 = 24, y1 = 24 },
				preload = "install",
				fallback = "native",
			}
		end
		-- one asset deliberately LAZY: it must never be requested at install
		assets.later = { content = "rbxassetid://999", preload = "lazy", fallback = "native" }
		return definePackage(id, nil, {
			assets = assets,
			icons = { increment = "plate", decrement = "plateAgain" },
			chrome = {
				panel = {
					kind = "nineSlice",
					asset = "plate",
					contentInsets = { top = 10, right = 10, bottom = 10, left = 10 },
					fallback = "native",
				},
			},
		})
	end

	local function fakeProvider()
		local state: any = { keys = {}, live = 0 }
		local api: any = {}
		function api.acquire(scope: any, key: string)
			table.insert(state.keys, key)
			state.live += 1
			local released = false
			local handle: any = { key = key }
			function handle.release()
				if released then
					return
				end
				released = true
				state.live -= 1
			end
			scope:own(handle.release)
			return handle
		end
		return api, state
	end

	it("requests each distinct content id exactly once, and never a lazy one", function()
		-- two asset NAMES sharing one upload: the transport must be asked once
		local pkg = skinned("preload-a", { plate = "rbxassetid://700", plateAgain = "rbxassetid://700" })
		local provider, state = fakeProvider()
		local env = environment.new(customFactory.new())
		local controller = theme_controller.install(fake_target.new(), pkg, {
			env = env,
			forceFallback = true,
			resources = provider,
		})
		expect(#state.keys).toBe(1)
		expect(state.keys[1]).toBe("rbxassetid://700")
		expect(controller.inspect().preload.driven).toBe(true)
		expect(controller.inspect().preload.requested).toBe(1)
		controller.uninstall()
		-- the handles are released with the controller, so the provider's cache
		-- can evict a theme nobody is running any more
		expect(state.live).toBe(0)
	end)

	it("a swap releases the old package's requests and takes the new one's", function()
		local a = skinned("preload-b", { plate = "rbxassetid://701", plateAgain = "rbxassetid://702" })
		local b = skinned("preload-c", { plate = "rbxassetid://703", plateAgain = "rbxassetid://704" })
		local provider, state = fakeProvider()
		local env = environment.new(customFactory.new())
		local controller = theme_controller.install(fake_target.new(), a, {
			env = env,
			forceFallback = true,
			resources = provider,
		})
		expect(state.live).toBe(2)
		controller.swapPackage(b)
		expect(state.live).toBe(2) -- two released, two taken
		expect(state.keys[3]).toBe("rbxassetid://703")
		expect(controller.inspect().preload.requested).toBe(2)
		controller.uninstall()
		expect(state.live).toBe(0)
	end)

	it("with NO provider the step is lazily skipped and claims nothing", function()
		local pkg = skinned("preload-d", { plate = "rbxassetid://705", plateAgain = "rbxassetid://706" })
		local env = environment.new(customFactory.new())
		local controller = theme_controller.install(fake_target.new(), pkg, { env = env, forceFallback = true })
		local preload = controller.inspect().preload
		expect(preload.driven).toBe(false)
		expect(preload.requested).toBe(0)
		controller.uninstall()
	end)
end)
