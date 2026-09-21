--!strict
local harness = require("./lib/harness")
-- A THEME COMMIT RE-RESOLVES ADAPTER-OWNED PAINT (director report 2026-08-14).
--
-- *"when i changed to the parchment theme, the spinner stayed blue. i'd expect
-- to make it a similar color?"*
--
-- THE MECHANISM. A theme commit is a RE-SOLVE and never a rebuild
-- — that is what keeps mount identity, focus, scroll and text entry alive across
-- a swap. `themeMetrics` is one of the renderer's coalesced GEOMETRY keys, so the
-- commit re-derives everything the SOLVER reads. It re-derives nothing the
-- ADAPTER paints, and a node whose layout did not change is never re-visited.
-- Most paint survives that because a StyleSheet rule owns it and the sheet is
-- swapped wholesale. The exceptions are the paints NO rule can express:
--
--   * the FOCUS RING's colour     — fixed 2026-07-25, when a director saw it
--   * the TOGGLE's palette        — fixed in the same family
--   * the `tint` channel          — a rule cannot see a VALUE
--   * a `UI.Path`'s stroke ROLE   — a Path2D is not a GuiObject, so no selector
--                                   can reach one at all
--
-- The first two each grew their own refresh at the moment somebody noticed. The
-- last two never did, so:
--
--   * a STATIC tint kept the outgoing package's colour for the rest of its life
--     (a reactive one self-heals on its next write, which is why this looked
--     like "only some things are stale");
--   * a Path's role resolved against the palette the TARGET WAS CONSTRUCTED
--     WITH, so a stroked path had never worn any package's colours — the
--     circular ProgressView's accent arc was Facet-Neutral blue on a parchment
--     screen, permanently.
--
-- WHICH LAYER. The framework's EMISSION is correct and always was: the control
-- emits role names, and `sheet_model.tintColor` / `paletteColor` resolve them
-- correctly against whatever theme they are handed. The defect is entirely in
-- the adapter's APPLICATION — which theme it hands them, and whether it hands
-- them anything at all on a commit. So this spec drives an adapter, not a
-- solver, and the live adapter's half is pinned by source contract below (its
-- engine writes cannot execute here) plus a Studio canary in
-- artifacts/theme-tint-repaint/.
--
-- WHY NO EXISTING CHECK CAUGHT IT: `tests/lib/fake_target` resolved EVERY tint
-- against a hard-coded neutral theme. A fake that cannot tell a themed colour
-- from a stale one cannot fail this test. It now tracks the pushed package, the
-- same way the live target's `paletteTheme()` does.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local customFactory = harness.coreFactory
local UI = harness.UI
local mountLib = harness
local environment = require("../src/env/environment")
local rendererLib = require("../src/render/renderer")
local snapshot = require("../src/themes/snapshot")
local themes = require("../src/themes/package")
local theme_controller = require("../src/client/theme_controller")
local sheet_model = require("../src/tokens/sheet_model")
local default_style = require("../src/tokens/default_style")
local fake_target = require("./lib/fake_target")
local adapter_source = require("./lib/adapter_source")

local adapterSource = adapter_source.live()

