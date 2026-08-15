--!strict
-- P1.3/P1.4 renderer tests: end-to-end headless slice — blueprint → mount →
-- solve → adapter — minimal writes on paint updates, re-arrange on viewport
-- change, structural add/remove through When, env per-key isolation, token
-- compilation, authority enforcement.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local customFactory = require("../src/core/custom")
local UI = require("../src/blueprint")
local mountLib = require("../src/mount")
local environment = require("../src/env/environment")
local renderer = require("../src/render/renderer")
local authority = require("../src/render/authority")
local tokensLib = require("../src/tokens/tokens")
local fake_target = require("../tests/lib/fake_target")
local adapter_source = require("./lib/adapter_source")
-- the renderer as ONE text: two files since the 200k `Source` write-cap split
-- (tests/lib/renderer_source names them and says why)
local renderer_source = require("./lib/renderer_source")

local function makeSlice()
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = 390, h = 844 })
	env:set("coreSafeInsets", { top = 59, bottom = 34, left = 0, right = 0 })
	local music = core:signal(false)
	local showAdvanced = core:signal(false)
	local bp = UI.Screen({
		id = "Settings",
		children = {
			UI.Text({ id = "Title", text = "Settings", textSize = 24 }),
			UI.Toggle({ id = "Music", label = "Music", value = music }),
			UI.When({
				id = "Advanced",
				condition = showAdvanced,
				thenView = function()
					return UI.Text({ id = "Hint", text = "advanced options", textSize = 14 })
				end,
			}),
			UI.Button({ id = "Save", label = "Save" }),
		},
	})
	local root = mountLib.mount(core, bp)
	local adapter = fake_target.new()
	local controller = renderer.attach(core, root, env, adapter, { rootPolicy = "coreSafeContent" })
	controller.initialRender()
	adapter.takeOps()
	return core, env, root, adapter, controller, music, showAdvanced
end

