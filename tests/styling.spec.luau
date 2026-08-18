--!strict
-- Phase 4 engine styling adoption (design §17 Phase 4; UI-STYLE-001,
-- UI-FID-001): UIShadow + per-corner UICorner adopted through the token and
-- property-authority path as SwiftUI-style modifiers. UI.shadow / UI.corners
-- apply to a single element or a container (styling the container's own
-- surface); UI.styleGroup applies to every element of a collection (SwiftUI
-- Group semantics). Shadow params are engine-true per the verified platform
-- facts (BlurRadius is a UDim {scale, offset}; Spread/Offset are UDim2
-- shapes; ZIndex negative-only); corner styling emits EXACTLY ONE form per
-- node (uniform alias or four per-corner radii) — mixing is a build error.
-- Styling is pure paint: it never enters the layout solver. The style lint
-- flags the jagged large-radius-with-shadow caveat and the ~100-on-screen
-- shadow budget.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local Facet = require("../src") :: any
local mountLib = require("../src/mount")
local rendererLib = require("../src/render/renderer")
local style_lint = require("../src/render/style_lint")
local fake_target = require("../tests/lib/fake_target")

local UI = Facet.UI

local function present(screen: any)
	local core = Facet.newCore()
	local env = Facet.newEnvironment(core)
	local adapter = fake_target.new()
	local root = mountLib.mount(core, screen)
	local controller = rendererLib.attach(core, root, env, adapter, {})
	controller.initialRender()
	return core, root, controller, adapter
end