describe("native palette switches without a package", function()
	it("repaints mounted Badge roles through the actual native switch and tint writer", function()
		-- Execute the two real adapter methods and the native paint module with
		-- engine objects mocked. Studio separately proves StyleSheet resolution.
		local fs, luau, rb = require("@lune/fs"), require("@lune/luau"), require("@lune/roblox")
		local w = require("./lib/world").new()
		w.present(function()
			return w.UI.Screen("S")({
				w.UI.VStack({
					width = { type = "fixed", px = 320 },
					w.UI.Badge("Standard")({ label = "Ready", icon = "status.info" }),
					w.UI.Badge("Utility")({ label = "Utility", icon = "settings", appearance = "utility" }),
					w.UI.Badge("Media")({ label = "Media", icon = "clock", over = "media" }),
					w.UI.Box("Direct")({
						tint = { direct = "#123456" },
						width = { type = "fixed", px = 20 },
						height = { type = "fixed", px = 20 },
					}),
				}),
			})
		end)
		local handles = {}
		for path, node in w.adapter.liveNodes() do
			if node.props.tint then
				local class = if node.class == "Text" then "TextLabel" else "Frame"
				handles[path] = {
					class = node.class,
					tint = node.props.tint,
					instance = {
						IsA = function(_, wanted)
							return wanted == class or wanted == "GuiObject"
						end,
					},
				}
			end
		end
		local model = sheet_model.build({
			themes = {
				{ name = "Dark", style = default_style },
				{ name = "Light", style = require("../src/tokens/default_light_style") },
			},
		})
		local nativeHandle = { themes = {}, activeTheme = "Dark" }
		for _, theme in model.themes do
			local attributes = {}
			for name, value in theme.tokens do
				if value.kind == "color" then
					attributes[name] = rb.Color3.new(value.r, value.g, value.b)
				end
			end
			nativeHandle.themes[theme.name] = {
				GetAttributes = function()
					return attributes
				end,
			}
		end
		nativeHandle.setTheme = function(name)
			assert(nativeHandle.themes[name])
			nativeHandle.activeTheme = name
		end
		local paint, activePackage
		local noop = function() end
		local source = fs.readFile("src/client/screen_target.luau")
		local active = assert(source:match("(\tfunction setActiveTheme%(.-\n\tend)"))
		local switch = assert(source:match("(\tfunction adapter.setNativeTheme%(.-\n\tend)"))
		local bridge = luau.load(
			"local activeTheme, focusTreatment, setActiveTheme\nlocal adapter = {}\n"
				.. active
				.. "\n"
				.. switch
				.. "\nreturn {adapter=adapter, setActiveTheme=setActiveTheme, theme=function() return activeTheme end}",
			{
				injectGlobals = true,
				environment = {
					nativeMode = true,
					nativeHandle = nativeHandle,
					native_style = require("../src/client/native_style"),
					chrome_slots = require("../src/tokens/chrome_slots"),
					chromeState = {
						package = function()
							return activePackage
						end,
					},
					toColor3 = function(value)
						return value
					end,
					refreshFocusVisuals = noop,
					refreshThemedPaint = function()
						paint.refreshThemedPaint()
					end,
				},
			}
		)()
		local imports = {
			["../tokens/sheet_model"] = sheet_model,
			["../tokens/styling"] = require("../src/tokens/styling"),
			["../tokens/chrome_slots"] = require("../src/tokens/chrome_slots"),
			["../themes/snapshot"] = snapshot,
			["../render/authority"] = require("../src/render/authority"),
		}
		paint = luau.load(fs.readFile("src/client/screen_paint.luau"), {
			injectGlobals = true,
			environment = {
				game = {
					GetService = function()
						return {}
					end,
				},
				UDim2 = rb.UDim2,
				require = function(name)
					return assert(imports[name], name)
				end,
			},
		})().new({
			nativeMode = true,
			style = default_style,
			handlesByPath = handles,
			activeTheme = bridge.theme,
			toColor3 = function(value)
				return value
			end,
			claimPaint = noop,
			assertBespokePaint = noop,
			syncTags = noop,
			chrome = { syncChrome = noop },
		})
		bridge.setActiveTheme(nil)
		local function assertPalette()
			local attrs = nativeHandle.themes[nativeHandle.activeTheme].GetAttributes()
			local count = 0
			for _, handle in handles do
				local actual = if handle.class == "Text"
					then handle.instance.TextColor3
					else handle.instance.BackgroundColor3
				if handle.tint.role then
					local role = handle.tint.role
					local expected = attrs[role:sub(1, 1):upper() .. role:sub(2)]
					assert(
						math.abs(actual.r - expected.R) < 1e-6,
						`{nativeHandle.activeTheme} {role}: painted {actual.r}, sheet {expected.R}`
					)
					expect(actual.g).toBeCloseTo(expected.G, 1e-6)
					expect(actual.b).toBeCloseTo(expected.B, 1e-6)
					count += 1
				else
					expect(actual).toEqual({ r = 0x12 / 255, g = 0x34 / 255, b = 0x56 / 255 })
				end
			end
			expect(count).toBe(8) -- three icon/label pairs, two painted plates
		end
		for _, name in { "Dark", "Light", "Dark", "Light" } do
			bridge.adapter.setNativeTheme(name)
			assertPalette()
		end
		-- Switching the unused legacy sheet cannot take an installed package's paint.
		activePackage = snapshot.neutralPackage()
		bridge.setActiveTheme(activePackage)
		local installed = bridge.theme()
		bridge.adapter.setNativeTheme("Dark")
		expect(bridge.theme()).toBe(installed)
		activePackage = nil
		bridge.setActiveTheme(nil)
		assertPalette()
		w.close()
	end)
end)