describe("renderer: minimal updates", function()
	it("initial render creates every mounted node with rects inside the safe content rect", function()
		local _, _, _, adapter = makeSlice()
		-- Screen, Title, Music, When region container, Save
		expect(adapter.liveCount()).toBe(5)
		local title = adapter.node("/Settings/Title")
		expect(title.rect.y >= 59).toBe(true)
	end)

	it("a paint/semantics-only change writes the prop and never re-solves or writes rects", function()
		local _, _, _, adapter, controller, music = makeSlice()
		local solvesBefore = controller.stats().solves
		music:set(true)
		controller.refresh()
		local ops = adapter.takeOps()
		expect(#ops).toBe(1)
		expect(string.find(ops[1], "prop /Settings/Music.value=true") ~= nil).toBe(true)
		expect(controller.stats().solves).toBe(solvesBefore)
	end)

	it("a viewport change re-solves and writes only changed rects", function()
		local _, env, _, adapter, controller = makeSlice()
		-- viewport rotation: the renderer's env subscription re-solves
		env:set("viewportRect", { x = 0, y = 0, w = 844, h = 390 })
		env:set("coreSafeInsets", { top = 0, bottom = 21, left = 59, right = 59 })
		local ops = adapter.takeOps()
		expect(#ops > 0).toBe(true)
		for _, op in ops do
			-- a re-arrange writes GEOMETRY only: changed rects, and the derived hit
			-- rects the effective-target floor needs (B-BTN3). No creates, removes,
			-- or prop writes.
			local kind = string.sub(op, 1, 4)
			if kind ~= "rect" and kind ~= "hitr" then
				error(`unexpected op on a pure re-arrange: {op}`)
			end
		end
	end)

	it("When toggling creates/removes adapter nodes and re-solves", function()
		local _, _, _, adapter, controller, _, showAdvanced = makeSlice()
		local live = adapter.liveCount()
		showAdvanced:set(true)
		controller.refresh()
		expect(adapter.liveCount()).toBe(live + 1)
		expect(adapter.node("/Settings/Advanced/then/Hint") ~= nil).toBe(true)
		showAdvanced:set(false)
		controller.refresh()
		expect(adapter.liveCount()).toBe(live)
		expect(adapter.node("/Settings/Advanced/then/Hint")).toBe(nil)
	end)

	it("dispose destroys the adapter root", function()
		local _, _, root, adapter, controller = makeSlice()
		controller.dispose()
		root.dispose()
		expect(adapter.rootCount()).toBe(0)
	end)
end)

describe("environment: per-key isolation", function()
	it("a keyboard-occlusion change never touches a color-only subscriber", function()
		local core = customFactory.new()
		local env = environment.new(core)
		local colorFires, keyboardFires = 0, 0
		core:observe(env:get("preferredTransparency"), function()
			colorFires += 1
		end)
		core:observe(env:get("keyboardOcclusionRect"), function()
			keyboardFires += 1
		end)
		env:set("keyboardOcclusionRect", { x = 0, y = 500, w = 390, h = 344 })
		expect(keyboardFires).toBe(1)
		expect(colorFires).toBe(0)
	end)

	it("derived sizeClass recomputes only from viewportRect", function()
		local core = customFactory.new()
		local env = environment.new(core)
		expect(env:get("sizeClass"):get()).toBe("wide")
		env:set("viewportRect", { x = 0, y = 0, w = 390, h = 844 })
		expect(env:get("sizeClass"):get()).toBe("compact")
	end)

	-- ADR-0015: the live interaction-class set, derived from capabilities +
	-- preferredInput (never the preference alone)
	it("derived interactionClasses: defaults are a pointer/keyboard desktop", function()
		local core = customFactory.new()
		local env = environment.new(core)
		local classes = env:get("interactionClasses"):get()
		expect(classes.pointer).toBe(true)
		expect(classes.keyboard).toBe(true)
		expect(classes.touch).toBe(false)
		expect(classes.gamepad).toBe(false)
		expect(classes.primary).toBe("pointer")
	end)

	it("derived interactionClasses: a live gamepad capability joins the set without moving primary", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("capabilities", { keyboard = true, mouse = true, touch = false, gamepad = true })
		local classes = env:get("interactionClasses"):get()
		expect(classes.gamepad).toBe(true)
		expect(classes.pointer).toBe(true)
		expect(classes.primary).toBe("pointer")
	end)

	it("derived interactionClasses: the preferred class is forced live even when its capability fact lags", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("preferredInput", "Gamepad")
		local classes = env:get("interactionClasses"):get()
		expect(classes.gamepad).toBe(true)
		expect(classes.primary).toBe("gamepad")
	end)

	-- console 10-foot (input-paradigms expansion): displaySize is an engine
	-- fact (GuiService.ViewportDisplaySize), overscanInsets a developer-space
	-- fact distinct from the mobile notch; distanceProfile keys off Large
	it("displaySize fact defaults to Medium and distanceProfile derives ten-foot from Large", function()
		local core = customFactory.new()
		local env = environment.new(core)
		expect(env:get("displaySize"):get()).toBe("Medium")
		expect(env:get("distanceProfile"):get()).toBe("near")
		env:set("displaySize", "Large")
		expect(env:get("distanceProfile"):get()).toBe("ten-foot")
		env:set("displaySize", "garbage")
		expect(env:get("distanceProfile"):get()).toBe("near")
	end)

	it("overscanInsets fact defaults to zero and is settable", function()
		local core = customFactory.new()
		local env = environment.new(core)
		local insets = env:get("overscanInsets"):get()
		expect(insets.top).toBe(0)
		expect(insets.left).toBe(0)
		env:set("overscanInsets", { top = 27, bottom = 27, left = 48, right = 48 })
		expect(env:get("overscanInsets"):get().left).toBe(48)
	end)
end)

describe("tokens and authority", function()
	it("compiles a valid schema and reports contrast", function()
		local compiled, report = tokensLib.compile({
			colors = {
				surface = { r = 0.1, g = 0.1, b = 0.14 },
				content = { r = 0.95, g = 0.95, b = 0.97 },
				surfaceStrong = { r = 0.05, g = 0.05, b = 0.08 },
				contentStrong = { r = 1, g = 1, b = 1 },
				accent = { r = 0.09, g = 0.28, b = 0.6 },
				onAccent = { r = 1, g = 1, b = 1 },
			},
			type = { body = 16, label = 14, heading = 20, title = 24 },
			space = { xs = 4, s = 8, m = 16, l = 24, xl = 40 },
			targetSizes = { minimum = 44 },
			motion = { fast = 0.12, normal = 0.25 },
		})
		expect(report.ok).toBe(true)
		expect(compiled.space.m).toBe(16)
		expect(#report.contrast).toBe(3)
	end)

	it("rejects an incomplete or low-contrast schema with a named report", function()
		local compiled, report = tokensLib.compile({
			colors = {
				surface = { r = 0.5, g = 0.5, b = 0.5 },
				content = { r = 0.55, g = 0.55, b = 0.55 }, -- unreadable
				surfaceStrong = { r = 0, g = 0, b = 0 },
				contentStrong = { r = 1, g = 1, b = 1 },
				accent = { r = 0.2, g = 0.4, b = 1 },
				onAccent = { r = 1, g = 1, b = 1 },
			},
			type = { body = 16, label = 14, heading = 20, title = 24 },
			space = { xs = 4, s = 8, m = 16, l = 24, xl = 40 },
			targetSizes = { minimum = 44 },
			motion = { fast = 0.12, normal = 0.25 },
		})
		expect(compiled).toBe(nil)
		expect(report.ok).toBe(false)
		expect(report.contrast[1].ok).toBe(false)
	end)

	it("authority conflicts are loud errors", function()
		local ok, err = pcall(function()
			authority.assertWrite("Text", "text", "style")
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "owned by binding") ~= nil).toBe(true)
		local ok2 = pcall(function()
			authority.assertWrite("Text", "text", "binding")
		end)
		expect(ok2).toBe(true)
	end)
end)

describe("Button padding reaches the adapter (playlist stars defect 2026-07-20)", function()
	it("forwards the blueprint padding so the engine text inset matches the solver", function()
		-- the adapter hardcoded a 12px UIPadding; a 22px star button solved
		-- with padding=2 but rendered with a -2px text area (invisible glyph)
		local LuauUI = require("../src") :: any
		local mountLib = require("../src/mount")
		local rendererLib = require("../src/render/renderer")
		local fake_target = require("./lib/fake_target")
		local core = LuauUI.newCore()
		local env = LuauUI.newEnvironment(core)
		local adapter = fake_target.new()
		local screen = LuauUI.UI.Screen({
			id = "S",
			children = {
				LuauUI.UI.Button({ id = "Tiny", label = "★", padding = 2, width = { type = "fixed", px = 22 } }),
				LuauUI.UI.Button({ id = "Normal", label = "Save" }),
			},
		})
		local root = mountLib.mount(core, screen)
		local controller = rendererLib.attach(core, root, env, adapter, {})
		controller.initialRender()
		expect(adapter.node("/S/Tiny").props.padding).toBe(2)
		expect(adapter.node("/S/Normal").props.padding).toBe(12) -- the default
		root.dispose()
	end)
end)

describe("Toggle sizing honors its label (gallery place defect 2026-07-20)", function()
	it("a bare labeled Toggle measures wide enough for label text PLUS the track chrome", function()
		-- ScreenTarget renders label-left + 44px track right-aligned with
		-- 12px inset and 16px label margin; a 56px track-only rect painted
		-- the label UNDER the track (director screenshot, settings place)
		local LuauUI = require("../src") :: any
		local mountLib = require("../src/mount")
		local rendererLib = require("../src/render/renderer")
		local fake_target = require("./lib/fake_target")
		local core = LuauUI.newCore()
		local env = LuauUI.newEnvironment(core)
		local adapter = fake_target.new()
		local screen = LuauUI.UI.Screen({
			id = "S",
			padding = 16,
			gap = 8,
			children = {
				LuauUI.UI.Toggle({ id = "Music", label = "Music", value = core:signal(false) }),
				LuauUI.UI.Text({ id = "Below", text = "below", textSize = 14 }),
			},
		})
		local root = mountLib.mount(core, screen)
		local controller = rendererLib.attach(core, root, env, adapter, {})
		controller.initialRender()
		local toggle = adapter.node("/S/Music").rect
		-- label region (>= measured text at the adapter's 16pt label size)
		-- plus the track chrome the adapter reserves (12 + 44 + 12 + 16)
		local text_metrics = require("../src/layout/text_metrics")
		local labelWidth = text_metrics.measure("Music", "BuilderSans", 16, math.huge).width
		expect(toggle.w).toBeGreaterThanOrEqual(labelWidth + 84)
		expect(toggle.h).toBeGreaterThanOrEqual(28) -- never shorter than the track row
		-- an explicit width still wins (the Settings-port row pattern)
		local screen2 = LuauUI.UI.Screen({
			id = "T",
			children = {
				LuauUI.UI.Toggle({
					id = "Wide",
					label = "Music",
					value = core:signal(false),
					width = { type = "fixed", px = 300 },
				}),
			},
		})
		local root2 = mountLib.mount(core, screen2)
		local adapter2 = fake_target.new()
		local controller2 = rendererLib.attach(core, root2, env, adapter2, {})
		controller2.initialRender()
		expect(adapter2.node("/T/Wide").rect.w).toBe(300)
		root.dispose()
		root2.dispose()
	end)
end)

describe("safe areas: deviceSafeContent root policy (native-substrate NS-A1)", function()
	local function makeDeviceSlice()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 390, h = 844 })
		env:set("coreSafeInsets", { top = 59, bottom = 34, left = 0, right = 0 })
		env:set("deviceSafeInsets", { top = 0, bottom = 21, left = 47, right = 47 })
		local bp = UI.Screen({
			id = "SafeArea",
			children = {
				UI.Text({ id = "Title", text = "safe", textSize = 20 }),
			},
		})
		local root = mountLib.mount(core, bp)
		local adapter = fake_target.new()
		local controller = renderer.attach(core, root, env, adapter, { rootPolicy = "deviceSafeContent" })
		controller.initialRender()
		adapter.takeOps()
		return core, env, root, adapter, controller
	end

	it("deviceSafeContent insets the content rect by the per-edge MAX of core and device insets", function()
		local _, _, _, adapter = makeDeviceSlice()
		local rootNode = adapter.node("/SafeArea")
		-- top max(59,0)=59, bottom max(34,21)=34, left max(0,47)=47, right max(0,47)=47
		expect(rootNode.rect.x).toBe(47)
		expect(rootNode.rect.y).toBe(59)
		expect(rootNode.rect.w).toBe(390 - 47 - 47)
		expect(rootNode.rect.h).toBe(844 - 59 - 34)
	end)

	it("a deviceSafeInsets fact change re-solves and writes rects", function()
		local _, env, _, adapter = makeDeviceSlice()
		env:set("deviceSafeInsets", { top = 0, bottom = 21, left = 60, right = 40 })
		local ops = adapter.takeOps()
		expect(#ops > 0).toBe(true)
		local sawRect = false
		for _, op in ops do
			if string.sub(op, 1, 4) == "rect" then
				sawRect = true
			end
		end
		expect(sawRect).toBe(true)
	end)

	it("coreSafeContent policy ignores deviceSafeInsets (default unchanged)", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 390, h = 844 })
		env:set("coreSafeInsets", { top = 59, bottom = 34, left = 0, right = 0 })
		env:set("deviceSafeInsets", { top = 0, bottom = 21, left = 47, right = 47 })
		local bp = UI.Screen({ id = "CoreOnly", children = { UI.Text({ id = "T", text = "x", textSize = 14 }) } })
		local root = mountLib.mount(core, bp)
		local adapter = fake_target.new()
		local controller = renderer.attach(core, root, env, adapter, { rootPolicy = "coreSafeContent" })
		controller.initialRender()
		local rootNode = adapter.node("/CoreOnly")
		expect(rootNode.rect.x).toBe(0)
		expect(rootNode.rect.y).toBe(59)
		controller.dispose()
		root.dispose()
	end)
end)