describe("engine styling: shadows and per-corner rounding (§17)", function()
	it("UI.shadow on an element lands as engine-true style data via the style authority", function()
		local screen = UI.Screen({
			id = "S",
			children = {
				UI.shadow(UI.Button({ id = "Go", label = "Go" }), {
					blurRadius = { scale = 0, offset = 12 },
					color = { r = 0, g = 0, b = 0 },
					transparency = 0.5,
					offset = { x = { scale = 0, offset = 0 }, y = { scale = 0, offset = 2 } },
				}),
			},
		})
		local _, root, _, adapter = present(screen)
		local shadow = adapter.node("/S/Go").props.shadow
		expect(shadow ~= nil).toBeTruthy()
		expect(shadow.blurRadius.offset).toBe(12)
		expect(shadow.blurRadius.scale).toBe(0)
		expect(shadow.transparency).toBe(0.5)
		expect(shadow.offset.y.offset).toBe(2)
		expect(shadow.zIndex < 0).toBeTruthy() -- negative-only, defaulted
		expect(shadow.enabled).toBe(true)
		root.dispose()
	end)

	it("a token preset shadow resolves from the style's shadow tokens", function()
		local screen = UI.Screen({
			id = "S",
			children = { UI.shadow(UI.Button({ id = "Go", label = "Go" }), "raised") },
		})
		local _, root, _, adapter = present(screen)
		local shadow = adapter.node("/S/Go").props.shadow
		expect(shadow ~= nil).toBeTruthy()
		expect(shadow.blurRadius.offset > 0).toBeTruthy()
		root.dispose()
	end)

	it("shadows never enter layout: identical rects with and without a shadow", function()
		local plain = UI.Screen({ id = "S", children = { UI.Button({ id = "Go", label = "Go" }) } })
		local shadowed = UI.Screen({
			id = "S",
			children = { UI.shadow(UI.Button({ id = "Go", label = "Go" }), "raised") },
		})
		local _, rootA, controllerA = present(plain)
		local _, rootB, controllerB = present(shadowed)
		local a = controllerA.rectOf("/S/Go")
		local b = controllerB.rectOf("/S/Go")
		expect(a.x).toBe(b.x)
		expect(a.y).toBe(b.y)
		expect(a.w).toBe(b.w)
		expect(a.h).toBe(b.h)
		rootA.dispose()
		rootB.dispose()
	end)

	it("uniform corners emit the alias form; distinct corners emit the per-corner form", function()
		local screen = UI.Screen({
			id = "S",
			children = {
				UI.corners(UI.Button({ id = "Uniform", label = "U" }), 10),
				UI.corners(UI.Button({ id = "Mixed", label = "M" }), { topLeft = 12, topRight = 12 }),
			},
		})
		local _, root, _, adapter = present(screen)
		local uniform = adapter.node("/S/Uniform").props.corners
		expect(uniform.form).toBe("uniform")
		expect(uniform.radius).toBe(10)
		expect(uniform.topLeft).toBeNil() -- exactly one form
		local mixed = adapter.node("/S/Mixed").props.corners
		expect(mixed.form).toBe("perCorner")
		expect(mixed.topLeft).toBe(12)
		expect(mixed.topRight).toBe(12)
		expect(mixed.bottomLeft).toBe(0) -- unspecified corners are explicit zeros
		expect(mixed.radius).toBeNil() -- never the alias too
		root.dispose()
	end)

	it("corner radii resolve token names from the active style", function()
		local bp = UI.corners(UI.Button({ id = "B", label = "B" }), "control")
		expect(bp.props.corners.form).toBe("uniform")
		expect(bp.props.corners.radius).toBe(8) -- default style radii.control
	end)

	it("mixing the alias and per-corner radii in one spec is a build error", function()
		local ok, err = pcall(function()
			return UI.corners(UI.Button({ id = "B", label = "B" }), { radius = 8, topLeft = 2 })
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "one form") ~= nil).toBeTruthy()
	end)

	it("a positive shadow zIndex is a build error (engine: negative only)", function()
		local ok = pcall(function()
			return UI.shadow(
				UI.Button({ id = "B", label = "B" }),
				{ blurRadius = { scale = 0, offset = 4 }, zIndex = 1 }
			)
		end)
		expect(ok).toBe(false)
	end)

	it("UI.styleGroup applies the modifier set to EACH element (SwiftUI Group semantics)", function()
		local group = UI.styleGroup({ shadow = "raised", corners = 10 }, {
			UI.Button({ id = "A", label = "A" }),
			UI.Button({ id = "B", label = "B" }),
		})
		local screen = UI.Screen({ id = "S", children = group })
		local _, root, _, adapter = present(screen)
		for _, id in { "A", "B" } do
			local node = adapter.node(`/S/{id}`)
			expect(node.props.shadow ~= nil).toBeTruthy()
			expect(node.props.corners.radius).toBe(10)
		end
		root.dispose()
	end)

	it("styling a container styles the container's own surface, not its children", function()
		local screen = UI.Screen({
			id = "S",
			children = {
				UI.shadow(
					UI.VStack({
						id = "Panel",
						children = { UI.Button({ id = "Inner", label = "I" }) },
					}),
					"overlay"
				),
			},
		})
		local _, root, _, adapter = present(screen)
		expect(adapter.node("/S/Panel").props.shadow ~= nil).toBeTruthy()
		expect(adapter.node("/S/Panel/Inner").props.shadow).toBeNil()
		root.dispose()
	end)

	it("style lint warns on the jagged shadow+large-corner caveat and the shadow budget", function()
		local children = {}
		table.insert(children, UI.corners(UI.shadow(UI.Button({ id = "Jagged", label = "J" }), "raised"), 32))
		for i = 1, 101 do
			table.insert(children, UI.shadow(UI.Box({ id = `Bx{i}` }), "raised"))
		end
		local core = Facet.newCore()
		local root = mountLib.mount(core, UI.Screen({ id = "S", children = children }))
		local warnings = style_lint.lint(root.node)
		local sawJagged, sawBudget = false, false
		for _, w in warnings do
			if w.rule == "jagged-corner-shadow" then
				sawJagged = true
			elseif w.rule == "shadow-budget" then
				sawBudget = true
			end
		end
		expect(sawJagged).toBeTruthy()
		expect(sawBudget).toBeTruthy()
		root.dispose()
	end)
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- THE PER-VIEW GRADIENT MODIFIER (charter cap 11 "views may apply
-- shadow/gradient modifiers locally, with the two composing predictably";
-- ADR-0020 R8 rung 2). It follows UI.shadow's architecture exactly: bounded
-- normalized DATA on a style-authority prop, materialized by the adapter as one
-- bespoke child instance — never a sheet rule, because a rule and an instance
-- would be two authorities over the same paint.
--
-- The propositions worth testing are the ones that would otherwise be found on
-- a device:
--   1. the spec normalizes to engine-true data and is BOUNDED (2-3 stops,
--      ordered, endpoints pinned, tokens resolved);
--   2. the ADR-0019 gradient ban still holds at this rung — a value control's
--      own chrome refuses a wash, with the same style of error;
--   3. a text-bearing node refuses it, because a UIGradient multiplies the
--      node's OWN engine-drawn glyphs (the Step 3.5 truth);
--   4. it never enters layout;
--   5. it survives a theme-package swap — the view wins on that node, and the
--      child is neither clobbered nor duplicated (ADR-0020 R8 composition).
-- ─────────────────────────────────────────────────────────────────────────────
local stylingLib = require("../src/tokens/styling")
local themePackage = require("../src/themes/package")
local chromeSlots = require("../src/tokens/chrome_slots")
local default_style = require("../src/tokens/default_style")