-- Fantasy Parchment's real accent — "the illuminator's gold", rgb(122, 72, 26).
-- Taken from the shipped package rather than restated, so a repaint that lands
-- on the wrong palette cannot accidentally match a constant written here.
local parchmentModule = require("../examples/themes/fantasy_parchment")

local function parchmentPackage(): (any, any)
	local pkg = (parchmentModule :: any).build({
		define = themes.define,
		SCHEMA = themes.SCHEMA,
		neutralPackage = snapshot.neutralPackage,
	} :: any)
	local theme: any = nil
	for _, entry in pkg.style.themes do
		if entry.name == pkg.style.defaultTheme then
			theme = entry
		end
	end
	return pkg, theme
end

local function surface(screen: any)
	local core = customFactory.new()
	local env = environment.new(core)
	env:set("viewportRect", { x = 0, y = 0, w = 400, h = 600 })
	env:set("coreSafeInsets", { top = 0, bottom = 0, left = 0, right = 0 })
	local root = mountLib.mount(core, screen)
	local adapter = fake_target.new()
	local controller = rendererLib.attach(core, root, env, adapter, { rootPolicy = "edgeToEdge" })
	controller.initialRender()
	return { core = core, env = env, adapter = adapter, controller = controller }
end

local function near(actual: any, expected: any)
	expect(actual ~= nil).toBe(true)
	expect(actual.r).toBeCloseTo(expected.r, 1e-6)
	expect(actual.g).toBeCloseTo(expected.g, 1e-6)
	expect(actual.b).toBeCloseTo(expected.b, 1e-6)
end

describe("a theme commit re-resolves the tint channel", function()
	it("repaints a STATIC tint that nothing will ever re-write", function()
		local w = surface(UI.VStack({
			id = "S",
			children = {
				UI.Box({
					id = "Mark",
					width = { type = "fixed", px = 8 },
					height = { type = "fixed", px = 8 },
					-- the showcase HUD's task mark, verbatim: a colour and no surface
					tint = { role = "accent", blend = 1 },
				}),
			},
		}))
		local mark = w.adapter.node("/S/Mark")
		near(mark.tintColor, default_style.colors.accent)

		local pkg, theme = parchmentPackage()
		theme_controller.install(w.adapter, pkg, { env = w.env })
		-- NOTHING re-writes this tint: no animation drives it, its value did not
		-- change, and its node's layout did not change. If the commit does not
		-- repaint it, nothing ever will.
		near(w.adapter.node("/S/Mark").tintColor, theme.colors.accent)
	end)

	it("repaints a tint that BLENDS from another role, base and target both", function()
		local w = surface(UI.VStack({
			id = "S",
			children = {
				UI.Box({
					id = "Dot",
					width = { type = "fixed", px = 8 },
					height = { type = "fixed", px = 8 },
					-- the dot spinner's own tint, at a resting fraction
					tint = { role = "accent", from = "control", blend = 0.5 },
				}),
			},
		}))
		local pkg, theme = parchmentPackage()
		theme_controller.install(w.adapter, pkg, { env = w.env })
		near(
			w.adapter.node("/S/Dot").tintColor,
			sheet_model.tintColor(theme, { role = "accent", from = "control", blend = 0.5 }, "Box")
		)
	end)

	it("leaves a `direct` tint alone — it named a colour, not a role", function()
		local w = surface(UI.VStack({
			id = "S",
			children = {
				UI.Box({
					id = "Brand",
					width = { type = "fixed", px = 8 },
					height = { type = "fixed", px = 8 },
					tint = { direct = { r = 0.25, g = 0.5, b = 0.75 } },
				}),
			},
		}))
		local pkg = parchmentPackage()
		theme_controller.install(w.adapter, pkg, { env = w.env })
		near(w.adapter.node("/S/Brand").tintColor, { r = 0.25, g = 0.5, b = 0.75 })
	end)
end)