describe("preferred text applied exactly once (native-substrate NS-A9)", function()
	local function makeTextSlice()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 400 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local bp = UI.Screen({
			id = "T",
			children = { UI.Text({ id = "Body", text = "hello", textSize = 20 }) },
		})
		local root = mountLib.mount(core, bp)
		local adapter = fake_target.new()
		local controller = renderer.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
		controller.initialRender()
		return core, env, root, adapter, controller
	end

	it("the player preference scales MEASUREMENT (reserved bounds) but never the painted TextSize", function()
		local _, env, _, adapter, controller = makeTextSlice()
		local baseH = adapter.node("/T/Body").rect.h
		expect(adapter.node("/T/Body").props.textSize).toBe(20)
		env:set("preferredTextSize", 1.45) -- Largest (reservation factor)
		controller.refresh()
		-- measure seam: the solver reserved a taller box for the engine-scaled text
		expect(adapter.node("/T/Body").rect.h > baseH).toBe(true)
		-- paint seam: LuauUI did NOT multiply the preference into TextSize —
		-- the ENGINE applies the preference at draw time (double-application fix)
		expect(adapter.node("/T/Body").props.textSize).toBe(20)
	end)

	it("authored ten-foot scale still reaches BOTH seams (it is not engine-owned)", function()
		local _, env, _, adapter, controller = makeTextSlice()
		env:set("displaySize", "Large")
		controller.refresh()
		expect(adapter.node("/T/Body").props.textSize).toBe(30) -- 20 * 1.5 floor
	end)

	-- preferred-text sweep, 2026-07-24. The split seams are only safe while
	-- MEASURE >= PAINT. typographyScale's legal domain starts at 0.5, but the
	-- paint seam carries no preference factor — so a sub-1 preference used to
	-- reserve HALF the box the engine then drew into. Proven live in Studio at
	-- preferredTextSize=0.5: 10 nodes reported TextFits == false on both the
	-- compact-phone-portrait and desktop-standard profiles.
	it("a preference BELOW 1 never reserves less than the painted size", function()
		local _, env, _, adapter, controller = makeTextSlice()
		local baseH = adapter.node("/T/Body").rect.h
		env:set("preferredTextSize", 0.5) -- the floor of typographyScale's legal domain
		controller.refresh()
		-- paint is unchanged, so the reservation must be unchanged too
		expect(adapter.node("/T/Body").props.textSize).toBe(20)
		expect(adapter.node("/T/Body").rect.h).toBe(baseH)
	end)

	it("the reservation floor composes with the ten-foot paint scale", function()
		local _, env, _, adapter, controller = makeTextSlice()
		env:set("displaySize", "Large") -- paint scale 1.5 -> painted TextSize 30
		env:set("preferredTextSize", 0.5) -- would drag measure back to 0.75x
		controller.refresh()
		local painted = adapter.node("/T/Body").props.textSize
		expect(painted).toBe(30)
		-- the box must still hold the 30px text the engine is told to draw
		local reservedH = adapter.node("/T/Body").rect.h
		env:set("preferredTextSize", 1)
		controller.refresh()
		expect(reservedH).toBe(adapter.node("/T/Body").rect.h)
	end)
end)