describe("engine styling: the per-view gradient modifier (rung 2)", function()
	it("normalizes to engine-true data: ordered stops, pinned endpoints, resolved tokens", function()
		local g = stylingLib.normalizeGradient({
			colors = { "surfaceStrong", { r = 1, g = 1, b = 1 }, "accent" },
			rotation = 90,
			transparency = { 0.1, 0.35 },
		})
		expect(#g.colors).toBe(3)
		expect(g.colors[1].t).toBe(0)
		expect(g.colors[2].t).toBe(0.5)
		expect(g.colors[3].t).toBe(1)
		-- a token resolved against the ACTIVE style, exactly as UI.corners' radius
		-- tokens do — so a gradient written once follows the style it is read under
		expect(g.colors[1].r).toBe(default_style.colors.surfaceStrong.r)
		expect(g.colors[2].r).toBe(1)
		expect(g.colors[3].b).toBe(default_style.colors.accent.b)
		expect(g.rotation).toBe(90)
		expect(#g.transparency).toBe(2)
		expect(g.transparency[1].t).toBe(0)
		expect(g.transparency[2].t).toBe(1)
		expect(g.transparency[2].v).toBe(0.35)
		expect(g.enabled).toBe(true)
		expect(table.isfrozen(g)).toBe(true)
	end)

	it("is BOUNDED: one stop, four stops, an unordered ramp and an unknown token all refuse", function()
		local cases = {
			{ colors = { "accent" } },
			{ colors = { "accent", "surface", "control", "danger" } },
			{ colors = { { t = 0.4, color = "accent" }, { t = 0.2, color = "surface" } } },
			{ colors = { "accent", "nosuchtoken" } },
			{ colors = { "accent", "surface" }, rotation = 0 / 0 },
		}
		for index, spec in cases do
			local ok = pcall(stylingLib.normalizeGradient, spec)
			expect(ok).never().toBe(true)
			expect(index > 0).toBe(true)
		end
	end)

	it("keeps the SAME alpha ceiling the theme path enforces, for the same reason", function()
		-- UIGradient.Transparency fades the parent's ENTIRE rendering; a near-1
		-- stop ghosts the control rather than softening the wash. One number, two
		-- authoring paths — asserted equal so they cannot drift apart.
		expect(stylingLib.GRADIENT_ALPHA_MAX).toBe(themePackage.GRADIENT_ALPHA_MAX)
		local ok, err = pcall(stylingLib.normalizeGradient, {
			colors = { "accent", "surface" },
			transparency = { 0.1, 0.95 },
		})
		expect(ok).toBe(false)
		expect(string.find(tostring(err), tostring(stylingLib.GRADIENT_ALPHA_MAX), 1, true) ~= nil).toBe(true)
		expect(string.find(tostring(err), "ENTIRE", 1, true) ~= nil).toBe(true)
	end)

	it("UI.gradient lands on a Box as style data via the style authority", function()
		local screen = UI.Screen({
			id = "S",
			children = {
				UI.gradient(UI.Box({ id = "Card", surface = "raised" }), {
					colors = { "surfaceStrong", "control" },
					rotation = 90,
				}),
			},
		})
		local _, root, _, adapter = present(screen)
		local node = adapter.node("/S/Card")
		local gradient = node.props.gradient
		expect(gradient ~= nil).toBeTruthy()
		expect(#gradient.colors).toBe(2)
		expect(gradient.rotation).toBe(90)
		-- APPLICATION, not just emission (the Step 3.5 lesson): the adapter
		-- materialized ONE bespoke child from that data, mirrored headlessly
		expect(node.gradientInstance ~= nil).toBe(true)
		expect(node.gradientInstance.className).toBe("UIGradient")
		expect(node.gradientInstance.rotation).toBe(90)
		expect(#node.gradientInstance.colorStops).toBe(2)
		root.dispose()
	end)

	it("refuses a TEXT-BEARING node, because a wash multiplies its own glyphs", function()
		for _, make in
			{
				function()
					return UI.Text({ id = "T", text = "hello" })
				end,
				function()
					return UI.Button({ id = "B", label = "Go" })
				end,
				function()
					return UI.Toggle({ id = "Sw", label = "On", value = Facet.newCore():signal(false) })
				end,
			}
		do
			local ok, err = pcall(function()
				return UI.gradient(make(), { colors = { "accent", "surface" } })
			end)
			expect(ok).toBe(false)
			expect(string.find(tostring(err), "glyph", 1, true) ~= nil).toBe(true)
			-- the error carries the FIX, not just the refusal
			expect(string.find(tostring(err), "UI.Box", 1, true) ~= nil).toBe(true)
		end
		-- ...and the fix actually works: the same wash on a Box behind the label
		local ok = pcall(function()
			return UI.gradient(UI.Box({ id = "Card", surface = "raised" }), { colors = { "accent", "surface" } })
		end)
		expect(ok).toBe(true)
	end)

	it("refuses a VALUE CONTROL's own chrome, the same wall themes.define puts up", function()
		for _, slot in { "sliderTrack", "sliderThumb", "barTrack", "barFill" } do
			local hinted = chromeSlots.attachHint(UI.Box({ id = "Rail" }), { slot = slot })
			local ok, err = pcall(function()
				return UI.gradient(hinted, { colors = { "accent", "surface" } })
			end)
			expect(ok).toBe(false)
			expect(string.find(tostring(err), slot, 1, true) ~= nil).toBe(true)
			expect(string.find(tostring(err), "see-through", 1, true) ~= nil).toBe(true)
		end
		-- a gradientable slot is untouched by the ban
		local panel = chromeSlots.attachHint(UI.Box({ id = "Panel" }), { slot = "panel" })
		expect(pcall(function()
			return UI.gradient(panel, { colors = { "accent", "surface" } })
		end)).toBe(true)
	end)

	it("never enters layout: identical rects with and without a gradient", function()
		local plain = UI.Screen({ id = "S", children = { UI.Box({ id = "Card", surface = "raised" }) } })
		local washed = UI.Screen({
			id = "S",
			children = {
				UI.gradient(UI.Box({ id = "Card", surface = "raised" }), { colors = { "accent", "surface" } }),
			},
		})
		local _, rootA, _, adapterA = present(plain)
		local _, rootB, _, adapterB = present(washed)
		local a, b = adapterA.node("/S/Card").rect, adapterB.node("/S/Card").rect
		expect(b.x).toBe(a.x)
		expect(b.y).toBe(a.y)
		expect(b.w).toBe(a.w)
		expect(b.h).toBe(a.h)
		rootA.dispose()
		rootB.dispose()
	end)

	-- arch-F1 (rich-skinning-v2 verifier fix round): styleGroup normalized the same
	-- gradient spec but reached `withProps` directly, so BOTH of UI.gradient's
	-- construction-time walls were bypassed by writing the collection form. One
	-- shared `assertGradientable` is now called by both entry points.
	it("UI.styleGroup enforces the SAME two gradient walls as UI.gradient", function()
		-- wall 1: text-bearing classes
		for _, make in
			{
				function()
					return UI.Text({ id = "T", text = "hello" })
				end,
				function()
					return UI.Button({ id = "B", label = "Go" })
				end,
				function()
					return UI.Toggle({ id = "Sw", label = "On", value = Facet.newCore():signal(false) })
				end,
			}
		do
			local ok, err = pcall(function()
				return UI.styleGroup({ gradient = { colors = { "accent", "surface" } } }, { make() })
			end)
			expect(ok).toBe(false)
			expect(string.find(tostring(err), "glyph", 1, true) ~= nil).toBe(true)
			expect(string.find(tostring(err), "UI.Box", 1, true) ~= nil).toBe(true)
		end
		-- wall 2: a value control's own chrome
		for _, slot in { "sliderTrack", "sliderThumb", "barTrack", "barFill" } do
			local hinted = chromeSlots.attachHint(UI.Box({ id = "Rail" }), { slot = slot })
			local ok, err = pcall(function()
				return UI.styleGroup({ gradient = { colors = { "accent", "surface" } } }, { hinted })
			end)
			expect(ok).toBe(false)
			expect(string.find(tostring(err), slot, 1, true) ~= nil).toBe(true)
			expect(string.find(tostring(err), "see-through", 1, true) ~= nil).toBe(true)
		end
		-- a refusal is per-element: one bad member refuses the whole call even when
		-- gradientable siblings sit beside it (no half-applied collection)
		local ok = pcall(function()
			return UI.styleGroup(
				{ gradient = { colors = { "accent", "surface" } } },
				{ UI.Box({ id = "A" }), UI.Text({ id = "T", text = "hi" }) }
			)
		end)
		expect(ok).toBe(false)
		-- and the gradientable collection still passes
		expect(pcall(function()
			return UI.styleGroup(
				{ gradient = { colors = { "accent", "surface" } } },
				{ UI.Box({ id = "A" }), chromeSlots.attachHint(UI.Box({ id = "P" }), { slot = "panel" }) }
			)
		end)).toBe(true)
		-- the OTHER modifiers styleGroup carries are unwalled (shadow on a Button is legal)
		expect(pcall(function()
			return UI.styleGroup({ shadow = "raised" }, { UI.Button({ id = "B", label = "Go" }) })
		end)).toBe(true)
	end)

	it("UI.styleGroup carries the gradient to every element of a collection", function()
		local screen = UI.Screen({
			id = "S",
			children = UI.styleGroup(
				{ gradient = { colors = { "accent", "surface" } } },
				{ UI.Box({ id = "A" }), UI.Box({ id = "B" }) }
			),
		})
		local _, root, _, adapter = present(screen)
		expect(adapter.node("/S/A").props.gradient ~= nil).toBe(true)
		expect(adapter.node("/S/B").props.gradient ~= nil).toBe(true)
		root.dispose()
	end)
end)

-- ===========================================================================
-- api-architecture-consistency (0.8.0): the two style grammars that skipped the
-- strict boundary (ledger/blueprints.md BP-F1 / BP-F2).
-- ===========================================================================

describe("F-4 (BP-F1): UI.styleGroup is the WHOLE style-modifier family, and closed", function()
	it("carries `stroke`, the fourth family member, like the singular UI.stroke", function()
		local out = UI.styleGroup({ stroke = { thickness = 2 } }, { UI.Box({ id = "A" }), UI.Box({ id = "B" }) })
		expect(out[1].props.stroke.thickness).toBe(2)
		expect(out[2].props.stroke.thickness).toBe(2)
		-- same normalization path as UI.stroke: the theme's hairline colour + alpha
		expect(out[1].props.stroke).toEqual(UI.strokeData({ thickness = 2 }))
	end)

	it("a stroked collection reaches the adapter under the style authority", function()
		local screen = UI.Screen({
			id = "S",
			children = UI.styleGroup({ stroke = { thickness = 3 } }, { UI.Box({ id = "A" }), UI.Box({ id = "B" }) }),
		})
		local _, root, _, adapter = present(screen)
		expect(adapter.node("/S/A").props.stroke.thickness).toBe(3)
		expect(adapter.node("/S/B").props.stroke.thickness).toBe(3)
		root.dispose()
	end)

	it("an unknown spec key is refused, naming the modifier and the legal set", function()
		local ok, err = pcall(function()
			return UI.styleGroup({ shadwo = "raised" } :: any, { UI.Box({ id = "A" }) })
		end)
		expect(ok).toBe(false)
		local message = tostring(err)
		expect(string.find(message, "UI.styleGroup", 1, true) ~= nil).toBe(true)
		expect(string.find(message, "shadwo", 1, true) ~= nil).toBe(true)
		expect(string.find(message, "shadow", 1, true) ~= nil).toBe(true)
		expect(string.find(message, "gradient", 1, true) ~= nil).toBe(true)
		expect(string.find(message, "corners", 1, true) ~= nil).toBe(true)
		expect(string.find(message, "stroke", 1, true) ~= nil).toBe(true)
	end)

	it("the four legal keys all still pass", function()
		expect(pcall(function()
			return UI.styleGroup({
				shadow = "raised",
				gradient = { colors = { "accent", "surface" } },
				corners = 6,
				stroke = {},
			}, { UI.Box({ id = "A" }) })
		end)).toBe(true)
	end)
end)

describe("F-5 (BP-F2): the shadow and gradient grammars are closed like the stroke one", function()
	it("a typo'd gradient field is refused instead of silently producing the default", function()
		local ok, err = pcall(function()
			return UI.gradient(UI.Box({ id = "A" }), { colors = { "accent", "surface" }, roation = 45 })
		end)
		expect(ok).toBe(false)
		local message = tostring(err)
		expect(string.find(message, "roation", 1, true) ~= nil).toBe(true)
		expect(string.find(message, "rotation", 1, true) ~= nil).toBe(true)
	end)

	it("a typo'd shadow field is refused", function()
		local ok, err = pcall(function()
			return UI.shadow(UI.Box({ id = "A" }), {
				blurRadius = { scale = 0, offset = 12 },
				transparancy = 0.5,
			})
		end)
		expect(ok).toBe(false)
		expect(string.find(tostring(err), "transparancy", 1, true) ~= nil).toBe(true)
		expect(string.find(tostring(err), "transparency", 1, true) ~= nil).toBe(true)
	end)

	it("every LEGAL field of both grammars still passes", function()
		expect(pcall(function()
			return UI.shadow(UI.Box({ id = "A" }), {
				blurRadius = { scale = 0, offset = 12 },
				color = { r = 0, g = 0, b = 0 },
				transparency = 0.5,
				offset = { x = { scale = 0, offset = 0 }, y = { scale = 0, offset = 2 } },
				spread = { x = { scale = 0, offset = 0 }, y = { scale = 0, offset = 0 } },
				zIndex = -2,
				enabled = true,
			})
		end)).toBe(true)
		expect(pcall(function()
			return UI.gradient(UI.Box({ id = "A" }), {
				colors = { "accent", "surface" },
				rotation = 45,
				transparency = { 0, 0.3 },
				enabled = true,
			})
		end)).toBe(true)
	end)

	it("the preset-NAME form of a shadow still works on both shipped styles", function()
		expect(pcall(function()
			return UI.shadow(UI.Box({ id = "A" }), "raised")
		end)).toBe(true)
		expect(pcall(function()
			return UI.shadow(UI.Box({ id = "A" }), "overlay")
		end)).toBe(true)
		expect(pcall(function()
			return UI.shadow(UI.Box({ id = "A" }), "raised", require("../src/tokens/default_light_style"))
		end)).toBe(true)
	end)
end)