describe("a theme commit re-resolves a UI.Path's stroke role", function()
	it("paints the ring's accent arc and secondary track in the INSTALLED package", function()
		local ring = { { x = 0.5, y = 0.1 }, { x = 0.9, y = 0.5 }, { x = 0.5, y = 0.9 }, { x = 0.1, y = 0.5 } }
		local w = surface(UI.ZStack({
			id = "S",
			children = {
				-- the circular ProgressView's two paths, verbatim
				UI.Path({
					id = "Track",
					points = ring,
					closed = true,
					thickness = 3,
					role = "secondary",
					width = { type = "fixed", px = 40 },
					height = { type = "fixed", px = 40 },
				}),
				UI.Path({
					id = "Arc",
					points = ring,
					thickness = 3,
					role = "accent",
					width = { type = "fixed", px = 40 },
					height = { type = "fixed", px = 40 },
				}),
			},
		}))
		near(w.adapter.node("/S/Arc").pathRoleColor, default_style.colors.accent)

		local pkg, theme = parchmentPackage()
		theme_controller.install(w.adapter, pkg, { env = w.env })
		near(w.adapter.node("/S/Arc").pathRoleColor, sheet_model.paletteColor(theme, "accent"))
		near(w.adapter.node("/S/Track").pathRoleColor, sheet_model.paletteColor(theme, "contentSecondary"))
	end)

	it("paints a path that declares NO role in the installed package's content colour", function()
		local w = surface(UI.ZStack({
			id = "S",
			children = {
				UI.Path({
					id = "Bare",
					points = { { x = 0.1, y = 0.1 }, { x = 0.9, y = 0.9 } },
					thickness = 2,
					width = { type = "fixed", px = 40 },
					height = { type = "fixed", px = 40 },
				}),
			},
		}))
		local pkg, theme = parchmentPackage()
		theme_controller.install(w.adapter, pkg, { env = w.env })
		near(w.adapter.node("/S/Bare").pathRoleColor, sheet_model.paletteColor(theme, "content"))
	end)
end)

describe("the live adapter carries the same commit (source contract)", function()
	-- The engine writes cannot execute in this suite, so these pin the SHAPE the
	-- Studio canary confirmed: the commit calls the sweep, the sweep re-resolves
	-- both channels, and the Path role no longer reads the construction-time
	-- palette.
	local function has(needle: string): boolean
		return string.find(adapterSource, needle, 1, true) ~= nil
	end

	it("setActiveTheme calls refreshThemedPaint beside the focus and toggle refreshes", function()
		-- READ THE FUNCTION'S OWN BODY, not the whole adapter: `refreshThemedPaint`
		-- is DEFINED in screen_paint, which adapter_source concatenates, so a
		-- whole-text search for the name matches the definition and passes however
		-- the commit is mutated. That version of this check was written first, and
		-- mutation testing is what caught it doing nothing
		-- ("the check that proves nothing").
		local body = string.match(adapterSource, "\n\tfunction setActiveTheme%(.-%)\n(.-)\n\tend\n")
		expect(body ~= nil).toBe(true)
		expect(string.find(body :: string, "refreshFocusVisuals()", 1, true) ~= nil).toBe(true)
		expect(string.find(body :: string, "refreshToggleVisuals()", 1, true) ~= nil).toBe(true)
		expect(string.find(body :: string, "refreshThemedPaint()", 1, true) ~= nil).toBe(true)
	end)

	it("refreshThemedPaint re-applies the path role AND the tint, tint last", function()
		local body = string.match(adapterSource, "local function refreshThemedPaint%(%)(.-)\n\tend")
		expect(body ~= nil).toBe(true)
		local roleAt = string.find(body :: string, "applyPathRole(handle)", 1, true)
		local tintAt = string.find(body :: string, "applyTint(handle)", 1, true)
		expect(roleAt ~= nil).toBe(true)
		expect(tintAt ~= nil).toBe(true)
		-- the tint is the final word on the property it claimed
		expect((tintAt :: number) > (roleAt :: number)).toBe(true)
	end)

	it("a Path's stroke colour no longer comes from the construction-time palette", function()
		-- the exact chain that made every stroked path Facet-Neutral blue
		expect(has('then COLOR.accent\n\t\t\t\t\telseif value == "secondary" then COLOR.contentSecondary')).toBe(false)
		expect(has("path2d.Color3 = COLOR.content")).toBe(false)
		expect(has("handle.pathRole = value")).toBe(true)
	end)
end)