describe("preferred text ADDITIVE reservation (platform verifier F1/F2, 2026-07-23)", function()
	it("the live additive offset grows reserved bounds for EXPLICIT and DEFAULT-size text, never paint", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 400 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local bp = UI.Screen({
			id = "AO",
			children = {
				UI.Text({ id = "Explicit", text = "hello", textSize = 12 }),
				UI.Text({ id = "Default", text = "hello" }),
			},
		})
		local root = mountLib.mount(core, bp)
		local adapter = fake_target.new()
		local controller = renderer.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
		controller.initialRender()
		local hExplicit = adapter.node("/AO/Explicit").rect.h
		local hDefault = adapter.node("/AO/Default").rect.h
		-- the engine applies the preference as a FIXED PIXEL OFFSET: a
		-- multiplier under-reserves small text (12 * 1.45 < 12 + 14), so the
		-- live reservation must be additive and cover intrinsic defaults too
		env:set("preferredTextOffset", 14)
		controller.refresh()
		expect(adapter.node("/AO/Explicit").rect.h > hExplicit).toBe(true)
		expect(adapter.node("/AO/Default").rect.h > hDefault).toBe(true)
		expect(adapter.node("/AO/Explicit").props.textSize).toBe(12)
		controller.dispose()
		root.dispose()
	end)
end)

-- ===== REVIEW-FIX round: padding follows the theme (F27) ====================

describe("Button padding is re-pushed on every solve, minimally", function()
	local themeSnapshot = require("../src/themes/snapshot")

	local function paddingWorld()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local root =
			mountLib.mount(core, UI.Screen({ id = "S", children = { UI.Button({ id = "Go", label = "Go" }) } }))
		local adapter = fake_target.new()
		local r = renderer.attach(core, root, env, adapter, {})
		r.initialRender()
		return core, env, adapter, r
	end

	-- count padding writes at the adapter seam: `setProp` is where the minimal-
	-- write contract is actually observable
	local function countingWorld()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local root =
			mountLib.mount(core, UI.Screen({ id = "S", children = { UI.Button({ id = "Go", label = "Go" }) } }))
		local adapter = fake_target.new()
		local writes = 0
		local base = adapter.setProp
		adapter.setProp = function(handle: any, prop: string, value: any, authority: string)
			if prop == "padding" then
				writes += 1
			end
			return base(handle, prop, value, authority)
		end
		local r = renderer.attach(core, root, env, adapter, {})
		r.initialRender()
		return env, adapter, r, function()
			return writes
		end
	end

	it("a theme commit moves the engine inset, not just the solver's reservation", function()
		local _, env, adapter = paddingWorld()
		-- the construction inset landed once
		expect(adapter.node("/S/Go").props.padding).toBe(themeSnapshot.neutral().controls.button.padding)

		local roomier = themeSnapshot.resolve(
			themeSnapshot.neutralPackage(),
			nil,
			{},
			{ ["controls.button.padding"] = 40 }
		)
		env:set("themeMetrics", roomier)

		-- the SECOND write: without it the engine kept the construction inset for
		-- the rest of the session while the solver reserved 40
		expect(adapter.node("/S/Go").props.padding).toBe(40)
	end)

	-- PER-SIDE PADDING REACHES THE ENGINE AS A TABLE (found 2026-07-26 by the
	-- gallery picker's tight-vertical chip). `padding = { top = "xs" }` is an
	-- ordinary authored value on every container the schema declares, Button
	-- included, and the adapter's write handed it straight to `UDim.new`, which
	-- errors on a table — a crash on documented input, on the paint seam, on
	-- every solve.
	it("carries an authored PER-SIDE padding through the same seam, resolved", function()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local root = mountLib.mount(
			core,
			UI.Screen({
				id = "S",
				children = {
					UI.Button({
						id = "Chip",
						label = "Classic Desktop",
						padding = {
							top = "xs",
							bottom = "xs",
							left = "controls.button.padding",
							right = "controls.button.padding",
						},
					}),
				},
			})
		)
		local adapter = fake_target.new()
		local r = renderer.attach(core, root, env, adapter, {})
		r.initialRender()
		local neutral = themeSnapshot.neutral()
		local written = adapter.node("/S/Chip").props.padding
		expect(type(written)).toBe("table")
		expect(written.top).toBe(neutral.space.xs)
		expect(written.left).toBe(neutral.controls.button.padding)
		-- the box the SOLVER reserved agrees with what was written: tighter than
		-- the same label under the default all-round padding, and the same width
		local plainCore = customFactory.new()
		local plainEnv = environment.new(plainCore)
		plainEnv:set("viewportRect", { x = 0, y = 0, w = 800, h = 600 })
		local plainRoot = mountLib.mount(
			plainCore,
			UI.Screen({ id = "S", children = { UI.Button({ id = "Chip", label = "Classic Desktop" }) } })
		)
		local plainAdapter = fake_target.new()
		local plainR = renderer.attach(plainCore, plainRoot, plainEnv, plainAdapter, {})
		plainR.initialRender()
		local rect, plain = adapter.node("/S/Chip").rect, plainAdapter.node("/S/Chip").rect
		expect(rect.h).toBe(plain.h - 2 * (neutral.controls.button.padding - neutral.space.xs))
		expect(rect.w).toBe(plain.w)
		plainR.dispose()
		plainRoot.dispose()
		-- ...and a theme commit still moves it, per side
		env:set(
			"themeMetrics",
			themeSnapshot.resolve(themeSnapshot.neutralPackage(), nil, {}, { ["controls.button.padding"] = 40 })
		)
		expect(adapter.node("/S/Chip").props.padding.left).toBe(40)
		expect(adapter.node("/S/Chip").props.padding.top).toBe(neutral.space.xs)
		r.dispose()
		root.dispose()
	end)

	it("the adapter spends the HORIZONTAL pair of that table, never the table itself", function()
		-- the engine inset is horizontal by construction (the label centres inside
		-- the box the solver reserved), and an unwritten side is 0 — the same
		-- reading `solver.sides` gave the measure pass. Anchored on source: this
		-- half is an engine write.
		local fs = require("@lune/fs")
		-- the LIVE adapter as ONE text: three files since the 200k split
		local target = adapter_source.live()
		local at = string.find(target, 'elseif prop == "padding" then', 1, true)
		expect(at ~= nil).toBe(true)
		local body = string.sub(target, at :: number, (at :: number) + 1400)
		expect(string.find(body, "value.left", 1, true) ~= nil).toBe(true)
		expect(string.find(body, "value.right", 1, true) ~= nil).toBe(true)
		-- the crashing form is gone
		expect(string.find(body, "pad.PaddingLeft = UDim.new(0, value)", 1, true)).toBeNil()
	end)

	it("a steady theme costs zero padding writes (minimal-write contract)", function()
		local env, adapter, r, writes = countingWorld()
		local before = writes()
		expect(before).toBe(1) -- exactly one at construction
		-- solves that change nothing about padding
		env:set("viewportRect", { x = 0, y = 0, w = 700, h = 600 })
		env:set("viewportRect", { x = 0, y = 0, w = 640, h = 480 })
		r.refresh()
		expect(writes()).toBe(before)
		-- ...and a theme that DOES move it costs exactly one more
		env:set(
			"themeMetrics",
			themeSnapshot.resolve(themeSnapshot.neutralPackage(), nil, {}, { ["controls.button.padding"] = 40 })
		)
		expect(writes()).toBe(before + 1)
		expect(adapter.node("/S/Go").props.padding).toBe(40)
	end)
end)

-- ===========================================================================
-- DIRECTOR ROUND 9 (2026-07-26): a control row's label column
-- ===========================================================================

describe("RS-DIR9: the Toggle's label column is ONE description, not two", function()
	local themeSnapshot = require("../src/themes/snapshot")
	local fs = require("@lune/fs")

	it("the neutral answer is byte-identical to the constants the adapter used to carry", function()
		-- the compatibility statement: `space.s + 4` and `space.m` of the boot
		-- style happened to equal `trackInset` and the gap under Studio Neutral,
		-- which is exactly why the divergence hid for four stages
		local pad = themeSnapshot.toggleRowPadding(themeSnapshot.neutral())
		expect(pad.left).toBe(12)
		expect(pad.right).toBe(44 + 12 + 16)
		expect(pad.top).toBe(4) -- space.xs, exactly as the measure seam always used
		expect(pad.bottom).toBe(4)
	end)

	it("it follows the LIVE metrics — the classic-desktop and sci-fi numbers that clipped", function()
		-- classic-desktop: space.m = 8, so the reserved label column is 8 px WIDER
		-- than the adapter's boot-constant one drew. Measured live: the row solved
		-- to 104 px, the solver reserved 28 px of label and the adapter drew 20.
		local classic = { controls = { toggle = { trackWidth = 44, trackInset = 12 } }, space = { xs = 2, m = 8 } }
		local pad = themeSnapshot.toggleRowPadding(classic)
		expect(pad.left).toBe(12)
		expect(pad.right).toBe(64)
		expect(104 - pad.left - pad.right).toBe(28)
		-- sci-fi: space.m = 14, and the same row solved to 122
		local scifi = { controls = { toggle = { trackWidth = 44, trackInset = 12 } }, space = { xs = 4, m = 14 } }
		local sci = themeSnapshot.toggleRowPadding(scifi)
		expect(122 - sci.left - sci.right).toBe(40)
	end)

	it("a package that moves the track moves BOTH ends of the row", function()
		local wide = { controls = { toggle = { trackWidth = 60, trackInset = 20 } }, space = { xs = 6, m = 18 } }
		local pad = themeSnapshot.toggleRowPadding(wide)
		expect(pad.left).toBe(20)
		expect(pad.right).toBe(98)
	end)

	it("the renderer's measure seam reads it, and so does the adapter's paint seam", function()
		-- the whole property: the two seams cannot disagree because there is one
		-- function. Anchored on source because the adapter half is an engine write.
		local renderer = renderer_source.all()
		expect(string.find(renderer, "themeSnapshot.toggleRowPadding(metrics)", 1, true) ~= nil).toBe(true)
		-- the LIVE adapter as ONE text: three files since the 200k split
		local target = adapter_source.live()
		expect(string.find(target, "themeSnapshot.toggleRowPadding(snap)", 1, true) ~= nil).toBe(true)
		-- ...and the boot-constant expression is gone
		expect(string.find(target, "style.space.s + 4 + 44 + 12 + style.space.m", 1, true)).toBeNil()
		-- the label's SIZE follows the node's published textSize (the size the
		-- solver measured with), instead of the hardcoded 16 it was born at
		expect(string.find(target, "handle.labelInstance.TextSize = value", 1, true) ~= nil).toBe(true)
		-- and a theme swap re-applies the column
		local at = string.find(target, "function adapter.setThemePackage", 1, true)
		expect(at ~= nil).toBe(true)
		local body = string.sub(target, at :: number, (at :: number) + 3000)
		expect(string.find(body, "applyToggleLabelBox(handle)", 1, true) ~= nil).toBe(true)
	end)
end)

-- ===========================================================================
-- DIRECTOR FINDING 13 (2026-07-26): flipping a value must not move geometry,
-- and a Toggle's label must never break mid-word
-- ===========================================================================

describe("RS-DIR13: a value flip is PAINT — it moves no solved geometry", function()
	local LuauUI = require("../src") :: any
	local themeSnapshot = require("../src/themes/snapshot")

	local PACKAGES = {
		classic_desktop = require("../examples/themes/classic_desktop"),
		scifi_hud = require("../examples/themes/scifi_hud"),
		glossy_mobile = require("../examples/themes/glossy_mobile"),
		glossy_touch = require("../examples/themes/glossy_touch"),
		compact_pointer = require("../examples/themes/compact_pointer"),
		fantasy_ornate = require("../examples/themes/fantasy_ornate"),
		fantasy_parchment = require("../examples/themes/fantasy_parchment"),
		pixel_quest = require("../examples/themes/pixel_quest"),
	}

	-- a settings-shaped row set: two switches sharing one signal (the second one
	-- disabled, so the sweep covers the state the accessibility floor paints) and
	-- a Button beside them, all under the package's own resolved metrics
	local function world(pkg: any)
		local core = LuauUI.newCore()
		local env = LuauUI.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 1233, h = 1067 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		env:set("themeMetrics", themeSnapshot.resolve(pkg, nil, {}))
		local adapter = fake_target.new()
		local presenter = LuauUI.newPresenter(core, env, adapter, LuauUI.newActionSystem(core))
		local switch = core:signal(false)
		presenter.present(LuauUI.UI.Screen({
			id = "S",
			padding = 16,
			gap = 8,
			children = {
				LuauUI.UI.Toggle({ id = "Music", label = "Music", value = switch }),
				LuauUI.UI.Toggle({ id = "Locked", label = "Locked", value = switch, enabled = false }),
				LuauUI.UI.Button({ id = "Save", label = "Save" }),
			},
		}))
		presenter.refresh()
		local function geometry(): string
			local paths = adapter.paths()
			table.sort(paths)
			local parts: { string } = {}
			for _, path in paths do
				local node = adapter.node(path)
				local rect = node.rect
				if rect ~= nil then
					table.insert(parts, `{path}={rect.x},{rect.y},{rect.w},{rect.h}`)
				end
			end
			return table.concat(parts, "|")
		end
		return { switch = switch, presenter = presenter, geometry = geometry, adapter = adapter }
	end

	it("is byte-stable across repeated flips, in every reference package", function()
		local names: { string } = { "studio-neutral" }
		for name in PACKAGES do
			table.insert(names, name)
		end
		table.sort(names)
		for _, name in names do
			local pkg = if name == "studio-neutral"
				then LuauUI.themes.neutralPackage()
				else (PACKAGES[name] :: any).build(LuauUI.themes)
			local w = world(pkg)
			local before = w.geometry()
			for _ = 1, 3 do
				w.switch:set(true)
				w.presenter.refresh()
				expect(w.geometry()).toBe(before)
				w.switch:set(false)
				w.presenter.refresh()
				expect(w.geometry()).toBe(before)
			end
		end
	end)

	it("says so at the boundary: `value` dirties paint and semantics, never measure", function()
		-- the invariant expressed where it is DECIDED, so a future prop edit that
		-- would re-solve on every flip fails here rather than in a capture
		local schema = require("../src/blueprint_schema")
		local dirty = table.concat(schema.propDirty().Toggle.value, ",")
		expect(string.find(dirty, "paint", 1, true) ~= nil).toBe(true)
		expect(string.find(dirty, "measure", 1, true)).toBeNil()
		expect(string.find(dirty, "arrange", 1, true)).toBeNil()
		expect(string.find(dirty, "structure", 1, true)).toBeNil()
	end)
end)

describe("RS-DIR13: a Toggle's label is ONE line — it never breaks mid-word", function()
	local LuauUI = require("../src") :: any
	local themeSnapshot = require("../src/themes/snapshot")
	local fs = require("@lune/fs")

	-- THE DEFECT, measured live 2026-07-26 (Studio 0.731, 1233x1067, native
	-- StyleSheets on). The reserved label column is `ceil(measured width)` and the
	-- engine draws exactly that, so under four of nine reference packages the
	-- column and the drawn bounds are EQUAL to the pixel: Studio Neutral 35/35,
	-- classic-desktop 28/28, and the ValueProbe's "Candlelight" at 67/67 (neutral)
	-- and 73/73 (sci-fi). With `TextWrapped = true` a one-pixel shortfall does not
	-- clip — it BREAKS THE WORD: perturbing the live Music row by −1 px collapsed
	-- `TextBounds` from 35x16 to 28x16, which is "Musi" on line one and "c" on line
	-- two, clipped by a 28 px-tall row. That is the director's "Musi c" exactly.
	-- Setting `TextWrapped = false` on the same perturbed row restored 35x16.
	--
	-- And the row IS perturbed on every flip: `extra.pressedScale` (0.985) shrinks
	-- the whole control while the press animates, measured live at 104 -> 102.44 ->
	-- 104 under classic-desktop.

	it("the adapter draws the toggle label on one line and ellipsizes rather than wrapping", function()
		-- the LIVE adapter as ONE text: three files since the 200k split
		local target = adapter_source.live()
		local at = string.find(target, "local function buildToggleVisual", 1, true)
		expect(at ~= nil).toBe(true)
		local body = string.sub(target, at :: number, (at :: number) + 2200)
		expect(string.find(body, "label.TextWrapped = false", 1, true) ~= nil).toBe(true)
		expect(string.find(body, "label.TextTruncate = Enum.TextTruncate.AtEnd", 1, true) ~= nil).toBe(true)
	end)

	it("...and the SOLVER reserves one line too, so measure and paint agree", function()
		-- the class of defect this stage keeps finding: a paint seam that draws
		-- one thing while the measure seam reserved another. A single-line label
		-- must be MEASURED single-line or the row reserves height for a second
		-- line nobody draws.
		local core = LuauUI.newCore()
		local env = LuauUI.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 320, h = 600 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		env:set("themeMetrics", themeSnapshot.resolve(LuauUI.themes.neutralPackage(), nil, {}))
		local adapter = fake_target.new()
		local presenter = LuauUI.newPresenter(core, env, adapter, LuauUI.newActionSystem(core))
		presenter.present(LuauUI.UI.Screen({
			id = "S",
			children = {
				-- a label far too long for the column the track leaves behind, in a
				-- row that is NOT free to grow (fill width inside a 320px screen)
				LuauUI.UI.Toggle({
					id = "Long",
					label = "Ambient occlusion quality preset",
					value = false,
					width = { type = "fill", weight = 1 },
				}),
			},
		}))
		presenter.refresh()
		local row = adapter.node("/S/Long").rect
		local snap = themeSnapshot.resolve(LuauUI.themes.neutralPackage(), nil, {})
		local pad = themeSnapshot.toggleRowPadding(snap)
		local role = snap.type[themeSnapshot.INTRINSIC_TEXT_ROLE.Toggle]
		-- the label genuinely does not fit: the column the track leaves is
		-- narrower than the one line the adapter draws (so this is the ellipsize
		-- case, not a row that had room all along)
		local column = row.w - pad.left - pad.right
		local text_metrics = require("../src/layout/text_metrics")
		local oneLine = text_metrics.measure(
			"Ambient occlusion quality preset",
			role.fontKey,
			role.size,
			math.huge,
			role.lineHeight
		)
		expect(oneLine.width > column).toBe(true)
		-- ...and the row is still ONE line of the toggle's own typography role
		-- plus its padding, never the two-line box wrapping would have reserved
		expect(row.h).toBe(
			math.max(math.ceil(role.size * role.lineHeight) + pad.top + pad.bottom, snap.controls.toggle.minHeight)
		)
		expect(oneLine.lines).toBe(1)
	end)

	it("a long label still GROWS the row where the row is free to grow", function()
		-- "ellipsize-or-grow per the row's rules": an intrinsic-width row takes the
		-- width its one line needs instead of wrapping into a second one
		local core = LuauUI.newCore()
		local env = LuauUI.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 1233, h = 600 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		env:set("themeMetrics", themeSnapshot.resolve(LuauUI.themes.neutralPackage(), nil, {}))
		local adapter = fake_target.new()
		local presenter = LuauUI.newPresenter(core, env, adapter, LuauUI.newActionSystem(core))
		presenter.present(LuauUI.UI.Screen({
			id = "S",
			children = {
				LuauUI.UI.Toggle({ id = "Short", label = "Music", value = false }),
				LuauUI.UI.Toggle({ id = "Long", label = "Ambient occlusion quality", value = false }),
			},
		}))
		presenter.refresh()
		local short = adapter.node("/S/Short").rect
		local long = adapter.node("/S/Long").rect
		expect(long.w > short.w).toBe(true)
		expect(long.h).toBe(short.h)
	end)
end)

-- ===========================================================================
-- ROOT POLICY — decoration paints to the edges, and an unknown mode fails loudly
-- ===========================================================================
--
-- `edgeToEdge` was passed by every modal scrim and read by no branch here, so
-- the scrim was silently inset for months while a comment at the call site said
-- otherwise. These cases pin both halves of the fix.
describe("renderer — root policy", function()
	local LuauUI = require("../src") :: any
	local themeSnapshot = require("../src/themes/snapshot")
	local function world(insets: any)
		local core = LuauUI.newCore()
		local env = LuauUI.newEnvironment(core)
		env:set("viewportRect", { x = 0, y = 0, w = 400, h = 300 })
		env:set("coreSafeInsets", insets)
		env:set("themeMetrics", themeSnapshot.resolve(LuauUI.themes.neutralPackage(), nil, {}))
		local adapter = fake_target.new()
		local presenter = LuauUI.newPresenter(core, env, adapter, LuauUI.newActionSystem(core))
		return presenter, adapter
	end
	local function fullScreen(id: string)
		return LuauUI.UI.Screen({
			id = id,
			children = {
				LuauUI.UI.Spacer({
					id = "Fill",
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
				}),
			},
		})
	end

	it("insets a content root by the core safe area (the default)", function()
		local presenter, adapter = world({ top = 40, bottom = 10, left = 5, right = 5 })
		presenter.present(fullScreen("Content"))
		presenter.refresh()
		local rect = adapter.node("/Content/Fill").rect
		expect(rect.y).toBe(40)
		expect(rect.h).toBe(250) -- 300 - 40 - 10
		expect(rect.w).toBe(390) -- 400 - 5 - 5
	end)

	it("paints an edgeToEdge root under the insets — a backdrop is not content", function()
		local presenter, adapter = world({ top = 40, bottom = 10, left = 5, right = 5 })
		presenter.present(fullScreen("Backdrop"), { rootPolicy = "edgeToEdge" })
		presenter.refresh()
		local rect = adapter.node("/Backdrop/Fill").rect
		expect(rect.x).toBe(0)
		expect(rect.y).toBe(0)
		expect(rect.w).toBe(400)
		expect(rect.h).toBe(300)
	end)

	it("refuses an unknown policy instead of silently using the default", function()
		local presenter = world({ top = 40, bottom = 0, left = 0, right = 0 })
		local ok, err = pcall(function()
			presenter.present(fullScreen("Typo"), { rootPolicy = "edge-to-edge" })
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "unknown rootPolicy", 1, true) ~= nil).toBe(true)
	end)
end)

--[[ THE READ METHODS HAND BACK COPIES (api-architecture-consistency F-30).
	`stats()` cloned; `hiddenRoots()`, `diagnostics()` and `compositionAt(nil)`
	handed out the renderer's live internal tables. Two costs: a caller who
	mutated one corrupted the renderer's own state for the frame, and a caller who
	cached one held a table the next solve replaced under it. These are diagnostic
	reads (a focus rebuild, a test, a debug overlay) — one shallow copy per call is
	free, and it makes the whole read family answer the same way. ]]
describe("renderer: diagnostic reads are copies, not the live tables (F-30)", function()
	local function makeFits()
		local core = customFactory.new()
		local env = environment.new(core)
		env:set("viewportRect", { x = 0, y = 0, w = 300, h = 400 })
		env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
		local bp = UI.Screen({
			id = "S",
			children = {
				UI.ViewThatFits({
					id = "Fits",
					width = { type = "fill", weight = 1 },
					children = {
						UI.Box({
							id = "Wide",
							width = { type = "fixed", px = 500 },
							height = { type = "fixed", px = 40 },
						}),
						UI.Box({
							id = "Narrow",
							width = { type = "fixed", px = 100 },
							height = { type = "fixed", px = 40 },
						}),
					},
				}),
			},
		})
		local root = mountLib.mount(core, bp)
		local adapter = fake_target.new()
		local controller = renderer.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
		controller.initialRender()
		return controller
	end

	it("mutating the hiddenRoots a caller was handed cannot corrupt the renderer", function()
		local controller = makeFits()
		local hidden = controller.hiddenRoots()
		expect(hidden["/S/Fits/Wide"]).toBe(true) -- the 500px candidate lost
		hidden["/S/Fits/Wide"] = nil
		hidden["/S/Fits/Invented"] = true
		local second = controller.hiddenRoots()
		expect(second["/S/Fits/Wide"]).toBe(true)
		expect(second["/S/Fits/Invented"]).toBeNil()
		expect(second == hidden).toBe(false)
	end)

	it("diagnostics and the whole composition set are copies too", function()
		local controller = makeFits()
		local diagnostics = controller.diagnostics()
		table.insert(diagnostics, { node = "/S/Invented", issue = "written by the caller" })
		expect(#controller.diagnostics()).toBe(#diagnostics - 1)
		expect(controller.diagnostics() == diagnostics).toBe(false)

		local compositions = controller.compositionAt()
		compositions["/S/Invented"] = { arrangement = "written by the caller" }
		expect(controller.compositionAt()["/S/Invented"]).toBeNil()
		expect(controller.compositionAt() == compositions).toBe(false)
		-- the per-path read still hands back the stored dump itself (unchanged)
		expect(controller.compositionAt("/S/Fits")).toBeNil()
	end)
end)
